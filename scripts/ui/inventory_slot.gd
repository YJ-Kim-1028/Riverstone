extends TextureButton
class_name InventorySlot

## One inventory grid cell. Purely presentational - the owning screen (e.g.
## equipment_panel.gd) decides what goes in it via setup() and listens for
## clicks via slot_pressed.

signal slot_pressed(slot_index: int)
## 소비 아이템/레시피 아이템을 클릭-선택+버튼 없이 바로 쓰기 위한 우클릭
## 제스처(사용자 지시 - "레시피 아이템 설명대로 우클릭으로 사용"). Control의
## `gui_input` 신호를 그냥 듣기만 하는 방식이라, BaseButton이 내부적으로
## 처리하는 좌클릭(pressed)/드래그 동작에는 영향이 없다.
signal slot_right_clicked(slot_index: int)
## storage_screen.gd처럼 인벤토리가 아닌 데이터(상자 내용물)를 보여주는 다른
## 그리드와 서로 드래그로 아이템을 주고받아야 하는 화면에서 쓴다. 기본값
## false라 기존 사용처(equipment_panel.gd/kitchen_screen.gd)는 영향 없음.
signal slot_drop_received(source_tag: String, slot_index: int, data: Dictionary)

@onready var _icon: TextureRect = $Icon
@onready var _count_label: Label = $CountLabel

var slot_index := -1
## 어느 화면에서 왔는지 구분하는 태그(예: "bag"/"box") - 드래그 데이터에
## 실려서 드롭받는 쪽이 "내가 아닌 다른 그리드에서 왔다"를 판별하는 데 쓴다.
var source_tag := ""
var accepts_drops := false
## setup()이 받은 원본 데이터를 그대로 보관 - _get_drag_data()가
## InventoryManager를 직접 다시 조회하지 않고 이 값을 그대로 쓴다. 그래야
## 이 슬롯이 플레이어 인벤토리가 아닌 다른 데이터(상자 내용물 등)를 보여줄
## 때도 드래그가 실제로 화면에 보이는 것과 항상 일치한다("순수 표시용"
## 원칙 - 클래스 docstring 참고).
var _slot_data = null


func _ready() -> void:
	pressed.connect(func() -> void: slot_pressed.emit(slot_index))
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		slot_right_clicked.emit(slot_index)


func setup(index: int, slot_data) -> void:
	slot_index = index
	_slot_data = slot_data
	if slot_data == null:
		_icon.texture = null
		_count_label.text = ""
		return
	var item_id := String(slot_data.get("item_id", ""))
	var count := int(slot_data.get("count", 0))
	_icon.texture = InventoryManager.get_item_icon_texture(item_id)
	_count_label.text = str(count) if count > 1 else ""


## 조리기구/완성대 화면처럼 "인벤토리 전체를 보여주되 지금 쓸 수 없는 아이템은
## disabled 처리"하는 패턴에서 쓴다(new_cooking_system.md 3.3 확정 사항 -
## cooking_screen.gd의 INGREDIENT_LOCKED_TINT와 동일한 톤으로 어둡게 표시).
const DISABLED_TINT := Color(0.45, 0.45, 0.45, 1.0)

func set_enabled(is_enabled: bool) -> void:
	disabled = not is_enabled
	modulate = Color.WHITE if is_enabled else DISABLED_TINT


## 상태창 장비 탭(장비 슬롯), 조리기구 화면(조리 슬롯) 등 여러 화면에서 이
## 슬롯을 드래그해 놓는 용도로 쓴다 - 종류 제한은 여기서 안 하고, 받는 쪽
## (_can_drop_data)이 알아서 맞는 것만 받아들인다(맞는 드롭 대상이 없는
## 화면에서는 그냥 아무 효과 없이 취소된다).
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _slot_data == null:
		return null
	var item_id := String(_slot_data.get("item_id", ""))
	var count := int(_slot_data.get("count", 0))
	if item_id.is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	# _icon과 똑같은 expand_mode/stretch_mode를 안 주면, 아이콘 그림(스프라이트
	# 시트에서 16x16으로 잘라낸 것)이 기본 EXPAND_KEEP_SIZE 때문에 슬롯 안
	# 실제 표시 크기(12x12)가 아니라 원본 16x16 크기로 그려진다 - 그러면 아래
	# "절반만큼 당기기" 보정이 실제 그려지는 크기와 안 맞아서 여전히 커서에서
	# 살짝 벗어나 보인다. _icon과 동일하게 맞춰서 실제로 12x12로 그려지게 한다.
	preview.expand_mode = _icon.expand_mode
	preview.stretch_mode = _icon.stretch_mode
	preview.size = _icon.size
	preview.custom_minimum_size = _icon.size
	# set_drag_preview()는 preview.position을 마우스 커서 기준 오프셋으로 쓴다 -
	# 기본값 (0,0)이면 아이콘 좌상단이 커서에 붙어서, 아이콘이 커서에서 오른쪽
	# 아래로 크게 떨어져 보인다는 피드백으로 커서가 아이콘 중앙에 오도록 절반만큼
	# 당겨준다.
	preview.position = -_icon.size / 2.0
	set_drag_preview(preview)
	return {"item_id": item_id, "count": count, "source": source_tag}


func _can_drop_data(_at_position: Vector2, data) -> bool:
	return accepts_drops and typeof(data) == TYPE_DICTIONARY and String(data.get("item_id", "")).length() > 0


func _drop_data(_at_position: Vector2, data) -> void:
	slot_drop_received.emit(source_tag, slot_index, data)
