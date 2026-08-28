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
	# 예전엔 "책장에서 등록"(register_memento())해야 도감에 떴는데, 실제로
	# 그걸 부르는 곳이 없어서 인벤토리에 들고 있어도 "?"로만 남는 버그였다.
	# 그걸 고치려다 사용자 지시로 아예 방식을 바꿈(2026-08-26 - "들고 있지
	# 않아도 얻기만 해도 도감에 보여야돼") - 소지 여부와 무관하게 받는 순간
	# 바로 등록한다.
	NPCManager.memento_received.connect(_on_memento_received)
	SaveManager.game_loaded.connect(_on_game_loaded)


func is_memento_acquired(npc_id: String) -> bool:
	return _memento_entries.has(npc_id)


## 위 방식(받는 순간 자동 등록)이 생기기 "전" 세이브는 인벤토리에 추억의
## 물건을 이미 들고 있으면서도 한 번도 등록된 적 없을 수 있다(사용자 리포트,
## 2026-08-26 - "그 전에 만든 세이브파일로 하다보니 계속 안뜨는거만 보여서").
## 불러올 때마다 한 번 훑어서 들고 있는데 미등록인 것만 등록해준다 - 이미
## 등록된 건 is_memento_acquired()에서 걸러져 중복 걱정 없음.
func _on_game_loaded(_slot: int) -> void:
	for npc_id in NPCManager.get_all_ids():
		if not is_memento_acquired(npc_id) and InventoryManager.has_item("memento_%s" % npc_id):
			_on_memento_received(npc_id)


## true once the NPC has died without ever handing over the memento - the
## collection.md "???" / 더 이상 이 추억을 만날 수 없습니다" slot.
func is_memento_locked(npc_id: String) -> bool:
	return not is_memento_acquired(npc_id) and not NPCManager.is_alive(npc_id)


func _on_memento_received(npc_id: String) -> void:
	if is_memento_acquired(npc_id):
		return
	_memento_entries[npc_id] = {"acquired_day": TimeManager.current_day}
	memento_registered.emit(npc_id)
	if not _full_collection_announced and is_full_memento_collection():
		_full_collection_announced = true
		full_memento_collection_achieved.emit()


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
