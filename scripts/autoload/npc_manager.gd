extends Node

## Owns JSON-backed NPC definitions and runtime state (affection, life status).
## Dialogue/email line selection, world placement, and murder execution belong
## to other systems; this manager only exposes the data and the affection/
## death state machine described in npc.md.

signal affection_changed(npc_id: String, affection: int)
signal affection_event_triggered(npc_id: String, threshold: int)
signal memento_received(npc_id: String)
## affection_events의 "gift" 타입(예: 모카가 호감도 임계값에서 커피를 선물) -
## memento_received와 같은 구조, item_id만 이벤트 데이터에서 그대로 넘긴다.
signal npc_gift_item_triggered(npc_id: String, item_id: String)
signal npc_died(npc_id: String)
## 도감 완성 보상(제단 부활, 사용자 지시 2026-08-25) 전용 - revive_npc() 참고.
signal npc_revived(npc_id: String)
signal murder_candidate_registered(npc_id: String)
signal gift_given(npc_id: String)
## NPC 머리 위 이모지 반응(백로그 스펙 확정, 이번에 구현) - npc_world_manager.gd가
## 듣고 있다가 그 NPC가 지금 화면에 보이면 NPCSprite.show_emote()를 호출한다.
## 화면에 없으면 조용히 무시된다(큐잉 안 함 - 안 보이는 반응은 의미 없음).
## duration이 0 이하면 NPCSprite의 기본 지속시간을 그대로 쓴다 - 호감도 100
## 컷신(사용자 지시, 2026-08-25 - "이모지 오래 보여주기")처럼 평소보다 오래
## 띄우고 싶을 때만 명시적으로 넘긴다.
signal npc_emote_requested(npc_id: String, emote_id: String, duration: float)
## 추억의 물건(memento) 마일스톤이 대기 큐에 들어간 채로 며칠째 소비가 안 되는
## NPC용 안전장치(사용자 지시, 2026-08-25 - "선물만 주다 120까지 가버리면
## 대사를 아예 못 받고 지나칠 수 있잖아... 메일이라도 보내야되나"). 대화를
## 통해서만 소비되는 마일스톤 구조상, 대화 없이 선물/식사/메일로만 호감도를
## 올리면 이론상 놓칠 수 있어 추가함. email_manager.gd가 듣고 있다가 그
## NPC의 emails.memento_reminder를 메일함에 꽂는다. 딱 한 번만 보낸다 - 그래도
## 안 가면(사용자 지시) 그건 플레이어의 선택으로 취급하고 재촉하지 않는다.
signal memento_reminder_ready(npc_id: String, title: String, lines: Array)

enum FoodPreference { NEUTRAL, FAVORITE, DISLIKED }

const DATA_DIR := "res://data/npc/"

const MIN_AFFECTION := 0
const MAX_AFFECTION := 150
const MEMENTO_AFFECTION := 100
const MURDER_CANDIDATE_AFFECTION := 120
## 추억의 물건 마일스톤이 며칠째 대기 상태면 알림 메일을 보낼지(사용자 지시,
## 2026-08-25) - 2차 살인 알리바이 재촉 메일(murder_manager.gd)과 같은 3일
## 기준으로 맞춘다.
const MEMENTO_REMINDER_DELAY_DAYS := 3

const AFFECTION_TIER_MID := 50
const AFFECTION_TIER_HIGH := 100

const AFFECTION_GAIN_TALK := 2
const AFFECTION_GAIN_GIFT := 5
const AFFECTION_GAIN_MEAL := 3
const AFFECTION_GAIN_FAVORITE_MEAL := 5
const AFFECTION_LOSS_DISLIKED_MEAL := -5
const AFFECTION_GAIN_EMAIL := 3
## 요청함 완료 보상(사용자 지시, 2026-08-25 - "퀘스트 완료하면... 호감도 3정도
## 오르는게 좋지않을까") - 선물/메일 보낼 때와 같은 값으로 통일.
const AFFECTION_GAIN_REQUEST_COMPLETE := 3

## 이모지 스펙(2026-08-06 브레인스토밍, 2026-08-07 아트 반영) 8종 중 트리거가
## 확정된 5종만 여기서 문자열 상수로 노출한다 - 물음표/불편/부끄는 아직 배정된
## 트리거가 없어 예비로 남겨두되, 시트에는 이미 자리(3/4/7번 칸)가 있다.
const EMOTE_SMILE := "smile"
const EMOTE_HEART := "heart"
const EMOTE_EXCITED := "excited"
const EMOTE_DEJECTED := "dejected"
const EMOTE_EXCLAMATION := "exclamation"
const EMOTE_QUESTION := "question"
const EMOTE_UNCOMFORTABLE := "uncomfortable"
const EMOTE_SHY := "shy"

const EMOTE_ICON_PATH := "res://assets/npc/emoji/NpcEmote.png"
const EMOTE_ICON_GRID_SIZE := 16
## 시트의 왼쪽부터 칸 순서(사용자 확정) - 느낌표 다음 8번째 칸에 부끄가 추가됨.
const EMOTE_COLUMN_INDEX := {
	EMOTE_SMILE: 0,
	EMOTE_HEART: 1,
	EMOTE_EXCITED: 2,
	EMOTE_QUESTION: 3,
	EMOTE_UNCOMFORTABLE: 4,
	EMOTE_DEJECTED: 5,
	EMOTE_EXCLAMATION: 6,
	EMOTE_SHY: 7,
}

const WEEKDAY_GROUPS := {
	"월": "mon_wed_thu", "수": "mon_wed_thu", "목": "mon_wed_thu",
	"화": "tue_fri", "금": "tue_fri",
	"토": "weekend", "일": "weekend",
}

var _definitions: Dictionary = {}
var _affection: Dictionary = {}
var _alive: Dictionary = {}
var _completed_events: Dictionary = {}
## npc_id -> [int, ...] - completed_events와 달리 "실제로 화면에 뜬" 임계값만
## 기록한다(has_shown_event() 참고). affection_events의 "requires" 필드로 다른
## NPC의 이벤트를 선행 조건으로 걸 때 이걸로 판정한다 - completed_events는
## 대사를 보여주기도 전에 대기열에 등록되는 순간 채워져서 이 용도로는 못 씀.
var _shown_events: Dictionary = {}
## npc_id -> [{"threshold": int, "is_memento": bool}, ...] - 호감도 임계값을
## 넘긴 affection_event 중 아직 실제로 보여주지 않은 것들의 대기열(FIFO).
## consume_pending_milestone() 참고 - 2026-08-16 사용자 리포트: 예전엔 임계값
## 넘는 순간 대사 없이 바로 추억의 물건이 가방에 들어갔음(대사를 실제로 본
## 뒤에 받아야 함). 2026-08-23: 큰 폭의 호감도 상승 한 번으로 임계값 두 개를
## 동시에 넘기면(예: 100 추억의 물건 + 105 불안 신호) 단일 Dictionary로는
## 나중 것이 먼저 것을 덮어써서 하나가 통째로 씹혔음 - 배열 대기열로 바꿔서
## 넘은 순서 그대로 하나씩 소비되게 함.
var _pending_milestone: Dictionary = {}
## npc_id -> 추억의 물건 마일스톤이 큐에 들어간 날(TimeManager.current_day) -
## MEMENTO_REMINDER_DELAY_DAYS 경과 판정용. consume_pending_milestone()에서
## 지워진다.
var _memento_pending_since_day: Dictionary = {}
## npc_id -> bool - 추억의 물건 알림 메일을 이미 보냈는지(중복 발송 방지, 딱
## 한 번만).
var _memento_reminder_sent: Dictionary = {}
var _murder_candidate_flagged: Dictionary = {}
## npc_id -> bool - PARTNER_DEATH_PAIRS 참고, get_daily_dialogue()가 채운다.
var _partner_death_reaction_shown: Dictionary = {}
## npc_id -> 실제로 보여준 날짜 - was_partner_death_reaction_shown_today()가
## "오늘" 여부만 가려낼 때 쓴다(위 플래그는 한 번 켜지면 영구 true라 날짜
## 구분이 안 됨). 세이브에 안 남아도 된다 - 당일에만 의미 있는 상태.
var _partner_death_reaction_shown_day: Dictionary = {}
var _dead_npc_ids: Array[String] = []
var _death_days: Dictionary = {}
var _last_daily_dialogue_index: Dictionary = {}
var _talked_today: Dictionary = {}
## npc_id -> bool - 오늘 그 NPC와 나눈 마지막 대화가 "특수 대사"(마일스톤/
## 알리바이/애도/세이지 전용 트리거 등, get_daily_dialogue()의 여러 조기
## return 분기 - 일회성이라 다시 보여주면 안 됨)였는지. true면 오늘은 다시
## 말을 못 건다. 일상 잡담 로테이션(요일/호감도 풀, 비/공포 대화, 메일 반응,
## 세이지 운세 포함)만 나왔을 땐 false라 하루에 여러 번 계속 말을 걸 수
## 있다 - 단 호감도는 talk()이 하루 1회로 별도 제한(사용자 지시, 2026-09-05 -
## "일상 대사는 같은 말 계속 걸어도... 호감도는 처음 1번만 올려주고, 대사는
## 계속 보여주는 식... 특수한 대사일 경우... 하루에 한번만", 다음날 세션).
var _special_dialogue_shown_today: Dictionary = {}
## npc_id -> 오늘 처음 뽑힌 일상 잡담 대사(최종 결과, 메일 반응 등 그때 같이
## 붙은 것까지 포함) - 재대화 때마다 로테이션으로 다른 대사가 나오지 말고,
## 그날 정해진 대사를 계속 그대로 보여줘야 한다(사용자 지시, 2026-09-05 -
## "요일 대사 돌아가면서 보여주는 게 아니라 그 날 보여주기로 지정된 대사를
## 계속 보여주는 게 나을 거 같아"). _on_day_changed()에서 비운다.
## 세이지 운세는 여기 포함하지 않는다 - 캐시에 같이 구워버리면 오늘 첫
## 운세가 붙은 대사가 재대화할 때마다 매번 다시 나와서 운세가 반복되는
## 버그가 있었다(사용자 리포트, 2026-09-05 - "운세 중복으로 나와"). 아래
## get_daily_dialogue()가 캐시 히트/미스와 무관하게 매번 별도로 붙인다 -
## _build_fortune_offer_lines() 자체가 _fortune_offered_day로 하루 1회만
## 실제 내용을 돌려주므로 중복 없이 딱 한 번만 섞여 들어간다.
var _daily_dialogue_cache: Dictionary = {}
var _spawn_index: Dictionary = {}
var _pending_scent: Dictionary = {}
var _active_scent: Dictionary = {}
## 2026-08-23 사용자 지시: 플레이어가 선물 안 해도 모카/플로라는 가끔 자기가
## 알아서 향수를 뿌린 채로 나온다 - 두 사람만 해당, 매일 밤 자정에 확률
## 판정(_on_day_changed 참고). 이미 그날 선물로 향을 받았으면(=_active_scent에
## 이미 값이 있으면) 건드리지 않는다.
const SELF_SCENT_NPC_IDS := ["mocha", "flora"]
const SELF_SCENT_CHANCE := 0.05
const SELF_SCENT_COLORS := ["blue", "purple", "white"]
## npc_id -> {"map_id": String, "position": Vector2} - 실제로 걸어서 정확히
## 그 좌표에 도착해 확정된(걷는 중이 아닌) 위치. get_npc_world_position()은
## 스케줄이 가리키는 위치를 즉시 반환하지만, 다구간 이동은 물론 같은 맵 안
## 이동조차도 NPC가 실제로 그 좌표까지 걸어서 도착하기까지는 시간이 걸린다 -
## 계산대처럼 "스케줄상 여기 있어야 한다"가 아니라 "실제로 지금 정확히 그
## 자리에 있는지"를 확인해야 하는 상호작용은 이 값을 써야 한다.
## NPCWorldManager가 도착/출발 시점마다 갱신한다
## (set_npc_physical_spot/clear_npc_physical_spot).
var _npc_physical_spot: Dictionary = {}
## npc_id -> bool - heart_event_30(호감도 30 최초 이벤트, 2026-08-24) 시청 여부.
## affection_events의 _shown_events와 별개로 관리한다 - 별도 스키마(anchor_state/
## scene_map_id 등)를 쓰고 main.gd가 직접 트리거하는 구조라 대기열(pending_milestone)을
## 안 거친다.
var _shown_heart_events: Dictionary = {}


func _ready() -> void:
	_load_all_definitions()
	_build_spawn_index()
	for npc_id in _definitions:
		_affection[npc_id] = 0
		_alive[npc_id] = true
		_completed_events[npc_id] = []
		_shown_events[npc_id] = []
		_murder_candidate_flagged[npc_id] = false
	TimeManager.day_changed.connect(_on_day_changed)


func get_all_ids() -> Array:
	return _definitions.keys()


func get_definition(npc_id: String) -> Dictionary:
	return _definitions.get(npc_id, {})


func is_stalker(npc_id: String) -> bool:
	return bool(get_definition(npc_id).get("is_stalker", false))


func is_story_npc(npc_id: String) -> bool:
	return get_definition(npc_id).get("npc_type", "") == "story"


func can_die(npc_id: String) -> bool:
	return bool(get_definition(npc_id).get("can_die", false))


func is_alive(npc_id: String) -> bool:
	return bool(_alive.get(npc_id, false))


func get_affection(npc_id: String) -> int:
	return int(_affection.get(npc_id, 0))


## 하루 한 번만 호감도가 오르게 한다 - UI 쪽(대화창)에서도 이미 오늘 대화한
## NPC와는 상호작용 자체를 막지만, 백엔드 자체도 방어적으로 안전해야 한다.
func talk(npc_id: String) -> void:
	if has_talked_today(npc_id):
		return
	_talked_today[npc_id] = true
	_add_affection(npc_id, AFFECTION_GAIN_TALK)


func has_talked_today(npc_id: String) -> bool:
	return bool(_talked_today.get(npc_id, false))


## npc_world_manager.gd get_nearest_talkable_npc()가 이걸로 "오늘 다시 말 걸
## 수 있는지"를 판단한다(has_talked_today()가 아니라) - get_daily_dialogue()
## 참고.
func has_special_dialogue_shown_today(npc_id: String) -> bool:
	return bool(_special_dialogue_shown_today.get(npc_id, false))


## amount/scent_color come from the gifted item's data (items.json's
## gift_affection/scent_color) - InventoryManager.give_gift() looks those up
## before calling here. Plain gifts with no override just use the flat
## affection.md value and no scent.
func give_gift(npc_id: String, amount: int = AFFECTION_GAIN_GIFT, scent_color: String = "") -> void:
	_add_affection(npc_id, amount)
	if not scent_color.is_empty():
		_pending_scent[npc_id] = scent_color
	gift_given.emit(npc_id)
	# 신남: 선물 받을 때 - 호불호 구분 없이 전부 통일(사용자 지시).
	request_emote(npc_id, EMOTE_EXCITED)


## 이 NPC가 지금 화면에 보이면 npc_world_manager.gd가 머리 위에 emote_id
## 아이콘을 잠깐 띄운다. 알 수 없는 emote_id는 조용히 무시한다(오타 방지).
## duration_override는 0 이하면 무시(기본 지속시간 사용).
func request_emote(npc_id: String, emote_id: String, duration_override: float = 0.0) -> void:
	if not EMOTE_COLUMN_INDEX.has(emote_id):
		return
	npc_emote_requested.emit(npc_id, emote_id, duration_override)


## CookingManager.get_recipe_icon_texture()와 동일한 슬라이싱 방식 - 시트가
## 아직 없으면(에셋 준비 전) null을 반환해서 안전하게 아무것도 안 그린다.
func get_emote_icon_texture(emote_id: String) -> Texture2D:
	if not EMOTE_COLUMN_INDEX.has(emote_id):
		return null
	if not ResourceLoader.exists(EMOTE_ICON_PATH):
		return null
	var sheet := load(EMOTE_ICON_PATH) as Texture2D
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(int(EMOTE_COLUMN_INDEX[emote_id]) * EMOTE_ICON_GRID_SIZE, 0, EMOTE_ICON_GRID_SIZE, EMOTE_ICON_GRID_SIZE)
	return atlas


## "" if the NPC isn't wearing a gifted scent today. Set the day after a
## perfume gift (see _on_day_changed) and lasts exactly one day.
func get_scent_color(npc_id: String) -> String:
	return String(_active_scent.get(npc_id, ""))


## restaurant.md: 완성된 요리 이름("찹 스테이크", "딸기 스무디" 등 data/cooking/recipes.json의
## 복합 이름)은 preferred_food/disliked_food(원재료 이름, 예: "소고기", "베리")와
## 절대 문자열이 일치하지 않아 이 함수가 요리 이름을 직접 받는 형태였을 때는 좋아하는
## 재료 판정이 사실상 항상 실패했다(2026-08-14 발견, 근본 원인 수정). 대신 그 요리를
## 만든 원재료 아이템 id 목록(CookingManager.cook()의 dish["ingredients"], 예:
## ["cooked_beef", "salad_greens"])을 받아 items.json의 base_material로 원재료
## 이름을 역추적해 판정한다. 두 재료 중 하나라도 선호 재료면 그 요리는 FAVORITE로
## 친다(좋아하는 재료 하나만 들어가도 좋아하는 요리라는 게 자연스러운 판정).
func get_food_preference_for_ingredients(npc_id: String, ingredient_item_ids: Array) -> FoodPreference:
	var definition := get_definition(npc_id)
	var preferred: Array = definition.get("preferred_food", [])
	var disliked: Array = definition.get("disliked_food", [])
	var found_disliked := false
	for item_id in ingredient_item_ids:
		var base_material := String(InventoryManager.get_item_definition(String(item_id)).get("base_material", ""))
		if base_material.is_empty():
			continue
		if preferred.has(base_material):
			return FoodPreference.FAVORITE
		if disliked.has(base_material):
			found_disliked = true
	return FoodPreference.DISLIKED if found_disliked else FoodPreference.NEUTRAL


## Lower-level entry point for callers that already know the reaction should
## be forced (e.g. cooking.md: NPC들은 괴상한 요리를 항상 비선호) rather than
## looked up from the NPC's own preferred/disliked food lists.
func feed_with_preference(npc_id: String, preference: FoodPreference) -> void:
	match preference:
		FoodPreference.FAVORITE:
			_add_affection(npc_id, AFFECTION_GAIN_FAVORITE_MEAL)
			# 하트: 좋아하는 음식 서빙받았을 때.
			request_emote(npc_id, EMOTE_HEART)
		FoodPreference.DISLIKED:
			_add_affection(npc_id, AFFECTION_LOSS_DISLIKED_MEAL)
			# 곤란함: 비선호 음식 서빙받았을 때(사용자 지시, 2026-08-25).
			request_emote(npc_id, EMOTE_UNCOMFORTABLE)
		_:
			_add_affection(npc_id, AFFECTION_GAIN_MEAL)


func send_email(npc_id: String) -> void:
	_add_affection(npc_id, AFFECTION_GAIN_EMAIL)


## dialogue.daily 안의 선택지(choice.options[].affection)가 호감도에 주는 영향을
## 그대로 적용한다 - dialogue_screen.gd가 플레이어의 선택을 확정할 때 호출한다.
func apply_dialogue_choice(npc_id: String, affection_delta: int) -> void:
	if affection_delta != 0:
		_add_affection(npc_id, affection_delta)


## email_manager.gd의 claim_request()가 요청 완료 보상을 지급할 때 호출 -
## 부탁을 들어준 셈이니 호감도가 조금 오른다(사용자 지시, 2026-08-25).
func add_request_completion_affection(npc_id: String) -> void:
	if is_alive(npc_id):
		_add_affection(npc_id, AFFECTION_GAIN_REQUEST_COMPLETE)


## npc.md's own table caps this at "1명만 살해당한 경우" (candidates 1-2 only),
## but ending.md's 체포 엔딩 needs a confirmed 3rd target whose murder attempt
## gets interrupted by the police. So eligibility here is affection-only;
## MurderManager (which owns the murder count/ending state) is the one that
## decides how many candidates it actually accepts into its queue.
func is_murder_candidate(npc_id: String) -> bool:
	if not is_alive(npc_id) or is_story_npc(npc_id) or is_stalker(npc_id):
		return false
	return get_affection(npc_id) >= MURDER_CANDIDATE_AFFECTION


func kill_npc(npc_id: String) -> void:
	if not is_alive(npc_id):
		return
	_alive[npc_id] = false
	_dead_npc_ids.append(npc_id)
	_death_days[npc_id] = TimeManager.current_day
	npc_died.emit(npc_id)


## RevivalManager/main.gd의 제단 부활 컷신이 호출 - "관계가 완전히 처음부터
## 다시 시작"되도록(사용자 지시, 2026-08-25) 사망 이전의 관계 진행 상태를
## 전부 초기화한다. 이미 받은 추억의 물건 자체(CollectionManager 도감 기록)는
## 건드리지 않는다 - 죽기 전 정당하게 받은 것이므로 영구 보존, 여기서는
## "다시 100을 찍으면 또 받을 수 있는 상태"로 재무장할 뿐이다.
func revive_npc(npc_id: String) -> void:
	if is_alive(npc_id):
		return
	_alive[npc_id] = true
	_dead_npc_ids.erase(npc_id)
	_death_days.erase(npc_id)
	## _add_affection()은 is_alive()가 false면 조용히 무시하므로, 반드시
	## 위에서 _alive를 먼저 true로 바꾼 뒤에 호출해야 한다.
	_add_affection(npc_id, 0 - get_affection(npc_id))
	_completed_events[npc_id] = []
	_shown_events[npc_id] = []
	_pending_milestone[npc_id] = []
	_shown_heart_events[npc_id] = false
	_murder_candidate_flagged[npc_id] = false
	_partner_death_reaction_shown[npc_id] = false
	_memento_pending_since_day.erase(npc_id)
	_memento_reminder_sent[npc_id] = false
	npc_revived.emit(npc_id)


func has_horror_mode_started() -> bool:
	return not _dead_npc_ids.is_empty()


const DEAD_PORTRAIT_SHADER_PATH := "res://scripts/shaders/grayscale_portrait.gdshader"
var _dead_portrait_material: ShaderMaterial

## horror_events.md "NPC 사망 - 초상화 회색 처리" - 죽은 NPC의 초상화를 보여주는
## 화면(dialogue_screen.gd/mail_app.gd)이 공통으로 쓰는 흑백 셰이더 머티리얼.
## 매번 새로 안 만들고 하나만 캐싱해서 재사용한다.
func get_dead_portrait_material() -> ShaderMaterial:
	if _dead_portrait_material == null:
		_dead_portrait_material = ShaderMaterial.new()
		_dead_portrait_material.shader = load(DEAD_PORTRAIT_SHADER_PATH)
	return _dead_portrait_material


func get_dead_npc_ids() -> Array[String]:
	return _dead_npc_ids.duplicate()


## 가장 최근에 사망한 NPC id("" = 아직 아무도 안 죽음) - HorrorEventManager가
## 스토커 이메일의 "{victim_name}" 자리표시자를 실제 피해자 이름으로 채울 때 쓴다.
func get_most_recent_death_npc_id() -> String:
	var latest_id := ""
	var latest_day := -1
	for npc_id in _dead_npc_ids:
		var day := get_death_day(npc_id)
		if day > latest_day:
			latest_day = day
			latest_id = npc_id
	return latest_id


## -1 if the NPC hasn't died (or died before this was tracked in a save).
func get_death_day(npc_id: String) -> int:
	return int(_death_days.get(npc_id, -1))


## stalker.md: 어셔가 스토커. 하드코딩 대신 is_stalker 플래그로 찾아서, 데이터만
## 바뀌면 코드 변경 없이 다른 NPC를 스토커로 바꿀 수 있게 했다.
func get_stalker_id() -> String:
	for npc_id in _definitions:
		if is_stalker(npc_id):
			return npc_id
	return ""


func get_milestone_dialogue(npc_id: String, threshold: int) -> Array:
	for event in get_definition(npc_id).get("affection_events", []):
		if int(event.get("threshold", -1)) == threshold:
			return event.get("lines", [])
	return []


## get_milestone_dialogue()와 같은 이벤트를 찾아, lines 안에 있는
## {"type":"gift","item_id":...} 줄의 item_id를 돌려준다(없으면 빈 문자열) -
## _check_affection_events()가 큐에 넣기 전에 인벤토리 자리를 미리 확인하는
## 용도. 이벤트 하나에 gift 줄이 여러 개면 첫 번째만 본다(지금까지 실제로는
## 항상 하나뿐).
func _find_gift_item_id(threshold: int, npc_id: String) -> String:
	for line in get_milestone_dialogue(npc_id, threshold):
		if line is Dictionary and String(line.get("type", "")) == "gift":
			return String(line.get("item_id", ""))
	return ""


func has_completed_event(npc_id: String, threshold: int) -> bool:
	return (_completed_events.get(npc_id, []) as Array).has(threshold)


func get_affection_tier(npc_id: String) -> String:
	var affection := get_affection(npc_id)
	if affection >= AFFECTION_TIER_HIGH:
		return "high"
	if affection >= AFFECTION_TIER_MID:
		return "mid"
	return "low"


## Picks one dialogue entry (an ordered array of lines to show in sequence)
## at random from today's pool: dialogue.daily[weekday][affection_tier], with
## horror_conversation mixed in once any NPC has died, and rain_conversation
## mixed in on rainy days (both are additive pools, not a separate weekday x
## tier x weather matrix - keeps the JSON schema small). 요일별로 대사가
## 따로 있다(스케줄과 달리 3그룹으로 안 묶임, 사용자 지시 2026-08-12 - 잡담이
## 3그룹으로 뭉쳐 있으니 너무 반복되는 느낌이라는 피드백. 스케줄은 여전히
## get_weekday_group()의 3그룹을 그대로 쓴다). Avoids repeating the same
## entry twice in a row when the pool has more than one option.
const SAGE_NPC_ID := "sage"
const POLI_NPC_ID := "poli"
## 로시는 평일엔 비가 와야만 등장하는 스케줄이라(visible_only_when_raining),
## 평일 만남이 전부 "비 오는 날"이 되어버려 rain_conversation이 매번 요일별
## 대사 풀과 섞이며 어렵게 쓴 요일별 대사가 묻힌다는 지적(사용자 지시,
## 2026-08-29) - 로시만 rain_conversation 혼합에서 제외한다.
const ROSHI_NPC_ID := "roshi"
## 세이지 운세 보기(사용자 지시, 2026-08-25 - "세이지 메리트가 너무 없다") -
## 하루 일상 대사(스토리 대사 제외) 끝에 "봐줄까?" 선택지를 붙인다. 좋은/나쁜
## 결과는 player.apply_speed_effect()(모카 커피 버프/기절 디버프와 같은
## 시스템)를 그대로 재사용 - 완전히 새 버프 종류를 만들지 않는다.
const FORTUNE_GOOD_CHANCE := 0.7
const FORTUNE_BUFF_PERCENT := 0.20
## 10%는 체감이 안 된다는 지적(사용자 지시, 2026-08-26) - 기절 디버프(-30%,
## main.gd COLLAPSE_DEBUFF_PERCENT)보다는 약하지만 확실히 티나는 -20%로.
const FORTUNE_DEBUFF_PERCENT := -0.20
## 1게임분=현실 1초(CLAUDE.md)라서, 180게임분이 정확히 "현실 3분"(사용자 지시)과
## 같다 - 기절 디버프(COLLAPSE_DEBUFF_MINUTES, main.gd)와 같은 환산.
const FORTUNE_DURATION_MINUTES := 180
## 오늘 이미 운세를 물어봤는지(수락/거절 상관없이) - TimeManager.current_day와
## 비교하는 방식이라 day_changed 신호를 따로 구독할 필요가 없다.
var _fortune_offered_day := -1
## 공범 엔딩(사용자 지시, 2026-08-24) - 어셔가 플레이어와 동거를 시작하면 매일
## 밤 자기 서점 대신 집으로 온다. 집 레벨(EconomyManager.house_level)에 따라
## home_interior.tmx/_2.tmx/_3.tmx가 통째로 바뀌는 별개 파일이라(사용자 지적,
## 2026-08-24), 세 파일 전부의 Spawn 레이어에 이 이름으로 지점이 있어야 한다
## (사용자 배치 예정). _resolve_usher_home_position()이 매번 "지금 집 레벨의"
## 파일을 새로 읽으므로(_spawn_index 캐시 미사용) 셋 중 어느 파일에 지점이
## 없으면 그 레벨에서만 조용히 안 보이게 된다(에러 없음).
const USHER_NPC_ID := "usher"
const USHER_LIVING_WITH_PLAYER_STATE := "usher_home_standing"
## 셰퍼드/모카 불륜 관계 - get_daily_dialogue()의 partner_death_reaction 참고.
const PARTNER_DEATH_PAIRS := {
	"shepherd": "mocha",
	"mocha": "shepherd",
}


## get_daily_dialogue()의 partner_death_reaction 분기와 같은 조건을 소비 없이
## 미리 확인한다 - MurderManager.has_pending_alibi_line()과 같은 이유(마주침
## 이모지가 오늘 눈물을 띄울지 미리 알아야 함).
func has_pending_partner_death_reaction(npc_id: String) -> bool:
	if not PARTNER_DEATH_PAIRS.has(npc_id):
		return false
	var partner_id: String = PARTNER_DEATH_PAIRS[npc_id]
	if is_alive(partner_id) or bool(_partner_death_reaction_shown.get(npc_id, false)):
		return false
	return not (get_definition(npc_id).get("story_dialogue", {}).get("partner_death_reaction", []) as Array).is_empty()


## has_pending_partner_death_reaction()이 "아직 소비 전"만 잡아내는 것과 달리,
## 대화가 끝나 소비된 뒤(dialogue_screen.gd의 close())에도 "오늘 그 대사를
## 했었다"는 걸 알아야 웃음/수줍음으로 안 바뀐다(MurderManager.was_alibi_shown_today()와
## 같은 이유).
func was_partner_death_reaction_shown_today(npc_id: String) -> bool:
	return int(_partner_death_reaction_shown_day.get(npc_id, -1)) == TimeManager.current_day


## requires_alive 필드는 문자열 하나("npc_id") 또는 배열(["a", "b"]) 둘 다
## 받는다 - 대사 한 줄이 다른 NPC를 두 명 이상 언급하는 경우도 있어서(사용자
## 지시, 2026-08-26 - "requires_alive 이거 두명은 체크 못해?"). 배열이면
## 적힌 전원이 다 살아있어야 조건 충족. 빈 문자열/빈 배열이면 조건 없음.
## 언더스코어 없이 공개해둔다 - email_manager.gd(emails.greeting 등)도 같은
## 필드를 재사용한다(사용자 지시, 2026-08-26 - 마린 죽었을 때도 셰퍼드가
## "오늘 마린이 왔다 갔어" 메일을 보내는 문제).
func requires_alive_met(value: Variant) -> bool:
	if value is Array:
		for npc_id in value:
			if not is_alive(String(npc_id)):
				return false
		return true
	var npc_id := String(value)
	return npc_id.is_empty() or is_alive(npc_id)


## 일상 대사 풀(dialogue.daily.요일.tier) 항목은 기존처럼 순수 배열
## (["줄1", "줄2"])이거나, 다른 NPC 생존 여부에 따라 내용이 갈리는
## {"lines": [...], "requires_alive": "npc_id", "fallback_lines": [...]}
## 형태일 수 있다(사용자 지시, 2026-08-26 - 셰퍼드가 죽은 벨제를 현재형으로
## 언급하는 잡담을 그대로 하는 문제 대응). requires_alive 대상이 죽었으면
## fallback_lines를(없으면 아무것도) 대신 쓴다 - 그냥 건너뛰기만 하면 그
## NPC가 죽을 때마다 잡담 풀이 계속 좁아지기 때문(사용자 지시 - "그러면 대사
## 풀이 좁아지잖아").
func _resolve_daily_pool_entry(entry: Variant) -> Array:
	if entry is Array:
		return entry
	if entry is Dictionary:
		if requires_alive_met(entry.get("requires_alive", "")):
			return entry.get("lines", [])
		return entry.get("fallback_lines", [])
	return []


func get_daily_dialogue(npc_id: String) -> Array:
	## 기본값은 "특수 대사"(오늘 다시 말 못 검) - 아래 일상 잡담 로테이션까지
	## 무사히 도달했을 때만 false로 내린다(_special_dialogue_shown_today 선언부
	## 주석 참고). 이 함수의 조기 return 분기들(애도/알리바이/마일스톤/세이지
	## 전용 트리거/파트너 사망 반응)은 전부 일회성이라 따로 안 건드려도 기본값
	## true가 자연히 적용된다.
	_special_dialogue_shown_today[npc_id] = true
	## murder_system.md 경찰 조사 - 살인 후 5일 이내 이 NPC와 처음 나누는
	## 대화는 그 자체로 애도+알리바이 대화여야 한다(사용자 지시, 2026-08-23 -
	## "살인 일어난 후 바로 다음 대화는 알리바이와 애도여야 할 거 같아"). 다른
	## 어떤 대기 중인 이벤트(호감도 마일스톤 등)보다도 먼저 확인한다 - 원래는
	## 마일스톤 우선순위 체크 "다음"에 있었는데, 그러다 보니 밀린 마일스톤
	## 대사가 있으면 애도 대신 그게 먼저 나와버렸다(사용자 리포트, 2026-08-26 -
	## "이샤 이벤트 안보고 살인 일어났더니 애도는 안하고 플로라 욕이나 하고
	## 있네"). 그래서 맨 위로 옮김. 순서: (있으면) 애도 대사
	## (story_dialogue.murder_grief) → 알리바이 한 줄(MurderManager.consume_alibi_line(),
	## 한 번 나오면 다시 안 나옴) → (스토커의 거짓 알리바이인 경우만)
	## corroboration_line → 목격 진술(consume_witness_line()). 목격 진술/뒷받침도
	## 선택 없이 곧바로 이어서 보여준다 - 플레이어가 놓칠 수 있는 선택지로
	## 만들지 않는다(사용자 지시, 2026-08-17: "무조건 보게 만들거라").
	var alibi_line := MurderManager.consume_alibi_line(npc_id)
	if not alibi_line.is_empty():
		# 눈물: 살인 사건 스토리 대화(애도/알리바이/목격 진술)일 때(사용자 지시,
		# 2026-08-25) - 아래 두 분기(폴리 고백/일반 애도) 둘 다 해당.
		request_emote(npc_id, EMOTE_DEJECTED)
		## 폴리는 이 "살인 후 첫 재회" 순간, 첫 번째 살인에 한해 일반 알리바이
		## 대신 "그날 밤 기억이 없다" 고백(poli.json story_dialogue.
		## first_murder_occurred)으로 완전히 대체한다(사용자 지시, 2026-08-17 -
		## 새 트리거 안 만들고 이미 있는 alibi_pending 재사용). 두 번째 살인
		## 이후엔(이미 한 번 고백했으므로) 폴리도 다른 NPC들처럼 평소 알리바이를
		## 댄다.
		if npc_id == POLI_NPC_ID and MurderManager.get_murder_count() == 1:
			var confession: Array = get_definition(npc_id).get("story_dialogue", {}).get("first_murder_occurred", {}).get("lines", [])
			if not confession.is_empty():
				return confession.duplicate()
		var lines: Array = []
		## 2차 이후 살인은 애도 대사가 1차랑 겹치면 안 되니(사용자 지시,
		## 2026-08-23) "murder_grief_<N>"이 있으면 그걸 우선 쓰고, 없으면
		## murder_grief로 폴백한다 - 지금까지처럼 murder_grief만 있는 NPC도
		## 그대로 동작.
		var story_dialogue: Dictionary = get_definition(npc_id).get("story_dialogue", {})
		var numbered_key := "murder_grief_%d" % MurderManager.get_murder_count()
		var grief_lines: Array = story_dialogue.get(numbered_key, story_dialogue.get("murder_grief", []))
		if not grief_lines.is_empty():
			var grief_victim_name: String = String(get_definition(get_most_recent_death_npc_id()).get("name", "그 사람"))
			lines.append_array(_substitute_victim_name(grief_lines, grief_victim_name))
		lines.append(alibi_line)
		var corroboration_line := MurderManager.consume_stalker_corroboration_line(npc_id)
		if not corroboration_line.is_empty():
			lines.append(corroboration_line)
		var witness_line := MurderManager.consume_witness_line(npc_id)
		if not witness_line.is_empty():
			lines.append(witness_line)
		return lines
	## 2차 살인 이후 용의자 지목 소문(story_dialogue.suspicion_talk_2) - 위
	## 애도/알리바이 대화와 같은 날 한 번에 몰아서 나오면 어색하다는 지적
	## (사용자 지시, 2026-08-26 - "1차때처럼 동일하게 다들 자기 알리바이만
	## 얘기했다가, 그 다음에 말 걸때 일상대사 대신에 나와야 하는 거야") - 그래서
	## 완전히 분리된 별도 대기열(MurderManager._suspicion_talk_2_pending)로 뺐다.
	## 알리바이 대화가 이미 끝난(그 NPC의 alibi_line이 더는 안 뜨는) 다음 재회
	## 때만 걸린다 - 위 알리바이 분기가 매번 먼저 확인되고 non-empty면 그 즉시
	## return하기 때문에, 이 아래 코드는 그 NPC의 알리바이가 이미 소비된
	## 이후로만 자연스럽게 도달한다.
	if MurderManager.has_pending_suspicion_talk(npc_id):
		var suspicion: Dictionary = get_definition(npc_id).get("story_dialogue", {}).get("suspicion_talk_2", {})
		var suspicion_lines: Array = suspicion.get("lines", [])
		MurderManager.consume_suspicion_talk(npc_id)
		if not suspicion_lines.is_empty() and requires_alive_met(suspicion.get("requires_alive", "")):
			return suspicion_lines.duplicate()
	## 호감도 마일스톤(추억의 물건 등) 대기 중이면 애도/알리바이 다음으로
	## 보여준다 - 여기서 뽑히는 순간 consume_pending_milestone()이 신호를
	## 내보내고(추억의 물건이면 이때 지급) 다시는 안 나온다. 추억의 물건
	## (is_memento)의 "그 NPC의 공간 안"에서만 터지는 위치 제한은 사용자 지시로
	## 없앴다(2026-08-26 - "광장에서도 마주쳤을 때 뛰어오고 그런 게 필요하다") -
	## heart_event_30(30 이벤트)의 위치 조건은 그대로 두고 100만 어디서든
	## 근접만으로 터진다. 인벤토리 자리(inventory_ok)는 그대로 확인한다
	## (사용자 리포트, 2026-08-25) - 자리가 없는데 그냥
	## 터뜨리면 InventoryManager.add_item()이 조용히 실패하고 이 마일스톤은
	## 이미 "봤음" 처리라 다시는 못 받아 도감 100% 수집이 영구히 막힘.
	## requires_alive(다른 NPC를 현재형으로 언급하는 대사)는 inventory_ok와 달리
	## "영원히 못 풀리는" 조건이라(죽은 NPC는 되살아나지 않음) 막고 대기시키면
	## 뒤에 대기 중인 다른 마일스톤(추억의 물건 포함)까지 영영 막힌다 - 그래서
	## while로 돌면서 조용히 건너뛴다(대사 없이 consume만, 화면엔 아무 것도 안
	## 보여줌).
	var pending_queue: Array = _pending_milestone.get(npc_id, [])
	while not pending_queue.is_empty():
		var pending: Dictionary = pending_queue[0]
		if not requires_alive_met(pending.get("requires_alive", "")):
			consume_pending_milestone(npc_id)
			pending_queue = _pending_milestone.get(npc_id, [])
			continue
		var threshold := int(pending.get("threshold", -1))
		var is_memento := bool(pending.get("is_memento", false))
		## 추억의 물건뿐 아니라 일반 선물(음반 등, lines 안 {"type":"gift",...}
		## 줄)도 인벤토리 자리를 확인해야 한다 - 자리가 없으면 선물 줄이 조용히
		## InventoryManager.add_item() 실패로 넘어가서 대사는 나왔는데 아이템은
		## 영영 사라지는 버그가 있었다(사용자 리포트, 2026-09-05 - "음반 못
		## 받았어.. 인벤이 다 차서 그런가바"). 추억의 물건과 같은 방식으로
		## 자리 날 때까지 큐에 그대로 대기시킨다.
		var gift_item_id := _find_gift_item_id(threshold, npc_id)
		var inventory_ok := true
		if is_memento:
			inventory_ok = InventoryManager.can_add_item("memento_%s" % npc_id, 1)
		elif not gift_item_id.is_empty():
			inventory_ok = InventoryManager.can_add_item(gift_item_id, 1)
		if inventory_ok:
			var milestone_lines: Array = get_milestone_dialogue(npc_id, threshold)
			consume_pending_milestone(npc_id)
			if not milestone_lines.is_empty():
				return milestone_lines.duplicate()
		break
	## 세이지의 스토리 트리거 3종 - 조건이 맞으면 평소 잡담 로테이션을 완전히
	## 건너뛰고 대체된다. 우선순위(더 구체적이고 드문 사건이 위): 무고한 NPC
	## 독살(공범 엔딩) > 첫 살인 후 영혼을 보기 시작함 > 살인 대기 중 경고
	## (하루 1회, horror_events.md). 셋 다 sage.json의 story_dialogue에서
	## 실제 문구를 가져온다 - 코드에는 조건 판정만 있고 대사는 데이터에 둠.
	if npc_id == SAGE_NPC_ID:
		## 영혼의 결정 설명(사용자 지시, 2026-08-25 - "그 아이템을 가진채로
		## 세이지에게 말을 걸면 딱 한번 대사 이벤트가 뜨게 돼") - 다른 세이지
		## 전용 트리거들보다 먼저 확인한다. 딱 한 번만 나온다.
		if InventoryManager.has_item(RevivalManager.SOUL_CRYSTAL_ITEM_ID) and not RevivalManager.has_explained_soul_crystal():
			var explanation: Array = RevivalManager.get_narration("soul_crystal_explanation")
			if not explanation.is_empty():
				RevivalManager.mark_soul_crystal_explained()
				return explanation.duplicate()
		if HorrorEventManager.consume_sage_poisoned_innocent_trigger():
			var lines: Array = get_definition(npc_id).get("story_dialogue", {}).get("player_poisoned_innocent_npc", [])
			if not lines.is_empty():
				return lines.duplicate()
		elif HorrorEventManager.consume_sage_soul_sight_trigger():
			var lines: Array = get_definition(npc_id).get("story_dialogue", {}).get("post_first_murder_soul_sight", [])
			if not lines.is_empty():
				return lines.duplicate()
		elif HorrorEventManager.consume_sage_warning_trigger():
			var warnings: Array = get_definition(npc_id).get("story_dialogue", {}).get("murder_warning_examples", [])
			if not warnings.is_empty():
				return (warnings.pick_random() as Array).duplicate()
	## 오늘 이미 일상 잡담이 한 번 뽑혔으면 새로 굴리지 않고 그대로 재생 -
	## _daily_dialogue_cache 선언부 주석 참고. (세이지 운세는 이 캐시에
	## 안 구워져 있으므로 아래에서 캐시 히트/미스와 무관하게 항상 따로 붙인다.)
	var picked: Array
	if _daily_dialogue_cache.has(npc_id):
		picked = (_daily_dialogue_cache[npc_id] as Array).duplicate(true)
	else:
		var dialogue: Dictionary = get_definition(npc_id).get("dialogue", {})
		var daily: Dictionary = dialogue.get("daily", {})
		var day: Dictionary = daily.get(TimeManager.get_weekday(), {})
		var pool: Array = []
		for entry in (day.get(get_affection_tier(npc_id), []) as Array):
			var resolved := _resolve_daily_pool_entry(entry)
			if not resolved.is_empty():
				pool.append(resolved)
		## 로시 제외(ROSHI_NPC_ID 참고) - 평일엔 비가 와야만 등장해서 평일 만남이
		## 전부 "비 오는 날"이 되어버리는 바람에, 이 혼합이 매번 걸려서 요일별로
		## 공들여 쓴 대사가 묻혔다(사용자 지시, 2026-08-29).
		if WeatherManager.is_raining() and npc_id != ROSHI_NPC_ID:
			pool.append_array(dialogue.get("rain_conversation", []))
		if has_horror_mode_started():
			## 사용자 지시(2026-08-23): "그 사람" 대신 실제 희생자 이름으로 - 가장
			## 최근 사건의 피해자 이름을 {victim_name} 자리에 채운다.
			var victim_name: String = String(get_definition(get_most_recent_death_npc_id()).get("name", "그 사람"))
			for entry in (dialogue.get("horror_conversation", []) as Array):
				pool.append(_substitute_victim_name(entry, victim_name))
		## 플레이어가 이 NPC에게 자유 작성 메일을 보냈고 아직 언급 안 됐으면, 오늘의
		## 후보 풀에 mail_reaction 템플릿 하나를 더 끼워 넣는다 - "{player_mail_content}"를
		## 실제 메일 본문으로 바로 치환해서 넣어둔다(EmailManager.clear_pending_mail_reaction()로
		## 지우기 전에 내용을 먼저 읽어와야 하므로 여기서 치환까지 끝내는 게 안전함).
		## 이게 뽑히면 아래에서 지워서 같은 메일이 두 번 언급되지 않게 한다.
		var mail_reaction_index := -1
		if EmailManager.has_pending_mail_reaction(npc_id):
			var mail_templates: Array = dialogue.get("mail_reaction", [])
			if not mail_templates.is_empty():
				var mail_content := EmailManager.get_pending_mail_reaction_content(npc_id)
				mail_reaction_index = pool.size()
				pool.append(_substitute_mail_content(mail_templates.pick_random(), mail_content))
		if pool.is_empty():
			return []
		var index := randi() % pool.size()
		if pool.size() > 1 and index == int(_last_daily_dialogue_index.get(npc_id, -1)):
			index = (index + 1) % pool.size()
		_last_daily_dialogue_index[npc_id] = index
		if index == mail_reaction_index:
			EmailManager.clear_pending_mail_reaction(npc_id)
		picked = pool[index]
		## 셰퍼드/모카는 서로 불륜 상대다(shepherd.json/mocha.json special_notes) -
		## 둘 중 한쪽이 살해당하면, 남은 쪽에게는 위 애도+알리바이 대화 다음번
		## 재회 때 한정으로 한 번 더 특별한 반응을 보여준다(사용자 지시,
		## 2026-08-23). PARTNER_DEATH_PAIRS에 없는 NPC나 상대가 죽지 않았으면
		## 그냥 무시하고 평소 잡담으로 넘어간다.
		if PARTNER_DEATH_PAIRS.has(npc_id):
			var partner_id: String = PARTNER_DEATH_PAIRS[npc_id]
			if not is_alive(partner_id) and not bool(_partner_death_reaction_shown.get(npc_id, false)):
				var reaction: Array = get_definition(npc_id).get("story_dialogue", {}).get("partner_death_reaction", [])
				if not reaction.is_empty():
					_partner_death_reaction_shown[npc_id] = true
					_partner_death_reaction_shown_day[npc_id] = TimeManager.current_day
					return reaction.duplicate()
		## 여기까지 왔으면 정말로 일상 잡담 로테이션(비/공포 대화, 메일 반응
		## 포함)이라 오늘 다시 말 걸 수 있다 - 이번에 뽑힌 대사(운세 제외)를
		## 오늘 하루 고정으로 캐시해서, 재대화 때 로테이션 대신 같은 대사를
		## 반복한다.
		_daily_dialogue_cache[npc_id] = picked.duplicate(true)
	_special_dialogue_shown_today[npc_id] = false
	if npc_id == SAGE_NPC_ID:
		var fortune_lines := _build_fortune_offer_lines()
		if not fortune_lines.is_empty():
			picked = picked.duplicate(true)
			picked.append_array(fortune_lines)
	return picked


## 세이지 전용(호출부에서 이미 SAGE_NPC_ID로 걸러서 부름) - 오늘 이미 물어봤으면
## 빈 배열(못 보는 날이 있어도 괜찮다는 사용자 지시라 별도 예외 처리 불필요).
## 물어봤다는 표시는 실제로 이 배열이 오늘의 대사에 붙어 나가는 이 순간
## 남긴다 - 좋은/나쁜 결과는 여기서 미리 굴려서 대사(fortune.good_lines/
## bad_lines)와 실제 효과(buff 타입 줄, dialogue_screen.gd가 처리)를 같이 묶는다.
func _build_fortune_offer_lines() -> Array:
	if _fortune_offered_day == TimeManager.current_day:
		return []
	var fortune: Dictionary = get_definition(SAGE_NPC_ID).get("fortune", {})
	var offer_line := String(fortune.get("offer_line", ""))
	if offer_line.is_empty():
		return []
	var is_debuff := randf() >= FORTUNE_GOOD_CHANCE
	var pool: Array = fortune.get("bad_lines" if is_debuff else "good_lines", [])
	if pool.is_empty():
		return []
	_fortune_offered_day = TimeManager.current_day
	var result_line: String = String(pool[randi() % pool.size()])
	var percent := FORTUNE_DEBUFF_PERCENT if is_debuff else FORTUNE_BUFF_PERCENT
	return [
		offer_line,
		{
			"type": "choice",
			"options": [
				{
					"label": String(fortune.get("accept_label", "봐줘")),
					"affection": 0,
					"response": [
						result_line,
						{"type": "buff", "percent": percent, "duration_minutes": FORTUNE_DURATION_MINUTES, "is_debuff": is_debuff},
					],
				},
				{
					"label": String(fortune.get("decline_label", "괜찮아")),
					"affection": 0,
					"response": (fortune.get("decline_response", []) as Array).duplicate(true),
				},
			],
		},
	]


## dialogue.mail_reaction 템플릿(문자열 또는 {"text","emotion"} 줄의 배열) 안에
## 있는 "{player_mail_content}"를 실제 메일 본문으로 바꿔치기한 새 배열을 만든다 -
## 원본 JSON 데이터를 건드리지 않도록 깊은 복사 위에서 치환한다.
func _substitute_mail_content(template: Array, mail_content: String) -> Array:
	var result: Array = template.duplicate(true)
	for i in result.size():
		var line: Variant = result[i]
		if line is Dictionary:
			line["text"] = String(line.get("text", "")).replace("{player_mail_content}", mail_content)
		else:
			result[i] = String(line).replace("{player_mail_content}", mail_content)
	return result


## dialogue.horror_conversation 항목 안의 "{victim_name}"을 가장 최근 사건의
## 피해자 이름으로 바꿔치기한다 - _substitute_mail_content()와 동일한 패턴.
func _substitute_victim_name(template: Array, victim_name: String) -> Array:
	var result: Array = template.duplicate(true)
	for i in result.size():
		var line: Variant = result[i]
		if line is Dictionary:
			line["text"] = apply_korean_particles(String(line.get("text", "")), "{victim_name}", victim_name)
		else:
			result[i] = apply_korean_particles(String(line), "{victim_name}", victim_name)
	return result


## 데이터(horror_conversation, endings.json, stalker_emails.json 등)에는
## 예전엔 받침 유무를 계산해서 이/가·은/는·을/를·이랑/랑을 자동으로 바꿔치기
## 했는데, "이다"/"이었" 같은 조사가 아닌 표현(예: marin.json "{player_name}이다")
## 까지 조사로 오인해서 "가다"처럼 완전히 엉뚱한 말을 만드는 등 계속 새로운
## 예외가 나왔다(사용자 지시, 2026-08-26 - "개같은 이름끝처리좀지워"). 이제
## 자동 변환 없이 이름만 그대로 채워 넣는다 - 조사는 데이터 쪽에서 항상
## "{player_name}(이)가"처럼 괄호로 직접 표기하는 걸로 완전히 넘어감(사용자
## 확정: "보통 그렇게 다 괄호표시로 보여줘").
func apply_korean_particles(text: String, placeholder: String, name: String) -> String:
	return text.replace(placeholder, name)


func get_weekday_group(weekday: String) -> String:
	return String(WEEKDAY_GROUPS.get(weekday, "weekend"))


## murder_system.md/horror_events.md: 사망한 NPC는 스케줄이 삭제된다.
## shop.md 승계 규칙("한쪽이 죽으면 남은 쪽이 가게를 잇는다")을 스케줄에도
## 반영한다(2026-08-16 사용자 확정 - "벨제 가게 자리에 벨제가 없는데 사용은
## 되네, 셰퍼드가 봐준다는 설정이면 셰퍼드 스케줄을 벨제처럼 해야 할 거
## 같다"). 자세한 승계 방향은 SHOP_PRIMARY_OPERATOR/_get_dead_shop_partner_id()
## 참고 - 주 운영자가 죽었을 때만 보조가 그 스케줄을 잇고, 둘 다 살아있거나
## 보조가 죽었을 땐 원래 자기 것 그대로.
func _get_effective_schedule(npc_id: String) -> Dictionary:
	if npc_id == USHER_NPC_ID and MurderManager.is_living_with_stalker():
		return _usher_living_with_player_schedule()
	var dead_partner_id := _get_dead_shop_partner_id(npc_id)
	if not dead_partner_id.is_empty():
		return get_definition(dead_partner_id).get("schedule", {})
	return get_definition(npc_id).get("schedule", {})


## 요일군(월수목/화금/주말) 전부 마지막 스케줄 항목(=서점 마감 후 상태, 지금은
## 전부 21:00 "book_working")만 USHER_LIVING_WITH_PLAYER_STATE로 바꿔치기한다 -
## 낮 동안 서점 운영은 그대로 두고 "퇴근길"만 집으로 바꾸는 것.
func _usher_living_with_player_schedule() -> Dictionary:
	var base: Dictionary = (get_definition(USHER_NPC_ID).get("schedule", {}) as Dictionary).duplicate(true)
	for group_key in base.keys():
		var entries: Array = (base[group_key] as Dictionary).get("entries", [])
		if entries.is_empty():
			continue
		var last_entry: Dictionary = entries[entries.size() - 1]
		last_entry["state"] = USHER_LIVING_WITH_PLAYER_STATE
	return base


## 2인 상점에서 실제로 상점을 지키는 "주 운영자"(벨제/마린 - 스케줄이 거의
## 항상 "_working")가 죽었을 때만, 한가하게 돌아다니던 "보조"(셰퍼드/로시 -
## "_looking"/"_sitting" 위주)가 그 스케줄을 대신 쓴다(사용자 지적,
## 2026-08-24 - "벨제가 셰퍼드의 스케줄을 대신하면, 상점을 운영할 사람이
## 없어. 벨제나 마린은 로시의 죽음을 대체할 필요가 없어"). 예전엔 양방향으로
## 동작해서, 보조가 죽으면 오히려 주 운영자가 보조의 "돌아다니는" 스케줄로
## 끌려가 상점이 실질적으로 비어버리는 버그가 있었다. 셰퍼드/로시처럼 array
## 순서만으론 누가 주 운영자인지 알 수 없어서(로시가 먼저 나오지만 실제
## 운영자는 마린) shops.json 구조는 안 건드리고 여기 표로만 관리한다.
const SHOP_PRIMARY_OPERATOR := {
	"shepherd": "belje",
	"roshi": "marin",
}


func _get_dead_shop_partner_id(npc_id: String) -> String:
	var primary_id := String(SHOP_PRIMARY_OPERATOR.get(npc_id, ""))
	if not primary_id.is_empty() and not is_alive(primary_id):
		return primary_id
	return ""


func get_current_schedule_state(npc_id: String) -> String:
	if not is_alive(npc_id):
		return ""
	var schedule: Dictionary = _get_effective_schedule(npc_id)
	var group: Dictionary = schedule.get(get_weekday_group(TimeManager.get_weekday()), {})
	if group.is_empty():
		return ""
	if bool(group.get("visible_only_when_raining", false)) and not WeatherManager.is_raining():
		return ""
	var current_state := ""
	for entry in group.get("entries", []):
		if TimeManager.get_time_string() >= String(entry.get("time", "00:00")):
			current_state = String(entry.get("state", ""))
	return current_state


## get_current_schedule_state()와 같은 판정이지만 "지금"이 아니라 임의 요일·
## 시각 기준으로 그 시점의 상태를 구한다(사용자 지시, 2026-08-17). 알리바이
## 조사 시각을 살인 시각(22시, 다들 이미 자기 자리로 돌아가 있어 서로 겹칠
## 일이 거의 없음)이 아니라 더 이른 시각으로 잡을 때 씀 - MurderManager의
## ALIBI_CHECK_HOUR 참고.
func get_schedule_state_at(npc_id: String, weekday: String, time_string: String, is_raining: bool) -> String:
	if not is_alive(npc_id):
		return ""
	var schedule: Dictionary = _get_effective_schedule(npc_id)
	var group: Dictionary = schedule.get(get_weekday_group(weekday), {})
	if group.is_empty():
		return ""
	if bool(group.get("visible_only_when_raining", false)) and not is_raining:
		return ""
	var state := ""
	for entry in group.get("entries", []):
		if time_string >= String(entry.get("time", "00:00")):
			state = String(entry.get("state", ""))
	return state


## murder_system.md 경찰 조사 확장(목격 증언, 사용자 지시 2026-08-17) - npc_id가
## 주어진 요일·비 여부 기준으로 "하루 종일" 스케줄상 같은 맵에 시간대가
## 겹쳤던 다른 생존 NPC들을 {"npc_id","map_id"} 딕셔너리 배열로 돌려준다.
## map_id를 같이 주는 이유(사용자 지시, 2026-08-17) - "그날 [이름]을 봤어"만
## 으론 어디서 봤는지가 없어서 플레이어가 알리바이와 대조할 수가 없다.
## 정확한 자리(state 문자열)가 아니라 _spawn_index의 실제 map_id로 비교한다 -
## "pond_standing_plaza4"처럼 접두어 문자열만으론 장소를 못 알아내는 마커도
## 정확히 잡아내기 위함. 결과 해석은 호출부(MurderManager) 몫: 비어있으면
## 아무도 못 봄, 하나 이상이면 그중 하나를 골라 이름+장소를 증언.
func get_witness_candidates(npc_id: String, weekday: String, is_raining: bool) -> Array[Dictionary]:
	var my_ranges := _get_day_map_ranges(npc_id, weekday, is_raining)
	if my_ranges.is_empty():
		return []
	var result: Array[Dictionary] = []
	for other_id in get_all_ids():
		if other_id == npc_id or not is_alive(other_id):
			continue
		var overlap_map_id := _find_overlap_map_id(my_ranges, _get_day_map_ranges(other_id, weekday, is_raining))
		if not overlap_map_id.is_empty():
			result.append({"npc_id": other_id, "map_id": overlap_map_id})
	return result


## get_witness_candidates()용 - 하루치 스케줄 항목을 (map_id, 시작시각, 종료시각)
## 구간 배열로 펼친다. 마지막 항목의 종료시각은 자정(24:00)까지로 본다.
func _get_day_map_ranges(npc_id: String, weekday: String, is_raining: bool) -> Array[Dictionary]:
	var schedule: Dictionary = _get_effective_schedule(npc_id)
	var group: Dictionary = schedule.get(get_weekday_group(weekday), {})
	if group.is_empty():
		return []
	if bool(group.get("visible_only_when_raining", false)) and not is_raining:
		return []
	var entries: Array = group.get("entries", [])
	var ranges: Array[Dictionary] = []
	for i in entries.size():
		var state := String(entries[i].get("state", ""))
		var map_id := String(_spawn_index.get(state, {}).get("map_id", ""))
		if map_id.is_empty():
			continue
		var end_time := "24:00" if i == entries.size() - 1 else String(entries[i + 1].get("time", "24:00"))
		ranges.append({"map_id": map_id, "start": String(entries[i].get("time", "00:00")), "end": end_time})
	return ranges


## 겹치는 첫 구간의 map_id를 돌려준다(없으면 ""). 두 사람이 하루에 여러 곳에서
## 겹칠 수 있지만, 증언 한 줄엔 장소 하나만 쓰므로 첫 번째로 찾은 것만 쓴다.
func _find_overlap_map_id(a: Array[Dictionary], b: Array[Dictionary]) -> String:
	for ra in a:
		for rb in b:
			if String(ra["map_id"]) == String(rb["map_id"]) and String(ra["start"]) < String(rb["end"]) and String(rb["start"]) < String(ra["end"]):
				return String(ra["map_id"])
	return ""


## get_current_schedule_state()가 고르는 "지금 활성 상태" 바로 다음으로 오늘
## 안에서 바뀔 예정인 항목을 반환한다({"time":"HH:MM","state":...}). 오늘
## 더 이상 남은 항목이 없으면(지금이 이미 마지막 항목) 빈 Dictionary - 자정
## 취침으로 인한 다음 날 스케줄 전환은 이미 하드 리셋이라 예측 대상이 아니다.
## NPCWorldManager가 "지금 출발해야 제 시간에 도착하는지" 미리 내다볼 때 쓴다.
func get_next_schedule_change(npc_id: String) -> Dictionary:
	if not is_alive(npc_id):
		return {}
	var schedule: Dictionary = _get_effective_schedule(npc_id)
	var group: Dictionary = schedule.get(get_weekday_group(TimeManager.get_weekday()), {})
	if group.is_empty():
		return {}
	if bool(group.get("visible_only_when_raining", false)) and not WeatherManager.is_raining():
		return {}
	var now := TimeManager.get_time_string()
	for entry in group.get("entries", []):
		if String(entry.get("time", "00:00")) > now:
			return entry.duplicate()
	return {}


## 스케줄 상태 이름(예: "plaza5_standing")을 실제 맵+좌표로 바꾼다.
## get_npc_world_position()과 같은 _spawn_index를 쓰되, "지금" 활성 상태가
## 아니라 임의의 상태 이름(get_next_schedule_change()가 돌려준 다음 상태 등)을
## 넘길 수 있다.
func resolve_state_position(state: String) -> Dictionary:
	if state.is_empty():
		return {}
	if state == USHER_LIVING_WITH_PLAYER_STATE:
		return _resolve_usher_home_position()
	var spawn: Dictionary = _spawn_index.get(state, {})
	if spawn.is_empty():
		return {}
	return spawn.duplicate()


## NPCWorldManager가 이 NPC를 실제로 map_id의 position 좌표에 확정 정착시켰을
## 때(같은 맵 안 이동이든 맵 간 이동이든, 걷는 게 완전히 끝났을 때) 호출한다.
func set_npc_physical_spot(npc_id: String, map_id: String, position: Vector2) -> void:
	_npc_physical_spot[npc_id] = {"map_id": map_id, "position": position}


## NPCWorldManager가 이 NPC를 어딘가로 출발시킬 때(더 이상 어느 한 좌표에
## 확정적으로 있다고 할 수 없을 때) 호출한다.
func clear_npc_physical_spot(npc_id: String) -> void:
	_npc_physical_spot.erase(npc_id)


## 스케줄이 아니라 실제로 걸어서 정확히 그 좌표까지 도착해 있는지 확인한다 -
## 계산대처럼 "실제로 지금 정확히 그 자리에 있어야만" 되는 상호작용에 쓴다.
## ARRIVE_EPSILON 수준의 부동소수점 오차는 허용한다.
func is_npc_settled_at(npc_id: String, map_id: String, position: Vector2) -> bool:
	var spot: Dictionary = _npc_physical_spot.get(npc_id, {})
	if spot.is_empty() or String(spot.get("map_id", "")) != map_id:
		return false
	return Vector2(spot.get("position", Vector2.INF)).distance_to(position) <= 1.0


## Resolves the NPC's current schedule state to an actual map + coordinate by
## looking it up in the Spawn layer index (schedule.md states are authored
## to match real Spawn point names, e.g. "pasture_working" in
## pasture_interior.tmx). Returns {} if the NPC isn't visible right now
## (e.g. 로시 on a non-rainy day) or its state has no matching spawn point.
func get_npc_world_position(npc_id: String) -> Dictionary:
	var seated_station := RestaurantManager.get_seated_station(npc_id)
	if seated_station != -1:
		var seat: Dictionary = _spawn_index.get("restaurant_seat%d" % (seated_station + 1), {})
		if not seat.is_empty():
			return seat.duplicate()
	return get_schedule_only_position(npc_id)


## get_npc_world_position()과 달리 식당 착석 여부를 무시하고, 순전히 스케줄
## 상으로만 지금 어디 있어야 하는지 계산한다. NPCWorldManager가 "한 번도
## 추적한 적 없는 NPC가 마침 식당 손님으로 배정된 그 순간" 임시 기준 위치를
## 잡을 때 쓴다 - get_npc_world_position()을 그대로 쓰면 이미 좌석 좌표를
## 돌려주는 바람에 "원래 있던 자리"가 곧 "목표 좌석"이 되어버려서, 걸어오는
## 거리가 0으로 계산돼 애니메이션 없이 좌석에 순간이동한 것처럼 보이는
## 버그가 있었다(사용자 리포트 - 로시가 식당에 처음 배정될 때 순간이동).
func get_schedule_only_position(npc_id: String) -> Dictionary:
	var state := get_current_schedule_state(npc_id)
	if state.is_empty():
		return {}
	if state == USHER_LIVING_WITH_PLAYER_STATE:
		return _resolve_usher_home_position()
	var spawn: Dictionary = _spawn_index.get(state, {})
	if spawn.is_empty():
		push_warning("No spawn point found for schedule state '%s' (npc: %s)" % [state, npc_id])
		return {}
	return spawn.duplicate()


## _spawn_index는 부팅 시점에 home_interior "레벨 1" 파일만 읽어서 만들어져
## 있어서(WorldMap.MAP_PATHS가 고정 경로), 집을 업그레이드한 플레이어에겐
## 좌표가 안 맞을 수 있다는 지적(사용자, 2026-08-24 - "2,3 레벨이 되면 아예
## 맵이 바뀌는 거 아니야?"). 그래서 이 상태만 캐시를 안 쓰고 호출될 때마다
## WorldMap.get_map_path()로 "지금 집 레벨의" 실제 파일을 다시 읽어서 정확한
## 좌표를 구한다 - home_interior_2/3.tmx에도 같은 이름(usher_home_standing)의
## 스폰 지점이 있어야 한다(사용자 배치 예정, 3개 파일 전부).
func _resolve_usher_home_position() -> Dictionary:
	var path := WorldMap.get_map_path("home_interior")
	if path.is_empty():
		return {}
	var spawns: Dictionary = WorldMap.parse_spawns(path)
	if not spawns.has(USHER_LIVING_WITH_PLAYER_STATE):
		return {}
	return {"map_id": "home_interior", "position": spawns[USHER_LIVING_WITH_PLAYER_STATE]}


# 아래는 겹침 자동 보정 시도(사용자 요청 범위 밖이라 되돌림, 2026-08-01) -
# 삭제하지 않고 주석으로만 남겨둠. 나중에 실제로 필요해지면 위 함수의
# `return spawn.duplicate()`를 `return _deconflict_position(npc_id, spawn.duplicate())`로
# 바꾸고 get_current_schedule_state/spawn 조회 부분을 _resolve_schedule_position()으로
# 옮기면 그대로 재사용 가능.
#
# ## 좌석/자리 겹침 보정 없이, 스케줄만 보고 계산한 순수 위치 - _deconflict_position()이
# ## 다른 NPC들과 비교할 때 이걸 써야 한다(안 그러면 이미 보정된 위치끼리 비교해서
# ## 보정이 누적/진동할 수 있다).
# func _resolve_schedule_position(npc_id: String) -> Dictionary:
# 	var state := get_current_schedule_state(npc_id)
# 	if state.is_empty():
# 		return {}
# 	var spawn: Dictionary = _spawn_index.get(state, {})
# 	if spawn.is_empty():
# 		push_warning("No spawn point found for schedule state '%s' (npc: %s)" % [state, npc_id])
# 		return {}
# 	return spawn.duplicate()
#
# ## 같은 이름의 스케줄 상태(예: "general_looking")를 여러 NPC가 동시에 공유해서
# ## 정확히 같은 좌표에 겹쳐 서는 경우가 있다(day4 점검에서 다수 발견 - 로시/마린,
# ## 폴리/어셔, 벨제/플로라/마린 등). 기획 데이터를 손대는 대신, 같은 맵의 같은
# ## 좌표를 공유하는 다른 살아있는 NPC가 있으면 id 알파벳 순으로 순번을 매겨
# ## 두 번째부터 작은 고정 오프셋만큼 떨어뜨린다.
# const DECONFLICT_EPSILON := 1.0
# const DECONFLICT_OFFSETS: Array[Vector2] = [
# 	Vector2(-10, 0), Vector2(10, 0), Vector2(0, -10), Vector2(0, 10),
# 	Vector2(-10, -8), Vector2(10, -8), Vector2(-10, 8), Vector2(10, 8),
# ]
#
# func _deconflict_position(npc_id: String, base: Dictionary) -> Dictionary:
# 	var sharing: Array[String] = [npc_id]
# 	for other_id in get_all_ids():
# 		if other_id == npc_id or not is_alive(other_id):
# 			continue
# 		if RestaurantManager.get_seated_station(other_id) != -1:
# 			continue
# 		var other_base := _resolve_schedule_position(other_id)
# 		if other_base.is_empty():
# 			continue
# 		if String(other_base["map_id"]) != String(base["map_id"]):
# 			continue
# 		if (other_base["position"] as Vector2).distance_to(base["position"]) > DECONFLICT_EPSILON:
# 			continue
# 		sharing.append(other_id)
# 	if sharing.size() <= 1:
# 		return base
# 	sharing.sort()
# 	var index := sharing.find(npc_id)
# 	if index <= 0:
# 		return base
# 	var result := base.duplicate()
# 	result["position"] = (base["position"] as Vector2) + DECONFLICT_OFFSETS[(index - 1) % DECONFLICT_OFFSETS.size()]
# 	return result


## "current_position"은 참고용으로만 저장된다 - 불러올 때는 쓰지 않고, 복원된
## 시간/요일/날씨로부터 get_npc_world_position()이 매번 새로 계산한다. 그래서
## 저장된 좌표가 오래돼서 실제 상태와 어긋나는 일이 애초에 생기지 않는다.
func get_save_data() -> Dictionary:
	var npc_states: Dictionary = {}
	for npc_id in _definitions:
		npc_states[npc_id] = {
			"affection": get_affection(npc_id),
			"alive": is_alive(npc_id),
			"completed_events": (_completed_events.get(npc_id, []) as Array).duplicate(),
			"memento_received": has_completed_event(npc_id, MEMENTO_AFFECTION),
			"murder_candidate_flagged": bool(_murder_candidate_flagged.get(npc_id, false)),
			"partner_death_reaction_shown": bool(_partner_death_reaction_shown.get(npc_id, false)),
			"talked_today": has_talked_today(npc_id),
			"special_dialogue_shown_today": has_special_dialogue_shown_today(npc_id),
			"daily_dialogue_cache": (_daily_dialogue_cache.get(npc_id, []) as Array).duplicate(true),
			"current_position": _serialize_position(npc_id),
			"death_day": get_death_day(npc_id),
			"scent_color": get_scent_color(npc_id),
			"pending_milestone": (_pending_milestone.get(npc_id, []) as Array).duplicate(true),
			"shown_events": (_shown_events.get(npc_id, []) as Array).duplicate(),
			"heart_event_30_shown": has_shown_heart_event(npc_id),
			"memento_pending_since_day": int(_memento_pending_since_day.get(npc_id, -1)),
			"memento_reminder_sent": bool(_memento_reminder_sent.get(npc_id, false)),
		}
	return {
		"npc_states": npc_states,
		"dead_npc_ids": _dead_npc_ids,
		"fortune_offered_day": _fortune_offered_day,
	}


func load_save_data(data: Dictionary) -> void:
	var npc_states: Dictionary = data.get("npc_states", {})
	for npc_id in npc_states:
		var state: Dictionary = npc_states[npc_id]
		_affection[npc_id] = int(state.get("affection", 0))
		_alive[npc_id] = bool(state.get("alive", true))
		var completed: Array = []
		for threshold in (state.get("completed_events", []) as Array):
			completed.append(int(threshold))
		_completed_events[npc_id] = completed
		## 이 필드가 없던 세이브(2026-08-23 이전)는 빈 배열로 취급 - requires
		## 게이팅이 걸린 이벤트가 있으면 다시 조건을 만족할 때 자연스럽게 뜬다.
		var shown: Array = []
		for threshold in (state.get("shown_events", []) as Array):
			shown.append(int(threshold))
		_shown_events[npc_id] = shown
		_shown_heart_events[npc_id] = bool(state.get("heart_event_30_shown", false))
		_murder_candidate_flagged[npc_id] = bool(state.get("murder_candidate_flagged", false))
		_partner_death_reaction_shown[npc_id] = bool(state.get("partner_death_reaction_shown", false))
		_talked_today[npc_id] = bool(state.get("talked_today", false))
		_special_dialogue_shown_today[npc_id] = bool(state.get("special_dialogue_shown_today", false))
		var cached_daily_dialogue: Array = (state.get("daily_dialogue_cache", []) as Array).duplicate(true)
		if not cached_daily_dialogue.is_empty():
			_daily_dialogue_cache[npc_id] = cached_daily_dialogue
		var death_day := int(state.get("death_day", -1))
		if death_day >= 0:
			_death_days[npc_id] = death_day
		var scent_color := String(state.get("scent_color", ""))
		if not scent_color.is_empty():
			_active_scent[npc_id] = scent_color
		## 큐 도입 전 세이브(2026-08-23 이전)는 이 필드가 단일 Dictionary였음 -
		## 예전 세이브를 불러와도 죽지 않게 배열로 감싸서 받아들인다.
		var pending_raw: Variant = state.get("pending_milestone", [])
		var pending_queue: Array = []
		if pending_raw is Array:
			for entry in pending_raw:
				pending_queue.append((entry as Dictionary).duplicate())
		elif pending_raw is Dictionary and not (pending_raw as Dictionary).is_empty():
			pending_queue.append((pending_raw as Dictionary).duplicate())
		if not pending_queue.is_empty():
			_pending_milestone[npc_id] = pending_queue
		var pending_since := int(state.get("memento_pending_since_day", -1))
		if pending_since >= 0:
			_memento_pending_since_day[npc_id] = pending_since
		if bool(state.get("memento_reminder_sent", false)):
			_memento_reminder_sent[npc_id] = true
	_dead_npc_ids.clear()
	for npc_id in data.get("dead_npc_ids", []):
		_dead_npc_ids.append(String(npc_id))
	_fortune_offered_day = int(data.get("fortune_offered_day", -1))


## 디버그 전용(game_manager.gd F8) - 살인 시스템 테스트용으로 호감도를
## 곧장 특정 값까지 끌어올린다. _add_affection()을 그대로 거쳐가서 murder
## candidate 등록/호감도 임계 이벤트 트리거가 실제 플레이와 동일하게 작동한다.
func debug_set_affection(npc_id: String, value: int) -> void:
	_add_affection(npc_id, value - get_affection(npc_id))


func _add_affection(npc_id: String, amount: int) -> void:
	if not is_alive(npc_id):
		return
	var old_tier := get_affection_tier(npc_id)
	var new_value: int = clampi(get_affection(npc_id) + amount, MIN_AFFECTION, MAX_AFFECTION)
	_affection[npc_id] = new_value
	affection_changed.emit(npc_id, new_value)
	# 하트: 호감도 구간(low/mid/high)을 막 넘었을 때 - 내려갈 때(비선호 음식 등)는
	# 제외하고 올라갈 때만.
	if _affection_tier_rank(get_affection_tier(npc_id)) > _affection_tier_rank(old_tier):
		request_emote(npc_id, EMOTE_HEART)
	_check_affection_events(npc_id, new_value)
	if is_murder_candidate(npc_id) and not bool(_murder_candidate_flagged.get(npc_id, false)):
		_murder_candidate_flagged[npc_id] = true
		murder_candidate_registered.emit(npc_id)


func _affection_tier_rank(tier: String) -> int:
	match tier:
		"high":
			return 2
		"mid":
			return 1
		_:
			return 0


## 임계값을 처음 넘은 순간 "완료됨" 표시(재중복 방지)까지는 바로 하지만,
## 실제 신호(affection_event_triggered/memento_received)와 추억의 물건 지급은
## 아직 안 한다 - NPCManager.consume_pending_milestone()이 그 대사가 실제로
## 화면에 뜰 때(get_daily_dialogue()가 골라 보여줄 때) 대신 내보낸다.
## 2026-08-23: 이벤트가 다른 NPC의 이벤트를 먼저 봐야 열리는 경우("requires":
## {"npc_id": ..., "threshold": ...})를 지원한다 - 선행 조건이 아직 실제로
## 화면에 뜨지 않았으면(has_shown_event) completed 처리를 미루고 다음 기회에
## 다시 검사한다(예: 이 NPC 호감도가 먼저 임계값을 넘고 선행 대사는 나중에
## 보는 순서라도 놓치지 않게, consume_pending_milestone()이 _recheck_gated_events()
## 로 다른 NPC들을 재검사해준다).
func _check_affection_events(npc_id: String, affection: int) -> void:
	var completed: Array = _completed_events.get(npc_id, [])
	for event in get_definition(npc_id).get("affection_events", []):
		var threshold := int(event.get("threshold", -1))
		if affection < threshold or completed.has(threshold):
			continue
		var requires: Dictionary = event.get("requires", {})
		if not requires.is_empty():
			var required_npc_id := String(requires.get("npc_id", ""))
			var required_threshold := int(requires.get("threshold", -1))
			if not has_shown_event(required_npc_id, required_threshold):
				continue
		## requires와 반대로, 다른 NPC 쪽 이벤트가 "이미 나왔으면" 이 이벤트는
		## 영원히 건너뛴다(재시도 큐에 안 넣음) - 황금 낚싯대처럼 로시/마린 중
		## 한쪽만 줄 수 있는 상호 배타 이벤트용(사용자 지시, 2026-09 - "한번
		## 황금 낚시대 얻으면 남은 로시or마린은 낚시대 이벤트 안나오는거로").
		## has_shown_event()(대사로 실제 소비된 시점)가 아니라 has_completed_event()
		## (임계값을 넘어 확정된 시점)로 판정해야 한다 - 두 NPC 호감도가 거의
		## 동시에(예: 디버그로 전원 호감도 일괄 상승) 50을 넘으면, 아직 둘 다
		## 대사로 소비되기 전이라 has_shown_event 기준으로는 서로를 못 막아서
		## 로시/마린 둘 다 황금 낚싯대를 주는 버그가 있었다(사용자 리포트,
		## 2026-09-04 - "황금 낚시대 마린한테 이미 받았는데 로시가 또 주는데?").
		var requires_not_shown: Dictionary = event.get("requires_not_shown", {})
		if not requires_not_shown.is_empty():
			var excluded_npc_id := String(requires_not_shown.get("npc_id", ""))
			var excluded_threshold := int(requires_not_shown.get("threshold", -1))
			if has_completed_event(excluded_npc_id, excluded_threshold):
				completed.append(threshold)
				_completed_events[npc_id] = completed
				continue
		completed.append(threshold)
		_completed_events[npc_id] = completed
		var queue: Array = _pending_milestone.get(npc_id, [])
		queue.append({
			"threshold": threshold,
			"is_memento": String(event.get("type", "")) == "memento",
			## 다른 NPC를 현재형으로 언급하는 대사(예: 이샤가 "오늘 플로라가
			## 왔어")가 그 NPC 사망 후에도 나오지 않게 - suspicion_talk_2와
			## 같은 필드명(사용자 지시, 2026-08-25). get_daily_dialogue()가
			## 소비 시점에 확인한다(대상이 그때 이미 죽어있을 수도 있어서).
			"requires_alive": String(event.get("requires_alive", "")),
		})
		_pending_milestone[npc_id] = queue
		if String(event.get("type", "")) == "memento" and not _memento_pending_since_day.has(npc_id):
			_memento_pending_since_day[npc_id] = TimeManager.current_day


func has_shown_event(npc_id: String, threshold: int) -> bool:
	return (_shown_events.get(npc_id, []) as Array).has(threshold)


## heart_event_30(호감도 30 최초 이벤트) 데이터 - 없는 NPC(폴리 등)는 빈
## Dictionary. main.gd의 _maybe_trigger_heart_event()가 트리거 조건 판정에 쓴다.
func get_heart_event_30(npc_id: String) -> Dictionary:
	return get_definition(npc_id).get("heart_event_30", {})


func has_shown_heart_event(npc_id: String) -> bool:
	return bool(_shown_heart_events.get(npc_id, false))


func mark_heart_event_shown(npc_id: String) -> void:
	_shown_heart_events[npc_id] = true


## 대기 중인 마일스톤이 추억의 물건이고(requires_alive가 있다면 그 조건까지
## 통과) 지금 당장 보여줄 수 있는 상태면 그 threshold를, 아니면 -1을
## 반환한다. main.gd의 호감도 100 컷신(사용자 지시, 2026-08-25 - "NPC가 다가와서
## 시작") 자동 트리거 판정용 - get_daily_dialogue()의 마일스톤 소비 로직과
## 별개로 E 없이 근접만으로 터지는 경로라 여기서 따로 판정해야 한다. 위치/
## 인벤토리 조건은 여기서 안 보고 호출부(main.gd)가 직접 확인한다.
func get_pending_memento_threshold(npc_id: String) -> int:
	var queue: Array = _pending_milestone.get(npc_id, [])
	if queue.is_empty():
		return -1
	var pending: Dictionary = queue[0]
	if not bool(pending.get("is_memento", false)):
		return -1
	if not requires_alive_met(pending.get("requires_alive", "")):
		return -1
	return int(pending.get("threshold", -1))


## get_daily_dialogue()가 대기 중인 마일스톤 대사를 실제로 보여주기로 결정한
## 순간 호출한다 - 그때서야 신호를 내보내고(추억의 물건이면 지급도 그때).
func consume_pending_milestone(npc_id: String) -> void:
	var queue: Array = _pending_milestone.get(npc_id, [])
	if queue.is_empty():
		return
	var pending: Dictionary = queue.pop_front()
	if queue.is_empty():
		_pending_milestone.erase(npc_id)
	else:
		_pending_milestone[npc_id] = queue
	var threshold := int(pending.get("threshold", -1))
	var shown: Array = _shown_events.get(npc_id, [])
	shown.append(threshold)
	_shown_events[npc_id] = shown
	affection_event_triggered.emit(npc_id, threshold)
	if bool(pending.get("is_memento", false)):
		memento_received.emit(npc_id)
		# 하트: 추억의 물건 건넬 때(사용자 지시, 2026-08-25).
		request_emote(npc_id, EMOTE_HEART)
		_memento_pending_since_day.erase(npc_id)
		_memento_reminder_sent.erase(npc_id)
	_recheck_gated_events()


## requires로 다른 NPC의 이벤트를 기다리던 항목들을 다시 검사한다 - 방금 막
## 화면에 뜬 이벤트가 다른 누군가의 선행 조건이었을 수 있으니, 그쪽 호감도가
## 이미 오래 전에 임계값을 넘어서 대기만 하고 있던 경우를 놓치지 않게 한다.
func _recheck_gated_events() -> void:
	for other_id in _definitions:
		_check_affection_events(other_id, get_affection(other_id))


## 호감도 임계값이 아니라 특정 dialogue.daily 대사 줄이 실제로 화면에 나왔을 때
## 아이템을 선물하는 경우(예: 모카의 커피) - dialogue_screen.gd가 lines 배열
## 안의 {"type":"gift","item_id":...} 줄을 만나면 호출한다.
func grant_gift_item(npc_id: String, item_id: String) -> void:
	npc_gift_item_triggered.emit(npc_id, item_id)
	# 웃음: 선물(예: 커피)을 건넬 때.
	request_emote(npc_id, EMOTE_SMILE)


func _on_day_changed(_day: int, _weekday: String) -> void:
	_talked_today.clear()
	_special_dialogue_shown_today.clear()
	_daily_dialogue_cache.clear()
	_active_scent = _pending_scent.duplicate()
	_pending_scent.clear()
	for npc_id in SELF_SCENT_NPC_IDS:
		if _active_scent.has(npc_id) or not is_alive(npc_id):
			continue
		if randf() < SELF_SCENT_CHANCE:
			_active_scent[npc_id] = SELF_SCENT_COLORS[randi() % SELF_SCENT_COLORS.size()]
	_check_memento_reminders()


func _check_memento_reminders() -> void:
	for npc_id in _memento_pending_since_day.keys():
		if bool(_memento_reminder_sent.get(npc_id, false)) or not is_alive(npc_id):
			continue
		var since_day := int(_memento_pending_since_day[npc_id])
		if TimeManager.current_day - since_day < MEMENTO_REMINDER_DELAY_DAYS:
			continue
		var reminder: Dictionary = get_definition(npc_id).get("emails", {}).get("memento_reminder", {})
		var lines: Array = reminder.get("lines", [])
		if lines.is_empty():
			continue
		_memento_reminder_sent[npc_id] = true
		memento_reminder_ready.emit(npc_id, String(reminder.get("title", "")), lines)


func _serialize_position(npc_id: String) -> Dictionary:
	var world_position := get_npc_world_position(npc_id)
	if world_position.is_empty():
		return {}
	var position: Vector2 = world_position.get("position", Vector2.ZERO)
	return {"map_id": world_position.get("map_id", ""), "x": position.x, "y": position.y}


func _build_spawn_index() -> void:
	for map_id in WorldMap.MAP_PATHS:
		var spawns: Dictionary = WorldMap.parse_spawns(String(WorldMap.MAP_PATHS[map_id]))
		for spawn_name in spawns:
			_spawn_index[spawn_name] = {"map_id": map_id, "position": spawns[spawn_name]}


func _load_all_definitions() -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("NPC data directory could not be opened: %s" % DATA_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_definition(DATA_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_definition(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("NPC data file could not be opened: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("NPC data file is not valid JSON: %s" % path)
		return
	var definition: Dictionary = parsed
	var npc_id := String(definition.get("id", ""))
	if npc_id.is_empty():
		push_error("NPC data file is missing an id: %s" % path)
		return
	_definitions[npc_id] = definition
