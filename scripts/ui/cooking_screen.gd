extends Control

## cooking.md UI: 요리대 상호작용으로 열리는 화면. Main이 cooking_station_interacted
## 신호로 open_cooking(station_index)를 호출한다. 재료 2개를 슬롯에 담고 냄비를 눌러
## RestaurantManager.cook_and_serve()를 호출한다. 창이 좁아 문구를 넣을 자리가 없어서
## 결과는 냄비 색상 플래시 + 효과음으로만 표현한다.

const READY_TINT_DIM := Color(0.95, 0.92, 0.75, 1.0)
const READY_TINT_BRIGHT := Color(1.3, 1.25, 1.0, 1.0)
const DIM_TINT := Color(0.55, 0.55, 0.55, 1.0)
const NORMAL_TINT := Color(1.0, 1.0, 1.0, 1.0)
const FAIL_TINT := Color(1.6, 0.5, 0.5, 1.0)
const RAT_POISON_ARMED_TINT := Color(1.0, 0.4, 0.4, 1.0)
const RAT_POISON_INACTIVE_TINT := Color(0.45, 0.45, 0.45, 1.0)
const INGREDIENT_LOCKED_TINT := Color(0.45, 0.45, 0.45, 1.0)
const PULSE_DURATION := 0.8

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _pot: TextureButton = $Background/Pot
@onready var _slot_a: TextureButton = $Background/Pot/SlotA
@onready var _slot_a_icon: TextureRect = $Background/Pot/SlotA/Icon
@onready var _slot_b: TextureButton = $Background/Pot/SlotB
@onready var _slot_b_icon: TextureRect = $Background/Pot/SlotB/Icon
@onready var _ingredient_grid: GridContainer = $Background/InventoryPanel/InventoryScroll/InventoryGrid
@onready var _ingredient_scroll: ScrollContainer = $Background/InventoryPanel/InventoryScroll
@onready var _rat_poison_toggle: TextureButton = $Background/Pot/RatPoisonToggle
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
	_pot.pressed.connect(_on_pot_pressed)
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


func _unhandled_input(event: InputEvent) -> void:
	if _is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _is_confirm_open():
			_on_confirm_no()
		else:
			close()


func open_cooking(station_index: int) -> void:
	_station_index = station_index
	_selected_a = ""
	_selected_b = ""
	_rat_poison_toggle.button_pressed = false
	_rat_poison_toggle.disabled = false
	_rat_poison_toggle.modulate = RAT_POISON_INACTIVE_TINT
	_set_confirm_open(false)
	_refresh_ingredient_grid()
	_refresh_selected_icons()
	_refresh_pot_state()
	_refresh_ingredient_lock()
	_set_open(true)


func close() -> void:
	_set_confirm_open(false)
	_set_open(false)


func _is_open() -> bool:
	return modulate.a > 0.0


## 자식을 하나하나 나열해서 껐다 켰다 하면(예전 방식) InventoryPanel처럼
## 목록에서 빠뜨린 배경 컨트롤이 기본값(STOP)으로 계속 남아서, 창을 닫아도
## 그 자리의 다른 화면 클릭을 계속 먹는 문제가 반복됐다(collection_screen
## 에서도 같은 문제가 있었음). 서브트리 전체를 재귀로 순회해서 빠짐없이
## 처리하되, SlotA/SlotB 안의 Icon처럼 "항상 마우스를 무시해야 하는" 장식용
## 오버레이는 _ALWAYS_IGNORE_MOUSE 그룹으로 표시해두고 건드리지 않는다.
const _ALWAYS_IGNORE_MOUSE_GROUP := &"_always_ignore_mouse"


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
	modulate.a = 1.0 if is_open else 0.0
	var filter := Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	# ConfirmPopup(쥐약 확인창)은 Background의 형제 노드라 여기 안 걸리고,
	# _set_confirm_open()이 따로 독립적으로 관리한다.
	_apply_mouse_filter_recursive($Background, filter)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control and not node.is_in_group(_ALWAYS_IGNORE_MOUSE_GROUP):
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _clear_selected(slot: int) -> void:
	if slot == 0:
		_selected_a = ""
	else:
		_selected_b = ""
	_refresh_selected_icons()
	_refresh_pot_state()
	_refresh_ingredient_lock()


## F9 같은 디버그 치트나 낚시/채집으로 요리창을 연 채로 재료를 얻는 경우,
## open_cooking() 때 한 번만 그리던 재료 목록이 새로 생긴 재료를 못 비추는
## 문제가 있었다. 인벤토리가 바뀔 때마다 (창이 열려 있으면) 다시 그린다.
func _on_inventory_changed() -> void:
	if not _is_open():
		return
	_refresh_ingredient_grid()
	_refresh_ingredient_lock()


## 창이 열려 있는 동안 손님이 식사를 마치고 떠나거나(다른 요리대일 수도 있는
## 손님이 방금 요리를 받거나) 하면, 지금 보고 있는 요리대의 냄비 상태(손님
## 있음/이미 서빙함)가 그새 바뀌었을 수 있다 - 다시 계산해서 반영한다.
func _on_station_state_changed(_station_index: int, _npc_id: String = "", _dish: Dictionary = {}) -> void:
	if not _is_open():
		return
	_refresh_pot_state()


func _refresh_ingredient_grid() -> void:
	for child in _ingredient_grid.get_children():
		child.queue_free()
	var seen_ids: Dictionary = {}
	for slot in InventoryManager.get_slots():
		if slot == null:
			continue
		var item_id := String(slot.get("item_id", ""))
		if seen_ids.has(item_id):
			continue
		var definition := InventoryManager.get_item_definition(item_id)
		if String(definition.get("category", "")) != "material" or String(definition.get("subtype", "")) == "seed":
			continue
		seen_ids[item_id] = true
		_ingredient_grid.add_child(_build_ingredient_button(item_id))
	# 폴리/세이지/라마(can_die:false)한테는 독살이 애초에 안 먹히니(MurderManager.
	# _on_npc_poisoned() 참고) 서빙 대상이 그 셋 중 하나면 토글 자체를 숨긴다
	# (사용자 지시, 2026-08-26 - serving_screen.gd와 동일한 이유).
	var current_npc_id := RestaurantManager.get_station_npc(_station_index)
	_rat_poison_toggle.visible = InventoryManager.has_item("rat_poison", 1) and NPCManager.can_die(current_npc_id)


func _build_ingredient_button(item_id: String) -> TextureButton:
	var button := TextureButton.new()
	button.custom_minimum_size = Vector2(6, 6)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_normal = InventoryManager.get_item_icon_texture(item_id)
	button.pressed.connect(func() -> void: _on_ingredient_picked(item_id))
	return button


func _on_ingredient_picked(item_id: String) -> void:
	if not _selected_a.is_empty() and not _selected_b.is_empty():
		return
	if _selected_a.is_empty():
		_selected_a = item_id
	else:
		_selected_b = item_id
	_refresh_selected_icons()
	_refresh_pot_state()
	_refresh_ingredient_lock()


func _refresh_selected_icons() -> void:
	_slot_a_icon.texture = InventoryManager.get_item_icon_texture(_selected_a) if not _selected_a.is_empty() else null
	_slot_b_icon.texture = InventoryManager.get_item_icon_texture(_selected_b) if not _selected_b.is_empty() else null


## 슬롯 2개가 다 차면 재료창을 어둡게 잠가서, 추가로 재료를 눌러 기존 선택을
## 덮어써버리는 일이 없도록 한다 (슬롯을 직접 비워야만 다시 고를 수 있음).
func _refresh_ingredient_lock() -> void:
	var is_full := not _selected_a.is_empty() and not _selected_b.is_empty()
	_ingredient_grid.modulate = INGREDIENT_LOCKED_TINT if is_full else NORMAL_TINT
	for child in _ingredient_grid.get_children():
		if child is BaseButton:
			child.disabled = is_full


## 쥐약은 비활성 -> 활성으로 켤 때만 확인을 받는다 (끄는 쪽은 되돌리는 거라
## 안전하므로 바로 처리). NPCManager 쪽에 실제 독살 반영은 cook_and_serve()가
## use_rat_poison 값을 그대로 넘길 때 이미 처리된다 - 여기서는 UI 확인만 담당.
func _on_rat_poison_toggled(pressed: bool) -> void:
	if pressed:
		_set_confirm_open(true)
	else:
		_rat_poison_toggle.modulate = RAT_POISON_INACTIVE_TINT


## shop_screen.gd과 같은 방식: button.png/button_hover.png로 9-슬라이스 스타일을
## 입히고, 진한 글자색을 직접 override해서 기본 엔진 버튼의 칙칙한 회색 모양
## 대신 게임 톤에 맞는 버튼으로 보이게 한다.
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


## 한번 활성화하면 실수로 다시 눌러 꺼버리는 일이 없도록 버튼 자체를 잠근다 -
## 요리창을 닫았다 다시 열어야만(open_cooking이 disabled를 초기화) 되돌릴 수 있다.
func _on_confirm_yes() -> void:
	_set_confirm_open(false)
	_rat_poison_toggle.modulate = RAT_POISON_ARMED_TINT
	_rat_poison_toggle.disabled = true


func _on_confirm_no() -> void:
	_set_confirm_open(false)
	_rat_poison_toggle.button_pressed = false


## 크기를 바꾸면 테두리가 움직이는 것처럼 보여서, 대신 밝기만 두근거리듯
## 오르내리게 한다 (위치/크기는 그대로 고정).
func _refresh_pot_state() -> void:
	var is_ready := not _selected_a.is_empty() and not _selected_b.is_empty() \
		and not RestaurantManager.get_station_npc(_station_index).is_empty() \
		and RestaurantManager.get_station_dish(_station_index).is_empty()
	_pot.disabled = not is_ready
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if is_ready:
		_pot.modulate = READY_TINT_DIM
		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(_pot, "modulate", READY_TINT_BRIGHT, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(_pot, "modulate", READY_TINT_DIM, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
	else:
		_pot.modulate = DIM_TINT


## 성공하면 창을 바로 닫는다 - 요리가 식탁 위에 놓이는 걸(RestaurantDishLayer가
## dish_served 신호를 받아 처리) 플레이어가 바로 볼 수 있게. 실패했을 때만
## 냄비를 붉게 반짝이고 창은 열어둔 채로 다시 시도할 수 있게 한다.
func _on_pot_pressed() -> void:
	var use_rat_poison := _rat_poison_toggle.button_pressed
	var success := RestaurantManager.cook_and_serve(_station_index, _selected_a, _selected_b, use_rat_poison)
	_selected_a = ""
	_selected_b = ""
	_rat_poison_toggle.button_pressed = false
	if success:
		AudioManager.play_sfx(AudioManager.SFX_POSITIVE_BEEP)
		close()
		return
	_refresh_selected_icons()
	_refresh_ingredient_grid()
	_refresh_pot_state()
	_refresh_ingredient_lock()
	_flash_pot_fail()
	AudioManager.play_sfx(AudioManager.SFX_BEEP)


func _flash_pot_fail() -> void:
	var base_tint := _pot.modulate
	var tween := create_tween()
	tween.tween_property(_pot, "modulate", FAIL_TINT, 0.1)
	tween.tween_property(_pot, "modulate", base_tint, 0.15)
