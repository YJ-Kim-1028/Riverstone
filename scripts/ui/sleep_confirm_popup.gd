extends Control

## home_interior.tmx의 "sleep"(침대) 타일에 닿으면(main.gd가 호출) E 없이 바로
## 뜨는 확인창. cooking_screen.gd의 쥐약 확인 팝업과 동일한 스타일/패턴
## (button.png 9-슬라이스, modulate.a + mouse_filter로 열고 닫기)을 쓴다.

## 예를 고르면 main.gd가 하루 전환 연출을 재생한다 - 실제 날짜 전환
## (TimeManager.sleep_now())은 그 연출 안에서 화면이 까매진 다음에 실행된다.
signal slept

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


func _set_open(is_open: bool) -> void:
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
	slept.emit()


func _on_no_pressed() -> void:
	_set_open(false)
