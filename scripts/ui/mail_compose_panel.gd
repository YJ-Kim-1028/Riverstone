extends Control

## MailWindow(mail_app.gd)의 메일쓰기 화면. "안부 메일" 버튼 = 자유 작성
## 모드(100자 제한, 성공 시 발신함에 저장), "초대장" 버튼 = 내용 고정 +
## 입력 비활성화(레스토랑 초대 - RestaurantManager.invite_npc()가 자체
## 1일 1회 제한을 관리하므로 발신함에는 따로 저장하지 않음, 사용자 지시).

enum Mode { NONE, GREETING, INVITE }

const CONTENT_CHAR_LIMIT := 100
## 초대장 모드의 제목 - 내용과 마찬가지로 시스템이 고정한다(사용자 지시).
const INVITE_TITLE_TEXT := "레스토랑 초대장"
## 모드를 아직 안 고른 초기 상태 - 내용 칸이 비활성화된 이유(그림 배경이
## 진해 보이는 게 아니라 아직 안부 메일/초대장을 안 골라서임)를 안내한다.
const MODE_GUIDE_TEXT := "내용을 작성하려면 안부 메일을, 주민을 초대하려면 초대장을 클릭하세요."
## email.md: "하루에 한 번 NPC 한 명에게 이메일을 보낼 수 있다" - 이미 오늘
## 다 쓴 상태에서 안부 메일/초대장 모드로 들어가려 하면 이 문구로 막는다.
const DAILY_LIMIT_MESSAGE := "하루 한 번만 주민에게 메일과 초대장을 보낼 수 있습니다."

const BUTTON_TEXTURE := preload("res://assets/ui/btn_computer.png")

## 실제로 메일/초대장이 전송됐을 때 - mail_app.gd가 "발송되었습니다." 팝업을
## 띄우고, 확인하면 안부 메일은 발신함으로, 초대장은 초대 내역으로 이동시킨다.
signal send_succeeded(is_invite: bool)
## 하루 한도 초과, 제목/내용 미작성 등 - mail_app.gd가 안내 팝업만 띄우고
## (화면 이동 없음) 그 외 상태는 그대로 유지된다.
signal info_requested(message: String)

@onready var _title_edit: LineEdit = $VBox/TitleBox/TitleEdit
@onready var _npc_prev_button: Button = $VBox/NpcPicker/PrevButton
@onready var _npc_name_label: Label = $VBox/NpcPicker/NpcNameLabel
@onready var _npc_next_button: Button = $VBox/NpcPicker/NextButton
@onready var _greeting_mode_button: Button = $VBox/ModeRow/GreetingModeButton
@onready var _invite_mode_button: Button = $VBox/ModeRow/InviteModeButton
@onready var _content_edit: TextEdit = $VBox/ContentBox/ContentEdit
@onready var _date_label: Label = $VBox/BottomRow/DateLabel
@onready var _feedback_label: Label = $VBox/FeedbackLabel

var _npc_ids: Array = []
var _npc_index := 0
var _mode := Mode.NONE


## OptionButton의 드롭다운은 이 화면 전체를 감싼 축소 배율(mail_app.tscn의
## ScaledContent) 밖에서 별도 팝업 창으로 뜨는 탓에 프로젝트 기본 테마의
## 일반 데스크톱 크기 그대로 화면 전체만큼 크게 나왔다 - 폰트만 줄여선 못
## 고쳐서(팝업 자체가 이 UI의 축소 규칙을 안 따름), 팝업 없는 이전/다음
## 버튼 방식으로 바꿨다.
func _ready() -> void:
	_greeting_mode_button.pressed.connect(_on_greeting_mode_pressed)
	_invite_mode_button.pressed.connect(_on_invite_mode_pressed)
	_npc_prev_button.pressed.connect(func() -> void: _step_npc(-1))
	_npc_next_button.pressed.connect(func() -> void: _step_npc(1))
	_content_edit.text_changed.connect(_on_content_changed)
	for button in [_greeting_mode_button, _invite_mode_button, _npc_prev_button, _npc_next_button]:
		(button as Button).add_theme_stylebox_override("normal", _build_button_style())
		(button as Button).add_theme_stylebox_override("hover", _build_button_style())
		(button as Button).add_theme_stylebox_override("pressed", _build_button_style())


func _build_button_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURE
	style.texture_margin_left = 3
	style.texture_margin_right = 3
	style.texture_margin_top = 1
	style.texture_margin_bottom = 1
	return style


func refresh() -> void:
	_feedback_label.text = ""
	_title_edit.text = ""
	_date_label.text = EmailManager.get_current_real_date_string()
	_refresh_npc_list()
	_set_mode(Mode.NONE)


func _refresh_npc_list() -> void:
	_npc_ids.clear()
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		_npc_ids.append(npc_id)
	_npc_index = 0
	_update_npc_label()


func _step_npc(delta: int) -> void:
	if _npc_ids.is_empty():
		return
	_npc_index = (_npc_index + delta + _npc_ids.size()) % _npc_ids.size()
	_update_npc_label()


func _update_npc_label() -> void:
	if _npc_ids.is_empty():
		_npc_name_label.text = "(NPC 없음)"
		return
	var npc_id := String(_npc_ids[_npc_index])
	_npc_name_label.text = String(NPCManager.get_definition(npc_id).get("name", npc_id))


func _on_greeting_mode_pressed() -> void:
	if not EmailManager.can_send_email_today():
		info_requested.emit(DAILY_LIMIT_MESSAGE)
		return
	_set_mode(Mode.GREETING)


func _on_invite_mode_pressed() -> void:
	if RestaurantManager.has_invited_today():
		info_requested.emit(DAILY_LIMIT_MESSAGE)
		return
	_set_mode(Mode.INVITE)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	match mode:
		Mode.GREETING:
			_title_edit.editable = true
			_title_edit.text = ""
			_content_edit.editable = true
			_content_edit.text = ""
		Mode.INVITE:
			_title_edit.editable = false
			_title_edit.text = INVITE_TITLE_TEXT
			_content_edit.editable = false
			_content_edit.text = "당신을 %s에 초대합니다! 맛있는 만찬을 즐기고 가세요~" % GameManager.restaurant_name
		_:
			_title_edit.editable = false
			_title_edit.text = ""
			_content_edit.editable = false
			_content_edit.text = MODE_GUIDE_TEXT


func _on_content_changed() -> void:
	if _mode != Mode.GREETING:
		return
	if _content_edit.text.length() > CONTENT_CHAR_LIMIT:
		_content_edit.text = _content_edit.text.substr(0, CONTENT_CHAR_LIMIT)
		_content_edit.set_caret_column(CONTENT_CHAR_LIMIT)


## mail_app.gd 산하 전송 버튼이 눌렸을 때 호출하는 진입점. 버튼 자체는 항상
## 눌러볼 수 있게 두고(비활성화로 헷갈리지 않게 - 사용자 지시), 필수값이
## 없으면 여기서 안내 팝업만 띄우고 실제 발송은 막는다.
func send() -> void:
	var npc_id := _selected_npc_id()
	if npc_id.is_empty():
		return
	match _mode:
		Mode.GREETING, Mode.NONE:
			if _title_edit.text.is_empty():
				info_requested.emit("제목을 작성해주세요.")
				return
			# NONE 상태의 내용 칸은 사용자가 쓴 게 아니라 안내 문구(MODE_GUIDE_TEXT)라
			# 실제 내용으로 치지 않는다 - 안부 메일을 고르기 전이라도 똑같이 막는다.
			if _mode == Mode.NONE or _content_edit.text.is_empty():
				info_requested.emit("내용을 작성해주세요.")
				return
			if EmailManager.compose_and_send(npc_id, _title_edit.text, _content_edit.text):
				send_succeeded.emit(false)
		Mode.INVITE:
			if RestaurantManager.invite_npc(npc_id):
				EmailManager.log_invite(npc_id)
				send_succeeded.emit(true)
		_:
			pass


func _selected_npc_id() -> String:
	if _npc_index < 0 or _npc_index >= _npc_ids.size():
		return ""
	return String(_npc_ids[_npc_index])
