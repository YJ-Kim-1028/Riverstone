extends Control

## 타이틀 화면 진입 시 가장 먼저 뜨는 콘텐츠 주의 팝업 - 스팀 등 유통 플랫폼의
## 콘텐츠 서베이/연령 등급과 별개로, 게임 내에서도 폭력성/어두운 내용에 대한
## 경고를 띄워야 한다는 사용자 지시(2026-10-03)로 추가. CLAUDE.md의 공포
## 시스템 규칙("첫 번째 살인 사건 전까지 플레이어가 공포 요소의 존재를
## 인지해서는 안 된다")을 지키기 위해 "살인", "스토커" 같은 구체적인 단어
## 없이 포괄적인 문구만 사용한다 - 스포일러 없이 경고 의무만 충족.
##
## 열고/닫는 구조는 quit_confirm_popup.gd와 동일한 패턴(9-슬라이스 패널,
## modulate.a + mouse_filter 재귀 적용).

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _confirm_button: Button = $Panel/Margin/VBox/ConfirmButton


func _ready() -> void:
	_confirm_button.pressed.connect(close)
	_style_button(_confirm_button)
	_set_open(false)


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if modulate.a > 0.0 and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


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
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
