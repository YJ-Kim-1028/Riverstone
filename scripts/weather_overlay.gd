extends CanvasLayer

## Full-screen weather presentation: darkens the view for cloudy/rain and
## drives the rain particle emitter. Sits alongside the world (not inside
## WorldMap), so it survives map warps untouched.

const CLOUDY_DARKEN := 0.35
const RAIN_DARKEN := 0.35

@onready var _darken: ColorRect = $Darken
@onready var _rain: CPUParticles2D = $Rain

var _is_indoor := false


func _ready() -> void:
	WeatherManager.weather_changed.connect(_on_weather_changed)
	_apply_weather(WeatherManager.current_weather)


## main.gd가 맵을 새로 불러올 때마다 호출한다 - 날씨는 실외에만 적용돼야
## 해서, 실내 맵(map_id가 "_interior")에서는 흐림/비 연출을 꺼두고 맑음
## 상태로 고정한다.
func set_indoor(is_indoor: bool) -> void:
	_is_indoor = is_indoor
	_apply_weather(WeatherManager.current_weather)


func _on_weather_changed(weather: WeatherManager.Weather) -> void:
	_apply_weather(weather)


func _apply_weather(weather: WeatherManager.Weather) -> void:
	if _is_indoor:
		_darken.color.a = 0.0
		_rain.emitting = false
		return
	match weather:
		WeatherManager.Weather.SUNNY:
			_darken.color.a = 0.0
			_rain.emitting = false
		WeatherManager.Weather.CLOUDY:
			_darken.color.a = CLOUDY_DARKEN
			_rain.emitting = false
		WeatherManager.Weather.RAIN:
			_darken.color.a = RAIN_DARKEN
			_rain.emitting = true
