extends Control

## shop.md UI: 계산대 상호작용으로 열리는 구매 화면. Main이 shop_interacted
## 신호로 open_shop(shop_id)를 호출한다. 판매 목록이 없는 상품은 shop.md 문서
## 그대로 planned_stock에만 있고 stock은 비어있을 수 있다 (data/shop/README.md).

const ROW_FONT_SIZE := 6
const DESCRIPTION_FONT_SIZE := 4

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const COIN_ICON := preload("res://assets/ui/icon_coin.png")
const COIN_ICON_MAX_WIDTH := 6

const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)
## 이미 동물이 있는 칸 버튼을 어둡게 처리하는 데 쓴다(title_screen.gd의
## DISABLED_TINT와 같은 값) - 칸 고르기 버튼이 기본 엔진 버튼 그대로라 못생겼다는
## 지적(사용자 지시, 2026-08-25)으로 다른 버튼들과 같은 button.png 스타일을 입힌다.
const STALL_DISABLED_TINT := Color(0.55, 0.55, 0.55)

const SCROLLBAR_WIDTH := 4
## 목장가게(belje_shop)의 소/돼지 판매 항목(ShopManager.LIVESTOCK_PREFIX와
## 동일한 값) - 가축은 인벤토리 아이템이 아니라서 즉시 구매가 아니라 "어느
## 칸에 배치할지" 먼저 물어야 한다(사용자 지시).
const LIVESTOCK_PREFIX := "livestock:"
const STALL_COUNT := 4
## ShopManager.INVENTORY_EXPANSION_ITEM_ID와 동일한 값 - 가격이 고정이 아니라
## 매번 EconomyManager.get_inventory_expansion_cost()로 다시 조회해야 한다.
const INVENTORY_EXPANSION_ITEM_ID := "inventory_expansion"
## 인벤토리 확장 아이콘 - Tools.png 13번 칸(괭이 옆에 그려진 가방, 사용자 지시).
const INVENTORY_EXPANSION_ICON_SHEET := "res://assets/icon/Tools.png"
const INVENTORY_EXPANSION_ICON_INDEX := 13
const INVENTORY_EXPANSION_ICON_GRID_SIZE := 16
## 집 확장 - ShopManager.HOUSE_UPGRADE_ITEM_ID와 동일한 값.
const HOUSE_UPGRADE_ITEM_ID := "house_upgrade"
const HOUSE_UPGRADE_ICON := preload("res://assets/img/furniture/house_upgrade_icon.png")

@onready var _rows_scroll: ScrollContainer = $Background/Margin/VBox/RowsScroll
@onready var _rows: VBoxContainer = $Background/Margin/VBox/RowsScroll/RowsMargin/Rows
@onready var _message_label: Label = $Background/Margin/VBox/MessageLabel
@onready var _close_button: TextureButton = $Background/CloseButton
@onready var _stall_picker: Control = $StallPicker
@onready var _stall_message_label: Label = $StallPicker/Panel/Margin/VBox/MessageLabel
@onready var _stall_row: HBoxContainer = $StallPicker/Panel/Margin/VBox/StallRow
@onready var _stall_cancel_button: Button = $StallPicker/Panel/Margin/VBox/CancelButton
@onready var _color_picker: Control = $ColorPicker
@onready var _color_message_label: Label = $ColorPicker/Panel/Margin/VBox/MessageLabel
@onready var _color_preview_rect: TextureRect = $ColorPicker/Panel/Margin/VBox/PreviewRect
@onready var _color_slots_scroll: ScrollContainer = $ColorPicker/Panel/Margin/VBox/SlotsScroll
@onready var _color_slots_container: VBoxContainer = $ColorPicker/Panel/Margin/VBox/SlotsScroll/SlotsMargin/SlotsContainer
@onready var _color_buy_button: Button = $ColorPicker/Panel/Margin/VBox/ButtonRow/BuyButton
@onready var _color_cancel_button: Button = $ColorPicker/Panel/Margin/VBox/ButtonRow/CancelButton

var _shop_id := ""
var _is_open := false
var _pending_livestock_item_id := ""

## 가구/바닥장식/벽장식 색상 커스터마이징용(색 2/3 슬롯). 2026-08-10까지는
## character_creation_screen.gd의 SWATCH_COLORS(고정 12개, 스와치 버튼 12개짜리
## 씬 레이아웃과 1:1로 묶여있음)와 값을 동일하게 맞춰뒀었는데, 사용자가 이
## 팔레트만 26개(선명한 색 13 + 파스텔 13)로 확장 지정하면서 두 팔레트가
## 의도적으로 갈라졌다 - SWATCH_COLORS는 캐릭터 생성 화면 UI가 정확히 12칸
## 고정이라 그대로 12개 유지, 이 배열만 늘어난 상태(따로 갱신 요청 전까지는
## 서로 다른 값으로 유지).
const SWATCH_PALETTE: Array[Color] = [
	Color("d94a38"), # Red
	Color("e67e22"), # Orange
	Color("f2c230"), # Yellow
	Color("8bcf3f"), # Lime
	Color("43b84f"), # Green
	Color("3fcf9a"), # Mint
	Color("4aa8f0"), # Sky Blue
	Color("3f73e8"), # Blue
	Color("8b57e6"), # Purple
	Color("e65fae"), # Pink
	Color("a8642a"), # Brown
	Color("2d1e18"), # Black
	Color("f08a84"), # Pastel Red
	Color("f5b26b"), # Pastel Orange
	Color("f5de7a"), # Pastel Yellow
	Color("b7de72"), # Pastel Lime
	Color("8fd38a"), # Pastel Green
	Color("8fe0c5"), # Pastel Mint
	Color("8ecdf2"), # Pastel Sky
	Color("8faef2"), # Pastel Blue
	Color("b59bf0"), # Pastel Purple
	Color("f2a8d1"), # Pastel Pink
	Color("c99a72"), # Pastel Brown
	Color("f8f1dd"), # Cream
	Color("4a3327"), # Dark Brown
]
## 색 1(회색 3단계 마커, 명암 자동 계산)은 가구 대부분이 나무 재질이라 일반
## 팔레트 대신 원목 색상만 고르게 한다(사용자 지정 - 나무 느낌이 나는 색만
## 일부러 골라온 목록). 색 2/3(마젠타/형광녹색 마커)은 계속 SWATCH_PALETTE.
## 2026-08-10: 기존 값도 뿌옇게 느껴진다는 사용자 피드백으로 더 채도 높은
## 색으로 세 차례 전체 교체(사용자 지정, 최신 값 기준).
const WOOD_PALETTE: Array[Color] = [
	Color("472f1d"), # Dark Walnut
	Color("8d562c"), # Classic Oak
	Color("c97a22"), # Golden Oak
	Color("d97f1f"), # Orange Oak
	Color("e19328"), # Honey Wood
	Color("e88a1a"), # Amber Wood
	Color("c45a1e"), # Autumn Wood
	Color("b63c2c"), # Cherry Wood
	Color("922e24"), # Red Mahogany
	Color("d96a18"), # Pumpkin Wood
	Color("c85b19"), # Copper Wood
	Color("f0a43a"), # Bright Maple
]
const SWATCH_BUTTON_SIZE := Vector2(14, 8)
const SWATCH_GRID_COLUMNS := 6
const SWATCH_BORDER_COLOR := Color(0.25, 0.15, 0.08)
const COLOR_SLOT_LABELS := ["색 1", "색 2", "색 3"]

var _pending_color_item_id := ""
var _pending_color_world_sprite_path := ""
var _pending_color_slots: Array[Color] = []
## 마커별로 실제 그림에 있는지([색1, 색2, 색3]) - 색1 없이 색2만 있는 그림
## (vase2~4 등)에서 색1 슬롯을 건너뛰는 데 쓴다(_build_color_slot_rows 참고).
var _pending_color_present: Array[bool] = [false, false, false]


func _ready() -> void:
	# Godot doesn't correctly resolve font color/modulate for controls built
	# while their ancestor's `visible` was ever false, even briefly - so this
	# screen stays `visible = true` for its whole life and is hidden/shown via
	# transparency + mouse_filter instead (see _set_open below).
	_set_open(false)
	_close_button.pressed.connect(close)
	_stall_cancel_button.pressed.connect(_close_stall_picker)
	_set_stall_picker_open(false)
	_color_buy_button.pressed.connect(_on_color_buy_pressed)
	_color_cancel_button.pressed.connect(_close_color_picker)
	_set_color_picker_open(false)
	# 확대 필터를 명시적으로 지정 안 해두면 상속 체인에 따라 부드럽게(linear)
	# 보간될 수 있어서 - 픽셀아트가 경계에서 뭉개져 흐릿해 보이는 걸 막기 위해
	# 항상 니어레스트로 고정한다(icon_rect들과 동일한 의도).
	# expand_mode는 기본값(EXPAND_KEEP_SIZE)을 그대로 둔다 - PreviewRect의
	# custom_minimum_size 너비가 0이라(씬 파일 참고), EXPAND_IGNORE_SIZE로
	# 바꾸면 텍스처 크기를 최소 크기 계산에서 무시하게 되어 실제 폭이 0으로
	# 줄어들어 그림이 아예 안 보이는 버그가 있었다(모든 가구에서 재현,
	# 사용자 리포트) - 기본값이어야 텍스처 크기만큼 자동으로 폭을 잡는다.
	_color_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	for button in [_stall_cancel_button, _color_buy_button, _color_cancel_button]:
		button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
		button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
		button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		## StallPicker의 취소 버튼은 .tscn에 font_color가 아예 안 박혀있어서
		## Godot 기본(밝은) 글자색 그대로 나와 배경 위에서 안 보였다(사용자
		## 리포트, 2026-08-27 - "글자 색이 검정색이 아니라 잘 안보여"). 여기서
		## 세 버튼 다 동일하게 맞춰준다(ColorPicker 둘은 .tscn에 이미 같은 색이
		## 박혀있어 사실상 값은 같지만, 한 곳에서 일괄 관리하는 게 더 안전하다).
		button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
		button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)
	_style_scrollbar(_rows_scroll)
	_style_scrollbar(_color_slots_scroll)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_shop(shop_id: String) -> void:
	_shop_id = shop_id
	_message_label.text = ""
	# _set_open(true)를 _refresh_rows()보다 먼저 불러야 한다 - 순서가 반대면
	# _build_row()가 막 만든 상품 버튼 위 가격 아이콘/글자(mouse_filter=IGNORE,
	# 클릭이 버튼까지 뚫고 내려가라고 일부러 지정한 것)가 재귀 STOP 적용에
	# 다시 덮어써져서 클릭을 가로챈다 - kitchen_screen.gd 그리드 슬롯 아이콘이
	# 겪었던 것과 동일한 함정(사용자 리포트, 2026-08-29 - "상점 구매 버튼이
	# 안 눌림", 재접속 직후에도 재현되는 것으로 확인). close()는 반대로 rows를
	# 먼저 갱신해야 하지만(맨 위 close() 주석 참고), open은 이 순서가 맞다.
	_set_open(true)
	_refresh_rows()


func close() -> void:
	# _refresh_rows()를 _set_open(false)보다 먼저 불러야 한다 - _build_row()가
	# 만드는 상품 줄 버튼은 그때그때 새로 생성되는데, 순서가 반대면 이 새
	# 버튼들이 막 지나간 재귀 mouse_filter 적용을 못 받고 TextureButton
	# 기본값(STOP)인 채로 남아, 화면은 안 보여도 그 자리 클릭을 계속
	# 가로챈다(사용자 리포트 - 인벤 창에서 같은 계열로 확인된 문제와 동일한
	# 원인, equipment_panel.gd 참고).
	_close_stall_picker()
	_close_color_picker()
	_refresh_rows()
	_set_open(false)


## 이 화면의 루트는 전체화면이 아니라 가운데 고정 크기 박스라
## computer_screen.gd와 동일한 이유/동일한 수정(사용자 리포트, 2026-08-27 -
## "스크롤도 잘 안먹어.. 상점에서도 그랬고") - 자기 값을 자기에게 재대입하는
## 방식은 효과가 없어서, 크기는 유지한 채 진짜로 다시 가운데 정렬시키는
## PRESET_CENTER + KEEP_SIZE로 교체한다.
## mouse_filter는 정해진 노드 몇 개에만 수동으로 지정했었는데, _build_row()가
## 매번 새로 만드는 상품 줄 버튼들은 그 목록에 없어서 기본값(STOP)인 채로
## 남아 화면이 닫혀도 클릭을 가로챌 수 있었다(사용자 리포트, 2026-08-29 -
## "인벤 창이 안 사라져서 요청함이 안 눌림"과 같은 계열, 코드 추적으로 이
## 화면도 같은 구조적 원인이 있음을 확인함). 다른 17개 화면과 동일하게 자기
## 서브트리 전체를 재귀로 처리하는 방식으로 교체한다.
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _refresh_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var stock: Array = ShopManager.get_stock(_shop_id)
	## 집 확장이 최대치(더 이상 업글 불가, get_house_upgrade_cost() < 0)에
	## 도달하면 "최대"라고 비활성화 버튼으로 남겨두는 대신, 낚싯대 같은
	## 1회성 상품이 다 사고 나면 목록에서 사라지는 것과 동일하게 통째로
	## 빼버린다(사용자 지시, 2026-08-30 - "최대 뜨지말고 사라지게").
	stock = stock.filter(func(listing: Dictionary) -> bool:
		return String(listing.get("item_id", "")) != HOUSE_UPGRADE_ITEM_ID \
			or EconomyManager.get_house_upgrade_cost() >= 0
	)
	if stock.is_empty():
		var empty_label := Label.new()
		empty_label.text = "판매 중인 상품이 없습니다."
		empty_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		_rows.add_child(empty_label)
		return
	# Flexible spacers before/after the rows: when the list is shorter than
	# the scroll area, a VBoxContainer splits the extra space evenly between
	# them, which centers the rows instead of leaving them stuck at the top.
	# When the list overflows, both spacers just shrink to nothing and
	# scrolling behaves exactly as before.
	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_child(top_spacer)
	for listing in stock:
		_rows.add_child(_build_row(listing))
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_child(bottom_spacer)


func _build_row(listing: Dictionary) -> Control:
	var item_id := String(listing.get("item_id", ""))
	var price := int(listing.get("price", 0))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _build_row_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(12, 12)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = InventoryManager.get_item_icon_texture(item_id)
	row.add_child(icon_rect)

	var display_name := item_id
	var display_description := ""
	var is_maxed := false
	## legend_statue는 골드가 아니라 전설의 물고기 100개로 교환하는 특수
	## 구매(ShopManager._buy_legend_statue() 참고, 사용자 지시 2026-09-05) -
	## 가격 표시도 동전 아이콘+골드 대신 물고기 아이콘+개수로 바꾼다.
	var price_icon_override: Texture2D = null
	var price_text_override := ""
	if item_id == ShopManager.LEGEND_STATUE_ITEM_ID:
		price_icon_override = InventoryManager.get_item_icon_texture(FishingManager.LEGENDARY_FISH_ITEM_ID)
		price_text_override = str(ShopManager.LEGEND_STATUE_FISH_COST)
	if item_id.begins_with(LIVESTOCK_PREFIX):
		var animal_type := item_id.trim_prefix(LIVESTOCK_PREFIX)
		var animal_definition := LivestockManager.get_animal_definition(animal_type)
		display_name = String(animal_definition.get("name", item_id))
		display_description = "외양간에 배치해 기를 수 있다."
		icon_rect.texture = LivestockManager.get_animal_icon_texture(animal_type, false)
	elif item_id == INVENTORY_EXPANSION_ITEM_ID:
		display_name = "인벤토리 확장"
		display_description = "소지 가능한 아이템 칸을 5개 늘린다."
		icon_rect.texture = _inventory_expansion_icon_texture()
		price = EconomyManager.get_inventory_expansion_cost()
		is_maxed = price < 0
	elif item_id == HOUSE_UPGRADE_ITEM_ID:
		display_name = "집 확장"
		display_description = "집 내부를 더 넓게 만든다."
		icon_rect.texture = HOUSE_UPGRADE_ICON
		price = EconomyManager.get_house_upgrade_cost()
		is_maxed = price < 0
	else:
		var definition := InventoryManager.get_item_definition(item_id)
		display_name = String(definition.get("name", item_id))
		display_description = String(definition.get("description", ""))

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.custom_minimum_size = Vector2(90, 0)
	text_column.add_theme_constant_override("separation", 0)
	row.add_child(text_column)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	text_column.add_child(name_label)

	var description_label := Label.new()
	description_label.text = display_description
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	description_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	text_column.add_child(description_label)

	var buy_button := Button.new()
	buy_button.custom_minimum_size = Vector2(45, 16)
	# 설명이 길어서 여러 줄로 늘어나면 HBoxContainer가 이 버튼도 행 높이만큼
	# 같이 늘리려 하는데(기본은 세로로 꽉 채움), SHRINK_CENTER로 막아서 버튼은
	# 항상 1줄 크기(16px)로 고정하고 세로 중앙에 배치한다(사용자 지시).
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	buy_button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	buy_button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	buy_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	buy_button.pressed.connect(func() -> void: _on_buy_pressed(item_id))
	# 구매 성공 시 AudioManager가 SFX_COIN을 따로 재생하므로(item_purchased 구독),
	# main.gd의 모달 공통 클릭음과 겹쳐서 나지 않도록 이 버튼만 제외한다.
	buy_button.add_to_group(&"_no_click_sfx")
	# 인벤토리 확장이 이미 최대치(30칸)면 더 살 수 없으니 버튼을 비활성화한다.
	buy_button.disabled = is_maxed
	row.add_child(buy_button)

	# Button's own icon+text rendering wouldn't pick up the font color
	# override reliably here, so the coin icon + price are drawn as separate
	# child controls centered over the button instead.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buy_button.add_child(center)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 2)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(price_row)

	if not is_maxed:
		var price_icon := TextureRect.new()
		price_icon.custom_minimum_size = Vector2(COIN_ICON_MAX_WIDTH, COIN_ICON_MAX_WIDTH)
		price_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		price_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		price_icon.texture = price_icon_override if price_icon_override != null else COIN_ICON
		price_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price_row.add_child(price_icon)

	var price_label := Label.new()
	if is_maxed:
		price_label.text = "최대"
	elif not price_text_override.is_empty():
		price_label.text = price_text_override
	else:
		price_label.text = EconomyManager.format_gold(price)
	price_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	price_label.modulate = BUTTON_TEXT_COLOR
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(price_label)

	return panel


func _inventory_expansion_icon_texture() -> Texture2D:
	if not ResourceLoader.exists(INVENTORY_EXPANSION_ICON_SHEET):
		return _flat_color_icon_texture(Color(0.6, 0.5, 0.3))
	var atlas := AtlasTexture.new()
	atlas.atlas = load(INVENTORY_EXPANSION_ICON_SHEET)
	atlas.region = Rect2(INVENTORY_EXPANSION_ICON_INDEX * INVENTORY_EXPANSION_ICON_GRID_SIZE, 0, INVENTORY_EXPANSION_ICON_GRID_SIZE, INVENTORY_EXPANSION_ICON_GRID_SIZE)
	return atlas


func _flat_color_icon_texture(color: Color) -> Texture2D:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _build_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.15)
	style.border_color = Color(0.35, 0.25, 0.15, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func _build_button_style(texture: Texture2D, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	style.modulate_color = tint
	return style


## Godot's default ScrollContainer scrollbar is a thick engine-styled gray
## bar that doesn't match this UI's look and doesn't fit the small panel -
## shrink it and flatten its colors instead of drawing a new asset for it.
func _style_scrollbar(scroll: ScrollContainer) -> void:
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.15)
	track.set_corner_radius_all(2)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.55, 0.4, 0.25, 0.9)
	grabber.set_corner_radius_all(2)
	scrollbar.add_theme_stylebox_override("scroll", track)
	scrollbar.add_theme_stylebox_override("grabber", grabber)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber)


func _on_buy_pressed(item_id: String) -> void:
	if item_id.begins_with(LIVESTOCK_PREFIX):
		_open_stall_picker(item_id)
		return
	if item_id != INVENTORY_EXPANSION_ITEM_ID:
		var world_sprite_path := String(InventoryManager.get_item_definition(item_id).get("world_sprite", ""))
		var present := FurnitureAppearance.detect_present_markers(world_sprite_path)
		if present.has(true):
			_open_color_picker(item_id, world_sprite_path, present)
			return
	var failure_reason := ShopManager.buy(_shop_id, item_id)
	if failure_reason.is_empty():
		_message_label.text = "구매했습니다."
	else:
		_message_label.text = failure_reason
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
	_refresh_rows()


## 그림에 색 마커가 있는 아이템(가구/바닥장식/벽장식)은 바로 사지 않고, 색을
## 고르는 패널을 먼저 연다(사용자 지시) - 마커별로 실제 있는지는 그림을
## 스캔해 자동으로 정해진다(FurnitureAppearance.detect_present_markers).
## present는 [색1 있음, 색2 있음, 색3 있음] - 색1 없이 색2만 있는 그림도
## 있어서(vase2~4 등) 마지막으로 있는 마커 인덱스까지만 슬롯을 만들되, 중간에
## 없는 자리(예: 색1)는 _build_color_slot_rows()가 UI에서 건너뛴다. 기본
## 선택색은 팔레트를 슬롯마다 하나씩 돌려가며 미리 채워서 처음부터
## 미리보기가 비어 보이지 않게 한다 - 없는 자리는 고정 자리표시 색(어차피
## 그 마커가 그림에 없어서 렌더링에 전혀 영향 없음, 같은 아이템끼리 스택이
## 갈리지 않도록 항상 같은 값을 씀).
const ABSENT_MARKER_PLACEHOLDER := Color("808080")


func _open_color_picker(item_id: String, world_sprite_path: String, present: Array[bool]) -> void:
	_pending_color_item_id = item_id
	_pending_color_world_sprite_path = world_sprite_path
	_pending_color_present = present
	var last_present_index := -1
	for i in present.size():
		if present[i]:
			last_present_index = i
	_pending_color_slots.clear()
	for i in (last_present_index + 1):
		if present[i]:
			var palette := _palette_for_slot(i)
			_pending_color_slots.append(palette[i % palette.size()])
		else:
			_pending_color_slots.append(ABSENT_MARKER_PLACEHOLDER)
	var definition := InventoryManager.get_item_definition(item_id)
	_color_message_label.text = tr("%s 색을 골라주세요") % String(definition.get("name", item_id))
	_build_color_slot_rows()
	_refresh_color_preview()
	_set_color_picker_open(true)


## 색 1(회색 마커)은 가구 재질이 대부분 나무라 WOOD_PALETTE, 색 2/3(마젠타/
## 형광녹색 마커)은 일반 SWATCH_PALETTE를 쓴다(사용자 지정).
func _palette_for_slot(slot_index: int) -> Array[Color]:
	return WOOD_PALETTE if slot_index == 0 else SWATCH_PALETTE


## 슬롯마다 라벨 + 팔레트 스와치 그리드(SwatchRow, character_creation_screen.gd와
## 동일한 6열 구성) 한 줄씩 새로 만든다 - 아이템마다 슬롯 수가 달라서 매번
## 새로 지어야 한다(기존 노드 재사용 안 함).
func _build_color_slot_rows() -> void:
	for child in _color_slots_container.get_children():
		child.queue_free()
	for slot_index in _pending_color_slots.size():
		if not _pending_color_present[slot_index]:
			continue
		var label := Label.new()
		label.text = COLOR_SLOT_LABELS[slot_index] if slot_index < COLOR_SLOT_LABELS.size() else tr("색 %d") % (slot_index + 1)
		label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
		_color_slots_container.add_child(label)
		var grid := GridContainer.new()
		grid.columns = SWATCH_GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 2)
		_color_slots_container.add_child(grid)
		for color in _palette_for_slot(slot_index):
			var swatch := Button.new()
			swatch.custom_minimum_size = SWATCH_BUTTON_SIZE
			swatch.focus_mode = Control.FOCUS_NONE
			_style_swatch_button(swatch, color, color.is_equal_approx(_pending_color_slots[slot_index]))
			swatch.pressed.connect(_on_swatch_pressed.bind(slot_index, color))
			grid.add_child(swatch)


func _style_swatch_button(button: Button, color: Color, is_selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var border_width := 2 if is_selected else 1
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = SWATCH_BORDER_COLOR
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_swatch_pressed(slot_index: int, color: Color) -> void:
	_pending_color_slots[slot_index] = color
	_build_color_slot_rows()
	_refresh_color_preview()


## 고른 색 그대로 FurnitureAppearance로 즉석 리컬러해서 미리보기에 보여준다
## (구매 전 프리뷰라 캐싱 없이 매번 새로 계산 - 그림이 작아 비용 문제 없음).
func _refresh_color_preview() -> void:
	var image := FurnitureAppearance.build_recolored_image(_pending_color_world_sprite_path, _pending_color_slots)
	_color_preview_rect.texture = ImageTexture.create_from_image(image) if image != null else null


func _on_color_buy_pressed() -> void:
	var item_id := _pending_color_item_id
	var colors := _pending_color_slots.duplicate()
	_close_color_picker()
	var failure_reason := ShopManager.buy(_shop_id, item_id, -1, colors)
	if failure_reason.is_empty():
		_message_label.text = "구매했습니다."
	else:
		_message_label.text = failure_reason
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
	_refresh_rows()


func _close_color_picker() -> void:
	_pending_color_item_id = ""
	_pending_color_world_sprite_path = ""
	_pending_color_slots.clear()
	_pending_color_present = [false, false, false]
	_set_color_picker_open(false)


func _set_color_picker_open(is_open: bool) -> void:
	_color_picker.modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(_color_picker, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


## 가축은 배치할 칸을 먼저 골라야 해서, 산 자리에서 바로 확정하지 않고 이
## 작은 그리드 팝업을 연다(사용자 지시). 이미 동물이 있는 칸은 비활성 처리.
func _open_stall_picker(item_id: String) -> void:
	_pending_livestock_item_id = item_id
	var animal_definition := LivestockManager.get_animal_definition(item_id.trim_prefix(LIVESTOCK_PREFIX))
	_stall_message_label.text = tr("%s를 어느 칸에 배치할까요?") % String(animal_definition.get("name", ""))
	for child in _stall_row.get_children():
		child.queue_free()
	for i in STALL_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2(24, 16)
		button.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
		button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
		button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
		button.add_theme_stylebox_override("disabled", _build_button_style(BUTTON_TEXTURE, STALL_DISABLED_TINT))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
		button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)
		button.add_theme_color_override("font_disabled_color", BUTTON_TEXT_COLOR.lerp(Color.BLACK, 0.3))
		if LivestockManager.is_stall_empty(i):
			button.text = str(i + 1)
			button.pressed.connect(func() -> void: _on_stall_chosen(i))
		else:
			button.text = "-"
			button.disabled = true
		_stall_row.add_child(button)
	_set_stall_picker_open(true)


func _close_stall_picker() -> void:
	_pending_livestock_item_id = ""
	_set_stall_picker_open(false)


func _on_stall_chosen(stall_index: int) -> void:
	var item_id := _pending_livestock_item_id
	_close_stall_picker()
	var failure_reason := ShopManager.buy(_shop_id, item_id, stall_index)
	if failure_reason.is_empty():
		_message_label.text = "구매했습니다."
	else:
		_message_label.text = failure_reason
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
	_refresh_rows()


func _set_stall_picker_open(is_open: bool) -> void:
	_stall_picker.modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(_stall_picker, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


## _color_picker/_stall_picker는 자기 열고 닫힘을 따로 관리한다
## (_set_color_picker_open()/_set_stall_picker_open()) - 메인 창 전체를 도는
## 재귀(_set_open()에서 self로 호출)가 그 둘까지 밟아버리면, 메인 창이 열릴 때
## 지금 닫혀있는 두 팝업까지 STOP으로 덮어써서 안 보이는 채로 화면을 가로막게
## 된다. 자식으로 만났을 때만 건너뛰고, 이 둘을 직접 node로 넘겨 호출하는
## 기존 경로(_set_color_picker_open() 등)는 그대로 동작해야 하므로 진입점
## 자체는 걸러내지 않는다.
func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		if child == _color_picker or child == _stall_picker:
			continue
		_apply_mouse_filter_recursive(child, filter)
