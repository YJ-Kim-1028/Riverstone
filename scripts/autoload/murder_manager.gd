extends Node

## Owns the stalker murder queue/conditions (murder_system.md), the player's
## one-time poison murder ("플레이어 살인"), and all three endings ending.md
## ties to them (진실/체포/공범). Doesn't touch presentation (portraits, UI,
## actual email delivery) - other systems watch its signals for that.

signal murder_occurred(victim_id: String, murder_number: int)
signal player_murder_committed(victim_id: String)
signal truth_ending_triggered
signal arrest_ending_triggered(spared_npc_id: String)
signal accomplice_ending_triggered(victim_id: String)

const MURDER_HOUR := 22
const MAX_STALKER_MURDERS := 2

## ending.md 체포 엔딩: 2명을 죽인 뒤 "세 번째 살해 대상이 확정된" 상태여야
## 하므로, 대기열에는 최대 3명(실제 희생자 2 + 체포 엔딩용 3번째)까지만 받는다.
const MAX_CANDIDATES := 3

## murder_system.md의 "피해자의 집" - NPC별 개인 주거 맵이 실제로는 존재하지
## 않아서(04_locations에 상점/공용 공간만 있음), 발견 장소는 이 문자열로만
## 남긴다. 실제 "피해자 집으로 이동 처리"는 시각적으로 할 맵이 없어 생략했다.
const DISCOVERY_LOCATION := "피해자의 집"

const LOCATION_NAMES := {
	"hospital": "병원", "pasture": "목장", "farm": "농가게", "cafe": "카페",
	"shrine": "신사", "temple": "절", "book": "서점", "general": "잡화점",
	"furniture": "가구점", "fish": "낚시가게", "police": "경찰서",
	"plaza1": "광장", "plaza2": "광장", "plaza3": "광장", "plaza4": "광장", "plaza5": "광장",
	"restaurant": "레스토랑", "home": "집",
}

var _candidate_queue: Array[String] = []
var _resolved_candidates: Dictionary = {}
var _cases: Array = []
var _murder_count := 0

## ending.md: "엔딩은 중복 달성이 불가능하다" - "" | "truth" | "arrest" | "accomplice".
var _ending_achieved := ""

var _player_used_poison := false
var _player_killed_npc_id := ""
var _arrested := false
var _accomplice_ending := false
var _stalker_killed := false
var _living_with_stalker := false
var _usher_death_method := ""


func _ready() -> void:
	NPCManager.murder_candidate_registered.connect(_on_candidate_registered)
	RestaurantManager.npc_poisoned.connect(_on_npc_poisoned)
	TimeManager.minute_passed.connect(_on_minute_passed)
	_update_pending_state()


func get_murder_count() -> int:
	return _murder_count


func get_achieved_ending() -> String:
	return _ending_achieved


func has_ending_achieved() -> bool:
	return not _ending_achieved.is_empty()


func is_stalker_killed() -> bool:
	return _stalker_killed


## save.md "경찰 체포 여부" - 체포 엔딩(스토커 체포/자결)과 공범 엔딩의 "플레이어
## 일시 체포" 둘 다 여기 해당하므로, 둘 중 하나라도 일어나면 true.
func is_arrested() -> bool:
	return _arrested


func is_accomplice_ending() -> bool:
	return _accomplice_ending


func is_living_with_stalker() -> bool:
	return _living_with_stalker


func has_player_used_poison() -> bool:
	return _player_used_poison


func get_player_killed_npc_id() -> String:
	return _player_killed_npc_id


func get_usher_death_method() -> String:
	return _usher_death_method


## murder_system.md: "조건 미충족 시 다음 날 동일 조건 재검사" - 대상이 있는 한
## WeatherManager가 3일 이내 비를 강제하도록 계속 신호를 보낸다.
func has_pending_victim() -> bool:
	return _get_next_queued_candidate() != ""


func get_case_count() -> int:
	return _cases.size()


func get_case_info(case_number: int) -> Dictionary:
	if case_number < 1 or case_number > _cases.size():
		return {}
	var case_data: Dictionary = _cases[case_number - 1]
	return {
		"victim_id": case_data.get("victim_id", ""),
		"day": case_data.get("day", -1),
		"weekday": case_data.get("weekday", ""),
		"discovery_location": DISCOVERY_LOCATION,
	}


## murder_system.md "경찰 조사": NPC 알리바이는 스케줄 데이터를 기반으로 자동
## 생성된다. 살인 당시 각 생존 NPC의 스케줄 상태를 그대로 저장해뒀다가,
## 장소 접두사만 한글 지명으로 바꿔서 문장으로 돌려준다.
func describe_alibi(npc_id: String, case_number: int) -> String:
	if case_number < 1 or case_number > _cases.size():
		return ""
	var alibis: Dictionary = _cases[case_number - 1].get("alibis", {})
	if not alibis.has(npc_id):
		return "그날 밤 어디에 있었는지 알려진 바가 없다."
	return "오후 10시에는 %s에 있었다고 말한다." % _describe_location(String(alibis[npc_id]))


func get_save_data() -> Dictionary:
	return {
		"candidate_queue": _candidate_queue,
		"resolved_candidates": _resolved_candidates.duplicate(),
		"ending_achieved": _ending_achieved,
		"murder_count": _murder_count,
		"cases": _cases.duplicate(true),
		"player_used_poison": _player_used_poison,
		"player_killed_npc_id": _player_killed_npc_id,
		"arrested": _arrested,
		"accomplice_ending": _accomplice_ending,
		"stalker_killed": _stalker_killed,
		"living_with_stalker": _living_with_stalker,
		"usher_death_method": _usher_death_method,
	}


func load_save_data(data: Dictionary) -> void:
	_candidate_queue.clear()
	for npc_id in (data.get("candidate_queue", []) as Array):
		_candidate_queue.append(String(npc_id))
	_resolved_candidates = (data.get("resolved_candidates", {}) as Dictionary).duplicate()
	_ending_achieved = String(data.get("ending_achieved", ""))
	_murder_count = int(data.get("murder_count", 0))
	_cases = (data.get("cases", []) as Array).duplicate(true)
	_player_used_poison = bool(data.get("player_used_poison", false))
	_player_killed_npc_id = String(data.get("player_killed_npc_id", ""))
	_arrested = bool(data.get("arrested", false))
	_accomplice_ending = bool(data.get("accomplice_ending", false))
	_stalker_killed = bool(data.get("stalker_killed", false))
	_living_with_stalker = bool(data.get("living_with_stalker", false))
	_usher_death_method = String(data.get("usher_death_method", ""))
	_update_pending_state()


func _on_candidate_registered(npc_id: String) -> void:
	if _candidate_queue.size() >= MAX_CANDIDATES:
		return
	_candidate_queue.append(npc_id)
	_update_pending_state()


## murder_system.md "플레이어 살인": 독약으로 단 한 번만 살해 가능. 대상이
## 스토커 본인이면 ending.md의 진실 엔딩, 무고한 NPC면 공범 엔딩으로 갈린다.
func _on_npc_poisoned(npc_id: String) -> void:
	if _player_used_poison or has_ending_achieved():
		return
	_player_used_poison = true
	_player_killed_npc_id = npc_id
	_resolved_candidates[npc_id] = true
	_record_case(npc_id)
	NPCManager.kill_npc(npc_id)
	if npc_id == NPCManager.get_stalker_id():
		_stalker_killed = true
		_usher_death_method = "player_killed"
		_ending_achieved = "truth"
		truth_ending_triggered.emit()
	else:
		_arrested = true
		_accomplice_ending = true
		_living_with_stalker = true
		_ending_achieved = "accomplice"
		accomplice_ending_triggered.emit(npc_id)
	player_murder_committed.emit(npc_id)


func _on_minute_passed(hour: int, minute: int) -> void:
	if hour != MURDER_HOUR or minute != 0 or has_ending_achieved() or _stalker_killed:
		return
	var candidate_id := _get_next_queued_candidate()
	if candidate_id.is_empty() or not WeatherManager.is_raining():
		return
	if not _positions_allow_murder(candidate_id):
		return
	if _murder_count >= MAX_STALKER_MURDERS:
		_trigger_arrest_ending(candidate_id)
	else:
		_commit_murder(candidate_id)


func _get_next_queued_candidate() -> String:
	if _stalker_killed:
		return ""
	for candidate_id in _candidate_queue:
		if not bool(_resolved_candidates.get(candidate_id, false)):
			return candidate_id
	return ""


## murder_system.md 예시: 플레이어/스토커/피해자 중 어느 둘도 같은 맵에 있으면
## 안 된다 (세 명이 서로 다른 맵에 있어야 함).
func _positions_allow_murder(victim_id: String) -> bool:
	var stalker_id := NPCManager.get_stalker_id()
	var stalker_position := NPCManager.get_npc_world_position(stalker_id)
	var victim_position := NPCManager.get_npc_world_position(victim_id)
	if stalker_position.is_empty() or victim_position.is_empty():
		return false
	var player_map := GameManager.current_map_id
	var stalker_map := String(stalker_position.get("map_id", ""))
	var victim_map := String(victim_position.get("map_id", ""))
	return player_map != stalker_map and player_map != victim_map and stalker_map != victim_map


func _commit_murder(victim_id: String) -> void:
	_resolved_candidates[victim_id] = true
	_record_case(victim_id)
	NPCManager.kill_npc(victim_id)
	_murder_count += 1
	_update_pending_state()
	murder_occurred.emit(victim_id, _murder_count)


## ending.md 체포 엔딩: "실제 살인은 발생하지 않는다. 살인 조건 충족 시점에
## 경찰 체포 이벤트가 대신 발동된다. 세 번째 살해 대상 NPC는 생존한다." +
## "어셔의 사망으로 인해 이메일이 중단된다" (poli.json: 범인이 그 자리에서
## 스스로 목숨을 끊는다) - 그래서 대상은 살고, 스토커가 대신 죽는다.
func _trigger_arrest_ending(spared_npc_id: String) -> void:
	_resolved_candidates[spared_npc_id] = true
	_arrested = true
	_stalker_killed = true
	_usher_death_method = "self_killed"
	_ending_achieved = "arrest"
	NPCManager.kill_npc(NPCManager.get_stalker_id())
	_update_pending_state()
	arrest_ending_triggered.emit(spared_npc_id)


func _record_case(victim_id: String) -> void:
	_cases.append({
		"victim_id": victim_id,
		"day": TimeManager.current_day,
		"weekday": TimeManager.get_weekday(),
		"alibis": _snapshot_alibis(victim_id),
	})


func _snapshot_alibis(victim_id: String) -> Dictionary:
	var alibis: Dictionary = {}
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		alibis[npc_id] = NPCManager.get_current_schedule_state(npc_id)
	return alibis


func _describe_location(state: String) -> String:
	for prefix in LOCATION_NAMES:
		if state.begins_with(prefix):
			return String(LOCATION_NAMES[prefix])
	return "알 수 없는 장소"


func _update_pending_state() -> void:
	WeatherManager.set_murder_pending(has_pending_victim())
