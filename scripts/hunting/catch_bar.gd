extends Node2D

## 사냥 포획 판정 바 - 플레이어의 자식으로 붙어서 그 머리 위에 떠 있는다
## (사용자 지시, 2026-08-30 - "토끼 머리 위로 움직이는 게 뜨는 게 아니라,
## 사용자 머리 위에 떠야 돼. 그래야 더 잘보여" - 동물 쪽에 붙이면 도망/이탈
## 중 화면 구석으로 밀려나기 쉬워서 플레이어 쪽으로 옮김). player.gd의
## EMOTE_OFFSET(0, -FRAME_HEIGHT-6 = -38)과 같은 높이대를 참고해 머리 위로
## 잡았다. HuntingManager.get_marker_ratio()/get_sweet_spot_range()를 매
## 프레임 읽어 그리기만 하고, 판정 로직은 전부 HuntingManager 쪽에 있다
## (이 노드는 순수 표시용).

const BAR_SIZE := Vector2(24, 4)
const VERTICAL_OFFSET := Vector2(-12, -40)
const BG_COLOR := Color(0.1, 0.1, 0.1, 0.75)
const SWEET_SPOT_COLOR := Color(0.4, 0.85, 0.4, 0.9)
const MARKER_COLOR := Color(0.95, 0.25, 0.25, 1.0)
const MARKER_WIDTH := 2.0


func _ready() -> void:
	position = VERTICAL_OFFSET


func _process(_delta: float) -> void:
	if HuntingManager.is_aiming():
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BAR_SIZE), BG_COLOR)
	var sweet_spot: Vector2 = HuntingManager.get_sweet_spot_range()
	var sweet_rect := Rect2(
		Vector2(sweet_spot.x * BAR_SIZE.x, 0),
		Vector2((sweet_spot.y - sweet_spot.x) * BAR_SIZE.x, BAR_SIZE.y)
	)
	draw_rect(sweet_rect, SWEET_SPOT_COLOR)
	var marker_x: float = HuntingManager.get_marker_ratio() * BAR_SIZE.x
	draw_rect(Rect2(Vector2(marker_x - MARKER_WIDTH / 2.0, -1), Vector2(MARKER_WIDTH, BAR_SIZE.y + 2)), MARKER_COLOR)
