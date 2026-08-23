extends Node

## 바닥에 까는 장식(러그 등). furniture_manager.gd의 구조를 그대로 베낀 병렬
## 구조 - 상속/공유 베이스 없이 따로 둔다(FurnitureManager/StorageBoxManager와
## 동일한 관례, 사용자 지시).
##
## FurnitureManager와 다른 점: 가구/이동을 막지 않는다(러그를 깔아도 그 위에
## 가구를 놓을 수 있고, 플레이어도 밟고 지나다닐 수 있어야 함 - 사용자 확정).
## 그래서 배치 성공 시에도 WorldMap.set_area_blocked()를 절대 호출하지 않고,
## 겹침 판정(has_floor_decor_overlap)도 FurnitureManager의 _furniture와는
## 완전히 별개인 자기 Dictionary끼리만 비교한다(가구와는 겹쳐도 됨). 다만
## 벽/물처럼 원래부터 막혀있는 칸(WorldMap._blocked_cells)에는 못 깔게
## is_area_blocked()는 읽기 전용으로 그대로 검사한다.
##
## 설치 가능한 맵: FurnitureManager.ALLOWED_MAP_IDS를 그대로 참조한다(마당+집
## 내부, 사용자가 "가구·바닥장식 둘 다"라고 확정한 범위가 두 매니저 사이에서
## 드리프트되지 않도록).

const FLOOR_DECOR_INTERACT_RADIUS := 20.0
const PLACEHOLDER_COLOR := Color(0.5, 0.5, 0.5)
## 같은 칸의 가구보다 항상 아래에 그려지도록(Y-sort 동률 문제 회피) - Godot은
## z_index가 다르면 y_sort보다 z_index를 우선하므로, 가구(기본 z_index 0)보다
## 낮은 값을 주면 항상 밑에 깔린다.
const SPRITE_Z_INDEX := -1

signal floor_decor_changed

## map_id(String) -> { anchor_cell(Vector2i) -> {"item_id": String} }
var _decor: Dictionary = {}

var _world_map: WorldMap = null
var _current_map_id := ""
## anchor_cell(Vector2i) -> Sprite2D, 현재 로드된 맵에 속한 바닥장식만.
var _sprites: Dictionary = {}
## item_id(색상 합성 id 포함) -> 리컬러된 Texture2D. _recolored_texture() 참고.
var _recolor_cache: Dictionary = {}


func get_footprint(item_id: String) -> Vector2i:
	var definition := InventoryManager.get_item_definition(item_id)
	return Vector2i(maxi(int(definition.get("footprint_width", 1)), 1), maxi(int(definition.get("footprint_height", 1)), 1))


## main.gd가 설치 미리보기 스프라이트에 쓴다.
func get_preview_texture(item_id: String) -> Texture2D:
	return _decor_texture(item_id)


func can_place_floor_decor(item_id: String, world_position: Vector2) -> bool:
	if _world_map == null or not FurnitureManager.is_placement_allowed(_current_map_id):
		return false
	var footprint := get_footprint(item_id)
	return not _world_map.is_area_blocked(world_position, Vector2(footprint) * WorldMap.TILE_SIZE)


func has_floor_decor_overlap(map_id: String, anchor_cell: Vector2i, footprint: Vector2i) -> bool:
	var target := Rect2i(anchor_cell, footprint)
	for existing_cell in (_decor.get(map_id, {}) as Dictionary):
		var existing_item_id := String((_decor[map_id] as Dictionary)[existing_cell].get("item_id", ""))
		var existing_rect := Rect2i(existing_cell, get_footprint(existing_item_id))
		if target.intersects(existing_rect):
			return true
	return false


## EquipmentManager.HAND_SLOT에 category=="floor_decor" 아이템이 장착돼 있어야
## 하고, FurnitureManager.ALLOWED_MAP_IDS 위여야 하고, 대상 영역이 원래부터
## 막힌 칸(벽/물 등)이 아니고 다른 바닥장식과 겹치지 않아야 한다 - 가구와는
## 겹쳐도 된다(그 검사는 애초에 하지 않음). 성공하면 빈 문자열, 실패하면
## main.gd가 _show_temporary_message()로 그대로 표시할 한글 메시지를
## 반환한다(furniture_manager.gd와 동일한 관례).
func place_floor_decor(world_position: Vector2) -> String:
	var item_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	if InventoryManager.get_item_category(item_id) != "floor_decor":
		return ""
	if _world_map == null:
		return ""
	if not FurnitureManager.is_placement_allowed(_current_map_id):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "집 안이나 마당에서만 깔 수 있다."
	var footprint := get_footprint(item_id)
	var anchor_cell := _world_to_anchor_cell(world_position, footprint)
	if has_floor_decor_overlap(_current_map_id, anchor_cell, footprint):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "이미 깔려 있다."
	if not can_place_floor_decor(item_id, world_position):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "이 곳에는 깔 수 없다."
	if not _decor.has(_current_map_id):
		_decor[_current_map_id] = {}
	(_decor[_current_map_id] as Dictionary)[anchor_cell] = {"item_id": item_id}
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_spawn_sprite(anchor_cell, item_id)
	AudioManager.play_sfx(AudioManager.SFX_UI_SLOT_IN)
	floor_decor_changed.emit()
	return ""


## 내부 슬롯이 없어서(가구와 동일) "비어있어야" 조건이 없다 - 항상 바로
## 회수 가능. 애초에 이동/설치를 막은 적이 없으므로 set_area_blocked()로
## 되돌릴 것도 없다(FurnitureManager.remove_furniture()와의 유일한 차이).
func remove_floor_decor(map_id: String, anchor_cell: Vector2i) -> String:
	if not (_decor.get(map_id, {}) as Dictionary).has(anchor_cell):
		return ""
	var item_id := String((_decor[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
	if not InventoryManager.can_add_item(item_id, 1):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "인벤토리가 가득 찼다."
	InventoryManager.add_item(item_id, 1)
	(_decor[map_id] as Dictionary).erase(anchor_cell)
	if map_id == _current_map_id:
		_despawn_sprite(anchor_cell)
	floor_decor_changed.emit()
	return ""


## 바닥장식은 이동을 막지 않아 플레이어가 위에 설 수 있으므로, 가구와 달리
## "칸 안에 서 있어도" 항상 사각형 경계까지의 거리가 0으로 잡혀 자연스럽게
## 인식된다(FurnitureManager.get_nearest_furniture()와 동일한 거리 기반
## 최근접 패턴).
func get_nearest_floor_decor(position: Vector2, current_map_id: String) -> Dictionary:
	if _world_map == null or not _decor.has(current_map_id):
		return {}
	var best_cell := Vector2i.MAX
	var best_distance := INF
	for anchor_cell in (_decor[current_map_id] as Dictionary):
		var item_id := String((_decor[current_map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		var footprint := get_footprint(item_id)
		var rect := Rect2(Vector2(anchor_cell) * WorldMap.TILE_SIZE, Vector2(footprint) * WorldMap.TILE_SIZE)
		var closest := Vector2(clampf(position.x, rect.position.x, rect.end.x), clampf(position.y, rect.position.y, rect.end.y))
		var distance := position.distance_to(closest)
		if distance <= FLOOR_DECOR_INTERACT_RADIUS and distance < best_distance:
			best_distance = distance
			best_cell = anchor_cell
	if best_cell == Vector2i.MAX:
		return {}
	return {"anchor_cell": best_cell, "distance": best_distance}


## furniture_manager.gd의 get_light_source_positions()와 완전히 동일한 패턴.
func get_light_source_positions(map_id: String) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for anchor_cell in (_decor.get(map_id, {}) as Dictionary):
		var item_id := String((_decor[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		if not bool(InventoryManager.get_item_definition(item_id).get("emits_light", false)):
			continue
		var footprint := get_footprint(item_id)
		positions.append(Vector2(anchor_cell.x + footprint.x / 2.0, anchor_cell.y + 0.5) * WorldMap.TILE_SIZE)
	return positions


## main.gd가 맵을 옮길 때마다 호출한다(furniture_manager.gd.set_world_map()과
## 완전히 같은 패턴).
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	for anchor_cell in _sprites.keys():
		_despawn_sprite(anchor_cell)
	_world_map = world_map
	_current_map_id = map_id
	for anchor_cell in (_decor.get(map_id, {}) as Dictionary):
		var item_id := String((_decor[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		_spawn_sprite(anchor_cell, item_id)


## EconomyManager.upgrade_house()가 지도 좌표계가 바뀌었을 때 호출한다
## (WorldMap.get_room_anchor_shift() 참고) - furniture_manager.gd의 같은
## 이름 함수와 동일한 패턴.
func shift_map_placements(map_id: String, delta_cells: Vector2i) -> void:
	if delta_cells == Vector2i.ZERO or not _decor.has(map_id):
		return
	var shifted: Dictionary = {}
	for anchor_cell in (_decor[map_id] as Dictionary):
		shifted[anchor_cell + delta_cells] = (_decor[map_id] as Dictionary)[anchor_cell]
	_decor[map_id] = shifted
	if map_id == _current_map_id:
		set_world_map(_world_map, _current_map_id)


func get_save_data() -> Dictionary:
	var maps: Dictionary = {}
	for map_id in _decor:
		var cells: Dictionary = {}
		for anchor_cell in (_decor[map_id] as Dictionary):
			cells["%d,%d" % [anchor_cell.x, anchor_cell.y]] = (_decor[map_id][anchor_cell] as Dictionary).duplicate(true)
		maps[map_id] = cells
	return {"placed": maps}


func load_save_data(data: Dictionary) -> void:
	_decor.clear()
	var saved: Dictionary = data.get("placed", {})
	for map_id in saved:
		var cells: Dictionary = {}
		for key in (saved[map_id] as Dictionary):
			var parts := String(key).split(",")
			if parts.size() != 2:
				continue
			cells[Vector2i(int(parts[0]), int(parts[1]))] = (saved[map_id][key] as Dictionary).duplicate(true)
		_decor[String(map_id)] = cells
	floor_decor_changed.emit()


func _spawn_sprite(anchor_cell: Vector2i, item_id: String) -> void:
	if _world_map == null:
		return
	_despawn_sprite(anchor_cell)
	var footprint := get_footprint(item_id)
	var center := _anchor_cell_to_center(anchor_cell, footprint)
	var sprite := Sprite2D.new()
	sprite.position = center
	sprite.z_index = SPRITE_Z_INDEX
	_apply_decor_visual(sprite, item_id, footprint)
	sprite.add_to_group(&"_floor_decor_sprite")
	_world_map.add_child(sprite)
	_sprites[anchor_cell] = sprite


func _despawn_sprite(anchor_cell: Vector2i) -> void:
	var sprite: Node = _sprites.get(anchor_cell)
	if sprite != null:
		sprite.queue_free()
		_sprites.erase(anchor_cell)


## 바닥장식은 가구와 달리 오버행 개념이 없다(항상 바닥에 딱 붙는 평면
## 그림) - 그림 크기를 footprint*16 그대로 쓴다.
func _apply_decor_visual(sprite: Sprite2D, item_id: String, footprint: Vector2i) -> void:
	sprite.texture = _decor_texture(item_id)


func _decor_texture(item_id: String) -> Texture2D:
	var definition := InventoryManager.get_item_definition(item_id)
	var path := String(definition.get("world_sprite", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		if definition.has("colors"):
			return _recolored_texture(item_id, path, definition["colors"])
		return load(path)
	var footprint := get_footprint(item_id)
	var icon_color := String(definition.get("icon_color", ""))
	var color := Color(icon_color) if not icon_color.is_empty() else PLACEHOLDER_COLOR
	var image := Image.create(footprint.x * WorldMap.TILE_SIZE, footprint.y * WorldMap.TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## furniture_manager.gd의 _recolored_texture()와 완전히 동일한 패턴.
func _recolored_texture(item_id: String, path: String, colors_hex: Array) -> Texture2D:
	if _recolor_cache.has(item_id):
		return _recolor_cache[item_id]
	var colors: Array[Color] = []
	for hex in colors_hex:
		colors.append(Color(String(hex)))
	var image := FurnitureAppearance.build_recolored_image(path, colors)
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null else null
	_recolor_cache[item_id] = texture
	return texture


## world_position은 footprint의 "중심" 좌표(main.gd 미리보기가 계산해서
## 넘겨주는 값과 동일한 기준) - furniture_manager.gd와 동일한 방식으로
## 좌상단 칸을 역산한다.
func _world_to_anchor_cell(world_position: Vector2, footprint: Vector2i) -> Vector2i:
	var top_left: Vector2 = world_position - Vector2(footprint) * WorldMap.TILE_SIZE / 2.0
	return Vector2i(roundi(top_left.x / WorldMap.TILE_SIZE), roundi(top_left.y / WorldMap.TILE_SIZE))


func _anchor_cell_to_center(anchor_cell: Vector2i, footprint: Vector2i) -> Vector2:
	return Vector2(anchor_cell) * WorldMap.TILE_SIZE + Vector2(footprint) * WorldMap.TILE_SIZE / 2.0
