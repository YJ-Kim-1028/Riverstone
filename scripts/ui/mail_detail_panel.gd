extends Control

## MailWindow(mail_app.gd)의 메일 자세히보기. 수신함에서 들어왔으면
## "보낸 사람", 발신함에서 들어왔으면 "수신인"으로 라벨만 바뀐다. 요청함
## 항목(show_request() 참고)은 CompleteButton이 추가로 나타나고, 목표를 아직
## 못 채웠으면 눌러도 소용없게(사용자 지시, 2026-08-25 - "완료가 되었을 때만
## 완료 버튼 클릭이 가능") 비활성화된다.

signal claim_pressed(request_id: String)

const BUTTON_TEXTURE := preload("res://assets/ui/btn_computer.png")
## 목표 미달성 상태의 완료 버튼 - title_screen.gd의 DISABLED_TINT와 같은 값,
## "누를 수는 있어 보이지만 지금은 안 된다"는 느낌을 통일한다.
const DISABLED_TINT := Color(0.55, 0.55, 0.55)
## 호감도 탭/상점 화면 스크롤바랑 다르게 생겼다는 지적(사용자 지시,
## 2026-08-26) - mail_list_panel.gd의 _style_scrollbar()와 완전히 같은 값.
const SCROLLBAR_WIDTH := 4

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _person_label: Label = $VBox/PersonLabel
@onready var _content_scroll: ScrollContainer = $VBox/ContentScroll
@onready var _content_label: Label = $VBox/ContentScroll/ContentMargin/ContentLabel
@onready var _date_label: Label = $VBox/DateLabel
@onready var _complete_button: Button = $VBox/CompleteButton

var _current_request_id := ""


func _ready() -> void:
	_complete_button.add_theme_stylebox_override("normal", _build_button_style())
	_complete_button.add_theme_stylebox_override("hover", _build_button_style())
	_complete_button.add_theme_stylebox_override("pressed", _build_button_style())
	_complete_button.add_theme_stylebox_override("disabled", _build_button_style(DISABLED_TINT))
	_complete_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_complete_button.pressed.connect(func() -> void: claim_pressed.emit(_current_request_id))
	_style_scrollbar()


func _style_scrollbar() -> void:
	var scrollbar := _content_scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.15)
	track.set_corner_radius_all(2)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.55, 0.4, 0.25, 0.9)
	grabber.set_corner_radius_all(2)
	scrollbar.add_theme_stylebox_override("scroll", track)
	scrollbar.add_theme_stylebox_override("grabber", grabber)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber)


func _build_button_style(tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURE
	style.texture_margin_left = 6
	style.texture_margin_right = 6
	style.texture_margin_top = 3
	style.texture_margin_bottom = 3
	style.modulate_color = tint
	return style


## 요청함 목록에서 항목을 골랐을 때(mail_app.gd) - 일반 메일과 같은 레이아웃을
## 재사용하되, "보낸 사람" 자리에 요청 보낸 NPC를, 날짜 자리 대신 완료 버튼을
## 보여준다. objective_met이 false면 버튼이 비활성화된 채로 보인다(사용자 지시).
func show_request(entry: Dictionary, objective_met: bool) -> void:
	AudioManager.play_sfx(AudioManager.SFX_MAIL_OPEN)
	## 이전 메일에서 스크롤을 내려놓은 채로 다음 걸 열면 그대로 밑에서 시작되는
	## 문제(사용자 지시, 2026-08-26 - "항상 스크롤이 제일 위에 있게") - 매번
	## 새로 열 때 맨 위로 되돌린다.
	_content_scroll.scroll_vertical = 0
	_current_request_id = String(entry.get("id", ""))
	_title_label.text = String(entry.get("title", "")).replace("{player_name}", GameManager.player_name)
	var npc_id := String(entry.get("npc_id", ""))
	_person_label.text = "보낸 사람 : %s" % String(NPCManager.get_definition(npc_id).get("name", npc_id))
	var lines: Array = entry.get("lines", [])
	var body := "\n".join(lines).replace("{player_name}", GameManager.player_name)
	var reward_line := _build_reward_line(entry)
	if not reward_line.is_empty():
		body += "\n\n%s" % reward_line
	## "인사한 npc 몇 명인지 요청함에서 볼 수 있게"(사용자 지시, 2026-08-25) -
	## 이 문구가 필요없는 요청은 빈 문자열이라 아무것도 안 붙는다.
	var progress_line := EmailManager.get_request_progress_text(_current_request_id)
	if not progress_line.is_empty():
		body += "\n\n%s" % progress_line
	var expired := bool(entry.get("expired", false))
	if expired:
		body += "\n\n(만료된 요청입니다.)"
	_content_label.text = body
	_date_label.text = ""
	_complete_button.visible = true
	_complete_button.disabled = expired or not objective_met


## 보상이 뭔지 안 보여서 답답하다는 지적(사용자 지시, 2026-08-25) - 골드/
## 아이템 중 있는 것만 이어붙인다.
func _build_reward_line(entry: Dictionary) -> String:
	var parts: Array[String] = []
	var reward_gold := int(entry.get("reward_gold", 0))
	if reward_gold > 0:
		parts.append("%d원" % reward_gold)
	var reward_item_id := String(entry.get("reward_item_id", ""))
	var reward_item_count := int(entry.get("reward_item_count", 0))
	if not reward_item_id.is_empty() and reward_item_count > 0:
		var item_name := String(InventoryManager.get_item_definition(reward_item_id).get("name", reward_item_id))
		parts.append("%s x%d" % [item_name, reward_item_count])
	if parts.is_empty():
		return ""
	return "보상: %s" % ", ".join(parts)


func show_email(entry: Dictionary, is_sent: bool) -> void:
	_content_scroll.scroll_vertical = 0
	_complete_button.visible = false
	## 스토커 이메일 전용 효과음(사용자 지시, 2026-08-24) - EmailManager._add_mail()이
	## 저장한 category로 구분한다.
	## 사칭 메일(impersonation)도 스토커 메일과 같은 소름끼치는 소리로 취급한다
	## (사용자 지시, 2026-08-24).
	var category := String(entry.get("category", ""))
	if category == "stalker" or category == "impersonation":
		AudioManager.play_sfx(AudioManager.SFX_STALKER_MAIL)
	else:
		AudioManager.play_sfx(AudioManager.SFX_MAIL_OPEN)
	# {player_name} 자리표시자 - mail_list_panel.gd와 동일하게 제목도 치환.
	_title_label.text = String(entry.get("title", "")).replace("{player_name}", GameManager.player_name)
	var npc_id := String(entry.get("npc_id", ""))
	var npc_name := String(NPCManager.get_definition(npc_id).get("name", npc_id))
	_person_label.text = ("수신인 : %s" if is_sent else "보낸 사람 : %s") % npc_name
	var lines: Array = entry.get("lines", [])
	# {player_name} 자리표시자 - dialogue_screen.gd와 동일한 규칙(README 참고).
	_content_label.text = "\n".join(lines).replace("{player_name}", GameManager.player_name)
	_date_label.text = String(entry.get("date", ""))
