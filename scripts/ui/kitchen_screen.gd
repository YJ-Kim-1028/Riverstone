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
## 요리창 UI에도 불 이펙트가 있으면 좋겠다는 지적(사용자 지시, 2026-08-29 -
## 플레이테스트 피드백 #41) - 월드맵 버전(kitchen_progress_layer.gd)과 달리
## 여기는 그림을 번갈아 보여주는 대신, 그림 1장(기구별로 각각)을 ToolVessel의
## 기존 흔들림 트윈에 자연스럽게 얹는 방식으로 간다(_set_shaking() 참고).
## 냄비/프라이팬 그림 자체가 서로 달라서 불 그림도 기구별로 따로 그린다
## (사용자 지시). 도마/믹서기는 불을 안 써서 제외.
const FIRE_ICON_TEXTURES := {
	"cooking_area1": preload("res://assets/img/restaurant/fire_pot_ui.png"),
	"cooking_area2": preload("res://assets/img/restaurant/fire_pan_ui.png"),
}
## 조리 중일 때 냄비/프라이팬 등이 살짝 흔들리는 각도(라디안) - deg_to_rad(3).
const SHAKE_ANGLE := 0.0524
const SHAKE_DURATION := 0.12

@onready var _grid_scroll: ScrollContainer = $Background/Margin/VBox/GridScroll
@onready var _grid: GridContainer = $Background/Margin/VBox/GridScroll/GridMargin/Grid
@onready var _tool_label: Label = $Background/Margin/VBox/StatusRow/ToolLabel
@onready var _tool_vessel: Control = $Background/Margin/VBox/StatusRow/ToolVessel
@onready var _tool_image: TextureRect = $Background/Margin/VBox/StatusRow/ToolVessel/ToolImage
@onready var _fire_icon: TextureRect = $Background/Margin/VBox/StatusRow/ToolVessel/FireIcon
@onready var _status_icon: TextureButton = $Background/Margin/VBox/StatusRow/ToolVessel/StatusIcon
@onready var _status_icon_texture: TextureRect = $Background/Margin/VBox/StatusRow/ToolVessel/StatusIcon/Icon
@onready var _start_button: Button = $Background/Margin/VBox/StatusRow/StartButton
@onready var _close_button: TextureButton = $Background/CloseButton
@onready var _tooltip: PanelContainer = $Tooltip
@onready var _tooltip_label: Label = $Tooltip/Label

var _station_id := ""
var _slots: Array = []
var _selected_item_id := ""
var _pulse_tween: Tween
var _shake_tween: Tween
var _ready_glow_tween: Tween
var _was_busy := false
var _was_ready := false


func _ready() -> void:
	_set_open(false)
	_close_button.pressed.connect(close)
	_status_icon.pressed.connect(_on_status_icon_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_style_confirm_button(_start_button)
	InventoryManager.inventory_changed.connect(_refresh)
	_style_scrollbar()
	## 인벤은 드래그인데 요리할 때는 클릭이라 헷갈린다는 피드백(플레이테스트
	## 8번, 사용자 지시 2026-09-01) - 클릭은 그대로 두고, 재료 슬롯을 조리기구
	## 그림(ToolVessel) 위로 드래그해도 클릭과 똑같이 선택되게 한다. 그리드
	## 슬롯(InventorySlot)은 이미 자체적으로 드래그 소스를 지원해서
	## (inventory_slot.gd의 _get_drag_data(), from_index 포함) 여기선 드롭
	## 대상만 Control.set_drag_forwarding()으로 즉석에서 연결한다.
	_tool_vessel.set_drag_forwarding(
		func(_at_position: Vector2) -> Variant: return null,
		_can_drop_ingredient,
		_drop_ingredient
	)
	## ToolVessel 안의 ToolImage/FireIcon은 mouse_filter=IGNORE라 드롭이 그
	## 밑의 ToolVessel까지 그대로 통과하지만, StatusIcon(재료 아이콘이 실제로
	## 보이는 자리 - 화면 정중앙이라 가장 먼저 드롭을 시도하게 되는 위치)은
	## 자기 버튼이 STOP으로 가로채서 안 통과했다(사용자 리포트, 2026-09-01 -
	## "도마에 드래그로 재료 올리니까 안되는데"). 여기도 같은 대상으로 연결.
	_status_icon.set_drag_forwarding(
		func(_at_position: Vector2) -> Variant: return null,
		_can_drop_ingredient,
		_drop_ingredient
	)


func _can_drop_ingredient(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("from_index")


func _drop_ingredient(_at_position: Vector2, data: Variant) -> void:
	_on_slot_pressed(int(data["from_index"]))


## 요리대에서도 재료 설명을 보고 싶다는 피드백(플레이테스트 39번, 사용자
## 지시 2026-09-01 - "조리창, 요리창 띄웠을 때 툴팁 보여달라는 요청") -
## equipment_panel.gd와 동일한 방식(엔진 기본 tooltip_text는 이 게임의 4배
## 확대 캔버스에서 위치가 어긋나서 안 씀, 자체 Tooltip 노드를 직접 위치
## 계산). 이 화면은 clip_contents=true인 작은 고정 박스라 뷰포트 크기가
## 아니라 자기 자신의 크기(size)로 클램프한다.
func _show_tooltip(source: Control) -> void:
	var text := String(source.get_meta("tooltip_text", ""))
	if text.is_empty():
		return
	_tooltip_label.text = text
	_tooltip.visible = true
	_tooltip.size = _tooltip.get_combined_minimum_size()
	## get_global_transform().affine_inverse()로 변환해야 이 화면(또는
	## cooking_screen.gd처럼 scale이 1이 아닌 화면)에서도 정확한 로컬 좌표가
	## 나온다 - 단순히 global_position을 빼기만 하면 scale이 걸린 화면에서는
	## 배율만큼 어긋난다.
	var source_rect := source.get_global_rect()
	var local_top: Vector2 = get_global_transform().affine_inverse() * source_rect.position
	var local_bottom: Vector2 = get_global_transform().affine_inverse() * (source_rect.position + source_rect.size)
	var target := Vector2(local_top.x, local_bottom.y + 2.0)
	target.x = clampf(target.x, 0.0, size.x - _tooltip.size.x)
	target.y = clampf(target.y, 0.0, size.y - _tooltip.size.y)
	_tooltip.position = target


func _hide_tooltip() -> void:
	_tooltip.visible = false


func _tooltip_for(slot_data) -> String:
	if slot_data == null:
		return ""
	var definition := InventoryManager.get_item_definition(String(slot_data.get("item_id", "")))
	var name_text := String(definition.get("name", ""))
	var description_text := String(definition.get("description", ""))
	return "%s\n%s" % [name_text, description_text] if not description_text.is_empty() else name_text


func _process(_delta: float) -> void:
	if not _is_open() or _station_id.is_empty():
		return
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_kitchen(station_id: String) -> void:
	_station_id = station_id
	_selected_item_id = ""
	_tool_label.text = tr(KitchenManager.get_tool_name(station_id))
	_tool_image.texture = STATION_BACKDROP_TEXTURES.get(station_id)
	_fire_icon.texture = FIRE_ICON_TEXTURES.get(station_id)
	# close()가 아닌 다른 경로로 이전에 숨겨졌을 가능성까지 대비해서, 새로
	# 열 때도 항상 흔들림/글로우를 확실히 꺼둔 상태에서 시작한다 - 안 그러면
	# 이전 기구에서 켜져 있던 트윈이 이 ToolVessel(공용 노드)에 남아있는 동안
	# 새 기구가 조리 중이 아닌데도 흔들려 보일 수 있다.
	_set_shaking(false)
	_set_ready_glow(false)
	_was_busy = false
	_was_ready = false
	## 주의: 이 화면은 원래 전체화면이 아니라 가운데 고정 크기 박스로 설계된
	## 창이다 - set_anchors_and_offsets_preset(PRESET_FULL_RECT)를 넣었더니
	## 화면 전체를 덮어버리는 새 버그가 생겼다(사용자 리포트, 2026-08-26 -
	## "요리창도 화면에 꽉 차") - 그 호출은 여기 넣으면 안 됨.
	_set_open(true)
	_refresh()


func close() -> void:
	_set_open(false)
	_set_shaking(false)
	_set_ready_glow(false)
	_was_busy = false
	_was_ready = false


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
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
	# StatusIcon/Icon은 상태 아이콘 버튼 전체를 덮는 순전히 그림용 오버레이라
	# 항상 클릭을 통과시켜야 한다(.tscn에 mouse_filter=IGNORE로 지정해둠) -
	# 위 재귀 호출이 이걸 STOP으로 덮어써버리면 Icon이 클릭을 먼저 먹어서
	# 정작 StatusIcon 버튼의 pressed가 한 번도 안 터진다(사용자 리포트,
	# 2026-08-27: "조리 다 된 거 클릭해도 안꺼내져") - fishing_screen.gd의
	# Fish/Icon과 동일한 문제/해법. 재귀 적용 후 다시 IGNORE로 되돌린다.
	_status_icon_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Tooltip도 순수 장식용(클릭이 통과해야 함)이라 위 재귀 호출이 덮어쓴
	## mouse_filter를 다시 IGNORE로 되돌린다(CLAUDE.md UI 모달 mouse_filter
	## 체크리스트 3번과 동일한 패턴).
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func current_station_id() -> String:
	return _station_id


func _refresh() -> void:
	if _station_id.is_empty():
		return
	_update_status()
	## 그리드가 통째로 다시 만들어지므로, 지금 뜬 툴팁이 가리키던 슬롯도 같이
	## 사라진다 - mouse_exited가 그 슬롯에서 안 올 수 있으니 여기서 미리 끈다.
	_hide_tooltip()
	for child in _grid.get_children():
		child.queue_free()
	_slots = InventoryManager.get_slots()
	var available: Array = KitchenManager.get_available_ingredients(_station_id)
	var busy := KitchenManager.is_busy(_station_id)
	for i in _slots.size():
		var slot_instance := SlotScene.instantiate() as TextureButton
		_grid.add_child(slot_instance)
		# equipment_panel.gd와 같은 원인 - close()가 _station_id를 안 비워서,
		# 창이 닫힌 뒤에도 InventoryManager.inventory_changed가 쏘면 이
		# _refresh()가 그대로 다시 돈다. 새로 생기는 슬롯이 TextureButton
		# 기본값(STOP)이면 안 보이는 채로 클릭을 가로챈다 - 이 화면 자신의
		# mouse_filter는 _set_open()이 열고 닫을 때마다 갱신되므로 그 값을
		# 그대로 물려준다.
		slot_instance.mouse_filter = mouse_filter
		slot_instance.call("setup", i, _slots[i])
		var item_id := ""
		if _slots[i] != null:
			item_id = String(_slots[i].get("item_id", ""))
		var enabled := not busy and not item_id.is_empty() and available.has(item_id) and KitchenManager.can_start(_station_id, item_id)
		slot_instance.call("set_enabled", enabled)
		slot_instance.connect("slot_pressed", _on_slot_pressed)
		slot_instance.set_meta("tooltip_text", _tooltip_for(_slots[i]))
		slot_instance.mouse_entered.connect(_show_tooltip.bind(slot_instance))
		slot_instance.mouse_exited.connect(_hide_tooltip)
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
	## FireIcon이 ToolVessel의 자식이라, 이 회전 트윈을 그대로 같이 타면서
	## 불도 냄비/프라이팬이랑 같이 흔들린다 - 따로 애니메이션을 안 만들어도 됨.
	_fire_icon.visible = shaking and FIRE_ICON_TEXTURES.has(_station_id)
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
