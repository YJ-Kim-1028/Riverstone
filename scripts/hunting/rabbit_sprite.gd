extends Node2D

## 추격형 사냥감 - 평소엔 스폰 지점 근처를 배회하다가(사용자 지시, 2026-08-30 -
## "가만히 있냐" 리포트 후 추가), 플레이어가 감지 반경 안에 들어오면 반대
## 방향으로 도망친다. 이동 로직은 player.gd의 _move_clamped()을
## 단순화한 버전(축별 이동 + 충돌 검사, 몸통 폭 여백 없이 발밑 한 점만 검사 -
## 토끼가 작아서 이 정도로도 충분). 정지 중엔 정면 포즈, 배회/도망 중엔
## 옆모습 포즈로 바꾸고 좌우 이동 방향에 따라 flip_h로 뒤집는다(그림은 오른쪽
## 보는 옆모습 한 장만 있으면 되고 왼쪽은 코드가 뒤집어서 만든다).

## 사용자 지시, 2026-08-30 - "토끼가 20px부터 알아채면, 사용자는 22px 정도
## 범위에 들어왔을 때 머리에 E 조준이 떠야돼": HuntingManager.CATCH_RADIUS
## 보다 살짝 좁게 잡아서, 두 반경 사이의 짧은 접근 구간에서만 아직 눈치채지
## 못한 토끼를 조준할 수 있다. 사용자 지시, 2026-08-31 - "범위가 너무 좁아서
## 지금보다 2배는 늘려도 되겠다. 40px에 42px로": 20에서 40으로 확대. ("새보다
## 토끼가 더 어려웠으면 좋겠어"는 감지 반경이 아니라 미니게임(바 속도/성공
## 구간) 얘기였다고 정정받아 43으로 좁혔던 걸 40으로 되돌림 - hunting_manager.gd
## MARKER_PERIOD_SECONDS/SWEET_SPOT_WIDTH 참고.)
const DETECTION_RADIUS := 40.0
## 한 번 도망치기 시작하면 DETECTION_RADIUS보다 더 멀어져야 멈춘다(사용자
## 리포트, 2026-08-31 - "토끼가 도망가는 그게 매번 불러와지다 보니 1초에
## 1번씩 도망가서 존나 이상하게 버벅거리는거처럼 보여") - 시작/종료 반경이
## 같으면 플레이어가 그 경계선 부근에서 서성이기만 해도 매 프레임 도망
## 상태가 켜졌다 꺼졌다 하면서 포즈/사운드가 계속 다시 시작된다. 종료 반경을
## 더 넓게 둬서 한 번 도망치면 확실히 멀어질 때까지는 계속 도망치게 한다.
## 사용자 지시, 2026-08-31 - "사용자한테서 100px 벗어날 때까지 도망치면
## 안 돼?" → "아니다 100은 너무 심하고 80" → "그리고 120px 밖으로 해야겠다":
## 60px(예전 DETECTION_RADIUS+20)로는 코너에 몰렸을 때 플레이어가 접근 각도를
## 잡느라 살짝 물러나는 것만으로도 이 반경을 넘어 도망이 풀리기 쉬웠다 -
## 절대값 120으로 키운다.
const STOP_FLEEING_RADIUS := 120.0
## 사용자 지시, 2026-08-31 - "토끼 도망 속도 사용자 속도보다 2배 더 빠르게
## 해줘": player.gd의 SPEED(50.0) 대비 2배. ("토끼 너무 쉬워, 움직이는 속도
## 더 빠르게"는 도망 이동이 아니라 미니게임 바 얘기였다고 정정받아 150→100
## 으로 되돌림.)
const FLEE_SPEED := 100.0
## 스폰 지점에서 이 반경을 벗어나면 배회 중에도 다시 스폰 지점 쪽으로
## 방향을 튼다 - 안 그러면 시간이 지날수록 HuntZone 밖으로 계속 흘러나갈 수
## 있다.
const WANDER_RADIUS := 24.0
const WANDER_SPEED := 16.0
const WANDER_MOVE_SECONDS := 1.0
const WANDER_IDLE_MIN_SECONDS := 1.5
const WANDER_IDLE_MAX_SECONDS := 4.0
## 구석에 막혀서 중심으로 방향을 튼 뒤, 이 시간 동안은 매 프레임 재판단 없이
## 무조건 중심 방향으로 계속 달린다(사용자 리포트, 2026-08-31 - "중앙으로
## 안간다니까" - 예전엔 매 프레임 "막혔는지"를 새로 판단해서, 한 프레임
## 중심으로 가면 그 즉시 안 막힌 걸로 판정되어 바로 다음 프레임에 다시
## 플레이어 반대 방향으로 튕겨나가는 지그재그가 나서 사실상 거의 못
## 움직이는 것처럼 보였다).
const RECOVERY_DURATION := 0.4
## 토끼/새 각각 별도 파일로(사용자 지시, 2026-08-30) - animal.png 하나를
## 공유하던 이전 방식에서 변경.
const TEXTURE_PATH := "res://assets/img/hunting/rabbit.png"
const SPRITE_CELL_SIZE := 32
## rabbit.png 칸 배치(왼쪽부터): 0=정면 정지, 1=옆모습(오른쪽 기준, 왼쪽은
## flip_h로 뒤집음).
const RABBIT_IDLE_CELL_INDEX := 0
const RABBIT_RUN_CELL_INDEX := 1

## HuntingManager._spawn_one()이 animal.set("animal_type", ...)으로 채운다
## (HuntingManager.AnimalType.RABBIT과 같은 정수값 - class_name 타입 참조를
## 피해서 이름 기반으로 넘긴다, WorldMap 관련 오토로드 컴파일 순서 문제를
## 이번 세션에서 겪은 뒤로 통일한 규칙).
var animal_type: int = 0
## HuntingManager._spawn_one()이 animal.set("zone_rect", ...)으로 채운다 -
## 도망칠 때 이 존 밖으로 벗어나지 못하게 막는 경계(사용자 지시, 2026-08-31 -
## "존 안에서만 도망가야지 냅다 존 밖까지 토끼가 벗어나버리잖아").
var zone_rect := Rect2()

var _world_map: WorldMap
var _paused := false
## 감지되는 순간에만 도망 소리를 한 번 내기 위한 상태 추적 - 매 프레임 재생하면
## 도망치는 내내 소리가 겹쳐 재생된다.
var _fleeing := false

var _spawn_position := Vector2.ZERO
var _wandering := false
var _wander_direction := Vector2.ZERO
## 배회 상태(이동/정지) 남은 시간 - 0 이하가 되면 반대 상태로 전환한다.
var _wander_timer := 0.0
## 구석에 막혀서 중심으로 달아나는 중인지 - 매 프레임 다시 판단하지 않고
## 이 상태 동안엔 무조건 중심 방향으로만 이동한다(아래 RECOVERY_DURATION
## 주석 참고).
var _recovering := false
var _recovery_timer := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_world_map = get_parent() as WorldMap
	_spawn_position = position
	_wander_timer = randf_range(WANDER_IDLE_MIN_SECONDS, WANDER_IDLE_MAX_SECONDS)
	_load_sprite()


## assets/img/hunting/rabbit.png는 사용자가 그려야 하는 신규 에셋이라(assets/
## 폴더는 Claude Code 수정 금지) 아직 없을 수 있다 - load()는 preload()와
## 달리 파일이 없으면 그냥 null을 돌려주므로, 그림이 없는 동안은 스프라이트가
## 안 보일 뿐 에러 없이 동작한다.
func _load_sprite() -> void:
	var texture: Texture2D = load(TEXTURE_PATH) as Texture2D
	if texture == null:
		return
	_sprite.texture = texture
	_sprite.region_enabled = true
	_set_pose(RABBIT_IDLE_CELL_INDEX)


func _set_pose(cell_index: int) -> void:
	_sprite.region_rect = Rect2(cell_index * SPRITE_CELL_SIZE, 0, SPRITE_CELL_SIZE, SPRITE_CELL_SIZE)


## HuntingManager가 조준 판정(catch_bar) 도중 도망 이동을 멈추려고 부른다 -
## 안 그러면 판정 중에도 계속 도망쳐서 바가 동물이랑 같이 화면 밖으로
## 밀려난다.
## HuntingManager._nearest_animal()이 조준 대상 후보를 고를 때 부른다 -
## 도망치는 동안엔 조준 자체가 안 되게 한다(사용자 지시, 2026-08-31 -
## "토끼가 도망치는 동안은 조준이 안되게 하는건 어때?") - 그러면 아직 눈치
## 못 챈 짧은 접근 구간(CATCH_RADIUS~DETECTION_RADIUS 사이)에서만 조준
## 기회가 생기고, 한번 도망치기 시작하면 STOP_FLEEING_RADIUS를 벗어나 다시
## 진정될 때까지는 못 잡는다 - "미친듯이 쫓아가면서 E만 누르면 항상 조준됨"
## 문제를 반경 값 조정 없이 해결.
func is_fleeing() -> bool:
	return _fleeing


func set_paused(value: bool) -> void:
	_paused = value
	if value:
		_fleeing = false
		_recovering = false
		_wandering = false
		_set_pose(RABBIT_IDLE_CELL_INDEX)


func _physics_process(delta: float) -> void:
	## npc_sprite.gd와 동일한 규칙(사용자 리포트, 2026-08-30 - "인벤 누르면
	## 시간 멈춘건데 왜 토끼들이 돌아다니는 소리가 나") - 모달 창이 열려
	## TimeManager.is_running이 꺼진 동안은 배회/도망 이동과 그때 나는 소리도
	## 같이 멈춰야 한다. HuntingManager._paused(조준 중 등)와는 별개 조건이라
	## 둘 다 체크한다.
	if not TimeManager.is_running:
		return
	if _paused or _world_map == null or HuntingManager.player == null:
		return
	var to_self: Vector2 = position - HuntingManager.player.position
	var distance := to_self.length()
	## 이미 도망 중이면 더 넓은 STOP_FLEEING_RADIUS를 벗어나야 멈춘다(위
	## STOP_FLEEING_RADIUS 주석 참고) - 시작 판정(DETECTION_RADIUS)만 쓰면
	## 경계선에서 매 프레임 켜짐/꺼짐이 반복돼 버벅거려 보인다.
	var flee_trigger_radius := STOP_FLEEING_RADIUS if _fleeing else DETECTION_RADIUS
	if distance < flee_trigger_radius and distance > 0.001:
		_wandering = false
		if not _fleeing:
			_fleeing = true
			_set_pose(RABBIT_RUN_CELL_INDEX)
			AudioManager.play_sfx(AudioManager.SFX_RABBIT_FLEE)
		## 구석에 막혀서 중심으로 도망치기로 정한 뒤엔, 매 프레임 "막혔는지"를
		## 다시 판단하지 않고 RECOVERY_DURATION 동안 무조건 중심으로 달린다
		## (사용자 리포트, 2026-08-31 - "중앙으로 안간다니까" - 매 프레임
		## 재판단하면 한 프레임 중심으로 간 순간 "안 막힘"으로 판정되어 바로
		## 다음 프레임에 플레이어 반대 방향으로 되돌아가는 지그재그가 나서
		## 사실상 거의 못 움직이는 것처럼 보였다).
		if _recovering:
			_recovery_timer -= delta
			var to_center := zone_rect.get_center() - position
			if _recovery_timer <= 0.0 or to_center.length() <= 1.0:
				_recovering = false
			else:
				var center_direction := to_center.normalized()
				_face(center_direction)
				_move_clamped(center_direction * FLEE_SPEED * delta)
				return
		var flee_direction := to_self / distance
		_face(flee_direction)
		_move_clamped(flee_direction * FLEE_SPEED * delta)
		## 존 구석(특히 대각선 꼭짓점)에 몰려서 "플레이어 반대 방향"이 그대로
		## 존 밖을 향하면(clamp에 막혀 실제로는 거의 못 움직임) 계속 그 방향만
		## 밀어봐야 영원히 못 벗어난다(사용자 리포트, 2026-08-31 - "토끼가 맵
		## 끝으로 몰리면 더 도망갈 곳이 없어서 계속 못도망가던데") - 그 자리에서
		## 존 중심으로 달리는 "복구 모드"를 켠다(사용자 지시 - "냅다 중심으로
		## 뛰는거 괜찮은데?"). "막혔다"는 이동 거리가 아니라 "플레이어와의
		## 거리가 실제로 벌어졌는지"로 판단한다(사용자 지적 - "그러니까
		## 중앙으로 안뛰지...." - 이동 거리 기준 임계값은 너무 타이트해서
		## 살짝만 비스듬히 움직여도 조건이 거의 안 걸렸다).
		var distance_after := position.distance_to(HuntingManager.player.position)
		if distance_after <= distance and zone_rect.size != Vector2.ZERO:
			_recovering = true
			_recovery_timer = RECOVERY_DURATION
		return
	if _fleeing:
		_fleeing = false
		_recovering = false
		_set_pose(RABBIT_IDLE_CELL_INDEX)
	_process_wander(delta)


## 평소 배회 - 짧게 걷다가 잠깐 멈추기를 반복한다(사용자 지시, 2026-08-30).
func _process_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wandering = not _wandering
		if _wandering:
			_wander_direction = _pick_wander_direction()
			_set_pose(RABBIT_RUN_CELL_INDEX)
			_wander_timer = WANDER_MOVE_SECONDS
			AudioManager.play_sfx(AudioManager.SFX_RABBIT_WANDER)
		else:
			_set_pose(RABBIT_IDLE_CELL_INDEX)
			_wander_timer = randf_range(WANDER_IDLE_MIN_SECONDS, WANDER_IDLE_MAX_SECONDS)
	if not _wandering:
		return
	_face(_wander_direction)
	_move_clamped(_wander_direction * WANDER_SPEED * delta)


## 스폰 지점에서 너무 멀어졌으면 되돌아가는 방향, 아니면 임의 방향.
func _pick_wander_direction() -> Vector2:
	var away_from_spawn := position - _spawn_position
	if away_from_spawn.length() > WANDER_RADIUS:
		return -away_from_spawn.normalized()
	return Vector2.from_angle(randf() * TAU)


func _face(direction: Vector2) -> void:
	if absf(direction.x) > 0.01:
		_sprite.flip_h = direction.x < 0.0


## 사용자 지시, 2026-08-31 - "토끼는 충돌판정 없게해줘 걸리니까 영원히
## 도망 못간다": 벽/나무/건물에 도망 방향이 그대로 가로막히면 제자리에
## 갇힌 채 플레이어가 계속 다가올 수 있었다 - is_cell_blocked() 검사를
## 없앴다. 대신 맵/존 밖으로 완전히 사라져버리는 일(사용자 리포트,
## 2026-08-31 - "토끼들이 맵 밖으로 사라져버리네", 이어서 "존 안에서만
## 도망가야지 냅다 존 밖까지 토끼가 벗어나버리잖아")은 막아야 해서, HuntZone
## 사각형(zone_rect) 안으로 위치를 clamp한다 - zone_rect가 없는 예외적인
## 경우(스폰 경로를 안 거친 테스트 등)만 맵 전체 픽셀 범위로 대신 clamp한다.
## 실제로 움직인 거리(clamp 이후)를 돌려준다 - 도망 로직이 "이 방향으로는
## 거의 못 움직였다"를 판단하는 데 쓴다.
func _move_clamped(delta_movement: Vector2) -> Vector2:
	var before := position
	position += delta_movement
	if zone_rect.size != Vector2.ZERO:
		position.x = clampf(position.x, zone_rect.position.x, zone_rect.position.x + zone_rect.size.x)
		position.y = clampf(position.y, zone_rect.position.y, zone_rect.position.y + zone_rect.size.y)
	elif _world_map != null:
		var map_size: Vector2i = _world_map.get_map_size()
		position.x = clampf(position.x, 0.0, float(map_size.x))
		position.y = clampf(position.y, 0.0, float(map_size.y))
	return position - before
