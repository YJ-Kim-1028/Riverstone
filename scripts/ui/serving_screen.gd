extends Control

## new_cooking_system.md 3.4/3.5 - 완성대(serving_area) 화면. Main이
## serving_area_interacted 신호로 open_serving(station_index)를 호출한다.
## 조리된 재료(category=="cooked_ingredient") 2개를 슬롯에 담고 완성 버튼을
## 누르면 RestaurantManager.cook_and_serve()를 호출한다. 쥐약 토글+확인 팝업은
## cooking_screen.gd(옛 요리대 UI)의 패턴을 그대로 재사용한다(3.5 확정 사항).
## 인벤토리 그리드는 kitchen_screen.gd와 동일하게 "전체 표시 + disabled"
## 방식(사용자 확정) - 옛 cooking_screen처럼 목록 자체를 필터링해서 숨기지 않는다.

const SlotScene := preload("res://scenes/ui/inventory_slot.tscn")
const SCROLLBAR_WIDTH := 4
const SELECTABLE_CATEGORY := "cooked_ingredient"

const READY_TINT_DIM := Color(0.95, 0.92, 0.75, 1.0)
const READY_TINT_BRIGHT := Color(1.3, 1.25, 1.0, 1.0)
const DIM_TINT := Color(0.55, 0.55, 0.55, 1.0)
const FAIL_TINT := Color(1.6, 0.5, 0.5, 1.0)
const RAT_POISON_ARMED_TINT := Color(1.0, 0.4, 0.4, 1.0)
const RAT_POISON_INACTIVE_TINT := Color(0.45, 0.45, 0.45, 1.0)
const PULSE_DURATION := 0.8

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _complete_button: Button = $Background/Margin/VBox/PlateRow/CompleteButton
@onready var _slot_a: TextureButton = $Background/Margin/VBox/PlateRow/SlotA
@onready var _slot_a_icon: TextureRect = $Background/Margin/VBox/PlateRow/SlotA/Icon
@onready var _slot_b: TextureButton = $Background/Margin/VBox/PlateRow/SlotB
@onready var _slot_b_icon: TextureRect = $Background/Margin/VBox/PlateRow/SlotB/Icon
@onready var _rat_poison_toggle: TextureButton = $Background/Margin/VBox/PlateRow/RatPoisonToggle
@onready var _grid_scroll: ScrollContainer = $Background/Margin/VBox/GridScroll
@onready var _grid: GridContainer = $Background/Margin/VBox/GridScroll/GridMargin/Grid
@onready var _close_button: TextureButton = $Background/CloseButton
@onready var _confirm_popup: Control = $ConfirmPopup
@onready var _confirm_dim: ColorRect = $ConfirmPopup/Dim
@onready var _confirm_yes: Button = $ConfirmPopup/Panel/Margin/VBox/ButtonRow/YesButton
@onready var _confirm_no: Button = $ConfirmPopup/Panel/Margin/VBox/ButtonRow/NoButton

var _station_index := -1
var _selected_a := ""
var _selected_b := ""
var _pulse_tween: Tween


func _ready() -> void:
	_set_open(false)
	_complete_button.pressed.connect(_on_complete_pressed)
	_style_confirm_button(_complete_button)
	_slot_a.pressed.connect(func() -> void: _clear_selected(0))
	_slot_b.pressed.connect(func() -> void: _clear_selected(1))
	_rat_poison_toggle.texture_normal = InventoryManager.get_item_icon_texture("rat_poison")
	_rat_poison_toggle.toggled.connect(_on_rat_poison_toggled)
	_close_button.pressed.connect(close)
	_set_confirm_open(false)
	_style_confirm_button(_confirm_yes)
	_style_confirm_button(_confirm_no)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_no.pressed.connect(_on_confirm_no)
	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	RestaurantManager.npc_departed.connect(_on_station_state_changed)
	RestaurantManager.dish_served.connect(_on_station_state_changed)
	_style_scrollbar()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _is_confirm_open():
			_on_confirm_no()
		else:
			close()


func open_serving(station_index: int) -> void:
	_station_index = station_index
	_selected_a = ""
	_selected_b = ""
	_rat_poison_toggle.button_pressed = false
	_rat_poison_toggle.disabled = false
	_rat_poison_toggle.modulate = RAT_POISON_INACTIVE_TINT
	_set_confirm_open(false)
	_refresh_grid()
	_refresh_selected_icons()
	_refresh_plate_state()
	_set_open(true)


## 완성하지 않고 ESC나 닫기 버튼으로 나가면, 슬롯에 미리 빼둔 재료를 인벤토리로
## 돌려준다(사용자 지시 - 슬롯에 넣는 순간 인벤토리에서 -1, 완성 못 하고 닫으면
## 다시 +1).
func close() -> void:
	_return_selected_to_inventory()
	_set_confirm_open(false)
	_set_open(false)


func _return_selected_to_inventory() -> void:
	if not _selected_a.is_empty():
		InventoryManager.add_item(_selected_a, 1)
		_selected_a = ""
	if not _selected_b.is_empty():
		InventoryManager.add_item(_selected_b, 1)
		_selected_b = ""


func _is_open() -> bool:
	return modulate.a > 0.0


func current_station_index() -> int:
	return _station_index


const _ALWAYS_IGNORE_MOUSE_GROUP := &"_always_ignore_mouse"


func _set_open(is_open: bool) -> void:
	modulate.a = 1.0 if is_open else 0.0
	var filter := Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	_apply_mouse_filter_recursive($Background, filter)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control and not node.is_in_group(_ALWAYS_IGNORE_MOUSE_GROUP):
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


## 슬롯을 눌러서 비우면(SlotA/SlotB 클릭) 빼뒀던 재료를 인벤토리로 돌려준다.
func _clear_selected(slot: int) -> void:
	var item_id := _selected_a if slot == 0 else _selected_b
	if not item_id.is_empty():
		InventoryManager.add_item(item_id, 1)
	if slot == 0:
		_selected_a = ""
	else:
		_selected_b = ""
	_refresh_selected_icons()
	_refresh_plate_state()
	_refresh_grid()


func _on_inventory_changed() -> void:
	if not _is_open():
		return
	_refresh_grid()


func _on_station_state_changed(_station_index: int, _npc_id: String = "", _dish: Dictionary = {}) -> void:
	if not _is_open():
		return
	_refresh_plate_state()


func _refresh_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var slots: Array = InventoryManager.get_slots()
	var both_full := not _selected_a.is_empty() and not _selected_b.is_empty()
	for i in slots.size():
		var slot_instance := SlotScene.instantiate() as TextureButton
		_grid.add_child(slot_instance)
		slot_instance.call("setup", i, slots[i])
		# _set_open()의 _apply_mouse_filter_recursive()가 열릴 때 $Background
		# 밑의 모든 Control을 STOP으로 덮어써서, 이 그리드 슬롯의 Icon/CountLabel도
		# (SlotA/SlotB와 달리 애초에 그룹 태그가 없어) 클릭을 가로채 슬롯 본체
		# TextureButton까지 못 가게 막고 있었다 - 아이콘을 클릭하면 선택이
		# 안 되고 슬롯 여백만 눌러야 되던 버그의 원인. 동적으로 만들어지는
		# 노드라 그룹에 즉시 추가해준다.
		slot_instance.get_node("Icon").add_to_group(_ALWAYS_IGNORE_MOUSE_GROUP)
		slot_instance.get_node("CountLabel").add_to_group(_ALWAYS_IGNORE_MOUSE_GROUP)
		var item_id := ""
		if slots[i] != null:
			item_id = String(slots[i].get("item_id", ""))
		var eligible := not item_id.is_empty() and InventoryManager.get_item_category(item_id) == SELECTABLE_CATEGORY
		slot_instance.call("set_enabled", eligible and not both_full)
		slot_instance.connect("slot_pressed", _on_slot_pressed)
	# cooking_screen.gd(_refresh_ingredient_grid)와 같은 처리 - 여기선 빠져있어서
	# 쥐약을 산 적이 없어도 토글 아이콘이 계속 보이는 버그가 있었다(사용자 리포트).
	_rat_poison_toggle.visible = InventoryManager.has_item("rat_poison", 1)


func _on_slot_pressed(index: int) -> void:
	if not _selected_a.is_empty() and not _selected_b.is_empty():
		return
	var slots: Array = InventoryManager.get_slots()
	if index < 0 or index >= slots.size() or slots[index] == null:
		return
	var item_id := String(slots[index].get("item_id", ""))
	if InventoryManager.get_item_category(item_id) != SELECTABLE_CATEGORY:
		return
	## 슬롯에 넣는 순간 인벤토리에서 바로 뺀다(사용자 지시) - 완성 못 하고 나가면
	## close()/_clear_selected()가 되돌려준다.
	if not InventoryManager.remove_item(item_id, 1):
		return
	if _selected_a.is_empty():
		_selected_a = item_id
	else:
		_selected_b = item_id
	_refresh_selected_icons()
	_refresh_plate_state()
	_refresh_grid()
	AudioManager.play_sfx(AudioManager.SFX_UI_SLOT_IN)


func _refresh_selected_icons() -> void:
	_slot_a_icon.texture = InventoryManager.get_item_icon_texture(_selected_a) if not _selected_a.is_empty() else null
	_slot_b_icon.texture = InventoryManager.get_item_icon_texture(_selected_b) if not _selected_b.is_empty() else null


func _on_rat_poison_toggled(pressed: bool) -> void:
	if pressed:
		_set_confirm_open(true)
	else:
		_rat_poison_toggle.modulate = RAT_POISON_INACTIVE_TINT


func _style_confirm_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)


func _build_button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	return style


func _is_confirm_open() -> bool:
	return _confirm_popup.modulate.a > 0.0


func _set_confirm_open(is_open: bool) -> void:
	_confirm_popup.modulate.a = 1.0 if is_open else 0.0
	var filter := Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
	_confirm_popup.mouse_filter = filter
	_confirm_dim.mouse_filter = filter
	_confirm_yes.mouse_filter = filter
	_confirm_no.mouse_filter = filter


func _on_confirm_yes() -> void:
	_set_confirm_open(false)
	_rat_poison_toggle.modulate = RAT_POISON_ARMED_TINT
	_rat_poison_toggle.disabled = true


func _on_confirm_no() -> void:
	_set_confirm_open(false)
	_rat_poison_toggle.button_pressed = false


func _refresh_plate_state() -> void:
	var is_ready := not _selected_a.is_empty() and not _selected_b.is_empty() \
		and RestaurantManager.is_station_npc_settled(_station_index) \
		and RestaurantManager.get_station_dish(_station_index).is_empty()
	_complete_button.disabled = not is_ready
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if is_ready:
		_complete_button.modulate = READY_TINT_DIM
		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(_complete_button, "modulate", READY_TINT_BRIGHT, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(_complete_button, "modulate", READY_TINT_DIM, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
	else:
		_complete_button.modulate = DIM_TINT


func _on_complete_pressed() -> void:
	var use_rat_poison := _rat_poison_toggle.button_pressed
	var ingredient_a := _selected_a
	var ingredient_b := _selected_b
	## cook_and_serve()가 내부적으로 인벤토리에서 다시 재료를 소모하는 구조라
	## (CookingManager는 안 건드림), 슬롯에 넣을 때 미리 빼뒀던 걸 여기서
	## 되돌려준 다음 그대로 넘긴다 - 기존 소모 로직을 그대로 재사용하기 위함.
	if not ingredient_a.is_empty():
		InventoryManager.add_item(ingredient_a, 1)
	if not ingredient_b.is_empty():
		InventoryManager.add_item(ingredient_b, 1)
	var success := RestaurantManager.cook_and_serve(_station_index, ingredient_a, ingredient_b, use_rat_poison)
	_selected_a = ""
	_selected_b = ""
	_rat_poison_toggle.button_pressed = false
	if success:
		AudioManager.play_sfx(AudioManager.SFX_POSITIVE_BEEP)
		close()
		return
	_refresh_selected_icons()
	_refresh_grid()
	_refresh_plate_state()
	_flash_complete_fail()
	AudioManager.play_sfx(AudioManager.SFX_BEEP)


func _flash_complete_fail() -> void:
	var base_tint := _complete_button.modulate
	var tween := create_tween()
	tween.tween_property(_complete_button, "modulate", FAIL_TINT, 0.1)
	tween.tween_property(_complete_button, "modulate", base_tint, 0.15)


func _style_scrollbar() -> void:
	var scrollbar := _grid_scroll.get_v_scroll_bar()
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
