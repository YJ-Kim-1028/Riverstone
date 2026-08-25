extends Control

## home_interior.tmx의 "collection"(책장) 오브젝트로 열리는 도감 화면.
## 왼쪽 페이지는 레시피 도감, 오른쪽 페이지는 추억의 물건 도감 - 각자 따로
## 페이지를 넘긴다(사용자 확정, references/refer_collection.png 참고).
## CollectionManager.get_all_recipe_entries()/get_all_memento_entries()가
## 이미 획득 여부를 관리하고 있어서, 이 화면은 그 데이터를 페이지당 3x3(9개)
## 슬롯 그리드로 보여주기만 한다. 물건별 개별 아이콘은 아직 없어서(사용자
## 확정) 슬롯은 얻었는지 여부로만 slot_book/slot_book_unknown을 바꿔 끼우고,
## 이름/설명은 슬롯에 마우스를 올렸을 때 뜨는 툴팁으로 보여준다.
## 닫기는 버튼 없이 ESC 전용(사용자 확정 - 책 디자인에 맞는 닫기 버튼이
## 없어서, 다른 화면들도 다 지원하는 ESC로 통일).
## shop_screen.gd와 동일하게 "항상 visible=true, modulate.a + mouse_filter로
## 열고 닫기" 패턴을 쓴다 (Godot이 ancestor.visible=false였던 적 있는
## 컨트롤의 폰트/테마를 잘못 그리는 문제 회피용).

const SLOTS_PER_PAGE := 9
const SLOT_SIZE := 6
const TOOLTIP_FONT_SIZE := 5
## 마우스 커서 바로 아래로(오른쪽 아래 살짝) - 이 화면 로컬 좌표 기준 오프셋.
const TOOLTIP_OFFSET := Vector2(4, 4)

const SLOT_ACQUIRED_TEXTURE := preload("res://assets/ui/slot_book.png")
const SLOT_LOCKED_TEXTURE := preload("res://assets/ui/slot_book_unknown.png")

@onready var _recipe_grid: GridContainer = $RecipeGrid
@onready var _memento_grid: GridContainer = $MementoGrid
@onready var _recipe_prev: TextureButton = $RecipePrevButton
@onready var _recipe_next: TextureButton = $RecipeNextButton
@onready var _memento_prev: TextureButton = $MementoPrevButton
@onready var _memento_next: TextureButton = $MementoNextButton

var _is_open := false
var _recipe_page := 0
var _memento_page := 0
var _tooltip_panel: PanelContainer
var _tooltip_label: Label


func _ready() -> void:
	_recipe_prev.pressed.connect(func() -> void: _change_recipe_page(-1))
	_recipe_next.pressed.connect(func() -> void: _change_recipe_page(1))
	_memento_prev.pressed.connect(func() -> void: _change_memento_page(-1))
	_memento_next.pressed.connect(func() -> void: _change_memento_page(1))
	_build_tooltip_panel()
	_set_open(false)


## 이 화면 루트(CollectionScreen)가 scale=3으로 확대되어 있어서(scenes/ui/
## collection_screen.tscn), Godot 기본 툴팁 팝업의 위치 계산이 이 배율을 제대로
## 반영하지 못해 슬롯 위치에 따라 툴팁이 커서에서 제각각 떨어져 보이는
## 문제가 있었다(사용자 리포트) - 게다가 획득한 레시피 슬롯 위에 올라간 요리
## 아이콘(mouse_filter=IGNORE)이 _set_open()의 재귀 필터 적용 순서 때문에 STOP로
## 덮어써져서 그 위에서는 툴팁 자체가 아예 안 뜨는 별도 버그도 있었다(위 open()
## 참고). 기본 tooltip_text 대신, 같은 스케일 트리 안에서 직접 위치를 계산하는
## 수동 패널로 교체해서 두 문제를 한 번에 해결한다.
func _process(_delta: float) -> void:
	if not _is_open:
		return
	_update_tooltip()


func _update_tooltip() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var text := ""
	if hovered != null and hovered.has_meta(&"tooltip_text"):
		text = String(hovered.get_meta(&"tooltip_text"))
	if text.is_empty():
		_tooltip_panel.visible = false
		return
	_tooltip_label.text = text
	_tooltip_panel.visible = true
	_tooltip_panel.reset_size()
	# _tooltip_panel.scale(1/3)로 화면에 실제 그려지는 크기는 축소되지만,
	# .size 자체는 축소 "전" 크기를 그대로 보고하므로(Godot의 scale은 layout이
	# 아니라 렌더링에만 영향) 클램핑은 실제 화면 발자국(size*scale) 기준으로
	# 계산해야 한다.
	var effective_size := _tooltip_panel.size * _tooltip_panel.scale
	var pos := get_local_mouse_position() + TOOLTIP_OFFSET
	pos.x = clampf(pos.x, 0.0, maxf(size.x - effective_size.x, 0.0))
	pos.y = clampf(pos.y, 0.0, maxf(size.y - effective_size.y, 0.0))
	_tooltip_panel.position = pos


## 엔진 기본 툴팁(큼직한 회색 박스)이 이 작은 픽셀아트 책이랑 안 어울려서
## 직접 배경/폰트를 작게 그린다(_build_slot()이 붙이는 "tooltip_text" 메타를
## 읽어서 이 패널 하나로 모든 슬롯의 툴팁을 대신한다).
func _build_tooltip_panel() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100
	# 이 화면 루트가 scale=3이라(ScaledContent가 라벨에 이미 쓰고 있는 것과
	# 동일한 상쇄 기법), 이 패널도 1/3로 줄여 순 배율을 1배로 되돌린다 -
	# 안 그러면 TOOLTIP_FONT_SIZE가 그대로 3배 커져 보인다(사용자 리포트).
	_tooltip_panel.scale = Vector2(1.0 / 3.0, 1.0 / 3.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.98, 0.93, 0.82, 0.95)
	panel_style.border_color = Color(0.42, 0.27, 0.15, 1)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(1)
	panel_style.content_margin_left = 3.0
	panel_style.content_margin_right = 3.0
	panel_style.content_margin_top = 1.0
	panel_style.content_margin_bottom = 1.0
	_tooltip_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_tooltip_panel)
	_tooltip_label = Label.new()
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.add_theme_font_size_override("font_size", TOOLTIP_FONT_SIZE)
	_tooltip_label.add_theme_color_override("font_color", Color(0.42, 0.27, 0.15, 1))
	_tooltip_panel.add_child(_tooltip_label)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open() -> void:
	_recipe_page = 0
	_memento_page = 0
	# 순서 중요: _set_open(true)를 먼저 호출해야 한다 - 그 안의
	# _apply_mouse_filter_recursive()가 서브트리 전체를 재귀로 STOP으로
	# 덮어쓰는데, 이걸 그리드를 채운 "다음"에 하면 _build_slot()이 획득한
	# 레시피 아이콘에 일부러 준 MOUSE_FILTER_IGNORE(슬롯 밑 툴팁이 보이게
	# 하려고)까지 STOP으로 덮어써버려서, 아이콘이 슬롯 대신 마우스를 가로채
	# 툴팁이 안 뜨는 버그가 있었다(사용자 리포트 - 미획득 슬롯은 아이콘이 없어
	# 멀쩡했음). 먼저 열어둔 뒤 슬롯을 채우면 이후 이 함수가 그 슬롯들을 다시
	# 건드리지 않으니 각자 지정한 필터가 그대로 유지된다.
	_set_open(true)
	_refresh_recipe_page()
	_refresh_memento_page()
	AudioManager.play_sfx(AudioManager.SFX_COLLECTION_OPEN, AudioManager.SFX_COLLECTION_VOLUME_DB)


func close() -> void:
	_set_open(false)
	for child in _recipe_grid.get_children():
		child.queue_free()
	for child in _memento_grid.get_children():
		child.queue_free()


func _set_open(is_open: bool) -> void:
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	# 자식을 하나하나 나열해서 끄면 Background/라벨처럼 목록에서 빠뜨린
	# 컨트롤이 기본값(MOUSE_FILTER_STOP)으로 남아있게 된다 - 실제로 이 화면을
	# 닫아도 그 배경이 계속 클릭을 먹어서 같은 자리의 컴퓨터 창이 하나도 안
	# 눌리는 버그가 있었다. computer_screen.gd와 동일하게 전체 서브트리를
	# 재귀적으로 순회해서 빠짐없이 처리한다.
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
	# 위 재귀 호출이 툴팁 패널도 같이 STOP으로 덮어써버리므로(열려있는 동안
	# 클릭을 가로채면 안 됨) 매번 다시 IGNORE로 되돌린다. 닫을 때는 _process()가
	# 더 이상 안 돌아서 스스로 안 사라지니 여기서 직접 숨긴다(ESC로 닫아도
	# 마우스가 슬롯 위에 남아있으면 툴팁이 계속 떠 있던 문제).
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_open:
		_tooltip_panel.visible = false


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _change_recipe_page(direction: int) -> void:
	var last_page := (CollectionManager.get_all_recipe_entries().size() - 1) / SLOTS_PER_PAGE
	var new_page := clampi(_recipe_page + direction, 0, last_page)
	if new_page == _recipe_page:
		return
	_recipe_page = new_page
	_refresh_recipe_page()
	AudioManager.play_sfx(AudioManager.SFX_COLLECTION_MOVE, AudioManager.SFX_COLLECTION_VOLUME_DB)


func _change_memento_page(direction: int) -> void:
	var last_page := (CollectionManager.get_all_memento_entries().size() - 1) / SLOTS_PER_PAGE
	var new_page := clampi(_memento_page + direction, 0, last_page)
	if new_page == _memento_page:
		return
	_memento_page = new_page
	_refresh_memento_page()
	AudioManager.play_sfx(AudioManager.SFX_COLLECTION_MOVE, AudioManager.SFX_COLLECTION_VOLUME_DB)


func _refresh_recipe_page() -> void:
	var entries := CollectionManager.get_all_recipe_entries()
	_fill_grid(_recipe_grid, entries, _recipe_page * SLOTS_PER_PAGE, true)
	var last_page := (entries.size() - 1) / SLOTS_PER_PAGE
	_recipe_prev.visible = _recipe_page > 0
	_recipe_next.visible = _recipe_page < last_page


func _refresh_memento_page() -> void:
	var entries := CollectionManager.get_all_memento_entries()
	_fill_grid(_memento_grid, entries, _memento_page * SLOTS_PER_PAGE, false)
	var last_page := (entries.size() - 1) / SLOTS_PER_PAGE
	_memento_prev.visible = _memento_page > 0
	_memento_next.visible = _memento_page < last_page


func _fill_grid(grid: GridContainer, entries: Array, start_index: int, is_recipe: bool) -> void:
	for child in grid.get_children():
		child.queue_free()
	for i in SLOTS_PER_PAGE:
		var index := start_index + i
		if index < entries.size():
			grid.add_child(_build_slot(entries[index], is_recipe))
		else:
			grid.add_child(_build_empty_slot())
	# _update_tooltip()이 매 프레임 gui_get_hovered_control()을 직접 확인하므로
	# (tooltip_text 기반 엔진 툴팁과 달리 "마우스 움직임 이벤트"에 의존하지
	# 않음), 슬롯을 새로 만든 직후 마우스가 이미 그 위에 있어도 다음 프레임에
	# 바로 반영된다 - 예전엔 이걸 위해 마우스를 강제로 재이동시키는 우회가
	# 필요했지만 이제 필요 없다.


## recipes.json의 ingredient_pairs(재료 id 쌍의 배열 - 한 레시피가 여러 조합을
## 허용할 수 있음, 예: 생선 구이는 고등어+고등어/고등어+연어/연어+연어 전부
## 가능)를 "찐 고등어 + 찐 고등어" 같은 표시용 이름 문자열로 바꾼다.
func _format_ingredient_pairs(pairs: Array) -> String:
	var lines: Array = []
	for pair in pairs:
		if not (pair is Array) or pair.size() != 2:
			continue
		var a := String(InventoryManager.get_item_definition(String(pair[0])).get("name", String(pair[0])))
		var b := String(InventoryManager.get_item_definition(String(pair[1])).get("name", String(pair[1])))
		lines.append("%s + %s" % [a, b])
	return "\n".join(lines)


func _build_slot(entry: Dictionary, is_recipe: bool) -> TextureButton:
	var acquired := bool(entry.get("acquired", false))
	var slot := _build_empty_slot()
	slot.texture_normal = SLOT_ACQUIRED_TEXTURE if acquired else SLOT_LOCKED_TEXTURE
	# 레시피는 "owner" 개념이 없어서 name으로 대체 - 설명(맛 표현 등)은 요청에
	# 따라 뺐지만, 조합법(어떤 재료 2개를 합쳐야 하는지)은 플레이어가 다
	# 기억 못 할 거라는 피드백으로 획득한 레시피에 한해 따로 붙인다.
	var tooltip := String(entry.get("owner", entry.get("name", "")))
	if is_recipe and acquired:
		var pairs_text := _format_ingredient_pairs(CookingManager.get_recipe_definition(String(entry.get("recipe_id", ""))).get("ingredient_pairs", []))
		if not pairs_text.is_empty():
			tooltip += "\n" + pairs_text
	slot.set_meta(&"tooltip_text", tooltip)
	# 레시피는 CookingManager.get_recipe_icon_texture()로, 추억의 물건은
	# memento.png(사용자가 2026-08-25 13장 직접 그려 등록)로 InventoryManager를
	# 통해 실제 그림을 얻는다 - 둘 다 획득한 것만 슬롯 배경 위에 겹쳐 보여준다.
	if acquired:
		var icon_texture: Texture2D = CookingManager.get_recipe_icon_texture(String(entry.get("recipe_id", ""))) if is_recipe \
			else InventoryManager.get_item_icon_texture("memento_%s" % String(entry.get("npc_id", "")))
		if icon_texture != null:
			var icon := TextureRect.new()
			icon.texture = icon_texture
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.anchor_right = 1.0
			icon.anchor_bottom = 1.0
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot.add_child(icon)
	return slot


func _build_empty_slot() -> TextureButton:
	var slot := TextureButton.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.ignore_texture_size = true
	slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	return slot
