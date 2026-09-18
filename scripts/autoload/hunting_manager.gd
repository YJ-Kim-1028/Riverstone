extends Node

## 사냥 시스템(사용자 지시, 2026-08-30) - 토끼(추격형)/새(은신형) 두 종류를
## HuntZone 안에서 스폰한다. 낚시처럼 UI 팝업을 여는 게 아니라(사용자 지시,
## 2026-08-30 - "UI 창에서 진행된 거 아니지? 그냥 맵에서 진행됐으면 좋겠는데"),
## 동물에게 다가가 E를 누르면 플레이어 머리 위에 좌우로 움직이는 바가 뜨고
## (catch_bar.gd, 맵 위 월드 스페이스에 직접 그려짐 - 사용자 지시, 2026-08-30
## "동물 말고 사용자 머리 위에 떠야 더 잘보여"), 마커가 강조 구간 안에 있을
## 때 다시 E를 누르면 포획 성공 - 한 번의 반응속도 판정이라 낚시의 "정해진
## 횟수만큼 클릭" 방식보다 훨씬 짧고 즉각적이다.

signal hunt_started
signal hunt_ended(result: Dictionary)  ## {"success": bool, "item_id": String, "added_to_inventory": bool}

enum Phase { IDLE, AIMING }
enum AnimalType { RABBIT, BIRD }

const RABBIT_ITEM_ID := "rabbit_meat"
const BIRD_ITEM_ID := "bird_meat"
## 사용자 지시, 2026-08-31 - "사냥용 소총 안끼고 있는데 조준 표시가 왜 떠?":
## 손에 사냥용 소총을 장착하고 있어야만 조준 프롬프트/조준 시도가 가능하다.
const RIFLE_ITEM_ID := "hunting_rifle"
## 사용자 지시, 2026-08-31 - "새 3마리에 토끼 2마리로 바꿔줘".
const RABBIT_COUNT_PER_ZONE := 2
const BIRD_COUNT_PER_ZONE := 3
## 사용자 지시, 2026-08-30 - "22px 정도 범위에 들어왔을 때 머리에 E 조준
## 이게 떠야돼": 동물의 감지 반경(rabbit_sprite.gd DETECTION_RADIUS/
## bird_sprite.gd STARTLE_RADIUS)보다 살짝 넓게 잡아서, 감지 반경~이 반경
## 사이의 짧은 접근 구간에서만 "아직 눈치채지 못한" 동물을 조준할 수 있다.
## 사용자 지시, 2026-08-31 - "범위가 너무 좁아서 지금보다 2배는 늘려도
## 되겠다. 40px에 42px로": 20/22에서 40/42로 확대. 이어서 "픽셀 차이 좀만
## 늘릴까 ㅠ 5px정도는 되게" - 감지 반경(40)과의 틈을 2px에서 5px로 넓힌다.
const CATCH_RADIUS := 45.0
## 마커가 바를 한 번 왕복하는 데 걸리는 시간 - 짧을수록 어렵다. 기획 문서가
## 없어 임의 결정(기획 확정 시 조정).
## 사용자 지시, 2026-08-31 - "새보다 토끼가 더 어려웠으면 좋겠어... 바 움직이는
## 속도 더 높이고 성공 간격 더 줄이라고" - 토끼가 새보다 짧은 주기(더 빠른
## 마커)로 바뀜(원래는 새가 더 빡빡했다).
const MARKER_PERIOD_SECONDS := {AnimalType.RABBIT: 0.6, AnimalType.BIRD: 0.6}
## 강조 구간(포획 성공 판정 범위)의 폭 - 0.0~1.0 비율. 토끼가 새보다 더
## 좁아짐(위 MARKER_PERIOD_SECONDS와 같은 이유).
const SWEET_SPOT_WIDTH := {AnimalType.RABBIT: 0.15, AnimalType.BIRD: 0.2}
## 한 번에 포획되던 걸 fishing_manager.gd의 get_required_hits()와 같은 방식으로
## 여러 번 성공해야 하게 바꿨다(사용자 지시, 2026-09-16 - "한번만 성공해도
## 바로 돼서... 3번 성공해야지만 포획할수있게"). 실패(스위트스팟 밖에서 시도)는
## 예전처럼 그 즉시 전체 실패 처리 - 몇 번 성공했었는지는 리셋된다.
const REQUIRED_SUCCESSES := 3
## 원래 1번만 맞히면 됐을 때의 시간(4초)을 3번 기준으로 넉넉히 늘림 - 기획
## 확정 전 임의 값, 실제로 해보고 너무 길거나 짧으면 조정.
const AIMING_TIME_LIMIT_SECONDS := 10.0
## 사용자 지시, 2026-08-31 - "한 마리를 잡고 나면 무작위로 토끼나 새 둘 중
## 한 마리가 30초 뒤에 스폰 되지만, 헌팅 존 안에 이미 5마리의 동물이 있으면
## 더는 스폰 되지 않게" → "엥 놓쳐도 리스폰 되게 해야지....": 포획 성공/실패
## 상관없이(도망쳐서 사라진 경우 포함) 개체가 하나 빠질 때마다 지연 리스폰을
## 예약한다.
const RESPAWN_DELAY_SECONDS := 30.0
## "이미 5마리" 기준 - 존 하나의 원래 스폰 수(토끼+새)와 동일하게 맞춘다.
const MAX_ANIMALS_PER_MAP := RABBIT_COUNT_PER_ZONE + BIRD_COUNT_PER_ZONE
const CATCH_BAR_SCENE := preload("res://scenes/hunting/catch_bar.tscn")
const RABBIT_SCENE := preload("res://scenes/hunting/rabbit_sprite.tscn")
const BIRD_SCENE := preload("res://scenes/hunting/bird_sprite.tscn")

var player: Node2D = null

var _phase := Phase.IDLE
var _aiming_elapsed := 0.0
var _success_count := 0
var _current_type := AnimalType.RABBIT
var _current_animal: Node2D = null
var _current_bar: Node2D = null
var _sweet_spot_start := 0.0  ## 0.0~(1.0 - width) 범위에서 랜덤 결정.

var _world_map: WorldMap = null
## map_id -> Array[Node2D], 오늘 이 맵에 스폰된 동물들(잡히면 배열에서 제거).
var _active_animals: Dictionary = {}
## 오늘 스폰을 이미 했는지(맵 재입장 시 중복 스폰 방지) - map_id -> bool.
var _spawned_today: Dictionary = {}


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func _process(delta: float) -> void:
	if _phase != Phase.AIMING:
		return
	_aiming_elapsed += delta
	if _aiming_elapsed >= AIMING_TIME_LIMIT_SECONDS:
		## 시간 초과는 총을 쏘지도 못한 채 동물이 가버린 것 - 총소리 없이
		## 실패음만 낸다(attempt_catch()의 실패와 구분).
		AudioManager.play_sfx(AudioManager.SFX_HUNT_CATCH_FAIL)
		_finish({"success": false, "item_id": ""})


func _on_day_changed(_day: int, _weekday: String) -> void:
	_spawned_today.clear()
	for map_id in _active_animals.keys():
		_clear_map_animals(map_id)
	if _world_map != null:
		_spawn_for_map(GameManager.current_map_id)


## main.gd가 _load_map()에서 다른 매니저들과 동일하게 호출한다
## (berry_bush_manager.gd의 set_world_map()과 같은 패턴). world_map은 맵이
## 바뀌어도 파괴되지 않고 재사용되는 노드라(_clear_tiles()가 "_map_tile"
## 그룹 소속만 지우고, 동물 스프라이트는 그 그룹이 아니라서 그대로 남는다 -
## 사용자 리포트, 2026-08-30 "토끼랑 새는 반드시 plaza6에 있을때만 보여야돼")
## 다른 맵의 동물은 여기서 직접 숨기고 멈춰야 한다.
func set_world_map(world_map: WorldMap, map_id: String) -> void:
	_world_map = world_map
	_update_visibility(map_id)
	_spawn_for_map(map_id)


## 지금 맵의 동물만 보이고 움직이게, 나머지 맵의 동물은 숨기고 멈춘다.
func _update_visibility(current_map_id: String) -> void:
	for map_id in _active_animals:
		var is_current: bool = map_id == current_map_id
		for animal in (_active_animals[map_id] as Array):
			if not is_instance_valid(animal):
				continue
			animal.visible = is_current
			animal.call("set_paused", not is_current)


func _spawn_for_map(map_id: String) -> void:
	if bool(_spawned_today.get(map_id, false)):
		return
	_spawned_today[map_id] = true
	var zones: Array = _world_map.get_hunt_zones()
	if zones.is_empty():
		return
	var animals: Array[Node2D] = []
	for zone in zones:
		var rect: Rect2 = zone["rect"]
		var forced_type: String = String(zone.get("animal_type", ""))
		## 존 하나를 공유하는 걷기 가능 칸 목록 - 토끼/새가 서로 같은 칸을
		## 두 번 뽑아가지 않게 여기서 한 번만 만들고 섞어서 넘긴다.
		var walkable := _collect_walkable_positions(rect)
		walkable.shuffle()
		if forced_type == "rabbit":
			_spawn_many(animals, AnimalType.RABBIT, RABBIT_COUNT_PER_ZONE + BIRD_COUNT_PER_ZONE, walkable, rect)
		elif forced_type == "bird":
			_spawn_many(animals, AnimalType.BIRD, RABBIT_COUNT_PER_ZONE + BIRD_COUNT_PER_ZONE, walkable, rect)
		else:
			_spawn_many(animals, AnimalType.RABBIT, RABBIT_COUNT_PER_ZONE, walkable, rect)
			_spawn_many(animals, AnimalType.BIRD, BIRD_COUNT_PER_ZONE, walkable, rect)
	_active_animals[map_id] = animals


func _spawn_many(out_animals: Array[Node2D], type: AnimalType, count: int, walkable_positions: Array[Vector2], zone_rect: Rect2) -> void:
	for _i in count:
		if walkable_positions.is_empty():
			return
		var spawn_position: Vector2 = walkable_positions.pop_back()
		var animal := _spawn_one(type, spawn_position, zone_rect)
		if animal != null:
			out_animals.append(animal)


## world_map을 add_child 직후 바로 넘기지 않고 스프라이트 스크립트 스스로
## get_parent()로 얻게 한다(npc_world_manager.gd의 _world_map 패턴과 동일) -
## add_child()를 call_deferred로 미룬다(부모가 아직 자기 자식들을 세팅
## 중일 때 add_child가 막히는 문제를 npc_world_manager.gd에서 실제로 겪어서
## 방어적으로 적용, 2026-08-30).
func _spawn_one(type: AnimalType, spawn_position: Vector2, zone_rect: Rect2) -> Node2D:
	var scene: PackedScene = RABBIT_SCENE if type == AnimalType.RABBIT else BIRD_SCENE
	var animal: Node2D = scene.instantiate()
	animal.position = spawn_position
	animal.set("animal_type", type)
	## 도망 이동을 이 존 안으로만 묶어두는 데 쓴다(사용자 지시, 2026-08-31 -
	## "존 안에서만 도망가야지 냅다 존 밖까지 토끼가 벗어나버리잖아") -
	## rabbit_sprite.gd만 실제로 사용하지만, 이름 기반 set()이라 새에 줘도
	## 그냥 무시된다.
	animal.set("zone_rect", zone_rect)
	_world_map.call_deferred("add_child", animal)
	return animal


## rect 안의 걷기 가능한 칸(타일 중심 좌표)을 전부 스캔해서 모은다 - 예전엔
## 동물 한 마리마다 무작위 좌표를 최대 20번 뽑아 시도했는데, 존 안에 나무/물
## 같은 막힌 칸이 많으면 20번이 전부 실패해서 5마리를 요청해도 가끔 더 적게
## 스폰되는 문제가 있었다(사용자 리포트, 2026-08-31 - "항상 5마리로 스폰
## 안되는데?"). 존 전체를 한 번만 스캔해서 목록으로 만들어두면, 그 존에
## 걸을 수 있는 칸이 스폰 마릿수보다 많기만 하면 항상 정확한 수만큼 스폰된다.
func _collect_walkable_positions(rect: Rect2) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var start_x := floori(rect.position.x / WorldMap.TILE_SIZE) * WorldMap.TILE_SIZE
	var start_y := floori(rect.position.y / WorldMap.TILE_SIZE) * WorldMap.TILE_SIZE
	var y := start_y
	while y < rect.position.y + rect.size.y:
		var x := start_x
		while x < rect.position.x + rect.size.x:
			var candidate := Vector2(x + WorldMap.TILE_SIZE / 2.0, y + WorldMap.TILE_SIZE / 2.0)
			if rect.has_point(candidate) and not _world_map.is_cell_blocked(candidate):
				positions.append(candidate)
			x += WorldMap.TILE_SIZE
		y += WorldMap.TILE_SIZE
	return positions


func _clear_map_animals(map_id: String) -> void:
	for animal in (_active_animals.get(map_id, []) as Array):
		if is_instance_valid(animal):
			animal.queue_free()
	_active_animals.erase(map_id)


## main.gd의 _on_interact_pressed()가 다른 근접 상호작용(채집 등)과 같은 자리에서
## 호출한다 - 사냥 시도 대상이 있으면 조준 바를 띄우고 true, 없으면 false.
func try_catch(map_id: String) -> bool:
	if _phase != Phase.IDLE or player == null or not _has_rifle_equipped():
		return false
	var animal := _nearest_animal(map_id, CATCH_RADIUS)
	if animal == null:
		return false
	_current_animal = animal
	_current_type = int(animal.get("animal_type")) as AnimalType
	_phase = Phase.AIMING
	_aiming_elapsed = 0.0
	_success_count = 0
	_sweet_spot_start = randf() * (1.0 - float(SWEET_SPOT_WIDTH[_current_type]))
	animal.call("set_paused", true)
	_current_bar = CATCH_BAR_SCENE.instantiate()
	## 동물이 아니라 플레이어의 자식으로 붙인다(사용자 지시, 2026-08-30 -
	## "토끼 머리 위로 움직이는 게 뜨는 게 아니라, 사용자 머리 위에 떠야 돼.
	## 그래야 더 잘보여") - 동물은 20px 안쪽이면 이미 도망/이탈 중이라 화면
	## 구석으로 빠르게 밀려날 수 있는데, 플레이어는 조준 중 고정돼 있어서
	## 마커를 계속 보기 편하다.
	player.add_child(_current_bar)
	AudioManager.play_sfx(AudioManager.SFX_HUNT_AIM_START)
	hunt_started.emit()
	return true


## _process()의 상호작용 프롬프트 체인(main.gd)이 매 프레임 호출한다 -
## FishingManager.can_start_fishing() 등과 같은 자리. CATCH_RADIUS 안이면
## 조준 프롬프트, 아니면 빈 문자열(숨김) - "조금 더 가까이 붙어야 한다" 접근
## 안내는 없앴다(사용자 지시, 2026-08-31 - "그냥 안보이게 해도 되겠다 알아서
## 눈치 채야지").
func get_interact_prompt(map_id: String) -> String:
	if _phase != Phase.IDLE or player == null or not _has_rifle_equipped():
		return ""
	var animal := _nearest_animal(map_id, CATCH_RADIUS)
	if animal == null:
		return ""
	return "E 조준"


## fishing_manager.gd의 can_fit_all_species()와 같은 이유(사용자 리포트,
## 2026-09-01 - "인벤 가득 차있을 때 E 조준은 뜨는데 사냥 자체가 안 되네") -
## 낚시와 달리 어떤 동물을 잡을지 조준 전에 이미 정해져 있어서(가장 가까운
## 동물의 종류), 그 동물 하나의 아이템만 확인하면 된다. main.gd가 이걸로
## "E 조준"을 누른 시점에 자리가 없으면 조준을 시작하는 대신 "가방이 가득
## 찼다."를 보여준다.
func can_fit_catch(map_id: String) -> bool:
	var animal := _nearest_animal(map_id, CATCH_RADIUS)
	if animal == null:
		return true
	var animal_type := int(animal.get("animal_type")) as AnimalType
	var item_id := RABBIT_ITEM_ID if animal_type == AnimalType.RABBIT else BIRD_ITEM_ID
	return InventoryManager.can_add_item(item_id, 1)


func _has_rifle_equipped() -> bool:
	return EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT) == RIFLE_ITEM_ID


## 조준 중(Phase.AIMING)에 E를 다시 누르면 여기로 온다 - 마커가 지금 강조
## 구간 안에 있는지로 성공/실패를 가른다. 스위트스팟을 놓치면(실패) 그
## 즉시 전체 실패로 끝나지만, 맞혀도(성공) REQUIRED_SUCCESSES번 채우기
## 전까지는 조준을 계속 이어간다(사용자 지시, 2026-09-16) - fishing_manager.gd
## register_hit()의 "필요 횟수 채우면 그때 끝" 패턴과 동일.
func attempt_catch() -> void:
	if _phase != Phase.AIMING:
		return
	var marker: float = get_marker_ratio()
	var in_sweet_spot := marker >= _sweet_spot_start and marker <= _sweet_spot_start + float(SWEET_SPOT_WIDTH[_current_type])
	if in_sweet_spot:
		_success_count += 1
		if _success_count >= REQUIRED_SUCCESSES:
			## 사용자 지시, 2026-08-31 - "실패하면 총소리 안나고 실패 소리만 나게
			## 해줘": 총소리는 이제 성공했을 때만 재생한다.
			AudioManager.play_sfx(AudioManager.SFX_HUNT_GUNSHOT)
			AudioManager.play_sfx(AudioManager.SFX_HUNT_CATCH_SUCCESS)
			_finish(_resolve_catch())
		else:
			## 아직 다 안 채운 중간 성공 - 같은 스팟을 반복해서 맞히기만 하면
			## 너무 쉬워지니 다음 판정용 스위트스팟을 새로 뽑는다.
			AudioManager.play_sfx(AudioManager.SFX_HUNT_CATCH_SUCCESS)
			_sweet_spot_start = randf() * (1.0 - float(SWEET_SPOT_WIDTH[_current_type]))
	else:
		AudioManager.play_sfx(AudioManager.SFX_HUNT_CATCH_FAIL)
		_finish({"success": false, "item_id": ""})


## 도망/이탈 중인 동물은 후보에서 아예 제외한다(사용자 지시, 2026-08-31 -
## "토끼가 도망치는 동안은 조준이 안되게 하는건 어때?") - rabbit_sprite.gd/
## bird_sprite.gd의 is_fleeing()을 이름 기반으로 호출.
func _nearest_animal(map_id: String, radius: float) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for animal in (_active_animals.get(map_id, []) as Array):
		if not is_instance_valid(animal):
			continue
		if bool(animal.call("is_fleeing")):
			continue
		var distance: float = player.position.distance_to(animal.position)
		if distance <= radius and distance < best_distance:
			best = animal
			best_distance = distance
	return best


func is_active() -> bool:
	return _phase != Phase.IDLE


func is_aiming() -> bool:
	return _phase == Phase.AIMING


## 0.0~1.0 왕복(ping-pong) - catch_bar.gd가 매 프레임 읽어서 마커를 그린다.
func get_marker_ratio() -> float:
	if _phase != Phase.AIMING:
		return 0.0
	var period: float = MARKER_PERIOD_SECONDS[_current_type]
	return abs(fmod(_aiming_elapsed, period * 2.0) - period) / period


func get_sweet_spot_range() -> Vector2:
	return Vector2(_sweet_spot_start, _sweet_spot_start + float(SWEET_SPOT_WIDTH.get(_current_type, 0.25)))


func cancel_catch() -> void:
	if _phase != Phase.AIMING:
		return
	_finish({"success": false, "item_id": "", "cancelled": true})


func _resolve_catch() -> Dictionary:
	var item_id := RABBIT_ITEM_ID if _current_type == AnimalType.RABBIT else BIRD_ITEM_ID
	var added := InventoryManager.add_item(item_id, 1)
	return {"success": true, "item_id": item_id, "added_to_inventory": added}


func _finish(result: Dictionary) -> void:
	_phase = Phase.IDLE
	if is_instance_valid(_current_bar):
		_current_bar.queue_free()
	_current_bar = null
	## 성공이든 실패든(새는 실패하면 날아가고, 토끼는 실패해도 도망 상태로
	## 계속 남되 다시 시도 가능) - MVP는 단순하게 둘 다 그 자리에서 사라지게
	## 통일한다. 나중에 "토끼는 재시도 가능"으로 바꾸고 싶으면 여기 분기만
	## 추가하면 된다.
	if is_instance_valid(_current_animal):
		var map_id := GameManager.current_map_id
		(_active_animals.get(map_id, []) as Array).erase(_current_animal)
		_current_animal.queue_free()
		## 사용자 지시, 2026-08-31 - "엥 놓쳐도 리스폰 되게 해야지....":
		## 처음엔 포획 성공 시에만 리스폰을 예약했는데, 놓쳐서 도망간 경우도
		## 개체 수가 그대로 줄어드는 건 마찬가지라 성공/실패 상관없이 예약한다.
		_schedule_respawn(map_id)
	_current_animal = null
	hunt_ended.emit(result)


## get_tree().create_timer()는 HuntingManager 자체 상태와 무관한 SceneTree
## 전역 타이머라, 그 30초 사이 플레이어가 다른 맵으로 넘어가 _world_map
## 내용이 통째로 다른 맵으로 바뀌어도(위 set_world_map() 주석 참고 - 같은
## 노드를 재사용) 안전하게 만료만 되고 끝난다 - 실제 스폰은 콜백 안에서
## "그때도 여전히 그 맵에 있는지"를 다시 확인한 뒤에만 해서, 로드돼 있는
## 게 다른 맵인데 그 좌표 체계로 스폰해버리는 사고를 막는다.
func _schedule_respawn(map_id: String) -> void:
	get_tree().create_timer(RESPAWN_DELAY_SECONDS).timeout.connect(
		_respawn_one_if_room.bind(map_id)
	)


## bird_sprite.gd가 조준 시도 없이 스스로 놀라서 날아가 사라질 때 부른다 -
## HuntingManager._finish()가 처리하는 "플레이어가 조준 시도 후 성공/실패"
## 경로를 안 거치는 유일한 이탈 경로라, 여기서 직접 목록 정리+리스폰 예약을
## 안 해주면 _active_animals에 이미 free된 노드 참조가 그대로 남는다(사용자
## 리포트, 2026-08-31 - "새 그냥 훨훨 날아가버리면 스폰도 다시 안된다니까" -
## 남은 죽은 참조가 개체 수 카운트를 부풀려서, 진짜 개체 수와 상관없이
## "이미 5마리"로 착각해 이후 리스폰까지 전부 막혀버렸다).
func report_self_escaped(animal: Node2D) -> void:
	for map_id in _active_animals.keys():
		var animals: Array = _active_animals[map_id]
		if animals.has(animal):
			animals.erase(animal)
			_schedule_respawn(map_id)
			return


## _active_animals 항목이 이미 free된 노드를 가리키고 있을 수 있는 경로가
## 있었던 전례(바로 위 report_self_escaped() 주석) - 실제 마릿수는 항상
## is_instance_valid()로 걸러 센다.
func _respawn_one_if_room(map_id: String) -> void:
	if _world_map == null or GameManager.current_map_id != map_id:
		return
	var current_count := 0
	for animal in (_active_animals.get(map_id, []) as Array):
		if is_instance_valid(animal):
			current_count += 1
	if current_count >= MAX_ANIMALS_PER_MAP:
		return
	var zones: Array = _world_map.get_hunt_zones()
	if zones.is_empty():
		return
	var zone: Dictionary = zones[randi() % zones.size()]
	var rect: Rect2 = zone["rect"]
	var walkable := _collect_walkable_positions(rect)
	if walkable.is_empty():
		return
	var forced_type: String = String(zone.get("animal_type", ""))
	var type := AnimalType.RABBIT if randi() % 2 == 0 else AnimalType.BIRD
	if forced_type == "rabbit":
		type = AnimalType.RABBIT
	elif forced_type == "bird":
		type = AnimalType.BIRD
	var spawn_position: Vector2 = walkable[randi() % walkable.size()]
	var animal := _spawn_one(type, spawn_position, rect)
	if animal == null:
		return
	if not _active_animals.has(map_id):
		_active_animals[map_id] = []
	(_active_animals[map_id] as Array).append(animal)


func get_save_data() -> Dictionary:
	return {"spawned_today": _spawned_today.duplicate()}


## _spawned_today는 일부러 저장된 값을 안 돌려받는다(사용자 리포트,
## 2026-08-31 - "세이브데이터로 관리하고 있어서 한번 껐다 키면 토끼와 새가
## 젠이안돼") - 실제로 스폰된 동물(_active_animals의 Node2D)은 세이브에 담을
## 수 없어서 재시작하면 무조건 사라지는데, "오늘 이미 스폰함" 플래그만 저장돼
## 살아남으면 재시작할 때마다 그 맵은 동물이 하나도 없이 그 날이 끝날 때까지
## 영원히 빈 상태가 된다. 같은 세션 안에서 같은 날 맵을 여러 번 들락거릴 때
## 중복 스폰을 막는 용도로만 쓰고(그 목적은 메모리 상 _spawned_today로 충분),
## 세션을 넘어서는 지속성은 주지 않는다 - get_save_data()는 디버깅/향후 확장
## 대비로 계속 기록하되, load_save_data()는 읽지 않는다.
func load_save_data(_data: Dictionary) -> void:
	pass
