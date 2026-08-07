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


## -1 once house_level is already at MAX_HOUSE_LEVEL.
func get_house_upgrade_cost() -> int:
	return int(HOUSE_UPGRADE_COST.get(house_level + 1, -1))


func upgrade_house() -> bool:
	var cost := get_house_upgrade_cost()
	if cost < 0 or not spend(cost):
		return false
	house_level += 1
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
