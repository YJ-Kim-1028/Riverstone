extends Control

## MailWindow(mail_app.gd)의 메일쓰기 화면. "안부 메일" 버튼 = 자유 작성
## 모드(100자 제한, 성공 시 발신함에 저장), "초대장" 버튼 = 내용 고정 +
## 입력 비활성화(레스토랑 초대 - RestaurantManager.invite_npc()가 자체
## 1일 1회 제한을 관리하므로 발신함에는 따로 저장하지 않음, 사용자 지시).

enum Mode { NONE, GREETING, INVITE }

const CONTENT_CHAR_LIMIT := 100
## 초대장 모드의 제목 - 내용과 마찬가지로 시스템이 고정한다(사용자 지시,
## 2026-08-25 - "%s 레스토랑에 초대합니다!" 형식으로 레스토랑 이름을 넣도록 수정).
const INVITE_TITLE_FORMAT := "%s 레스토랑에 초대합니다!"
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
## 제목(LineEdit)에 한글을 조합 중일 때 마우스로 바로 본문(TextEdit)을
## 클릭해 넘어가면, 아직 커밋 안 된 마지막 조합 글자가 제목에서는 사라지고
## 본문 쪽으로 새어 들어갔다(사용자 리포트, 2026-09-05 - "제목에 입력한
## 마지막 글자가 본문까지 따라 내려가고 그래" - 스페이스바를 한 번 더 눌러
## 조합을 먼저 끝내면 정상 동작한다는 것도 같은 원인을 가리킴). Godot의 IME
## 조합 커밋이 포커스가 이미 새 필드로 넘어간 뒤에 도착해서 생기는 엔진
## 타이밍 문제라 - 포커스가 들어오는 순간 한 프레임 놓았다 다시 잡아서, 그
## 사이에 이전 필드로 향하던 커밋이 새 필드를 오염시키기 전에 정리되게 한다.
var _ime_refocus_guard := false


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
	_title_edit.focus_entered.connect(_on_text_field_focus_entered.bind(_title_edit))
	_content_edit.focus_entered.connect(_on_text_field_focus_entered.bind(_content_edit))
	for button in [_greeting_mode_button, _invite_mode_button, _npc_prev_button, _npc_next_button]:
		(button as Button).add_theme_stylebox_override("normal", _build_button_style())
		(button as Button).add_theme_stylebox_override("hover", _build_button_style())
		(button as Button).add_theme_stylebox_override("pressed", _build_button_style())


## _ready()의 focus_entered 연결 참고 - 새 필드로 포커스가 넘어오는 순간
## 한 프레임 놓았다 다시 잡아서, 이전 필드로 향하던 IME 조합 커밋이 새
## 필드에 새는 것을 막는다.
func _on_text_field_focus_entered(field: Control) -> void:
	if _ime_refocus_guard:
		return
	_ime_refocus_guard = true
	field.release_focus()
	await get_tree().process_frame
	_ime_refocus_guard = false
	if is_instance_valid(field):
		field.grab_focus()


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
			_title_edit.text = tr(INVITE_TITLE_FORMAT) % GameManager.restaurant_name
			_content_edit.editable = false
			_content_edit.text = tr("당신을 %s에 초대합니다! 맛있는 만찬을 즐기고 가세요~") % GameManager.restaurant_name
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
## 한글 마지막 글자를 조합 중인 상태로 바로 이 버튼을 누르면(텍스트 필드가
## 아니라 버튼으로 포커스가 넘어가서 _on_text_field_focus_entered 가드가
## 걸리지 않는다) 그 글자가 커밋되기 전에 .text를 읽어버려서 통째로
## 누락됐다(사용자 리포트, 2026-09-18 - "입력이 완성되지 않아"). 43번 줄
## 주석과 같은 원인(IME 커밋이 한 프레임 늦게 도착) - release_focus()로 커밋을
## 유도한 뒤 한 프레임 기다렸다가 읽는다.
func send() -> void:
	if _title_edit.has_focus():
		_title_edit.release_focus()
		await get_tree().process_frame
	elif _content_edit.has_focus():
		_content_edit.release_focus()
		await get_tree().process_frame
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
