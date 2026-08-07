extends Node

## 장비(모자/신발/손) 착용 상태를 관리한다. 상태창(TAB) 장비 탭에서 인벤토리
## 아이템을 슬롯으로 드래그해서 착용/해제하는 데 쓰인다. 모자/신발은 능력치
## 효과가 기획에 명시된 바 없어 착용 여부만 추적하는 코스메틱이지만, "손"
## 슬롯(낚싯대 등 category=="tool")은 실제로 장착 여부가 게임플레이(낚시
## 가능 여부)에 영향을 준다.

signal equipment_changed

const EQUIP_SLOTS := ["hat", "hand", "shoes"]
const HAND_SLOT := "hand"
## equip_item()이 받아줄 카테고리 - hat/shoes(코스메틱 "equipment")와 낚싯대
## 같은 "tool"을 같은 슬롯 시스템에 태운다. equipment_slot.gd의 드롭 판정도
## 이 목록을 그대로 참조해서 카테고리 판단 로직이 두 곳으로 흩어지지 않게 한다.
## "material"도 포함하는 이유: 여물(animal_feed)은 재료 카테고리라 스택
## 99개가 맞지만, 축산 급여는 낚싯대와 똑같이 "손에 장착 후 상호작용" UX를
## 쓴다(사용자 지시) - slot 필드가 "hand"로 명시된 아이템만 실제로 통과되므로
## (아래 equip_item()), 이 카테고리 추가가 다른 재료를 장착 가능하게 만들지는
## 않는다.
## "gift"도 포함하는 이유: 선물을 NPC에게 주는 것도 여물 급여와 같은
## "손에 장착 후 상호작용" UX로 만들기로 함(사용자 지시). 개수는 여물과
## 달리 1개씩만 든다(STACKABLE_CATEGORIES에는 없음 - 선물은 한 번에 한
## NPC에게 하나씩 주는 개별 행동이라 스택 들기가 안 맞음).
const EQUIPPABLE_CATEGORIES := ["equipment", "tool", "material", "gift"]
## 여물처럼 스택 가능한 재료를 장착할 땐 인벤토리에 있는 만큼 전부 손에
## 들고, consume_equipped()로 한 개씩 소모한다 - 하나 주고 다시 장착하고를
## 반복하지 않게 하기 위함(사용자 지시: "5개를 샀으면 장비창에 5개가
## 들어가게"). 모자/신발/도구(낚싯대·양동이·작은 칼 등)는 원래부터 1개
## 단위라 그대로 1개씩 취급된다.
const STACKABLE_CATEGORIES := ["material"]

var _equipped: Dictionary = {"hat": "", "shoes": "", "hand": ""}
## 장착된 개수 - 도구류는 항상 1, 스택 가능한 재료만 1보다 클 수 있다.
var _equipped_counts: Dictionary = {"hat": 0, "shoes": 0, "hand": 0}


func get_equipped(slot: String) -> String:
	return String(_equipped.get(slot, ""))


## 상태창 장비 슬롯이 개수 표시(여물 5개 등)에 쓴다.
func get_equipped_count(slot: String) -> int:
	return int(_equipped_counts.get(slot, 0))


## STACKABLE_CATEGORIES에 속해도, 그 아이템의 실제 인벤토리 스택 한도
## (InventoryManager.get_stack_limit, 아이템별 "stack_limit" 오버라이드 포함)가
## 1이면 손에도 하나만 들린다 - storage_box(보관함)가 여물(animal_feed)과
## 같은 "material" 카테고리라 원래는 인벤토리에 있는 만큼 전부 손에 잡혔는데,
## 상자를 가구처럼(슬롯당 1개) 바꾼 뒤에도 이 부분만 예전 그대로라 3개가
## 한꺼번에 손에 들리던 버그가 있었다(사용자 리포트). "gift"처럼 애초에
## STACKABLE_CATEGORIES에 없는 카테고리는 이 함수와 무관하게 항상 1개.
func _is_stackable_equip(item_id: String) -> bool:
	return STACKABLE_CATEGORIES.has(String(InventoryManager.get_item_category(item_id))) \
		and InventoryManager.get_stack_limit(item_id) > 1


## 인벤토리에 있는 item_id를 착용한다. 스택 가능한 재료는 인벤토리에 있는
## 전체 개수를 한 번에 손에 들고, 그 외(도구/코스메틱)는 1개만 옮긴다. 그
## 슬롯에 이미 착용 중이던 게 있으면 인벤토리로 돌려준다(인벤토리가 꽉 차서
## 돌려줄 수 없으면 착용 자체를 취소한다).
func equip_item(item_id: String) -> bool:
	var definition := InventoryManager.get_item_definition(item_id)
	if not EQUIPPABLE_CATEGORIES.has(String(definition.get("category", ""))):
		return false
	var slot := String(definition.get("slot", ""))
	if not EQUIP_SLOTS.has(slot):
		return false
	var stackable := _is_stackable_equip(item_id)
	var take_count := InventoryManager.get_item_count(item_id) if stackable else 1
	if take_count <= 0 or not InventoryManager.remove_item(item_id, take_count):
		return false
	var previous := String(_equipped.get(slot, ""))
	var previous_count := get_equipped_count(slot)
	if not previous.is_empty() and not InventoryManager.add_item(previous, previous_count):
		InventoryManager.add_item(item_id, take_count)
		return false
	_equipped[slot] = item_id
	_equipped_counts[slot] = take_count
	equipment_changed.emit()
	return true


## 슬롯을 클릭하면 착용 해제하고 (남은 개수 전부) 인벤토리로 돌려준다.
func unequip(slot: String) -> bool:
	if not EQUIP_SLOTS.has(slot):
		return false
	var current := String(_equipped.get(slot, ""))
	if current.is_empty():
		return false
	if not InventoryManager.add_item(current, get_equipped_count(slot)):
		return false
	_equipped[slot] = ""
	_equipped_counts[slot] = 0
	equipment_changed.emit()
	return true


## 여물처럼 한 번 쓰면 사라지는 소모성 장비를 한 개 소모한다 - unequip()과
## 달리 인벤토리로 돌려주지 않는다(LivestockManager.perform_feed()가 급여
## 성공 시 호출). 여러 개를 들고 있었으면 개수만 줄고, 마지막 1개를 쓰면
## 슬롯이 완전히 빈다.
func consume_equipped(slot: String) -> void:
	if not EQUIP_SLOTS.has(slot) or String(_equipped.get(slot, "")).is_empty():
		return
	var remaining := get_equipped_count(slot) - 1
	if remaining > 0:
		_equipped_counts[slot] = remaining
	else:
		_equipped[slot] = ""
		_equipped_counts[slot] = 0
	equipment_changed.emit()


## 이미 손에 장착된 스택형 재료(여물 등)와 종류가 같으면, 새로 들어오는
## 수량을 인벤토리 새 칸이 아니라 장비창 수량에 바로 합친다(사용자 리포트 -
## 여물을 장착한 채로 더 사면 기존 것과 안 합쳐지고 인벤토리에 따로 쌓임).
## count가 음수면 되돌리기용(구매 실패 롤백)으로도 쓴다. 흡수하지 못했으면
## (장착 중이 아니거나 다른 아이템/비스택형이면) count를 그대로 돌려주고,
## 호출부가 그 나머지를 InventoryManager.add_item()으로 넘겨야 한다.
func top_up_equipped(item_id: String, count: int) -> int:
	for slot in EQUIP_SLOTS:
		if String(_equipped.get(slot, "")) != item_id:
			continue
		if not _is_stackable_equip(item_id):
			continue
		_equipped_counts[slot] = maxi(get_equipped_count(slot) + count, 0)
		equipment_changed.emit()
		return 0
	return count


func get_save_data() -> Dictionary:
	return {"equipped": _equipped.duplicate(), "counts": _equipped_counts.duplicate()}


## data가 예전 형식(개수 개념이 없던 시절 - {"hat": "...", "shoes": "...",
## "hand": "..."} 그대로 최상위)이면, 착용된 아이템마다 개수 1로 간주해서
## 자연스럽게 새 형식으로 승격한다.
func load_save_data(data: Dictionary) -> void:
	var equipped: Dictionary = data.get("equipped", data)
	var counts: Dictionary = data.get("counts", {})
	_equipped = {"hat": "", "shoes": "", "hand": ""}
	_equipped_counts = {"hat": 0, "shoes": 0, "hand": 0}
	for slot in EQUIP_SLOTS:
		var item_id := String(equipped.get(slot, ""))
		if item_id.is_empty():
			continue
		_equipped[slot] = item_id
		_equipped_counts[slot] = int(counts.get(slot, 1))
	equipment_changed.emit()
