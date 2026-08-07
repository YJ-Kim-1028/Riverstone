extends Node

## Owns the "도감" album described in collection.md: the acquisition record
## (day + method) for mementos and recipes, the death-lock rule for
## never-received mementos, and completion tracking. The underlying data
## (memento names/descriptions, recipe names/prices/craft counts) still
## lives in NPCManager/CookingManager - this manager only layers the
## collection-specific bookkeeping on top and decides what's shown/locked.

signal memento_registered(npc_id: String)
signal recipe_registered(recipe_id: String)
signal full_memento_collection_achieved

const LOCKED_NAME := "???"
const LOCKED_DESCRIPTION := "더 이상 이 추억을 만날 수 없습니다."
const MEMENTO_ACQUISITION_METHOD := "호감도 100 달성"
const RECIPE_ACQUISITION_METHOD := "요리 제작"

var _memento_entries: Dictionary = {}
var _recipe_entries: Dictionary = {}
var _full_collection_announced := false


func _ready() -> void:
	CookingManager.dish_cooked.connect(_on_dish_cooked)
	CookingManager.recipe_learned.connect(_on_recipe_learned)


func is_memento_acquired(npc_id: String) -> bool:
	return _memento_entries.has(npc_id)


## true once the NPC has died without ever handing over the memento - the
## collection.md "???" / 더 이상 이 추억을 만날 수 없습니다" slot.
func is_memento_locked(npc_id: String) -> bool:
	return not is_memento_acquired(npc_id) and not NPCManager.is_alive(npc_id)


## inventory.md: 추억의 물건은 책장에서 도감에 등록하는 순간 인벤토리에서
## 자동 삭제된다. 그래서 등록은 "받는 순간"이 아니라 이걸 호출하는 순간
## (미래의 책장 상호작용)에 일어나고, 실제로 아이템을 들고 있어야 성공한다.
func register_memento(npc_id: String) -> bool:
	if is_memento_acquired(npc_id):
		return false
	var item_id := "memento_%s" % npc_id
	if not InventoryManager.has_item(item_id):
		return false
	InventoryManager.remove_memento(npc_id)
	_memento_entries[npc_id] = {"acquired_day": TimeManager.current_day}
	memento_registered.emit(npc_id)
	if not _full_collection_announced and is_full_memento_collection():
		_full_collection_announced = true
		full_memento_collection_achieved.emit()
	return true


func get_memento_entry(npc_id: String) -> Dictionary:
	var npc_definition := NPCManager.get_definition(npc_id)
	var memento_definition: Dictionary = npc_definition.get("memento_item", {})
	var acquired := is_memento_acquired(npc_id)
	var locked := is_memento_locked(npc_id)
	return {
		"npc_id": npc_id,
		"owner": String(npc_definition.get("name", "")),
		"name": LOCKED_NAME if locked else String(memento_definition.get("name", "")),
		"description": LOCKED_DESCRIPTION if locked else String(memento_definition.get("description", "")),
		"acquired": acquired,
		"acquired_day": int(_memento_entries.get(npc_id, {}).get("acquired_day", -1)),
		"acquisition_method": MEMENTO_ACQUISITION_METHOD,
		"locked": locked,
	}


func get_all_memento_entries() -> Array:
	var entries: Array = []
	for npc_id in NPCManager.get_all_ids():
		if not (NPCManager.get_definition(npc_id).get("memento_item", {}) as Dictionary).is_empty():
			entries.append(get_memento_entry(npc_id))
	return entries


func get_memento_completion_rate() -> float:
	var total := get_all_memento_entries().size()
	return float(_memento_entries.size()) / float(total) if total > 0 else 0.0


func is_full_memento_collection() -> bool:
	return get_memento_completion_rate() >= 1.0


## cooking.md: 도감에는 "만든 요리"가 등록된다. 레시피는 재료 조합을 처음
## 맞혀서 요리해보는 순간 배움과 동시에 발견되므로, 실질적으로 처음 요리에
## 성공한 순간 도감에도 함께 등록된다 (CookingManager.cook() 참고).
func is_recipe_acquired(recipe_id: String) -> bool:
	return _recipe_entries.has(recipe_id)


func get_recipe_entry(recipe_id: String) -> Dictionary:
	var definition := CookingManager.get_recipe_definition(recipe_id)
	var acquired := is_recipe_acquired(recipe_id)
	return {
		"recipe_id": recipe_id,
		"name": String(definition.get("name", "")) if acquired else LOCKED_NAME,
		"description": String(definition.get("description", "")) if acquired else LOCKED_DESCRIPTION,
		"price": int(definition.get("price", 0)) if acquired else 0,
		"ingredient_pairs": (definition.get("ingredient_pairs", []) as Array) if acquired else [],
		"craft_count": CookingManager.get_craft_count(recipe_id),
		"acquired": acquired,
		"acquired_day": int(_recipe_entries.get(recipe_id, {}).get("acquired_day", -1)),
		"acquisition_method": RECIPE_ACQUISITION_METHOD,
	}


func get_all_recipe_entries() -> Array:
	var entries: Array = []
	for recipe_id in CookingManager.get_all_recipe_ids():
		entries.append(get_recipe_entry(recipe_id))
	return entries


func get_save_data() -> Dictionary:
	return {
		"memento_entries": _memento_entries.duplicate(true),
		"recipe_entries": _recipe_entries.duplicate(true),
		"full_collection_announced": _full_collection_announced,
	}


func load_save_data(data: Dictionary) -> void:
	_memento_entries = (data.get("memento_entries", {}) as Dictionary).duplicate(true)
	_recipe_entries = (data.get("recipe_entries", {}) as Dictionary).duplicate(true)
	_full_collection_announced = bool(data.get("full_collection_announced", false))


func _on_dish_cooked(dish: Dictionary) -> void:
	_register_recipe(String(dish.get("id", "")))


## 레시피 아이템(만능 요리 레시피 포함)을 우클릭으로 사용해 배운 경우도
## 한 번도 요리해본 적 없어도 도감에 바로 등록되어야 한다(사용자 리포트 -
## 예전엔 dish_cooked만 듣고 있어서 실제로 요리를 한 번 해봐야만 등록됐음).
## 조합을 처음 맞혀서 배운 경우는 CookingManager.cook()이 이미 learn_recipe()를
## 거치므로 이 신호로도 같이 들어오지만, _register_recipe의 중복 체크 덕분에
## dish_cooked와 두 번 등록되지 않는다. 괴상한 요리(weird_dish)는 learn_recipe()
## 자체가 거부하는 특수 케이스라 여전히 dish_cooked를 통해서만 등록된다.
func _on_recipe_learned(recipe_id: String, _via_item: bool) -> void:
	_register_recipe(recipe_id)


func _register_recipe(recipe_id: String) -> void:
	if recipe_id.is_empty() or is_recipe_acquired(recipe_id):
		return
	_recipe_entries[recipe_id] = {"acquired_day": TimeManager.current_day}
	recipe_registered.emit(recipe_id)
