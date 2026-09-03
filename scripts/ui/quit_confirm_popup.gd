extends Control

## TAB 상태창의 게임 종료 아이콘을 누르면 뜨는 확인창. restaurant_confirm_popup.gd/
## sleep_confirm_popup.gd와 완전히 동일한 패턴(button.png 9-슬라이스,
## modulate.a + mouse_filter로 열고 닫기).

signal confirmed
## "아니오"/ESC로 취소했을 때만 쏜다 - status_screen.gd가 ESC 단독 오픈
## 경로(open_quit_confirm())에서 자신의 modulate를 임시로 되돌리는 데 쓴다.
signal canceled

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _yes_button: Button = $Panel/Margin/VBox/ButtonRow/YesButton
@onready var _no_button: Button = $Panel/Margin/VBox/ButtonRow/NoButton


func _ready() -> void:
	_yes_button.pressed.connect(_on_yes_pressed)
	_no_button.pressed.connect(_on_no_pressed)
	for button in [_yes_button, _no_button]:
		_style_button(button)
	_set_open(false)


func open() -> void:
	_set_open(true)


## main.gd가 모달 없을 때 ESC로 이 팝업을 단독으로 여는 경로가 생기면서
## (2026-09-01, 플레이테스트 20번) ESC로 취소도 되어야 자연스럽다 - "아니오"와
## 동일하게 처리한다.
func _unhandled_input(event: InputEvent) -> void:
	if modulate.a > 0.0 and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_no_pressed()


func _style_button(button: Button) -> void:
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


## 이 화면은 원래부터 modulate 방식을 썼는데도 익스포트 빌드에서 좌측
## 상단에 눌려 뜨는 문제가 있었다(사용자 리포트, 2026-08-26 - "종료하기
## 버튼 누르면 나오는 팝업은 이번에도 좌측 상단에 고정되어있단다") - 즉
## visible/modulate 방식 자체가 원인이 아니라, 익스포트 빌드에서 앵커 기반
## 크기/위치가 창이 완전히 자리잡기 전 값으로 굳어버리는 게 진짜 원인이다.
## 자기 자신에게 값을 재대입하는 방식은 값이 이미 같으면 엔진이 다시 계산을
## 안 하는 것으로 보여 재발했다(slot_picker_screen.gd에서 같은 문제로 확인,
## 2026-08-26) - PRESET_FULL_RECT 재적용이라야 실제로 고쳐진다. 이 팝업의
## 루트(자신)는 Dim 배경을 깔기 위해 원래도 전체화면 앵커(0/0/1/1)라 이
## preset을 self에 적용해도 안전하다(안쪽 작은 박스는 Panel이라는 별도
## 자식이라 영향 없음).
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 1.0 if is_open else 0.0
	var filter := Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
	_apply_mouse_filter_recursive(self, filter)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _on_yes_pressed() -> void:
	_set_open(false)
	confirmed.emit()


func _on_no_pressed() -> void:
	_set_open(false)
	canceled.emit()
