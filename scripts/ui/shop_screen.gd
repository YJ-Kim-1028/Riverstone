extends Control

## shop.md UI: 계산대 상호작용으로 열리는 구매 화면. Main이 shop_interacted
## 신호로 open_shop(shop_id)를 호출한다. 판매 목록이 없는 상품은 shop.md 문서
## 그대로 planned_stock에만 있고 stock은 비어있을 수 있다 (data/shop/README.md).

const ROW_FONT_SIZE := 7
const DESCRIPTION_FONT_SIZE := 5

const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const COIN_ICON := preload("res://assets/ui/icon_coin.png")
const COIN_ICON_MAX_WIDTH := 6

const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)

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

@onready var _rows_scroll: ScrollContainer = $Background/Margin/VBox/RowsScroll
@onready var _rows: VBoxContainer = $Background/Margin/VBox/RowsScroll/RowsMargin/Rows
@onready var _message_label: Label = $Background/Margin/VBox/MessageLabel
@onready var _close_button: TextureButton = $Background/CloseButton
@onready var _stall_picker: Control = $StallPicker
@onready var _stall_message_label: Label = $StallPicker/Panel/Margin/VBox/MessageLabel
@onready var _stall_row: HBoxContainer = $StallPicker/Panel/Margin/VBox/StallRow
@onready var _stall_cancel_button: Button = $StallPicker/Panel/Margin/VBox/CancelButton

var _shop_id := ""
var _is_open := false
var _pending_livestock_item_id := ""


func _ready() -> void:
	# Godot doesn't correctly resolve font color/modulate for controls built
	# while their ancestor's `visible` was ever false, even briefly - so this
	# screen stays `visible = true` for its whole life and is hidden/shown via
	# transparency + mouse_filter instead (see _set_open below).
	_set_open(false)
	_close_button.pressed.connect(close)
	_stall_cancel_button.pressed.connect(_close_stall_picker)
	_set_stall_picker_open(false)
	_style_scrollbar()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_shop(shop_id: String) -> void:
	_shop_id = shop_id
	_message_label.text = ""
	_refresh_rows()
	_set_open(true)


func close() -> void:
	_set_open(false)
	_close_stall_picker()
	_refresh_rows()


func _set_open(is_open: bool) -> void:
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	var filter := Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	$Background.mouse_filter = filter
	_close_button.mouse_filter = filter
	$Background/Margin.mouse_filter = filter
	$Background/Margin/VBox.mouse_filter = filter
	_rows_scroll.mouse_filter = filter
	_rows.mouse_filter = filter


func _refresh_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var stock: Array = ShopManager.get_stock(_shop_id)
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
		price_icon.texture = COIN_ICON
		price_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price_row.add_child(price_icon)

	var price_label := Label.new()
	price_label.text = "최대" if is_maxed else str(price)
	price_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	price_label.modulate = BUTTON_TEXT_COLOR
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(price_label)

	return panel


func _inventory_expansion_icon_texture() -> Texture2D:
	if not ResourceLoader.exists(INVENTORY_EXPANSION_ICON_SHEET):
		var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.6, 0.5, 0.3))
		return ImageTexture.create_from_image(image)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(INVENTORY_EXPANSION_ICON_SHEET)
	atlas.region = Rect2(INVENTORY_EXPANSION_ICON_INDEX * INVENTORY_EXPANSION_ICON_GRID_SIZE, 0, INVENTORY_EXPANSION_ICON_GRID_SIZE, INVENTORY_EXPANSION_ICON_GRID_SIZE)
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


## Godot's default ScrollContainer scrollbar is a thick engine-styled gray
## bar that doesn't match this UI's look and doesn't fit the small panel -
## shrink it and flatten its colors instead of drawing a new asset for it.
func _style_scrollbar() -> void:
	var scrollbar := _rows_scroll.get_v_scroll_bar()
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
	if ShopManager.buy(_shop_id, item_id):
		_message_label.text = "구매했습니다."
	else:
		_message_label.text = ""
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
	_refresh_rows()


## 가축은 배치할 칸을 먼저 골라야 해서, 산 자리에서 바로 확정하지 않고 이
## 작은 그리드 팝업을 연다(사용자 지시). 이미 동물이 있는 칸은 비활성 처리.
func _open_stall_picker(item_id: String) -> void:
	_pending_livestock_item_id = item_id
	var animal_definition := LivestockManager.get_animal_definition(item_id.trim_prefix(LIVESTOCK_PREFIX))
	_stall_message_label.text = "%s를 어느 칸에 배치할까요?" % String(animal_definition.get("name", ""))
	for child in _stall_row.get_children():
		child.queue_free()
	for i in STALL_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2(24, 16)
		button.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
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
	if ShopManager.buy(_shop_id, item_id, stall_index):
		_message_label.text = "구매했습니다."
	else:
		_message_label.text = ""
		AudioManager.play_sfx(AudioManager.SFX_BEEP)
	_refresh_rows()


func _set_stall_picker_open(is_open: bool) -> void:
	_stall_picker.modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(_stall_picker, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
