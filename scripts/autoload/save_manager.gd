extends Node

## Owns JSON save-slot orchestration: gathering every system's
## get_save_data() into the structure save.md defines (Player / Player
## Progress / NPC / Horror / Restaurant / World), writing/reading the 3
## save slots, and the autosave triggers (취침, 맵 이동). Each system stays
## the source of truth for its own state - this just calls into them.

signal game_saved(slot: int)
signal game_loaded(slot: int)

const SAVE_DIR := "user://saves/"
const SAVE_SLOT_COUNT := 3
const SCHEMA_VERSION := 1

var current_slot := 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	TimeManager.forced_sleep.connect(_on_forced_sleep)
	GameManager.map_changed.connect(_on_map_changed)


func set_current_slot(slot: int) -> void:
	current_slot = clampi(slot, 1, SAVE_SLOT_COUNT)


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_save(slot: int) -> bool:
	if not has_save(slot):
		return false
	return DirAccess.remove_absolute(_slot_path(slot)) == OK


func save_game(slot: int) -> bool:
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not open save slot for writing: %s" % slot)
		return false
	file.store_string(JSON.stringify(_gather_save_data(), "\t"))
	game_saved.emit(slot)
	return true


func load_game(slot: int) -> bool:
	if not has_save(slot):
		return false
	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		push_error("Could not open save slot for reading: %s" % slot)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Save slot %s is not valid JSON" % slot)
		return false
	_apply_save_data(parsed)
	current_slot = slot
	game_loaded.emit(slot)
	return true


## 슬롯 선택 화면용 요약 정보만 읽는다 (전체 상태를 실제로 복원하지 않음).
func get_save_summary(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var player: Dictionary = (parsed as Dictionary).get("player", {})
	return {
		"player_name": player.get("name", ""),
		"day": player.get("day", 0),
		"money": player.get("money", 0),
		"play_time_seconds": player.get("play_time_seconds", 0.0),
	}


func _on_forced_sleep() -> void:
	save_game(current_slot)


func _on_map_changed(_map_id: String) -> void:
	save_game(current_slot)


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "save_slot_%d.json" % slot


func _gather_save_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"player": {
			"name": GameManager.player_name,
			"restaurant_name": GameManager.restaurant_name,
			"money": EconomyManager.gold,
			"day": TimeManager.current_day,
			"hour": TimeManager.current_hour,
			"minute": TimeManager.current_minute,
			"weekday": TimeManager.get_weekday(),
			"map": GameManager.current_map_id,
			"play_time_seconds": GameManager.play_time_seconds,
			"inventory": InventoryManager.get_save_data(),
			"hair_id": GameManager.hair_id,
			"hair_color_1": GameManager.hair_color_1,
			"hair_color_2": GameManager.hair_color_2,
			"hair_color_3": GameManager.hair_color_3,
			"skin_color": GameManager.skin_color,
			"eye_color": GameManager.eye_color,
			"cheek_color": GameManager.cheek_color,
			"outfit_color_1": GameManager.outfit_color_1,
			"outfit_color_2": GameManager.outfit_color_2,
			"shoe_color": GameManager.shoe_color,
			"accessory_color": GameManager.accessory_color,
			"outfit_id": GameManager.outfit_id,
			"shoe_id": GameManager.shoe_id,
			"accessory_id": GameManager.accessory_id,
		},
		"player_progress": {
			"house_level": EconomyManager.house_level,
			"economy": EconomyManager.get_save_data(),
			"cooking": CookingManager.get_save_data(),
			"collection": CollectionManager.get_save_data(),
		},
		"npc": NPCManager.get_save_data(),
		"horror": _gather_horror_data(),
		"restaurant": RestaurantManager.get_save_data(),
		"world": {
			"weather": WeatherManager.get_save_data(),
		},
		"shop": ShopManager.get_save_data(),
		"email": EmailManager.get_save_data(),
		"equipment": EquipmentManager.get_save_data(),
		"kitchen": KitchenManager.get_save_data(),
		"livestock": LivestockManager.get_save_data(),
		"farming": FarmingManager.get_save_data(),
		"storage_boxes": StorageBoxManager.get_save_data(),
	}


## save.md가 요구하는 필드 이름은 그대로 미러링해서 저장 파일만 봐도 읽히게
## 해두고, 실제 로드는 항상 murder_manager/horror_events 쪽 전체 상태에서 한다.
func _gather_horror_data() -> Dictionary:
	return {
		"murdered_npc_ids": NPCManager.get_dead_npc_ids(),
		"first_murder_occurred": MurderManager.get_murder_count() >= 1,
		"second_murder_occurred": MurderManager.get_murder_count() >= 2,
		"arrested": MurderManager.is_arrested(),
		"stalker_killed": MurderManager.is_stalker_killed(),
		"accomplice_ending": MurderManager.is_accomplice_ending(),
		"living_with_stalker": MurderManager.is_living_with_stalker(),
		"usher_death_method": MurderManager.get_usher_death_method(),
		"achieved_ending": MurderManager.get_achieved_ending(),
		"murder_manager": MurderManager.get_save_data(),
		"horror_events": HorrorEventManager.get_save_data(),
	}


func _apply_save_data(data: Dictionary) -> void:
	var player: Dictionary = data.get("player", {})
	var progress: Dictionary = data.get("player_progress", {})

	TimeManager.load_save_data({
		"day": player.get("day", 1),
		"hour": player.get("hour", TimeManager.DAY_START_HOUR),
		"minute": player.get("minute", 0),
	})
	GameManager.load_save_data({
		"player_name": player.get("name", GameManager.DEFAULT_PLAYER_NAME),
		"restaurant_name": player.get("restaurant_name", GameManager.DEFAULT_RESTAURANT_NAME),
		"play_time_seconds": player.get("play_time_seconds", 0.0),
		"current_map_id": player.get("map", ""),
		"hair_id": player.get("hair_id", ""),
		"hair_color_1": player.get("hair_color_1", "d8d8d8"),
		"hair_color_2": player.get("hair_color_2", "9a9a9a"),
		"hair_color_3": player.get("hair_color_3", "565656"),
		"skin_color": player.get("skin_color", "f8e7da"),
		"eye_color": player.get("eye_color", "38b57a"),
		"cheek_color": player.get("cheek_color", "f4a6b3"),
		"outfit_color_1": player.get("outfit_color_1", "9a9a9a"),
		"outfit_color_2": player.get("outfit_color_2", "565656"),
		"shoe_color": player.get("shoe_color", "9a9a9a"),
		"accessory_color": player.get("accessory_color", "9a9a9a"),
		"outfit_id": player.get("outfit_id", ""),
		"shoe_id": player.get("shoe_id", ""),
		"accessory_id": player.get("accessory_id", ""),
	})
	InventoryManager.load_save_data(player.get("inventory", {}))
	EconomyManager.load_save_data(progress.get("economy", {}))
	CookingManager.load_save_data(progress.get("cooking", {}))
	CollectionManager.load_save_data(progress.get("collection", {}))
	NPCManager.load_save_data(data.get("npc", {}))
	var horror: Dictionary = data.get("horror", {})
	MurderManager.load_save_data(horror.get("murder_manager", {}))
	HorrorEventManager.load_save_data(horror.get("horror_events", {}))
	RestaurantManager.load_save_data(data.get("restaurant", {}))
	WeatherManager.load_save_data((data.get("world", {}) as Dictionary).get("weather", {}))
	ShopManager.load_save_data(data.get("shop", {}))
	EmailManager.load_save_data(data.get("email", {}))
	EquipmentManager.load_save_data(data.get("equipment", {}))
	KitchenManager.load_save_data(data.get("kitchen", {}))
	LivestockManager.load_save_data(data.get("livestock", {}))
	FarmingManager.load_save_data(data.get("farming", {}))
	StorageBoxManager.load_save_data(data.get("storage_boxes", {}))
