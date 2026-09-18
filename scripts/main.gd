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
## 공범 엔딩(사용자 지시, 2026-08-24) - 노크 이후 문 앞에서 E를 눌러 어셔를
## 맞이하는 순간.
signal accomplice_door_answered
signal collection_interacted
signal jukebox_interacted
## "closet" Interactable(집) - 인게임 옷장 재커스터마이즈 화면(피드백 #11).
signal wardrobe_interacted
## 도감 완성 보상(제단 부활, 사용자 지시 2026-08-25) - soul_altar Interactable.
signal soul_altar_interacted
signal npc_talk_interacted(npc_id: String)
## StorageBoxManager - 근처에 이미 상자가 있을 때 E를 누르면(설치 아님, 열기).
signal storage_box_interacted(cell: Vector2i)

const SERVING_AREA_PREFIX := "serving_area"
const KITCHEN_STATION_PREFIX := "cooking_area"
const RESTAURANT_NOT_READY_MESSAGE := "먼저 레스토랑을 열자."
const ALREADY_SERVED_MESSAGE := "이미 손님이 요리를 먹고 있다."
const RESTAURANT_HOURS_MESSAGE := "오전 10시부터 오후 4시까지만 영업할 수 있다."
const RESTAURANT_CANNOT_LEAVE_MESSAGE := "영업 중에는 레스토랑을 벗어날 수 없다."
## RestaurantManager.can_player_leave()가 false인 두 번째 경우(문은 닫았지만
## 아직 식사 중인 손님이 남음) 전용 - 위 메시지를 그대로 쓰면 "영업 중"이라고
## 나와서 "닫았는데 뭔 소리냐"는 혼란을 준다(사용자 리포트, 2026-09-01).
const RESTAURANT_CUSTOMERS_REMAINING_MESSAGE := "아직 손님이 남아있다."
## 영업 종료 시간(CLOSE_HOUR)이 지나도 레스토랑은 자동으로 안 닫히고 플레이어가
## 직접 팻말에서 닫아야 하는데(RestaurantManager.is_open이 하루가 바뀔 때만
## 초기화됨), 그 사실을 알려주는 문구가 하나도 없어서 마감 시간이 지난 줄
## 모르고 계속 안에 있을 수 있다는 지적(사용자 지시, 2026-08-25).
const RESTAURANT_CLOSING_TIME_MESSAGE := "영업 종료 시간이다."
## TimeManager.restaurant_closed(영업 종료 시간이 되는 순간 자동으로만 뜨는
## 신호 - RestaurantManager.restaurant_closed와 달리 플레이어가 직접 팻말로
## 닫았을 땐 안 뜬다)를 받아서 보여주는 문구(사용자 지시, 2026-08-27 -
## "레스토랑 안에 있을 때 4시가 넘어서 자동으로 레스토랑 문이 닫히는 경우...
## 아직 소리소문 없이 닫히는 중").
const RESTAURANT_AUTO_CLOSED_MESSAGE := "4시가 지나 영업이 종료되었다."
## RestaurantManager.all_visitors_served 전용(사용자 피드백 42번, 2026-09-01) -
## 오늘 배정된 손님을 전부 받으면 영업시간이 남아있어도 더 이상 새 손님이
## 안 온다는 걸 알려준다.
const RESTAURANT_ALL_VISITORS_SERVED_MESSAGE := "오늘 손님은 전부 받았다."
## horror_events.md "NPC 집 잠금" - "NPC맵=NPC가게"(사용자 확정 2026-08-16)라
## 상점 맵으로 해석해서 막는다.
const SHOP_LOCKED_MESSAGE := "문이 굳게 잠겨 있다."
## 옷장(closet)은 처음엔 낡아서 고장난 상태 - 우디 호감도 50 이벤트
## (woody.json affection_events, "낡은 옷장을 발견하고 고쳐주겠다고 한다")를
## 본 뒤에야 실제로 열린다. has_shown_event()가 곧 "고쳐짐" 상태라 별도
## 플래그가 필요 없다(사용자 지시, 2026-08-30).
const WARDROBE_BROKEN_MESSAGE := "낡아서 문이 열리지 않는다."
const WARDROBE_UNLOCK_NPC_ID := "woody"
const WARDROBE_UNLOCK_THRESHOLD := 50
## 공범 엔딩(사용자 지시, 2026-08-24) - 스토커 메일을 확인하기 전엔 집 밖으로
## 못 나간다.
const ACCOMPLICE_CANNOT_LEAVE_MESSAGE := "왠지 지금은 밖에 나가면 안 될 것 같다."
## 살인 대기 중인 밤(비 오는 중 + 22시 전)에 취침을 막을 때 쓰는 문구 - 첫
## 살인 전엔 공포 요소를 인지시키면 안 되므로(CLAUDE.md) 노골적인 암시 없이
## 평범한 "잠이 안 온다" 톤으로 잡았다. 문구는 임시 - 기획 확정 시 교체 가능.
const SLEEPLESS_NIGHT_MESSAGE := "잠이 오지 않아."
const MESSAGE_DURATION := 2.0
## 레스토랑 개점/마감/만석 안내는 놓치면 헷갈리는 정보라 기본보다 길게
## 띄운다(플레이테스트 피드백 #9, 2026-09-05 - "너무 짧게 뜬다").
const RESTAURANT_STATUS_MESSAGE_DURATION := 4.0
const FURNITURE_DESCRIPTIONS_PATH := "res://data/furniture/descriptions.json"
## 16x16 그림 - 준비되면 이 경로에 파일만 넣으면 코드 수정 없이 자동으로
## 아이콘으로 바뀐다(player.gd의 show_interaction_icon() 참고).
const FURNITURE_DESC_ICON_PATH := "res://assets/ui/icon_talk_bubble.png"
## 밭갈기/물주기처럼 한 프레임에 즉시 끝나는 액션은 자체 지속시간이 없어서,
## player.tool_overlay 사용 포즈가 최소 이만큼은 눈에 보이도록 붙잡아둔다
## (낚시는 자체 대기시간이 있어 이 상수를 안 쓴다. 망치 회수는 사용자 지시로
## 포즈 대상에서 제외, 2026-08-12).
const TOOL_USE_HOLD_SECONDS := 0.35
const FARM_TILE_HIGHLIGHT_BORDER := 2

const FADE_DURATION := 0.2
const UI_DIM_ALPHA := 0.5
const DAY_LABEL_HOLD_DURATION := 1.2

## items.json의 "americano" 설명("잠시 플레이어의 이속을 증가시킨다")과 같은
## 효과를 가리킨다. data/items/items.json의 "energy_tonic"은 설명에 "(디버프
## 해제)"로 명시되어 있음. 10%는 체감이 안 된다는 지적(사용자 지시,
## 2026-08-26)으로 30%로 상향 - data/npc/mocha.json의 buff_item 설명 텍스트도
## 같이 맞춰둠.
const AMERICANO_SPEED_BONUS := 0.30
## 1게임분=현실 1초라서 3게임분은 체감 3초로 너무 짧았다(사용자 지시,
## 2026-08-26 - "현실 3분으로 해줘"). COLLAPSE_DEBUFF_MINUTES와 같은 환산으로
## 180게임분 = 현실 3분.
const AMERICANO_DURATION_MINUTES := 180

## time.md: "취침 시간이 될 때까지 야외에 있을 경우, 길바닥 기절 후 다음 날
## 디버프를 얻는다." 디버프 수치(-30%, 게임 시간 3시간)와 기상 위치는 이전
## 세션에서 이미 합의된 값(plan/day4.md) - 병원 기상 스폰(hospital_lying_player)은
## 사용자가 hospital_interior.tmx에 직접 배치했다.
const COLLAPSE_DEBUFF_PERCENT := -0.30
const COLLAPSE_DEBUFF_MINUTES := 180
const HOSPITAL_MAP_ID := "hospital_interior"
const HOSPITAL_WAKE_SPAWN := "hospital_lying_player"

const HEART_EVENT_AFFECTION_THRESHOLD := 30
## 사용자 지시(2026-08-26) - 전역 FADE_DURATION(0.2, 모든 맵 전환 공용)보다
## 길게 줘서 "이벤트 느낌"을 낸다. heart_event_30 전용 페이드에만 사용.
## 0.6 → 1.2로 재조정(사용자 지시, 2026-08-26 - "여전히 너무 빨리 사라져").
const HEART_EVENT_FADE_DURATION := 1.2
## 도착 직후 정면을 본 채로 잠깐 멈춰 "여기 도착했다"는 인지가 되게 한다
## (사용자 지시, 2026-08-26 - "옆이나 뒤 보고 있으니까 이상해"). 1.0 → 1.5로
## 늘림(사용자 지시, 2026-08-26 - "대사 하기 전에 pause 주는 시간도 좀만 더").
const HEART_EVENT_ARRIVE_PAUSE_SECONDS := 1.5
## heart_event_30 json의 "player_facing"으로 기본 동작(NPC 쪽을 바라봄)을
## 덮어쓸 때 쓰는 방향 이름 (예: 플로라는 나란히 서서 보는 연출이라 뒷모습이
## 맞다는 사용자 지시 - "player_facing": "up").
const HEART_EVENT_FACING_DIRECTIONS := {
	"up": Vector2i(0, -1), "down": Vector2i(0, 1),
	"left": Vector2i(-1, 0), "right": Vector2i(1, 0),
}

## 호감도 100(추억의 물건) 컷신(사용자 지시, 2026-08-25) - 스폰 좌표 없이,
## 플레이어가 NPC 근처에 있으면 NPC가 실시간으로 다가와서 자동 시작된다.
## 3 → 5로 늘림(사용자 지시, 2026-08-26 - "다가온다는 느낌이 잘 안드는 거
## 같은데") - 3이면 접근 정지 거리(1타일)를 빼면 최대 2타일밖에 안 걸어서
## 밋밋했다. 320x180 해상도(가로 20타일) 기준으로 화면 밖으로 나가지 않는
## 선에서 늘린 값.
const MEMENTO_EVENT_PROXIMITY_TILES := 5
## NPC가 플레이어 바로 위에 겹치지 않고 한 칸 앞에서 멈추게 하는 접근 거리.
const MEMENTO_EVENT_APPROACH_DISTANCE := 16.0
## 평소 암전(순검정)과 구분되는 따뜻한 톤 - "특별한 순간"이라는 걸 색으로도
## 표시한다(사용자 지시). 컷신 끝나면 다시 순검정으로 되돌린다(_set_fade_tint 참고).
const MEMENTO_EVENT_FADE_TINT := Color(0.55, 0.35, 0.15)
## 사용자 지시(2026-08-26) - "호감도 100때도 페이드 시간 너무 짧다". heart_event_30과
## 같은 값으로 통일(HEART_EVENT_FADE_DURATION). 0.6 → 1.2로 재조정(사용자 지시,
## 2026-08-26 - "여전히 너무 빨리 사라져").
const MEMENTO_EVENT_FADE_DURATION := 1.2
## 물건을 건네는 대사 직후, 실제 지급 전에 한 박자 멈춰서 무게감을 준다.
const MEMENTO_EVENT_GRANT_PAUSE_SECONDS := 0.6
## 마린의 호감도 100 컷신 전용 - 다가오는 동안 축구공이 좌우로 튕기는 연출
## (사용자 지시, 2026-08-26). memento_marin 아이템 아이콘(축구공)을 그대로
## 재사용해서 별도 에셋 없이 만든다.
const MARIN_NPC_ID := "marin"
const MARIN_BALL_ITEM_ID := "memento_marin"
const MARIN_BALL_BOUNCE_SECONDS := 0.3
const MARIN_BALL_Z_INDEX := 50
## 마린 30 이벤트 도착 직후 공을 주고받는 연출의 재생 시간(0.3초 다리
## 6개 = 왕복 3번, 사용자 지시). 이동 시간과는 완전히 분리된 고정 길이 -
## 원래 도착 전 "걸어오는 내내" 재생되던 걸 도착 후 이 시간만큼만 재생하게
## 바꿨다(사용자 지시, 2026-08-26).
const MARIN_BALL_MIN_VISIBLE_SECONDS := 1.8
## 지급 직후 하트 이모지를 평소(1초)보다 오래 띄운다(사용자 지시 - "이모지
## 오래 보여주기").
const MEMENTO_EVENT_EMOTE_HOLD_SECONDS := 2.5

## 도감 완성 보상(제단 부활, 사용자 지시 2026-08-25) - 제단 상호작용 화면
## 깜빡임 전용 톤. 따뜻한 추억의 물건 톤(MEMENTO_EVENT_FADE_TINT)과 구분되게
## 서늘한 청백색으로.
const SOUL_ALTAR_FADE_TINT := Color(0.55, 0.6, 0.7)
## 제단 상호작용 시 화면 깜빡임 횟수/밝기/한 번 깜빡이는 시간.
const ALTAR_FLICKER_COUNT := 3
const ALTAR_FLICKER_PEAK_ALPHA := 0.75
const ALTAR_FLICKER_FLASH_SECONDS := 0.1

## 영혼의 결정 지급 컷신(사용자 지시, 2026-08-25 재설계) - 신사 밖(plaza5)에서
## 영혼이 하늘로 날아올랐다가, 잠든/기절한 플레이어가 있는 맵으로 돌아와
## 가슴팍에 스며든다. 사용자가 assets/img/sage_altar.png로 직접 그려준
## "영혼" 그림을 그대로 쓴다(제단 자체의 그림이 아니라 날아다니는 영혼
## 그림이라고 확인받음, 2026-08-25).
const SOUL_CRYSTAL_SPRITE_TEXTURE := preload("res://assets/img/sage_altar.png")
## 집/캐릭터 뒤에 가려서 안 보인다는 지적(사용자 지시, 2026-08-25) - world_map은
## Y-sort로 그리는데, 이 영혼 스프라이트는 항상 다른 모든 것 위에 떠 보여야
## 하므로 Y-sort보다 z_index가 우선하도록 명시적으로 높은 값을 준다
## (z_as_relative=false로 부모 z_index 영향도 안 받게 고정).
const SOUL_CRYSTAL_SPRITE_Z_INDEX := 100
## shrine_interior.tmx의 Warp("shrine_out")가 나가는 plaza5의 스폰 지점을
## 그대로 재사용 - 신사 바로 앞에서 날아오르는 그림이 자연스러워서 새 스폰을
## 따로 안 만듦.
const SOUL_CRYSTAL_SHRINE_EXIT_SPAWN := "shrine_exit"
const SOUL_CRYSTAL_FLYOUT_OFFSET := Vector2(0, -80)
const SOUL_CRYSTAL_FLYOUT_SECONDS := 2.2
const SOUL_CRYSTAL_MERGE_START_OFFSET := Vector2(0, -24)
const SOUL_CRYSTAL_MERGE_END_OFFSET := Vector2(0, -10)
const SOUL_CRYSTAL_MERGE_SECONDS := 1.6
## 컷신이 너무 빨리 지나간다는 지적(사용자 지시, 2026-08-25) - 장면이 바뀐
## 직후/애니메이션이 끝난 직후 화면을 잠깐 그대로 유지하는 여백 시간.
const SOUL_CRYSTAL_BEAT_SECONDS := 0.5
## 취침 중 지급 컷신이 끝난 뒤 되돌아올 자리 - 취침은 항상 home_interior의
## 침대 타일에서만 시작되므로(sleep_confirm_popup 참고) 고정값으로 충분하다.
## 침대 밖 임의 위치로 복원하면 "누워있는 플레이어"처럼 안 보인다는 지적
## (사용자 지시, 2026-08-25)으로, 기획자가 home_interior.tmx의 Spawn
## 레이어에 직접 찍어준 전용 스폰을 쓴다 - 정확히 침대 안, 정면(아래)을
## 보는 자리로 찍혀 있어야 한다.
const SOUL_CRYSTAL_HOME_RETURN_MAP_ID := "home_interior"
const SOUL_CRYSTAL_HOME_RETURN_SPAWN := "soul_crystal_sleep_spot"

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
## 이름은 팻말 전용처럼 보이지만 실제 값은 그냥 레스토랑 맵 id라, 대화/호감도
## 이벤트를 레스토랑 안에서 막는 조건(_find_matching_heart_event(),
## _maybe_trigger_memento_event(), 사용자 지시 2026-08-26)에도 그대로 재사용한다.
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
@onready var pet_name_popup: Control = get_node_or_null("UI/PetNamePopup") as Control
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
@onready var wardrobe_screen: Control = get_node_or_null("UI/WardrobeScreen") as Control
@onready var minimap_screen: Control = get_node_or_null("UI/MinimapScreen") as Control
@onready var memento_toast: Control = get_node_or_null("UI/MementoToast") as Control
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
## 튜토리얼 컷신(_maybe_play_tutorial_intro())이 특정 상호작용 지점을 노란색
## 점멸로 가리키는 데 쓴다 - _farm_tile_highlight와 달리 한 번에 여러 지점을
## 동시에 가리켜야 할 때가 있어서(냄비+프라이팬 둘 다 완료됐을 때) 배열로 둔다.
var _tutorial_highlights: Array[Sprite2D] = []
var _tutorial_highlight_tweens: Array[Tween] = []
## _on_restaurant_confirmed()이 RestaurantManager.open_restaurant()에
## bypass_hours로 그대로 넘겨준다 - 신규 슬롯 튜토리얼이 "restaurant_open"
## 하이라이트를 켜둔 구간에서만 true(사용자 지시, 2026-09-01 - "튜토일때는
## 영업시간 전이어도 열수있게 해주고").
var _tutorial_awaiting_restaurant_open := false
## 튜토리얼이 강제로 열어둔 레스토랑을 플레이어가 중간에 직접 닫아버리지
## 못하게 막는다(사용자 지시, 2026-09-01 - "열었을땐 못닫게 해줘") - 개점
## 직후부터 튜토리얼이 끝나며 스스로 close_restaurant()를 부를 때까지 켜둔다.
var _tutorial_locks_restaurant_close := false
## 레스토랑에 들어온 뒤부터(_tutorial_intro_locks_movement가 풀린 뒤) 요리/서빙
## 튜토리얼이 끝날 때까지 건물 워프로 나가는 것 자체를 막는다(사용자 지시,
## 2026-09-03 - "튜토때 레스토랑 밖으로 못나가게 막아야할거같아") - 입구
## 스폰이 나가는 워프("restaurant_out")와 좌표가 겹쳐 있어서, 들어가자마자
## 그 자리에서 E를 누르면 곧바로 튕겨 나가는 문제가 있었다(스폰 좌표는
## restaurant_interior_new.tmx에서 따로 옮겨 고쳤지만, 재발 방지로 이중 잠금).
var _tutorial_locks_restaurant_exit := false
## 신규 슬롯 튜토리얼이 레스토랑 안으로 들어가기 전(폴리 인사~문 앞 이동
## 구간)에는 플레이어가 직접 걸어다닐 수 없게 막는다(사용자 지시, 2026-09-01 -
## "튜토 레스토랑 들어가기 전까지는 플레이어가 조작 못하게 해줘 이동
## 누르게 되네") - player.set_movement_enabled()를 매 프레임 재계산하는
## 코드(아래 _murder_scene_active 등과 같은 자리)에 같이 얹는다.
var _tutorial_intro_locks_movement := false

var _is_transitioning := false
## _on_murder_occurred() 진행 중에는 참 - 플레이어가 player.walk_to()로
## 스크립트 이동하는 동안 워프 지점을 밟아도 _process()의 평소 "밟으면 자동
## 다음 맵" 로직이 끼어들지 않게 막는다(끼어들면 같은 전환을 두 시스템이
## 동시에 처리하려다 페이드가 서로 꼬여서 멈춰버림 - 실제로 이 버그로 게임이
## 응답 없음 상태가 됐었음, 2026-08-16). 맵 전환은 이 씬이 진행되는 동안
## _on_murder_occurred() 자신이 명시적으로만 처리한다.
var _murder_scene_active := false
## 공범 엔딩(사용자 지시, 2026-08-24): 어셔가 이사오기 전, 집에 갇힌 채 스토커
## 메일을 확인해야 하는 구간에서만 참 - _murder_scene_active와 달리 이동/E
## 상호작용(컴퓨터로 메일 확인 등)은 그대로 허용하고 "집 밖으로 나가는 워프"만
## 막는다.
var _accomplice_awaiting_mail_read := false
## 노크 소리가 끝난 뒤, 문 앞에서 E를 누르길 기다리는 단계(사용자 지시,
## 2026-08-24). 이때 문 워프는 평소처럼 밖으로 안 나가고 accomplice_door_answered
## 신호만 쏜다.
var _accomplice_awaiting_door_open := false
## heart_event_30(호감도 30 최초 이벤트, 2026-08-24 사용자 지시 - "스듀식"
## 컷신) 재생 중에만 참 - E 상호작용을 막는다(이동은 player.walk_to()가
## _scripted_move_direction으로 실제 입력을 덮어써서 별도로 안 막아도 된다).
var _heart_event_active := false
## _prepare_heart_event()가 암전 중에 미리 찾아 둔 비-이동형 heart_event_30 -
## {npc_id, event, player_spawn_position, decoy}. 비어있으면 준비된 게 없다는
## 뜻(_run_pending_heart_event() 참고).
var _pending_heart_event: Dictionary = {}
## 호감도 100(추억의 물건) 컷신 재생 중에만 참(사용자 지시, 2026-08-25) -
## _should_pause_time()/_update_ui_blocking()의 이동 잠금에 직접 연결돼서
## 시간 정지/이동 잠금은 따라오지만, 화면 디밍(_ui_dim)은 안 켜진다(사용자
## 지시 - "디밍 거슬릴 것 같다", _is_any_modal_open()과는 별도로 취급).
var _memento_event_active := false
var _marin_ball_tween: Tween = null
## 제단(soul_altar) 부활 컷신 재생 중에만 참(사용자 지시, 2026-08-25) -
## _memento_event_active와 같은 방식으로 시간 정지/이동 잠금에 연결되고,
## 화면 디밍은 안 켜짐(이 프로젝트의 기존 대형 서사 컷신들도 디밍 없이
## 페이드/대사만으로 처리하는 관례를 따름).
var _revival_event_active := false
## RevivalManager.soul_crystal_granted가 다른 컷신 도중(엔딩/도감 화면 등)
## 도착하면 즉시 재생하지 않고 이 플래그만 세워둔다 - _process()가 매
## 프레임 안전한 타이밍을 엿보다가 소비한다(사용자 지시, 2026-08-25 - "지급
## 순간에도 특별 연출").
var _pending_soul_crystal_grant_cutscene := false
## 괭이/물뿌리개 포즈 재생 중(TOOL_USE_HOLD_SECONDS)에 E를 한 번 더 누르면
## _on_interact_pressed()가 재진입해서 perform_till()이 아직 커밋 안 된 같은
## 칸을 "till"로 다시 판정 - 첫 호출이 끝나기 전에 두 번째 코루틴이 같은
## 애니메이션/타이머를 새로 시작해버리는 레이스였다(사용자 리포트: "괭이질
## 한 번 더 하면 안 갈아둔 상태로 복귀", 2026-08-16). 진행 중엔 새 농사
## 액션을 아예 안 받는다.
var _farm_action_active := false
var _message_timer := 0.0
## 방금 메시지 대상이었던 Interactable 이름 - 다른 오브젝트로 옮겨가면 그
## 오브젝트 얘기가 아니게 되므로 _message_timer를 강제로 끝내서, 새 프롬프트가
## 최대 MESSAGE_DURATION(2초)까지 늦게 뜨던 문제를 막는다(사용자 리포트,
## 2026-08-30 - "조리대에서 다른 조리대랑 상호작용 하면 다음 조리기구 범위에
## 들어가도 바로 안 뜨는 거 같다").
var _last_prompt_interactable_name := ""
var _sleep_prompt_shown := false
var _is_sleep_transition_playing := false
## "지금 대화 가능 범위 안에 있는 NPC" - 이 값이 바뀌는 순간(멀어졌다 다시
## 가까워질 때)만 "마주쳤다"는 이모지를 한 번 띄운다(_handle_npc_encounter
## 참고). 범위를 벗어나면 빈 문자열로 리셋되어 다음 접근에서 다시 트리거된다.
var _last_nearby_npc_id := ""
## npc_id -> 오늘 이미 마주침 이모지를 띄웠는지. 하루가 바뀌면
## _on_day_changed_clear_greetings()가 비운다(사용자 지시, 2026-08-25 - "너무
## 많이 떠서 하루에 처음 마주칠 때만"). 일시적 상태라 세이브 대상 아님
## (_open_doors와 같은 이유).
var _greeted_today: Dictionary = {}
## 영업 종료 시간(CLOSE_HOUR) 지난 뒤 레스토랑 안에 있으면 안내 문구를 하루에
## 한 번만 띄운다(사용자 지시, 2026-08-25) - 매 프레임 계속 뜨면 거슬리므로.
var _closing_time_reminder_shown_today := false
## 외양간 문(door1_open~4) 이름 -> 지금 열려있는지. _load_map()마다 비운다
## (WorldMap.load_map()이 맵을 새로 그릴 때마다 문도 항상 닫힌 상태로
## 리셋되므로, 여기 기록도 그대로 맞춰야 한다 - "일시적으로"만 열려있는
## 상호작용이라 세이브 대상도 아니다).
var _open_doors: Dictionary = {}
## furniture_desc Interactable의 "id" 프로퍼티 → 설명 문구. _ready()에서 한 번만
## 채운다(FURNITURE_DESCRIPTIONS_PATH 참고).
var _furniture_descriptions: Dictionary = {}
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
	_load_furniture_descriptions()
	_load_tutorial_dialogue()
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
		dialogue_screen.buff_requested.connect(_on_dialogue_buff_requested)
		dialogue_screen.closed.connect(_on_dialogue_screen_closed_for_pet_naming)
	if pet_name_popup != null:
		pet_name_popup.name_confirmed.connect(_on_pet_name_confirmed)
	if sleep_confirm_popup != null:
		sleep_confirm_popup.slept.connect(_play_sleep_transition)
	if restaurant_confirm_popup != null:
		restaurant_confirm_popup.confirmed.connect(_on_restaurant_confirmed)
	if livestock_confirm_popup != null:
		livestock_confirm_popup.confirmed.connect(_on_livestock_confirmed)
	if status_screen != null and book_screen != null:
		status_screen.book_open_requested.connect(book_screen.open_book)
	if status_screen != null:
		## TAB은 status_screen이 직접 듣는 전역 단축키라, 컴퓨터(메일)처럼 다른
		## 배타적 화면이 이미 열려있어도 그 위에 겹쳐 열려버리는 문제가
		## 있었다(사용자 리포트, 2026-08-27) - 열려는 순간(_is_open이 아직
		## false일 때) 다른 모달이 하나라도 열려있으면 막는다.
		status_screen.set_open_blocked_check(func() -> bool: return _is_any_modal_open())
	if storage_screen != null:
		storage_box_interacted.connect(storage_screen.open_box)
	if jukebox_screen != null:
		jukebox_interacted.connect(jukebox_screen.open)
	if wardrobe_screen != null:
		wardrobe_interacted.connect(wardrobe_screen.open)
	if minimap_screen != null:
		minimap_screen.setup(player)
		## status_screen과 동일 이유(위 417번 줄 참고) - M도 이 화면이 직접 듣는
		## 전역 단축키라 다른 모달 위에 겹쳐 열리지 않게 막는다.
		minimap_screen.set_open_blocked_check(func() -> bool: return _is_any_modal_open())
	HuntingManager.player = player
	RestaurantManager.restaurant_opened.connect(_update_restaurant_sign)
	RestaurantManager.restaurant_closed.connect(_update_restaurant_sign)
	RestaurantManager.all_visitors_served.connect(_on_all_visitors_served)
	TimeManager.restaurant_closed.connect(_on_restaurant_auto_closed)
	InventoryManager.item_used.connect(_on_item_used)
	CookingManager.recipe_learned.connect(_on_recipe_learned)
	NPCManager.memento_received.connect(_on_memento_received)
	NPCManager.affection_event_triggered.connect(_on_affection_event_triggered_for_pet_naming)
	TimeManager.player_collapsed.connect(_play_collapse_transition)
	TimeManager.hour_changed.connect(_on_hour_changed)
	FurnitureManager.furniture_changed.connect(_on_decor_changed)
	FloorDecorManager.floor_decor_changed.connect(_on_decor_changed)
	WallDecorManager.wall_decor_changed.connect(_on_decor_changed)
	ShopManager.furniture_hammer_granted.connect(_on_furniture_hammer_granted)
	FishingManager.fishing_ended.connect(_on_fishing_ended)
	## 조준 바가 뜨는 동안 사냥총을 든 포즈를 보여준다(낚싯대와 동일한 패턴) -
	## HuntingManager.player는 Node2D로만 타입을 잡아서(오토로드 컴파일 순서
	## 문제 회피용 규칙) 여기 main.gd의 정식 타입 player로 직접 처리한다.
	HuntingManager.hunt_started.connect(func() -> void: player.tool_overlay.start("hunting_rifle"))
	HuntingManager.hunt_ended.connect(func(_result: Dictionary) -> void: player.tool_overlay.stop())
	AudioManager.knock_sequence_finished.connect(_on_knock_sequence_finished)
	TimeManager.day_changed.connect(_on_day_changed_clear_knock_check)
	TimeManager.day_changed.connect(_on_day_changed_clear_greetings)
	TimeManager.day_changed.connect(_on_day_changed_clear_closing_time_reminder)
	MurderManager.murder_occurred.connect(_on_murder_occurred)
	MurderManager.accomplice_ending_triggered.connect(_on_accomplice_ending_triggered)
	MurderManager.truth_ending_triggered.connect(_on_truth_ending_triggered)
	MurderManager.arrest_ending_triggered.connect(_on_arrest_ending_triggered)
	soul_altar_interacted.connect(_on_soul_altar_interacted)
	RevivalManager.soul_crystal_granted.connect(_on_soul_crystal_granted)
	_build_box_preview()
	_build_furniture_preview()
	_build_floor_decor_preview()
	_build_wall_decor_preview()
	_build_farm_tile_highlight()
	await _load_map("Home", "start_spawn")
	## _load_map()이 끝나 _is_transitioning이 풀린 뒤에 불러야 안에서 또
	## _load_map()을 부르는 이 함수가 씹히지 않는다.
	await _maybe_play_tutorial_intro()
	_maybe_resume_accomplice_ending()
	_maybe_resume_arrest_ending()


func _on_item_used(item_id: String) -> void:
	match item_id:
		"americano":
			player.apply_speed_effect(AMERICANO_SPEED_BONUS, AMERICANO_DURATION_MINUTES, false)
			AudioManager.play_sfx(AudioManager.SFX_DRINKING)
		"energy_tonic":
			player.clear_debuff()
			AudioManager.play_sfx(AudioManager.SFX_DRINKING)
		"perfume_somewhere_behind_you":
			# 마르가 호감도 선물로 준 향수 - NPC에게는 선물할 수 없고(category
			# "perfume", inventory_manager.gd), 우클릭으로 나에게 뿌린다(사용자
			# 지시, 2026-09-05). 소모되지 않으므로 다시 뿌리면 지속 시간만 갱신.
			player.apply_scent("gold")
			AudioManager.play_sfx(AudioManager.SFX_PERFUME_SPRAY)
			_show_temporary_message("좋은 향기가 나.")


## 레시피 아이템(만능 요리 레시피 포함)을 우클릭으로 써서 배웠을 때 플레이어
## 머리 위에 안내 문구를 띄운다(사용자 지시) - 조합을 처음 맞혀서 우연히
## 배운 경우(via_item==false)는 이미 냄비 완성 연출이 있어서 겹치면 어색하니
## 제외한다(CookingManager.learn_recipe()의 via_item 구분과 동일).
func _on_recipe_learned(recipe_id: String, via_item: bool) -> void:
	if not via_item:
		return
	var recipe_name := String(CookingManager.get_recipe_definition(recipe_id).get("name", recipe_id))
	_show_temporary_message(tr("%s 레시피를 획득했다!") % recipe_name)


## 인벤토리 화면을 안 열어도 어떤 추억의 물건을 받았는지 바로 보이도록 화면에
## 작게 아이콘+이름을 띄운다(사용자 지시, 2026-08-25 - "인벤에만 보여주는 거
## 말고"). NPCManager.get_daily_dialogue()가 인벤토리에 자리 있을 때만
## 지급하도록 이미 걸러주므로(consume_pending_milestone() 직전 inventory_ok
## 체크 참고) 이 신호가 오면 실제로 인벤토리에 들어간 뒤라고 봐도 된다.
func _on_memento_received(npc_id: String) -> void:
	if memento_toast != null:
		memento_toast.show_memento(npc_id)


## 호감도 이벤트로 동물(고양이/강아지)을 받는 임계값 -> {prompt, default_name}
## (사용자 지시, 2026-09-16 - "이름 지어주는 것도 만들 수 있어? 고양이 받은
## 순간에"). CatWorldManager/DogWorldManager가 스폰 여부를 판단하는 것과
## 같은 npc_id/threshold 조합을 그대로 쓴다.
const PET_GIFT_EVENTS := {
	"belje": {50: {"prompt": "고양이 이름을 지어주세요!", "default_name": "고양이"}},
	"shepherd": {50: {"prompt": "강아지 이름을 지어주세요!", "default_name": "강아지"}},
}
## consume_pending_milestone()이 dialogue_screen이 열리기도 전에 신호를
## 쏘기 때문에(get_daily_dialogue() 내부에서 호출), 그 자리에서 바로 이름
## 팝업을 띄우면 방금 연 대화창과 겹친다 - 여기 대기시켜뒀다가 그 대화창이
## 실제로 닫힌 뒤(_on_dialogue_screen_closed_for_pet_naming) 띄운다.
var _pending_pet_naming: Dictionary = {}


func _on_affection_event_triggered_for_pet_naming(npc_id: String, threshold: int) -> void:
	var per_npc: Dictionary = PET_GIFT_EVENTS.get(npc_id, {})
	if per_npc.has(threshold):
		_pending_pet_naming = {"npc_id": npc_id}
		_pending_pet_naming.merge(per_npc[threshold] as Dictionary)


func _on_dialogue_screen_closed_for_pet_naming() -> void:
	if _pending_pet_naming.is_empty() or pet_name_popup == null:
		return
	var pending := _pending_pet_naming
	_pending_pet_naming = {}
	pet_name_popup.open(String(pending.get("prompt", "")), String(pending.get("default_name", "")))
	_pending_pet_naming_npc_id = String(pending.get("npc_id", ""))


## _on_dialogue_screen_closed_for_pet_naming()이 팝업을 띄우는 시점과
## _on_pet_name_confirmed()가 결과를 받는 시점이 갈라져 있어서(팝업이 떠있는
## 동안 대상 npc_id를 어딘가에 들고 있어야 함) 별도 변수로 넘긴다.
var _pending_pet_naming_npc_id := ""


func _on_pet_name_confirmed(pet_name: String) -> void:
	if _pending_pet_naming_npc_id.is_empty():
		return
	NPCManager.set_pet_name(_pending_pet_naming_npc_id, pet_name)
	_pending_pet_naming_npc_id = ""
	## 어쨌든 선물(사용자 지시, 2026-09-16 - "추억의 물건 얻을 때 사운드가
	## 나면 좋겠어 어쨌든 이것도 선물이잖아") - _play_memento_event()가 쓰는
	## 것과 같은 효과음을 그대로 재사용.
	AudioManager.play_sfx(AudioManager.SFX_MEMORY)


## dialogue_screen.gd의 "buff" 타입 대사 줄(세이지 운세 보기 전용)을 실제
## 이동속도 효과로 적용한다 - 모카 커피/기절 디버프와 완전히 같은
## player.apply_speed_effect() 경로를 그대로 쓴다. 아메리카노/기력회복제는
## 마실 때 SFX_DRINKING이 나는데 이 경로만 효과음이 없었다(사용자 리포트,
## 2026-09-01 - 플레이테스트 13번) - 버프/디버프를 구분해서 재생한다.
func _on_dialogue_buff_requested(percent: float, duration_minutes: int, is_debuff: bool) -> void:
	if player != null:
		player.apply_speed_effect(percent, duration_minutes, is_debuff)
	AudioManager.play_sfx(AudioManager.SFX_FISHING_FAIL if is_debuff else AudioManager.SFX_GIFT)


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
## 가게 주인이 이미 죽은 뒤(그래서 상점이 온라인으로 전환된 뒤) 온라인으로
## 첫 가구를 사는 경우엔 죽은 NPC가 대사를 하며 나타나면 안 된다(사용자
## 지시, 2026-09-05 - "죽은 우디 영혼이 주는건 좀 이상하지 않아?") - 이럴 땐
## 대사 없이 조용히 망치만 받는다(아이템 자체는 가구 회수 기능에 필요하므로
## 계속 지급).
func _on_furniture_hammer_granted(npc_id: String) -> void:
	if shop_screen != null:
		shop_screen.close()
	if not NPCManager.is_alive(npc_id):
		_show_temporary_message("가구용 망치를 손에 넣었다.")
		return
	if dialogue_screen != null:
		var lines: Array = NPCManager.get_definition(npc_id).get("furniture_hammer_gift_lines", [])
		dialogue_screen.open_special(npc_id, lines)


const MURDER_DISCOVERY_MAP_ID := "plaza3"
const MURDER_DISCOVERY_NPC_ID := "poli"
const MURDER_DISCOVERY_TRIGGER := "murder_discovery"
## plaza3.tmx의 Spawn 오브젝트 레이어에 이 이름으로 지점 하나를 추가해야
## 한다(사용자 배치 예정) - 도착 후 폴리한테까지 마지막으로 뛰어가는 목적지.
const MURDER_DISCOVERY_POLI_SPAWN := "poli_murder_scene"
## 플레이어가 폴리 지점(MURDER_DISCOVERY_POLI_SPAWN)까지 그대로 걸어가면
## 폴리 분신과 겹쳐 서게 된다는 리포트(2026-08-26) - 플레이어는 이 지점까지만
## 걸어가고 멈춘다(사용자가 plaza3.tmx Spawn 레이어에 배치). 없으면 기존처럼
## 폴리 지점까지 그대로 걸어간다.
const MURDER_DISCOVERY_PLAYER_SPAWN := "player_murder_scene"
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
## 자루 스폰 시점에 플레이어가 문으로 걸어 들어온 원래 자리에 그대로 있다
## 보니 자루랑 겹쳐 보인다는 리포트(2026-08-26) - 이 지점이 있으면 자루를
## 세울 때 플레이어를 여기로 스냅시킨다(사용자가 Home.tmx Spawn 레이어에
## 배치 예정). 없으면 기존처럼 원래 위치 그대로 둔다.
const SECOND_MURDER_PLAYER_SPAWN := "second_murder_sack_player"
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

## 공범 엔딩(사용자 지시, 2026-08-24): 독약이 서빙된 다음날, 실제로 죽으면서
## 시작되는 컷신. 순서: 체포 내레이션 → 마을 사람들이 (스토커와 다른 수법에)
## 술렁이는 반응 몽타주(초상화 있는 진짜 대화, 죽었거나 story_dialogue에
## poison_victim_reaction이 없는 NPC는 조용히 건너뜀) → 어셔의 위증 →
## 위증 이후 내레이션 → 어셔가 집에 들어옴 → 마무리 내레이션. 내레이션은
## data/horror/endings.json(MurderManager.get_ending_narration())에서,
## 초상화 있는 대사는 각 npc.json의 story_dialogue에서 가져온다.
const ACCOMPLICE_ENDING_ID := "accomplice"
## 사용자 지시(2026-08-24): 모카/이샤/라마 반응 삭제, 폴리 단독으로.
const POISON_REACTION_NPC_IDS: Array[String] = ["poli"]
const POISON_REACTION_KEY := "poison_victim_reaction"
const ACCOMPLICE_TESTIMONY_KEY := "accomplice_testimony"
## 어셔의 위증 직후 폴리가 반응하는 자리(사용자 지시, 2026-08-24 - "이후에도
## 폴리가 대사하는 공간이 있었으면 좋겠어"). poli.json의 story_dialogue에 둠.
const ACCOMPLICE_RELEASE_KEY := "accomplice_release"
const ACCOMPLICE_MOVE_IN_KEY := "accomplice_move_in"
const USHER_NPC_ID := "usher"
const ENDING_BEAT_DELAY_SECONDS := 1.5

## 위증 전까지의 경찰서 장면(사용자 지시, 2026-08-26 - "나레이션 끝나고
## 페이드 해서 경찰서로 순간이동 하는 게 맞는 거 같은데... 폴리랑 대화하는데
## 갑자기 개뜬금으로 집에있으니까 이상해"). police_interior.tmx의 Spawn
## 레이어에 이미 있는 지점을 그대로 쓴다 - police_working(폴리 분신 자리),
## player_ending/usher_ending(사용자가 직접 배치), police_office_enterance
## (어셔가 걸어 들어오는 시작점).
const ACCOMPLICE_SCENE_MAP_ID := "police_interior"
const ACCOMPLICE_SCENE_POLI_SPAWN := "police_working"
const ACCOMPLICE_SCENE_PLAYER_SPAWN := "player_ending"
const ACCOMPLICE_SCENE_USHER_ENTER_SPAWN := "police_office_enterance"
const ACCOMPLICE_SCENE_USHER_SPAWN := "usher_ending"
## 어셔가 usher_ending에 도착한 뒤 대사가 뜨기 전 잠깐 정지(사용자 지시,
## 2026-08-26 - "어셔가 도착한 후 1초 뒤에 어셔의 대사가 뜨게 해줘").
const ACCOMPLICE_USHER_ARRIVE_PAUSE_SECONDS := 1.0
## npc_world_manager.gd의 NPC_WALK_TIMEOUT_SECONDS와 같은 안전장치 - 경로를
## 못 찾는 등의 이유로 영원히 안 멈추는 상황을 막는다.
const ACCOMPLICE_USHER_WALK_TIMEOUT_SECONDS := 5.0
## 시간 경과 내레이션 이후, 어셔가 이사오기 전에 플레이어가 집에 갇혀 스토커
## 메일을 확인하는 구간(사용자 지시, 2026-08-24). home_interior.tmx의 Spawn
## 레이어에 이미 있는 지점("home_enterance")을 그대로 재사용 - 새로 안 만듦.
const ACCOMPLICE_MAIL_MAP_ID := "home_interior"
const ACCOMPLICE_MAIL_SPAWN := "home_enterance"

## 체포 엔딩(사용자 지시, 2026-08-24): 경고 사격 소리 → 지금 있는 맵에서
## book_interior(어셔의 서점)까지 실제로 뛰어감(WorldMap.find_map_route()의
## BFS 최단경로 - MURDER_RUN_CHAIN처럼 수동 표를 새로 안 만들어도 어디서든
## 동작함) → 도착하면 폴리/어셔/살아남은 3번째 대상(spared_npc_id) 분신을
## 각자 자리에 세우고 플레이어도 지정 자리로 이동 → 폴리 경고 → 어셔의 마지막
## 말 → 자결 총소리 → 페이드 → 마무리 내레이션. book_interior.tmx의 Spawn
## 레이어에 아래 4개 지점이 필요하다(사용자 배치 예정).
const ARREST_ENDING_ID := "arrest"
const ARREST_SCENE_MAP_ID := "book_interior"
const ARREST_SCENE_PLAYER_SPAWN := "arrest_scene_player"
const ARREST_SCENE_POLI_SPAWN := "arrest_scene_poli"
const ARREST_SCENE_USHER_SPAWN := "arrest_scene_usher"
const ARREST_SCENE_VICTIM_SPAWN := "arrest_scene_victim"
const ARREST_SCENE_WARNING_KEY := "arrest_scene_warning"
const ARREST_SCENE_FINAL_WORDS_KEY := "arrest_scene_final_words"
## 어셔의 마지막 말에 폴리가 한 번 더 받아치는 자리(사용자 지시, 2026-08-24 -
## "티키타카 할 수 있도록"). poli.json의 story_dialogue에 둠.
const ARREST_SCENE_REACTION_KEY := "arrest_scene_reaction"
## 나이프 떨어지는 소리 직후, 죽어가는 어셔의 마지막 한 마디(사용자 지시,
## 2026-08-24). usher.json의 story_dialogue에 둠.
const ARREST_SCENE_LAST_BREATH_KEY := "arrest_scene_last_breath"
## 마무리 나레이션 사이, 기절한 대상을 업은 폴리가 플레이어에게 건네는 마지막
## 한마디(사용자 지시, 2026-08-24). poli.json의 story_dialogue에 둠.
const ARREST_SCENE_FAREWELL_KEY := "arrest_scene_farewell"

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
## 영혼의 결정 지급 컷신이 있었던 날 아침(사용자 지시, 2026-08-25).
const SOUL_CRYSTAL_WAKE_UP_MONOLOGUE: Array[String] = [
	"...무슨 꿈이었지?",
]
## 노크 이후 실제로 문을 열고 나가봤을 때(home_interior -> Home) 아무도
## 없었다는 혼잣말(초안, 사용자 지시 2026-08-24 - "나가면 아무것도 없는거로").
## 문구는 아직 확정 아님, 수정 환영.
const KNOCK_CHECK_RESULT_MONOLOGUE: Array[String] = [
	"...아무도 없다.",
	"그냥 기분 탓이었나.",
]

## 신규 슬롯 튜토리얼 컷신(_maybe_play_tutorial_intro()) 전용 - 사용자 지시,
## 2026-09-01. 폴리가 첫 손님이 되어 레스토랑 조작법을 안내한다.
const TUTORIAL_POLI_ID := "poli"
## Home 맵에 미리 배치해야 하는 스폰 지점 - 게임 시작 시 플레이어(start_spawn)
## 바로 옆에서 인사를 건네는 위치(폴리가 뛰어와서 도착하는 지점).
const TUTORIAL_POLI_HOME_SPAWN := "poli_tutorial_greet"
## Home 맵에 미리 배치해야 하는 스폰 지점 - 폴리가 인사하러 뛰어오기 시작하는
## 출발 위치(사용자 지시, 2026-09-01 - "가만히 있는 플레이어에게 뛰어오는
## 폴리 모션이 없음"). start_spawn(320,224)에서 살짝 떨어진, 화면 안에서
## 뛰어오는 게 보일만한 지점으로 잡아야 함.
const TUTORIAL_POLI_RUN_START_SPAWN := "poli_tutorial_run_start"
## Home.tmx의 실제 "restaurant_in" Warp 오브젝트(x=112,y=208,w=32,h=16) 중심
## 좌표 - Tiled 오브젝트는 파싱 시 좌상단이 아니라 중심점으로 변환되므로
## (home_map.gd 오브젝트 파싱 참고) 112+16, 208+8. 플레이어를 프리 무브 대신
## 컷신으로 문 앞까지 직접 걸어가게 한 뒤(사용자 지시, 2026-09-01 - "플레이어
## 자유 이동이 아니라 알아서 컷씬 이벤트로 이동 되어야됨") 바로 이 지점에서
## restaurant_interior로 넘긴다. 새 스폰을 따로 안 만들고 이미 있는 실제 문
## 위치를 그대로 쓴다.
const TUTORIAL_PLAYER_DOOR_POSITION := Vector2(128.0, 216.0)
## restaurant_interior_new.tmx에 이미 있는 정식 입장 스폰(사용자가 새로 만들
## 필요 없음) - 평소 Warp도 이 스폰으로 들어온다.
const TUTORIAL_RESTAURANT_ENTRANCE_SPAWN := "restaurant_enterance"
## 폴리 분신이 문 앞까지 같이 걸어가는 시간 제한(usher_decoy 걷기 대기와 동일
## 이유 - 길찾기가 실패해도 컷신이 영원히 멈추지 않게).
const TUTORIAL_DECOY_WALK_TIMEOUT_SECONDS := 8.0
## restaurant_interior 맵에 미리 배치해야 하는 스폰 지점 - 개점 전까지 문 안쪽에
## 서서 기다리는 위치(restaurant_seat1 자리에 바로 앉지 않고, 개점 후에야
## 자리로 걸어감).
const TUTORIAL_POLI_RESTAURANT_SPAWN := "poli_tutorial_entrance"
const TUTORIAL_POLI_STATION_INDEX := 0
const TUTORIAL_SIGN_INTERACTABLE := "restaurant_open"
## 튜토리얼 대사는 코드에 직접 안 쓰고 데이터 파일로 뺐다(사용자 지시,
## 2026-09-05 - "언제든 내가 수정할 수 있게") - CLAUDE.md "NPC 대사를 코드에
## 작성" 금지 원칙과도 맞춤. _load_tutorial_dialogue()가 채운다.
const TUTORIAL_DIALOGUE_PATH := "res://data/tutorial/intro_dialogue.json"
var _tutorial_dialogue: Dictionary = {}
## cooking_stations.json 확인 결과 냄비=potato->cooked_potato,
## 프라이팬=mackerel->cooked_mackerel, 15초 조리. cooked_mackerel+cooked_potato는
## recipes.json에 실제로 등록된 레시피(생선과 감자튀김을 곁들인 요리)라 서빙도
## 정상적으로 완성된다.
const TUTORIAL_POT_STATION := "cooking_area1"
const TUTORIAL_PAN_STATION := "cooking_area2"
const TUTORIAL_RAW_POTATO_ID := "potato"
const TUTORIAL_RAW_MACKEREL_ID := "mackerel"
const TUTORIAL_COOKED_POTATO_ID := "cooked_potato"
const TUTORIAL_COOKED_MACKEREL_ID := "cooked_mackerel"
const TUTORIAL_SERVING_STATION := "serving_area1"
## KitchenManager에 진행 상태 신호가 없어서(is_busy/is_ready를 매번 다시 물어야
## 함) usher_decoy 걷기 대기(위 _play_accomplice_ending_sequence 근방)와 동일한
## 폴링 방식을 쓴다.
const TUTORIAL_POLL_INTERVAL_SECONDS := 0.2
const TUTORIAL_HIGHLIGHT_COLOR := Color(1.0, 0.92, 0.25, 0.6)
const TUTORIAL_HIGHLIGHT_DIM_ALPHA := 0.15
const TUTORIAL_HIGHLIGHT_PULSE_DURATION := 0.5

## 1차 살인 비명 직후, 바로 뛰어가지 않고 "!" 반응 + 한 박자 나레이션을
## 먼저 보여준다(사용자 지시, 2026-08-26 - "바로 뛰어가는 것보다 플레이어
## 머리 위에 ! 이모티콘을 띄워주고, 나레이션으로... 이게 있으면 좋겠어").
const MURDER_SCREAM_REACTION_MONOLOGUE: Array[String] = [
	"이게 무슨 소리지? 소리가 들린 쪽으로 가보자.",
]

## 체포 엔딩의 경고 사격 직후 반응(사용자 작성, 2026-08-26).
const ARREST_GUNSHOT_REACTION_MONOLOGUE: Array[String] = [
	"총소리가 들렸다. 어서 가봐야겠어!",
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
## 원래 0.2였는데 맵을 자주 오가다 보니 너무 자주 나온다는 피드백으로 0.05로
## 낮춤(사용자 지시, 2026-08-30).
const SHADOW_FIGURE_APPEAR_CHANCE := 0.05
const SHADOW_FIGURE_VANISH_DISTANCE := 64.0
## 등장 순간 호러 브금 스팅(사용자 지시, 2026-08-26 - "스토커 볼 때는 한
## 7초정도?"). AudioManager.play_horror_sting() 참고.
const SHADOW_FIGURE_HORROR_STING_SECONDS := 7.0

var _shadow_figure_node: Sprite2D = null

## 노크 이후 아직 문을 열고 나가보지 않은 상태 - main.gd._load_map()이
## home_interior에서 Home으로 나갈 때 이 플래그를 보고 "아무도 없다" 반응을
## 한 번 보여준 뒤 끈다.
var _knock_check_pending := false

## 공범 엔딩의 문 앞 노크(_play_accomplice_mail_wait_beat)가 재생되는 동안만
## true - _on_knock_sequence_finished() 참고.
var _suppress_knock_check_pending := false

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
	AudioManager.duck_bgm_for_scene()
	AudioManager.play_sfx(AudioManager.SFX_SCREAM)
	if player != null:
		player.show_emote(NPCManager.EMOTE_EXCLAMATION)
	if dialogue_screen != null:
		dialogue_screen.open_special("", MURDER_SCREAM_REACTION_MONOLOGUE.duplicate())
		await dialogue_screen.closed
	while GameManager.current_map_id != MURDER_DISCOVERY_MAP_ID:
		var current_map_id := GameManager.current_map_id
		var next_map_id := String(MURDER_RUN_CHAIN.get(current_map_id, ""))
		var warp: Dictionary = world_map.get_warp_for_target_map(next_map_id) if not next_map_id.is_empty() else world_map.get_any_warp()
		if warp.is_empty():
			push_error("murder discovery run: no warp found from %s" % current_map_id)
			_murder_scene_active = false
			AudioManager.restore_bgm_after_scene()
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
		var player_target := world_map.get_spawn_position(MURDER_DISCOVERY_PLAYER_SPAWN)
		await player.walk_to(player_target if player_target != Vector2.INF else poli_spawn)
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
	AudioManager.restore_bgm_after_scene()
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
	if player != null:
		var player_spawn: Vector2 = world_map.get_spawn_position(SECOND_MURDER_PLAYER_SPAWN)
		if player_spawn != Vector2.INF:
			player.position = player_spawn
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
	AudioManager.duck_bgm_for_scene()
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
	AudioManager.restore_bgm_after_scene()
	MurderManager.consume_second_murder_discovery_pending()
	# 자루를 직접 발견한 직후 익명 스토커 메일(사용자 지시, 2026-08-26 -
	# "자루 발견 후에 익명의 스토커 메일로 '잘 받았어?' 이런 거 오면 좋을 듯").
	HorrorEventManager.send_second_murder_sack_email()
	await _fade_in()


func _on_accomplice_ending_triggered(_victim_id: String) -> void:
	await _play_accomplice_ending_sequence()


## 진실 엔딩(사용자 작성, 2026-08-24) - 화자 없는 내레이션 한 토막뿐이라 맵
## 이동이 없다. 그래서 공범 엔딩과 달리 재접속 시 이어보기 안전장치가
## 필요없다 - 자동저장이 걸릴 시점(맵 이동) 자체가 이 안에 없어서, 도중에
## 꺼도 다음 접속 때 _pending_poison_victim이 그대로 남아있어 알아서 처음부터
## 다시 재생된다(murder_manager.gd의 day_changed 처리 참고).
func _on_truth_ending_triggered() -> void:
	_murder_scene_active = true
	_close_all_screens()
	await _play_narration_beat("truth", "closing_narration")
	_murder_scene_active = false


func _on_arrest_ending_triggered(spared_npc_id: String) -> void:
	await _play_arrest_ending_sequence(spared_npc_id)


## 순서/스폰 지점은 ARREST_ENDING_ID 상수 근처 주석 참고.
func _play_arrest_ending_sequence(spared_npc_id: String) -> void:
	_murder_scene_active = true
	_close_all_screens()
	# 살인 발견 씬과 같은 이유(사용자 지시, 2026-08-26 - "체포엔딩때도 넣어주라
	# 좋네") - 게임에서 가장 긴장감 높은 장면인데 평소 브금이 그대로 깔리면
	# 몰입이 깨진다. 체포 엔딩 전용 브금(BGM_ARREST_ENDING)을 총소리와 동시에
	# 튼다(사용자 지시, 2026-08-26).
	AudioManager.duck_bgm_for_scene(AudioManager.BGM_ARREST_ENDING)
	AudioManager.play_sfx(AudioManager.SFX_GUNSHOT, AudioManager.SFX_GUNSHOT_VOLUME_DB)
	## 살인 발견 씬(MURDER_SCREAM_REACTION_MONOLOGUE)과 동일한 이유 - 총소리가
	## 나자마자 바로 뛰어가는 대신 "!" 반응 + 한 박자 나레이션(사용자 지시,
	## 2026-08-26 - "총소리가 나고 나서 처음 살인 발견했을 때처럼 ! 머리 위에
	## 뜨고... 나레이션 있어야할듯").
	if player != null:
		player.show_emote(NPCManager.EMOTE_EXCLAMATION)
	if dialogue_screen != null:
		dialogue_screen.open_special("", ARREST_GUNSHOT_REACTION_MONOLOGUE.duplicate())
		await dialogue_screen.closed
	var route := WorldMap.find_map_route(GameManager.current_map_id, ARREST_SCENE_MAP_ID)
	for next_map_id in route:
		var warp: Dictionary = world_map.get_warp_for_target_map(next_map_id)
		if warp.is_empty():
			warp = world_map.get_any_warp()
		if warp.is_empty():
			push_error("arrest ending run: no warp found from %s" % GameManager.current_map_id)
			_murder_scene_active = false
			AudioManager.restore_bgm_after_scene()
			return
		await player.walk_to(warp["position"])
		await _load_map(String(warp["target_map"]), String(warp["target_spawn"]))
	_set_all_npc_sprites_hidden(true)
	var scene_props: Array[Node2D] = []
	var poli_spawn: Vector2 = world_map.get_spawn_position(ARREST_SCENE_POLI_SPAWN)
	if poli_spawn != Vector2.INF:
		scene_props.append(_spawn_npc_decoy(MURDER_DISCOVERY_NPC_ID, poli_spawn))
	var usher_spawn: Vector2 = world_map.get_spawn_position(ARREST_SCENE_USHER_SPAWN)
	if usher_spawn != Vector2.INF:
		scene_props.append(_spawn_npc_decoy(USHER_NPC_ID, usher_spawn))
	var victim_spawn: Vector2 = world_map.get_spawn_position(ARREST_SCENE_VICTIM_SPAWN)
	if not spared_npc_id.is_empty() and victim_spawn != Vector2.INF:
		scene_props.append(_spawn_npc_decoy(spared_npc_id, victim_spawn))
	var player_spawn: Vector2 = world_map.get_spawn_position(ARREST_SCENE_PLAYER_SPAWN)
	if player_spawn != Vector2.INF:
		await player.walk_to(player_spawn)
	await get_tree().create_timer(ENDING_BEAT_DELAY_SECONDS).timeout
	await _play_npc_beat(MURDER_DISCOVERY_NPC_ID, ARREST_SCENE_WARNING_KEY)
	await _play_npc_beat(USHER_NPC_ID, ARREST_SCENE_FINAL_WORDS_KEY)
	await _play_npc_beat(MURDER_DISCOVERY_NPC_ID, ARREST_SCENE_REACTION_KEY)
	## "총소리만 빵 하고 끝낼거야" (사용자 지시, 2026-08-24) - 대사 끝나면
	## 바로 총소리 + 암전, 여운 없이 끊는다.
	AudioManager.play_sfx(AudioManager.SFX_GUNSHOT, AudioManager.SFX_GUNSHOT_VOLUME_DB)
	## 치명상 총소리 이후는 서글픈 여운으로 바뀐다(사용자 지시, 2026-08-26).
	AudioManager.play_bgm(AudioManager.BGM_ARREST_AFTERMATH)
	await _fade_out()
	## 어셔가 실제로 죽는 순간은 여기다 - 예전엔 MurderManager._trigger_arrest_ending()이
	## 컷신 시작 전에 미리 죽여둬서, 아직 총 맞기 전인 앞쪽 대사(경고/최후
	## 진술/반응)에서도 초상화가 계속 흑백(사망 처리)으로 떴다(사용자 리포트,
	## 2026-08-26 - "체포엔딩에서 어셔 초상화 왜 흑백으로 떠?"). 화면이 검게
	## 된 지금부터 실제로 죽은 것으로 처리한다.
	NPCManager.kill_npc(NPCManager.get_stalker_id())
	## 총소리 직후 암전은 "여운 없이 끊는" 짧은 컷 전환용일 뿐, closing_narration
	## 자체는 다시 밝은 화면에서 보여준다(사용자 지시, 2026-08-26 - "나레이션
	## 할 때 화면 밝혀줘야돼"). 원래는 엔딩이 다 끝날 때까지 계속 암전
	## 상태였는데, 대사가 몇 개나 남았는지 모른 채 계속 검은 화면만 보여서
	## 멈춘 것처럼 느껴졌다는 리포트도 있었음.
	await _fade_in()
	await _play_arrest_closing_narration("closing_narration", spared_npc_id)
	AudioManager.play_sfx(AudioManager.SFX_KNIFE_DROP)
	await _play_npc_beat(USHER_NPC_ID, ARREST_SCENE_LAST_BREATH_KEY)
	await _play_arrest_closing_narration("aftermath_narration", spared_npc_id)
	await _play_npc_beat(MURDER_DISCOVERY_NPC_ID, ARREST_SCENE_FAREWELL_KEY)
	await _play_narration_beat(ARREST_ENDING_ID, "final_narration")
	## 밝은 화면에서 분신을 바로 지우면 폴리/어셔/대상이 눈에 띄게 사라지는
	## 것처럼 보인다 - 공범 엔딩과 동일하게 암전 상태에서 정리한다.
	await _fade_out()
	_cleanup_murder_discovery_scene_props(scene_props)
	_set_all_npc_sprites_hidden(false)
	_murder_scene_active = false
	## 엔딩 씬이 완전히 끝나면 평소 브금으로 되돌린다(사용자 지시, 2026-08-26).
	## 한 번은 "화면이 안 밝아진다"는 리포트 때문에 씬이 아직 안 끝난 줄
	## 알고 되돌리지 말라고 했었는데, 페이드 타이밍을 고친 뒤 다시 확인해보니
	## 씬이 진짜 끝나면 원래대로 되돌리는 게 맞았다("엔딩 씬 끝나면 브금도
	## 원래대로 다시 돌려줘야할 거 같아" / "계속 슬픈 브금이 나와").
	AudioManager.restore_bgm_after_scene()
	MurderManager.mark_arrest_sequence_completed()
	await _fade_in()


## _spawn_murder_discovery_poli_decoy()의 범용 버전 - 폴리 전용이 아니라 아무
## npc_id나 특정 위치에 세울 때 쓴다(체포 엔딩: 폴리/어셔/살아남은 3번째 대상).
func _spawn_npc_decoy(npc_id: String, spawn_position: Vector2) -> Node2D:
	var decoy := POLI_DECOY_SCENE.instantiate() as Node2D
	world_map.add_child(decoy)
	decoy.call("set_npc_id", npc_id)
	decoy.call("snap_to", spawn_position)
	decoy.call("face_down")
	return decoy


## 순서(사용자 지시, 2026-08-24, 2026-08-26에 위치 수정): 발견 → 경찰서 이동 →
## 마을 반응(폴리, 경찰서에서) → 체포 → 어셔 위증 → 위증 직후 내레이션 →
## 폴리의 석방 반응 → 시간 경과 내레이션 → 동거 → 마무리. 내용은
## ACCOMPLICE_ENDING_ID 상수 근처 주석 참고.
func _play_accomplice_ending_sequence() -> void:
	_murder_scene_active = true
	_close_all_screens()
	await _play_narration_beat(ACCOMPLICE_ENDING_ID, "discovery_narration")
	## 경찰서 이동은 마을 반응(폴리 대사)보다 먼저 - 원래는 대사 다음에
	## 옮겼더니 발견 나레이션 직후에도 여전히 플레이어가 있던 맵 그대로 남아
	## 있는 것처럼 보였다(사용자 리포트, 2026-08-26 - "나레이션 끝나고 페이드
	## 된 다음에 경찰서 안가는데?... 폴리 대사 전에 가는거로 고쳐야돼").
	var scene_props := await _play_accomplice_police_arrival()
	await get_tree().create_timer(ENDING_BEAT_DELAY_SECONDS).timeout
	for npc_id in POISON_REACTION_NPC_IDS:
		if not NPCManager.is_alive(npc_id):
			continue
		var lines: Array = (NPCManager.get_definition(npc_id).get("story_dialogue", {}).get(POISON_REACTION_KEY, []) as Array).duplicate()
		if lines.is_empty():
			continue
		if dialogue_screen != null:
			dialogue_screen.open_special(npc_id, lines)
			await dialogue_screen.closed
		await get_tree().create_timer(ENDING_BEAT_DELAY_SECONDS).timeout
	await _play_accomplice_usher_testimony(scene_props)
	await _play_narration_beat(ACCOMPLICE_ENDING_ID, "post_testimony_narration")
	await _play_npc_beat(MURDER_DISCOVERY_NPC_ID, ACCOMPLICE_RELEASE_KEY)
	await _play_narration_beat(ACCOMPLICE_ENDING_ID, "time_skip_narration")
	## 화면이 밝은 채로 분신을 지우면 폴리/어셔가 그 자리에서 눈에 띄게
	## 사라지는 것처럼 보인다 - 체포 엔딩과 동일하게 암전 상태에서 정리한다.
	await _fade_out()
	_cleanup_murder_discovery_scene_props(scene_props)
	_set_all_npc_sprites_hidden(false)
	await _play_accomplice_home_arrival_sequence()


## 경찰서(police_interior)로 이동해 폴리 분신/플레이어를 자리에 세우기까지
## (사용자 지시, 2026-08-26 - "나레이션 끝나고 페이드 해서 경찰서로 순간이동
## 하는 게 맞는 거 같은데... 폴리랑 대화하는데 갑자기 개뜬금으로 집에있으니까
## 이상해"). 체포 엔딩(_play_arrest_ending_sequence)과 같은 이유로 실제
## 스케줄 스프라이트를 숨기고 분신을 세운다 - 폴리 스케줄이 마침 여기 있을
## 때만 서 있는 게 아니라 항상 확실하게 서 있게 하기 위함. 반환값은 호출부가
## 나중에 정리할 분신 목록 - _play_accomplice_usher_testimony()가 어셔 분신을
## 여기에 이어서 추가한다.
func _play_accomplice_police_arrival() -> Array[Node2D]:
	var scene_props: Array[Node2D] = []
	var route := WorldMap.find_map_route(GameManager.current_map_id, ACCOMPLICE_SCENE_MAP_ID)
	for next_map_id in route:
		var warp: Dictionary = world_map.get_warp_for_target_map(next_map_id)
		if warp.is_empty():
			warp = world_map.get_any_warp()
		if warp.is_empty():
			push_error("accomplice ending run: no warp found from %s" % GameManager.current_map_id)
			return scene_props
		await player.walk_to(warp["position"])
		await _load_map(String(warp["target_map"]), String(warp["target_spawn"]))
	_set_all_npc_sprites_hidden(true)
	var poli_spawn: Vector2 = world_map.get_spawn_position(ACCOMPLICE_SCENE_POLI_SPAWN)
	if poli_spawn != Vector2.INF:
		scene_props.append(_spawn_npc_decoy(MURDER_DISCOVERY_NPC_ID, poli_spawn))
	var player_spawn: Vector2 = world_map.get_spawn_position(ACCOMPLICE_SCENE_PLAYER_SPAWN)
	if player_spawn != Vector2.INF:
		await player.walk_to(player_spawn)
	## 뒷모습(사용자 지시, 2026-08-26 - "자리에 도착하면 플레이어는 뒷모습").
	player.facing_direction = Vector2i(0, -1)
	return scene_props


## 위증까지 - arrest_narration(이미 "그때, 예상하지 못한 사람이 나타났다 /
## 어셔였다" 포함) 직후 페이드, 어셔가 police_office_enterance에서
## usher_ending까지 실제로 걸어 들어오는 모습을 보여준다(사용자 지시 -
## "경찰서로 어셔가 들어오는 애니메이션이 있어야겠어"). scene_props는
## _play_accomplice_police_arrival()이 만든 배열을 그대로 받아 어셔 분신을
## 이어서 추가한다(Array는 참조 타입이라 호출부의 scene_props도 같이 갱신됨).
func _play_accomplice_usher_testimony(scene_props: Array[Node2D]) -> void:
	await _play_narration_beat(ACCOMPLICE_ENDING_ID, "arrest_narration")
	await _fade_out()
	var usher_enter_spawn: Vector2 = world_map.get_spawn_position(ACCOMPLICE_SCENE_USHER_ENTER_SPAWN)
	var usher_decoy: Node2D = null
	if usher_enter_spawn != Vector2.INF:
		usher_decoy = _spawn_npc_decoy(USHER_NPC_ID, usher_enter_spawn)
		scene_props.append(usher_decoy)
	await _fade_in()
	if usher_decoy != null:
		var usher_spawn: Vector2 = world_map.get_spawn_position(ACCOMPLICE_SCENE_USHER_SPAWN)
		if usher_spawn != Vector2.INF:
			var path: PackedVector2Array = world_map.find_path(usher_decoy.position, usher_spawn)
			usher_decoy.call("walk_to", path)
			var elapsed := 0.0
			while bool(usher_decoy.call("is_walking")) and elapsed < ACCOMPLICE_USHER_WALK_TIMEOUT_SECONDS:
				await get_tree().physics_frame
				elapsed += get_physics_process_delta_time()
		usher_decoy.call("face_left")
	await get_tree().create_timer(ACCOMPLICE_USHER_ARRIVE_PAUSE_SECONDS).timeout
	await _play_npc_beat(USHER_NPC_ID, ACCOMPLICE_TESTIMONY_KEY)


## time_skip_narration 이후 부분만 따로 뗀 이유(사용자 지시, 2026-08-24 -
## "컷씬하다가 게임 꺼버리면?"): 이 지점부터 home_interior로 맵이 바뀌면서
## 자동저장이 걸린다. _play_accomplice_ending_sequence()가 순서상 이 함수를
## 마지막에 부른다.
func _play_accomplice_home_arrival_sequence() -> void:
	await _load_map(ACCOMPLICE_MAIL_MAP_ID, ACCOMPLICE_MAIL_SPAWN)
	## 메일 확인/문 앞 대기 중엔 _murder_scene_active를 잠깐 풀어야 컴퓨터 E
	## 상호작용(메일함 열기)과 이동이 막히지 않는다 - 대신 _accomplice_awaiting_mail_read/
	## _accomplice_awaiting_door_open이 문 워프만 따로 막는다(둘 다
	## _play_accomplice_mail_wait_beat() 안에서 관리).
	_murder_scene_active = false
	await _play_accomplice_mail_wait_beat()
	_murder_scene_active = true
	await _fade_out()
	await _fade_in()
	await _play_npc_beat(USHER_NPC_ID, ACCOMPLICE_MOVE_IN_KEY)
	await _play_narration_beat(ACCOMPLICE_ENDING_ID, "closing_narration")
	_murder_scene_active = false
	MurderManager.mark_accomplice_sequence_completed()


## 게임을 새로 켤 때(_ready()에서 호출) - 공범 엔딩은 확정됐는데 마무리 컷신을
## 끝까지 못 봤으면(중간에 게임을 껐으면) 처음부터 다시 보여준다. 예전엔
## _play_accomplice_home_arrival_sequence()로 바로 건너뛰었으나, 이 세션에
## 추가된 경찰서 장면(discovery_narration → 경찰서 이동 → 위증)이 그 사이에
## 몇 번씩 맵을 옮기면서 매번 자동저장을 걸어서, 그 구간에서 게임을 끄면
## 발견/경찰서/위증 내용이 통째로 건너뛰어지는 문제가 있었다(QA 점검,
## 2026-08-26). 이미 본 내용을 한 번 더 보여주는 게, 아예 못 보고 넘어가는
## 것보다 안전한 쪽이라 처음부터 다시 재생한다.
func _maybe_resume_accomplice_ending() -> void:
	if MurderManager.get_achieved_ending() != "accomplice":
		return
	if MurderManager.is_accomplice_sequence_completed():
		return
	_murder_scene_active = true
	_close_all_screens()
	await _play_accomplice_ending_sequence()


## _maybe_resume_accomplice_ending()과 동일한 이유(QA 점검, 2026-08-26) - 체포
## 엔딩도 컷신 도중 맵을 여러 번 옮기며 자동저장을 거는데, 재개 경로 자체가
## 아예 없었다. 처음부터 다시 재생한다.
func _maybe_resume_arrest_ending() -> void:
	if MurderManager.get_achieved_ending() != "arrest":
		return
	if MurderManager.is_arrest_sequence_completed():
		return
	_murder_scene_active = true
	_close_all_screens()
	await _play_arrest_ending_sequence(MurderManager.get_spared_npc_id())


## 플레이어가 home_interior에서 눈을 뜬 채로, 스토커 메일을 실제로 열어
## 읽을 때까지 집 밖으로 나갈 수 없다(사용자 지시, 2026-08-24). stalker_mail
## 내용이 아직 없으면(TODO) 조용히 건너뛴다 - 이때는 잠금 자체도 안 건다.
## 순서: 메일 도착 → 플레이어가 직접 열람할 때까지 대기(집 밖 워프만 막힘,
## 컴퓨터 상호작용은 허용) → 열람 후 플레이어가 메일 창을 직접 닫을(또는
## ESC로 나갈) 때까지 대기 → 노크 소리 → 문 앞에서 E를 눌러야 다음 단계로.
## 원래는 열람 즉시 60초간 강제로 붙잡아뒀으나(직접 못 닫음), 실제로 켜보니
## 뭔가 멈춘 줄 알았다는 지적(사용자 리포트, 2026-08-26 - "유지시간이 너무
## 길어서 에러났나했어... 닫기나 뒤로가기 눌렀을 때 다음 노크소리 들리게
## 하는 게 맞으려나")으로, 강제 대기 대신 플레이어가 직접 닫을 때까지만
## 기다리는 방식으로 바꿨다.
func _play_accomplice_mail_wait_beat() -> void:
	var mail: Dictionary = MurderManager.get_ending_mail(ACCOMPLICE_ENDING_ID, "stalker_mail")
	var lines: Array = mail.get("lines", [])
	if lines.is_empty():
		return
	_accomplice_awaiting_mail_read = true
	var mail_id := EmailManager.send_stalker_mail(String(mail.get("title", "")), lines)
	AudioManager.play_sfx(AudioManager.SFX_STALKER_MAIL)
	## 평소 새 메일 알림(_maybe_show_mail_reminder)은 _load_map() 끝에서만
	## 자동으로 체크되는데, 이 스토커 메일은 그 시점(맵 로드 직후) 이후에
	## 도착해서 알림이 그냥 넘어갔다(사용자 리포트, 2026-08-26 - "집에 오고
	## 난 다음에 메일 확인하라는 머리 문구는 아직도 안떠") - 메일을 보낸
	## 직후 같은 함수를 직접 한 번 더 불러준다.
	_maybe_show_mail_reminder(GameManager.current_map_id)
	if mail_id >= 0:
		while not EmailManager.is_mail_read(mail_id):
			await EmailManager.inbox_updated
		if computer_screen != null:
			await computer_screen.mail_dismissed
	_accomplice_awaiting_mail_read = false
	_suppress_knock_check_pending = true
	await AudioManager.play_knock_sequence()
	_suppress_knock_check_pending = false
	_accomplice_awaiting_door_open = true
	await accomplice_door_answered


## 화자 없는 나레이션 한 토막 - 내용이 없으면(TODO 등) 조용히 건너뛴다.
func _play_narration_beat(ending_id: String, section: String) -> void:
	var lines: Array = MurderManager.get_ending_narration(ending_id, section)
	if lines.is_empty() or dialogue_screen == null:
		return
	dialogue_screen.open_special("", lines.duplicate())
	await dialogue_screen.closed


## 체포 엔딩 전용 - endings.json의 {spared_name}은 dialogue_screen.gd가 자동
## 치환해주는 {player_name}/{victim_name}과 달리 여기서 직접 채워야 한다
## (spared_npc_id는 그때그때 다른 NPC라 범용 치환 목록에 넣기보다 이 한
## 곳에서만 처리). closing_narration뿐 아니라 aftermath_narration도
## {spared_name}을 쓰는데 원래 그쪽은 일반 _play_narration_beat()로 재생되고
## 있어서 "{spared_name}" 글자가 그대로 노출되고 있었다 - 두 섹션 다 이
## 함수로 받도록 section 인자를 받게 바꿨다.
func _play_arrest_closing_narration(section: String, spared_npc_id: String) -> void:
	var lines: Array = MurderManager.get_ending_narration(ARREST_ENDING_ID, section)
	if lines.is_empty() or dialogue_screen == null:
		return
	var spared_name := String(NPCManager.get_definition(spared_npc_id).get("name", ""))
	var substituted: Array = []
	for line in lines:
		if line is Dictionary:
			var entry: Dictionary = (line as Dictionary).duplicate()
			entry["text"] = String(entry.get("text", "")).replace("{spared_name}", spared_name)
			substituted.append(entry)
		else:
			substituted.append(String(line).replace("{spared_name}", spared_name))
	dialogue_screen.open_special("", substituted)
	await dialogue_screen.closed


## npc.json의 story_dialogue[key] 배열을 초상화 있는 대사로 보여준다.
func _play_npc_beat(npc_id: String, story_dialogue_key: String) -> void:
	var lines: Array = (NPCManager.get_definition(npc_id).get("story_dialogue", {}).get(story_dialogue_key, []) as Array).duplicate()
	if lines.is_empty() or dialogue_screen == null:
		return
	dialogue_screen.open_special(npc_id, lines)
	await dialogue_screen.closed


## heart_event_30(호감도 30 최초 이벤트, 사용자 지시 2026-08-24 - "스듀식"
## 컷신) 조건을 만족하는 NPC 하나를 찾는다 - _prepare_heart_event()(암전
## 상태에서, 비-이동형 전용)와 _maybe_trigger_heart_event()(화면 밝아진 뒤,
## 이동형 폴백) 둘 다 이 판정을 공유한다. 다른 컷신(엔딩/공범 대기) 도중엔
## 끼어들지 않는다.
## 우디(화병)/모카(커피)/로시(오징어)/이샤(자양강장제)/마르(꽃다발)처럼
## 대사 중에 {"type":"gift"} 줄로 아이템을 바로 지급하는 30 이벤트가 있다.
## InventoryManager는 자리가 없으면 그냥 push_warning만 하고 아이템을 조용히
## 버리는데, 30 이벤트는 한 번 보면 has_shown_heart_event()로 영원히 다시 안
## 뜨니 그 순간 인벤토리가 꽉 차 있으면 그 선물은 영구히 못 받는다(호감도 100
## 마일스톤과 같은 문제) - 발동 조건 자체에 인벤토리 여유를 포함시켜서 자리가
## 날 때까지 미룬다(사용자 지시, 2026-08-26 - "30이벤트에 물건 주는 애들
## 있어... 확인해야겠는데?").
func _heart_event_inventory_ok(event: Dictionary) -> bool:
	for line in event.get("lines", []) as Array:
		if line is Dictionary and String(line.get("type", "")) == "gift":
			var item_id := String(line.get("item_id", ""))
			if not item_id.is_empty() and not InventoryManager.can_add_item(item_id, 1):
				return false
	return true


func _find_matching_heart_event(map_id: String) -> Dictionary:
	if _murder_scene_active or _heart_event_active \
			or _accomplice_awaiting_mail_read or _accomplice_awaiting_door_open \
			or map_id == RESTAURANT_SIGN_MAP_ID:
		return {}
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		var event: Dictionary = NPCManager.get_heart_event_30(npc_id)
		if event.is_empty() or NPCManager.has_shown_heart_event(npc_id):
			continue
		if NPCManager.get_affection(npc_id) < HEART_EVENT_AFFECTION_THRESHOLD:
			continue
		# 애도/알리바이 대사가 밀려있는 NPC는 그게 최우선이어야 한다(사용자
		# 지시, 2026-08-26 - "이샤 이벤트 안보고 살인 일어났더니 애도는 안하고
		# 플로라 욕이나 하고 있네") - 그 대사를 실제로 봐서 소비될 때까지
		# 호감도 이벤트는 뒤로 미룬다.
		if MurderManager.has_pending_alibi_line(npc_id):
			continue
		if not _heart_event_inventory_ok(event):
			continue
		var anchor_state := String(event.get("anchor_state", ""))
		# anchor_state가 "지금 이 시간대엔 이 NPC가 정말 활동 중"이라는 대용
		# 조건 역할도 겸한다 - 로시(비 오는 날만)처럼 항상 뜨지 않는 NPC도
		# 자연스럽게 그 시간까지 기다리게 된다.
		if anchor_state.is_empty() or NPCManager.get_current_schedule_state(npc_id) != anchor_state:
			continue
		var anchor_pos: Dictionary = NPCManager.resolve_state_position(anchor_state)
		if String(anchor_pos.get("map_id", "")) != map_id:
			continue
		return {"npc_id": npc_id, "event": event}
	return {}


## 장소 이동형(벨제/플로라의 "같이 나가자")만 처리하는 폴백 - _load_map()의
## 화면이 이미 밝아진 뒤 호출된다(_prepare_heart_event()가 비-이동형을 전부
## 가로채서 여기까지 오는 건 실질적으로 이동형뿐임). 한 번에 하나만
## 트리거하고, 나머지는 다음 맵 진입 때 다시 검사한다.
func _maybe_trigger_heart_event(map_id: String) -> void:
	var match_result := _find_matching_heart_event(map_id)
	if not match_result.is_empty():
		await _play_heart_event(String(match_result["npc_id"]), match_result["event"])


## _prepare_heart_event()는 맵을 "새로 들어오는" 순간에만 검사한다 - 이미 그
## 맵 안에 서 있는 동안 호감도가 30을 넘으면(선물/디버그 단축키 등) 나갔다
## 다시 들어오기 전까진 영영 검사되지 않는 사각지대가 있었다(사용자 리포트,
## 2026-08-26 - "우디는 아예 호감도 이벤트가 발동이 안됐어"). 호감도 100
## 이벤트(_maybe_trigger_memento_event())와 같은 방식으로 매 프레임 다시
## 확인한다. 같은 자리(비-이동형)만 여기서 직접 처리 - 장소 이동형(벨제/
## 플로라)은 원래도 작업 장소에 "들어오는" 순간 _maybe_trigger_heart_event()가
## 잡아주므로 그대로 둔다(scene_map_id가 다르면 조용히 넘어간다).
func _maybe_trigger_live_heart_event() -> void:
	if _murder_scene_active or _heart_event_active or _memento_event_active or _revival_event_active \
			or _accomplice_awaiting_mail_read or _accomplice_awaiting_door_open \
			or _is_transitioning or _is_any_modal_open() or world_map == null or player == null:
		return
	var match_result := _find_matching_heart_event(GameManager.current_map_id)
	if match_result.is_empty():
		return
	var npc_id: String = match_result["npc_id"]
	var event: Dictionary = match_result["event"]
	var scene_map_id := String(event.get("scene_map_id", ""))
	if not scene_map_id.is_empty() and scene_map_id != GameManager.current_map_id:
		return
	var npc_spawn_position := world_map.get_spawn_position(String(event.get("npc_spawn", "")))
	var player_spawn_position := world_map.get_spawn_position(String(event.get("player_spawn", "")))
	if npc_spawn_position == Vector2.INF or player_spawn_position == Vector2.INF:
		return
	_heart_event_active = true
	if npc_world_manager != null:
		npc_world_manager.set_npc_sprite_hidden(npc_id, true)
	AudioManager.play_sfx(AudioManager.SFX_MEMORY)
	await _fade_out(HEART_EVENT_FADE_DURATION)
	var decoy: Node2D = _spawn_npc_decoy(npc_id, npc_spawn_position)
	await _fade_in(HEART_EVENT_FADE_DURATION)
	await player.walk_to(player_spawn_position, false)
	await _settle_after_heart_event_arrival(event, decoy.position)
	await _play_heart_event_dialogue(npc_id, event)
	await _finish_heart_event(npc_id, decoy)


## _load_map()이 화면을 다시 밝히기(_fade_in()) 직전에 부른다 - 같은 맵 안에서
## 끝나는 heart_event_30(대부분)은 NPC 숨김/분신 배치를 이 암전 상태에서 미리
## 끝내둬서, 화면이 밝아지는 순간 이미 그 자리에 서있는 것처럼 보이게 한다
## (사용자 지시, 2026-08-25 - "들어갈 때 페이드에서 이미 다 있어야지, 들어가고
## 나서 또 페이드하는 게 아니라"). 장소 이동형(scene_map_id가 anchor_state
## 위치와 다름)은 여기서 거른다 - 리드아웃 대사를 원래 근무지에서 먼저 보여줘야
## 해서 애초에 이 암전 전에 끝낼 수 없고, _maybe_trigger_heart_event()(화면
## 밝아진 뒤)가 그대로 처리한다. npc_spawn/player_spawn이 아직 tmx에
## 안 찍혀있으면 아무것도 안 하고 조용히 넘어간다(다음 기회에 재시도).
func _prepare_heart_event(map_id: String) -> void:
	_pending_heart_event = {}
	if world_map == null or player == null:
		return
	var match_result := _find_matching_heart_event(map_id)
	if match_result.is_empty():
		return
	var npc_id: String = match_result["npc_id"]
	var event: Dictionary = match_result["event"]
	var anchor_state := String(event.get("anchor_state", ""))
	var anchor_map_id := String(NPCManager.resolve_state_position(anchor_state).get("map_id", ""))
	var scene_map_id := String(event.get("scene_map_id", ""))
	if scene_map_id.is_empty():
		scene_map_id = anchor_map_id
	if scene_map_id != anchor_map_id:
		return
	var npc_spawn_position := world_map.get_spawn_position(String(event.get("npc_spawn", "")))
	var player_spawn_position := world_map.get_spawn_position(String(event.get("player_spawn", "")))
	if npc_spawn_position == Vector2.INF or player_spawn_position == Vector2.INF:
		return
	_heart_event_active = true
	if npc_world_manager != null:
		npc_world_manager.set_npc_sprite_hidden(npc_id, true)
	_pending_heart_event = {
		"npc_id": npc_id,
		"event": event,
		"player_spawn_position": player_spawn_position,
		"decoy": _spawn_npc_decoy(npc_id, npc_spawn_position),
	}


## _prepare_heart_event()가 암전 중에 미리 준비해둔 이벤트를 화면이 밝아진 뒤
## 실행한다 - 문에서 그 자리까지 플레이어가 걸어가는 모습만 화면이 보이는
## 채로 진행되고(사용자 지시, 2026-08-25), 나머지(대사/마무리 페이드)는 기존
## 방식과 같다.
func _run_pending_heart_event() -> void:
	var pending := _pending_heart_event
	_pending_heart_event = {}
	var npc_id: String = pending["npc_id"]
	var event: Dictionary = pending["event"]
	var decoy: Node2D = pending["decoy"]
	AudioManager.play_sfx(AudioManager.SFX_MEMORY)
	await player.walk_to(pending["player_spawn_position"], false)
	if decoy != null:
		await _settle_after_heart_event_arrival(event, decoy.position)
	await _play_heart_event_dialogue(npc_id, event)
	await _finish_heart_event(npc_id, decoy)


## 걸어서 도착한 직후 공통 처리 - 기본은 NPC 쪽을 정면으로 보되,
## event["player_facing"]("up"/"down"/"left"/"right")이 있으면 그 방향을
## 그대로 따른다(사용자 지시, 2026-08-26). 이후 도착 인지가 될 만큼 짧게 멈춘다.
func _settle_after_heart_event_arrival(event: Dictionary, npc_position: Vector2) -> void:
	var facing_override := String(event.get("player_facing", ""))
	if HEART_EVENT_FACING_DIRECTIONS.has(facing_override):
		player.facing_direction = HEART_EVENT_FACING_DIRECTIONS[facing_override]
	else:
		player.face_toward(npc_position)
	await get_tree().create_timer(HEART_EVENT_ARRIVE_PAUSE_SECONDS).timeout


## 두 흐름(비-이동형/이동형) 공통 마무리 - 분신 제거, 실제 NPC 복원, 페이드인.
## 완료 후 음표 이모지를 띄운다(사용자 지시, 2026-08-25 - "30 이벤트 끝날 때
## 하트 다음에 있는 음표 그림" - EMOTE_EXCITED가 실제로는 음표 그림이다).
## 페이드는 HEART_EVENT_FADE_DURATION(길게)을 써서 이벤트 느낌을 낸다
## (사용자 지시, 2026-08-26).
func _finish_heart_event(npc_id: String, decoy: Node2D) -> void:
	await _fade_out(HEART_EVENT_FADE_DURATION)
	if decoy != null:
		decoy.queue_free()
	if npc_world_manager != null:
		npc_world_manager.set_npc_sprite_hidden(npc_id, false)
	await _fade_in(HEART_EVENT_FADE_DURATION)
	NPCManager.request_emote(npc_id, NPCManager.EMOTE_EXCITED)
	_heart_event_active = false


## heart_event_30 중 장소 이동형(벨제/플로라, scene_map_id가 anchor_state
## 위치와 다른 경우) 전용 - 비-이동형(대부분)은 _prepare_heart_event()/
## _run_pending_heart_event()가 담당한다(위 두 함수 주석 참고). lead_out_lines를
## 원래 근무지에서 먼저 보여준 뒤 페이드 아웃 → _load_map()으로 이동(그 안에서
## 분신을 미리 배치하고 페이드 인) → 대사 → 마무리 페이드.
func _play_heart_event(npc_id: String, event: Dictionary) -> void:
	if world_map == null or player == null:
		return
	var anchor_state := String(event.get("anchor_state", ""))
	var anchor_map_id := String(NPCManager.resolve_state_position(anchor_state).get("map_id", ""))
	var scene_map_id := String(event.get("scene_map_id", ""))
	if scene_map_id.is_empty():
		scene_map_id = anchor_map_id
	if scene_map_id == anchor_map_id:
		return
	var npc_spawn_name := String(event.get("npc_spawn", ""))
	var player_spawn_name := String(event.get("player_spawn", ""))
	var dest_path := WorldMap.get_map_path(scene_map_id)
	if dest_path.is_empty():
		return
	var dest_spawns: Dictionary = WorldMap.parse_spawns(dest_path)
	if not dest_spawns.has(npc_spawn_name) or not dest_spawns.has(player_spawn_name):
		return
	# entry_spawn(예: 벨제=pasture_exit, 플로라=farm_exit - 원래 근무지에서
	# 평소 걸어 나오던 plaza2 워프 자리)이 있으면 거기서부터 이벤트 자리까지
	# 걸어가는 모습을 보여준다(사용자 지시, 2026-08-26 - "plaza2 out 워프자리에서부터
	# 스폰 지점 찍은곳까지 걸어가는 이동 씬이 없어"). 없거나 tmx에 없으면
	# 기존처럼 목적지에 바로 서있는 걸로 대체.
	var entry_spawn_name := String(event.get("entry_spawn", ""))
	var use_entry_walk := not entry_spawn_name.is_empty() and dest_spawns.has(entry_spawn_name)
	_heart_event_active = true
	AudioManager.play_sfx(AudioManager.SFX_MEMORY)
	var lead_out_lines: Array = (event.get("lead_out_lines", []) as Array).duplicate(true)
	if not lead_out_lines.is_empty() and dialogue_screen != null:
		dialogue_screen.open_special(npc_id, lead_out_lines, false)
		await dialogue_screen.closed
	if npc_world_manager != null:
		npc_world_manager.set_npc_sprite_hidden(npc_id, true)
	await _fade_out(HEART_EVENT_FADE_DURATION)
	await _load_map(scene_map_id, entry_spawn_name if use_entry_walk else player_spawn_name, true)
	var npc_spawn_position := world_map.get_spawn_position(npc_spawn_name)
	var decoy: Node2D = null
	if npc_spawn_position != Vector2.INF:
		decoy = _spawn_npc_decoy(npc_id, npc_spawn_position)
	await _fade_in(HEART_EVENT_FADE_DURATION)
	if use_entry_walk:
		var player_spawn_position := world_map.get_spawn_position(player_spawn_name)
		if player_spawn_position != Vector2.INF:
			await player.walk_to(player_spawn_position, false)
	if decoy != null:
		await _settle_after_heart_event_arrival(event, decoy.position)
	# 마린 전용 - 도착해서 자리 잡은 "다음"에만 잠깐 공을 주고받는다. 원래
	# 문에서 나오자마자(=걸어오는 내내) 차고 있어서 도착 전부터 공이 나오고
	# 걷는 시간만큼(체감 1분 가까이) 계속 차는 문제가 있었다(사용자 리포트,
	# 2026-08-26 - "플레이어가 스폰 지점에 갔을 때 공이 나와야지").
	if npc_id == MARIN_NPC_ID and decoy != null:
		var marin_ball := _spawn_marin_ball_bounce(player.position, decoy.position)
		await get_tree().create_timer(MARIN_BALL_MIN_VISIBLE_SECONDS).timeout
		_stop_marin_ball_bounce(marin_ball)
	await _play_heart_event_dialogue(npc_id, event)
	await _finish_heart_event(npc_id, decoy)


## emote(세이지의 말풍선 등)가 있으면 대사창을 열기 전에 잠깐 먼저 보여준다.
func _play_heart_event_dialogue(npc_id: String, event: Dictionary) -> void:
	var emote := String(event.get("emote", ""))
	if not emote.is_empty():
		NPCManager.request_emote(npc_id, emote)
		await get_tree().create_timer(0.6).timeout
	var lines: Array = (event.get("lines", []) as Array).duplicate(true)
	if dialogue_screen != null and not lines.is_empty():
		dialogue_screen.open_special(npc_id, lines, false)
		await dialogue_screen.closed
	NPCManager.mark_heart_event_shown(npc_id)


## 호감도 100(추억의 물건) 컷신 트리거 - heart_event_30(맵 진입 시 1회 검사)과
## 달리 매 프레임 근접 여부를 검사한다(사용자 지시, 2026-08-25). NPC가
## 스폰 좌표 없이 그 자리에서 실시간으로 다가오는 연출이라 "이 NPC가 지금
## 화면에 실제로 보이는가/얼마나 가까운가"를 프레임마다 알아야 하기 때문 -
## 성능 부담은 무시할 수준(맵당 NPC 몇 명, 거리 계산 하나뿐이고 이미 완료된
## NPC는 get_pending_memento_threshold()에서 바로 걸러짐 - _handle_npc_encounter()가
## 이미 똑같은 패턴으로 매 프레임 근접 판정을 하고 있음). "그 NPC의 공간 안"
## 위치 제한은 없앴다(사용자 지시, 2026-08-26 - "광장에서도 마주쳤을 때
## 뛰어오고 그런 게 필요하다") - 세이지/셰퍼드처럼 근무지 밖에서 마주쳐도
## 근접(MEMENTO_EVENT_PROXIMITY_TILES)만 만족하면 어디서든 터진다.
func _maybe_trigger_memento_event() -> void:
	if _murder_scene_active or _heart_event_active or _memento_event_active \
			or _accomplice_awaiting_mail_read or _accomplice_awaiting_door_open \
			or _is_transitioning or _is_any_modal_open() or npc_world_manager == null \
			or GameManager.current_map_id == RESTAURANT_SIGN_MAP_ID:
		return
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id):
			continue
		var threshold := NPCManager.get_pending_memento_threshold(npc_id)
		if threshold < 0:
			continue
		# heart_event_30과 같은 이유(위 _find_matching_heart_event() 참고) -
		# 애도/알리바이 대사가 밀려있으면 100 이벤트도 뒤로 미룬다.
		if MurderManager.has_pending_alibi_line(npc_id):
			continue
		if not InventoryManager.can_add_item("memento_%s" % npc_id, 1):
			continue
		var npc_position: Vector2 = npc_world_manager.get_active_npc_position(npc_id)
		if npc_position == Vector2.INF:
			continue
		if player.position.distance_to(npc_position) > MEMENTO_EVENT_PROXIMITY_TILES * WorldMap.TILE_SIZE:
			continue
		_play_memento_event(npc_id, threshold)
		return


## _fade의 색조를 바꾼다(알파는 그대로 유지) - 평소 페이드는 순검정이지만
## 호감도 100 컷신만 따뜻한 톤을 쓴다(_play_memento_event 참고). 컷신이 끝나면
## 반드시 다시 검정으로 되돌려야 다른 모든 전환(문/침대 등)이 정상으로 보인다.
func _set_fade_tint(color: Color) -> void:
	if _fade != null:
		_fade.color = Color(color.r, color.g, color.b, _fade.color.a)


## _maybe_trigger_memento_event()가 조건을 다 만족한 순간 자동 재생 - 스폰
## 좌표가 필요 없다(heart_event_30과 대조적). NPC가 실시간 좌표 기준으로
## 플레이어 한 칸 앞까지 걸어온 뒤(_memento_event_active가 켜져 있는 동안
## _is_any_modal_open()에 걸려서 이동/E/시간이 전부 자동으로 잠김) 따뜻한
## 톤의 짧은 페이드 → 기존 마일스톤 대사 → 건네는 순간 한 박자 정지 →
## consume_pending_milestone()(지급 + 기존 하트 이모지) → 그 위에 오래 지속되는
## 하트 이모지를 덧띄운다(사용자 지시: NPC가 다가옴/다른 톤 페이드/건넬 때
## 정지/이모지 롱테이크).
func _play_memento_event(npc_id: String, threshold: int) -> void:
	if world_map == null or player == null or npc_world_manager == null:
		return
	_memento_event_active = true
	AudioManager.play_sfx(AudioManager.SFX_MEMORY)
	# 갑자기 다가오는 게 어색하다는 지적(사용자 지시, 2026-08-26) - 이름을
	# 부르는 대사 대신 기존 "!" 이모트로 "발견하고 달려온다"는 느낌만 준다.
	NPCManager.request_emote(npc_id, NPCManager.EMOTE_EXCLAMATION)
	var npc_position: Vector2 = npc_world_manager.get_active_npc_position(npc_id)
	var approach_target := player.position
	if npc_position != Vector2.INF and not npc_position.is_equal_approx(player.position):
		approach_target = player.position + (npc_position - player.position).normalized() * MEMENTO_EVENT_APPROACH_DISTANCE
	await npc_world_manager.walk_npc_to_position(npc_id, approach_target)
	_set_fade_tint(MEMENTO_EVENT_FADE_TINT)
	await _fade_out(MEMENTO_EVENT_FADE_DURATION)
	await _fade_in(MEMENTO_EVENT_FADE_DURATION)
	_set_fade_tint(Color.BLACK)
	var milestone_lines: Array = NPCManager.get_milestone_dialogue(npc_id, threshold)
	if dialogue_screen != null and not milestone_lines.is_empty():
		dialogue_screen.open_special(npc_id, milestone_lines)
		await dialogue_screen.closed
	await get_tree().create_timer(MEMENTO_EVENT_GRANT_PAUSE_SECONDS).timeout
	NPCManager.consume_pending_milestone(npc_id)
	NPCManager.request_emote(npc_id, NPCManager.EMOTE_HEART, MEMENTO_EVENT_EMOTE_HOLD_SECONDS)
	await get_tree().create_timer(MEMENTO_EVENT_EMOTE_HOLD_SECONDS).timeout
	_memento_event_active = false


## 플레이어와 마린 사이를 반복해서 왕복하는 정지 이미지(공) 하나를 만든다 -
## 걷기 애니메이션 없이 위치만 튕기면 된다는 지시라 별도 스프라이트 시트 없이
## Sprite2D 하나 + Tween 왕복으로 충분하다.
func _spawn_marin_ball_bounce(from_position: Vector2, to_position: Vector2) -> Sprite2D:
	if world_map == null:
		return null
	var texture := InventoryManager.get_item_icon_texture(MARIN_BALL_ITEM_ID)
	if texture == null:
		return null
	var ball := Sprite2D.new()
	ball.texture = texture
	ball.z_index = MARIN_BALL_Z_INDEX
	ball.z_as_relative = false
	ball.position = from_position
	world_map.add_child(ball)
	_marin_ball_tween = create_tween()
	_marin_ball_tween.set_loops()
	_marin_ball_tween.tween_property(ball, "position", to_position, MARIN_BALL_BOUNCE_SECONDS)
	_marin_ball_tween.tween_property(ball, "position", from_position, MARIN_BALL_BOUNCE_SECONDS)
	return ball


func _stop_marin_ball_bounce(ball: Sprite2D) -> void:
	if _marin_ball_tween != null and _marin_ball_tween.is_valid():
		_marin_ball_tween.kill()
	_marin_ball_tween = null
	if ball != null:
		ball.queue_free()


## RevivalManager.soul_crystal_granted가 오면(도감 완성 + 엔딩 달성이 어느
## 순서로든 둘 다 채워진 순간) 호출된다(사용자 지시, 2026-08-25 - "지급
## 순간에도 특별 연출"). 엔딩 컷신/도감 화면 등 다른 화면과 겹칠 수 있어서
## 즉시 재생 가능한 상태가 아니면 대기 플래그만 세우고, _process()의
## _maybe_play_pending_soul_crystal_grant()가 안전한 타이밍에 대신 재생한다.
## RevivalManager.soul_crystal_granted가 오면(도감 완성 + 엔딩 달성이 어느
## 순서로든 둘 다 채워진 순간) 즉시 컷신을 틀지 않고 플래그만 세워둔다 -
## 사용자 지시(2026-08-25): "사용자가 잠에 들면 그 때 하고 싶은데. 잠에
## 들거나 기절했을 때 페이드되잖아. 그럼 n일차 뜨기 전에 컷씬이 나오는거지."
## 다음 취침/기절 전환(_play_sleep_transition/_play_collapse_transition)이
## 화면이 까매진 직후, "N일차" 라벨이 뜨기 전에 소비한다.
func _on_soul_crystal_granted() -> void:
	_pending_soul_crystal_grant_cutscene = true


## plaza5로 잠깐 넘어가서 신사에서 영혼이 날아올라 하늘로 사라지는 장면을
## 보여준다(사용자 지시, 2026-08-25 - "누우면 페이드되고, plaza5 맵을 다시
## 보여줘. 그리고 거기서 날아가는 장면"). 끝나면 다시 암전 상태로 남는다 -
## 호출부가 원래 있던 맵으로 되돌리는 걸 책임진다.
func _play_soul_crystal_flyout() -> void:
	await _load_map("plaza5", SOUL_CRYSTAL_SHRINE_EXIT_SPAWN, true)
	if world_map == null:
		return
	## plaza5는 영혼만 보이면 되는 장면이라 플레이어 캐릭터는 안 나와도 된다
	## (사용자 지시, 2026-08-25 - "신사 앞에 서있어서 말해봤어" - 실제로는 잠들어
	## 있으니 거기 서있는 게 어색함). 돌아가서 페이드인하기 직전에 다시 보이게
	## 한다.
	if player != null:
		player.visible = false
	## _load_map(..., skip_fade=true)는 화면을 안 밝혀준다 - 여기서 직접 밝히지
	## 않으면 plaza5가 다 준비돼도 화면은 계속 까만 채로 남아있어서 아무것도
	## 안 보이고 소리만 들린다(사용자 리포트, 2026-08-25 - "바다소리만 들리고
	## 맵은 하나도 안보여"). 이게 진짜 원인이었음.
	await _fade_in()
	## 화면 전환 직후 바로 애니메이션이 시작되면 뭐가 보이기도 전에 지나가
	## 버린다(사용자 지시, 2026-08-25 - "컷씬 너무 빨리 지나감") - plaza5가
	## 눈에 들어올 시간을 잠깐 준다.
	await get_tree().create_timer(SOUL_CRYSTAL_BEAT_SECONDS).timeout
	var start_position := world_map.get_spawn_position(SOUL_CRYSTAL_SHRINE_EXIT_SPAWN)
	if start_position == Vector2.INF:
		start_position = player.position if player != null else Vector2.ZERO
	var sprite := Sprite2D.new()
	sprite.texture = SOUL_CRYSTAL_SPRITE_TEXTURE
	sprite.z_index = SOUL_CRYSTAL_SPRITE_Z_INDEX
	sprite.z_as_relative = false
	world_map.add_child(sprite)
	sprite.position = start_position
	AudioManager.play_sfx(AudioManager.SFX_WIND)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "position", start_position + SOUL_CRYSTAL_FLYOUT_OFFSET, SOUL_CRYSTAL_FLYOUT_SECONDS)
	tween.tween_property(sprite, "modulate:a", 0.0, SOUL_CRYSTAL_FLYOUT_SECONDS * 0.5).set_delay(SOUL_CRYSTAL_FLYOUT_SECONDS * 0.5)
	await tween.finished
	sprite.queue_free()
	## 하늘로 사라진 뒤에도 한 박자 그대로 머문다 - 바로 암전하면 날아가는 걸
	## 보다가 화면이 뚝 끊기는 느낌이라.
	await get_tree().create_timer(SOUL_CRYSTAL_BEAT_SECONDS).timeout
	await _fade_out()
	if player != null:
		player.visible = true


## 플레이어가 있는 맵(집/병원)으로 돌아온 뒤, 잠든/기절한 플레이어 가슴팍으로
## 영혼이 내려와 스며드는 장면(사용자 지시 - "누워있는 플레이어 가슴팍에
## 스며드는거. 그리고 인벤에 들어와있고"). 화면이 이미 밝은 상태에서 호출한다 -
## 끝나면 영혼의 결정을 실제로 지급한다(RevivalManager.complete_soul_crystal_grant).
func _play_soul_crystal_merge() -> void:
	if player == null or world_map == null:
		return
	## 집/병원 화면이 밝아지자마자 바로 스며들면 "누워있는 나"를 인지할 틈이
	## 없다(사용자 지시, 2026-08-25 - "컷씬 너무 빨리 지나감") - 한 박자 쉰다.
	await get_tree().create_timer(SOUL_CRYSTAL_BEAT_SECONDS).timeout
	var sprite := Sprite2D.new()
	sprite.texture = SOUL_CRYSTAL_SPRITE_TEXTURE
	sprite.z_index = SOUL_CRYSTAL_SPRITE_Z_INDEX
	sprite.z_as_relative = false
	world_map.add_child(sprite)
	sprite.position = player.position + SOUL_CRYSTAL_MERGE_START_OFFSET
	AudioManager.play_sfx(AudioManager.SFX_WIND)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "position", player.position + SOUL_CRYSTAL_MERGE_END_OFFSET, SOUL_CRYSTAL_MERGE_SECONDS)
	tween.tween_property(sprite, "scale", Vector2(0.2, 0.2), SOUL_CRYSTAL_MERGE_SECONDS)
	tween.tween_property(sprite, "modulate:a", 0.0, SOUL_CRYSTAL_MERGE_SECONDS)
	await tween.finished
	sprite.queue_free()
	RevivalManager.complete_soul_crystal_grant()
	## 스며든 직후 바로 암전하지 않고 한 박자 머문다 - "됐다"는 여운.
	await get_tree().create_timer(SOUL_CRYSTAL_BEAT_SECONDS).timeout


## 화면을 몇 번 깜빡인다(사용자 지시 - "화면이 몇 번 깜빡이다가 밑에
## 나레이션"). 완전한 암전(_fade_out)과 달리 알파를 끝까지 안 올리고
## 몇 번 튕겨서 "번쩍"이는 느낌만 준다.
func _play_altar_flicker() -> void:
	if _fade == null:
		return
	for i in ALTAR_FLICKER_COUNT:
		var tween := create_tween()
		tween.tween_property(_fade, "color:a", ALTAR_FLICKER_PEAK_ALPHA, ALTAR_FLICKER_FLASH_SECONDS)
		tween.tween_property(_fade, "color:a", 0.0, ALTAR_FLICKER_FLASH_SECONDS)
		await tween.finished


## 제단(soul_altar) 상호작용(사용자 지시, 2026-08-25 재설계) - 세이지는 더 이상
## 등장하지 않는다. 효과음 + 화면 깜빡임 뒤, 대상 선택도 별도 UI 창이 아니라
## NPC 대화와 똑같은 하단 대사창에서 진행한다(사용자 지시 - "npc와 대화할
## 때처럼 하단에 고정된 부분에서... UI 창 같은 느낌이 아니라",
## dialogue_screen.gd의 DYNAMIC_CHOICE_TYPE 참고). ESC로 언제든 그냥 닫을 수
## 있다(대화창 기본 동작).
func _on_soul_altar_interacted() -> void:
	if world_map == null or player == null or not RevivalManager.can_use_altar() or dialogue_screen == null:
		return
	_revival_event_active = true
	_close_all_screens()
	AudioManager.play_sfx(AudioManager.SFX_MEMORY)
	_set_fade_tint(SOUL_ALTAR_FADE_TINT)
	await _play_altar_flicker()
	_set_fade_tint(Color.BLACK)
	var lines: Array = RevivalManager.get_narration("altar_prompt_narration").duplicate()
	var candidates: Array[String] = RevivalManager.get_revivable_victim_ids()
	if candidates.is_empty():
		var empty_text := RevivalManager.get_text("no_candidates_text")
		if not empty_text.is_empty():
			lines.append(empty_text)
	else:
		var options: Array = []
		for npc_id in candidates:
			options.append({
				"label": String(NPCManager.get_definition(npc_id).get("name", npc_id)),
				"callback": func() -> void: _on_revival_candidate_chosen(npc_id),
			})
		lines.append({"type": "dynamic_choice", "options": options})
	dialogue_screen.open_special("", lines)
	await dialogue_screen.closed
	_revival_event_active = false


## 부활 대상을 고른 직후 - 되돌릴 수 없는 선택이라 확인 선택지를 하나 더
## 이어붙인다(사용자 지시, 2026-08-25 - "확인 문구 있는 것도 좋네").
func _on_revival_candidate_chosen(npc_id: String) -> void:
	if dialogue_screen == null:
		return
	var npc_name := String(NPCManager.get_definition(npc_id).get("name", npc_id))
	var confirm_text := RevivalManager.get_text("confirm_text")
	confirm_text = (confirm_text if not confirm_text.is_empty() else tr("정말 {npc_name}을(를) 되살리시겠습니까?")).replace("{npc_name}", npc_name)
	dialogue_screen.push_lines([
		confirm_text,
		{
			"type": "dynamic_choice",
			"options": [
				{"label": "되살리기", "callback": func() -> void: _on_revival_confirmed(npc_id)},
				{"label": "취소", "callback": func() -> void: dialogue_screen.close()},
			],
		},
	])


## 되살린 직후 아무 반응이 없으면 "된 건지 만 건지" 알 수 없다는 지적(사용자
## 지시, 2026-08-25) - 화면을 한 번 더 깜빡인 뒤(다 끝날 때까지 기다렸다가 -
## fire-and-forget으로 던져두면 대화 선택 처리 흐름과 겹쳐 실제로 재생이
## 안 되는 경우가 있었음, 2026-08-26 사용자 리포트) 결과를 알려주는 짧은
## 나레이션을 이어 붙인다. 다 읽으면 평소처럼 마지막 줄에서 자동으로 닫힌다.
func _on_revival_confirmed(npc_id: String) -> void:
	InventoryManager.remove_item(RevivalManager.SOUL_CRYSTAL_ITEM_ID, 1)
	NPCManager.revive_npc(npc_id)
	RevivalManager.mark_revival_used(npc_id)
	## 깜빡이는 동안 방금 눌렀던 "정말 되살리시겠습니까?" 대사창이 그대로
	## 남아 보이면 안 된다는 지적(사용자 지시, 2026-08-26) - 대화창을 닫지는
	## 않고(잠금 유지) 잠깐 시각적으로만 숨긴다.
	if dialogue_screen != null:
		dialogue_screen.set_box_visible(false)
	await _play_altar_flicker()
	if dialogue_screen == null:
		return
	dialogue_screen.set_box_visible(true)
	var npc_name := String(NPCManager.get_definition(npc_id).get("name", npc_id))
	var lines: Array = RevivalManager.get_narration("revival_success_narration")
	if lines.is_empty():
		lines = ["제단의 빛이 서서히 사그라들었다.", tr("%s, 다시 이 마을로 돌아왔다.") % npc_name]
	else:
		lines = lines.duplicate()
		for i in lines.size():
			lines[i] = String(lines[i]).replace("{npc_name}", npc_name)
	dialogue_screen.push_lines(lines)


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
	for screen in [shop_screen, cooking_screen, computer_screen, collection_screen, dialogue_screen, status_screen, kitchen_screen, serving_screen, fishing_screen, book_screen, storage_screen, jukebox_screen, wardrobe_screen, minimap_screen]:
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
	## 공범 엔딩(_play_accomplice_mail_wait_beat)도 같은 노크 시퀀스를
	## 재사용하는데, 그때도 여기서 _knock_check_pending을 세우면 엔딩이 끝나고
	## 집을 나설 때 엉뚱하게 "아무도 없다" 반응이 뜬다(사용자 리포트,
	## 2026-08-26 - "엔딩 다 보고 나서 밖에 나오니까... 이거는 이벤트에만
	## 떠야돼"). 엔딩 노크 동안은 _suppress_knock_check_pending으로 막는다.
	if not _suppress_knock_check_pending:
		_knock_check_pending = true
	if dialogue_screen != null:
		dialogue_screen.open_special("", KNOCK_PLAYER_MONOLOGUE.duplicate())


## 그 밤 안에 나가서 확인하지 않으면(잠들었든, 기절해서 병원에 실려갔든)
## 하루가 지나 뜬금없이 반응이 뜨는 게 어색하다는 지적(사용자 리포트,
## 2026-08-24)으로, 날짜가 바뀌면 그 밤의 "확인 대기" 자체를 없던 일로
## 한다.
func _on_day_changed_clear_knock_check(_day: int, _weekday: String) -> void:
	_knock_check_pending = false


func _on_day_changed_clear_greetings(_day: int, _weekday: String) -> void:
	_greeted_today.clear()


func _on_day_changed_clear_closing_time_reminder(_day: int, _weekday: String) -> void:
	_closing_time_reminder_shown_today = false


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
	## 아무 창도 안 떠 있을 때 ESC를 누르면 게임 종료 확인창을 띄운다(사용자
	## 지시, 2026-09-01 - 플레이테스트 피드백 20번, "보통 ESC 눌러서 나가기
	## 때문에"). TAB 상태창 맨 아래 종료 버튼이 이미 여는 것과 같은 팝업을
	## 재사용한다(status_screen.gd의 QuitConfirmPopup) - "예"를 누르면 그
	## 팝업이 이미 현재 슬롯 저장 후 종료까지 처리한다. 컷신 진행 중에는 다른
	## 모달 열림 판정과 같은 기준(_murder_scene_active 등)으로 막는다.
	## _is_any_modal_open()이 아니라 _any_modal_open_last_frame(이전 프레임
	## 기준)을 보는 이유는 그 변수 선언부 주석 참고 - 같은 ESC 입력으로
	## 인벤토리 등이 먼저 닫히는 것과의 경쟁을 피하기 위함.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE \
			and status_screen != null and not _any_modal_open_last_frame and not _murder_scene_active \
			and not _heart_event_active and not _memento_event_active and not _revival_event_active:
		status_screen.open_quit_confirm()
		return
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


## 실제 로드된 WorldMap(HomeMap)의 자식으로 붙여 Y-sort 그룹에 참여시킨다
## (restaurant_dish_layer.gd와 같은 이유). 옷장은 책상들과 달리 YSortAnchor로
## 묶여있지 않아서 get_tile_sort_y()의 칸-반올림이 오히려 정렬 기준을 실제
## 밑변보다 아래로 밀어 항상 플레이어보다 앞에 그려지는 문제가 있었다(사용자
## 리포트, 2026-08-30) - player.gd/npc_sprite.gd와 같은 방식으로 밑변 Y좌표를
## 그대로 정렬 기준(position.y)으로 쓰도록 단순화.
## 우디 호감도 50 이벤트(옷장 고쳐주겠다는 약속)를 아직 못 봤으면 낡은 옷장
## 그림으로 새 옷장 타일을 덮고, 이벤트를 본 뒤엔 다시 지운다. EffectArea
## "closet"(Interactable의 "closet"과 이름은 같지만 다른 레이어라 충돌 없음)는
## 사용자가 Tiled에 직접 찍는다(집 레벨이 여러 개면 각 레벨마다 필요).
const CLOSET_OLD_EFFECT_AREA := "closet"
const CLOSET_OLD_TEXTURE := preload("res://assets/img/home/old_closet.png")
const CLOSET_OLD_Z_INDEX := 0

var _closet_old_sprite: Sprite2D = null


## 맵이 바뀌어도(WorldMap/HomeMap은 새로 만들지 않고 내용만 갈아끼우므로)
## 예전 맵에서 만든 스프라이트가 자식으로 그대로 남아있어서 엉뚱한 맵에서도
## 보이는 버그가 있었다(사용자 리포트, 2026-08-30 - "전맵에 다 나오고
## 있잖아") - 맵 로드마다 항상 지우고, 필요하면(이 맵에 closet EffectArea가
## 실제로 있을 때만) 새로 만든다.
func _update_closet_old_overlay() -> void:
	if _closet_old_sprite != null:
		_closet_old_sprite.queue_free()
		_closet_old_sprite = null
	if world_map == null or NPCManager.has_shown_event(WARDROBE_UNLOCK_NPC_ID, WARDROBE_UNLOCK_THRESHOLD):
		return
	var area := world_map.get_effect_area(CLOSET_OLD_EFFECT_AREA)
	if area.position == Vector2.INF:
		return
	var base := Vector2(area.position.x + area.size.x / 2.0, area.position.y + area.size.y)
	var sprite := Sprite2D.new()
	sprite.texture = CLOSET_OLD_TEXTURE
	sprite.z_index = CLOSET_OLD_Z_INDEX
	sprite.position = base
	sprite.offset = Vector2(0, -CLOSET_OLD_TEXTURE.get_height() / 2.0)
	world_map.add_child(sprite)
	_closet_old_sprite = sprite


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
	_maybe_trigger_memento_event()
	_maybe_trigger_live_heart_event()
	_maybe_show_closing_time_reminder()
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
		var talk_npc_id := String(_nearest_talkable_npc(player.position, _is_holding_gift()).get("npc_id", ""))
		_handle_npc_encounter(talk_npc_id)
		var npc_prompt := _npc_interact_prompt(talk_npc_id)
		if npc_prompt.is_empty():
			player.hide_interaction_prompt()
		elif _message_timer <= 0.0:
			player.show_interaction_prompt(npc_prompt)
		return
	_handle_npc_encounter("")
	## 기절해서 병원으로 실려간 경우(_play_collapse_transition, 워프 타일 체크를
	## 안 거치고 _load_map을 직접 부름) 대비 - 집에 있을 때만 잠그면, 병원에
	## 옮겨진 순간 자동으로 풀려서 병원 밖으로 못 나가는 소프트락을 피한다
	## (사용자 지적, 2026-08-24 - "기절해도 병원 안가? 워프차단하면").
	if _murder_scene_active:
		return
	if _accomplice_awaiting_mail_read and GameManager.current_map_id == ACCOMPLICE_MAIL_MAP_ID:
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
	if interactable_name != _last_prompt_interactable_name:
		_message_timer = 0.0
		_last_prompt_interactable_name = interactable_name
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
		## 레스토랑이 닫혀있으면 요리창 자체를 안 띄운다(재료를 넣어둔 채 닫으면
		## 영구히 못 꺼내던 문제, 사용자 지시 2026-08-29 - 플레이테스트 피드백
		## #43) - 다 익은 게 있으면 그 자리에서 바로 꺼낼 수 있게, 없으면(비어
		## 있거나 아직 조리 중) 프롬프트 자체를 안 띄워 상호작용이 안 된다는
		## 걸 알린다.
		if not RestaurantManager.is_open and not KitchenManager.is_ready(interactable_name):
			## "먼저 레스토랑을 열자" 임시 메시지(_show_temporary_message())가
			## player.show_interaction_prompt()로 그려지는데, 이 분기가
			## _message_timer를 안 보고 매 프레임 무조건 hide 시켜버려서 메시지가
			## 뜨자마자 바로 지워지고 있었다(사용자 리포트, 2026-09-05 - "레스토랑
			## 닫혀있으면 아예 조리대랑 상호작용이 안되네") - 메시지 표시 중에는
			## hide를 건너뛴다.
			if _message_timer <= 0.0:
				player.hide_interaction_prompt()
			return
		if _message_timer <= 0.0:
			var tool_name := KitchenManager.get_tool_name(interactable_name)
			if not RestaurantManager.is_open:
				player.show_interaction_prompt(tr("E %s에서 꺼내기") % tool_name if not tool_name.is_empty() else tr("E 꺼내기"))
			else:
				player.show_interaction_prompt(tr("E %s 사용") % tool_name if not tool_name.is_empty() else tr("E 조리하기"))
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
	if interactable_name == "closet":
		if _message_timer <= 0.0:
			player.show_interaction_prompt("E 옷장 열기")
		return
	if interactable_name == "furniture_desc":
		if _message_timer <= 0.0:
			## FURNITURE_DESC_ICON_PATH 자리에 16x16 그림이 채워지면 자동으로
			## 그 아이콘으로 바뀐다 - 그림이 없는 동안은 임시로 말풍선 이모지를
			## 대신 보여준다(show_interaction_icon() 참고).
			player.show_interaction_icon(FURNITURE_DESC_ICON_PATH, "💬")
		return
	if interactable_name == "soul_altar":
		## 영혼의 결정이 없거나 이미 부활을 썼으면 프롬프트 자체를 안 띄워서
		## 조용히 배경 오브젝트로 취급한다(사용자 지시, 2026-08-25).
		if RevivalManager.can_use_altar() and _message_timer <= 0.0:
			player.show_interaction_prompt("E 결정을 바친다")
		else:
			player.hide_interaction_prompt()
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
		if FishingManager.can_start_fishing() and _is_facing_water():
			## 가방에 자리가 있는지는 여기서 미리 안 본다 - E를 눌러서 실제로
			## 시작하지 못했을 때만 "가방이 가득 찼다."를 짧게 띄운다(사용자
			## 지시, 2026-09-01 - "E 낚시가 먼저 뜨고, 눌렀는데 안 되는 상태일
			## 때만 짧게 나오는 게 맞지"). 아래 실제 시작 처리(E 입력) 참고.
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 낚시하기")
			return
		var hunting_prompt := HuntingManager.get_interact_prompt(GameManager.current_map_id)
		if not hunting_prompt.is_empty():
			if _message_timer <= 0.0:
				player.show_interaction_prompt(hunting_prompt)
			return
		if not BerryBushManager.get_available_bush(player.position).is_empty():
			if _message_timer <= 0.0:
				player.show_interaction_prompt("E 채집")
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
		"untill":
			return "E 갈아엎기"
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
	elif not RestaurantManager.open_restaurant(_tutorial_awaiting_restaurant_open):
		_show_temporary_message(RESTAURANT_HOURS_MESSAGE)


## duration을 안 넘기면 기본 MESSAGE_DURATION(2초)을 쓴다 - 레스토랑 영업
## 상태 안내처럼 놓치면 아쉬운 메시지는 개별적으로 더 길게 줄 수 있게
## 파라미터로 뺐다(플레이테스트 피드백 #9, 2026-09-05 - "너무 짧게 뜬다").
func _show_temporary_message(text: String, duration: float = MESSAGE_DURATION) -> void:
	_message_timer = duration
	player.show_interaction_prompt(text)


## descriptions.json의 값은 문자열 하나 또는 문자열 배열 둘 다 지원한다(사용자
## 지시, 2026-08-29) - 배열이면 그 순서 그대로 전부 대화창의 여러 줄로
## 보여준다(E로 한 줄씩 넘김, dialogue_screen.open_description() 참고). 빈
## 문자열은 "아직 안 쓴 자리"로 보고 목록에서 제외한다(작업 중인 배열에 빈
## 칸이 섞여 있어도 안전하게 동작).
func _furniture_description_lines(entry: Variant) -> Array:
	if entry is Array:
		return (entry as Array).filter(func(line) -> bool: return String(line) != "")
	var text := String(entry)
	return [text] if not text.is_empty() else []


## .json은 원시 파일이라 FileAccess.file_exists() 규칙(day20 export 검증 참고,
## .png 등 import 리소스의 ResourceLoader.exists()와 반대)을 따른다.
func _load_tutorial_dialogue() -> void:
	if not FileAccess.file_exists(TUTORIAL_DIALOGUE_PATH):
		return
	var file := FileAccess.open(TUTORIAL_DIALOGUE_PATH, FileAccess.READ)
	if file == null:
		push_error("Tutorial dialogue could not be opened: %s" % TUTORIAL_DIALOGUE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_tutorial_dialogue = Localizer.apply_language(parsed, TUTORIAL_DIALOGUE_PATH) as Dictionary


## data/tutorial/intro_dialogue.json에 키가 없으면(파일 손상 등) 빈 배열 -
## dialogue_screen.open_special/open_description이 빈 배열이면 조용히
## PLACEHOLDER_LINES로 대체하므로 크래시 없이 안전하게 넘어간다.
func _tutorial_lines(key: String) -> Array[String]:
	var lines: Array[String] = []
	for line in (_tutorial_dialogue.get(key, []) as Array):
		lines.append(String(line))
	return lines


func _load_furniture_descriptions() -> void:
	if not FileAccess.file_exists(FURNITURE_DESCRIPTIONS_PATH):
		return
	var file := FileAccess.open(FURNITURE_DESCRIPTIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Furniture descriptions could not be opened: %s" % FURNITURE_DESCRIPTIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_furniture_descriptions = Localizer.apply_language(parsed, FURNITURE_DESCRIPTIONS_PATH) as Dictionary


func _is_any_modal_open() -> bool:
	return (shop_screen != null and shop_screen.modulate.a > 0.0) \
		or (cooking_screen != null and cooking_screen.modulate.a > 0.0) \
		or (computer_screen != null and computer_screen.modulate.a > 0.0) \
		or (collection_screen != null and collection_screen.modulate.a > 0.0) \
		or (dialogue_screen != null and dialogue_screen.modulate.a > 0.0) \
		or (sleep_confirm_popup != null and sleep_confirm_popup.modulate.a > 0.0) \
		or (pet_name_popup != null and pet_name_popup.modulate.a > 0.0) \
		or (status_screen != null and status_screen.modulate.a > 0.0) \
		or (restaurant_confirm_popup != null and restaurant_confirm_popup.modulate.a > 0.0) \
		or (kitchen_screen != null and kitchen_screen.modulate.a > 0.0) \
		or (serving_screen != null and serving_screen.modulate.a > 0.0) \
		or (fishing_screen != null and fishing_screen.modulate.a > 0.0) \
		or (livestock_confirm_popup != null and livestock_confirm_popup.modulate.a > 0.0) \
		or (book_screen != null and book_screen.modulate.a > 0.0) \
		or (storage_screen != null and storage_screen.modulate.a > 0.0) \
		or (jukebox_screen != null and jukebox_screen.modulate.a > 0.0) \
		or (wardrobe_screen != null and wardrobe_screen.modulate.a > 0.0) \
		or (minimap_screen != null and minimap_screen.modulate.a > 0.0) \
		or (status_screen != null and status_screen.is_quit_confirm_open()) \
		or _is_sleep_transition_playing


## _is_any_modal_open()과 같지만 kitchen_screen은 제외한다 - 위 함수 주석 참고.
func _should_pause_time() -> bool:
	## 공범 엔딩(사용자 지시, 2026-08-24 - "시간도 안 흐르고 집 밖으로 못
	## 나가게 하는 게 좋을 거 같은데") - 메일 대기/문 앞 대기 구간 내내 시간을
	## 멈춘다. 취침 강제(TimeManager.player_collapsed)가 이 구간에 끼어들
	## 여지 자체를 없앤다.
	if _accomplice_awaiting_mail_read or _accomplice_awaiting_door_open or _memento_event_active or _revival_event_active:
		return true
	if kitchen_screen != null and kitchen_screen.modulate.a > 0.0:
		return false
	return _is_any_modal_open()


## 요리창/상점창/인벤토리창 등 모달 창이 하나라도 열려있으면 플레이어 이동을
## 막고, 창 바깥(게임 월드) 위에 반투명 검은 막을 씌워 비활성 느낌을 준다.
## 시간 정지는 조리기구 화면(kitchen_screen)만 예외다 - 조리기구는 실제 시간
## 기준으로 돌아가는데(new_cooking_system.md 3.3), 화면을 열어둔 동안 게임
## 시간까지 멈추면 레스토랑 영업시간/NPC 스케줄이 그만큼 밀리는 게 사용자
## 피드백으로 어색하다고 확인됨 - 조리기구 화면만 열려있을 땐 시간이 계속 간다.
var _debug_last_open_screens := ""
## ESC로 "모달 없을 때 종료 확인"을 판단할 때 쓴다(main.gd._unhandled_input) -
## 그 자리에서 직접 _is_any_modal_open()을 불러서 비교하면, 인벤토리(TAB)처럼
## 자기 자신도 ESC로 닫히는 화면이 같은 키 입력에 대해 먼저 닫히고 난 뒤에
## (둘 다 _unhandled_input이라 한 이벤트에 여러 핸들러가 다 불림, 아무도
## set_input_as_handled()를 안 부름) 이 코드가 "이제 모달이 없네"로 잘못
## 판단해서 인벤토리를 닫자마자 종료 확인창까지 같이 떠버렸다(사용자 리포트,
## 2026-09-01 - "인벤 띄우고 esc 눌러도 종료하시겠습니까 팝업 나오는데").
## 매 프레임 끝에서 그 시점 상태를 저장해두고, ESC 핸들러는 이 "이전 프레임"
## 값을 보게 하면 같은 프레임 안에서의 경쟁이 사라진다.
var _any_modal_open_last_frame := false

func _update_ui_blocking() -> void:
	var any_open := _is_any_modal_open()
	## 상시 유지하는 디버그 로그(사용자 지시, 2026-08-30 - "지우지말고 두고두고
	## 쓰자") - 조리대 클릭 씹힘처럼 "어떤 화면이 열려있다고 잡히는지" 자체가
	## 의심스러운 UI 버그를 추적할 때 계속 도움이 됨. 어떤 화면들이 "열림"으로
	## 잡히는지 바뀔 때만 한 번 출력한다(매 프레임 스팸 방지).
	var open_names := []
	for entry in [
		["shop", shop_screen], ["cooking", cooking_screen], ["computer", computer_screen],
		["collection", collection_screen], ["dialogue", dialogue_screen], ["status", status_screen],
		["restaurant_confirm", restaurant_confirm_popup], ["kitchen", kitchen_screen],
		["serving", serving_screen], ["fishing", fishing_screen], ["livestock_confirm", livestock_confirm_popup],
		["book", book_screen], ["storage", storage_screen], ["jukebox", jukebox_screen],
		["wardrobe", wardrobe_screen], ["minimap", minimap_screen],
	]:
		var node: Control = entry[1]
		if node != null and node.modulate.a > 0.0:
			open_names.append(String(entry[0]))
	var joined := ",".join(open_names)
	if joined != _debug_last_open_screens:
		print("[DEBUG] open screens changed -> [", joined, "]")
		_debug_last_open_screens = joined
	# 낚싯줄이 나가 있는 동안(입질 대기 + 미니게임)은 모달 창이 없어도 이동을
	# 막는다 - 그래야 웜프 타일을 밟거나 맵을 벗어나는 상황 자체가 물리적으로
	# 발생하지 않아서, 낚시 도중 맵이 바뀌는 경우를 따로 취소 처리할 필요가 없다.
	if player != null:
		# 노크 소리가 나는 동안 문 앞으로 뛰쳐나가 확인할 수 없게 이동도 같이
		# 잠근다(사용자 지시, 2026-08-24). 호감도 100 컷신(_memento_event_active)도
		# 화면 디밍 없이 이동만 잠가야 해서 any_open과 별도로 확인한다(사용자
		# 지시, 2026-08-25 - "디밍 거슬릴 것 같다"). 살인 발견 씬(_murder_scene_active)/
		# 호감도 30 컷신(_heart_event_active)도 대사창이 안 떠 있는 타이머 대기
		# 구간(예: 2차 발견 씬 대사 사이 정지)에는 any_open만으론 안 걸려서
		# 그 사이에 플레이어가 자유롭게 걸어다닐 수 있었다(사용자 리포트,
		# 2026-08-26 - "2차 살인 컷씬이 진행되는 동안 플레이어가 움직이면
		# 안될 거 같아").
		player.set_movement_enabled(not any_open and not _memento_event_active and not _revival_event_active \
			and not _murder_scene_active and not _heart_event_active and not _tutorial_intro_locks_movement \
			and not FishingManager.is_active() and not HuntingManager.is_active() and not AudioManager.is_knock_playing())
	if _ui_dim != null:
		# furniture_desc(배경 가구 설명)는 박스 높이도 짧게 줄였는데, 화면
		# 전체를 덮는 디밍까지 그대로면 여전히 화면을 다 차지하는 느낌이라는
		# 지적(사용자 지시, 2026-08-29) - 위 memento_event_active와 같은
		# 이유로 이 경우만 디밍을 끈다.
		var showing_furniture_desc: bool = dialogue_screen != null and dialogue_screen.is_description_mode()
		_ui_dim.color.a = UI_DIM_ALPHA if (any_open and not showing_furniture_desc) else 0.0
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
	_any_modal_open_last_frame = any_open


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


## 튜토리얼 컷신 전용 - 상호작용(interactable) 이름으로 위치를 찾아 그 위에
## 노란 점멸 사각형을 띄운다. 한 번에 여러 지점(냄비+프라이팬)을 동시에
## 가리켜야 할 때가 있어서 이름 배열을 받는다 - 이미 켜져 있던 하이라이트는
## 먼저 정리하고 다시 만든다. world_map.get_interactable_position()이
## Vector2.INF를 돌려주면(아직 Tiled에 배치 안 된 지점) 그 이름만 조용히
## 건너뛴다.
func _set_tutorial_highlight(interactable_names: Array) -> void:
	_clear_tutorial_highlight()
	if world_map == null:
		return
	var image := Image.create(WorldMap.TILE_SIZE, WorldMap.TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(TUTORIAL_HIGHLIGHT_COLOR)
	var texture := ImageTexture.create_from_image(image)
	for interactable_name in interactable_names:
		var pos: Vector2 = world_map.get_interactable_position(String(interactable_name))
		if pos == Vector2.INF:
			push_warning("Tutorial highlight target is missing: %s" % interactable_name)
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = pos
		sprite.z_index = WorldMap.FLAT_Z_INDEX
		world_map.add_child(sprite)
		_tutorial_highlights.append(sprite)
	for sprite in _tutorial_highlights:
		var tween := create_tween()
		tween.set_loops()
		tween.tween_property(sprite, "modulate:a", TUTORIAL_HIGHLIGHT_DIM_ALPHA, TUTORIAL_HIGHLIGHT_PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(sprite, "modulate:a", 1.0, TUTORIAL_HIGHLIGHT_PULSE_DURATION).set_ease(Tween.EASE_IN_OUT)
		_tutorial_highlight_tweens.append(tween)


func _clear_tutorial_highlight() -> void:
	for tween in _tutorial_highlight_tweens:
		if tween != null:
			tween.kill()
	_tutorial_highlight_tweens.clear()
	for sprite in _tutorial_highlights:
		if is_instance_valid(sprite):
			sprite.queue_free()
	_tutorial_highlights.clear()


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
		and (equipped == "hoe" or equipped == "watering_can" or equipped == FarmingManager.GOLDEN_WATERING_CAN_ITEM_ID) \
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


## 오후 9시 이후엔 NPC 상점에 못 들어간다(사용자 지시, 2026-08-30) -
## ShopManager.get_shop_id_for_map()이 이미 "NPC맵=NPC가게" 등록 목록이라,
## 플레이어의 레스토랑/집은 애초에 그 목록에 없어서 자동으로 제외된다. 목장
## (belje_shop, pasture_interior)도 벨제/셰퍼드의 상점이라 예외 없이 똑같이
## 잠긴다 - 플레이어 자신의 가축 우리(LivestockManager 마구간)는 이 맵 워프
## 시스템과 무관한 별도 상호작용이라 애초에 이 잠금의 영향을 안 받는다
## (사용자 확인, 2026-08-30 - "자기 우리만 들어갈 수 있으면 돼").
const SHOP_TIME_LOCK_HOUR := 21
const SHOP_TIME_LOCK_MESSAGE := "시간이 너무 늦었다. 내일 오자."

func _is_shop_closed_for_night(map_id: String) -> bool:
	return not ShopManager.get_shop_id_for_map(map_id).is_empty() \
		and TimeManager.current_hour >= SHOP_TIME_LOCK_HOUR


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
	AudioManager.play_horror_sting(SHADOW_FIGURE_HORROR_STING_SECONDS)


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
		_update_closet_old_overlay()
		if map_id == RESTAURANT_SIGN_MAP_ID:
			_maybe_play_restaurant_frame_blood_effect()
		LivestockManager.set_world_map(world_map, map_id)
		FarmingManager.set_world_map(world_map, map_id)
		BerryBushManager.set_world_map(world_map, map_id)
		HuntingManager.set_world_map(world_map, map_id)
		StorageBoxManager.set_world_map(world_map, map_id)
		FurnitureManager.set_world_map(world_map, map_id)
		FloorDecorManager.set_world_map(world_map, map_id)
		WallDecorManager.set_world_map(world_map, map_id)
		if was_indoor != is_indoor:
			AudioManager.play_sfx(AudioManager.SFX_DOOR)
		_maybe_spawn_shadow_figure(map_id)
	# 화면이 아직 검은 이 시점에 heart_event_30(비-이동형) NPC 숨김/분신
	# 배치를 미리 끝내둔다 - 그래야 아래 _fade_in()으로 화면이 밝아지는 순간
	# 이미 그 자리에 서있는 것처럼 보인다(사용자 지시, 2026-08-25 - "들어갈 때
	# 페이드에서 이미 다 있어야지, 들어가고 나서 또 페이드하는 게 아니라").
	_prepare_heart_event(map_id)
	if not skip_fade:
		await _fade_in()
	if _knock_check_pending and was_home_interior and map_id == "Home":
		_knock_check_pending = false
		if dialogue_screen != null:
			dialogue_screen.open_special("", KNOCK_CHECK_RESULT_MONOLOGUE.duplicate())
	_is_transitioning = false
	if not _pending_heart_event.is_empty():
		_run_pending_heart_event()
	else:
		_maybe_trigger_heart_event(map_id)
	_maybe_show_mail_reminder(map_id)


## 튜토리얼이 없어서 컴퓨터/메일함 존재 자체를 못 찾을 수 있다는 우려(사용자
## 지시, 2026-08-25) - 안 읽은 메일이 있는 채로 집 안(home_interior, 컴퓨터가
## 있는 곳)에 들어올 때마다 머리 위에 짧게 알려준다. 마당(Home)에선 안 뜬다
## (사용자 지시 - "home_interior 들어갈 때만"). 도감은 늦게 발견해도 상관없지만
## 메일은 스토리 진행에 바로 필요해서 이것만 챙긴다. 다른 컷신이 막 시작됐으면
## 겹쳐 보이지 않게 건너뛴다.
func _maybe_show_mail_reminder(map_id: String) -> void:
	if map_id != "home_interior" or not EmailManager.has_unread():
		return
	## _revival_event_active는 제단 컷신 전용 플래그라 취침 중 영혼의 결정
	## 컷신(플레이어 가슴에 스며드는 연출)에는 안 걸렸었다 - 그 컷신은
	## _play_sleep_transition() 안에서 _load_map()을 호출하는데, 그때 여전히
	## "메일이 왔다"가 같이 떴다(사용자 리포트, 2026-08-26 - "불이 가슴 안으로
	## 들어올 때 메일이 왔다 뜬다"). _is_sleep_transition_playing은 그 컷신
	## 내내 켜져있으므로 이것도 같이 막는다 - 평소 취침은 애초에 _load_map을
	## 안 부르니 이 가드가 영향 줄 일이 없다.
	if _heart_event_active or _murder_scene_active or _memento_event_active or _revival_event_active or _is_sleep_transition_playing:
		return
	_show_temporary_message("메일이 왔다. 확인해보자.")


## 영업 종료 시간(RestaurantManager.CLOSE_HOUR)이 되면 RestaurantManager가
## 실제로 레스토랑을 자동으로 닫는다(close_restaurant() - is_open=false, 서빙
## 전 손님 퇴장) - 그 순간 레스토랑 안에 있었다면 바로 알려준다. 플레이어가
## 직접 팻말로 닫았을 땐 이 신호(TimeManager.restaurant_closed)가 아니라
## RestaurantManager.restaurant_closed만 뜨므로 여긴 안 걸린다(사용자 지시,
## 2026-08-27).
func _on_restaurant_auto_closed() -> void:
	if GameManager.current_map_id == RESTAURANT_SIGN_MAP_ID:
		_show_temporary_message(RESTAURANT_AUTO_CLOSED_MESSAGE, RESTAURANT_STATUS_MESSAGE_DURATION)


## 오늘 배정된 손님(RestaurantManager.DAILY_VISITOR_COUNT명 한도)을 전부
## 서빙하면 뜬다 - cook_and_serve()로만 트리거되므로 항상 레스토랑 안일 때만
## 불리지만, 다른 자동 메시지들과 동일하게 맵 확인은 방어적으로 남겨둔다.
func _on_all_visitors_served() -> void:
	if GameManager.current_map_id == RESTAURANT_SIGN_MAP_ID:
		_show_temporary_message(RESTAURANT_ALL_VISITORS_SERVED_MESSAGE, RESTAURANT_STATUS_MESSAGE_DURATION)


## 영업 종료 시간(RestaurantManager.CLOSE_HOUR)이 지났는데 레스토랑 안에 있고
## 아직 영업 중이면(직접 안 닫았으면 자동으로 안 닫힘) 하루에 한 번만 알려준다
## (사용자 지시, 2026-08-25 - "소리소문없이 닫혀서 플레이어가 모를 거 같다").
func _maybe_show_closing_time_reminder() -> void:
	if _closing_time_reminder_shown_today or GameManager.current_map_id != RESTAURANT_SIGN_MAP_ID:
		return
	if not RestaurantManager.is_open or TimeManager.current_hour < RestaurantManager.CLOSE_HOUR:
		return
	_closing_time_reminder_shown_today = true
	_show_temporary_message(RESTAURANT_CLOSING_TIME_MESSAGE, RESTAURANT_STATUS_MESSAGE_DURATION)


func _fade_out(duration: float = FADE_DURATION) -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, duration)
	await tween.finished


func _fade_in(duration: float = FADE_DURATION) -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, duration)
	await tween.finished


## 새 슬롯을 만들고 처음 게임에 들어온 순간(_ready()의 boot _load_map() 직후)
## 딱 한 번만 재생하는 튜토리얼 컷신(사용자 지시, 2026-09-01) -
## GameManager.tutorial_intro_shown이 신규 게임에서만 false로 시작한다(기존
## 세이브를 이어할 땐 항상 true라 여긴 그냥 지나감, game_manager.gd 참고).
## 실제 연출(대사/카메라 이동/NPC 배치 등)은 사용자가 직접 채울 예정이라,
## heart_event_30과 동일한 페이드 인/아웃 브래킷만 갖춘 자리표시자로 남겨둔다.
func _maybe_play_tutorial_intro() -> void:
	if GameManager.tutorial_intro_shown:
		return
	GameManager.tutorial_intro_shown = true
	if dialogue_screen == null or npc_world_manager == null or world_map == null:
		return
	## 레스토랑에 들어가기 전(인사~문 앞 이동)까지는 플레이어 직접 조작을
	## 막는다 - _get_move_direction()이 스크립트 이동(player.walk_to())은
	## _movement_enabled와 무관하게 항상 우선 처리하므로, 아래 player.walk_to()
	## 호출 자체는 이 락과 무관하게 정상 동작한다(player.gd 참고).
	_tutorial_intro_locks_movement = true
	await _fade_out(HEART_EVENT_FADE_DURATION)
	## 사용자 지시(2026-09-01) - 신규 게임 첫 화면에 "1일차" 카드가 안 뜨던
	## 문제. 취침/기절 전환(_play_sleep_transition/_play_collapse_transition)과
	## 동일한 구조(암전 -> N일차 표시 -> 대기 -> 숨김)를 튜토리얼 맨 앞으로
	## 당겨서 넣는다.
	if _day_label != null:
		_day_label.text = tr("%d일차") % TimeManager.current_day
		_day_label.modulate.a = 1.0
		await get_tree().create_timer(DAY_LABEL_HOLD_DURATION).timeout
		_day_label.modulate.a = 0.0
	npc_world_manager.set_npc_sprite_hidden(TUTORIAL_POLI_ID, true)
	## 가만히 서 있는 플레이어에게 폴리가 뛰어와서 도착하는 모습을 보여준다
	## (사용자 지시, 2026-09-01 - "가만히 있는 플레이어에게 뛰어오는 폴리
	## 모션이 없음") - 화면이 밝아진 뒤에 걷는 모습이 보여야 하므로, 분신은
	## 출발 지점에 세워만 두고 실제로 걷기 시작하는 건 fade_in 이후다.
	var decoy := _tutorial_spawn_decoy(TUTORIAL_POLI_ID, TUTORIAL_POLI_RUN_START_SPAWN)
	await _fade_in(HEART_EVENT_FADE_DURATION)
	if decoy != null:
		await _tutorial_walk_decoy_to_spawn(decoy, TUTORIAL_POLI_HOME_SPAWN)
	dialogue_screen.open_special(TUTORIAL_POLI_ID, _tutorial_lines("poli_greeting"), false)
	await dialogue_screen.closed
	## 플레이어 자유 이동이 아니라 컷신이 직접 문 앞까지 걸어가게 한다(사용자
	## 지시, 2026-09-01 - "플레이어 자유 이동이 아니라 알아서 컷씬 이벤트로
	## 이동 되어야됨"). 폴리도 같은 타이밍에 같은 문으로 같이 걸어가게 해서
	## "바로 뒤따라서 들어옴"을 재현한다 - 폴리 쪽은 await 안 하고 먼저
	## 걷기 시작만 시켜서 플레이어와 거의 동시에 도착하게 한다.
	if decoy != null and is_instance_valid(decoy):
		var decoy_path: PackedVector2Array = world_map.find_path(decoy.position, TUTORIAL_PLAYER_DOOR_POSITION)
		decoy.call("walk_to", decoy_path)
	await player.walk_to(TUTORIAL_PLAYER_DOOR_POSITION, false)
	## 플레이어가 먼저 도착해도 폴리가 아직 문 앞까지 안 왔으면 잠깐 기다렸다가
	## 맵을 넘긴다(사용자 지시, 2026-09-01 - "폴리가 레스토랑 문 앞에 오기
	## 전까지 레스토랑 들어가지마").
	if decoy != null and is_instance_valid(decoy):
		var wait_elapsed := 0.0
		while bool(decoy.call("is_walking")) and wait_elapsed < TUTORIAL_DECOY_WALK_TIMEOUT_SECONDS:
			await get_tree().create_timer(TUTORIAL_POLL_INTERVAL_SECONDS).timeout
			wait_elapsed += TUTORIAL_POLL_INTERVAL_SECONDS
		decoy.queue_free()
	await _load_map(RESTAURANT_SIGN_MAP_ID, TUTORIAL_RESTAURANT_ENTRANCE_SPAWN)
	## 레스토랑 안으로 들어온 뒤부터는 냄비/프라이팬/완성대를 직접 찾아가야
	## 하므로 여기서 조작 잠금을 푼다. 대신 요리/서빙이 끝날 때까지 밖으로
	## 나가는 것 자체는 계속 막는다(_tutorial_locks_restaurant_exit 참고).
	_tutorial_intro_locks_movement = false
	_tutorial_locks_restaurant_exit = true
	## 진짜 원인을 찾음(사용자 지시, 2026-09-02 - "레스토랑 열어서 확인했는데
	## 일반 npc들 안사라져 튜토리얼 컷신에서만 사라지는거야") - _load_map()이
	## 맵을 바꾸면 NPCWorldManager._populate_initial()이 모든 NPC를 훑으며
	## "마지막으로 추적된 맵 != 지금 맵"이면 스프라이트를 그냥 지워버린다.
	## 폴리는 숨겨진 채 계속 Home으로 추적되고 있었어서 방금 그 체크에 걸려
	## 스프라이트가 파괴됐던 것 - 이후 set_npc_sprite_hidden(false)를 불러도
	## 이미 없는 노드라 아무 일도 안 일어났다. 일반 손님이 안 그런 건 한 번도
	## 숨겨진 적이 없어서 추적이 안 끊겼기 때문. plant_npc_at()으로 추적
	## 상태와 스프라이트를 지금 이 자리에 다시 심어서 근본 원인을 고친다.
	## 문 앞에서 기다리는 분신은 스폰 좌표가 벽 위/안쪽에 겹쳐서 어색하게 서
	## 있는 모습이 됐다(사용자 지시, 2026-09-02 - "레스토랑 열기 전까지는
	## 폴리가 안보여야할거같아 벽에 서있어") - 개점 전까지는 아예 안 보이게
	## 두고, 개점하는 순간 실제 시스템이 문에서부터 자리까지 걸어오는 모습을
	## 처음 보여주는 것으로 단순화한다.
	var entrance_position := world_map.get_spawn_position(TUTORIAL_POLI_RESTAURANT_SPAWN)
	if entrance_position != Vector2.INF:
		npc_world_manager.plant_npc_at(TUTORIAL_POLI_ID, RESTAURANT_SIGN_MAP_ID, entrance_position, true)
	dialogue_screen.open_description(_tutorial_lines("open_hint"))
	await dialogue_screen.closed
	## 게임이 09:00에 시작하는데 정식 영업시간(10시)까지 기다리게 하면 튜토리얼이
	## 막힌다는 지적(사용자 지시, 2026-09-01) - 이 하이라이트가 켜져 있는 동안만
	## _on_restaurant_confirmed()가 영업시간 제한을 건너뛰게 한다. 그리고 방문객
	## 자동 추첨/착석도 꺼서(RestaurantManager.suppress_auto_visitors) 튜토리얼
	## 도중에 엉뚱한 손님이 같이 들어오지 않게 한다(사용자 지시 - "튜토일때는
	## 레스토랑 열어도 손님 안오게 해줘"). 둘 다 튜토리얼이 끝날 때 되돌린다.
	_tutorial_awaiting_restaurant_open = true
	RestaurantManager.suppress_auto_visitors = true
	_set_tutorial_highlight([TUTORIAL_SIGN_INTERACTABLE])
	await RestaurantManager.restaurant_opened
	_tutorial_awaiting_restaurant_open = false
	_tutorial_locks_restaurant_close = true
	_clear_tutorial_highlight()
	## plant_npc_at()로 추적이 이미 이 맵(entrance 좌표)에 정확히 심어져 있으니,
	## 이제 정식 착석 시스템(force_seat_npc -> NPCManager 재조정)이 매일 오는
	## 손님과 완전히 같은 경로로 문 앞에서 자리까지 실제로 걸어가게 둔다.
	## 개점 전까지 숨겨뒀던 걸 여기서 처음 보여준다.
	npc_world_manager.set_npc_sprite_hidden(TUTORIAL_POLI_ID, false)
	RestaurantManager.force_seat_npc(TUTORIAL_POLI_STATION_INDEX, TUTORIAL_POLI_ID)
	## 평소 손님은 실제 크로스맵 이동(_complete_current_hop -> notify_npc_entered_map)이
	## 문에 도착하는 순간 종을 울리는데, 폴리는 plant_npc_at()/force_seat_npc()로
	## 직접 배치돼서 그 이동 경로를 안 타 종이 안 울렸다(사용자 리포트,
	## 2026-09-05 - "튜토에서 폴리 들어올 때 띵동 소리 안나"). 방금 자리를
	## 배정했으니 get_seated_station()이 바로 유효해서 여기서 직접 불러도 된다.
	## notify_npc_entered_map() 자체가 좌석당 1회만 실제로 울리도록 막혀있어서
	## (restaurant_manager.gd _seat_npc()/_station_entry_notified 참고) 이 호출과
	## 스케줄 재조정이 우연히 만들어내는 자연 재진입이 겹쳐도 중복으로 울리지
	## 않는다.
	RestaurantManager.notify_npc_entered_map(TUTORIAL_POLI_ID)
	while not RestaurantManager.is_station_npc_settled(TUTORIAL_POLI_STATION_INDEX):
		await get_tree().create_timer(TUTORIAL_POLL_INTERVAL_SECONDS).timeout
	dialogue_screen.open_special(TUTORIAL_POLI_ID, _tutorial_lines("poli_seated"), false)
	await dialogue_screen.closed
	## 오직 튜토리얼에서만 지급하는 재료(사용자 지시) - 감자는 냄비(cooking_area1),
	## 고등어는 프라이팬(cooking_area2)에서만 조리 가능하다(cooking_stations.json).
	InventoryManager.add_item(TUTORIAL_RAW_POTATO_ID, 1)
	InventoryManager.add_item(TUTORIAL_RAW_MACKEREL_ID, 1)
	_set_tutorial_highlight([TUTORIAL_POT_STATION])
	while not KitchenManager.is_busy(TUTORIAL_POT_STATION):
		await get_tree().create_timer(TUTORIAL_POLL_INTERVAL_SECONDS).timeout
	_set_tutorial_highlight([TUTORIAL_PAN_STATION])
	while not KitchenManager.is_busy(TUTORIAL_PAN_STATION):
		await get_tree().create_timer(TUTORIAL_POLL_INTERVAL_SECONDS).timeout
	_clear_tutorial_highlight()
	## KitchenManager.is_ready()는 수거하는 순간 다시 false로 돌아간다 - 두
	## 기구가 거의 동시에 다 됐을 때 플레이어가 한쪽을 먼저 수거해버리면
	## "둘 다 동시에 ready인 순간"이 폴링(0.2초 간격)에 안 걸려서 무한 대기에
	## 빠졌다(사용자 리포트, 2026-09-02 - "재료 두 개 다 수급했는데 요리
	## 상호작용이 깜빡이질 않아"). is_ready 게이트를 없애고 인벤토리 보유
	## 여부만으로 판정한다 - 각 기구가 다 익기 전에 하이라이트가 살짝 일찍
	## 켜질 수는 있지만(대기 시간 자체를 숨기진 못함), 수거 순서와 무관하게
	## 항상 정확히 끝난다.
	_set_tutorial_highlight([TUTORIAL_POT_STATION, TUTORIAL_PAN_STATION])
	while not (InventoryManager.has_item(TUTORIAL_COOKED_POTATO_ID, 1) and InventoryManager.has_item(TUTORIAL_COOKED_MACKEREL_ID, 1)):
		await InventoryManager.inventory_changed
	_set_tutorial_highlight([TUTORIAL_SERVING_STATION])
	while true:
		await RestaurantManager.dish_served
		if RestaurantManager.get_station_npc(TUTORIAL_POLI_STATION_INDEX) == TUTORIAL_POLI_ID \
				and not RestaurantManager.get_station_dish(TUTORIAL_POLI_STATION_INDEX).is_empty():
			break
	_clear_tutorial_highlight()
	## 실제 자동 완료 타이머(RestaurantManager._on_minute_passed)가 식사를 끝내며
	## 자리를 비우는 순간, 분신으로 자리를 지켜서 대사가 뜨기 전에 폴리가 먼저
	## 걸어 나가버리는 것처럼 보이지 않게 한다(사용자 지시 - "폴리가 다 먹을
	## 때까지 잠시 대기... 다 먹으면 바로 자리를 뜨지 않고, 대사가 먼저 뜸").
	var seat_state := NPCManager.resolve_state_position("restaurant_seat%d" % (TUTORIAL_POLI_STATION_INDEX + 1))
	var seat_position: Vector2 = seat_state.get("position", Vector2.INF)
	var eating_decoy: Node2D = null
	if seat_position != Vector2.INF:
		npc_world_manager.set_npc_sprite_hidden(TUTORIAL_POLI_ID, true)
		eating_decoy = _spawn_npc_decoy(TUTORIAL_POLI_ID, seat_position)
		## 정식 레스토랑 손님은 RestaurantManager.dish_served -> npc_world_manager.gd의
		## start_eating() 연결로 자동으로 먹는 모션이 나오는데, 이 분신은 그
		## 신호 체계 밖에서 직접 만든 별도 NPCSprite라 같은 신호를 못 받는다 -
		## 여기서 직접 걸어줘야 한다(사용자 리포트, 2026-09-05 - "튜토에서
		## 폴리가 먹는 행동도 안해").
		if eating_decoy != null:
			eating_decoy.call("start_eating")
	while true:
		await RestaurantManager.npc_departed
		if RestaurantManager.get_station_npc(TUTORIAL_POLI_STATION_INDEX).is_empty():
			break
	dialogue_screen.open_special(TUTORIAL_POLI_ID, _tutorial_lines("poli_farewell"), false)
	await dialogue_screen.closed
	dialogue_screen.open_description(_tutorial_lines("mail_hint"))
	await dialogue_screen.closed
	## 여기서부터 실제 관리 스프라이트를 되돌린다 - 평소 스케줄로 복귀하며
	## 걸어 나가는 모습이 그대로 "폴리가 나가는 애니메이션"이 된다.
	if eating_decoy != null and is_instance_valid(eating_decoy):
		eating_decoy.queue_free()
	npc_world_manager.set_npc_sprite_hidden(TUTORIAL_POLI_ID, false)
	## 튜토리얼 동안 영업시간을 무시하고 강제로 열어뒀던 레스토랑을 정리한다
	## (사용자 지시, 2026-09-01 - "튜토 끝나면 레스토랑 닫아줘"). 방문객 억제도
	## 같이 풀어서 이후로는 평소처럼 정상 영업/방문객 추첨이 동작하게 한다.
	RestaurantManager.suppress_auto_visitors = false
	_tutorial_locks_restaurant_close = false
	_tutorial_locks_restaurant_exit = false
	if RestaurantManager.is_open:
		RestaurantManager.close_restaurant()


## _maybe_play_tutorial_intro() 전용 헬퍼 - 지정한 스폰 지점에 분신을 세운다.
## 스폰 지점이 아직 Tiled에 배치되지 않았으면(Vector2.INF) 경고만 남기고
## null을 돌려준다 - 씬 전체가 멈추면 안 되므로 조용히 건너뛴다.
func _tutorial_spawn_decoy(npc_id: String, spawn_name: String) -> Node2D:
	var spawn_position := world_map.get_spawn_position(spawn_name)
	if spawn_position == Vector2.INF:
		push_warning("Tutorial spawn point is missing: %s" % spawn_name)
		return null
	var decoy := _spawn_npc_decoy(npc_id, spawn_position)
	## npc_sprite.gd의 _process()는 TimeManager.is_running이 false면(대사창 등
	## 모달이 열려있는 동안 자동으로 멈춘다) _ignore_time_pause가 아닌 이상
	## 걷기/애니메이션을 아예 처리하지 않는다 - 튜토리얼 분신은 대사창이 뜬
	## 직후에도 걸어야 하므로 항상 무시하게 한다(사용자 리포트, 2026-09-01 -
	## "한 5초있다가 폴리가 정한 지점으로 순간이동하는데" - 멈춰있다가
	## _tutorial_walk_decoy_to_spawn()의 타임아웃 snap_to로만 넘어간 것).
	if decoy != null:
		decoy.call("set_ignore_time_pause", true)
	return decoy


## _maybe_play_tutorial_intro() 전용 헬퍼 - 분신을 지정한 스폰 지점까지 실제로
## 걸어가게 한다(usher_decoy 걷기 대기 - _play_accomplice_ending_sequence()
## 근방 - 와 동일한 패턴). 목표 스폰이 없으면 조용히 넘어간다. 길찾기가
## 실패하거나(장애물에 막혀 find_path()가 빈 경로를 돌려주면 walk_to()가
## 즉시 멈춤) 타임아웃에 걸려도, 마지막에 무조건 target으로 snap_to해서
## "도착 안 했는데 다음 대사가 먼저 뜨는" 상황이 안 생기게 한다(사용자 리포트,
## 2026-09-01 - "폴리가 지점에 도착 안했는데 대사 재생됨").
func _tutorial_walk_decoy_to_spawn(decoy: Node2D, spawn_name: String) -> void:
	var target := world_map.get_spawn_position(spawn_name)
	if target == Vector2.INF:
		push_warning("Tutorial spawn point is missing: %s" % spawn_name)
		return
	await _tutorial_walk_decoy_to_position(decoy, target)


## _tutorial_walk_decoy_to_spawn()의 좌표 버전 - restaurant_seatN처럼
## Spawn 오브젝트가 아니라 NPCManager.resolve_state_position()으로 얻는
## 좌표까지 걸어갈 때 쓴다.
func _tutorial_walk_decoy_to_position(decoy: Node2D, target: Vector2) -> void:
	var path: PackedVector2Array = world_map.find_path(decoy.position, target)
	decoy.call("walk_to", path)
	var elapsed := 0.0
	while bool(decoy.call("is_walking")) and elapsed < TUTORIAL_DECOY_WALK_TIMEOUT_SECONDS:
		await get_tree().create_timer(TUTORIAL_POLL_INTERVAL_SECONDS).timeout
		elapsed += TUTORIAL_POLL_INTERVAL_SECONDS
	decoy.call("snap_to", target)
	decoy.call("face_down")


## 침대 확인창에서 "예"를 고르면 화면을 잠깐 까맣게 만들고 그 위에 "N일차"를
## 띄워서 실제로 하루가 지났다는 걸 체감시킨다 - 날짜 자체는 화면이 완전히
## 까매진 다음 TimeManager.sleep_now()로 넘긴다(글자에 찍히는 날짜가 항상
## 넘어간 다음 날짜가 되도록).
func _play_sleep_transition() -> void:
	_is_sleep_transition_playing = true
	await _fade_out()
	## 인벤토리가 꽉 차있으면 지급이 조용히 실패하고 이 기회를 영영 날린다
	## (npc_manager.gd의 추억의 물건 inventory_ok 체크와 같은 이유 - 사용자
	## 지시, 2026-08-25 - "인벤이 가득차면 이거 어떻게 받아?"). 자리가 없으면
	## 플래그를 그대로 남겨둬서 다음 취침 때 다시 시도한다.
	var played_soul_crystal_cutscene := false
	if _pending_soul_crystal_grant_cutscene and InventoryManager.can_add_item(RevivalManager.SOUL_CRYSTAL_ITEM_ID, 1):
		_pending_soul_crystal_grant_cutscene = false
		played_soul_crystal_cutscene = true
		await _play_soul_crystal_flyout()
		## SOUL_CRYSTAL_HOME_RETURN_SPAWN 자리에 정확히 눕혀서 세운다(사용자
		## 지시, 2026-08-25 - "정확히 침대 안이 아니다보니까 이상하게 보이네.
		## 좌표 찍어서 정면을 보고 있게") - _load_map()이 스폰을 찾으면
		## player.position/카메라를 알아서 맞춰주므로 따로 복원 안 해도 된다.
		await _load_map(SOUL_CRYSTAL_HOME_RETURN_MAP_ID, SOUL_CRYSTAL_HOME_RETURN_SPAWN, true)
		player.facing_direction = Vector2i(0, 1)
		await _fade_in()
		await _play_soul_crystal_merge()
		await _fade_out()
	TimeManager.sleep_now()
	if _day_label != null:
		_day_label.text = tr("%d일차") % TimeManager.current_day
		_day_label.modulate.a = 1.0
	await get_tree().create_timer(DAY_LABEL_HOLD_DURATION).timeout
	if _day_label != null:
		_day_label.modulate.a = 0.0
	await _fade_in()
	## 지급 컷신이 있었던 날 아침에만 짧은 여운을 남긴다(사용자 지시, 2026-08-25 -
	## "...무슨 꿈이었지?"). 이 대사가 다 끝날 때까지 기다렸다가 메일 알림을
	## 띄운다 - 안 그러면 컷신 도중 로드된 home_interior에서 "메일이 왔다"가
	## 몰입 깨면서 겹쳐 떴다(사용자 지시, 2026-08-25 - "나레이션 끝나고 뜨게").
	if played_soul_crystal_cutscene and dialogue_screen != null:
		dialogue_screen.open_special("", SOUL_CRYSTAL_WAKE_UP_MONOLOGUE.duplicate())
		await dialogue_screen.closed
	## 평소 취침(침대 상호작용)은 _load_map()을 안 부르고 제자리에서 시간만
	## 넘기므로, _load_map() 끝에 붙어있는 _maybe_show_mail_reminder()가 한
	## 번도 안 불려서 기상 시점엔 알림이 안 떴다 - 다음에 home_interior를
	## 나갔다 들어와야만 뒤늦게 떴다(플레이테스트 피드백 #15, 2026-09-05 -
	## "처음 일어날 때도 메일 왔다는 알림이 떠야 함"). 소울 크리스탈 컷신
	## 유무와 무관하게 기상 직후 여기서 한 번 확인한다 - _maybe_show_mail_reminder()
	## 자체가 _is_sleep_transition_playing 중엔 안 뜨게 막아뒀으므로(컷신과 겹침
	## 방지), 이 플래그부터 내린 뒤에 불러야 한다.
	_is_sleep_transition_playing = false
	_maybe_show_mail_reminder("home_interior")


## 24:00까지 스스로 취침하지 않았을 때(TimeManager.player_collapsed) - 취침
## 연출(_play_sleep_transition)과 같은 구조(페이드아웃 -> "N일차" 표시 ->
## 페이드인)를 쓰되, 그 사이에 병원으로 맵을 옮기고 디버프를 건다.
func _play_collapse_transition() -> void:
	_is_sleep_transition_playing = true
	await _fade_out()
	## 인벤토리 자리 없으면 다음 기회로 미룬다(_play_sleep_transition() 참고).
	var granting_soul_crystal := _pending_soul_crystal_grant_cutscene and InventoryManager.can_add_item(RevivalManager.SOUL_CRYSTAL_ITEM_ID, 1)
	if granting_soul_crystal:
		_pending_soul_crystal_grant_cutscene = false
		await _play_soul_crystal_flyout()
	await _load_map(HOSPITAL_MAP_ID, HOSPITAL_WAKE_SPAWN, true)
	player.apply_speed_effect(COLLAPSE_DEBUFF_PERCENT, COLLAPSE_DEBUFF_MINUTES, true)
	if granting_soul_crystal:
		await _fade_in()
		await _play_soul_crystal_merge()
		await _fade_out()
	if _day_label != null:
		_day_label.text = tr("%d일차") % TimeManager.current_day
		_day_label.modulate.a = 1.0
	await get_tree().create_timer(DAY_LABEL_HOLD_DURATION).timeout
	if _day_label != null:
		_day_label.modulate.a = 0.0
	await _fade_in()
	if granting_soul_crystal and dialogue_screen != null:
		dialogue_screen.open_special("", SOUL_CRYSTAL_WAKE_UP_MONOLOGUE.duplicate())
	_is_sleep_transition_playing = false


func _on_interact_pressed() -> void:
	if world_map == null or player == null:
		return
	# 대화창 등 모달이 이미 열려있으면 E는 그 창 자신의 _unhandled_input이
	# 처리한다(대화 넘기기 등) - 여기서 또 월드 상호작용(계산대/조리대 등)까지
	# 같이 처리하면, NPC가 자기 근무지 바로 옆에 서 있을 때 대화 넘기려고 누른
	# E가 계산대까지 같이 눌러버리는 문제가 생긴다.
	if _is_any_modal_open() or _murder_scene_active or _heart_event_active or _memento_event_active or _revival_event_active:
		return
	# 조준 바가 떠 있는 동안 E는 다른 무엇보다 먼저 포획 시도 판정으로
	# 간다(낚시의 is_waiting_for_bite() 우선 처리와 동일한 이유 - 안 그러면
	# 동물 위에 겹친 다른 상호작용이 먼저 먹어버릴 수 있음).
	if HuntingManager.is_aiming():
		HuntingManager.attempt_catch()
		return
	if _second_murder_sack_awaiting_interaction and _second_murder_sack_node != null \
			and player.position.distance_to(_second_murder_sack_position) <= SECOND_MURDER_SACK_INTERACT_RADIUS:
		_continue_second_murder_discovery()
		return
	var interactable := world_map.get_interactable_at(player.position)
	if _is_npc_talk_priority(interactable):
		var npc_id := String(_nearest_talkable_npc(player.position, _is_holding_gift()).get("npc_id", ""))
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
		# 신규 슬롯 튜토리얼(사용자 지시, 2026-09-01 - "사용자 E 조작해서
		# 레스토랑 들어가지잖아 조작 막아달라고") - 이동은 막아도 E는 별개
		# 입력이라 플레이어가 문 앞에 스크립트로 도착한 뒤(또는 접근 중) 직접
		# E를 눌러 먼저 들어가버릴 수 있었다. 조작 잠금 구간에는 건물 워프
		# 진입 자체를 막는다 - main.gd._maybe_play_tutorial_intro()가 끝나면
		# _load_map()을 직접 불러서 넘긴다.
		if _tutorial_intro_locks_movement:
			return
		# 신규 슬롯 튜토리얼: 레스토랑에 들어온 뒤 요리/서빙이 끝날 때까지는
		# 밖으로 나가는 워프 자체를 막는다(_tutorial_locks_restaurant_exit 참고,
		# 사용자 지시, 2026-09-03 - "튜토때 레스토랑 밖으로 못나가게 막아야할거같아").
		if _tutorial_locks_restaurant_exit:
			_show_temporary_message(RESTAURANT_CANNOT_LEAVE_MESSAGE)
			return
		# 공범 엔딩(사용자 지시, 2026-08-24): 노크 소리가 끝난 뒤 문 앞에서 E를
		# 누르면 평소처럼 밖으로 나가는 대신 어셔를 맞이하는 컷신으로 이어진다.
		if _accomplice_awaiting_door_open and GameManager.current_map_id == ACCOMPLICE_MAIL_MAP_ID:
			_accomplice_awaiting_door_open = false
			accomplice_door_answered.emit()
			return
		# 공범 엔딩: 스토커 메일을 확인할 때까지 집 밖으로 나갈 수 없다.
		if _accomplice_awaiting_mail_read and GameManager.current_map_id == ACCOMPLICE_MAIL_MAP_ID:
			_show_temporary_message(ACCOMPLICE_CANNOT_LEAVE_MESSAGE)
			return
		# restaurant.md: "영업 중엔 레스토랑을 벗어날 수 없다 - 외출하려면 먼저
		# 영업을 종료해야 한다." RestaurantManager.can_player_leave()는 이미
		# 있었는데 아무도 호출을 안 해서 실제로는 막히지 않고 있었다.
		if GameManager.current_map_id == RESTAURANT_SIGN_MAP_ID and not RestaurantManager.can_player_leave():
			_show_temporary_message(RESTAURANT_CANNOT_LEAVE_MESSAGE if RestaurantManager.is_open else RESTAURANT_CUSTOMERS_REMAINING_MESSAGE)
			return
		if _is_locked_shop_map(String(warp["target_map"])):
			_show_temporary_message(SHOP_LOCKED_MESSAGE)
			return
		if _is_shop_closed_for_night(String(warp["target_map"])) and dialogue_screen != null:
			dialogue_screen.open_description([SHOP_TIME_LOCK_MESSAGE])
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
	if FishingManager.can_start_fishing() and _is_facing_water():
		if not FishingManager.can_fit_all_species():
			_show_temporary_message("가방이 가득 찼다.")
			return
		if FishingManager.start_fishing():
			AudioManager.play_sfx(AudioManager.SFX_BUBBLE)
			player.tool_overlay.start("fishing_rod")
		return
	if not HuntingManager.get_interact_prompt(GameManager.current_map_id).is_empty():
		## 낚시와 동일한 패턴(사용자 지시, 2026-09-01) - "E 조준"은 인벤 상태와
		## 무관하게 항상 뜨고, 실제로 눌러서 담을 자리가 없을 때만 "가방이
		## 가득 찼다."를 짧게 보여준다.
		if not HuntingManager.can_fit_catch(GameManager.current_map_id):
			_show_temporary_message("가방이 가득 찼다.")
		else:
			HuntingManager.try_catch(GameManager.current_map_id)
		return
	var available_bush := BerryBushManager.get_available_bush(player.position)
	if not available_bush.is_empty():
		_show_temporary_message(BerryBushManager.perform_harvest(available_bush))
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
			# 하드코딩된 "watering_can"이라 황금 물뿌리개를 쥐고 있어도 항상
			# 일반 물뿌리개 아이콘이 나오던 버그(사용자 리포트, 2026-09-16) -
			# 실제로 장착 중인 아이템 id를 그대로 넘긴다.
			player.tool_overlay.start(EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT), TOOL_USE_HOLD_SECONDS)
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
		"untill":
			# "till"과 같은 이유로 포즈 재생 후 맨땅으로 되돌린다(사용자 지시,
			# 2026-08-24).
			if _farm_action_active:
				return
			_farm_action_active = true
			player.tool_overlay.start("hoe", TOOL_USE_HOLD_SECONDS)
			await get_tree().create_timer(TOOL_USE_HOLD_SECONDS).timeout
			FarmingManager.perform_untill(farm_position)
			_farm_action_active = false


func _nearest_talkable_npc(position: Vector2, ignore_talked_today: bool = false) -> Dictionary:
	if npc_layer == null:
		return {}
	return npc_layer.call("get_nearest_talkable_npc", position, ignore_talked_today)


## 손에 선물(category=="gift")이 장착돼 있는지 - _nearest_talkable_npc()의
## ignore_talked_today 인자를 결정하는 데 여러 곳(프롬프트 표시, 실제 상호작용,
## 우선순위 판정)에서 똑같이 필요해서 하나로 뺐다.
func _is_holding_gift() -> bool:
	return InventoryManager.get_item_category(EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT)) == "gift"


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
	if npc_id.is_empty() or bool(_greeted_today.get(npc_id, false)):
		return
	_greeted_today[npc_id] = true
	EmailManager.record_npc_greeted(npc_id)
	# 고정 3일 대신, 오늘 실제로 이 NPC가 살인 관련 스토리 대사(애도/알리바이/
	# 목격 진술 또는 불륜 상대 사망 반응)를 할 차례면 웃는 얼굴 대신 눈물을
	# 띄운다(사용자 지시, 2026-08-26 - "살인 관련 스토리 대사를 말하는 날에는
	# 이모지가 눈물로 뜨게 해줘"). get_daily_dialogue()가 실제로 그 대사를
	# 꺼낼 때 쓰는 것과 같은 조건을 소비 없이 미리 확인한다.
	if MurderManager.has_pending_alibi_line(npc_id) or NPCManager.has_pending_partner_death_reaction(npc_id) \
			or MurderManager.was_alibi_shown_today(npc_id) or NPCManager.was_partner_death_reaction_shown_today(npc_id):
		NPCManager.request_emote(npc_id, NPCManager.EMOTE_DEJECTED)
	else:
		NPCManager.request_emote(npc_id, NPCManager.EMOTE_SMILE)


## TALK_RADIUS(24px)가 계산대 같은 정적 Interactable의 INTERACT_RADIUS(12px)
## 보다 넓다 보니, 카페처럼 계산대와 NPC가 서 있는 자리가 가까운 곳에서는 항상
## 대화 판정 범위 안에 계산대도 함께 들어와 버린다("계산대를 쓰려는데 말이
## 걸어짐"). 둘 다 범위 안이면 실제로 더 가까운 쪽을 우선하도록 거리를 비교한다
## - 정적 Interactable이 범위 밖이면(= 지금 대화만 가능한 상황) 그대로 대화 우선.
func _is_npc_talk_priority(interactable: Dictionary) -> bool:
	var talk_info := _nearest_talkable_npc(player.position, _is_holding_gift())
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
		if RestaurantManager.is_open and _tutorial_locks_restaurant_close:
			# 신규 슬롯 튜토리얼이 강제로 열어둔 레스토랑은 튜토리얼이 끝날
			# 때까지 플레이어가 직접 닫을 수 없다(사용자 지시, 2026-09-01 -
			# "열었을땐 못닫게 해줘").
			return
		if RestaurantManager.is_open:
			restaurant_confirm_popup.open_with_message("레스토랑을 닫으시겠습니까?")
		elif not _tutorial_awaiting_restaurant_open \
				and (TimeManager.current_hour < RestaurantManager.OPEN_HOUR or TimeManager.current_hour >= RestaurantManager.CLOSE_HOUR):
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
	if interactable_name == "closet":
		if NPCManager.has_shown_event(WARDROBE_UNLOCK_NPC_ID, WARDROBE_UNLOCK_THRESHOLD):
			wardrobe_interacted.emit()
		elif dialogue_screen != null:
			## 머리 위 임시 문구 대신 설명창으로(사용자 지시, 2026-08-30) -
			## furniture_desc와 같은 방식.
			dialogue_screen.open_description([WARDROBE_BROKEN_MESSAGE])
		return
	if interactable_name == "furniture_desc":
		var desc_id := String(interactable.get("id", ""))
		var map_descriptions: Dictionary = _furniture_descriptions.get(GameManager.current_map_id, {})
		var lines := _furniture_description_lines(map_descriptions.get(desc_id, ""))
		## 머리 위 임시 문구 대신 대화창으로 띄우되, 높이는 짧은 설명창 전용으로
		## 줄인다(사용자 지시, 2026-08-29 - dialogue_screen.open_description()
		## 참고). 배열로 쓴 문장은 전부 순서대로(E로 한 줄씩) 보여준다.
		if not lines.is_empty() and dialogue_screen != null:
			dialogue_screen.open_description(lines)
		return
	if interactable_name == "soul_altar":
		if RevivalManager.can_use_altar():
			soul_altar_interacted.emit()
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
		## 레스토랑이 닫혀있으면 요리창을 열지 않고, 다 익은 게 있으면 그
		## 자리에서 바로 꺼낸다(사용자 지시 2026-08-29 - 피드백 #43, 재료를
		## 넣어둔 채 닫으면 영구히 못 꺼내던 문제). 프롬프트 표시 로직에서
		## 이미 닫혀있고 다 안 익었으면 상호작용 자체가 안 뜨게 막아뒀으니,
		## 여기 도달했다면 사실상 항상 collect()가 성공해야 하지만 인벤토리가
		## 꽉 찬 경우를 대비해 실패 메시지도 처리한다.
		if not RestaurantManager.is_open:
			if KitchenManager.is_ready(interactable_name):
				var cooked_id := KitchenManager.get_cooking_result(interactable_name)
				if KitchenManager.collect(interactable_name):
					var cooked_name: String = String(InventoryManager.get_item_definition(cooked_id).get("name", cooked_id))
					_show_temporary_message(tr("%s을(를) 꺼냈다.") % cooked_name)
				else:
					_show_temporary_message("인벤토리가 가득 찼다.")
			else:
				## 프롬프트는 안 뜨지만(2240번 줄) E는 여전히 눌러볼 수 있어서, 아무
				## 반응도 없으면 조리대가 고장났다고 오해할 수 있다(플레이테스트
				## 피드백 #3, 2026-09-05 - "조리대 사용 불가능할때 원래
				## 떴잖아"). 서빙대(SERVING_AREA_PREFIX)와 동일한 안내로 복원.
				_show_temporary_message(RESTAURANT_NOT_READY_MESSAGE)
		else:
			kitchen_station_interacted.emit(interactable_name)
