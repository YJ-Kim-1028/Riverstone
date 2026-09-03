extends Node2D

## 사냥 포획 판정 바 - 플레이어의 자식으로 붙어서 그 머리 위에 떠 있는다
## (사용자 지시, 2026-08-30 - "토끼 머리 위로 움직이는 게 뜨는 게 아니라,
## 사용자 머리 위에 떠야 돼. 그래야 더 잘보여" - 동물 쪽에 붙이면 도망/이탈
## 중 화면 구석으로 밀려나기 쉬워서 플레이어 쪽으로 옮김). player.gd의
## EMOTE_OFFSET(0, -FRAME_HEIGHT-6 = -38)과 같은 높이대를 참고해 머리 위로
## 잡았다. HuntingManager.get_marker_ratio()/get_sweet_spot_range()를 매
## 프레임 읽어 그리기만 하고, 판정 로직은 전부 HuntingManager 쪽에 있다
## (이 노드는 순수 표시용). 텍스처 에셋 없이 draw_* 만으로 그린다.

const BAR_SIZE := Vector2(28, 4)
const VERTICAL_OFFSET := Vector2(-14, -42)

const BORDER_COLOR := Color(0.95, 0.85, 0.25, 1.0)
const BG_COLOR := Color(0.95, 0.95, 0.95, 0.9)
const BG_SHINE_COLOR := Color(1.0, 1.0, 1.0, 0.6)

const SWEET_SPOT_COLOR := Color(0.35, 0.85, 0.45, 1.0)
const SPARKLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)

const MARKER_COLOR := Color(1.0, 0.3, 0.3, 1.0)
const MARKER_WIDTH := 1.0


func _ready() -> void:
	position = VERTICAL_OFFSET


func _process(_delta: float) -> void:
	if HuntingManager.is_aiming():
		queue_redraw()


func _draw() -> void:
	_draw_frame()
	var sweet_rect := _sweet_spot_rect()
	_draw_sweet_spot(sweet_rect)
	_draw_sparkles(sweet_rect)
	_draw_marker()


## 노란 테두리 + 안쪽 흰 배경 + 위쪽 하이라이트 한 줄(픽셀 베벨 느낌).
func _draw_frame() -> void:
	draw_rect(Rect2(Vector2(-1, -1), BAR_SIZE + Vector2(2, 2)), BORDER_COLOR)
	draw_rect(Rect2(Vector2.ZERO, BAR_SIZE), BG_COLOR)
	draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_SIZE.x, 1)), BG_SHINE_COLOR)


func _sweet_spot_rect() -> Rect2:
	var sweet_spot: Vector2 = HuntingManager.get_sweet_spot_range()
	return Rect2(
		Vector2(sweet_spot.x * BAR_SIZE.x, 0),
		Vector2((sweet_spot.y - sweet_spot.x) * BAR_SIZE.x, BAR_SIZE.y)
	)


func _draw_sweet_spot(sweet_rect: Rect2) -> void:
	draw_rect(sweet_rect, SWEET_SPOT_COLOR)


## 스위트스팟 안에서 하얀 점 두 개가 서로 반대 위상으로 깜빡여서 반짝이는
## 느낌을 준다 - 텍스처 없이 draw_rect만으로 표현.
func _draw_sparkles(sweet_rect: Rect2) -> void:
	if sweet_rect.size.x < 3.0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var glow_a := sin(t * 6.0) * 0.5 + 0.5
	var glow_b := sin(t * 6.0 + PI) * 0.5 + 0.5
	var spark_a := sweet_rect.position + Vector2(sweet_rect.size.x * 0.25, 1)
	var spark_b := sweet_rect.position + Vector2(sweet_rect.size.x * 0.7, sweet_rect.size.y - 2)
	draw_rect(Rect2(spark_a, Vector2(1, 1)), Color(SPARKLE_COLOR, glow_a))
	draw_rect(Rect2(spark_b, Vector2(1, 1)), Color(SPARKLE_COLOR, glow_b))


## 바를 관통하는 세로선으로 마커를 표시한다. 판정은 이 선의 x좌표
## (HuntingManager.get_marker_ratio()) 딱 한 점 기준이라, 선이 두꺼우면
## "들어간 것처럼 보이는데 판정은 안 나는" 괴리가 생긴다(사용자 리포트) -
## 얇게 유지한다.
func _draw_marker() -> void:
	var marker_x: float = HuntingManager.get_marker_ratio() * BAR_SIZE.x
	draw_rect(Rect2(Vector2(marker_x - MARKER_WIDTH / 2.0, -1), Vector2(MARKER_WIDTH, BAR_SIZE.y + 2)), MARKER_COLOR)
