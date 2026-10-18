extends Control

## 새 게임 시작 시(슬롯 고른 다음) 뜨는 캐릭터 생성 화면 - 레스토랑 이름/
## 플레이어 이름 입력 + 피부/눈동자/머리/옷/장신구 선택 + 미리보기. 완료하면
## GameManager에 값을 채우고 그 슬롯에 바로 저장한 뒤 confirmed 신호를 낸다
## (title_screen.gd가 그 신호를 받아 main.tscn으로 전환).
##
## 머리/옷/장신구 전부 같은 구조다(사용자 확정: 옷도 "머리랑 동일하게 처리해줘야돼
## 머리스타일이랑 동일하게 스프라이트에 맞게 그려놨어") - 파일 한 장에 여러
## 스타일이 세로로 쌓여있다(사용자 확정: 32px = 16px 두 줄 = 프레임 하나,
## 한 스타일당 가로로 12프레임(192px) - 즉 한 스타일이 192x32 한 "줄"을
## 이루고, 그 줄들이 세로로 쌓여 전체 시트가 된다). 줄 개수는 시트 세로
## 길이를 32로 나눠서 구한다 - 새 스타일을 추가하면 그만큼 줄만 늘어나면
## 되고 코드 변경은 필요 없다. 0번째 줄이 빈 그림인지 여부는 파일마다
## 다르다(실측 확인) - 머리/장신구는 0번째 줄이 빈 그림(머리는 대머리,
## 장신구는 "없음")이지만, 옷은 0번째 줄부터 이미 실제로 그려진 스타일이라
## "없음" 개념 자체가 없다(모든 줄이 유효한 스타일).
##
## 색은 고정 스와치 12개(SWATCH_COLORS) 중에서만 고른다(사용자 확정, 2026-08-09:
## "색깔 고르는 것도 팔레트 아니고 내가 제공한 컬러중에서만 고르게 해줘") -
## 이전엔 색상환(HueStrip+SVSquare)으로 자유롭게 골랐었는데, 자유도가 너무
## 높으면 오히려 조합이 이상해지기 쉽다는 사용자 판단으로 교체함(이 화면의
## 색 편집 UI가 이번 세션에만 4번 바뀐 이력 - 앞으로도 바뀔 수 있음을 염두에
## 둘 것). 편집 대상(피부/눈동자/머리/뺨/옷1/옷2/옷3/악세서리 - 총 8개)을
## 작은 스와치 탭으로 전환하며 쓰는 방식은 그대로 유지.
##
## 피부색은 원본에 명도 3단계 마커가 그려져 있어서(SKIN_MARKER_COLORS) 스와치에서
## 고른 색을 "기준색"(중간 톤) 삼아 SKIN_LIGHT_DELTA/SKIN_DARK_DELTA를 더하고
## 빼서 밝음/어둠 톤을 자동 계산한다. 머리도 같은 방식으로 바뀜(사용자 확정,
## 2026-08-09: "머리도 피부처럼 그냥 색 하나 고르면 음영 계산해서 자동으로 색
## 채워주고") - 예전엔 마커 3단계(HAIR_MARKER_COLORS)를 독립적으로 골랐는데
## "3개 다 고르니까 조합이 이상하게 나온다"는 피드백으로 변경. 저장 스키마는
## 그대로(hair_color_1/2/3 3개 다 저장) - 1개 기준색에서 계산한 최종 3색을
## 저장할 뿐이라 SaveData 구조 변경은 아님. 눈동자/뺨/악세서리는 마커가
## 하나뿐이라(예: EYE_MARKER_COLOR) 고른 색을 그대로 치환한다. 옷만 유일하게
## 예외로 3색을 각각 독립적으로 고른다(사용자 확정: "옷 컬러 고를 때만
## 예외적으로 색깔 3개 고르게 해줘") - player_outfit.png를 새로 그리면서
## 마커도 피부와 같은 3단계(D6D6D6/A8A8A8/727272)로 바뀜.
##
## 파일 규격(사용자에게 안내할 것): 몸/옷은 res://assets/player/body|outfit/
## 에 16x32 프레임 12장(가로로 이어붙임, 192x32) - npc_sprite.gd와 동일한
## 프레임 순서. 머리/장신구는 위 설명대로 192x32짜리 "줄"이 여러 개 쌓인
## 시트(192xN*32) - 이 화면 미리보기는 그 중 "앞"(0번, x=0) 프레임만 쓴다.
##
## 신발은 더 이상 별도 선택 항목이 아니다(사용자 지시, 2026-08-10) - outfit
## 그림에 이미 신발이 함께 그려져 있어서, 예전처럼 신발 레이어를 따로
## 합성하면 새로 그린 신발을 덮어씌워버린다. 신발 스타일/색 선택 UI와
## player_shoes.png 관련 로직은 전부 제거됨(GameManager.shoe_id/shoe_color
## 필드 자체는 SaveData 구조라 그대로 남아있지만 더 이상 이 화면에서 쓰지
## 않음).

const UIUtil := preload("res://scripts/ui/ui_util.gd")

signal confirmed

const BODY_PATH := "res://assets/player/body/player_body.png"
const HAIR_SHEET_PATH := "res://assets/player/hair/player_hair.png"
## 옷도 헤어와 같은 방식(사용자 확정: "머리랑 동일하게 처리해줘야돼") - 폴더
## 스캔이 아니라 파일 하나에 스타일이 여러 줄.
const OUTFIT_SHEET_PATH := "res://assets/player/outfit/player_outfit.png"
## 장신구도 폴더 스캔이 아니라 헤어와 같은 방식(사용자 확정: "하나의 그림에
## 여러개 그려뒀고 양식은 머리와 같아") - 파일 하나에 스타일이 여러 줄.
const ACCESSORY_SHEET_PATH := "res://assets/player/accessory/player_accessory.png"
const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
const NONE_LABEL := "없음"

## 사용자가 제공한 고정 팔레트(사용자 확정, 2026-08-09 12색 + 피부톤 3색 추가) -
## 모든 색 선택 대상(피부/눈동자/머리/뺨/옷1~3/신발/악세서리) 공통으로 이 안에서만
## 고른다. 이름은 주석용(코드에서 참조 안 함) - 순서가 SwatchRow의 Swatch0~14
## 노드 순서와 정확히 일치해야 한다.
const SWATCH_COLORS: Array[Color] = [
	Color("d95763"), # 빨강
	Color("e78a42"), # 주황
	Color("e8c84d"), # 노랑
	Color("8fcf59"), # 연두
	Color("58a45c"), # 초록
	Color("6fd4c2"), # 민트
	Color("67b7f3"), # 하늘
	Color("4f78d9"), # 파랑
	Color("8c72d8"), # 보라
	Color("f08ab5"), # 분홍
	Color("8a5c3b"), # 갈색
	Color("8d929c"), # 회색
	Color("f8e7da"), # 피부(밝음)
	Color("e3b18e"), # 피부(중간)
	Color("2f211a"), # 피부(어둠)
]

## 사용자가 player_hair.png 원본에 그려둔 표식 색(사용자 확정 - 색1/색2/색3
## 순서 그대로) - 리컬러 대상 판정에만 쓴다(정확히 이 색과 일치하는 픽셀만
## 바뀜).
const HAIR_MARKER_COLORS: Array[Color] = [
	Color(0xD8 / 255.0, 0xD8 / 255.0, 0xD8 / 255.0),
	Color(0x9A / 255.0, 0x9A / 255.0, 0x9A / 255.0),
	Color(0x56 / 255.0, 0x56 / 255.0, 0x56 / 255.0),
]
## 마커 간 실제 명도 차이(원본에서 그대로 측정: D8D8D8와 9A9A9A, 9A9A9A와
## 565656의 채널별 차이) - SKIN_LIGHT_DELTA/SKIN_DARK_DELTA와 동일한 원리로,
## 스와치에서 고른 "기준색"(=중간 톤) 하나에 이 차이를 더하고 빼서 밝음/어둠
## 톤을 자동 계산한다(사용자 확정, 2026-08-09).
const HAIR_LIGHT_DELTA := 62.0 / 255.0
const HAIR_DARK_DELTA := 68.0 / 255.0

## 사용자 확정 기본값(2026-08-07) - 머리 기준색(중간 톤). 갈색 계열.
const HAIR_DEFAULT_COLOR := Color(0x8A / 255.0, 0x5C / 255.0, 0x3B / 255.0)

## player_body.png에 그려둔 명도 3단계 마커(헤어와 값이 다름 - 실측 확인함).
## 순서는 [밝음, 중간, 어둠].
const SKIN_MARKER_COLORS: Array[Color] = [
	Color(0xD6 / 255.0, 0xD6 / 255.0, 0xD6 / 255.0),
	Color(0xA8 / 255.0, 0xA8 / 255.0, 0xA8 / 255.0),
	Color(0x72 / 255.0, 0x72 / 255.0, 0x72 / 255.0),
]
## 마커 간 실제 명도 차이(원본에서 그대로 측정: D6D6D6와 A8A8A8, A8A8A8와
## 727272의 채널별 차이). 사용자 확정 - 스와치에서 고른 "기준색"(=중간 톤)
## 하나에 이 차이를 그대로 더하고 빼서 밝음/어둠 톤을 자동 계산한다.
const SKIN_LIGHT_DELTA := 46.0 / 255.0
const SKIN_DARK_DELTA := 54.0 / 255.0

## 사용자 확정 기본값(2026-08-07): "기본 색으로 #F8E7DA 이거 설정해두고".
const SKIN_DEFAULT_COLOR := Color(0xF8 / 255.0, 0xE7 / 255.0, 0xDA / 255.0)

## player_body.png의 눈 마커(#FF00FF) - 명암 단계 없이 단일 색이라(실측 확인:
## 표식이 한 종류뿐) 밝음/어둠 계산 없이 바로 치환한다.
const EYE_MARKER_COLOR := Color(1.0, 0.0, 1.0)

## 사용자 확정 기본값(2026-08-07): "눈동자는 기본으로 38B57A 이거 해두고".
const EYE_DEFAULT_COLOR := Color(0x38 / 255.0, 0xB5 / 255.0, 0x7A / 255.0)

## player_body.png의 볼터치 마커(#00FF66) - 눈과 같은 이유로 단일 색 치환.
const CHEEK_MARKER_COLOR := Color(0.0, 1.0, 0x66 / 255.0)
## 실제 기획 값을 받기 전 임시 기본값(옅은 분홍) - 스와치로 바로 고쳐 고를
## 수 있으니 피부/눈동자/머리 기본값만큼 정확할 필요는 없음.
const CHEEK_DEFAULT_COLOR := Color(0xF4 / 255.0, 0xA6 / 255.0, 0xB3 / 255.0)

## player_outfit.png를 사용자가 새로 그리면서 마커도 피부와 같은 명도 3단계
## 구조(D6D6D6/A8A8A8/727272)로 바뀜(사용자 지시, 2026-08-09). 옷은 유일하게
## 3색을 각각 독립적으로 고른다(자동 음영 계산 없음, 사용자 확정) - "상의"/
## "하의"/"신발"(2026-08-25 이전엔 "포인트"였음)이라는 이름표가 실제 그림 속
## 부위와 정확히 대응하는 건 아니고 이 마커 3개에 붙인 이름표다.
const OUTFIT_MARKER_COLORS: Array[Color] = [
	Color(0xD6 / 255.0, 0xD6 / 255.0, 0xD6 / 255.0),
	Color(0xA8 / 255.0, 0xA8 / 255.0, 0xA8 / 255.0),
	Color(0x72 / 255.0, 0x72 / 255.0, 0x72 / 255.0),
]
## 사용자 확정 기본값(2026-08-08 상의/하의 2색 → 2026-08-09 포인트색 추가).
const OUTFIT_DEFAULT_COLORS: Array[Color] = [
	Color(0x6F / 255.0, 0x9B / 255.0, 0x5A / 255.0),
	Color(0x56 / 255.0, 0x73 / 255.0, 0xA8 / 255.0),
	Color(0x8A / 255.0, 0x5C / 255.0, 0x3B / 255.0),
]

## player_accessory.png에 그려진 명도 마커(실측 확인 - 딱 1가지, #9A9A9A).
const ACCESSORY_MARKER_COLOR := Color(0x9A / 255.0, 0x9A / 255.0, 0x9A / 255.0)
## 사용자 확정 기본값(2026-08-08): 악세서리 #D2A94A.
const ACCESSORY_DEFAULT_COLOR := Color(0xD2 / 255.0, 0xA9 / 255.0, 0x4A / 255.0)

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

@onready var _restaurant_name_edit: LineEdit = $Panel/Margin/VBox/HBox/RightColumn/RestaurantRow/RestaurantNameEdit
@onready var _player_name_edit: LineEdit = $Panel/Margin/VBox/HBox/RightColumn/PlayerRow/PlayerNameEdit
@onready var _preview: Control = $Panel/Margin/VBox/HBox/LeftColumn/Preview
## 사용자 확정(2026-08-07): 활성 대상 하나만 라벨로 알려주는 대신, 각 스와치
## 위에 이름을 항상 고정으로 보여준다. 머리가 3톤에서 1개로 줄면서(2026-08-09)
## 9개로 재구성됐다가, 신발 선택 제거로(2026-08-10) 8개(피부/눈동자/머리/뺨/
## 옷1/옷2/옷3/악세서리)가 됨.
## 피부/뺨/옷/악세서리 색은 HD 모드에서 안 보여서 탭에서 뺐다(사용자 지시,
## 2026-09-03 - "이젠 머리색이랑 눈색만 고를 수 잇으면 돼. 다른 색은 필요
## 없어.") - 그 값들은 _on_confirm_pressed()에서 기본값으로 고정 저장된다
## (SaveData 필드 자체는 그대로 유지).
@onready var _palette_tabs: Dictionary = {
	"eye": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/EyeCol/EyeTab,
	"hair": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/HairCol/HairTab,
}
## SWATCH_COLORS와 순서가 정확히 같은 12개 버튼(SwatchRow의 Swatch0~11) -
## get_children()로 한 번에 가져와서 인덱스로 SWATCH_COLORS와 짝짓는다.
@onready var _swatch_row: GridContainer = $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/SwatchRow
## HD 헤어스타일/눈/옷 선택(wardrobe_screen.gd와 같은 구조) - 사용자 지시,
## 2026-09-03 "고르는 거에 헤어, 눈, 옷 이렇게 3개 추가해줘".
@onready var _hairstyle_label: Label = $Panel/Margin/VBox/HBox/RightColumn/HairstyleRow/HairstyleLabel
@onready var _eye_label: Label = $Panel/Margin/VBox/HBox/RightColumn/EyeRow/EyeLabel
@onready var _hd_outfit_label: Label = $Panel/Margin/VBox/HBox/RightColumn/HdOutfitRow/HdOutfitLabel
@onready var _message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var _back_button: Button = $Panel/Margin/VBox/BottomRow/BackButton
@onready var _confirm_button: Button = $Panel/Margin/VBox/BottomRow/ConfirmButton

var _slot := 1
## 이 화면에서 더 이상 고를 수 없다(사용자 지시, 2026-09-03 - "고르는 거에
## 헤어, 눈, 옷 이렇게 3개 추가해줘", HD 피커로 대체됨) - GameManager.outfit_id/
## accessory_id에 쓸 고정값 캐시로만 남는다(SaveData 필드 유지 목적).
var _outfit_index := 0
var _accessory_index := 0

## 스킨/뺨/옷 색은 더 이상 고를 수 없다(사용자 지시, 2026-09-03 - "다른 색은
## 필요 없어") - 항상 기본값으로 저장된다(SaveData 필드 유지 목적).
var _skin_color := SKIN_DEFAULT_COLOR
var _eye_color := EYE_DEFAULT_COLOR
var _cheek_color := CHEEK_DEFAULT_COLOR
var _outfit_colors: Array[Color] = OUTFIT_DEFAULT_COLORS.duplicate()
var _accessory_color := ACCESSORY_DEFAULT_COLOR
## 지금 스와치 목록이 어느 대상을 편집 중인지 - _palette_tabs의 키("hair"/"eye"만 유효).
var _active_palette_target := "hair"

## HD 헤어스타일/눈/옷 선택 - wardrobe_screen.gd와 완전히 같은 구조/이름표
## (중복 관리 방지를 위해 나중에 공용화 가능하지만, 지금은 두 파일 다 같이
## 갱신해야 하는 중복 상수).
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
const EYE_LABELS := {
	"anime_eyes": "애니메 눈",
	"droopy_eyes": "처진 눈",
	"fox_eyes": "여우 눈",
	"lash_eyes": "속눈썹 눈",
}
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
var _hairstyle_index := 0
var _hd_eye_index := 0
var _hd_outfit_index := 0

## 몸/머리 원본 시트를 픽셀 단위로 만질 수 있는 Image로 한 번만 읽어둔다
## (Texture2D는 GPU 쪽이라 픽셀을 직접 못 바꾼다 - get_image()로 CPU
## 이미지를 얻어야 리컬러가 가능하다).
var _body_sheet_image: Image = null
var _outfit_sheet_image: Image = null
var _outfit_row_count := 0
var _hair_sheet_image: Image = null
var _hair_row_count := 0
var _hair_index := 0
## 머리 기준색(중간 톤) - 밝음/어둠은 HAIR_LIGHT_DELTA/HAIR_DARK_DELTA로 매번
## 계산한다(피부와 동일한 방식, 사용자 확정 2026-08-09).
var _hair_color := HAIR_DEFAULT_COLOR
var _accessory_sheet_image: Image = null
var _accessory_row_count := 0


var _is_open := false


func _ready() -> void:
	_set_open(false)
	_load_body_sheet()
	_load_outfit_sheet()
	_load_hair_sheet()
	_load_accessory_sheet()
	for button in [_back_button, _confirm_button]:
		_style_button(button)
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_connect_hairstyle_arrows()
	_connect_hd_eye_arrows()
	_connect_hd_outfit_arrows()
	for target in _palette_tabs.keys():
		(_palette_tabs[target] as Button).pressed.connect(_on_palette_tab_pressed.bind(target))
	var swatch_buttons := _swatch_row.get_children()
	for i in mini(swatch_buttons.size(), SWATCH_COLORS.size()):
		var swatch_button := swatch_buttons[i] as Button
		_set_swatch_style(swatch_button, SWATCH_COLORS[i], false)
		swatch_button.pressed.connect(_on_swatch_pressed.bind(SWATCH_COLORS[i]))


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_back_pressed()


## slot_picker_screen.gd와 동일한 이유/동일한 수정(사용자 리포트, 2026-08-26) -
## 이 화면의 루트도 원래 전체화면(anchor 0/0/1/1)이라 PRESET_FULL_RECT 재적용이
## 안전하고, 실제로 이 방식이어야 익스포트 빌드에서 고쳐졌다.
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func open(slot: int) -> void:
	_slot = slot
	_restaurant_name_edit.text = ""
	_player_name_edit.text = ""
	_message_label.text = ""
	_hair_index = 1 if _hair_row_count > 1 else 0
	## 옷은 0번째 줄부터 이미 실제 스타일이라(머리/장신구와 달리 빈 그림이
	## 아님) 그냥 0번으로 시작하면 된다 - 건너뛸 "없음"이 없다.
	_outfit_index = 0
	## 사용자 확정: 머리/옷은 "없음"을 없애고 항상 첫 번째 값을 기본으로
	## 끼운다. 장신구만 유일하게 "없음"이 유효한 선택이라 0번(빈 그림)으로
	## 시작한다(헤어 시트와 같은 구조 - 0번이 곧 "없음"). 피부/눈동자는
	## 애초에 "없음"이 없는 상태(스와치 - 항상 뭔가 색이 정해져 있음)라
	## 별도 처리가 필요 없다.
	_accessory_index = 0
	_hair_color = HAIR_DEFAULT_COLOR
	_skin_color = SKIN_DEFAULT_COLOR
	_eye_color = EYE_DEFAULT_COLOR
	_cheek_color = CHEEK_DEFAULT_COLOR
	_outfit_colors = OUTFIT_DEFAULT_COLORS.duplicate()
	_accessory_color = ACCESSORY_DEFAULT_COLOR
	_active_palette_target = "hair"
	_hairstyle_index = _hd_hairstyle_choices().find(GameManager.hd_hairstyle_id)
	if _hairstyle_index < 0:
		_hairstyle_index = 0
	_hd_eye_index = _hd_eye_choices().find(GameManager.hd_eye_style_id)
	if _hd_eye_index < 0:
		_hd_eye_index = 0
	_hd_outfit_index = _hd_outfit_choices().find(GameManager.hd_outfit_id)
	if _hd_outfit_index < 0:
		_hd_outfit_index = 0
	_update_palette_tab_styles()
	_refresh_pickers()
	_set_open(true)


func _on_back_pressed() -> void:
	_set_open(false)


func _on_confirm_pressed() -> void:
	var restaurant_name := _restaurant_name_edit.text.strip_edges()
	var player_name := _player_name_edit.text.strip_edges()
	if restaurant_name.is_empty():
		_message_label.text = "레스토랑 이름을 입력해주세요."
		return
	if player_name.is_empty():
		_message_label.text = "이름을 입력해주세요."
		return
	GameManager.player_name = player_name
	GameManager.restaurant_name = restaurant_name
	GameManager.skin_color = _skin_color.to_html(false)
	GameManager.eye_color = _eye_color.to_html(false)
	GameManager.cheek_color = _cheek_color.to_html(false)
	GameManager.hair_id = str(_hair_index)
	## 저장 스키마는 그대로 3색(hair_color_1/2/3) - 기준색 하나에서 계산한
	## 최종 밝음/어둠 톤을 그때그때 구해서 저장할 뿐이다(SaveData 구조 변경 아님).
	GameManager.hair_color_1 = CharacterAppearance.offset_brightness(_hair_color, HAIR_LIGHT_DELTA).to_html(false)
	GameManager.hair_color_2 = _hair_color.to_html(false)
	GameManager.hair_color_3 = CharacterAppearance.offset_brightness(_hair_color, -HAIR_DARK_DELTA).to_html(false)
	GameManager.outfit_color_1 = _outfit_colors[0].to_html(false)
	GameManager.outfit_color_2 = _outfit_colors[1].to_html(false)
	GameManager.outfit_color_3 = _outfit_colors[2].to_html(false)
	GameManager.accessory_color = _accessory_color.to_html(false)
	GameManager.outfit_id = str(_outfit_index)
	GameManager.accessory_id = str(_accessory_index)
	GameManager.hd_hairstyle_id = _hd_hairstyle_choices()[_hairstyle_index]
	GameManager.hd_eye_style_id = _hd_eye_choices()[_hd_eye_index]
	GameManager.hd_outfit_id = _hd_outfit_choices()[_hd_outfit_index]
	## 신규 게임 확정 시점에만 지나므로, 이 슬롯은 아직 튜토리얼 컷신을 못 본
	## 상태로 명시적으로 표시한다(main.gd._maybe_play_tutorial_intro() 참고).
	GameManager.tutorial_intro_shown = false
	SaveManager.set_current_slot(_slot)
	SaveManager.save_game(_slot)
	_set_open(false)
	confirmed.emit()


## wardrobe_screen.gd의 _connect_hairstyle_arrows()/_cycle_hairstyle()와 완전히
## 같은 구조 - HD_HAIRSTYLES를 순환하며 GameManager.hd_hairstyle_id를 바로 쓴다.
func _connect_hairstyle_arrows() -> void:
	var row := get_node("Panel/Margin/VBox/HBox/RightColumn/HairstyleRow") as HBoxContainer
	(row.get_node("PrevButton") as TextureButton).pressed.connect(_cycle_hairstyle.bind(-1))
	(row.get_node("NextButton") as TextureButton).pressed.connect(_cycle_hairstyle.bind(1))


func _cycle_hairstyle(direction: int) -> void:
	var choices := _hd_hairstyle_choices()
	_hairstyle_index = wrapi(_hairstyle_index + direction, 0, choices.size())
	_refresh_pickers()


## wardrobe_screen.gd의 _hd_hairstyle_choices()와 완전히 같은 구조 - 소유한
## 헤어스타일로만 좁힌다(ShopManager.is_hd_hairstyle_unlocked() 참고).
func _hd_hairstyle_choices() -> Array[String]:
	var choices: Array[String] = []
	for style in PlayerController.HD_HAIRSTYLES:
		if ShopManager.is_hd_hairstyle_unlocked(style):
			choices.append(style)
	return choices


## 헤어와 같은 방식으로 "없음"이 없다(사용자 지시, 2026-09-03 - "눈 없음은
## 뭐야..? 이런게 있으면 안되지") - 항상 HD_EYE_STYLES 중 하나로만 순환한다.
func _hd_eye_choices() -> Array[String]:
	return PlayerController.HD_EYE_STYLES.duplicate()


func _connect_hd_eye_arrows() -> void:
	var row := get_node("Panel/Margin/VBox/HBox/RightColumn/EyeRow") as HBoxContainer
	(row.get_node("PrevButton") as TextureButton).pressed.connect(_cycle_hd_eye.bind(-1))
	(row.get_node("NextButton") as TextureButton).pressed.connect(_cycle_hd_eye.bind(1))


func _cycle_hd_eye(direction: int) -> void:
	var choices := _hd_eye_choices()
	_hd_eye_index = wrapi(_hd_eye_index + direction, 0, choices.size())
	_refresh_pickers()


## wardrobe_screen.gd의 같은 이름 함수와 동일 - 소유한 스타일로만 좁힌다.
## 새 캐릭터 생성 시점엔 아직 아무것도 못 샀을 테니 사실상 항상 기본 두 벌만
## 나온다.
func _hd_outfit_choices() -> Array[String]:
	var choices: Array[String] = []
	for style in PlayerController.HD_OUTFITS:
		if ShopManager.is_hd_outfit_unlocked(style):
			choices.append(style)
	return choices


func _connect_hd_outfit_arrows() -> void:
	var row := get_node("Panel/Margin/VBox/HBox/RightColumn/HdOutfitRow") as HBoxContainer
	(row.get_node("PrevButton") as TextureButton).pressed.connect(_cycle_hd_outfit.bind(-1))
	(row.get_node("NextButton") as TextureButton).pressed.connect(_cycle_hd_outfit.bind(1))


func _cycle_hd_outfit(direction: int) -> void:
	var choices := _hd_outfit_choices()
	_hd_outfit_index = wrapi(_hd_outfit_index + direction, 0, choices.size())
	_refresh_pickers()


## 탭 9개(피부/눈동자/머리/뺨/옷1/옷2/옷3/신발/악세서리) 중 하나를 눌러
## 스와치 목록이 어느 걸 편집 중인지 바꾼다.
func _on_palette_tab_pressed(target: String) -> void:
	_active_palette_target = target
	_update_palette_tab_styles()


## 스와치 버튼을 누르면 지금 활성 대상(_active_palette_target)의 색을 그
## 스와치 색으로 바로 바꾼다 - 색상환처럼 위치 계산이 필요 없다.
func _on_swatch_pressed(color: Color) -> void:
	_set_target_color(color)
	_update_palette_tab_styles()
	_refresh_pickers()


## target이 가리키는 실제 Color 변수를 읽는다 - 이제 "hair"/"eye" 둘뿐이다
## (사용자 지시, 2026-09-03 - "머리색이랑 눈색만 고를 수 잇으면 돼").
func _get_target_color(target: String) -> Color:
	match target:
		"eye":
			return _eye_color
		"hair":
			return _hair_color
	return Color.WHITE


func _set_target_color(color: Color) -> void:
	match _active_palette_target:
		"eye":
			_eye_color = color
		"hair":
			_hair_color = color


## 탭 2개(눈동자/머리) 배경을 각각의 지금 색으로 칠해서 어느 탭이 활성인지
## (테두리 두께) + 지금 그 색이 뭔지를 동시에 보여준다. 머리 탭은 머리가
## 대머리(0번)일 때 비활성화한다 - 리컬러할 마커 픽셀 자체가 안 그려지기 때문.
func _update_palette_tab_styles() -> void:
	for target in _palette_tabs.keys():
		var button := _palette_tabs[target] as Button
		_set_swatch_style(button, _get_target_color(target), target == _active_palette_target)
		button.disabled = target == "hair" and _hair_index == 0


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


func _refresh_pickers() -> void:
	_update_palette_tab_styles()
	var hairstyle_id: String = _hd_hairstyle_choices()[_hairstyle_index]
	_hairstyle_label.text = HAIRSTYLE_LABELS.get(hairstyle_id, hairstyle_id)
	var hd_eye_id: String = _hd_eye_choices()[_hd_eye_index]
	_eye_label.text = EYE_LABELS.get(hd_eye_id, hd_eye_id)
	var hd_outfit_id: String = _hd_outfit_choices()[_hd_outfit_index]
	_hd_outfit_label.text = NONE_LABEL if hd_outfit_id == "" else OUTFIT_LABELS.get(hd_outfit_id, hd_outfit_id)
	## wardrobe_screen.gd와 같은 기준 - HD 시트가 있으면 미리보기도 HD로
	## (사용자 지시, 2026-09-03 - "예전 플레이어 스프라이트가 그대로 나오고
	## 잇어" - 이 화면이 여태 구형 4레이어 합성만 그리고 있던 버그).
	if ResourceLoader.exists(PlayerController.hd_sprite_path(PlayerController.HD_SPRITE_DEFAULT_STYLE)):
		var hairstyle_sprite_path := PlayerController.resolve_hd_sprite_path(hairstyle_id)
		## 파라의 헤어샵 special_hair는 원본 색 그대로(사용자 지시, 2026-09-04) -
		## wardrobe_screen.gd/player.gd와 같은 기준.
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


## wardrobe_screen.gd의 같은 이름 함수와 동일 - player.gd._build_hd_composite_texture()와
## 같은 회색조 hue 치환 리컬러를 미리보기에도 적용한다(사용자 지시, 2026-09-03 -
## "고른 색이 머리랑 눈에 적용이 안 돼").
func _recolored_hd_texture(path: String, target_color: Color) -> Texture2D:
	var image := (load(path) as Texture2D).get_image()
	CharacterAppearance.recolor_grayscale_to_hue(image, target_color)
	return ImageTexture.create_from_image(image)


func _load_body_sheet() -> void:
	if not ResourceLoader.exists(BODY_PATH):
		return
	var sheet := load(BODY_PATH) as Texture2D
	if sheet == null:
		return
	_body_sheet_image = sheet.get_image()


func _load_outfit_sheet() -> void:
	if not ResourceLoader.exists(OUTFIT_SHEET_PATH):
		return
	var sheet := load(OUTFIT_SHEET_PATH) as Texture2D
	if sheet == null:
		return
	_outfit_sheet_image = sheet.get_image()
	_outfit_row_count = maxi(_outfit_sheet_image.get_height() / FRAME_HEIGHT, 1)


func _load_hair_sheet() -> void:
	if not ResourceLoader.exists(HAIR_SHEET_PATH):
		return
	var sheet := load(HAIR_SHEET_PATH) as Texture2D
	if sheet == null:
		return
	_hair_sheet_image = sheet.get_image()
	_hair_row_count = maxi(_hair_sheet_image.get_height() / FRAME_HEIGHT, 1)


func _load_accessory_sheet() -> void:
	if not ResourceLoader.exists(ACCESSORY_SHEET_PATH):
		return
	var sheet := load(ACCESSORY_SHEET_PATH) as Texture2D
	if sheet == null:
		return
	_accessory_sheet_image = sheet.get_image()
	_accessory_row_count = maxi(_accessory_sheet_image.get_height() / FRAME_HEIGHT, 1)


## 지금 고른 피부색/눈동자색/볼터치색으로 리컬러한 몸 "앞" 프레임을 돌려준다.
func _current_body_texture() -> Texture2D:
	if _body_sheet_image == null:
		return null
	var region := Rect2i(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
	var frame_image := _body_sheet_image.get_region(region)
	var skin_palette: Array[Color] = [
		CharacterAppearance.offset_brightness(_skin_color, SKIN_LIGHT_DELTA),
		_skin_color,
		CharacterAppearance.offset_brightness(_skin_color, -SKIN_DARK_DELTA),
	]
	CharacterAppearance.recolor_image(frame_image, SKIN_MARKER_COLORS, skin_palette)
	var eye_markers: Array[Color] = [EYE_MARKER_COLOR]
	var eye_palette: Array[Color] = [_eye_color]
	CharacterAppearance.recolor_image(frame_image, eye_markers, eye_palette)
	var cheek_markers: Array[Color] = [CHEEK_MARKER_COLOR]
	var cheek_palette: Array[Color] = [_cheek_color]
	CharacterAppearance.recolor_image(frame_image, cheek_markers, cheek_palette)
	return ImageTexture.create_from_image(frame_image)


## 지금 고른 옷 스타일 줄의 "앞" 프레임을 색1/색2/색3으로 리컬러해서 돌려준다 -
## 헤어/장신구와 같은 구조(_outfit_sheet_image에 미리 읽어둔 시트에서
## _outfit_index번째 줄을 자른다). 0번줄부터 실제 스타일이라 헤어처럼
## "빈 그림이면 null" 처리가 필요 없다.
func _current_outfit_texture() -> Texture2D:
	if _outfit_sheet_image == null:
		return null
	var region := Rect2i(0, _outfit_index * FRAME_HEIGHT, FRAME_WIDTH, FRAME_HEIGHT)
	if region.position.y + region.size.y > _outfit_sheet_image.get_height():
		return null
	var frame_image := _outfit_sheet_image.get_region(region)
	CharacterAppearance.recolor_image(frame_image, OUTFIT_MARKER_COLORS, _outfit_colors)
	return ImageTexture.create_from_image(frame_image)


## 0번(대머리)이면 null(레이어 없음). 그 외엔 그 줄의 "앞" 프레임(0번 열)만
## 잘라서, 기준색(_hair_color)에서 자동 계산한 밝음/어둠 톤으로 리컬러한 뒤
## 텍스처로 만들어 돌려준다(피부와 동일한 방식, 사용자 확정 2026-08-09).
func _current_hair_texture() -> Texture2D:
	if _hair_sheet_image == null or _hair_index <= 0:
		return null
	var region := Rect2i(0, _hair_index * FRAME_HEIGHT, FRAME_WIDTH, FRAME_HEIGHT)
	if region.position.y + region.size.y > _hair_sheet_image.get_height():
		return null
	var frame_image := _hair_sheet_image.get_region(region)
	var hair_palette: Array[Color] = [
		CharacterAppearance.offset_brightness(_hair_color, HAIR_LIGHT_DELTA),
		_hair_color,
		CharacterAppearance.offset_brightness(_hair_color, -HAIR_DARK_DELTA),
	]
	CharacterAppearance.recolor_image(frame_image, HAIR_MARKER_COLORS, hair_palette)
	return ImageTexture.create_from_image(frame_image)


## 0번(없음)이면 null(레이어 없음) - 헤어와 똑같은 구조. 그 외엔 그 줄의
## "앞" 프레임을 잘라서 고른 색으로 리컬러한 뒤 텍스처로 만들어 돌려준다.
func _current_accessory_texture() -> Texture2D:
	if _accessory_sheet_image == null or _accessory_index <= 0:
		return null
	var region := Rect2i(0, _accessory_index * FRAME_HEIGHT, FRAME_WIDTH, FRAME_HEIGHT)
	if region.position.y + region.size.y > _accessory_sheet_image.get_height():
		return null
	var frame_image := _accessory_sheet_image.get_region(region)
	var markers: Array[Color] = [ACCESSORY_MARKER_COLOR]
	var palette: Array[Color] = [_accessory_color]
	CharacterAppearance.recolor_image(frame_image, markers, palette)
	return ImageTexture.create_from_image(frame_image)


func _connect_arrows(row_path: String, method_name: String) -> void:
	var row := get_node(row_path) as HBoxContainer
	var prev_button := row.get_node("PrevButton") as TextureButton
	var next_button := row.get_node("NextButton") as TextureButton
	prev_button.pressed.connect(func() -> void: call(method_name, -1))
	next_button.pressed.connect(func() -> void: call(method_name, 1))


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
