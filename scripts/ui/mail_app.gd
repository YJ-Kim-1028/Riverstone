extends Control

## computer_screen.gd 산하 이메일 창. 좌측 사이드바(수신함/발신함/메일쓰기)는
## 목록 화면에서만 보이고, 메일 자세히보기/메일쓰기에서는 사라지는 대신
## 좌측 상단 뒤로가기 버튼이 나온다 (사용자가 그린 참고 이미지 구조 그대로).
## computer_screen.gd와 동일하게 modulate.a + mouse_filter로 하위 화면을
## 전환한다 (Godot이 ancestor.visible=false였던 적 있는 컨트롤의 폰트/테마를
## 잘못 그리는 문제 회피 - shop_screen.gd 참고).

const UIUtil := preload("res://scripts/ui/ui_util.gd")

signal closed

enum View { INBOX_LIST, SENT_LIST, INVITE_HISTORY, REQUEST_LIST, DETAIL, COMPOSE }

const BUTTON_TEXTURE := preload("res://assets/ui/btn_computer.png")
## 요청함 탭 버튼의 알림 배지 - Godot 내장 Button.icon 슬롯은 이 작은 픽셀
## 스케일에서 위치/여백이 어색해서(사용자 지시, 2026-09-01) 직접 위치를
## 계산하는 방식으로 되돌림. 텍스트가 가운데 정렬이라 버튼 폭이 바뀌어도
## 항상 글씨 바로 왼쪽에 오도록, 보일 때마다 실제 렌더링된 글자 폭을 재서
## 위치를 새로 잡는다(_refresh_request_notify_icon 참고).
const NOTIFY_ICON_GAP := 1.0

@onready var _close_button: TextureButton = $CloseButton
@onready var _back_button: TextureButton = $BackButton
@onready var _sidebar_background: Control = $ScaledContent/Margin/HBox/Sidebar/SidebarBackground
@onready var _nav_vbox: Control = $ScaledContent/Margin/HBox/Sidebar/NavVBox
@onready var _inbox_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/InboxButton
@onready var _inbox_notify_icon: TextureRect = $ScaledContent/Margin/HBox/Sidebar/NavVBox/InboxButton/NotifyIcon
@onready var _sent_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/SentButton
@onready var _invite_history_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/InviteHistoryButton
@onready var _request_button: Button = $ScaledContent/Margin/HBox/Sidebar/NavVBox/RequestButton
@onready var _request_notify_icon: TextureRect = $ScaledContent/Margin/HBox/Sidebar/NavVBox/RequestButton/NotifyIcon
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
	_request_button.pressed.connect(func() -> void: _show_list(View.REQUEST_LIST))
	_compose_button.pressed.connect(_show_compose)
	_compose_send_button.pressed.connect(func() -> void: _compose_panel.send())
	_compose_panel.send_succeeded.connect(func(is_invite: bool) -> void:
		_show_info_popup("발송되었습니다.", func() -> void: _show_list(View.INVITE_HISTORY if is_invite else View.SENT_LIST)))
	_compose_panel.info_requested.connect(func(message: String) -> void: _show_info_popup(message))
	_info_ok_button.pressed.connect(_on_info_popup_ok_pressed)
	_list_panel.row_selected.connect(_on_row_selected)
	_list_panel.request_selected.connect(_on_request_row_selected)
	_detail_panel.claim_pressed.connect(_on_claim_pressed)
	_set_active(_info_popup, false)
	for button in [_inbox_button, _sent_button, _invite_history_button, _request_button, _compose_button, _compose_send_button]:
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
	# 이 창의 자식 중 CloseButton만 오른쪽 기준(anchor_left/right = 1.0)이라,
	# 부모 크기가 아직 0인 상태에서 앵커가 굳으면 x = 1.0 * 0 + offset이 되어
	# 혼자 왼쪽 위로 튀어나온다(BackButton은 anchor 0이라 부모 크기와 무관해서
	# 멀쩡하다). 내보낸 빌드에서만 창이 자리잡기 전에 굳어서 재현되고 에디터
	# Play에서는 안 나타나는, day18에서 여러 화면을 고쳤던 것과 같은 문제다
	# (사용자 리포트: "메일함에서 닫기 버튼이 왼쪽으로 치우쳐져 있어",
	# 2026-08-28). 값 재대입은 값이 같으면 엔진이 재계산을 건너뛰므로
	# set_anchors_and_offsets_preset()을 실제로 호출해야 한다 - 이 루트는
	# 부모를 꽉 채우는 0/0/1/1이라 PRESET_FULL_RECT다. 버튼에 직접 프리셋을
	# 걸지 않는 이유: PRESET_TOP_RIGHT는 오른쪽 모서리에 딱 붙여버려서 원래
	# 의도된 5px 여백(offset_right = -5)이 사라진다. 루트 크기만 제대로
	# 다시 잡히면 자식들의 앵커 위치는 Godot이 알아서 재계산한다.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_show_list(View.INBOX_LIST)


## computer_screen.gd 참고 - 공범 엔딩 컷신에서 이 메일 창의 닫기/뒤로가기
## 버튼을 잠깐 막을 때 쓴다.
func set_interaction_locked(locked: bool) -> void:
	_close_button.disabled = locked
	_back_button.disabled = locked


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
	## 요청함 탭에 완료된(미수령) 요청이 있다는 배지(사용자 지시,
	## 2026-09-01, 플레이테스트 23번) - 이 창을 오갈 때마다 다시 확인한다.
	_refresh_request_notify_icon()
	## 수신함 탭에도 같은 방식으로(플레이테스트 피드백 #11, 2026-09-05 -
	## "수신함에도 New 뜨면 좋을듯").
	_refresh_inbox_notify_icon()
	match view:
		View.INBOX_LIST:
			_list_panel.display(EmailManager.get_inbox())
		View.SENT_LIST:
			_list_panel.display(EmailManager.get_sent_mail(), true)
		View.INVITE_HISTORY:
			_list_panel.display_invite_history(EmailManager.get_invite_history())
		View.REQUEST_LIST:
			_list_panel.display_requests(EmailManager.get_active_requests())
		_:
			pass


## 완료된 요청이 있으면 배지를 켜고, 가운데 정렬된 "요청함" 글자의 실제
## 렌더링 폭을 재서 그 바로 왼쪽에 위치시킨다(사용자 지시, 2026-09-01 -
## "요청함 글씨 좌측 옆에 뜨게, 지금은 글씨랑 너무 멀어"). 고정 좌표 대신
## 이렇게 재는 이유: 텍스트가 중앙 정렬이라 버튼 폭이 조금만 달라져도 글자
## 시작 위치가 바뀐다. 아이콘 그림 대신 빨간 점(ColorRect)으로 그린다(사용자
## 지시, 2026-09-01 - 작은 크기에서 느낌표보다 점이 더 잘 읽힘).
func _refresh_request_notify_icon() -> void:
	var claimable := EmailManager.has_claimable_request()
	_request_notify_icon.visible = claimable
	## 위 _set_active(_nav_vbox, true)가 재귀로 STOP을 덮어썼으므로, 순전히
	## 장식용인 이 아이콘은 다시 IGNORE로 되돌린다(CLAUDE.md UI 모달
	## mouse_filter 체크리스트 3번과 동일한 패턴).
	_request_notify_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not claimable:
		return
	var font := _request_button.get_theme_font("font")
	var font_size := _request_button.get_theme_font_size("font_size")
	var text_width := font.get_string_size(_request_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_left := (_request_button.size.x - text_width) / 2.0
	_request_notify_icon.position = Vector2(
		text_left - _request_notify_icon.size.x - NOTIFY_ICON_GAP,
		(_request_button.size.y - _request_notify_icon.size.y) / 2.0
	)


## 위 _refresh_request_notify_icon()과 완전히 같은 패턴 - "수신함" 글자 왼쪽에
## 안 읽은 메일이 있을 때만 배지를 띄운다(플레이테스트 피드백 #11, 2026-09-05).
func _refresh_inbox_notify_icon() -> void:
	var unread := EmailManager.has_unread()
	_inbox_notify_icon.visible = unread
	_inbox_notify_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unread:
		return
	var font := _inbox_button.get_theme_font("font")
	var font_size := _inbox_button.get_theme_font_size("font_size")
	var text_width := font.get_string_size(_inbox_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_left := (_inbox_button.size.x - text_width) / 2.0
	_inbox_notify_icon.position = Vector2(
		text_left - _inbox_notify_icon.size.x - NOTIFY_ICON_GAP,
		(_inbox_button.size.y - _inbox_notify_icon.size.y) / 2.0
	)


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


## 요청함 항목 클릭(사용자 지시, 2026-08-25) - _on_row_selected()와 같은 레이아웃
## 전환이지만 id가 문자열이라 별도 신호/조회 경로를 쓴다.
func _on_request_row_selected(request_id: String) -> void:
	for entry in EmailManager.get_active_requests():
		if String(entry.get("id", "")) != request_id:
			continue
		EmailManager.mark_request_read(request_id)
		_set_active(_info_popup, false)
		_set_active(_sidebar_background, false)
		_set_active(_nav_vbox, false)
		_set_active(_compose_vbox, false)
		_set_active(_portrait_box, true)
		_set_active(_back_button, true)
		_set_active(_list_panel, false)
		_set_active(_detail_panel, true)
		_set_active(_compose_panel, false)
		_detail_panel.show_request(entry, EmailManager.is_request_objective_met(request_id))
		_update_portrait(String(entry.get("npc_id", "")))
		return


## 완료 버튼(사용자 지시) - 성공하면 보상을 받고 바로 요청함으로 돌아간다.
## 실패(목표 미달성 등)는 버튼이 애초에 비활성화돼 있어 정상 경로로는 안 일어남.
## "보상을 받았다." 확인 팝업은 굳이 안 알려줘도 된다는 지적으로 제거하고
## 코인 소리로만 알린다(사용자 지시, 2026-09-01).
func _on_claim_pressed(request_id: String) -> void:
	if EmailManager.claim_request(request_id):
		AudioManager.play_sfx(AudioManager.SFX_COIN)
		_show_list(View.REQUEST_LIST)


## 자세히보기에서 사이드바 자리(원래 수신함/발신함 버튼이 있던 곳)에 발신인
## (수신함) 또는 수신인(발신함) 초상화를 보여준다 - portraits.default 경로는
## NPC마다 달라서 preload가 아니라 매번 load()로 불러온다.
func _update_portrait(npc_id: String) -> void:
	var portraits: Dictionary = NPCManager.get_definition(npc_id).get("portraits", {})
	var path := String(portraits.get("default", ""))
	_portrait_box.texture = load(path) if not path.is_empty() else null
	# horror_events.md "NPC 사망 - 초상화 회색 처리" - 죽은 뒤에 온 사칭 메일뿐
	# 아니라, 살아있을 때 받았던 옛 메일을 다시 봐도 회색으로 보인다(의도적 -
	# "이제는 없는 사람"이라는 사실 자체가 기준이라 메일이 언제 온 건지는 안 따짐).
	_portrait_box.material = null if NPCManager.is_alive(npc_id) else NPCManager.get_dead_portrait_material()


func _set_active(control: Control, active: bool) -> void:
	control.modulate.a = 1.0 if active else 0.0
	var filter := Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	UIUtil.apply_mouse_filter(control, filter)
