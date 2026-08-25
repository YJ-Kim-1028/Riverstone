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
@onready var _palette_tabs: Dictionary = {
	"skin": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/SkinCol/SkinTab,
	"eye": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/EyeCol/EyeTab,
	"hair": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/HairCol/HairTab,
	"cheek": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/CheekCol/CheekTab,
	"outfit_1": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/Outfit1Col/Outfit1Tab,
	"outfit_2": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/Outfit2Col/Outfit2Tab,
	"outfit_3": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/Outfit3Col/Outfit3Tab,
	"accessory": $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/TabRow/AccessoryColorCol/AccessoryColorTab,
}
## SWATCH_COLORS와 순서가 정확히 같은 12개 버튼(SwatchRow의 Swatch0~11) -
## get_children()로 한 번에 가져와서 인덱스로 SWATCH_COLORS와 짝짓는다.
@onready var _swatch_row: GridContainer = $Panel/Margin/VBox/HBox/LeftColumn/SkinEyePalette/SwatchRow
@onready var _hair_label: Label = $Panel/Margin/VBox/HBox/RightColumn/HairRow/HairLabel
@onready var _outfit_label: Label = $Panel/Margin/VBox/HBox/RightColumn/OutfitRow/OutfitLabel
@onready var _accessory_label: Label = $Panel/Margin/VBox/HBox/RightColumn/AccessoryRow/AccessoryLabel
@onready var _message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var _back_button: Button = $Panel/Margin/VBox/BottomRow/BackButton
@onready var _confirm_button: Button = $Panel/Margin/VBox/BottomRow/ConfirmButton

var _slot := 1
## 헤어와 같은 방식(사용자 확정: "머리랑 동일하게 처리해줘야돼") - 0번줄부터
## 이미 실제 스타일이라("없음" 개념 없음) 더 이상 폴더 스캔 인덱스가 아니다.
var _outfit_index := 0
## 헤어와 같은 방식으로 바뀜(0=없음/빈 그림, 1부터 실제 스타일) - 더 이상
## 폴더 스캔 인덱스가 아니다.
var _accessory_index := 0

var _skin_color := SKIN_DEFAULT_COLOR
var _eye_color := EYE_DEFAULT_COLOR
var _cheek_color := CHEEK_DEFAULT_COLOR
## 인덱스 0/1/2 = 색1(마커 D6D6D6)/색2(마커 A8A8A8)/색3(마커 727272) - 이름은
## "상의"/"하의"/"신발"이지만 실제로는 그림 속 부위가 아니라 마커 3개에 붙인
## 이름표일 뿐(사용자 확정, OUTFIT_MARKER_COLORS 주석 참고).
var _outfit_colors: Array[Color] = OUTFIT_DEFAULT_COLORS.duplicate()
var _accessory_color := ACCESSORY_DEFAULT_COLOR
## 지금 스와치 목록이 어느 대상을 편집 중인지 - _palette_tabs의 키.
var _active_palette_target := "skin"

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


func _ready() -> void:
	visible = false
	_load_body_sheet()
	_load_outfit_sheet()
	_load_hair_sheet()
	_load_accessory_sheet()
	for button in [_back_button, _confirm_button]:
		_style_button(button)
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_connect_arrows("Panel/Margin/VBox/HBox/RightColumn/HairRow", "_cycle_hair")
	_connect_arrows("Panel/Margin/VBox/HBox/RightColumn/OutfitRow", "_cycle_outfit")
	_connect_arrows("Panel/Margin/VBox/HBox/RightColumn/AccessoryRow", "_cycle_accessory")
	for target in _palette_tabs.keys():
		(_palette_tabs[target] as Button).pressed.connect(_on_palette_tab_pressed.bind(target))
	var swatch_buttons := _swatch_row.get_children()
	for i in mini(swatch_buttons.size(), SWATCH_COLORS.size()):
		var swatch_button := swatch_buttons[i] as Button
		_set_swatch_style(swatch_button, SWATCH_COLORS[i], false)
		swatch_button.pressed.connect(_on_swatch_pressed.bind(SWATCH_COLORS[i]))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_back_pressed()


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
	_active_palette_target = "skin"
	_update_palette_tab_styles()
	_refresh_pickers()
	visible = true


func _on_back_pressed() -> void:
	visible = false


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
	SaveManager.set_current_slot(_slot)
	SaveManager.save_game(_slot)
	visible = false
	confirmed.emit()


## 정정(사용자 확정 2026-08-07): 0번(대머리)을 "없음"과 동일 취급해서 순환
## 대상에서 뺐었는데("없음을 없애자"는 요청을 잘못 적용함) - 사용자가 직접
## 그려둔 정식 헤어스타일 중 하나(민머리 스타일)이지 "선택 안 함"이 아니다.
## 그래서 다시 0번부터 전체 순환하도록 되돌림 - 기본값만 1번(민머리가 아닌
## 첫 스타일)으로 유지(open() 참고).
func _cycle_hair(direction: int) -> void:
	_hair_index = wrapi(_hair_index + direction, 0, _hair_row_count)
	_refresh_pickers()


## 헤어와 같은 방식(사용자 확정: "outfit도 머리랑 동일하게 처리해줘야돼") -
## 0번줄부터 이미 실제 스타일이라(빈 그림 없음) 그냥 전체 줄을 순환한다.
func _cycle_outfit(direction: int) -> void:
	_outfit_index = wrapi(_outfit_index + direction, 0, _outfit_row_count)
	_refresh_pickers()


## 헤어와 같은 방식(사용자 확정: "양식은 머리와 같아") - 0번이 곧 빈 그림
## ("없음")이라 헤어처럼 별도의 -1 상태가 필요 없다. 헤어와 달리 0번을
## "정식 스타일"이 아니라 "없음"으로 취급하는 이유: 장신구는 원래도 유일하게
## "없음"이 허용된 항목이었고(사용자 확정), 0번 그림도 실제로 빈 그림이라
## 의미가 그대로 맞아떨어진다.
func _cycle_accessory(direction: int) -> void:
	_accessory_index = wrapi(_accessory_index + direction, 0, _accessory_row_count)
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


## target이 가리키는 실제 Color 변수를 읽는다 - 피부/눈동자/뺨/머리/
## 악세서리는 단일 변수, 옷 3색은 _outfit_colors 배열의 해당 인덱스
## (OUTFIT_MARKER_COLORS와 같은 순서). 지금 편집 중인 색(_active_palette_target
## 기준)을 읽을 때도, 탭 8개 전부의 스와치 배경을 그릴 때도 재사용한다.
func _get_target_color(target: String) -> Color:
	match target:
		"skin":
			return _skin_color
		"eye":
			return _eye_color
		"cheek":
			return _cheek_color
		"hair":
			return _hair_color
		"outfit_1":
			return _outfit_colors[0]
		"outfit_2":
			return _outfit_colors[1]
		"outfit_3":
			return _outfit_colors[2]
		"accessory":
			return _accessory_color
	return Color.WHITE


func _set_target_color(color: Color) -> void:
	match _active_palette_target:
		"skin":
			_skin_color = color
		"eye":
			_eye_color = color
		"cheek":
			_cheek_color = color
		"hair":
			_hair_color = color
		"outfit_1":
			_outfit_colors[0] = color
		"outfit_2":
			_outfit_colors[1] = color
		"outfit_3":
			_outfit_colors[2] = color
		"accessory":
			_accessory_color = color


## 탭 8개 배경을 각각의 지금 색으로 칠해서 어느 탭이 활성인지(테두리 두께) +
## 지금 그 색이 뭔지를 동시에 보여준다. 머리 탭은 머리가 대머리(0번)일 때
## 비활성화한다 - 리컬러할 마커 픽셀 자체가 안 그려지기 때문.
func _update_palette_tab_styles() -> void:
	for target in _palette_tabs.keys():
		var button := _palette_tabs[target] as Button
		_set_swatch_style(button, _get_target_color(target), target == _active_palette_target)
		if target == "hair":
			button.disabled = _hair_index == 0
		elif target == "accessory":
			button.disabled = _accessory_index == 0
		else:
			## 눈동자/뺨/옷은 항상 뭔가 그려져 있어서(옷도 0번줄부터
			## 실제 스타일이라 "없음"이 없음) 비활성화할 일이 없다.
			button.disabled = false


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
	_hair_label.text = "대머리" if _hair_index == 0 else "헤어 %d" % _hair_index
	_update_palette_tab_styles()
	_outfit_label.text = "옷 %d" % (_outfit_index + 1)
	_accessory_label.text = NONE_LABEL if _accessory_index == 0 else "악세서리 %d" % _accessory_index
	_preview.set_layers(
		_current_body_texture(),
		_current_outfit_texture(),
		_current_hair_texture(),
		_current_accessory_texture()
	)


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
