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

enum Phase { IDLE, WAITING_FOR_BITE, MINIGAME, GHOST_VANISH }

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
## squid는 원래 appear 0.4 / hide 0.6 / hits 7로 다른 어종보다 더 어렵게
## 잡았는데, 실제로 해보니 "개어렵다"는 피드백(사용자 리포트, 2026-08-24)이
## 와서 완화 - hits는 다른 어종과 동일한 6으로 낮추고, appear/hide는 살짝만
## 더 빡빡하게 남겨서(0.45/0.55) squid가 여전히 조금 더 어려운 어종이라는
## 차별화는 유지한다.
const SPECIES_DIFFICULTY := {
	"salmon": {"appear": 0.5, "hide": 0.5, "hits": 6},
	"mackerel": {"appear": 0.5, "hide": 0.5, "hits": 6},
	"squid": {"appear": 0.45, "hide": 0.55, "hits": 6},
}
const DEFAULT_DIFFICULTY := {"appear": 0.5, "hide": 0.5, "hits": 6}

## 공포 연출(사용자 지시, 2026-08-24): plaza3(시체가 발견됐던 곳)에서 첫 살인
## 이후 낚시하면, 확률적으로 진짜 입질 대신 "물귀신"이 낚아채는 가짜 입질이
## 온다 - 미니게임 UI는 아예 안 열고(fishing_screen.gd가 is_ghost_bite()를
## 보고 스스로 안 연다), 대신 물고기 등장 효과음(SFX_FISHING_APPEAR)을 짧은
## 간격으로 여러 번 반복 재생해서 "뭔가와 씨름하는" 느낌을 준 뒤 뚝 끊고
## 실패 처리한다 - 이후 연출(호러 사운드 + 독백)은 main.gd의
## _on_fishing_ended가 이어받는다(미끼/낚싯대 소모는 평소 실패와 동일하게 없음).
const GHOST_BITE_MAP_ID := "plaza3"
const GHOST_BITE_CHANCE := 0.35
const GHOST_STRUGGLE_DURATION_SECONDS := 1.3
const GHOST_STRUGGLE_SFX_INTERVAL_SECONDS := 0.12

var _phase := Phase.IDLE
var _bite_wait_elapsed := 0.0
var _bite_wait_duration := 0.0
var _minigame_elapsed := 0.0
var _hit_count := 0
var _current_species := ""
var _is_ghost_bite := false
var _ghost_struggle_sfx_elapsed := 0.0


func _process(delta: float) -> void:
	match _phase:
		Phase.WAITING_FOR_BITE:
			_bite_wait_elapsed += delta
			if _bite_wait_elapsed >= _bite_wait_duration:
				_minigame_elapsed = 0.0
				if _is_ghost_bite:
					_phase = Phase.GHOST_VANISH
					_ghost_struggle_sfx_elapsed = 0.0
				else:
					_phase = Phase.MINIGAME
					_hit_count = 0
					_roll_species()
				bite_started.emit()
		Phase.GHOST_VANISH:
			_minigame_elapsed += delta
			_ghost_struggle_sfx_elapsed += delta
			if _ghost_struggle_sfx_elapsed >= GHOST_STRUGGLE_SFX_INTERVAL_SECONDS:
				_ghost_struggle_sfx_elapsed = 0.0
				AudioManager.play_sfx(AudioManager.SFX_FISHING_APPEAR)
			if _minigame_elapsed >= GHOST_STRUGGLE_DURATION_SECONDS:
				_finish({"success": false, "item_id": "", "ghost": true})
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
	_is_ghost_bite = GameManager.current_map_id == GHOST_BITE_MAP_ID \
			and MurderManager.get_murder_count() > 0 \
			and randf() < GHOST_BITE_CHANCE
	return true


## 입질 대기 중 E로 취소하든, 미니게임 중 ESC로 취소하든(fishing_screen.gd)
## 이 한 곳을 거친다 - fishing_ended를 똑같이 쏴줘야 그 신호에 기대는 쪽(예:
## player.tool_overlay, main.gd의 _on_fishing_ended)이 취소도 "낚시 끝남"으로
## 알아챈다. 예전엔 이 신호를 안 쏴서, 미니게임 중 ESC로 닫으면 낚시대 사용
## 포즈가 안 풀린 채로 계속 걸어다니는 버그가 있었다(2026-08-12 리포트).
func cancel_fishing() -> void:
	_phase = Phase.IDLE
	_current_species = ""
	fishing_ended.emit({"success": false, "item_id": "", "cancelled": true})


func is_waiting_for_bite() -> bool:
	return _phase == Phase.WAITING_FOR_BITE


func is_biting() -> bool:
	return _phase == Phase.MINIGAME


## fishing_screen.gd가 bite_started를 받았을 때 미니게임 UI를 열지 말지
## 판단하는 용도 - 물귀신 가짜 입질은 UI 없이 사운드+독백으로만 연출한다.
func is_ghost_bite() -> bool:
	return _is_ghost_bite


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
