extends Node

## Ambient/flavor horror beats from horror_events.md, plus the staged
## stalker emails from email.md/stalker.md. Doesn't own murder logic
## (MurderManager does) - just decides "should this flavor event happen
## right now" and hands back line pools for a future dialogue/email UI.

signal knock_event_triggered
signal impersonation_email_ready(npc_id: String, title: String, lines: Array)
## quiet가 true면 EmailManager/mail_detail_panel.gd가 무서운 효과음
## (SFX_STALKER_MAIL) 대신 평범한 메일 효과음을 쓴다 - QUIET_STALKER_EMAIL_COUNT
## 참고.
signal stalker_email_ready(sender_id: String, title: String, lines: Array, quiet: bool)

const KNOCK_PROBABILITY := 0.3
const KNOCK_MAP_ID := "home_interior"

const STALKER_EMAILS_PATH := "res://data/horror/stalker_emails.json"
const IMPERSONATION_EMAILS_PATH := "res://data/horror/impersonation_emails.json"

## 발신인을 알 수 없는 메일이라, 진짜 NPC id가 아니라 이 문자열을 그대로
## npc_id 겸 표시 이름으로 쓴다 - NPCManager.get_definition("???")은 빈
## Dictionary를 돌려주고, mail_list_panel.gd/mail_app.gd 둘 다
## `.get("name", npc_id)`처럼 npc_id를 그대로 폴백으로 쓰는 구조라 초상화 없이
## "???"라는 발신인 이름만 자연스럽게 뜬다.
const STALKER_SENDER_ID := "???"
## email.md에 스토커 메일 발송 빈도 규칙이 없어 사용자 지시(2026-08-15)로
## "며칠에 한 번씩" 고정 간격을 뒀다 - 임의 값, 필요하면 조정.
const STALKER_EMAIL_INTERVAL_DAYS := 3
## 원래 Day 2(첫 취침 직후)부터 바로 왔는데, 플레이어가 NPC들과 최소 한 번씩은
## 대화할 시간을 준 뒤 시작하길 원해 사용자 지시(2026-08-16)로 미룸 - Day 8로
## 미뤘다가 너무 늦다는 지적으로 Day 5로 다시 당김(사용자 지시, 2026-08-26).
const STALKER_EMAIL_START_DAY := 5
## 스토커 메일을 여는 무서운 효과음(SFX_STALKER_MAIL)이 첫 통부터 나오면
## 공포라는 걸 너무 일찍 드러낸다는 지적(사용자 지시, 2026-08-26 - "처음부터
## 공포라는걸 너무 알려주고 싶진 않단말이야... 7번째 메일부터 호러
## 효과음이 들리면 돼"). early 풀의 앞 6통(장난스러운 익명 펜팔 톤)까지는
## 평범한 메일 효과음, 7번째("어제 저녁 네 밭을 구경했어" - 스토킹이 처음
## 명시적으로 드러남)부터 무서운 효과음으로 바뀐다. stalker_email_ready
## 신호의 quiet 인자로 넘긴다.
const QUIET_STALKER_EMAIL_COUNT := 6

var _stalker_emails: Dictionary = {}
var _impersonation_emails: Dictionary = {}
var _impersonation_sent: Dictionary = {}
## horror_events.md "레스토랑 액자 이벤트" 트리거 상태 - consume_restaurant_frame_blood_trigger() 참고.
var _restaurant_frame_blood_shown_for_murder_count := 0
## 스토커 메일을 early→mid→late 순서(파일에 적힌 순서 그대로) 하나씩 순차
## 발송하기 위한 상태 - _stalker_email_unlocked_pool() 참고.
var _stalker_email_index := 0
var _last_stalker_email_day := -STALKER_EMAIL_INTERVAL_DAYS
## 2차 살인: 플레이어가 자루를 직접 발견한 직후 보내는 전용 스토커 메일 -
## 내용은 코드가 아니라 stalker_emails.json의 "second_murder_sack" 키에서
## 가져온다(사용자 지시, 2026-08-26 - "스토커 메일 json에서 수정할 수 있는거지?" -
## 다른 스토커 메일들과 동일하게 데이터로만 관리, 코드에는 대사 없음). 위
## 주기적 발송(_maybe_send_stalker_email)과 별개로 발견 직후 딱 한 번만 보낸다.
var _second_murder_sack_email_sent := false
## consume_sage_warning_line()이 오늘 이미 경고 대사를 내줬는지 추적.
var _sage_warning_last_shown_day := -1
## 세이지의 일회성 스토리 대사 2종 - 한 번 보여주면 다시 안 나옴.
var _sage_soul_sight_shown := false
var _sage_poisoned_innocent_shown := false


func _ready() -> void:
	_stalker_emails = _load_json(STALKER_EMAILS_PATH)
	_impersonation_emails = _load_json(IMPERSONATION_EMAILS_PATH)
	TimeManager.night_events_enabled.connect(_on_night_events_enabled)
	TimeManager.day_changed.connect(_on_day_changed)


## horror_events.md "세이지": 살인 조건을 충족하는 날 대화를 나누면 경고 대사가
## 나온다. "충족하는 날"을 비가 오고 있고 아직 처리되지 않은 대기 대상이 있는
## 날로 해석했다 (스토커의 위치 조건까지는 세이지가 알 도리가 없으므로 제외).
## 2026-08-16 사용자 확정: 조건 맞으면 랜덤이 아니라 무조건 나오되, 하루에
## 한 번만. 실제 문구는 다른 NPC 대사와 같은 컨벤션으로 sage.json의
## story_dialogue.murder_warning_examples 풀에 있다(사용자가 직접 채움) -
## 여기선 "오늘 이미 보여줬는지 + 조건"만 판정하고, 그 풀에서 실제로 하나
## 골라 보여주는 건 NPCManager.get_daily_dialogue()가 한다.
func consume_sage_warning_trigger() -> bool:
	if MurderManager.is_stalker_killed():
		return false
	if not (WeatherManager.is_raining() and MurderManager.has_pending_victim()):
		return false
	if _sage_warning_last_shown_day == TimeManager.current_day:
		return false
	_sage_warning_last_shown_day = TimeManager.current_day
	return true


## sage.json special_notes: "첫 번째 살인 사건 이후 플레이어 곁의 정체불명
## 영혼을 보기 시작한다" - 첫 살인 이후 세이지와의 대화에서 한 번만 나온다.
func consume_sage_soul_sight_trigger() -> bool:
	if _sage_soul_sight_shown or MurderManager.get_murder_count() < 1:
		return false
	_sage_soul_sight_shown = true
	return true


## 공범 엔딩(무고한 NPC를 독살) 확정 이후 세이지와의 대화에서 한 번만 나온다.
## murder_warning_examples/soul_sight보다 더 구체적이고 드문 사건이라
## NPCManager.get_daily_dialogue()에서 우선순위가 가장 높다.
func consume_sage_poisoned_innocent_trigger() -> bool:
	if _sage_poisoned_innocent_shown or not MurderManager.is_accomplice_ending():
		return false
	_sage_poisoned_innocent_shown = true
	return true


## stalker.md는 이메일이 "초반/중반/후반"으로 톤이 바뀐다고만 하고 정확한 전환
## 조건은 안 정해뒀다. 스토커가 실제로 저지른 살인 수(공포가 실제로 진행된
## 정도)를 기준으로 삼은 건 이 구현의 해석이며, 다른 기준이 낫다면 바꾸면 된다.
func get_stalker_email_stage() -> String:
	var count := MurderManager.get_murder_count()
	if count >= 2:
		return "late"
	if count >= 1:
		return "mid"
	return "early"


## 2026-08-15 재설계(사용자 확정): 랜덤이 아니라 early→mid→late 순서(각 배열
## 내부도 적힌 순서 그대로) 하나씩 순차 발송한다. 다만 아직 안 일어난 살인
## 단계의 문구(예: 살인 전인데 late의 위협적인 내용)가 먼저 나가면 안 되므로,
## 지금 살인 건수로 "열린" 단계까지만 풀에 포함시켜 상한을 건다 - 이미 다
## 보낸 상태에서 다음 살인이 아직 안 났으면 그 시점까지는 더 안 보내고 멈춘다.
func _stalker_email_unlocked_pool() -> Array:
	var pool: Array = (_stalker_emails.get("early", []) as Array).duplicate()
	var murder_count := MurderManager.get_murder_count()
	if murder_count >= 1:
		pool.append_array(_stalker_emails.get("mid", []))
	if murder_count >= 2:
		pool.append_array(_stalker_emails.get("late", []))
	return pool


## npc_id 전용 문구가 없으면 "default"(공용 문구)로 대체한다 - 사망 사칭 메일은
## 어차피 스토커가 그 사람 흉내를 내는 것뿐이라 본인 목소리가 아니어도
## 자연스럽고, 13명 전부 따로 쓰지 않아도 된다는 사용자 확정(2026-08-15).
## 반환값은 {"title","lines"} - data/npc/*.json 이메일과 같은 모양으로 통일함.
## 2026-08-24: 두 번째 희생자가 첫 번째와 똑같은 문구를 또 받으면 어색하다는
## 지적으로, "default_<case_number>"가 있으면 우선 쓰고(murder_grief_<N>과
## 동일한 폴백 방식) 없으면 그냥 "default"로 대체한다.
func get_impersonation_email(npc_id: String, case_number: int = 0) -> Dictionary:
	if _impersonation_emails.has(npc_id):
		return (_impersonation_emails[npc_id] as Dictionary).duplicate(true)
	var numbered_key := "default_%d" % case_number
	if case_number > 0 and _impersonation_emails.has(numbered_key):
		return (_impersonation_emails[numbered_key] as Dictionary).duplicate(true)
	return (_impersonation_emails.get("default", {}) as Dictionary).duplicate(true)


func get_save_data() -> Dictionary:
	return {
		"impersonation_sent": _impersonation_sent.duplicate(),
		"restaurant_frame_blood_shown_for_murder_count": _restaurant_frame_blood_shown_for_murder_count,
		"stalker_email_index": _stalker_email_index,
		"last_stalker_email_day": _last_stalker_email_day,
		"sage_warning_last_shown_day": _sage_warning_last_shown_day,
		"sage_soul_sight_shown": _sage_soul_sight_shown,
		"sage_poisoned_innocent_shown": _sage_poisoned_innocent_shown,
		"second_murder_sack_email_sent": _second_murder_sack_email_sent,
	}


func load_save_data(data: Dictionary) -> void:
	_impersonation_sent = (data.get("impersonation_sent", {}) as Dictionary).duplicate()
	_restaurant_frame_blood_shown_for_murder_count = int(data.get("restaurant_frame_blood_shown_for_murder_count", 0))
	_stalker_email_index = int(data.get("stalker_email_index", 0))
	_last_stalker_email_day = int(data.get("last_stalker_email_day", -STALKER_EMAIL_INTERVAL_DAYS))
	_sage_warning_last_shown_day = int(data.get("sage_warning_last_shown_day", -1))
	_sage_soul_sight_shown = bool(data.get("sage_soul_sight_shown", false))
	_sage_poisoned_innocent_shown = bool(data.get("sage_poisoned_innocent_shown", false))
	_second_murder_sack_email_sent = bool(data.get("second_murder_sack_email_sent", false))


## horror_events.md "레스토랑 액자 이벤트" - 살인이 새로 일어난 뒤 플레이어가
## 레스토랑에 처음 들어올 때 딱 한 번만 발동시킨다(살인 1건당 최대 1회, 최대
## 2번 살인이니 총 최대 2번). 매번 입장할 때마다 재생되면 일상 플레이를
## 방해한다는 사용자 피드백(2026-08-15)으로 "입장마다"에서 이렇게 바꿈.
## 디버그 전용(game_manager.gd F12) - 이미 소비된 상태여도 레스토랑 재입장
## 시 다시 뜨게 리셋한다. 실제로 murder_count가 어디까지 갔는지는 안 건드리고
## "몇 번째까지 보여줬는지"만 0으로 되돌린다.
func debug_reset_restaurant_frame_blood_trigger() -> void:
	_restaurant_frame_blood_shown_for_murder_count = 0


## 디버그 전용(game_manager.gd F10 - F8은 Godot 에디터 "실행 중지" 단축키와
## 겹쳐서 F10으로 바꿈) - murder_count/맵/시간/확률 조건을 다 건너뛰고 노크
## 사운드 시퀀스만 바로 들어본다(사용자 리포트, 2026-08-24: 실제 조건을 다
## 맞춰서 테스트하기엔 너무 번거로움 - 조건만 알려주는 걸로 바꿨다가 다시
## 요청함).
func debug_trigger_knock_event() -> void:
	knock_event_triggered.emit()


func consume_restaurant_frame_blood_trigger() -> bool:
	var murder_count := MurderManager.get_murder_count()
	if murder_count <= _restaurant_frame_blood_shown_for_murder_count:
		return false
	_restaurant_frame_blood_shown_for_murder_count = murder_count
	return true


## horror_events.md "집 이벤트": 첫 번째 살인 이후부터, 매일 밤 30% 확률로,
## 플레이어가 집(home_interior) 안에 있을 때만 노크 소리가 발동한다.
func _on_night_events_enabled() -> void:
	if MurderManager.get_murder_count() <= 0:
		return
	if GameManager.current_map_id != KNOCK_MAP_ID:
		return
	if randf() <= KNOCK_PROBABILITY:
		knock_event_triggered.emit()


## email.md "NPC 사망 이후": NPC가 죽으면 다음 날 그 NPC 명의로 메일이 온다.
## 이건 "스토커가 자기 희생자 행세를 하며 플레이어를 놀리는" 연출이라
## 스토커가 직접 죽인 NPC에만 해당한다 - 플레이어가 독약으로 죽인 NPC(공범
## 엔딩)에게도 그대로 나가서, 스토커가 죽인 것처럼 보이는 사칭 메일이
## 도착하는 버그가 있었다(사용자 리포트, 2026-08-26 - "내가 잘못 독살한 npc가
## 마치 두번째로 살해당한거처럼 나에게 메일을 보냈어... 이거 스토커가 죽인게
## 아니라 내가 죽인건데"). MurderManager.get_player_killed_npc_id()로 걸러낸다.
func _on_day_changed(_day: int, _weekday: String) -> void:
	for npc_id in NPCManager.get_dead_npc_ids():
		if bool(_impersonation_sent.get(npc_id, false)):
			continue
		if TimeManager.current_day != NPCManager.get_death_day(npc_id) + 1:
			continue
		if npc_id == MurderManager.get_player_killed_npc_id():
			_impersonation_sent[npc_id] = true
			continue
		_impersonation_sent[npc_id] = true
		var email := get_impersonation_email(npc_id, MurderManager.get_case_number_for_victim(npc_id))
		# 사칭 메일은 항상 "죽은 그 본인" 명의니까 {victim_name}은 최근 사망자
		# 조회 없이 이 npc_id 자신의 이름으로 바로 채운다("나야, {victim_name}"
		# 처럼 죽은 사람이 자기 이름을 대는 용도).
		var self_name := String(NPCManager.get_definition(npc_id).get("name", ""))
		impersonation_email_ready.emit(npc_id, NPCManager.apply_korean_particles(String(email.get("title", "")), "{victim_name}", self_name), _substitute_victim_name((email.get("lines", []) as Array), self_name))
	_maybe_send_stalker_email()


## stalker.md 진실 엔딩: 어셔가 죽으면 이메일이 완전히 중단된다. 그 외엔
## STALKER_EMAIL_INTERVAL_DAYS마다 한 번씩, _stalker_email_unlocked_pool()의
## 다음 순번을 보낸다 - 이미 다 보냈거나(index가 풀 크기를 넘음) 다음 살인
## 단계가 아직 안 열렸으면 그냥 스킵.
func _maybe_send_stalker_email() -> void:
	if MurderManager.is_stalker_killed():
		return
	if TimeManager.current_day < STALKER_EMAIL_START_DAY:
		return
	if TimeManager.current_day - _last_stalker_email_day < STALKER_EMAIL_INTERVAL_DAYS:
		return
	var pool := _stalker_email_unlocked_pool()
	if _stalker_email_index >= pool.size():
		return
	var email: Dictionary = pool[_stalker_email_index]
	var quiet := _stalker_email_index < QUIET_STALKER_EMAIL_COUNT
	_stalker_email_index += 1
	_last_stalker_email_day = TimeManager.current_day
	## "{victim_name}" 자리표시자 - mid/late 단계 문구에서 실제 최근 피해자
	## 이름을 언급할 때 쓴다({player_name}과 같은 방식, 대사 쪽은
	## dialogue_screen.gd가 표시 시점에 치환하지만 이메일은 발송 시점에
	## 확정해서 보내는 게 자연스러워 여기서 바로 치환한다).
	var victim_name := String(NPCManager.get_definition(NPCManager.get_most_recent_death_npc_id()).get("name", ""))
	var title := NPCManager.apply_korean_particles(String(email.get("title", "")), "{victim_name}", victim_name)
	var lines := _substitute_victim_name((email.get("lines", []) as Array), victim_name)
	stalker_email_ready.emit(STALKER_SENDER_ID, title, lines, quiet)


## main.gd가 2차 살인 자루 발견 씬(_continue_second_murder_discovery)이 끝난
## 직후 호출한다.
func send_second_murder_sack_email() -> void:
	if _second_murder_sack_email_sent or MurderManager.is_stalker_killed():
		return
	var email: Dictionary = _stalker_emails.get("second_murder_sack", {})
	var lines: Array = email.get("lines", [])
	if lines.is_empty():
		return
	_second_murder_sack_email_sent = true
	## 2차 살인 이후라 이미 공포가 다 드러난 시점 - 항상 무서운 효과음.
	stalker_email_ready.emit(STALKER_SENDER_ID, String(email.get("title", "")), lines.duplicate(), false)


## "{victim_name}" 자리표시자를 lines 배열 안의 각 문자열에 치환한다 -
## _on_day_changed()의 사칭 메일 경로와 _maybe_send_stalker_email() 둘 다 쓴다.
## 이름에 받침이 없으면 이/은/을이 붙은 조사도 알맞게 가/는/를로 바뀐다
## (사용자 리포트, 2026-08-26 - NPCManager.apply_korean_particles() 참고).
func _substitute_victim_name(lines: Array, victim_name: String) -> Array:
	return lines.map(func(line: String) -> String: return NPCManager.apply_korean_particles(line, "{victim_name}", victim_name))


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Horror data file could not be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Horror data file is not valid JSON: %s" % path)
		return {}
	## 다국어(2026-09-14) - stalker_emails.en.json 같은 언어별 형제 파일을
	## 합친다(Localizer.merge_json 참고). npc_manager.gd의 동일 패턴과 이유 같음.
	return Localizer.apply_language(parsed, path) as Dictionary


## 언어 설정 화면에서 언어를 바꾸면 호출된다 - 매번 디스크에서 새로 읽는
## 구조라 재호출만으로 안전하게 다시 합쳐진다(npc_manager.gd의
## reload_for_language()와 동일 패턴).
func reload_for_language() -> void:
	_stalker_emails = _load_json(STALKER_EMAILS_PATH)
	_impersonation_emails = _load_json(IMPERSONATION_EMAILS_PATH)
