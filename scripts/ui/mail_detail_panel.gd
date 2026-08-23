extends Control

## MailWindow(mail_app.gd)의 메일 자세히보기. 수신함에서 들어왔으면
## "보낸 사람", 발신함에서 들어왔으면 "수신인"으로 라벨만 바뀐다.

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _person_label: Label = $VBox/PersonLabel
@onready var _content_label: Label = $VBox/ContentScroll/ContentLabel
@onready var _date_label: Label = $VBox/DateLabel


func show_email(entry: Dictionary, is_sent: bool) -> void:
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
