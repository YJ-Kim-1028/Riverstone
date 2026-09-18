extends Node2D
class_name CatWorldManager

## 새 파일 - 벨제 호감도 50 이벤트(고양이 증정)로 풀리는 고양이를 Home.tmx/
## home_interior.tmx에서만 스폰/제거하는 전담 매니저(사용자 지시,
## 2026-09-16). 기존 NPCWorldManager(npc_world_manager.gd)와 완전히 분리된
## 파일로 둔 이유: 그 파일은 NPC 스케줄/경로탐색 엔진이라 "손대지 말고
## 승인부터 받기"로 지정된 핵심 시스템인데, 이 작은 애완동물 기능 때문에
## 그 파일을 건드릴 필요가 없어서다. main.tscn에서 NPCLayer(같은
## npc_world_manager.gd)의 형제 노드로 HomeMap 밑에 배치한다 -
## _world_map(get_parent())/Player를 얻는 방식도 동일하게 따름.

const CatScene := preload("res://scenes/pets/cat.tscn")
const HOME_MAP_ID := "Home"
const HOME_INTERIOR_MAP_ID := "home_interior"
const CAT_NPC_ID := "belje"
const CAT_AFFECTION_THRESHOLD := 50
## 처음엔 플레이어 기본 스폰(start_spawn/home_enterance)을 빌려썼는데,
## 문 근처에서만 배회하는 것처럼 보인다는 리포트(사용자, 2026-09-16 -
## "고양이가 너무 문쪽에서만 왓다갓다 하는 거 같아")로 고양이 전용 스폰을
## Home.tmx/home_interior.tmx(레벨 1~3 전부)의 "Spawn" 레이어에 직접
## 추가해서 그쪽을 쓴다.
const HOME_SPAWN_NAME := "cat_home_spawn"
const HOME_INTERIOR_SPAWN_NAME := "cat_interior_spawn"
## 아직 플레이어가 이름을 안 지어줬을 때(팝업이 뜨기 전 짧은 틈) 이름표에
## 대신 보여줄 기본값.
const DEFAULT_PET_NAME := "고양이"

@onready var _world_map: WorldMap = get_parent() as WorldMap

var _cat: Node2D = null


func _ready() -> void:
	GameManager.map_changed.connect(_on_map_changed)
	NPCManager.affection_event_triggered.connect(_on_affection_event_triggered)
	NPCManager.pet_name_changed.connect(_on_pet_name_changed)
	WeatherManager.weather_changed.connect(_on_weather_changed)
	## 재접속 직후 이 _ready()가 NPCManager 세이브 데이터 적용보다 먼저 돌면
	## has_shown_event()가 아직 false라서 고양이가 안 나타나는 채로 멈추는
	## 경우가 있었다(dog_world_manager.gd와 동일한 버그, 사용자 리포트
	## 2026-09-17). map_changed/affection_event_triggered/weather_changed
	## 셋 다 안 일어나면 다시 확인할 계기가 없으므로, 몇 초마다(게임 내
	## 1분) 자동으로 재확인하는 안전장치.
	TimeManager.minute_passed.connect(_on_minute_passed)
	_refresh_cat()


func _on_map_changed(_map_id: String) -> void:
	_refresh_cat()


func _on_minute_passed(_hour: int, _minute: int) -> void:
	_refresh_cat()


func _on_affection_event_triggered(npc_id: String, threshold: int) -> void:
	if npc_id == CAT_NPC_ID and threshold == CAT_AFFECTION_THRESHOLD:
		_refresh_cat()


## 비 오는 날엔 실내(home_interior)로, 맑은 날엔 마당(Home)으로(사용자 지시,
## 2026-09-16 - "비올때는 home_interior.tmx에 스폰"). 두 맵 다 아닌 곳(다른
## 지도)에 있을 땐 어느 쪽이든 존재하지 않는다.
func _on_weather_changed(_weather: WeatherManager.Weather) -> void:
	_refresh_cat()


func _on_pet_name_changed(npc_id: String) -> void:
	if npc_id == CAT_NPC_ID and _cat != null:
		_cat.set_pet_name(_current_pet_name())


func _current_pet_name() -> String:
	var pet_name := NPCManager.get_pet_name(CAT_NPC_ID)
	return pet_name if not pet_name.is_empty() else DEFAULT_PET_NAME


func _target_map_id() -> String:
	return HOME_INTERIOR_MAP_ID if WeatherManager.is_raining() else HOME_MAP_ID


func _refresh_cat() -> void:
	## has_completed_event()는 "호감도 임계값을 넘겨서 대사가 대기열에 등록됨"
	## 만 뜻해서 대사를 실제로 보기 전에도 true였다(버그 리포트, 2026-09-16 -
	## "벨제랑만 대화했는데 갑자기 고양이랑 강아지가 생겼어.. 심지어
	## 대화이벤트도 아니었는데") - 오래된 세이브는 호감도가 이미 50을 넘겨둔
	## 상태라 곧바로 걸렸다. "실제로 그 대사를 본 적 있는지"는
	## has_shown_event()라 이걸로 바꿔야 한다.
	var unlocked := NPCManager.has_shown_event(CAT_NPC_ID, CAT_AFFECTION_THRESHOLD)
	var should_exist := unlocked and GameManager.current_map_id == _target_map_id()
	if should_exist and _cat == null:
		_spawn_cat()
	elif not should_exist and _cat != null:
		_cat.queue_free()
		_cat = null


func _spawn_cat() -> void:
	if _world_map == null:
		return
	var spawn_name := HOME_INTERIOR_SPAWN_NAME if GameManager.current_map_id == HOME_INTERIOR_MAP_ID else HOME_SPAWN_NAME
	var spawn_position: Vector2 = _world_map.get_spawn_position(spawn_name)
	if spawn_position == Vector2.INF:
		return
	_cat = CatScene.instantiate() as Node2D
	_cat.position = spawn_position
	_cat.set_world_map(_world_map)
	## _ready()가 아직 안 돌아서(add_child() 전) @onready _name_label이 null인
	## 상태로 set_pet_name()을 부르면 조용히 무시된다(사용자 리포트, 2026-09-16
	## - "고양이한테 이름 안나온ㄴ") - add_child() 뒤로 순서를 옮겨야 한다.
	_world_map.add_child(_cat)
	_cat.set_pet_name(_current_pet_name())
	_cat.set_giver_npc_id(CAT_NPC_ID)
