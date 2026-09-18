extends Node2D
class_name Cat

## 새 파일 - 벨제 호감도 50 이벤트로 받는 고양이(사용자 지시, 2026-09-16).
## NPCWorldManager(NPC 스케줄/경로탐색 엔진 - 기존 지시상 손대지 말고 승인
## 먼저 받아야 하는 핵심 시스템)와는 완전히 분리된 배회 전용 독립 엔티티라
## 새 파일로 뺐다. 스폰/제거는 CatWorldManager가 담당하고, 이 스크립트는
## 이미 스폰된 뒤의 이동/애니메이션만 맡는다.
## 원래 플레이어를 따라다니는 기능도 있었는데, 강아지와 동시에 따라오면
## 서로 부딪히며 버벅거리고(사용자 리포트, 2026-09-16) "고양이는 안
## 따라오는게 낫겠어"라는 지시로 배회만 하도록 뺐다 - dog.gd와 달리
## 플레이어 위치를 아예 필요로 하지 않는다.

const WANDER_SPEED := 20.0
const WANDER_RADIUS := 56.0
const REACH_TARGET_DISTANCE := 4.0
## 목적지가 벽 너머라 실제로는 못 가는 자리일 수 있다 - 이 시간(WANDER_RADIUS/
## WANDER_SPEED로 걸리는 최대 시간보다 넉넉하게 잡음) 안에 도착 못 하면
## 포기하고 새 목적지를 고른다. 없으면 벽에 막힌 채 같은 방향으로 계속
## 움직이려는 것처럼 보인다(사용자 리포트, 2026-09-16 - "갈 수 없는 곳인데
## 자꾸 위로만 가려고 하니까 뭔가 인공지능이 이상하고 멍청해보여").
const MAX_WANDER_TRAVEL_SECONDS := 4.0
## 배회 중 목적지에 도착해서 쉬는 동안, 서 있기 대신 앉아있을 확률과 지속
## 시간(사용자 지시, 2026-09-16 - "가끔 앉은 자세도 나오게"). 앉은 자세가
## 서 있는 자세보다 좀 더 오래 유지되게 해서 실제로 쉬는 느낌이 나게 했다.
const SIT_CHANCE := 0.35
const SIT_PAUSE_MIN := 3.0
const SIT_PAUSE_MAX := 6.0
const STAND_PAUSE_MIN := 1.5
const STAND_PAUSE_MAX := 4.0
## _update_facing()의 방향 전환 히스테리시스 배율(dog.gd와 동일한 버그/이유
## - "걷는 애니메이션 ㅈㄴ 버벅거려", 2026-09-16).
const FACING_SWITCH_BIAS := 1.3
## 마우스가 이 반경 안에 들어오면 이름표를 보여준다(사용자 지시, 2026-09-16
## - "마우스 갖다대면 이름 떴으면 좋겠는뎀"). position(발밑 원점) 기준
## 반경이라, 실제로 보이는 몸통/머리는 원점보다 위쪽(-y)에 있다 - 반경만
## 원점 기준으로 좁게 잡으면 몸통 위에 마우스를 올려도 안 뜨는 버그가
## 있었다(사용자 리포트, 2026-09-16 - "이름 안더") - 판정 중심을 몸통 쪽으로
## 올리고 반경도 전체 스프라이트를 덮도록 넉넉하게 잡았다.
const HOVER_NAME_CENTER_OFFSET_Y := -8.0
const HOVER_NAME_RADIUS := 16.0
## 클릭할 때(하루 한 번만) 호감도가 오르는 효과(사용자 지시, 2026-09-16 -
## "강아랑 고양도 호감도 있었으면 좋겠어... 하루 한 번 클릭 횟수. 호감도가
## 오를 때만 강아 머리 위에 하트 이모지 뜨면 좋겠어") - affection_panel.gd
## 의 하트 아이콘을 그대로 재사용한 세계공간 이모트.
const HEART_TEXTURE := preload("res://assets/ui/icon_heart_full.png")
const HEART_EMOTE_RISE := 12.0
const HEART_EMOTE_DURATION := 1.0

var _world_map: WorldMap = null
## 이 고양이를 준 NPC id("belje") - register_pet_click()에 호감도를 누구
## 앞으로 쌓을지 알려주는 데 쓴다.
var _giver_npc_id := ""
var _home_position := Vector2.ZERO
var _wander_target := Vector2.ZERO
var _wander_pause_timer := 0.0
var _wander_travel_timer := 0.0
var _pause_active := false
var _sitting := false
var _is_moving := false
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


func set_pet_name(pet_name: String) -> void:
	if _name_label != null:
		_name_label.text = pet_name


func set_giver_npc_id(npc_id: String) -> void:
	_giver_npc_id = npc_id


func _physics_process(delta: float) -> void:
	_is_moving = false
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
		AudioManager.play_sfx(AudioManager.SFX_CAT)
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


func _process_wander(delta: float) -> void:
	if position.distance_to(_wander_target) <= REACH_TARGET_DISTANCE:
		if not _pause_active:
			_pause_active = true
			_sitting = randf() < SIT_CHANCE
			_wander_pause_timer = randf_range(SIT_PAUSE_MIN, SIT_PAUSE_MAX) if _sitting else randf_range(STAND_PAUSE_MIN, STAND_PAUSE_MAX)
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
	_sitting = false
	_wander_travel_timer = 0.0


## 대각선 대신 더 큰 축 하나만 바라보게 한다(4방향 스프라이트 전제).
## direction은 정규화된 벡터라 성분이 대부분 소수(0.6, 0.8 등)라서 int()로
## 자르면 거의 항상 0이 되고 signi(0)==0이 되는 버그가 있었다(사용자 리포트,
## 2026-09-16 - "걸어가는 방향에 따라 다른 애니메이션이 보여야하는데
## 그렇지도 않아") - 부호만 직접 비교해서 고쳤다.
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
	var state_name := "idle"
	if _sitting:
		state_name = "sit"
	elif _is_moving:
		state_name = "walk"
	var anim_name := "%s_%s" % [state_name, _direction_name(facing)]
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
