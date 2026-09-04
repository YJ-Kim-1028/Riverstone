extends Node

## Owns restaurant open/close state, the 3 cooking-station/table pairs, the
## daily NPC visitor queue, seating/eating timing, and serving. Calls into
## CookingManager for the actual ingredient -> dish resolution and into
## NPCManager to apply the affection reaction once a dish is served. Payment
## (EconomyManager.add_income) is deliberately delayed until the NPC actually
## finishes eating and leaves (사용자 지시 - 호감도는 서빙 즉시, 돈은 다 먹고
## 떠날 때).

signal restaurant_opened
signal restaurant_closed
signal npc_seated(station_index: int, npc_id: String)
## npc_seated와 달리 "논리적으로 배정됨"이 아니라 NPC가 실제로 restaurant_interior
## 맵에 들어오는(워프되는) 그 순간에만 쏜다(NPCWorldManager.notify_npc_entered_map
## 참고) - AudioManager가 "NPC가 레스토랑에 들어올 때" 효과음(sfx_bell)을 여기
## 연결한다. npc_seated에 연결했더니 목적지만 정해진 시점에 너무 일찍 울렸고,
## 자리에 완전히 앉은 순간(is_station_npc_settled) 기준으로 바꿨더니 이번엔
## NPC마다 판정이 들쭉날쭉하고 한 손님한테 여러 번 울리는 문제가 있어 최종적으로
## "맵 진입 시점 정확히 한 번"으로 정착(사용자 지시).
signal npc_arrived(station_index: int, npc_id: String)
## paid_amount: 식사를 마치고 떠나는 시점에 실제로 받은 돈(사용자 지시 -
## 호감도는 서빙 즉시 반영되지만 돈은 "다 먹고 떠날 때" 받는다). 서빙 전에
## 쫓겨난 손님(_evict_unserved_customers)은 애초에 돈을 낸 적이 없으므로 0.
signal npc_departed(station_index: int, npc_id: String, paid_amount: int)
signal dish_served(station_index: int, npc_id: String, dish: Dictionary)
signal npc_poisoned(npc_id: String)
## 오늘 배정된 손님(_todays_visitors, 최대 DAILY_VISITOR_COUNT명) 전원이
## 서빙까지 완료된 순간 정확히 한 번만 쏜다 - 영업시간이 남아도 더 이상 새
## 손님은 안 온다는 걸 플레이어에게 알려주기 위함(사용자 피드백 42번,
## 2026-09-01 - "4시까지 영업이 길어서 10명 채워도 시간이 남을 듯. 오늘 받을
## 손님이 없을 때는 머리 위에 띄워주기").
signal all_visitors_served

const STATION_COUNT := 3
const OPEN_HOUR := 10
const CLOSE_HOUR := 16
const NEW_GUEST_CUTOFF_HOUR := 14
const NEW_GUEST_CUTOFF_MINUTE := 30
## 기존 5는 좌석 회전을 아무리 빨리 해도 하루 수입이 항상 낮게 막혀서
## "숙련도가 늘수록 더 번다"는 느낌이 안 난다는 사용자 피드백으로 상향함.
## NPC 전체가 13명뿐이라(data/npc/*.json) 그보다는 작게 잡아 상식적인
## 상한을 유지 - 실질 상한은 이 값과 그날 스케줄상 보이는 NPC 수, 좌석 3개
## 회전 속도 중 가장 작은 값으로 자연히 정해진다.
const DAILY_VISITOR_COUNT := 10
const EATING_DURATION_MINUTES := 30
## 호감도를 고루고루 올리게 유도하려고(사용자 지시, 2026-09-04 - "호감도 제일
## 낮은 npc 2명을 항상 레스토랑 열자마자 초대") 매일 호감도가 가장 낮은 살아있는
## NPC 2명을 자동으로 오늘 방문객 맨 앞에 꽂는다 - 수동 초대(_invited_npc_id)와
## 합쳐도 최대 3명(=STATION_COUNT)이라 자리가 모자라지 않는다.
const AUTO_LOW_AFFECTION_INVITE_COUNT := 2

var is_open := false
## 신규 슬롯 튜토리얼(main.gd._maybe_play_tutorial_intro()) 전용 - true인 동안
## 정상적인 방문객 자동 추첨/착석(_try_admit_next_visitor)을 건너뛴다(사용자
## 지시, 2026-09-01 - "튜토일때는 레스토랑 열어도 손님 안오게 해줘"). 튜토리얼이
## force_seat_npc()로 폴리를 직접 앉히는 것과는 무관하게 항상 동작한다.
var suppress_auto_visitors := false

var _stations: Array = []
var _todays_visitors: Array = []
var _visited_today: Dictionary = {}
## 다음날 확정 방문으로 예약된 초대(invite_npc()가 채움, _generate_daily_visitors()가
## 그날 방문객 목록에 반영하며 비움).
## all_visitors_served를 하루에 한 번만 쏘기 위한 플래그 - _generate_daily_visitors()가
## 매일 리셋한다.
var _all_visitors_notified := false
var _invited_npc_id := ""
## _generate_daily_visitors()가 _invited_npc_id를 소비하는 순간, "오늘 확정
## 방문객으로 반영된 NPC가 누구였는지"를 하루 동안 기억해두는 용도 -
## _resolve_invite_outcome()이 그 다음날로 넘어가기 직전(=_visited_today가
## 지워지기 전)에 이 값으로 실제 방문 여부를 확인해 EmailManager 초대 내역에
## 결과를 남긴다. _invited_npc_id 자체는 그사이 플레이어가 또 다른 NPC를
## 초대하면 값이 덮여써지므로 별도로 들고 있어야 한다.
var _todays_invited_npc_id := ""
var _invite_used_today := false


func _ready() -> void:
	for i in STATION_COUNT:
		_stations.append({"npc_id": "", "dish": null, "eating_until": -1, "entry_notified": false})
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.restaurant_closed.connect(_on_time_restaurant_closed)
	TimeManager.minute_passed.connect(_on_minute_passed)
	_generate_daily_visitors()


## NPCWorldManager가 이 NPC의 다음 홉이 "restaurant_interior"에 막 도착한
## 순간(맵이 바뀐 그 프레임, 문 앞 스폰 지점) 호출한다 - 예전엔 "자리에 완전히
## 앉은 순간"(is_station_npc_settled) 기준으로 벨을 울렸는데, NPC마다 그
## 판정이 들쭉날쭉하고(특히 화면 밖에서 미리 정착 처리된 경우) 한 손님한테
## 여러 번 울리기도 하는 문제가 있었다 - "문에 들어온 순간 정확히 한 번"으로
## 단순화(사용자 지시).
## entry_notified로 이 좌석(=이번 착석)당 딱 한 번만 실제로 울리게 막는다 -
## 튜토리얼의 폴리처럼 plant_npc_at()으로 직접 배치된 NPC는 정상 스케줄
## 재조정(스케줄상 다른 곳에 있어야 한다고 판단해 몰래 나갔다 돌아오는 등)이
## 이 함수를 자연스럽게도 한 번 더 호출할 수 있어서, 벨이 두 번 울리는 문제가
## 있었다(사용자 리포트, 2026-09-05 - "폴리 들어올 때 띵동소리가 두번
## 울리는데"). _seat_npc()가 새로 앉을 때마다 다시 false로 리셋한다.
func notify_npc_entered_map(npc_id: String) -> void:
	var station_index := get_seated_station(npc_id)
	if station_index == -1 or bool(_stations[station_index].get("entry_notified", false)):
		return
	_stations[station_index]["entry_notified"] = true
	npc_arrived.emit(station_index, npc_id)


## bypass_hours: 신규 슬롯 튜토리얼(main.gd._maybe_play_tutorial_intro()) 전용
## - 게임이 09:00에 시작하는데 정식 영업시간(OPEN_HOUR=10)까지 기다리게
## 하면 튜토리얼이 막힌다는 지적(사용자 지시, 2026-09-01 - "튜토일때는
## 영업시간 전이어도 열수있게 해주고"). 튜토리얼이 끝나면 다시 닫아준다.
func open_restaurant(bypass_hours: bool = false) -> bool:
	if is_open or (not bypass_hours and (TimeManager.current_hour < OPEN_HOUR or TimeManager.current_hour >= CLOSE_HOUR)):
		return false
	is_open = true
	restaurant_opened.emit()
	_try_admit_next_visitor()
	return true


## restaurant.md: 손님은 요리를 받기 전까지는 스스로 자리를 뜨지 않는다 - 유일한
## 예외가 이거다: 플레이어가 아직 서빙 안 한 손님을 앉혀둔 채로 레스토랑을
## 닫으면, 그 손님들은 (주문을 못 받았으니) 바로 자리를 뜬다. 이미 서빙되어
## 식사 중인 손님은 영업 종료와 무관하게 원래 eating_until까지 그대로 있는다.
func close_restaurant() -> bool:
	if not is_open:
		return false
	is_open = false
	restaurant_closed.emit()
	_evict_unserved_customers()
	return true


func _evict_unserved_customers() -> void:
	for i in STATION_COUNT:
		var station: Dictionary = _stations[i]
		if not String(station.get("npc_id", "")).is_empty() and station.get("dish") == null:
			var npc_id: String = station["npc_id"]
			station["npc_id"] = ""
			station["eating_until"] = -1
			# 요리를 받기 전에 쫓겨난 거라 실제로 방문을 완료한 게 아니다 -
			# _visited_today에 그대로 남아있으면 나중에 다시 영업을 열어도 이
			# 손님이 영영 후순위(초대 손님이었다면 초대 자체가 무의미해짐)로
			# 밀려버린다. 다시 대기 목록에 넣어서 재입장 가능하게 한다.
			_visited_today.erase(npc_id)
			npc_departed.emit(i, npc_id, 0)


## restaurant.md: 영업 중엔 레스토랑을 벗어날 수 없고, 영업 종료 후에도 남은
## 손님이 식사를 마칠 때까지는 나갈 수 없다. 실제 이동 차단은 맵/워프 쪽에서
## 이 값을 확인해서 처리해야 한다 (아직 NPC/맵 상호작용 시스템이 없음).
func can_player_leave() -> bool:
	return not is_open and _count_seated() == 0


func get_station_npc(station_index: int) -> String:
	if station_index < 0 or station_index >= STATION_COUNT:
		return ""
	return String(_stations[station_index].get("npc_id", ""))


## shop_manager.gd의 is_staffed()와 같은 이유 - get_station_npc()는 "논리적으로
## 이 손님이 배정됐다"는 것만 알려주고, NPC가 실제로 걸어서 그 자리에 도착했는지는
## 별개다(다구간 이동 중일 수 있음). 완성대(serving_area) 상호작용은 실제로
## 자리에 앉아있는 손님한테만 허용해야 한다.
func is_station_npc_settled(station_index: int) -> bool:
	var npc_id := get_station_npc(station_index)
	if npc_id.is_empty():
		return false
	var seat: Dictionary = NPCManager.resolve_state_position("restaurant_seat%d" % (station_index + 1))
	if seat.is_empty():
		return false
	return NPCManager.is_npc_settled_at(npc_id, String(seat["map_id"]), seat["position"])


## NPCManager uses this to override a seated NPC's world position with their
## table spot ("restaurant_seatN") instead of wherever their normal daily
## schedule would otherwise place them. Returns -1 if not currently seated.
func get_seated_station(npc_id: String) -> int:
	for i in STATION_COUNT:
		if String(_stations[i].get("npc_id", "")) == npc_id:
			return i
	return -1


func get_station_dish(station_index: int) -> Dictionary:
	if station_index < 0 or station_index >= STATION_COUNT:
		return {}
	var dish = _stations[station_index].get("dish")
	return dish if dish != null else {}


## restaurant.md: "연결된 식탁에 NPC가 없다면 해당 요리대는 사용할 수 없다."
## 이미 요리가 나가 식사 중인 요리대도 새로 요리할 수 없다(미리 만들어 둘 수 없음).
func can_cook_at(station_index: int) -> bool:
	if not is_open or station_index < 0 or station_index >= STATION_COUNT:
		return false
	var station: Dictionary = _stations[station_index]
	return not String(station.get("npc_id", "")).is_empty() and station.get("dish") == null


func cook_and_serve(station_index: int, ingredient_a: String, ingredient_b: String, use_rat_poison: bool = false) -> bool:
	if not can_cook_at(station_index):
		return false
	var dish: Dictionary = CookingManager.cook(ingredient_a, ingredient_b, use_rat_poison)
	if dish.is_empty():
		return false
	var station: Dictionary = _stations[station_index]
	var npc_id: String = station["npc_id"]
	station["dish"] = dish
	station["eating_until"] = _absolute_minutes() + EATING_DURATION_MINUTES
	var preference: int = NPCManager.FoodPreference.DISLIKED
	if not bool(dish.get("is_weird", false)):
		preference = NPCManager.get_food_preference_for_ingredients(npc_id, (dish.get("ingredients", []) as Array))
	NPCManager.feed_with_preference(npc_id, preference)
	# EmailManager가 dish_served를 듣고 "오늘 이 NPC가 선호 재료 요리를 받았는지"를
	# 별도 계산 없이 그대로 읽어 event_invite 메일 내용을 고르는 데 쓴다.
	dish["preference"] = preference
	# 실제로 요리를 받아서 호감도가 반영된 시점에만 "오늘 방문 완료"로 친다 -
	# 앉기만 하고 서빙 전에 쫓겨나면(_evict_unserved_customers) 방문한 게
	# 아니므로 다음에 다시 앉을 수 있어야 한다.
	_visited_today[npc_id] = true
	if not _all_visitors_notified and _visited_today.size() >= _todays_visitors.size():
		_all_visitors_notified = true
		all_visitors_served.emit()
	# 돈은 여기서 바로 받지 않는다 - 호감도(위 NPCManager.feed 등)는 서빙 즉시
	# 반영되지만, 실제 결제는 손님이 식사를 마치고 떠날 때(_on_minute_passed)로
	# 미룬다(사용자 지시).
	dish_served.emit(station_index, npc_id, dish)
	if bool(dish.get("poisoned", false)):
		npc_poisoned.emit(npc_id)
	return true


func get_todays_visitor_ids() -> Array:
	return _todays_visitors.duplicate()


## 로시처럼 오늘 스케줄상 안 보이는 NPC라도, 플레이어가 직접 초대하면 예외적
## 으로 온다(사용자 확정) - _generate_daily_visitors()의 무작위 후보 필터링과
## 달리 초대는 "안 오는데 왜 안 오지?" 하고 플레이어가 헷갈리면 안 되는
## 명시적 행동이라 여기엔 비가시 필터를 안 건다.
func invite_npc(npc_id: String) -> bool:
	if _invite_used_today or not NPCManager.is_alive(npc_id):
		return false
	_invited_npc_id = npc_id
	_invite_used_today = true
	return true


func has_invited_today() -> bool:
	return _invite_used_today


func get_save_data() -> Dictionary:
	return {
		"is_open": is_open,
		"todays_visitors": _todays_visitors.duplicate(),
		"visited_today": _visited_today.duplicate(),
		"invited_npc_id": _invited_npc_id,
		"todays_invited_npc_id": _todays_invited_npc_id,
		"invite_used_today": _invite_used_today,
	}


func load_save_data(data: Dictionary) -> void:
	# is_open을 세이브 값 그대로 복원하면 안 된다 - 바로 아래에서 _stations를
	# 전부 빈 상태로 리셋하는데(재접속 시 실제로 앉아있는 손님/조리 중인 요리가
	# 있을 리 없음), is_open만 true로 살아있으면 "문은 열려있는데 아무도 없는"
	# 상태가 되어 NPC 스케줄이 다시 레스토랑으로 몰려든다(사용자 리포트 -
	# 게임 종료 후 재접속하면 레스토랑이 열린 채로 남아 NPC들이 우르르 들어옴).
	# _on_day_changed()가 "하루가 바뀌면 무조건 닫힌 상태로 시작"하는 것과 같은
	# 이유로, 재접속도 항상 닫힌 상태로 시작해서 플레이어가 직접 다시 열어야 한다.
	is_open = false
	_todays_visitors = (data.get("todays_visitors", []) as Array).duplicate()
	_visited_today = (data.get("visited_today", {}) as Dictionary).duplicate()
	_invited_npc_id = String(data.get("invited_npc_id", ""))
	_todays_invited_npc_id = String(data.get("todays_invited_npc_id", ""))
	_invite_used_today = bool(data.get("invite_used_today", false))
	for station in _stations:
		station["npc_id"] = ""
		station["dish"] = null
		station["eating_until"] = -1


## is_open은 자동으로 초기화되지 않는 값이라, 어제 마감 시간(CLOSE_HOUR) 전에
## 취침해서 하루가 넘어가면 직접 닫은 적이 없어도 true 상태가 다음 날까지
## 이어진다 - _try_admit_next_visitor()는 "마감(신규 손님 컷오프)"만 확인하고
## "아직 오픈 시간(OPEN_HOUR) 전"인지는 안 봐서, 그 상태로 아침 일찍 들어가면
## 문 연 적 없이 손님이 조용히 착석해있는 것처럼 보이는 버그가 있었다. 하루가
## 바뀌면 무조건 닫힌 상태로 시작해서 매일 직접 열어야 하게 한다.
func _on_day_changed(_day: int, _weekday: String) -> void:
	_resolve_invite_outcome()
	_generate_daily_visitors()
	_invite_used_today = false
	if is_open:
		close_restaurant()


## 오늘 확정 방문으로 예약돼있던 NPC가 있었다면(_todays_invited_npc_id) 실제로
## 방문했는지(_visited_today) 확인해서 EmailManager 초대 내역에 결과를 남긴다 -
## _generate_daily_visitors()가 _visited_today를 지우기 전에 먼저 호출해야 한다.
func _resolve_invite_outcome() -> void:
	if _todays_invited_npc_id.is_empty():
		return
	EmailManager.mark_invite_outcome(_todays_invited_npc_id, _visited_today.has(_todays_invited_npc_id))


func _on_time_restaurant_closed() -> void:
	close_restaurant()


func _on_minute_passed(_hour: int, _minute: int) -> void:
	var now := _absolute_minutes()
	for i in STATION_COUNT:
		var station: Dictionary = _stations[i]
		if station["dish"] != null and now >= int(station["eating_until"]):
			var npc_id: String = station["npc_id"]
			var paid_amount := int((station["dish"] as Dictionary).get("price", 0))
			station["npc_id"] = ""
			station["dish"] = null
			station["eating_until"] = -1
			EconomyManager.add_income(paid_amount)
			npc_departed.emit(i, npc_id, paid_amount)
	_try_admit_next_visitor()


## 로시처럼 "비 안 오는 날은 아예 등장하지 않는" NPC는 그날 스케줄상 실존하지
## 않는 것과 같다 - 손님 후보에서도 빠져야 한다(사용자 확정: "로시는 그냥
## 안온다는거야"). NPCManager.get_schedule_only_position()이 비어있으면
## 오늘 스케줄상 어디에도 없는(안 보이는) NPC라는 뜻이라 후보에서 제외한다.
func _generate_daily_visitors() -> void:
	var candidates: Array = []
	for npc_id in NPCManager.get_all_ids():
		if NPCManager.is_alive(npc_id) and not NPCManager.get_schedule_only_position(npc_id).is_empty():
			candidates.append(npc_id)
	candidates.shuffle()
	var visitors: Array = []
	if not _invited_npc_id.is_empty() and NPCManager.is_alive(_invited_npc_id):
		visitors.append(_invited_npc_id)
		candidates.erase(_invited_npc_id)
	for npc_id in _lowest_affection_npc_ids(AUTO_LOW_AFFECTION_INVITE_COUNT, visitors):
		visitors.append(npc_id)
		candidates.erase(npc_id)
	for npc_id in candidates:
		if visitors.size() >= DAILY_VISITOR_COUNT:
			break
		visitors.append(npc_id)
	_todays_visitors = visitors
	_visited_today.clear()
	_all_visitors_notified = false
	# _resolve_invite_outcome()이 내일 이 값으로 "오늘 초대 확정 방문객이 실제로
	# 왔는지" 판정한다 - _invited_npc_id를 비우기 전에 넘겨받아야 한다.
	_todays_invited_npc_id = _invited_npc_id
	_invited_npc_id = ""


## 호감도가 가장 낮은 살아있는 NPC부터 count명을 뽑는다(exclude에 이미 담긴,
## 예를 들어 수동 초대로 이미 오늘 방문이 확정된 NPC는 제외) - 동점자는 매일
## 다른 순서로 섞여서 항상 같은 두 명으로 고정되지 않는다.
## 로시처럼 그날 스케줄이 아예 없는 NPC(예: 비 안 오는 날)는 후보에서
## 제외한다(사용자 지시, 2026-09-05) - 처음엔 수동 초대처럼 스케줄 무관하게
## 강제 방문시켰는데, 그러면 "걸어올 원래 자리"가 없어서 순간이동하듯 이미
## 좌석에 앉아있는 것처럼 보이는 문제가 있었다("로시가 문 열자마자 이미
## 앉아있었다" 리포트) - 로시의 "비 오는 날 외엔 안 보임" 규칙 자체는 이
## 자동 초대에서도 그대로 지킨다.
func _lowest_affection_npc_ids(count: int, exclude: Array) -> Array:
	var pool: Array = []
	for npc_id in NPCManager.get_all_ids():
		if NPCManager.is_alive(npc_id) and not exclude.has(npc_id) \
				and not NPCManager.get_schedule_only_position(npc_id).is_empty():
			pool.append(npc_id)
	pool.shuffle()
	pool.sort_custom(func(a, b): return NPCManager.get_affection(a) < NPCManager.get_affection(b))
	return pool.slice(0, count)


func _is_past_new_guest_cutoff() -> bool:
	if TimeManager.current_hour > NEW_GUEST_CUTOFF_HOUR:
		return true
	return TimeManager.current_hour == NEW_GUEST_CUTOFF_HOUR and TimeManager.current_minute >= NEW_GUEST_CUTOFF_MINUTE


func _try_admit_next_visitor() -> void:
	if suppress_auto_visitors or not is_open or _is_past_new_guest_cutoff():
		return
	var station_index := _find_free_station()
	if station_index == -1:
		return
	for npc_id in _todays_visitors:
		if _visited_today.has(npc_id) or not NPCManager.is_alive(npc_id):
			continue
		# 서빙 전에 쫓겨났다가 다시 앉을 수 있게 된 손님이 아직 다른 자리에
		# 앉아있는 채로 또 앉혀지는 일이 없도록 확인한다(_visited_today는 이제
		# 서빙 완료 시점에만 찍히므로, 착석 여부는 따로 봐야 한다).
		if get_seated_station(npc_id) != -1:
			continue
		_seat_npc(station_index, npc_id)
		return


## 신규 슬롯 튜토리얼 컷신(main.gd._maybe_play_tutorial_intro()) 전용 - 정상적인
## 방문객 추첨(_generate_daily_visitors/_try_admit_next_visitor)을 거치지 않고
## 특정 NPC를 특정 자리에 강제로 앉힌다. _seat_npc()와 동일하게 npc_seated를
## 쏘므로, NPCManager는 평소 손님과 똑같이 그 자리로 걸어가게 만든다(사용자
## 지시, 2026-09-01). 자리가 이미 차 있으면 아무 일도 안 하고 false.
func force_seat_npc(station_index: int, npc_id: String) -> bool:
	if station_index < 0 or station_index >= STATION_COUNT:
		return false
	if not String(_stations[station_index].get("npc_id", "")).is_empty():
		return false
	_seat_npc(station_index, npc_id)
	return true


func _seat_npc(station_index: int, npc_id: String) -> void:
	_stations[station_index]["npc_id"] = npc_id
	_stations[station_index]["dish"] = null
	_stations[station_index]["eating_until"] = -1
	_stations[station_index]["entry_notified"] = false
	npc_seated.emit(station_index, npc_id)


func _find_free_station() -> int:
	for i in STATION_COUNT:
		if String(_stations[i].get("npc_id", "")).is_empty():
			return i
	return -1


func _count_seated() -> int:
	var total := 0
	for station in _stations:
		if not String(station.get("npc_id", "")).is_empty():
			total += 1
	return total


func _absolute_minutes() -> int:
	return TimeManager.current_day * 1440 + TimeManager.current_hour * 60 + TimeManager.current_minute
