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
## 하트 5개 x 30점 = 호감도 최대 150 전부 표현(스타듀밸리 방식) - 사용자가
## icon_heart_full/half/empty.png를 8x8로 그려서 assets/ui/에 넣어줬다.
const HEART_SIZE := Vector2(8, 8)
const HEART_COUNT := 5
const POINTS_PER_HEART := 30
const HEART_FULL := preload("res://assets/ui/icon_heart_full.png")
const HEART_HALF := preload("res://assets/ui/icon_heart_half.png")
const HEART_EMPTY := preload("res://assets/ui/icon_heart_empty.png")
## shop_screen.gd의 _style_scrollbar()와 동일한 값 - 스크롤 화면마다 기본
## 스크롤바(두껍고 회색)를 따로 스타일링하고 있어서 창마다 굵기/색이 달라
## 보인다는 피드백으로, 상점 것과 똑같이 맞춘다.
const SCROLLBAR_WIDTH := 4

@onready var _rows_scroll: ScrollContainer = $RowsScroll
@onready var _rows: VBoxContainer = $RowsScroll/RowsMargin/Rows


func _ready() -> void:
	_style_scrollbar()


func refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for npc_id in NPCManager.get_all_ids():
		_rows.add_child(_build_row(npc_id))


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


func _build_row(npc_id: String) -> Control:
	var definition := NPCManager.get_definition(npc_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	## 아이콘 원본이 15x16이라, expand_mode를 안 주면 custom_minimum_size를
	## 무시하고 원본 크기 그대로 커진다(64x64 초상화 때와 같은 이유).
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_id := String(PORTRAIT_ICON_ID_OVERRIDES.get(npc_id, npc_id))
	var icon_path := PORTRAIT_ICON_DIR % icon_id
	if FileAccess.file_exists(icon_path):
		portrait.texture = load(icon_path)
	if not NPCManager.is_alive(npc_id):
		portrait.modulate = DEAD_TINT
	row.add_child(portrait)

	var name_label := Label.new()
	name_label.text = String(definition.get("name", npc_id))
	name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color.BLACK)
	name_label.custom_minimum_size = Vector2(26, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var hearts_row := HBoxContainer.new()
	hearts_row.add_theme_constant_override("separation", 1)
	hearts_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var affection := NPCManager.get_affection(npc_id)
	for i in HEART_COUNT:
		var heart := TextureRect.new()
		heart.custom_minimum_size = HEART_SIZE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.texture = _heart_texture_for(affection, i)
		hearts_row.add_child(heart)
	row.add_child(hearts_row)

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
