extends Node2D

## Spawns/repositions/removes one NPCSprite per NPC that currently belongs on
## the active map, driven entirely by NPCManager.get_npc_world_position()
## (itself derived from time/weekday/weather/schedule). Needs no wiring from
## main.gd beyond existing as a node in the same coordinate space as
## HomeMap/Player - it reconciles itself off autoload signals.
##
## 스케줄이 다른 맵을 가리키면, 두 맵이 직접 이어져있지 않을 수 있으므로
## (예: plaza5 -> plaza1은 plaza4/Home을 거쳐야 함) WorldMap.find_map_route()로
## 전체 경로(거쳐야 할 맵 순서)를 구하고, 한 번에 한 홉씩 진행한다:
## - 지금 플레이어가 보고 있는 맵이 그 홉의 출발/도착 맵이면 실제로 걷는 모습을
##   보여준다(기존 스프라이트 걷기 재사용).
## - 안 보이는 맵이면 스프라이트 없이, 그 맵을 임시로 한 번 로드해서 실제 거리를
##   구해 초 단위로 환산한 타이머만 두고, 시간이 지나면 다음 홉으로 넘어간다.
## 각 홉의 문/도착 스폰은 Warp 오브젝트의 target_map/target_spawn을 그대로 쓴다
## (플레이어 워프와 완전히 같은 규칙) - 맵 그래프가 항상 완전히 연결되어 있다는
## 전제라 "이 맵의 기본 문" 같은 폴백은 없다.
##
## - _populate_initial(): map_changed에서만 호출. 정착해 있는 NPC는 그 자리에
##   즉시 스냅. 마침 이 맵을 지나가는 중이던(오프스크린이었던) NPC를 만나면,
##   문에서부터 다시 걷는 게 아니라 지금까지 흐른 시간 비율만큼 실제 경로 위를
##   이동한 지점부터 걷는 모습으로 보여준다(_resume_interrupted_hop 참고) -
##   그래야 맵 중앙쯤 지나가고 있어야 할 NPC가 방금 워프된 것처럼 보이지 않는다.
## - _reconcile_tick(): 그 외 신호(분 경과 - 실제 1초에 한 번, 날씨, 식당
##   착석/퇴장)에서 호출. 스케줄 목표가 바뀌었으면 새 여정을 시작하고, 진행 중인
##   홉이 끝났으면(보이는 홉은 걷기 완료, 안 보이는 홉은 타이머 만료) 다음 홉으로
##   잇는다.
## - _check_preemptive_departures(): minute_passed에서만 호출. 스케줄 시간이
##   되고 나서 출발하면 이동 시간만큼 늦게 도착하므로, 오늘 남은 다음 스케줄
##   항목을 미리 내다보고 전체 이동 예상 시간을 계산해 "지금 출발해야 정확히
##   그 시간에 도착"하는 순간 실제 스케줄이 바뀌기 전에 미리 여정을 시작한다.

const NPCSpriteScene := preload("res://scenes/npc_sprite.tscn")
## npc_sprite.gd의 WALK_SPEED와 반드시 일치해야 한다 - 안 보이는 홉의 소요 시간을
## (실제 거리 / 이 속도)로 추정하는데, 보이는 홉은 스프라이트가 실제로 이 속도로
## 걷기 때문에 두 계산이 어긋나면 안 보이던 NPC가 화면에 나타나는 타이밍이
## 부자연스러워진다.
const WALK_SPEED := 25.0
## 정적 Interactable(WorldMap.INTERACT_RADIUS=12)과 달리, NPC는 특정 타일
## 중심에 서 있고 플레이어는 그 "바로 옆 칸"에서 말을 걸 것으로 기대된다 -
## 타일 중심 간 거리(가로/세로 16px, 대각선 약 22.6px)보다 반경이 작으면
## 정확히 같은 칸에 서야만 대화가 가능해져서 너무 빡빡하다. 대각선으로
## 인접한 칸까지 넉넉히 포함하도록 24.0으로 잡는다.
const TALK_RADIUS := 24.0
## restaurant_dish_layer.gd/main.gd와 동일한 값 - 이 맵에 막 도착한 NPC가
## 식당 손님이면 RestaurantManager.notify_npc_entered_map()으로 알린다
## (_complete_current_hop 참고).
const RESTAURANT_MAP_ID := "restaurant_interior"

@onready var _world_map: WorldMap = get_parent() as WorldMap

var _active_sprites: Dictionary = {}
## npc_id -> 마지막으로 확정된 위치가 속한 맵 id. 화면에 보이든 안 보이든 항상
## 최신 상태를 유지한다 - 다음 홉/재경로 계산의 출발점.
var _npc_last_map: Dictionary = {}
## npc_id -> _npc_last_map 안에서의 좌표(스폰 지점이거나 최종 정착 좌표).
var _npc_last_position: Dictionary = {}
## npc_id -> 지금 향하고 있는(또는 이미 도착해 정착한) 스케줄상의 최종 맵 id.
## _npc_last_map과 같으면 "이미 그 맵에 있다"는 뜻(정착 또는 그 맵 안 마지막 다리).
var _npc_journey_target_map: Dictionary = {}
## npc_id -> 남은 경유 맵 id 배열(WorldMap.find_map_route() 결과, 다음 홉부터).
## 비어있으면 "더 거칠 맵 없음 - 지금 맵이 최종 맵".
var _npc_route: Dictionary = {}
## npc_id -> 최종 맵 안에서 실제로 서 있어야 할 스케줄 좌표.
var _npc_final_target: Dictionary = {}
## npc_id -> 지금 진행 중인 홉이 도착할 다음 맵에서 등장할 target_spawn 이름.
## 경유 홉(최종 다리가 아닌 홉)에서만 설정된다.
var _npc_pending_spawn: Dictionary = {}
## npc_id -> 안 보이는 홉이 끝날 때까지 남은 시간(게임 초 단위). TimeManager의
## minute_passed가 실제로 한 틱 지날 때만 깎는다 - Time.get_ticks_msec() 같은
## OS 실제 시계를 쓰면 안 된다: --fixed-fps로 빨리 돌리는 테스트나 메뉴를 열어
## TimeManager가 일시정지된 동안에는 실제 시간과 게임 시간이 전혀 안 맞아서
## 이 타이머가 사실상 영원히 안 끝나버린다(TimeManager.SECONDS_PER_GAME_MINUTE
## 참고 - 게임의 다른 모든 스케줄 계산이 이 시계를 기준으로 하므로 맞춰야 함).
var _npc_offscreen_remaining: Dictionary = {}
## npc_id -> 지금 안 보이는 홉을 시작할 때 추정했던 전체 소요 시간(게임 초).
## _npc_offscreen_remaining과 비교해 "몇 % 진행됐는지" 계산하는 용도 -
## 플레이어가 마침 이 홉이 지나가는 맵에 들어왔을 때, 문에서부터 처음부터
## 다시 걷는 것처럼 보이지 않고 실제 진행률만큼 이미 지나온 지점부터 보여주기
## 위해 필요하다(_resume_interrupted_hop 참고).
var _npc_hop_total_seconds: Dictionary = {}
## npc_id -> bool. 여정(하나 이상의 홉 + 마지막 다리) 진행 중이면 true, 완전히
## 정착하면 지운다.
var _npc_in_transit: Dictionary = {}
## "map_id|from|to" -> 실제 거리(px). WorldMap.compute_path_length()는 그 맵을
## 임시로 한 번 로드해야 해서, 매일 반복되는 스케줄에서 같은 구간을 계속
## 다시 계산하지 않도록 캐싱한다.
var _hop_length_cache: Dictionary = {}
## npc_id -> 지난 틱에 NPCManager.get_npc_world_position()이 실제로 돌려준
## 맵 id(우리가 미리 출발했는지와 무관한, "진짜 스케줄" 값). 사전 출발
## (_check_preemptive_departures) 때문에 _npc_journey_target_map이 아직
## 스케줄과 다른 상태에서도, "스케줄 자체가 방금 또 바뀐 건지"를 정확히
## 구분하기 위해 필요하다.
var _npc_last_seen_schedule_map: Dictionary = {}
## npc_id -> 같은 맵 안에서 걷는 중일 때 도착하면 확정할 좌표. 맵 간 이동
## (_npc_in_transit)과 달리 같은 맵 안 이동은 별도 진행 상태가 없어서, 도착
## 여부를 이걸로 따로 확인한다(_check_same_map_arrivals 참고) - 계산대처럼
## "정확히 그 좌표에 도착했는지" 확인해야 하는 쪽이 걷는 도중을 도착으로
## 착각하지 않게 하기 위함.
var _npc_same_map_target: Dictionary = {}
## npc_id -> bool. 스케줄이 갑자기 "안 보임"으로 바뀌었는데(예: 로시가 식당
## 손님으로 앉았다가 퇴장하는 순간 비가 그쳐서 원래 스케줄이 없어짐) 화면에
## 스프라이트가 떠 있는 상태라면, 그 자리에서 바로 지우지 않고 맵 출구까지
## 걸어 나가게 한 뒤에만 지운다(_handle_invisible_target/_check_same_map_arrivals
## 참고) - 안 그러면 화면에 보이는 채로 순간 사라져 보인다(사용자 리포트).
var _npc_exit_pending: Dictionary = {}


func _ready() -> void:
	GameManager.map_changed.connect(_on_map_changed)
	TimeManager.minute_passed.connect(_on_minute_passed)
	TimeManager.day_changed.connect(_on_day_changed)
	WeatherManager.weather_changed.connect(_on_weather_changed)
	NPCManager.npc_died.connect(_on_npc_died)
	NPCManager.npc_emote_requested.connect(_on_npc_emote_requested)
	RestaurantManager.npc_seated.connect(_on_restaurant_seating_changed)
	RestaurantManager.npc_departed.connect(_on_restaurant_seating_changed)
	_populate_initial()


## 이 NPC가 지금 화면(현재 맵)에 없으면 조용히 무시한다 - 안 보이는 반응은
## 큐잉하지 않는다(NPCManager.npc_emote_requested 참고).
func _on_npc_emote_requested(npc_id: String, emote_id: String) -> void:
	var sprite: Node2D = _active_sprites.get(npc_id)
	if sprite != null:
		sprite.call("show_emote", emote_id)


func _on_map_changed(_map_id: String) -> void:
	_populate_initial()


## 지금 화면에 보이는(현재 맵의) NPC 중 position 근처(TALK_RADIUS 이내)에
## 있으면서 오늘 아직 대화하지 않은 NPC 중 가장 가까운 쪽을 찾아
## {"npc_id": String, "distance": float}로 반환한다(없으면 빈 Dictionary).
## NPC는 고정된 Tiled Interactable이 아니라 매 순간 위치가 바뀌므로, WorldMap의
## 정적 오브젝트 판정과 별개로 여기서 동적으로 확인해야 한다. distance를 같이
## 주는 이유는, TALK_RADIUS를 넓힌 뒤로 계산대처럼 가까이 붙어있는 정적
## Interactable과 판정 범위가 겹치는 경우가 생겨서 - 호출하는 쪽(main.gd)이
## "둘 다 범위 안이면 더 가까운 쪽 우선"으로 판단할 수 있어야 한다.
func get_nearest_talkable_npc(position: Vector2) -> Dictionary:
	var best_id := ""
	var best_distance := INF
	for npc_id in _active_sprites:
		if not NPCManager.is_alive(npc_id):
			continue
		if NPCManager.has_talked_today(npc_id):
			continue
		var sprite: Node2D = _active_sprites[npc_id]
		var distance := sprite.position.distance_to(position)
		if distance <= TALK_RADIUS and distance < best_distance:
			best_id = npc_id
			best_distance = distance
	if best_id.is_empty():
		return {}
	return {"npc_id": best_id, "distance": best_distance}


## 자정 취침으로 하루가 넘어갈 때, 그날의 첫 스케줄 위치까지 걸어가게 하지
## 않고 즉시 그 자리에 있는 것으로 확정한다 - 플레이어도 자고 일어나면 순간
## 리셋되는 것과 마찬가지로 취급해야 한다. 안 그러면 전날 마지막 위치에서 새
## 하루 첫 위치까지 걸어오는 데 실제 시간이 걸려서, 플레이어가 아침 9시에
## 일어나자마자 가게로 달려가도 주인이 아직 도착 전이라 계산대를 못 쓰는
## 부자연스러운 상황이 생긴다.
func _on_day_changed(_day: int, _weekday: String) -> void:
	var player_map := GameManager.current_map_id
	for npc_id in NPCManager.get_all_ids():
		_hard_reset_npc(npc_id, player_map)


## npc_id의 진행 중이던 여정/타이머를 전부 폐기하고, 지금 스케줄이 가리키는
## 위치에 걷지 않고 바로 정착한 것으로 다시 초기화한다.
func _hard_reset_npc(npc_id: String, player_map: String) -> void:
	_npc_route.erase(npc_id)
	_npc_final_target.erase(npc_id)
	_npc_pending_spawn.erase(npc_id)
	_npc_offscreen_remaining.erase(npc_id)
	_npc_hop_total_seconds.erase(npc_id)
	_npc_in_transit.erase(npc_id)
	_npc_same_map_target.erase(npc_id)
	_npc_exit_pending.erase(npc_id)
	_npc_last_map.erase(npc_id)
	_npc_last_position.erase(npc_id)
	_npc_journey_target_map.erase(npc_id)
	_npc_last_seen_schedule_map.erase(npc_id)
	NPCManager.clear_npc_physical_spot(npc_id)
	_remove_sprite(npc_id)

	if not NPCManager.is_alive(npc_id):
		return
	var resolved := NPCManager.get_npc_world_position(npc_id)
	if resolved.is_empty():
		return
	var map_id := String(resolved["map_id"])
	var pos: Vector2 = resolved["position"]
	_npc_last_map[npc_id] = map_id
	_npc_last_position[npc_id] = pos
	_npc_journey_target_map[npc_id] = map_id
	_npc_last_seen_schedule_map[npc_id] = map_id
	NPCManager.set_npc_physical_spot(npc_id, map_id, pos)
	if map_id == player_map:
		var sprite := _ensure_sprite(npc_id)
		sprite.call("snap_to", pos)


func _on_minute_passed(_hour: int, _minute: int) -> void:
	_advance_offscreen_timers()
	_check_preemptive_departures()
	_reconcile_tick()


## 스케줄 시간이 되고 나서 출발하면 이동 시간만큼 늦게 도착한다 - 오늘 남은
## 다음 스케줄 항목을 미리 내다보고, "지금 출발해야 정확히 그 시간에 도착"하는
## 순간이 되면 실제 스케줄이 바뀌기 전에 미리 여정을 시작시킨다. 식당에 앉아
## 있는 동안은 건너뛴다 - 식사 중에 스케줄 시간이 됐다고 미리 일어나 걸어
## 나가면 부자연스럽다(식사 종료는 RestaurantManager가 별도로 처리).
func _check_preemptive_departures() -> void:
	var player_map := GameManager.current_map_id
	var now_minutes := TimeManager.current_hour * 60 + TimeManager.current_minute
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		if bool(_npc_in_transit.get(npc_id, false)):
			continue
		if not _npc_last_map.has(npc_id):
			continue
		if RestaurantManager.get_seated_station(npc_id) != -1:
			continue

		var next_change: Dictionary = NPCManager.get_next_schedule_change(npc_id)
		if next_change.is_empty():
			continue
		var next_target: Dictionary = NPCManager.resolve_state_position(String(next_change.get("state", "")))
		if next_target.is_empty():
			continue
		var next_map := String(next_target["map_id"])
		var known_map: String = _npc_last_map[npc_id]
		if next_map == known_map:
			continue

		var next_minutes := _parse_time_to_minutes(String(next_change.get("time", "")))
		var minutes_until := next_minutes - now_minutes
		if minutes_until <= 0:
			continue

		var next_pos: Vector2 = next_target["position"]
		var travel_seconds := _estimate_travel_seconds(known_map, _npc_last_position.get(npc_id, Vector2.ZERO), next_map, next_pos)
		if travel_seconds <= 0.0:
			continue
		if float(minutes_until) <= travel_seconds:
			_begin_journey(npc_id, known_map, next_map, next_pos, player_map)


func _parse_time_to_minutes(time_str: String) -> int:
	var parts := time_str.split(":")
	if parts.size() != 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])


## from_map(from_pos에 있다고 치고)에서 to_map(to_pos)까지 전체 여정에 걸리는
## 시간을 미리 추정한다(아직 아무 홉도 시작 안 한 상태에서, 사전 출발 판단용).
## _start_hop()이 한 번에 한 홉씩 실제로 하는 것과 같은 계산을, 경로 전체에
## 대해 한 번에 미리 훑는다 - 아직 어느 맵도 화면에 보이는 상태가 아닐 수
## 있으므로 항상 정적 맵 그래프/스폰 인덱스만 사용한다.
func _estimate_travel_seconds(from_map: String, from_pos: Vector2, to_map: String, to_pos: Vector2) -> float:
	if from_map == to_map:
		return _cached_path_length(from_map, from_pos, to_pos) / WALK_SPEED
	var route: Array[String] = WorldMap.find_map_route(from_map, to_map)
	if route.is_empty():
		return 0.0
	var total := 0.0
	var current_map := from_map
	var current_pos := from_pos
	for hop_map in route:
		var warp: Dictionary = _static_warp_for_target_map(current_map, hop_map)
		if warp.is_empty():
			return 0.0
		total += _cached_path_length(current_map, current_pos, warp["position"])
		var spawn_name: String = String(warp.get("target_spawn", ""))
		var resolved_name: String = String(WorldMap.SPAWN_ALIASES.get(spawn_name, spawn_name))
		var next_info: Dictionary = NPCManager.resolve_state_position(resolved_name)
		current_pos = next_info.get("position", warp["position"])
		current_map = hop_map
	total += _cached_path_length(to_map, current_pos, to_pos)
	return total / WALK_SPEED


## 안 보이는 홉들의 남은 시간을 게임 시계 기준으로 정확히 한 틱만큼 깎는다 -
## minute_passed에서만 호출해야 한다(날씨/식당 착석 신호에서도 _reconcile_tick이
## 불리지만, 그건 실제로 게임 시간이 흐른 게 아니므로 여기서 중복으로 깎으면
## 안 된다).
func _advance_offscreen_timers() -> void:
	var player_map := GameManager.current_map_id
	for npc_id in _npc_offscreen_remaining.keys().duplicate():
		var remaining: float = float(_npc_offscreen_remaining[npc_id]) - TimeManager.SECONDS_PER_GAME_MINUTE
		if remaining <= 0.0:
			_npc_offscreen_remaining.erase(npc_id)
			_complete_current_hop(npc_id, player_map)
		else:
			_npc_offscreen_remaining[npc_id] = remaining


func _on_weather_changed(_weather) -> void:
	_reconcile_tick()


func _on_npc_died(npc_id: String) -> void:
	_forget_npc(npc_id)


func _on_restaurant_seating_changed(_station_index: int, _npc_id: String) -> void:
	_reconcile_tick()


## 맵을 처음 불러왔을 때(막 들어온 상태) - 정착해 있는 NPC는 그 자리에 바로
## 스냅한다. 마침 이 맵을 지나가는 중이던(오프스크린이었던) NPC는 그 홉을
## 처음부터(이번엔 실제로 보이게) 다시 걷게 한다.
func _populate_initial() -> void:
	var player_map := GameManager.current_map_id
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			_forget_npc(npc_id)
			continue
		_bootstrap_if_unknown(npc_id)
		if not _npc_last_map.has(npc_id):
			continue

		var known_map: String = _npc_last_map[npc_id]
		if known_map != player_map:
			# 걷는 중이던 홉을 플레이어가 다른 맵으로 떠나버려서 화면 밖으로
			# 밀어낸 경우 - 스프라이트만 지우고 끝내면 그 홉이 영원히 안 끝나서
			# 여정이 멈춰버린다. 지금까지 걸어온 위치를 확정하고 같은 홉을
			# 안 보이는 타이머로 이어서 계속 진행시킨다.
			if bool(_npc_in_transit.get(npc_id, false)) and _active_sprites.has(npc_id):
				_npc_last_position[npc_id] = _active_sprites[npc_id].position
				_remove_sprite(npc_id)
				_start_hop(npc_id, known_map, player_map)
			else:
				_remove_sprite(npc_id)
			continue

		if bool(_npc_in_transit.get(npc_id, false)):
			if _npc_offscreen_remaining.has(npc_id):
				_resume_interrupted_hop(npc_id, player_map)
			else:
				# 방어적 대체 수단 - 정상 흐름에서는 여기 도달하지 않아야 한다
				# (안 보이는 홉 중이 아니면서 in_transit인 경우는 없어야 함).
				var sprite := _ensure_sprite(npc_id)
				sprite.call("snap_to", _npc_last_position.get(npc_id, Vector2.ZERO))
				_start_hop(npc_id, player_map, player_map)
		else:
			var sprite2 := _ensure_sprite(npc_id)
			sprite2.call("snap_to", _npc_last_position.get(npc_id, Vector2.ZERO))
			if RestaurantManager.get_seated_station(npc_id) != -1:
				sprite2.call("face_down")


## 지금 진행 중인 홉(경유 홉이면 다음 문, 마지막 다리면 최종 목표)의 목적지
## 좌표를 구한다. map_id는 이 홉이 실제로 진행되고 있는 맵.
func _current_hop_end_position(npc_id: String, map_id: String, player_map: String) -> Vector2:
	var start_pos: Vector2 = _npc_last_position.get(npc_id, Vector2.ZERO)
	if _npc_pending_spawn.has(npc_id):
		var route: Array[String] = _npc_route.get(npc_id, [])
		var next_map: String = route[0] if route.size() > 0 else ""
		var warp: Dictionary = _find_warp(map_id, next_map, player_map)
		if not warp.is_empty():
			return warp["position"]
		return start_pos
	return _npc_final_target.get(npc_id, start_pos)


## 진행 중이던 안 보이는 홉이 있으면, 지금까지 흐른 시간 비율만큼 실제 경로
## 위를 이동한 "진짜 현재 위치"로 _npc_last_position을 갱신하고 그 홉의
## 타이머를 지운다. 이동 도중 스케줄이 또 바뀌어 재경로해야 할 때
## (_begin_journey) 이걸 먼저 안 하면, 이미 걸어온 만큼을 무시하고 그 맵
## 입구부터 다시 계산해버려서 도착 예정 시간이 부정확해진다. 화면에 보이는
## 홉 중이면(오프스크린 타이머가 없으면) 아무것도 안 한다 - 그 경우는
## _start_hop이 스프라이트의 실제 위치를 그대로 쓴다.
func _settle_offscreen_progress(npc_id: String, map_id: String, player_map: String) -> void:
	if not _npc_offscreen_remaining.has(npc_id):
		return
	var start_pos: Vector2 = _npc_last_position.get(npc_id, Vector2.ZERO)
	var end_pos: Vector2 = _current_hop_end_position(npc_id, map_id, player_map)
	var total: float = float(_npc_hop_total_seconds.get(npc_id, 0.0))
	var remaining: float = float(_npc_offscreen_remaining.get(npc_id, 0.0))
	_npc_offscreen_remaining.erase(npc_id)
	_npc_hop_total_seconds.erase(npc_id)

	if total <= 0.0 or start_pos.is_equal_approx(end_pos):
		return
	var map_path := String(WorldMap.MAP_PATHS.get(map_id, ""))
	if map_path.is_empty():
		return
	var elapsed_fraction := clampf(1.0 - (remaining / total), 0.0, 1.0)
	var length := _cached_path_length(map_id, start_pos, end_pos)
	_npc_last_position[npc_id] = WorldMap.compute_point_along_path(map_path, start_pos, end_pos, length * elapsed_fraction)


## 화면 밖에서 이 맵을 지나가던 중이던 NPC를, 문에서부터 처음이 아니라 실제
## 진행률만큼 이미 지나온 지점부터 걷는 모습으로 등장시킨다 - 안 그러면 맵
## 중앙쯤 지나고 있어야 할 NPC가 방금 워프된 것처럼 문에 딱 붙어서 나타나
## 몰입을 깬다.
func _resume_interrupted_hop(npc_id: String, player_map: String) -> void:
	var start_pos: Vector2 = _npc_last_position.get(npc_id, Vector2.ZERO)
	var end_pos: Vector2 = _current_hop_end_position(npc_id, player_map, player_map)
	var total: float = float(_npc_hop_total_seconds.get(npc_id, 0.0))
	var remaining: float = float(_npc_offscreen_remaining.get(npc_id, 0.0))
	_npc_offscreen_remaining.erase(npc_id)
	_npc_hop_total_seconds.erase(npc_id)

	var sprite := _ensure_sprite(npc_id)
	if _world_map == null:
		sprite.call("snap_to", start_pos)
		return

	var full_path := _world_map.find_path(start_pos, end_pos)
	if full_path.is_empty():
		sprite.call("snap_to", start_pos)
		return

	var elapsed_fraction := 0.0
	if total > 0.0:
		elapsed_fraction = clampf(1.0 - (remaining / total), 0.0, 1.0)
	var full_length := 0.0
	for i in full_path.size() - 1:
		full_length += full_path[i].distance_to(full_path[i + 1])

	var advance: Dictionary = WorldMap.advance_along_path(full_path, full_length * elapsed_fraction)
	sprite.call("snap_to", advance["position"])
	sprite.call("walk_to", advance["remaining"])


## 맵을 이미 보고 있는 상태에서 시간/날씨/식당 착석 등으로 상황이 바뀌었을 때
## 호출된다. 진행 중인 홉이 끝났으면 다음 단계로 잇고, 스케줄 목표 자체가
## 바뀐 NPC는 새 여정을 시작한다.
func _reconcile_tick() -> void:
	var player_map := GameManager.current_map_id
	_check_visible_arrivals(player_map)
	_check_same_map_arrivals()

	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			_forget_npc(npc_id)
			continue

		var resolved := NPCManager.get_npc_world_position(npc_id)
		if resolved.is_empty():
			_handle_invisible_target(npc_id, player_map)
			continue

		var target_map := String(resolved["map_id"])
		var target_pos: Vector2 = resolved["position"]
		_bootstrap_if_unknown(npc_id, target_map, target_pos)
		var known_map: String = _npc_last_map.get(npc_id, target_map)

		# "스케줄이 진짜로 방금 바뀌었는지"는 _npc_journey_target_map이 아니라
		# 이 값(지난 틱에 관찰한 스케줄 원본)과 비교해야 한다 -
		# _check_preemptive_departures()가 스케줄이 실제로 바뀌기 전에 미리
		# 여정을 시작시켜두면, 그동안은 target_map(아직 옛 상태)과
		# _npc_journey_target_map(미리 정한 다음 목표)이 서로 다른 게 정상이라
		# 그것만으로 "또 바뀜"이라고 오판하면 사전 출발한 여정을 즉시 취소해버린다.
		var schedule_just_changed := target_map != String(_npc_last_seen_schedule_map.get(npc_id, target_map))
		_npc_last_seen_schedule_map[npc_id] = target_map

		if bool(_npc_in_transit.get(npc_id, false)):
			if String(_npc_journey_target_map.get(npc_id, "")) == target_map:
				_npc_final_target[npc_id] = target_pos
			elif schedule_just_changed:
				_begin_journey(npc_id, known_map, target_map, target_pos, player_map)
			continue

		if known_map == target_map:
			_settle_in_place(npc_id, known_map, target_pos, player_map)
		else:
			_begin_journey(npc_id, known_map, target_map, target_pos, player_map)


## get_npc_world_position()이 빈 값을 돌려줄 때(스케줄상 지금 안 보여야 하는
## NPC) 호출된다. 화면에 스프라이트가 없으면(원래 안 보이던 NPC) 그냥 잊으면
## 되지만, 방금까지 보이던 NPC(예: 식당 손님 퇴장)라면 그 자리에서 바로
## 지우지 않고 맵 출구까지 걸어나가게 한 뒤에 지운다.
func _handle_invisible_target(npc_id: String, player_map: String) -> void:
	if not _active_sprites.has(npc_id) or bool(_npc_in_transit.get(npc_id, false)):
		_forget_npc(npc_id)
		return
	if bool(_npc_exit_pending.get(npc_id, false)):
		return
	var exit_pos := _find_any_exit(player_map)
	if exit_pos == Vector2.INF:
		_forget_npc(npc_id)
		return
	_npc_exit_pending[npc_id] = true
	_npc_same_map_target.erase(npc_id)
	_start_same_map_walk(npc_id, exit_pos)
	_npc_same_map_target[npc_id] = exit_pos


## map_id에 있는 워프(문) 중 아무거나 하나의 좌표를 돌려준다 - 출구가 여러
## 개여도 어느 쪽이 "원래 들어온 문"인지 알 방법이 없어서, 화면 밖으로 나가는
## 모습만 보여주면 충분하다는 전제로 첫 번째를 그냥 쓴다. 출구가 없는 맵이면
## Vector2.INF.
func _find_any_exit(map_id: String) -> Vector2:
	var graph: Dictionary = WorldMap.get_map_graph()
	var warps: Array = graph.get(map_id, [])
	if warps.is_empty():
		return Vector2.INF
	return Vector2(warps[0]["position"])


## 아직 한 번도 추적한 적 없는(또는 죽었다가/비가시 상태였다가 방금 다시
## 나타난) NPC를 "지금 스케줄 위치에 이미 정착해 있는 상태"로 초기화한다 -
## 어디서 걸어온 것처럼 보이면 안 되고 그냥 그 자리에 있던 것으로 취급한다.
func _bootstrap_if_unknown(npc_id: String, target_map: String = "", target_pos: Vector2 = Vector2.ZERO) -> void:
	if _npc_last_map.has(npc_id):
		return
	var map_id := target_map
	var pos := target_pos
	# 식당에 이미 앉아있는 상태로 처음 추적을 시작하는 경우(예: 오늘 한 번도
	# 안 보인 NPC가 갑자기 손님으로 배정됨) - 넘겨받은 target은 이미 좌석
	# 좌표라서(get_npc_world_position() 참고) 그대로 "원래 있던 자리"로 쓰면
	# 좌석까지 걸어오는 거리가 0이 되어 순간이동한 것처럼 보인다(사용자
	# 리포트 - 로시가 식당에 처음 배정될 때 걷지 않고 바로 나타남). 순수하게
	# 스케줄만 봤을 때의 위치를 기준으로 잡아서, 이후 정상 흐름이 그 자리에서
	# 좌석까지 실제로 걷게 한다. 스케줄상으로도 지금 안 보이는 상태라면(예:
	# 로시가 비 안 오는 날) 걸어올 "원래 자리" 자체가 없으니 좌석을 그대로 쓴다.
	if RestaurantManager.get_seated_station(npc_id) != -1:
		var schedule_pos := NPCManager.get_schedule_only_position(npc_id)
		if not schedule_pos.is_empty():
			map_id = String(schedule_pos["map_id"])
			pos = schedule_pos["position"]
	if map_id.is_empty():
		var resolved := NPCManager.get_npc_world_position(npc_id)
		if resolved.is_empty():
			return
		map_id = String(resolved["map_id"])
		pos = resolved["position"]
	_npc_last_map[npc_id] = map_id
	_npc_last_position[npc_id] = pos
	_npc_journey_target_map[npc_id] = map_id
	NPCManager.set_npc_physical_spot(npc_id, map_id, pos)


## 이미 목표 맵에 있는(정착한) NPC - 화면에 보이면 스프라이트를 확실히
## 만들어두고, 스케줄 좌표가 이전과 달라졌으면 같은 맵 안에서 걷게 한다.
## 실제로 그 좌표에 도착하기 전까지는 NPCManager에 "정확히 정착했다"고
## 알리지 않는다 - 같은 맵 안 이동은 _npc_in_transit을 안 쓰므로, 걷기 시작한
## 경우엔 _npc_same_map_target에 등록해두고 _check_same_map_arrivals()가 실제
## 도착을 확인한 뒤에 알린다.
func _settle_in_place(npc_id: String, map_id: String, target_pos: Vector2, player_map: String) -> void:
	_npc_journey_target_map[npc_id] = map_id
	if map_id != player_map:
		# 화면 밖 같은 맵 이동은 지금도 순간 처리(시간 시뮬레이션 없음) -
		# 지연시킬 실제 걷기가 없으므로 바로 확정해도 된다.
		_npc_last_position[npc_id] = target_pos
		_npc_same_map_target.erase(npc_id)
		NPCManager.set_npc_physical_spot(npc_id, map_id, target_pos)
		return
	var last_pos: Vector2 = _npc_last_position.get(npc_id, target_pos)
	if not _active_sprites.has(npc_id):
		var sprite := _ensure_sprite(npc_id)
		sprite.call("snap_to", last_pos)
	if not last_pos.is_equal_approx(target_pos):
		_start_same_map_walk(npc_id, target_pos)
		_npc_same_map_target[npc_id] = target_pos
	else:
		_npc_same_map_target.erase(npc_id)
		NPCManager.set_npc_physical_spot(npc_id, map_id, target_pos)
		if RestaurantManager.get_seated_station(npc_id) != -1:
			# 이미 도착해서 더 움직일 필요 없음 - 식당에 앉아있는 중이면 정면 유지.
			_active_sprites[npc_id].call("face_down")
	_npc_last_position[npc_id] = target_pos


## 스케줄이 지금 있는 맵과 다른 맵을 가리킬 때 새 여정을 시작한다(또는 이미
## 이동 중이던 여정을 새 목표로 다시 잡는다). WorldMap.find_map_route()로
## 전체 경로를 구하고 첫 홉을 시작한다.
func _begin_journey(npc_id: String, from_map: String, to_map: String, final_pos: Vector2, player_map: String) -> void:
	# 새 목표(_npc_final_target 등)를 덮어쓰기 전에, 화면 밖에서 이미 진행
	# 중이던 홉이 있으면 지금까지 걸어온 진짜 위치부터 이어가도록 확정해둔다 -
	# 안 그러면 그 맵 입구로 되돌아간 것처럼 계산돼서 도착 예정 시간이 어긋난다.
	_settle_offscreen_progress(npc_id, from_map, player_map)
	# 이 순간부터 이동 중이라 어느 한 좌표에 확정적으로 있다고 할 수 없다 -
	# 계산대처럼 "실제로 지금 여기 있는지"를 확인하는 쪽이 스케줄만 보고
	# 착각하지 않도록 여기서 즉시 지운다(스케줄은 이미 도착한 것처럼 보일 수
	# 있어도, 실제로는 방금 떠난 참이다).
	NPCManager.clear_npc_physical_spot(npc_id)
	_npc_same_map_target.erase(npc_id)

	_npc_journey_target_map[npc_id] = to_map
	_npc_final_target[npc_id] = final_pos
	_npc_pending_spawn.erase(npc_id)
	_npc_offscreen_remaining.erase(npc_id)
	_npc_hop_total_seconds.erase(npc_id)

	var route: Array[String] = WorldMap.find_map_route(from_map, to_map)
	if route.is_empty() and from_map != to_map:
		# 맵 그래프에 경로가 없다 - 정상적인 맵 데이터라면 도달하지 않아야 함.
		# 안전하게 순간이동으로 대체하고 즉시 정착시킨다.
		push_warning("NPC %s: no map route found from %s to %s" % [npc_id, from_map, to_map])
		_npc_route.erase(npc_id)
		_npc_in_transit.erase(npc_id)
		_npc_last_map[npc_id] = to_map
		_npc_last_position[npc_id] = final_pos
		NPCManager.set_npc_physical_spot(npc_id, to_map, final_pos)
		if to_map == player_map:
			var sprite := _ensure_sprite(npc_id)
			sprite.call("snap_to", final_pos)
		else:
			_remove_sprite(npc_id)
		return

	_npc_route[npc_id] = route
	_npc_in_transit[npc_id] = true
	_start_hop(npc_id, from_map, player_map)


## from_map에서 다음 목적지로 가는 한 홉을 시작한다. 남은 경유 맵이 없으면
## 최종 목표 좌표까지 마지막 다리를 시작한다.
func _start_hop(npc_id: String, from_map: String, player_map: String) -> void:
	var route: Array[String] = _npc_route.get(npc_id, [])
	var from_pos: Vector2 = _npc_last_position.get(npc_id, Vector2.ZERO)
	if from_map == player_map and _active_sprites.has(npc_id):
		from_pos = _active_sprites[npc_id].position

	if route.is_empty():
		_start_final_leg(npc_id, from_map, from_pos, player_map)
		return

	var next_map: String = route[0]
	var warp: Dictionary = _find_warp(from_map, next_map, player_map)
	if warp.is_empty():
		push_warning("NPC %s: no warp from %s to %s" % [npc_id, from_map, next_map])
		_npc_route[npc_id] = route.slice(1)
		_npc_last_map[npc_id] = next_map
		_start_hop(npc_id, next_map, player_map)
		return

	_npc_pending_spawn[npc_id] = String(warp.get("target_spawn", ""))
	var door_pos: Vector2 = warp["position"]

	if from_map == player_map and _world_map != null:
		var sprite := _ensure_sprite(npc_id)
		var path := _world_map.find_path(from_pos, door_pos)
		if path.is_empty():
			sprite.call("snap_to", door_pos)
		else:
			sprite.call("walk_to", path)
	else:
		var length := _cached_path_length(from_map, from_pos, door_pos)
		var seconds := length / WALK_SPEED
		_npc_offscreen_remaining[npc_id] = seconds
		_npc_hop_total_seconds[npc_id] = seconds


## 남은 경유 맵이 없을 때(이미 최종 맵에 있음) - 스케줄이 실제로 지정한
## 좌표까지 마지막으로 걷는다.
func _start_final_leg(npc_id: String, map_id: String, from_pos: Vector2, player_map: String) -> void:
	var final_pos: Vector2 = _npc_final_target.get(npc_id, from_pos)
	if map_id == player_map and _world_map != null:
		var sprite := _ensure_sprite(npc_id)
		var path := _world_map.find_path(from_pos, final_pos)
		if path.is_empty():
			sprite.call("snap_to", final_pos)
		else:
			sprite.call("walk_to", path)
	else:
		var length := _cached_path_length(map_id, from_pos, final_pos)
		var seconds := length / WALK_SPEED
		_npc_offscreen_remaining[npc_id] = seconds
		_npc_hop_total_seconds[npc_id] = seconds


## from_map에서 next_map으로 이어지는 워프를 찾는다. from_map이 지금 보이는
## 맵이면 실제 로드된 WorldMap의 라이브 데이터를 쓰고, 아니면 정적 맵 그래프
## 캐시(WorldMap.get_map_graph())에서 찾는다.
func _find_warp(from_map: String, next_map: String, player_map: String) -> Dictionary:
	if from_map == player_map and _world_map != null:
		return _world_map.get_warp_for_target_map(next_map)
	return _static_warp_for_target_map(from_map, next_map)


## _find_warp()과 달리 항상 정적 맵 그래프 캐시만 쓴다 - 사전 출발 추정처럼
## "지금 이 맵이 화면에 보이는지"가 아직 의미 없는(어느 홉도 시작 안 한)
## 상황에서 쓴다.
func _static_warp_for_target_map(map_id: String, target_map_id: String) -> Dictionary:
	var graph: Dictionary = WorldMap.get_map_graph()
	for warp in graph.get(map_id, []):
		if String(warp.get("target_map", "")) == target_map_id:
			return warp
	return {}


## 화면에 보이는 홉이 끝났는지(걷기 완료) 확인한다. 안 보이는 홉의 완료는
## _advance_offscreen_timers()(minute_passed 전용)가 따로 처리한다.
func _check_visible_arrivals(player_map: String) -> void:
	for npc_id in _active_sprites.keys().duplicate():
		if not bool(_npc_in_transit.get(npc_id, false)):
			continue
		if _npc_offscreen_remaining.has(npc_id):
			continue
		var sprite: Node2D = _active_sprites[npc_id]
		if not bool(sprite.call("is_walking")):
			_complete_current_hop(npc_id, player_map)


## 같은 맵 안에서 걷던(맵 간 이동이 아닌) NPC가 목표 좌표에 실제로 도착했는지
## 확인한다 - _npc_in_transit을 안 쓰는 흐름이라 _check_visible_arrivals와는
## 별도로 확인해야 한다. 도착하면 NPCManager에 정확한 좌표를 알린다.
func _check_same_map_arrivals() -> void:
	for npc_id in _npc_same_map_target.keys().duplicate():
		if bool(_npc_in_transit.get(npc_id, false)):
			# 그 사이 맵 간 이동으로 전환됨 - _check_visible_arrivals 쪽이 처리.
			_npc_same_map_target.erase(npc_id)
			continue
		if not _active_sprites.has(npc_id):
			_npc_same_map_target.erase(npc_id)
			continue
		if bool(_active_sprites[npc_id].call("is_walking")):
			continue
		var target: Vector2 = _npc_same_map_target[npc_id]
		_npc_same_map_target.erase(npc_id)
		if bool(_npc_exit_pending.get(npc_id, false)):
			# 출구까지 다 걸어나갔다 - 이제서야 지운다(_handle_invisible_target).
			_npc_exit_pending.erase(npc_id)
			_forget_npc(npc_id)
			continue
		NPCManager.set_npc_physical_spot(npc_id, String(_npc_last_map.get(npc_id, "")), target)


## 진행 중이던 한 홉(경유 홉 또는 마지막 다리)이 끝났을 때 호출된다. 경유
## 홉이었으면 도착한 맵/좌표를 확정하고 다음 홉을 잇는다. 마지막 다리였으면
## 완전히 정착한다.
func _complete_current_hop(npc_id: String, player_map: String) -> void:
	if not _npc_pending_spawn.has(npc_id):
		# 마지막 다리 도착 완료 - 정착.
		_npc_last_position[npc_id] = _npc_final_target.get(npc_id, _npc_last_position.get(npc_id, Vector2.ZERO))
		_npc_in_transit.erase(npc_id)
		NPCManager.set_npc_physical_spot(npc_id, String(_npc_last_map.get(npc_id, "")), _npc_last_position[npc_id])
		if RestaurantManager.get_seated_station(npc_id) != -1 and _active_sprites.has(npc_id):
			_active_sprites[npc_id].call("face_down")
		return

	var spawn_name: String = String(_npc_pending_spawn[npc_id])
	_npc_pending_spawn.erase(npc_id)
	var route: Array[String] = _npc_route.get(npc_id, [])
	var next_map: String = route[0] if route.size() > 0 else ""
	_npc_route[npc_id] = route.slice(1) if route.size() > 0 else []

	if _active_sprites.has(npc_id):
		_remove_sprite(npc_id)

	if next_map.is_empty():
		return

	var arrive_pos := Vector2.INF
	if next_map == player_map and _world_map != null:
		arrive_pos = _world_map.get_spawn_position(spawn_name)
	else:
		# get_spawn_position()과 동일하게 SPAWN_ALIASES를 거쳐야 한다 - 안 그러면
		# "hospital_in" 같은 옛 이름이 안 보이는(오프스크린) 경로에서만 못 찾아진다.
		# NPCManager._spawn_index는 전체 맵의 스폰을 이미 한 번에 캐싱해뒀으니
		# 그걸 재사용한다 - 매번 XML을 다시 읽지 않는다.
		var resolved_name: String = String(WorldMap.SPAWN_ALIASES.get(spawn_name, spawn_name))
		var info: Dictionary = NPCManager.resolve_state_position(resolved_name)
		if not info.is_empty() and String(info.get("map_id", "")) == next_map:
			arrive_pos = info["position"]
	if arrive_pos == Vector2.INF:
		push_warning("NPC %s: spawn '%s' not found in %s" % [npc_id, spawn_name, next_map])
		arrive_pos = _npc_final_target.get(npc_id, Vector2.ZERO)

	_npc_last_map[npc_id] = next_map
	_npc_last_position[npc_id] = arrive_pos
	if next_map == RESTAURANT_MAP_ID:
		RestaurantManager.notify_npc_entered_map(npc_id)
	if next_map == player_map:
		var sprite := _ensure_sprite(npc_id)
		sprite.call("snap_to", arrive_pos)
	_start_hop(npc_id, next_map, player_map)


## 같은 맵 안에서 목표만 바뀐 경우(스케줄 상태 전환, 식당 착석/퇴장 등) -
## 지금 위치(걷는 중이면 그 중간 지점)에서 새 목표까지 다시 경로를 구한다.
func _start_same_map_walk(npc_id: String, target: Vector2) -> void:
	var sprite: Node2D = _active_sprites[npc_id]
	var path: PackedVector2Array = _world_map.find_path(sprite.position, target) if _world_map != null else PackedVector2Array()
	if path.is_empty():
		sprite.call("snap_to", target)
	else:
		sprite.call("walk_to", path)


## map_id 안에서 from_pos -> to_pos 실제 거리(px)를 구한다. 매일 반복되는
## 스케줄에서 같은 구간을 계속 다시 로드하지 않도록 캐싱한다.
func _cached_path_length(map_id: String, from_pos: Vector2, to_pos: Vector2) -> float:
	var key := "%s|%s|%s" % [map_id, from_pos, to_pos]
	if _hop_length_cache.has(key):
		return float(_hop_length_cache[key])
	var map_path := String(WorldMap.MAP_PATHS.get(map_id, ""))
	var length := 0.0
	if not map_path.is_empty():
		length = WorldMap.compute_path_length(map_path, from_pos, to_pos)
	_hop_length_cache[key] = length
	return length


## npc_id의 모든 추적 상태를 지운다(죽었거나, 지금 스케줄상 어디에도 없는
## 경우 - 예: 비가 안 올 때의 Roshi). 나중에 다시 나타나면
## _bootstrap_if_unknown()이 "그 자리에 이미 있던 것"으로 새로 초기화한다.
func _forget_npc(npc_id: String) -> void:
	_remove_sprite(npc_id)
	_npc_last_map.erase(npc_id)
	_npc_last_position.erase(npc_id)
	_npc_journey_target_map.erase(npc_id)
	_npc_route.erase(npc_id)
	_npc_final_target.erase(npc_id)
	_npc_offscreen_remaining.erase(npc_id)
	_npc_hop_total_seconds.erase(npc_id)
	_npc_pending_spawn.erase(npc_id)
	_npc_in_transit.erase(npc_id)
	_npc_last_seen_schedule_map.erase(npc_id)
	_npc_same_map_target.erase(npc_id)
	_npc_exit_pending.erase(npc_id)
	NPCManager.clear_npc_physical_spot(npc_id)


## Avoids typing the instance as the NPCSprite class_name on purpose: that
## resolution depends on the editor's global script class cache being fresh,
## which isn't guaranteed on a plain headless run. call() dispatches by name
## at runtime instead, regardless of cache state.
func _ensure_sprite(npc_id: String) -> Node2D:
	var sprite: Node2D = _active_sprites.get(npc_id)
	if sprite == null:
		sprite = NPCSpriteScene.instantiate() as Node2D
		# NPCLayer(자기 자신) 밑이 아니라 WorldMap의 직접 자식으로 붙인다 -
		# Player도 WorldMap의 직접 자식이고, 타일들도 WorldMap.add_child()로
		# 직접 붙는다. y_sort_enabled가 중첩된 래퍼 노드를 거쳐도 제대로
		# 전파되는지 애매하게 의존하기보다, 아예 같은 부모 밑에 둬서 확실하게
		# 만든다.
		if _world_map != null:
			_world_map.add_child(sprite)
		else:
			add_child(sprite)
		sprite.call("set_npc_id", npc_id)
		_active_sprites[npc_id] = sprite
	return sprite


func _remove_sprite(npc_id: String) -> void:
	var sprite: Node2D = _active_sprites.get(npc_id)
	if sprite != null:
		sprite.queue_free()
		_active_sprites.erase(npc_id)
