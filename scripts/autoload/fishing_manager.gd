extends Node

## 낚시 진행 상태 하나만 관리한다(동시에 여러 낚시 세션 없음) - 입질 대기
## (실제 시간 기준, KitchenManager와 같은 이유로 TimeManager 게임 시간이 아님)
## -> 두더지 게임(스폰 지점을 옮겨다니는 물고기를 타이밍 맞춰 클릭, 어종별로
## 노출/은신 시간과 필요 클릭 수가 다름 - SPECIES_DIFFICULTY 참고) 두 단계로
## 구성된다. main.gd는 is_active() 동안 플레이어 이동을 잠근다 - 낚싯줄이
## 나가 있는 동안엔 맵을 벗어날 수 없으므로 맵 이동에 따른 별도 취소 처리가
## 필요 없다.

signal bite_started
signal fishing_ended(result: Dictionary)  ## {"success": bool, "item_id": String, "added_to_inventory": bool, "used_bait": bool}

enum Phase { IDLE, WAITING_FOR_BITE, MINIGAME }

## 아래 수치는 낚시 메커닉을 규정한 기획 문서가 없어 전부 임의 결정 - 기획
## 확정 시 조정.
const MINIGAME_TIME_LIMIT_SECONDS := 14.0
const BITE_WAIT_MIN_SECONDS := 3.0
const BITE_WAIT_MAX_SECONDS := 8.0
const SPECIES_WEIGHTS := {"salmon": 45, "mackerel": 40, "squid": 15}
## bait 설명("오징어를 낚을 확률이 증가한다")과 일치하도록 오징어 가중치만 올린다.
const BAIT_SQUID_WEIGHT_BONUS := 25
## 어종별 난이도(사용자 지시) - 물고기가 화면에 보이는/숨는 시간, 완료까지
## 필요한 클릭 수. 어종은 입질이 시작되는 순간(_roll_species(), 미니게임
## 시작 시점) 미리 정해져 있어야 fishing_fish.gd가 처음부터 맞는 난이도로
## 움직인다 - 예전엔 성공 시점(_resolve_catch)에만 어종을 정했는데, 그러면
## 미니게임 도중엔 어종을 몰라서 난이도를 못 나눴다.
const SPECIES_DIFFICULTY := {
	"salmon": {"appear": 0.5, "hide": 0.5, "hits": 6},
	"mackerel": {"appear": 0.5, "hide": 0.5, "hits": 6},
	"squid": {"appear": 0.4, "hide": 0.6, "hits": 7},
}
const DEFAULT_DIFFICULTY := {"appear": 0.5, "hide": 0.5, "hits": 6}

var _phase := Phase.IDLE
var _bite_wait_elapsed := 0.0
var _bite_wait_duration := 0.0
var _minigame_elapsed := 0.0
var _hit_count := 0
var _current_species := ""


func _process(delta: float) -> void:
	match _phase:
		Phase.WAITING_FOR_BITE:
			_bite_wait_elapsed += delta
			if _bite_wait_elapsed >= _bite_wait_duration:
				_phase = Phase.MINIGAME
				_minigame_elapsed = 0.0
				_hit_count = 0
				_roll_species()
				bite_started.emit()
		Phase.MINIGAME:
			_minigame_elapsed += delta
			if _minigame_elapsed >= MINIGAME_TIME_LIMIT_SECONDS:
				_finish({"success": false, "item_id": ""})


func can_start_fishing() -> bool:
	return _phase == Phase.IDLE and EquipmentManager.get_equipped(EquipmentManager.HAND_SLOT) == "fishing_rod"


func start_fishing() -> bool:
	if not can_start_fishing():
		return false
	_phase = Phase.WAITING_FOR_BITE
	_bite_wait_elapsed = 0.0
	_bite_wait_duration = randf_range(BITE_WAIT_MIN_SECONDS, BITE_WAIT_MAX_SECONDS)
	return true


func cancel_fishing() -> void:
	_phase = Phase.IDLE


func is_waiting_for_bite() -> bool:
	return _phase == Phase.WAITING_FOR_BITE


func is_biting() -> bool:
	return _phase == Phase.MINIGAME


## 입질 대기든 미니게임이든, 낚싯줄이 나가 있는 동안엔 전부 true - main.gd가
## 이걸로 이동을 잠근다.
func is_active() -> bool:
	return _phase != Phase.IDLE


func get_hit_count() -> int:
	return _hit_count


func get_required_hits() -> int:
	return int(_current_difficulty().get("hits", DEFAULT_DIFFICULTY["hits"]))


## fishing_fish.gd가 두더지 게임 사이클마다 참고한다.
func get_fish_appear_duration() -> float:
	return float(_current_difficulty().get("appear", DEFAULT_DIFFICULTY["appear"]))


func get_fish_hide_duration() -> float:
	return float(_current_difficulty().get("hide", DEFAULT_DIFFICULTY["hide"]))


func _current_difficulty() -> Dictionary:
	return SPECIES_DIFFICULTY.get(_current_species, DEFAULT_DIFFICULTY)


## 시간 바 UI용 - 남은 비율(1.0=풀타임, 0.0=시간 끝).
func get_minigame_time_remaining_ratio() -> float:
	if _phase != Phase.MINIGAME:
		return 0.0
	return clampf(1.0 - _minigame_elapsed / MINIGAME_TIME_LIMIT_SECONDS, 0.0, 1.0)


## 두더지 게임 화면이 "지금 문 물고기를 클릭했다"고 알릴 때 호출한다.
## 어종별 필요 클릭 수(get_required_hits())를 채우면 여기서 바로 성공
## 처리까지 끝낸다.
func register_hit() -> bool:
	if _phase != Phase.MINIGAME:
		return false
	_hit_count += 1
	if _hit_count >= get_required_hits():
		_finish(_resolve_catch())
	return true


func _finish(result: Dictionary) -> void:
	_phase = Phase.IDLE
	_current_species = ""
	fishing_ended.emit(result)


## 어종(_current_species)은 미니게임이 시작되는 시점(_roll_species)에 이미
## 정해져 있다 - 여기서는 그 결과로 실제 지급/미끼 소모만 처리한다.
func _roll_species() -> void:
	var weights: Dictionary = SPECIES_WEIGHTS.duplicate()
	if InventoryManager.has_item("bait", 1):
		weights["squid"] = int(weights["squid"]) + BAIT_SQUID_WEIGHT_BONUS
	_current_species = _roll_weighted(weights)


func _resolve_catch() -> Dictionary:
	var used_bait := InventoryManager.has_item("bait", 1)
	if used_bait:
		InventoryManager.remove_item("bait", 1)
	var added := InventoryManager.add_item(_current_species, 1)
	return {"success": true, "item_id": _current_species, "added_to_inventory": added, "used_bait": used_bait}


func _roll_weighted(weights: Dictionary) -> String:
	var total := 0
	for w in weights.values():
		total += int(w)
	var roll := randi_range(1, total)
	var cumulative := 0
	for species in weights:
		cumulative += int(weights[species])
		if roll <= cumulative:
			return String(species)
	return String(weights.keys()[0])
