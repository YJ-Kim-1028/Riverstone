extends Node2D

## new_cooking_system.md 3.3 - 조리기구 4곳 위에 아주 작은 진행바를 띄워서,
## 조리기구 화면을 안 열어도 진행 상황을 알 수 있게 한다. restaurant_dish_layer.gd와
## 같은 패턴(맵 전환에 반응, 이 맵이 아니면 아무것도 안 함).

const RESTAURANT_MAP_ID := "restaurant_interior"
const STATION_IDS: Array[String] = ["cooking_area1", "cooking_area2", "cooking_area3", "cooking_area4"]
## 사용자가 직접 확인해서 알려준 좌표(조리기구 그림 위치에 맞춤) - 나중에
## 테스트하면서 조정될 수 있다.
const STATION_POSITIONS := {
	"cooking_area1": Vector2(32, 72),
	"cooking_area2": Vector2(32, 102),
	"cooking_area3": Vector2(32, 128),
	"cooking_area4": Vector2(32, 150),
}
const BAR_OFFSET := Vector2(-7, -16)
const Z_INDEX := 8 ## player.tscn/npc_sprite.tscn과 같은 z_index (restaurant_dish_layer.gd 참고).
## 기구별 진행바 색(사용자 지정 헥스값) - 전부 같은 색이라 진행 상황을 구분하기
## 어렵다는 피드백으로 기구마다 다르게 칠한다.
const BAR_COLORS := {
	"cooking_area1": Color(0xc4 / 255.0, 0x7a / 255.0, 0x2e / 255.0), # 냄비
	"cooking_area2": Color(0x95 / 255.0, 0x53 / 255.0, 0x1a / 255.0), # 프라이팬
	"cooking_area3": Color(0x6b / 255.0, 0x8f / 255.0, 0x3a / 255.0), # 도마
	"cooking_area4": Color(0x4d / 255.0, 0x9c / 255.0, 0xa7 / 255.0), # 믹서기
}

var _bars: Dictionary = {}


func _ready() -> void:
	GameManager.map_changed.connect(_on_map_changed)
	_reconcile()


func _process(_delta: float) -> void:
	if GameManager.current_map_id != RESTAURANT_MAP_ID:
		return
	for station_id in STATION_IDS:
		if KitchenManager.is_busy(station_id):
			_ensure_bar(station_id)
			_bars[station_id].progress = KitchenManager.get_progress(station_id)
		else:
			_remove_bar(station_id)


func _on_map_changed(_map_id: String) -> void:
	_reconcile()


func _reconcile() -> void:
	if GameManager.current_map_id != RESTAURANT_MAP_ID:
		for station_id in _bars.keys().duplicate():
			_remove_bar(station_id)


func _ensure_bar(station_id: String) -> void:
	if _bars.has(station_id):
		return
	var bar := KitchenBar.new()
	bar.position = STATION_POSITIONS.get(station_id, Vector2.ZERO) + BAR_OFFSET
	bar.z_index = Z_INDEX
	bar.fill_color = BAR_COLORS.get(station_id, bar.fill_color)
	add_child(bar)
	_bars[station_id] = bar


func _remove_bar(station_id: String) -> void:
	var bar: Node = _bars.get(station_id)
	if bar != null:
		bar.queue_free()
		_bars.erase(station_id)


## 조리기구 위에 뜨는 미니 진행바 하나. 그림 없이 직접 그린다(작은 사각형
## 2개 - 배경 + 진행분).
class KitchenBar:
	extends Node2D

	var progress := 0.0:
		set(value):
			progress = clampf(value, 0.0, 1.0)
			queue_redraw()

	var fill_color := Color(0.85, 0.65, 0.25, 1.0)

	const _SIZE := Vector2(14, 3)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, _SIZE), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2(1, 1), Vector2(_SIZE.x - 2, _SIZE.y - 2) * Vector2(progress, 1.0)), fill_color)
