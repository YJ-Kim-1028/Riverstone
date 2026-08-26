extends Control

## 언어 설정 화면. 이 프로젝트에는 다국어(i18n) 시스템 자체가 아직 없어서
## (번역 문자열 테이블도, 언어 전환 로직도 없음) 실제 기능은 구현하지 않고
## 안내만 하는 자리표시자로 남겨둔다(CLAUDE.md: 미구현 항목을 임의로 채우지
## 말 것) - 실제 다국어 지원을 시작할 때 이 화면에 진짜 옵션을 채우면 된다.

signal closed

@onready var _back_button: Button = $Panel/Margin/VBox/BackButton

var _is_open := false


func _ready() -> void:
	_set_open(false)
	_back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)
	closed.emit()


## slot_picker_screen.gd와 동일한 이유/동일한 수정(사용자 리포트, 2026-08-27 -
## "언어 박스도 좌측 상단 고정되어 잇긴 하네") - 이 화면의 루트는 원래 전체화면
## (anchor 0/0/1/1)이라 PRESET_FULL_RECT 재적용이 안전하고, 실제로 이
## 방식이어야 익스포트 빌드에서 고쳐진다.
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
