extends Node2D
class_name NPCSprite

## Visual stand-in for one NPC on the currently active map. Shows the real
## sprite sheet (assets/npc/sprite/*.png, 기본 16x32 프레임) and animates a
## 4방향 걷기 사이클 while walking. 시트는 방향 그룹 4개(DOWN,LEFT,RIGHT,UP
## 순서)가 나란히 있고, 그룹 하나는 [정지 1칸, 걷기 N칸]으로 구성된다 -
## 기본은 N=2(기획자가 확정한 배치, 총 12칸: 0=정면 정지, 1/2=정면 걷기,
## 3=좌측 정지, 4/5=좌측 걷기, 6=우측 정지, 7/8=우측 걷기, 9=뒷모습 정지,
## 10/11=뒷모습 걷기). data/npc/*.json의 "sprite_walk_frame_count"로 이
## N을 NPC마다 다르게 지정할 수 있다(사용자 지시, 2026-09-01 - 이샤를 AI로
## 8프레임짜리 걷기 애니메이션으로 새로 그림) - 안 쓰면 기존 2 그대로라
## 다른 NPC는 전혀 영향 없다. 실제 인덱스는 _apply_npc_id()가 계산한다.

const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
## AI 원본이 캐릭터 주변에 여백을 두고 나와서(예전 손그림은 캔버스를 꽉 채워
## 그림) 16x32 기준으로 스케일을 맞춰도 작아 보인다는 피드백(사용자 지시,
## 2026-09-02) - 고해상도 NPC(sprite_frame_width/height 지정된 NPC)만
## 더 키운다(_apply_npc_id() 참고). 1.3배로 했다가 "생각보다 크다"는
## 피드백으로 1.2배로 낮춤(같은 날). player.gd HD_SCALE과 같은 배율로
## 플레이어/NPC 크기를 통일한다.
const HD_VISUAL_BOOST := 1.2
enum Direction { DOWN, UP, LEFT, RIGHT }
## 시트 안에서 방향 그룹이 나열되는 순서(기존 12칸 배치 - 0=DOWN, 3=LEFT,
## 6=RIGHT, 9=UP - 와 동일하게 유지).
const DIRECTION_ORDER: Array[Direction] = [Direction.DOWN, Direction.LEFT, Direction.RIGHT, Direction.UP]
const DEFAULT_WALK_FRAME_COUNT := 2
## 한 방향 걷기 프레임을 처음부터 끝까지 한 바퀴 도는 데 걸리는 시간(초) -
## 프레임 전환 간격이 아니라 "전체 한 걸음 주기"를 고정해두고, 실제 프레임당
## 간격(_walk_frame_interval)은 이 값을 프레임 개수로 나눠서 정한다. 기존
## 2프레임(0.35초 간격 - 두 걷기 프레임 차이가 커서 빠르게 돌리면 걷는 게
## 아니라 춤추는 것처럼 보인다는 피드백으로 넉넉하게 잡았던 값)과 정확히
## 같은 체감 속도가 나오도록 0.35*2=0.7로 역산했다 - 프레임이 8개인 NPC
## (이샤)도 같은 한 걸음 주기를 유지하면서 프레임만 더 촘촘해진다.
const WALK_CYCLE_DURATION := 0.7
## 레스토랑에서 서빙받은 뒤 먹는 동안(RestaurantManager.EATING_DURATION_MINUTES)
## 재생하는 별도 시트(assets/npc/sprite/<sprite 파일명에서 "Sprite"를 "Eating"으로
## 바꾼 이름>.png, 정면 한 방향만 가로로 나열된 프레임들 - build_eating_sheet.ps1
## 참고) - 없는 NPC는 조용히 기존 정지/앉은 자세 그대로 유지한다(사용자 지시,
## 2026-09-05 - "요리대에서 요리 완성하고 먹는 30초동안 이 gif가 나오도록").
const EATING_FRAME_INTERVAL := 0.35
const SCENT_CENTER := Vector2(0, -FRAME_HEIGHT / 2.0)
const SCENT_COUNT := 3
const SCENT_ORBIT := Vector2(10.0, 6.0)
const SCENT_SPEED := 1.4
const SCENT_TEXTURES := {
	"blue": preload("res://assets/img/scent/ocean_scent.png"),
	"purple": preload("res://assets/img/scent/lilac_scent.png"),
	"white": preload("res://assets/img/scent/light_scent.png"),
	"gold": preload("res://assets/img/scent/gold_scent.png"),
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
## 대부분 NPC는 FRAME_WIDTH/FRAME_HEIGHT(16x32) 그대로지만, 고해상도로 새로
## 그린 NPC는 data/npc/*.json에 "sprite_frame_width"/"sprite_frame_height"를
## 지정해 더 큰 원본을 쓸 수 있다(사용자 지시, 2026-09-01 - 이샤를 AI로
## 32x64 2배 해상도로 다시 그림). 화면에 보이는 실제 크기는 항상 16x32와
## 같게 유지해야 해서, _apply_npc_id()가 이 실제 프레임 크기 대비 배율만큼
## _sprite에 보정 스케일을 건다 - 그래야 다른 NPC들과 크기가 안 어긋난다.
var _frame_width := FRAME_WIDTH
var _frame_height := FRAME_HEIGHT
## Direction -> 정지 프레임 인덱스 / Direction -> 걷기 프레임 인덱스 배열.
## _apply_npc_id()가 _walk_frame_count 기준으로 매번 다시 계산한다(기본값
## 2일 때는 기존 IDLE_FRAME/WALK_FRAMES 상수와 동일한 값이 나온다).
var _idle_frame: Dictionary = {}
var _walk_frames: Dictionary = {}
var _walk_frame_interval := WALK_CYCLE_DURATION / float(DEFAULT_WALK_FRAME_COUNT)
var _facing := Direction.DOWN
var _walk_frame_timer := 0.0
## 불리언 토글 대신 인덱스로 순환 - 걷기 프레임이 2개가 아니라 N개일 수
## 있어서(_walk_frame_count).
var _walk_frame_index := 0
var _emote_sprite: Sprite2D
var _emote_timer: Timer
## 이 NPC의 정상 걷기/정지 시트 - 먹는 동안 _atlas.atlas를 _eating_texture로
## 바꿨다가 stop_eating()에서 이걸로 되돌리는 데 쓴다.
var _normal_texture: Texture2D
var _eating_texture: Texture2D
var _eating_frame_count := 0
var _is_eating := false
var _eating_frame_index := 0
var _eating_frame_timer := 0.0
## 호감도 100 컷신(main.gd)이 이 NPC를 플레이어 쪽으로 걸어오게 만드는 그
## 한 번의 걸음만 예외적으로 시간 정지 중에도 진행되게 한다(NPCWorldManager.
## walk_npc_to_position()이 걷는 동안만 true로 세팅) - 그 컷신 자체가
## _memento_event_active로 TimeManager를 멈추는데, 아래 시간정지 체크에
## 그대로 걸리면 정작 "다가오라"고 시킨 그 걸음 자체가 못 움직인 채 얼어붙어서,
## 컷신이 끝나고 시간이 다시 흐르는 순간에야 갑자기 옆에 나타나는 것처럼 보였다
## (사용자 리포트, 2026-08-26 - "working에 서있다가 플레이어 옆으로 오는게
## 안 돼... 이벤트가 끝나고 나서야 내 옆으로 오네").
var _ignore_time_pause := false


func _ready() -> void:
	_sprite.centered = true
	## offset/scale은 실제 프레임 크기가 정해지는 _apply_npc_id()에서 맞춘다
	## (기본 16x32 NPC는 거기서 결국 이 값과 동일하게 다시 세팅됨).
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
	if not TimeManager.is_running and not _ignore_time_pause:
		return
	if _is_walking:
		_advance_walk(delta)
	_update_animation(delta)


func set_ignore_time_pause(value: bool) -> void:
	_ignore_time_pause = value


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


## RestaurantManager가 서빙 순간 호출한다(npc_world_manager.gd 경유) - 먹는
## 시트가 없는 NPC는 조용히 무시하고 기존 앉은 정지 자세 그대로 유지한다.
func start_eating() -> void:
	if _eating_texture == null or _eating_frame_count <= 0:
		return
	face_down()
	_is_eating = true
	_eating_frame_index = 0
	_eating_frame_timer = 0.0
	_atlas.atlas = _eating_texture
	_atlas.region = Rect2(0, 0, _frame_width, _frame_height)


## 다 먹었을 때(퇴장 등) 원래 시트로 되돌린다 - 이미 안 먹는 중이면 조용히 무시.
func stop_eating() -> void:
	if not _is_eating:
		return
	_is_eating = false
	_atlas.atlas = _normal_texture
	_set_frame(_idle_frame[_facing])


func is_eating() -> bool:
	return _is_eating


## 공범 엔딩 경찰서 씬(main.gd) - 어셔가 도착 지점(usher_ending)에서 좌측을
## 보고 서게 하는 용도(사용자 지시, 2026-08-26).
func face_left() -> void:
	_facing = Direction.LEFT


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
	if _is_eating:
		_eating_frame_timer += delta
		if _eating_frame_timer >= EATING_FRAME_INTERVAL:
			_eating_frame_timer -= EATING_FRAME_INTERVAL
			_eating_frame_index = (_eating_frame_index + 1) % _eating_frame_count
		_atlas.region = Rect2(_eating_frame_index * _frame_width, 0, _frame_width, _frame_height)
		return
	if _is_walking:
		_walk_frame_timer += delta
		if _walk_frame_timer >= _walk_frame_interval:
			_walk_frame_timer -= _walk_frame_interval
			_walk_frame_index += 1
		var frames: Array = _walk_frames[_facing]
		_set_frame(frames[_walk_frame_index % frames.size()])
	else:
		_walk_frame_timer = 0.0
		_walk_frame_index = 0
		_set_frame(_idle_frame[_facing])


func _set_frame(frame_index: int) -> void:
	if _atlas == null:
		return
	_atlas.region = Rect2(frame_index * _frame_width, 0, _frame_width, _frame_height)


func _apply_npc_id() -> void:
	var definition := NPCManager.get_definition(npc_id)
	var sprite_path := String(definition.get("sprite", ""))
	if sprite_path.is_empty():
		push_error("NPC has no sprite path registered: %s" % npc_id)
		return
	var texture := load(sprite_path) as Texture2D
	if texture == null:
		push_error("NPC sprite texture could not be loaded: %s" % sprite_path)
		return
	## 기본값(FRAME_WIDTH/HEIGHT)과 다른 원본 해상도를 쓰는 NPC는
	## "sprite_frame_width"/"sprite_frame_height"로 지정한다 - 없으면 기존
	## 16x32 그대로. 화면에 보이는 크기는 항상 16x32와 같아야 하므로, 그
	## 비율만큼 _sprite에 보정 스케일을 걸어 실제 원본 해상도와 무관하게
	## 다른 NPC들과 동일한 크기로 보이게 한다.
	_frame_width = int(definition.get("sprite_frame_width", FRAME_WIDTH))
	_frame_height = int(definition.get("sprite_frame_height", FRAME_HEIGHT))
	var base_scale := Vector2(FRAME_WIDTH / float(_frame_width), FRAME_HEIGHT / float(_frame_height))
	## 기본 해상도(16x32) NPC는 base_scale이 이미 1.0이라 그대로 둔다 - 같이
	## 키우면 이 NPC들만 이상하게 커진다. 고해상도 NPC만 부스트 적용.
	if _frame_width != FRAME_WIDTH or _frame_height != FRAME_HEIGHT:
		base_scale *= HD_VISUAL_BOOST
	_sprite.scale = base_scale
	_sprite.offset = Vector2(0, -_frame_height / 2.0)
	_build_frame_indices(int(definition.get("sprite_walk_frame_count", DEFAULT_WALK_FRAME_COUNT)))
	_normal_texture = texture
	_atlas = AtlasTexture.new()
	_atlas.atlas = texture
	_atlas.region = Rect2(_idle_frame[_facing] * _frame_width, 0, _frame_width, _frame_height)
	_sprite.texture = _atlas
	_load_eating_texture(sprite_path)


## "beljeSprite.png" -> "beljeEating.png"처럼 정상 시트 파일명에서 "Sprite"를
## "Eating"으로 바꾼 경로를 찾는다 - NPC마다 sprite 파일명 표기가 제각각이라
## (예: 라마는 ramaSprite.png, 모카는 mokaSprite.png) npc_id에서 바로 유도할
## 수 없어서, 이미 정상 동작하는 sprite_path를 그대로 재활용한다. 없으면
## 조용히 무시(_eating_texture null 유지) - start_eating()이 알아서 아무 것도
## 안 한다.
func _load_eating_texture(sprite_path: String) -> void:
	_eating_texture = null
	_eating_frame_count = 0
	if not sprite_path.ends_with("Sprite.png"):
		return
	var eating_path := sprite_path.replace("Sprite.png", "Eating.png")
	if not ResourceLoader.exists(eating_path):
		return
	var eating_texture := load(eating_path) as Texture2D
	if eating_texture == null:
		return
	_eating_texture = eating_texture
	_eating_frame_count = int(eating_texture.get_width() / _frame_width)


## 시트 안 방향 그룹 순서(DIRECTION_ORDER)를 따라 [정지 1칸, 걷기
## walk_frame_count칸]씩 차례로 배정한다 - walk_frame_count가 기본값 2면
## 기존 12칸 배치(0,1,2 / 3,4,5 / 6,7,8 / 9,10,11)와 완전히 같은 값이 나온다.
func _build_frame_indices(walk_frame_count: int) -> void:
	_idle_frame.clear()
	_walk_frames.clear()
	_walk_frame_interval = WALK_CYCLE_DURATION / float(walk_frame_count)
	var group_size := 1 + walk_frame_count
	for i in DIRECTION_ORDER.size():
		var direction: Direction = DIRECTION_ORDER[i]
		var base := i * group_size
		_idle_frame[direction] = base
		var walk: Array = []
		for w in walk_frame_count:
			walk.append(base + 1 + w)
		_walk_frames[direction] = walk
