extends Node

## Owns the daily weather roll (decided every day at 09:00) and the rain-guarantee
## rules from weather.md. NPC/murder reactions to weather belong to other systems.

enum Weather { SUNNY, CLOUDY, RAIN }

signal weather_changed(weather: Weather)

const WEATHER_NAMES: Array[String] = ["맑음", "흐림", "비"]
const WEATHER_OPTIONS: Array[Weather] = [Weather.SUNNY, Weather.CLOUDY, Weather.RAIN]
const WEATHER_ROLL_WEIGHTS: Array[float] = [0.5, 0.3, 0.2]

const FIRST_RAIN_DEADLINE_DAY := 5
const MAX_DRY_DAYS := 4
const MURDER_PENDING_RAIN_DEADLINE_DAYS := 3

var current_weather: Weather = Weather.SUNNY

var _days_since_rain := 0
var _has_ever_rained := false
var _murder_pending := false
var _murder_pending_days_waited := 0


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)
	_decide_weather(TimeManager.current_day)


func set_murder_pending(pending: bool) -> void:
	_murder_pending = pending
	_murder_pending_days_waited = 0


func is_murder_pending() -> bool:
	return _murder_pending


func is_raining() -> bool:
	return current_weather == Weather.RAIN


func get_weather_name() -> String:
	return WEATHER_NAMES[current_weather]


func get_save_data() -> Dictionary:
	return {
		"weather": current_weather,
		"days_since_rain": _days_since_rain,
		"has_ever_rained": _has_ever_rained,
		"murder_pending": _murder_pending,
		"murder_pending_days_waited": _murder_pending_days_waited,
	}


func load_save_data(data: Dictionary) -> void:
	current_weather = data.get("weather", Weather.SUNNY) as Weather
	_days_since_rain = int(data.get("days_since_rain", 0))
	_has_ever_rained = bool(data.get("has_ever_rained", false))
	_murder_pending = bool(data.get("murder_pending", false))
	_murder_pending_days_waited = int(data.get("murder_pending_days_waited", 0))


func _on_day_changed(day: int, _weekday: String) -> void:
	_decide_weather(day)


## 사용자 확정(2026-08-07): 캐릭터 생성을 마치고 "생성하고 시작"을 눌러야
## 진짜 게임이 시작되는데, 그 즉시 비가 오는 건 첫인상으로 맞지 않는다 -
## 1일차는 강제 비 규칙(_must_rain)도 건너뛰고 비가 아예 나오지 않게 한다
## (맑음/흐림만 굴림). 2일차부터는 원래 확률 그대로.
func _decide_weather(day: int) -> void:
	if day <= 1:
		current_weather = _roll_first_day_weather()
	else:
		current_weather = Weather.RAIN if _must_rain(day) else _roll_weather()
	_update_rain_tracking()
	weather_changed.emit(current_weather)


## 비를 제외하고 맑음/흐림만 굴린다 - 원래 가중치(0.5/0.3)의 상대 비율을
## 그대로 유지해 정규화한 값(0.5/0.8, 0.3/0.8).
func _roll_first_day_weather() -> Weather:
	return Weather.SUNNY if randf() <= 0.625 else Weather.CLOUDY


func _must_rain(day: int) -> bool:
	if _days_since_rain >= MAX_DRY_DAYS:
		return true
	if not _has_ever_rained and day >= FIRST_RAIN_DEADLINE_DAY:
		return true
	if _murder_pending:
		_murder_pending_days_waited += 1
		if _murder_pending_days_waited >= MURDER_PENDING_RAIN_DEADLINE_DAYS:
			return true
	return false


func _roll_weather() -> Weather:
	var roll := randf()
	var cumulative := 0.0
	for i in WEATHER_OPTIONS.size():
		cumulative += WEATHER_ROLL_WEIGHTS[i]
		if roll <= cumulative:
			return WEATHER_OPTIONS[i]
	return Weather.SUNNY


func _update_rain_tracking() -> void:
	if current_weather == Weather.RAIN:
		_days_since_rain = 0
		_has_ever_rained = true
		if _murder_pending:
			_murder_pending_days_waited = 0
	else:
		_days_since_rain += 1
