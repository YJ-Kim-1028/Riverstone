extends Node2D
class_name NPCSprite

## Visual stand-in for one NPC on the currently active map. Shows the real
## sprite sheet (assets/npc/sprite/*.png, 16x32 프레임, 가로 한 줄에 12칸)
## and animates a 4방향 걷기 사이클 while walking. 프레임 순서(기획자가 확정한
## 배치, 0-indexed):
##   0=정면 정지, 1/2=정면 걷기(왼발/오른발), 3=좌측 정지, 4/5=좌측 걷기(발모임/발벌림),
##   6=우측 정지, 7/8=우측 걷기(발모임/발벌림), 9=뒷모습 정지, 10/11=뒷모습 걷기(왼발/오른발)
## 좌/우 전용 정지 프레임(3, 6)이 추가되기 전에는 발이 모인 쪽 걷기 프레임을
## 정지 포즈로 재사용했었으나, 전 NPC 시트에 전용 프레임이 그려지면서 더 이상
## 재사용하지 않는다.

const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
enum Direction { DOWN, UP, LEFT, RIGHT }
const IDLE_FRAME := {
	Direction.DOWN: 0,
	Direction.UP: 9,
	Direction.LEFT: 3,
	Direction.RIGHT: 6,
}
const WALK_FRAMES := {
	Direction.DOWN: [1, 2],
	Direction.UP: [10, 11],
	Direction.LEFT: [4, 5],
	Direction.RIGHT: [7, 8],
}
## 걷기 프레임을 바꾸는 간격(초) - 두 걷기 프레임 차이가 커서 빠르게 돌리면
## 걷는 게 아니라 춤추는 것처럼 보인다는 피드백으로 넉넉하게 잡았다. 실제
## 게임에서 보면서 조정할 값.
const WALK_FRAME_INTERVAL := 0.35
const SCENT_CENTER := Vector2(0, -FRAME_HEIGHT / 2.0)
const SCENT_COUNT := 3
const SCENT_ORBIT := Vector2(10.0, 6.0)
const SCENT_SPEED := 1.4
const SCENT_TEXTURES := {
	"blue": preload("res://assets/img/scent/ocean_scent.png"),
	"purple": preload("res://assets/img/scent/lilac_scent.png"),
	"white": preload("res://assets/img/scent/light_scent.png"),
}
## 플레이어(SPEED=80.0, player.gd)보다 느리게 걸어서 좀 더 여유 있는 걸음처럼
## 보이게 한다.
const WALK_SPEED := 25.0
## 경로의 다음 지점까지 이 거리 이하로 남으면 그냥 도착한 것으로 처리한다 -
## 딱 0으로 비교하면 프레임마다 조금씩 오차가 남아서 영원히 "거의 다 왔는데
## 도착 못 함" 상태에 머무를 수 있다.
const ARRIVE_EPSILON := 1.0
## 머리 위 이모지 반응(NPCManager.request_emote() 참고) - 머리 꼭대기보다 살짝
## 위에 뜨도록 정지 프레임 기준(FRAME_HEIGHT)보다 조금 더 올린다.
const EMOTE_OFFSET := Vector2(0, -FRAME_HEIGHT - 6)
## 사용자 지시: 뜬 채로 1초 정도 유지.
const EMOTE_DISPLAY_DURATION := 1.0

@onready var _sprite: Sprite2D = $Sprite2D

var npc_id := ""
var _scent_sprites: Array[Sprite2D] = []
var _scent_time := 0.0
var _has_scent := false
var _path: PackedVector2Array = PackedVector2Array()
var _path_index := 0
var _is_walking := false
var _atlas: AtlasTexture
var _facing := Direction.DOWN
var _walk_frame_timer := 0.0
var _walk_frame_toggle := false
var _emote_sprite: Sprite2D
var _emote_timer: Timer


func _ready() -> void:
	_sprite.centered = true
	_sprite.offset = Vector2(0, -FRAME_HEIGHT / 2.0)
	_build_scent_sprites()
	_build_emote_sprite()
	TimeManager.day_changed.connect(_on_day_changed)
	if not npc_id.is_empty():
		_apply_npc_id()
	_refresh_scent()


func set_npc_id(id: String) -> void:
	npc_id = id
	if is_inside_tree():
		_apply_npc_id()
		_refresh_scent()


func _on_day_changed(_day: int, _weekday: String) -> void:
	_refresh_scent()


## Each flower drifts on its own phase-offset ellipse around the character
## so the little group looks like it's loosely floating, not orbiting in
## lockstep. 향수 효과가 없어도(_has_scent==false) 걷기 진행은 계속돼야 해서,
## 예전처럼 _process 자체를 통째로 꺼버리면 안 된다 - 향 애니메이션만 조건부로
## 돌린다.
## TimeManager.is_running이 꺼져있는 동안(대화창 등 모달로 게임 시간이 정지된
## 상태)은 걷기/애니메이션 진행도 같이 멈춘다 - 스케줄 판정(NPCWorldManager)은
## minute_passed 신호가 안 와서 이미 멈춰 있는데, 프레임 단위로 직접 이동하는
## 이 스프라이트만 안 멈추면 시간이 정지된 동안에도 NPC가 계속 걸어가 보인다.
func _process(delta: float) -> void:
	if _has_scent:
		_scent_time += delta
		for i in _scent_sprites.size():
			var phase := _scent_time * SCENT_SPEED + i * (TAU / SCENT_COUNT)
			_scent_sprites[i].position = SCENT_CENTER + Vector2(cos(phase) * SCENT_ORBIT.x, sin(phase) * SCENT_ORBIT.y)
	if not TimeManager.is_running:
		return
	if _is_walking:
		_advance_walk(delta)
	_update_animation(delta)


func _build_scent_sprites() -> void:
	for i in SCENT_COUNT:
		var sprite := Sprite2D.new()
		sprite.visible = false
		add_child(sprite)
		_scent_sprites.append(sprite)


func _build_emote_sprite() -> void:
	_emote_sprite = Sprite2D.new()
	_emote_sprite.visible = false
	_emote_sprite.centered = true
	_emote_sprite.position = EMOTE_OFFSET
	# 걷기 애니메이션이나 향수 이펙트보다 항상 위에 그려지도록 - 이 프로젝트는
	# 타일/캐릭터를 Y좌표 기준으로 자동 정렬하는데, 머리 위 아이콘은 그 정렬과
	# 무관하게 항상 최상단이어야 한다.
	_emote_sprite.z_index = 100
	add_child(_emote_sprite)
	_emote_timer = Timer.new()
	_emote_timer.one_shot = true
	_emote_timer.wait_time = EMOTE_DISPLAY_DURATION
	_emote_timer.timeout.connect(func() -> void: _emote_sprite.visible = false)
	add_child(_emote_timer)


## NPCManager.npc_emote_requested를 npc_world_manager.gd가 받아 이 NPC가 지금
## 화면에 있으면 호출한다(.call()로 이름 기반 호출 - 다른 크로스-스크립트 참조와
## 동일하게 정적 타입 캐스팅 대신 이름 기반으로 통일한 규칙을 따름).
## 텍스처를 못 찾으면(에셋 미준비) 조용히 아무 일도 하지 않는다.
## duration을 생략하면 평소처럼 EMOTE_DISPLAY_DURATION만큼만 보인다 - 살인
## 발견 씬처럼 더 오래 띄워야 하는 경우에만 넘긴다(main.gd 참고).
func show_emote(emote_id: String, duration: float = EMOTE_DISPLAY_DURATION) -> void:
	var texture := NPCManager.get_emote_icon_texture(emote_id)
	if texture == null:
		return
	_emote_sprite.texture = texture
	_emote_sprite.visible = true
	_emote_timer.wait_time = duration
	_emote_timer.start()


## Perfume gifts (data/items/items.json's scent_color) make a gifted NPC
## "wear" the scent starting the day after (see NPCManager.get_scent_color) -
## a few tiny flower sprites (assets/img/scent/*.png) drift around them for that
## one day.
func _refresh_scent() -> void:
	var color_name := NPCManager.get_scent_color(npc_id)
	var texture: Texture2D = SCENT_TEXTURES.get(color_name)
	_has_scent = texture != null
	for sprite in _scent_sprites:
		sprite.visible = _has_scent
		sprite.texture = texture


## 목표 지점까지 즉시 이동하고 걷기 상태를 해제한다 - 맵을 처음 불러왔을 때
## 원래 있던 자리에 그냥 서 있게 하거나(NPCWorldManager._populate_initial),
## 경로탐색이 실패했을 때 대체 수단으로 쓰인다.
func snap_to(world_position: Vector2) -> void:
	position = world_position
	_path = PackedVector2Array()
	_path_index = 0
	_is_walking = false


## 주어진 경로(타일 중심 좌표들, WorldMap.find_path() 결과)를 따라 걷기
## 시작한다. 경로의 첫 지점이 지금 위치랑 거의 같으면(경로탐색이 "지금 서있는
## 칸"부터 시작해서 흔히 있는 경우) 그 지점은 건너뛴다 - 안 그러면 이미 다
## 온 첫 걸음에서 잠깐 멈칫하는 것처럼 보인다.
func walk_to(path: PackedVector2Array) -> void:
	if path.is_empty():
		_is_walking = false
		return
	_path = path
	_path_index = 0
	_is_walking = true
	if _path.size() > 1 and position.distance_to(_path[0]) <= ARRIVE_EPSILON:
		_path_index = 1


func is_walking() -> bool:
	return _is_walking


## 식탁에 앉아있는 동안은 항상 정면을 보게 한다 - 마지막으로 걸어온 방향이
## 옆/뒤였다면 그 방향을 그대로 유지해서 옆을 보고 밥을 먹는 것처럼 보이면
## 안 되기 때문에(NPCWorldManager가 식당 착석이 확정될 때 호출한다).
func face_down() -> void:
	_facing = Direction.DOWN


## delta가 waypoint 사이 거리(보통 타일 한 칸, 16~22.6px)보다 큰 경우(프레임
## 드랍/랙 스파이크, 혹은 --fixed-fps로 가속한 헤드리스 테스트 등) 남는 이동
## 예산을 다음 waypoint로 이어서 계속 소모해야 한다 - 안 그러면 한 프레임에
## waypoint 하나만 이동하고 나머지 예산을 버려서, 실제로는 WALK_SPEED보다
## 느리게 걷는 것처럼 되어버린다(일반 60fps 플레이에선 delta가 워낙 작아
## 드러나지 않지만, 여전히 잠재적 버그).
func _advance_walk(delta: float) -> void:
	var budget := WALK_SPEED * delta
	while budget > 0.0:
		if _path_index >= _path.size():
			_is_walking = false
			return
		var target: Vector2 = _path[_path_index]
		var to_target := target - position
		_facing = _direction_from_vector(to_target)
		var distance := to_target.length()
		if distance <= max(budget, ARRIVE_EPSILON):
			position = target
			_path_index += 1
			budget -= distance
			if _path_index >= _path.size():
				_is_walking = false
				return
		else:
			position += to_target.normalized() * budget
			return


## AStarGrid2D의 대각선 이동까지 4방향 스프라이트로 눌러 담아야 해서, 더 큰
## 축을 기준으로 방향을 정한다(대각선이면 어느 쪽이든 자연스럽다).
func _direction_from_vector(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return Direction.RIGHT if v.x > 0.0 else Direction.LEFT
	return Direction.DOWN if v.y > 0.0 else Direction.UP


func _update_animation(delta: float) -> void:
	if _is_walking:
		_walk_frame_timer += delta
		if _walk_frame_timer >= WALK_FRAME_INTERVAL:
			_walk_frame_timer -= WALK_FRAME_INTERVAL
			_walk_frame_toggle = not _walk_frame_toggle
		var frames: Array = WALK_FRAMES[_facing]
		_set_frame(frames[1] if _walk_frame_toggle else frames[0])
	else:
		_walk_frame_timer = 0.0
		_walk_frame_toggle = false
		_set_frame(IDLE_FRAME[_facing])


func _set_frame(frame_index: int) -> void:
	if _atlas == null:
		return
	_atlas.region = Rect2(frame_index * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)


func _apply_npc_id() -> void:
	var sprite_path := String(NPCManager.get_definition(npc_id).get("sprite", ""))
	if sprite_path.is_empty():
		push_error("NPC has no sprite path registered: %s" % npc_id)
		return
	var texture := load(sprite_path) as Texture2D
	if texture == null:
		push_error("NPC sprite texture could not be loaded: %s" % sprite_path)
		return
	_atlas = AtlasTexture.new()
	_atlas.atlas = texture
	_atlas.region = Rect2(IDLE_FRAME[_facing] * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
	_sprite.texture = _atlas
