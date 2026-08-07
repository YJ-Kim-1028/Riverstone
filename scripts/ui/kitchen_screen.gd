extends Control

## new_cooking_system.md 3.3 - 조리기구(냄비/프라이팬/도마/믹서기) 화면. Main이
## kitchen_station_interacted 신호로 open_kitchen(station_id)를 호출한다.
## 인벤토리 슬롯을 클릭해서 원재료를 고르고, "조리 시작" 버튼을 눌러 시작한다
## (드래그 방식을 써봤는데 작은 슬롯에서 정밀하게 끌어다 놓기가 불편하다는
## 사용자 피드백으로 클릭+버튼 방식으로 되돌림 - 이 버튼 방식 자체는 유지).
## 시작하면 창을 닫고, 조리 진행은 KitchenProgressLayer가 월드에 띄우는 작은
## 진행바로 확인한다 - 다 되면 다시 이 화면을 열어 상태 아이콘을 눌러서
## 회수한다. 상태 아이콘은 조리기구 그림(ToolVessel/ToolImage) 위에 겹쳐
## 놓여서 "재료가 기구 위에 놓인" 느낌을 내고, 조리 중에는 살짝 흔들린다
## (사용자 피드백 - 슬롯에 넣는 느낌만 나고 요리하는 느낌이 안 난다고 함).

const SlotScene := preload("res://scenes/ui/inventory_slot.tscn")
const SCROLLBAR_WIDTH := 4

const READY_TINT_DIM := Color(0.95, 0.92, 0.75, 1.0)
const READY_TINT_BRIGHT := Color(1.3, 1.25, 1.0, 1.0)
const DIM_TINT := Color(0.55, 0.55, 0.55, 1.0)
const FAIL_TINT := Color(1.6, 0.5, 0.5, 1.0)
const PULSE_DURATION := 0.8

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

## 사용자가 assets/img/restaurant/에 넣어준 조리기구 그림(cooking_stations.json
## 의 area1~4 대응 그대로) - ToolVessel 안에서 상태 아이콘 뒤에 크게 보여준다.
const STATION_BACKDROP_TEXTURES := {
	"cooking_area1": preload("res://assets/img/restaurant/img_pot.png"),
	"cooking_area2": preload("res://assets/img/restaurant/img_pan.png"),
	"cooking_area3": preload("res://assets/img/restaurant/img_knife.png"),
	"cooking_area4": preload("res://assets/img/restaurant/img_mixer.png"),
}
## 조리 중일 때 냄비/프라이팬 등이 살짝 흔들리는 각도(라디안) - deg_to_rad(3).
const SHAKE_ANGLE := 0.0524
const SHAKE_DURATION := 0.12

@onready var _grid_scroll: ScrollContainer = $Background/Margin/VBox/GridScroll
@onready var _grid: GridContainer = $Background/Margin/VBox/GridScroll/GridMargin/Grid
@onready var _tool_label: Label = $Background/Margin/VBox/StatusRow/ToolLabel
@onready var _tool_vessel: Control = $Background/Margin/VBox/StatusRow/ToolVessel
@onready var _tool_image: TextureRect = $Background/Margin/VBox/StatusRow/ToolVessel/ToolImage
@onready var _status_icon: TextureButton = $Background/Margin/VBox/StatusRow/ToolVessel/StatusIcon
@onready var _status_icon_texture: TextureRect = $Background/Margin/VBox/StatusRow/ToolVessel/StatusIcon/Icon
@onready var _start_button: Button = $Background/Margin/VBox/StatusRow/StartButton
@onready var _close_button: TextureButton = $Background/CloseButton

var _station_id := ""
var _slots: Array = []
var _selected_item_id := ""
var _pulse_tween: Tween
var _shake_tween: Tween
var _ready_glow_tween: Tween
var _was_busy := false
var _was_ready := false


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	_status_icon.pressed.connect(_on_status_icon_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_style_confirm_button(_start_button)
	InventoryManager.inventory_changed.connect(_refresh)
	_style_scrollbar()


func _process(_delta: float) -> void:
	if not visible or _station_id.is_empty():
		return
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_kitchen(station_id: String) -> void:
	_station_id = station_id
	_selected_item_id = ""
	_tool_label.text = KitchenManager.get_tool_name(station_id)
	_tool_image.texture = STATION_BACKDROP_TEXTURES.get(station_id)
	# close()가 아닌 다른 경로로 이전에 숨겨졌을 가능성까지 대비해서, 새로
	# 열 때도 항상 흔들림/글로우를 확실히 꺼둔 상태에서 시작한다 - 안 그러면
	# 이전 기구에서 켜져 있던 트윈이 이 ToolVessel(공용 노드)에 남아있는 동안
	# 새 기구가 조리 중이 아닌데도 흔들려 보일 수 있다.
	_set_shaking(false)
	_set_ready_glow(false)
	_was_busy = false
	_was_ready = false
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_set_shaking(false)
	_set_ready_glow(false)
	_was_busy = false
	_was_ready = false


func _is_open() -> bool:
	return visible


func current_station_id() -> String:
	return _station_id


func _refresh() -> void:
	if _station_id.is_empty():
		return
	_update_status()
	for child in _grid.get_children():
		child.queue_free()
	_slots = InventoryManager.get_slots()
	var available: Array = KitchenManager.get_available_ingredients(_station_id)
	var busy := KitchenManager.is_busy(_station_id)
	for i in _slots.size():
		var slot_instance := SlotScene.instantiate() as TextureButton
		_grid.add_child(slot_instance)
		slot_instance.call("setup", i, _slots[i])
		var item_id := ""
		if _slots[i] != null:
			item_id = String(_slots[i].get("item_id", ""))
		var enabled := not busy and not item_id.is_empty() and available.has(item_id) and KitchenManager.can_start(_station_id, item_id)
		slot_instance.call("set_enabled", enabled)
		slot_instance.connect("slot_pressed", _on_slot_pressed)
	_refresh_start_button()


func _on_slot_pressed(index: int) -> void:
	if KitchenManager.is_busy(_station_id):
		return
	if index < 0 or index >= _slots.size() or _slots[index] == null:
		return
	var item_id := String(_slots[index].get("item_id", ""))
	var available: Array = KitchenManager.get_available_ingredients(_station_id)
	if not available.has(item_id) or not KitchenManager.can_start(_station_id, item_id):
		return
	_selected_item_id = item_id
	_update_status()
	_refresh_start_button()
	AudioManager.play_sfx(AudioManager.SFX_UI_SLOT_IN)


## 조리 중이면 다 됐을 때 회수하고, 아니면 선택한 재료를 취소하는 용도로 겸용.
func _on_status_icon_pressed() -> void:
	if _station_id.is_empty():
		return
	if KitchenManager.is_busy(_station_id):
		if KitchenManager.is_ready(_station_id) and KitchenManager.collect(_station_id):
			_refresh()
		return
	if not _selected_item_id.is_empty():
		_selected_item_id = ""
		_update_status()
		_refresh_start_button()


func _on_start_pressed() -> void:
	if _selected_item_id.is_empty():
		return
	var item_id := _selected_item_id
	if KitchenManager.start_cooking(_station_id, item_id):
		_selected_item_id = ""
		# 조리대 시작 버튼 소리가 유독 크다는 피드백(사용자 지시)으로 이 위치만
		# -6dB 낮춤 - cooking_screen/serving_screen의 같은 성공음은 그대로.
		AudioManager.play_sfx(AudioManager.SFX_POSITIVE_BEEP, -6.0)
		AudioManager.play_cooking_sfx(KitchenManager.get_tool_name(_station_id), KitchenManager.get_duration(_station_id))
		close()
		return
	_flash_start_fail()
	AudioManager.play_sfx(AudioManager.SFX_BEEP)


func _flash_start_fail() -> void:
	var tween := create_tween()
	tween.tween_property(_status_icon, "modulate", FAIL_TINT, 0.1)
	tween.tween_property(_status_icon, "modulate", Color.WHITE, 0.15)


func _refresh_start_button() -> void:
	_start_button.disabled = _selected_item_id.is_empty() or KitchenManager.is_busy(_station_id)
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if not _start_button.disabled:
		_start_button.modulate = READY_TINT_DIM
		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(_start_button, "modulate", READY_TINT_BRIGHT, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(_start_button, "modulate", READY_TINT_DIM, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
	else:
		_start_button.modulate = DIM_TINT


func _update_status() -> void:
	var busy := KitchenManager.is_busy(_station_id)
	# is_busy()는 다 익어서 회수만 하면 되는 상태에서도 계속 true라서(회수
	# 전까지 기구가 "차 있는" 상태), 진행바를 없앤 뒤로는 이 둘을 구분할
	# 방법이 없어서 다 됐는데도 계속 "조리 중"으로 보이는 문제가 있었다
	# (사용자 리포트 - 기다려도 조리된 재료로 안 바뀐 것처럼 보인다고 함).
	# 실제로는 이미 다 됐고 회수만 안 한 상태였다 - ready 상태를 따로 표시.
	var ready := busy and KitchenManager.is_ready(_station_id)
	if ready:
		# 다 익었으면 원재료가 아니라 조리된 재료 아이콘으로 바꿔서 보여준다
		# (사용자 리포트 - 계속 원재료 그림이라 조리됐는지 구분이 안 됐음).
		_status_icon_texture.texture = InventoryManager.get_item_icon_texture(KitchenManager.get_cooking_result(_station_id))
	elif busy:
		_status_icon_texture.texture = InventoryManager.get_item_icon_texture(KitchenManager.get_cooking_ingredient(_station_id))
	elif not _selected_item_id.is_empty():
		_status_icon_texture.texture = InventoryManager.get_item_icon_texture(_selected_item_id)
	else:
		_status_icon_texture.texture = null
	if busy != _was_busy or ready != _was_ready:
		_was_busy = busy
		_was_ready = ready
		_set_shaking(busy and not ready)
		_set_ready_glow(ready)


## 조리 중일 때 조리기구가 살짝 흔들리게 해서 "지금 조리되고 있다"는 걸
## 진행바 말고도 느낌으로 알 수 있게 한다(사용자 피드백 - 슬롯에 넣는 느낌만
## 나고 요리하는 느낌이 안 난다고 함).
func _set_shaking(shaking: bool) -> void:
	if _shake_tween != null:
		_shake_tween.kill()
		_shake_tween = null
	_tool_vessel.rotation = 0.0
	if not shaking:
		return
	_shake_tween = create_tween()
	_shake_tween.set_loops()
	_shake_tween.tween_property(_tool_vessel, "rotation", SHAKE_ANGLE, SHAKE_DURATION).set_ease(Tween.EASE_IN_OUT)
	_shake_tween.tween_property(_tool_vessel, "rotation", -SHAKE_ANGLE, SHAKE_DURATION).set_ease(Tween.EASE_IN_OUT)
	_shake_tween.tween_property(_tool_vessel, "rotation", 0.0, SHAKE_DURATION).set_ease(Tween.EASE_IN_OUT)


## 다 익어서 회수만 하면 되는 상태를 흔들림 대신 밝기 펄스로 알려준다
## (조리 시작 버튼이 준비됐을 때 쓰는 것과 같은 톤).
func _set_ready_glow(is_ready: bool) -> void:
	if _ready_glow_tween != null:
		_ready_glow_tween.kill()
		_ready_glow_tween = null
	_tool_vessel.modulate = Color.WHITE
	if not is_ready:
		return
	_ready_glow_tween = create_tween()
	_ready_glow_tween.set_loops()
	_ready_glow_tween.tween_property(_tool_vessel, "modulate", READY_TINT_BRIGHT, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
	_ready_glow_tween.tween_property(_tool_vessel, "modulate", READY_TINT_DIM, PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)


## serving_screen.gd/cooking_screen.gd와 동일한 버튼 스타일링(9-슬라이스
## button.png + 진한 글자색)을 재사용한다.
func _style_confirm_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("disabled", _build_button_style(BUTTON_TEXTURE))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_disabled_color", BUTTON_TEXT_COLOR)


func _build_button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	return style


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
