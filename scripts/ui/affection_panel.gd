extends Control

## 상태창(TAB) "호감도" 탭 - NPC 전원을 초상화+이름+호감도 진행바(0~150)
## 목록으로 보여준다. npc.md 사망 규칙대로 죽은 NPC는 초상화를 회색 처리한다.

const DEAD_TINT := Color(0.5, 0.5, 0.5)
const ROW_FONT_SIZE := 6
const PORTRAIT_SIZE := Vector2(10, 10)
## assets/npc/icon/의 머리만 딴 15x16 아이콘(사용자가 npc 스프라이트에서
## 직접 크롭) - 전신 초상화(64x64) 대신 이 목록에서 쓴다. 파일명이 npc_id와
## 다른 2명(lama->rama, shepherd->shep)만 예외 매핑.
const PORTRAIT_ICON_DIR := "res://assets/npc/icon/icon_%s.png"
const PORTRAIT_ICON_ID_OVERRIDES := {
	"lama": "rama",
	"shepherd": "shep",
}
## 하트 15개 x 10점 = 호감도 최대 150 전부 표현(사용자 지시, 2026-08-25 -
## 5개짜리보다 더 세밀하게). 한 줄에 다 못 들어가서 2줄로 나눠 보여준다
## (HEART_ROW_COLUMNS 참고) - 이름 자리는 그 위에 따로 둔다(_build_row 참고).
const HEART_SIZE := Vector2(8, 8)
const HEART_COUNT := 15
const POINTS_PER_HEART := 10
## 하트를 2줄로 나눌 때 한 줄에 몇 개씩 넣을지(15개 -> 8+7).
const HEART_ROW_COLUMNS := 8
const HEART_FULL := preload("res://assets/ui/icon_heart_full.png")
const HEART_HALF := preload("res://assets/ui/icon_heart_half.png")
const HEART_EMPTY := preload("res://assets/ui/icon_heart_empty.png")
## shop_screen.gd의 _style_scrollbar()와 동일한 값 - 스크롤 화면마다 기본
## 스크롤바(두껍고 회색)를 따로 스타일링하고 있어서 창마다 굵기/색이 달라
## 보인다는 피드백으로, 상점 것과 똑같이 맞춘다.
const SCROLLBAR_WIDTH := 4
## 고양이/강아지 호감도(사용자 지시, 2026-09-16 - "강아랑 고양도 호감도
## 있었으면 좋겠어") - NPCManager 정식 NPC 목록에 얹지 않고(NPC 스케줄/사망
## 등 다른 시스템과 얽히면 위험해서 cat_world_manager.gd 등과 동일하게 완전
## 분리) 이 화면에서만 별도로 그린다. 그 동물을 실제로 받은 뒤에야 나타난다
## (사용자 지시 - "얻고나서야 탭에서 보이는거지") - CatWorldManager/
## DogWorldManager의 CAT_AFFECTION_THRESHOLD/DOG_AFFECTION_THRESHOLD(둘 다
## 50)와 같은 값.
const PETS := [
	{"npc_id": "belje", "threshold": 50, "icon": "res://assets/npc/icon/icon_cat.png", "default_name": "고양이"},
	{"npc_id": "shepherd", "threshold": 50, "icon": "res://assets/npc/icon/icon_dog.png", "default_name": "강아지"},
]

@onready var _rows_scroll: ScrollContainer = $RowsScroll
@onready var _rows: VBoxContainer = $RowsScroll/RowsMargin/Rows


func _ready() -> void:
	_style_scrollbar()


func refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for npc_id in NPCManager.get_all_ids():
		_rows.add_child(_build_row(npc_id))
	for pet in PETS:
		if NPCManager.has_shown_event(String(pet.npc_id), int(pet.threshold)):
			_rows.add_child(_build_pet_row(pet))


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


## 하트 15개가 한 줄에 다 안 들어가서(사용자 지시, 2026-08-25) 세로로 쌓는다 -
## 윗줄은 초상화+이름, 아랫줄은 하트 2줄(GridContainer가 HEART_ROW_COLUMNS
## 개마다 자동으로 다음 줄로 넘긴다).
func _build_row(npc_id: String) -> Control:
	var definition := NPCManager.get_definition(npc_id)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	row.add_child(name_row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	## 아이콘 원본이 15x16이라, expand_mode를 안 주면 custom_minimum_size를
	## 무시하고 원본 크기 그대로 커진다(64x64 초상화 때와 같은 이유).
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_id := String(PORTRAIT_ICON_ID_OVERRIDES.get(npc_id, npc_id))
	var icon_path := PORTRAIT_ICON_DIR % icon_id
	# .png는 import를 거치는 리소스라 내보낸 빌드에서 원본 파일이 pck에 없다 -
	# FileAccess.file_exists()로 확인하면 빌드에서만 항상 false가 되어 아이콘이
	# 조용히 안 나온다(home_map.gd _find_tileset_image()와 같은 원인).
	if ResourceLoader.exists(icon_path):
		portrait.texture = load(icon_path)
	if not NPCManager.is_alive(npc_id):
		portrait.modulate = DEAD_TINT
	name_row.add_child(portrait)

	var name_label := Label.new()
	name_label.text = String(definition.get("name", npc_id))
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color.BLACK)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(name_label)

	var hearts_grid := GridContainer.new()
	hearts_grid.columns = HEART_ROW_COLUMNS
	hearts_grid.add_theme_constant_override("h_separation", 1)
	hearts_grid.add_theme_constant_override("v_separation", 1)
	var affection := NPCManager.get_affection(npc_id)
	for i in HEART_COUNT:
		var heart := TextureRect.new()
		heart.custom_minimum_size = HEART_SIZE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.texture = _heart_texture_for(affection, i)
		hearts_grid.add_child(heart)
	row.add_child(hearts_grid)

	return row


## _build_row()와 거의 같은 구조지만 NPCManager.get_affection() 대신
## NPCManager.get_pet_affection()을 본다 - 고양이/강아지는 NPC가 아니라서
## definition/사망 여부가 없다.
func _build_pet_row(pet: Dictionary) -> Control:
	var npc_id := String(pet.npc_id)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	row.add_child(name_row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path := String(pet.icon)
	if ResourceLoader.exists(icon_path):
		portrait.texture = load(icon_path)
	name_row.add_child(portrait)

	var name_label := Label.new()
	var pet_name := NPCManager.get_pet_name(npc_id)
	name_label.text = pet_name if not pet_name.is_empty() else String(pet.default_name)
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color.BLACK)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(name_label)

	var hearts_grid := GridContainer.new()
	hearts_grid.columns = HEART_ROW_COLUMNS
	hearts_grid.add_theme_constant_override("h_separation", 1)
	hearts_grid.add_theme_constant_override("v_separation", 1)
	var affection := NPCManager.get_pet_affection(npc_id)
	for i in HEART_COUNT:
		var heart := TextureRect.new()
		heart.custom_minimum_size = HEART_SIZE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.texture = _heart_texture_for(affection, i)
		hearts_grid.add_child(heart)
	row.add_child(hearts_grid)

	return row


## 하트 i번째(0-indexed)가 가득/반/빈 상태 중 뭘 보여줄지 판정한다 - 하트 하나가
## POINTS_PER_HEART(30)점을 나타낸다(0~150을 하트 5개로 표현).
func _heart_texture_for(affection: int, heart_index: int) -> Texture2D:
	var threshold := (heart_index + 1) * POINTS_PER_HEART
	if affection >= threshold:
		return HEART_FULL
	if affection >= threshold - POINTS_PER_HEART / 2:
		return HEART_HALF
	return HEART_EMPTY
