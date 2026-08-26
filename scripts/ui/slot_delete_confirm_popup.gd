extends Control

## 이어하기 화면에서 세이브 슬롯을 삭제하기 전 뜨는 확인창.
## restaurant_confirm_popup.gd/sleep_confirm_popup.gd와 완전히 동일한 패턴
## (button.png 9-슬라이스, modulate.a + mouse_filter로 열고 닫기) - 이
## 프로젝트는 확인창마다 이런 작은 전용 스크립트를 각각 두는 관례라 그대로
## 따랐다(공용 팝업 하나를 여러 화면이 돌려쓰지 않음).

signal confirmed

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var _yes_button: Button = $Panel/Margin/VBox/ButtonRow/YesButton
@onready var _no_button: Button = $Panel/Margin/VBox/ButtonRow/NoButton


func _ready() -> void:
	_yes_button.pressed.connect(_on_yes_pressed)
	_no_button.pressed.connect(_on_no_pressed)
	for button in [_yes_button, _no_button]:
		_style_button(button)
	_set_open(false)


func open_with_message(text: String) -> void:
	_message_label.text = text
	_set_open(true)


func close() -> void:
	_set_open(false)


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


## quit_confirm_popup.gd와 동일한 이유/동일한 수정(사용자 리포트, 2026-08-27 -
## "삭제팝업은 근데 여전히 좌측에 처박혀") - 자기 값을 자기에게 재대입하는
## _refresh_layout() 방식은 값이 이미 같으면 엔진이 재계산을 안 해서 효과가
## 없었다. 이 팝업의 루트(자신)는 Dim 배경을 깔기 위해 원래도 전체화면
## 앵커(0/0/1/1)라 PRESET_FULL_RECT 재적용이 안전하다(안쪽 작은 박스는 Panel
## 이라는 별도 자식이라 영향 없음).
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
