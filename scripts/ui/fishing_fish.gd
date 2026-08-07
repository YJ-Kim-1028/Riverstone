extends Button
class_name FishingFish

## 두더지 게임의 물고기 하나 - 나타나서 잠깐 클릭 가능하다가 숨는 사이클만
## 책임진다. 어디에 나타날지(스폰 지점 선택)는 fishing_screen.gd가 결정해서
## position을 직접 옮겨준다 - 이 스크립트는 "지금 이 자리에서 보이는 중인지"만
## 안다. 전용 물고기 그림이 아직 없어서(assets는 읽기 전용, 실제 그림은 추후
## 교체) 텍스트 버튼으로 자리만 잡아둔다.

signal hit_while_visible
signal relocate_requested

var _elapsed := 0.0
## FishingManager.get_fish_appear/hide_duration() - 어종별로 다르다(사용자
## 지시). start_cycle()마다(=매 스폰마다) 다시 읽어온다 - 미니게임 도중엔
## 어종이 안 바뀌므로 사실상 한 번만 정해지지만, 매번 다시 물어봐도 비용이
## 거의 없어서 굳이 별도로 캐싱하지 않는다.
var _appear_duration := 0.5
var _hide_duration := 0.5
var _appearing := true
## visible만으로는 "숨어있는 사이 구간(HIDE_DURATION)"을 셀 수 없어서(visible이
## false면 _process를 건너뛰어야 클릭 판정도 같이 꺼지므로) 사이클 진행 여부를
## 따로 추적한다.
var _cycling := false


func _ready() -> void:
	pressed.connect(_on_pressed)
	visible = false


func start_cycle() -> void:
	_elapsed = 0.0
	_appear_duration = FishingManager.get_fish_appear_duration()
	_hide_duration = FishingManager.get_fish_hide_duration()
	_appearing = true
	_cycling = true
	visible = true
	AudioManager.play_sfx(AudioManager.SFX_FISHING_APPEAR)


## fishing_screen.gd가 낚시가 끝났을 때(성공/실패/취소) 호출한다 - 그냥
## visible만 꺼서는 안 된다. 사이클이 마침 "나타난" 구간 도중이었다면 이후에도
## _process가 계속 돌아서, 숨김 구간이 끝나는 순간 relocate_requested를 다시
## 쏴서 화면이 이미 닫힌/끝난 뒤에도 물고기가 되살아나 보이는 버그가 있었다.
func stop_cycle() -> void:
	_cycling = false
	visible = false


func _process(delta: float) -> void:
	if not _cycling:
		return
	_elapsed += delta
	var limit := _appear_duration if _appearing else _hide_duration
	if _elapsed < limit:
		return
	_elapsed = 0.0
	if _appearing:
		_appearing = false
		visible = false
	else:
		_cycling = false
		relocate_requested.emit()


func _on_pressed() -> void:
	if _appearing:
		hit_while_visible.emit()
