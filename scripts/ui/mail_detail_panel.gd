extends Control

## MailWindow(mail_app.gd)의 메일 자세히보기. 수신함에서 들어왔으면
## "보낸 사람", 발신함에서 들어왔으면 "수신인"으로 라벨만 바뀐다.

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _person_label: Label = $VBox/PersonLabel
@onready var _content_label: Label = $VBox/ContentScroll/ContentLabel
@onready var _date_label: Label = $VBox/DateLabel


func show_email(entry: Dictionary, is_sent: bool) -> void:
	_title_label.text = String(entry.get("title", ""))
	var npc_id := String(entry.get("npc_id", ""))
	var npc_name := String(NPCManager.get_definition(npc_id).get("name", npc_id))
	_person_label.text = ("수신인 : %s" if is_sent else "보낸 사람 : %s") % npc_name
	var lines: Array = entry.get("lines", [])
	_content_label.text = "\n".join(lines)
	_date_label.text = String(entry.get("date", ""))
