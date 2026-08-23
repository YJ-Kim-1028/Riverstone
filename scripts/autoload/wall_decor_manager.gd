extends Node

## 벽에 거는 장식(그림 등). furniture_manager.gd의 구조를 그대로 베낀 병렬
## 구조 - 상속/공유 베이스 없이 따로 둔다(FurnitureManager/StorageBoxManager와
## 동일한 관례, 사용자 지시).
##
## FurnitureManager와 다른 점: (1) 실제 "Wall" 타일이 있는 칸에만 설치 가능
## (WorldMap.is_wall_cell(), 사용자 확정 - 아무 데나 걸리면 어색하니까).
## (2) 벽 칸은 타일 자체 collision으로 항상 이미 막혀있으므로
## WorldMap.set_area_blocked()/is_area_blocked()를 설치/회수 어느 쪽에서도
## 절대 건드리지 않는다 - 건드리면 순수 중복이고, 회수 시 실수로 진짜 벽의
## 막힘 상태를 풀어버릴 위험만 생긴다. 배치 가능 여부는 오직
## is_wall_cell()(전 칸)과 has_wall_decor_overlap()(자기 Dictionary)로만
## 판정한다. (3) 설치 가능한 맵이 "Wall" 레이어가 있는 맵으로 제한된다(Home
## 마당엔 벽 자체가 없음) - home_interior에서 시작해서, 2026-08-10 지하실
## (basement_interior, 집 레벨 3에서 연결)이 사용자 지시로 추가됨.

const ALLOWED_MAP_IDS := {"home_interior": true, "basement_interior": true}
const WALL_DECOR_INTERACT_RADIUS := 20.0
const PLACEHOLDER_COLOR := Color(0.5, 0.5, 0.5)

signal wall_decor_changed

## map_id(String) -> { anchor_cell(Vector2i) -> {"item_id": String} }
var _wall_decor: Dictionary = {}

var _world_map: WorldMap = null
var _current_map_id := ""
## anchor_cell(Vector2i) -> Sprite2D, 현재 로드된 맵에 속한 벽장식만.
var _sprites: Dictionary = {}
## item_id(색상 합성 id 포함) -> 리컬러된 Texture2D. _recolored_texture() 참고.
var _recolor_cache: Dictionary = {}


func get_footprint(item_id: String) -> Vector2i:
	var definition := InventoryManager.get_item_definition(item_id)
	return Vector2i(maxi(int(definition.get("footprint_width", 1)), 1), maxi(int(definition.get("footprint_height", 1)), 1))


## main.gd가 설치 미리보기 스프라이트에 쓴다.
func get_preview_texture(item_id: String) -> Texture2D:
	return _decor_texture(item_id)


## anchor_cell부터 footprint 범위의 모든 칸이 "Wall" 타일인지 검사한다 -
## 하나라도 벽이 아니면 실패. WorldMap.is_wall_cell()은 칸 하나만 보므로
## 여기서 footprint 전체를 순회한다(WorldMap.is_area_blocked()가 같은
## 방식으로 여러 칸을 순회하는 것과 동일한 접근).
func _is_footprint_on_wall(anchor_cell: Vector2i, footprint: Vector2i) -> bool:
	if _world_map == null:
		return false
	for dx in range(footprint.x):
		for dy in range(footprint.y):
			var cell := anchor_cell + Vector2i(dx, dy)
			var cell_center := Vector2(cell) * WorldMap.TILE_SIZE + Vector2(WorldMap.TILE_SIZE, WorldMap.TILE_SIZE) / 2.0
			if not _world_map.is_wall_cell(cell_center):
				return false
	return true


func can_place_wall_decor(item_id: String, world_position: Vector2) -> bool:
	if _world_map == null or not ALLOWED_MAP_IDS.has(_current_map_id):
		return false
	var footprint := get_footprint(item_id)
	var anchor_cell := _world_to_anchor_cell(world_position, footprint)
	return _is_footprint_on_wall(anchor_cell, footprint)


func has_wall_decor_overlap(map_id: String, anchor_cell: Vector2i, footprint: Vector2i) -> bool:
	var target := Rect2i(anchor_cell, footprint)
	for existing_cell in (_wall_decor.get(map_id, {}) as Dictionary):
		var existing_item_id := String((_wall_decor[map_id] as Dictionary)[existing_cell].get("item_id", ""))
		var existing_rect := Rect2i(existing_cell, get_footprint(existing_item_id))
		if target.intersects(existing_rect):
			return true
	return false


## EquipmentManager.HAND_SLOT에 category=="wall_decor" 아이템이 장착돼 있어야
## 하고, ALLOWED_MAP_IDS(집 내부/지하실) 위여야 하고, 대상 영역 전체가 실제
## 벽 타일이고 다른 벽장식과 겹치지 않아야 한다. 성공하면 빈 문자열, 실패하면
## main.gd가 _show_temporary_message()로 그대로 표시할 한글 메시지를 반환한다
## (furniture_manager.gd와 동일한 관례).
func place_wall_decor(world_position: Vector2) -> String:
	var item_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	if InventoryManager.get_item_category(item_id) != "wall_decor":
		return ""
	if _world_map == null:
		return ""
	if not ALLOWED_MAP_IDS.has(_current_map_id):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "집 안의 벽에만 걸 수 있다."
	var footprint := get_footprint(item_id)
	var anchor_cell := _world_to_anchor_cell(world_position, footprint)
	if has_wall_decor_overlap(_current_map_id, anchor_cell, footprint):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "이미 걸려 있다."
	if not _is_footprint_on_wall(anchor_cell, footprint):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "벽에만 걸 수 있다."
	if not _wall_decor.has(_current_map_id):
		_wall_decor[_current_map_id] = {}
	(_wall_decor[_current_map_id] as Dictionary)[anchor_cell] = {"item_id": item_id}
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_spawn_sprite(anchor_cell, item_id)
	AudioManager.play_sfx(AudioManager.SFX_UI_SLOT_IN)
	wall_decor_changed.emit()
	return ""


## 내부 슬롯이 없어서(가구와 동일) "비어있어야" 조건이 없다 - 항상 바로
## 회수 가능. 벽 칸은 원래부터(타일 collision으로) 막혀있어 설치 때도
## set_area_blocked()를 호출한 적이 없으므로, 회수 때도 되돌릴 게 없다.
func remove_wall_decor(map_id: String, anchor_cell: Vector2i) -> String:
	if not (_wall_decor.get(map_id, {}) as Dictionary).has(anchor_cell):
		return ""
	var item_id := String((_wall_decor[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
	if not InventoryManager.can_add_item(item_id, 1):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "인벤토리가 가득 찼다."
	InventoryManager.add_item(item_id, 1)
	(_wall_decor[map_id] as Dictionary).erase(anchor_cell)
	if map_id == _current_map_id:
		_despawn_sprite(anchor_cell)
	wall_decor_changed.emit()
	return ""


## 벽 칸은 항상 막혀있어 플레이어가 그 안에 설 수 없으므로, 가구와 동일하게
## 사각형 "경계"까지의 거리로 최근접을 찾는다(FurnitureManager.
## get_nearest_furniture()와 동일한 패턴).
func get_nearest_wall_decor(position: Vector2, current_map_id: String) -> Dictionary:
	if _world_map == null or not _wall_decor.has(current_map_id):
		return {}
	var best_cell := Vector2i.MAX
	var best_distance := INF
	for anchor_cell in (_wall_decor[current_map_id] as Dictionary):
		var item_id := String((_wall_decor[current_map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		var footprint := get_footprint(item_id)
		var rect := Rect2(Vector2(anchor_cell) * WorldMap.TILE_SIZE, Vector2(footprint) * WorldMap.TILE_SIZE)
		var closest := Vector2(clampf(position.x, rect.position.x, rect.end.x), clampf(position.y, rect.position.y, rect.end.y))
		var distance := position.distance_to(closest)
		if distance <= WALL_DECOR_INTERACT_RADIUS and distance < best_distance:
			best_distance = distance
			best_cell = anchor_cell
	if best_cell == Vector2i.MAX:
		return {}
	return {"anchor_cell": best_cell, "distance": best_distance}


## furniture_manager.gd의 get_light_source_positions()와 완전히 동일한 패턴.
func get_light_source_positions(map_id: String) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for anchor_cell in (_wall_decor.get(map_id, {}) as Dictionary):
		var item_id := String((_wall_decor[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
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
	for anchor_cell in (_wall_decor.get(map_id, {}) as Dictionary):
		var item_id := String((_wall_decor[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		_spawn_sprite(anchor_cell, item_id)


## EconomyManager.upgrade_house()가 지도 좌표계가 바뀌었을 때 호출한다
## (WorldMap.get_room_anchor_shift() 참고) - furniture_manager.gd의 같은
## 이름 함수와 동일한 패턴.
func shift_map_placements(map_id: String, delta_cells: Vector2i) -> void:
	if delta_cells == Vector2i.ZERO or not _wall_decor.has(map_id):
		return
	var shifted: Dictionary = {}
	for anchor_cell in (_wall_decor[map_id] as Dictionary):
		shifted[anchor_cell + delta_cells] = (_wall_decor[map_id] as Dictionary)[anchor_cell]
	_wall_decor[map_id] = shifted
	if map_id == _current_map_id:
		set_world_map(_world_map, _current_map_id)


func get_save_data() -> Dictionary:
	var maps: Dictionary = {}
	for map_id in _wall_decor:
		var cells: Dictionary = {}
		for anchor_cell in (_wall_decor[map_id] as Dictionary):
			cells["%d,%d" % [anchor_cell.x, anchor_cell.y]] = (_wall_decor[map_id][anchor_cell] as Dictionary).duplicate(true)
		maps[map_id] = cells
	return {"placed": maps}


func load_save_data(data: Dictionary) -> void:
	_wall_decor.clear()
	var saved: Dictionary = data.get("placed", {})
	for map_id in saved:
		var cells: Dictionary = {}
		for key in (saved[map_id] as Dictionary):
			var parts := String(key).split(",")
			if parts.size() != 2:
				continue
			cells[Vector2i(int(parts[0]), int(parts[1]))] = (saved[map_id][key] as Dictionary).duplicate(true)
		_wall_decor[String(map_id)] = cells
	wall_decor_changed.emit()


## 특별한 z-index 처리 없이 가구와 동일하게 world_map 자식으로 추가한다 -
## WorldMap의 y_sort_enabled를 그대로 상속받아 플레이어/가구와 자동으로
## Y-sort된다(벽장식은 벽 칸에 고정되므로 실질적으로 항상 플레이어보다
## 위쪽에 그려지는 게 자연스러운 결과).
func _spawn_sprite(anchor_cell: Vector2i, item_id: String) -> void:
	if _world_map == null:
		return
	_despawn_sprite(anchor_cell)
	var footprint := get_footprint(item_id)
	var center := _anchor_cell_to_center(anchor_cell, footprint)
	var sprite := Sprite2D.new()
	sprite.position = center
	_apply_decor_visual(sprite, item_id, footprint)
	sprite.add_to_group(&"_wall_decor_sprite")
	_world_map.add_child(sprite)
	_sprites[anchor_cell] = sprite


func _despawn_sprite(anchor_cell: Vector2i) -> void:
	var sprite: Node = _sprites.get(anchor_cell)
	if sprite != null:
		sprite.queue_free()
		_sprites.erase(anchor_cell)


## 그림 세로 길이가 footprint 세로 칸수(*16)보다 길 수 있다(위로만 오버행 -
## furniture_manager.gd와 동일한 원리) - 그림 아래쪽만 footprint 맨 아랫줄에
## 걸치도록 위로 띄운다.
func _apply_decor_visual(sprite: Sprite2D, item_id: String, footprint: Vector2i) -> void:
	var texture := _decor_texture(item_id)
	sprite.texture = texture
	var footprint_height := footprint.y * WorldMap.TILE_SIZE
	var height := texture.get_height() if texture != null else footprint_height
	sprite.offset = Vector2(0, -(height - footprint_height) / 2.0)


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
