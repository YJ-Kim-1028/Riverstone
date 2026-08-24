extends Control

## home_interior.tmx의 "computer" 오브젝트로 열리는 화면. 데스크탑
## 배경(computer_background.png) 위에 아이콘 2개(이메일/샵)가 있고, 클릭하면
## 각각 창이 뜬다 (사용자가 그린 refer_computer_background.png 구조 그대로).
## shop_screen.gd와 동일하게 "항상 visible=true, modulate.a + mouse_filter로
## 열고 닫기" 패턴을 데스크탑/각 창 단위로 반복 적용한다 (Godot이
## ancestor.visible=false였던 적 있는 컨트롤의 폰트/테마를 잘못 그리는 문제
## 회피용 - shop_screen.gd 주석 참고).

enum Screen { DESKTOP, MAIL, SHOP }

@onready var _desktop: Control = $Desktop
@onready var _email_icon: TextureButton = $Desktop/EmailIcon
@onready var _shop_icon: TextureButton = $Desktop/ShopIcon
@onready var _onoff_button: TextureButton = $Desktop/OnOffButton
@onready var _mail_window: Control = $MailWindow
@onready var _shop_window: Control = $ShopWindow

var _is_open := false
var _current_screen := Screen.DESKTOP
## 공범 엔딩(사용자 지시, 2026-08-24): 스토커 메일을 연 순간부터 일정 시간
## 동안은 플레이어가 직접 닫을 수 없어야 한다 - ESC/전원 버튼/메일 창의
## 뒤로가기·닫기 버튼을 전부 막는다. main.gd가 force_close()로 강제로 닫을
## 때만 예외.
var _interaction_locked := false


func _ready() -> void:
	_email_icon.pressed.connect(_open_mail)
	_shop_icon.pressed.connect(_open_shop)
	_onoff_button.pressed.connect(close)
	_mail_window.closed.connect(_show_desktop)
	_shop_window.closed.connect(_show_desktop)
	# _show_desktop()가 Desktop의 mouse_filter를 STOP으로 켜기 때문에, 그
	# 다음에 _set_open(false)를 불러야 전체 화면(닫힘) 상태로 확실히
	# 덮어써진다 - 순서가 반대였을 때는 컴퓨터 화면이 닫혀 있어도(투명) Desktop
	# 영역(화면 대부분을 차지)이 계속 클릭을 먹어서, 그 뒤에 겹치는 다른 화면
	# (요리창 등)의 상호작용이 막히는 버그가 있었다.
	_show_desktop()
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or _interaction_locked or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if _current_screen == Screen.DESKTOP:
			close()
		else:
			_show_desktop()


func open() -> void:
	_set_open(true)
	_show_desktop()


func close() -> void:
	if _interaction_locked:
		return
	_set_open(false)


## main.gd의 공범 엔딩 컷신 전용 - 잠금 여부와 상관없이 강제로 닫는다.
func force_close() -> void:
	set_interaction_locked(false)
	_set_open(false)


func set_interaction_locked(locked: bool) -> void:
	_interaction_locked = locked
	_onoff_button.disabled = locked
	_mail_window.set_interaction_locked(locked)


func _open_mail() -> void:
	_current_screen = Screen.MAIL
	_set_active(_desktop, false)
	_set_active(_mail_window, true)
	_set_active(_shop_window, false)
	_mail_window.open()


func _open_shop() -> void:
	_current_screen = Screen.SHOP
	_set_active(_desktop, false)
	_set_active(_mail_window, false)
	_set_active(_shop_window, true)
	_shop_window.refresh()


func _show_desktop() -> void:
	_current_screen = Screen.DESKTOP
	_set_active(_desktop, true)
	_set_active(_mail_window, false)
	_set_active(_shop_window, false)


func _set_open(is_open: bool) -> void:
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _set_active(control: Control, active: bool) -> void:
	control.modulate.a = 1.0 if active else 0.0
	_apply_mouse_filter_recursive(control, Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
