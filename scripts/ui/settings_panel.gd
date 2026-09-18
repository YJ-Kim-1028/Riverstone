extends Control

## 상태창(TAB) "설정" 탭 - 브금/효과음(비/실내빗소리/파도/강 등 배경음
## 전부) 볼륨 슬라이더. 실제 볼륨 적용과 저장은 AudioManager(오디오 버스 +
## user://audio_settings.cfg)가 전담하고, 이 패널은 슬라이더 UI와 값
## 동기화만 담당한다.
## 행동키/미니맵 키 재지정(사용자 지시, 2026-09-16 - "키설정도 할 수
## 잇으면 좋겠는데 미니맵이랑 행동키 정도")도 여기 같이 둔다 - 실제 키코드
## 저장/조회는 Keybinds(scripts/autoload/keybind_manager.gd)가 전담.

@onready var _bgm_slider: HSlider = $VBox/BgmRow/Slider
@onready var _bgm_value_label: Label = $VBox/BgmRow/ValueLabel
@onready var _sfx_slider: HSlider = $VBox/SfxRow/Slider
@onready var _sfx_value_label: Label = $VBox/SfxRow/ValueLabel
@onready var _interact_key_button: Button = $VBox/InteractRow/KeyButton
@onready var _minimap_key_button: Button = $VBox/MinimapRow/KeyButton

const REBINDING_LABEL := "..."
## 다른 팝업들(sleep_confirm_popup.gd 등)과 같은 9-슬라이스 버튼 스타일 -
## 안 입혀서 키 버튼만 엔진 기본 회색 버튼으로 튀어보였다(사용자 리포트,
## 2026-09-16 - "버튼 설정 디자인 너무못생겼음").
const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

## 재지정 중인 행동(Keybinds.INTERACT_ACTION 등) - 비어있으면 재지정 중이
## 아님.
var _rebinding_action := ""


func _ready() -> void:
	_bgm_slider.value = AudioManager.get_bgm_volume() * 100.0
	_sfx_slider.value = AudioManager.get_sfx_volume() * 100.0
	_update_value_label(_bgm_value_label, _bgm_slider.value)
	_update_value_label(_sfx_value_label, _sfx_slider.value)
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_refresh_key_button(Keybinds.INTERACT_ACTION)
	_refresh_key_button(Keybinds.MINIMAP_ACTION)
	_interact_key_button.pressed.connect(_on_interact_key_button_pressed)
	_minimap_key_button.pressed.connect(_on_minimap_key_button_pressed)
	_style_button(_interact_key_button)
	_style_button(_minimap_key_button)


func _on_bgm_changed(value: float) -> void:
	AudioManager.set_bgm_volume(value / 100.0)
	_update_value_label(_bgm_value_label, value)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value / 100.0)
	_update_value_label(_sfx_value_label, value)


func _update_value_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(value))


func _on_interact_key_button_pressed() -> void:
	_start_rebind(Keybinds.INTERACT_ACTION)


func _on_minimap_key_button_pressed() -> void:
	_start_rebind(Keybinds.MINIMAP_ACTION)


func _start_rebind(action: String) -> void:
	_rebinding_action = action
	_button_for_action(action).text = REBINDING_LABEL


## 재지정 대기 중일 때만 다음 키 입력을 가로챈다 - 그 외엔 아무 것도 안 해서
## 다른 화면의 입력 처리를 막지 않는다.
func _unhandled_input(event: InputEvent) -> void:
	if _rebinding_action.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var action := _rebinding_action
	_rebinding_action = ""
	if event.keycode != KEY_ESCAPE:
		Keybinds.set_keycode(action, event.keycode)
	_refresh_key_button(action)
	get_viewport().set_input_as_handled()


func _refresh_key_button(action: String) -> void:
	_button_for_action(action).text = Keybinds.get_key_label(action)


func _button_for_action(action: String) -> Button:
	return _interact_key_button if action == Keybinds.INTERACT_ACTION else _minimap_key_button


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
