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

@onready var _close_button: TextureButton = $CloseButton
@onready var _rows: VBoxContainer = $ScaledContent/Margin/VBox/RowsScroll/Rows
@onready var _message_label: Label = $ScaledContent/Margin/VBox/MessageLabel


func _ready() -> void:
	_close_button.pressed.connect(func() -> void: closed.emit())


func refresh() -> void:
	_message_label.text = ""
	_refresh_rows()


func _refresh_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var online_shop_ids := _get_online_shop_ids()
	if online_shop_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "온라인으로 전환된 상점이 없습니다."
		empty_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		_rows.add_child(empty_label)
		return
	for shop_id in online_shop_ids:
		_rows.add_child(_build_header(shop_id))
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
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(12, 12)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = InventoryManager.get_item_icon_texture(item_id)
	row.add_child(icon_rect)

	var definition := InventoryManager.get_item_definition(item_id)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.custom_minimum_size = Vector2(90, 0)
	text_column.add_theme_constant_override("separation", 0)
	row.add_child(text_column)

	var name_label := Label.new()
	name_label.text = String(definition.get("name", item_id))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	text_column.add_child(name_label)

	var description_label := Label.new()
	description_label.text = String(definition.get("description", ""))
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	description_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	text_column.add_child(description_label)

	var buy_button := Button.new()
	buy_button.custom_minimum_size = Vector2(45, 16)
	# shop_screen.gd와 동일 - 설명이 여러 줄로 늘어나도 버튼은 1줄 크기로
	# 고정하고 세로 중앙에 배치한다.
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	buy_button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	buy_button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	buy_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	buy_button.pressed.connect(func() -> void: _on_buy_pressed(shop_id, item_id))
	# 구매 성공 시 AudioManager가 SFX_COIN을 따로 재생하므로(item_purchased 구독),
	# main.gd의 모달 공통 클릭음과 겹쳐서 나지 않도록 이 버튼만 제외한다.
	buy_button.add_to_group(&"_no_click_sfx")
	row.add_child(buy_button)

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

	return panel


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
