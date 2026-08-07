extends TextureButton
class_name EquipmentSlot

## 상태창 장비 탭의 슬롯 하나(모자 또는 신발). slot_name은 씬에서 인스턴스별로
## 지정한다("hat"/"shoes" - EquipmentManager.EQUIP_SLOTS와 일치해야 함).
## 인벤토리 슬롯(inventory_slot.gd)을 이 위로 드래그하면 착용된다. 빼는 것도
## 같은 방식(드래그해서 밖으로 꺼내면 해제)으로 통일했다(사용자 지시 - "넣는
## 건 드래그, 빼는 건 클릭"이라 통일성이 없다는 피드백). 클릭으로 해제하는
## 기존 방식도 그대로 남겨둔다(굳이 없앨 이유가 없어서 - 짧게 클릭하면 그대로
## 착용 해제, 길게 끌어서 놓으면 그 자리에서 해제).

## 맞지 않는 장비(예: 신발 칸에 모자)를 놓으려고 하면 쏜다 - _can_drop_data가
## false를 반환하는 것만으로는 화면에 아무 안내도 안 뜨므로, 별도로 감지해서
## 상위(EquipmentPanel)에 안내 문구를 띄우게 한다.
signal invalid_drop_attempted

@export var slot_name := ""

@onready var _icon: TextureRect = $Icon
@onready var _count_label: Label = $CountLabel

var _empty_texture: Texture2D = null
## 드래그 중 이 슬롯 위를 지나갈 때마다 _can_drop_data가 계속 호출되므로,
## "마지막으로 이 슬롯 위에 있던 게 종류는 맞는 장비인데 칸이 안 맞았는지"를
## 여기 기록해둔다. 실제 "마우스를 뗀 순간"은 NOTIFICATION_DRAG_END로 감지한다 -
## Godot의 드래그앤드롭은 거부된 드롭에서 _gui_input을 별도로 안 주기 때문에
## (드래그 중엔 뷰포트가 마우스 이벤트를 가로채 _can_drop_data/커서 갱신에만
## 쓴다), _gui_input으로는 감지가 안 됐다.
var _last_hover_mismatch := false
## 이 슬롯 자신의 장착 아이템을 드래그해서 꺼내는 중인지 - NOTIFICATION_DRAG_END
## 때 마우스가 이 슬롯을 벗어나 있으면 그 자리에서 해제한다.
var _dragging_self := false


func _ready() -> void:
	_empty_texture = texture_normal
	pressed.connect(_on_pressed)
	EquipmentManager.equipment_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var item_id := EquipmentManager.get_equipped(slot_name)
	_icon.texture = InventoryManager.get_item_icon_texture(item_id) if not item_id.is_empty() else null
	var count := EquipmentManager.get_equipped_count(slot_name)
	_count_label.text = str(count) if count > 1 else ""


func _on_pressed() -> void:
	EquipmentManager.unequip(slot_name)


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		_last_hover_mismatch = false
		return false
	var item_id := String(data.get("item_id", ""))
	var definition := InventoryManager.get_item_definition(item_id)
	var is_equippable := EquipmentManager.EQUIPPABLE_CATEGORIES.has(String(definition.get("category", "")))
	var matches := is_equippable and String(definition.get("slot", "")) == slot_name
	_last_hover_mismatch = is_equippable and not matches
	return matches


func _drop_data(_at_position: Vector2, data) -> void:
	if EquipmentManager.equip_item(String(data.get("item_id", ""))):
		AudioManager.play_sfx(AudioManager.SFX_UI_SLOT_IN)


## inventory_slot.gd의 _get_drag_data()와 같은 방식(아이콘 미리보기, 커서
## 중앙 정렬) - 여기선 인벤토리가 아니라 이 슬롯에 장착된 아이템 자체를 든다.
func _get_drag_data(_at_position: Vector2) -> Variant:
	var item_id := EquipmentManager.get_equipped(slot_name)
	if item_id.is_empty():
		return null
	_dragging_self = true
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.expand_mode = _icon.expand_mode
	preview.stretch_mode = _icon.stretch_mode
	preview.size = _icon.size
	preview.custom_minimum_size = _icon.size
	preview.position = -_icon.size / 2.0
	set_drag_preview(preview)
	return {"item_id": item_id, "count": EquipmentManager.get_equipped_count(slot_name), "source": "equipment"}


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	if _dragging_self:
		# 놓은 자리가 어디든(빈 공간/인벤토리 그리드 등 상관없이) 이 슬롯
		# 밖이면 해제 - 받는 쪽이 드롭을 실제로 처리했는지와 무관하게, "여기서
		# 벗어났다"는 사실 자체로 판단한다(도착지가 accepts_drops를 지원하는지
		# 몰라도 항상 동작해야 하므로).
		if not get_global_rect().has_point(get_global_mouse_position()):
			EquipmentManager.unequip(slot_name)
		_dragging_self = false
		return
	if _last_hover_mismatch and get_global_rect().has_point(get_global_mouse_position()):
		invalid_drop_attempted.emit()
	_last_hover_mismatch = false
