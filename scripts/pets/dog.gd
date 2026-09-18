extends Node2D
class_name Dog

## 새 파일 - 셰퍼드 호감도 50 이벤트로 받는 강아지(사용자 지시,
## 2026-09-16). cat.gd와 같은 배회/따라다니기 상태머신 구조를 그대로
## 따르되, "앉기" 대신 "짖기"(bark - 남쪽 방향 그림만 있음)를 쓴다는 점만
## 다르다 - 강아지는 고양이와 달리 비가 와도 계속 Home.tmx 밖에 있는다
## (DogWorldManager가 날씨 분기 없이 처리).

const WANDER_SPEED := 20.0
const FOLLOW_SPEED := 70.0
## 이 거리 안에 플레이어가 들어오면 배회를 멈추고 따라다니기 시작한다.
const NOTICE_RADIUS := 96.0
## 따라다니는 중에 플레이어가 이 거리보다 멀어지면(맵 반대편으로 뛰어가는 등)
## 쫓아가는 걸 포기하고 다시 배회 상태로 돌아간다.
const GIVE_UP_RADIUS := 220.0
## 따라다닐 때 플레이어 위에 완전히 겹치지 않도록 두는 여유 거리(사용자
## 리포트, 2026-09-16 - "너무 사용자 발 바로옆에 따라와서 이상해 약간의
## 거리가 있는게 낫지" - 18에서 32로 늘림).
const FOLLOW_STOP_DISTANCE := 32.0
## 이 거리를 넘어야 다시 움직이기 시작한다(FOLLOW_STOP_DISTANCE보다 크게
## 잡아 여유 구간을 둠) - 딱 32px 경계에서 멈췄다/움직였다를 반복하며
## 버벅거리던 문제(사용자 리포트, 2026-09-17 - "나 따라올때 너무
## 버벅거려") 수정용 히스테리시스.
const FOLLOW_RESUME_DISTANCE := 48.0
const WANDER_RADIUS := 56.0
const REACH_TARGET_DISTANCE := 4.0
## 목적지가 벽 너머라 실제로는 못 가는 자리일 수 있다 - 이 시간 안에 도착
## 못 하면 포기하고 새 목적지를 고른다(cat.gd와 동일한 버그, 사용자 리포트
## 2026-09-16 - "갈 수 없는 곳인데 자꾸 위로만 가려고 하니까... 멍청해보여").
const MAX_WANDER_TRAVEL_SECONDS := 4.0
## 배회 중 목적지에 도착해서 쉬는 동안, 서 있기 대신 짖을 확률과 지속 시간
## (사용자 지시, 2026-09-16 - "짖는 gif가 있어"). 짖는 그림은 남쪽(정면)
## 방향만 있어서, 짖을 땐 실제로 어느 방향을 보고 있었든 강제로 남쪽을
## 보게 한다.
const BARK_CHANCE := 0.35
const BARK_DURATION_MIN := 2.0
const BARK_DURATION_MAX := 3.5
const STAND_PAUSE_MIN := 1.5
const STAND_PAUSE_MAX := 4.0
## 클릭하면 짖는 소리뿐 아니라 짖는 애니메이션도 나오게(사용자 지시,
## 2026-09-16 - "클릭해서 짖을 때 bark 애니메이션 나오면 좋겠어") - 이
## 시간 동안은 배회/따라다니기를 멈추고 강제로 짖는 자세를 보여준다.
const CLICK_BARK_DURATION := 1.5
## _update_facing()의 방향 전환 히스테리시스 배율 - 값을 키울수록 축이
## 잘 안 바뀌어서(더 안정적) 대각선 근처에서 덜 흔들리지만, 실제로 방향이
## 바뀔 때 반응이 조금 늦어진다.
const FACING_SWITCH_BIAS := 1.3
## 마우스가 이 반경 안에 들어오면 이름표를 보여준다(사용자 지시, 2026-09-16
## - "마우스 갖다대면 이름 떴으면 좋겠는뎀"). position(발밑 원점) 기준
## 반경이라, 실제로 보이는 몸통/머리는 원점보다 위쪽(-y)에 있다 - 반경만
## 원점 기준으로 좁게 잡으면 몸통 위에 마우스를 올려도 안 뜨는 버그가
## 있었다(cat.gd와 동일한 버그, 사용자 리포트 2026-09-16 "이름 안더") -
## 판정 중심을 몸통 쪽으로 올리고 반경도 전체 스프라이트를 덮도록 넉넉하게
## 잡았다. 강아지가 고양이보다 커야 한다는 지시(2026-09-16 - "강아지는
## 더 커야할거같앜ㅋㅋㅋㅋ 고양이보단 커야해서")로 스프라이트 스케일을
## 0.6으로 키운 만큼 반경도 같이 키움.
const HOVER_NAME_CENTER_OFFSET_Y := -12.0
const HOVER_NAME_RADIUS := 24.0
## 클릭할 때(하루 한 번만) 호감도가 오르는 효과(사용자 지시, 2026-09-16 -
## "강아랑 고양도 호감도 있었으면 좋겠어... 하루 한 번 클릭 횟수. 호감도가
## 오를 때만 강아 머리 위에 하트 이모지 뜨면 좋겠어") - affection_panel.gd
## 의 하트 아이콘을 그대로 재사용한 세계공간 이모트.
const HEART_TEXTURE := preload("res://assets/ui/icon_heart_full.png")
const HEART_EMOTE_RISE := 12.0
const HEART_EMOTE_DURATION := 1.0

var _world_map: WorldMap = null
var _player: Node2D = null
## 이 강아지를 준 NPC id("shepherd") - register_pet_click()에 호감도를 누구
## 앞으로 쌓을지 알려주는 데 쓴다.
var _giver_npc_id := ""
var _home_position := Vector2.ZERO
var _wander_target := Vector2.ZERO
var _wander_pause_timer := 0.0
var _wander_travel_timer := 0.0
var _pause_active := false
var _barking := false
var _is_moving := false
var _following := false
var _forced_bark_timer := 0.0
## FOLLOW_STOP_DISTANCE~FOLLOW_RESUME_DISTANCE 사이에서 멈춰있는 중인지 -
## true인 동안은 FOLLOW_RESUME_DISTANCE를 넘어야만 다시 움직인다.
var _follow_parked := false
## HD_DIRECTION_GROUP_INDEX(player.gd)와 같은 규칙 - south=(0,1), north=(0,-1),
## west=(-1,0), east=(1,0).
var facing := Vector2i(0, 1)

@onready var _sprite: AnimatedSprite2D = get_node_or_null("Sprite") as AnimatedSprite2D
@onready var _name_label: Label = get_node_or_null("NameLabel") as Label


func _ready() -> void:
	_home_position = position
	_pick_new_wander_target()
	_update_animation()


func set_world_map(world_map: WorldMap) -> void:
	_world_map = world_map


func set_player(player: Node2D) -> void:
	_player = player


func set_pet_name(pet_name: String) -> void:
	if _name_label != null:
		_name_label.text = pet_name


func set_giver_npc_id(npc_id: String) -> void:
	_giver_npc_id = npc_id


func _physics_process(delta: float) -> void:
	## 스폰되는 순간 Player 노드가 아직 트리에 없어서 set_player()가 null을
	## 받으면, 그 뒤로 다시는 안 채워져서 영영 안 따라다니는 버그가 있었다
	## (사용자 리포트, 2026-09-16 - "시작하자마자는 안따라다니네... 어디
	## 갔다가 돌아와야지만") - 매 프레임 스스로 다시 찾아보게 해서
	## 외부 트리거 없이도 저절로 복구되게 한다.
	if _player == null and _world_map != null:
		_player = _world_map.get_node_or_null("Player")
	if _forced_bark_timer > 0.0:
		_forced_bark_timer -= delta
		_barking = true
		facing = Vector2i(0, 1)
		_is_moving = false
		_update_animation()
		_update_name_label_visibility()
		return
	if _player == null:
		return
	var distance_to_player := position.distance_to(_player.position)
	if _following:
		if distance_to_player >= GIVE_UP_RADIUS:
			_following = false
			_pick_new_wander_target()
	elif distance_to_player <= NOTICE_RADIUS:
		_following = true
	_is_moving = false
	if _following:
		_process_follow(distance_to_player, delta)
	else:
		_process_wander(delta)
	_update_animation()
	_update_name_label_visibility()


## 사용자 지시, 2026-09-16 - "강아지랑 고양이 누를 때 소리 나면 좋겠어".
## set_input_as_handled()는 일부러 안 부른다 - 클릭이 furniture 배치 등
## 다른 시스템으로도 그대로 전달돼야 한다.
func _unhandled_input(event: InputEvent) -> void:
	if _world_map == null:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mouse_world: Vector2 = _world_map.get_global_mouse_position()
	var check_center := global_position + Vector2(0, HOVER_NAME_CENTER_OFFSET_Y)
	if check_center.distance_to(mouse_world) <= HOVER_NAME_RADIUS:
		AudioManager.play_sfx(AudioManager.SFX_DOG)
		_forced_bark_timer = CLICK_BARK_DURATION
		if not _giver_npc_id.is_empty() and NPCManager.register_pet_click(_giver_npc_id):
			_show_heart_emote()


## 하트 아이콘 하나를 몸통 위에 띄워서 위로 떠오르며 사라지게 한다 -
## 호감도가 실제로 오른 클릭에만 호출된다(하루 한 번).
func _show_heart_emote() -> void:
	var heart := Sprite2D.new()
	heart.texture = HEART_TEXTURE
	heart.position = Vector2(0, HOVER_NAME_CENTER_OFFSET_Y)
	add_child(heart)
	var tween := create_tween()
	tween.tween_property(heart, "position:y", heart.position.y - HEART_EMOTE_RISE, HEART_EMOTE_DURATION)
	tween.parallel().tween_property(heart, "modulate:a", 0.0, HEART_EMOTE_DURATION)
	tween.tween_callback(heart.queue_free)


func _process_follow(distance_to_player: float, delta: float) -> void:
	_barking = false
	if distance_to_player <= FOLLOW_STOP_DISTANCE:
		_follow_parked = true
		return
	if _follow_parked and distance_to_player < FOLLOW_RESUME_DISTANCE:
		return
	_follow_parked = false
	var direction := (_player.position - position).normalized()
	_update_facing(direction)
	_move(direction * FOLLOW_SPEED * delta)
	_is_moving = true


func _process_wander(delta: float) -> void:
	if position.distance_to(_wander_target) <= REACH_TARGET_DISTANCE:
		if not _pause_active:
			_pause_active = true
			_barking = randf() < BARK_CHANCE
			if _barking:
				facing = Vector2i(0, 1)
				_wander_pause_timer = randf_range(BARK_DURATION_MIN, BARK_DURATION_MAX)
			else:
				_wander_pause_timer = randf_range(STAND_PAUSE_MIN, STAND_PAUSE_MAX)
		_wander_pause_timer -= delta
		if _wander_pause_timer <= 0.0:
			_pick_new_wander_target()
		return
	_wander_travel_timer += delta
	if _wander_travel_timer >= MAX_WANDER_TRAVEL_SECONDS:
		_pick_new_wander_target()
		return
	var direction := (_wander_target - position).normalized()
	_update_facing(direction)
	_move(direction * WANDER_SPEED * delta)
	_is_moving = true


func _pick_new_wander_target() -> void:
	var offset := Vector2(randf_range(-WANDER_RADIUS, WANDER_RADIUS), randf_range(-WANDER_RADIUS, WANDER_RADIUS))
	_wander_target = _home_position + offset
	_pause_active = false
	_barking = false
	_wander_travel_timer = 0.0


## 대각선 대신 더 큰 축 하나만 바라보게 한다(4방향 스프라이트 전제).
## direction은 정규화된 벡터라 성분이 대부분 소수(0.6, 0.8 등)라서 int()로
## 자르면 거의 항상 0이 되고 signi(0)==0이 되는 버그가 있었다(사용자 리포트,
## 2026-09-16 - "걸어가는 방향에 따라 다른 애니메이션이 보여야하는데
## 그렇지도 않아") - 부호만 직접 비교해서 고쳤다.
## 목적지가 대각선 방향이면 x/y 성분이 비슷비슷해서, 매 프레임 재계산할 때
## 우세한 축이 남<->동처럼 계속 뒤집히고 그때마다 애니메이션이 처음부터
## 다시 재생돼 버벅거려 보였다(사용자 리포트, 2026-09-16 - "걷는 애니메이션
## ㅈㄴ 버벅거려") - 지금 보고 있는 축을 유지하다가, 반대 축이 확실히
## 우세해질 때만(FACING_SWITCH_BIAS배 이상) 전환하도록 히스테리시스를 줬다.
func _update_facing(direction: Vector2) -> void:
	var was_horizontal := facing.x != 0
	var use_horizontal: bool
	if was_horizontal:
		use_horizontal = not (absf(direction.y) > absf(direction.x) * FACING_SWITCH_BIAS)
	else:
		use_horizontal = absf(direction.x) > absf(direction.y) * FACING_SWITCH_BIAS
	if use_horizontal:
		facing = Vector2i(1 if direction.x > 0.0 else -1, 0)
	else:
		facing = Vector2i(0, 1 if direction.y > 0.0 else -1)


## 벽/가구에 안 걸리게 x/y축을 따로 검사한다(player.gd의 축별 분리 이동과
## 같은 방식) - 한 축이 막히면 그 축만 멈추고 나머지 축으로는 계속 움직인다.
func _move(delta_position: Vector2) -> void:
	if delta_position == Vector2.ZERO:
		return
	var next_x := Vector2(position.x + delta_position.x, position.y)
	if _world_map == null or not _world_map.is_cell_blocked(next_x):
		position.x = next_x.x
	var next_y := Vector2(position.x, position.y + delta_position.y)
	if _world_map == null or not _world_map.is_cell_blocked(next_y):
		position.y = next_y.y


func _update_name_label_visibility() -> void:
	if _name_label == null or _world_map == null:
		return
	var mouse_world: Vector2 = _world_map.get_global_mouse_position()
	var check_center := global_position + Vector2(0, HOVER_NAME_CENTER_OFFSET_Y)
	_name_label.visible = check_center.distance_to(mouse_world) <= HOVER_NAME_RADIUS


func _update_animation() -> void:
	if _sprite == null:
		return
	var anim_name := "bark_south" if _barking else "%s_%s" % [("walk" if _is_moving else "idle"), _direction_name(facing)]
	if _sprite.animation != StringName(anim_name):
		_sprite.play(anim_name)


func _direction_name(direction: Vector2i) -> String:
	if direction.y > 0:
		return "south"
	if direction.y < 0:
		return "north"
	if direction.x < 0:
		return "west"
	return "east"
