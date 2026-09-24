extends Node

## 자유 배치형 가구(스타듀밸리식). storage_box_manager.gd의 구조(맵별 Vector2i
## 키 Dictionary, "x,y" 문자열 세이브 포맷, set_world_map 스폰/디스폰 패턴,
## place_box()류 "검증→커밋→메시지 문자열 반환" 흐름)를 그대로 베낀 병렬
## 구조 - 상속/공유 베이스 없이 따로 둔다(기존에 잘 동작 중인 보관 상자
## 코드는 손대지 않음, 사용자 지시).
##
## 보관 상자와 다른 점: (1) 가구는 아이템마다 칸수(footprint)가 달라서 항상
## 1칸이 아니라 items.json의 footprint_width/footprint_height를 읽어서
## 매번 계산한다. (2) 내부 슬롯이 없다 - 순수 장식용이라 배치/회수만
## 되고(사용자 확정), 그래서 회수에 "비어있어야" 조건도 없다. (3) 회전 없음
## (사용자 확정) - 그려진 모습 그대로 한 방향으로만 놓인다.
##
## 설치: 손(EquipmentManager.HAND_SLOT)에 category=="furniture" 아이템을
## 장착하면(특정 아이템 id를 하드코딩하지 않음 - 가구가 몇 종류든 코드 변경
## 없이 동작) main.gd가 마우스 아래 칸에 반투명 미리보기를 띄우고, 좌클릭하면
## 그 자리에 설치한다. ALLOWED_MAP_IDS(마당+집 내부)에서만 설치 가능 - 원래는
## Home(마당)만 가능했으나(보관 상자와 동일한 사용자 지시), day10에서 벽장식
## 시스템(WallDecorManager)을 추가하면서 실내 배치 필요성이 생겨 home_interior도
## 함께 허용하도록 확장함(사용자 지시). StorageBoxManager/FarmingManager는
## 이 확장 대상이 아니라 손대지 않음(각자 독립된 HOME_MAP_ID/FARM_MAP_ID).

## 설치 가능한 맵들 - Home(마당)은 StorageBoxManager.HOME_MAP_ID와 같은 값
## 유지(사용자 지시로 코드는 따로 두는 관례를 그대로 따름). home_interior는
## 2026-08-10 벽장식 시스템 도입을 계기로 추가됨. basement_interior(집
## 레벨 3에서 연결되는 지하실)는 사용자 지시로 같이 추가됨.
const HOME_MAP_ID := "Home"
const HOME_INTERIOR_MAP_ID := "home_interior"
const BASEMENT_MAP_ID := "basement_interior"
const ALLOWED_MAP_IDS := {HOME_MAP_ID: true, HOME_INTERIOR_MAP_ID: true, BASEMENT_MAP_ID: true}
const FURNITURE_INTERACT_RADIUS := 20.0
const PLACEHOLDER_COLOR := Color(0.5, 0.5, 0.5)


## FloorDecorManager가 같은 맵 범위를 참조하는 데 쓴다(맵 목록이 둘 사이에서
## 드리프트되지 않도록 - 사용자가 "가구·바닥장식 둘 다 마당+집 내부" 라고
## 확정한 범위를 한 곳에서만 관리).
func is_placement_allowed(map_id: String) -> bool:
	return ALLOWED_MAP_IDS.has(map_id)

signal furniture_changed

## map_id(String) -> { anchor_cell(Vector2i) -> {"item_id": String} }
## anchor_cell은 footprint의 좌상단 칸(회전 없음, 사용자 확정) - 실제로 막힌
## 칸 범위는 그때그때 get_footprint(item_id)로 다시 계산한다(저장하지 않음 -
## items.json 쪽 값이 나중에 바뀌어도 항상 최신 기준을 따르게).
var _furniture: Dictionary = {}

var _world_map: WorldMap = null
var _current_map_id := ""
## anchor_cell(Vector2i) -> Sprite2D, 현재 로드된 맵에 속한 가구만.
var _sprites: Dictionary = {}
## item_id(색상 합성 id 포함) -> 리컬러된 Texture2D. _recolored_texture() 참고.
var _recolor_cache: Dictionary = {}


func get_footprint(item_id: String) -> Vector2i:
	var definition := InventoryManager.get_item_definition(item_id)
	return Vector2i(maxi(int(definition.get("footprint_width", 1)), 1), maxi(int(definition.get("footprint_height", 1)), 1))


## main.gd가 설치 미리보기 스프라이트에 쓴다.
func get_preview_texture(item_id: String) -> Texture2D:
	return _furniture_texture(item_id)


func can_place_furniture(item_id: String, world_position: Vector2) -> bool:
	if _world_map == null or not is_placement_allowed(_current_map_id):
		return false
	var footprint := get_footprint(item_id)
	return not _world_map.is_area_blocked(world_position, Vector2(footprint) * WorldMap.TILE_SIZE)


func has_furniture_overlap(map_id: String, anchor_cell: Vector2i, footprint: Vector2i) -> bool:
	var target := Rect2i(anchor_cell, footprint)
	for existing_cell in (_furniture.get(map_id, {}) as Dictionary):
		var existing_item_id := String((_furniture[map_id] as Dictionary)[existing_cell].get("item_id", ""))
		var existing_rect := Rect2i(existing_cell, get_footprint(existing_item_id))
		if target.intersects(existing_rect):
			return true
	return false


## EquipmentManager.HAND_SLOT에 category=="furniture" 아이템이 장착돼 있어야
## 하고, ALLOWED_MAP_IDS(마당/집 내부) 위여야 하고, 대상 영역(마우스 아래 칸
## 기준 - main.gd 미리보기 참고)이 막혀있지 않고 다른 가구와 겹치지 않아야
## 한다. 성공하면 빈 문자열, 실패하면 main.gd가 _show_temporary_message()로
## 그대로 표시할 한글 메시지를 반환한다(storage_box_manager.gd와 동일한 관례).
func place_furniture(world_position: Vector2) -> String:
	var item_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	if InventoryManager.get_item_category(item_id) != "furniture":
		return ""
	if _world_map == null:
		return ""
	if not is_placement_allowed(_current_map_id):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("집 안이나 마당에서만 설치할 수 있다.")
	var footprint := get_footprint(item_id)
	var anchor_cell := _world_to_anchor_cell(world_position, footprint)
	if has_furniture_overlap(_current_map_id, anchor_cell, footprint):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("이미 가구가 있다.")
	if not can_place_furniture(item_id, world_position):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("이 곳에는 설치할 수 없다.")
	if not _furniture.has(_current_map_id):
		_furniture[_current_map_id] = {}
	(_furniture[_current_map_id] as Dictionary)[anchor_cell] = {"item_id": item_id}
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_spawn_sprite(anchor_cell, item_id)
	AudioManager.play_sfx(AudioManager.SFX_UI_SLOT_IN)
	furniture_changed.emit()
	return ""


## 내부 슬롯이 없어서(사용자 확정) 보관 상자와 달리 "비어있어야" 조건이
## 없다 - 항상 바로 회수 가능.
func remove_furniture(map_id: String, anchor_cell: Vector2i) -> String:
	if not (_furniture.get(map_id, {}) as Dictionary).has(anchor_cell):
		return ""
	var item_id := String((_furniture[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
	if not InventoryManager.can_add_item(item_id, 1):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return tr("인벤토리가 가득 찼다.")
	InventoryManager.add_item(item_id, 1)
	(_furniture[map_id] as Dictionary).erase(anchor_cell)
	if map_id == _current_map_id:
		var footprint := get_footprint(item_id)
		_despawn_sprite(anchor_cell)
		_world_map.set_area_blocked(_anchor_cell_to_center(anchor_cell, footprint), Vector2(footprint) * WorldMap.TILE_SIZE, false)
	furniture_changed.emit()
	return ""


## 가구 칸은 항상 막혀있어 플레이어가 그 안에 설 수 없으므로, 가장 가까운
## 가구는 항상 그 가구의 사각형 "경계"까지의 거리로 수렴한다(LivestockManager.
## get_nearest_stall()과 같은 거리 기반 최근접 패턴을 사각형으로 확장).
func get_nearest_furniture(position: Vector2, current_map_id: String) -> Dictionary:
	if _world_map == null or not _furniture.has(current_map_id):
		return {}
	var best_cell := Vector2i.MAX
	var best_distance := INF
	for anchor_cell in (_furniture[current_map_id] as Dictionary):
		var item_id := String((_furniture[current_map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		var footprint := get_footprint(item_id)
		var rect := Rect2(Vector2(anchor_cell) * WorldMap.TILE_SIZE, Vector2(footprint) * WorldMap.TILE_SIZE)
		var closest := Vector2(clampf(position.x, rect.position.x, rect.end.x), clampf(position.y, rect.position.y, rect.end.y))
		var distance := position.distance_to(closest)
		if distance <= FURNITURE_INTERACT_RADIUS and distance < best_distance:
			best_distance = distance
			best_cell = anchor_cell
	if best_cell == Vector2i.MAX:
		return {}
	return {"anchor_cell": best_cell, "distance": best_distance}


## LightingLayer.rebuild_lights()가 map_id에 배치된 가구 중 emits_light인
## 것들의 조명 위치를 얻는 데 쓴다. WorldMap._compute_light_source_positions()의
## "맨 윗칸 중심" 개념과 동일하게 footprint 맨 윗줄 가운데를 위치로 쓴다 -
## set_world_map()으로 아직 전환되지 않은 맵도(맵 로드 중 조명을 먼저
## 다시 만들 때) _furniture가 map_id별로 다 들고 있어서 바로 조회 가능하다.
func get_light_source_positions(map_id: String) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for anchor_cell in (_furniture.get(map_id, {}) as Dictionary):
		var item_id := String((_furniture[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		if not bool(InventoryManager.get_item_definition(item_id).get("emits_light", false)):
			continue
		var footprint := get_footprint(item_id)
		positions.append(Vector2(anchor_cell.x + footprint.x / 2.0, anchor_cell.y + 0.5) * WorldMap.TILE_SIZE)
	return positions


## main.gd가 맵을 옮길 때마다 호출한다(storage_box_manager.gd.set_world_map()과
## 완전히 같은 패턴).
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	for anchor_cell in _sprites.keys():
		_despawn_sprite(anchor_cell)
	_world_map = world_map
	_current_map_id = map_id
	for anchor_cell in (_furniture.get(map_id, {}) as Dictionary):
		var item_id := String((_furniture[map_id] as Dictionary)[anchor_cell].get("item_id", ""))
		_spawn_sprite(anchor_cell, item_id)


## EconomyManager.upgrade_house()가 지도 좌표계가 바뀌었을 때 호출한다
## (WorldMap.get_room_anchor_shift() 참고) - 이미 저장된 배치를 새 좌표로
## 옮기고, 지금 그 맵을 보고 있었다면 스프라이트도 다시 그린다.
func shift_map_placements(map_id: String, delta_cells: Vector2i) -> void:
	if delta_cells == Vector2i.ZERO or not _furniture.has(map_id):
		return
	var shifted: Dictionary = {}
	for anchor_cell in (_furniture[map_id] as Dictionary):
		shifted[anchor_cell + delta_cells] = (_furniture[map_id] as Dictionary)[anchor_cell]
	_furniture[map_id] = shifted
	if map_id == _current_map_id:
		set_world_map(_world_map, _current_map_id)


func get_save_data() -> Dictionary:
	var maps: Dictionary = {}
	for map_id in _furniture:
		var cells: Dictionary = {}
		for anchor_cell in (_furniture[map_id] as Dictionary):
			cells["%d,%d" % [anchor_cell.x, anchor_cell.y]] = (_furniture[map_id][anchor_cell] as Dictionary).duplicate(true)
		maps[map_id] = cells
	return {"placed": maps}


func load_save_data(data: Dictionary) -> void:
	_furniture.clear()
	var saved: Dictionary = data.get("placed", {})
	for map_id in saved:
		var cells: Dictionary = {}
		for key in (saved[map_id] as Dictionary):
			var parts := String(key).split(",")
			if parts.size() != 2:
				continue
			cells[Vector2i(int(parts[0]), int(parts[1]))] = (saved[map_id][key] as Dictionary).duplicate(true)
		_furniture[String(map_id)] = cells
	furniture_changed.emit()


## WorldMap.load_map()이 맵을 새로 불러올 때마다 _blocked_cells를 타일
## 데이터에서 완전히 새로 만들기 때문에, set_area_blocked()는 스폰될 때마다
## (= set_world_map()으로 다시 불려올 때마다) 매번 다시 걸어줘야 한다
## (storage_box_manager.gd._spawn_sprite()와 동일한 이유).
func _spawn_sprite(anchor_cell: Vector2i, item_id: String) -> void:
	if _world_map == null:
		return
	_despawn_sprite(anchor_cell)
	var footprint := get_footprint(item_id)
	var center := _anchor_cell_to_center(anchor_cell, footprint)
	var sprite := Sprite2D.new()
	sprite.position = center
	_apply_furniture_visual(sprite, item_id, footprint)
	sprite.add_to_group(&"_furniture_sprite")
	_world_map.add_child(sprite)
	_sprites[anchor_cell] = sprite
	_world_map.set_area_blocked(center, Vector2(footprint) * WorldMap.TILE_SIZE, true)


func _despawn_sprite(anchor_cell: Vector2i) -> void:
	var sprite: Node = _sprites.get(anchor_cell)
	if sprite != null:
		sprite.queue_free()
		_sprites.erase(anchor_cell)


## 그림 세로 길이가 footprint 세로 칸수(*16)보다 길 수 있다(기본은 위로만
## 오버행 - storage_box_manager.gd의 열린 상자 그림과 같은 원리) - 그림
## 아래쪽만 footprint 맨 아랫줄에 걸치도록 위로 띄운다. items.json에
## "overhang_below": true가 있으면 반대로(침대처럼 충돌이 그림 위쪽에 있고
## 그림이 아래로 튀어나오는 경우, 사용자 지시) 그림 윗쪽을 footprint 맨
## 윗줄에 걸치도록 아래로 띄운다 - 기본값은 false라 기존 아이템은 전부
## 그대로 동작한다. 가로는 오버행을 지원하지 않는다(항상
## footprint_width*16으로 정확히 그려야 함 - 사용자에게 안내할 규격).
func _apply_furniture_visual(sprite: Sprite2D, item_id: String, footprint: Vector2i) -> void:
	var texture := _furniture_texture(item_id)
	sprite.texture = texture
	var footprint_height := footprint.y * WorldMap.TILE_SIZE
	var height := texture.get_height() if texture != null else footprint_height
	var overhang_below := bool(InventoryManager.get_item_definition(item_id).get("overhang_below", false))
	var direction := 1.0 if overhang_below else -1.0
	sprite.offset = Vector2(0, direction * (height - footprint_height) / 2.0)


func _furniture_texture(item_id: String) -> Texture2D:
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


## FurnitureAppearance로 마커를 구매 시 고른 색으로 치환한 텍스처를 만들어
## 캐싱한다 - item_id(색 조합까지 포함된 합성 id)당 결과가 항상 같으므로
## 한 번만 계산하면 된다(미리보기가 매 프레임 다시 부르므로 캐시 필수).
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
## 넘겨주는 값과 동일한 기준) - set_area_blocked()의 center/size 계산과
## 정확히 같은 방식으로 좌상단 칸을 역산한다.
func _world_to_anchor_cell(world_position: Vector2, footprint: Vector2i) -> Vector2i:
	var top_left: Vector2 = world_position - Vector2(footprint) * WorldMap.TILE_SIZE / 2.0
	return Vector2i(roundi(top_left.x / WorldMap.TILE_SIZE), roundi(top_left.y / WorldMap.TILE_SIZE))


func _anchor_cell_to_center(anchor_cell: Vector2i, footprint: Vector2i) -> Vector2:
	return Vector2(anchor_cell) * WorldMap.TILE_SIZE + Vector2(footprint) * WorldMap.TILE_SIZE / 2.0
