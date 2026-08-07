extends Control

## 상태창(TAB) "설정" 탭 - 브금/효과음(비/실내빗소리/파도/강 등 배경음
## 전부) 볼륨 슬라이더. 실제 볼륨 적용과 저장은 AudioManager(오디오 버스 +
## user://audio_settings.cfg)가 전담하고, 이 패널은 슬라이더 UI와 값
## 동기화만 담당한다.

@onready var _bgm_slider: HSlider = $VBox/BgmRow/Slider
@onready var _bgm_value_label: Label = $VBox/BgmRow/ValueLabel
@onready var _sfx_slider: HSlider = $VBox/SfxRow/Slider
@onready var _sfx_value_label: Label = $VBox/SfxRow/ValueLabel


func _ready() -> void:
	_bgm_slider.value = AudioManager.get_bgm_volume() * 100.0
	_sfx_slider.value = AudioManager.get_sfx_volume() * 100.0
	_update_value_label(_bgm_value_label, _bgm_slider.value)
	_update_value_label(_sfx_value_label, _sfx_slider.value)
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)


func _on_bgm_changed(value: float) -> void:
	AudioManager.set_bgm_volume(value / 100.0)
	_update_value_label(_bgm_value_label, value)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value / 100.0)
	_update_value_label(_sfx_value_label, value)


func _update_value_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(value))
