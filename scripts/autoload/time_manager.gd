extends Node

## Owns the in-game 09:00-24:00 clock.
## Only advances time, advances the date, and publishes time events.
## NPC movement, restaurant operation, and event execution belong to other systems.

signal minute_passed(hour: int, minute: int)
signal hour_changed(hour: int)
signal day_changed(day: int, weekday: String)
signal restaurant_opened
signal restaurant_closed
signal night_events_enabled
signal forced_sleep
## 자발적 취침(sleep_now())과 달리, 24:00까지 스스로 안 잤을 때만 쏜다 -
## main.gd가 이걸 받아서 그 자리 기절 연출 + 병원 기상 + 이동속도 디버프를
## 처리한다(day4 노트: 두 취침이 forced_sleep 하나로 동일하게 처리되던 문제).
signal player_collapsed

const DAY_START_HOUR := 9
const DAY_END_HOUR := 24
const RESTAURANT_OPEN_HOUR := 10
const RESTAURANT_CLOSE_HOUR := 16
const NIGHT_EVENT_HOUR := 21
const SECONDS_PER_GAME_MINUTE := 1.0
const WEEKDAY_NAMES: Array[String] = ["월", "화", "수", "목", "금", "토", "일"]

var current_day := 1
var current_hour := DAY_START_HOUR
var current_minute := 0
## 오토로드라 씬과 무관하게 부팅 즉시 _process가 돈다 - true로 시작하면
## 타이틀/슬롯선택/캐릭터생성 화면에 머무는 동안에도 시계가 계속 흘러서,
## 그 사이 실제 시간이 몇 분만 지나도 며칠씩 지나가 버린다(사용자 리포트:
## "캐릭터 생성창만 띄워놨는데 이미 3일차"). main.gd._ready()가 실제
## 게임플레이가 시작되는 시점에 resume()을 호출해야 시계가 돌기 시작한다
## (AudioManager._game_started와 같은 문제, 같은 해법).
var is_running := false

var _minute_accumulator := 0.0


func _process(delta: float) -> void:
	if not is_running:
		return
	_minute_accumulator += delta
	while _minute_accumulator >= SECONDS_PER_GAME_MINUTE:
		_minute_accumulator -= SECONDS_PER_GAME_MINUTE
		_advance_minute()


func pause() -> void:
	is_running = false


func resume() -> void:
	is_running = true


func get_time_string() -> String:
	return "%02d:%02d" % [current_hour, current_minute]


func get_weekday_index() -> int:
	return (current_day - 1) % WEEKDAY_NAMES.size()


func get_weekday() -> String:
	return WEEKDAY_NAMES[get_weekday_index()]


func is_restaurant_open() -> bool:
	return current_hour >= RESTAURANT_OPEN_HOUR and current_hour < RESTAURANT_CLOSE_HOUR


## 침대 상호작용(자발적 취침) 진입점 - 24:00 강제취침과 똑같이 forced_sleep을
## 쏴서 SaveManager의 자동저장을 그대로 태우고 다음 날 09:00로 넘어간다.
func sleep_now() -> void:
	forced_sleep.emit()
	_advance_day()


func get_save_data() -> Dictionary:
	return {
		"day": current_day,
		"hour": current_hour,
		"minute": current_minute,
		"weekday": get_weekday(),
	}


func load_save_data(data: Dictionary) -> void:
	current_day = int(data.get("day", 1))
	current_hour = int(data.get("hour", DAY_START_HOUR))
	current_minute = int(data.get("minute", 0))
	_minute_accumulator = 0.0


func _advance_minute() -> void:
	current_minute += 1
	if current_minute >= 60:
		current_minute = 0
		_advance_hour()
	minute_passed.emit(current_hour, current_minute)


func _advance_hour() -> void:
	current_hour += 1
	if current_hour >= DAY_END_HOUR:
		## _advance_day()를 먼저 호출해야 한다 - SaveManager.forced_sleep 핸들러가
		## 이 신호를 받는 즉시 save_game()을 부르는데, 순서가 반대였을 때는 아직
		## current_hour가 24로 남아있는 상태(다음 날 09:00 리셋 전)가 그대로
		## 저장돼서, 이어하기로 불러오면 24:00~24:59 사이를 강제취침 검사 없이
		## 플레이할 수 있는 버그가 있었다(사용자 리포트: 1번 슬롯 이어하기 시
		## 24:30까지 진행됨).
		_advance_day()
		forced_sleep.emit()
		player_collapsed.emit()
		return
	hour_changed.emit(current_hour)
	_emit_hour_events()


func _emit_hour_events() -> void:
	match current_hour:
		RESTAURANT_OPEN_HOUR:
			restaurant_opened.emit()
		RESTAURANT_CLOSE_HOUR:
			restaurant_closed.emit()
		NIGHT_EVENT_HOUR:
			night_events_enabled.emit()


func _advance_day() -> void:
	current_day += 1
	current_hour = DAY_START_HOUR
	current_minute = 0
	hour_changed.emit(current_hour)
	day_changed.emit(current_day, get_weekday())
