extends Control

## 새 파일 - NPC 호감도 이벤트로 받은 동물(고양이/강아지)의 이름을 그 자리에서
## 지어주는 팝업(사용자 지시, 2026-09-16 - "고양이 받은 순간에" 이름 짓기).
## sleep_confirm_popup.gd와 동일한 스타일/열고닫기 패턴(button.png 9-슬라이스,
## modulate.a + mouse_filter 재귀 적용)을 따르되, 버튼 두 개 대신 LineEdit
## 한 칸 + 확인 버튼 하나로 바꾼 형태.

signal name_confirmed(pet_name: String)

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)
const MAX_NAME_LENGTH := 12

@onready var _prompt_label: Label = $Panel/Margin/VBox/PromptLabel
@onready var _name_edit: LineEdit = $Panel/Margin/VBox/NameEdit
@onready var _confirm_button: Button = $Panel/Margin/VBox/ConfirmButton

var _default_name := ""


func _ready() -> void:
	_name_edit.max_length = MAX_NAME_LENGTH
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_style_button(_confirm_button)
	_set_open(false)


## default_name: 플레이어가 빈 이름으로 확인을 누르면 대신 쓸 이름(동물 종류
## 기본값, 예: "고양이").
func open(prompt_text: String, default_name: String) -> void:
	_prompt_label.text = prompt_text
	_name_edit.text = ""
	_name_edit.placeholder_text = default_name
	## LineEdit.placeholder_text는 Control 속성이라 자동 번역되지만, 빈 이름
	## 확인 시 실제로 저장되는 값(_default_name)은 그냥 변수라 자동 번역이
	## 안 걸린다 - 직접 tr()을 걸어서 화면에 보이던 언어 그대로 저장되게 한다.
	_default_name = tr(default_name)
	_set_open(true)
	_name_edit.grab_focus()


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
	_apply_mouse_filter_recursive(self, filter)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _on_confirm_pressed() -> void:
	_confirm(_name_edit.text)


func _on_name_submitted(submitted_text: String) -> void:
	_confirm(submitted_text)


func _confirm(raw_name: String) -> void:
	var trimmed := raw_name.strip_edges()
	_set_open(false)
	name_confirmed.emit(trimmed if not trimmed.is_empty() else _default_name)
