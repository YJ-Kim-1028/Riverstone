extends Node

## Owns the shop catalog (data/shop/shops.json), purchase transactions, the
## death-succession/online-conversion rules from shop.md, and the online
## shop's next-day-9am delivery queue. Payment goes through EconomyManager;
## items go through InventoryManager. A stock listing only appears once its
## price is actually known - see data/shop/README.md for what's still open.

signal item_purchased(shop_id: String, item_id: String, price: int)
signal shop_mode_changed(shop_id: String, mode: String)

const SHOPS_PATH := "res://data/shop/shops.json"
## 가축(소/돼지)은 인벤토리 아이템이 아니라 외양간 칸에 배치되는 대상이라
## data/shop/README.md가 이미 지적한 대로 별도 분기가 필요하다 - item_id가
## 이 접두사로 시작하면 buy()가 stall_index를 받아 LivestockManager로
## 넘긴다(일반 아이템처럼 InventoryManager.add_item()을 타지 않는다).
const LIVESTOCK_PREFIX := "livestock:"
## 인벤토리 칸 확장 - 인벤토리 아이템이 아니라 EconomyManager.expand_inventory()를
## 직접 호출하는 특수 항목이라 별도 분기가 필요하다(가축과 같은 이유). 가격이
## 고정이 아니라 현재 slot_count에 따라 달라져서(EconomyManager.
## INVENTORY_EXPANSION_COST) shops.json에는 price를 안 적어둔다 - UI가
## get_inventory_expansion_cost()로 매번 다시 조회해서 보여준다.
const INVENTORY_EXPANSION_ITEM_ID := "inventory_expansion"

var _shops: Dictionary = {}
var _purchase_counts: Dictionary = {}
var _pending_deliveries: Array = []


func _ready() -> void:
	_load_shops()
	TimeManager.day_changed.connect(_on_day_changed)
	NPCManager.npc_died.connect(_on_npc_died)


func get_shop_ids() -> Array:
	return _shops.keys()


func get_shop_definition(shop_id: String) -> Dictionary:
	return _shops.get(shop_id, {})


## shop.md: "별도 승계 규칙이 명시되지 않은 상점은 운영 NPC 사망 시 즉시 온라인
## 상점으로 전환된다" + 벨제/셰퍼드, 마린/로시의 "한쪽이 죽으면 남은 쪽이
## 잇는다" 승계 규칙. owner_npc_ids 중 한 명이라도 살아있으면 "in_person"
## (1인 상점이든 2인 상점이든 동일한 결과이므로 둘을 구분할 필요가 없다).
func get_shop_mode(shop_id: String) -> String:
	for npc_id in (get_shop_definition(shop_id).get("owner_npc_ids", []) as Array):
		if NPCManager.is_alive(npc_id):
			return "in_person"
	return "online"


## shop.md의 사망 승계 규칙(get_shop_mode)과는 별개로, "지금 이 순간 정확히
## 스케줄상 근무 지점 좌표에 걸어서 도착해 있는 운영 NPC가 있는지" 확인한다 -
## 살아있어도 스케줄상 다른 곳에 있으면(자고 있거나 외출 중이거나) 계산대를
## 쓸 수 없어야 하고, 스케줄이 "여기 있어야 한다"고 막 바뀐 순간이라도 다구간
## 이동(혹은 같은 맵 안 이동)이 아직 끝나지 않았으면 안 된다. 그래서
## NPCManager.get_npc_world_position()(스케줄 기반 즉시 계산)이 아니라
## is_npc_settled_at()(NPCWorldManager가 정확한 좌표 도착을 확정한 값)을
## 써야 한다.
func is_staffed(shop_id: String) -> bool:
	var definition := get_shop_definition(shop_id)
	var shop_map := String(definition.get("map_id", ""))
	if shop_map.is_empty():
		return false
	for npc_id in (definition.get("owner_npc_ids", []) as Array):
		if not NPCManager.is_alive(npc_id):
			continue
		var resolved := NPCManager.get_npc_world_position(npc_id)
		if String(resolved.get("map_id", "")) != shop_map:
			continue
		if NPCManager.is_npc_settled_at(npc_id, shop_map, resolved.get("position", Vector2.INF)):
			return true
	return false


## purchase_limit이 있는 항목(만능 요리 레시피, 서점 책 등)은 그 한도를 다
## 채우면 목록에서 아예 빠진다(사용자 지시 - 눌러도 실패하는 비활성 버튼
## 대신, 더 살 수 없으면 안 보이는 쪽으로 통일).
func get_stock(shop_id: String) -> Array:
	var stock: Array = (get_shop_definition(shop_id).get("stock", []) as Array).duplicate(true)
	return stock.filter(func(listing: Dictionary) -> bool:
		var limit := int(listing.get("purchase_limit", 0))
		var item_id := String(listing.get("item_id", ""))
		return limit <= 0 or get_purchase_count(item_id) < limit
	)


func get_purchase_count(item_id: String) -> int:
	return int(_purchase_counts.get(item_id, 0))


## In-person purchase adds the item to the bag immediately; online purchase
## charges now and queues delivery for the next day's 09:00 (email.md/shop.md:
## "다음 날 오전 9시 우편함으로 배송"). Fails without charging if the shop
## doesn't sell the item, the purchase limit was reached, gold is short, or
## (in-person only) the inventory has no room.
## stall_index는 item_id가 "livestock:"로 시작할 때만 쓰인다(어느 외양간
## 칸에 배치할지) - 그 외 아이템은 무시한다.
func buy(shop_id: String, item_id: String, stall_index: int = -1) -> bool:
	if item_id.begins_with(LIVESTOCK_PREFIX):
		return _buy_livestock(shop_id, item_id, stall_index)
	if item_id == INVENTORY_EXPANSION_ITEM_ID:
		return _buy_inventory_expansion(shop_id, item_id)
	var listing := _find_listing(shop_id, item_id)
	if listing.is_empty():
		return false
	var price := int(listing.get("price", 0))
	var limit := int(listing.get("purchase_limit", 0))
	if limit > 0 and get_purchase_count(item_id) >= limit:
		return false
	if not EconomyManager.can_afford(price):
		return false
	if get_shop_mode(shop_id) == "online":
		if not EconomyManager.spend(price):
			return false
		_pending_deliveries.append({"item_id": item_id, "count": 1})
	else:
		# 이미 손에 장착 중인 스택형 재료(여물 등)면 인벤토리 새 칸이 아니라
		# 장비창 수량에 바로 합친다(사용자 리포트) - 흡수 못 한 나머지만
		# 인벤토리로.
		var remaining := EquipmentManager.top_up_equipped(item_id, 1)
		if remaining > 0 and not InventoryManager.add_item(item_id, remaining):
			return false
		if not EconomyManager.spend(price):
			if remaining > 0:
				InventoryManager.remove_item(item_id, remaining)
			else:
				EquipmentManager.top_up_equipped(item_id, -1)
			return false
	_purchase_counts[item_id] = get_purchase_count(item_id) + 1
	item_purchased.emit(shop_id, item_id, price)
	return true


## 목장가게(pasture_interior)는 in_person일 때만 방문 가능하므로 온라인 배송
## 개념이 없다 - 즉시 결제하고 즉시 배치한다.
func _buy_livestock(shop_id: String, item_id: String, stall_index: int) -> bool:
	if not LivestockManager.is_stall_empty(stall_index):
		return false
	var listing := _find_listing(shop_id, item_id)
	if listing.is_empty():
		return false
	var price := int(listing.get("price", 0))
	if not EconomyManager.can_afford(price):
		return false
	var animal_type := item_id.trim_prefix(LIVESTOCK_PREFIX)
	if not LivestockManager.place_animal(stall_index, animal_type):
		return false
	if not EconomyManager.spend(price):
		LivestockManager.remove_animal(stall_index)
		return false
	item_purchased.emit(shop_id, item_id, price)
	return true


## 인벤토리 아이템이 아니라 EconomyManager.expand_inventory()를 직접 호출하는
## 특수 구매 - 가격은 고정이 아니라 현재 slot_count에 따라 달라지므로
## (EconomyManager.INVENTORY_EXPANSION_COST) 여기서 직접 계산하지 않고
## expand_inventory()에 맡긴다(자체적으로 비용 조회+결제+칸 확장까지 처리).
func _buy_inventory_expansion(shop_id: String, item_id: String) -> bool:
	if _find_listing(shop_id, item_id).is_empty():
		return false
	var price := EconomyManager.get_inventory_expansion_cost()
	if price < 0 or not EconomyManager.expand_inventory():
		return false
	item_purchased.emit(shop_id, item_id, price)
	return true


func get_save_data() -> Dictionary:
	return {
		"purchase_counts": _purchase_counts.duplicate(),
		"pending_deliveries": _pending_deliveries.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_purchase_counts = (data.get("purchase_counts", {}) as Dictionary).duplicate()
	_pending_deliveries = (data.get("pending_deliveries", []) as Array).duplicate(true)


func _on_day_changed(_day: int, _weekday: String) -> void:
	for delivery in _pending_deliveries:
		var item_id := String(delivery.get("item_id", ""))
		var count := int(delivery.get("count", 0))
		if not InventoryManager.add_item(item_id, count):
			push_warning("Inventory full - could not deliver online order: %s" % item_id)
	_pending_deliveries.clear()


func _on_npc_died(npc_id: String) -> void:
	for shop_id in _shops:
		if (_shops[shop_id].get("owner_npc_ids", []) as Array).has(npc_id):
			shop_mode_changed.emit(shop_id, get_shop_mode(shop_id))


func _find_listing(shop_id: String, item_id: String) -> Dictionary:
	for listing in (get_shop_definition(shop_id).get("stock", []) as Array):
		if String(listing.get("item_id", "")) == item_id:
			return listing
	return {}


func _load_shops() -> void:
	var file := FileAccess.open(SHOPS_PATH, FileAccess.READ)
	if file == null:
		push_error("Shop catalog could not be opened: %s" % SHOPS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Shop catalog is not valid JSON: %s" % SHOPS_PATH)
		return
	_shops = parsed
