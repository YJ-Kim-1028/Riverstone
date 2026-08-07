extends Control

## 언어 설정 화면. 이 프로젝트에는 다국어(i18n) 시스템 자체가 아직 없어서
## (번역 문자열 테이블도, 언어 전환 로직도 없음) 실제 기능은 구현하지 않고
## 안내만 하는 자리표시자로 남겨둔다(CLAUDE.md: 미구현 항목을 임의로 채우지
## 말 것) - 실제 다국어 지원을 시작할 때 이 화면에 진짜 옵션을 채우면 된다.

signal closed

@onready var _back_button: Button = $Panel/Margin/VBox/BackButton


func _ready() -> void:
	visible = false
	_back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open() -> void:
	visible = true


func close() -> void:
	visible = false
	closed.emit()
