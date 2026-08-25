extends Node

## 도감 완성 보상: 추억의 물건 13개를 다 모으고(CollectionManager) 엔딩 3종 중
## 하나를 보면(MurderManager) "영혼의 결정"을 지급하고, 그걸 신사 제단에
## 바치면 죽은 피해자 한 명을 부활시킬 수 있다(사용자 지시, 2026-08-25).
## 두 조건은 어느 쪽이 먼저 채워지든 상관없어서, 각 신호가 올 때마다 둘 다
## 채워졌는지 매번 확인하는 방식(_check_grant_condition)으로 순서 무관하게
## 딱 한 번만 지급한다. 지급/부활 컷신 연출 자체는 main.gd가 담당하고, 여기는
## 조건 판정 + 상태(1회성 플래그, 인벤토리 지급)만 책임진다.

signal soul_crystal_granted
signal npc_revival_completed(npc_id: String)

const SOUL_CRYSTAL_ITEM_ID := "soul_crystal"
## endings.json과 같은 형식(화자 없는 문장 배열이 섹션별로) - 제단 컷신/지급
## 연출용 문구. 실제 한국어 내용은 기획자가 채운다(CLAUDE.md 규칙), 지금은
## 구조만 있고 TODO 상태.
const REVIVAL_DATA_PATH := "res://data/horror/revival.json"

var _soul_crystal_granted := false
var _revival_used := false
var _revival_data: Dictionary = {}
## 세이지에게 영혼의 결정을 들고 가서 설명을 들은 적 있는지(사용자 지시,
## 2026-08-25 - "그 아이템을 가진채로 세이지에게 말을 걸면 딱 한번 대사
## 이벤트가 뜨게 돼"). npc_manager.gd::get_daily_dialogue()가 확인/소비한다.
var _soul_crystal_explained := false


func _ready() -> void:
	_load_revival_data()
	CollectionManager.full_memento_collection_achieved.connect(_check_grant_condition)
	MurderManager.truth_ending_triggered.connect(_check_grant_condition)
	MurderManager.accomplice_ending_triggered.connect(func(_victim_id: String) -> void: _check_grant_condition())
	MurderManager.arrest_ending_triggered.connect(func(_spared_npc_id: String) -> void: _check_grant_condition())


func _load_revival_data() -> void:
	var file := FileAccess.open(REVIVAL_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Revival data could not be opened: %s" % REVIVAL_DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Revival data is not valid JSON: %s" % REVIVAL_DATA_PATH)
		return
	_revival_data = parsed


## main.gd의 제단/지급 컷신이 화자 없는 내레이션 줄을 가져올 때 쓴다 -
## murder_manager.gd::get_ending_narration()과 같은 용도, 다른 데이터 파일.
func get_narration(section: String) -> Array:
	return (_revival_data.get(section, []) as Array).duplicate()


func get_text(key: String) -> String:
	return String(_revival_data.get(key, ""))


func _check_grant_condition() -> void:
	if _soul_crystal_granted:
		return
	if not CollectionManager.is_full_memento_collection():
		return
	if not MurderManager.has_ending_achieved():
		return
	_soul_crystal_granted = true
	soul_crystal_granted.emit()


## main.gd::_play_soul_crystal_merge()가 영혼이 플레이어 가슴팍에 스며드는
## 연출이 끝난 순간 호출 - 인벤토리 지급을 여기로 미뤄서(사용자 지시,
## 2026-08-25 - "그러고 인벤에 들어와있고") 컷신이 실제로 보여준 뒤에야 아이템이
## 생기게 한다. _check_grant_condition()은 조건 판정/플래그만 처리하고 지급은
## 여기가 전담.
func complete_soul_crystal_grant() -> void:
	InventoryManager.add_item(SOUL_CRYSTAL_ITEM_ID, 1)


func has_explained_soul_crystal() -> bool:
	return _soul_crystal_explained


func mark_soul_crystal_explained() -> void:
	_soul_crystal_explained = true


## main.gd가 제단 상호작용 프롬프트를 보여줄지 판단할 때 쓴다 - 영혼의
## 결정이 없거나 이미 부활을 썼으면 조용히 그냥 배경 오브젝트로 취급.
func can_use_altar() -> bool:
	return not _revival_used and InventoryManager.has_item(SOUL_CRYSTAL_ITEM_ID)


## 부활 후보 - 스토커(어셔) 본인만 제외한 죽은 NPC 전원. 스토커가 죽인
## 1~2명과, 플레이어가 직접 독살한 무고한 NPC가 있으면 그 사람까지 자연히
## 여기 포함된다(둘 다 NPCManager._dead_npc_ids에 동일하게 쌓이므로 별도
## 분기 불필요 - 사용자 지시, 2026-08-25).
func get_revivable_victim_ids() -> Array[String]:
	var result: Array[String] = []
	var stalker_id := NPCManager.get_stalker_id()
	for npc_id in NPCManager.get_dead_npc_ids():
		if npc_id != stalker_id:
			result.append(npc_id)
	return result


## 디버그 전용(game_manager.gd F6) - 도감 13개 다 모으고 엔딩까지 안 봐도
## 지급 컷신부터 바로 테스트할 수 있게, 조건 판정만 건너뛰고 실제 지급 신호는
## 그대로 흘려보낸다(사용자 지시, 2026-08-25) - _check_grant_condition()의
## 성공 분기와 동일하게 처리해서, 다음 취침/기절 시 main.gd의 진짜 비행
## 컷신이 재생되고 그게 끝나야 인벤토리에 들어온다(디버그와 실전 경로가
## 최대한 같아야 컷신 자체를 신뢰성 있게 테스트할 수 있음).
## 반복 테스트 지원 - 이미 한 번 지급/부활을 써본 상태(이전 테스트나 옛
## 저장파일에서 이미 _soul_crystal_granted가 true)여도 매번 다시 발동되도록
## 강제로 리셋한다. 이미 인벤토리에 남아있던 영혼의 결정도 지워서(중복 방지)
## 컷신이 끝난 뒤에야 새로 1개 들어오게 한다.
func debug_force_grant_soul_crystal() -> void:
	if InventoryManager.has_item(SOUL_CRYSTAL_ITEM_ID):
		InventoryManager.remove_item(SOUL_CRYSTAL_ITEM_ID, InventoryManager.get_item_count(SOUL_CRYSTAL_ITEM_ID))
	_soul_crystal_granted = true
	_revival_used = false
	soul_crystal_granted.emit()


func mark_revival_used(npc_id: String) -> void:
	_revival_used = true
	npc_revival_completed.emit(npc_id)


func get_save_data() -> Dictionary:
	return {
		"soul_crystal_granted": _soul_crystal_granted,
		"revival_used": _revival_used,
		"soul_crystal_explained": _soul_crystal_explained,
	}


func load_save_data(data: Dictionary) -> void:
	_soul_crystal_granted = bool(data.get("soul_crystal_granted", false))
	_revival_used = bool(data.get("revival_used", false))
	_soul_crystal_explained = bool(data.get("soul_crystal_explained", false))
