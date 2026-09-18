extends RefCounted
class_name LivestockTrough

## LivestockManager의 여물통 표시 전담 - livestock_manager.gd가 이미
## 300줄 규칙에 걸려있어서 player.gd/player_tool_overlay.gd와 같은 이유로
## 분리했다(사용자 지시, 2026-09-05 - 외양간 4칸마다 개별 여물통).
## BerryBushManager와 완전히 같은 방식으로 WorldMap.find_toggleable_clusters()가
## cowshed_interior.tmx의 "Furniture_empty"(빈 여물통) 레이어를 스캔해서 위치를
## 자동으로 찾고, 각 클러스터를 가장 가까운 칸(spot1~4)에 매칭한다.

const TROUGH_LAYER_NAME := "Furniture_empty"

## map_id -> Array[Dictionary{"id","cells","center"}] - 지형은 런타임에 안
## 바뀌므로 맵당 한 번만 스캔하고 재사용한다.
var _trough_cache: Dictionary = {}
## stall_index -> 그 칸과 가장 가까운 여물통 클러스터.
var _stall_trough_cluster: Dictionary = {}


## LivestockManager.set_world_map()이 cowshed_interior를 불러올 때마다 호출.
## stalls는 LivestockManager._stalls 배열을 그대로 넘겨받는다(fed_day 조회용).
func refresh_for_map(world_map: WorldMap, map_id: String, stall_spawn_names: Array, stall_count: int, stalls: Array) -> void:
	if not _trough_cache.has(map_id):
		_trough_cache[map_id] = world_map.find_toggleable_clusters(TROUGH_LAYER_NAME)
		_match_to_stalls(world_map, _trough_cache[map_id], stall_spawn_names, stall_count)
	apply_state(world_map, stall_count, stalls)


func _match_to_stalls(world_map: WorldMap, clusters: Array, stall_spawn_names: Array, stall_count: int) -> void:
	for i in stall_count:
		var stall_position: Vector2 = world_map.get_spawn_position(stall_spawn_names[i])
		if stall_position == Vector2.INF:
			continue
		var best_cluster := {}
		var best_distance := INF
		for cluster in clusters:
			var distance: float = stall_position.distance_to((cluster as Dictionary)["center"])
			if distance < best_distance:
				best_distance = distance
				best_cluster = cluster
		if not best_cluster.is_empty():
			_stall_trough_cluster[i] = best_cluster


## 4칸 전부 fed_day를 오늘 날짜와 비교해서 다시 맞춘다(재입장/자정 통과 공통
## 경로) - 언제 찼는지/비었는지 판단은 fed_day 비교 하나로 끝난다.
func apply_state(world_map: WorldMap, stall_count: int, stalls: Array) -> void:
	for i in stall_count:
		set_fed(world_map, i, int((stalls[i] as Dictionary).get("fed_day", -1)) == TimeManager.current_day)


func set_fed(world_map: WorldMap, stall_index: int, fed: bool) -> void:
	if world_map == null:
		return
	var cluster: Dictionary = _stall_trough_cluster.get(stall_index, {})
	if cluster.is_empty():
		return
	for cell in (cluster["cells"] as Array):
		if fed:
			world_map.erase_toggleable_cell(TROUGH_LAYER_NAME, cell)
		else:
			world_map.restore_toggleable_cell(TROUGH_LAYER_NAME, cell)
