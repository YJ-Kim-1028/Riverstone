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
## 알리바이 조사 기준 시각(사용자 지시, 2026-08-17) - 22시(살인 시각)는 다들
## 이미 자기 자리로 돌아가 있어 서로 겹칠 일이 거의 없다. "시신이 물속에
## 있어 부패가 빨리 진행됐지만 실제 사망 추정 시각은 4시간 정도 전"이라는
## 설정으로, 더 이른 시각(18시)을 알리바이 조사 기준으로 삼는다 - 이 시간대가
## NPC들이 아직 밖에 나와 있어 알리바이/목격 진술 둘 다 훨씬 유의미해진다.
const ALIBI_CHECK_HOUR := 18
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

## 목격 진술용(사용자 지시, 2026-08-17) - LOCATION_NAMES는 state 문자열 접두어
## 기준이라 목격 증언에서 쓰는 실제 map_id(NPCManager._spawn_index 기준, 예:
## "general_interior")와 키 형태가 다르다. WorldMap.MAP_PATHS의 맵 id 그대로
## 키를 맞췄다.
const MAP_ID_NAMES := {
	"Home": "집", "home_interior": "집",
	"plaza1": "광장", "plaza2": "광장", "plaza3": "광장", "plaza4": "광장", "plaza5": "광장",
	"basement_interior": "지하실", "book_interior": "서점", "cafe_interior": "카페",
	"cowshed_interior": "축사", "farm_interior": "농가게", "fish_interior": "낚시가게",
	"furniture_interior": "가구점", "general_interior": "잡화점",
	"hospital_interior": "병원", "pasture_interior": "목장", "police_interior": "경찰서",
	"restaurant_interior": "레스토랑", "shrine_interior": "신사", "temple_interior": "절",
}

var _candidate_queue: Array[String] = []
var _resolved_candidates: Dictionary = {}
var _cases: Array = []
var _murder_count := 0

## 2026-08-16 사용자 확정: 살인 발생 후 5일 이내에 처음 만나는 생존 NPC는
## 대화 첫 줄로 그날 밤 알리바이를 무조건 진술한다(한 번 말하면 다시 안 함).
## npc_id -> true인 동안 "아직 안 물어봤음". 새 살인이 또 나면 그 전 살인
## 몫으로 아직 안 받은 진술은 버리고 최신 사건 기준으로 다시 채운다(둘 다
## 들고 있게 하지 않음 - 최대 2번 살인이라 실무상 드문 경우).
const ALIBI_WINDOW_DAYS := 5
var _alibi_pending: Dictionary = {}
var _alibi_deadline_day := -1

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
## 생성된다. 살인 시각(22시)이 아니라 ALIBI_CHECK_HOUR(18시) 기준 각 생존
## NPC의 스케줄 상태를 저장해뒀다가, 장소 접두어만 한글 지명으로 바꿔서
## 문장으로 돌려준다.
func describe_alibi(npc_id: String, case_number: int) -> String:
	if case_number < 1 or case_number > _cases.size():
		return ""
	var alibis: Dictionary = _cases[case_number - 1].get("alibis", {})
	if not alibis.has(npc_id):
		return "그날 밤 어디에 있었는지 알려진 바가 없다."
	return "오후 6시에는 %s에 있었다고 말한다." % _describe_location(String(alibis[npc_id]))


## murder_system.md 경찰 조사 - 살인 후 ALIBI_WINDOW_DAYS 이내 이 NPC와 처음
## 나누는 대화의 첫 줄로 쓸 1인칭 알리바이 진술. describe_alibi()의 3인칭
## 나레이션("~라고 말한다")과 달리 NPC 본인이 직접 하는 말투로 새로 포맷한다.
## 한 번 불러가면(대화가 실제로 열렸다는 뜻) 다시는 안 나온다 - 기간이 지나도
## 마찬가지로 지워서 나중에 뜬금없이 나오지 않게 한다.
func consume_alibi_line(npc_id: String) -> String:
	if not _alibi_pending.get(npc_id, false):
		return ""
	_alibi_pending.erase(npc_id)
	if TimeManager.current_day > _alibi_deadline_day or _cases.is_empty():
		return ""
	if npc_id == NPCManager.get_stalker_id():
		var lie := _stalker_alibi_lie()
		if not lie.is_empty():
			return "그날 오후 6시엔 %s에 있었어." % lie
	var alibis: Dictionary = _cases[_cases.size() - 1].get("alibis", {})
	if not alibis.has(npc_id):
		return "그날 밤 어디 있었는지는... 나도 잘 기억이 안 나."
	return "그날 오후 6시엔 %s에 있었어." % _describe_location(String(alibis[npc_id]))


## 스토커(어셔)의 거짓 알리바이(사용자 지시, 2026-08-17) - 실제 스케줄과 무관하게
## usher.json의 murder_alibi_lie.location_label을 그대로 주장하게 한다.
## consume_witness_line()은 이 거짓말과 별개로 다른 NPC들의 진짜 스케줄
## 데이터를 그대로 쓰므로, 그날 실제로 어셔와 마주친 NPC가 있으면 그 NPC의
## 목격 진술이 자동으로 이 거짓말과 모순된다 - 대조 로직을 따로 만들 필요
## 없이 "잡히는" 구조. 기획자가 아직 안 채웠으면(TODO로 시작) 빈 문자열을
## 돌려줘서 평소처럼 실제 스케줄 기반 알리바이로 폴백한다.
func _stalker_alibi_lie() -> String:
	var stalker_id := NPCManager.get_stalker_id()
	if stalker_id.is_empty():
		return ""
	var label := String(NPCManager.get_definition(stalker_id).get("murder_alibi_lie", {}).get("location_label", ""))
	if label.begins_with("TODO"):
		return ""
	return label


## _stalker_alibi_lie()가 실제로 쓰였을 때(거짓 알리바이가 나온 바로 그 순간)
## 이어지는 두 번째 거짓말 - usher.json의 murder_alibi_lie.corroboration_line.
## 실존하지 않는 뒷받침 근거(예: "세이지가 나한테 그랬어")를 대서 거짓말에
## 무게를 싣는 용도. 세이지 쪽엔 대응하는 대사를 절대 넣지 않는다 - 플레이어가
## 나중에 세이지와 대화하며 그런 말을 한 적이 없다는 걸 스스로 알아채는 게
## 핵심이라, 코드로 대조하지 않는다. npc_id가 스토커가 아니면 항상 "".
func consume_stalker_corroboration_line(npc_id: String) -> String:
	if npc_id != NPCManager.get_stalker_id():
		return ""
	var line := String(NPCManager.get_definition(npc_id).get("murder_alibi_lie", {}).get("corroboration_line", ""))
	if line.begins_with("TODO"):
		return ""
	return line


## consume_alibi_line()과 같은 첫 재회 순간에 이어서 나오는 목격 진술(사용자
## 지시, 2026-08-17) - "그날 오후 10시" 알리바이와 달리 하루 전체 기준. 후보가
## 0명이면 아무도 못 봤다고 하고, 1명 이상이면 그중 무작위로 한 명만 골라
## 이름을 댄다(2명 이상이어도 "여러 명 중 하나"로 굳이 얼버무리지 않음 -
## 사용자 지시, 2026-08-17). consume() 시점(대화가 실제로 열렸을 때) 한 번만
## 뽑고 다시 안 나오므로 재대화마다 바뀌지 않는다. _alibi_pending으로 따로
## 게이팅하지 않는다 - 호출부가 consume_alibi_line()이 빈 문자열이 아닐 때만
## 이어서 부르는 걸 전제로 한다.
func consume_witness_line(npc_id: String) -> String:
	if _cases.is_empty():
		return ""
	var witnesses: Dictionary = _cases[_cases.size() - 1].get("witnesses", {})
	if not witnesses.has(npc_id):
		return ""
	var candidates: Array = witnesses[npc_id]
	if candidates.is_empty():
		return "아, 근데 그날은 딱히 아무도 못 봤던 것 같아."
	var picked: Dictionary = candidates.pick_random()
	var seen_name := String(NPCManager.get_definition(String(picked.get("npc_id", ""))).get("name", ""))
	var seen_place := _describe_map(String(picked.get("map_id", "")))
	return "아, 그러고 보니 그날 %s에서 %s를 본 것 같기도 해." % [seen_place, seen_name]


## consume_witness_line()용 - LOCATION_NAMES(state 접두어 기준)와 달리
## map_id를 그대로 키로 쓴다.
func _describe_map(map_id: String) -> String:
	return String(MAP_ID_NAMES.get(map_id, "어딘가"))


## 새 살인이 날 때마다 대기열을 새로 채운다 - 이전 사건 몫으로 아직 못 받은
## 진술이 있어도 최신 사건 기준으로 덮어쓴다(둘 다 들고 있게 하지 않음).
func _refresh_alibi_pending(victim_id: String) -> void:
	_alibi_pending.clear()
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		_alibi_pending[npc_id] = true
	_alibi_deadline_day = TimeManager.current_day + ALIBI_WINDOW_DAYS


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
		"alibi_pending": _alibi_pending.duplicate(),
		"alibi_deadline_day": _alibi_deadline_day,
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
	_alibi_pending = (data.get("alibi_pending", {}) as Dictionary).duplicate()
	_alibi_deadline_day = int(data.get("alibi_deadline_day", -1))
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
	_refresh_alibi_pending(victim_id)
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
		"witnesses": _snapshot_witnesses(victim_id),
	})


func _snapshot_alibis(victim_id: String) -> Dictionary:
	var alibis: Dictionary = {}
	var weekday := TimeManager.get_weekday()
	var is_raining := WeatherManager.is_raining()
	var check_time := "%02d:00" % ALIBI_CHECK_HOUR
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		alibis[npc_id] = NPCManager.get_schedule_state_at(npc_id, weekday, check_time, is_raining)
	return alibis


## 목격 증언(사용자 지시, 2026-08-17) - "그날 오후 6시" 한 시점이 아니라 그날
## 하루 전체를 기준으로, 각 생존 NPC가 스케줄상 마주쳤을 만한 다른 NPC를 사건
## 당시 시점에 미리 계산해서 고정해둔다(알리바이와 같은 이유로 나중에 다시
## 계산하지 않음 - NPCManager.get_witness_candidates() 참고).
func _snapshot_witnesses(victim_id: String) -> Dictionary:
	var witnesses: Dictionary = {}
	var weekday := TimeManager.get_weekday()
	var is_raining := WeatherManager.is_raining()
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		witnesses[npc_id] = NPCManager.get_witness_candidates(npc_id, weekday, is_raining)
	return witnesses


func _describe_location(state: String) -> String:
	for prefix in LOCATION_NAMES:
		if state.begins_with(prefix):
			return String(LOCATION_NAMES[prefix])
	return "알 수 없는 장소"


func _update_pending_state() -> void:
	WeatherManager.set_murder_pending(has_pending_victim())
