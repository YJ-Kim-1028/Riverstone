extends Control

## StorageBoxManager가 관리하는 상자 하나를 여닫는 화면. 예전엔 kitchen_screen.gd처럼
## plain visible을 쓰면서 "visible=true를 먼저, 그 다음에 슬롯을 채우면
## 된다"고 봤었는데, 그걸로도 익스포트 빌드에서 이 화면(과 kitchen/fishing/
## status)이 좌측 상단에 눌려 뜨는 문제가 있었다(사용자 리포트, 2026-08-26 -
## "이어하기 눌렀을 때 뜨는 창이 화면 밖으로 나가있는데"). 순서 문제가 아니라
## "생성된 뒤 한 번도 화면 크기가 자리잡기 전에 visible=false로 시작한 Control은
## 앵커가 잘못 굳는다"는 쪽이 진짜 원인으로 보여, shop_screen.gd/computer_screen.gd와
## 동일하게 항상 visible=true로 두고 modulate.a + mouse_filter로 여닫는 방식으로
## 바꿨다.
## 왼쪽 = 플레이어 인벤토리, 오른쪽 = 상자 내용물. 둘 다 inventory_slot.tscn을
## 재사용하고, 드래그 또는 클릭으로 서로 아이템을 옮긴다(inventory_slot.gd의
## accepts_drops/source_tag 확장 참고). 클릭 한 번으로도 반대쪽으로 즉시
## 옮겨지게 했다(사용자 지시 - 매번 드래그하기 귀찮음). 어느 방식이든 항상
## 그 슬롯의 전체 스택을 옮긴다(부분 이동/분할 없음 - 이 프로젝트의 다른
## 드래그 상호작용과 동일).

const SlotScene := preload("res://scenes/ui/inventory_slot.tscn")
const SCROLLBAR_WIDTH := 4
const BAG_SOURCE := "bag"
const BOX_SOURCE := "box"
## 스타듀밸리처럼 뚜껑 열리는 모션 + 소리를 먼저 보여준 다음 UI를 띄운다
## (사용자 지시) - 카메라가 항상 플레이어를 화면 중앙에 두고 그 위에 이 UI가
## 크게 뜨다 보니 열린 그림이 사실상 안 보이는 문제가 있었는데, UI가 뜨기
## 직전 짧게라도 보여주면(+소리) 최소한 "열렸다"는 인식은 줄 수 있다.
const OPEN_DELAY_SECONDS := 0.35

@onready var _bag_grid: GridContainer = $Background/Margin/VBox/HBox/BagPanel/BagScroll/BagGridMargin/BagGrid
@onready var _box_grid: GridContainer = $Background/Margin/VBox/HBox/BoxPanel/BoxScroll/BoxGridMargin/BoxGrid
@onready var _bag_scroll: ScrollContainer = $Background/Margin/VBox/HBox/BagPanel/BagScroll
@onready var _box_scroll: ScrollContainer = $Background/Margin/VBox/HBox/BoxPanel/BoxScroll
@onready var _close_button: TextureButton = $Background/CloseButton
@onready var _pickup_button: TextureButton = $Background/Margin/VBox/BottomRow/PickupButton
@onready var _message_label: Label = $Background/Margin/VBox/BottomRow/MessageLabel
@onready var _sort_button: TextureButton = $Background/Margin/VBox/HBox/BoxPanel/BoxLabelRow/SortButton
@onready var _tooltip: PanelContainer = $Tooltip
@onready var _tooltip_label: Label = $Tooltip/Label

## inventory_slot.gd의 DISABLED_TINT와 동일한 톤 - TextureButton은 Button과
## 달리 disabled여도 저절로 어두워지지 않아서 직접 modulate를 덮어써야 한다.
const PICKUP_DISABLED_TINT := Color(0.45, 0.45, 0.45, 1.0)

var _map_id := ""
var _cell := Vector2i.ZERO
## open_box()가 딜레이 중일 때 다시 눌려도(연타/재접근) 중복으로 안 들어가게
## 막는다 - 이 동안은 visible이 아직 false라 _is_open()만으로는 구분이 안 됨.
var _opening := false


func _ready() -> void:
	_set_open(false)
	_close_button.pressed.connect(close)
	_pickup_button.pressed.connect(_on_pickup_pressed)
	_sort_button.pressed.connect(_on_sort_pressed)
	InventoryManager.inventory_changed.connect(_refresh)
	StorageBoxManager.boxes_changed.connect(_refresh)
	_style_scrollbar(_bag_scroll)
	_style_scrollbar(_box_scroll)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_box(cell: Vector2i) -> void:
	if _is_open() or _opening:
		return
	_opening = true
	_map_id = GameManager.current_map_id
	_cell = cell
	_message_label.text = ""
	StorageBoxManager.set_box_open_visual(cell, true)
	AudioManager.play_sfx(AudioManager.SFX_DOOR)
	await get_tree().create_timer(OPEN_DELAY_SECONDS).timeout
	_opening = false
	_set_open(true)
	_refresh()


func close() -> void:
	if _is_open():
		StorageBoxManager.set_box_open_visual(_cell, false)
	_set_open(false)


func _is_open() -> bool:
	return modulate.a > 0.0


## 익스포트 빌드에서 앵커 기반 크기/위치가 창이 완전히 자리잡기 전 값으로
## 굳어버리는 문제 회피(사용자 리포트, 2026-08-26) - 값은 그대로 자신에게
## 다시 대입해서 Godot이 현재 부모 크기 기준으로 강제로 다시 계산하게 만든다.
func _refresh_layout() -> void:
	anchor_left = anchor_left
	anchor_top = anchor_top
	anchor_right = anchor_right
	anchor_bottom = anchor_bottom
	offset_left = offset_left
	offset_top = offset_top
	offset_right = offset_right
	offset_bottom = offset_bottom


func _set_open(is_open: bool) -> void:
	if is_open:
		_refresh_layout()
	else:
		_hide_tooltip()
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
	## Tooltip은 장식용(클릭이 통과해야 함)이라 위 재귀 호출이 STOP으로
	## 덮어쓴 걸 다시 IGNORE로 되돌린다 - CLAUDE.md UI 모달 mouse_filter
	## 체크리스트 3번과 동일한 패턴(equipment_panel.gd _refresh_inventory() 참고).
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func current_cell() -> Vector2i:
	return _cell


func _refresh() -> void:
	if not _is_open():
		return
	## 그리드가 통째로 다시 만들어지므로, 지금 뜬 툴팁이 가리키던 슬롯도 같이
	## 사라진다 - mouse_exited가 그 슬롯에서 안 올 수 있으니 여기서 미리 끈다
	## (equipment_panel.gd _refresh_inventory()와 동일한 패턴).
	_hide_tooltip()
	_rebuild_grid(_bag_grid, InventoryManager.get_slots(), BAG_SOURCE)
	_rebuild_grid(_box_grid, StorageBoxManager.get_box_slots(_map_id, _cell), BOX_SOURCE)
	var box_empty := _is_box_empty()
	_pickup_button.disabled = not box_empty
	_pickup_button.modulate = Color.WHITE if box_empty else PICKUP_DISABLED_TINT


func _is_box_empty() -> bool:
	for slot in StorageBoxManager.get_box_slots(_map_id, _cell):
		if slot != null:
			return false
	return true


func _rebuild_grid(grid: GridContainer, slots: Array, source_tag: String) -> void:
	for child in grid.get_children():
		child.queue_free()
	for i in slots.size():
		var slot_instance := SlotScene.instantiate()
		grid.add_child(slot_instance)
		slot_instance.call("setup", i, slots[i])
		slot_instance.source_tag = source_tag
		slot_instance.accepts_drops = true
		slot_instance.set_meta("tooltip_text", _tooltip_for(slots[i]))
		slot_instance.mouse_entered.connect(_show_tooltip.bind(slot_instance))
		slot_instance.mouse_exited.connect(_hide_tooltip)
		slot_instance.connect("slot_drop_received", _on_slot_drop_received)
		slot_instance.connect("slot_pressed", _on_slot_pressed.bind(source_tag))


## equipment_panel.gd의 _tooltip_for()/_show_tooltip()/_hide_tooltip()와 동일한
## 패턴 - 인벤토리 화면엔 있는 아이템 이름/설명 툴팁이 보관함 화면(가방/상자
## 양쪽 슬롯)에는 아예 안 뜨던 것을 사용자가 발견(2026-09-05 - "보관함
## 상자에서는 툴팁이 안떠"). 엔진 기본 tooltip_text 대신 화면 안의 Control을
## 직접 켜고/끄는 이유는 equipment_panel.gd의 같은 주석 참고(4배 확대 캔버스
## 배율 문제).
func _tooltip_for(slot_data) -> String:
	if slot_data == null:
		return ""
	var definition := InventoryManager.get_item_definition(String(slot_data.get("item_id", "")))
	var name_text := String(definition.get("name", ""))
	var description_text := String(definition.get("description", ""))
	return "%s\n%s" % [name_text, description_text] if not description_text.is_empty() else name_text


func _show_tooltip(source: Control) -> void:
	var text := String(source.get_meta("tooltip_text", ""))
	if text.is_empty():
		return
	_tooltip_label.text = text
	_tooltip.visible = true
	_tooltip.size = _tooltip.get_combined_minimum_size()
	var viewport_size := get_viewport_rect().size
	var target := source.get_global_rect().position + Vector2(0, source.get_global_rect().size.y + 2.0)
	target.x = clampf(target.x, 0.0, viewport_size.x - _tooltip.size.x)
	target.y = clampf(target.y, 0.0, viewport_size.y - _tooltip.size.y)
	_tooltip.global_position = target


func _hide_tooltip() -> void:
	_tooltip.visible = false


func _on_slot_drop_received(target_source: String, _target_index: int, data: Dictionary) -> void:
	var from_source := String(data.get("source", ""))
	if from_source == target_source or from_source.is_empty():
		return
	var item_id := String(data.get("item_id", ""))
	var count := int(data.get("count", 0))
	if item_id.is_empty() or count <= 0:
		return
	_move_item(from_source, target_source, item_id, count)


## 슬롯을 클릭하면(드래그 대신) 그 슬롯의 전체 스택을 즉시 반대쪽으로 옮긴다
## (사용자 지시 - 매번 드래그하는 게 귀찮다는 피드백). 드롭과 마찬가지로
## 어느 쪽 슬롯을 눌렀는지만 알면 반대쪽이 자동으로 정해진다(가방 슬롯 클릭
## -> 상자로, 상자 슬롯 클릭 -> 가방으로).
func _on_slot_pressed(index: int, source_tag: String) -> void:
	var slots := InventoryManager.get_slots() if source_tag == BAG_SOURCE else StorageBoxManager.get_box_slots(_map_id, _cell)
	if index < 0 or index >= slots.size() or slots[index] == null:
		return
	var item_id := String(slots[index].get("item_id", ""))
	var count := int(slots[index].get("count", 0))
	if item_id.is_empty() or count <= 0:
		return
	var target_source := BOX_SOURCE if source_tag == BAG_SOURCE else BAG_SOURCE
	_move_item(source_tag, target_source, item_id, count)


func _move_item(from_source: String, target_source: String, item_id: String, count: int) -> void:
	if from_source == BAG_SOURCE and target_source == BOX_SOURCE:
		if not StorageBoxManager.can_add_item_to_box(_map_id, _cell, item_id, count):
			_show_message("상자에 넣을 공간이 없다.")
			return
		InventoryManager.remove_item(item_id, count)
		StorageBoxManager.add_item_to_box(_map_id, _cell, item_id, count)
	elif from_source == BOX_SOURCE and target_source == BAG_SOURCE:
		if not InventoryManager.can_add_item(item_id, count):
			_show_message("인벤토리에 넣을 공간이 없다.")
			return
		StorageBoxManager.remove_item_from_box(_map_id, _cell, item_id, count)
		InventoryManager.add_item(item_id, count)
	_refresh()


func _on_sort_pressed() -> void:
	StorageBoxManager.sort_box(_map_id, _cell)


func _on_pickup_pressed() -> void:
	var message := StorageBoxManager.remove_box(_map_id, _cell)
	if not message.is_empty():
		_show_message(message)
		return
	close()


func _show_message(text: String) -> void:
	_message_label.text = text


## shop_screen.gd/equipment_panel.gd와 동일한 스크롤바 스타일 - 창마다
## 굵기/색이 달라 보인다는 피드백으로 전부 통일한다.
func _style_scrollbar(scroll: ScrollContainer) -> void:
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.15)
	track.set_corner_radius_all(2)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.55, 0.4, 0.25, 0.9)
	grabber.set_corner_radius_all(2)
	scrollbar.add_theme_stylebox_override("scroll", track)
	scrollbar.add_theme_stylebox_override("grabber", grabber)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber)
