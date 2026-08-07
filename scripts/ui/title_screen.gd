extends Control

## 프로젝트의 새 시작 지점(project.godot run/main_scene) - 시작하기/이어하기/
## 언어설정/종료 4개 버튼. 시작하기는 슬롯 선택(새 게임 모드) -> 캐릭터 생성
## 화면까지 마치고 나서야 main.tscn으로 넘어가고, 이어하기는 슬롯 선택(이어
## 하기 모드)에서 데이터가 있는 슬롯을 고르면 SaveManager.load_game() 이후
## 바로 main.tscn으로 넘어간다.
##
## 이어하기로 재개할 때 정확한 좌표는 복원하지 않는다 - SaveData에 플레이어
## 위치 자체가 저장 항목으로 없고(맵 id만 있음), 새로 추가하는 것도
## "SaveData 구조 변경 금지"(CLAUDE.md)에 해당한다고 판단해 하지 않았다.
## main.tscn이 항상 그렇듯 Home의 기본 스폰(home_pond_standing)에서 시작하며,
## 이건 사실 기존에도 마찬가지였다(자동저장이 취침/맵이동 때만 발생하고, 취침
## 자동저장은 어차피 다음날 Home에서 시작하는 게 맞으므로 대부분의 실제
## 케이스에서는 이 단순화가 정확하다).

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)
const DISABLED_TINT := Color(0.55, 0.55, 0.55)
const MODE_NEW_GAME := "new_game"
const MODE_CONTINUE := "continue"

@onready var _start_button: Button = $ButtonColumn/StartButton
@onready var _continue_button: Button = $ButtonColumn/ContinueButton
@onready var _language_button: Button = $ButtonColumn/LanguageButton
@onready var _quit_button: Button = $ButtonColumn/QuitButton
@onready var _slot_picker: Control = $SlotPickerScreen
@onready var _character_creation: Control = $CharacterCreationScreen
@onready var _language_screen: Control = $LanguageSettingsScreen


func _ready() -> void:
	for button in [_start_button, _continue_button, _language_button, _quit_button]:
		_style_button(button)
	_start_button.pressed.connect(func() -> void: _slot_picker.open(MODE_NEW_GAME))
	_continue_button.pressed.connect(func() -> void: _slot_picker.open(MODE_CONTINUE))
	_language_button.pressed.connect(_language_screen.open)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_slot_picker.slot_confirmed.connect(_on_slot_confirmed)
	_slot_picker.closed.connect(_refresh_continue_button)
	_character_creation.confirmed.connect(_on_character_confirmed)
	_refresh_continue_button()


## 세이브가 하나도 없으면 이어하기를 아예 못 누르게 - 빈 슬롯 3개짜리
## 화면을 열어봤자 아무것도 할 게 없으므로.
func _refresh_continue_button() -> void:
	var has_any_save := false
	for slot in SaveManager.SAVE_SLOT_COUNT:
		if SaveManager.has_save(slot + 1):
			has_any_save = true
			break
	_continue_button.disabled = not has_any_save


func _on_slot_confirmed(slot: int, mode: String) -> void:
	if mode == MODE_CONTINUE:
		SaveManager.load_game(slot)
		_go_to_main()
	else:
		_slot_picker.close()
		_character_creation.open(slot)


func _on_character_confirmed() -> void:
	_go_to_main()


func _go_to_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	# disabled를 안 채워두면(예: 세이브가 하나도 없어 이어하기가 비활성일 때)
	# Godot 기본 테마의 밋밋한 사각형으로 보인다 - 같은 버튼 그림을 어둡게
	# 입혀서 "버튼은 맞는데 지금은 못 누른다"는 느낌으로 통일한다.
	button.add_theme_stylebox_override("disabled", _build_button_style(BUTTON_TEXTURE, DISABLED_TINT))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_disabled_color", BUTTON_TEXT_COLOR.lerp(Color.BLACK, 0.3))


func _build_button_style(texture: Texture2D, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	style.modulate_color = tint
	return style
