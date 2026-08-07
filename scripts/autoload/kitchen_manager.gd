extends Node

## Owns the 4 cooking-tool stations described in new_cooking_system.md 3.1~3.3
## (냄비/프라이팬/도마/믹서기, cooking_area1~4). Each station holds at most one
## raw ingredient while it cooks, on a REAL-TIME timer (not game time) -
## independent of CookingManager, which only knows about the final
## "조리된 재료 2개 -> 레시피" matching. 레스토랑 영업 중에만 사용 가능하다
## (3.6 - 사재기 완전 차단은 포기, 이 정도 제약만 건다).

const STATIONS_PATH := "res://data/cooking/cooking_stations.json"

var _stations: Dictionary = {}
## station_id -> {"ingredient_id": String, "cooked_id": String, "started_at": float, "duration": float}
var _active: Dictionary = {}


func _ready() -> void:
	_load_stations()


func _process(delta: float) -> void:
	for station_id in _active:
		_active[station_id]["elapsed"] = float(_active[station_id]["elapsed"]) + delta


func get_tool_name(station_id: String) -> String:
	return String(_stations.get(station_id, {}).get("tool_name", ""))


func get_duration(station_id: String) -> float:
	return float(_stations.get(station_id, {}).get("duration_seconds", 0.0))


## UI가 인벤토리 슬롯을 활성/비활성 처리하는 데 쓴다 - 이 기구에서 조리 가능한
## 원재료 id 목록.
func get_available_ingredients(station_id: String) -> Array:
	return (_stations.get(station_id, {}).get("ingredients", {}) as Dictionary).keys()


func is_busy(station_id: String) -> bool:
	return _active.has(station_id)


## 지금 그 기구 안에 들어있는 원재료 id(조리 중이든 완료 대기든) - 빈 문자열이면
## 비어있음.
func get_cooking_ingredient(station_id: String) -> String:
	return String(_active.get(station_id, {}).get("ingredient_id", ""))


## 다 익었을 때 collect()로 나올 조리된 재료 id - kitchen_screen.gd가
## is_ready()일 때 원재료 아이콘 대신 이걸로 바꿔 보여주는 데 쓴다(사용자
## 리포트 - 다 익어도 계속 원재료 그림이라 조리됐는지 구분이 안 됐음).
func get_cooking_result(station_id: String) -> String:
	return String(_active.get(station_id, {}).get("cooked_id", ""))


func get_progress(station_id: String) -> float:
	if not _active.has(station_id):
		return 0.0
	var duration: float = float(_active[station_id]["duration"])
	if duration <= 0.0:
		return 1.0
	return clampf(float(_active[station_id]["elapsed"]) / duration, 0.0, 1.0)


func is_ready(station_id: String) -> bool:
	return is_busy(station_id) and get_progress(station_id) >= 1.0


func can_start(station_id: String, item_id: String) -> bool:
	if not RestaurantManager.is_open or is_busy(station_id):
		return false
	var ingredients: Dictionary = _stations.get(station_id, {}).get("ingredients", {})
	return ingredients.has(item_id) and InventoryManager.get_item_count(item_id) > 0


## 인벤토리에서 원재료 1개를 소모하고 그 기구의 타이머를 시작한다.
func start_cooking(station_id: String, item_id: String) -> bool:
	if not can_start(station_id, item_id):
		return false
	if not InventoryManager.remove_item(item_id, 1):
		return false
	var station: Dictionary = _stations[station_id]
	var cooked_id: String = String((station["ingredients"] as Dictionary)[item_id])
	_active[station_id] = {
		"ingredient_id": item_id,
		"cooked_id": cooked_id,
		"elapsed": 0.0,
		"duration": float(station.get("duration_seconds", 0.0)),
	}
	return true


## 조리가 끝난 뒤 같은 상호작용으로 조리된 재료를 인벤토리로 꺼낸다. 아직 덜
## 익었으면 아무 일도 안 하고 false.
func collect(station_id: String) -> bool:
	if not is_ready(station_id):
		return false
	var cooked_id: String = String(_active[station_id]["cooked_id"])
	if not InventoryManager.add_item(cooked_id, 1):
		return false
	_active.erase(station_id)
	return true


func get_save_data() -> Dictionary:
	return _active.duplicate(true)


func load_save_data(data: Dictionary) -> void:
	_active = (data as Dictionary).duplicate(true)


func _load_stations() -> void:
	var file := FileAccess.open(STATIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Cooking station catalog could not be opened: %s" % STATIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Cooking station catalog is not valid JSON: %s" % STATIONS_PATH)
		return
	_stations = parsed
