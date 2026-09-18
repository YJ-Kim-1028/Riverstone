extends Node2D
class_name PlayerToolOverlay

## 도구 사용 포즈 + 손 위치 아이콘 상태를 전담하는 노드. player.gd(이미
## 300줄 규칙에 걸려있는 파일)를 더 무겁게 만들지 않으려고 상태 관리까지
## 이 파일로 모았다 - player.gd는 매 프레임 is_active()/get_frame()/
## update_position()만 물어보고, 실제 시작/종료는 main.gd가 이 노드를
## 직접 호출한다(player.tool_overlay.start(...)). 아이콘은 기본적으로
## InventoryManager의 기존 인벤토리 아이콘(Tools.png 등)을 그대로
## 재사용한다(2026-08-12 사용자 결정).

## 프레임 배치는 player.gd의 IDLE_FRAME/WALK_FRAMES와 같은 시트
## (player_body.png/player_outfit.png, 2026-08-12 12~15번 칸 추가) - 방향당
## 1프레임만 있고 걷기처럼 번갈아 재생하지 않는다.
const USE_FRAME := {
	Vector2i(0, 1): 12, Vector2i(0, -1): 15,
	Vector2i(-1, 0): 13, Vector2i(1, 0): 14,
}

## 프레임(16x32) 안에서 손이 오는 대략적 위치 - player_body.png의 12~15번
## 프레임(사용 포즈)을 눈대중으로 본 값이라 정확하지 않을 수 있다. y=-16이
## 프레임 세로 중앙(발 기준 -32가 정수리, 0이 발) - 낚싯대 손잡이가 발에
## 붙어 보인다는 리포트(2026-08-12)로 4방향 다 세로를 중앙으로 올림. 실제
## 인게임에서 보고 더 어긋나면 이 값만 조정하면 된다.
const ICON_OFFSET := {
	Vector2i(0, 1): Vector2(0, -12),
	Vector2i(0, -1): Vector2(4, -20),
	Vector2i(-1, 0): Vector2(-11, -19),
	Vector2i(1, 0): Vector2(11, -19),
}

## 정면(아래쪽)을 볼 때만 도구별로 위치를 따로 올릴 수 있게 하는 예외표 -
## 사용자 지시, 2026-08-31 - "괭이나 물뿌리개등 다른 도구는 지금 위치
## 고정하고, 총만 정면 보고 있을 때 착용되는 위치 더 올릴 수 있어?": 다른
## 방향/다른 도구는 위 ICON_OFFSET을 그대로 쓰고, 여기 등록된 도구만 정면
## 볼 때 이 값으로 덮어쓴다.
const FRONT_FACING_OFFSET_OVERRIDES := {
	"hunting_rifle": Vector2(0, -16),
}

## 방향 상관없이 특정 도구 하나만 위치를 미세 조정하고 싶을 때 쓰는 가산값 -
## 다른 도구는 그대로 두고 이 도구만 옮긴다(사용자 지시, 2026-09-16 - "물뿌리개
## 아이콘만 조금 내릴 수 있어? 다른 소총이나 괭이 낚시대는 그대로 두고").
const TOOL_OFFSET_ADJUSTMENT := {
	"watering_can": Vector2(0, 3),
	"golden_watering_can": Vector2(0, 3),
}

## 인벤토리 아이콘(Tools.png 등)은 옆에서 본 사선 모양으로 그려져 있어서
## 좌/우를 볼 때는 자연스럽지만, 아래(정면)를 볼 때는 "1자로 곧게" 나와야
## 해서 회전/반전으로 흉내가 안 된다(2026-08-12 사용자 리포트). 물뿌리개/
## 낚싯대/괭이/사냥총 전부 Tools.png의 같은 열, 바로 아래 줄에 정면용 그림을
## 따로 그려 넣는 규칙이다(도구마다 기준 줄 자체는 다를 수 있음 - 예: 물뿌리개/
## 낚싯대/괭이는 1행(0-index 0)+정면 2행(0-index 1), 사냥총은 3행(0-index 2)+
## 정면 4행(0-index 3), 2026-08-30 사용자 지시) - 그래서 고정 상수가 아니라
## "그 도구의 기준 줄(icon_row, 기본 0) + 1"을 매번 계산해서 쓴다
## (_resolve_texture() 참고). 위(후면)를 볼 때는 도구를 아예 숨기는 쪽이 더
## 자연스럽다는 사용자 판단으로 아이콘을 표시하지 않는다.

## 좌/우 반전 기준: 괭이/낚싯대는 "몸통(손잡이)이 오른쪽, 날/끝이 왼쪽 아래로
## 뻗은" 방향으로 그려져 있어 오른쪽을 볼 때 그대로, 왼쪽을 볼 때만 반전하면
## 맞는다. 물뿌리개는 반대로(주둥이가 왼쪽) 그려져 있어서 그 관례가 뒤집힌다 -
## 그대로 두면 오른쪽을 볼 때도 계속 손잡이 쪽을 쥔 것처럼 보인다(2026-08-12
## 사용자 리포트). 이런 tool_id는 여기 등록해서 반전 판정을 뒤집는다.
const MIRRORED_ICON_TOOLS := ["watering_can", "golden_watering_can"]

@onready var _icon_sprite: Sprite2D = $IconSprite

var _active := false
var _tool_id := ""
## start()가 hold_seconds와 함께 건 자동 stop 타이머가, 그 사이 새로 시작된
## 포즈를 잘못 끄지 않도록 구분하는 값 - 호출마다 증가시키고, 타이머가
## 깨어났을 때 자기 번호가 최신인지 확인한다.
var _hold_token := 0


func _ready() -> void:
	_icon_sprite.centered = true
	_icon_sprite.visible = false


## tool_id는 data/items/items.json의 아이템 id(예: "hoe"). hold_seconds > 0이면
## 그 시간 뒤 자동으로 stop()한다(밭갈기처럼 한 프레임에 끝나는 즉시 액션용 -
## 자연 지속시간이 없어서 최소한 이만큼은 눈에 보이도록 붙잡아둔다). 0이면
## (기본값) 낚시처럼 호출부가 stop()을 직접 부를 때까지 유지한다(사용자 지시,
## 2026-08-12). 실제 아이콘 텍스처는 방향에 따라 달라질 수 있어 update_position()
## 에서 매번 다시 고른다.
func start(tool_id: String, hold_seconds: float = 0.0) -> void:
	_active = true
	_tool_id = tool_id
	if hold_seconds <= 0.0:
		return
	_hold_token += 1
	var token := _hold_token
	await get_tree().create_timer(hold_seconds).timeout
	if token == _hold_token:
		stop()


func stop() -> void:
	_active = false
	_tool_id = ""
	_hold_token += 1
	_icon_sprite.visible = false


func is_active() -> bool:
	return _active


func get_frame(facing_direction: Vector2i) -> int:
	return USE_FRAME[facing_direction]


## 아이콘 원본(옆에서 본 사선 모양)은 왼쪽을 볼 때 그대로 붙이면 손잡이/끝이
## 뒤바뀌어 보여서(2026-08-12 사용자 리포트) 왼쪽 방향일 때만 좌우 반전한다.
## 아래(정면)는 FRONT_ICON_ROW 전용 그림을 쓰고, 위(후면)는 아이콘을 숨긴다.
func update_position(facing_direction: Vector2i) -> void:
	if not _active:
		return
	if facing_direction == Vector2i(0, 1) and FRONT_FACING_OFFSET_OVERRIDES.has(_tool_id):
		_icon_sprite.position = FRONT_FACING_OFFSET_OVERRIDES[_tool_id]
	else:
		_icon_sprite.position = ICON_OFFSET.get(facing_direction, Vector2.ZERO)
	_icon_sprite.position += TOOL_OFFSET_ADJUSTMENT.get(_tool_id, Vector2.ZERO)
	var facing_left := facing_direction == Vector2i(-1, 0)
	_icon_sprite.flip_h = facing_left != MIRRORED_ICON_TOOLS.has(_tool_id)
	var texture := _resolve_texture(facing_direction)
	_icon_sprite.texture = texture
	_icon_sprite.visible = texture != null


func _resolve_texture(facing_direction: Vector2i) -> Texture2D:
	if facing_direction == Vector2i(0, -1):
		return null
	if facing_direction == Vector2i(0, 1):
		var base_row := int(InventoryManager.get_item_definition(_tool_id).get("icon_row", 0))
		return InventoryManager.get_item_icon_texture(_tool_id, base_row + 1)
	return InventoryManager.get_item_icon_texture(_tool_id)
