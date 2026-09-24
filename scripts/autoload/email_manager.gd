extends Node

## Owns the email inbox/sent box (email.md): received mail + read state, sent
## greeting mail, the daily 09:00 send-decision for NPC-authored mail
## (data/npc/<id>.json's `emails` field - see data/npc/README.md for the
## {title, lines} shape and what each category means), and the player's own
## daily "send an email" / "send an invite" allowance. Restaurant invites
## still go through RestaurantManager.invite_npc() (own daily flag, not
## logged to the sent box - only the free-written greeting mail is per the
## computer UI spec); this only adds the separate "하루에 한 번 메일 발송"
## limit for that greeting mail.
##
## NOTE: the daily send-decision rules below (_generate_daily_emails) were
## redesigned 2026-09-04 per user spec - gift_thanks/event_invite stay
## affection-independent reactions to real player actions, greeting is now a
## 3-stage per-NPC affection milestone (GREETING_THRESHOLDS, no daily cap/
## cooldown - see _maybe_send_greeting_milestones). EVENT_INVITE_CHANCE_PER_DAY
## is still an untuned placeholder (email.md has no frequency spec) - fine to
## adjust that one number freely, but check with the user before changing the
## rules/priority structure itself again.

signal inbox_updated
signal mail_received(entry: Dictionary)

## email.md gives no frequency rule for filler mail, so this chance is still
## an invented placeholder (day3.md) - now only gates event_invite (gift_thanks/
## greeting are conditional-certain sends, see the constants below).
const EVENT_INVITE_CHANCE_PER_DAY := 0.5

## 2026-09-04 재설계(사용자 지시 - "메일은 첫번째 메일은 호감도 20, 두번째
## 메일은 호감도 40, 세 번째 메일은 호감도 75에서 발송되게 해줘"): 안부(greeting)
## 메일이 더 이상 호감도 80 단일 임계값 + 7일 쿨다운 + 하루 2명 랜덤 추첨이
## 아니라, NPC별 emails.greeting 풀(3개)을 순서대로 이 임계값들에 맞춰 마일스톤
## 처럼 발송한다 - affection_events의 threshold 패턴과 동일한 개념. 하루 추첨
## 상한이 없어져서, 같은 날 여러 NPC가(혹은 한 NPC가 디버그 등으로 여러 단계를
## 한꺼번에 넘으면 그 NPC가 한 번에 여러 통을) 받을 수 있다 - 의도된 동작.
## gift_thanks/event_invite는 플레이어의 실제 행동(선물/초대)에 대한 반응이라
## 호감도/쿨다운 없이 그대로 유지.
const GREETING_THRESHOLDS: Array[int] = [20, 40, 75]

## 요청함(사용자 지시, 2026-08-25 - "초반에 할 게 없다"는 문제를 온보딩성
## 부탁으로 풀어보려는 시도) - 일반 수신함과 분리된 별도 목록. 목표(objective_type/
## objective_target)를 실제로 달성했는지 매번 살아있는 상태로 확인하고
## (is_request_objective_met), 달성했을 때만 완료 버튼이 눌리게 한다(사용자
## 지시). 완료 처리는 한 번뿐이라 별도 "진행 중" 상태 저장 없이 claimed 여부만
## 저장하면 충분하다.
const REQUESTS_PATH := "res://data/requests/requests.json"
var _request_definitions: Dictionary = {}
var _claimed_requests: Dictionary = {}
## 요청함도 수신함처럼 읽음/안읽음 아이콘이 있어야 한다는 지적(사용자 지시,
## 2026-08-25) - 이건 "목표 달성 여부"(is_request_objective_met)와는 완전히
## 별개 축이라 따로 저장한다.
var _read_requests: Dictionary = {}
## "감자 수확해보기" 같은 튜토리얼 요청용(사용자 지시, 2026-08-25) - 지금
## 인벤토리에 몇 개 있는지가 아니라 "그동안 한 번이라도 얻어본 적 있는지"를
## 물어보는 요청이라(바로 요리에 써버려도 조건은 유지돼야 함), 현재 재고가
## 아니라 InventoryManager.item_added 신호로 누적 총량을 따로 센다.
var _lifetime_item_counts: Dictionary = {}
## "한 접시 대접해보기" 요청용 - RestaurantManager.dish_served 누적 횟수.
var _lifetime_dishes_served := 0
## "모든 NPC와 인사하기" 요청용(사용자 지시, 2026-08-25 - "제한기간 없이") -
## main.gd._handle_npc_encounter()가 하루 첫 마주침마다 record_npc_greeted()로
## 채운다. 날짜가 지나도 안 지워지는 누적 집합이라 _greeted_today(하루마다
## 리셋)와는 완전히 다른 저장소.
var _greeted_npc_ids: Dictionary = {}

## 반복/희귀 요청(사용자 지시, 2026-08-25 - "초반에 할 게 없다" 문제 완화) -
## requests.json의 고정 항목과 달리 실행 중에 생성/소멸한다. 스키마는
## _request_definitions 항목과 동일하되 "expires_day"(TimeManager.current_day
## 기준 만료일, -1이면 무제한)가 추가로 붙는다. is_request_objective_met/
## claim_request은 _get_request_definition()으로 두 저장소를 함께 조회한다.
const RECURRING_TEMPLATES_PATH := "res://data/requests/recurring_templates.json"
const RECURRING_INTERVAL_MIN_DAYS := 2
const RECURRING_INTERVAL_MAX_DAYS := 3
## 원래 2명씩 뽑았으나, 요청함이 한꺼번에 너무 많이 쌓인다는 사용자 지시로
## 사이클당 1명으로 축소(2026-09-04).
const RECURRING_NPC_COUNT_PER_CYCLE := 1
const RECURRING_REWARD_GOLD := 150
## 선호 재료 한국어 이름 -> 실제 인벤토리 아이템 id. data/npc/*.json의
## preferred_food는 요리 판정용 한국어 원재료 이름이고(base_material과 동일
## 규칙 - npc_manager.gd get_food_preference_for_ingredients 참고), 배달 요청의
## 목표 아이템 id로 쓰려면 이 변환이 필요하다. data/items/items.json의 원재료
## (material) 9종 + 우유 + 사냥 고기(토끼고기/새고기, 2026-09-05 우디/어셔
## 선호 재료 변경) 전부.
const FOOD_NAME_TO_ITEM_ID := {
	"감자": "potato",
	"옥수수": "corn",
	"상추": "lettuce",
	"돼지고기": "pork",
	"소고기": "beef",
	"연어": "salmon",
	"고등어": "mackerel",
	"오징어": "squid",
	"베리": "berry",
	"우유": "milk",
	"토끼고기": "rabbit_meat",
	"새고기": "bird_meat",
}
## "요청함에 도착하고 4일 이내"(사용자 지시) - 지나면 claim 불가하고 "만료"로
## 표시된다. 만료된 채로 하루 더 남겨뒀다가(사용자가 놓쳤다는 걸 확인할 시간)
## _sweep_expired_dynamic_requests()가 정리한다.
const REQUEST_EXPIRE_GRACE_DAYS := 4
const EXPIRED_CLEANUP_DELAY_DAYS := 1

## 가구 배달 요청(사용자 지시, 2026-08-25 - "가구는 랜덤하게, rare 요청이어야
## 됨") - 10일 이후부터 매일 낮은 확률로 하나 생성. 매번 나오는 게 아니라
## 특정 NPC 목소리를 붙이기엔 아까워서, 아무 NPC한테나 자연스럽게 어울리는
## 일반 문구 여러 개 중 무작위로 고른다.
const FURNITURE_QUEST_START_DAY := 10
const FURNITURE_QUEST_DAILY_CHANCE := 0.12
const FURNITURE_QUEST_REWARD_MARGIN := 300
const FURNITURE_SHOP_ID := "woody_shop"
const FURNITURE_QUEST_TEMPLATES := [
	{
		"title": "부탁 하나만 해도 될까?",
		"lines": [
			"집 좀 꾸며보려고 하는데, 아무래도 혼자 고르긴 자신이 없어서.",
			"가구점에서 {item_name} 하나만 구해다 줄 수 있어?",
			"값은 넉넉하게 챙겨줄게, 부탁해."
		]
	},
	{
		"title": "이상하게 들릴 수도 있는데",
		"lines": [
			"요즘 집에 뭐가 하나 빠진 느낌이 들어서 고민하다가 부탁하는 거야.",
			"가구점에 {item_name}가 있던데, 그거 하나만 사다 줄래?",
			"귀찮은 부탁인 거 아는데, 갚을게."
		]
	},
	{
		"title": "심부름 좀 부탁해도 돼?",
		"lines": [
			"요즘 가게 일 때문에 가구점 들를 시간이 도저히 안 나.",
			"{item_name} 하나 필요한데, 대신 좀 사다 줄 수 있어?",
			"수고비는 확실히 챙겨줄게."
		]
	}
]
var _recurring_templates: Dictionary = {}
var _dynamic_requests: Dictionary = {}
var _next_recurring_day := 0

var _inbox: Array = []
var _sent: Array = []
var _invite_history: Array = []
var _next_id := 1
var _player_email_used_today := false
var _gifted_today: Dictionary = {}
## RestaurantManager.dish_served로 실시간 기록 - 오늘 이 NPC에게 선호 재료가 들어간
## 요리가 나갔는지. _gifted_today와 같은 패턴으로 다음날 이메일 생성 시점에
## 스냅샷을 뜨고 비운다(아래 _generate_daily_emails 참고).
var _favorite_food_served_today: Dictionary = {}
var _sent_story_triggers: Dictionary = {}
## npc_id -> 그 NPC의 emails.greeting 풀에서 몇 번째(0-based)까지 이미 보냈는지
## (GREETING_THRESHOLDS와 같은 길이/순서) - 마일스톤이 중복 발송되지 않게 막는
## 진행도 저장소. gift_thanks/event_invite는 여기 안 남는다(마일스톤 대상이 아님).
var _greeting_stage_sent: Dictionary = {}
## npc_id -> 플레이어가 compose_and_send()로 마지막으로 보낸 자유 작성 메일의
## 본문. NPCManager.get_daily_dialogue()가 이 NPC와 대화할 때 dialogue.mail_reaction
## 풀에서 하나를 뽑아 "{player_mail_content}"를 이 값으로 채워 넣을 후보로 쓴다 -
## 그 대사가 실제로 뽑히면 clear_pending_mail_reaction()으로 지워져서 한 번만
## 언급된다. 같은 NPC에게 또 메일을 보내면 이전 것 대신 최신 내용으로 덮어써짐.
var _pending_mail_reaction: Dictionary = {}


func _ready() -> void:
	_load_requests()
	_load_recurring_templates()
	_next_recurring_day = TimeManager.current_day + randi_range(RECURRING_INTERVAL_MIN_DAYS, RECURRING_INTERVAL_MAX_DAYS)
	NPCManager.gift_given.connect(_on_gift_given)
	RestaurantManager.dish_served.connect(_on_dish_served)
	InventoryManager.item_added.connect(_on_item_added)
	TimeManager.day_changed.connect(_on_day_changed)
	HorrorEventManager.impersonation_email_ready.connect(_on_impersonation_email_ready)
	HorrorEventManager.stalker_email_ready.connect(_on_stalker_email_ready)
	MurderManager.alibi_reminder_ready.connect(_on_alibi_reminder_ready)
	NPCManager.memento_reminder_ready.connect(_on_memento_reminder_ready)


## 메일함 UI는 게임 내 "N일차"가 아니라 플레이어가 실제로 메일을 주고받은
## 현실의 날짜를 보여주고 싶다는 사용자 요청 - 시스템 시계에서 가져온다.
## 현실 날짜 뒤에 게임 내 진행 일차(TimeManager.current_day)를 같이 표시한다 -
## 하루에 여러 일차를 플레이할 수 있어서 현실 날짜만으로는 메일/초대 내역을
## 구분할 수 없다는 사용자 피드백으로 추가(day4 TODO).
func get_current_real_date_string() -> String:
	var d := Time.get_datetime_dict_from_system()
	return tr("%d년 %d월 %d일 %d일차") % [d.year, d.month, d.day, TimeManager.current_day]


func get_inbox() -> Array:
	return _inbox.duplicate(true)


func get_sent_mail() -> Array:
	return _sent.duplicate(true)


## 초대장은 발신함(안부 메일 전용, 사용자 지시)에는 안 남지만, 누구를
## 초대했는지 확인할 방법이 없다는 사용자 피드백으로 별도 내역을 남긴다.
## 컴퓨터 UI의 메일쓰기 화면(mail_compose_panel.gd)이 초대 성공 직후 호출한다.
## outcome은 초대 시점엔 아직 알 수 없어 "pending"으로 시작 - 그 다음날이
## 끝날 때 RestaurantManager가 mark_invite_outcome()으로 채운다.
func log_invite(npc_id: String) -> void:
	_invite_history.append({"npc_id": npc_id, "date": get_current_real_date_string(), "outcome": "pending"})


## RestaurantManager._on_day_changed()가 초대한 다음날이 끝나기 직전(그날의
## _visited_today가 지워지기 전)에 실제 방문 여부를 확인해서 호출한다 - 해당
## npc_id의 가장 최근 "pending" 항목을 찾아 결과를 채운다(같은 NPC를 여러 번
## 초대했을 수 있으니 가장 최근 것부터 역순으로 찾음).
##
## 실제로 방문했다면(visited) _event_invite_target_npc_id에 남겨서, 이번
## day_changed 신호의 뒷부분에서 도는 _generate_daily_emails()가 오늘(=방문한
## 다음날) event_invite 메일을 보내게 한다. RestaurantManager가 이 함수보다
## 먼저 autoload되어 있어 항상 먼저 불린다(project.godot 순서 - RestaurantManager
## 33번째 줄, EmailManager 38번째 줄) - 즉 방문 여부가 확정된 뒤에야
## _generate_daily_emails()가 돈다. 예전엔 RestaurantManager.get_todays_invited_npc_id()
## ("오늘 방문 예정"인 NPC)로 판정해서, 초대한 다음날 - 즉 아직 방문하기도 전에
## "어제 즐거웠어" 메일이 먼저 도착하는 버그가 있었다(사용자 리포트, 2026-08-26 -
## "플로라가 레스토랑에 초대메일을 받으면 그 다음날 오는데 그 다음날에 오기도
## 전에 초대해줘서 고맙다는 메일 써놨음").
var _event_invite_target_npc_id := ""


func mark_invite_outcome(npc_id: String, visited: bool) -> void:
	for i in range(_invite_history.size() - 1, -1, -1):
		var entry: Dictionary = _invite_history[i]
		if String(entry.get("npc_id", "")) == npc_id and String(entry.get("outcome", "")) == "pending":
			entry["outcome"] = "visited" if visited else "missed"
			break
	if visited:
		_event_invite_target_npc_id = npc_id


func get_invite_history() -> Array:
	return _invite_history.duplicate(true)


## 아직 완료 보상을 안 받은 요청들 - mail_app.gd 요청함 목록용. 완료(claim)한
## 요청은 여기서 아예 빠진다(별도 "완료함" 보관 없음). 고정 요청(_request_definitions)
## 뒤에 반복/희귀 요청(_dynamic_requests)이 이어 붙는다 - 만료 여부는 저장된
## 상태가 아니라 조회 시점에 TimeManager.current_day로 매번 새로 계산한다.
func get_active_requests() -> Array:
	var active: Array = []
	for request_id in _request_definitions:
		if _claimed_requests.has(request_id):
			continue
		var entry: Dictionary = (_request_definitions[request_id] as Dictionary).duplicate(true)
		## 요청 12개가 첫날부터 한꺼번에 다 뜨면 정신없다는 지적(사용자 지시,
		## 2026-08-30) - "available_from_day"(선택 필드, 기본 1 = 기존 동작
		## 그대로 첫날부터)가 지금 날짜보다 크면 아직 안 보여준다.
		if TimeManager.current_day < int(entry.get("available_from_day", 1)):
			continue
		entry["id"] = request_id
		entry["expired"] = false
		active.append(entry)
	for request_id in _dynamic_requests:
		if _claimed_requests.has(request_id):
			continue
		var entry: Dictionary = (_dynamic_requests[request_id] as Dictionary).duplicate(true)
		entry["id"] = request_id
		entry["expired"] = _is_request_expired(entry)
		active.append(entry)
	return active


## 완료됐지만 아직 안 받은 요청이 있는지 - `!` 알림 배지 표시 여부 판단용
## (mail_app.gd 사이드바 요청함 탭, computer_screen.gd 데스크탑 메일 아이콘,
## 사용자 지시 2026-09-01, 플레이테스트 23번).
func has_claimable_request() -> bool:
	for entry in get_active_requests():
		var request_id := String(entry.get("id", ""))
		if not bool(entry.get("expired", false)) and is_request_objective_met(request_id):
			return true
	return false


func _is_request_expired(definition: Dictionary) -> bool:
	var expires_day := int(definition.get("expires_day", -1))
	return expires_day >= 0 and TimeManager.current_day > expires_day


func _get_request_definition(request_id: String) -> Dictionary:
	if _request_definitions.has(request_id):
		return _request_definitions[request_id]
	return _dynamic_requests.get(request_id, {})


func is_request_read(request_id: String) -> bool:
	return bool(_read_requests.get(request_id, false))


func mark_request_read(request_id: String) -> void:
	_read_requests[request_id] = true


## jukebox_manager.gd가 "인벤토리에 한 번이라도 들어온 적 있는지"를 물을 때 쓴다
## (2026-09-18 - 선물받은 음반이 _gift_unlocked_item_ids 도입 이전 기록이라
## 인벤토리에서 사라지면 다시 잠기던 문제 수정).
func get_lifetime_item_count(item_id: String) -> int:
	return int(_lifetime_item_counts.get(item_id, 0))


## 목표를 실제로 달성했는지 매번 새로 확인한다(저장된 "진행 상태" 없음) - 새
## objective_type을 추가하려면 이 match에 분기만 늘리면 된다.
func is_request_objective_met(request_id: String) -> bool:
	var definition := _get_request_definition(request_id)
	if definition.is_empty():
		return false
	var target := int(definition.get("objective_target", 0))
	match String(definition.get("objective_type", "")):
		"total_income":
			return EconomyManager.total_income >= target
		"lifetime_item_count":
			var item_id := String(definition.get("objective_item_id", ""))
			return int(_lifetime_item_counts.get(item_id, 0)) >= target
		"lifetime_dishes_served":
			return _lifetime_dishes_served >= target
		"deliver_item":
			var deliver_item_id := String(definition.get("objective_item_id", ""))
			return InventoryManager.has_item(deliver_item_id, target)
		"greet_all_npcs":
			return _greeted_npc_ids.size() >= target
		_:
			return false


## 요청함 상세 화면에 붙이는 진행 상황 문구(사용자 지시, 2026-08-25 - "인사한
## npc 몇 명인지 요청함에서 볼 수 있게") - 이 문구가 필요한 objective_type만
## 채워서 반환하고, 그 외는 빈 문자열(mail_detail_panel.gd가 비어있으면 안 붙임).
func get_request_progress_text(request_id: String) -> String:
	var definition := _get_request_definition(request_id)
	match String(definition.get("objective_type", "")):
		"greet_all_npcs":
			return tr("%d / %d명과 인사함") % [_greeted_npc_ids.size(), int(definition.get("objective_target", 0))]
		_:
			return ""


## main.gd._handle_npc_encounter()가 하루 첫 마주침마다 호출 - "모든 NPC와
## 인사하기" 요청의 진행 상태를 쌓는다. 한 번 인사한 NPC는 영구히 카운트된다.
func record_npc_greeted(npc_id: String) -> void:
	_greeted_npc_ids[npc_id] = true


## 완료 버튼이 눌렸을 때(mail_app.gd) - 목표를 아직 못 채웠거나 이미 받았거나
## 만료된 요청이면 조용히 실패. deliver_item 타입은 보상 지급 전에 인벤토리에서
## 실제로 재료를 차감한다(사용자 지시, 2026-08-25 - "인벤에 템이 있고 완료
## 버튼 누르면 자동으로 -1"). 성공하면 요청함에서 사라진다.
func claim_request(request_id: String) -> bool:
	if _claimed_requests.has(request_id):
		return false
	var definition := _get_request_definition(request_id)
	if definition.is_empty() or _is_request_expired(definition) or not is_request_objective_met(request_id):
		return false
	if String(definition.get("objective_type", "")) == "deliver_item":
		var deliver_item_id := String(definition.get("objective_item_id", ""))
		var deliver_count := int(definition.get("objective_target", 1))
		if not InventoryManager.remove_item(deliver_item_id, deliver_count):
			return false
	var reward_gold := int(definition.get("reward_gold", 0))
	if reward_gold > 0:
		EconomyManager.add_income(reward_gold)
	var reward_item_id := String(definition.get("reward_item_id", ""))
	if not reward_item_id.is_empty():
		InventoryManager.add_item(reward_item_id, int(definition.get("reward_item_count", 1)))
	## 부탁을 들어준 셈이니 발신자 호감도도 오른다(사용자 지시, 2026-08-25) -
	## 단, requests.json의 고정 초기 튜토리얼 요청("감자 한번 캐볼래?" 등,
	## 반복 생성되는 recurring_templates.json 요청과 달리 스토리상 진짜
	## 부탁이 아니라 안내에 가까움)은 제외한다(사용자 지시, 2026-09-05 -
	## "초기 퀘스트는 완료해도 오르면 안될 거 같아") - 플로라가 이런 초기
	## 요청을 4개나 갖고 있어서 다른 NPC보다 호감도가 유독 빨리 오르던
	## 원인이었다.
	if not _request_definitions.has(request_id):
		NPCManager.add_request_completion_affection(String(definition.get("npc_id", "")))
	_claimed_requests[request_id] = true
	return true


func _load_requests() -> void:
	var file := FileAccess.open(REQUESTS_PATH, FileAccess.READ)
	if file == null:
		push_error("Request catalog could not be opened: %s" % REQUESTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Request catalog is not valid JSON: %s" % REQUESTS_PATH)
		return
	_request_definitions = Localizer.apply_language(parsed, REQUESTS_PATH) as Dictionary


func _load_recurring_templates() -> void:
	var file := FileAccess.open(RECURRING_TEMPLATES_PATH, FileAccess.READ)
	if file == null:
		push_error("Recurring request template catalog could not be opened: %s" % RECURRING_TEMPLATES_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Recurring request template catalog is not valid JSON: %s" % RECURRING_TEMPLATES_PATH)
		return
	_recurring_templates = Localizer.apply_language(parsed, RECURRING_TEMPLATES_PATH) as Dictionary


## 2~3일마다 살아있는 NPC 2명이 새로 선호 재료 배달을 요청한다(사용자 지시,
## 2026-08-25). 이미 다른 반복/가구 요청이 걸려있는 NPC는 후보에서 빠진다 -
## 한 명한테 동시에 요청이 여러 개 쌓이는 걸 막기 위함.
func _maybe_generate_recurring_requests() -> void:
	if TimeManager.current_day < _next_recurring_day:
		return
	_next_recurring_day = TimeManager.current_day + randi_range(RECURRING_INTERVAL_MIN_DAYS, RECURRING_INTERVAL_MAX_DAYS)
	var pool := _eligible_dynamic_request_npc_ids()
	pool.shuffle()
	for npc_id in pool.slice(0, RECURRING_NPC_COUNT_PER_CYCLE):
		_create_recurring_request(npc_id)


func _eligible_dynamic_request_npc_ids() -> Array:
	var result: Array = []
	for npc_id in _recurring_templates.keys():
		if not NPCManager.is_alive(npc_id):
			continue
		if _has_active_dynamic_request_from(npc_id):
			continue
		result.append(npc_id)
	return result


func _has_active_dynamic_request_from(npc_id: String) -> bool:
	for request_id in _dynamic_requests:
		if _claimed_requests.has(request_id):
			continue
		if String((_dynamic_requests[request_id] as Dictionary).get("npc_id", "")) == npc_id:
			return true
	return false


func _create_recurring_request(npc_id: String) -> void:
	var preferred: Array = NPCManager.get_definition(npc_id).get("preferred_food", [])
	if preferred.is_empty():
		return
	var food_name := String(preferred.pick_random())
	var item_id := String(FOOD_NAME_TO_ITEM_ID.get(food_name, ""))
	if item_id.is_empty():
		return
	var template: Dictionary = _recurring_templates.get(npc_id, {})
	if template.is_empty():
		return
	var lines: Array = (template.get("lines", []) as Array).duplicate()
	for i in lines.size():
		lines[i] = String(lines[i]).replace("{item_name}", food_name)
	var request_id := "recurring_%s_%d" % [npc_id, TimeManager.current_day]
	_dynamic_requests[request_id] = {
		"npc_id": npc_id,
		"title": String(template.get("title", "")).replace("{item_name}", food_name),
		"lines": lines,
		"objective_type": "deliver_item",
		"objective_item_id": item_id,
		"objective_target": 1,
		"reward_gold": RECURRING_REWARD_GOLD,
		"reward_item_id": "",
		"reward_item_count": 0,
		"expires_day": TimeManager.current_day + REQUEST_EXPIRE_GRACE_DAYS,
	}


## 10일차 이후부터 매일 낮은 확률로 가구 배달 요청 하나를 생성한다(사용자
## 지시 - "가구는 랜덤하게, rare 요청이어야 됨"). ShopManager의 실제 가구점
## 재고에서 고르므로 신규 가구가 추가돼도 코드 수정 없이 그대로 후보가 된다.
func _maybe_generate_furniture_request() -> void:
	if TimeManager.current_day < FURNITURE_QUEST_START_DAY or _has_active_furniture_request():
		return
	if randf() > FURNITURE_QUEST_DAILY_CHANCE:
		return
	var stock: Array = ShopManager.get_stock(FURNITURE_SHOP_ID).filter(func(listing: Dictionary) -> bool: return int(listing.get("price", 0)) > 0)
	var sender_pool := _eligible_dynamic_request_npc_ids()
	if stock.is_empty() or sender_pool.is_empty():
		return
	var listing: Dictionary = stock.pick_random()
	var item_id := String(listing.get("item_id", ""))
	var item_name := String(InventoryManager.get_item_definition(item_id).get("name", item_id))
	var price := int(listing.get("price", 0))
	var npc_id := String(sender_pool.pick_random())
	var template: Dictionary = FURNITURE_QUEST_TEMPLATES.pick_random()
	var lines: Array = (template.get("lines", []) as Array).duplicate()
	for i in lines.size():
		lines[i] = tr(String(lines[i])).replace("{item_name}", item_name)
	var request_id := "furniture_%s_%d" % [npc_id, TimeManager.current_day]
	_dynamic_requests[request_id] = {
		"npc_id": npc_id,
		"title": tr(String(template.get("title", ""))),
		"lines": lines,
		"objective_type": "deliver_item",
		"objective_item_id": item_id,
		"objective_target": 1,
		"reward_gold": price + FURNITURE_QUEST_REWARD_MARGIN,
		"reward_item_id": "",
		"reward_item_count": 0,
		"expires_day": TimeManager.current_day + REQUEST_EXPIRE_GRACE_DAYS,
	}


func _has_active_furniture_request() -> bool:
	for request_id in _dynamic_requests:
		if String(request_id).begins_with("furniture_") and not _claimed_requests.has(request_id):
			return true
	return false


## 만료된 지 EXPIRED_CLEANUP_DELAY_DAYS일이 지난 반복/가구 요청을 완전히
## 정리한다 - 그 전까지는 "만료" 표시로 요청함에 남아있는다(사용자가 놓쳤다는
## 걸 확인할 시간을 주기 위함, 사용자 지시).
func _sweep_expired_dynamic_requests() -> void:
	var to_remove: Array = []
	for request_id in _dynamic_requests:
		var expires_day := int((_dynamic_requests[request_id] as Dictionary).get("expires_day", -1))
		if expires_day >= 0 and TimeManager.current_day > expires_day + EXPIRED_CLEANUP_DELAY_DAYS:
			to_remove.append(request_id)
	for request_id in to_remove:
		_dynamic_requests.erase(request_id)
		_claimed_requests.erase(request_id)
		_read_requests.erase(request_id)


func has_unread() -> bool:
	for entry in _inbox:
		if not bool(entry.get("read", false)):
			return true
	return false


func mark_read(email_id: int) -> void:
	for entry in _inbox:
		if int(entry.get("id", -1)) == email_id:
			entry["read"] = true
			inbox_updated.emit()
			return


func is_mail_read(email_id: int) -> bool:
	for entry in _inbox:
		if int(entry.get("id", -1)) == email_id:
			return bool(entry.get("read", false))
	return false


func can_send_email_today() -> bool:
	return not _player_email_used_today


func has_pending_mail_reaction(npc_id: String) -> bool:
	return _pending_mail_reaction.has(npc_id)


func get_pending_mail_reaction_content(npc_id: String) -> String:
	return String(_pending_mail_reaction.get(npc_id, ""))


func clear_pending_mail_reaction(npc_id: String) -> void:
	_pending_mail_reaction.erase(npc_id)


## 컴퓨터 메일쓰기 화면의 "안부 메일" 모드 전송 버튼이 호출. email.md: "플레이어는
## 하루에 한 번 NPC 한 명에게 이메일을 보낼 수 있다. 이메일을 받은 NPC는 호감도가
## 3 상승한다." - NPCManager.send_email()이 호감도 증가를 처리하고, 여기서는
## 하루 제한과 발신함 기록만 담당한다.
func compose_and_send(npc_id: String, title: String, content: String) -> bool:
	if _player_email_used_today or not NPCManager.is_alive(npc_id) or content.is_empty():
		return false
	NPCManager.send_email(npc_id)
	_player_email_used_today = true
	_pending_mail_reaction[npc_id] = content
	_sent.append({
		"id": _next_id,
		"npc_id": npc_id,
		"title": title,
		"lines": [content],
		"date": get_current_real_date_string(),
	})
	_next_id += 1
	inbox_updated.emit()
	return true


func get_save_data() -> Dictionary:
	return {
		"inbox": _inbox.duplicate(true),
		"sent": _sent.duplicate(true),
		"invite_history": _invite_history.duplicate(true),
		"next_id": _next_id,
		"player_email_used_today": _player_email_used_today,
		"gifted_today": _gifted_today.duplicate(),
		"favorite_food_served_today": _favorite_food_served_today.duplicate(),
		"sent_story_triggers": _sent_story_triggers.duplicate(true),
		"greeting_stage_sent": _greeting_stage_sent.duplicate(),
		"pending_mail_reaction": _pending_mail_reaction.duplicate(),
		"claimed_requests": _claimed_requests.duplicate(),
		"read_requests": _read_requests.duplicate(),
		"lifetime_item_counts": _lifetime_item_counts.duplicate(),
		"lifetime_dishes_served": _lifetime_dishes_served,
		"greeted_npc_ids": _greeted_npc_ids.duplicate(),
		"dynamic_requests": _dynamic_requests.duplicate(true),
		"next_recurring_day": _next_recurring_day,
	}


func load_save_data(data: Dictionary) -> void:
	_inbox = (data.get("inbox", []) as Array).duplicate(true)
	_sent = (data.get("sent", []) as Array).duplicate(true)
	_invite_history = (data.get("invite_history", []) as Array).duplicate(true)
	_next_id = int(data.get("next_id", 1))
	_player_email_used_today = bool(data.get("player_email_used_today", false))
	_claimed_requests = (data.get("claimed_requests", {}) as Dictionary).duplicate()
	_read_requests = (data.get("read_requests", {}) as Dictionary).duplicate()
	_lifetime_item_counts = (data.get("lifetime_item_counts", {}) as Dictionary).duplicate()
	_lifetime_dishes_served = int(data.get("lifetime_dishes_served", 0))
	_greeted_npc_ids = (data.get("greeted_npc_ids", {}) as Dictionary).duplicate()
	_dynamic_requests = (data.get("dynamic_requests", {}) as Dictionary).duplicate(true)
	_next_recurring_day = int(data.get("next_recurring_day", _next_recurring_day))
	_gifted_today = (data.get("gifted_today", {}) as Dictionary).duplicate()
	_favorite_food_served_today = (data.get("favorite_food_served_today", {}) as Dictionary).duplicate()
	_sent_story_triggers = (data.get("sent_story_triggers", {}) as Dictionary).duplicate(true)
	_greeting_stage_sent = (data.get("greeting_stage_sent", {}) as Dictionary).duplicate()
	_pending_mail_reaction = (data.get("pending_mail_reaction", {}) as Dictionary).duplicate()


func _on_gift_given(npc_id: String) -> void:
	_gifted_today[npc_id] = true


func _on_dish_served(_station_index: int, npc_id: String, dish: Dictionary) -> void:
	_lifetime_dishes_served += 1
	if int(dish.get("preference", NPCManager.FoodPreference.NEUTRAL)) == NPCManager.FoodPreference.FAVORITE:
		_favorite_food_served_today[npc_id] = true


func _on_item_added(item_id: String, count: int) -> void:
	_lifetime_item_counts[item_id] = int(_lifetime_item_counts.get(item_id, 0)) + count


func _on_day_changed(_day: int, _weekday: String) -> void:
	_player_email_used_today = false
	_generate_daily_emails()
	_maybe_generate_recurring_requests()
	_maybe_generate_furniture_request()
	_sweep_expired_dynamic_requests()


func _generate_daily_emails() -> void:
	var gifted_yesterday := _gifted_today.duplicate()
	_gifted_today.clear()
	var favorite_food_served_yesterday := _favorite_food_served_today.duplicate()
	_favorite_food_served_today.clear()
	## RestaurantManager._on_day_changed()가 이 신호 안에서 이미 먼저 돌아
	## mark_invite_outcome()으로 채워둔 값 - 방문이 확정된 그 하루치만 쓰고
	## 바로 비운다(_event_invite_target_npc_id 주석 참고).
	var event_invite_target := _event_invite_target_npc_id
	_event_invite_target_npc_id = ""
	## 오늘 이미 gift_thanks/event_invite를 보낸 NPC는 안부 마일스톤 체크에서
	## 제외한다(하루 1통 원칙) - 그 외 전원은 매일 자기 호감도가 다음 안부
	## 마일스톤(GREETING_THRESHOLDS)을 넘었는지 확인한다.
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		_maybe_send_story_progress(npc_id)
		if gifted_yesterday.has(npc_id):
			_maybe_send_category(npc_id, "gift_thanks", 1.0)
		elif npc_id == event_invite_target:
			_maybe_send_category(npc_id, "event_invite", EVENT_INVITE_CHANCE_PER_DAY, favorite_food_served_yesterday.has(npc_id))
		else:
			_maybe_send_greeting_milestones(npc_id)


## GREETING_THRESHOLDS를 순서대로 통과했는지 확인해 그만큼 emails.greeting
## 풀(0번째, 1번째, 2번째...)을 보낸다 - 디버그 등으로 여러 임계값을 한 번에
## 넘으면 이 안에서 while로 몇 통이든 그날 한꺼번에 보낸다. 그 NPC의 풀이
## 3개보다 적으면(예: 아직 이메일 없는 NPC) 있는 만큼만 보내고 멈춘다.
func _maybe_send_greeting_milestones(npc_id: String) -> void:
	var stage := int(_greeting_stage_sent.get(npc_id, 0))
	var affection := NPCManager.get_affection(npc_id)
	while stage < GREETING_THRESHOLDS.size() and affection >= int(GREETING_THRESHOLDS[stage]):
		if not _send_greeting_stage(npc_id, stage):
			break
		stage += 1
	_greeting_stage_sent[npc_id] = stage


func _send_greeting_stage(npc_id: String, stage: int) -> bool:
	var emails: Dictionary = NPCManager.get_definition(npc_id).get("emails", {})
	var pool: Array = (emails.get("greeting", []) as Array).filter(
		func(entry): return NPCManager.requires_alive_met(entry.get("requires_alive", ""))
	)
	if stage >= pool.size():
		return false
	var entry: Dictionary = pool[stage]
	_add_mail(npc_id, "greeting", String(entry.get("title", "")), (entry.get("lines", []) as Array).duplicate())
	return true


## favorite_food_served: event_invite 전용 - 오늘 이 NPC에게 실제로 선호 재료가
## 들어간 요리가 나갔는지(_on_dish_served 참고). data/npc/README.md의 event_invite
## 항목에 "requires_favorite_food": true를 붙이면 그 문구는 실제로 선호 재료
## 요리를 받은 날에만 뽑힐 수 있다 - 태그 없는 문구는 항상 뽑힐 수 있는 일반
## 문구로 취급한다. 다른 카테고리(greeting/gift_thanks)는 이 값을 안 쓴다.
func _maybe_send_category(npc_id: String, category: String, chance: float, favorite_food_served: bool = false) -> bool:
	var emails: Dictionary = NPCManager.get_definition(npc_id).get("emails", {})
	var pool: Array = emails.get(category, [])
	if category == "event_invite":
		pool = pool.filter(func(entry): return not bool(entry.get("requires_favorite_food", false)) or favorite_food_served)
	# 다른 NPC를 현재형으로 언급하는 메일(예: 셰퍼드의 "오늘 마린이 왔다
	# 갔어")이 그 NPC 사망 후에도 계속 발송되는 문제(사용자 지시, 2026-08-26) -
	# dialogue.daily와 같은 requires_alive 필드를 이메일 풀에도 재사용한다.
	pool = pool.filter(func(entry): return NPCManager.requires_alive_met(entry.get("requires_alive", "")))
	if pool.is_empty() or randf() > chance:
		return false
	var picked: Dictionary = pool.pick_random()
	_add_mail(npc_id, category, String(picked.get("title", "")), (picked.get("lines", []) as Array).duplicate())
	return true


## story_progress (email.md의 공포/스토리 메일) - 트리거 이름으로 조회하는
## 고정 메일이라 랜덤 풀이 아니며, 같은 트리거는 NPC당 한 번만 보낸다.
## 현재 확정된 트리거는 살인 발생 여부뿐 - 그 외 키는 데이터에 채워져도
## 조건을 아는 시스템이 없어서 발송되지 않는다 (TODO: 트리거 늘어나면 여기 추가).
func _maybe_send_story_progress(npc_id: String) -> void:
	var emails: Dictionary = NPCManager.get_definition(npc_id).get("emails", {})
	var triggers: Dictionary = emails.get("story_progress", {})
	var sent: Dictionary = _sent_story_triggers.get(npc_id, {})
	for trigger_name in triggers:
		if sent.has(trigger_name) or not _is_story_trigger_active(String(trigger_name), npc_id):
			continue
		var entry: Dictionary = triggers[trigger_name]
		_add_mail(npc_id, "story_progress", String(entry.get("title", "")), (entry.get("lines", []) as Array).duplicate())
		sent[trigger_name] = true
	_sent_story_triggers[npc_id] = sent


## "affection_<N>_reached" 형식의 트리거는 특정 NPC 전용이 아니라 범용 규칙이다 -
## 그 NPC의 affection_events에 있는 임계값 N짜리 이벤트(예: 셰퍼드의 반지 증정,
## threshold 100)가 이미 완료됐는지를 그대로 물어본다. 호감도 마일스톤 대사가
## 이미 나온 "다음날"에야 그 여운을 편지로 잇고 싶을 때(예: 반지를 준 뒤에야
## 진짜 속마음을 편지로 고백) 이 이름 규칙으로 새 트리거를 추가하면 된다 -
## 별도 코드 없이 아무 NPC나 재사용 가능.
func _is_story_trigger_active(trigger_name: String, npc_id: String) -> bool:
	if trigger_name.begins_with("affection_") and trigger_name.ends_with("_reached"):
		var threshold_str := trigger_name.trim_prefix("affection_").trim_suffix("_reached")
		return threshold_str.is_valid_int() and NPCManager.has_completed_event(npc_id, int(threshold_str))
	## "player_arrival_day_N" - NPC 13명의 환영 메일이 첫날 한꺼번에 다 오면
	## 정신없다는 지적(사용자 지시, 2026-08-30 - 요청함 12개 동시 공개랑 같은
	## 문제) - affection_N_reached와 같은 이름 규칙으로, data/npc/<id>.json의
	## emails.story_progress 키를 "player_arrival"에서 "player_arrival_day_N"
	## (예: player_arrival_day_3)으로 바꾸면 그 날짜부터 발송된다. 접미사
	## 없는 기존 "player_arrival"은 하위 호환으로 계속 즉시 발송(항상 true).
	if trigger_name.begins_with("player_arrival_day_"):
		var day_str := trigger_name.trim_prefix("player_arrival_day_")
		return day_str.is_valid_int() and TimeManager.current_day >= int(day_str)
	match trigger_name:
		"first_murder_occurred":
			return MurderManager.get_murder_count() >= 1
		"second_murder_occurred":
			return MurderManager.get_murder_count() >= 2
		"player_arrival":
			return true
		_:
			return false


## 새 게임 시작 시(캐릭터 생성 확정 직후) title_screen.gd가 호출 - 평소
## story_progress는 _generate_daily_emails()가 날짜 바뀔 때마다 검사하지만,
## 새 게임은 첫날 안에 메일함에서 바로 환영 메일이 보이길 원한다는 사용자
## 요청(2026-08-12)이라 게임 시작 시점에 한 번 즉시 검사해준다. "player_arrival"은
## 항상 active라서 이미 켜진 세이브에서도(2026-08-12 이전 세이브 포함) 다음
## 날짜 변경 때 자연히 한 번 발송되고, _sent_story_triggers가 그 이후 중복을 막는다.
func send_arrival_emails() -> void:
	for npc_id in NPCManager.get_all_ids():
		if NPCManager.is_alive(npc_id):
			_maybe_send_story_progress(npc_id)


## horror_events.md/email.md "NPC 사망 이후": HorrorEventManager가 사망 다음날
## 판정해서 넘겨주는 사칭 메일을 실제로 받은 메일함에 꽂는다. 제목은 다른
## title은 이제 JSON의 {"title","lines"}에서 오지만(2026-08-15 스키마 통일),
## 아직 비워뒀을 수 있으므로 비어있으면 죽은 NPC의 이름으로 대체한다 - 실제
## 그 사람 이름으로 온 메일이라는 사실 자체가 이미 섬뜩해서 제목이 없어도
## 어색하지 않다는 판단.
func _on_impersonation_email_ready(npc_id: String, title: String, lines: Array) -> void:
	var display_title := title if not title.is_empty() else String(NPCManager.get_definition(npc_id).get("name", npc_id))
	_add_mail(npc_id, "impersonation", display_title, lines)


## HorrorEventManager.STALKER_SENDER_ID("???")를 그대로 npc_id로 써서 메일함에
## 꽂는다 - 발신인을 알 수 없는 메일이라는 게 스펙(email.md "공포 메일")이라
## 일부러 실제 NPC id를 안 쓴다. 제목도 비어있으면 그대로 빈 제목으로 둔다
## (정체불명 발신인이 제목도 없이 보낸 메일이 오히려 더 자연스러움).
func _on_stalker_email_ready(sender_id: String, title: String, lines: Array, quiet: bool) -> void:
	_add_mail(sender_id, "stalker", title, lines, quiet)


## MurderManager._on_day_changed() - 2차 살인 알리바이 창이 열려 있는데 3일
## 넘게 대화를 못 나눈 NPC가 보내는 재촉 메일.
func _on_alibi_reminder_ready(npc_id: String, title: String, lines: Array) -> void:
	_add_mail(npc_id, "alibi_reminder", title, lines)


## NPCManager.memento_reminder_ready 참고 - 추억의 물건 마일스톤이 며칠째
## 대화로 소비되지 않은 NPC가 보내는 안전장치 메일. 딱 한 번만 온다.
func _on_memento_reminder_ready(npc_id: String, title: String, lines: Array) -> void:
	_add_mail(npc_id, "memento_reminder", title, lines)


## 반환값은 main.gd의 엔딩 컷신처럼 "이 메일이 실제로 읽힐 때까지 기다리기"가
## 필요한 호출부를 위한 것 - 대부분의 기존 호출부는 그냥 무시한다.
## quiet=true는 스토커 메일 중 아직 무서운 효과음을 쓰면 안 되는 초반 몇 통용
## (HorrorEventManager.QUIET_STALKER_EMAIL_COUNT 참고) - mail_detail_panel.gd가
## 이 값을 보고 SFX_STALKER_MAIL 대신 평범한 메일 효과음을 쓴다. 다른 카테고리
## 메일들은 그냥 기본값(false)을 쓰면 되므로 새 인자 하나 늘었다고 기존 호출부를
## 다 고칠 필요는 없다.
func _add_mail(npc_id: String, category: String, title: String, lines: Array, quiet: bool = false) -> Dictionary:
	var entry := {
		"id": _next_id,
		"npc_id": npc_id,
		"category": category,
		"title": title,
		"date": get_current_real_date_string(),
		"read": false,
		"lines": lines,
		"quiet": quiet,
	}
	_next_id += 1
	_inbox.append(entry)
	mail_received.emit(entry)
	inbox_updated.emit()
	return entry


## 엔딩 컷신 등 특정 서사 지점에서 스토커 메일을 즉시 한 통 보낼 때 쓴다.
## 발신인은 평소 순차 발송되는 스토커 메일과 동일하게 HorrorEventManager.
## STALKER_SENDER_ID("???")를 재사용 - 초상화 없이 "???"라는 발신인만 뜬다.
func send_stalker_mail(title: String, lines: Array) -> int:
	var entry := _add_mail(HorrorEventManager.STALKER_SENDER_ID, "stalker", title, lines)
	return int(entry.get("id", -1))
