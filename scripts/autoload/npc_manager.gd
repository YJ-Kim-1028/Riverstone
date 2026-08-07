extends Node

## Owns JSON-backed NPC definitions and runtime state (affection, life status).
## Dialogue/email line selection, world placement, and murder execution belong
## to other systems; this manager only exposes the data and the affection/
## death state machine described in npc.md.

signal affection_changed(npc_id: String, affection: int)
signal affection_event_triggered(npc_id: String, threshold: int)
signal memento_received(npc_id: String)
signal npc_died(npc_id: String)
signal murder_candidate_registered(npc_id: String)
signal gift_given(npc_id: String)
## NPC 머리 위 이모지 반응(백로그 스펙 확정, 이번에 구현) - npc_world_manager.gd가
## 듣고 있다가 그 NPC가 지금 화면에 보이면 NPCSprite.show_emote()를 호출한다.
## 화면에 없으면 조용히 무시된다(큐잉 안 함 - 안 보이는 반응은 의미 없음).
signal npc_emote_requested(npc_id: String, emote_id: String)

enum FoodPreference { NEUTRAL, FAVORITE, DISLIKED }

const DATA_DIR := "res://data/npc/"

const MIN_AFFECTION := 0
const MAX_AFFECTION := 150
const MEMENTO_AFFECTION := 100
const MURDER_CANDIDATE_AFFECTION := 120

const AFFECTION_TIER_MID := 50
const AFFECTION_TIER_HIGH := 100

const AFFECTION_GAIN_TALK := 1
const AFFECTION_GAIN_GIFT := 3
const AFFECTION_GAIN_MEAL := 1
const AFFECTION_GAIN_FAVORITE_MEAL := 5
const AFFECTION_LOSS_DISLIKED_MEAL := -5
const AFFECTION_GAIN_EMAIL := 3

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
var _murder_candidate_flagged: Dictionary = {}
var _dead_npc_ids: Array[String] = []
var _death_days: Dictionary = {}
var _last_daily_dialogue_index: Dictionary = {}
var _talked_today: Dictionary = {}
var _spawn_index: Dictionary = {}
var _pending_scent: Dictionary = {}
var _active_scent: Dictionary = {}
## npc_id -> {"map_id": String, "position": Vector2} - 실제로 걸어서 정확히
## 그 좌표에 도착해 확정된(걷는 중이 아닌) 위치. get_npc_world_position()은
## 스케줄이 가리키는 위치를 즉시 반환하지만, 다구간 이동은 물론 같은 맵 안
## 이동조차도 NPC가 실제로 그 좌표까지 걸어서 도착하기까지는 시간이 걸린다 -
## 계산대처럼 "스케줄상 여기 있어야 한다"가 아니라 "실제로 지금 정확히 그
## 자리에 있는지"를 확인해야 하는 상호작용은 이 값을 써야 한다.
## NPCWorldManager가 도착/출발 시점마다 갱신한다
## (set_npc_physical_spot/clear_npc_physical_spot).
var _npc_physical_spot: Dictionary = {}


func _ready() -> void:
	_load_all_definitions()
	_build_spawn_index()
	for npc_id in _definitions:
		_affection[npc_id] = 0
		_alive[npc_id] = true
		_completed_events[npc_id] = []
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
func request_emote(npc_id: String, emote_id: String) -> void:
	if not EMOTE_COLUMN_INDEX.has(emote_id):
		return
	npc_emote_requested.emit(npc_id, emote_id)


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


func get_food_preference(npc_id: String, food_name: String) -> FoodPreference:
	var definition := get_definition(npc_id)
	if (definition.get("preferred_food", []) as Array).has(food_name):
		return FoodPreference.FAVORITE
	if (definition.get("disliked_food", []) as Array).has(food_name):
		return FoodPreference.DISLIKED
	return FoodPreference.NEUTRAL


func feed(npc_id: String, food_name: String) -> void:
	feed_with_preference(npc_id, get_food_preference(npc_id, food_name))


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
		_:
			_add_affection(npc_id, AFFECTION_GAIN_MEAL)


func send_email(npc_id: String) -> void:
	_add_affection(npc_id, AFFECTION_GAIN_EMAIL)


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


func has_horror_mode_started() -> bool:
	return not _dead_npc_ids.is_empty()


func get_dead_npc_ids() -> Array[String]:
	return _dead_npc_ids.duplicate()


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
## at random from today's pool: dialogue.daily[weekday_group][affection_tier],
## with horror_conversation mixed in once any NPC has died, and
## rain_conversation mixed in on rainy days (both are additive pools, not a
## separate weekday x tier x weather matrix - keeps the JSON schema small).
## Avoids repeating the same entry twice in a row when the pool has more than
## one option.
func get_daily_dialogue(npc_id: String) -> Array:
	var dialogue: Dictionary = get_definition(npc_id).get("dialogue", {})
	var daily: Dictionary = dialogue.get("daily", {})
	var group: Dictionary = daily.get(get_weekday_group(TimeManager.get_weekday()), {})
	var pool: Array = (group.get(get_affection_tier(npc_id), []) as Array).duplicate()
	if WeatherManager.is_raining():
		pool.append_array(dialogue.get("rain_conversation", []))
	if has_horror_mode_started():
		pool.append_array(dialogue.get("horror_conversation", []))
	if pool.is_empty():
		return []
	var index := randi() % pool.size()
	if pool.size() > 1 and index == int(_last_daily_dialogue_index.get(npc_id, -1)):
		index = (index + 1) % pool.size()
	_last_daily_dialogue_index[npc_id] = index
	return pool[index]


func get_weekday_group(weekday: String) -> String:
	return String(WEEKDAY_GROUPS.get(weekday, "weekend"))


## murder_system.md/horror_events.md: 사망한 NPC는 스케줄이 삭제된다.
func get_current_schedule_state(npc_id: String) -> String:
	if not is_alive(npc_id):
		return ""
	var schedule: Dictionary = get_definition(npc_id).get("schedule", {})
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


## get_current_schedule_state()가 고르는 "지금 활성 상태" 바로 다음으로 오늘
## 안에서 바뀔 예정인 항목을 반환한다({"time":"HH:MM","state":...}). 오늘
## 더 이상 남은 항목이 없으면(지금이 이미 마지막 항목) 빈 Dictionary - 자정
## 취침으로 인한 다음 날 스케줄 전환은 이미 하드 리셋이라 예측 대상이 아니다.
## NPCWorldManager가 "지금 출발해야 제 시간에 도착하는지" 미리 내다볼 때 쓴다.
func get_next_schedule_change(npc_id: String) -> Dictionary:
	if not is_alive(npc_id):
		return {}
	var schedule: Dictionary = get_definition(npc_id).get("schedule", {})
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
	var spawn: Dictionary = _spawn_index.get(state, {})
	if spawn.is_empty():
		push_warning("No spawn point found for schedule state '%s' (npc: %s)" % [state, npc_id])
		return {}
	return spawn.duplicate()


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
			"talked_today": has_talked_today(npc_id),
			"current_position": _serialize_position(npc_id),
			"death_day": get_death_day(npc_id),
			"scent_color": get_scent_color(npc_id),
		}
	return {
		"npc_states": npc_states,
		"dead_npc_ids": _dead_npc_ids,
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
		_murder_candidate_flagged[npc_id] = bool(state.get("murder_candidate_flagged", false))
		_talked_today[npc_id] = bool(state.get("talked_today", false))
		var death_day := int(state.get("death_day", -1))
		if death_day >= 0:
			_death_days[npc_id] = death_day
		var scent_color := String(state.get("scent_color", ""))
		if not scent_color.is_empty():
			_active_scent[npc_id] = scent_color
	_dead_npc_ids.clear()
	for npc_id in data.get("dead_npc_ids", []):
		_dead_npc_ids.append(String(npc_id))


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


func _check_affection_events(npc_id: String, affection: int) -> void:
	var completed: Array = _completed_events.get(npc_id, [])
	for event in get_definition(npc_id).get("affection_events", []):
		var threshold := int(event.get("threshold", -1))
		if affection >= threshold and not completed.has(threshold):
			completed.append(threshold)
			_completed_events[npc_id] = completed
			affection_event_triggered.emit(npc_id, threshold)
			if String(event.get("type", "")) == "memento":
				memento_received.emit(npc_id)
				# 웃음: 추억의 물건 건넬 때.
				request_emote(npc_id, EMOTE_SMILE)


func _on_day_changed(_day: int, _weekday: String) -> void:
	_talked_today.clear()
	_active_scent = _pending_scent.duplicate()
	_pending_scent.clear()


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
