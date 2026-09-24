extends Node

## Home.tmx 등에 기획자가 Tiled에서 직접 그려둔 "Grass"(열매 있음)/
## "Grass_empty"(열매 없음, 항상 Grass 밑에 깔려있음) 타일 레이어 쌍을 베리
## 덤불로 취급한다. 스폰 좌표를 따로 안 찍어도 된다 - 맵을 불러올 때마다
## WorldMap.find_toggleable_clusters("Grass")로 그려진 칸을 그대로 스캔해서
## 덤불 위치/개수를 자동으로 알아낸다(FarmingManager의 "가장 가까운 칸" 대신
## 낚시처럼 "근접 판정"을 쓰는 이유는 덤불이 2x2 이상으로 넓어서 - 축사/농사와
## 달리 정확히 한 칸에 서야 하는 구조가 아님).

const BERRY_LAYER_NAME := "Grass"
const BERRY_ITEM_ID := "berry"
const BERRY_YIELD_COUNT := 1
## 애니멀 상호작용 반경(24px)과 같은 급 - 덤불이 여러 칸이라 정확히 한 칸에
## 설 필요 없이 근처면 딸 수 있게 한다.
const INTERACT_RADIUS := 24.0

var _world_map: WorldMap = null
## map_id -> Array[Dictionary{"id","cells","center"}] - 맵 지형은 런타임에 안
## 바뀌므로 맵당 한 번만 스캔하고 재사용한다.
var _bush_cache: Dictionary = {}
## "map_id:cluster_id" -> 오늘 이미 땄는지. 하루 지나면(day_changed) 전부
## 비운다 - FarmingManager의 watered_today와 같은 "하루 1회" 패턴.
var _picked_today: Dictionary = {}


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func _on_day_changed(_day: int, _weekday: String) -> void:
	_picked_today.clear()
	if _world_map != null:
		_restore_all_bushes()


## main.gd가 맵을 옮길 때마다 호출한다(FarmingManager.set_world_map()과 같은
## 패턴) - 이번 맵의 덤불 목록을 캐시하고, 오늘 이미 딴 덤불이 있으면 다시
## 지워서(맵은 항상 원본 그림 그대로 로드되므로) 상태를 유지한다.
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	_world_map = world_map
	if not _bush_cache.has(map_id):
		_bush_cache[map_id] = world_map.find_toggleable_clusters(BERRY_LAYER_NAME)
	for bush in (_bush_cache[map_id] as Array):
		if bool(_picked_today.get("%s:%s" % [map_id, bush["id"]], false)):
			_erase_bush(bush)


## main.gd가 "E 채집" 프롬프트/실제 수확 판정에 쓴다 - 반경 안에 아직 안 딴
## 덤불이 있으면 그 Dictionary를, 없으면 빈 Dictionary.
func get_available_bush(world_position: Vector2) -> Dictionary:
	var map_id := GameManager.current_map_id
	for bush in (_bush_cache.get(map_id, []) as Array):
		if bool(_picked_today.get("%s:%s" % [map_id, bush["id"]], false)):
			continue
		if world_position.distance_to(bush["center"]) <= INTERACT_RADIUS:
			return bush
	return {}


func perform_harvest(bush: Dictionary) -> String:
	if bush.is_empty():
		return ""
	if not InventoryManager.can_add_item(BERRY_ITEM_ID, BERRY_YIELD_COUNT):
		return tr("인벤토리가 가득 찼다.")
	InventoryManager.add_item(BERRY_ITEM_ID, BERRY_YIELD_COUNT)
	_picked_today["%s:%s" % [GameManager.current_map_id, bush["id"]]] = true
	_erase_bush(bush)
	AudioManager.play_sfx(AudioManager.SFX_ITEM_PICKING)
	return tr("베리를 땄다.")


func _erase_bush(bush: Dictionary) -> void:
	if _world_map == null:
		return
	for cell in (bush["cells"] as Array):
		_world_map.erase_toggleable_cell(BERRY_LAYER_NAME, cell)


func _restore_all_bushes() -> void:
	for bush in (_bush_cache.get(GameManager.current_map_id, []) as Array):
		for cell in (bush["cells"] as Array):
			_world_map.restore_toggleable_cell(BERRY_LAYER_NAME, cell)


func get_save_data() -> Dictionary:
	return {"picked_today": _picked_today.duplicate()}


func load_save_data(data: Dictionary) -> void:
	_picked_today = (data.get("picked_today", {}) as Dictionary).duplicate()
