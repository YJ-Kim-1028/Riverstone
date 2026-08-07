extends Control

## StorageBoxManager가 관리하는 상자 하나를 여닫는 화면. kitchen_screen.gd와
## 동일하게 plain visible로 열고 닫는다 - 동적으로 슬롯을 채우는 그리드
## 화면은 visible=true를 먼저 하고 그 다음에 채워야(open_kitchen()과 동일한
## 순서) shop_screen.gd가 문서화한 "ancestor.visible이 한 번이라도 false였던
## 컨트롤은 폰트/모듈레이트가 깨지는" 버그를 피할 수 있다.
## 왼쪽 = 플레이어 인벤토리, 오른쪽 = 상자 내용물. 둘 다 inventory_slot.tscn을
## 재사용하고, 드래그로 서로 아이템을 옮긴다(inventory_slot.gd의
## accepts_drops/source_tag 확장 참고). 드래그는 항상 그 슬롯의 전체 스택을
## 옮긴다(부분 이동/분할 없음 - 이 프로젝트의 다른 드래그 상호작용과 동일).

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

## inventory_slot.gd의 DISABLED_TINT와 동일한 톤 - TextureButton은 Button과
## 달리 disabled여도 저절로 어두워지지 않아서 직접 modulate를 덮어써야 한다.
const PICKUP_DISABLED_TINT := Color(0.45, 0.45, 0.45, 1.0)

var _map_id := ""
var _cell := Vector2i.ZERO
## open_box()가 딜레이 중일 때 다시 눌려도(연타/재접근) 중복으로 안 들어가게
## 막는다 - 이 동안은 visible이 아직 false라 _is_open()만으로는 구분이 안 됨.
var _opening := false


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	_pickup_button.pressed.connect(_on_pickup_pressed)
	_sort_button.pressed.connect(_on_sort_pressed)
	InventoryManager.inventory_changed.connect(_refresh)
	StorageBoxManager.boxes_changed.connect(_refresh)
	_style_scrollbar(_bag_scroll)
	_style_scrollbar(_box_scroll)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_box(cell: Vector2i) -> void:
	if visible or _opening:
		return
	_opening = true
	_map_id = GameManager.current_map_id
	_cell = cell
	_message_label.text = ""
	StorageBoxManager.set_box_open_visual(cell, true)
	AudioManager.play_sfx(AudioManager.SFX_DOOR)
	await get_tree().create_timer(OPEN_DELAY_SECONDS).timeout
	_opening = false
	visible = true
	_refresh()


func close() -> void:
	if visible:
		StorageBoxManager.set_box_open_visual(_cell, false)
	visible = false


func _is_open() -> bool:
	return visible


func current_cell() -> Vector2i:
	return _cell


func _refresh() -> void:
	if not visible:
		return
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
		slot_instance.connect("slot_drop_received", _on_slot_drop_received)


func _on_slot_drop_received(target_source: String, _target_index: int, data: Dictionary) -> void:
	var from_source := String(data.get("source", ""))
	if from_source == target_source or from_source.is_empty():
		return
	var item_id := String(data.get("item_id", ""))
	var count := int(data.get("count", 0))
	if item_id.is_empty() or count <= 0:
		return
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
