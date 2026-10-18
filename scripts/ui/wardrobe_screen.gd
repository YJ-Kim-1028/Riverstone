extends Control

## 집의 "closet" Interactable로 여는 인게임 외형 재커스터마이즈 화면(피드백 #11).
## character_creation_screen.gd와 구조는 같지만(탭 8개 + 헤어/옷/악세서리 순환 +
## 미리보기) 확정 단계 없이 고르는 즉시 반영 + appearance_changed를 쏜다(강제
## 저장 안 함). 색은 고정 스와치 대신 Godot 내장 ColorPicker(SV사각형+색상
## 슬라이더만, RGB/헥스/모드탭/샘플러/프리셋은 숨김 - 사용자 확정, 2026-08-30).

const UIUtil := preload("res://scripts/ui/ui_util.gd")

const FRAME_WIDTH := CharacterAppearance.FRAME_WIDTH
const FRAME_HEIGHT := CharacterAppearance.FRAME_HEIGHT
const NONE_LABEL := "없음"

## character_appearance.gd엔 없는 델타값 - character_creation_screen.gd와
## 동일, 두 파일 다 같이 갱신해야 하는 중복 상수.
const HAIR_LIGHT_DELTA := 62.0 / 255.0
const HAIR_DARK_DELTA := 68.0 / 255.0

@onready var _preview: Control = $Panel/Margin/VBox/HBox/RightColumn/Preview
## 눈동자/머리색만 고를 수 있다(사용자 지시, 2026-09-03 - "눈동자랑 머리색만
## 남겨두고... 나머지 안쓰는색들 지워주는게 나을 거 같아") - 피부/뺨/악세서리
## 색은 HD 모드에서 안 보여서 뺐다(character_creation_screen.gd와 같은 정리).
@onready var _palette_tabs: Dictionary = {
	"eye": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/EyeCol/EyeTab,
	"hair": $Panel/Margin/VBox/HBox/LeftColumn/TabRow/HairCol/HairTab,
}
@onready var _color_picker: ColorPicker = $Panel/Margin/VBox/HBox/LeftColumn/ColorPicker
@onready var _hairstyle_label: Label = $Panel/Margin/VBox/HBox/LeftColumn/HairstyleRow/HairstyleLabel
@onready var _hd_outfit_label: Label = $Panel/Margin/VBox/HBox/LeftColumn/HdOutfitRow/HdOutfitLabel
@onready var _eye_label: Label = $Panel/Margin/VBox/HBox/LeftColumn/EyeRow/EyeLabel
@onready var _close_button: TextureButton = $Panel/CloseButton

var _is_open := false
var _active_palette_target := "hair"

## 구형 마커 리컬러 헤어 시스템 - 이 화면에서 더 이상 고를 수 없다(사용자 지시,
## 2026-09-02 - "옛날 헤어 고르는 거 없애줘", HD 헤어스타일로 대체됨). GameManager.hair_id를
## 그대로 읽어만 두는 캐시로만 남겨서, HD 스프라이트가 없는 방어적 상황(_refresh_pickers()
## 의 else 분기)에서 폴백 미리보기가 여전히 뭔가는 그리게 한다.
var _hair_index := 0
## 구형 마커 리컬러 옷 시스템도 마찬가지로 이 화면에서 더 이상 고를 수 없다
## (사용자 지시, 2026-09-03 - "기존 옷 구성은 날리고 새로 만드는거로 해줘",
## HD 아웃핏 오버레이로 대체됨) - _hair_index와 같은 이유로 GameManager.outfit_id를
## 읽어만 두는 캐시로 남겨서 폴백 미리보기가 계속 뭔가는 그리게 한다.
var _outfit_index := 0
## 악세서리 탭/순환도 이 화면에서 더 이상 고를 수 없다(사용자 지시, 2026-09-03 -
## "악세사리 스타일 고르는거랑 나머지 안쓰는색들 지워주는게 나을 거 같아") -
## 위 두 필드와 같은 이유로 폴백 미리보기용 캐시로만 남는다.
var _accessory_index := 0

## player.gd HD_HAIRSTYLES와 완전히 별개인 고해상도 프로토타입 헤어스타일 선택
## (사용자 지시, 2026-09-02 - "거울에서 고를수있게 적용해주면 안 돼?"). 목록
## 자체는 PlayerController.HD_HAIRSTYLES를 그대로 참조해서 두 곳에 중복 관리
## 안 하고, 여긴 화면에 보여줄 한글 이름표만 둔다.
const HAIRSTYLE_LABELS := {
	"danbal": "단발",
	"bun": "묶은머리",
	"curl_short_hair": "곱슬 단발",
	"one-side_tied": "한쪽 묶음",
	"shortcut": "숏컷",
	"straight_long_hair": "긴 생머리",
	"twin_tail": "트윈테일",
	"special_hair1": "스페셜 헤어 1",
	"special_hair2": "스페셜 헤어 2",
	"special_hair3": "스페셜 헤어 3",
	"special_hair4": "스페셜 헤어 4",
}
var _hairstyle_index := 0

## HD 아웃핏 오버레이 선택(player.gd HD_OUTFITS 참고) - 헤어스타일과 달리
## "없음"(빈 문자열, 옷 안 입은 상태)이 목록 맨 앞에 항상 들어간다. 라벨도
## 여기 한글 이름표로만 관리(중복 관리 방지는 헤어스타일과 동일한 방식).
const OUTFIT_LABELS := {
	"plain": "기본 세트 1",
	"plain2": "기본 세트 2",
	"look1": "룩 1",
	"look2": "룩 2",
	"look3": "룩 3",
	"look4": "룩 4",
	"look5": "룩 5",
	"look6": "룩 6",
	"look7": "룩 7",
	"look8": "룩 8",
	"look9": "룩 9",
	"look10": "룩 10",
}
var _hd_outfit_index := 0

## HD 눈 오버레이 선택(player.gd HD_EYE_STYLES 참고) - 옷과 달리 "없음"이
## 목록에 없는 게 기본(항상 뭔가 하나는 낀 상태)이지만, 화살표로 계속 돌리면
## "없음"도 고를 수 있게 목록 맨 끝에 붙여둔다.
const EYE_LABELS := {
	"anime_eyes": "애니메 눈",
	"droopy_eyes": "처진 눈",
	"fox_eyes": "여우 눈",
	"lash_eyes": "속눈썹 눈",
}
var _hd_eye_index := 0

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
	_connect_hairstyle_arrows()
	_connect_hd_outfit_arrows()
	_connect_hd_eye_arrows()
	for target in _palette_tabs.keys():
		(_palette_tabs[target] as Button).pressed.connect(_on_palette_tab_pressed.bind(target))


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


## 캐릭터 생성 화면과 달리 디폴트로 리셋하지 않는다 - GameManager에 이미 저장된
## "지금 입고 있는" 외형을 그대로 불러와 편집을 시작한다.
func open() -> void:
	_hairstyle_index = _hd_hairstyle_choices().find(GameManager.hd_hairstyle_id)
	if _hairstyle_index < 0:
		_hairstyle_index = 0
	_hd_outfit_index = _hd_outfit_choices().find(GameManager.hd_outfit_id)
	if _hd_outfit_index < 0:
		_hd_outfit_index = 0
	_hd_eye_index = _hd_eye_choices().find(GameManager.hd_eye_style_id)
	if _hd_eye_index < 0:
		_hd_eye_index = 0
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


## 옷장은 고르는 즉시 GameManager에 반영되지만(주석 상단 참고), 취침/맵 이동
## 때만 자동 저장되던 기존 규칙 그대로면 그 사이에 게임이 꺼질 경우 방금 고른
## 외형이 날아간다 - 옷장을 닫는 시점에도 저장한다(사용자 지시, 2026-09-04 -
## "옷장 닫을 때 플레이어 캐릭터 저장하는 거 있어야 할 거 같아").
func close() -> void:
	SaveManager.save_game(SaveManager.current_slot)
	_set_open(false)


func _on_palette_tab_pressed(target: String) -> void:
	_active_palette_target = target
	_color_picker.color = _get_target_color(target)
	_refresh_pickers()


## ColorPicker에서 색을 고를 때마다(드래그 중엔 여러 번) 바로 반영 - 캐릭터
## 생성 화면과 달리 "확정" 단계가 없어서, 고르는 즉시 GameManager와 미리보기가
## 같이 갱신된다.
func _on_color_picker_color_changed(color: Color) -> void:
	_set_target_color(color)
	_write_target_to_game_manager(_active_palette_target)
	_update_palette_tab_styles()
	_refresh_pickers()
	GameManager.appearance_changed.emit()


## HD 헤어스타일 전용 화살표 - GameManager 필드가
## 숫자 인덱스가 아니라 스타일 이름 문자열이라 별도 함수로 뺐다.
func _connect_hairstyle_arrows() -> void:
	var row := get_node("Panel/Margin/VBox/HBox/LeftColumn/HairstyleRow") as HBoxContainer
	(row.get_node("PrevButton") as TextureButton).pressed.connect(_cycle_hairstyle.bind(-1))
	(row.get_node("NextButton") as TextureButton).pressed.connect(_cycle_hairstyle.bind(1))


func _cycle_hairstyle(direction: int) -> void:
	var choices := _hd_hairstyle_choices()
	_hairstyle_index = wrapi(_hairstyle_index + direction, 0, choices.size())
	GameManager.hd_hairstyle_id = choices[_hairstyle_index]
	_refresh_pickers()
	GameManager.appearance_changed.emit()


## PlayerController.HD_HAIRSTYLES 전체가 아니라 실제로 소유한(기본 7종 +
## 파라의 헤어샵에서 구매한 special_hair) 스타일로만 좁힌다(사용자 지시,
## 2026-09-04) - _hd_outfit_choices()와 동일한 패턴, ShopManager.
## is_hd_hairstyle_unlocked() 참고.
func _hd_hairstyle_choices() -> Array[String]:
	var choices: Array[String] = []
	for style in PlayerController.HD_HAIRSTYLES:
		if ShopManager.is_hd_hairstyle_unlocked(style):
			choices.append(style)
	return choices


## ""(없음)을 맨 앞에 붙인 목록 - player.gd resolve_hd_outfit_sprite_path()가
## ""을 "옷 없음"으로 취급하는 것과 짝을 맞춘다. PlayerController.HD_OUTFITS
## 전체가 아니라 실제로 소유한(기본 두 벌 + 온라인 상점에서 구매한) 스타일로만
## 좁힌다(사용자 지시, 2026-09-03 - "온라인 상점에서 구매해야 해금") -
## ShopManager.is_hd_outfit_unlocked() 참고.
## 헤어/눈과 같은 방식으로 "없음"이 없다(사용자 지시, 2026-09-03 - "옷
## 없음도 못고르게 지워줘") - 소유한 스타일 중에서만 순환한다.
func _hd_outfit_choices() -> Array[String]:
	var choices: Array[String] = []
	for style in PlayerController.HD_OUTFITS:
		if ShopManager.is_hd_outfit_unlocked(style):
			choices.append(style)
	return choices


func _connect_hd_outfit_arrows() -> void:
	var row := get_node("Panel/Margin/VBox/HBox/LeftColumn/HdOutfitRow") as HBoxContainer
	(row.get_node("PrevButton") as TextureButton).pressed.connect(_cycle_hd_outfit.bind(-1))
	(row.get_node("NextButton") as TextureButton).pressed.connect(_cycle_hd_outfit.bind(1))


func _cycle_hd_outfit(direction: int) -> void:
	var choices := _hd_outfit_choices()
	_hd_outfit_index = wrapi(_hd_outfit_index + direction, 0, choices.size())
	GameManager.hd_outfit_id = choices[_hd_outfit_index]
	_refresh_pickers()
	GameManager.appearance_changed.emit()


## 헤어와 같은 방식으로 "없음"이 없다(사용자 지시, 2026-09-03 - "눈 없음은
## 뭐야..? 이런게 있으면 안되지") - 항상 HD_EYE_STYLES 중 하나로만 순환한다.
func _hd_eye_choices() -> Array[String]:
	return PlayerController.HD_EYE_STYLES.duplicate()


func _connect_hd_eye_arrows() -> void:
	var row := get_node("Panel/Margin/VBox/HBox/LeftColumn/EyeRow") as HBoxContainer
	(row.get_node("PrevButton") as TextureButton).pressed.connect(_cycle_hd_eye.bind(-1))
	(row.get_node("NextButton") as TextureButton).pressed.connect(_cycle_hd_eye.bind(1))


func _cycle_hd_eye(direction: int) -> void:
	var choices := _hd_eye_choices()
	_hd_eye_index = wrapi(_hd_eye_index + direction, 0, choices.size())
	GameManager.hd_eye_style_id = choices[_hd_eye_index]
	_refresh_pickers()
	GameManager.appearance_changed.emit()


## 로컬 변수 이름이 전부 "_<target>_color"라 get()으로 읽는다(옷은 더 이상
## 탭이 없어 여기 안 옴 - _outfit_colors는 폴백 미리보기 색상 캐시로만 남음).
func _get_target_color(target: String) -> Color:
	return get("_%s_color" % target)


func _set_target_color(color: Color) -> void:
	set("_%s_color" % _active_palette_target, color)


## 필드 이름이 그대로 대응해 set()으로 쓴다 - 단, 머리는 GameManager에
## "hair_color"라는 필드가 없다(hair_color_1/2/3 3단계뿐, character_creation_screen.gd
## _on_confirm_pressed()와 같은 스키마). 그대로 "%s_color" % "hair"로 쓰면
## 존재하지 않는 필드라 Object.set()이 조용히 아무 일도 안 해서, 옷장 미리보기는
## 로컬 _hair_color로 바로 반영되지만 실제 게임 캐릭터(player.gd가 읽는
## GameManager.hair_color_2)는 절대 안 바뀌는 버그가 있었다(사용자 리포트,
## 2026-09-04 - "거울에선 바뀌는데 실제로 걸을 때 안바뀜"). HD 리컬러
## (recolor_grayscale_to_hue)는 밝기 보존이라 hair_color_1/3(옛 3단계 마커
## 시스템용)은 안 쓰지만, SaveData 구조/구형 폴백 프리뷰 호환을 위해 그대로
## 같이 채워둔다.
func _write_target_to_game_manager(target: String) -> void:
	var color: Color = get("_%s_color" % target)
	if target == "hair":
		GameManager.hair_color_1 = CharacterAppearance.offset_brightness(color, HAIR_LIGHT_DELTA).to_html(false)
		GameManager.hair_color_2 = color.to_html(false)
		GameManager.hair_color_3 = CharacterAppearance.offset_brightness(color, -HAIR_DARK_DELTA).to_html(false)
		return
	GameManager.set("%s_color" % target, color.to_html(false))


func _update_palette_tab_styles() -> void:
	for target in _palette_tabs.keys():
		var button := _palette_tabs[target] as Button
		_set_swatch_style(button, _get_target_color(target), target == _active_palette_target)


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
	var hairstyle_id: String = _hd_hairstyle_choices()[_hairstyle_index]
	_hairstyle_label.text = HAIRSTYLE_LABELS.get(hairstyle_id, hairstyle_id)
	var hd_outfit_id: String = _hd_outfit_choices()[_hd_outfit_index]
	_hd_outfit_label.text = NONE_LABEL if hd_outfit_id == "" else OUTFIT_LABELS.get(hd_outfit_id, hd_outfit_id)
	var hd_eye_id: String = _hd_eye_choices()[_hd_eye_index]
	_eye_label.text = EYE_LABELS.get(hd_eye_id, hd_eye_id)
	_update_palette_tab_styles()
	## 실제 인게임 플레이어가 HD 프로토타입으로 보이는 중이면(player.gd와
	## 같은 판정 기준) 미리보기도 HD로 - 장신구는 아직 HD에 레이어가 없어서
	## 이 모드일 땐 안 보여준다(사용자 지시, 2026-09-02 - 옷장에도 HD 반영).
	## 옷/눈은 player.gd와 같은 별도 오버레이로 같이 그린다(사용자 지시,
	## 2026-09-03 - "그냥 게임에 바로 적용해줘봐", "눈도... 고를수잇게 해줘").
	if ResourceLoader.exists(PlayerController.hd_sprite_path(PlayerController.HD_SPRITE_DEFAULT_STYLE)):
		var hairstyle_sprite_path := PlayerController.resolve_hd_sprite_path(hairstyle_id)
		## 파라의 헤어샵 special_hair는 원본 색 그대로(사용자 지시, 2026-09-04) -
		## player.gd build_hd_composite_texture()와 같은 기준.
		if hairstyle_id in PlayerController.HD_HAIRSTYLES_FIXED_COLOR:
			_preview.set_hd_texture(load(hairstyle_sprite_path))
		else:
			_preview.set_hd_texture(_recolored_hd_texture(hairstyle_sprite_path, _hair_color))
		var outfit_path := PlayerController.resolve_hd_outfit_sprite_path(hd_outfit_id)
		_preview.set_hd_outfit_texture(load(outfit_path) if outfit_path != "" else null)
		var eye_path := PlayerController.resolve_hd_eye_sprite_path(hd_eye_id)
		_preview.set_hd_eye_texture(_recolored_hd_texture(eye_path, _eye_color) if eye_path != "" else null)
	else:
		_preview.set_layers(
			_current_body_texture(),
			_current_outfit_texture(),
			_current_hair_texture(),
			_current_accessory_texture()
		)


## player.gd._build_hd_composite_texture()와 같은 회색조 hue 치환 리컬러를
## 미리보기에도 적용한다(사용자 지시, 2026-09-03 - "고른 색이 머리랑 눈에
## 적용이 안 돼").
func _recolored_hd_texture(path: String, target_color: Color) -> Texture2D:
	var image := (load(path) as Texture2D).get_image()
	CharacterAppearance.recolor_grayscale_to_hue(image, target_color)
	return ImageTexture.create_from_image(image)


func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
	## ColorPicker는 드래그 상태를 자체적으로 들고 있어서 mouse_filter만으로는
	## 안 끊긴다(CLAUDE.md "UI 모달 화면 체크리스트" 6번 참고) - visible도
	## 같이 꺼야 Godot이 그 상태까지 확실히 놓아버린다.
	visible = is_open


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
