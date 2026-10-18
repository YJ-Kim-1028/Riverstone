extends Control

const UIUtil := preload("res://scripts/ui/ui_util.gd")

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

## 동적 선택지 줄: {"type": "dynamic_choice", "options": [{"label","callback"}, ...]}.
## CHOICE_TYPE과 화면/조작(▲▼ E, 라벨 목록)은 완전히 같지만 static JSON이
## 아니라 코드에서 그때그때 만든 목록을 보여줄 때 쓴다(사용자 지시,
## 2026-08-25 - "제단 선택도 npc 대화할 때처럼 하단에서, UI 창 느낌 아니게").
## 호감도/response 자동 처리 대신, 고른 option의 callback(Callable)을 그대로
## 호출한다 - 이어서 보여줄 대사가 있으면 콜백이 push_lines()를 부르고, 끝낼
## 거면 close()를 부른다(둘 중 하나는 반드시 호출해야 함).
const DYNAMIC_CHOICE_TYPE := "dynamic_choice"

## 선물 트리거 줄: {"type": "gift", "item_id": "..."}. 화면에 아무것도 띄우지
## 않고 그 자리에서 바로 아이템을 지급한 뒤 다음 줄로 넘어간다(사용자 지시 -
## 호감도 임계값이 아니라 "이 대사가 실제로 나왔을 때" 선물이 되어야 한다).
const GIFT_TYPE := "gift"

## 버프 트리거 줄: {"type": "buff", "percent", "duration_minutes", "is_debuff"}.
## GIFT_TYPE과 같은 패턴(화면에 아무것도 안 띄우고 바로 다음 줄로) - 세이지
## 운세 보기(NPCManager._build_fortune_offer_lines()) 전용. NPCManager는
## player를 직접 모르므로(main.gd 소유) 여기서 신호만 쏘고 실제 적용은
## main.gd가 한다.
const BUFF_TYPE := "buff"
signal buff_requested(percent: float, duration_minutes: int, is_debuff: bool)

## 효과음 트리거 줄: {"type": "sfx"}. GIFT_TYPE/BUFF_TYPE과 같은 패턴(화면에
## 아무것도 안 띄우고 바로 다음 줄로) - 마지막 줄로 넣어두면 "그 대사가 실제로
## 끝나는 순간" 소리가 난다. 호감도 이벤트 발생 시점(대사 뜨기 전)에 바로
## 트는 것보다 자연스럽다는 사용자 지시(2026-08-30 - 우디 옷장 이벤트, 지금은
## 대사 시작하자마자 나온다는 리포트) - AudioManager.SFX_MEMORY만 재사용,
## 필요해지면 그때 종류를 늘린다.
const SFX_TYPE := "sfx"

## npc_id 없이 여는 혼잣말(open_special("", ...), 예: 물귀신 낚시 이벤트)은
## 초상화가 없는데 TextureRect 자리만 비어 보여서 어색하다는 지적(사용자
## 리포트, 2026-08-24) - 초상화를 아예 숨기고, 텍스트 영역을 그 자리까지
## 왼쪽으로 당겨서 채운다.
const TEXT_AREA_OFFSET_LEFT_WITH_PORTRAIT := 30.0
const TEXT_AREA_OFFSET_LEFT_NO_PORTRAIT := 6.0

## 대화창 세로 크기/위치(루트 Control의 offset_top/offset_bottom - .tscn
## 원래 값과 동일).
const DEFAULT_BOX_OFFSET_TOP := -40.0
const DEFAULT_BOX_OFFSET_BOTTOM := -8.0
## furniture_desc(짧은 배경 가구 설명) 전용. offset_bottom은 화면 맨 아래에서
## 띄우는 여백 - 원래 -24였는데 "전체 화면과의 마진을 절반으로" 지적(사용자
## 지시, 2026-08-29)으로 -12로 줄임. offset_top으로 높이를 조절한다 - 높이
## 20(기존 8의 2.5배)이 확정값(사용자 확인, 2026-08-29).
const DESCRIPTION_BOX_OFFSET_BOTTOM := -12.0
const DESCRIPTION_BOX_HEIGHT := 20.0
const DESCRIPTION_BOX_OFFSET_TOP := DESCRIPTION_BOX_OFFSET_BOTTOM - DESCRIPTION_BOX_HEIGHT
const DEFAULT_BOX_HEIGHT := DEFAULT_BOX_OFFSET_BOTTOM - DEFAULT_BOX_OFFSET_TOP
## TextArea/AdvanceHintArea의 .tscn 원래(기본 높이 32 기준) 오프셋 - 박스
## 높이가 바뀔 때 _sync_pivot_to_height()가 이 값들에 비율을 곱해 같이
## 줄인다.
const TEXT_AREA_DEFAULT_OFFSET_TOP := 6.0
const TEXT_AREA_DEFAULT_OFFSET_BOTTOM := 56.0
const ADVANCE_HINT_DEFAULT_OFFSET_TOP := 24.0
const ADVANCE_HINT_DEFAULT_OFFSET_BOTTOM := 39.0
## Background(NinePatchRect)의 .tscn 원래 patch_margin_top/bottom 값.
const BACKGROUND_DEFAULT_PATCH_MARGIN_V := 16.0
## 설명창일 때 글씨/E▶에 추가로 주는 최소 여백(사용자 지시, 2026-08-29).
const DESCRIPTION_EXTRA_PADDING := 3.0

@onready var _background: Control = $Background
@onready var _portrait: TextureRect = $Background/Portrait
@onready var _text_area: Control = $Background/TextArea
@onready var _name_label: Label = $Background/TextArea/VBox/NameLabel
@onready var _text_label: Label = $Background/TextArea/VBox/TextLabel
@onready var _choice_box: VBoxContainer = $Background/TextArea/VBox/ChoiceBox
@onready var _advance_hint: Label = $Background/AdvanceHintArea/AdvanceHint
@onready var _advance_hint_area: Control = $Background/AdvanceHintArea

var _npc_id := ""
var _lines: Array = []
## open_description()으로 열렸는지 - main.gd가 이 경우만 화면 전체 디밍을
## 끄는 데 쓴다(is_description_mode() 참고).
var _is_description := false
var _line_index := 0
## 줄마다 "emotion"을 안 적으면 DEFAULT_EMOTION(평소 표정)으로 매번 리셋되던
## 문제(사용자 리포트, 2026-08-26 - "알리바이 말할 때 갑자기 웃는 얼굴이
## 나와서 이상해") - 애도 대사(emotion:"sad") 뒤에 조사만 치환해서 그대로
## 붙이는 알리바이 문장(순수 문자열이라 emotion 필드가 없음)이 이어지면
## 표정이 뜬금없이 평소 얼굴로 튀었다. 이제 emotion 명시 없는 줄은 직전 줄의
## 표정을 그대로 이어간다.
var _current_emotion := DEFAULT_EMOTION
var _pending_choice: Dictionary = {}
var _choice_index := 0
var _choice_labels: Array[Label] = []
var _is_dynamic_choice := false

## 타자기 효과(사용자 지시, 2026-08-23) - 한 글자씩 visible_characters를 늘려가며
## 보여준다. _typewriter_token은 진행 중인 코루틴을 무효화하는 용도 -
## _start_typewriter()가 호출될 때마다 증가시켜서, 이전 줄의 루프가 도중에
## 자기 token이 최신이 아님을 발견하면 스스로 멈춘다(새 줄이 이미 시작됐다는 뜻).
## 0.03 → 0.04로 살짝 늦춤(사용자 지시, 2026-08-26 - "지금 좀 빠른 거 같아서").
const TYPEWRITER_CHAR_INTERVAL := 0.04
## 매 글자마다 소리를 내면 너무 시끄러워서, 이 글자 수마다 한 번만 재생한다.
const TYPEWRITER_BLIP_SFX_STRIDE := 2
## 타자 소리가 너무 크다는 지적(사용자 지시, 2026-08-25) - 원래 음량의 20%만큼
## 줄인다. 20*log10(0.8) ≈ -1.94dB(선형 볼륨 기준 정확히 80%로 낮추는 값).
const TYPEWRITER_BLIP_VOLUME_DB := -1.94
var _typewriter_token := 0
var _is_typing := false


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
	if event.keycode == Keybinds.get_keycode(Keybinds.INTERACT_ACTION):
		if _is_typing:
			_complete_typewriter()
		else:
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
	## 엔터로도 확정되면 좋겠다는 지적(사용자 지시, 2026-08-25) - E와 동일 취급.
	elif keycode == Keybinds.get_keycode(Keybinds.INTERACT_ACTION) or keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_confirm_choice()
	elif keycode == KEY_ESCAPE:
		close()


func open_dialogue(npc_id: String) -> void:
	_is_description = false
	NPCManager.talk(npc_id)
	# duplicate(true): NPCManager가 돌려주는 배열은 JSON에서 로드된 원본 대사
	# 풀을 그대로 참조한다 - 선택지 응답을 _lines에 끼워 넣을 때 원본 데이터를
	# 건드리지 않도록 깊은 복사본을 쓴다.
	_open_with_lines(npc_id, (NPCManager.get_daily_dialogue(npc_id) as Array).duplicate(true))
	# _open_with_lines() -> _set_open()이 _refresh_layout()에서 앵커/오프셋을
	# 자기 자신에게 재대입하는데(export 앵커 버그 대응, day18), 그 과정에서
	# Godot이 "현재 실제 rect 기준으로 offset을 다시 계산"해버려 그 전에
	# 세팅한 값을 덮어쓴다(사용자 리포트, 2026-08-29 - 설명창 높이가 안
	# 줄어듦). 그래서 offset_top/offset_bottom은 반드시 _open_with_lines()
	# 호출 뒤에 마지막으로 세팅해야 확실히 남는다.
	offset_top = DEFAULT_BOX_OFFSET_TOP
	offset_bottom = DEFAULT_BOX_OFFSET_BOTTOM
	_sync_pivot_to_height()


## npc_talk_interacted 없이(플레이어가 직접 말 건 게 아니라) 코드에서 강제로
## 여는 일회성 대화 - 가구용 망치를 처음 받는 순간처럼, 요일/호감도별 로테이션
## (NPCManager.get_daily_dialogue())을 거치지 않고 정해진 대사만 그대로
## 보여주고 싶을 때 쓴다. lines가 비어있으면(아직 대사 안 채워짐)
## open_dialogue()와 동일하게 PLACEHOLDER_LINES로 대체된다.
## mark_talked=false는 플레이어가 E로 직접 건 대화가 아니라 강제로 재생되는
## 컷신 대사(heart_event_30 등)에 쓴다 - _talked_today를 건드리지 않아야
## 컷신이 끝난 뒤에도 그날 남은 시간에 정상적으로 말을 걸 수 있다(사용자
## 리포트, 2026-08-26 - "호감도 이벤트 끝나고 나서 그 날은 말걸기가 안 돼").
func open_special(npc_id: String, lines: Array, mark_talked: bool = true) -> void:
	_is_description = false
	if mark_talked:
		NPCManager.talk(npc_id)
	_open_with_lines(npc_id, lines)
	# open_dialogue()와 동일한 이유 - _refresh_layout()이 offset_top/bottom을
	# 덮어쓰므로 _open_with_lines() 다음에 마지막으로 세팅한다.
	offset_top = DEFAULT_BOX_OFFSET_TOP
	offset_bottom = DEFAULT_BOX_OFFSET_BOTTOM
	_sync_pivot_to_height()


## furniture_desc(맵에 미리 배치된 배경 가구 조사) 전용 - main.gd가 부른다.
## 대화창/나레이션창(open_special)과 스타일은 완전히 같고 높이만 짧게
## 줄인 채로 연다(사용자 지시, 2026-08-29 - "화면에 너무 가득 차서", 짧은
## 설명 몇 줄엔 기본 높이가 과하다는 지적). lines를 순서대로 전부 보여준다 -
## 무작위로 하나만 고르지 않는다("B안", 이전엔 랜덤 하나만 고르는 방식이었으나
## 사용자가 "한 번 조사하면 쓴 문장이 전부 순서대로 나오는" 쪽을 원함).
func open_description(lines: Array) -> void:
	_is_description = true
	_open_with_lines("", lines)
	# open_dialogue()와 동일한 이유 - _refresh_layout()이 offset_top/bottom을
	# 덮어쓰므로 _open_with_lines() 다음에 마지막으로 세팅한다.
	offset_top = DESCRIPTION_BOX_OFFSET_TOP
	offset_bottom = DESCRIPTION_BOX_OFFSET_BOTTOM
	_sync_pivot_to_height()


## TextArea/AdvanceHintArea는 전부 .tscn에서 기본 높이(32) 박스 하나에 맞춰
## 손으로 잡아둔 고정 오프셋이다(TextArea 6~56, AdvanceHintArea 24~39). 루트
## 높이만 바꾸고 이 자식들은 그대로 두면 서로 따로 놀 수밖에 없다(사용자
## 리포트, 2026-08-29 - "패딩도 없고 E도 따로 논다") - 전부 "기본 높이 대비
## 지금 높이 비율"로 같이 스케일한다. 이 화면은 scale=2.5를 pivot_offset
## 기준으로 적용하는데(.tscn 원래 값 (60,32) - 기본 높이 32의 딱 바닥 중앙),
## pivot_offset도 안 맞으면 스케일이 엉뚱한 점을 기준으로 걸려서 박스가
## 화면 밖으로 처박혀 보인다 - 그래서 이것도 매번 지금 높이로 다시 맞춘다.
func _sync_pivot_to_height() -> void:
	var current_height := offset_bottom - offset_top
	var ratio := current_height / DEFAULT_BOX_HEIGHT
	pivot_offset.y = current_height
	## 비율로만 줄이면 글씨/E▶가 테두리에 바싹 붙어 보인다는 지적(사용자 지시,
	## 2026-08-29) - 설명창일 때만 최소 여백을 추가로 더한다(기본 대화창은
	## 원래 크기라 이 문제가 없어서 그대로 둠).
	var extra_padding := DESCRIPTION_EXTRA_PADDING if _is_description else 0.0
	_text_area.offset_top = TEXT_AREA_DEFAULT_OFFSET_TOP * ratio + extra_padding
	_text_area.offset_bottom = TEXT_AREA_DEFAULT_OFFSET_BOTTOM * ratio
	_advance_hint_area.offset_top = ADVANCE_HINT_DEFAULT_OFFSET_TOP * ratio - extra_padding
	_advance_hint_area.offset_bottom = ADVANCE_HINT_DEFAULT_OFFSET_BOTTOM * ratio - extra_padding
	## Background(NinePatchRect) 테두리 그림의 patch_margin(.tscn 원래 16, 상하좌우
	## 전부)은 "기본 높이 32짜리 박스"용 픽셀 두께로 고정되어 있다 - 세로만
	## 8까지 줄어드는데 위/아래 여백은 그대로 16이면 도합 32(margin_top+bottom)가
	## 박스 자체 높이(8)보다 커져서, 모서리 그림이 다 못 들어가고 원래 크기로
	## 삐져나온다(사용자 리포트, 2026-08-29 - "패널이 밑에 고정돼서 나온다").
	## 가로(폭)는 안 바뀌므로 좌우 margin은 그대로 두고, 세로만 같은 비율로
	## 줄인다.
	var patch_margin_v := roundi(BACKGROUND_DEFAULT_PATCH_MARGIN_V * ratio)
	(_background as NinePatchRect).patch_margin_top = patch_margin_v
	(_background as NinePatchRect).patch_margin_bottom = patch_margin_v


func is_description_mode() -> bool:
	return _is_description


func _open_with_lines(npc_id: String, lines: Array) -> void:
	_npc_id = npc_id
	_lines = lines.duplicate(true)
	if _lines.is_empty():
		_lines = PLACEHOLDER_LINES.duplicate()
	_line_index = 0
	_current_emotion = DEFAULT_EMOTION
	_name_label.text = String(NPCManager.get_definition(npc_id).get("name", ""))
	## 설명창은 이름표 자체가 없는데도 빈 Label이 VBoxContainer separation과
	## 같이 줄 하나만큼 공간을 그냥 차지하고 있었다 - 안 그래도 좁힌 높이에서
	## 그 낭비가 두드러져서(사용자 리포트, 2026-08-29 - 스크린샷으로 확인,
	## 줄여도 여전히 크게 보임) 아예 감춘다.
	_name_label.visible = not _is_description
	_show_current_line()
	_set_open(true)


## 호감도 80 이상 부끄러움 임계값 - 대화 끝날 때 웃음 대신 이 이상이면
## 수줍음으로 바뀐다(사용자 지시, 2026-08-25).
const CLOSE_EMOTE_SHY_AFFECTION_THRESHOLD := 80


func close() -> void:
	# 웃음(또는 호감도 80 이상이면 수줍음): 대화 끝나고 헤어질 때(닫는 방식과
	# 무관 - 마지막 줄 넘김/ESC 둘 다). 단, 오늘 이 NPC가 살인 관련 스토리
	# 대사(애도/알리바이/목격 진술 또는 불륜 상대 사망 반응)를 한 참이면 웃음도
	# 수줍음도 안 어울린다 - 눈물을 유지한다(사용자 지시, 2026-08-26 - "그런
	# 대사를 하는 날엔 샤이도 안뜨는게 맞아").
	if not _npc_id.is_empty():
		if MurderManager.was_alibi_shown_today(_npc_id) or NPCManager.was_partner_death_reaction_shown_today(_npc_id):
			NPCManager.request_emote(_npc_id, NPCManager.EMOTE_DEJECTED)
		else:
			var emote := NPCManager.EMOTE_SHY if NPCManager.get_affection(_npc_id) >= CLOSE_EMOTE_SHY_AFFECTION_THRESHOLD else NPCManager.EMOTE_SMILE
			NPCManager.request_emote(_npc_id, emote)
	_typewriter_token += 1
	_is_typing = false
	_set_choice_mode(false)
	_pending_choice = {}
	_is_dynamic_choice = false
	_set_open(false)
	closed.emit()


func _advance() -> void:
	AudioManager.play_sfx(AudioManager.SFX_DIALOGUE_ADVANCE)
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
	if line is Dictionary and String(line.get("type", "")) == DYNAMIC_CHOICE_TYPE:
		_show_dynamic_choice(line)
		return
	if line is Dictionary and String(line.get("type", "")) == GIFT_TYPE:
		NPCManager.grant_gift_item(_npc_id, String(line.get("item_id", "")))
		_advance()
		return
	if line is Dictionary and String(line.get("type", "")) == BUFF_TYPE:
		buff_requested.emit(float(line.get("percent", 0.0)), int(line.get("duration_minutes", 0)), bool(line.get("is_debuff", false)))
		_advance()
		return
	if line is Dictionary and String(line.get("type", "")) == SFX_TYPE:
		AudioManager.play_sfx(AudioManager.SFX_MEMORY)
		_advance()
		return
	var text := ""
	var emotion := _current_emotion
	if line is Dictionary:
		text = String(line.get("text", ""))
		emotion = String(line.get("emotion", _current_emotion))
	else:
		text = String(line)
	_current_emotion = emotion
	# {player_name} 자리표시자 - 대사에서 플레이어를 이름으로 직접 부를 수 있게 한다.
	# {victim_name} - 살인사건 발견 씬(main.gd) 등에서 가장 최근 피해자 이름을
	# 그대로 부를 때 쓴다({player_mail_content}는 NPCManager.get_daily_dialogue()가
	# 뽑는 시점에 이미 치환해서 돌려주므로 여기서는 신경 쓸 필요 없음).
	var victim_name := String(NPCManager.get_definition(NPCManager.get_most_recent_death_npc_id()).get("name", ""))
	## 이름에 받침이 없으면(로시, 벨제 등) "{victim_name}이"처럼 받침 있는
	## 조사가 하드코딩된 데이터가 문법이 틀어진다(사용자 리포트, 2026-08-26) -
	## NPCManager.apply_korean_particles()가 이/가·은/는·을/를을 이름에 맞게
	## 골라준다.
	var resolved_text := NPCManager.apply_korean_particles(text, "{player_name}", GameManager.player_name)
	resolved_text = NPCManager.apply_korean_particles(resolved_text, "{victim_name}", victim_name)
	# {days_since_arrival} - 플레이어가 마을에 온 지 며칠째인지(TimeManager.current_day,
	# 첫날=1). 숫자 그대로 넣는 자리라 조사 처리가 필요 없다(사용자 지시, 2026-08-26).
	resolved_text = resolved_text.replace("{days_since_arrival}", str(TimeManager.current_day))
	_start_typewriter(resolved_text)
	_update_portrait(emotion)


## 대사 한 줄을 한 글자씩 늘려가며 보여준다(사용자 지시, 2026-08-23). 텍스트
## 자체는 처음부터 전부 대입해둬야 줄바꿈/크기 계산이 완성본 기준으로 맞고,
## visible_characters로 실제 노출 글자 수만 제어한다.
func _start_typewriter(text: String) -> void:
	_typewriter_token += 1
	var token := _typewriter_token
	_text_label.text = text
	_text_label.visible_characters = 0
	var length := text.length()
	if length == 0:
		_is_typing = false
		return
	_is_typing = true
	for i in length:
		await get_tree().create_timer(TYPEWRITER_CHAR_INTERVAL).timeout
		if token != _typewriter_token:
			return
		_text_label.visible_characters = i + 1
		if i % TYPEWRITER_BLIP_SFX_STRIDE == 0:
			AudioManager.play_sfx(AudioManager.SFX_DIALOGUE_TYPE, TYPEWRITER_BLIP_VOLUME_DB)
	_is_typing = false


## E로 타이핑 도중 넘기면(사용자 지시) 즉시 전체 텍스트를 다 보여주고 끝낸다 -
## 다음 E 입력은 그제서야 다음 줄로 넘어간다(한 번에 두 동작이 겹치지 않게).
func _complete_typewriter() -> void:
	_typewriter_token += 1
	_text_label.visible_characters = -1
	_is_typing = false


func _update_portrait(emotion: String) -> void:
	if _npc_id.is_empty():
		_portrait.visible = false
		_text_area.offset_left = TEXT_AREA_OFFSET_LEFT_NO_PORTRAIT
		return
	_portrait.visible = true
	_text_area.offset_left = TEXT_AREA_OFFSET_LEFT_WITH_PORTRAIT
	var portraits: Dictionary = NPCManager.get_definition(_npc_id).get("portraits", {})
	var path := String(portraits.get(emotion, portraits.get("default", "")))
	_portrait.texture = load(path) if not path.is_empty() else null
	_portrait.material = null if NPCManager.is_alive(_npc_id) else NPCManager.get_dead_portrait_material()


func _is_choice_active() -> bool:
	return not _pending_choice.is_empty()


func _show_choice(choice: Dictionary) -> void:
	_is_dynamic_choice = false
	_pending_choice = choice
	_choice_index = 0
	_rebuild_choice_labels()
	_set_choice_mode(true)


func _show_dynamic_choice(choice: Dictionary) -> void:
	_is_dynamic_choice = true
	_pending_choice = choice
	_choice_index = 0
	_rebuild_choice_labels()
	_set_choice_mode(true)


## 대화창을 닫지 않은 채(입력 잠금/모달 상태 유지, closed 신호도 안 쏨) 대사
## 상자 전체(초상화+텍스트박스)만 잠깐 숨긴다 - 제단 부활 컷신의 화면 깜빡임
## 연출 중엔 대사창이 아예 안 보여야 한다는 지적(사용자 지시, 2026-08-26 -
## "깜빡일 때는 아무런 대화창도 안보여야 맞지"). close()로 완전히 닫으면
## 호출부의 "await dialogue_screen.closed"가 거기서 끝나버려서 이어지는
## 나레이션을 못 보여주므로, 시각적으로만 숨기는 이 방법을 쓴다.
func set_box_visible(box_visible: bool) -> void:
	_background.visible = box_visible


## DYNAMIC_CHOICE_TYPE 옵션의 callback 안에서 호출 - 지금 대화 흐름에 새 줄을
## 이어붙이고 바로 다음 줄(방금 끼워넣은 첫 줄)로 넘어간다. 정적 choice의
## response 삽입과 완전히 같은 방식(CHOICE_TYPE 처리부 참고)이라 대사/선택지가
## 자연스럽게 이어진다 - 예: 부활 대상을 고른 뒤 "정말 되살리시겠습니까?"
## 확인 선택지를 이어붙일 때.
func push_lines(lines: Array) -> void:
	for i in lines.size():
		_lines.insert(_line_index + 1 + i, lines[i])
	_advance()


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
	if _is_dynamic_choice:
		_is_dynamic_choice = false
		_pending_choice = {}
		_set_choice_mode(false)
		var callback: Callable = chosen.get("callback", Callable())
		if callback.is_valid():
			callback.call()
		else:
			_advance()
		return
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
	var key_label := Keybinds.get_key_label(Keybinds.INTERACT_ACTION)
	_advance_hint.text = "▲▼ %s" % key_label if active else "%s ▶" % key_label


func _is_open() -> bool:
	return modulate.a > 0.0


## 익스포트 빌드에서 앵커 기반 크기/위치가 창이 완전히 자리잡기 전 값으로
## 굳어버리는 문제 회피(사용자 리포트, 2026-08-26) - 값은 그대로 자신에게
## 다시 대입해서 Godot이 현재 부모 크기 기준으로 강제로 다시 계산하게 만든다.
func _refresh_layout() -> void:
	anchor_left = anchor_left
	anchor_top = anchor_top
	anchor_right = anchor_right
	anchor_bottom = anchor_bottom
	offset_left = offset_left
	offset_top = offset_top
	offset_right = offset_right
	offset_bottom = offset_bottom


func _set_open(is_open: bool) -> void:
	if is_open:
		_refresh_layout()
	modulate.a = 1.0 if is_open else 0.0
	## 다른 17개 화면과 달리 이 화면만 루트 자신의 mouse_filter만 바꾸고
	## 자식들은 그대로 뒀었다 - 정적 배치된 자식들은 .tscn에 전부
	## mouse_filter=2(IGNORE)가 미리 박혀있어서 평소엔 안 드러났지만,
	## _rebuild_choice_labels()가 동적으로 만드는 선택지 Label은 이 설정이
	## 없어서 기본값(STOP)인 채로 다음 선택지 대화 전까지 남아있을 수 있다
	## (사용자 리포트, 2026-08-29 - 대화 이후 다른 화면 버튼이 안 눌림 조사).
	## 다른 화면들과 동일하게 재귀로 통일한다.
	UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
