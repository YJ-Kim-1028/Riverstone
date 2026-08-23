@tool
extends Node2D
class_name PlayerController

signal interact_pressed
## 걷기 프레임이 토글되는(=발이 땅에 닿는) 시점마다 발생 - AudioManager가
## 매 프레임 위치로 Path/Ground 타일을 검사하는 대신 이 신호를 받은 시점에만
## 검사해서 재생하면, 타일 경계에서 떨림 없이 걸음 박자에 맞춰 발소리가 난다.
signal footstep

## NPC(WALK_SPEED=25, npc_sprite.gd)보다 3배 이상 빨랐던 80에서 낮춤 - 걷기
## 프레임 2장으로 도는 애니메이션이 "덜덜거린다"는 사용자 피드백(2026-08-08,
## WALK_FRAME_INTERVAL 주석 참고). 체감으로 맞추는 값이라 더 조정될 수 있음.
const SPEED := 50.0
const PROMPT_DEFAULT_OFFSET_Y := -46.0
const PROMPT_SCREEN_MARGIN := 2.0
const COLLISION_HALF_WIDTH := 7.0
## 16x32 캐릭터 프레임 크기에 맞춘 값(NPCSprite와 동일).
const SPRITE_HALF_WIDTH := 8.0
const SPRITE_HEIGHT := 32.0

## 실제로 쓰이는 외형은 CharacterAppearance가 합성한다(_build_appearance_texture()
## 참고) - 이건 몸 에셋 파일이 없는 방어적 상황에서만 쓰는 폴백이다.
const TEMP_NPC_SPRITE := preload("res://assets/npc/sprite/usherSprite.png")
const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
## 프레임 배치는 npc_sprite.gd와 동일(16x32, 한 줄 12칸, 좌/우 전용 정지
## 프레임 포함).
const IDLE_FRAME := {
	Vector2i(0, 1): 0, Vector2i(0, -1): 9,
	Vector2i(-1, 0): 3, Vector2i(1, 0): 6,
}
const WALK_FRAMES := {
	Vector2i(0, 1): [1, 2], Vector2i(0, -1): [10, 11],
	Vector2i(-1, 0): [4, 5], Vector2i(1, 0): [7, 8],
}
## npc_sprite.gd의 값(0.35) 그대로 썼다가, 다리가 너무 빨리 번갈아져서
## "진동하는 것처럼 보인다"는 피드백으로 늘림(SPEED도 같이 낮춤, 위 참고).
const WALK_FRAME_INTERVAL := 0.5

@onready var _interaction_prompt: Label = $InteractionPrompt
@onready var _sprite: Sprite2D = $Sprite2D
## 도구 사용 포즈 + 손 위치 아이콘 담당(scripts/player/player_tool_overlay.gd) -
## main.gd가 밭갈기/낚시 등 액션 지점에서 이 노드를 직접 start()/stop()한다.
@onready var tool_overlay: PlayerToolOverlay = $ToolOverlay

var _map_size := Vector2i.ZERO
var _movement_enabled := true
var _world_map: WorldMap = null
## 지금 바라보는 방향 - 이동 입력과 별개로 "정면"을 기억해둔다(낚시의 "정면
## 물 타일" 판정, 나중엔 농사 밭 타겟팅 등에도 재사용 가능하도록 낚시 전용
## 이름을 쓰지 않음). 매 프레임 실제 이동 벡터의 우세한 축으로 갱신한다
## (_direction_from_vector, npc_sprite.gd의 같은 함수와 동일한 방식) - 눌린
## 키 자체를 추적하면 대각선 이동 중이거나(예: 우상단 이동인데 위쪽만 보임)
## 서로 반대되는 두 키가 동시에 눌려 상쇄될 때(예: W+S를 같이 눌러 세로
## 이동은 없는데 이후 놓은 순서에 따라 엉뚱한 방향을 보이는 문제) 실제
## 이동 방향과 안 맞는 포즈가 나오는 문제가 있었다. 이동이 없을 때는(제자리
## 정지) 갱신하지 않아 마지막으로 걷던 방향을 그대로 유지한다.
var facing_direction := Vector2i(0, 1)  ## 기본값 아래
var _atlas: AtlasTexture
var _walk_frame_timer := 0.0
var _walk_frame_toggle := false

## 이동속도 버프/디버프 - data/npc/mocha.json의 buff_item(이동속도 +10%,
## 3분)처럼 아이템/이벤트가 부여하는 일시적 배율. 게임 시간(TimeManager) 기준
## 분 단위로 줄어든다 - 대화 등으로 시간이 멈추면 이 효과도 같이 멈춰야
## 자연스럽다(NPCSprite와 같은 이유).
var _speed_modifier := 1.0
var _speed_effect_minutes_remaining := 0
var _speed_effect_is_debuff := false

## AudioManager가 발소리를 "실제로 걷고 있을 때만" 재생하는 데 쓴다
## (_update_animation()의 애니메이션 전환과 같은 기준 - 걷기 프레임이 도는
## 동안에만 true).
var _is_moving := false

## 컷신 전용 스크립트 이동(walk_to() 참고) - 0이 아니면 _get_move_direction()이
## 실제 키 입력 대신 이 값을 돌려준다. 그래서 충돌/애니메이션/발소리 등
## _physics_process()의 나머지 로직은 평소 이동과 완전히 동일하게 재사용된다.
var _scripted_move_direction := Vector2.ZERO


func _ready() -> void:
	_sprite.centered = true
	_sprite.offset = Vector2(0, -FRAME_HEIGHT / 2.0)
	_atlas = AtlasTexture.new()
	_atlas.atlas = _build_appearance_texture()
	_atlas.region = Rect2(IDLE_FRAME[facing_direction] * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
	_sprite.texture = _atlas
	if not Engine.is_editor_hint():
		TimeManager.minute_passed.connect(_on_minute_passed)


## 캐릭터 생성 화면에서 고른 외형(GameManager에 저장된 색/스타일)을 CharacterAppearance로
## 합성해 NPC 스프라이트와 같은 형식(192x32, 12프레임)의 한 장짜리 텍스처로 돌려준다.
## 몸 레이어를 못 만들면(에셋 파일 없음) TEMP_NPC_SPRITE로 폴백 - 캐릭터가 아예 안 보이는
## 최악의 상황만 방지한다.
func _build_appearance_texture() -> Texture2D:
	var composite := CharacterAppearance.build_current_composite_sheet()
	if composite == null:
		return TEMP_NPC_SPRITE
	return ImageTexture.create_from_image(composite)


## 요리창/상점창 등 모달 UI가 열려있는 동안 main.gd가 호출해서 이동을 잠근다.
func set_movement_enabled(enabled: bool) -> void:
	_movement_enabled = enabled


## main.gd가 한 번 호출해서 넘겨준다 - 벽/가구 등 collision=true 타일 충돌
## 체크에 쓰인다 (WorldMap.is_cell_blocked).
func set_world_map(world_map: WorldMap) -> void:
	_world_map = world_map


func show_interaction_prompt(text: String) -> void:
	_interaction_prompt.text = text
	_interaction_prompt.visible = true


func hide_interaction_prompt() -> void:
	_interaction_prompt.visible = false


## AudioManager가 발소리 재생 여부를 판단하는 데 쓴다 - 실제로 입력을 받아
## 움직이고 있을 때만 true(정지 중엔 false, 모달 등으로 이동이 잠긴 동안도 false).
func is_moving() -> bool:
	return _is_moving


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var move_direction := _get_move_direction()
	var is_moving := _movement_enabled and move_direction != Vector2.ZERO
	_is_moving = is_moving
	if _movement_enabled:
		_move_with_collision(move_direction * SPEED * _speed_modifier * _delta)
		if is_moving:
			facing_direction = _direction_from_vector(move_direction)
	_clamp_to_map_bounds()
	_update_animation(_delta, is_moving)


## percent: +0.1이면 이동속도 +10%(버프), -0.3이면 -30%(디버프). 새 효과가
## 기존 효과를 덮어쓴다(현재 데이터상 버프/디버프가 동시에 겹칠 일이 없음).
func apply_speed_effect(percent: float, duration_minutes: int, is_debuff: bool) -> void:
	_speed_modifier = 1.0 + percent
	_speed_effect_minutes_remaining = duration_minutes
	_speed_effect_is_debuff = is_debuff


## 이샤의 디버프 해제 아이템(자양 강장제) 전용 - 지금 걸린 효과가 디버프일
## 때만 지운다. 버프 중에 잘못 마셔서 버프까지 사라지면 안 되기 때문.
func clear_debuff() -> void:
	if _speed_effect_is_debuff:
		_speed_modifier = 1.0
		_speed_effect_minutes_remaining = 0
		_speed_effect_is_debuff = false


## HUD가 버프/디버프 아이콘 표시 여부와 툴팁 내용을 판단하는 데 쓴다. 효과가
## 없으면 빈 Dictionary.
func get_speed_effect_info() -> Dictionary:
	if _speed_effect_minutes_remaining <= 0:
		return {}
	return {
		"percent": _speed_modifier - 1.0,
		"minutes_remaining": _speed_effect_minutes_remaining,
		"is_debuff": _speed_effect_is_debuff,
	}


func _on_minute_passed(_hour: int, _minute: int) -> void:
	if _speed_effect_minutes_remaining <= 0:
		return
	_speed_effect_minutes_remaining -= 1
	if _speed_effect_minutes_remaining <= 0:
		_speed_modifier = 1.0
		_speed_effect_is_debuff = false


## 축(x/y)을 따로 검사해서, 대각선으로 이동하다 한쪽만 막혀도 나머지 축으로는
## 계속 미끄러지듯 움직일 수 있게 한다 (완전히 막힌 것처럼 뚝 멈추지 않게).
## world_map이 아직 없으면(에디터 프리뷰 등) 충돌 없이 그냥 이동한다.
func _move_with_collision(delta_movement: Vector2) -> void:
	if _world_map == null:
		position += delta_movement
		return
	var next_position := Vector2(position.x + delta_movement.x, position.y)
	if not _is_blocked_at(next_position):
		position.x = next_position.x
	next_position = Vector2(position.x, position.y + delta_movement.y)
	if not _is_blocked_at(next_position):
		position.y = next_position.y


## 발밑 좌표 한 점만 검사하면, 몸통 폭(16px)이 그 점보다 넓어서 발은 아직
## 안 막힌 칸에 있는데 몸통 옆면은 이미 막힌 타일 그림 위로 겹쳐 보이는
## 문제가 있었다(나무/화단 같은 세로로 긴 오브젝트 옆면에서 특히 눈에 띔).
## 발밑 좌우 가장자리도 같이 검사해서 몸통 폭만큼은 막힌 칸에 못 들어가게 한다.
func _is_blocked_at(check_position: Vector2) -> bool:
	if _world_map.is_cell_blocked(Vector2(check_position.x - COLLISION_HALF_WIDTH, check_position.y)):
		return true
	if _world_map.is_cell_blocked(Vector2(check_position.x + COLLISION_HALF_WIDTH, check_position.y)):
		return true
	return _world_map.is_cell_blocked(check_position)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _interaction_prompt.visible:
		return
	_keep_prompt_on_screen()


## The prompt normally floats above the player's head. Near a map edge the
## camera can't scroll any further (see set_camera_bounds), so "above head"
## may fall outside the visible view - pull it back down into frame instead
## of letting it render off-screen.
func _keep_prompt_on_screen() -> void:
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var half_view_height: float = (get_viewport_rect().size.y / 2.0) / camera.zoom.y
	var view_top_world_y: float = camera.get_screen_center_position().y - half_view_height
	var min_offset_y: float = view_top_world_y - position.y + PROMPT_SCREEN_MARGIN
	_interaction_prompt.position.y = max(PROMPT_DEFAULT_OFFSET_Y, min_offset_y)


## 실내 맵은 Wall 레이어 충돌이 맵 가장자리보다 몇 칸 안쪽에서 미리 막아주는데,
## 광장 같은 실외 맵은 가장자리를 막는 별도 레이어가 없어서 사각형 경계
## 끝까지 그냥 걸어갈 수 있었다. 거기다 발밑(position)이 맵 경계에 딱
## 붙으면, 발 위로 솟아있는 몸통/머리 부분은 카메라 limit(맵 경계에 고정)
## 밖이라 화면에 아예 안 그려져서 캐릭터가 사라진 것처럼 보였다 - 스프라이트
## 크기만큼 여백을 두고 clamp해서 몸 전체가 항상 경계 안쪽에 있게 한다.
func _clamp_to_map_bounds() -> void:
	if _map_size == Vector2i.ZERO:
		return
	position.x = clamp(position.x, SPRITE_HALF_WIDTH, float(_map_size.x) - SPRITE_HALF_WIDTH)
	position.y = clamp(position.y, SPRITE_HEIGHT, float(_map_size.y))


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		interact_pressed.emit()


## npc_sprite.gd의 _update_animation()과 같은 방식(걷는 중이면 두 걷기 프레임을
## 번갈아, 아니면 정지 프레임) - facing_direction 기준이라 방향키를 안 눌러도
## 마지막으로 보던 방향을 그대로 유지한다.
func _update_animation(delta: float, is_moving: bool) -> void:
	if tool_overlay.is_active():
		_set_frame(tool_overlay.get_frame(facing_direction))
		tool_overlay.update_position(facing_direction)
		return
	if is_moving:
		_walk_frame_timer += delta
		if _walk_frame_timer >= WALK_FRAME_INTERVAL:
			_walk_frame_timer -= WALK_FRAME_INTERVAL
			_walk_frame_toggle = not _walk_frame_toggle
			footstep.emit()
		var frames: Array = WALK_FRAMES[facing_direction]
		_set_frame(frames[1] if _walk_frame_toggle else frames[0])
	else:
		_walk_frame_timer = 0.0
		_walk_frame_toggle = false
		_set_frame(IDLE_FRAME[facing_direction])


func _set_frame(frame_index: int) -> void:
	if _atlas == null:
		return
	_atlas.region = Rect2(frame_index * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)


func _get_move_direction() -> Vector2:
	if _scripted_move_direction != Vector2.ZERO:
		return _scripted_move_direction
	var horizontal := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var vertical := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	return Vector2(horizontal, vertical).normalized()


## 컷신에서 키 입력 없이 목표 지점까지 뛰어가게 한다(main.gd의 살인 발견
## 씬 등). _scripted_move_direction을 매 프레임 목표 방향으로 갱신하는
## 방식이라, 충돌/걷기 애니메이션/발소리 전부 평소 이동 로직 그대로 재사용됨.
## 2026-08-16: 처음엔 목표까지 직선으로 밀고 나가는 방식이었는데, 가구 등
## 오브젝트에 걸려서 못 지나가는 버그 발견(사용자 리포트) - NPC 이동에 이미
## 쓰이는 WorldMap.find_path()로 바꿔서 장애물을 실제로 피해가는 경로를
## 구한 뒤, 그 경유점을 순서대로 따라간다.
## RUN_SPEED_MULTIPLIER로 평소보다 빠르게(뛰는 느낌) 움직이고, 경유점 하나당
## SCRIPTED_WALK_TIMEOUT_SECONDS를 넘기면(벽에 낌 등 예외 상황 안전장치)
## 그 경유점은 포기하고 다음으로 넘어간다.
const RUN_SPEED_MULTIPLIER := 1.8
const SCRIPTED_WALK_ARRIVAL_DISTANCE := 3.0
const SCRIPTED_WALK_TIMEOUT_SECONDS := 10.0

func walk_to(target_position: Vector2) -> void:
	set_movement_enabled(true)
	var previous_speed_modifier := _speed_modifier
	_speed_modifier = RUN_SPEED_MULTIPLIER
	var waypoints: PackedVector2Array = _world_map.find_path(position, target_position) if _world_map != null else PackedVector2Array()
	if waypoints.is_empty():
		waypoints = PackedVector2Array([target_position])
	for waypoint in waypoints:
		var elapsed := 0.0
		while position.distance_to(waypoint) > SCRIPTED_WALK_ARRIVAL_DISTANCE and elapsed < SCRIPTED_WALK_TIMEOUT_SECONDS:
			_scripted_move_direction = (waypoint - position).normalized()
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
	_scripted_move_direction = Vector2.ZERO
	_speed_modifier = previous_speed_modifier


## npc_sprite.gd의 같은 이름 함수와 동일한 규칙 - 4방향 스프라이트로 대각선
## 이동까지 눌러 담아야 해서, 더 큰 축을 기준으로 방향을 정한다.
func _direction_from_vector(v: Vector2) -> Vector2i:
	if absf(v.x) > absf(v.y):
		return Vector2i(1, 0) if v.x > 0.0 else Vector2i(-1, 0)
	return Vector2i(0, 1) if v.y > 0.0 else Vector2i(0, -1)


## 현재 바라보는 방향으로 한 칸 앞의 월드 좌표.
func get_facing_tile_position() -> Vector2:
	return position + Vector2(facing_direction) * WorldMap.TILE_SIZE


func set_camera_bounds(map_size: Vector2i) -> void:
	_map_size = map_size
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_size.x
	camera.limit_bottom = map_size.y


## Skips the smoothing catch-up after a teleport so the camera is already
## settled on the new position before the transition fade reveals it.
func snap_camera() -> void:
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
