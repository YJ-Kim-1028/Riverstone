extends Node

## 외양간(cowshed_interior) 4칸의 소/돼지를 관리한다. 목장가게(belje_shop)에서
## ShopManager.buy("livestock:cow"/"livestock:pig", stall_index)로 배치되고,
## 손(EquipmentManager.HAND_SLOT)에 무엇을 장착했는지에 따라 상호작용 결과가
## 달라진다 - 여물이면 급여(성체/아기 공통, 게임 날짜 기준 1일 1회), 양동이면
## 착유(성체 소 전용, 1일 1회, 오늘 급여를 마쳐야 가능), 작은 칼이면 도살(성체
## 전용, 아기에겐 안 먹힘 - 고기 획득 + 칸 비움, 확인 팝업을 거쳐야 하므로
## main.gd가 get_slaughter_request()로 진행 가능 여부/문구를 받는다). 돼지는
## 정기 생산물이 없고 도살로만 고기를 얻는다(사용자 확정).
## 성장(사용자 지시): 날짜 경과가 아니라 "실제로 여물을 먹은 횟수"로 큰다 -
## 여물이 하루 1번만 가능하므로 결과적으로 최소 며칠은 걸리지만, 하루를
## 걸러서 못 먹이면 그만큼 늦어진다. animals.json의 growth_feedings번 먹으면
## 성체(소 5번, 돼지 4번) - 그 전까지는 아기로 취급되어 착유/도살이
## 불가능하고, 스프라이트도 animal.png의 아기 칸(2/3번째 - 사용자 지시)으로
## 그려진다.

signal stalls_changed

const ANIMALS_PATH := "res://data/animals/animals.json"
const STALL_COUNT := 4
## Spawn 오브젝트 레이어에 이미 있는 4칸 좌표(cowshed_interior.tmx) - 순서대로
## 0~3번 칸에 대응시킨다.
const STALL_SPAWN_NAMES := ["spot1", "spot2", "spot3", "spot4"]
const COWSHED_MAP_ID := "cowshed_interior"
## NPC 대화 판정(TALK_RADIUS=24)과 같은 크기 - 동물도 다가가면 상호작용 가능.
const ANIMAL_INTERACT_RADIUS := 24.0

## 사용자가 assets/img/cowshed/animal.png에 32x32 칸으로 그려준 시트 - 1번째
## 칸이 성체 소, 2번째가 성체 돼지, 3번째가 아기 소, 4번째가 아기 돼지(사용자
## 지시). items.json의 icon_index 슬라이싱, home_map.gd의 타일 아틀라스
## 슬라이싱과 같은 방식으로 파일을 자르지 않고 그대로 칸만 잘라 쓴다. 이
## 파일이 없으면(아직 안 그려짐) 조용히 아래 자리표시용 색 사각형으로 대체한다.
const ANIMAL_SPRITE_SHEET := "res://assets/img/cowshed/animal.png"
const ANIMAL_SPRITE_SIZE := 32
const ANIMAL_SPRITE_COLUMNS_ADULT := {
	"cow": 0,
	"pig": 1,
}
const ANIMAL_SPRITE_COLUMNS_BABY := {
	"cow": 2,
	"pig": 3,
}
## 위 시트가 아직 없을 때만 쓰는 자리표시 색 사각형.
const PLACEHOLDER_COLORS := {
	"cow": Color(0.95, 0.95, 0.95),
	"pig": Color(0.95, 0.75, 0.78),
}
const PLACEHOLDER_SIZE := 16

var _animals: Dictionary = {}
## index 0~3 -> {} (비어있음) 또는 {"type": "cow"/"pig", "fed_day": int,
## "milked_day": int, "fed_count": int(성장 판정용 - 실제로 먹인 횟수), "placed_day": int}
var _stalls: Array = [{}, {}, {}, {}]

var _world_map: WorldMap = null
var _sprites: Array = [null, null, null, null]
## 여물통 표시 전담(사용자 지시, 2026-09-05) - livestock_trough.gd 참고.
var _trough := LivestockTrough.new()


func _ready() -> void:
	_load_animals()
	TimeManager.day_changed.connect(_on_day_changed)


## Home에 계속 서서 밤을 넘기는 경우의 무덤(Grave)과 같은 이유 - 외양간에 계속
## 있다가 자정을 넘기는 드문 경우에도 여물통이 바로 반영되게 한다. 평소에는
## set_world_map()이 재입장할 때마다 fed_day를 새 날짜와 비교해 알아서 다시
## 맞춰지므로 이 훅이 없어도 다음 방문 때는 정상 동작한다.
func _on_day_changed(_day: int, _weekday: String) -> void:
	if _world_map != null and GameManager.current_map_id == COWSHED_MAP_ID:
		_trough.apply_state(_world_map, STALL_COUNT, _stalls)


func get_animal_definition(animal_type: String) -> Dictionary:
	return _animals.get(animal_type, {})


func get_stall(stall_index: int) -> Dictionary:
	if not _is_valid_index(stall_index):
		return {}
	return (_stalls[stall_index] as Dictionary).duplicate()


func is_stall_empty(stall_index: int) -> bool:
	return not _is_valid_index(stall_index) or (_stalls[stall_index] as Dictionary).is_empty()


func get_empty_stall_indices() -> Array:
	var result: Array = []
	for i in STALL_COUNT:
		if is_stall_empty(i):
			result.append(i)
	return result


## ShopManager._buy_livestock()가 결제 확인 후 호출한다. 항상 아기 상태로
## 시작한다(fed_count=0부터 - is_adult()가 growth_feedings번 먹었는지로 판정).
func place_animal(stall_index: int, animal_type: String) -> bool:
	if not _is_valid_index(stall_index) or not is_stall_empty(stall_index) or not _animals.has(animal_type):
		return false
	_stalls[stall_index] = {
		"type": animal_type,
		"fed_day": -1,
		"milked_day": -1,
		"fed_count": 0,
		"placed_day": TimeManager.current_day,
	}
	_spawn_sprite(stall_index)
	stalls_changed.emit()
	return true


## 여물을 animals.json의 growth_feedings번 먹었는지 - 그 전까지는 아기.
func is_adult(stall_index: int) -> bool:
	if is_stall_empty(stall_index):
		return false
	var stall: Dictionary = _stalls[stall_index]
	var required := int(get_animal_definition(String(stall.get("type", ""))).get("growth_feedings", 0))
	return int(stall.get("fed_count", 0)) >= required


## 결제 실패 롤백 전용(ShopManager) - 도살과 달리 고기를 주지 않고 그냥 비운다.
func remove_animal(stall_index: int) -> void:
	if not _is_valid_index(stall_index):
		return
	_stalls[stall_index] = {}
	_despawn_sprite(stall_index)
	stalls_changed.emit()


## 지금 손에 든 도구로 이 칸에서 뭘 할 수 있는지 - "feed"/"milk"/"slaughter"/""
## (main.gd가 상호작용 프롬프트 문구를 정하는 데도 쓴다).
func get_equipped_action(stall_index: int) -> String:
	if is_stall_empty(stall_index):
		return ""
	match EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT):
		"animal_feed":
			return "feed"
		"bucket":
			var milk_item_id := String(get_animal_definition(String(_stalls[stall_index].get("type", ""))).get("milk_item_id", ""))
			return "milk" if not milk_item_id.is_empty() else "milk_wrong_animal"
		"small_knife":
			return "slaughter"
		_:
			return ""


## main.gd가 착유/도살 프롬프트를 인벤토리 여유 공간으로 숨길지 판단하는 데
## 쓴다(사용자 지시 - 인벤토리가 가득 차면 상호작용 자체를 아예 막는다).
## feed 등 인벤토리 소모가 없는 액션은 항상 true.
func can_perform_action(stall_index: int) -> bool:
	var action := get_equipped_action(stall_index)
	if action != "milk" and action != "slaughter":
		return true
	var definition := get_animal_definition(String(_stalls[stall_index].get("type", "")))
	var item_id := String(definition.get("milk_item_id" if action == "milk" else "meat_item_id", ""))
	if item_id.is_empty():
		return true
	return InventoryManager.can_add_item(item_id, 1)


## 여물 급여 - 성공/실패 여부와 무관하게 안내 문구를 돌려준다(main.gd가 그대로
## 머리 위 메시지로 띄운다). 하루 1번(게임 날짜 기준)만 가능.
func perform_feed(stall_index: int) -> String:
	if get_equipped_action(stall_index) != "feed":
		return ""
	var stall: Dictionary = _stalls[stall_index]
	if int(stall.get("fed_day", -1)) == TimeManager.current_day:
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("오늘은 이미 먹이를 줬다.")
	stall["fed_day"] = TimeManager.current_day
	# 성장 판정은 날짜 경과가 아니라 실제로 먹인 횟수 기준(사용자 지시) - 이
	# 급여로 막 성체가 됐을 수도 있으니 스프라이트를 바로 다시 그린다(전에는
	# 하루가 바뀔 때만 갱신했는데, 이제 성장 시점이 자정이 아니라 이 순간이라
	# 그래야 즉시 반영된다).
	stall["fed_count"] = int(stall.get("fed_count", 0)) + 1
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_spawn_sprite(stall_index)
	_trough.set_fed(_world_map, stall_index, true)
	stalls_changed.emit()
	AudioManager.play_sfx(AudioManager.SFX_FEEDING)
	match String(stall.get("type", "")):
		"cow":
			AudioManager.play_sfx(AudioManager.SFX_COW)
		"pig":
			AudioManager.play_sfx(AudioManager.SFX_PIG)
	return tr("맛있게 먹어.")


## 착유(성체 소 전용) - 오늘 먼저 먹이를 줘야 하고, 하루 1번만 가능.
func perform_milk(stall_index: int) -> String:
	if get_equipped_action(stall_index) != "milk":
		return ""
	if not is_adult(stall_index):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("아직 아기라 짤 수 없다.")
	var stall: Dictionary = _stalls[stall_index]
	if int(stall.get("fed_day", -1)) != TimeManager.current_day:
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("오늘 먼저 먹이를 줘야 한다.")
	if int(stall.get("milked_day", -1)) == TimeManager.current_day:
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("오늘은 이미 짰다.")
	var milk_item_id := String(get_animal_definition(String(stall.get("type", ""))).get("milk_item_id", ""))
	if not InventoryManager.add_item(milk_item_id, 1):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("인벤토리가 가득 찼다.")
	stall["milked_day"] = TimeManager.current_day
	stalls_changed.emit()
	AudioManager.play_sfx(AudioManager.SFX_ITEM_PICKING)
	return tr("우유를 얻었다.")


## main.gd가 작은 칼로 상호작용할 때 호출한다 - 도살 액션이 아니면 빈
## Dictionary(아무 반응도 안 함). 아기(아직 성체가 아님)면 즉시 거부 문구를
## {"denied": true, "message": ...}로 돌려주고(확인 팝업 없이 바로 안내만),
## 성체면 {"denied": false, "message": ...}를 돌려준다 - main.gd는 denied=false일
## 때 확인 팝업 없이 바로 도살한다(모든 동물 공통, 사용자 지시).
func get_slaughter_request(stall_index: int) -> Dictionary:
	if get_equipped_action(stall_index) != "slaughter":
		return {}
	var definition := get_animal_definition(String(_stalls[stall_index].get("type", "")))
	var animal_name := String(definition.get("name", tr("동물")))
	if not is_adult(stall_index):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return {"denied": true, "message": tr("이런 짓을 하기엔 너무 어리다.")}
	return {
		"denied": false,
		"message": tr("%s를 정말 도살하시겠습니까? 되돌릴 수 없습니다.") % animal_name,
	}


## 확인 팝업에서 "예"를 누른 뒤 main.gd가 호출한다 - 고기를 얻고 칸을 비운다.
func perform_slaughter(stall_index: int) -> String:
	if not _is_valid_index(stall_index) or is_stall_empty(stall_index):
		return ""
	if not is_adult(stall_index):
		return ""
	var definition := get_animal_definition(String(_stalls[stall_index].get("type", "")))
	var meat_item_id := String(definition.get("meat_item_id", ""))
	var meat_count := int(definition.get("meat_count", 1))
	if not meat_item_id.is_empty() and not InventoryManager.add_item(meat_item_id, meat_count):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("인벤토리가 가득 찼다.")
	var animal_name := String(definition.get("name", tr("동물")))
	remove_animal(stall_index)
	if not meat_item_id.is_empty():
		AudioManager.play_sfx(AudioManager.SFX_ITEM_PICKING)
	return tr("%s에게서 고기를 얻었다.") % animal_name


## main.gd가 맵을 옮길 때마다 호출한다(AudioManager.set_world_map()과 같은
## 패턴). **반드시 먼저 기존 스프라이트를 _despawn_sprite()로 지워야 한다** -
## Player/타일과 마찬가지로 소/돼지 스프라이트도 WorldMap(HomeMap) 노드의
## 직접 자식으로 붙는데, 이 노드는 맵이 바뀌어도 재생성되지 않고
## world_map.load_map()으로 내용만 바뀐다(_clear_tiles()는 "_map_tile"
## 그룹만 지우므로 이 스프라이트는 그 대상이 아니다). 예전엔 여기서 배열
## 참조만 비웠더니 실제 노드가 안 지워져서, 외양간을 나가도 소/돼지가 다음
## 맵(집 등)까지 계속 보이는 버그가 있었다.
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	for i in STALL_COUNT:
		_despawn_sprite(i)
	_world_map = world_map
	if map_id != COWSHED_MAP_ID:
		return
	for i in STALL_COUNT:
		if not is_stall_empty(i):
			_spawn_sprite(i)
	_trough.refresh_for_map(world_map, map_id, STALL_SPAWN_NAMES, STALL_COUNT, _stalls)


## 외양간 안에서 플레이어 위치 기준 상호작용 가능한(동물이 있는) 가장 가까운
## 칸 - NPC 대화의 _nearest_talkable_npc()와 같은 역할.
func get_nearest_stall(position: Vector2, current_map_id: String) -> Dictionary:
	if current_map_id != COWSHED_MAP_ID or _world_map == null:
		return {}
	var best_index := -1
	var best_distance := INF
	for i in STALL_COUNT:
		if is_stall_empty(i):
			continue
		var stall_position: Vector2 = _world_map.get_spawn_position(STALL_SPAWN_NAMES[i])
		if stall_position == Vector2.INF:
			continue
		var distance := position.distance_to(stall_position)
		if distance <= ANIMAL_INTERACT_RADIUS and distance < best_distance:
			best_distance = distance
			best_index = i
	if best_index == -1:
		return {}
	return {"stall_index": best_index, "distance": best_distance}


func get_save_data() -> Dictionary:
	return {"stalls": _stalls.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	var saved: Array = data.get("stalls", [])
	_stalls = [{}, {}, {}, {}]
	for i in mini(saved.size(), STALL_COUNT):
		_stalls[i] = (saved[i] as Dictionary).duplicate(true)
	stalls_changed.emit()


## 목장가게 상점 목록(shop_screen.gd)도 이걸로 아이콘을 그린다(항상 구매
## 직후 상태인 아기 칸을 보여준다) - 시트가 아직 없으면 자리표시 색 사각형을
## 돌려준다(_spawn_sprite와 동일한 폴백).
func get_animal_icon_texture(animal_type: String, is_adult_stage: bool) -> Texture2D:
	var columns: Dictionary = ANIMAL_SPRITE_COLUMNS_ADULT if is_adult_stage else ANIMAL_SPRITE_COLUMNS_BABY
	if columns.has(animal_type) and ResourceLoader.exists(ANIMAL_SPRITE_SHEET):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(ANIMAL_SPRITE_SHEET)
		atlas.region = Rect2(int(columns[animal_type]) * ANIMAL_SPRITE_SIZE, 0, ANIMAL_SPRITE_SIZE, ANIMAL_SPRITE_SIZE)
		return atlas
	var image := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(PLACEHOLDER_COLORS.get(animal_type, Color.WHITE))
	return ImageTexture.create_from_image(image)


func _is_valid_index(stall_index: int) -> bool:
	return stall_index >= 0 and stall_index < STALL_COUNT


func _spawn_sprite(stall_index: int) -> void:
	if _world_map == null or GameManager.current_map_id != COWSHED_MAP_ID:
		return
	_despawn_sprite(stall_index)
	var position: Vector2 = _world_map.get_spawn_position(STALL_SPAWN_NAMES[stall_index])
	if position == Vector2.INF:
		return
	var animal_type := String(_stalls[stall_index].get("type", ""))
	var sprite := Sprite2D.new()
	sprite.texture = get_animal_icon_texture(animal_type, is_adult(stall_index))
	sprite.position = position
	# home_map.gd가 맵 타일을 "_map_tile" 그룹으로 태그해서 자기 타일만 구분해
	# 지우는 것과 같은 이유 - 이 스프라이트도 구분 태그가 있어야 나중에 다른
	# 코드(디버그/테스트 등)가 맵 타일과 안 헷갈리고 찾을 수 있다.
	sprite.add_to_group(&"_livestock_sprite")
	_world_map.add_child(sprite)
	_sprites[stall_index] = sprite
	# 사용자가 animal.tsx에 소/돼지 칸을 전부 collision=true로 표시해뒀지만,
	# 이 스프라이트는 TileSet이 아니라 잘라 붙인 그림이라 그 설정이 자동
	# 적용되지 않는다 - 같은 32x32 범위를 WorldMap 충돌 칸으로 직접 등록해서
	# 실제로 그 자리를 막는다.
	_world_map.set_area_blocked(position, Vector2(ANIMAL_SPRITE_SIZE, ANIMAL_SPRITE_SIZE), true)


func _despawn_sprite(stall_index: int) -> void:
	var sprite: Node = _sprites[stall_index]
	if sprite != null:
		sprite.queue_free()
		_sprites[stall_index] = null
	if _world_map == null:
		return
	var position: Vector2 = _world_map.get_spawn_position(STALL_SPAWN_NAMES[stall_index])
	if position != Vector2.INF:
		_world_map.set_area_blocked(position, Vector2(ANIMAL_SPRITE_SIZE, ANIMAL_SPRITE_SIZE), false)


func _load_animals() -> void:
	var file := FileAccess.open(ANIMALS_PATH, FileAccess.READ)
	if file == null:
		push_error("Animal catalog could not be opened: %s" % ANIMALS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Animal catalog is not valid JSON: %s" % ANIMALS_PATH)
		return
	_animals = Localizer.apply_language(parsed, ANIMALS_PATH) as Dictionary


## 언어 변경 시 language_settings_screen.gd가 호출한다.
func reload_for_language() -> void:
	_load_animals()
