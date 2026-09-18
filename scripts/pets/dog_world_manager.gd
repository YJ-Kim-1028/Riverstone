extends Node2D
class_name DogWorldManager

## 새 파일 - 셰퍼드 호감도 50 이벤트(강아지 증정)로 풀리는 강아지를
## Home.tmx에서만 스폰/제거하는 전담 매니저(사용자 지시, 2026-09-16).
## cat_world_manager.gd와 거의 같은 구조지만, 강아지는 비가 와도 계속
## 마당에 있어야 해서(사용자 지시 - "비오는 날에도 고양이랑 다르게 밖에
## 있게") 날씨 분기가 없다 - Home 여부만 본다.
## NPCWorldManager(npc_world_manager.gd, 핵심 시스템이라 손대지 말 것)와는
## 완전히 분리된 파일 - main.tscn에서 NPCLayer/CatLayer의 형제 노드로
## HomeMap 밑에 배치한다.

const DogScene := preload("res://scenes/pets/dog.tscn")
const HOME_MAP_ID := "Home"
const DOG_NPC_ID := "shepherd"
const DOG_AFFECTION_THRESHOLD := 50
## 문 근처에서만 배회하는 것처럼 보인다는 리포트(cat_world_manager.gd와
## 동일, 사용자 2026-09-16)로 강아지 전용 스폰을 Home.tmx의 "Spawn"
## 레이어에 직접 추가해서 그쪽을 쓴다.
const HOME_SPAWN_NAME := "dog_home_spawn"
## 아직 플레이어가 이름을 안 지어줬을 때(팝업이 뜨기 전 짧은 틈) 이름표에
## 대신 보여줄 기본값.
const DEFAULT_PET_NAME := "강아지"

@onready var _world_map: WorldMap = get_parent() as WorldMap

var _dog: Node2D = null


func _ready() -> void:
	GameManager.map_changed.connect(_on_map_changed)
	NPCManager.affection_event_triggered.connect(_on_affection_event_triggered)
	NPCManager.pet_name_changed.connect(_on_pet_name_changed)
	## 재접속 직후 이 _ready()가 NPCManager 세이브 데이터 적용보다 먼저 돌면
	## has_shown_event()가 아직 false라서 강아지가 안 나타나는 채로 멈추는
	## 경우가 있었다(사용자 리포트, 2026-09-17 - "강아지가 아예 안보임").
	## map_changed/affection_event_triggered 둘 다 안 일어나면 다시 확인할
	## 계기가 없으므로, 몇 초마다(게임 내 1분) 자동으로 재확인하는 안전장치.
	TimeManager.minute_passed.connect(_on_minute_passed)
	_refresh_dog()


func _on_map_changed(_map_id: String) -> void:
	_refresh_dog()


func _on_minute_passed(_hour: int, _minute: int) -> void:
	_refresh_dog()


func _on_affection_event_triggered(npc_id: String, threshold: int) -> void:
	if npc_id == DOG_NPC_ID and threshold == DOG_AFFECTION_THRESHOLD:
		_refresh_dog()


func _on_pet_name_changed(npc_id: String) -> void:
	if npc_id == DOG_NPC_ID and _dog != null:
		_dog.set_pet_name(_current_pet_name())


func _current_pet_name() -> String:
	var pet_name := NPCManager.get_pet_name(DOG_NPC_ID)
	return pet_name if not pet_name.is_empty() else DEFAULT_PET_NAME


func _refresh_dog() -> void:
	## has_completed_event()는 "호감도 임계값을 넘겨서 대사가 대기열에 등록됨"
	## 만 뜻하고 실제로 그 대사를 본 것과는 다르다(cat_world_manager.gd 버그
	## 리포트 참고, 2026-09-16) - has_shown_event()로 바꿔야 실제로 그 대사를
	## 본 뒤에만 나타난다.
	var should_exist := GameManager.current_map_id == HOME_MAP_ID and NPCManager.has_shown_event(DOG_NPC_ID, DOG_AFFECTION_THRESHOLD)
	if should_exist and _dog == null:
		_spawn_dog()
	elif not should_exist and _dog != null:
		_dog.queue_free()
		_dog = null


func _spawn_dog() -> void:
	if _world_map == null:
		return
	var spawn_position: Vector2 = _world_map.get_spawn_position(HOME_SPAWN_NAME)
	if spawn_position == Vector2.INF:
		return
	_dog = DogScene.instantiate() as Node2D
	_dog.position = spawn_position
	_dog.set_world_map(_world_map)
	## _ready()가 아직 안 돌아서(add_child() 전) @onready _name_label이 null인
	## 상태로 set_pet_name()을 부르면 조용히 무시된다(cat_world_manager.gd와
	## 동일한 버그, 사용자 리포트 2026-09-16) - add_child() 뒤로 순서를 옮겨야
	## 한다.
	_world_map.add_child(_dog)
	_dog.set_player(_world_map.get_node_or_null("Player"))
	_dog.set_pet_name(_current_pet_name())
	_dog.set_giver_npc_id(DOG_NPC_ID)
