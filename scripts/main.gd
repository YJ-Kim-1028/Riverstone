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
signal jukebox_interacted
signal npc_talk_interacted(npc_id: String)
## StorageBoxManager - 근처에 이미 상자가 있을 때 E를 누르면(설치 아님, 열기).
signal storage_box_interacted(cell: Vector2i)

const SERVING_AREA_PREFIX := "serving_area"
const KITCHEN_STATION_PREFIX := "cooking_area"
const RESTAURANT_NOT_READY_MESSAGE := "먼저 레스토랑을 열자."
const ALREADY_SERVED_MESSAGE := "이미 손님이 요리를 먹고 있다."
const RESTAURANT_HOURS_MESSAGE := "오전 10시부터 오후 4시까지만 영업할 수 있다."
const RESTAURANT_CANNOT_LEAVE_MESSAGE := "영업 중에는 레스토랑을 벗어날 수 없다."
## horror_events.md "NPC 집 잠금" - "NPC맵=NPC가게"(사용자 확정 2026-08-16)라
## 상점 맵으로 해석해서 막는다.
const SHOP_LOCKED_MESSAGE := "문이 굳게 잠겨 있다."
## 살인 대기 중인 밤(비 오는 중 + 22시 전)에 취침을 막을 때 쓰는 문구 - 첫
## 살인 전엔 공포 요소를 인지시키면 안 되므로(CLAUDE.md) 노골적인 암시 없이
## 평범한 "잠이 안 온다" 톤으로 잡았다. 문구는 임시 - 기획 확정 시 교체 가능.
const SLEEPLESS_NIGHT_MESSAGE := "잠이 오지 않아."
const MESSAGE_DURATION := 2.0
## 밭갈기/물주기처럼 한 프레임에 즉시 끝나는 액션은 자체 지속시간이 없어서,
## player.tool_overlay 사용 포즈가 최소 이만큼은 눈에 보이도록 붙잡아둔다
## (낚시는 자체 대기시간이 있어 이 상수를 안 쓴다. 망치 회수는 사용자 지시로
## 포즈 대상에서 제외, 2026-08-12).
const TOOL_USE_HOLD_SECONDS := 0.35
const FARM_TILE_HIGHLIGHT_BORDER := 2

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
@onready var npc_world_manager: Node2D = get_node_or_null("HomeMap/NPCLayer") as Node2D
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
@onready var jukebox_screen: Control = get_node_or_null("UI/JukeboxScreen") as Control
@onready var _restaurant_sign: Sprite2D = get_node_or_null("HomeMap/RestaurantSign") as Sprite2D
## horror_events.md "레스토랑 액자 이벤트" - Wall_deco 레이어의 액자 타일(15,2)
## 위에 겹쳐 놓은 오버레이. RestaurantSign과 같은 방식으로 world_map 하위에
## 미리 배치해두고, 살인 발생 후 첫 입장 때만 색을 빨갛게 튀겼다 되돌린다.
@onready var _restaurant_frame_blood: ColorRect = get_node_or_null("HomeMap/RestaurantFrameBlood") as ColorRect
## _load_map()이 맵을 나갈 때 이 트윈을 강제로 죽이고 오버레이를 숨긴다
## (사용자 리포트, 2026-08-24: "레스토랑에서 나갔는데도 핏자국이 보여" -
## 애니메이션이 안 끝난 채로 맵을 나가면 다음 맵까지 계속 남아있었음).
var _restaurant_frame_blood_tween: Tween = null
## 2026-08-24: 하드코딩된 셀 좌표(15,2)가 입구에서 안 보이는 맵 반대쪽
## 구석이었다는 사용자 리포트로, restaurant_interior_new.tmx의 "EffectArea"
## 오브젝트 레이어(WorldMap.get_effect_area() 참고)에 이 이름으로 찍은
## 영역을 쓰는 걸로 바꿨다(사용자 배치 예정) - 액자 실제 그림 크기만큼
## 영역을 잡아서 오버레이가 액자 전체를 덮게 한다. 못 찾으면(아직 안
## 찍었으면) 조용히 스킵한다(다른 사용자 제공 좌표들과 동일 패턴).
const RESTAURANT_FRAME_AREA := "restaurant_frame_blood"
## 2026-08-24: 절차적 얼룩 모양 셰이더를 시도했다가 "PPT 클립아트 같다"는
## 피드백으로 폐기 - 대신 곱하기(Multiply) 블렌드로 실제 액자 그림 위에
## 빨간 틴트만 씌운다(그림 자체가 빨갛게 변한 것처럼 보임, 새 그림 불필요).
## 흰색(곱해도 원본 그대로)에서 이 색으로 갔다가 다시 흰색으로 돌아온다.
const RESTAURANT_FRAME_BLOOD_TINT := Color(0.9, 0.1, 0.1, 1.0)
const RESTAURANT_FRAME_BLOOD_IN_SECONDS := 0.15
const RESTAURANT_FRAME_BLOOD_HOLD_SECONDS := 3.0
const RESTAURANT_FRAME_BLOOD_OUT_SECONDS := 0.4
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

## 가구 설치 미리보기 - _box_preview와 완전히 같은 방식(world_map 자식,
## _build_furniture_preview()에서 한 번만 생성)이지만 칸수(footprint)가
## 아이템마다 달라서 크기/오프셋을 매 프레임 다시 계산한다.
var _furniture_preview: Sprite2D = null

## 바닥/벽 장식 설치 미리보기 - _furniture_preview와 완전히 같은 패턴
## (day10, 벽장식 시스템 도입을 계기로 가구 옆에 나란히 추가).
var _floor_decor_preview: Sprite2D = null
var _wall_decor_preview: Sprite2D = null

## 괭이/물뿌리개를 손에 들고 있을 때 밭갈기/물주기 대상 칸(플레이어가 서 있는
## 칸 - FarmingManager.get_available_action()과 같은 기준)에 뜨는 반투명 칸
## 표시 - _box_preview와 같은 패턴(world_map 자식, 한 번만 생성, modulate로
## 흰색/붉은색만 바꿔가며 재사용). 실제 아이템 그림이 아니라 흰 정사각형
## 하나를 코드로 만들어 쓴다(assets/ 폴더에 새 그림 추가 불가 - CLAUDE.md).
var _farm_tile_highlight: Sprite2D = null

var _is_transitioning := false
## _on_murder_occurred() 진행 중에는 참 - 플레이어가 player.walk_to()로
## 스크립트 이동하는 동안 워프 지점을 밟아도 _process()의 평소 "밟으면 자동
## 다음 맵" 로직이 끼어들지 않게 막는다(끼어들면 같은 전환을 두 시스템이
## 동시에 처리하려다 페이드가 서로 꼬여서 멈춰버림 - 실제로 이 버그로 게임이
## 응답 없음 상태가 됐었음, 2026-08-16). 맵 전환은 이 씬이 진행되는 동안
## _on_murder_occurred() 자신이 명시적으로만 처리한다.
var _murder_scene_active := false
## 괭이/물뿌리개 포즈 재생 중(TOOL_USE_HOLD_SECONDS)에 E를 한 번 더 누르면
## _on_interact_pressed()가 재진입해서 perform_till()이 아직 커밋 안 된 같은
## 칸을 "till"로 다시 판정 - 첫 호출이 끝나기 전에 두 번째 코루틴이 같은
## 애니메이션/타이머를 새로 시작해버리는 레이스였다(사용자 리포트: "괭이질
## 한 번 더 하면 안 갈아둔 상태로 복귀", 2026-08-16). 진행 중엔 새 농사
## 액션을 아예 안 받는다.
var _farm_action_active := false
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
	if jukebox_screen != null:
		jukebox_interacted.connect(jukebox_screen.open)
	RestaurantManager.restaurant_opened.connect(_update_restaurant_sign)
	RestaurantManager.restaurant_closed.connect(_update_restaurant_sign)
	InventoryManager.item_used.connect(_on_item_used)
	CookingManager.recipe_learned.connect(_on_recipe_learned)
	TimeManager.player_collapsed.connect(_play_collapse_transition)
	TimeManager.hour_changed.connect(_on_hour_changed)
	FurnitureManager.furniture_changed.connect(_on_decor_changed)
	FloorDecorManager.floor_decor_changed.connect(_on_decor_changed)
	WallDecorManager.wall_decor_changed.connect(_on_decor_changed)
	ShopManager.furniture_hammer_granted.connect(_on_furniture_hammer_granted)
	FishingManager.fishing_ended.connect(_on_fishing_ended)
	AudioManager.knock_sequence_finished.connect(_on_knock_sequence_finished)
	TimeManager.day_changed.connect(_on_day_changed_clear_knock_check)
	MurderManager.murder_occurred.connect(_on_murder_occurred)
	_build_box_preview()
	_build_furniture_preview()
	_build_floor_decor_preview()
	_build_wall_decor_preview()
	_build_farm_tile_highlight()
	_load_map("Home", "start_spawn")


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


## 23시가 되면 취침(24시 강제취침)이 머지않았음을 미리 알린다(사용자 지시).
const SLEEPY_WARNING_HOUR := 23
const SLEEPY_WARNING_MESSAGE := "졸려 쓰러질 거 같다..."


func _on_hour_changed(hour: int) -> void:
	if hour == SLEEPY_WARNING_HOUR:
		_show_temporary_message(SLEEPY_WARNING_MESSAGE)


## 가구/바닥장식/벽장식이 배치·회수될 때마다(emits_light인 아이템이 아니어도
## 매번 호출되지만 개수가 적어 비용 무시 가능) 조명을 다시 계산한다 - 맵을
## 나갔다 들어오지 않아도 조명 가구를 놓는 즉시 방이 밝아지도록.
func _on_decor_changed() -> void:
	if _lighting_layer == null or world_map == null:
		return
	_lighting_layer.rebuild_lights(world_map, GameManager.current_map_id.ends_with("_interior"), GameManager.current_map_id)


## 가구/바닥장식/벽장식 회수(프롬프트 표시 + E 실행 둘 다)는 가구용 망치를
## 손에 들고 있을 때만 동작한다(사용자 지시) - 그냥 지나갈 때마다 "E 가구
## 회수" 프롬프트가 뜨는 게 거슬린다는 피드백 해결. 망치는 우디 가게에서
## 가구/바닥장식/벽장식을 처음 사면 선물로 받는다(ShopManager 참고).
func _is_furniture_hammer_equipped() -> bool:
	return EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT) == ShopManager.FURNITURE_HAMMER_ITEM_ID


## 가구용 망치를 처음 받는 순간(사용자 지시: "구매창은 바로 닫히고 우디의
## 말이 뜨고 전해받는게 낫다") - 상점 창을 닫고, 그 상점 주인이 선물 대사를
## 하는 일회성 대화를 강제로 띄운다(dialogue_screen.open_special() 참고,
## 요일/호감도 로테이션 없이 woody.json의 furniture_hammer_gift_lines만 그대로
## 보여줌). 아직 대사가 안 채워져 있으면 dialogue_screen이 알아서 자리표시자로
## 대체한다.
func _on_furniture_hammer_granted(npc_id: String) -> void:
	if shop_screen != null:
		shop_screen.close()
	if dialogue_screen != null:
		var lines: Array = NPCManager.get_definition(npc_id).get("furniture_hammer_gift_lines", [])
		dialogue_screen.open_special(npc_id, lines)


const MURDER_DISCOVERY_MAP_ID := "plaza3"
const MURDER_DISCOVERY_NPC_ID := "poli"
const MURDER_DISCOVERY_TRIGGER := "murder_discovery"
## plaza3.tmx의 Spawn 오브젝트 레이어에 이 이름으로 지점 하나를 추가해야
## 한다(사용자 배치 예정) - 도착 후 폴리한테까지 마지막으로 뛰어가는 목적지.
const MURDER_DISCOVERY_POLI_SPAWN := "poli_murder_scene"
## 사용자 확정 경로표: 각 맵에서 plaza3 방향으로 가려면 어느 맵을 향해
## 뛰어야 하는지. 표에 없는 맵(실내)은 "문(그 맵의 워프 아무거나)"으로
## 향한다 - WorldMap.get_any_warp() 참고.
const MURDER_RUN_CHAIN := {
	"plaza5": "plaza4", "plaza4": "plaza2", "plaza2": "plaza1", "plaza1": "plaza3", "Home": "plaza1",
}
const POLI_DECOY_SCENE := preload("res://scenes/npc_sprite.tscn")
## 사용자 피드백(2026-08-23): 도착하자마자 바로 대사가 시작돼서 자루/폴리를
## 볼 틈이 없었음 - 폴리 위에 슬픈 이모트를 띄우고 이 시간만큼 멈춘 뒤에
## 대사를 시작한다. 대사가 끝난 직후에도 곧장 암전되어 자루가 잘 안 보인다는
## 지적이 있어 페이드 전에도 같은 시간만큼 멈춘다.
const MURDER_DISCOVERY_REACTION_DELAY_SECONDS := 5.0
const MURDER_DISCOVERY_AFTERMATH_DELAY_SECONDS := 2.5

## 2차 살인은 1차와 다른 씬으로 간다(사용자 지시, 2026-08-23 - "더 대담해진
## 범행"): plaza3까지 뛰어가는 대신, 시체가 플레이어 집(Home.tmx) 앞에
## 놓이고 플레이어가 나중에 직접 돌아왔을 때 발견한다. Home.tmx의 Spawn
## 레이어에 이 이름으로 지점 하나를 추가해야 한다(사용자 배치 예정).
const SECOND_MURDER_SACK_SPAWN := "second_murder_sack_home"
const SECOND_MURDER_DISCOVERY_TRIGGER := "second_murder_discovery"
const SECOND_MURDER_POLI_OFFSET := Vector2(10, 4)
## 자루를 확인한 직후 플레이어 혼잣말(사용자 작성, 2026-08-24) - NPC 대사가
## 아니라 dialogue_screen.open_special("", ...)로 이름/초상화 없이 띄운다.
const SECOND_MURDER_PLAYER_MONOLOGUE: Array[String] = [
	"...뭐지?",
	"이 자루, 왜 우리 집 앞에 있는 거지?",
	"안에... 뭔가 들어있다.",
	"설마...",
	"일단... 신고부터 해야겠다.",
]

## 물귀신 가짜 입질(FishingManager.is_ghost_bite()) 직후 플레이어 혼잣말
## (사용자 작성, 2026-08-24) - 씨름하는 듯한 반복 효과음이 뚝 끊긴 다음
## 호러 사운드로 놀래킨 뒤 이 대사로 마무리한다.
const GHOST_BITE_MONOLOGUE: Array[String] = [
	"무언가가 낚시대를 거세게 잡아당겼다.",
	"그러나 낚시대엔 아무것도 없다.",
]

## 노크 소리가 끝난 직후 플레이어 혼잣말(사용자 작성, 2026-08-24).
const KNOCK_PLAYER_MONOLOGUE: Array[String] = [
	"방금 무슨 소리지?",
	"나가서 확인해볼까...?",
]
## 노크 이후 실제로 문을 열고 나가봤을 때(home_interior -> Home) 아무도
## 없었다는 혼잣말(초안, 사용자 지시 2026-08-24 - "나가면 아무것도 없는거로").
## 문구는 아직 확정 아님, 수정 환영.
const KNOCK_CHECK_RESULT_MONOLOGUE: Array[String] = [
	"...아무도 없다.",
	"그냥 기분 탓이었나.",
]

## 정체를 밝히지 않는 그림자 인영(사용자 지시, 2026-08-24) - 스토커인지
## 아닌지 확정하지 않는다. 1차 살인 이후, 스토커가 아직 살아있는 동안만
## (스토커가 죽으면 이 이벤트도 저절로 끝남 - 사용자 지시) 지정된 맵에
## 들어갈 때마다 낮은 확률로 스폰 지점에 조용히 서 있다가, 플레이어가
## SHADOW_FIGURE_VANISH_DISTANCE 안으로 다가가면 그 자리에서 사라진다.
## 처음엔 기존 NPCSprite를 검게 물들여 재사용했으나, 체형/머리 모양으로
## 성별이 드러날 수 있다는 지적(사용자 리포트, 2026-08-24)으로 전용 그림
## 한 장으로 바꿨다 - 가만히 서 있기만 하므로 정면 그림 한 장이면 충분(사용자
## 확정). 파일 없으면 조용히 아무 일도 안 한다(다른 사용자 제공 에셋과 동일한
## 관례). 스폰 지점은 사용자가 직접 각 맵의 Tiled Spawn 레이어에 찍어뒀다.
const SHADOW_FIGURE_TEXTURE_PATH := "res://assets/img/shadow_figure.png"
const SHADOW_FIGURE_SPAWN_NAMES := {
	"Home": "shadow_figure_home",
	"plaza1": "shadow_figure_plaza1",
	"plaza4": "shadow_figure_plaza4",
	"plaza5": "shadow_figure_plaza5",
}
const SHADOW_FIGURE_APPEAR_CHANCE := 0.2
const SHADOW_FIGURE_VANISH_DISTANCE := 64.0

var _shadow_figure_node: Sprite2D = null

## 노크 이후 아직 문을 열고 나가보지 않은 상태 - main.gd._load_map()이
## home_interior에서 Home으로 나갈 때 이 플래그를 보고 "아무도 없다" 반응을
## 한 번 보여준 뒤 끈다.
var _knock_check_pending := false

## MurderManager.murder_occurred - 살인 발생 시각(오후 10시)에 플레이어가 뭘
## 하고 있었든 강제로 끊고 들어가는 발견 씬(사용자 지시): 비명 → 지금 있는
## 맵에서 plaza3까지 맵을 몇 개 거치든 실제로 뛰어감(MURDER_RUN_CHAIN을 한
## 칸씩 따라가며 그 방향 워프까지 player.walk_to()로 뛰고, 워프를 밟으면
## 평소 이동과 똑같이 _load_map()이 페이드와 함께 다음 맵으로 넘김) →
## plaza3 도착 즉시 폴리를 그 자리에 세워두고(실제 스케줄 스프라이트는 숨기고
## 자리표시용 분신을 하나 세움 - 스케줄이 그를 계속 다른 곳으로 끌고 가려는
## 걸 그대로 두면 씬 도중 사라져 보이는 문제 방지) 그 옆까지 뛰어가서 강제
## 대화. 대화가 끝나면 분신을 지우고 원래 스프라이트를 다시 보이게 한다.
## 2차 살인(murder_number==2)은 여기서 바로 끊고 들어가지 않는다 - 아래
## _run_second_murder_discovery_scene() 참고. MurderManager가 대기 플래그를
## 쥐고 있다가, 플레이어가 나중에 Home으로 돌아올 때 _process()가 확인해서
## 그때 씬을 재생한다.
func _on_murder_occurred(_victim_id: String, murder_number: int) -> void:
	if murder_number == 2:
		return
	_close_all_screens()
	_murder_scene_active = true
	AudioManager.play_sfx(AudioManager.SFX_SCREAM)
	while GameManager.current_map_id != MURDER_DISCOVERY_MAP_ID:
		var current_map_id := GameManager.current_map_id
		var next_map_id := String(MURDER_RUN_CHAIN.get(current_map_id, ""))
		var warp: Dictionary = world_map.get_warp_for_target_map(next_map_id) if not next_map_id.is_empty() else world_map.get_any_warp()
		if warp.is_empty():
			push_error("murder discovery run: no warp found from %s" % current_map_id)
			_murder_scene_active = false
			return
		await player.walk_to(warp["position"])
		await _load_map(String(warp["target_map"]), String(warp["target_spawn"]))
	# 이 시각 plaza3에 스케줄상 이미 있던 다른 NPC들까지 배경에 태연히 서있으면
	# 어색하다는 사용자 지적(2026-08-16) - 폴리(분신으로 대체) 포함 전원을
	# 씬 동안 숨긴다.
	_set_all_npc_sprites_hidden(true)
	var poli_spawn: Vector2 = world_map.get_spawn_position(MURDER_DISCOVERY_POLI_SPAWN)
	var scene_props: Array[Node2D] = []
	if poli_spawn != Vector2.INF:
		scene_props = _spawn_murder_discovery_poli_decoy(poli_spawn)
		await player.walk_to(poli_spawn)
		AudioManager.play_sfx(AudioManager.SFX_MURDER_1)
		if not scene_props.is_empty():
			scene_props[0].call("show_emote", NPCManager.EMOTE_DEJECTED, MURDER_DISCOVERY_REACTION_DELAY_SECONDS)
		await get_tree().create_timer(MURDER_DISCOVERY_REACTION_DELAY_SECONDS).timeout
	if dialogue_screen != null:
		var trigger: Dictionary = NPCManager.get_definition(MURDER_DISCOVERY_NPC_ID).get("story_dialogue", {}).get(MURDER_DISCOVERY_TRIGGER, {})
		dialogue_screen.open_special(MURDER_DISCOVERY_NPC_ID, (trigger.get("lines", []) as Array).duplicate())
		await dialogue_screen.closed
	# 대화가 끝나자마자 뚝 끊기지 않도록, 잠깐 정지 → 암전 → 분신/소품 정리 →
	# 전원 다시 보이게 → 암전 해제로 씬을 마무리한다("살해현장이 사라진다"는
	# 사용자 요청) - 플레이어는 같은 자리(plaza3)에서 다시 조작 가능해진다.
	await get_tree().create_timer(MURDER_DISCOVERY_AFTERMATH_DELAY_SECONDS).timeout
	await _fade_out()
	_cleanup_murder_discovery_scene_props(scene_props)
	_set_all_npc_sprites_hidden(false)
	_murder_scene_active = false
	await _fade_in()


## _process()가 "플레이어가 Home에 있고, 2차 살인 발견이 대기 중"일 때
## 호출한다. 자루만 먼저 보여주고(플레이어가 직접 발견하는 순간) 잠깐 뒤에
## 암전 → 폴리가 도착한 걸로 처리(분신 배치) → 암전 해제 → 강제 대화 →
## 마무리, 순서는 1차 발견 씬과 동일하되 뛰어가는 구간이 없다.
##
## 2단계로 나뉜다(사용자 지시, 2026-08-24 - "E 키로 상호작용해서 먼저
## 확인하고 나왔으면 좋겠다"): 1단계(_spawn_second_murder_sack, _process()가
## Home 입장을 감지해서 호출)는 자루만 조용히 세워두고 플레이어 조작은 그대로
## 풀어둔다. 2단계(_continue_second_murder_discovery, _on_interact_pressed()가
## 자루 옆에서 E를 감지하면 호출)에서만 실제로 암전/폴리 도착/강제 대화가
## 진행된다. 시체가 있는 동안은 1차 발견 씬 때처럼 마을에 아무도 지나다니지
## 않는 게 맞다는 지적이 있어서, NPC 숨김은 1단계(자루가 보이는 시점)부터
## 걸어둔다.
const SECOND_MURDER_SACK_INTERACT_RADIUS := 16.0
var _second_murder_sack_awaiting_interaction := false
var _second_murder_sack_node: Sprite2D = null
var _second_murder_sack_position := Vector2.ZERO


func _spawn_second_murder_sack() -> void:
	var sack_spawn: Vector2 = world_map.get_spawn_position(SECOND_MURDER_SACK_SPAWN)
	if sack_spawn == Vector2.INF or not ResourceLoader.exists(POLI_SACK_TEXTURE_PATH):
		return
	_set_all_npc_sprites_hidden(true)
	var sack := Sprite2D.new()
	sack.texture = load(POLI_SACK_TEXTURE_PATH)
	sack.position = sack_spawn
	world_map.add_child(sack)
	_second_murder_sack_node = sack
	_second_murder_sack_position = sack_spawn
	_second_murder_sack_awaiting_interaction = true


func _continue_second_murder_discovery() -> void:
	_second_murder_sack_awaiting_interaction = false
	_murder_scene_active = true
	_close_all_screens()
	AudioManager.play_sfx(AudioManager.SFX_FIND_BODY_2)
	var scene_props: Array[Node2D] = []
	if _second_murder_sack_node != null:
		scene_props.append(_second_murder_sack_node)
	if dialogue_screen != null:
		dialogue_screen.open_special("", SECOND_MURDER_PLAYER_MONOLOGUE.duplicate())
		await dialogue_screen.closed
	await get_tree().create_timer(MURDER_DISCOVERY_REACTION_DELAY_SECONDS).timeout
	await _fade_out()
	var poli_decoy := POLI_DECOY_SCENE.instantiate() as Node2D
	world_map.add_child(poli_decoy)
	poli_decoy.call("set_npc_id", MURDER_DISCOVERY_NPC_ID)
	poli_decoy.call("snap_to", _second_murder_sack_position + SECOND_MURDER_POLI_OFFSET)
	poli_decoy.call("face_down")
	scene_props.append(poli_decoy)
	await _fade_in()
	if dialogue_screen != null:
		var trigger: Dictionary = NPCManager.get_definition(MURDER_DISCOVERY_NPC_ID).get("story_dialogue", {}).get(SECOND_MURDER_DISCOVERY_TRIGGER, {})
		var lines: Array = (trigger.get("lines", []) as Array).duplicate()
		if not lines.is_empty():
			dialogue_screen.open_special(MURDER_DISCOVERY_NPC_ID, lines)
			await dialogue_screen.closed
	await get_tree().create_timer(MURDER_DISCOVERY_AFTERMATH_DELAY_SECONDS).timeout
	await _fade_out()
	_cleanup_murder_discovery_scene_props(scene_props)
	_second_murder_sack_node = null
	_set_all_npc_sprites_hidden(false)
	_murder_scene_active = false
	MurderManager.consume_second_murder_discovery_pending()
	await _fade_in()


func _set_all_npc_sprites_hidden(hidden: bool) -> void:
	if npc_world_manager == null:
		return
	for npc_id in NPCManager.get_all_ids():
		npc_world_manager.set_npc_sprite_hidden(npc_id, hidden)


## 사용자가 아직 안 그려서 파일이 없을 수 있음 - ResourceLoader.exists()로
## 확인해서 없으면 조용히 생략한다(다른 사용자 제공 에셋들과 동일 패턴).
## 폴리 옆에 놓을 오프셋은 임의값 - 실제 그림 크기 보고 조정 필요.
const POLI_SACK_TEXTURE_PATH := "res://assets/npc/poli_murder_sack.png"
const POLI_SACK_OFFSET := Vector2(10, 4)

## npc_world_manager.gd의 npc_sprite.tscn 인스턴스를 하나 더 만들어(같은
## 씬이라 겉모습은 완전히 동일) 정해진 자리에 고정시켜둔다 - 진짜 스케줄
## 스프라이트는 _set_all_npc_sprites_hidden()이 이미 숨겨둔 상태(호출부 참고).
## 자루 그림이 있으면 그 옆에 같이 세워둔다(씬 전용 소품이라 정리 대상에
## 같이 담아서 반환).
func _spawn_murder_discovery_poli_decoy(spawn_position: Vector2) -> Array[Node2D]:
	var decoy := POLI_DECOY_SCENE.instantiate() as Node2D
	world_map.add_child(decoy)
	decoy.call("set_npc_id", MURDER_DISCOVERY_NPC_ID)
	decoy.call("snap_to", spawn_position)
	decoy.call("face_down")
	var nodes: Array[Node2D] = [decoy]
	if ResourceLoader.exists(POLI_SACK_TEXTURE_PATH):
		var sack := Sprite2D.new()
		sack.texture = load(POLI_SACK_TEXTURE_PATH)
		sack.position = spawn_position + POLI_SACK_OFFSET
		world_map.add_child(sack)
		nodes.append(sack)
	return nodes


func _cleanup_murder_discovery_scene_props(nodes: Array[Node2D]) -> void:
	for node in nodes:
		if node != null:
			node.queue_free()


## 살인 발견 씬처럼 플레이어가 뭘 하던 중이든 강제로 끼어드는 이벤트 전에,
## 열려있을 수 있는 화면들을 방어적으로 닫는다 - close() 메서드가 있는
## 화면만 골라 부른다(이 프로젝트 화면들은 전부 이 컨벤션을 따름).
func _close_all_screens() -> void:
	for screen in [shop_screen, cooking_screen, computer_screen, collection_screen, dialogue_screen, status_screen, kitchen_screen, serving_screen, fishing_screen, book_screen, storage_screen, jukebox_screen]:
		if screen != null and screen.has_method("close"):
			screen.close()


## 낚시 사용 포즈(_on_interact_pressed의 FishingManager.start_fishing() 지점에서
## 켰음)를 입질 대기든 미니게임이든 낚싯줄이 완전히 걷힌 시점에 끈다 - 성공/실패/
## 취소(cancel_fishing()도 이 신호를 쏨, 2026-08-12) 전부 이 한 곳으로 모인다.
func _on_fishing_ended(result: Dictionary) -> void:
	player.tool_overlay.stop()
	if bool(result.get("ghost", false)):
		AudioManager.play_sfx(AudioManager.SFX_FIND_BODY_2)
		if dialogue_screen != null:
			dialogue_screen.open_special("", GHOST_BITE_MONOLOGUE.duplicate())


func _on_knock_sequence_finished() -> void:
	_knock_check_pending = true
	if dialogue_screen != null:
		dialogue_screen.open_special("", KNOCK_PLAYER_MONOLOGUE.duplicate())


## 그 밤 안에 나가서 확인하지 않으면(잠들었든, 기절해서 병원에 실려갔든)
## 하루가 지나 뜬금없이 반응이 뜨는 게 어색하다는 지적(사용자 리포트,
## 2026-08-24)으로, 날짜가 바뀌면 그 밤의 "확인 대기" 자체를 없던 일로
## 한다.
func _on_day_changed_clear_knock_check(_day: int, _weekday: String) -> void:
	_knock_check_pending = false


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


## 상자/가구/바닥장식/벽장식 미리보기가 떠 있을 때 좌클릭하면 그 자리에
## 설치한다(사용자 지시 - E 대신 마우스 클릭). 모달이 열려있으면
## _update_box_preview()/_update_furniture_preview()/_update_floor_decor_preview()/
## _update_wall_decor_preview()가 이미 각 preview.visible을 꺼두므로 여기서
## 다시 확인할 필요는 없다. 손에 장착 가능한 아이템은 한 번에 하나뿐이라
## 네 미리보기가 동시에 보이는 경우는 없다.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _box_preview != null and _box_preview.visible:
		var box_message := StorageBoxManager.place_box(_box_preview.position)
		if not box_message.is_empty():
			_show_temporary_message(box_message)
		get_viewport().set_input_as_handled()
		return
	if _furniture_preview != null and _furniture_preview.visible:
		var furniture_message := FurnitureManager.place_furniture(_furniture_preview.position)
		if not furniture_message.is_empty():
			_show_temporary_message(furniture_message)
		get_viewport().set_input_as_handled()
		return
	if _floor_decor_preview != null and _floor_decor_preview.visible:
		var floor_decor_message := FloorDecorManager.place_floor_decor(_floor_decor_preview.position)
		if not floor_decor_message.is_empty():
			_show_temporary_message(floor_decor_message)
		get_viewport().set_input_as_handled()
		return
	if _wall_decor_preview != null and _wall_decor_preview.visible:
		var wall_decor_message := WallDecorManager.place_wall_decor(_wall_decor_preview.position)
		if not wall_decor_message.is_empty():
			_show_temporary_message(wall_decor_message)
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


## RestaurantSign과 달리 이 오버레이는 벽에 평평하게 붙은 장식이라(플레이어
## 앞뒤로 가려질 일이 없음) Y-sort 앵커가 필요 없다 - RESTAURANT_FRAME_SPAWN
## 지점을 그대로 위치로 쓴다. HorrorEventManager.consume_restaurant_frame_blood_trigger()가
## 참(=이번 살인 건수에 대해 아직 안 보여줬음)일 때만 색을 튀긴다.
func _maybe_play_restaurant_frame_blood_effect() -> void:
	if _restaurant_frame_blood == null or world_map == null:
		return
	## 영역을 아직 안 찍었으면 트리거 자체를 소비하지 않고 그대로 남겨둔다 -
	## 나중에 찍고 나서도 다음 살인/리셋(F12) 때 정상 작동하게.
	var frame_area: Rect2 = world_map.get_effect_area(RESTAURANT_FRAME_AREA)
	if frame_area.position == Vector2.INF:
		return
	if not HorrorEventManager.consume_restaurant_frame_blood_trigger():
		return
	_restaurant_frame_blood.position = frame_area.position
	_restaurant_frame_blood.size = frame_area.size
	## 곱하기 블렌드로 실제 그림 위에 틴트만 씌운다(RESTAURANT_FRAME_BLOOD_TINT
	## 참고) - color가 흰색(1,1,1,1)일 땐 곱해도 원본 그대로라 평소엔 안 보이고
	## 없다.
	if _restaurant_frame_blood.material == null:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		_restaurant_frame_blood.material = material
	_restaurant_frame_blood.visible = true
	_restaurant_frame_blood.color = Color.WHITE
	## 사용자 지시(2026-08-24): 새 소리 구하는 대신 find_body_2를 재사용.
	AudioManager.play_sfx(AudioManager.SFX_FIND_BODY_2)
	if _restaurant_frame_blood_tween != null and _restaurant_frame_blood_tween.is_valid():
		_restaurant_frame_blood_tween.kill()
	_restaurant_frame_blood_tween = create_tween()
	_restaurant_frame_blood_tween.tween_property(_restaurant_frame_blood, "color", RESTAURANT_FRAME_BLOOD_TINT, RESTAURANT_FRAME_BLOOD_IN_SECONDS)
	_restaurant_frame_blood_tween.tween_interval(RESTAURANT_FRAME_BLOOD_HOLD_SECONDS)
	_restaurant_frame_blood_tween.tween_property(_restaurant_frame_blood, "color", Color.WHITE, RESTAURANT_FRAME_BLOOD_OUT_SECONDS)
	_restaurant_frame_blood_tween.tween_callback(func() -> void: _restaurant_frame_blood.visible = false)


func _process(delta: float) -> void:
	_update_ui_blocking()
	if world_map == null or player == null:
		return
	if not _murder_scene_active and not _is_transitioning:
		if GameManager.current_map_id == "Home" and MurderManager.is_second_murder_discovery_pending() \
				and not _second_murder_sack_awaiting_interaction and _second_murder_sack_node == null:
			_spawn_second_murder_sack()
		elif _second_murder_sack_awaiting_interaction and GameManager.current_map_id != "Home":
			# 집을 나가면 world_map이 다른 맵으로 다시 로드되면서 자루 노드는
			# 이미 사라진 상태 - 다음에 Home에 돌아오면 새로 스폰되게 리셋.
			_second_murder_sack_awaiting_interaction = false
			_second_murder_sack_node = null
		if _shadow_figure_node != null and player.position.distance_to(_shadow_figure_node.position) <= SHADOW_FIGURE_VANISH_DISTANCE:
			_shadow_figure_node.queue_free()
			_shadow_figure_node = null
	if _message_timer > 0.0:
		_message_timer = max(_message_timer - delta, 0.0)
	var interactable := world_map.get_interactable_at(player.position)
	_close_kitchen_screen_if_out_of_range(interactable)
	_close_serving_screen_if_out_of_range(interactable)
	_close_storage_screen_if_out_of_range()
	_update_box_preview()
	_update_furniture_preview()
	_update_floor_decor_preview()
	_update_wall_decor_preview()
	_update_farm_tile_highlight()
	if _second_murder_sack_awaiting_interaction and _second_murder_sack_node != null \
			and player.position.distance_to(_second_murder_sack_position) <= SECOND_MURDER_SACK_INTERACT_RADIUS:
		if _message_timer <= 0.0:
			player.show_interaction_prompt("E 확인")
		return
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
	if _murder_scene_active:
		return
	var warp: Dictionary = world_map.get_warp_at(player.position)
	if not warp.is_empty():
		if _is_building_transition(warp):
			if _is_locked_shop_map(String(warp.get("target_map", ""))):
				player.hide_interaction_prompt()
			elif _message_timer <= 0.0:
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
		if not _sleep_prompt_shown:
			_sleep_prompt_shown = true
			## TimeManager.sleep_now()는 시간을 분 단위로 흘려보내지 않고 바로
			## 다음날로 점프해서, 22시(MurderManager.MURDER_HOUR)에 걸리는
			## 판정(살인/밤 이벤트)이 통째로 스킵되는 문제가 있었다(사용자
			## 리포트, 2026-08-17: "그럼 살인 스킵돼?"). 취침 자체를 못 하게
			## 막아서, 22시를 실제 시계 흐름으로 반드시 통과하게 한다 - 그날
			## 밤 정말 살인이 걸릴지는 여기서 확정 못 하지만(WeatherManager가
			## "비 오고 대기 중"만 보므로 미확정), 조용히 지나쳤을 때보다
			## 과하게 막는 쪽이 안전하다.
			if WeatherManager.is_murder_pending() and WeatherManager.is_raining() and TimeManager.current_hour < MurderManager.MURDER_HOUR:
				_show_temporary_message(SLEEPLESS_NIGHT_MESSAGE)
			elif sleep_confirm_popup != null:
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
	if interactable_name == "computer" or interactable_name == "collection" or interactable_name == "jukebox":
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
			# 망치를 들고 있으면 상자도 "열기" 대신 "회수" 대상이다(사용자 지시 -
			# 망치 들고 있는데 상자 열기만 뜨고 회수할 방법이 없어서 이상했다는
			# 리포트). 망치가 없을 때는 기존 그대로 상자 열기.
			if _is_furniture_hammer_equipped():
				if _message_timer <= 0.0:
					player.show_interaction_prompt("E 상자 회수")
			elif _message_timer <= 0.0:
				player.show_interaction_prompt("E 상자 열기")
			return
		if _is_furniture_hammer_equipped():
			var furniture_info := FurnitureManager.get_nearest_furniture(player.position, GameManager.current_map_id)
			if not furniture_info.is_empty():
				if _message_timer <= 0.0:
					player.show_interaction_prompt("E 가구 회수")
				return
			var wall_decor_info := WallDecorManager.get_nearest_wall_decor(player.position, GameManager.current_map_id)
			if not wall_decor_info.is_empty():
				if _message_timer <= 0.0:
					player.show_interaction_prompt("E 그림 회수")
				return
			var floor_decor_info := FloorDecorManager.get_nearest_floor_decor(player.position, GameManager.current_map_id)
			if not floor_decor_info.is_empty():
				if _message_timer <= 0.0:
					player.show_interaction_prompt("E 러그 회수")
				return
		if FishingManager.is_waiting_for_bite():
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 낚시 취소")
			return
		if FishingManager.can_start_fishing() and _is_facing_water() and not InventoryManager.is_full():
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
		"needs_till":
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
			else:
				# 확인 팝업 없이 바로 도살한다(모든 동물 공통, 사용자 지시).
				_show_temporary_message(LivestockManager.perform_slaughter(stall_index))
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
		or (jukebox_screen != null and jukebox_screen.modulate.a > 0.0) \
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
		# 노크 소리가 나는 동안 문 앞으로 뛰쳐나가 확인할 수 없게 이동도 같이
		# 잠근다(사용자 지시, 2026-08-24).
		player.set_movement_enabled(not any_open and not FishingManager.is_active() and not AudioManager.is_knock_playing())
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
		and StorageBoxManager.is_placement_allowed(GameManager.current_map_id)
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


## 통짜 흰 사각형 대신 2px 테두리만 있는 정사각형 하나를 코드로 만들어 쓴다
## (놓을 아이템 그림이 없으니, 사용자 지시로 채우기 대신 테두리로 변경,
## 2026-08-12). WorldMap.FLAT_Z_INDEX(-1)를 써서 바닥 흙/작물 스프라이트와
## 같은 층에 두고 캐릭터보다 아래에 그려지게 한다(원래 캐릭터 위에 그려지던
## 버그 리포트).
func _build_farm_tile_highlight() -> void:
	_farm_tile_highlight = Sprite2D.new()
	_farm_tile_highlight.visible = false
	_farm_tile_highlight.z_index = WorldMap.FLAT_Z_INDEX
	var size := WorldMap.TILE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var on_border := x < FARM_TILE_HIGHLIGHT_BORDER or x >= size - FARM_TILE_HIGHLIGHT_BORDER \
				or y < FARM_TILE_HIGHLIGHT_BORDER or y >= size - FARM_TILE_HIGHLIGHT_BORDER
			if on_border:
				image.set_pixel(x, y, Color(1, 1, 1, 0.85))
	_farm_tile_highlight.texture = ImageTexture.create_from_image(image)
	world_map.add_child(_farm_tile_highlight)


## 괭이/물뿌리개를 들고 밭(FarmingManager.FARM_MAP_ID)의 Farmable 칸 위에 서
## 있을 때만 표시한다 - 같은 맵이어도 Farmable이 아닌 칸(길/잔디 등)에서는
## 뜨면 안 된다는 리포트로 is_farmable_cell 체크 추가(2026-08-12). 할 수
## 있고 없고에 따라 색을 바꾸지 않는다(사용자 지시) - 항상 같은 테두리로
## 위치만 보여준다.
func _update_farm_tile_highlight() -> void:
	if _farm_tile_highlight == null:
		return
	var equipped := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	var show_highlight := not _is_any_modal_open() \
		and (equipped == "hoe" or equipped == "watering_can") \
		and GameManager.current_map_id == FarmingManager.FARM_MAP_ID \
		and world_map.is_farmable_cell(player.position)
	_farm_tile_highlight.visible = show_highlight
	if not show_highlight:
		return
	var cell := Vector2i(int(player.position.x) / WorldMap.TILE_SIZE, int(player.position.y) / WorldMap.TILE_SIZE)
	_farm_tile_highlight.position = Vector2(cell) * WorldMap.TILE_SIZE + Vector2.ONE * WorldMap.TILE_SIZE * 0.5


## _build_box_preview()와 동일 - world_map 자식으로 한 번만 만들고 계속
## 재사용한다.
func _build_furniture_preview() -> void:
	_furniture_preview = Sprite2D.new()
	_furniture_preview.visible = false
	_furniture_preview.z_index = 100
	world_map.add_child(_furniture_preview)


## _update_box_preview()와 같은 구조지만 아이템 id를 하드코딩하지 않는다
## (category=="furniture"이면 어떤 가구든 동작 - 사용자 지시: 가구가 늘어나도
## 코드 추가 불필요) - 대신 칸수(footprint)가 아이템마다 달라서 미리보기
## 크기/오프셋/중심 좌표를 매 프레임 다시 계산한다.
func _update_furniture_preview() -> void:
	if _furniture_preview == null:
		return
	var equipped_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	var show_preview := not _is_any_modal_open() \
		and InventoryManager.get_item_category(equipped_id) == "furniture" \
		and FurnitureManager.is_placement_allowed(GameManager.current_map_id)
	_furniture_preview.visible = show_preview
	if not show_preview:
		return
	var mouse_world := world_map.get_global_mouse_position()
	var anchor_cell := Vector2i(int(mouse_world.x) / WorldMap.TILE_SIZE, int(mouse_world.y) / WorldMap.TILE_SIZE)
	var footprint := FurnitureManager.get_footprint(equipped_id)
	var footprint_px := Vector2(footprint) * WorldMap.TILE_SIZE
	var center := Vector2(anchor_cell) * WorldMap.TILE_SIZE + footprint_px / 2.0
	var texture := FurnitureManager.get_preview_texture(equipped_id)
	_furniture_preview.texture = texture
	_furniture_preview.position = center
	var height: float = texture.get_height() if texture != null else footprint_px.y
	_furniture_preview.offset = Vector2(0, -(height - footprint_px.y) / 2.0)
	var valid := FurnitureManager.can_place_furniture(equipped_id, center) \
		and not FurnitureManager.has_furniture_overlap(GameManager.current_map_id, anchor_cell, footprint)
	_furniture_preview.modulate = Color(1, 1, 1, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)


## _build_furniture_preview()와 완전히 동일 - world_map 자식으로 한 번만
## 만들고 계속 재사용한다.
func _build_floor_decor_preview() -> void:
	_floor_decor_preview = Sprite2D.new()
	_floor_decor_preview.visible = false
	_floor_decor_preview.z_index = 100
	world_map.add_child(_floor_decor_preview)


## _update_furniture_preview()와 완전히 같은 구조(category=="floor_decor")지만
## 맵 허용 판정과 배치 가능 판정을 FloorDecorManager로 위임한다.
func _update_floor_decor_preview() -> void:
	if _floor_decor_preview == null:
		return
	var equipped_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	var show_preview := not _is_any_modal_open() \
		and InventoryManager.get_item_category(equipped_id) == "floor_decor" \
		and FurnitureManager.is_placement_allowed(GameManager.current_map_id)
	_floor_decor_preview.visible = show_preview
	if not show_preview:
		return
	var mouse_world := world_map.get_global_mouse_position()
	var anchor_cell := Vector2i(int(mouse_world.x) / WorldMap.TILE_SIZE, int(mouse_world.y) / WorldMap.TILE_SIZE)
	var footprint := FloorDecorManager.get_footprint(equipped_id)
	var footprint_px := Vector2(footprint) * WorldMap.TILE_SIZE
	var center := Vector2(anchor_cell) * WorldMap.TILE_SIZE + footprint_px / 2.0
	var texture := FloorDecorManager.get_preview_texture(equipped_id)
	_floor_decor_preview.texture = texture
	_floor_decor_preview.position = center
	var height: float = texture.get_height() if texture != null else footprint_px.y
	_floor_decor_preview.offset = Vector2(0, -(height - footprint_px.y) / 2.0)
	var valid := FloorDecorManager.can_place_floor_decor(equipped_id, center) \
		and not FloorDecorManager.has_floor_decor_overlap(GameManager.current_map_id, anchor_cell, footprint)
	_floor_decor_preview.modulate = Color(1, 1, 1, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)


## _build_furniture_preview()와 완전히 동일.
func _build_wall_decor_preview() -> void:
	_wall_decor_preview = Sprite2D.new()
	_wall_decor_preview.visible = false
	_wall_decor_preview.z_index = 100
	world_map.add_child(_wall_decor_preview)


## _update_furniture_preview()와 같은 구조(category=="wall_decor")지만 맵 허용은
## home_interior 하나뿐이고, 배치 가능 판정은 WallDecorManager.can_place_wall_decor()
## (실제 벽 타일인지)가 겹침 판정까지 포함해서 대신한다.
func _update_wall_decor_preview() -> void:
	if _wall_decor_preview == null:
		return
	var equipped_id := EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)
	var show_preview := not _is_any_modal_open() \
		and InventoryManager.get_item_category(equipped_id) == "wall_decor" \
		and WallDecorManager.ALLOWED_MAP_IDS.has(GameManager.current_map_id)
	_wall_decor_preview.visible = show_preview
	if not show_preview:
		return
	var mouse_world := world_map.get_global_mouse_position()
	var anchor_cell := Vector2i(int(mouse_world.x) / WorldMap.TILE_SIZE, int(mouse_world.y) / WorldMap.TILE_SIZE)
	var footprint := WallDecorManager.get_footprint(equipped_id)
	var footprint_px := Vector2(footprint) * WorldMap.TILE_SIZE
	var center := Vector2(anchor_cell) * WorldMap.TILE_SIZE + footprint_px / 2.0
	var texture := WallDecorManager.get_preview_texture(equipped_id)
	_wall_decor_preview.texture = texture
	_wall_decor_preview.position = center
	var height: float = texture.get_height() if texture != null else footprint_px.y
	_wall_decor_preview.offset = Vector2(0, -(height - footprint_px.y) / 2.0)
	var valid := WallDecorManager.can_place_wall_decor(equipped_id, center) \
		and not WallDecorManager.has_wall_decor_overlap(GameManager.current_map_id, anchor_cell, footprint)
	_wall_decor_preview.modulate = Color(1, 1, 1, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)


## Building doors (entering/leaving a "*_interior" map) require an explicit E
## press; open-air plaza-to-plaza edges warp instantly on touch instead.
func _is_building_transition(warp: Dictionary) -> bool:
	var target_map := String(warp.get("target_map", ""))
	return GameManager.current_map_id.ends_with("_interior") or target_map.ends_with("_interior")


## 낚시 캐스팅 판정 - 바로 앞 한 칸이 물(바다/연못)이면 그걸로 끝. 아니면
## 그 칸의 대각선 이웃 두 곳, 또는 정면으로 한 칸 더(총 두 칸)가 "바다"인
## 경우만 추가로 허용한다(사용자 리포트, 2026-08-24: plaza3 해안선이 계단식
## 대각선이라 대각선만 보면 놓치는 케이스가 있고, 정면 2칸만 보면 너무 멀게
## 느껴짐 - 대각선 + 정면 2칸을 같이 허용해 실제 해안 형태를 더 폭넓게
## 커버한다. 연못/강까지 다 열어주면 너무 멀리서도 낚시가 되니 "Water"
## (바다) 레이어일 때만 이 추가 판정을 적용한다).
func _is_facing_water() -> bool:
	if world_map.is_water_cell(player.get_facing_tile_position()):
		return true
	var forward := Vector2(player.facing_direction) * WorldMap.TILE_SIZE
	var perpendicular := Vector2(-player.facing_direction.y, player.facing_direction.x) * WorldMap.TILE_SIZE
	var sea_candidates: Array[Vector2] = [
		player.position + forward + perpendicular,
		player.position + forward - perpendicular,
		player.position + forward * 2,
	]
	for candidate in sea_candidates:
		if world_map.is_sea_cell(candidate):
			return true
	return false


## horror_events.md "NPC 사망 - 집 잠금": map_id가 어느 상점의 map_id와
## 일치하고, 그 상점이 shop.md 승계 규칙상 이미 "online"(운영 NPC 전원
## 사망)으로 전환됐으면 잠긴 것으로 본다 - ShopManager.get_shop_mode()를
## 그대로 재사용해서 1인/2인 상점 승계 규칙과 항상 일치하게 유지한다.
func _is_locked_shop_map(map_id: String) -> bool:
	var shop_id := ShopManager.get_shop_id_for_map(map_id)
	return not shop_id.is_empty() and ShopManager.get_shop_mode(shop_id) == "online"


## SHADOW_FIGURE_SPAWN_NAMES에 등록된 맵이고, 1차 살인 이후 스토커가 아직
## 살아있으면(스토커 사망 시 이 이벤트는 저절로 끝남) 낮은 확률로 스폰
## 지점에 그림자 인영을 세운다. 다른 NPC 캐릭터의 몸/머리 실루엣을 재사용하지
## 않는 전용 그림(SHADOW_FIGURE_TEXTURE_PATH)만 쓰므로 성별 등 정체가 드러날
## 여지가 없다. position이 캐릭터 발 위치 기준이 되도록(NPCSprite와 동일한
## 관례) offset을 그림 높이의 절반만큼 위로 준다.
func _maybe_spawn_shadow_figure(map_id: String) -> void:
	if not SHADOW_FIGURE_SPAWN_NAMES.has(map_id):
		return
	if not ResourceLoader.exists(SHADOW_FIGURE_TEXTURE_PATH):
		return
	if MurderManager.get_murder_count() <= 0 or not NPCManager.is_alive(NPCManager.get_stalker_id()):
		return
	if randf() >= SHADOW_FIGURE_APPEAR_CHANCE:
		return
	var spawn_position: Vector2 = world_map.get_spawn_position(String(SHADOW_FIGURE_SPAWN_NAMES[map_id]))
	if spawn_position == Vector2.INF:
		return
	var figure := Sprite2D.new()
	figure.texture = load(SHADOW_FIGURE_TEXTURE_PATH)
	figure.centered = true
	figure.offset = Vector2(0, -figure.texture.get_height() / 2.0)
	figure.position = spawn_position
	world_map.add_child(figure)
	_shadow_figure_node = figure


## skip_fade: 호출하는 쪽이 이미 화면을 검게 만들어 둔 상태에서 맵만 갈아
## 끼우고 싶을 때 쓴다(예: _play_collapse_transition - 취침 연출처럼 페이드/
## "N일차" 표시를 자기가 직접 감싸고, 그 사이에 맵 전환만 조용히 끼워 넣어야
## 해서 이 함수가 또 자기만의 페이드를 하면 화면이 두 번 깜빡인다).
func _load_map(map_id: String, spawn_name: String, skip_fade: bool = false) -> void:
	if world_map == null or player == null or _is_transitioning:
		return
	var map_path: String = WorldMap.get_map_path(map_id)
	if map_path.is_empty():
		push_error("Map is not registered: %s" % map_id)
		return
	_is_transitioning = true
	_open_doors.clear()
	## 레스토랑 액자 핏자국이 애니메이션 도중 맵을 나가도 다음 맵까지 안 남게
	## 강제로 정리한다(사용자 리포트, 2026-08-24).
	if _restaurant_frame_blood_tween != null and _restaurant_frame_blood_tween.is_valid():
		_restaurant_frame_blood_tween.kill()
	if _restaurant_frame_blood != null:
		_restaurant_frame_blood.visible = false
	## world_map은 맵이 바뀌어도 파괴되지 않고 재사용되는 노드라서(furniture/
	## storage_box 스프라이트들이 매번 직접 despawn/respawn하는 이유와 동일),
	## 그림자 인영도 맵을 나갈 때 직접 지워야 다음 맵까지 안 남는다.
	if _shadow_figure_node != null:
		_shadow_figure_node.queue_free()
		_shadow_figure_node = null
	# 실내/실외 경계를 넘는지는 GameManager.current_map_id가 아직 이전 맵인
	# 지금 시점에 미리 재둬야 한다 - 아래 GameManager.set_current_map(map_id)가
	# 지나가면 "이전 맵"을 더 이상 알 수 없다.
	var was_indoor := GameManager.current_map_id.ends_with("_interior")
	var was_home_interior := GameManager.current_map_id == "home_interior"
	if not skip_fade:
		await _fade_out()
	world_map.load_map(map_path)
	var is_indoor := map_id.ends_with("_interior")
	if _lighting_layer != null:
		_lighting_layer.rebuild_lights(world_map, is_indoor, map_id)
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
		if map_id == RESTAURANT_SIGN_MAP_ID:
			_maybe_play_restaurant_frame_blood_effect()
		LivestockManager.set_world_map(world_map, map_id)
		FarmingManager.set_world_map(world_map, map_id)
		StorageBoxManager.set_world_map(world_map, map_id)
		FurnitureManager.set_world_map(world_map, map_id)
		FloorDecorManager.set_world_map(world_map, map_id)
		WallDecorManager.set_world_map(world_map, map_id)
		if was_indoor != is_indoor:
			AudioManager.play_sfx(AudioManager.SFX_DOOR)
		_maybe_spawn_shadow_figure(map_id)
	if not skip_fade:
		await _fade_in()
	if _knock_check_pending and was_home_interior and map_id == "Home":
		_knock_check_pending = false
		if dialogue_screen != null:
			dialogue_screen.open_special("", KNOCK_CHECK_RESULT_MONOLOGUE.duplicate())
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
	if _is_any_modal_open() or _murder_scene_active:
		return
	if _second_murder_sack_awaiting_interaction and _second_murder_sack_node != null \
			and player.position.distance_to(_second_murder_sack_position) <= SECOND_MURDER_SACK_INTERACT_RADIUS:
		_continue_second_murder_discovery()
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
		if _is_locked_shop_map(String(warp["target_map"])):
			_show_temporary_message(SHOP_LOCKED_MESSAGE)
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
		if _is_furniture_hammer_equipped():
			var box_message := StorageBoxManager.remove_box(GameManager.current_map_id, box_info["cell"])
			if not box_message.is_empty():
				_show_temporary_message(box_message)
		else:
			storage_box_interacted.emit(box_info["cell"])
		return
	if _is_furniture_hammer_equipped():
		var furniture_info := FurnitureManager.get_nearest_furniture(player.position, GameManager.current_map_id)
		if not furniture_info.is_empty():
			# 보관 상자와 달리 UI를 열 필요가 없는 즉시 액션이라 별도 신호 없이
			# 바로 처리한다(내부 슬롯이 없어 항상 즉시 회수 가능 - 확정 범위).
			var message := FurnitureManager.remove_furniture(GameManager.current_map_id, furniture_info["anchor_cell"])
			if not message.is_empty():
				_show_temporary_message(message)
			return
		var wall_decor_info := WallDecorManager.get_nearest_wall_decor(player.position, GameManager.current_map_id)
		if not wall_decor_info.is_empty():
			var wall_decor_message := WallDecorManager.remove_wall_decor(GameManager.current_map_id, wall_decor_info["anchor_cell"])
			if not wall_decor_message.is_empty():
				_show_temporary_message(wall_decor_message)
			return
		var floor_decor_info := FloorDecorManager.get_nearest_floor_decor(player.position, GameManager.current_map_id)
		if not floor_decor_info.is_empty():
			var floor_decor_message := FloorDecorManager.remove_floor_decor(GameManager.current_map_id, floor_decor_info["anchor_cell"])
			if not floor_decor_message.is_empty():
				_show_temporary_message(floor_decor_message)
			return
	if FishingManager.is_waiting_for_bite():
		# cancel_fishing()이 fishing_ended를 쏴서 _on_fishing_ended가 포즈를
		# 정리한다(2026-08-12) - 여기서 따로 stop() 안 불러도 됨.
		FishingManager.cancel_fishing()
		return
	if FishingManager.can_start_fishing() and _is_facing_water() and not InventoryManager.is_full():
		if FishingManager.start_fishing():
			AudioManager.play_sfx(AudioManager.SFX_BUBBLE)
			player.tool_overlay.start("fishing_rod")
		return
	# 농사는 낚시와 달리 바라보는 칸이 아니라 지금 서 있는 칸을 대상으로
	# 한다(사용자 지시, _process()의 프롬프트 판정과 동일 기준이어야 함).
	var farm_position := player.position
	match FarmingManager.get_available_action(farm_position):
		"till":
			# 마른/젖은 흙 그림이 바로 보이니 문구 없이 조용히 처리(사용자
			# 지시, "plant"/"water"와 같은 이유). 포즈가 먼저 재생되고 그게
			# 끝나는 시점에 흙이 바뀌도록 순서를 뒤집었다(사용자 지시,
			# 2026-08-12 - 즉각 반응이라 갬성이 없다는 피드백. 스타듀 밸리처럼
			# 휘두르는 동작에 살짝 시간이 걸리는 느낌).
			if _farm_action_active:
				return
			_farm_action_active = true
			player.tool_overlay.start("hoe", TOOL_USE_HOLD_SECONDS)
			await get_tree().create_timer(TOOL_USE_HOLD_SECONDS).timeout
			FarmingManager.perform_till(farm_position)
			_farm_action_active = false
		"water":
			# 젖은 흙 그림이 바로 보이니 문구 없이 조용히 처리(사용자 지시,
			# "plant"와 같은 이유). "till"과 같은 이유로 포즈 재생 후 흙이
			# 바뀌도록 순서를 뒤집었다(2026-08-12).
			if _farm_action_active:
				return
			_farm_action_active = true
			player.tool_overlay.start("watering_can", TOOL_USE_HOLD_SECONDS)
			await get_tree().create_timer(TOOL_USE_HOLD_SECONDS).timeout
			FarmingManager.perform_water(farm_position)
			_farm_action_active = false
		"needs_till":
			# 물뿌리개를 든 채 아직 안 간 밭에 물을 주려 한 경우(사용자 지시,
			# 2026-08-12) - 포즈 없이 안내 문구만 띄운다.
			_show_temporary_message("먼저 밭을 갈아야 한다.")
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
	if interactable_name == "jukebox":
		jukebox_interacted.emit()
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
