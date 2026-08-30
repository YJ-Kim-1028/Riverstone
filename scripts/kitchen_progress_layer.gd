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
## player.tscn/npc_sprite.tscn 둘 다 z_index=0이다 - 8은 restaurant_dish_layer.gd가
## 이미 한 번 확인 없이 넘겨짚었다가 정정한 것과 같은 잘못된 값이었다. 이 값이
## 그대로면 불 애니메이션이 플레이어 머리 위 상호작용 프롬프트(E OO 사용)보다
## 항상 위에 그려져서 글자를 가려버린다(사용자 리포트, 2026-08-29). 프롬프트
## 라벨/아이콘은 player.tscn에 z_index=2로 별도 지정해 항상 그 위에 뜨게 했다.
const Z_INDEX := 0
## 기구별 진행바 색(사용자 지정 헥스값) - 전부 같은 색이라 진행 상황을 구분하기
## 어렵다는 피드백으로 기구마다 다르게 칠한다.
const BAR_COLORS := {
	"cooking_area1": Color(0xc4 / 255.0, 0x7a / 255.0, 0x2e / 255.0), # 냄비
	"cooking_area2": Color(0x95 / 255.0, 0x53 / 255.0, 0x1a / 255.0), # 프라이팬
	"cooking_area3": Color(0x6b / 255.0, 0x8f / 255.0, 0x3a / 255.0), # 도마
	"cooking_area4": Color(0x4d / 255.0, 0x9c / 255.0, 0xa7 / 255.0), # 믹서기
}

## 조리 중일 때 냄비/프라이팬 밑에서 불이 붙은 것처럼 2장을 번갈아 보여주는
## 애니메이션(사용자 지시, 2026-08-29 - 플레이테스트 피드백 #40). 도마/믹서기는
## 불을 안 써서 대상에서 뺐다. STATION_POSITIONS(대략적인 좌표)가 아니라
## restaurant_interior_new.tmx의 "EffectArea" 레이어에 사용자가 직접 찍어준
## cooking_area1_fire/cooking_area2_fire 사각형(그림과 정확히 같은 32x32)을
## 쓴다 - restaurant_frame_blood와 동일한 패턴(WorldMap.get_effect_area()).
const FIRE_TEXTURES := {
	"cooking_area1": [
		preload("res://assets/img/restaurant/fire_pot1.png"),
		preload("res://assets/img/restaurant/fire_pot2.png"),
	],
	"cooking_area2": [
		preload("res://assets/img/restaurant/fire_pan1.png"),
		preload("res://assets/img/restaurant/fire_pan2.png"),
	],
}
const FIRE_EFFECT_AREA_NAMES := {
	"cooking_area1": "cooking_area1_fire",
	"cooking_area2": "cooking_area2_fire",
}
const FIRE_ANIMATION := &"fire"
## 초당 프레임 전환 수 - 4면 0.25초마다 그림이 바뀐다. 체감으로 조정 가능.
const FIRE_FRAME_FPS := 4.0

@onready var _world_map: WorldMap = get_node("../HomeMap")

var _bars: Dictionary = {}
var _fires: Dictionary = {}


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
		## is_busy()는 다 익어서 꺼내기만 하면 되는 상태(is_ready())에도 계속
		## true다(꺼내기 전까지 "사용 중"으로 침) - 불이 다 익은 뒤에도 안 꺼지고
		## 계속 타고 있던 원인이었다(사용자 리포트, 2026-08-29 - "안에 돼지고기
		## 안꺼내서 이러나"). 진짜 조리 중일 때만(다 익기 전까지만) 불을 켠다.
		if KitchenManager.is_busy(station_id) and not KitchenManager.is_ready(station_id):
			_ensure_fire(station_id)
		else:
			_remove_fire(station_id)


func _on_map_changed(_map_id: String) -> void:
	_reconcile()


func _reconcile() -> void:
	if GameManager.current_map_id != RESTAURANT_MAP_ID:
		for station_id in _bars.keys().duplicate():
			_remove_bar(station_id)
		for station_id in _fires.keys().duplicate():
			_remove_fire(station_id)


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


## FIRE_TEXTURES에 등록 안 된 기구(도마/믹서기)는 조용히 아무 일도 안 한다.
## EffectArea를 아직 안 찍었을 때도 마찬가지로 조용히 스킵한다
## (restaurant_frame_blood와 동일한 안전장치, get_effect_area() 참고).
func _ensure_fire(station_id: String) -> void:
	if _fires.has(station_id) or not FIRE_TEXTURES.has(station_id):
		return
	var area_name: String = FIRE_EFFECT_AREA_NAMES.get(station_id, "")
	var area := _world_map.get_effect_area(area_name)
	if area.position == Vector2.INF:
		return
	var frames := SpriteFrames.new()
	frames.add_animation(FIRE_ANIMATION)
	frames.set_animation_loop(FIRE_ANIMATION, true)
	frames.set_animation_speed(FIRE_ANIMATION, FIRE_FRAME_FPS)
	for texture in FIRE_TEXTURES[station_id]:
		frames.add_frame(FIRE_ANIMATION, texture)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = FIRE_ANIMATION
	## AnimatedSprite2D는 기본 centered=true라 position이 그림 중심이어야 한다 -
	## EffectArea는 top-left+size라 중심으로 변환.
	sprite.position = area.position + area.size / 2.0
	sprite.z_index = Z_INDEX
	add_child(sprite)
	sprite.play()
	_fires[station_id] = sprite


func _remove_fire(station_id: String) -> void:
	var sprite: Node = _fires.get(station_id)
	if sprite != null:
		sprite.queue_free()
		_fires.erase(station_id)


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
