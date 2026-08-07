extends Control

## NPC와의 일일 대화 화면. main.gd가 npc_talk_interacted 신호로
## open_dialogue(npc_id)를 호출한다. NPCManager.get_daily_dialogue()가 돌려주는
## 여러 줄을 한 줄씩 보여주다가 마지막 줄에서 E를 누르면 닫힌다.
## 실제 대사 문구는 기획자 콘텐츠 영역이라, dialogue.daily/*가 비어있는
## 동안에는(아직 아무것도 안 채워짐) 자리표시자 여러 줄을 대신 보여준다 -
## 한 줄만 두면 "여러 줄 넘기기"가 실제로 잘 되는지 테스트할 수 없어서, 임시로
## 3줄을 둔다(진짜 대사가 채워지면 이 폴백은 안 쓰인다).
const PLACEHOLDER_LINES: Array[String] = [
	"TODO: 첫 번째 자리표시자 문장 - 아직 실제 대사가 없습니다.",
	"TODO: 두 번째 문장은 이렇게 완전히 다른 내용입니다.",
	"TODO: 세 번째, 마지막 자리표시자 문장입니다.",
]

@onready var _portrait: TextureRect = $Background/Portrait
@onready var _name_label: Label = $Background/TextArea/VBox/NameLabel
@onready var _text_label: Label = $Background/TextArea/VBox/TextLabel

var _npc_id := ""
var _lines: Array = []
var _line_index := 0


func _ready() -> void:
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


func open_dialogue(npc_id: String) -> void:
	_npc_id = npc_id
	NPCManager.talk(npc_id)
	_lines = NPCManager.get_daily_dialogue(npc_id)
	if _lines.is_empty():
		_lines = PLACEHOLDER_LINES.duplicate()
	_line_index = 0
	_name_label.text = String(NPCManager.get_definition(npc_id).get("name", ""))
	_update_portrait()
	_show_current_line()
	_set_open(true)


func close() -> void:
	# 웃음: 대화 끝나고 헤어질 때(닫는 방식과 무관 - 마지막 줄 넘김/ESC 둘 다).
	if not _npc_id.is_empty():
		NPCManager.request_emote(_npc_id, NPCManager.EMOTE_SMILE)
	_set_open(false)


func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		close()
		return
	_show_current_line()


func _show_current_line() -> void:
	_text_label.text = String(_lines[_line_index])


func _update_portrait() -> void:
	var portraits: Dictionary = NPCManager.get_definition(_npc_id).get("portraits", {})
	var path := String(portraits.get("default", ""))
	_portrait.texture = load(path) if not path.is_empty() else null


func _is_open() -> bool:
	return modulate.a > 0.0


func _set_open(is_open: bool) -> void:
	modulate.a = 1.0 if is_open else 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
