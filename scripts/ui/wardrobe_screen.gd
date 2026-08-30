extends Control

## 집의 "closet" Interactable로 여는 인게임 외형 재커스터마이즈 화면(피드백 #11).
## character_creation_screen.gd와 구조는 같지만(탭 8개 + 헤어/옷/악세서리 순환 +
## 미리보기) 확정 단계 없이 고르는 즉시 반영 + appearance_changed를 쏜다(강제
## 저장 안 함). 색은 고정 스와치 대신 Godot 내장 ColorPicker(SV사각형+색상
## 슬라이더만, RGB/헥스/모드탭/샘플러/프리셋은 숨김 - 사용자 확정, 2026-08-30).

const FRAME_WIDTH := CharacterAppearance.FRAME_WIDTH
const FRAME_HEIGHT := CharacterAppearance.FRAME_HEIGHT
const NONE_LABEL := "없음"

## character_appearance.gd엔 없는 델타값 - character_creation_screen.gd와
## 동일, 두 파일 다 같이 갱신해야 하는 중복 상수.
const HAIR_LIGHT_DELTA := 62.0 / 255.0
const HAIR_DARK_DELTA := 68.0 / 255.0

@onready var _preview: Control = $Panel/Margin/VBox/HBox/RightColumn/Preview
@onready var _palette_tabs: Dictionary = {
	"skin": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/SkinCol/SkinTab,
	"eye": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/EyeCol/EyeTab,
	"hair": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/HairCol/HairTab,
	"cheek": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/CheekCol/CheekTab,
	"outfit_1": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/Outfit1Col/Outfit1Tab,
	"outfit_2": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/Outfit2Col/Outfit2Tab,
	"outfit_3": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/Outfit3Col/Outfit3Tab,
	"accessory": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/AccessoryCol/AccessoryTab,
}
@onready var _color_picker: ColorPicker = $Panel/Margin/VBox/HBox/LeftColumn/ColorPicker
@onready var _hair_label: Label = $Panel/Margin/VBox/HBox/LeftColumn/HairRow/HairLabel
@onready var _outfit_label: Label = $Panel/Margin/VBox/HBox/LeftColumn/OutfitRow/OutfitLabel
@onready var _accessory_label: Label = $Panel/Margin/VBox/HBox/LeftColumn/AccessoryRow/AccessoryLabel
@onready var _close_button: TextureButton = $Panel/CloseButton

var _is_open := false
var _active_palette_target := "skin"

var _hair_index := 0
var _outfit_index := 0
var _accessory_index := 0

var _skin_color := Color.WHITE
var _eye_color := Color.WHITE
var _cheek_color := Color.WHITE
var _hair_color := Color.WHITE
var _outfit_colors: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE]
var _accessory_color := Color.WHITE

var _body_sheet_image: Image = null
var _outfit_sheet_image: Image = null
var _outfit_row_count := 0
var _hair_sheet_image: Image = null
var _hair_row_count := 0
var _accessory_sheet_image: Image = null
var _accessory_row_count := 0


func _ready() -> void:
	_set_open(false)
	_load_sheets()
	_color_picker.picker_shape = ColorPicker.SHAPE_HSV_RECTANGLE
	_color_picker.sliders_visible = false
	_color_picker.hex_visible = false
	_color_picker.color_modes_visible = false
	_color_picker.sampler_visible = false
	_color_picker.presets_visible = false
	_color_picker.color_changed.connect(_on_color_picker_color_changed)
	_close_button.pressed.connect(close)
	_connect_arrows("Panel/Margin/VBox/HBox/LeftColumn/HairRow", "hair")
	_connect_arrows("Panel/Margin/VBox/HBox/LeftColumn/OutfitRow", "outfit")
	_connect_arrows("Panel/Margin/VBox/HBox/LeftColumn/AccessoryRow", "accessory")
	for target in _palette_tabs.keys():
		(_palette_tabs[target] as Button).pressed.connect(_on_palette_tab_pressed.bind(target))


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


## 캐릭터 생성 화면과 달리 디폴트로 리셋하지 않는다 - GameManager에 이미 저장된
## "지금 입고 있는" 외형을 그대로 불러와 편집을 시작한다.
func open() -> void:
	_hair_index = int(GameManager.hair_id)
	_outfit_index = int(GameManager.outfit_id)
	_accessory_index = int(GameManager.accessory_id)
	_skin_color = Color(GameManager.skin_color)
	_eye_color = Color(GameManager.eye_color)
	_cheek_color = Color(GameManager.cheek_color)
	_hair_color = Color(GameManager.hair_color_2) # 색2 = 기준(중간) 톤
	_outfit_colors = [
		Color(GameManager.outfit_color_1), Color(GameManager.outfit_color_2), Color(GameManager.outfit_color_3),
	]
	_accessory_color = Color(GameManager.accessory_color)
	_active_palette_target = "skin"
	_color_picker.color = _skin_color
	_update_palette_tab_styles()
	_refresh_pickers()
	_set_open(true)


func close() -> void:
	_set_open(false)


func _on_palette_tab_pressed(target: String) -> void:
	_active_palette_target = target
	_color_picker.color = _get_target_color(target)
	_refresh_pickers()


## 대머리/악세서리 "없음"이면 리컬러할 그림이 없어 팔레트를 숨긴다 - 탭이
## disabled라 눌러서 들어올 순 없지만, 이미 보던 중 화살표로 0이 되는 경우도
## 커버한다(사용자 지시, 2026-08-30).
func _update_color_picker_visibility() -> void:
	var hidden := (_active_palette_target == "hair" and _hair_index == 0) \
		or (_active_palette_target == "accessory" and _accessory_index == 0)
	_color_picker.visible = not hidden


## ColorPicker에서 색을 고를 때마다(드래그 중엔 여러 번) 바로 반영 - 캐릭터
## 생성 화면과 달리 "확정" 단계가 없어서, 고르는 즉시 GameManager와 미리보기가
## 같이 갱신된다.
func _on_color_picker_color_changed(color: Color) -> void:
	_set_target_color(color)
	_write_target_to_game_manager(_active_palette_target)
	_update_palette_tab_styles()
	_refresh_pickers()
	GameManager.appearance_changed.emit()


## 헤어/옷/악세서리 순환 화살표 공용 처리 - kind가 로컬 변수/GameManager 필드
## 이름에 그대로 꽂히는 명명 규칙(get/set 동적 접근)으로 함수 3개를 합쳤다.
func _cycle_style(kind: String, direction: int) -> void:
	var row_count: int = get("_%s_row_count" % kind)
	var index: int = wrapi(int(get("_%s_index" % kind)) + direction, 0, row_count)
	set("_%s_index" % kind, index)
	GameManager.set("%s_id" % kind, str(index))
	_refresh_pickers()
	GameManager.appearance_changed.emit()


## "outfit_1"/"outfit_2"/"outfit_3" 탭 이름의 접미사 숫자를 배열 인덱스로.
func _outfit_slot(target: String) -> int:
	return int(target.substr(7)) - 1


## outfit_* 이외는 로컬 변수 이름이 전부 "_<target>_color"라 get()으로 읽는다.
func _get_target_color(target: String) -> Color:
	if target.begins_with("outfit_"):
		return _outfit_colors[_outfit_slot(target)]
	return get("_%s_color" % target)


func _set_target_color(color: Color) -> void:
	if _active_palette_target.begins_with("outfit_"):
		_outfit_colors[_outfit_slot(_active_palette_target)] = color
		return
	set("_%s_color" % _active_palette_target, color)


## 머리/옷은 GameManager 필드 구조가 달라서(머리=자동 밝기 3색, 옷=슬롯별
## 독립 3색) 예외 처리하고, 나머지는 필드 이름이 그대로 대응해 set()으로 쓴다.
func _write_target_to_game_manager(target: String) -> void:
	if target.begins_with("outfit_"):
		var slot := _outfit_slot(target)
		GameManager.set("outfit_color_%d" % (slot + 1), _outfit_colors[slot].to_html(false))
		return
	if target == "hair":
		GameManager.hair_color_1 = CharacterAppearance.offset_brightness(_hair_color, HAIR_LIGHT_DELTA).to_html(false)
		GameManager.hair_color_2 = _hair_color.to_html(false)
		GameManager.hair_color_3 = CharacterAppearance.offset_brightness(_hair_color, -HAIR_DARK_DELTA).to_html(false)
		return
	GameManager.set("%s_color" % target, (get("_%s_color" % target) as Color).to_html(false))


func _update_palette_tab_styles() -> void:
	for target in _palette_tabs.keys():
		var button := _palette_tabs[target] as Button
		_set_swatch_style(button, _get_target_color(target), target == _active_palette_target)
		if target == "hair":
			button.disabled = _hair_index == 0
		elif target == "accessory":
			button.disabled = _accessory_index == 0
		else:
			button.disabled = false


## disabled 안 덮어쓰면 Godot 기본(둥근) 테마가 새어 나와 안 어울렸다.
const DISABLED_SWATCH_COLOR := Color(0.55, 0.5, 0.42)

func _set_swatch_style(button: Button, color: Color, is_active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var border_width := 2 if is_active else 1
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = Color(0.25, 0.15, 0.08)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var disabled_style := style.duplicate() as StyleBoxFlat
	disabled_style.bg_color = DISABLED_SWATCH_COLOR
	button.add_theme_stylebox_override("disabled", disabled_style)


func _refresh_pickers() -> void:
	_hair_label.text = "대머리" if _hair_index == 0 else "헤어 %d" % _hair_index
	_update_palette_tab_styles()
	_update_color_picker_visibility()
	_outfit_label.text = "옷 %d" % (_outfit_index + 1)
	_accessory_label.text = NONE_LABEL if _accessory_index == 0 else "악세서리 %d" % _accessory_index
	_preview.set_layers(
		_current_body_texture(),
		_current_outfit_texture(),
		_current_hair_texture(),
		_current_accessory_texture()
	)


func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
	## ColorPicker는 드래그 상태를 자체적으로 들고 있어서 mouse_filter만으로는
	## 안 끊긴다(CLAUDE.md "UI 모달 화면 체크리스트" 6번 참고) - visible도
	## 같이 꺼야 Godot이 그 상태까지 확실히 놓아버린다.
	visible = is_open


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _connect_arrows(row_path: String, kind: String) -> void:
	var row := get_node(row_path) as HBoxContainer
	var prev_button := row.get_node("PrevButton") as TextureButton
	var next_button := row.get_node("NextButton") as TextureButton
	prev_button.pressed.connect(_cycle_style.bind(kind, -1))
	next_button.pressed.connect(_cycle_style.bind(kind, 1))


func _load_sheets() -> void:
	_body_sheet_image = CharacterAppearance.load_sheet_image(CharacterAppearance.BODY_PATH)
	_outfit_sheet_image = CharacterAppearance.load_sheet_image(CharacterAppearance.OUTFIT_SHEET_PATH)
	_outfit_row_count = CharacterAppearance.sheet_row_count(_outfit_sheet_image)
	_hair_sheet_image = CharacterAppearance.load_sheet_image(CharacterAppearance.HAIR_SHEET_PATH)
	_hair_row_count = CharacterAppearance.sheet_row_count(_hair_sheet_image)
	_accessory_sheet_image = CharacterAppearance.load_sheet_image(CharacterAppearance.ACCESSORY_SHEET_PATH)
	_accessory_row_count = CharacterAppearance.sheet_row_count(_accessory_sheet_image)


## 몸은 피부/눈/뺨 3쌍을 한 프레임에 같이 리컬러해야 해서 마커·팔레트를 이어
## 붙여 한 번에 넘긴다(build_preview_texture는 한 쌍짜리 단순 케이스용).
func _current_body_texture() -> Texture2D:
	var frame_image := CharacterAppearance.extract_frame(_body_sheet_image, 0)
	if frame_image == null:
		return null
	var skin_palette: Array[Color] = [
		CharacterAppearance.offset_brightness(_skin_color, CharacterAppearance.SKIN_LIGHT_DELTA),
		_skin_color,
		CharacterAppearance.offset_brightness(_skin_color, -CharacterAppearance.SKIN_DARK_DELTA),
	]
	## Array[Color] + [..]는 타입이 지워진 Array를 돌려줘 런타임에 거부된다 -
	## duplicate() 후 append_array()로 이어 붙여야 타입이 유지된다.
	var markers: Array[Color] = CharacterAppearance.SKIN_MARKER_COLORS.duplicate()
	markers.append_array([CharacterAppearance.EYE_MARKER_COLOR, CharacterAppearance.CHEEK_MARKER_COLOR])
	var palette: Array[Color] = skin_palette.duplicate()
	palette.append_array([_eye_color, _cheek_color])
	CharacterAppearance.recolor_image(frame_image, markers, palette)
	return ImageTexture.create_from_image(frame_image)


func _current_outfit_texture() -> Texture2D:
	return CharacterAppearance.build_preview_texture(_outfit_sheet_image, _outfit_index, CharacterAppearance.OUTFIT_MARKER_COLORS, _outfit_colors)


func _current_hair_texture() -> Texture2D:
	if _hair_index <= 0:
		return null
	var hair_palette: Array[Color] = [
		CharacterAppearance.offset_brightness(_hair_color, HAIR_LIGHT_DELTA),
		_hair_color,
		CharacterAppearance.offset_brightness(_hair_color, -HAIR_DARK_DELTA),
	]
	return CharacterAppearance.build_preview_texture(_hair_sheet_image, _hair_index, CharacterAppearance.HAIR_MARKER_COLORS, hair_palette)


func _current_accessory_texture() -> Texture2D:
	if _accessory_index <= 0:
		return null
	return CharacterAppearance.build_preview_texture(_accessory_sheet_image, _accessory_index, [CharacterAppearance.ACCESSORY_MARKER_COLOR], [_accessory_color])
