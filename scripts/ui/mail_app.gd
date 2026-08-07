extends Control

## computer_screen.gd 산하 이메일 창. 좌측 사이드바(수신함/발신함/메일쓰기)는
## 목록 화면에서만 보이고, 메일 자세히보기/메일쓰기에서는 사라지는 대신
## 좌측 상단 뒤로가기 버튼이 나온다 (사용자가 그린 참고 이미지 구조 그대로).
## computer_screen.gd와 동일하게 modulate.a + mouse_filter로 하위 화면을
## 전환한다 (Godot이 ancestor.visible=false였던 적 있는 컨트롤의 폰트/테마를
## 잘못 그리는 문제 회피 - shop_screen.gd 참고).

signal closed

enum View { INBOX_LIST, SENT_LIST, INVITE_HISTORY, DETAIL, COMPOSE }

const BUTTON_TEXTURE := preload("res://assets/ui/btn_computer.png")

@onready var _close_button: TextureButton = $CloseButton
@onready var _back_button: TextureButton = $BackButton
@onready var _sidebar_background: Control = $ScaledContent/Margin/HBox/Sidebar/SidebarBackground
@onready var _nav_vbox: Control = $ScaledContent/Margin/HBox/Sidebar/NavVBox
@onready var _inbox_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/InboxButton
@onready var _sent_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/SentButton
@onready var _invite_history_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/InviteHistoryButton
@onready var _compose_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/ComposeButton
@onready var _compose_vbox: Control = $ScaledContent/Margin/HBox/Sidebar/ComposeVBox
@onready var _compose_send_button: Button = $ScaledContent/Margin/HBox/Sidebar/ComposeVBox/SendButton
@onready var _portrait_box: TextureRect = $ScaledContent/Margin/HBox/Sidebar/PortraitBox
@onready var _list_panel: Control = $ScaledContent/Margin/HBox/ContentArea/ListPanel
@onready var _detail_panel: Control = $ScaledContent/Margin/HBox/ContentArea/DetailPanel
@onready var _compose_panel: Control = $ScaledContent/Margin/HBox/ContentArea/ComposePanel
@onready var _info_popup: Control = $ScaledContent/InfoPopup
@onready var _info_message_label: Label = $ScaledContent/InfoPopup/Panel/Margin/VBox/MessageLabel
@onready var _info_ok_button: Button = $ScaledContent/InfoPopup/Panel/Margin/VBox/OkButtonRow/OkButton

var _last_list_view := View.INBOX_LIST
var _info_popup_callback := Callable()


func _ready() -> void:
	_close_button.pressed.connect(func() -> void: closed.emit())
	_back_button.pressed.connect(func() -> void: _show_list(_last_list_view))
	_inbox_button.pressed.connect(func() -> void: _show_list(View.INBOX_LIST))
	_sent_button.pressed.connect(func() -> void: _show_list(View.SENT_LIST))
	_invite_history_button.pressed.connect(func() -> void: _show_list(View.INVITE_HISTORY))
	_compose_button.pressed.connect(_show_compose)
	_compose_send_button.pressed.connect(func() -> void: _compose_panel.send())
	_compose_panel.send_succeeded.connect(func(is_invite: bool) -> void:
		_show_info_popup("발송되었습니다.", func() -> void: _show_list(View.INVITE_HISTORY if is_invite else View.SENT_LIST)))
	_compose_panel.info_requested.connect(func(message: String) -> void: _show_info_popup(message))
	_info_ok_button.pressed.connect(_on_info_popup_ok_pressed)
	_list_panel.row_selected.connect(_on_row_selected)
	_set_active(_info_popup, false)
	for button in [_inbox_button, _sent_button, _invite_history_button, _compose_button, _compose_send_button]:
		(button as Button).add_theme_stylebox_override("normal", _build_button_style())
		(button as Button).add_theme_stylebox_override("hover", _build_button_style())
		(button as Button).add_theme_stylebox_override("pressed", _build_button_style())
		(button as Button).add_theme_stylebox_override("disabled", _build_button_style())


## 확인 버튼 하나짜리 안내 팝업. on_ok는 확인을 누른 뒤에 실행할 동작(예:
## 발신함으로 이동) - 안 넘기면 그냥 닫기만 한다.
func _show_info_popup(message: String, on_ok: Callable = Callable()) -> void:
	_info_message_label.text = message
	_info_popup_callback = on_ok
	_set_active(_info_popup, true)


func _on_info_popup_ok_pressed() -> void:
	_set_active(_info_popup, false)
	var callback := _info_popup_callback
	_info_popup_callback = Callable()
	if callback.is_valid():
		callback.call()


func _build_button_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURE
	style.texture_margin_left = 6
	style.texture_margin_right = 6
	style.texture_margin_top = 3
	style.texture_margin_bottom = 3
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


func open() -> void:
	_show_list(View.INBOX_LIST)


func _show_list(view: View) -> void:
	_last_list_view = view
	_set_active(_info_popup, false)
	_set_active(_sidebar_background, true)
	_set_active(_nav_vbox, true)
	_set_active(_compose_vbox, false)
	_set_active(_portrait_box, false)
	_set_active(_back_button, false)
	_set_active(_list_panel, true)
	_set_active(_detail_panel, false)
	_set_active(_compose_panel, false)
	match view:
		View.INBOX_LIST:
			_list_panel.display(EmailManager.get_inbox())
		View.SENT_LIST:
			_list_panel.display(EmailManager.get_sent_mail(), true)
		View.INVITE_HISTORY:
			_list_panel.display_invite_history(EmailManager.get_invite_history())
		_:
			pass


## 메일쓰기는 버튼이 전송 하나뿐이라, 버튼 3개짜리 목록에서 쓰던 사이드바
## 액자 그림(SidebarBackground)까지 같이 보여주면 과해 보인다는 사용자
## 피드백으로 여기서는 액자 없이 버튼만 보여준다.
func _show_compose() -> void:
	_set_active(_info_popup, false)
	_set_active(_sidebar_background, false)
	_set_active(_nav_vbox, false)
	_set_active(_compose_vbox, true)
	_set_active(_portrait_box, false)
	_set_active(_back_button, true)
	_set_active(_list_panel, false)
	_set_active(_detail_panel, false)
	_set_active(_compose_panel, true)
	_compose_panel.refresh()


func _on_row_selected(email_id: int) -> void:
	var is_sent := _last_list_view == View.SENT_LIST
	var source: Array = EmailManager.get_sent_mail() if is_sent else EmailManager.get_inbox()
	for entry in source:
		if int(entry.get("id", -1)) != email_id:
			continue
		if not is_sent:
			EmailManager.mark_read(email_id)
		_set_active(_info_popup, false)
		_set_active(_sidebar_background, false)
		_set_active(_nav_vbox, false)
		_set_active(_compose_vbox, false)
		_set_active(_portrait_box, true)
		_set_active(_back_button, true)
		_set_active(_list_panel, false)
		_set_active(_detail_panel, true)
		_set_active(_compose_panel, false)
		_detail_panel.show_email(entry, is_sent)
		_update_portrait(String(entry.get("npc_id", "")))
		return


## 자세히보기에서 사이드바 자리(원래 수신함/발신함 버튼이 있던 곳)에 발신인
## (수신함) 또는 수신인(발신함) 초상화를 보여준다 - portraits.default 경로는
## NPC마다 달라서 preload가 아니라 매번 load()로 불러온다.
func _update_portrait(npc_id: String) -> void:
	var portraits: Dictionary = NPCManager.get_definition(npc_id).get("portraits", {})
	var path := String(portraits.get("default", ""))
	_portrait_box.texture = load(path) if not path.is_empty() else null


func _set_active(control: Control, active: bool) -> void:
	control.modulate.a = 1.0 if active else 0.0
	var filter := Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	_apply_mouse_filter_recursive(control, filter)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
