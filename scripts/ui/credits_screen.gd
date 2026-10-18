extends Control

## 타이틀 화면 "크레딧" 버튼으로 여는 팝업 - 사용 폰트(Galmuri, Ark Pixel)의
## SIL Open Font License 1.1 조건(라이선스 본문의 "바뀐 버전도 원 라이선스
## 그대로 유지" 조항과 별개로, 조건 2 "저작권 고지 + 라이선스를 사용자가
## 볼 수 있는 형태로 포함"을 지키기 위해 추가(사용자 지시, 2026-10-03).
## 열고/닫는 구조는 title_settings_screen.gd와 동일한 패턴.

const UIUtil := preload("res://scripts/ui/ui_util.gd")

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _back_button: Button = $Panel/Margin/VBox/BackButton

var _is_open := false


func _ready() -> void:
	_set_open(false)
	_back_button.pressed.connect(close)
	_style_button(_back_button)


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


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)


func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
