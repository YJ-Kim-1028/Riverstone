extends RefCounted
class_name Localizer

## 다국어(i18n) 상태를 전담하는 정적 유틸리티. 오토로드가 아니다 - CLAUDE.md가
## 못박은 6개 오토로드 목록을 더 늘리지 않으려고 home_map.gd의 `class_name
## WorldMap` 정적 유틸리티 패턴을 그대로 재사용했다(NPCManager/
## HorrorEventManager 양쪽에서 공통으로 필요해서 어느 한쪽 소유 인스턴스로
## 두면 plumbing이 더 필요했음). 2026-09-14 다국어 지원 1단계 - 계획 파일:
## C:\Users\code1\.claude\plans\expressive-twirling-fern.md

const SUPPORTED_LANGUAGES: Array[String] = ["ko", "en", "ja", "zh", "es"]
## tr() 키/데이터 원본 파일이 실제로 쓰여진 언어 - "번역이 필요 없는 기준
## 언어"라는 뜻이라 아래 INITIAL_LANGUAGE(첫 실행 시 화면에 보일 언어)와는
## 다른 개념이다. 절대 바꾸지 말 것 - 데이터 파일 자체가 한국어라 이 값이
## 곧 "그 언어는 번역 파일을 안 찾아도 됨"의 기준이 된다.
const DEFAULT_LANGUAGE := "ko"
## 언어 설정 파일(LANGUAGE_SETTINGS_PATH)이 아직 없는 최초 실행에서 보여줄
## 언어(사용자 지시, 2026-09-16 - "처음 게임 깔고 켰을때 기본 언어가 영어면
## 좋겠어"). 이 프로젝트를 처음 설치하는 사람이 한국어를 모를 수 있다는
## 전제 - 언어를 한 번이라도 고르고 나면 그 이후로는 이 값과 무관하게 저장된
## 선택이 그대로 쓰인다.
const INITIAL_LANGUAGE := "en"

## audio_manager.gd의 AUDIO_SETTINGS_PATH와 동일한 이유 - SaveData(3슬롯)와
## 무관한 전역 사용자 환경설정이라 세이브 파일이 아니라 여기 따로 저장한다
## (CLAUDE.md "SaveData 구조 변경 금지" 준수).
const LANGUAGE_SETTINGS_PATH := "user://language_settings.cfg"

static var current_language := INITIAL_LANGUAGE

## GDScript 로직이 식별자/enum/숫자로 직접 소비하는 키 - 번역 파일에 값이
## 있어도 절대 치환하지 않는다. 특히 requires_alive는 NPC id 문자열이라,
## 잘못 번역되면 죽은 NPC 대사 분기(fallback_lines)가 영구히 깨진다.
## preferred_food/disliked_food(data/npc)와 base_material(data/items)은 겉보기엔
## 평범한 한국어 재료 이름이라 번역하고 싶어지지만, `NPCManager.
## get_food_preference_for_ingredients()`가 이 둘을 서로 직접 문자열 비교한다 -
## items.json은 절대 번역되지 않으므로 preferred_food/disliked_food가 번역되면
## 그 언어에서 좋아하는/싫어하는 음식 판정이 조용히 깨진다(2026-09-15 실제
## 발견 - marr.en/sage.en/poli.en/poli.ja/belje.zh 5개 파일에 이미 있던 버그를
## 수동으로 고쳤음, 재발 방지 목적으로 여기 등록).
const DENYLIST_KEYS := [
	"type", "item_id", "emotion", "requires_alive", "affection", "id", "threshold",
	"preferred_food", "disliked_food", "base_material",
]

const GALMURI_FONT_PATH := "res://assets/fonts/Galmuri/Galmuri11-Bold.ttf"
## Galmuri(한글+라틴 전용)는 일본어/중국어 글자가 없어서, 그 두 언어일 때만
## Ark Pixel Font(TakWolf/ark-pixel-font, SIL OFL 1.1 - 상업적 사용 무료,
## 한/중/일 지원 픽셀체, assets/fonts/ArkPixel/LICENSE-OFL.txt)로 교체한다.
## 영어는 라틴 문자뿐이라 기존 Galmuri로 충분 - 폰트 안 바꿈.
const CJK_FONT_PATHS := {
	"ja": "res://assets/fonts/ArkPixel/ark-pixel-12px-ja.ttf",
	"zh": "res://assets/fonts/ArkPixel/ark-pixel-12px-zh.ttf",
}


const UI_STRINGS_PATH := "res://data/localization/strings.json"
## 한 세션에서 두 번 이상 로드하지 않도록(언어를 여러 번 바꿔도 TranslationServer에
## 같은 Translation을 중복 등록하지 않는다).
static var _ui_translations_loaded := false


## Godot의 CSV 자동 임포트 파이프라인 대신, UI 문자열 카탈로그를 JSON으로 두고
## `Translation.add_message()` + `TranslationServer.add_translation()`으로
## 런타임에 직접 등록한다 - 둘 다 공식 문서에 정의된 스크립트 API라 헤드리스
## 환경(에디터로 CSV를 다시 임포트할 수 없는 상황)에서도 동작이 보장된다.
## 키는 한국어 원문 그 자체(`tr("판매 중인 상품이 없습니다.")`처럼) - 새 키
## 체계를 발명하지 않고, 번역이 없으면 원문이 그대로 반환되는 Godot 기본
## 동작을 그대로 활용한다.
static func _load_ui_translations() -> void:
	if _ui_translations_loaded:
		return
	_ui_translations_loaded = true
	if not FileAccess.file_exists(UI_STRINGS_PATH):
		return
	var file := FileAccess.open(UI_STRINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("UI translation catalog is not valid JSON: %s" % UI_STRINGS_PATH)
		return
	var catalog: Dictionary = parsed
	var translations_by_language: Dictionary = {}
	for language in SUPPORTED_LANGUAGES:
		if language == DEFAULT_LANGUAGE:
			continue
		var translation := Translation.new()
		translation.locale = language
		translations_by_language[language] = translation
	for source_text in catalog.keys():
		var entry: Dictionary = catalog[source_text]
		for language in translations_by_language.keys():
			var value: Variant = entry.get(language)
			if value is String and not (value as String).is_empty():
				(translations_by_language[language] as Translation).add_message(source_text, value)
	for translation in translations_by_language.values():
		TranslationServer.add_translation(translation)


## GameManager._ready() 맨 앞에서 한 번 호출된다(NPCManager/HorrorEventManager
## 보다 먼저 초기화되어야 그 둘이 로드할 때부터 올바른 언어로 합쳐진다).
static func load_saved_language() -> void:
	_load_ui_translations()
	var config := ConfigFile.new()
	if config.load(LANGUAGE_SETTINGS_PATH) == OK:
		var saved: String = config.get_value("locale", "language", INITIAL_LANGUAGE)
		if saved in SUPPORTED_LANGUAGES:
			current_language = saved
	TranslationServer.set_locale(current_language)
	apply_font_for_language()


## language_settings_screen.gd가 언어를 바꿀 때 호출한다.
static func save_language(code: String) -> void:
	if not (code in SUPPORTED_LANGUAGES):
		return
	current_language = code
	var config := ConfigFile.new()
	config.set_value("locale", "language", code)
	config.save(LANGUAGE_SETTINGS_PATH)
	TranslationServer.set_locale(code)
	apply_font_for_language()
	_notify_translation_changed()


## `TranslationServer.set_locale()`만으로는 이미 화면에 떠 있는 Control(예:
## 타이틀 화면 뒤의 "시작하기" 버튼 - 언어 설정 팝업이 그 위에 열려 있을 뿐,
## 같은 씬트리 안에 계속 살아있음)의 표시 문자열이 즉시 안 바뀌는 경우가
## 있다(사용자 리포트, 2026-09-14 - "시작하기 이런거 다 번역이 안되어잇음") -
## Godot 커뮤니티에 잘 알려진 문제. `NOTIFICATION_TRANSLATION_CHANGED`를
## 트리 전체에 명시적으로 다시 뿌려서 모든 Control이 즉시 재번역하도록
## 강제한다.
static func _notify_translation_changed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.propagate_notification(Node.NOTIFICATION_TRANSLATION_CHANGED)


## 프로젝트 전역 Theme 리소스(res://theme/ui_theme.tres, project.godot의
## theme/custom) 하나를 직접 고쳐서 모든 Control에 한 번에 반영한다.
static func apply_font_for_language() -> void:
	var theme := ThemeDB.get_project_theme()
	if theme == null:
		return
	var font_path: String = CJK_FONT_PATHS.get(current_language, GALMURI_FONT_PATH)
	var font := load(font_path) as Font
	if font != null:
		theme.default_font = font


## data/npc/marin.json + "en" -> data/npc/marin.en.json (파일 없으면 null -
## 에러 아님, 그 언어는 전부 한국어로 폴백).
static func load_language_sibling(base_path: String, language: String) -> Variant:
	if language == DEFAULT_LANGUAGE:
		return null
	var sibling_path := base_path.replace(".json", ".%s.json" % language)
	if not FileAccess.file_exists(sibling_path):
		return null
	var file := FileAccess.open(sibling_path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


## 한국어 원본 구조를 기준으로, 번역 파일의 같은 경로에 있는 문자열 리프만
## 치환한다(값이 없거나 타입이 안 맞으면 그 자리는 한국어로 폴백). 배열은
## 길이가 다르면 통째로 폴백(부분 스플라이스 안 함) - stalker_emails.json의
## early/mid/late처럼 인덱스로만 대응되는 구조가 있어서, 길이가 어긋나면
## 조용히 엉뚱한 자리에 엉뚱한 번역이 들어갈 수 있다(크래시보다 위험한
## 종류의 버그라 안전한 쪽인 "전체 폴백"을 택함).
static func merge_json(korean: Variant, translated: Variant) -> Variant:
	if korean is String:
		if translated is String and not (translated as String).is_empty():
			return translated
		return korean
	if korean is Dictionary:
		if not (translated is Dictionary):
			return korean
		var out: Dictionary = (korean as Dictionary).duplicate(true)
		for key in (korean as Dictionary).keys():
			if key in DENYLIST_KEYS:
				continue
			out[key] = merge_json((korean as Dictionary)[key], (translated as Dictionary).get(key))
		return out
	if korean is Array:
		if not (translated is Array) or (translated as Array).size() != (korean as Array).size():
			if translated is Array:
				push_warning("Localizer: language array length mismatch, falling back to Korean")
			return korean
		var out_arr := []
		for i in (korean as Array).size():
			out_arr.append(merge_json((korean as Array)[i], (translated as Array)[i]))
		return out_arr
	return korean


## data/npc/marin.json 같은 원본 경로 하나를 현재 언어로 병합해서 돌려준다.
## 원본 로드/파싱 자체는 호출부(npc_manager.gd/horror_event_manager.gd)가
## 이미 하고 있으니, 파싱된 Variant를 받아서 언어 형제 파일과 합치기만 한다.
static func apply_language(korean: Variant, base_path: String) -> Variant:
	if current_language == DEFAULT_LANGUAGE:
		return korean
	var translated: Variant = load_language_sibling(base_path, current_language)
	if translated == null:
		return korean
	return merge_json(korean, translated)
