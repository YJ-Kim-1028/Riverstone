extends Control

## 미니맵 - M으로 열고 닫는다(ESC로도 닫힘). status_screen.gd의 모달 열기/닫기
## 패턴(CLAUDE.md UI 모달 mouse_filter 체크리스트)을 그대로 따른다.

const UIUtil := preload("res://scripts/ui/ui_util.gd")

@onready var _map_view: Control = $Background/Margin/MapView

var _is_open := false
## main.gd가 _ready()에서 채워준다(status_screen.set_open_blocked_check()와 동일
## 패턴) - 다른 모달이 이미 열려있을 때 M을 눌러도 그 위에 겹쳐 열리지 않게 함.
var _open_blocked_check: Callable = Callable()
var _player: Node2D = null


func setup(player: Node2D) -> void:
	_player = player


func set_open_blocked_check(check: Callable) -> void:
	_open_blocked_check = check


func _ready() -> void:
	_set_open(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == Keybinds.get_keycode(Keybinds.MINIMAP_ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _is_open:
		close()


func toggle() -> void:
	if _is_open:
		close()
	elif _open_blocked_check.is_valid() and _open_blocked_check.call():
		return
	else:
		open()


func open() -> void:
	_set_open(true)
	_map_view.refresh(GameManager.current_map_id, _player)


func close() -> void:
	_set_open(false)


func _set_open(is_open: bool) -> void:
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
