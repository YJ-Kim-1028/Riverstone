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
@onready var _hit_label: Label = $Background/HitLabel
@onready var _time_bar: FishingTimeBar = $Background/TimeBar
@onready var _result_icon: TextureRect = $Background/ResultIcon
@onready var _result_label: Label = $Background/ResultLabel

var _last_spawn_index := -1


func _ready() -> void:
	visible = false
	_result_label.visible = false
	FishingManager.bite_started.connect(_open)
	FishingManager.fishing_ended.connect(_on_fishing_ended)
	_fish.hit_while_visible.connect(_on_fish_hit)
	_fish.relocate_requested.connect(_relocate_fish)


func _process(_delta: float) -> void:
	if not visible or not FishingManager.is_biting():
		return
	_time_bar.progress = FishingManager.get_minigame_time_remaining_ratio()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_force_cancel()


func _open() -> void:
	## 물귀신 가짜 입질(FishingManager.is_ghost_bite())은 이 두더지 게임 UI를
	## 아예 안 연다(사용자 지시, 2026-08-24) - main.gd의 _on_fishing_ended가
	## 대신 사운드+독백으로 연출한다.
	if FishingManager.is_ghost_bite():
		return
	visible = true
	_result_label.visible = false
	_result_icon.visible = false
	_hit_label.text = "0 / %d" % FishingManager.get_required_hits()
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
	_hit_label.text = "%d / %d" % [FishingManager.get_hit_count(), FishingManager.get_required_hits()]
	if FishingManager.is_biting():
		_relocate_fish()


func _on_fishing_ended(result: Dictionary) -> void:
	if not visible:
		return
	_fish.stop_cycle()
	_result_label.visible = true
	_show_result(result)
	await get_tree().create_timer(RESULT_HOLD_SECONDS).timeout
	visible = false


## 성공하면 물고기 이름 대신 잡은 아이콘 그림 + "획득!"을 보여준다(사용자
## 지시) - 인벤토리가 꽉 차서 못 넣었거나 실패했을 때는 아이콘 없이 문구만.
func _show_result(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		_result_icon.visible = false
		_result_label.text = "실패"
		return
	var item_id := String(result.get("item_id", ""))
	if not bool(result.get("added_to_inventory", true)):
		_result_icon.visible = false
		var item_name := String(InventoryManager.get_item_definition(item_id).get("name", item_id))
		_result_label.text = "%s를 낚았지만 인벤토리가 가득 찼다." % item_name
		return
	_result_icon.visible = true
	_result_icon.texture = InventoryManager.get_item_icon_texture(item_id)
	_result_label.text = "획득!"


## cancel_fishing()이 fishing_ended를 쏘므로(2026-08-12부터), 그 신호가
## 도착하는 시점에 이미 visible=false여야 _on_fishing_ended의 "닫혀있으면
## 무시" 가드에 걸려 결과 팝업(실패 문구)이 잠깐 뜨는 걸 막을 수 있다 - 순서를
## 바꾸면 안 됨.
func _force_cancel() -> void:
	visible = false
	_fish.stop_cycle()
	FishingManager.cancel_fishing()
