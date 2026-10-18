extends Control

## 언어 설정 화면. 다국어 지원 1단계(2026-09-14, 계획 파일:
## C:\Users\code1\.claude\plans\expressive-twirling-fern.md)에서 Localizer
## (scripts/autoload/localization.gd)와 연결해 실제로 동작하게 채웠다.
## 처음엔 OptionButton(네이티브 드롭다운)으로 만들었는데, 이 프로젝트 어디에도
## OptionButton 쓰인 곳이 없어서 다른 화면들과 확 달라 보인다는 피드백(사용자
## 지시, 2026-09-14 - "버튼 디자인이 너무 못생겼엉") - Button 4개(toggle_mode +
## 공유 ButtonGroup으로 라디오 버튼처럼 동작)로 교체했다.
## 그래도 여전히 못생겼다는 후속 피드백("언어 고를때 디자인 버튼 디자인
## 씌워줘") - quit_confirm_popup.gd 등 이 프로젝트 팝업 전부가 쓰는
## button.png/button_hover.png 9-슬라이스 스타일을 처음에 빠뜨렸었음(그
## 화면들도 .tscn엔 기본 Button만 있고 실제 스타일은 _ready()에서
## 코드로 입힌다는 걸 놓쳤음) - 동일한 패턴을 그대로 가져와 입힘.

const UIUtil := preload("res://scripts/ui/ui_util.gd")

signal closed

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

## 순서 = Localizer.SUPPORTED_LANGUAGES와 동일하게 맞춘 배열 - index로
## 언어 코드를 그대로 찾는다.
@onready var _language_buttons: Array[Button] = [
	$Panel/Margin/VBox/LanguageRow/KoButton,
	$Panel/Margin/VBox/LanguageRow/EnButton,
	$Panel/Margin/VBox/LanguageRow/JaButton,
	$Panel/Margin/VBox/LanguageRow/ZhButton,
	$Panel/Margin/VBox/LanguageRow/EsButton,
]
@onready var _back_button: Button = $Panel/Margin/VBox/BackButton

var _is_open := false


func _ready() -> void:
	var current_index := Localizer.SUPPORTED_LANGUAGES.find(Localizer.current_language)
	for i in _language_buttons.size():
		var language: String = Localizer.SUPPORTED_LANGUAGES[i]
		_language_buttons[i].button_pressed = i == current_index
		_language_buttons[i].pressed.connect(_on_language_button_pressed.bind(language))
	for button in _language_buttons:
		_style_button(button)
	_style_button(_back_button)
	_set_open(false)
	_back_button.pressed.connect(close)


## quit_confirm_popup.gd의 _style_button()/_build_button_style()과 완전히
## 동일한 패턴 - normal/hover 두 상태만 있는 9-슬라이스 텍스처라, toggle_mode
## 버튼의 "눌린 채 유지" 상태(pressed)도 hover 텍스처를 그대로 써서 현재
## 선택된 언어가 계속 밝게 보이도록 한다(선택 표시를 겸함).
func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)


func _build_button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	return style


## NPCManager/HorrorEventManager는 이미 로드된 정의를 새 언어로 다시 합쳐서
## 갱신한다(둘 다 디스크에서 매번 새로 읽는 구조라 재호출만으로 안전 - 각
## reload_for_language() 참고). 폰트/TranslationServer 로케일 전환은
## Localizer.save_language() 안에서 같이 처리된다.
func _on_language_button_pressed(language: String) -> void:
	Localizer.save_language(language)
	NPCManager.reload_for_language()
	HorrorEventManager.reload_for_language()
	## 인벤토리는 NPCManager 다음이어야 한다 - memento_* 재등록이 NPC 정의의
	## memento_item.name/description을 읽는데, 그게 이미 새 언어여야 한다.
	InventoryManager.reload_for_language()
	CookingManager.reload_for_language()
	LivestockManager.reload_for_language()
	ShopManager.reload_for_language()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)
	closed.emit()


## slot_picker_screen.gd와 동일한 이유/동일한 수정(사용자 리포트, 2026-08-27 -
## "언어 박스도 좌측 상단 고정되어 잇긴 하네") - 이 화면의 루트는 원래 전체화면
## (anchor 0/0/1/1)이라 PRESET_FULL_RECT 재적용이 안전하고, 실제로 이
## 방식이어야 익스포트 빌드에서 고쳐진다.
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
