extends Node

## Home.tmx의 "Farmable" 레이어 위 경작지(밭)를 관리한다. 손에 든 도구에 따라
## 괭이질/물주기/심기/수확이 갈리는 구조는 livestock_manager.gd의 급여/착유/
## 도살 패턴을 그대로 따른다. 다만 축사는 고정 4칸(Spawn 좌표)인 반면 밭은
## Farmable 레이어 전체(수백 칸)라서, 대상 판정은 "가장 가까운 칸 탐색"이
## 아니라 낚시처럼 "플레이어가 바라보는 칸" 하나로 한다 - main.gd가 매
## 함수에 player.get_facing_tile_position()을 그대로 넘긴다.
## 성장(사용자 확정): "실제로 물을 준 횟수"(watered_count)로 큰다 - 물은 하루
## 1번만 가능(비 오는 날은 자동 급수). 표시는 0번=씨앗, 1번 이상=새싹, 필요
## 급수(crops.json의 waterings_required) 채우면 작물.
## **작물 그림은 물 준 그 즉시 바뀌지 않는다**(사용자 확정, 스타듀 밸리처럼
## "자고 일어나야 자란 게 보임" - 눈앞에서 휙휙 바뀌면 이상하다는 피드백).
## 그래서 실제 판정에 쓰는 watered_count와, 그림 표시에만 쓰는
## display_watered_count를 분리한다 - 후자는 다음 날짜 전환
## (_on_weather_changed) 시점에야 watered_count를 따라잡는다. 심은 직후에는
## (이미 젖은 흙에 심어서 watered_count가 1로 시작하더라도) display는 항상
## 0부터 시작해 씨앗 그림으로 보인다. 흙이 마른/젖은 상태(SOIL_*_INDEX)는
## 이 지연 대상이 아니다 - 물 준 순간 바로 젖은 흙으로 보이는 게 자연스럽다는
## 판단(작물 그림과 달리 사용자가 지연을 요청하지 않은 부분).

const CROPS_PATH := "res://data/crops/crops.json"
const FARM_MAP_ID := "Home"
## 사용자가 assets/crop/crop.png에 16x16 칸으로 그려준 시트 - 0=마른 경작지,
## 1=젖은 경작지, 2~10=감자/옥수수/상추 각각의 씨앗/새싹/작물(사용자 지시,
## crops.json의 sprite_index가 실제 인덱스를 갖고 있음).
const CROP_SPRITE_SHEET := "res://assets/crop/crop.png"
const CROP_SPRITE_SIZE := 16
const SOIL_DRY_INDEX := 0
const SOIL_WET_INDEX := 1
## 새싹으로 바뀌는 최소 급수 횟수 - 1번만 줘도 새싹으로 보인다(사용자 확정,
## 0번=씨앗 / 1번 이상=새싹).
const SPROUT_MIN_WATERINGS := 1

var _crops: Dictionary = {}
## seed_item_id -> crop_type 역방향 조회(손에 든 씨앗 아이템으로 무슨 작물을
## 심는지 바로 알아야 해서).
var _seed_to_crop: Dictionary = {}

## Vector2i(칸) -> {} (괭이질 안 됨, 키 자체가 없음) 또는
## {"watered_today": bool, "crop_type": String("" = 안 심음),
##  "watered_count": int(실제 급수 횟수 - 판정용),
##  "display_watered_count": int(그림 표시용 - 다음 날짜 전환에야 watered_count를 따라잡음)}
var _plots: Dictionary = {}

var _world_map: WorldMap = null
## 칸(Vector2i) -> Sprite2D. 흙은 괭이질된 모든 칸에 항상 있고, 작물은
## crop_type이 있을 때만 존재한다.
var _soil_sprites: Dictionary = {}
var _crop_sprites: Dictionary = {}


func _ready() -> void:
	_load_crops()
	WeatherManager.weather_changed.connect(_on_weather_changed)


## main.gd가 프롬프트 문구/실제 처리 양쪽에서 같은 판정을 쓴다
## (LivestockManager.get_equipped_action()과 동일한 역할).
## "till"/"water"/"needs_till"/"plant"/"harvest"/"" 중 하나. 다 자란 칸은 손에
## 뭘 들었든 항상 수확이 최우선이다(사용자 지시 - 물뿌리개를 든 채 다 자란
## 작물과 상호작용했더니 수확 대신 물이 나가버렸다는 피드백. 이미 다 자란
## 작물에 물을 더 주는 건 어차피 의미가 없으므로 물주기보다 수확이 항상
## 이긴다). "needs_till"은 물뿌리개를 든 채 아직 갈지 않은 밭에 물을 주려 할
## 때만 나온다 - main.gd가 이걸 보고 "먼저 밭을 갈아야 한다." 안내를 띄운다
## (2026-08-12 사용자 지시). 이미 오늘 물을 준 칸도 "water"를 그대로 돌려준다
## - 다시 줘도 막지 않되(사용자 지시), 실제 급수 횟수 중복 반영은
## perform_water()에서 따로 막는다(하루 1번 성장 판정은 유지).
func get_available_action(world_position: Vector2) -> String:
	if _world_map == null or not _world_map.is_farmable_cell(world_position):
		return ""
	var cell := _world_to_cell(world_position)
	var equipped := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	if not _plots.has(cell):
		if equipped == "hoe":
			return "till"
		if equipped == "watering_can":
			return "needs_till"
		return ""
	var plot: Dictionary = _plots[cell]
	if _is_grown(plot):
		return "harvest"
	if equipped == "watering_can":
		return "water"
	if _seed_to_crop.has(equipped) and String(plot.get("crop_type", "")).is_empty():
		return "plant"
	## 이미 갈아둔 빈 땅(작물 없음)에 괭이를 다시 쓰면 맨땅으로 되돌린다(사용자
	## 지시, 2026-08-24 - "괭이질 한번 더 하면 맨땅으로 돌아가게 해줘"). 작물이
	## 심어져 있으면(crop_type 비어있지 않음) 여기 안 걸리므로 실수로 작물을
	## 갈아엎을 일은 없다.
	if equipped == "hoe" and String(plot.get("crop_type", "")).is_empty():
		return "untill"
	return ""


func _is_grown(plot: Dictionary) -> bool:
	var crop_type := String(plot.get("crop_type", ""))
	if crop_type.is_empty():
		return false
	return _stage_for(crop_type, int(plot.get("display_watered_count", 0))) == "grown"


func perform_till(world_position: Vector2) -> String:
	if get_available_action(world_position) != "till":
		return ""
	var cell := _world_to_cell(world_position)
	# 비 오는 날 새로 간 경작지는 그 즉시 젖은 상태로 시작해야 한다 - 기존
	# 칸들은 하루가 시작될 때(_on_weather_changed) 이미 젖어있게 처리되지만,
	# 이 칸은 그 시점 이후(당일 중)에 새로 생겨서 그 처리를 못 받았기 때문.
	_plots[cell] = {"watered_today": WeatherManager.is_raining(), "crop_type": "", "watered_count": 0, "display_watered_count": 0}
	_spawn_plot_sprites(cell)
	AudioManager.play_sfx(AudioManager.SFX_DIGGING)
	# 마른/젖은 흙 그림이 바로 보이니 별도 문구 없이 조용히 처리한다(사용자 지시).
	return ""


## get_available_action()이 "untill"을 돌려줄 때만(이미 갈아둔 빈 땅 + 괭이
## 장착) 호출된다 - perform_till()과 반대 방향, 맨땅으로 되돌린다.
func perform_untill(world_position: Vector2) -> String:
	if get_available_action(world_position) != "untill":
		return ""
	var cell := _world_to_cell(world_position)
	_despawn_plot_sprites(cell)
	_plots.erase(cell)
	AudioManager.play_sfx(AudioManager.SFX_DIGGING)
	return ""


## 오늘 이미 물을 준 칸이어도 다시 물을 줄 수 있다(사용자 지시, 2026-08-12) -
## 다만 성장에 반영되는 건 하루 첫 급수뿐이라, watered_count는 그 경우에만
## 올린다(급수 무제한 반복으로 하루 만에 다 자라는 걸 막기 위한 기존 규칙 유지).
func perform_water(world_position: Vector2) -> String:
	if get_available_action(world_position) != "water":
		return ""
	var cell := _world_to_cell(world_position)
	var plot: Dictionary = _plots[cell]
	var first_watering_today := not bool(plot.get("watered_today", false))
	plot["watered_today"] = true
	if first_watering_today and not String(plot.get("crop_type", "")).is_empty():
		plot["watered_count"] = int(plot.get("watered_count", 0)) + 1
	_update_plot_sprites(cell)
	AudioManager.play_sfx(AudioManager.SFX_WATERING_CAN)
	# 젖은 흙 그림이 바로 보이니 별도 문구 없이 조용히 처리한다(사용자 지시).
	return ""


## 심는 시점에 이미 오늘 물 준(젖은) 경작지면 급수 1번을 이미 받은 것으로
## 친다(사용자 확정) - 같은 날 또 물 줄 수는 없으니(하루 1번 제한) 자연스럽게
## 맞물린다.
func perform_plant(world_position: Vector2) -> String:
	var equipped := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	if get_available_action(world_position) != "plant":
		return ""
	var cell := _world_to_cell(world_position)
	var plot: Dictionary = _plots[cell]
	plot["crop_type"] = String(_seed_to_crop.get(equipped, ""))
	plot["watered_count"] = 1 if bool(plot.get("watered_today", false)) else 0
	# display_watered_count는 항상 0부터(사용자 지시 - 젖은 흙에 심어서 실제
	# watered_count가 1로 시작해도 그림은 씨앗부터, 다음 날짜 전환에 따라잡음).
	plot["display_watered_count"] = 0
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_update_plot_sprites(cell)
	AudioManager.play_sfx(AudioManager.SFX_HARVEST)
	# 씨앗 그림이 바로 그 자리에 보이니 별도 문구 없이 조용히 처리한다(사용자 지시).
	return ""


## main.gd가 "E 수확" 프롬프트를 아예 숨길지 판단하는 데 쓴다(사용자 지시 -
## 인벤토리 가득 차면 상호작용 자체 차단).
func can_harvest(world_position: Vector2) -> bool:
	var cell := _world_to_cell(world_position)
	if not _plots.has(cell):
		return false
	var plot: Dictionary = _plots[cell]
	if not _is_grown(plot):
		return false
	var definition: Dictionary = _crops.get(String(plot.get("crop_type", "")), {})
	return InventoryManager.can_add_item(String(definition.get("produce_item_id", "")), int(definition.get("produce_count", 0)))


func perform_harvest(world_position: Vector2) -> String:
	if get_available_action(world_position) != "harvest":
		return ""
	var cell := _world_to_cell(world_position)
	var plot: Dictionary = _plots[cell]
	var crop_type := String(plot.get("crop_type", ""))
	var definition: Dictionary = _crops.get(crop_type, {})
	var produce_item_id := String(definition.get("produce_item_id", ""))
	var produce_count := int(definition.get("produce_count", 0))
	if not InventoryManager.add_item(produce_item_id, produce_count):
		return "인벤토리가 가득 찼다."
	# 경작지는 유지하고 바로 재파종 가능하게 비운다(사용자 확정 - 다시 괭이질 불필요).
	plot["crop_type"] = ""
	plot["watered_count"] = 0
	plot["display_watered_count"] = 0
	_update_plot_sprites(cell)
	AudioManager.play_sfx(AudioManager.SFX_ITEM_PICKING)
	return "%s을(를) 수확했다." % String(definition.get("name", "작물"))


## 매일 날씨가 정해질 때마다(비오는 날 포함, 09:00 취침/자정 기준) 발생하는
## WeatherManager.weather_changed에 맞춰 하루치 급수 상태를 갱신한다.
## TimeManager.day_changed가 아니라 이 신호를 쓰는 이유: WeatherManager도
## day_changed를 구독해서 그 안에서 날씨를 다시 굴리므로(weather_manager.gd),
## 오토로드 로드 순서에 의존하지 않고 항상 "그날 날씨가 이미 정해진 뒤"에
## 반응하려면 weather_changed가 안전하다.
## 순서가 중요하다(사용자 확정 - 작물 그림은 물 준 당일이 아니라 다음 날짜
## 전환에야 바뀜): 1) 어제까지의 watered_count를 display_watered_count로
## 따라잡혀서(=그림 갱신) 어제 한 급수가 오늘 아침 비로소 반영됨 2) 그 다음에
## 오늘치 급수(비 자동급수 포함)를 watered_count에 적용 - 이 순서를 지켜야
## "비가 와서 오늘 막 채운" 급수가 오늘 바로 그림에 반영되는 걸 막을 수 있다.
func _on_weather_changed(_weather: WeatherManager.Weather) -> void:
	for cell in _plots:
		var plot: Dictionary = _plots[cell]
		if not String(plot.get("crop_type", "")).is_empty():
			plot["display_watered_count"] = int(plot.get("watered_count", 0))
	var raining := WeatherManager.is_raining()
	for cell in _plots:
		var plot: Dictionary = _plots[cell]
		plot["watered_today"] = raining
		if raining and not String(plot.get("crop_type", "")).is_empty():
			plot["watered_count"] = int(plot.get("watered_count", 0)) + 1
		_update_plot_sprites(cell)


## main.gd가 맵을 옮길 때마다 호출한다(LivestockManager.set_world_map()과
## 완전히 같은 패턴) - 먼저 기존 스프라이트를 전부 지우고, Home 맵이면
## _plots에 있는 칸만 다시 그린다.
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	for cell in _plots.keys():
		_despawn_plot_sprites(cell)
	_world_map = world_map
	if map_id != FARM_MAP_ID:
		return
	for cell in _plots.keys():
		_spawn_plot_sprites(cell)


func get_save_data() -> Dictionary:
	var plots: Dictionary = {}
	for cell in _plots:
		plots["%d,%d" % [cell.x, cell.y]] = (_plots[cell] as Dictionary).duplicate()
	return {"plots": plots}


func load_save_data(data: Dictionary) -> void:
	_plots.clear()
	var saved: Dictionary = data.get("plots", {})
	for key in saved:
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		_plots[cell] = (saved[key] as Dictionary).duplicate()


## watered_count는 항상 display_watered_count를 넘겨받아야 한다(호출부 참고)
## - 실시간 watered_count를 바로 넘기면 물 준 당일에 그림이 바뀌어버린다.
func _stage_for(crop_type: String, watered_count: int) -> String:
	var required := int(_crops.get(crop_type, {}).get("waterings_required", 0))
	if watered_count >= required:
		return "grown"
	if watered_count >= SPROUT_MIN_WATERINGS:
		return "sprout"
	return "seed"


func _spawn_plot_sprites(cell: Vector2i) -> void:
	if _world_map == null or GameManager.current_map_id != FARM_MAP_ID:
		return
	_despawn_plot_sprites(cell)
	var soil := Sprite2D.new()
	soil.texture = _crop_frame_texture(_soil_frame_index(cell))
	soil.position = _cell_to_world(cell)
	soil.z_index = WorldMap.FLAT_Z_INDEX
	soil.add_to_group(&"_farm_plot_sprite")
	_world_map.add_child(soil)
	_soil_sprites[cell] = soil
	_update_crop_sprite(cell)


func _update_plot_sprites(cell: Vector2i) -> void:
	if not _soil_sprites.has(cell):
		_spawn_plot_sprites(cell)
		return
	(_soil_sprites[cell] as Sprite2D).texture = _crop_frame_texture(_soil_frame_index(cell))
	_update_crop_sprite(cell)


func _update_crop_sprite(cell: Vector2i) -> void:
	var plot: Dictionary = _plots.get(cell, {})
	var crop_type := String(plot.get("crop_type", ""))
	if crop_type.is_empty():
		if _crop_sprites.has(cell):
			(_crop_sprites[cell] as Sprite2D).queue_free()
			_crop_sprites.erase(cell)
		return
	if not _crop_sprites.has(cell):
		var sprite := Sprite2D.new()
		sprite.position = _cell_to_world(cell)
		sprite.z_index = WorldMap.FLAT_Z_INDEX
		sprite.add_to_group(&"_farm_plot_sprite")
		_world_map.add_child(sprite)
		_crop_sprites[cell] = sprite
	var frame := _crop_frame_index(crop_type, int(plot.get("display_watered_count", 0)))
	(_crop_sprites[cell] as Sprite2D).texture = _crop_frame_texture(frame)


func _despawn_plot_sprites(cell: Vector2i) -> void:
	if _soil_sprites.has(cell):
		(_soil_sprites[cell] as Sprite2D).queue_free()
		_soil_sprites.erase(cell)
	if _crop_sprites.has(cell):
		(_crop_sprites[cell] as Sprite2D).queue_free()
		_crop_sprites.erase(cell)


func _soil_frame_index(cell: Vector2i) -> int:
	var plot: Dictionary = _plots.get(cell, {})
	return SOIL_WET_INDEX if bool(plot.get("watered_today", false)) else SOIL_DRY_INDEX


func _crop_frame_index(crop_type: String, display_watered_count: int) -> int:
	var stage := _stage_for(crop_type, display_watered_count)
	return int(_crops.get(crop_type, {}).get("sprite_index", {}).get(stage, 0))


func _crop_frame_texture(frame_index: int) -> Texture2D:
	if not ResourceLoader.exists(CROP_SPRITE_SHEET):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(CROP_SPRITE_SHEET)
	atlas.region = Rect2(frame_index * CROP_SPRITE_SIZE, 0, CROP_SPRITE_SIZE, CROP_SPRITE_SIZE)
	return atlas


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x) / WorldMap.TILE_SIZE, int(world_position.y) / WorldMap.TILE_SIZE)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * WorldMap.TILE_SIZE + Vector2.ONE * WorldMap.TILE_SIZE * 0.5


func _load_crops() -> void:
	var file := FileAccess.open(CROPS_PATH, FileAccess.READ)
	if file == null:
		push_error("Crop catalog could not be opened: %s" % CROPS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Crop catalog is not valid JSON: %s" % CROPS_PATH)
		return
	_crops = parsed
	_seed_to_crop.clear()
	for crop_type in _crops:
		var seed_id := String(_crops[crop_type].get("seed_item_id", ""))
		if not seed_id.is_empty():
			_seed_to_crop[seed_id] = crop_type
