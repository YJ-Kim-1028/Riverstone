extends Control
class_name FishingHitGauge

## 낚시 미니게임 필요 클릭 수를 점(pip) 게이지로 보여준다 - 기존 "4 / 6" 텍스트가
## 낚시 배경 그림 위에서 대비가 안 나오고 폰트도 5px라 잘 안 보인다는 피드백
## (플레이테스트 34번)으로 교체. 클릭 한 번 = 점 하나가 켜지는 구조라 원래도
## 불연속적인 값이라, 부드러운 진행바보다 점 게이지가 더 자연스럽다. 각 점은
## 테두리 있는 흰 칸이고, 채워진 칸은 kitchen_progress_layer.gd의 KitchenBar와
## 동일한 밝기 펄스 반짝임을 얹는다(사용자 지시, 2026-09-01 - "네모도 테두리
## 있고 반짝 빛나게").

const PIP_SIZE := Vector2(6, 6)
const PIP_GAP := 2.0
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const BG_COLOR := Color(0.95, 0.95, 0.95, 0.9)
const FILL_COLOR := Color(0.55, 0.75, 0.9, 1.0)
const SPARKLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var hit_count := 0:
	set(value):
		hit_count = value

var required_hits := 6:
	set(value):
		required_hits = maxi(value, 1)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var glow := sin(t * 6.0) * 0.5 + 0.5
	for i in required_hits:
		var x := i * (PIP_SIZE.x + PIP_GAP)
		draw_rect(Rect2(Vector2(x, 0), PIP_SIZE), BORDER_COLOR)
		var inner_rect := Rect2(Vector2(x + 1, 1), PIP_SIZE - Vector2(2, 2))
		draw_rect(inner_rect, BG_COLOR)
		if i < hit_count:
			draw_rect(inner_rect, FILL_COLOR)
			draw_rect(inner_rect, Color(SPARKLE_COLOR, glow * 0.35))
