extends Node

## Ambient/flavor horror beats from horror_events.md, plus the staged
## stalker emails from email.md/stalker.md. Doesn't own murder logic
## (MurderManager does) - just decides "should this flavor event happen
## right now" and hands back line pools for a future dialogue/email UI.

signal knock_event_triggered
signal impersonation_email_ready(npc_id: String, lines: Array)

const KNOCK_PROBABILITY := 0.3
const KNOCK_MAP_ID := "home_interior"
const SAGE_WARNING_LINES: Array = ["오늘은 밖에 나가지 않는 게 좋을 것 같아."]

const STALKER_EMAILS_PATH := "res://data/horror/stalker_emails.json"
const IMPERSONATION_EMAILS_PATH := "res://data/horror/impersonation_emails.json"

var _stalker_emails: Dictionary = {}
var _impersonation_emails: Dictionary = {}
var _impersonation_sent: Dictionary = {}


func _ready() -> void:
	_stalker_emails = _load_json(STALKER_EMAILS_PATH)
	_impersonation_emails = _load_json(IMPERSONATION_EMAILS_PATH)
	TimeManager.night_events_enabled.connect(_on_night_events_enabled)
	TimeManager.day_changed.connect(_on_day_changed)


## horror_events.md "세이지": 살인 조건을 충족하는 날 대화를 나누면 경고 대사가
## 나온다. "충족하는 날"을 비가 오고 있고 아직 처리되지 않은 대기 대상이 있는
## 날로 해석했다 (스토커의 위치 조건까지는 세이지가 알 도리가 없으므로 제외).
func get_sage_warning_lines() -> Array:
	if MurderManager.is_stalker_killed():
		return []
	if WeatherManager.is_raining() and MurderManager.has_pending_victim():
		return SAGE_WARNING_LINES.duplicate()
	return []


## stalker.md는 이메일이 "초반/중반/후반"으로 톤이 바뀐다고만 하고 정확한 전환
## 조건은 안 정해뒀다. 스토커가 실제로 저지른 살인 수(공포가 실제로 진행된
## 정도)를 기준으로 삼은 건 이 구현의 해석이며, 다른 기준이 낫다면 바꾸면 된다.
func get_stalker_email_stage() -> String:
	var count := MurderManager.get_murder_count()
	if count >= 2:
		return "late"
	if count >= 1:
		return "mid"
	return "early"


## stalker.md 진실 엔딩: 어셔가 죽으면 이메일이 완전히 중단된다.
func get_stalker_email_pool() -> Array:
	if MurderManager.is_stalker_killed():
		return []
	return (_stalker_emails.get(get_stalker_email_stage(), []) as Array).duplicate()


func get_impersonation_lines(npc_id: String) -> Array:
	return (_impersonation_emails.get(npc_id, []) as Array).duplicate()


func get_save_data() -> Dictionary:
	return {"impersonation_sent": _impersonation_sent.duplicate()}


func load_save_data(data: Dictionary) -> void:
	_impersonation_sent = (data.get("impersonation_sent", {}) as Dictionary).duplicate()


## horror_events.md "집 이벤트": 첫 번째 살인 이후부터, 매일 밤 30% 확률로,
## 플레이어가 집(home_interior) 안에 있을 때만 노크 소리가 발동한다.
func _on_night_events_enabled() -> void:
	if MurderManager.get_murder_count() <= 0:
		return
	if GameManager.current_map_id != KNOCK_MAP_ID:
		return
	if randf() <= KNOCK_PROBABILITY:
		knock_event_triggered.emit()


## email.md "NPC 사망 이후": NPC가 죽으면 다음 날 그 NPC 명의로 메일이 온다.
func _on_day_changed(_day: int, _weekday: String) -> void:
	for npc_id in NPCManager.get_dead_npc_ids():
		if bool(_impersonation_sent.get(npc_id, false)):
			continue
		if TimeManager.current_day != NPCManager.get_death_day(npc_id) + 1:
			continue
		_impersonation_sent[npc_id] = true
		impersonation_email_ready.emit(npc_id, get_impersonation_lines(npc_id))


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Horror data file could not be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Horror data file is not valid JSON: %s" % path)
		return {}
	return parsed
