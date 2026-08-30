extends Node2D

## 은신형 사냥감 - 가만히 있다가 플레이어가 놀람 반경 안에 GRACE_SECONDS보다
## 오래 머무르면 날아서 도망친다. 그 사이에 E로 포획 시도가 시작되면
## (HuntingManager.try_catch() -> set_paused(true)) 유예 타이머가 멈춘다 -
## 조준 중엔 도망 판정을 안 한다. 날아갈 땐 즉시 사라지지 않고 나는 포즈로
## 바꿔서 잠깐 위쪽으로 날아간 뒤 사라진다(사용자 지시, 2026-08-30 - "새가
## 날아가는" 모습이 필요하다고 재확인).

## 사용자 지시, 2026-08-30 - "새는 놀라면 바로 날아가는거로 하고, 새도 20px부터
## 알아채고 사용자한테는 22px부터 조준이 떠야 돼": rabbit_sprite.gd
## DETECTION_RADIUS와 동일한 값(HuntingManager.CATCH_RADIUS보다 살짝 좁음)으로
## 맞춘다. 사용자 지시, 2026-08-31 - "범위가 너무 좁아서 지금보다 2배는 늘려도
## 되겠다. 40px에 42px로": 20에서 40으로 확대(rabbit_sprite.gd
## DETECTION_RADIUS와 계속 동일하게 맞춤).
const STARTLE_RADIUS := 40.0
## 0.35로 올렸다가 사용자 지시로 되돌림(2026-08-31 - "0초로 해 ㅅㅂ 나한테
## 허락 안맡은 거 고치지마") - "놀라면 바로 날아간다"가 확정 사양, 반응 시간
## 부여는 요청받지 않은 임의 변경이었다.
const GRACE_SECONDS := 0.0
const FLY_AWAY_DURATION := 0.5
const FLY_AWAY_SPEED := 70.0
## 토끼/새 각각 별도 파일로(사용자 지시, 2026-08-30).
const TEXTURE_PATH := "res://assets/img/hunting/bird.png"
const SPRITE_CELL_SIZE := 32
## bird.png 칸 배치(왼쪽부터): 0=정지(앉은 모습), 1=나는 모습.
const BIRD_IDLE_CELL_INDEX := 0
const BIRD_FLY_CELL_INDEX := 1

## rabbit_sprite.gd와 동일한 이유로 이름 기반 설정(HuntingManager.AnimalType.BIRD).
var animal_type: int = 1

var _paused := false
## -1.0 = 아직 놀라지 않음(플레이어가 반경 밖). 0 이상이면 반경 안에 머문
## 누적 시간.
var _startled_elapsed := -1.0
## 날아서 도망치는 중인지 - 이 동안은 startle 판정을 멈추고 위쪽으로 이동만
## 하다가 FLY_AWAY_DURATION 뒤에 queue_free()한다.
var _escaping := false
var _escape_elapsed := 0.0
var _escape_direction := Vector2.UP

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_load_sprite()
	AudioManager.play_sfx(AudioManager.SFX_BIRD_SPAWN)


## assets/img/hunting/animal.png는 사용자가 그려야 하는 신규 에셋(assets/
## 폴더는 Claude Code 수정 금지) - 아직 없으면 load()가 null을 돌려주고
## 스프라이트만 안 보일 뿐 에러 없이 동작한다.
func _load_sprite() -> void:
	var texture: Texture2D = load(TEXTURE_PATH) as Texture2D
	if texture == null:
		return
	_sprite.texture = texture
	_sprite.region_enabled = true
	_set_pose(BIRD_IDLE_CELL_INDEX)


func _set_pose(cell_index: int) -> void:
	_sprite.region_rect = Rect2(cell_index * SPRITE_CELL_SIZE, 0, SPRITE_CELL_SIZE, SPRITE_CELL_SIZE)


## rabbit_sprite.gd의 is_fleeing()과 같은 용도(HuntingManager._nearest_animal()이
## 호출) - 새는 GRACE_SECONDS가 0이라 놀란 순간 거의 바로 사라지긴 하지만,
## 혹시 그 찰나에도 조준이 안 걸리게 일관되게 막아둔다.
func is_fleeing() -> bool:
	return _escaping


func set_paused(value: bool) -> void:
	_paused = value
	if value:
		_startled_elapsed = -1.0


func _process(delta: float) -> void:
	## rabbit_sprite.gd와 동일한 규칙(사용자 리포트, 2026-08-30 - "인벤 누르면
	## 시간 멈춘건데 왜 토끼들이 돌아다니는 소리가 나") - 모달 창이 열린 동안은
	## 놀람 판정/도망 애니메이션 모두 멈춘다.
	if not TimeManager.is_running:
		return
	if _escaping:
		_escape_elapsed += delta
		position += _escape_direction * FLY_AWAY_SPEED * delta
		if _escape_elapsed >= FLY_AWAY_DURATION:
			## 플레이어가 조준 시도를 한 게 아니라 새 스스로 놀라서 날아가
			## 사라지는 경우라 HuntingManager._finish() 경로를 안 거친다 -
			## 여기서 직접 알려주지 않으면 HuntingManager._active_animals에
			## 이미 사라진 노드 참조가 그대로 남아 개체 수 카운트가 부풀려지고
			## (리스폰이 "이미 5마리"로 착각해 영영 안 걸림) 리스폰도 예약이
			## 안 된다(사용자 리포트, 2026-08-31 - "새 그냥 훨훨 날아가버리면
			## 스폰도 다시 안된다니까").
			HuntingManager.report_self_escaped(self)
			queue_free()
		return
	if _paused or HuntingManager.player == null:
		return
	var distance := position.distance_to(HuntingManager.player.position)
	if distance > STARTLE_RADIUS:
		_startled_elapsed = -1.0
		return
	if _startled_elapsed < 0.0:
		_startled_elapsed = 0.0
		return
	_startled_elapsed += delta
	if _startled_elapsed >= GRACE_SECONDS:
		_start_escape()


## 항상 우측 대각선 위로 날아간다(사용자 지시, 2026-08-30 - "좌측대각이 아니라
## 우측 대각으로 날아가야돼") - 예전엔 플레이어 반대 방향 기준이라 접근 방향에
## 따라 좌/우가 뒤섞였는데, 새 그림이 오른쪽을 보는 한 방향뿐이라 방향도
## 고정하는 쪽이 자연스럽다.
func _start_escape() -> void:
	_escaping = true
	_escape_elapsed = 0.0
	_escape_direction = Vector2(1.0, -1.0).normalized()
	_set_pose(BIRD_FLY_CELL_INDEX)
	AudioManager.play_sfx(AudioManager.SFX_BIRD_FLUTTER)
