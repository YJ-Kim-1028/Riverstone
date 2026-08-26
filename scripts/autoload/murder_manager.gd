extends Node

## Owns the stalker murder queue/conditions (murder_system.md), the player's
## one-time poison murder ("플레이어 살인"), and all three endings ending.md
## ties to them (진실/체포/공범). Doesn't touch presentation (portraits, UI,
## actual email delivery) - other systems watch its signals for that.

signal murder_occurred(victim_id: String, murder_number: int)
signal player_murder_committed(victim_id: String)
signal truth_ending_triggered
signal arrest_ending_triggered(spared_npc_id: String)
signal accomplice_ending_triggered(victim_id: String)
signal alibi_reminder_ready(npc_id: String, title: String, lines: Array)

const MURDER_HOUR := 22
## 알리바이 조사 기준 시각(사용자 지시, 2026-08-17) - 22시(살인 시각)는 다들
## 이미 자기 자리로 돌아가 있어 서로 겹칠 일이 거의 없다. "시신이 물속에
## 있어 부패가 빨리 진행됐지만 실제 사망 추정 시각은 4시간 정도 전"이라는
## 설정으로, 더 이른 시각(18시)을 알리바이 조사 기준으로 삼는다 - 이 시간대가
## NPC들이 아직 밖에 나와 있어 알리바이/목격 진술 둘 다 훨씬 유의미해진다.
const ALIBI_CHECK_HOUR := 18
const MAX_STALKER_MURDERS := 2
## 사용자 지시(2026-08-23): 두 번째 살인이 첫 번째 직후 며칠 만에 터지면
## 스토커 이메일(3일 간격 순차 발송)이 다 나오기도 전에 다음 사건이 덮친다 -
## 직전 살인일로부터 최소 이만큼은 지나야 다음 살인 조건 판정을 시작한다.
const MIN_DAYS_BETWEEN_MURDERS := 14

## ending.md 체포 엔딩: 2명을 죽인 뒤 "세 번째 살해 대상이 확정된" 상태여야
## 하므로, 대기열에는 최대 3명(실제 희생자 2 + 체포 엔딩용 3번째)까지만 받는다.
const MAX_CANDIDATES := 3

## murder_system.md의 "피해자의 집" - NPC별 개인 주거 맵이 실제로는 존재하지
## 않아서(04_locations에 상점/공용 공간만 있음), 발견 장소는 이 문자열로만
## 남긴다. 실제 "피해자 집으로 이동 처리"는 시각적으로 할 맵이 없어 생략했다.
const DISCOVERY_LOCATION := "피해자의 집"

## 엔딩 컷신용 내레이션(초상화 없는 나레이터 대사) 저장소. NPC 초상화가 있는
## 대사(어셔의 증언/동거 대사 등)는 각 npc.json의 story_dialogue에 있고, 여기
## endings.json은 그 사이사이를 잇는 화자 없는 문장만 담는다.
const ENDINGS_DATA_PATH := "res://data/horror/endings.json"

const LOCATION_NAMES := {
	"hospital": "병원", "pasture": "목장", "farm": "농가게", "cafe": "카페",
	"shrine": "신사", "temple": "절", "book": "서점", "general": "잡화점",
	"furniture": "가구점", "fish": "낚시가게", "police": "경찰서",
	"plaza1": "광장", "plaza2": "광장", "plaza3": "광장", "plaza4": "광장", "plaza5": "광장",
	"restaurant": "레스토랑", "home": "집",
}

## 목격 진술용(사용자 지시, 2026-08-17) - LOCATION_NAMES는 state 문자열 접두어
## 기준이라 목격 증언에서 쓰는 실제 map_id(NPCManager._spawn_index 기준, 예:
## "general_interior")와 키 형태가 다르다. WorldMap.MAP_PATHS의 맵 id 그대로
## 키를 맞췄다.
const MAP_ID_NAMES := {
	"Home": "집", "home_interior": "집",
	"plaza1": "광장", "plaza2": "광장", "plaza3": "광장", "plaza4": "광장", "plaza5": "광장",
	"basement_interior": "지하실", "book_interior": "서점", "cafe_interior": "카페",
	"cowshed_interior": "축사", "farm_interior": "농가게", "fish_interior": "낚시가게",
	"furniture_interior": "가구점", "general_interior": "잡화점",
	"hospital_interior": "병원", "pasture_interior": "목장", "police_interior": "경찰서",
	"restaurant_interior": "레스토랑", "shrine_interior": "신사", "temple_interior": "절",
}

var _candidate_queue: Array[String] = []
var _resolved_candidates: Dictionary = {}
var _cases: Array = []
var _murder_count := 0
## 두 번째 살인은 plaza3로 뛰어가는 1차 발견 씬 대신, 시체가 플레이어 집
## (Home.tmx) 앞에 놓이고 플레이어가 나중에 직접 발견하는 씬으로 간다(사용자
## 지시, 2026-08-23 - "더 대담해진 범행"). main.gd가 플레이어가 Home에
## 들어올 때마다 이 플래그를 확인해서 씬을 재생한다 - 세이브 사이에도 안
## 잊어버리게 여기서 관리한다.
var _second_murder_home_pending := false

## 2026-08-16 사용자 확정: 살인 발생 후 5일 이내에 처음 만나는 생존 NPC는
## 대화 첫 줄로 그날 밤 알리바이를 무조건 진술한다(한 번 말하면 다시 안 함).
## npc_id -> true인 동안 "아직 안 물어봤음". 새 살인이 또 나면 그 전 살인
## 몫으로 아직 안 받은 진술은 버리고 최신 사건 기준으로 다시 채운다(둘 다
## 들고 있게 하지 않음 - 최대 2번 살인이라 실무상 드문 경우).
const ALIBI_WINDOW_DAYS := 5
var _alibi_pending: Dictionary = {}
var _alibi_deadline_day := -1
## npc_id -> consume_alibi_line()이 실제로 대사를 내준 날짜 - 마주침/대화 종료
## 이모지가 "오늘 이 NPC가 그 대사를 했는지" 판정할 때 쓴다(has_pending_alibi_line()과
## 함께 main.gd/dialogue_screen.gd 참고). 세이브에 안 남아도 된다 - 하루 안에서만
## 의미 있는 상태.
var _alibi_shown_day: Dictionary = {}
var _alibi_start_day := -1

## 2차 살인 이후 용의자 지목 소문(story_dialogue.suspicion_talk_2) 전용 대기열 -
## 알리바이 대화와 같은 날 한꺼번에 나오면 어색하다는 지적(사용자 지시,
## 2026-08-26)으로 완전히 분리했다. _alibi_pending과 달리 알리바이 대화가
## "끝난 뒤" 다음 재회부터 걸리고, 만료일(ALIBI_WINDOW_DAYS) 제한이 없다 -
## npc_id -> true(아직 안 보여줌). npc_manager.gd의 get_daily_dialogue() 참고.
var _suspicion_talk_2_pending: Dictionary = {}

## 2차 살인 이후 한정(사용자 지시, 2026-08-24): 알리바이 대화를 아직 못 나눈
## NPC를 놓치기 쉽다는 지적 - 살인 발생일로부터 이 일수가 지나도록 못
## 만났으면 그 NPC 앞으로 메일 1통을 보내 찾아오라고 재촉한다. npc_id -> true
## (한 번 보내면 다시 안 보냄). 대상은 emails.alibi_reminder 필드를 가진
## NPC로만 한정(벨제/모카/셰퍼드/어셔).
const ALIBI_REMINDER_DELAY_DAYS := 3
var _alibi_reminder_sent: Dictionary = {}

## ending.md: "엔딩은 중복 달성이 불가능하다" - "" | "truth" | "arrest" | "accomplice".
var _ending_achieved := ""

## 독약이 서빙된 그날은 바로 안 죽고, 다음날 하루가 바뀌는 순간 실제로 죽고
## 엔딩 컷신이 시작된다(사용자 지시, 2026-08-24 - "독약을 서빙하고 다음날이
## 되면 npc가 죽고, 다음날이 되자마자 이벤트가 시작"). npc_id가 비어있으면
## 대기 중인 게 없다는 뜻.
var _pending_poison_victim := ""
var _endings_data: Dictionary = {}

## 공범 엔딩 컷신(메일 대기~어셔 이사)이 끝까지 재생됐는지(사용자 지시,
## 2026-08-24 - "컷씬하다가 게임 꺼버리면?"). 맵 이동 시점에 자동저장이 걸려서
## 컷신 도중 종료하면 진행 상태 자체는 안 남는데, 이 플래그로 "엔딩은
## 확정됐는데 마무리를 못 봤다"는 걸 구분해서 main.gd가 다음 접속 때 이어서
## 보여줄 수 있게 한다.
var _accomplice_sequence_completed := false
## 공범 엔딩과 동일한 이유(main.gd의 _maybe_resume_arrest_ending() 참고) -
## 체포 엔딩 컷신 도중 게임을 껐다 켜면 이어서(처음부터) 다시 보여줘야
## 하므로, "끝까지 다 봤는지"를 따로 기록해둔다.
var _arrest_sequence_completed := false
## main.gd._maybe_resume_arrest_ending()이 컷신을 다시 재생할 때 어떤 NPC가
## 살아남는 3번째 대상이었는지 알아야 한다 - _trigger_arrest_ending()이 채운다.
var _spared_npc_id := ""

var _player_used_poison := false
var _player_killed_npc_id := ""
var _arrested := false
var _accomplice_ending := false
var _stalker_killed := false
var _living_with_stalker := false
var _usher_death_method := ""


func _ready() -> void:
	NPCManager.murder_candidate_registered.connect(_on_candidate_registered)
	RestaurantManager.npc_poisoned.connect(_on_npc_poisoned)
	TimeManager.minute_passed.connect(_on_minute_passed)
	TimeManager.day_changed.connect(_on_day_changed)
	_endings_data = _load_json(ENDINGS_DATA_PATH)
	_update_pending_state()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Ending data file could not be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Ending data file is not valid JSON: %s" % path)
		return {}
	return parsed


## 엔딩 컷신에서 화자 없는 내레이션 한 토막을 가져온다(예: "accomplice",
## "arrest_narration"). 없으면 빈 배열 - 호출부가 조용히 그 구간을 건너뛴다.
func get_ending_narration(ending_id: String, section: String) -> Array:
	return (_endings_data.get(ending_id, {}) as Dictionary).get(section, []) as Array


## get_ending_narration()과 같은 데이터지만, 메일처럼 title+lines가 같이
## 필요한 구간용({"title": ..., "lines": [...]}).
func get_ending_mail(ending_id: String, section: String) -> Dictionary:
	return (_endings_data.get(ending_id, {}) as Dictionary).get(section, {}) as Dictionary


func get_murder_count() -> int:
	return _murder_count


func get_achieved_ending() -> String:
	return _ending_achieved


func has_ending_achieved() -> bool:
	return not _ending_achieved.is_empty()


func is_stalker_killed() -> bool:
	return _stalker_killed


## save.md "경찰 체포 여부" - 체포 엔딩(스토커 체포/자결)과 공범 엔딩의 "플레이어
## 일시 체포" 둘 다 여기 해당하므로, 둘 중 하나라도 일어나면 true.
func is_arrested() -> bool:
	return _arrested


func is_accomplice_ending() -> bool:
	return _accomplice_ending


func is_living_with_stalker() -> bool:
	return _living_with_stalker


func is_accomplice_sequence_completed() -> bool:
	return _accomplice_sequence_completed


## main.gd가 공범 엔딩 컷신(마무리 나레이션까지)을 실제로 끝까지 재생했을 때만
## 부른다.
func mark_accomplice_sequence_completed() -> void:
	_accomplice_sequence_completed = true


func is_arrest_sequence_completed() -> bool:
	return _arrest_sequence_completed


func get_spared_npc_id() -> String:
	return _spared_npc_id


## main.gd가 체포 엔딩 컷신(마무리 페이드인까지)을 실제로 끝까지 재생했을
## 때만 부른다.
func mark_arrest_sequence_completed() -> void:
	_arrest_sequence_completed = true


func has_player_used_poison() -> bool:
	return _player_used_poison


func get_player_killed_npc_id() -> String:
	return _player_killed_npc_id


func get_usher_death_method() -> String:
	return _usher_death_method


## murder_system.md: "조건 미충족 시 다음 날 동일 조건 재검사" - 대상이 있는 한
## WeatherManager가 3일 이내 비를 강제하도록 계속 신호를 보낸다.
func has_pending_victim() -> bool:
	return _get_next_queued_candidate() != "" and not _is_murder_cooldown_active()


## MIN_DAYS_BETWEEN_MURDERS 참고. 아직 아무도 안 죽었으면 쿨다운 자체가 없다.
func _is_murder_cooldown_active() -> bool:
	if _cases.is_empty():
		return false
	var last_murder_day := int(_cases[_cases.size() - 1].get("day", -1))
	return TimeManager.current_day < last_murder_day + MIN_DAYS_BETWEEN_MURDERS


func get_case_count() -> int:
	return _cases.size()


## 사칭 이메일 등 "이 NPC가 몇 번째로 죽었는지"가 필요한 곳에서 쓴다 -
## _cases에 기록된 순서(스토커 살인 + 플레이어 독살 전부 포함) 기준
## 1부터 시작, 못 찾으면 0(horror_event_manager.gd 참고).
func get_case_number_for_victim(npc_id: String) -> int:
	for i in _cases.size():
		if String(_cases[i].get("victim_id", "")) == npc_id:
			return i + 1
	return 0


func get_case_info(case_number: int) -> Dictionary:
	if case_number < 1 or case_number > _cases.size():
		return {}
	var case_data: Dictionary = _cases[case_number - 1]
	return {
		"victim_id": case_data.get("victim_id", ""),
		"day": case_data.get("day", -1),
		"weekday": case_data.get("weekday", ""),
		"discovery_location": DISCOVERY_LOCATION,
	}


## murder_system.md "경찰 조사": NPC 알리바이는 스케줄 데이터를 기반으로 자동
## 생성된다. 살인 시각(22시)이 아니라 ALIBI_CHECK_HOUR(18시) 기준 각 생존
## NPC의 스케줄 상태를 저장해뒀다가, 장소 접두어만 한글 지명으로 바꿔서
## 문장으로 돌려준다.
func describe_alibi(npc_id: String, case_number: int) -> String:
	if case_number < 1 or case_number > _cases.size():
		return ""
	var alibis: Dictionary = _cases[case_number - 1].get("alibis", {})
	if not alibis.has(npc_id):
		return "그날 밤 어디에 있었는지 알려진 바가 없다."
	return "오후 6시에는 %s에 있었다고 말한다." % _describe_location(String(alibis[npc_id]))


## consume_alibi_line()과 같은 유효성 조건을 소비 없이 확인만 한다 - 마주침
## 이모지(main.gd._handle_npc_encounter())가 "오늘 이 NPC가 애도/알리바이
## 대사를 할 차례인지" 미리 알아야 웃는 얼굴 대신 눈물을 띄울 수 있다(사용자
## 지시, 2026-08-26 - "살인 관련 스토리 대사를 말하는 날에는 이모지가 눈물로").
func has_pending_alibi_line(npc_id: String) -> bool:
	return _alibi_pending.get(npc_id, false) and TimeManager.current_day <= _alibi_deadline_day and not _cases.is_empty()


## has_pending_alibi_line()이 "아직 소비 전"만 잡아내는 것과 달리, 이미 대화가
## 끝나 소비된 뒤(dialogue_screen.gd의 close())에도 "오늘 그 대사를 했었다"는
## 걸 알아야 웃음/수줍음으로 안 바뀐다(사용자 지시, 2026-08-26 - "그런 대사를
## 하는 날엔 샤이도 안뜨는게 맞아").
func was_alibi_shown_today(npc_id: String) -> bool:
	return int(_alibi_shown_day.get(npc_id, -1)) == TimeManager.current_day


## murder_system.md 경찰 조사 - 살인 후 ALIBI_WINDOW_DAYS 이내 이 NPC와 처음
## 나누는 대화의 첫 줄로 쓸 1인칭 알리바이 진술. describe_alibi()의 3인칭
## 나레이션("~라고 말한다")과 달리 NPC 본인이 직접 하는 말투로 새로 포맷한다.
## 한 번 불러가면(대화가 실제로 열렸다는 뜻) 다시는 안 나온다 - 기간이 지나도
## 마찬가지로 지워서 나중에 뜬금없이 나오지 않게 한다.
## npc.json에 "alibi_speech": {"known": "...%s...", "unknown": "..."}가 있으면
## 그 NPC 고유 말투로 대체한다 - 기본 반말 문장이 마르(존댓말)/로시·폴리
## (하게체)처럼 독특한 말투를 쓰는 NPC랑 안 맞는다는 리포트(2026-08-26).
## 정보 내용은 그대로 두고 어미만 그 NPC의 기존 말투에 맞춘 것 - 없으면
## 기존 기본 문장 그대로.
func consume_alibi_line(npc_id: String) -> String:
	if not _alibi_pending.get(npc_id, false):
		return ""
	_alibi_pending.erase(npc_id)
	if TimeManager.current_day > _alibi_deadline_day or _cases.is_empty():
		return ""
	var speech_style: Dictionary = NPCManager.get_definition(npc_id).get("alibi_speech", {})
	var result := ""
	if npc_id == NPCManager.get_stalker_id():
		var lie := _stalker_alibi_lie()
		if not lie.is_empty():
			result = _format_alibi_known_line(speech_style, lie)
	if result.is_empty():
		var alibis: Dictionary = _cases[_cases.size() - 1].get("alibis", {})
		result = (String(speech_style.get("unknown", "그날 밤 어디 있었는지는... 나도 잘 기억이 안 나.")) if not alibis.has(npc_id)
			else _format_alibi_known_line(speech_style, _describe_location(String(alibis[npc_id]))))
	# dialogue_screen.gd의 close()가 "오늘 이 대화에서 방금 애도/알리바이
	# 대사를 했는지"를 알아야 웃음/수줍음 대신 눈물을 유지할 수 있다(사용자
	# 지시, 2026-08-26) - has_pending_alibi_line()은 이미 소비돼서 이 시점엔
	# false라 별도로 "오늘 소비함"만 따로 기록한다.
	_alibi_shown_day[npc_id] = TimeManager.current_day
	return result


func _format_alibi_known_line(speech_style: Dictionary, location: String) -> String:
	var template := String(speech_style.get("known", "난 그 날 오후 6시엔 %s에 있었어."))
	return template % location


## 스토커(어셔)의 거짓 알리바이(사용자 지시, 2026-08-17) - 실제 스케줄과 무관하게
## usher.json의 murder_alibi_lie.location_label을 그대로 주장하게 한다.
## consume_witness_line()은 이 거짓말과 별개로 다른 NPC들의 진짜 스케줄
## 데이터를 그대로 쓰므로, 그날 실제로 어셔와 마주친 NPC가 있으면 그 NPC의
## 목격 진술이 자동으로 이 거짓말과 모순된다 - 대조 로직을 따로 만들 필요
## 없이 "잡히는" 구조. 기획자가 아직 안 채웠으면(TODO로 시작) 빈 문자열을
## 돌려줘서 평소처럼 실제 스케줄 기반 알리바이로 폴백한다.
func _stalker_alibi_lie() -> String:
	var stalker_id := NPCManager.get_stalker_id()
	if stalker_id.is_empty():
		return ""
	var label := String(NPCManager.get_definition(stalker_id).get("murder_alibi_lie", {}).get("location_label", ""))
	if label.begins_with("TODO"):
		return ""
	return label


## _stalker_alibi_lie()가 실제로 쓰였을 때(거짓 알리바이가 나온 바로 그 순간)
## 이어지는 두 번째 거짓말 - usher.json의 murder_alibi_lie.corroboration_line.
## 실존하지 않는 뒷받침 근거(예: "세이지가 나한테 그랬어")를 대서 거짓말에
## 무게를 싣는 용도. 세이지 쪽엔 대응하는 대사를 절대 넣지 않는다 - 플레이어가
## 나중에 세이지와 대화하며 그런 말을 한 적이 없다는 걸 스스로 알아채는 게
## 핵심이라, 코드로 대조하지 않는다. npc_id가 스토커가 아니면 항상 "". 1차
## 살인 때만 나온다(사용자 지시, 2026-08-26 - "어셔는 2차 살인때도 세이지
## 안좋은 기운 어쩌고 하는데 이거 2차때는 말고 1차때만 들려줘도 될 거
## 같아") - 매 살인마다 똑같은 뒷받침 근거를 반복하면 어색하다.
func consume_stalker_corroboration_line(npc_id: String) -> String:
	if npc_id != NPCManager.get_stalker_id() or _murder_count != 1:
		return ""
	var line := String(NPCManager.get_definition(npc_id).get("murder_alibi_lie", {}).get("corroboration_line", ""))
	if line.begins_with("TODO"):
		return ""
	return line


## consume_alibi_line()과 같은 첫 재회 순간에 이어서 나오는 목격 진술(사용자
## 지시, 2026-08-17) - "그날 오후 10시" 알리바이와 달리 하루 전체 기준. 후보가
## 0명이면 아무도 못 봤다고 하고, 1명 이상이면 그중 무작위로 한 명만 골라
## 이름을 댄다(2명 이상이어도 "여러 명 중 하나"로 굳이 얼버무리지 않음 -
## 사용자 지시, 2026-08-17). consume() 시점(대화가 실제로 열렸을 때) 한 번만
## 뽑고 다시 안 나오므로 재대화마다 바뀌지 않는다. _alibi_pending으로 따로
## 게이팅하지 않는다 - 호출부가 consume_alibi_line()이 빈 문자열이 아닐 때만
## 이어서 부르는 걸 전제로 한다.
## consume_alibi_line()과 같은 alibi_speech(마르/로시/폴리처럼 독특한 말투를
## 쓰는 NPC용) 오버라이드를 여기도 재사용한다(사용자 리포트, 2026-08-26 -
## "마르 알리바이 말할 때, 광장에서 누구 봤다고 할 때 갑자기 반말 써" -
## 알리바이 본문은 존댓말로 고쳤는데 목격 진술 쪽은 별도 하드코딩 문장이라
## 놓쳤었다).
func consume_witness_line(npc_id: String) -> String:
	if _cases.is_empty():
		return ""
	var witnesses: Dictionary = _cases[_cases.size() - 1].get("witnesses", {})
	if not witnesses.has(npc_id):
		return ""
	var speech_style: Dictionary = NPCManager.get_definition(npc_id).get("alibi_speech", {})
	var candidates: Array = witnesses[npc_id]
	if candidates.is_empty():
		return String(speech_style.get("witness_none", "아, 근데 그날은 딱히 아무도 못 봤던 것 같아."))
	var picked: Dictionary = candidates.pick_random()
	var seen_name := String(NPCManager.get_definition(String(picked.get("npc_id", ""))).get("name", ""))
	var seen_place := _describe_map(String(picked.get("map_id", "")))
	var template := String(speech_style.get("witness_seen", "아, 그러고 보니 그날 %s에서 %s를 본 것 같기도 해."))
	return template % [seen_place, seen_name]


## consume_witness_line()용 - LOCATION_NAMES(state 접두어 기준)와 달리
## map_id를 그대로 키로 쓴다.
func _describe_map(map_id: String) -> String:
	return String(MAP_ID_NAMES.get(map_id, "어딘가"))


## 새 살인이 날 때마다 대기열을 새로 채운다 - 이전 사건 몫으로 아직 못 받은
## 진술이 있어도 최신 사건 기준으로 덮어쓴다(둘 다 들고 있게 하지 않음).
## 폴리는 1차 살인에 한해서만 포함한다(사용자 지시, 2026-08-26 - "경찰인데
## 왜?") - "그날 밤 기억이 없다" 특수 고백(first_murder_occurred)이 이
## 알리바이 슬롯을 그대로 재사용해서 뜨는 구조라 1차엔 필요하지만, 2차부터는
## 경찰인 그가 플레이어에게 자기 알리바이를 댈 이유가 없다.
func _refresh_alibi_pending(victim_id: String) -> void:
	_alibi_pending.clear()
	_alibi_reminder_sent.clear()
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		if npc_id == NPCManager.POLI_NPC_ID and _murder_count > 1:
			continue
		_alibi_pending[npc_id] = true
		# 2차 살인 이후에만 - 용의자 지목 소문은 알리바이 대화가 다 끝난 다음
		# 재회 때 별도로 뜬다(위 _suspicion_talk_2_pending 선언부 참고).
		if _murder_count == 2:
			_suspicion_talk_2_pending[npc_id] = true
	_alibi_start_day = TimeManager.current_day
	_alibi_deadline_day = TimeManager.current_day + ALIBI_WINDOW_DAYS


func has_pending_suspicion_talk(npc_id: String) -> bool:
	return bool(_suspicion_talk_2_pending.get(npc_id, false))


func consume_suspicion_talk(npc_id: String) -> void:
	_suspicion_talk_2_pending.erase(npc_id)


func get_save_data() -> Dictionary:
	return {
		"candidate_queue": _candidate_queue,
		"resolved_candidates": _resolved_candidates.duplicate(),
		"ending_achieved": _ending_achieved,
		"murder_count": _murder_count,
		"cases": _cases.duplicate(true),
		"player_used_poison": _player_used_poison,
		"player_killed_npc_id": _player_killed_npc_id,
		"arrested": _arrested,
		"accomplice_ending": _accomplice_ending,
		"stalker_killed": _stalker_killed,
		"living_with_stalker": _living_with_stalker,
		"usher_death_method": _usher_death_method,
		"alibi_pending": _alibi_pending.duplicate(),
		"alibi_deadline_day": _alibi_deadline_day,
		"alibi_start_day": _alibi_start_day,
		"alibi_reminder_sent": _alibi_reminder_sent.duplicate(),
		"second_murder_home_pending": _second_murder_home_pending,
		"pending_poison_victim": _pending_poison_victim,
		"accomplice_sequence_completed": _accomplice_sequence_completed,
		"arrest_sequence_completed": _arrest_sequence_completed,
		"spared_npc_id": _spared_npc_id,
		"suspicion_talk_2_pending": _suspicion_talk_2_pending.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	_candidate_queue.clear()
	for npc_id in (data.get("candidate_queue", []) as Array):
		_candidate_queue.append(String(npc_id))
	_resolved_candidates = (data.get("resolved_candidates", {}) as Dictionary).duplicate()
	_ending_achieved = String(data.get("ending_achieved", ""))
	_murder_count = int(data.get("murder_count", 0))
	_cases = (data.get("cases", []) as Array).duplicate(true)
	_player_used_poison = bool(data.get("player_used_poison", false))
	_player_killed_npc_id = String(data.get("player_killed_npc_id", ""))
	_alibi_pending = (data.get("alibi_pending", {}) as Dictionary).duplicate()
	_alibi_deadline_day = int(data.get("alibi_deadline_day", -1))
	_alibi_start_day = int(data.get("alibi_start_day", -1))
	_alibi_reminder_sent = (data.get("alibi_reminder_sent", {}) as Dictionary).duplicate()
	_suspicion_talk_2_pending = (data.get("suspicion_talk_2_pending", {}) as Dictionary).duplicate()
	_arrested = bool(data.get("arrested", false))
	_accomplice_ending = bool(data.get("accomplice_ending", false))
	_stalker_killed = bool(data.get("stalker_killed", false))
	_living_with_stalker = bool(data.get("living_with_stalker", false))
	_usher_death_method = String(data.get("usher_death_method", ""))
	_accomplice_sequence_completed = bool(data.get("accomplice_sequence_completed", false))
	_arrest_sequence_completed = bool(data.get("arrest_sequence_completed", false))
	_spared_npc_id = String(data.get("spared_npc_id", ""))
	_second_murder_home_pending = bool(data.get("second_murder_home_pending", false))
	_pending_poison_victim = String(data.get("pending_poison_victim", ""))
	_update_pending_state()


func _on_candidate_registered(npc_id: String) -> void:
	if _candidate_queue.size() >= MAX_CANDIDATES:
		return
	_candidate_queue.append(npc_id)
	_update_pending_state()


## murder_system.md "플레이어 살인": 독약으로 단 한 번만 살해 가능. 대상이
## 스토커 본인이면 ending.md의 진실 엔딩, 무고한 NPC면 공범 엔딩으로 갈린다.
## 서빙 즉시 죽이지 않는다 - _pending_poison_victim에 표시만 해두고, 다음날
## _on_day_changed()에서 실제로 죽이면서 엔딩 컷신을 시작한다.
func _on_npc_poisoned(npc_id: String) -> void:
	if _player_used_poison or has_ending_achieved() or not _pending_poison_victim.is_empty():
		return
	# CLAUDE.md/npc.md: 폴리/세이지/라마(can_die:false)는 살해 대상이 될 수
	# 없다 - 스토커의 살인 후보에서는 is_murder_candidate()가 이미 걸러주지만,
	# 플레이어의 독살은 아무 필터가 없어서 이 셋에게도 서빙하면 그대로
	# 죽어버리는 구멍이 있었다(사용자 리포트, 2026-08-26 - "스토리 npc한테
	# 독약 타서 주면 어떻게 돼?"). _player_used_poison을 여기서 소모하지
	# 않아야 무효 시도로 "1회뿐인 독살 기회"를 날리지 않는다.
	if not NPCManager.can_die(npc_id):
		return
	_player_used_poison = true
	_pending_poison_victim = npc_id


func _finalize_player_poison(npc_id: String) -> void:
	_player_killed_npc_id = npc_id
	_resolved_candidates[npc_id] = true
	_record_case(npc_id)
	NPCManager.kill_npc(npc_id)
	if npc_id == NPCManager.get_stalker_id():
		_stalker_killed = true
		_usher_death_method = "player_killed"
		_ending_achieved = "truth"
		truth_ending_triggered.emit()
	else:
		_arrested = true
		_accomplice_ending = true
		_living_with_stalker = true
		_ending_achieved = "accomplice"
		accomplice_ending_triggered.emit(npc_id)
	player_murder_committed.emit(npc_id)


func _on_minute_passed(hour: int, minute: int) -> void:
	if hour != MURDER_HOUR or minute != 0 or has_ending_achieved() or _stalker_killed:
		return
	if _is_murder_cooldown_active():
		return
	var candidate_id := _get_next_queued_candidate()
	if candidate_id.is_empty() or not WeatherManager.is_raining():
		return
	if not _positions_allow_murder(candidate_id):
		return
	if _murder_count >= MAX_STALKER_MURDERS:
		_trigger_arrest_ending(candidate_id)
	else:
		_commit_murder(candidate_id)


## 2차 살인 이후에만(사용자 지시, 2026-08-24 - "2번째 살인 이후로는") 동작한다.
## 알리바이 창(ALIBI_WINDOW_DAYS)이 열려 있는 동안, 아직 대화를 못 나눈 NPC가
## ALIBI_REMINDER_DELAY_DAYS일 넘게 방치되면 그 NPC 앞으로 메일을 한 번
## 보낸다. 알리바이를 이미 나눴으면(_alibi_pending에서 빠짐) 대상에서
## 자동으로 제외된다. 대상은 emails.alibi_reminder 필드를 가진 NPC로만
## 한정한다(사용자 지시, 2026-08-24) - 마르를 실제로 몰아가는 벨제/모카/
## 셰퍼드/어셔 4명만 해당, 방어하거나 무관한 NPC는 굳이 재촉할 이유가 없다는
## 판단. 몰아가는 대상(마르)이 이미 죽었으면 story_dialogue.suspicion_talk_2의
## requires_alive를 그대로 재사용해 조용히 건너뛴다.
func _on_day_changed(day: int, _weekday: String) -> void:
	if not _pending_poison_victim.is_empty():
		var victim_id := _pending_poison_victim
		_pending_poison_victim = ""
		_finalize_player_poison(victim_id)
	if _murder_count != 2 or day > _alibi_deadline_day:
		return
	if day - _alibi_start_day < ALIBI_REMINDER_DELAY_DAYS:
		return
	for npc_id in _alibi_pending.keys():
		if not bool(_alibi_pending[npc_id]) or bool(_alibi_reminder_sent.get(npc_id, false)):
			continue
		var definition: Dictionary = NPCManager.get_definition(npc_id)
		var reminder: Dictionary = definition.get("emails", {}).get("alibi_reminder", {})
		var lines: Array = reminder.get("lines", [])
		if lines.is_empty():
			continue
		var requires_alive: String = String(definition.get("story_dialogue", {}).get("suspicion_talk_2", {}).get("requires_alive", ""))
		if not requires_alive.is_empty() and not NPCManager.is_alive(requires_alive):
			continue
		_alibi_reminder_sent[npc_id] = true
		alibi_reminder_ready.emit(npc_id, String(reminder.get("title", "")), lines)


## 예전엔 대기열 순서 그대로(FIFO) 뽑아서, NPCManager.get_all_ids()가 파일을
## 알파벳순으로 읽어오는 탓에 디버그로 한꺼번에 호감도를 올리면 항상 "벨제 →
## 플로라" 순으로 죽었다(사용자 리포트, 2026-08-26 - "항상 처음은 벨제 그
## 다음은 플로라야?"). 아직 안 죽은 후보 중 무작위로 하나를 고른다.
func _get_next_queued_candidate() -> String:
	if _stalker_killed:
		return ""
	var unresolved: Array = _candidate_queue.filter(func(candidate_id): return not bool(_resolved_candidates.get(candidate_id, false)))
	if unresolved.is_empty():
		return ""
	return String(unresolved.pick_random())


## murder_system.md 예시가 실제로 보여준 건 "플레이어가 스토커/피해자 둘 중
## 하나와 같은 맵에 있으면 안 된다"는 것뿐이다(사용자 정정, 2026-08-23 -
## 스토커와 피해자는 같은 맵이어도 무방하다, 오히려 자연스럽다. 문제는
## 플레이어 눈앞에서 목격 가능한 상황이 되는 것뿐). 살인 자체는 murder_system.md
## "살해" 절에 따라 항상 피해자의 집에서 일어나는 것으로 처리되므로, 여기서
## 보는 위치는 스케줄상 22시 시점 위치일 뿐 실제 범행 장소와는 무관하다.
func _positions_allow_murder(victim_id: String) -> bool:
	var stalker_id := NPCManager.get_stalker_id()
	var stalker_position := NPCManager.get_npc_world_position(stalker_id)
	var victim_position := NPCManager.get_npc_world_position(victim_id)
	if stalker_position.is_empty() or victim_position.is_empty():
		return false
	var player_map := GameManager.current_map_id
	var stalker_map := String(stalker_position.get("map_id", ""))
	var victim_map := String(victim_position.get("map_id", ""))
	return player_map != stalker_map and player_map != victim_map


func _commit_murder(victim_id: String) -> void:
	_resolved_candidates[victim_id] = true
	_record_case(victim_id)
	NPCManager.kill_npc(victim_id)
	_murder_count += 1
	if _murder_count == 2:
		_second_murder_home_pending = true
	_refresh_alibi_pending(victim_id)
	_update_pending_state()
	murder_occurred.emit(victim_id, _murder_count)


## 디버그 전용(game_manager.gd) - 매번 스토리를 자연 진행 조건(비/22시/위치)까지
## 끌고 가기 너무 힘들다는 지적(사용자 지시, 2026-08-26) - 즉시 스토커 살인을
## 하나 커밋한다. 정식 _commit_murder()를 그대로 타므로 알리바이/사건 기록/
## 그리프 대사 등 다운스트림 시스템이 실제 살인과 동일하게 반응한다(F7의
## "생 죽이기"와 달리 이쪽은 진짜 살인 흐름). 두 번 누르면 1차/2차 순서대로.
## npc_id 생략 시 스토리/스토커 제외 살아있는 NPC 중 자동으로 하나 고른다.
func debug_force_commit_murder(npc_id: String = "") -> void:
	if has_ending_achieved() or _stalker_killed or _murder_count >= MAX_STALKER_MURDERS:
		return
	var target_id := npc_id
	if target_id.is_empty():
		for candidate_id in NPCManager.get_all_ids():
			if NPCManager.is_alive(candidate_id) and not NPCManager.is_story_npc(candidate_id) and not NPCManager.is_stalker(candidate_id) and not bool(_resolved_candidates.get(candidate_id, false)):
				target_id = candidate_id
				break
	if target_id.is_empty():
		return
	if not _candidate_queue.has(target_id):
		_candidate_queue.append(target_id)
	_commit_murder(target_id)


## 디버그 전용 - 진실 엔딩(플레이어가 스토커를 독살) 즉시 발동.
func debug_force_truth_ending() -> void:
	if has_ending_achieved():
		return
	_finalize_player_poison(NPCManager.get_stalker_id())


## 디버그 전용 - 공범 엔딩(플레이어가 무고한 NPC를 독살) 즉시 발동. npc_id
## 생략 시 스토리/스토커 제외 살아있는 NPC 중 하나를 자동으로 고른다.
func debug_force_accomplice_ending(npc_id: String = "") -> void:
	if has_ending_achieved():
		return
	var target_id := npc_id
	if target_id.is_empty():
		for candidate_id in NPCManager.get_all_ids():
			if NPCManager.is_alive(candidate_id) and not NPCManager.is_story_npc(candidate_id) and not NPCManager.is_stalker(candidate_id):
				target_id = candidate_id
				break
	if target_id.is_empty():
		return
	_finalize_player_poison(target_id)


## 디버그 전용 - 체포 엔딩(3번째 살해 시도 중 경찰이 스토커를 사살, 대상은
## 생존) 즉시 발동. spared_npc_id 생략 시 살아있는 NPC 중 하나를 자동으로
## 고른다.
func debug_force_arrest_ending(spared_npc_id: String = "") -> void:
	if has_ending_achieved():
		return
	var target_id := spared_npc_id
	if target_id.is_empty():
		for candidate_id in NPCManager.get_all_ids():
			if NPCManager.is_alive(candidate_id) and not NPCManager.is_story_npc(candidate_id) and not NPCManager.is_stalker(candidate_id):
				target_id = candidate_id
				break
	if target_id.is_empty():
		return
	_trigger_arrest_ending(target_id)


func is_second_murder_discovery_pending() -> bool:
	return _second_murder_home_pending


func consume_second_murder_discovery_pending() -> void:
	_second_murder_home_pending = false


## ending.md 체포 엔딩: "실제 살인은 발생하지 않는다. 살인 조건 충족 시점에
## 경찰 체포 이벤트가 대신 발동된다. 세 번째 살해 대상 NPC는 생존한다." +
## "어셔의 사망으로 인해 이메일이 중단된다" (poli.json: 범인이 그 자리에서
## 스스로 목숨을 끊는다) - 그래서 대상은 살고, 스토커가 대신 죽는다.
func _trigger_arrest_ending(spared_npc_id: String) -> void:
	_resolved_candidates[spared_npc_id] = true
	_spared_npc_id = spared_npc_id
	_arrested = true
	_stalker_killed = true
	## 사용자 확정(2026-08-24): 어셔가 스스로 목숨을 끊는 게 아니라, 살아남은
	## 3번째 대상을 칼로 위협하는 순간 폴리가 정당방위로 쏜다.
	_usher_death_method = "shot_by_poli"
	_ending_achieved = "arrest"
	## 실제로 NPCManager.kill_npc()를 부르는 건 main.gd의 컷신(_play_arrest_ending_sequence)
	## 안, 총 맞는 순간이다 - 여기서 미리 죽여두면 아직 총 맞기 전 대사에서도
	## 초상화가 사망 처리(흑백)로 뜨는 버그가 있었다(사용자 리포트, 2026-08-26).
	## _stalker_killed/_ending_achieved만으로 다른 시스템(살인 루프 정지, 스토커
	## 메일 중단 등)은 이미 충분히 멈춘다 - is_alive()에 의존하는 곳은 없음.
	_update_pending_state()
	arrest_ending_triggered.emit(spared_npc_id)


func _record_case(victim_id: String) -> void:
	_cases.append({
		"victim_id": victim_id,
		"day": TimeManager.current_day,
		"weekday": TimeManager.get_weekday(),
		"alibis": _snapshot_alibis(victim_id),
		"witnesses": _snapshot_witnesses(victim_id),
	})


func _snapshot_alibis(victim_id: String) -> Dictionary:
	var alibis: Dictionary = {}
	var weekday := TimeManager.get_weekday()
	var is_raining := WeatherManager.is_raining()
	var check_time := "%02d:00" % ALIBI_CHECK_HOUR
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		alibis[npc_id] = NPCManager.get_schedule_state_at(npc_id, weekday, check_time, is_raining)
	return alibis


## 목격 증언(사용자 지시, 2026-08-17) - "그날 오후 6시" 한 시점이 아니라 그날
## 하루 전체를 기준으로, 각 생존 NPC가 스케줄상 마주쳤을 만한 다른 NPC를 사건
## 당시 시점에 미리 계산해서 고정해둔다(알리바이와 같은 이유로 나중에 다시
## 계산하지 않음 - NPCManager.get_witness_candidates() 참고).
func _snapshot_witnesses(victim_id: String) -> Dictionary:
	var witnesses: Dictionary = {}
	var weekday := TimeManager.get_weekday()
	var is_raining := WeatherManager.is_raining()
	for npc_id in NPCManager.get_all_ids():
		if npc_id == victim_id or not NPCManager.is_alive(npc_id):
			continue
		witnesses[npc_id] = NPCManager.get_witness_candidates(npc_id, weekday, is_raining)
	return witnesses


## state가 빈 문자열이면 "지금 어느 맵에도 없는" NPC다 - 로시처럼
## visible_only_when_raining인 NPC가 비 안 오는 날 스케줄(로시.json 참고,
## 맑은 날엔 바다로 출항해 맵에서 안 보임)에 걸린 경우가 지금 유일한 사례.
## 그대로 두면 무고한 NPC가 "알 수 없는 장소"(=수상해 보임)로 처리돼버린다
## (사용자 리포트, 2026-08-26 - "바다에 나가있으면 알수없는 장소에 있었어
## 이러네 진짜 개수상해보임"). 지금은 로시 한 명뿐이라 하드코딩 - 비슷한
## 패턴의 NPC가 늘어나면 스케줄 데이터에 필드를 추가하는 쪽으로 일반화할 것.
func _describe_location(state: String) -> String:
	if state.is_empty():
		return "바다"
	for prefix in LOCATION_NAMES:
		if state.begins_with(prefix):
			return String(LOCATION_NAMES[prefix])
	return "알 수 없는 장소"


func _update_pending_state() -> void:
	WeatherManager.set_murder_pending(has_pending_victim())
