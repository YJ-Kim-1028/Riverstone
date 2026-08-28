extends Node

## Owns the player's slot-based inventory: item catalog, stacking, discard
## rules, quick slots, and the gift/recipe interactions described in
## inventory.md. Farming/cooking/shop logic (what an item DOES) belongs to
## other systems; this manager only owns where items live and whether they
## can be added, stacked, discarded, gifted, or learned.

signal inventory_changed
signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)
signal slots_expanded(new_slot_count: int)
signal quick_slots_changed
signal gift_given(npc_id: String, item_id: String)
signal recipe_learned(recipe_id: String)
signal item_used(item_id: String)

const ITEMS_PATH := "res://data/items/items.json"

## 10칸으로 시작하면 이것저것 사고 나서 금방 부족해진다는 피드백으로 15칸
## 시작으로 올림(사용자 지시) - EconomyManager.INVENTORY_EXPANSION_COST도
## 같이 한 단계씩 밀어서 맞춰뒀다.
const DEFAULT_SLOT_COUNT := 15
const MAX_SLOT_COUNT := 30
const SLOT_EXPAND_STEP := 5
const QUICK_SLOT_COUNT := 8

const CATEGORY_STACK_LIMITS := {
	"material": 99,
	"dish": 99,
	"furniture": 99,
	"floor_decor": 99,
	"wall_decor": 99,
	"gift": 5,
	"tool": 1,
	"rat_poison": 1,
	"memento": 1,
	"recipe": 1,
	"quest_item": 1,
	"consumable": 99,
	"book": 1,
	"equipment": 1,
	"cooked_ingredient": 99,
	"record": 1,
}

const NON_DISCARDABLE_CATEGORIES := ["tool", "rat_poison", "memento", "recipe", "quest_item", "book", "record"]

var slot_count := DEFAULT_SLOT_COUNT

var _item_catalog: Dictionary = {}
var _slots: Array = []
var _quick_slots: Array = []
var _gifted_today: Dictionary = {}


func _ready() -> void:
	_load_item_catalog()
	_register_memento_items()
	_slots.resize(slot_count)
	for i in QUICK_SLOT_COUNT:
		_quick_slots.append("")
	# 농사 기본 도구는 상점에서 안 팔고 게임 시작부터 기본 소지(사용자 지시) -
	# 세이브를 불러오면 load_save_data()가 _slots를 통째로 새로 만들어서
	# 덮어쓰므로, 여기서 준 것과 무관하게 저장된 상태만 남는다.
	add_item("hoe", 1)
	add_item("watering_can", 1)
	# 보관 상자도 하나는 기본 지급(사용자 지시) - 위 도구들과 동일한 이유로
	# 여기서 줘도 세이브 로드 시에는 저장된 상태로 덮어써진다.
	add_item("storage_box", 1)
	# 초반 자금 소프트락 대응(day17 백로그, 사용자 지시 2026-08-26) - 시작
	# 자금(500원)으로 씨앗을 못 사면 농사 자체를 못 시작할 수 있어서, 재배
	# 가능한 세 작물 씨앗을 하나씩 기본 지급한다.
	add_item("potato_seed", 1)
	add_item("corn_seed", 1)
	add_item("lettuce_seed", 1)
	NPCManager.memento_received.connect(_on_memento_received)
	NPCManager.npc_gift_item_triggered.connect(_on_npc_gift_item_triggered)
	TimeManager.day_changed.connect(_on_day_changed)


const ICON_GRID_SIZE := 16

## 색상 커스터마이징 가구("base_id@색1-색2-색3" 형태의 합성 id,
## build_colored_item_id() 참고)는 items.json에 없다 - 최초 조회 시 base 정의를
## 복제해서 "colors"(hex 문자열 배열)/"base_item_id" 필드만 얹어 즉석에서
## 만들고 _item_catalog에 캐시해둔다(다음부터는 그냥 캐시 히트). 세이브
## 파일에는 이 문자열 자체가 item_id로 저장되므로, 재접속 후에도 같은 로직으로
## 항상 재구성된다 - 별도 저장 로직이 필요 없다.
func get_item_definition(item_id: String) -> Dictionary:
	if _item_catalog.has(item_id):
		return _item_catalog[item_id]
	if not item_id.contains("@"):
		return {}
	var parts := item_id.split("@", true, 1)
	if parts.size() != 2:
		return {}
	var base_id := parts[0]
	var base_definition: Dictionary = _item_catalog.get(base_id, {})
	if base_definition.is_empty():
		return {}
	var colors: Array = []
	for hex in parts[1].split("-"):
		colors.append(String(hex))
	var definition := base_definition.duplicate(true)
	definition["id"] = item_id
	definition["base_item_id"] = base_id
	definition["colors"] = colors
	_item_catalog[item_id] = definition
	return definition


## 구매 시 고른 색을 반영한 합성 item_id를 만든다(예: "chair@d95763-4f78d9").
## FurnitureManager 등 배치 시스템은 이 문자열도 그냥 평범한 item_id 하나로만
## 취급하므로 인벤토리/장비/저장 로직을 전혀 건드릴 필요가 없다 - 위
## get_item_definition()의 지연 생성 분기가 실제 정의를 만들어준다. 호출
## 즉시 get_item_definition()을 한 번 태워서 캐시에 등록해둔다(반환 직후부터
## 바로 조회 가능하도록).
func build_colored_item_id(base_item_id: String, colors: Array[Color]) -> String:
	var hex_joined := ""
	for i in colors.size():
		if i > 0:
			hex_joined += "-"
		hex_joined += colors[i].to_html(false)
	var item_id := "%s@%s" % [base_item_id, hex_joined]
	get_item_definition(item_id)
	return item_id


## Most category icon files (Gift.png, Food.png, Tools.png, ...) are
## multi-icon sheets laid out in a 16x16 grid, not one icon per file. Items
## opt into slicing by setting icon_index (their 0-based column, left to
## right) and, if the sheet has more than one row, icon_row (0-based, default
## 0 = the first row). Without icon_index, no icon is shown yet (rather than
## handing UI the whole multi-icon sheet as if it were this one item's icon).
## row_override lets a caller pick a different row than the item's own
## icon_row while keeping the same sheet/column - player_tool_overlay.gd uses
## this for the front-facing pose variant some tools have drawn one row below
## their normal icon (2026-08-12).
func get_item_icon_texture(item_id: String, row_override: int = -1) -> Texture2D:
	var definition := get_item_definition(item_id)
	## 실제 아이콘 그림이 아직 없는 임시 아이템(예: 장비 테스트용)은 스프라이트
	## 시트 대신 "icon_color"(hex) 하나로 단색 아이콘을 대신 쓸 수 있다.
	var icon_color := String(definition.get("icon_color", ""))
	if not icon_color.is_empty():
		return _flat_color_texture(Color(icon_color))
	var icon_path := String(definition.get("icon", ""))
	if icon_path.is_empty() or not definition.has("icon_index"):
		return null
	var sheet := load(icon_path) as Texture2D
	if sheet == null:
		return null
	var column := int(definition["icon_index"])
	var row := row_override if row_override >= 0 else int(definition.get("icon_row", 0))
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(column * ICON_GRID_SIZE, row * ICON_GRID_SIZE, ICON_GRID_SIZE, ICON_GRID_SIZE)
	return atlas


func _flat_color_texture(color: Color) -> Texture2D:
	var image := Image.create(ICON_GRID_SIZE, ICON_GRID_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func is_item_known(item_id: String) -> bool:
	return not get_item_definition(item_id).is_empty()


func get_item_category(item_id: String) -> String:
	return String(get_item_definition(item_id).get("category", ""))


## 대부분은 카테고리 기본값을 그대로 쓰지만, recipe_random(만능 요리
## 레시피)처럼 같은 카테고리의 다른 아이템과 달리 여러 개를 갖고 있는 게
## 정상인 예외가 있다(일반 레시피 아이템은 어차피 1개만 쓰면 끝이라
## stack_limit 1이 맞지만, 랜덤 레시피는 상점 구매 한도만큼(2개) 미리 사둘 수
## 있어야 함) - items.json에 "stack_limit"을 직접 명시하면 그 값이 우선한다.
func get_stack_limit(item_id: String) -> int:
	var definition := get_item_definition(item_id)
	if definition.has("stack_limit"):
		return int(definition["stack_limit"])
	var category := get_item_category(item_id)
	if not CATEGORY_STACK_LIMITS.has(category):
		push_error("Unknown item category for stack limit: %s (%s)" % [item_id, category])
		return 1
	return int(CATEGORY_STACK_LIMITS[category])


func is_discardable(item_id: String) -> bool:
	return not NON_DISCARDABLE_CATEGORIES.has(get_item_category(item_id))


func get_slots() -> Array:
	return _slots.duplicate(true)


func get_item_count(item_id: String) -> int:
	var total := 0
	for slot in _slots:
		if slot != null and String(slot.get("item_id", "")) == item_id:
			total += int(slot["count"])
	return total


func has_item(item_id: String, count: int = 1) -> bool:
	return get_item_count(item_id) >= count


func find_slot_index(item_id: String) -> int:
	for i in _slots.size():
		var slot = _slots[i]
		if slot != null and String(slot.get("item_id", "")) == item_id:
			return i
	return -1


## 실제로 넣지 않고 "지금 넣으면 들어갈까"만 미리 확인한다(수확/착유/도살처럼
## 어떤 아이템이 몇 개 생길지 미리 아는 상호작용의 E 프롬프트를 인벤토리가
## 가득 찼을 때 아예 숨기는 데 쓴다 - main.gd). add_item()과 완전히 같은 용량
## 계산을 공유한다(_can_fit()).
func can_add_item(item_id: String, count: int) -> bool:
	return _can_fit(item_id, count)


## 빈 슬롯이 하나도 없는지 - 낚시처럼 무엇을 얻을지 미리 알 수 없는 상호작용의
## 프롬프트를 숨기는 데 쓴다(특정 아이템 스택에 여유가 있는지까지는 안 봄).
func is_full() -> bool:
	return _count_empty_slots() == 0


## "이 아이템은 통틀어 1개까지만 소지 가능한지"(inventory.md가 도구에 대해
## 명시한 "중복 획득 불가" - 실제로는 카테고리 기본 스택 한도가 원래 1인
## 것들(도구/쥐약/추억의 물건/레시피/퀘스트 아이템/책/장비) 전부에 적용되어
## 왔다). 아이템 정의에 "stack_limit"을 직접 지정해뒀으면(recipe_random의
## 2, storage_box의 1 등) 이 암묵 규칙에서 완전히 빠진다 - 그 값 자체가
## "이 아이템은 카테고리 기본과 다르게 취급하겠다"는 명시적 선언이기 때문.
## storage_box(보관함)는 카테고리 기본(material=99)이 아니라 "슬롯당 1개씩만
## 쌓이지만 여러 개를 따로따로 소지"하려는 의도로 stack_limit:1을 줬는데,
## 카테고리 기본값만 보고 판단하면 이것도 "통틀어 1개만"에 잘못 걸린다(실제
## 발생했던 버그) - 반대로 recipe_random은 카테고리 기본(recipe=1)이 원래
## 유니크지만 의도적으로 2까지 갖고 싶어서 오버라이드했으므로, 오버라이드가
## 있으면 무조건 이 규칙을 건너뛰는 쪽이 두 경우 모두에 맞다.
func _is_unique_item(item_id: String) -> bool:
	if get_item_definition(item_id).has("stack_limit"):
		return false
	var category := get_item_category(item_id)
	return int(CATEGORY_STACK_LIMITS.get(category, 0)) == 1


## All-or-nothing: fails without changing state if there isn't room for the
## full amount (inventory.md: "인벤토리가 가득 찬 경우 아이템을 획득할 수 없다").
## Unique items (tools/rat poison/mementos/recipes/quest items/books/equipment)
## additionally refuse a second copy entirely, even in a different empty slot -
## inventory.md calls this out explicitly for tools ("중복 획득 불가"). See
## _is_unique_item() for why this checks category defaults, not effective
## stack_limit.
func add_item(item_id: String, count: int) -> bool:
	if not _can_fit(item_id, count):
		return false
	var stack_limit := get_stack_limit(item_id)
	var remaining := count
	for i in _slots.size():
		if remaining <= 0:
			break
		var slot = _slots[i]
		if slot != null and String(slot.get("item_id", "")) == item_id and int(slot["count"]) < stack_limit:
			var add_amount: int = mini(stack_limit - int(slot["count"]), remaining)
			slot["count"] = int(slot["count"]) + add_amount
			remaining -= add_amount
	while remaining > 0:
		var index := _find_empty_slot_index()
		var add_amount: int = mini(stack_limit, remaining)
		_slots[index] = {"item_id": item_id, "count": add_amount}
		remaining -= add_amount
	inventory_changed.emit()
	item_added.emit(item_id, count)
	return true


## System-level removal (bypasses the discardable check) for other systems
## to consume items: cooking materials, using rat poison, learning a recipe,
## registering a memento into the collection book, etc.
func remove_item(item_id: String, count: int) -> bool:
	if count <= 0 or get_item_count(item_id) < count:
		return false
	var remaining := count
	for i in _slots.size():
		if remaining <= 0:
			break
		var slot = _slots[i]
		if slot != null and String(slot.get("item_id", "")) == item_id:
			var take: int = mini(int(slot["count"]), remaining)
			_remove_from_slot(i, take)
			remaining -= take
	return true


## Player-initiated discard. Refuses to drop tools/rat poison/mementos/
## recipes/quest items per inventory.md's "인벤토리 제한" list.
func discard_item(slot_index: int, count: int) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot = _slots[slot_index]
	if slot == null or not is_discardable(String(slot.get("item_id", ""))):
		return false
	return _remove_from_slot(slot_index, count)


func sort_by_name() -> void:
	var items: Array = []
	for slot in _slots:
		if slot != null:
			items.append(slot)
	items.sort_custom(func(a, b): return _item_name(String(a.get("item_id", ""))) < _item_name(String(b.get("item_id", ""))))
	_slots = []
	_slots.resize(slot_count)
	for i in items.size():
		_slots[i] = items[i]
	inventory_changed.emit()


func expand_slots() -> bool:
	if slot_count + SLOT_EXPAND_STEP > MAX_SLOT_COUNT:
		return false
	slot_count += SLOT_EXPAND_STEP
	_slots.resize(slot_count)
	slots_expanded.emit(slot_count)
	return true


func assign_quick_slot(quick_index: int, item_id: String) -> bool:
	if quick_index < 0 or quick_index >= QUICK_SLOT_COUNT:
		return false
	_quick_slots[quick_index] = item_id
	quick_slots_changed.emit()
	return true


func clear_quick_slot(quick_index: int) -> void:
	assign_quick_slot(quick_index, "")


func get_quick_slot_item(quick_index: int) -> String:
	if quick_index < 0 or quick_index >= QUICK_SLOT_COUNT:
		return ""
	return String(_quick_slots[quick_index])


func has_gifted_today(npc_id: String) -> bool:
	return bool(_gifted_today.get(npc_id, false))


## inventory.md "선물" rule: gift-category item, once per NPC per day,
## removes the item and raises the NPC's affection via NPCManager.
func give_gift(npc_id: String, slot_index: int) -> bool:
	if has_gifted_today(npc_id) or slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot = _slots[slot_index]
	if slot == null:
		return false
	var item_id := String(slot.get("item_id", ""))
	if get_item_category(item_id) != "gift":
		return false
	if not _remove_from_slot(slot_index, 1):
		return false
	_gifted_today[npc_id] = true
	_apply_gift(npc_id, item_id)
	return true


## give_gift()와 같은 규칙이지만, 인벤토리 슬롯이 아니라 손에 장착된(EquipmentManager
## HAND_SLOT) 선물 아이템을 대상으로 한다 - 선물도 여물/도구처럼 "장착 후
## NPC와 상호작용" UX를 쓰기로 해서(사용자 지시) main.gd가 이걸 호출한다.
## perform_feed() 등과 같은 패턴으로 결과 안내 문구를 돌려준다("" = 아무 일도
## 안 일어남 - 손에 든 게 선물이 아니거나 이미 오늘 이 NPC에게 선물했음).
func give_gift_from_hand(npc_id: String) -> String:
	if has_gifted_today(npc_id):
		return ""
	var item_id := String(EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT))
	if get_item_category(item_id) != "gift":
		return ""
	EquipmentManager.consume_equipped(EquipmentManager.HAND_SLOT)
	_gifted_today[npc_id] = true
	_apply_gift(npc_id, item_id)
	var npc_name := String(NPCManager.get_definition(npc_id).get("name", npc_id))
	var item_name := String(get_item_definition(item_id).get("name", item_id))
	return "%s에게 %s을(를) 선물했다." % [npc_name, item_name]


func _apply_gift(npc_id: String, item_id: String) -> void:
	var definition := get_item_definition(item_id)
	var affection_amount := int(definition.get("gift_affection", NPCManager.AFFECTION_GAIN_GIFT))
	var scent_color := String(definition.get("scent_color", ""))
	NPCManager.give_gift(npc_id, affection_amount, scent_color)
	gift_given.emit(npc_id, item_id)


## inventory.md "레시피" rule: right-click a recipe item to learn it. The
## item is consumed; a future collection/cooking system should mark
## `recipe_id` as known when it receives this signal.
## 소모품(category=="consumable", 예: 아메리카노/자양 강장제) 1개를 사용한다.
## 실제 효과(이동속도 버프/디버프 해제 등)는 아이템 이름을 판별할 수 있는
## player.gd 쪽에서 item_used 신호를 받아 처리한다 - 이 매니저는 소지품 소모만
## 담당한다(다른 사용 계열 함수인 learn_recipe와 동일한 역할 분리).
func use_item(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= _slots.size():
		return ""
	var slot = _slots[slot_index]
	if slot == null:
		return ""
	var item_id := String(slot.get("item_id", ""))
	if get_item_category(item_id) != "consumable" or not _remove_from_slot(slot_index, 1):
		return ""
	item_used.emit(item_id)
	return item_id


func learn_recipe(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= _slots.size():
		return ""
	var slot = _slots[slot_index]
	if slot == null:
		return ""
	var item_id := String(slot.get("item_id", ""))
	if get_item_category(item_id) != "recipe" or not _remove_from_slot(slot_index, 1):
		return ""
	recipe_learned.emit(item_id)
	return item_id


## inventory.md "추억의 물건": auto-removed once registered in the
## collection book. A future collection system should call this.
func remove_memento(npc_id: String) -> bool:
	return remove_item("memento_%s" % npc_id, 1)


func get_save_data() -> Dictionary:
	var items: Array = []
	for slot in _slots:
		if slot != null:
			items.append({"item_id": slot["item_id"], "count": slot["count"]})
	return {
		"inventory": items,
		"slot_count": slot_count,
		"quick_slots": _quick_slots.duplicate(),
		"gifted_today": _gifted_today.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	slot_count = clampi(int(data.get("slot_count", DEFAULT_SLOT_COUNT)), DEFAULT_SLOT_COUNT, MAX_SLOT_COUNT)
	_slots = []
	_slots.resize(slot_count)
	for item in (data.get("inventory", []) as Array):
		add_item(String(item.get("item_id", "")), int(item.get("count", 0)))
	var loaded_quick: Array = data.get("quick_slots", [])
	_quick_slots = []
	for i in QUICK_SLOT_COUNT:
		_quick_slots.append(String(loaded_quick[i]) if i < loaded_quick.size() else "")
	_gifted_today = (data.get("gifted_today", {}) as Dictionary).duplicate()


func _on_memento_received(npc_id: String) -> void:
	var item_id := "memento_%s" % npc_id
	if not add_item(item_id, 1):
		push_warning("Inventory full - could not deliver memento item: %s" % item_id)


func _on_npc_gift_item_triggered(npc_id: String, item_id: String) -> void:
	if item_id.is_empty():
		return
	if not add_item(item_id, 1):
		push_warning("Inventory full - could not deliver NPC gift item: %s from %s" % [item_id, npc_id])


func _on_day_changed(_day: int, _weekday: String) -> void:
	_gifted_today.clear()


func _item_name(item_id: String) -> String:
	return String(get_item_definition(item_id).get("name", item_id))


## add_item()/can_add_item()이 공유하는 용량 계산 - 원래 add_item() 안에
## 그대로 있던 로직을 뮤테이션 없이 재사용할 수 있도록 분리한 것뿐, 판정
## 결과는 이전과 동일하다.
##
## _item_catalog.has(item_id)로 직접 조회하면 안 된다(예전 버그) - 가구
## 색상 커스터마이징의 합성 item_id(예: "chair@a9794a")는 items.json에 없고
## get_item_definition()이 처음 호출될 때 지연 생성/등록되는데, 게임을 새로
## 켠 직후에는 아직 한 번도 조회된 적이 없어 _item_catalog에 없는 상태다.
## load_save_data() -> add_item() -> _can_fit()로 이어지는 로드 경로가 바로
## 이 함수라서, 여기서 카탈로그를 직접 봤더니 재접속 시 색칠된 가구가 전부
## "알 수 없는 아이템"으로 판정되어 조용히 사라지는 버그가 있었다(사용자
## 리포트). get_item_definition()을 거치면 그 자리에서 바로 등록되므로
## 해결된다.
func _can_fit(item_id: String, count: int) -> bool:
	if count <= 0 or get_item_definition(item_id).is_empty():
		return false
	var stack_limit := get_stack_limit(item_id)
	if _is_unique_item(item_id) and get_item_count(item_id) + count > 1:
		return false
	var existing_capacity := 0
	for slot in _slots:
		if slot != null and String(slot.get("item_id", "")) == item_id:
			existing_capacity += stack_limit - int(slot["count"])
	var overflow: int = maxi(count - existing_capacity, 0)
	var slots_needed: int = 0 if overflow == 0 else int(ceil(float(overflow) / float(stack_limit)))
	return slots_needed <= _count_empty_slots()


func _count_empty_slots() -> int:
	var total := 0
	for slot in _slots:
		if slot == null:
			total += 1
	return total


func _find_empty_slot_index() -> int:
	for i in _slots.size():
		if _slots[i] == null:
			return i
	return -1


func _remove_from_slot(slot_index: int, count: int) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot = _slots[slot_index]
	if slot == null or int(slot.get("count", 0)) < count:
		return false
	var item_id := String(slot.get("item_id", ""))
	slot["count"] = int(slot["count"]) - count
	if int(slot["count"]) <= 0:
		_slots[slot_index] = null
	inventory_changed.emit()
	item_removed.emit(item_id, count)
	return true


## assets/icon/memento.png는 16x16 칸 13개짜리 한 줄 시트(사용자가 직접
## 그려준 순서, 2026-08-25) - get_item_icon_texture()의 icon_index 규칙(왼쪽부터
## 0-based 열)을 그대로 따른다.
const MEMENTO_SPRITE_SHEET := "res://assets/icon/memento.png"
const MEMENTO_ICON_INDEX := {
	"belje": 0, "flora": 1, "isha": 2, "lama": 3, "marin": 4, "marr": 5,
	"mocha": 6, "poli": 7, "roshi": 8, "sage": 9, "shepherd": 10, "usher": 11,
	"woody": 12,
}


func _register_memento_items() -> void:
	for npc_id in NPCManager.get_all_ids():
		var memento: Dictionary = NPCManager.get_definition(npc_id).get("memento_item", {})
		var memento_name := String(memento.get("name", ""))
		if memento_name.is_empty():
			continue
		var item_id := "memento_%s" % npc_id
		var entry := {
			"id": item_id,
			"name": memento_name,
			"category": "memento",
			"subtype": "",
			"description": String(memento.get("description", "")),
			"icon": MEMENTO_SPRITE_SHEET,
		}
		if MEMENTO_ICON_INDEX.has(npc_id):
			entry["icon_index"] = MEMENTO_ICON_INDEX[npc_id]
		_item_catalog[item_id] = entry


func _load_item_catalog() -> void:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file == null:
		push_error("Item catalog could not be opened: %s" % ITEMS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Item catalog is not valid JSON: %s" % ITEMS_PATH)
		return
	_item_catalog = parsed
