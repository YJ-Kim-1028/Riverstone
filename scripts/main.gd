extends Node2D

## World-interaction routing: turns "player pressed E near object X" into a
## call on the relevant backend system, or a signal for a future UI to pick
## up when the interaction needs a screen (shop stock, cooking, inbox,
## collection) rather than a single immediate action.

signal shop_interacted(shop_id: String)
## new_cooking_system.md 3.4 - 조리된 재료 2개를 넣어 완성/서빙하는 지점(테이블당
## 1개, restaurant_seatN/dishN과 1:1). 예전의 "요리대"(restaurant_cooking1~3,
## 재료 2개를 직접 골라 즉시 완성하던 곳)를 대체한다.
signal serving_area_interacted(station_index: int)
## new_cooking_system.md 3.3 - 원재료를 넣고 실제 시간만큼 기다려 "조리된 재료"로
## 바꾸는 조리기구 4곳(냄비/프라이팬/도마/믹서기). station_id는
## KitchenManager/data/cooking/cooking_stations.json의 키("cooking_area1" 등)를
## 그대로 쓴다.
signal kitchen_station_interacted(station_id: String)
signal computer_interacted
signal collection_interacted
signal npc_talk_interacted(npc_id: String)
## StorageBoxManager - 근처에 이미 상자가 있을 때 E를 누르면(설치 아님, 열기).
signal storage_box_interacted(cell: Vector2i)

const SERVING_AREA_PREFIX := "serving_area"
const KITCHEN_STATION_PREFIX := "cooking_area"
const RESTAURANT_NOT_READY_MESSAGE := "먼저 레스토랑을 열자."
const ALREADY_SERVED_MESSAGE := "이미 손님이 요리를 먹고 있다."
const RESTAURANT_HOURS_MESSAGE := "오전 10시부터 오후 4시까지만 영업할 수 있다."
const RESTAURANT_CANNOT_LEAVE_MESSAGE := "영업 중에는 레스토랑을 벗어날 수 없다."
const MESSAGE_DURATION := 2.0

const FADE_DURATION := 0.2
const UI_DIM_ALPHA := 0.5
const DAY_LABEL_HOLD_DURATION := 1.2

## data/npc/mocha.json의 buff_item(이동속도 +10%, 3분)에 명시된 수치 그대로 -
## items.json의 "americano" 설명("잠시 플레이어의 이속을 증가시킨다")과 같은
## 효과를 가리킨다. data/items/items.json의 "energy_tonic"은 설명에 "(디버프
## 해제)"로 명시되어 있음.
const AMERICANO_SPEED_BONUS := 0.10
const AMERICANO_DURATION_MINUTES := 3

## time.md: "취침 시간이 될 때까지 야외에 있을 경우, 길바닥 기절 후 다음 날
## 디버프를 얻는다." 디버프 수치(-30%, 게임 시간 3시간)와 기상 위치는 이전
## 세션에서 이미 합의된 값(plan/day4.md) - 병원 기상 스폰(hospital_lying_player)은
## 사용자가 hospital_interior.tmx에 직접 배치했다.
const COLLAPSE_DEBUFF_PERCENT := -0.30
const COLLAPSE_DEBUFF_MINUTES := 180
const HOSPITAL_MAP_ID := "hospital_interior"
const HOSPITAL_WAKE_SPAWN := "hospital_lying_player"

## restaurant_interior.tmx의 Wall_deco 레이어에 원래 그려져 있던 팻말 타일(OPEN,
## GID 312/313, 칸 좌표 col6~7/row14, 픽셀로는 (96,224)~(128,240))과 정확히
## 같은 자리/크기 - 그 위에 이 스프라이트를 덮어 그려서 영업 상태에 따라
## OPEN/CLOSE를 바꾼다. 맵 파일은 읽기 전용이라 원래 타일은 그대로 두고
## 그림으로만 가린다.
## 이 타일은 옆 칸(파티션 벽)과 YSortAnchor로 묶여 "Wall" 레이어 전체의 맨
## 아래 행을 Y-sort 기준으로 물려받는데, 이 스프라이트는 원래 칸 좌표(row14)를
## 그대로 쓰면 그 벽 덩어리보다 기준값이 작아져서 원본 타일이 오히려 이
## 스프라이트보다 앞에 그려져 버린다 - 그래서 position/offset을 고정값 대신
## world_map.get_tile_sort_y()로 매번 다시 계산해서 원본 타일(Wall 레이어)과
## 항상 같은 기준을 쓰게 한다(_update_restaurant_sign 참고).
const RESTAURANT_SIGN_MAP_ID := "restaurant_interior"
const RESTAURANT_SIGN_CELL := Vector2i(6, 14)
const RESTAURANT_SIGN_VISUAL_CENTER := Vector2(112, 232)
const RESTAURANT_SIGN_OPEN_TEXTURE := preload("res://assets/ui/sign_open.png")
const RESTAURANT_SIGN_CLOSE_TEXTURE := preload("res://assets/ui/sign_close.png")

@onready var world_map: WorldMap = get_node_or_null("HomeMap") as WorldMap
@onready var player: PlayerController = get_node_or_null("HomeMap/Player") as PlayerController
@onready var hud: Control = get_node_or_null("UI/HUD") as Control
@onready var npc_layer: Node2D = get_node_or_null("HomeMap/NPCLayer") as Node2D
@onready var shop_screen: Control = get_node_or_null("UI/ShopScreen") as Control
@onready var cooking_screen: Control = get_node_or_null("UI/CookingScreen") as Control
@onready var computer_screen: Control = get_node_or_null("UI/ComputerScreen") as Control
@onready var sleep_confirm_popup: Control = get_node_or_null("UI/SleepConfirmPopup") as Control
@onready var restaurant_confirm_popup: Control = get_node_or_null("UI/RestaurantConfirmPopup") as Control
@onready var collection_screen: Control = get_node_or_null("UI/CollectionScreen") as Control
@onready var dialogue_screen: Control = get_node_or_null("UI/DialogueScreen") as Control
@onready var status_screen: Control = get_node_or_null("UI/StatusScreen") as Control
@onready var kitchen_screen: Control = get_node_or_null("UI/KitchenScreen") as Control
@onready var serving_screen: Control = get_node_or_null("UI/ServingScreen") as Control
@onready var fishing_screen: Control = get_node_or_null("UI/FishingScreen") as Control
@onready var livestock_confirm_popup: Control = get_node_or_null("UI/LivestockConfirmPopup") as Control
@onready var book_screen: Control = get_node_or_null("UI/BookScreen") as Control
@onready var storage_screen: Control = get_node_or_null("UI/StorageScreen") as Control
@onready var _restaurant_sign: Sprite2D = get_node_or_null("HomeMap/RestaurantSign") as Sprite2D
## main.tscn 안에서 이 노드의 기본 color는 불투명 검정이다(title_screen.gd가
## main.tscn으로 넘어가기 직전에 자기 화면을 먼저 검게 페이드하고 넘어오므로,
## 무거운 씬 인스턴싱이 끝난 첫 프레임에 게임 화면이 잠깐 안 가려진 채
## 보이는 걸 막기 위함) - _ready()의 _load_map()이 끝에서 _fade_in()으로
## 걷어내야 비로소 화면이 보인다.
@onready var _fade: ColorRect = get_node_or_null("TransitionLayer/Fade") as ColorRect
@onready var _day_label: Label = get_node_or_null("TransitionLayer/DayLabel") as Label
@onready var _ui_dim: ColorRect = get_node_or_null("UI/Dim") as ColorRect
@onready var _lighting_layer: LightingLayer = get_node_or_null("LightingLayer") as LightingLayer
@onready var _weather_layer: CanvasLayer = get_node_or_null("WeatherLayer") as CanvasLayer

## 상자를 손에 들고 있을 때 마우스 아래 칸에 뜨는 반투명 설치 미리보기
## (사용자 지시 - E로 바로 설치하는 대신 스타듀처럼 마우스로 위치를 보면서
## 좌클릭으로 설치). world_map의 직계 자식이라 다른 월드 오브젝트와 같은
## 좌표계를 쓴다 - _build_box_preview()에서 한 번만 만들고 맵이 바뀌어도
## (world_map 노드 자체는 재생성되지 않으므로) 계속 재사용한다.
var _box_preview: Sprite2D = null

var _is_transitioning := false
var _message_timer := 0.0
var _sleep_prompt_shown := false
var _is_sleep_transition_playing := false
## "지금 대화 가능 범위 안에 있는 NPC" - 이 값이 바뀌는 순간(멀어졌다 다시
## 가까워질 때)만 "마주쳤다"는 이모지를 한 번 띄운다(_handle_npc_encounter
## 참고). 범위를 벗어나면 빈 문자열로 리셋되어 다음 접근에서 다시 트리거된다.
var _last_nearby_npc_id := ""
## 외양간 문(door1_open~4) 이름 -> 지금 열려있는지. _load_map()마다 비운다
## (WorldMap.load_map()이 맵을 새로 그릴 때마다 문도 항상 닫힌 상태로
## 리셋되므로, 여기 기록도 그대로 맞춰야 한다 - "일시적으로"만 열려있는
## 상호작용이라 세이브 대상도 아니다).
var _open_doors: Dictionary = {}
## LivestockConfirmPopup이 확인을 받는 동안 어느 칸을 도살할지 기억해둔다
## (restaurant_confirm_popup과 같은 "펜딩 액션 1개" 패턴).
var _pending_slaughter_stall := -1


func _ready() -> void:
	if world_map == null or player == null:
		push_error("Main scene requires HomeMap and Player nodes.")
		set_process(false)
		return
	player.interact_pressed.connect(_on_interact_pressed)
	player.set_world_map(world_map)
	if hud != null:
		hud.set_player(player)
	AudioManager.set_player(player)
	AudioManager.set_world_map(world_map)
	GameManager.start_play_timer()
	if shop_screen != null:
		shop_interacted.connect(shop_screen.open_shop)
	if kitchen_screen != null:
		kitchen_station_interacted.connect(kitchen_screen.open_kitchen)
	if serving_screen != null:
		serving_area_interacted.connect(serving_screen.open_serving)
	if computer_screen != null:
		computer_interacted.connect(computer_screen.open)
	if collection_screen != null:
		collection_interacted.connect(collection_screen.open)
	if dialogue_screen != null:
		npc_talk_interacted.connect(dialogue_screen.open_dialogue)
	if sleep_confirm_popup != null:
		sleep_confirm_popup.slept.connect(_play_sleep_transition)
	if restaurant_confirm_popup != null:
		restaurant_confirm_popup.confirmed.connect(_on_restaurant_confirmed)
	if livestock_confirm_popup != null:
		livestock_confirm_popup.confirmed.connect(_on_livestock_confirmed)
	if status_screen != null and book_screen != null:
		status_screen.book_open_requested.connect(book_screen.open_book)
	if storage_screen != null:
		storage_box_interacted.connect(storage_screen.open_box)
	RestaurantManager.restaurant_opened.connect(_update_restaurant_sign)
	RestaurantManager.restaurant_closed.connect(_update_restaurant_sign)
	InventoryManager.item_used.connect(_on_item_used)
	CookingManager.recipe_learned.connect(_on_recipe_learned)
	TimeManager.player_collapsed.connect(_play_collapse_transition)
	_build_box_preview()
	_load_map("Home", "start_spawn")
	if OS.is_debug_build():
		GameManager._debug_give_test_equipment()


func _on_item_used(item_id: String) -> void:
	match item_id:
		"americano":
			player.apply_speed_effect(AMERICANO_SPEED_BONUS, AMERICANO_DURATION_MINUTES, false)
			AudioManager.play_sfx(AudioManager.SFX_DRINKING)
		"energy_tonic":
			player.clear_debuff()
			AudioManager.play_sfx(AudioManager.SFX_DRINKING)


## 레시피 아이템(만능 요리 레시피 포함)을 우클릭으로 써서 배웠을 때 플레이어
## 머리 위에 안내 문구를 띄운다(사용자 지시) - 조합을 처음 맞혀서 우연히
## 배운 경우(via_item==false)는 이미 냄비 완성 연출이 있어서 겹치면 어색하니
## 제외한다(CookingManager.learn_recipe()의 via_item 구분과 동일).
func _on_recipe_learned(recipe_id: String, via_item: bool) -> void:
	if not via_item:
		return
	var recipe_name := String(CookingManager.get_recipe_definition(recipe_id).get("name", recipe_id))
	_show_temporary_message("%s 레시피를 획득했다!" % recipe_name)


## UI 창이 하나라도 열려있는 동안의 마우스 클릭에 공통 클릭 효과음을 준다
## (사용자 지시) - Control의 _gui_input이 이벤트를 "처리됨"으로 표시하면
## _unhandled_input까지 전파가 안 되므로(버튼 클릭 대부분이 여기 해당), 그
## 필터링 전에 항상 먼저 호출되는 _input()에서 감지한다. 상점 구매 버튼처럼
## 자기만의 전용 효과음(SFX_COIN)이 따로 나는 버튼은 "_no_click_sfx" 그룹으로
## 표시해서 겹쳐 나지 않게 제외한다(사용자 지시).
func _input(event: InputEvent) -> void:
	if not _is_any_modal_open():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hovered.is_in_group(&"_no_click_sfx"):
			return
		AudioManager.play_sfx(AudioManager.SFX_CLICK)


## 상자 미리보기가 떠 있을 때 좌클릭하면 그 자리에 설치한다(사용자 지시 -
## E 대신 마우스 클릭). 모달이 열려있으면 _update_box_preview()가 이미
## _box_preview.visible을 꺼두므로 여기서 다시 확인할 필요는 없다.
func _unhandled_input(event: InputEvent) -> void:
	if _box_preview == null or not _box_preview.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var message := StorageBoxManager.place_box(_box_preview.position)
		if not message.is_empty():
			_show_temporary_message(message)
		get_viewport().set_input_as_handled()


func _update_restaurant_sign() -> void:
	if _restaurant_sign == null:
		return
	_restaurant_sign.visible = GameManager.current_map_id == RESTAURANT_SIGN_MAP_ID
	if not _restaurant_sign.visible:
		return
	var sort_y := world_map.get_tile_sort_y(RESTAURANT_SIGN_CELL, "Wall")
	_restaurant_sign.position = Vector2(RESTAURANT_SIGN_VISUAL_CENTER.x, sort_y)
	_restaurant_sign.offset = Vector2(0, RESTAURANT_SIGN_VISUAL_CENTER.y - sort_y)
	_restaurant_sign.texture = RESTAURANT_SIGN_OPEN_TEXTURE if RestaurantManager.is_open else RESTAURANT_SIGN_CLOSE_TEXTURE


func _process(delta: float) -> void:
	_update_ui_blocking()
	if world_map == null or player == null:
		return
	if _message_timer > 0.0:
		_message_timer = max(_message_timer - delta, 0.0)
	var interactable := world_map.get_interactable_at(player.position)
	_close_kitchen_screen_if_out_of_range(interactable)
	_close_serving_screen_if_out_of_range(interactable)
	_close_storage_screen_if_out_of_range()
	_update_box_preview()
	if _is_npc_talk_priority(interactable):
		var talk_npc_id := String(_nearest_talkable_npc(player.position).get("npc_id", ""))
		_handle_npc_encounter(talk_npc_id)
		var npc_prompt := _npc_interact_prompt(talk_npc_id)
		if npc_prompt.is_empty():
			player.hide_interaction_prompt()
		elif _message_timer <= 0.0:
			player.show_interaction_prompt(npc_prompt)
		return
	_handle_npc_encounter("")
	var warp: Dictionary = world_map.get_warp_at(player.position)
	if not warp.is_empty():
		if _is_building_transition(warp):
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 이동")
			return
		player.hide_interaction_prompt()
		_load_map(warp["target_map"], warp["target_spawn"])
		return
	var interactable_name := String(interactable.get("name", ""))
	# 침대는 E가 아니라 타일에 닿기만 하면 바로 확인창이 뜬다 - 한 번 닿아
	# 물어본 뒤(아니오를 골랐어도) 그 자리에 계속 서 있는 동안 또 안 뜨게
	# _sleep_prompt_shown으로 막고, 타일을 벗어나면 다시 물을 수 있게 푼다.
	if interactable_name == "sleep":
		if not _sleep_prompt_shown and sleep_confirm_popup != null:
			_sleep_prompt_shown = true
			sleep_confirm_popup.open()
		return
	_sleep_prompt_shown = false
	if interactable_name.begins_with(KITCHEN_STATION_PREFIX):
		if _message_timer <= 0.0:
			var tool_name := KitchenManager.get_tool_name(interactable_name)
			player.show_interaction_prompt("E %s 사용" % tool_name if not tool_name.is_empty() else "E 조리하기")
		return
	if interactable_name.begins_with(SERVING_AREA_PREFIX):
		var serving_index := interactable_name.trim_prefix(SERVING_AREA_PREFIX).to_int() - 1
		# get_station_npc()는 "논리적으로 배정됨"만 확인한다 - 손님이 아직
		# 자리로 걸어오는 중이면 완성대를 실제로 쓸 수 없으니 프롬프트도
		# 안 뜨게 한다(is_station_npc_settled로 실제 도착 여부까지 확인).
		if RestaurantManager.is_station_npc_settled(serving_index):
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 요리 제공")
		else:
			player.hide_interaction_prompt()
		return
	if interactable_name == "computer" or interactable_name == "collection":
		if _message_timer <= 0.0:
			player.show_interaction_prompt("E 사용")
		return
	if interactable_name == "cash_register":
		if ShopManager.is_staffed(String(interactable.get("shop_id", ""))):
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 사용")
		else:
			player.hide_interaction_prompt()
		return
	if interactable_name == "restaurant_open":
		if _message_timer <= 0.0:
			player.show_interaction_prompt("E 영업 종료" if RestaurantManager.is_open else "E 영업 시작")
		return
	if _is_livestock_door(interactable_name):
		if _message_timer <= 0.0:
			player.show_interaction_prompt("E 닫기" if _open_doors.get(interactable_name, false) else "E 열기")
		return
	if interactable_name.is_empty():
		var stall_info := LivestockManager.get_nearest_stall(player.position, GameManager.current_map_id)
		if not stall_info.is_empty():
			var stall_index := int(stall_info["stall_index"])
			if not LivestockManager.can_perform_action(stall_index):
				player.hide_interaction_prompt()
			elif _message_timer <= 0.0:
				player.show_interaction_prompt(_animal_action_prompt(stall_index))
			return
		var box_info := StorageBoxManager.get_nearest_box(player.position, GameManager.current_map_id)
		if not box_info.is_empty():
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 상자 열기")
			return
		if FishingManager.is_waiting_for_bite():
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 낚시 취소")
			return
		if FishingManager.can_start_fishing() and world_map.is_water_cell(player.get_facing_tile_position()) and not InventoryManager.is_full():
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 낚시하기")
			return
		# 농사는 낚시와 달리 바라보는 칸이 아니라 지금 서 있는 칸을 대상으로
		# 한다(사용자 지시) - 물 위에서 낚시하는 것과 달리 경작지는 그 위에
		# 직접 서서 작업하는 게 더 자연스럽다는 판단.
		var farm_action := FarmingManager.get_available_action(player.position)
		if not farm_action.is_empty():
			if farm_action == "harvest" and not FarmingManager.can_harvest(player.position):
				player.hide_interaction_prompt()
			elif _message_timer <= 0.0:
				player.show_interaction_prompt(_farm_action_prompt(farm_action))
			return
	if _message_timer <= 0.0:
		player.hide_interaction_prompt()


## cowshed_interior.tmx의 door1_open~door4_open과 같은 이름 규칙 - 다른 맵에
## 같은 규칙의 문이 추가돼도 하드코딩된 4개 목록 없이 자동으로 인식된다.
func _is_livestock_door(interactable_name: String) -> bool:
	return interactable_name.begins_with("door") and interactable_name.ends_with("_open")


## 손에 선물이 장착돼 있으면 대화 대신 "E 선물하기" 프롬프트를 보여준다(여물을
## 손에 들고 축사로 가는 것과 같은 UX - 사용자 지시). 이미 오늘 그 NPC에게
## 선물했으면 아예 프롬프트를 숨긴다(EquipmentManager는 선물을 계속 손에 들고
## 있으므로, 여기서 매번 has_gifted_today()로 걸러줘야 함).
func _npc_interact_prompt(npc_id: String) -> String:
	var hand_item_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	if InventoryManager.get_item_category(hand_item_id) == "gift":
		return "" if InventoryManager.has_gifted_today(npc_id) else "E 선물하기"
	return "E 대화"


func _farm_action_prompt(action: String) -> String:
	match action:
		"till":
			return "E 밭 갈기"
		"water":
			return "E 물 주기"
		"plant":
			return "E 씨앗 심기"
		"harvest":
			return "E 수확"
		_:
			return ""


func _animal_action_prompt(stall_index: int) -> String:
	match LivestockManager.get_equipped_action(stall_index):
		"feed":
			return "E 먹이 주기"
		"milk":
			return "E 착유"
		"slaughter":
			return "E 도살"
		_:
			return "E 상호작용"


func _handle_animal_interaction(stall_index: int) -> void:
	match LivestockManager.get_equipped_action(stall_index):
		"feed":
			_show_temporary_message(LivestockManager.perform_feed(stall_index))
		"milk":
			_show_temporary_message(LivestockManager.perform_milk(stall_index))
		"milk_wrong_animal":
			AudioManager.play_sfx(AudioManager.SFX_BEEP)
			_show_temporary_message("소에게만 사용할 수 있다.")
		"slaughter":
			var request := LivestockManager.get_slaughter_request(stall_index)
			if request.is_empty():
				pass
			elif bool(request.get("denied", false)):
				_show_temporary_message(String(request.get("message", "")))
			elif not bool(request.get("needs_confirm", true)):
				# 우유가 없는 동물(돼지 등)은 확인 팝업 없이 바로 도살한다(사용자 지시).
				_show_temporary_message(LivestockManager.perform_slaughter(stall_index))
			elif livestock_confirm_popup != null:
				_pending_slaughter_stall = stall_index
				livestock_confirm_popup.open_with_message(String(request.get("message", "")))
		_:
			AudioManager.play_sfx(AudioManager.SFX_BEEP)
			_show_temporary_message("여물/양동이/작은 칼을 손에 장착해야 한다.")


func _on_livestock_confirmed() -> void:
	if _pending_slaughter_stall < 0:
		return
	var message := LivestockManager.perform_slaughter(_pending_slaughter_stall)
	_pending_slaughter_stall = -1
	if not message.is_empty():
		_show_temporary_message(message)


func _on_restaurant_confirmed() -> void:
	if RestaurantManager.is_open:
		RestaurantManager.close_restaurant()
	elif not RestaurantManager.open_restaurant():
		_show_temporary_message(RESTAURANT_HOURS_MESSAGE)


func _show_temporary_message(text: String) -> void:
	_message_timer = MESSAGE_DURATION
	player.show_interaction_prompt(text)


func _is_any_modal_open() -> bool:
	return (shop_screen != null and shop_screen.modulate.a > 0.0) \
		or (cooking_screen != null and cooking_screen.modulate.a > 0.0) \
		or (computer_screen != null and computer_screen.modulate.a > 0.0) \
		or (collection_screen != null and collection_screen.modulate.a > 0.0) \
		or (dialogue_screen != null and dialogue_screen.modulate.a > 0.0) \
		or (sleep_confirm_popup != null and sleep_confirm_popup.modulate.a > 0.0) \
		or (status_screen != null and status_screen.visible) \
		or (restaurant_confirm_popup != null and restaurant_confirm_popup.modulate.a > 0.0) \
		or (kitchen_screen != null and kitchen_screen.visible) \
		or (serving_screen != null and serving_screen.modulate.a > 0.0) \
		or (fishing_screen != null and fishing_screen.visible) \
		or (livestock_confirm_popup != null and livestock_confirm_popup.modulate.a > 0.0) \
		or (book_screen != null and book_screen.modulate.a > 0.0) \
		or (storage_screen != null and storage_screen.visible) \
		or _is_sleep_transition_playing


## _is_any_modal_open()과 같지만 kitchen_screen은 제외한다 - 위 함수 주석 참고.
func _should_pause_time() -> bool:
	if kitchen_screen != null and kitchen_screen.visible:
		return false
	return _is_any_modal_open()


## 요리창/상점창/인벤토리창 등 모달 창이 하나라도 열려있으면 플레이어 이동을
## 막고, 창 바깥(게임 월드) 위에 반투명 검은 막을 씌워 비활성 느낌을 준다.
## 시간 정지는 조리기구 화면(kitchen_screen)만 예외다 - 조리기구는 실제 시간
## 기준으로 돌아가는데(new_cooking_system.md 3.3), 화면을 열어둔 동안 게임
## 시간까지 멈추면 레스토랑 영업시간/NPC 스케줄이 그만큼 밀리는 게 사용자
## 피드백으로 어색하다고 확인됨 - 조리기구 화면만 열려있을 땐 시간이 계속 간다.
func _update_ui_blocking() -> void:
	var any_open := _is_any_modal_open()
	# 낚싯줄이 나가 있는 동안(입질 대기 + 미니게임)은 모달 창이 없어도 이동을
	# 막는다 - 그래야 웜프 타일을 밟거나 맵을 벗어나는 상황 자체가 물리적으로
	# 발생하지 않아서, 낚시 도중 맵이 바뀌는 경우를 따로 취소 처리할 필요가 없다.
	if player != null:
		player.set_movement_enabled(not any_open and not FishingManager.is_active())
	if _ui_dim != null:
		_ui_dim.color.a = UI_DIM_ALPHA if any_open else 0.0
	if _should_pause_time():
		TimeManager.pause()
	else:
		TimeManager.resume()
	# 버튼을 클릭하면 그 버튼이 키보드 포커스를 가져가는데, 화면을 닫아도
	# 자동으로 안 풀린다 - 포커스가 남아있으면 TAB 등 단축키가 status_screen
	# 같은 _unhandled_input에 도달하기 전에 Godot의 내장 "다음 포커스로 이동"
	# 기능이 먼저 가로채버린다. 모달이 전부 닫힌 상태에선 항상 포커스를 비워서
	# 방지한다. **any_open 기준이어야 한다** - _should_pause_time() 기준으로
	# 하면(예전 실수) 조리기구 화면처럼 "열려있지만 시간은 안 멈추는" 모달이
	# 떠있는 동안 이 코드가 매 프레임 계속 실행돼서, 실제 마우스로 버튼을
	# 누르는 도중(누름-뗌 사이 여러 프레임 걸림)에 포커스가 계속 풀리며 클릭
	# 자체가 씹히는 버그가 있었다(사용자 리포트: 조리기구 화면의 닫기 버튼이
	# 안 눌림).
	if not any_open:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null:
			get_viewport().gui_release_focus()


## 조리기구 화면을 열어둔 채로 그 기구 범위를 벗어나면 자동으로 닫는다 - 안 그러면
## 자리를 벗어나도 계속 조리를 시도할 수 있었다(옛 cooking_screen과 동일한 이유).
func _close_kitchen_screen_if_out_of_range(interactable: Dictionary) -> void:
	if kitchen_screen == null or not kitchen_screen._is_open():
		return
	if String(interactable.get("name", "")) != kitchen_screen.current_station_id():
		kitchen_screen.close()


## 완성대 화면도 조리기구와 같은 이유로 범위를 벗어나면 자동으로 닫는다.
func _close_serving_screen_if_out_of_range(interactable: Dictionary) -> void:
	if serving_screen == null or not serving_screen._is_open():
		return
	var expected_name := "%s%d" % [SERVING_AREA_PREFIX, serving_screen.current_station_index() + 1]
	if String(interactable.get("name", "")) != expected_name:
		serving_screen.close()


## 상자는 Tiled Interactable이 아니라 StorageBoxManager가 근접 판정을 직접
## 하므로(get_nearest_box), 위 두 함수처럼 정적 interactable 이름을 비교하는
## 대신 지금 가장 가까운 상자 칸이 열려있는 칸과 같은지로 판단한다.
func _close_storage_screen_if_out_of_range() -> void:
	if storage_screen == null or not storage_screen._is_open():
		return
	var nearest := StorageBoxManager.get_nearest_box(player.position, GameManager.current_map_id)
	if nearest.is_empty() or Vector2i(nearest["cell"]) != storage_screen.current_cell():
		storage_screen.close()


## world_map의 직계 자식으로 한 번만 만들어두고 맵이 바뀌어도 계속 재사용한다
## (world_map 노드 자체는 재생성되지 않고 내용만 바뀌므로, 다른 런타임
## 오브젝트들과 달리 이건 despawn/respawn할 필요가 없다 - 항상 켜져 있다가
## visible만 토글됨).
func _build_box_preview() -> void:
	_box_preview = Sprite2D.new()
	_box_preview.visible = false
	_box_preview.z_index = 100
	world_map.add_child(_box_preview)


## 상자를 손에 들고 집(HOME_MAP_ID)에 있을 때만, 마우스 아래 칸에 반투명
## 미리보기를 띄운다 - 놓을 수 있는 칸이면 흰색, 막혀있거나 이미 상자가
## 있으면 붉게 표시한다(사용자 지시: 스타듀처럼 위치를 보면서 설치).
func _update_box_preview() -> void:
	if _box_preview == null:
		return
	var show_preview := not _is_any_modal_open() \
		and EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT) == StorageBoxManager.BOX_ITEM_ID \
		and GameManager.current_map_id == StorageBoxManager.HOME_MAP_ID
	_box_preview.visible = show_preview
	if not show_preview:
		return
	var mouse_world := world_map.get_global_mouse_position()
	var cell := Vector2i(int(mouse_world.x) / WorldMap.TILE_SIZE, int(mouse_world.y) / WorldMap.TILE_SIZE)
	var cell_center := Vector2(cell) * WorldMap.TILE_SIZE + Vector2.ONE * WorldMap.TILE_SIZE * 0.5
	var texture := StorageBoxManager.get_preview_texture()
	_box_preview.texture = texture
	_box_preview.position = cell_center
	var height: float = texture.get_height() if texture != null else WorldMap.TILE_SIZE
	_box_preview.offset = Vector2(0, -(height - WorldMap.TILE_SIZE) / 2.0)
	var valid := StorageBoxManager.can_place_box(cell_center) and not StorageBoxManager.has_box_at(GameManager.current_map_id, cell)
	_box_preview.modulate = Color(1, 1, 1, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)


## Building doors (entering/leaving a "*_interior" map) require an explicit E
## press; open-air plaza-to-plaza edges warp instantly on touch instead.
func _is_building_transition(warp: Dictionary) -> bool:
	var target_map := String(warp.get("target_map", ""))
	return GameManager.current_map_id.ends_with("_interior") or target_map.ends_with("_interior")


## skip_fade: 호출하는 쪽이 이미 화면을 검게 만들어 둔 상태에서 맵만 갈아
## 끼우고 싶을 때 쓴다(예: _play_collapse_transition - 취침 연출처럼 페이드/
## "N일차" 표시를 자기가 직접 감싸고, 그 사이에 맵 전환만 조용히 끼워 넣어야
## 해서 이 함수가 또 자기만의 페이드를 하면 화면이 두 번 깜빡인다).
func _load_map(map_id: String, spawn_name: String, skip_fade: bool = false) -> void:
	if world_map == null or player == null or _is_transitioning:
		return
	var map_path: String = String(WorldMap.MAP_PATHS.get(map_id, ""))
	if map_path.is_empty():
		push_error("Map is not registered: %s" % map_id)
		return
	_is_transitioning = true
	_open_doors.clear()
	# 실내/실외 경계를 넘는지는 GameManager.current_map_id가 아직 이전 맵인
	# 지금 시점에 미리 재둬야 한다 - 아래 GameManager.set_current_map(map_id)가
	# 지나가면 "이전 맵"을 더 이상 알 수 없다.
	var was_indoor := GameManager.current_map_id.ends_with("_interior")
	if not skip_fade:
		await _fade_out()
	world_map.load_map(map_path)
	var is_indoor := map_id.ends_with("_interior")
	if _lighting_layer != null:
		_lighting_layer.rebuild_lights(world_map, is_indoor)
	if _weather_layer != null:
		_weather_layer.set_indoor(is_indoor)
	var spawn_position: Vector2 = world_map.get_spawn_position(spawn_name)
	if spawn_position == Vector2.INF:
		push_error("Spawn point is missing: %s in %s" % [spawn_name, map_id])
	else:
		player.position = spawn_position
		player.set_camera_bounds(world_map.get_map_size())
		player.snap_camera()
		player.hide_interaction_prompt()
		GameManager.set_current_map(map_id)
		_update_restaurant_sign()
		LivestockManager.set_world_map(world_map, map_id)
		FarmingManager.set_world_map(world_map, map_id)
		StorageBoxManager.set_world_map(world_map, map_id)
		if was_indoor != is_indoor:
			AudioManager.play_sfx(AudioManager.SFX_DOOR)
	if not skip_fade:
		await _fade_in()
	_is_transitioning = false


func _fade_out() -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_DURATION)
	await tween.finished


func _fade_in() -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, FADE_DURATION)
	await tween.finished


## 침대 확인창에서 "예"를 고르면 화면을 잠깐 까맣게 만들고 그 위에 "N일차"를
## 띄워서 실제로 하루가 지났다는 걸 체감시킨다 - 날짜 자체는 화면이 완전히
## 까매진 다음 TimeManager.sleep_now()로 넘긴다(글자에 찍히는 날짜가 항상
## 넘어간 다음 날짜가 되도록).
func _play_sleep_transition() -> void:
	_is_sleep_transition_playing = true
	await _fade_out()
	TimeManager.sleep_now()
	if _day_label != null:
		_day_label.text = "%d일차" % TimeManager.current_day
		_day_label.modulate.a = 1.0
	await get_tree().create_timer(DAY_LABEL_HOLD_DURATION).timeout
	if _day_label != null:
		_day_label.modulate.a = 0.0
	await _fade_in()
	_is_sleep_transition_playing = false


## 24:00까지 스스로 취침하지 않았을 때(TimeManager.player_collapsed) - 취침
## 연출(_play_sleep_transition)과 같은 구조(페이드아웃 -> "N일차" 표시 ->
## 페이드인)를 쓰되, 그 사이에 병원으로 맵을 옮기고 디버프를 건다.
func _play_collapse_transition() -> void:
	_is_sleep_transition_playing = true
	await _fade_out()
	_load_map(HOSPITAL_MAP_ID, HOSPITAL_WAKE_SPAWN, true)
	player.apply_speed_effect(COLLAPSE_DEBUFF_PERCENT, COLLAPSE_DEBUFF_MINUTES, true)
	if _day_label != null:
		_day_label.text = "%d일차" % TimeManager.current_day
		_day_label.modulate.a = 1.0
	await get_tree().create_timer(DAY_LABEL_HOLD_DURATION).timeout
	if _day_label != null:
		_day_label.modulate.a = 0.0
	await _fade_in()
	_is_sleep_transition_playing = false


func _on_interact_pressed() -> void:
	if world_map == null or player == null:
		return
	# 대화창 등 모달이 이미 열려있으면 E는 그 창 자신의 _unhandled_input이
	# 처리한다(대화 넘기기 등) - 여기서 또 월드 상호작용(계산대/조리대 등)까지
	# 같이 처리하면, NPC가 자기 근무지 바로 옆에 서 있을 때 대화 넘기려고 누른
	# E가 계산대까지 같이 눌러버리는 문제가 생긴다.
	if _is_any_modal_open():
		return
	var interactable := world_map.get_interactable_at(player.position)
	if _is_npc_talk_priority(interactable):
		var npc_id := String(_nearest_talkable_npc(player.position).get("npc_id", ""))
		var hand_item_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
		if InventoryManager.get_item_category(hand_item_id) == "gift":
			# 이미 오늘 선물했으면 _npc_interact_prompt()가 프롬프트를 숨겨서 E를
			# 못 누르게 하지만, 그 사이 방어적으로 한 번 더 확인한다 - "" 그대로
			# _show_temporary_message에 넘기면 빈 프롬프트가 잠깐 뜨고 그동안
			# 다음 프롬프트 갱신도 막힌다(_farm_action_prompt 쪽과 동일 이유).
			if not InventoryManager.has_gifted_today(npc_id):
				_show_temporary_message(InventoryManager.give_gift_from_hand(npc_id))
		else:
			npc_talk_interacted.emit(npc_id)
		return
	var warp: Dictionary = world_map.get_warp_at(player.position)
	if not warp.is_empty() and _is_building_transition(warp):
		# restaurant.md: "영업 중엔 레스토랑을 벗어날 수 없다 - 외출하려면 먼저
		# 영업을 종료해야 한다." RestaurantManager.can_player_leave()는 이미
		# 있었는데 아무도 호출을 안 해서 실제로는 막히지 않고 있었다.
		if GameManager.current_map_id == RESTAURANT_SIGN_MAP_ID and not RestaurantManager.can_player_leave():
			_show_temporary_message(RESTAURANT_CANNOT_LEAVE_MESSAGE)
			return
		_load_map(warp["target_map"], warp["target_spawn"])
		return
	if not interactable.is_empty():
		_handle_interaction(interactable)
		return
	var stall_info := LivestockManager.get_nearest_stall(player.position, GameManager.current_map_id)
	if not stall_info.is_empty():
		_handle_animal_interaction(int(stall_info["stall_index"]))
		return
	var box_info := StorageBoxManager.get_nearest_box(player.position, GameManager.current_map_id)
	if not box_info.is_empty():
		storage_box_interacted.emit(box_info["cell"])
		return
	if FishingManager.is_waiting_for_bite():
		FishingManager.cancel_fishing()
		return
	if FishingManager.can_start_fishing() and world_map.is_water_cell(player.get_facing_tile_position()) and not InventoryManager.is_full():
		if FishingManager.start_fishing():
			AudioManager.play_sfx(AudioManager.SFX_BUBBLE)
		return
	# 농사는 낚시와 달리 바라보는 칸이 아니라 지금 서 있는 칸을 대상으로
	# 한다(사용자 지시, _process()의 프롬프트 판정과 동일 기준이어야 함).
	var farm_position := player.position
	match FarmingManager.get_available_action(farm_position):
		"till":
			# 마른/젖은 흙 그림이 바로 보이니 문구 없이 조용히 처리(사용자
			# 지시, "plant"/"water"와 같은 이유).
			FarmingManager.perform_till(farm_position)
		"water":
			# 젖은 흙 그림이 바로 보이니 문구 없이 조용히 처리(사용자 지시,
			# "plant"와 같은 이유).
			FarmingManager.perform_water(farm_position)
		"plant":
			# 씨앗 그림이 바로 보이니 문구 없이 조용히 처리(사용자 지시) - 빈
			# 문자열을 _show_temporary_message에 넘기면 빈 프롬프트가 잠깐
			# 뜨고 그동안 다음 프롬프트 갱신도 막히니 아예 호출하지 않는다.
			FarmingManager.perform_plant(farm_position)
		"harvest":
			_show_temporary_message(FarmingManager.perform_harvest(farm_position))


func _nearest_talkable_npc(position: Vector2) -> Dictionary:
	if npc_layer == null:
		return {}
	return npc_layer.call("get_nearest_talkable_npc", position)


## 웃음: 그냥 마주칠 때(기본 인사). npc_id가 이전 프레임과 같으면(계속 같은
## NPC 옆에 붙어있는 중) 아무것도 안 하고, 바뀔 때만(새로 접근했거나 아무도
## 없는 상태로 빠졌을 때) 갱신한다 - 그래야 붙어있는 동안 매 프레임 반복
## 발동하지 않고, 한 번 멀어졌다 다시 오면 재발동한다.
## 비 오는 날 풀죽음 트리거는 제거함(사용자 지시 2026-08-07) - 모든 NPC가
## 똑같은 트리거를 공유하면 "시스템"처럼 느껴진다며, 트리거는 나중에 NPC별로
## 따로 설계하겠다고 함. 풀죽음 아이콘 자체(EMOTE_DEJECTED)는 시트에 남아있고
## 나중에 다시 배정 가능.
func _handle_npc_encounter(npc_id: String) -> void:
	if npc_id == _last_nearby_npc_id:
		return
	_last_nearby_npc_id = npc_id
	if npc_id.is_empty():
		return
	NPCManager.request_emote(npc_id, NPCManager.EMOTE_SMILE)


## TALK_RADIUS(24px)가 계산대 같은 정적 Interactable의 INTERACT_RADIUS(12px)
## 보다 넓다 보니, 카페처럼 계산대와 NPC가 서 있는 자리가 가까운 곳에서는 항상
## 대화 판정 범위 안에 계산대도 함께 들어와 버린다("계산대를 쓰려는데 말이
## 걸어짐"). 둘 다 범위 안이면 실제로 더 가까운 쪽을 우선하도록 거리를 비교한다
## - 정적 Interactable이 범위 밖이면(= 지금 대화만 가능한 상황) 그대로 대화 우선.
func _is_npc_talk_priority(interactable: Dictionary) -> bool:
	var talk_info := _nearest_talkable_npc(player.position)
	if talk_info.is_empty():
		return false
	if interactable.is_empty():
		return true
	var npc_distance := float(talk_info.get("distance", 0.0))
	var interactable_distance := player.position.distance_to(interactable.get("position", player.position))
	return npc_distance <= interactable_distance


func _handle_interaction(interactable: Dictionary) -> void:
	var interactable_name := String(interactable.get("name", ""))
	if _is_livestock_door(interactable_name):
		var now_open := not bool(_open_doors.get(interactable_name, false))
		world_map.set_door_open(interactable, now_open)
		_open_doors[interactable_name] = now_open
		AudioManager.play_sfx(AudioManager.SFX_DOOR)
		return
	if interactable_name == "cash_register":
		var shop_id := String(interactable.get("shop_id", ""))
		if not shop_id.is_empty() and ShopManager.is_staffed(shop_id):
			shop_interacted.emit(shop_id)
		return
	if interactable_name == "restaurant_open":
		# 10시 전에 팻말 앞에서 연타하다 열렸다 닫혔다 하는 문제(사용자 리포트)로
		# 즉시 토글하지 않고 매번 확인창을 거친다 - 팝업이 열려있는 동안은
		# _is_any_modal_open()이 막아줘서 그 사이엔 다시 연타해도 안 먹힌다.
		if RestaurantManager.is_open:
			restaurant_confirm_popup.open_with_message("레스토랑을 닫으시겠습니까?")
		elif TimeManager.current_hour < RestaurantManager.OPEN_HOUR or TimeManager.current_hour >= RestaurantManager.CLOSE_HOUR:
			_show_temporary_message(RESTAURANT_HOURS_MESSAGE)
		else:
			restaurant_confirm_popup.open_with_message("레스토랑을 여시겠습니까?")
		return
	if interactable_name == "computer":
		computer_interacted.emit()
		return
	if interactable_name == "collection":
		collection_interacted.emit()
		return
	if interactable_name.begins_with(SERVING_AREA_PREFIX):
		var station_index := interactable_name.trim_prefix(SERVING_AREA_PREFIX).to_int() - 1
		if not RestaurantManager.is_station_npc_settled(station_index):
			_show_temporary_message(RESTAURANT_NOT_READY_MESSAGE)
		elif not RestaurantManager.get_station_dish(station_index).is_empty():
			_show_temporary_message(ALREADY_SERVED_MESSAGE)
		else:
			AudioManager.play_sfx(AudioManager.SFX_DISH)
			serving_area_interacted.emit(station_index)
		return
	if interactable_name.begins_with(KITCHEN_STATION_PREFIX):
		if not RestaurantManager.is_open:
			_show_temporary_message(RESTAURANT_NOT_READY_MESSAGE)
		else:
			kitchen_station_interacted.emit(interactable_name)
