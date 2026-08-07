extends Node

## 자유 배치형 보관 상자(스타듀밸리식 창고). livestock_manager.gd(스프라이트
## 스폰/디스폰, set_world_map, 세이브/로드 패턴)와 farming_manager.gd(Vector2i
## 키 임의 개수 상태, 문자열 키 세이브 포맷)를 그대로 베낀 구조 - 다만 이
## 프로젝트에서 처음으로 "여러 맵에 걸친 임의 개수 배치 상태"를 다뤄서
## map_id 레이어가 하나 더 있다.
## 설치: 손(EquipmentManager.HAND_SLOT)에 storage_box를 장착하면 main.gd가
## 마우스 아래 칸에 반투명 미리보기를 띄우고, 좌클릭하면 그 자리에 설치한다
## (사용자 지시 - 스타듀처럼 마우스로 위치를 보면서 설치). 오직 HOME_MAP_ID
## (집)에서만 설치 가능(사용자 지시 - 다른 맵은 배치 대상 아님).
## 회수: 상자가 비어있을 때만 가능(내용물 있는 채로 회수하는 기능은 없음 -
## "아이템이 사라지는 상자"를 만들지 않기 위한 단순화).

const BOX_ITEM_ID := "storage_box"
const BOX_SLOT_COUNT := 24            ## 6열 x 4줄
## 설치 가능한 유일한 맵(사용자 지시) - FarmingManager.FARM_MAP_ID와 같은 값.
const HOME_MAP_ID := "Home"
## 충돌은 항상 타일 하나(16x16)만 막는다 - 그림 크기와는 무관(_apply_box_visual
## 참고). 닫힌 그림(16x16)과 열린 그림(16x32, 뚜껑 때문에 세로로 김)의 실제
## 높이가 서로 달라서, 각 텍스처의 실제 높이를 기준으로 매번 offset을 다시
## 계산한다(사용자가 그림을 이렇게 그려서 준 것 - 고정 높이를 가정하지 않음).
const BOX_SPRITE_SIZE := 16
const BOX_INTERACT_RADIUS := 16.0
const BOX_SPRITE_CLOSED := "res://assets/img/storage/storage_box_closed.png"
const BOX_SPRITE_OPEN := "res://assets/img/storage/storage_box_open.png"
const PLACEHOLDER_COLOR := Color(0.55, 0.38, 0.22)

signal boxes_changed

## map_id(String) -> { cell(Vector2i) -> box_state(Dictionary) }
## box_state = {"items": Array[BOX_SLOT_COUNT] of null | {"item_id": String, "count": int}}
var _boxes: Dictionary = {}

var _world_map: WorldMap = null
var _current_map_id := ""
## cell(Vector2i) -> Sprite2D, 현재 로드된 맵에 속한 상자만(다른 맵으로
## 넘어가면 전부 지워지고 새 맵 것만 다시 스폰된다).
var _sprites: Dictionary = {}
## 상자 UI가 열려있는 동안 그 상자만 "열림" 그림으로 보이게 추적.
var _open_cell := Vector2i(-999999, -999999)


func can_place_box(world_position: Vector2) -> bool:
	return _world_map != null and _current_map_id == HOME_MAP_ID and not _world_map.is_cell_blocked(world_position)


## main.gd가 설치 미리보기 스프라이트에 쓴다 - 항상 닫힌 그림을 보여준다.
func get_preview_texture() -> Texture2D:
	return _box_texture(false)


func has_box_at(map_id: String, cell: Vector2i) -> bool:
	return (_boxes.get(map_id, {}) as Dictionary).has(cell)


func get_box(map_id: String, cell: Vector2i) -> Dictionary:
	return ((_boxes.get(map_id, {}) as Dictionary).get(cell, {}) as Dictionary).duplicate(true)


func get_box_slots(map_id: String, cell: Vector2i) -> Array:
	return (get_box(map_id, cell).get("items", []) as Array).duplicate(true)


## InventoryManager.sort_by_name()과 동일한 방식 - 이름순으로 앞에서부터
## 다시 채운다(빈 칸은 뒤로 몰림).
func sort_box(map_id: String, cell: Vector2i) -> void:
	if not has_box_at(map_id, cell):
		return
	var items: Array = (_boxes[map_id] as Dictionary)[cell]["items"]
	var packed: Array = []
	for slot in items:
		if slot != null:
			packed.append(slot)
	packed.sort_custom(func(a, b): return _item_name(String(a.get("item_id", ""))) < _item_name(String(b.get("item_id", ""))))
	var sorted_items: Array = []
	sorted_items.resize(items.size())
	for i in packed.size():
		sorted_items[i] = packed[i]
	(_boxes[map_id] as Dictionary)[cell]["items"] = sorted_items
	boxes_changed.emit()


func _item_name(item_id: String) -> String:
	return String(InventoryManager.get_item_definition(item_id).get("name", item_id))


## EquipmentManager.HAND_SLOT에 storage_box가 장착돼 있어야 하고, HOME_MAP_ID
## 위여야 하고, 대상 칸(마우스 아래 칸 - main.gd 미리보기 참고)이 막혀있지
## 않고 이미 다른 상자가 없어야 한다. 성공하면 빈 문자열, 실패하면 main.gd가
## _show_temporary_message()로 그대로 표시할 한글 메시지를 반환한다
## (LivestockManager.perform_feed()와 동일한 관례).
func place_box(world_position: Vector2) -> String:
	if EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT) != BOX_ITEM_ID:
		return ""
	if _world_map == null:
		return ""
	if _current_map_id != HOME_MAP_ID:
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "집에서만 설치할 수 있다."
	var cell := _world_to_cell(world_position)
	if has_box_at(_current_map_id, cell):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "이미 상자가 있다."
	if not can_place_box(world_position):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "이 곳에는 설치할 수 없다."
	if not _boxes.has(_current_map_id):
		_boxes[_current_map_id] = {}
	var items: Array = []
	items.resize(BOX_SLOT_COUNT)
	(_boxes[_current_map_id] as Dictionary)[cell] = {"items": items}
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_spawn_sprite(cell)
	AudioManager.play_sfx(AudioManager.SFX_DIGGING)
	boxes_changed.emit()
	return ""


## 상자가 비어있을 때만 회수 가능 - 성공하면 storage_box 아이템 1개가
## 인벤토리로 돌아간다. 실패해도 성공해도 main.gd가 표시할 메시지를 반환한다
## (빈 문자열이면 아무 것도 안 함, storage_screen.gd가 그 경우 조용히 닫는다).
func remove_box(map_id: String, cell: Vector2i) -> String:
	if not has_box_at(map_id, cell):
		return ""
	var items: Array = get_box(map_id, cell).get("items", [])
	for slot in items:
		if slot != null:
			AudioManager.play_sfx(AudioManager.SFX_BEEP)
			return "보관함을 비워야 회수할 수 있다."
	if not InventoryManager.can_add_item(BOX_ITEM_ID, 1):
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
		return "인벤토리가 가득 찼다."
	InventoryManager.add_item(BOX_ITEM_ID, 1)
	(_boxes[map_id] as Dictionary).erase(cell)
	if map_id == _current_map_id:
		_despawn_sprite(cell)
		_world_map.set_area_blocked(_cell_to_world(cell), Vector2(BOX_SPRITE_SIZE, BOX_SPRITE_SIZE), false)
	boxes_changed.emit()
	return ""


## LivestockManager.get_nearest_stall()과 동일한 형태(거리 기반 최근접).
func get_nearest_box(position: Vector2, current_map_id: String) -> Dictionary:
	if _world_map == null or not _boxes.has(current_map_id):
		return {}
	var best_cell := Vector2i.MAX
	var best_distance := INF
	for cell in (_boxes[current_map_id] as Dictionary):
		var distance := position.distance_to(_cell_to_world(cell))
		if distance <= BOX_INTERACT_RADIUS and distance < best_distance:
			best_distance = distance
			best_cell = cell
	if best_cell == Vector2i.MAX:
		return {}
	return {"cell": best_cell, "distance": best_distance}


## InventoryManager.add_item()과 같은 all-or-nothing 스택 로직을 상자의
## items 배열에 대해 그대로 구현한다 - InventoryManager 자체를 리팩토링해서
## 공유하지 않는다(승인 없는 리팩토링 금지, CLAUDE.md). get_stack_limit()만
## 재사용해서 상자/가방의 스택 한도가 항상 같게 맞춘다.
func can_add_item_to_box(map_id: String, cell: Vector2i, item_id: String, count: int) -> bool:
	if count <= 0 or not has_box_at(map_id, cell):
		return false
	var items: Array = (_boxes[map_id] as Dictionary)[cell]["items"]
	var stack_limit := InventoryManager.get_stack_limit(item_id)
	var existing_capacity := 0
	var empty_slots := 0
	for slot in items:
		if slot == null:
			empty_slots += 1
		elif String(slot.get("item_id", "")) == item_id:
			existing_capacity += stack_limit - int(slot["count"])
	var overflow: int = maxi(count - existing_capacity, 0)
	var slots_needed: int = 0 if overflow == 0 else int(ceil(float(overflow) / float(stack_limit)))
	return slots_needed <= empty_slots


func add_item_to_box(map_id: String, cell: Vector2i, item_id: String, count: int) -> bool:
	if not can_add_item_to_box(map_id, cell, item_id, count):
		return false
	var items: Array = (_boxes[map_id] as Dictionary)[cell]["items"]
	var stack_limit := InventoryManager.get_stack_limit(item_id)
	var remaining := count
	for i in items.size():
		if remaining <= 0:
			break
		var slot = items[i]
		if slot != null and String(slot.get("item_id", "")) == item_id and int(slot["count"]) < stack_limit:
			var add_amount: int = mini(stack_limit - int(slot["count"]), remaining)
			slot["count"] = int(slot["count"]) + add_amount
			remaining -= add_amount
	while remaining > 0:
		var index := items.find(null)
		var add_amount: int = mini(stack_limit, remaining)
		items[index] = {"item_id": item_id, "count": add_amount}
		remaining -= add_amount
	boxes_changed.emit()
	return true


func remove_item_from_box(map_id: String, cell: Vector2i, item_id: String, count: int) -> bool:
	if not has_box_at(map_id, cell):
		return false
	var items: Array = (_boxes[map_id] as Dictionary)[cell]["items"]
	var total := 0
	for slot in items:
		if slot != null and String(slot.get("item_id", "")) == item_id:
			total += int(slot["count"])
	if count <= 0 or total < count:
		return false
	var remaining := count
	for i in items.size():
		if remaining <= 0:
			break
		var slot = items[i]
		if slot != null and String(slot.get("item_id", "")) == item_id:
			var take: int = mini(int(slot["count"]), remaining)
			slot["count"] = int(slot["count"]) - take
			remaining -= take
			if int(slot["count"]) <= 0:
				items[i] = null
	boxes_changed.emit()
	return true


## storage_screen.gd가 상자를 열고 닫을 때 호출 - 그 상자만 열린 그림으로
## 바뀐다(사용자 확정, 스타듀처럼 열림/닫힘 그림이 다름).
func set_box_open_visual(cell: Vector2i, is_open: bool) -> void:
	_open_cell = cell if is_open else Vector2i(-999999, -999999)
	var sprite: Sprite2D = _sprites.get(cell)
	if sprite != null:
		_apply_box_visual(sprite, is_open)


## main.gd가 맵을 옮길 때마다 호출한다(LivestockManager.set_world_map()과
## 완전히 같은 패턴) - WorldMap 노드는 재생성되지 않고 내용만 바뀌므로 반드시
## 먼저 기존 스프라이트를 전부 지워야 다음 맵까지 안 남아있는다.
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	for cell in _sprites.keys():
		_despawn_sprite(cell)
	_world_map = world_map
	_current_map_id = map_id
	for cell in (_boxes.get(map_id, {}) as Dictionary):
		_spawn_sprite(cell)


func get_save_data() -> Dictionary:
	var maps: Dictionary = {}
	for map_id in _boxes:
		var cells: Dictionary = {}
		for cell in (_boxes[map_id] as Dictionary):
			cells["%d,%d" % [cell.x, cell.y]] = (_boxes[map_id][cell] as Dictionary).duplicate(true)
		maps[map_id] = cells
	return {"boxes": maps}


func load_save_data(data: Dictionary) -> void:
	_boxes.clear()
	var saved: Dictionary = data.get("boxes", {})
	for map_id in saved:
		var cells: Dictionary = {}
		for key in (saved[map_id] as Dictionary):
			var parts := String(key).split(",")
			if parts.size() != 2:
				continue
			cells[Vector2i(int(parts[0]), int(parts[1]))] = (saved[map_id][key] as Dictionary).duplicate(true)
		_boxes[String(map_id)] = cells
	boxes_changed.emit()


## WorldMap.load_map()이 맵을 새로 불러올 때마다 _blocked_cells를 타일
## 데이터에서 완전히 새로 만들기 때문에, set_area_blocked()는 최초 설치
## 시점 한 번이 아니라 스폰될 때마다(= set_world_map()으로 다시 불려올
## 때마다) 매번 다시 걸어줘야 한다(LivestockManager._spawn_sprite()와 동일).
func _spawn_sprite(cell: Vector2i) -> void:
	if _world_map == null:
		return
	_despawn_sprite(cell)
	var sprite := Sprite2D.new()
	sprite.position = _cell_to_world(cell)
	_apply_box_visual(sprite, cell == _open_cell)
	sprite.add_to_group(&"_storage_box_sprite")
	_world_map.add_child(sprite)
	_sprites[cell] = sprite
	_world_map.set_area_blocked(sprite.position, Vector2(BOX_SPRITE_SIZE, BOX_SPRITE_SIZE), true)


func _despawn_sprite(cell: Vector2i) -> void:
	var sprite: Node = _sprites.get(cell)
	if sprite != null:
		sprite.queue_free()
		_sprites.erase(cell)


## 닫힌 그림(16x16)과 열린 그림(16x32)의 실제 높이가 서로 달라서, 텍스처를
## 바꿀 때마다 그 텍스처의 실제 높이 기준으로 offset을 다시 계산해야 한다 -
## 충돌 판정용 타일(BOX_SPRITE_SIZE)은 항상 그대로 두고, 그림 아래쪽만 타일에
## 걸치도록 위로 띄운다(player.gd/npc_sprite.gd가 16x32 캐릭터 스프라이트를
## 발밑 기준점으로 앵커링하는 것과 동일한 방식 - 다만 여기선 그림 높이가
## 상태에 따라 바뀌므로 고정값 대신 texture.get_height()를 매번 쓴다).
func _apply_box_visual(sprite: Sprite2D, is_open: bool) -> void:
	var texture := _box_texture(is_open)
	sprite.texture = texture
	var height := texture.get_height() if texture != null else BOX_SPRITE_SIZE
	sprite.offset = Vector2(0, -(height - BOX_SPRITE_SIZE) / 2.0)


func _box_texture(is_open: bool) -> Texture2D:
	var path := BOX_SPRITE_OPEN if is_open else BOX_SPRITE_CLOSED
	if ResourceLoader.exists(path):
		return load(path)
	var height := BOX_SPRITE_SIZE * 2 if is_open else BOX_SPRITE_SIZE
	var image := Image.create(BOX_SPRITE_SIZE, height, false, Image.FORMAT_RGBA8)
	image.fill(PLACEHOLDER_COLOR)
	return ImageTexture.create_from_image(image)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x) / WorldMap.TILE_SIZE, int(world_position.y) / WorldMap.TILE_SIZE)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * WorldMap.TILE_SIZE + Vector2.ONE * WorldMap.TILE_SIZE * 0.5
