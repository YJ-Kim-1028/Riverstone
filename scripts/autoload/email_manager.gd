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
## NOTE: the daily send-decision logic below (_generate_daily_emails and the
## category priority/chances) is a placeholder the user plans to redesign -
## only touch it for the {title, lines} schema change, not the actual rules.

signal inbox_updated
signal mail_received(entry: Dictionary)

## email.md gives no frequency rule for filler mail, so these two chances are
## an invented placeholder (day3.md) - tune freely, they only gate how often
## greeting/event_invite categories fire once their JSON pools are filled in.
const GREETING_CHANCE_PER_DAY := 0.2
const EVENT_INVITE_CHANCE_PER_DAY := 0.5

var _inbox: Array = []
var _sent: Array = []
var _invite_history: Array = []
var _next_id := 1
var _player_email_used_today := false
var _gifted_today: Dictionary = {}
var _sent_story_triggers: Dictionary = {}


func _ready() -> void:
	NPCManager.gift_given.connect(_on_gift_given)
	TimeManager.day_changed.connect(_on_day_changed)


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


## 컴퓨터 메일쓰기 화면의 "안부 메일" 모드 전송 버튼이 호출. email.md: "플레이어는
## 하루에 한 번 NPC 한 명에게 이메일을 보낼 수 있다. 이메일을 받은 NPC는 호감도가
## 3 상승한다." - NPCManager.send_email()이 호감도 증가를 처리하고, 여기서는
## 하루 제한과 발신함 기록만 담당한다.
func compose_and_send(npc_id: String, title: String, content: String) -> bool:
	if _player_email_used_today or not NPCManager.is_alive(npc_id) or content.is_empty():
		return false
	NPCManager.send_email(npc_id)
	_player_email_used_today = true
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
		"sent_story_triggers": _sent_story_triggers.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_inbox = (data.get("inbox", []) as Array).duplicate(true)
	_sent = (data.get("sent", []) as Array).duplicate(true)
	_invite_history = (data.get("invite_history", []) as Array).duplicate(true)
	_next_id = int(data.get("next_id", 1))
	_player_email_used_today = bool(data.get("player_email_used_today", false))
	_gifted_today = (data.get("gifted_today", {}) as Dictionary).duplicate()
	_sent_story_triggers = (data.get("sent_story_triggers", {}) as Dictionary).duplicate(true)


func _on_gift_given(npc_id: String) -> void:
	_gifted_today[npc_id] = true


func _on_day_changed(_day: int, _weekday: String) -> void:
	_player_email_used_today = false
	_generate_daily_emails()


func _generate_daily_emails() -> void:
	var gifted_yesterday := _gifted_today.duplicate()
	_gifted_today.clear()
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		_maybe_send_story_progress(npc_id)
		if gifted_yesterday.has(npc_id):
			_maybe_send_category(npc_id, "gift_thanks", 1.0)
		elif RestaurantManager.get_todays_visitor_ids().has(npc_id):
			_maybe_send_category(npc_id, "event_invite", EVENT_INVITE_CHANCE_PER_DAY)
		else:
			_maybe_send_category(npc_id, "greeting", GREETING_CHANCE_PER_DAY)


func _maybe_send_category(npc_id: String, category: String, chance: float) -> void:
	var emails: Dictionary = NPCManager.get_definition(npc_id).get("emails", {})
	var pool: Array = emails.get(category, [])
	if pool.is_empty() or randf() > chance:
		return
	var picked: Dictionary = pool.pick_random()
	_add_mail(npc_id, category, String(picked.get("title", "")), (picked.get("lines", []) as Array).duplicate())


## story_progress (email.md의 공포/스토리 메일) - 트리거 이름으로 조회하는
## 고정 메일이라 랜덤 풀이 아니며, 같은 트리거는 NPC당 한 번만 보낸다.
## 현재 확정된 트리거는 살인 발생 여부뿐 - 그 외 키는 데이터에 채워져도
## 조건을 아는 시스템이 없어서 발송되지 않는다 (TODO: 트리거 늘어나면 여기 추가).
func _maybe_send_story_progress(npc_id: String) -> void:
	var emails: Dictionary = NPCManager.get_definition(npc_id).get("emails", {})
	var triggers: Dictionary = emails.get("story_progress", {})
	var sent: Dictionary = _sent_story_triggers.get(npc_id, {})
	for trigger_name in triggers:
		if sent.has(trigger_name) or not _is_story_trigger_active(String(trigger_name)):
			continue
		var entry: Dictionary = triggers[trigger_name]
		_add_mail(npc_id, "story_progress", String(entry.get("title", "")), (entry.get("lines", []) as Array).duplicate())
		sent[trigger_name] = true
	_sent_story_triggers[npc_id] = sent


func _is_story_trigger_active(trigger_name: String) -> bool:
	match trigger_name:
		"first_murder_occurred":
			return MurderManager.get_murder_count() >= 1
		"second_murder_occurred":
			return MurderManager.get_murder_count() >= 2
		_:
			return false


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
