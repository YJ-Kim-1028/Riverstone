extends Node

## Owns the player's wallet (economy.md): current gold, lifetime income/spend
## totals, and the flat cost tables for house upgrades and inventory
## expansion. Doesn't know what's being bought - ShopManager (purchases) and
## RestaurantManager (dish income) call spend()/add_income() here.

signal gold_changed(gold: int)
signal house_upgraded(level: int)

## 테스트/구매를 바로 해볼 수 있도록 만원으로 시작(사용자 지시, 기존 0G에서 변경).
const STARTING_GOLD := 10000
const MAX_HOUSE_LEVEL := 3

## economy.md "건물 확장 > 집": cost to reach this level.
const HOUSE_UPGRADE_COST := {
	2: 20000,
	3: 50000,
}

## economy.md "인벤토리 확장": cost to expand FROM this many slots to the next tier.
## 시작 칸이 10→15로 올라가면서(InventoryManager.DEFAULT_SLOT_COUNT) 예전
## "10→15" 단계가 필요 없어져 통째로 빠지고, 나머지 가격이 한 단계씩
## 앞으로 밀렸다(사용자 지시: 15→20이 옛 10→15 가격인 2000골드를 그대로 받음).
const INVENTORY_EXPANSION_COST := {
	15: 2000,
	20: 4000,
	25: 8000,
}

var gold := STARTING_GOLD
var total_income := 0
var total_spend := 0
var house_level := 1


func can_afford(amount: int) -> bool:
	return amount >= 0 and gold >= amount


func add_income(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	total_income += amount
	gold_changed.emit(gold)


func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	gold -= amount
	total_spend += amount
	gold_changed.emit(gold)
	return true


## 골드/가격 표시용 천 단위 구분 쉼표 포맷(예: 1234567 -> "1,234,567") - HUD
## 골드 표시와 상점 가격 표시가 공유한다. GDScript에 내장 천단위 포맷이 없어서
## 직접 문자열을 조립한다.
func format_gold(amount: int) -> String:
	var is_negative := amount < 0
	var digits := str(absi(amount))
	var grouped := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i != 0:
			grouped = "," + grouped
	return ("-" if is_negative else "") + grouped


## -1 once house_level is already at MAX_HOUSE_LEVEL.
func get_house_upgrade_cost() -> int:
	return int(HOUSE_UPGRADE_COST.get(house_level + 1, -1))


## home_interior 지도가 레벨마다 다른 .tmx 파일(WorldMap.HOME_INTERIOR_LEVEL_PATHS)이라,
## 그 사이 방을 다시 그리면서 기존 바닥이 밀렸을 수 있다 - "home_enterance"
## 스폰 지점을 기준으로 옛/새 지도의 좌표 차이를 구해서, 이미 배치해둔 가구/
## 장식/보관함도 같이 옮긴다(WorldMap.get_room_anchor_shift() 참고). 안 그러면
## 집을 넓힌 순간 기존에 놓아둔 물건들이 화면에 허공에 뜬 것처럼 보인다
## (사용자 리포트, 2026-08-10).
const HOME_INTERIOR_MAP_ID := "home_interior"
const HOME_INTERIOR_ANCHOR_SPAWN := "home_enterance"


func upgrade_house() -> bool:
	var cost := get_house_upgrade_cost()
	if cost < 0 or not spend(cost):
		return false
	var old_map_path := WorldMap.get_map_path(HOME_INTERIOR_MAP_ID)
	house_level += 1
	var new_map_path := WorldMap.get_map_path(HOME_INTERIOR_MAP_ID)
	var shift := WorldMap.get_room_anchor_shift(old_map_path, new_map_path, HOME_INTERIOR_ANCHOR_SPAWN)
	if shift != Vector2i.ZERO:
		FurnitureManager.shift_map_placements(HOME_INTERIOR_MAP_ID, shift)
		FloorDecorManager.shift_map_placements(HOME_INTERIOR_MAP_ID, shift)
		WallDecorManager.shift_map_placements(HOME_INTERIOR_MAP_ID, shift)
		StorageBoxManager.shift_map_placements(HOME_INTERIOR_MAP_ID, shift)
	house_upgraded.emit(house_level)
	return true


## -1 once InventoryManager.slot_count is already at its max (30).
func get_inventory_expansion_cost() -> int:
	return int(INVENTORY_EXPANSION_COST.get(InventoryManager.slot_count, -1))


func expand_inventory() -> bool:
	var cost := get_inventory_expansion_cost()
	if cost < 0 or not can_afford(cost):
		return false
	if not InventoryManager.expand_slots():
		return false
	spend(cost)
	return true


func get_save_data() -> Dictionary:
	return {
		"gold": gold,
		"total_income": total_income,
		"total_spend": total_spend,
		"house_level": house_level,
	}


func load_save_data(data: Dictionary) -> void:
	gold = int(data.get("gold", STARTING_GOLD))
	total_income = int(data.get("total_income", 0))
	total_spend = int(data.get("total_spend", 0))
	house_level = int(data.get("house_level", 1))
