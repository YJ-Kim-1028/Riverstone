extends Node2D
class_name LightingLayer

## 저녁 조명 연출 - 17시부터 서서히 어두워지기 시작해 20시에 완전히
## 어두워진다(사용자 확정, 밤 브금 전환 시각과 맞춤). TimeManager.NIGHT_EVENT_
## HOUR(22시, 공포 이벤트 트리거)와는 별개의 순수 시각 연출이라 여기서
## 독립적으로 시간을 계산한다. CanvasModulate로 전체 화면(HomeMap/Player가
## 속한 기본 캔버스)을 어둡게 깔고, WorldMap이 "Light" 레이어에서 뽑아준
## 가로등 위치(get_light_source_positions - 등롱이 실제로 있는 맨 윗칸)에
## PointLight2D를 놓아 그 어둠을 뚫고 빛나게 한다. UI는 별도 CanvasLayer라
## 이 어둠의 영향을 받지 않는다.

const DUSK_START_HOUR := 17
const NIGHT_FULL_HOUR := 20
const NIGHT_COLOR := Color(0.25, 0.28, 0.45)
const INDOOR_COLOR := Color(0.72, 0.7, 0.68)
const LIGHT_TEXTURE_SIZE := 128
const LIGHT_RADIUS := 56.0
const LIGHT_COLOR := Color(1.0, 0.85, 0.55)
const LIGHT_ENERGY := 0.8

@onready var _canvas_modulate: CanvasModulate = $CanvasModulate

var _lights: Array[PointLight2D] = []
var _light_texture: GradientTexture2D = _build_light_texture()
var _is_indoor := false


func _ready() -> void:
	TimeManager.minute_passed.connect(_on_minute_passed)
	_update_darkness(TimeManager.current_hour, TimeManager.current_minute)


## main.gd가 맵을 새로 불러올 때마다 호출한다 - 이전 맵의 조명을 지우고
## 새 맵의 get_light_source_positions()로 다시 만든다. is_indoor는 실내
## 맵인지(가로등처럼 밤에만 켜지는 게 아니라 실내 전등처럼 항상 켜져
## 있어야 하는지) 구분하는 값 - main.gd가 map_id의 "_interior" 여부로 넘겨준다.
func rebuild_lights(world_map: WorldMap, is_indoor: bool) -> void:
	_is_indoor = is_indoor
	for light in _lights:
		light.queue_free()
	_lights.clear()
	for light_position in world_map.get_light_source_positions():
		var light := PointLight2D.new()
		light.texture = _light_texture
		light.color = LIGHT_COLOR
		light.texture_scale = LIGHT_RADIUS / (LIGHT_TEXTURE_SIZE * 0.5)
		light.position = light_position
		add_child(light)
		_lights.append(light)
	_update_darkness(TimeManager.current_hour, TimeManager.current_minute)


func _on_minute_passed(hour: int, minute: int) -> void:
	_update_darkness(hour, minute)


## 실내 맵은 바깥 낮/밤과 상관없이 방 안 전등이 항상 켜져 있어야 해서,
## CanvasModulate를 시간과 무관하게 INDOOR_COLOR로 고정하고 조명도 항상
## 최대 밝기로 고정한다. 완전한 흰색(안 어두워짐)으로 두면 전등이 켜져도
## 티가 안 나서, 기본 실내를 살짝 어둡게 깔아 조명이 실제로 밝아 보이게
## 한다. 실외 맵만 19시~21시 사이에 서서히 어두워지고 가로등도 그 어둠에
## 맞춰 밝아진다.
func _update_darkness(hour: int, minute: int) -> void:
	if _is_indoor:
		_canvas_modulate.color = INDOOR_COLOR
		for light in _lights:
			light.energy = LIGHT_ENERGY
		return
	var darkness := _compute_darkness(hour, minute)
	_canvas_modulate.color = Color.WHITE.lerp(NIGHT_COLOR, darkness)
	for light in _lights:
		light.energy = LIGHT_ENERGY * darkness


func _compute_darkness(hour: int, minute: int) -> float:
	var minutes_since_dusk := (hour - DUSK_START_HOUR) * 60 + minute
	var transition_minutes := (NIGHT_FULL_HOUR - DUSK_START_HOUR) * 60
	return clampf(float(minutes_since_dusk) / float(transition_minutes), 0.0, 1.0)


## 에셋 파일 없이 런타임에 만드는 부드러운 원형 그라디언트 - 가로등 불빛
## 모양으로 쓴다(assets/ 폴더에 새 이미지 파일을 추가하지 않기 위함).
func _build_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = LIGHT_TEXTURE_SIZE
	texture.height = LIGHT_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
