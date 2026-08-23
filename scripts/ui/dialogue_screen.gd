extends Control

## NPC와의 일일 대화 화면. main.gd가 npc_talk_interacted 신호로
## open_dialogue(npc_id)를 호출한다. NPCManager.get_daily_dialogue()가 돌려주는
## 여러 줄을 한 줄씩 보여주다가 마지막 줄에서 E를 누르면 닫힌다.
## 실제 대사 문구는 기획자 콘텐츠 영역이라, dialogue.daily/*가 비어있는
## 동안에는(아직 아무것도 안 채워짐) 자리표시자 여러 줄을 대신 보여준다 -
## 한 줄만 두면 "여러 줄 넘기기"가 실제로 잘 되는지 테스트할 수 없어서, 임시로
## 3줄을 둔다(진짜 대사가 채워지면 이 폴백은 안 쓰인다).
## 살인 발견 씬(main.gd) 등 "대화가 끝나면 뒷정리를 해야 하는" 컷신에서
## 쓴다 - 마지막 줄 넘김/ESC 어느 쪽으로 닫히든 emit.
signal closed

const PLACEHOLDER_LINES: Array[String] = [
	"TODO: 첫 번째 자리표시자 문장 - 아직 실제 대사가 없습니다.",
	"TODO: 두 번째 문장은 이렇게 완전히 다른 내용입니다.",
	"TODO: 세 번째, 마지막 자리표시자 문장입니다.",
]

## 대사 줄은 문자열(감정 기본값 default, 무표정) 또는 {"text","emotion"} 딕셔너리(감정 지정) 둘 다 허용한다.
## 기쁜 대사만 "happy"로 명시 태그하고, 나머지는 무표정이 기본이 되도록 사용자가 확정함(2026-08-12).
const DEFAULT_EMOTION := "default"

## 선택지 줄: {"type": "choice", "options": [{"label","affection","response"}, ...]}.
## 플레이어가 고른 option의 response(줄 배열)가 선택 직후 바로 이어서 보여진다.
const CHOICE_TYPE := "choice"

## 선물 트리거 줄: {"type": "gift", "item_id": "..."}. 화면에 아무것도 띄우지
## 않고 그 자리에서 바로 아이템을 지급한 뒤 다음 줄로 넘어간다(사용자 지시 -
## 호감도 임계값이 아니라 "이 대사가 실제로 나왔을 때" 선물이 되어야 한다).
const GIFT_TYPE := "gift"

@onready var _portrait: TextureRect = $Background/Portrait
@onready var _name_label: Label = $Background/TextArea/VBox/NameLabel
@onready var _text_label: Label = $Background/TextArea/VBox/TextLabel
@onready var _choice_box: VBoxContainer = $Background/TextArea/VBox/ChoiceBox
@onready var _advance_hint: Label = $Background/AdvanceHintArea/AdvanceHint

var _npc_id := ""
var _lines: Array = []
var _line_index := 0
var _pending_choice: Dictionary = {}
var _choice_index := 0
var _choice_labels: Array[Label] = []


func _ready() -> void:
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _is_choice_active():
		_handle_choice_input(event.keycode)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_E:
		_advance()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _handle_choice_input(keycode: int) -> void:
	if keycode == KEY_UP:
		_move_choice(-1)
	elif keycode == KEY_DOWN:
		_move_choice(1)
	elif keycode == KEY_E:
		_confirm_choice()
	elif keycode == KEY_ESCAPE:
		close()


func open_dialogue(npc_id: String) -> void:
	NPCManager.talk(npc_id)
	# duplicate(true): NPCManager가 돌려주는 배열은 JSON에서 로드된 원본 대사
	# 풀을 그대로 참조한다 - 선택지 응답을 _lines에 끼워 넣을 때 원본 데이터를
	# 건드리지 않도록 깊은 복사본을 쓴다.
	_open_with_lines(npc_id, (NPCManager.get_daily_dialogue(npc_id) as Array).duplicate(true))


## npc_talk_interacted 없이(플레이어가 직접 말 건 게 아니라) 코드에서 강제로
## 여는 일회성 대화 - 가구용 망치를 처음 받는 순간처럼, 요일/호감도별 로테이션
## (NPCManager.get_daily_dialogue())을 거치지 않고 정해진 대사만 그대로
## 보여주고 싶을 때 쓴다. lines가 비어있으면(아직 대사 안 채워짐)
## open_dialogue()와 동일하게 PLACEHOLDER_LINES로 대체된다.
func open_special(npc_id: String, lines: Array) -> void:
	NPCManager.talk(npc_id)
	_open_with_lines(npc_id, lines)


func _open_with_lines(npc_id: String, lines: Array) -> void:
	_npc_id = npc_id
	_lines = lines.duplicate(true)
	if _lines.is_empty():
		_lines = PLACEHOLDER_LINES.duplicate()
	_line_index = 0
	_name_label.text = String(NPCManager.get_definition(npc_id).get("name", ""))
	_show_current_line()
	_set_open(true)


func close() -> void:
	# 웃음: 대화 끝나고 헤어질 때(닫는 방식과 무관 - 마지막 줄 넘김/ESC 둘 다).
	if not _npc_id.is_empty():
		NPCManager.request_emote(_npc_id, NPCManager.EMOTE_SMILE)
	_set_choice_mode(false)
	_pending_choice = {}
	_set_open(false)
	closed.emit()


func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		close()
		return
	_show_current_line()


func _show_current_line() -> void:
	var line: Variant = _lines[_line_index]
	if line is Dictionary and String(line.get("type", "")) == CHOICE_TYPE:
		_show_choice(line)
		return
	if line is Dictionary and String(line.get("type", "")) == GIFT_TYPE:
		NPCManager.grant_gift_item(_npc_id, String(line.get("item_id", "")))
		_advance()
		return
	var text := ""
	var emotion := DEFAULT_EMOTION
	if line is Dictionary:
		text = String(line.get("text", ""))
		emotion = String(line.get("emotion", DEFAULT_EMOTION))
	else:
		text = String(line)
	# {player_name} 자리표시자 - 대사에서 플레이어를 이름으로 직접 부를 수 있게 한다.
	# {victim_name} - 살인사건 발견 씬(main.gd) 등에서 가장 최근 피해자 이름을
	# 그대로 부를 때 쓴다({player_mail_content}는 NPCManager.get_daily_dialogue()가
	# 뽑는 시점에 이미 치환해서 돌려주므로 여기서는 신경 쓸 필요 없음).
	var victim_name := String(NPCManager.get_definition(NPCManager.get_most_recent_death_npc_id()).get("name", ""))
	_text_label.text = text.replace("{player_name}", GameManager.player_name).replace("{victim_name}", victim_name)
	_update_portrait(emotion)


func _update_portrait(emotion: String) -> void:
	var portraits: Dictionary = NPCManager.get_definition(_npc_id).get("portraits", {})
	var path := String(portraits.get(emotion, portraits.get("default", "")))
	_portrait.texture = load(path) if not path.is_empty() else null
	_portrait.material = null if NPCManager.is_alive(_npc_id) else NPCManager.get_dead_portrait_material()


func _is_choice_active() -> bool:
	return not _pending_choice.is_empty()


func _show_choice(choice: Dictionary) -> void:
	_pending_choice = choice
	_choice_index = 0
	_rebuild_choice_labels()
	_set_choice_mode(true)


func _rebuild_choice_labels() -> void:
	for child in _choice_box.get_children():
		child.queue_free()
	_choice_labels.clear()
	var options: Array = _pending_choice.get("options", [])
	for option in options:
		var label := Label.new()
		label.add_theme_font_override("font", _text_label.get_theme_font("font"))
		label.add_theme_font_size_override("font_size", _text_label.get_theme_font_size("font_size"))
		label.add_theme_color_override("font_color", _text_label.get_theme_color("font_color"))
		_choice_box.add_child(label)
		_choice_labels.append(label)
	_update_choice_highlight()


func _update_choice_highlight() -> void:
	var options: Array = _pending_choice.get("options", [])
	for i in _choice_labels.size():
		var option_label := String((options[i] as Dictionary).get("label", ""))
		var prefix := "▶ " if i == _choice_index else "   "
		_choice_labels[i].text = prefix + option_label


func _move_choice(delta: int) -> void:
	var count: int = (_pending_choice.get("options", []) as Array).size()
	if count == 0:
		return
	_choice_index = wrapi(_choice_index + delta, 0, count)
	_update_choice_highlight()


func _confirm_choice() -> void:
	var options: Array = _pending_choice.get("options", [])
	if _choice_index >= options.size():
		return
	var chosen: Dictionary = options[_choice_index]
	NPCManager.apply_dialogue_choice(_npc_id, int(chosen.get("affection", 0)))
	var response: Array = chosen.get("response", [])
	_pending_choice = {}
	_set_choice_mode(false)
	for i in response.size():
		_lines.insert(_line_index + 1 + i, response[i])
	_advance()


func _set_choice_mode(active: bool) -> void:
	_choice_box.visible = active
	_text_label.visible = not active
	_advance_hint.text = "▲▼ E" if active else "E ▶"


func _is_open() -> bool:
	return modulate.a > 0.0


func _set_open(is_open: bool) -> void:
	modulate.a = 1.0 if is_open else 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
