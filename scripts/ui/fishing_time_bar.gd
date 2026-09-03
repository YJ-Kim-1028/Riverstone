extends Control
class_name FishingTimeBar

## 낚시 미니게임 남은 시간 바 - kitchen_progress_layer.gd의 KitchenBar와 완전히
## 같은 디자인(흰 배경 + 채워진 부분 전체가 밝기 펄스로 반짝임)으로 맞췄다
## (사용자 지시, 2026-09-01 - "프로그레스바 디자인은 조리기구 시간 디자인이랑
## 똑같이"). 거기와 달리 이건 화면 안에 고정 배치된 씬 노드라 inner class 대신
## 독립 스크립트로 둔다. 가로로 줄어드는 것보다 위에서 아래로 떨어지듯 줄어드는
## 게 더 직관적이라는 피드백(플레이테스트 36번)으로 세로 방향 - 아래쪽에 고정된
## 채 남은 시간만큼의 높이만 채워서, 시간이 줄수록 물이 빠지듯 위쪽부터 사라진다.

const SIZE := Vector2(6, 60)
const BG_COLOR := Color(0.95, 0.95, 0.95, 0.9)
const FILL_COLOR := Color(0.35, 0.75, 0.55, 1.0)
const SPARKLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var progress := 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), BG_COLOR)
	var inner_height := SIZE.y - 2
	var fill_height := inner_height * progress
	if fill_height <= 0.0:
		return
	var fill_rect := Rect2(Vector2(1, 1 + inner_height - fill_height), Vector2(SIZE.x - 2, fill_height))
	draw_rect(fill_rect, FILL_COLOR)
	_draw_sparkle(fill_rect)


## kitchen_progress_layer.gd의 KitchenBar._draw_sparkle()과 동일 - 채워진 부분
## 전체가 밝기 펄스로 반짝이게 흰 반투명 레이어를 겹쳐 그린다.
func _draw_sparkle(fill_rect: Rect2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var glow := sin(t * 6.0) * 0.5 + 0.5
	draw_rect(fill_rect, Color(SPARKLE_COLOR, glow * 0.35))
