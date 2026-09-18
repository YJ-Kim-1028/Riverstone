extends Control

## Always-on readout so TimeManager/WeatherManager/EconomyManager progress is
## visible while testing: day/weekday/time, weather, gold.

const WEATHER_ICONS: Array[Texture2D] = [
	preload("res://assets/ui/icon_weather_sunny.png"),
	preload("res://assets/ui/icon_weather_cloudy.png"),
	preload("res://assets/ui/icon_weather_rain.png"),
]
const BUFF_ICON_TEXTURE := preload("res://assets/ui/icon_speed.png")
## collection_screen.gd의 TOOLTIP_FONT_SIZE와 동일 - 엔진 기본 툴팁 글자가
## 이 도트그림 UI엔 너무 커 보인다는 피드백으로 작게 맞춘다.
const TOOLTIP_FONT_SIZE := 5

@onready var _time_label: Label = $VBox/TimeGroup/TimeLabel
@onready var _weather_icon: TextureRect = $VBox/WeatherIcon
@onready var _gold_label: Label = $VBox/GoldGroup/GoldLabel
@onready var _buff_icon: TextureRect = $VBox/BuffIcon

var _player: Node = null


func _ready() -> void:
	theme = _build_tooltip_theme()
	TimeManager.minute_passed.connect(_on_time_tick)
	TimeManager.day_changed.connect(_on_day_changed)
	WeatherManager.weather_changed.connect(_on_weather_changed)
	EconomyManager.gold_changed.connect(_on_gold_changed)
	_update_time_label()
	_update_weather_icon()
	_update_gold_label()
	_buff_icon.texture = BUFF_ICON_TEXTURE
	_buff_icon.visible = false


## main.gd가 한 번 호출해서 넘겨준다(HUD는 UI CanvasLayer 아래, 플레이어는
## HomeMap 아래라 서로 직접 찾을 수 없다).
func set_player(player: Node) -> void:
	_player = player


func _process(_delta: float) -> void:
	if _player == null:
		return
	var info: Dictionary = _player.get_speed_effect_info()
	_buff_icon.visible = not info.is_empty()
	if info.is_empty():
		return
	var percent := float(info.get("percent", 0.0))
	var minutes := int(info.get("minutes_remaining", 0))
	var label := tr("디버프") if bool(info.get("is_debuff", false)) else tr("버프")
	_buff_icon.tooltip_text = tr("%s: 이동속도 %+d%%, %d:%02d") % [label, int(round(percent * 100.0)), minutes / 60, minutes % 60]


## collection_screen.gd의 _build_tooltip_theme()와 동일한 기법 - "TooltipPanel"/
## "TooltipLabel" 테마 타입만 덮어써서 엔진 기본 큼직한 툴팁 대신 작은 글자를 쓴다.
func _build_tooltip_theme() -> Theme:
	var tooltip_theme := Theme.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.98, 0.93, 0.82, 0.95)
	panel_style.border_color = Color(0.42, 0.27, 0.15, 1)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(1)
	panel_style.content_margin_left = 3.0
	panel_style.content_margin_right = 3.0
	panel_style.content_margin_top = 1.0
	panel_style.content_margin_bottom = 1.0
	tooltip_theme.set_stylebox("panel", "TooltipPanel", panel_style)
	tooltip_theme.set_font_size("font_size", "TooltipLabel", TOOLTIP_FONT_SIZE)
	tooltip_theme.set_color("font_color", "TooltipLabel", Color(0.42, 0.27, 0.15, 1))
	return tooltip_theme


func _on_time_tick(_hour: int, _minute: int) -> void:
	_update_time_label()


func _on_day_changed(_day: int, _weekday: String) -> void:
	_update_time_label()


func _on_weather_changed(_weather) -> void:
	_update_weather_icon()


func _on_gold_changed(_gold: int) -> void:
	_update_gold_label()


func _update_time_label() -> void:
	_time_label.text = tr("%d일차 (%s) %s") % [TimeManager.current_day, TimeManager.get_weekday_display(), TimeManager.get_time_string()]


func _update_weather_icon() -> void:
	_weather_icon.texture = WEATHER_ICONS[WeatherManager.current_weather]


func _update_gold_label() -> void:
	_gold_label.text = EconomyManager.format_gold(EconomyManager.gold)
