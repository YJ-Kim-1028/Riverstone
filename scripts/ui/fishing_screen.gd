extends Control

## 낚시 두더지 게임 화면 - FishingManager.bite_started가 뜨면 스스로 열리고,
## FishingManager.fishing_ended가 뜨면 결과를 잠깐 보여준 뒤 스스로 닫힌다.
## main.gd에 computer_interacted류의 라우팅 신호를 추가로 만들지 않는다
## (main.gd가 이미 300줄 가이드라인을 넘긴 상태라 더 키우지 않으려는 선택 -
## kitchen_screen.gd가 InventoryManager 신호를 직접 구독하는 것과 같은 방식).
## 닫기는 버튼 없이 ESC 전용(사용자 확정 - 시간 지나면 알아서 닫히니 X 버튼은
## 필요 없다고 판단, collection_screen.gd와 같은 방식).

const RESULT_HOLD_SECONDS := 1.5

@onready var _spawn_points: Node = $Background/SpawnPoints
@onready var _fish: FishingFish = $Background/Fish
@onready var _hit_gauge: FishingHitGauge = $Background/HitGauge
@onready var _time_bar: FishingTimeBar = $Background/TimeBar
@onready var _result_icon: TextureRect = $Background/ResultIcon
@onready var _result_label: Label = $Background/ResultLabel

var _last_spawn_index := -1


func _ready() -> void:
	_set_open(false)
	_result_label.visible = false
	FishingManager.bite_started.connect(_open)
	FishingManager.fishing_ended.connect(_on_fishing_ended)
	_fish.hit_while_visible.connect(_on_fish_hit)
	_fish.relocate_requested.connect(_relocate_fish)


func _process(_delta: float) -> void:
	if not _is_open() or not FishingManager.is_biting():
		return
	_time_bar.progress = FishingManager.get_minigame_time_remaining_ratio()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_force_cancel()


func _open() -> void:
	## 물귀신 가짜 입질(FishingManager.is_ghost_bite())은 이 두더지 게임 UI를
	## 아예 안 연다(사용자 지시, 2026-08-24) - main.gd의 _on_fishing_ended가
	## 대신 사운드+독백으로 연출한다.
	if FishingManager.is_ghost_bite():
		return
	## 주의: 이 화면은 원래 전체화면이 아니라 가운데 고정 크기 박스로 설계된
	## 창이다 - set_anchors_and_offsets_preset(PRESET_FULL_RECT)는 화면 전체를
	## 덮어버리는 새 버그를 만든다(status_screen.gd/kitchen_screen.gd와 동일한
	## 사용자 리포트, 2026-08-26) - 여기 넣으면 안 됨.
	_set_open(true)
	_result_label.visible = false
	_result_icon.visible = false
	_hit_gauge.required_hits = FishingManager.get_required_hits()
	_hit_gauge.hit_count = 0
	_last_spawn_index = -1
	_relocate_fish()


func _relocate_fish() -> void:
	var points := _spawn_points.get_children()
	if points.is_empty():
		return
	var index := randi() % points.size()
	if points.size() > 1:
		while index == _last_spawn_index:
			index = randi() % points.size()
	_last_spawn_index = index
	_fish.position = points[index].position
	_fish.start_cycle()


func _on_fish_hit() -> void:
	if not FishingManager.register_hit():
		return
	_hit_gauge.hit_count = FishingManager.get_hit_count()
	if FishingManager.is_biting():
		_relocate_fish()


func _on_fishing_ended(result: Dictionary) -> void:
	if not _is_open():
		return
	_fish.stop_cycle()
	_result_label.visible = true
	_show_result(result)
	await get_tree().create_timer(RESULT_HOLD_SECONDS).timeout
	_set_open(false)


## 성공하면 물고기 이름 대신 잡은 아이콘 그림 + "획득!"을 보여준다(사용자
## 지시) - 인벤토리가 꽉 차서 못 넣었을 때는 아이콘 없이 문구만. 그냥 실패
## (시간 초과)는 이제 SFX_FISHING_FAIL 사운드로 알리므로 "실패" 글자는 아예
## 안 띄운다(사용자 지시, 2026-09-01 - "사운드 있으니까 실패 글씨는 안떠도
## 될 거 같아").
func _show_result(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		_result_icon.visible = false
		_result_label.visible = false
		return
	var item_id := String(result.get("item_id", ""))
	if not bool(result.get("added_to_inventory", true)):
		_result_icon.visible = false
		var item_name := String(InventoryManager.get_item_definition(item_id).get("name", item_id))
		_result_label.text = tr("%s를 낚았지만 인벤토리가 가득 찼다.") % item_name
		return
	_result_icon.visible = true
	_result_icon.texture = InventoryManager.get_item_icon_texture(item_id)
	_result_label.text = "획득!"


## cancel_fishing()이 fishing_ended를 쏘므로(2026-08-12부터), 그 신호가
## 도착하는 시점에 이미 닫힌 상태(_is_open() == false)여야 _on_fishing_ended의
## "닫혀있으면 무시" 가드에 걸려 결과 팝업(실패 문구)이 잠깐 뜨는 걸 막을 수
## 있다 - 순서를 바꾸면 안 됨.
func _force_cancel() -> void:
	_set_open(false)
	_fish.stop_cycle()
	FishingManager.cancel_fishing()


func _is_open() -> bool:
	return modulate.a > 0.0


## 익스포트 빌드에서 앵커 기반 크기/위치가 창이 완전히 자리잡기 전 값으로
## 굳어버리는 문제 회피(사용자 리포트, 2026-08-26) - 값은 그대로 자신에게
## 다시 대입해서 Godot이 현재 부모 크기 기준으로 강제로 다시 계산하게 만든다.
func _refresh_layout() -> void:
	anchor_left = anchor_left
	anchor_top = anchor_top
	anchor_right = anchor_right
	anchor_bottom = anchor_bottom
	offset_left = offset_left
	offset_top = offset_top
	offset_right = offset_right
	offset_bottom = offset_bottom


func _set_open(is_open: bool) -> void:
	if is_open:
		_refresh_layout()
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)
	# Fish/Icon은 물고기 버튼(Fish) 전체를 덮는 순전히 그림용 오버레이라
	# 항상 클릭을 통과시켜야 한다(.tscn에 mouse_filter=IGNORE로 지정해둠) -
	# 위 재귀 호출이 이걸 STOP으로 덮어써버리면 Icon이 클릭을 먼저 먹어서
	# 정작 Fish 버튼의 pressed가 한 번도 안 터지는 버그가 생긴다(사용자
	# 리포트, 2026-08-27: "낚시 물고기 클릭이 아예 안돼") - 재귀 적용 후
	# 다시 IGNORE로 되돌린다.
	_fish.get_node("Icon").mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
