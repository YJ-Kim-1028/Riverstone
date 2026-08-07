extends TextureButton
class_name KitchenSlot

## 조리기구 화면의 재료 투입/회수 슬롯 하나. 인벤토리 슬롯을 이 위로 드래그하면
## 원재료를 넣고(비어있을 때만), 다 조리되면 클릭해서 회수한다(kitchen_screen.gd가
## 실제 시작/회수 로직을 담당 - 이 스크립트는 드롭 판정만 한다).

signal item_dropped(item_id: String)

var station_id := ""


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or station_id.is_empty():
		return false
	return KitchenManager.can_start(station_id, String(data.get("item_id", "")))


func _drop_data(_at_position: Vector2, data) -> void:
	item_dropped.emit(String(data.get("item_id", "")))
