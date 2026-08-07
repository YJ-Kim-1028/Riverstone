extends Control
class_name FishingTimeBar

## 낚시 미니게임 남은 시간 바 - kitchen_progress_layer.gd의 KitchenBar와 같은
## 기법(직접 그린 배경 사각형 + 진행분 사각형, Tween/AnimationPlayer 없음).
## 거기와 달리 이건 화면 안에 고정 배치된 씬 노드라 inner class 대신 독립
## 스크립트로 둔다.

const SIZE := Vector2(60, 6)
const FILL_COLOR := Color(0.35, 0.75, 0.55, 1.0)

var progress := 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(Vector2(1, 1), Vector2(SIZE.x - 2, SIZE.y - 2) * Vector2(progress, 1.0)), FILL_COLOR)
