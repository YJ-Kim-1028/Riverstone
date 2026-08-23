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
## redesigned 2026-08-15 per user spec - gift_thanks/event_invite stay
## affection-independent reactions to real player actions, greeting requires
## GREETING_AFFECTION_THRESHOLD+ affection and a GREETING_COOLDOWN_DAYS
## rotation capped at MAX_GREETING_EMAILS_PER_DAY/day. EVENT_INVITE_CHANCE_PER_DAY
## is still an untuned placeholder (email.md has no frequency spec) - fine to
## adjust that one number freely, but check with the user before changing the
## rules/priority structure itself again.

signal inbox_updated
signal mail_received(entry: Dictionary)

## email.md gives no frequency rule for filler mail, so this chance is still
## an invented placeholder (day3.md) - now only gates event_invite (gift_thanks/
## greeting are conditional-certain sends, see the constants below).
const EVENT_INVITE_CHANCE_PER_DAY := 0.5

## 2026-08-15 재설계(사용자 확정): 안부(greeting) 메일은 호감도 80 이상인 NPC만
## 후보가 되고, 같은 NPC가 다시 안부 메일을 보내려면 최소 7일 쿨다운을 거쳐야
## 하며, 하루에 최대 2명까지만 실제로 발송된다 - 13명이 매일 각자 확률을 굴리면
## 하루에 몰려서 오거나 매일 오는 느낌이라, 대신 "일주일에 나눠서, 하루 1~2통,
## 안 오는 날도 있음"이 되도록 로테이션 방식으로 바꿈. gift_thanks/event_invite는
## 플레이어의 실제 행동(선물/초대)에 대한 반응이라 호감도/쿨다운 없이 그대로 유지.
const GREETING_AFFECTION_THRESHOLD := 80
const GREETING_COOLDOWN_DAYS := 7
const MAX_GREETING_EMAILS_PER_DAY := 2

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
## npc_id -> TimeManager.current_day (안부 메일을 마지막으로 보낸 날) - GREETING_COOLDOWN_DAYS
## 쿨다운 판정에 쓴다. gift_thanks/event_invite는 여기 안 남는다(호감도/쿨다운 대상이 아님).
var _last_greeting_day: Dictionary = {}
## npc_id -> 플레이어가 compose_and_send()로 마지막으로 보낸 자유 작성 메일의
## 본문. NPCManager.get_daily_dialogue()가 이 NPC와 대화할 때 dialogue.mail_reaction
## 풀에서 하나를 뽑아 "{player_mail_content}"를 이 값으로 채워 넣을 후보로 쓴다 -
## 그 대사가 실제로 뽑히면 clear_pending_mail_reaction()으로 지워져서 한 번만
## 언급된다. 같은 NPC에게 또 메일을 보내면 이전 것 대신 최신 내용으로 덮어써짐.
var _pending_mail_reaction: Dictionary = {}


func _ready() -> void:
	NPCManager.gift_given.connect(_on_gift_given)
	RestaurantManager.dish_served.connect(_on_dish_served)
	TimeManager.day_changed.connect(_on_day_changed)
	HorrorEventManager.impersonation_email_ready.connect(_on_impersonation_email_ready)
	HorrorEventManager.stalker_email_ready.connect(_on_stalker_email_ready)


## 메일함 UI는 게임 내 "N일차"가 아니라 플레이어가 실제로 메일을 주고받은
## 현실의 날짜를 보여주고 싶다는 사용자 요청 - 시스템 시계에서 가져온다.
## 현실 날짜 뒤에 게임 내 진행 일차(TimeManager.current_day)를 같이 표시한다 -
## 하루에 여러 일차를 플레이할 수 있어서 현실 날짜만으로는 메일/초대 내역을
## 구분할 수 없다는 사용자 피드백으로 추가(day4 TODO).
func get_current_real_date_string() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%d년 %d월 %d일 %d일차" % [d.year, d.month, d.day, TimeManager.current_day]


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
func mark_invite_outcome(npc_id: String, visited: bool) -> void:
	for i in range(_invite_history.size() - 1, -1, -1):
		var entry: Dictionary = _invite_history[i]
		if String(entry.get("npc_id", "")) == npc_id and String(entry.get("outcome", "")) == "pending":
			entry["outcome"] = "visited" if visited else "missed"
			return


func get_invite_history() -> Array:
	return _invite_history.duplicate(true)


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
		"last_greeting_day": _last_greeting_day.duplicate(),
		"pending_mail_reaction": _pending_mail_reaction.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	_inbox = (data.get("inbox", []) as Array).duplicate(true)
	_sent = (data.get("sent", []) as Array).duplicate(true)
	_invite_history = (data.get("invite_history", []) as Array).duplicate(true)
	_next_id = int(data.get("next_id", 1))
	_player_email_used_today = bool(data.get("player_email_used_today", false))
	_gifted_today = (data.get("gifted_today", {}) as Dictionary).duplicate()
	_favorite_food_served_today = (data.get("favorite_food_served_today", {}) as Dictionary).duplicate()
	_sent_story_triggers = (data.get("sent_story_triggers", {}) as Dictionary).duplicate(true)
	_last_greeting_day = (data.get("last_greeting_day", {}) as Dictionary).duplicate()
	_pending_mail_reaction = (data.get("pending_mail_reaction", {}) as Dictionary).duplicate()


func _on_gift_given(npc_id: String) -> void:
	_gifted_today[npc_id] = true


func _on_dish_served(_station_index: int, npc_id: String, dish: Dictionary) -> void:
	if int(dish.get("preference", NPCManager.FoodPreference.NEUTRAL)) == NPCManager.FoodPreference.FAVORITE:
		_favorite_food_served_today[npc_id] = true


func _on_day_changed(_day: int, _weekday: String) -> void:
	_player_email_used_today = false
	_generate_daily_emails()


func _generate_daily_emails() -> void:
	var gifted_yesterday := _gifted_today.duplicate()
	_gifted_today.clear()
	var favorite_food_served_yesterday := _favorite_food_served_today.duplicate()
	_favorite_food_served_today.clear()
	## 오늘 이미 gift_thanks/event_invite를 보낸 NPC는 안부 후보에서 제외(하루 1통
	## 원칙) - 그 외 호감도 80+ & 쿨다운 지난 NPC만 후보로 모았다가 섞어서 최대
	## MAX_GREETING_EMAILS_PER_DAY명만 실제로 보낸다.
	var greeting_candidates: Array = []
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		_maybe_send_story_progress(npc_id)
		if gifted_yesterday.has(npc_id):
			_maybe_send_category(npc_id, "gift_thanks", 1.0)
		elif npc_id == RestaurantManager.get_todays_invited_npc_id():
			_maybe_send_category(npc_id, "event_invite", EVENT_INVITE_CHANCE_PER_DAY, favorite_food_served_yesterday.has(npc_id))
		elif NPCManager.get_affection(npc_id) >= GREETING_AFFECTION_THRESHOLD and _is_greeting_off_cooldown(npc_id):
			greeting_candidates.append(npc_id)
	greeting_candidates.shuffle()
	for npc_id in greeting_candidates.slice(0, MAX_GREETING_EMAILS_PER_DAY):
		if _maybe_send_category(npc_id, "greeting", 1.0):
			_last_greeting_day[npc_id] = TimeManager.current_day


func _is_greeting_off_cooldown(npc_id: String) -> bool:
	if not _last_greeting_day.has(npc_id):
		return true
	return TimeManager.current_day - int(_last_greeting_day[npc_id]) >= GREETING_COOLDOWN_DAYS


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
func _on_stalker_email_ready(sender_id: String, title: String, lines: Array) -> void:
	_add_mail(sender_id, "stalker", title, lines)


func _add_mail(npc_id: String, category: String, title: String, lines: Array) -> void:
	var entry := {
		"id": _next_id,
		"npc_id": npc_id,
		"category": category,
		"title": title,
		"date": get_current_real_date_string(),
		"read": false,
		"lines": lines,
	}
	_next_id += 1
	_inbox.append(entry)
	mail_received.emit(entry)
	inbox_updated.emit()
