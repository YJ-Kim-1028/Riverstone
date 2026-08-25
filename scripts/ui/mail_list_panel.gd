extends Control

## MailWindow(mail_app.gd)의 목록 화면 - 수신함/발신함 공용. 수신함은 아이콘
## (읽음/안읽음) + 제목 + 날짜, 발신함은 보낸 아이콘(icon_computer_send.png)
## + 제목 + 날짜.

signal row_selected(email_id: int)
## 요청함 전용(사용자 지시, 2026-08-25) - 일반 메일은 id가 정수라 row_selected를
## 그대로 쓰지만, 요청은 requests.json의 문자열 키가 id라서 신호를 따로 둔다.
signal request_selected(request_id: String)

const READ_ICON := preload("res://assets/ui/icon_computer_email_old.png")
const UNREAD_ICON := preload("res://assets/ui/icon_computer_email_new.png")
## 발신함 공용 + 초대 내역의 "visited"(방문함) 아이콘 - 빨간 하트(사용자 지시).
const SENT_ICON := preload("res://assets/ui/icon_computer_send.png")
## 초대 내역 전용 - 주황/회색 하트(사용자 지시: 빨간 하트=방문함 재사용,
## 주황=아직 결과 모름, 회색=그날 레스토랑을 안 열어서 못 옴). 아직 그림이
## 없을 수 있어 preload 대신 런타임 로드(없으면 단색 사각형 폴백,
## InventoryManager.get_item_icon_texture()와 같은 방식).
const PENDING_INVITE_ICON_PATH := "res://assets/ui/icon_computer_invite_pending.png"
const MISSED_INVITE_ICON_PATH := "res://assets/ui/icon_computer_invite_missed.png"
const PENDING_FALLBACK_COLOR := Color(0.9, 0.6, 0.1)
const MISSED_FALLBACK_COLOR := Color(0.5, 0.5, 0.5)
const ICON_SIZE := Vector2(3, 3)
const ROW_FONT_SIZE := 5
const DATE_FONT_SIZE := 4
const EMPTY_MESSAGE_FONT_SIZE := 4
## 행끼리 다닥다닥 붙어 보인다는 지적(사용자 지시, 2026-08-25) - 줄글노트처럼
## 각 행 밑에 얇은 구분선을 하나씩 넣는다. 스크롤바 grabber와 같은 갈색 계열,
## 다만 흐릿하게(줄노트 선 느낌).
const DIVIDER_COLOR := Color(0.55, 0.4, 0.25, 0.4)
const DIVIDER_HEIGHT := 1.0
## 호감도 탭/상점 화면 스크롤바랑 다르게 생겼다는 지적(사용자 지시,
## 2026-08-25) - affection_panel.gd/shop_screen.gd의 _style_scrollbar()와
## 완전히 같은 값으로 맞춘다.
const SCROLLBAR_WIDTH := 4

@onready var _rows_scroll: ScrollContainer = $RowsScroll
@onready var _rows: VBoxContainer = $RowsScroll/RowsMargin/Rows


func _ready() -> void:
	_style_scrollbar()


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


func display(entries: Array, is_sent: bool = false) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var ordered := entries.duplicate()
	ordered.reverse()
	if ordered.is_empty():
		var empty_label := Label.new()
		empty_label.text = "메일이 없습니다."
		empty_label.add_theme_font_size_override("font_size", EMPTY_MESSAGE_FONT_SIZE)
		empty_label.add_theme_color_override("font_color", Color.BLACK)
		_rows.add_child(empty_label)
		return
	for entry in ordered:
		_rows.add_child(_build_row(entry, is_sent))
		_rows.add_child(_build_divider())


## 초대 내역 전용 - 제목/읽음 아이콘 없이 날짜+수신인만 보여준다(사용자 지시).
## 클릭해서 들어갈 자세히보기 화면이 없어서 이 목록의 행은 버튼이 아니다.
func display_invite_history(entries: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var ordered := entries.duplicate()
	ordered.reverse()
	if ordered.is_empty():
		var empty_label := Label.new()
		empty_label.text = "초대 내역이 없습니다."
		empty_label.add_theme_font_size_override("font_size", EMPTY_MESSAGE_FONT_SIZE)
		empty_label.add_theme_color_override("font_color", Color.BLACK)
		_rows.add_child(empty_label)
		return
	for entry in ordered:
		_rows.add_child(_build_invite_row(entry))
		_rows.add_child(_build_divider())


## 요청함(사용자 지시, 2026-08-25) - EmailManager.get_active_requests()가 주는
## 목록을 그대로 받는다(완료된 요청은 애초에 그 목록에 안 들어있음). 목표를
## 이미 달성한 요청은 UNREAD_ICON(밝은 아이콘)으로, 아직이면 READ_ICON(흐린
## 아이콘)으로 구분해서 "지금 완료 가능한 게 있다"를 한눈에 보이게 한다.
func display_requests(requests: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()
	if requests.is_empty():
		var empty_label := Label.new()
		empty_label.text = "요청이 없습니다."
		empty_label.add_theme_font_size_override("font_size", EMPTY_MESSAGE_FONT_SIZE)
		empty_label.add_theme_color_override("font_color", Color.BLACK)
		_rows.add_child(empty_label)
		return
	for entry in requests:
		_rows.add_child(_build_request_row(entry))
		_rows.add_child(_build_divider())


func _build_request_row(entry: Dictionary) -> Control:
	var request_id := String(entry.get("id", ""))
	var expired := bool(entry.get("expired", false))
	var button := Button.new()
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: request_selected.emit(request_id))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)
	button.custom_minimum_size = Vector2(0, 10)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## 읽음/안읽음은 수신함과 똑같이 실제로 열어봤는지를 따른다(사용자 지시,
	## 2026-08-25) - "목표 달성"은 완전히 다른 축이라 아래 제목 글자색으로 따로
	## 표시한다(PENDING_FALLBACK_COLOR, 초대 내역의 "결과 대기" 주황과 같은 톤).
	icon_rect.texture = READ_ICON if EmailManager.is_request_read(request_id) else UNREAD_ICON
	row.add_child(icon_rect)

	var npc_id := String(entry.get("npc_id", ""))
	var title_label := Label.new()
	var title_text := String(entry.get("title", "")).replace("{player_name}", GameManager.player_name)
	## 만료 요청 표시(사용자 지시, 2026-08-25 - "요청함에 도착하고 4일 이내...
	## 만료 표시로") - 초대 내역의 "못 옴" 회색과 같은 톤을 재사용한다.
	title_label.text = "[만료] %s" % title_text if expired else title_text
	title_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	if expired:
		title_label.add_theme_color_override("font_color", MISSED_FALLBACK_COLOR)
	else:
		title_label.add_theme_color_override("font_color", PENDING_FALLBACK_COLOR if EmailManager.is_request_objective_met(request_id) else Color.BLACK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)

	var sender_label := Label.new()
	sender_label.text = String(NPCManager.get_definition(npc_id).get("name", npc_id))
	sender_label.add_theme_font_size_override("font_size", DATE_FONT_SIZE)
	sender_label.add_theme_color_override("font_color", Color.BLACK)
	sender_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(sender_label)

	return button


## 각 행 밑에 붙이는 얇은 구분선(사용자 지시, 2026-08-25) - 줄글노트처럼.
func _build_divider() -> Control:
	var divider := ColorRect.new()
	divider.color = DIVIDER_COLOR
	divider.custom_minimum_size = Vector2(0, DIVIDER_HEIGHT)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _build_invite_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _invite_icon_for(String(entry.get("outcome", "")))
	row.add_child(icon_rect)

	var npc_id := String(entry.get("npc_id", ""))
	var name_label := Label.new()
	name_label.text = String(NPCManager.get_definition(npc_id).get("name", npc_id))
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color.BLACK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var date_label := Label.new()
	date_label.text = String(entry.get("date", ""))
	date_label.add_theme_font_size_override("font_size", DATE_FONT_SIZE)
	date_label.add_theme_color_override("font_color", Color.BLACK)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(date_label)

	return row


## 하트 3색(사용자 지시): 방문함=빨강(SENT_ICON 재사용), 결과 미정=주황,
## 못 옴=회색. 과거 세이브(outcome 필드 자체가 없던 기록)는 "visited"와 같이
## 취급 - 이미 지나간 일이라 지금 와서 "결과 미정"으로 보일 이유가 없다.
func _invite_icon_for(outcome: String) -> Texture2D:
	match outcome:
		"pending":
			return _load_icon_or_fallback(PENDING_INVITE_ICON_PATH, PENDING_FALLBACK_COLOR)
		"missed":
			return _load_icon_or_fallback(MISSED_INVITE_ICON_PATH, MISSED_FALLBACK_COLOR)
		_:
			return SENT_ICON


func _load_icon_or_fallback(path: String, fallback_color: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var image := Image.create(int(ICON_SIZE.x), int(ICON_SIZE.y), false, Image.FORMAT_RGBA8)
	image.fill(fallback_color)
	return ImageTexture.create_from_image(image)


func _build_row(entry: Dictionary, is_sent: bool) -> Control:
	var button := Button.new()
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: row_selected.emit(int(entry.get("id", -1))))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)
	# Button은 Container가 아니라서 이렇게 add_child로 끼워넣은 자식(row)의
	# 크기가 버튼 자신의 최소 크기로 자동 반영되지 않는다 - 그래서 목록을 담은
	# VBoxContainer가 각 행에 실제 내용보다 훨씬 좁은 자리만 내주고 있었고,
	# 그 결과 행끼리 겹쳐 보였다. 고정 높이를 직접 줘서 해결한다.
	button.custom_minimum_size = Vector2(0, 10)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if is_sent:
		icon_rect.texture = SENT_ICON
	else:
		icon_rect.texture = READ_ICON if bool(entry.get("read", true)) else UNREAD_ICON
	row.add_child(icon_rect)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 0)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 3)
	text_column.add_child(title_row)

	var title_label := Label.new()
	# {player_name} 자리표시자 - mail_detail_panel.gd/dialogue_screen.gd와 동일한
	# 규칙(README 참고). 지금까지는 본문(lines)에서만 치환됐는데, 스토커 후반
	# 이메일 제목("조심해, {player_name}")처럼 제목에도 쓰이는 경우가 생겨서
	# 목록에서도 치환하도록 맞춤 - 안 하면 목록에 자리표시자 글자가 그대로 보임.
	title_label.text = String(entry.get("title", "")).replace("{player_name}", GameManager.player_name)
	title_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	title_label.add_theme_color_override("font_color", Color.BLACK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)

	## 목록에서 바로 누가 보냈는지/누구에게 보냈는지 보이면 좋겠다는 지적(사용자
	## 지시, 2026-08-25 - 요청함처럼) - 자세히보기에서만 보이던 이름을 목록에도
	## 노출한다.
	var sender_label := Label.new()
	sender_label.text = String(NPCManager.get_definition(String(entry.get("npc_id", ""))).get("name", ""))
	sender_label.add_theme_font_size_override("font_size", DATE_FONT_SIZE)
	sender_label.add_theme_color_override("font_color", Color.BLACK)
	sender_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(sender_label)

	var date_label := Label.new()
	date_label.text = String(entry.get("date", ""))
	date_label.add_theme_font_size_override("font_size", DATE_FONT_SIZE)
	date_label.add_theme_color_override("font_color", Color.BLACK)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text_column.add_child(date_label)

	return button
