extends Control

## computer_screen.gd 산하 온라인샵 창. shop_screen.gd와 같은 방식으로 상품
## 목록을 그리되, ShopManager.get_shop_mode()가 "online"인 상점(운영 NPC
## 사망으로 전환된 상점 - shop.md/email.md)만 모아서 상점 이름별로 묶어
## 보여준다. 구매는 그대로 ShopManager.buy()를 타므로 익일 09시 배송.

signal closed

const ROW_FONT_SIZE := 6
const DESCRIPTION_FONT_SIZE := 4
const HEADER_FONT_SIZE := 7

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const COIN_ICON := preload("res://assets/ui/icon_coin.png")
const COIN_ICON_MAX_WIDTH := 6

const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

## HD 아웃핏 해금 항목(ShopManager.is_hd_outfit_unlock_item()) 전용 - 인벤토리
## 아이템이 아니라서 items.json에 없다(house_upgrade/inventory_expansion과
## 같은 이유, shop_screen.gd 참고) - 이름표/아이콘을 여기서 직접 만든다.
## 이름은 wardrobe_screen.gd의 OUTFIT_LABELS와 중복 관리(두 파일 다 갱신 필요).
const HD_OUTFIT_LABELS := {
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
const HD_OUTFIT_ICON_SIZE := Vector2(12, 24)
## 파라의 헤어샵 전용(ShopManager.is_hd_hairstyle_unlock_item()) - HD_OUTFIT_LABELS와
## 같은 이유로 items.json에 없는 항목이라 이름표를 여기서 직접 관리한다.
## 이름은 wardrobe_screen.gd의 HAIRSTYLE_LABELS와 중복 관리(두 파일 다 갱신 필요).
const HD_HAIRSTYLE_LABELS := {
	"special_hair1": "스페셜 헤어 1",
	"special_hair2": "스페셜 헤어 2",
	"special_hair3": "스페셜 헤어 3",
	"special_hair4": "스페셜 헤어 4",
}
## 옷장이 잠겨있는 동안은(main.gd의 WARDROBE_UNLOCK_NPC_ID/THRESHOLD와
## 중복 관리 필요) HD 아웃핏 해금 버튼을 눌러도 소용없으니 아예 못 누르게
## 막는다(사용자 지시, 2026-09-03 - "구매 버튼은 오로지 옷장이 열렸을
## 때만 클릭 가능하게"). 상점 자체(항목 목록)는 그와 무관하게 항상 보인다.
const WARDROBE_UNLOCK_NPC_ID := "woody"
const WARDROBE_UNLOCK_THRESHOLD := 50

@onready var _close_button: TextureButton = $CloseButton
@onready var _rows_scroll: ScrollContainer = $ScaledContent/Margin/VBox/RowsScroll
@onready var _rows: VBoxContainer = $ScaledContent/Margin/VBox/RowsScroll/RowsMargin/Rows
@onready var _message_label: Label = $ScaledContent/Margin/VBox/MessageLabel


func _ready() -> void:
	_close_button.pressed.connect(func() -> void: closed.emit())
	## 세로 스크롤바가 기본 Godot 회색 굵은 바라 상점창이랑 안 맞고, 여백도
	## 없어서 버튼/가격 텍스트랑 겹쳐 보였다(사용자 지시, 2026-09-04 - "온라인샵
	## 세로 스크롤바가 너무 못생겨서 상점하고 통일해주고... 겹치지 않게 해줘") -
	## shop_screen.gd._style_scrollbar()와 같은 배색, RowsMargin(scene)이 겹침을 막는다.
	_style_v_scrollbar(_rows_scroll)


func refresh() -> void:
	_message_label.text = ""
	_refresh_rows()


func _refresh_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var online_shop_ids := _get_online_shop_ids()
	if online_shop_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "온라인 상점이 없습니다."
		empty_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		empty_label.add_theme_color_override("font_color", Color.BLACK)
		_rows.add_child(empty_label)
		return
	for shop_id in online_shop_ids:
		_rows.add_child(_build_header(shop_id))
		if _shop_is_hd_outfit_only(shop_id):
			_rows.add_child(_build_hd_outfit_card_row(shop_id))
		elif _shop_is_hd_hairstyle_only(shop_id):
			_rows.add_child(_build_hd_hairstyle_card_row(shop_id))
		else:
			for listing in ShopManager.get_stock(shop_id):
				_rows.add_child(_build_row(shop_id, listing))


func _get_online_shop_ids() -> Array:
	var ids: Array = []
	for shop_id in ShopManager.get_shop_ids():
		if ShopManager.get_shop_mode(shop_id) == "online":
			ids.append(shop_id)
	return ids


func _build_header(shop_id: String) -> Label:
	var label := Label.new()
	label.text = String(ShopManager.get_shop_definition(shop_id).get("name", shop_id))
	label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.BLACK)
	return label


func _build_row(shop_id: String, listing: Dictionary) -> Control:
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
	var is_hd_outfit := ShopManager.is_hd_outfit_unlock_item(item_id)
	var hd_outfit_style := item_id.trim_prefix(ShopManager.HD_OUTFIT_ITEM_PREFIX) if is_hd_outfit else ""

	var icon_rect := TextureRect.new()
	if is_hd_outfit:
		icon_rect.custom_minimum_size = HD_OUTFIT_ICON_SIZE
	else:
		icon_rect.custom_minimum_size = Vector2(12, 12)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _hd_outfit_preview_texture(hd_outfit_style) if is_hd_outfit else InventoryManager.get_item_icon_texture(item_id)
	row.add_child(icon_rect)

	## HD 아웃핏 해금 항목은 인벤토리 아이템이 아니라 items.json에 없다
	## (house_upgrade/inventory_expansion과 같은 이유) - 이름/설명을 여기서
	## 직접 만든다.
	var definition := InventoryManager.get_item_definition(item_id)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.custom_minimum_size = Vector2(90, 0)
	text_column.add_theme_constant_override("separation", 0)
	row.add_child(text_column)

	var name_label := Label.new()
	name_label.text = HD_OUTFIT_LABELS.get(hd_outfit_style, hd_outfit_style) if is_hd_outfit else String(definition.get("name", item_id))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color.BLACK)
	text_column.add_child(name_label)

	var description_label := Label.new()
	description_label.text = "옷장에서 착용할 수 있는 옷차림이다." if is_hd_outfit else String(definition.get("description", ""))
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	description_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	description_label.add_theme_color_override("font_color", Color.BLACK)
	text_column.add_child(description_label)

	var buy_button := _build_buy_button(shop_id, item_id, price, is_hd_outfit and not _is_wardrobe_unlocked())
	# shop_screen.gd와 동일 - 설명이 여러 줄로 늘어나도 버튼은 1줄 크기로
	# 고정하고 세로 중앙에 배치한다.
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buy_button)

	return panel


## 키라의 의상샵처럼 스타일 전체를 큰 이미지로 보여주는 게 나은 상점은 세로
## 목록 대신 가로로 슬라이딩하는 카드 목록으로 그린다(사용자 지시, 2026-09-03 -
## "목록이 위에서 아래가 아니라 좌에서 우로 슬라이딩 할 수 있으면 좋겠고,
## 룩을 크게 보여주고 그 밑에 그냥 룩3 이렇게만 보여도 될 거 같아").
func _shop_is_hd_outfit_only(shop_id: String) -> bool:
	var stock := ShopManager.get_stock(shop_id)
	if stock.is_empty():
		return false
	for listing in stock:
		if not ShopManager.is_hd_outfit_unlock_item(String(listing.get("item_id", ""))):
			return false
	return true


## 파라의 헤어샵처럼 헤어스타일 전체를 큰 이미지로 보여주는 상점 - 키라의
## 의상샵과 완전히 같은 이유/구조(사용자 지시, 2026-09-04 - "레이아웃은
## 의상샵이랑 똑같이 해줘").
func _shop_is_hd_hairstyle_only(shop_id: String) -> bool:
	var stock := ShopManager.get_stock(shop_id)
	if stock.is_empty():
		return false
	for listing in stock:
		if not ShopManager.is_hd_hairstyle_unlock_item(String(listing.get("item_id", ""))):
			return false
	return true


## ScaledContent가 1/3로 축소돼서 그려지는 화면이라(offset_top=10~offset_bottom=100,
## 90 "디자인 단위"가 실제로는 30px 남짓) 처음엔 48x96으로 했다가, 그 다음 절반인
## 24x48로 줄여도 여전히 세로 스크롤이 남았다(사용자 리포트, 2026-09-03 -
## "아직도 세로 스크롤 있어") - 헤더+메시지 라벨까지 감안한 실제 예산에 맞춰
## 훨씬 더 작게 잡는다.
const HD_OUTFIT_CARD_ICON_SIZE := Vector2(12, 18)
const HD_OUTFIT_CARD_SEPARATION := 6

func _build_hd_outfit_card_row(shop_id: String) -> Control:
	var scroll := ScrollContainer.new()
	# 카드(아이콘+버튼) 아래에 가로 스크롤바가 겹쳐 그려지지 않도록, 스크롤바
	# 높이만큼 여유를 더 둔다(사용자 지시, 2026-09-03 - "슬라이드 바랑 돈
	# 버튼이랑 안겹치게 해줘").
	scroll.custom_minimum_size = Vector2(0, HD_OUTFIT_CARD_ICON_SIZE.y + 18 + SCROLLBAR_HEIGHT + 3)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", HD_OUTFIT_CARD_SEPARATION)
	scroll.add_child(hbox)
	for listing in ShopManager.get_stock(shop_id):
		hbox.add_child(_build_hd_outfit_card(shop_id, listing))
	_style_h_scrollbar(scroll)
	return scroll


## shop_screen.gd._style_scrollbar()와 동일한 배색(가로 버전) - 기본 Godot
## 스크롤바가 이 UI 톤이랑 안 맞아서 눈에 띈다(사용자 지시, 2026-09-03 -
## "스크롤바 디자인 너무 밤티라서 상점창이랑 맞춰줘").
const SCROLLBAR_HEIGHT := 4

## 상품 목록 전체를 감싸는 세로 ScrollContainer(RowsScroll)용 - _style_h_scrollbar()와
## 같은 배색/두께(shop_screen.gd._style_scrollbar()와도 동일)로 통일한다.
func _style_v_scrollbar(scroll: ScrollContainer) -> void:
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size = Vector2(SCROLLBAR_HEIGHT, 0)
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


func _style_h_scrollbar(scroll: ScrollContainer) -> void:
	var scrollbar := scroll.get_h_scroll_bar()
	scrollbar.custom_minimum_size = Vector2(0, SCROLLBAR_HEIGHT)
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


## _build_hd_outfit_card_row()와 완전히 같은 구조 - 크기/여백 상수까지
## 그대로 재사용한다(사용자 지시, 2026-09-04 - "레이아웃은 의상샵이랑 똑같이").
func _build_hd_hairstyle_card_row(shop_id: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, HD_OUTFIT_CARD_ICON_SIZE.y + 18 + SCROLLBAR_HEIGHT + 3)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", HD_OUTFIT_CARD_SEPARATION)
	scroll.add_child(hbox)
	for listing in ShopManager.get_stock(shop_id):
		hbox.add_child(_build_hd_hairstyle_card(shop_id, listing))
	_style_h_scrollbar(scroll)
	return scroll


func _build_hd_hairstyle_card(shop_id: String, listing: Dictionary) -> Control:
	var item_id := String(listing.get("item_id", ""))
	var price := int(listing.get("price", 0))
	var style := item_id.trim_prefix(ShopManager.HD_HAIRSTYLE_ITEM_PREFIX)

	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(HD_OUTFIT_CARD_ICON_SIZE.x, 0)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 2)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = HD_OUTFIT_CARD_ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _hd_hairstyle_preview_texture(style)
	card.add_child(icon_rect)

	## 옷장이 잠겨있으면(WARDROBE_UNLOCK_NPC_ID/THRESHOLD) 헤어스타일도 어차피
	## 못 고르니 아웃핏 카드와 같은 기준으로 구매 버튼을 막는다.
	var buy_button := _build_buy_button(shop_id, item_id, price, not _is_wardrobe_unlocked())
	buy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(buy_button)

	return card


## _hd_outfit_preview_texture()와 달리 위쪽을 안 자른다 - 아웃핏 시트는 목
## 위(머리 부분)가 비어서 위를 잘라야 했지만, 헤어 시트는 반대로 머리/얼굴이
## 위쪽에 있고 목 아래(옷이 그려질 자리)가 비어있다.
func _hd_hairstyle_preview_texture(style: String) -> Texture2D:
	var path := PlayerController.hd_sprite_path(style)
	if not ResourceLoader.exists(path):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = Rect2(0, 0, PlayerController.HD_FRAME_WIDTH, PlayerController.HD_FRAME_HEIGHT)
	return atlas


func _build_hd_outfit_card(shop_id: String, listing: Dictionary) -> Control:
	var item_id := String(listing.get("item_id", ""))
	var price := int(listing.get("price", 0))
	var style := item_id.trim_prefix(ShopManager.HD_OUTFIT_ITEM_PREFIX)

	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(HD_OUTFIT_CARD_ICON_SIZE.x, 0)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 2)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = HD_OUTFIT_CARD_ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _hd_outfit_preview_texture(style)
	card.add_child(icon_rect)

	var buy_button := _build_buy_button(shop_id, item_id, price, not _is_wardrobe_unlocked())
	buy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(buy_button)

	return card


## _build_row()와 카드 뷰가 같이 쓰는 "가격 아이콘+가격이 가운데 얹힌 구매
## 버튼" - 중복 방지를 위해 공용화.
func _build_buy_button(shop_id: String, item_id: String, price: int, disabled: bool) -> Button:
	var buy_button := Button.new()
	buy_button.custom_minimum_size = Vector2(45, 16)
	buy_button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	buy_button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	buy_button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	buy_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	buy_button.pressed.connect(func() -> void: _on_buy_pressed(shop_id, item_id))
	# 구매 성공 시 AudioManager가 SFX_COIN을 따로 재생하므로(item_purchased 구독),
	# main.gd의 모달 공통 클릭음과 겹쳐서 나지 않도록 이 버튼만 제외한다.
	buy_button.add_to_group(&"_no_click_sfx")
	buy_button.disabled = disabled

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buy_button.add_child(center)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 2)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(price_row)

	var price_icon := TextureRect.new()
	price_icon.custom_minimum_size = Vector2(COIN_ICON_MAX_WIDTH, COIN_ICON_MAX_WIDTH)
	price_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	price_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	price_icon.texture = COIN_ICON
	price_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(price_icon)

	var price_label := Label.new()
	price_label.text = EconomyManager.format_gold(price)
	price_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	price_label.modulate = BUTTON_TEXT_COLOR
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(price_label)

	return buy_button


func _is_wardrobe_unlocked() -> bool:
	return NPCManager.has_shown_event(WARDROBE_UNLOCK_NPC_ID, WARDROBE_UNLOCK_THRESHOLD)


## player_outfit_<style>.png 전체 시트에서 south 그룹 idle 프레임(맨 앞 32x64)
## 만 오려서 보여준다(사용자 지시, 2026-09-03 - "이미지는 그냥 south 방향
## 정지 써주고") - 16x16 아이템 아이콘 그리드 규격과 안 맞아서 별도 처리.
## 위쪽 16px은 잘라낸다(사용자 지시, 2026-09-03 - "의상실 썸네일 이미지 위에
## 16px 만큼 높이 크롭해줘") - 아웃핏 시트는 목 위가 투명이라 그대로 두면
## 썸네일 위쪽 절반 가까이가 빈 공간으로 뜬다.
const PREVIEW_CROP_TOP := 16

func _hd_outfit_preview_texture(style: String) -> Texture2D:
	var path := PlayerController.hd_outfit_sprite_path(style)
	if not ResourceLoader.exists(path):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = Rect2(0, PREVIEW_CROP_TOP, PlayerController.HD_FRAME_WIDTH, PlayerController.HD_FRAME_HEIGHT - PREVIEW_CROP_TOP)
	return atlas


func _build_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.15)
	style.border_color = Color(0.35, 0.25, 0.15, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func _build_button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	return style


func _on_buy_pressed(shop_id: String, item_id: String) -> void:
	var failure_reason := ShopManager.buy(shop_id, item_id)
	if failure_reason.is_empty():
		_message_label.text = "주문했습니다. 다음 날 오전 9시에 배송됩니다."
	else:
		_message_label.text = failure_reason
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
	_refresh_rows()
