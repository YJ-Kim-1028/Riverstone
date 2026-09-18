extends RefCounted
class_name Keybinds

## 새 파일 - 미니맵 토글/상호작용("행동키") 키 재지정 기능(사용자 지시,
## 2026-09-16 - "키설정도 할 수 잇으면 좋겠는데 미니맵이랑 행동키 정도").
## CLAUDE.md가 정해둔 6개 오토로드 목록을 늘리지 않으려고 Localizer.gd와
## 같은 정적 유틸리티 패턴(오토로드가 아니라 class_name으로 전역 접근,
## audio_settings.cfg/language_settings.cfg와 동일하게 SaveData와 무관한
## user:// 설정 파일에 저장)을 그대로 재사용한다.

const INTERACT_ACTION := "interact"
const MINIMAP_ACTION := "minimap"
const REBINDABLE_ACTIONS: Array[String] = [INTERACT_ACTION, MINIMAP_ACTION]

const DEFAULT_KEYCODES := {
	INTERACT_ACTION: KEY_E,
	MINIMAP_ACTION: KEY_M,
}

const KEYBIND_SETTINGS_PATH := "user://keybind_settings.cfg"
const CONFIG_SECTION := "keybinds"

static var _keycodes: Dictionary = DEFAULT_KEYCODES.duplicate()
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(KEYBIND_SETTINGS_PATH) != OK:
		return
	for action in REBINDABLE_ACTIONS:
		_keycodes[action] = int(config.get_value(CONFIG_SECTION, action, int(DEFAULT_KEYCODES[action])))


static func get_keycode(action: String) -> int:
	_ensure_loaded()
	return int(_keycodes.get(action, DEFAULT_KEYCODES.get(action, KEY_NONE)))


static func set_keycode(action: String, keycode: int) -> void:
	_ensure_loaded()
	_keycodes[action] = keycode
	var config := ConfigFile.new()
	config.load(KEYBIND_SETTINGS_PATH)
	for a in REBINDABLE_ACTIONS:
		config.set_value(CONFIG_SECTION, a, int(_keycodes.get(a, DEFAULT_KEYCODES[a])))
	config.save(KEYBIND_SETTINGS_PATH)


## keybind_row.gd가 버튼에 표시할 사람이 읽을 수 있는 키 이름("E", "M", "F1" 등).
static func get_key_label(action: String) -> String:
	return OS.get_keycode_string(get_keycode(action))
