extends Node

## Owns the recipe catalog, ingredient-pair matching, known-recipe unlocks,
## and rat poison consumption described in cooking.md. Does not know about
## restaurant stations/tables or NPC seating - RestaurantManager calls
## cook() once it has confirmed a diner is waiting, then serves the result.

signal dish_cooked(dish: Dictionary)
## via_item: learn_recipe() 참고 - 레시피 아이템 소비로 배웠는지, 냄비 조합
## 성공으로 우연히 알게 됐는지.
signal recipe_learned(recipe_id: String, via_item: bool)

const RECIPES_PATH := "res://data/cooking/recipes.json"
const WEIRD_DISH_ID := "weird_dish"
const RAT_POISON_ITEM_ID := "rat_poison"
const RECIPE_ITEM_PREFIX := "recipe_"
const RANDOM_RECIPE_ITEM_ID := "recipe_random"
const ICON_GRID_SIZE := 16

var known_recipe_ids: Dictionary = {}

var _recipes: Dictionary = {}
var _craft_counts: Dictionary = {}
var _rat_poison_used := false


func _ready() -> void:
	_load_recipes()
	InventoryManager.recipe_learned.connect(_on_inventory_recipe_learned)


func get_recipe_definition(recipe_id: String) -> Dictionary:
	return _recipes.get(recipe_id, {})


func get_all_recipe_ids() -> Array:
	return _recipes.keys()


## InventoryManager.get_item_icon_texture()와 같은 규칙: icon_index가 없으면
## null (아이콘 위치를 아직 못 받은 요리).
func get_recipe_icon_texture(recipe_id: String) -> Texture2D:
	var definition := get_recipe_definition(recipe_id)
	var icon_path := String(definition.get("icon", ""))
	if icon_path.is_empty() or not definition.has("icon_index"):
		return null
	var sheet := load(icon_path) as Texture2D
	if sheet == null:
		return null
	var column := int(definition["icon_index"])
	var row := int(definition.get("icon_row", 0))
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(column * ICON_GRID_SIZE, row * ICON_GRID_SIZE, ICON_GRID_SIZE, ICON_GRID_SIZE)
	return atlas


func is_recipe_known(recipe_id: String) -> bool:
	return bool(known_recipe_ids.get(recipe_id, false))


## via_item: 레시피 아이템(두루마리 등)을 소비해서 배운 건지, 냄비에서 재료
## 조합을 처음 성공시켜서 우연히 알게 된 건지 - AudioManager가 전자에만 "새
## 레시피 습득" 효과음을 낸다(사용자 지시: 후자는 이미 냄비 완성 연출이 있어서
## 겹치면 어색함, 백로그: 나중에 후자도 완성대 앞 전용 애니메이션이 생기면
## 같이 재생 검토).
func learn_recipe(recipe_id: String, via_item: bool = false) -> bool:
	if recipe_id == WEIRD_DISH_ID or not _recipes.has(recipe_id) or is_recipe_known(recipe_id):
		return false
	known_recipe_ids[recipe_id] = true
	recipe_learned.emit(recipe_id, via_item)
	return true


func get_craft_count(recipe_id: String) -> int:
	return int(_craft_counts.get(recipe_id, 0))


func has_used_rat_poison() -> bool:
	return _rat_poison_used


## Consumes the two ingredients (and rat poison, if requested) from
## InventoryManager and returns the resulting dish, or {} if the player
## doesn't actually have what this call claims to use.
## cooking.md: 재료 조합이 레시피와 일치하면 미리 "배우지" 않았어도 그 요리가
## 나온다 - 맞는 조합을 처음 만들어보는 것 자체가 그 레시피를 발견/습득하는
## 방법이다. 조합이 어떤 레시피와도 맞지 않을 때만 "괴상한 요리"가 된다.
## (레시피 아이템을 사용해 미리 배워두는 것도 여전히 가능하지만, 필수는 아니다.)
func cook(ingredient_a: String, ingredient_b: String, use_rat_poison: bool = false) -> Dictionary:
	if not _has_ingredients(ingredient_a, ingredient_b):
		return {}
	if use_rat_poison and not InventoryManager.has_item(RAT_POISON_ITEM_ID, 1):
		return {}
	var matched_id := _match_recipe(ingredient_a, ingredient_b)
	var final_id: String = matched_id if not matched_id.is_empty() else WEIRD_DISH_ID
	if final_id != WEIRD_DISH_ID and not is_recipe_known(final_id):
		learn_recipe(final_id)
	var definition := get_recipe_definition(final_id)
	_consume_ingredients(ingredient_a, ingredient_b)
	if use_rat_poison:
		InventoryManager.remove_item(RAT_POISON_ITEM_ID, 1)
		_rat_poison_used = true
	_craft_counts[final_id] = get_craft_count(final_id) + 1
	var dish := {
		"id": final_id,
		"name": String(definition.get("name", "")),
		"price": int(definition.get("price", 0)),
		"is_weird": final_id == WEIRD_DISH_ID,
		"poisoned": use_rat_poison,
	}
	dish_cooked.emit(dish)
	return dish


func get_save_data() -> Dictionary:
	return {
		"known_recipes": known_recipe_ids.keys(),
		"craft_counts": _craft_counts.duplicate(),
		"rat_poison_used": _rat_poison_used,
	}


func load_save_data(data: Dictionary) -> void:
	known_recipe_ids.clear()
	for recipe_id in (data.get("known_recipes", []) as Array):
		known_recipe_ids[String(recipe_id)] = true
	_craft_counts = (data.get("craft_counts", {}) as Dictionary).duplicate()
	_rat_poison_used = bool(data.get("rat_poison_used", false))


func _on_inventory_recipe_learned(item_id: String) -> void:
	if item_id == RANDOM_RECIPE_ITEM_ID:
		var random_recipe_id := _pick_unknown_recipe_id()
		if not random_recipe_id.is_empty():
			learn_recipe(random_recipe_id, true)
		return
	if item_id.begins_with(RECIPE_ITEM_PREFIX):
		learn_recipe(item_id.substr(RECIPE_ITEM_PREFIX.length()), true)


## recipe_random(만능 요리 레시피)이 소비될 때 아직 안 배운 레시피 중 하나를
## 무작위로 고른다. 전부 이미 알고 있으면 빈 문자열을 반환한다(다른 레시피
## 아이템을 중복 사용할 때와 동일하게, 아이템만 소비되고 아무 것도 새로 배우지
## 않는다).
func _pick_unknown_recipe_id() -> String:
	var candidates: Array = []
	for recipe_id in _recipes:
		if recipe_id != WEIRD_DISH_ID and not is_recipe_known(recipe_id):
			candidates.append(recipe_id)
	if candidates.is_empty():
		return ""
	return String(candidates[randi() % candidates.size()])


func _has_ingredients(a: String, b: String) -> bool:
	if a == b:
		return InventoryManager.has_item(a, 2)
	return InventoryManager.has_item(a, 1) and InventoryManager.has_item(b, 1)


func _consume_ingredients(a: String, b: String) -> void:
	if a == b:
		InventoryManager.remove_item(a, 2)
	else:
		InventoryManager.remove_item(a, 1)
		InventoryManager.remove_item(b, 1)


func _match_recipe(a: String, b: String) -> String:
	for recipe_id in _recipes:
		if recipe_id == WEIRD_DISH_ID:
			continue
		for pair in (_recipes[recipe_id].get("ingredient_pairs", []) as Array):
			if (String(pair[0]) == a and String(pair[1]) == b) or (String(pair[0]) == b and String(pair[1]) == a):
				return recipe_id
	return ""


func _load_recipes() -> void:
	var file := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if file == null:
		push_error("Recipe catalog could not be opened: %s" % RECIPES_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Recipe catalog is not valid JSON: %s" % RECIPES_PATH)
		return
	_recipes = parsed
