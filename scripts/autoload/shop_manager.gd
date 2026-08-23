extends Node

## Owns the shop catalog (data/shop/shops.json), purchase transactions, the
## death-succession/online-conversion rules from shop.md, and the online
## shop's next-day-9am delivery queue. Payment goes through EconomyManager;
## items go through InventoryManager. A stock listing only appears once its
## price is actually known - see data/shop/README.md for what's still open.

signal item_purchased(shop_id: String, item_id: String, price: int)
signal shop_mode_changed(shop_id: String, mode: String)
## _grant_furniture_hammer_if_needed()가 실제로 망치를 지급한 순간에만 쏜다
## (이미 갖고 있으면 안 쏨) - main.gd가 이걸 받아서 상점 창을 닫고 우디의
## 선물 대사를 띄운다(사용자 지시).
signal furniture_hammer_granted(npc_id: String)

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
## 집 확장 - 인벤토리 확장과 완전히 같은 이유로 특수 항목이다(인벤토리
## 아이템이 아니라 EconomyManager.upgrade_house()를 직접 호출). 가격도
## 고정이 아니라 현재 house_level에 따라 달라져서(EconomyManager.
## HOUSE_UPGRADE_COST) shops.json에는 price를 안 적어둔다 - UI가
## get_house_upgrade_cost()로 매번 다시 조회해서 보여준다.
const HOUSE_UPGRADE_ITEM_ID := "house_upgrade"
## 가구/바닥장식/벽장식을 하나라도 사면 우디가 선물로 가구용 망치를 준다
## (사용자 지시) - 손에 들고 있을 때만 배치된 가구를 회수할 수 있게 해서,
## 그냥 지나갈 때마다 "E 가구 회수" 프롬프트가 뜨는 게 거슬린다는 피드백을
## 해결한다(FurnitureManager 등 회수 판정 자체는 main.gd가 이 아이템 장착
## 여부로 게이트한다). 도구 카테고리라 한번 받으면 버릴 수 없어서(NON_
## DISCARDABLE_CATEGORIES) 인벤토리에 이미 있는지만 확인하면 중복 지급 걱정
## 없다.
const FURNITURE_HAMMER_ITEM_ID := "furniture_hammer"
const FURNITURE_HAMMER_TRIGGER_CATEGORIES := ["furniture", "floor_decor", "wall_decor"]

var _shops: Dictionary = {}
var _purchase_counts: Dictionary = {}
## item_id -> 그 아이템을 처음 구매한 TimeManager.current_day. 순차 공개 항목
## (unlocks_after/unlock_delay_days - 어셔의 책 등)의 "며칠 지났는지" 판정에만 쓰인다.
var _purchase_days: Dictionary = {}
var _pending_deliveries: Array = []


func _ready() -> void:
	_load_shops()
	TimeManager.day_changed.connect(_on_day_changed)
	NPCManager.npc_died.connect(_on_npc_died)


func get_shop_ids() -> Array:
	return _shops.keys()


func get_shop_definition(shop_id: String) -> Dictionary:
	return _shops.get(shop_id, {})


## horror_events.md "NPC 집 잠금" - 이 프로젝트엔 NPC 개인 주거 맵이 따로
## 없고 "NPC맵=NPC가게"라는 사용자 확정(2026-08-16)이라, main.gd가 맵 입장을
## 막을지 판단할 때 이 함수로 map_id -> shop_id를 역으로 찾는다. 일치하는
## 상점이 없으면(플라자 등 상점이 아닌 맵) 빈 문자열.
func get_shop_id_for_map(map_id: String) -> String:
	for shop_id in _shops:
		if String(_shops[shop_id].get("map_id", "")) == map_id:
			return shop_id
	return ""


## 추억의 물건 컷신 위치 조건(사용자 지시, 2026-08-17) - "자기 가게에 있을 때"를
## 판정하려면 npc_id가 소유한 상점의 map_id가 필요하다. 공동소유 상점(목장:
## 벨제+셰퍼드, 낚시가게: 로시+마린)도 owner_npc_ids에 이미 둘 다 있어서
## 그대로 걸린다. 폴리/세이지/라마처럼 상점이 없는 NPC는 "" - 호출부가 이걸
## "가게가 없으니 위치 조건 자체를 안 건다"는 뜻으로 해석해야 한다.
func get_owned_shop_map_id(npc_id: String) -> String:
	for shop_id in _shops:
		if (_shops[shop_id].get("owner_npc_ids", []) as Array).has(npc_id):
			return String(_shops[shop_id].get("map_id", ""))
	return ""


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
		if limit > 0 and get_purchase_count(item_id) >= limit:
			return false
		return _is_release_unlocked(listing)
	)


func get_purchase_count(item_id: String) -> int:
	return int(_purchase_counts.get(item_id, 0))


## 어셔의 책처럼 순차 공개되는 항목용 - listing에 unlocks_after(선행 item_id)가
## 있으면, 그 선행 아이템을 구매한 뒤 unlock_delay_days일 이상 지나야 통과한다.
## 두 필드가 없는 일반 항목은 항상 true(기존 동작 그대로).
func _is_release_unlocked(listing: Dictionary) -> bool:
	var prerequisite := String(listing.get("unlocks_after", ""))
	if prerequisite.is_empty():
		return true
	if not _purchase_days.has(prerequisite):
		return false
	var delay := int(listing.get("unlock_delay_days", 0))
	return TimeManager.current_day >= int(_purchase_days[prerequisite]) + delay


## In-person purchase adds the item to the bag immediately; online purchase
## charges now and queues delivery for the next day's 09:00 (email.md/shop.md:
## "다음 날 오전 9시 우편함으로 배송"). Fails without charging if the shop
## doesn't sell the item, the purchase limit was reached, gold is short, or
## (in-person only) the inventory has no room.
## stall_index는 item_id가 "livestock:"로 시작할 때만 쓰인다(어느 외양간
## 칸에 배치할지) - 그 외 아이템은 무시한다.
## colors는 가구/바닥장식/벽장식처럼 색상 커스터마이징이 있는 아이템 구매에만
## 쓰인다 - 비어있지 않으면 InventoryManager가 만들어주는 합성 item_id(예:
## "chair@d95763-4f78d9")로 실제 인벤토리 지급/배송을 하되, 재고 조회·구매
## 한도·잠금 해제 판정(_find_listing/_purchase_counts/_purchase_days)은 계속
## 원래 item_id(base) 기준으로 한다 - 색상별로 재고가 나뉘면 안 되므로.
## 실패 사유 문구(사용자 요청, 2026-08-16 - 예전엔 bool만 돌려줘서 왜
## 실패했는지 안내가 없었음). UI는 반환값이 비어있으면 성공으로 취급한다.
const REASON_NOT_SOLD := "판매하지 않는 상품입니다."
const REASON_LIMIT_REACHED := "구매 한도를 초과했습니다."
const REASON_NOT_UNLOCKED := "아직 구매할 수 없는 상품입니다."
const REASON_NOT_ENOUGH_GOLD := "골드가 부족합니다."
const REASON_INVENTORY_FULL := "인벤토리가 가득 찼습니다."
const REASON_STALL_OCCUPIED := "이미 다른 동물이 있는 칸입니다."
const REASON_CANNOT_PLACE := "동물을 배치할 수 없습니다."
const REASON_MAX_LEVEL := "더 이상 확장할 수 없습니다."


func buy(shop_id: String, item_id: String, stall_index: int = -1, colors: Array[Color] = []) -> String:
	if item_id.begins_with(LIVESTOCK_PREFIX):
		return _buy_livestock(shop_id, item_id, stall_index)
	if item_id == INVENTORY_EXPANSION_ITEM_ID:
		return _buy_inventory_expansion(shop_id, item_id)
	if item_id == HOUSE_UPGRADE_ITEM_ID:
		return _buy_house_upgrade(shop_id, item_id)
	if JukeboxManager.is_record_item(item_id):
		return _buy_jukebox_record(shop_id, item_id)
	var listing := _find_listing(shop_id, item_id)
	if listing.is_empty():
		return REASON_NOT_SOLD
	var price := int(listing.get("price", 0))
	var limit := int(listing.get("purchase_limit", 0))
	if limit > 0 and get_purchase_count(item_id) >= limit:
		return REASON_LIMIT_REACHED
	if not _is_release_unlocked(listing):
		return REASON_NOT_UNLOCKED
	if not EconomyManager.can_afford(price):
		return REASON_NOT_ENOUGH_GOLD
	var final_item_id := item_id
	if not colors.is_empty():
		final_item_id = InventoryManager.build_colored_item_id(item_id, colors)
	if get_shop_mode(shop_id) == "online":
		if not EconomyManager.spend(price):
			return REASON_NOT_ENOUGH_GOLD
		_pending_deliveries.append({"item_id": final_item_id, "count": 1})
	else:
		# 이미 손에 장착 중인 스택형 재료(여물 등)면 인벤토리 새 칸이 아니라
		# 장비창 수량에 바로 합친다(사용자 리포트) - 흡수 못 한 나머지만
		# 인벤토리로.
		var remaining := EquipmentManager.top_up_equipped(final_item_id, 1)
		if remaining > 0 and not InventoryManager.add_item(final_item_id, remaining):
			return REASON_INVENTORY_FULL
		if not EconomyManager.spend(price):
			if remaining > 0:
				InventoryManager.remove_item(final_item_id, remaining)
			else:
				EquipmentManager.top_up_equipped(final_item_id, -1)
			return REASON_NOT_ENOUGH_GOLD
	_purchase_counts[item_id] = get_purchase_count(item_id) + 1
	if not _purchase_days.has(item_id):
		_purchase_days[item_id] = TimeManager.current_day
	_grant_furniture_hammer_if_needed(shop_id, item_id)
	item_purchased.emit(shop_id, final_item_id, price)
	return ""


## FURNITURE_HAMMER_TRIGGER_CATEGORIES에 속한 아이템을 처음 사는 순간 그
## 상점의 주인 NPC가 선물로 망치를 끼워준다 - 온라인/현장 구매 둘 다(방금
## 위에서 이미 결제/지급이 끝난 뒤라 실패할 이유가 없음). 인벤토리가 꽉 차
## 있으면 조용히 건너뛴다(구매 자체를 막을 정도의 문제는 아님) - 다음에
## 가구를 또 사면 그때 다시 시도된다.
func _grant_furniture_hammer_if_needed(shop_id: String, item_id: String) -> void:
	if not FURNITURE_HAMMER_TRIGGER_CATEGORIES.has(InventoryManager.get_item_category(item_id)):
		return
	if InventoryManager.get_item_count(FURNITURE_HAMMER_ITEM_ID) > 0:
		return
	InventoryManager.add_item(FURNITURE_HAMMER_ITEM_ID, 1)
	var owner_ids: Array = get_shop_definition(shop_id).get("owner_npc_ids", [])
	if not owner_ids.is_empty():
		furniture_hammer_granted.emit(String(owner_ids[0]))


## 목장가게(pasture_interior)는 in_person일 때만 방문 가능하므로 온라인 배송
## 개념이 없다 - 즉시 결제하고 즉시 배치한다.
func _buy_livestock(shop_id: String, item_id: String, stall_index: int) -> String:
	if not LivestockManager.is_stall_empty(stall_index):
		return REASON_STALL_OCCUPIED
	var listing := _find_listing(shop_id, item_id)
	if listing.is_empty():
		return REASON_NOT_SOLD
	var price := int(listing.get("price", 0))
	if not EconomyManager.can_afford(price):
		return REASON_NOT_ENOUGH_GOLD
	var animal_type := item_id.trim_prefix(LIVESTOCK_PREFIX)
	if not LivestockManager.place_animal(stall_index, animal_type):
		return REASON_CANNOT_PLACE
	if not EconomyManager.spend(price):
		LivestockManager.remove_animal(stall_index)
		return REASON_NOT_ENOUGH_GOLD
	item_purchased.emit(shop_id, item_id, price)
	return ""


## 인벤토리 아이템이 아니라 EconomyManager.expand_inventory()를 직접 호출하는
## 특수 구매 - 가격은 고정이 아니라 현재 slot_count에 따라 달라지므로
## (EconomyManager.INVENTORY_EXPANSION_COST) 여기서 직접 계산하지 않고
## expand_inventory()에 맡긴다(자체적으로 비용 조회+결제+칸 확장까지 처리).
func _buy_inventory_expansion(shop_id: String, item_id: String) -> String:
	if _find_listing(shop_id, item_id).is_empty():
		return REASON_NOT_SOLD
	var price := EconomyManager.get_inventory_expansion_cost()
	if price < 0:
		return REASON_MAX_LEVEL
	if not EconomyManager.expand_inventory():
		return REASON_NOT_ENOUGH_GOLD
	item_purchased.emit(shop_id, item_id, price)
	return ""


## _buy_inventory_expansion()과 완전히 동일한 구조 - 인벤토리 아이템이 아니라
## EconomyManager.upgrade_house()를 직접 호출하는 특수 구매. 가격은 현재
## house_level에 따라 달라지므로(EconomyManager.HOUSE_UPGRADE_COST) 여기서
## 직접 계산하지 않고 upgrade_house()에 맡긴다(자체적으로 비용 조회+결제+
## 레벨 증가까지 처리). 실제로 집이 넓어지는 효과는 WorldMap.get_map_path()가
## house_level을 읽어서 처리한다(여기서는 레벨 숫자만 올림).
func _buy_house_upgrade(shop_id: String, item_id: String) -> String:
	if _find_listing(shop_id, item_id).is_empty():
		return REASON_NOT_SOLD
	var price := EconomyManager.get_house_upgrade_cost()
	if price < 0:
		return REASON_MAX_LEVEL
	if not EconomyManager.upgrade_house():
		return REASON_NOT_ENOUGH_GOLD
	item_purchased.emit(shop_id, item_id, price)
	return ""


## 음반(주크박스 곡 해금 아이템, JukeboxManager.is_record_item())은 인벤토리
## 칸을 차지할 이유가 없다(사용자 지시, 2026-08-10 - 다 산 음반은 인벤토리에서
## 할 게 없는 죽은 아이템이었음) - InventoryManager.add_item()을 아예 타지
## 않고, 골드 결제 + _purchase_counts 기록만 한다. JukeboxManager.is_unlocked()가
## 바로 이 _purchase_counts를 보고 해금 여부를 판정하므로, 이 함수가 끝나는
## 순간 해당 곡이 즉시 재생 목록에 나타난다.
func _buy_jukebox_record(shop_id: String, item_id: String) -> String:
	var listing := _find_listing(shop_id, item_id)
	if listing.is_empty():
		return REASON_NOT_SOLD
	var limit := int(listing.get("purchase_limit", 0))
	if limit > 0 and get_purchase_count(item_id) >= limit:
		return REASON_LIMIT_REACHED
	var price := int(listing.get("price", 0))
	if not EconomyManager.can_afford(price) or not EconomyManager.spend(price):
		return REASON_NOT_ENOUGH_GOLD
	_purchase_counts[item_id] = get_purchase_count(item_id) + 1
	if not _purchase_days.has(item_id):
		_purchase_days[item_id] = TimeManager.current_day
	item_purchased.emit(shop_id, item_id, price)
	return ""


func get_save_data() -> Dictionary:
	return {
		"purchase_counts": _purchase_counts.duplicate(),
		"purchase_days": _purchase_days.duplicate(),
		"pending_deliveries": _pending_deliveries.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_purchase_counts = (data.get("purchase_counts", {}) as Dictionary).duplicate()
	_purchase_days = (data.get("purchase_days", {}) as Dictionary).duplicate()
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
