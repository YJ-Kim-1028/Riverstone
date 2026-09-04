extends Control

## 상태창(TAB) "장비" 탭. 왼쪽엔 플레이어 미리보기+모자/손/신발 슬롯(사용자
## 지시로 이 순서 - 손이 신발보다 위), 오른쪽엔 인벤토리 전체를 보여준다.
## 인벤토리 슬롯(category=="equipment" 또는 "tool")을 왼쪽 슬롯으로 드래그하면
## 착용된다(inventory_slot.gd/equipment_slot.gd 참고).
## 예전엔 별도 인벤토리 화면(I키)이 따로 있었는데, 여기 그리드랑 내용이
## 거의 겹쳐서 사용자 지시로 통합했다 - 정렬/버리기 버튼을 장비 슬롯 옆
## 남는 공간에 두고, 슬롯을 클릭하면 선택(테두리 강조)되어 버리기 대상이
## 되며, 이름/설명은 (그리드가 6칸씩이라 자리가 없어서) 마우스 오버 툴팁으로
## 대체했다(collection_screen.gd와 같은 방식).

## status_screen.gd(TAB 창 본체)가 듣고 닫아준다 - 레시피 우클릭 사용 시 머리
## 위 안내 문구가 이 창에 가려지지 않게 하기 위함(main.gd의 recipe_learned
## 처리 참고). 책 우클릭 사용 시에도 book_screen을 가리지 않도록 같이 쓴다.
signal status_close_requested
## status_screen.gd를 거쳐 main.gd까지 전달되어 book_screen.open_book()을
## 연다(main.gd만 UI 트리 전체에 접근할 수 있어서 - collection_interacted 등
## 다른 화면 열기 신호와 동일한 중계 패턴).
signal book_open_requested(item_id: String)
## status_screen.gd가 대신 띄워준다(아래 _show_tooltip()/_hide_tooltip() 주석
## 참고 - ContentArea의 clip_contents 때문에 이 패널 안에서는 오른쪽 끝(탭
## 아이콘 쪽) 근처 툴팁이 잘려서, 그 클립 바깥인 StatusScreen 쪽에서 대신
## 그려야 한다).
signal tooltip_requested(text: String, source: Control)
signal tooltip_hide_requested

const SlotScene := preload("res://scenes/ui/inventory_slot.tscn")
## storage_screen.gd의 BAG_SOURCE와 같은 값 - 같은 그리드 내 드래그 재정렬용
## source_tag로 쓴다(다른 화면과 데이터를 주고받는 용도가 아니라 단순 표식).
const BAG_SOURCE := "bag"
const INVALID_DROP_MESSAGE := "이 곳에는 착용할 수 없다."
## equipment_slot.gd의 equip_failed 참고 - 이미 장착된 아이템을 인벤토리로
## 돌려줄 자리가 없을 때 조용히 실패하던 걸 알려준다(사용자 리포트, 2026-08-27).
const EQUIP_FAILED_MESSAGE := "인벤토리에 자리가 없어 교체할 수 없다."
const MESSAGE_DURATION := 2.0
const SELECTED_TINT := Color(1.3, 1.15, 0.7)
## 다른 화면(상점창 등)의 _style_scrollbar()와 동일한 값 - 창마다 스크롤바
## 굵기/색이 달라 보인다는 피드백으로 전부 통일한다.
const SCROLLBAR_WIDTH := 4

@onready var _inventory_scroll: ScrollContainer = $VBox/InventoryScroll
@onready var _inventory_grid: GridContainer = $VBox/InventoryScroll/GridMargin/InventoryGrid
@onready var _hat_slot: EquipmentSlot = $VBox/TopRow/SlotsVBox/HatSlot
@onready var _hand_slot: EquipmentSlot = $VBox/TopRow/SlotsVBox/HandSlot
@onready var _shoes_slot: EquipmentSlot = $VBox/TopRow/SlotsVBox/ShoesSlot
@onready var _sort_button: TextureButton = $VBox/TopRow/ButtonsVBox/SortButton
@onready var _discard_button: TextureButton = $VBox/TopRow/ButtonsVBox/DiscardButton
@onready var _message_label: Label = $MessageLabel

var _message_timer := 0.0
var _selected_index := -1


func _ready() -> void:
	## 모자/신발 관련 아이템이 아직 하나도 없어서(items.json에 subtype
	## "hat"/"shoes" 항목 자체가 없음) 지금 상태로 내보내면 아무것도 착용 못 할
	## 빈 슬롯만 보인다(사용자 지시, 2026-08-26 - "현재 개발한 게 없어서 지금은
	## 이거 안보이게 해줄 수 있어?"). 손 슬롯은 도구/보관함 등 실제로 쓰이므로
	## 그대로 둔다. 콘텐츠 생기면 이 두 줄만 지우면 된다.
	_hat_slot.visible = false
	_shoes_slot.visible = false
	InventoryManager.inventory_changed.connect(_refresh_inventory)
	_hat_slot.invalid_drop_attempted.connect(_show_invalid_drop_message)
	_hand_slot.invalid_drop_attempted.connect(_show_invalid_drop_message)
	_shoes_slot.invalid_drop_attempted.connect(_show_invalid_drop_message)
	_hat_slot.equip_failed.connect(_show_equip_failed_message)
	_hand_slot.equip_failed.connect(_show_equip_failed_message)
	_shoes_slot.equip_failed.connect(_show_equip_failed_message)
	_hat_slot.mouse_entered.connect(_show_tooltip.bind(_hat_slot))
	_hat_slot.mouse_exited.connect(_hide_tooltip)
	_hand_slot.mouse_entered.connect(_show_tooltip.bind(_hand_slot))
	_hand_slot.mouse_exited.connect(_hide_tooltip)
	_shoes_slot.mouse_entered.connect(_show_tooltip.bind(_shoes_slot))
	_shoes_slot.mouse_exited.connect(_hide_tooltip)
	_sort_button.pressed.connect(_on_sort_pressed)
	_discard_button.pressed.connect(_on_discard_pressed)
	_style_scrollbar()


## 인벤토리 슬롯이 6칸씩 밖에 없어서 슬롯 개수가 늘어나면(인벤토리 확장 구매
## 등) 줄이 넘쳐 잘려 안 보이던 버그(사용자 리포트: "탭 인벤토리창에 스크롤이
## 안 됨") - 애초에 ScrollContainer 자체가 없었다. 상점창과 동일한 구조로
## 추가했다.
func _style_scrollbar() -> void:
	var scrollbar := _inventory_scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.15)
	track.set_corner_radius_all(2)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.55, 0.4, 0.25, 0.9)
	grabber.set_corner_radius_all(2)
	scrollbar.add_theme_stylebox_override("scroll", track)
	scrollbar.add_theme_stylebox_override("grabber", grabber)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber)


## 엔진 기본 툴팁(Control.tooltip_text)은 이 게임이 320x180 캔버스를 4배로
## 확대해서 보여주는 구조(project.godot의 window/stretch/mode="canvas_items")와
## 안 맞아서, 확대된 화면 기준으로 보면 커서와 동떨어진 자리에 뜬다(사용자
## 리포트, 2026-09-01 - "툴팁 뜨는 위치 이상하다") - 엔진 팝업은 이 캔버스
## 스케일을 모르는 별도 좌표계에서 위치를 계산하기 때문. 그래서 기본
## tooltip_text 대신 신호로 status_screen.gd에게 표시를 맡긴다. 슬롯 쪽은
## `.tooltip_text`(엔진 팝업을 같이 띄움) 대신 `set_meta("tooltip_text", ...)`로
## 문구만 들고 있게 했다(_refresh_inventory()/equipment_slot.gd 참고).
## 원래는 이 패널 안에 Tooltip 노드를 직접 두고 켜고/껐었는데, 부모
## ContentArea가 clip_contents=true(폭 170px)라 오른쪽 끝(탭 아이콘 쪽) 근처
## 슬롯의 툴팁이 그 경계에서 잘려 보였다(사용자 리포트, 2026-09-05 - "우측에
## 아이콘 범위에 들어가면 그렇게 되나봐"). z_index로는 clip_contents를
## 못 넘어서므로, 그 클립 바깥(StatusScreen 루트)에 있는 Tooltip을
## status_screen.gd가 대신 그리도록 신호로 위임했다.
func _show_tooltip(source: Control) -> void:
	var text := String(source.get_meta("tooltip_text", ""))
	if text.is_empty():
		return
	tooltip_requested.emit(text, source)


func _hide_tooltip() -> void:
	tooltip_hide_requested.emit()


func _process(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		_message_label.visible = false


func _show_invalid_drop_message() -> void:
	_message_label.text = INVALID_DROP_MESSAGE
	_message_label.visible = true
	_message_timer = MESSAGE_DURATION


func _show_equip_failed_message() -> void:
	_message_label.text = EQUIP_FAILED_MESSAGE
	_message_label.visible = true
	_message_timer = MESSAGE_DURATION


func refresh() -> void:
	## status_screen.gd가 TAB을 열 때마다 이걸 호출한다 - 인벤토리 그리드뿐
	## 아니라 장비 슬롯 3개도 같이 refresh()해야 equipment_slot.gd의 자가치유
	## (Icon/CountLabel mouse_filter 복구)가 매번 실제로 돌아간다(2026-08-27
	## 드래그 안 빠지는 버그 수정 참고).
	_hat_slot.refresh()
	_hand_slot.refresh()
	_shoes_slot.refresh()
	_refresh_inventory()


func _refresh_inventory() -> void:
	## 그리드가 통째로 다시 만들어지므로, 지금 뜬 툴팁이 가리키던 슬롯도 같이
	## 사라진다 - mouse_exited가 그 슬롯에서 안 올 수 있으니 여기서 미리 끈다.
	_hide_tooltip()
	for child in _inventory_grid.get_children():
		child.queue_free()
	var slots: Array = InventoryManager.get_slots()
	if _selected_index >= slots.size() or (_selected_index >= 0 and slots[_selected_index] == null):
		_selected_index = -1
	for i in slots.size():
		var slot_instance := SlotScene.instantiate() as TextureButton
		_inventory_grid.add_child(slot_instance)
		# status_screen.gd는 열고 닫을 때 그 순간 존재하는 서브트리에만 재귀로
		# mouse_filter를 STOP/IGNORE 처리한다 - 닫혀있는 동안(예: 선물/퀘스트
		# 보상으로) InventoryManager.inventory_changed가 쏴서 이 그리드가 다시
		# 만들어지면, 새로 생긴 슬롯은 그 재귀를 못 거치고 TextureButton 기본값인
		# STOP인 채로 남아 안 보이면서도 클릭을 가로챈다(사용자 리포트 - "인벤
		# 창이 안 사라져서 요청함이 안 눌림"). 이 패널 자신의 mouse_filter는
		# status_screen이 열고 닫을 때마다 항상 갱신되므로, 새 슬롯도 그 값을
		# 그대로 물려받게 하면 닫힌 동안 생겨도 처음부터 IGNORE로 시작한다.
		slot_instance.mouse_filter = mouse_filter
		slot_instance.call("setup", i, slots[i])
		slot_instance.set_meta("tooltip_text", _tooltip_for(slots[i]))
		slot_instance.mouse_entered.connect(_show_tooltip.bind(slot_instance))
		slot_instance.mouse_exited.connect(_hide_tooltip)
		slot_instance.source_tag = BAG_SOURCE
		slot_instance.accepts_drops = true
		slot_instance.connect("slot_pressed", _on_slot_pressed)
		slot_instance.connect("slot_right_clicked", _on_slot_right_clicked)
		slot_instance.connect("slot_drop_received", _on_slot_drop_received)
		slot_instance.modulate = SELECTED_TINT if i == _selected_index else Color.WHITE


func _tooltip_for(slot_data) -> String:
	if slot_data == null:
		return ""
	var definition := InventoryManager.get_item_definition(String(slot_data.get("item_id", "")))
	var name_text := String(definition.get("name", ""))
	var description_text := String(definition.get("description", ""))
	return "%s\n%s" % [name_text, description_text] if not description_text.is_empty() else name_text


func _on_slot_pressed(index: int) -> void:
	_selected_index = -1 if _selected_index == index else index
	_refresh_inventory()


## 인벤 그리드 안에서 슬롯을 드래그해 다른 슬롯에 놓으면 두 자리를 맞바꾼다
## (사용자 지시, 2026-08-30 - "인벤 내에서 위치 바꿀수있게끔"). 장비 슬롯(모자/
## 손/신발)에서 꺼내는 드래그(equipment_slot.gd)는 from_index 대신
## equipment_slot 키가 실려오는데, 놓은 칸(target_index) 그대로 돌려준다
## (사용자 리포트, 2026-09-01 - "원하는 칸에 드래그 했는데 항상 맨 앞칸으로
## 들어간다" - 예전엔 여기서 그냥 무시하고 equipment_slot.gd의
## NOTIFICATION_DRAG_END 쪽 fallback이 항상 첫 빈 칸에 넣었었다). 그리드
## 바깥(빈 공간)에 놓는 경우는 이 신호 자체가 안 와서 여전히 그 fallback이
## 처리한다.
func _on_slot_drop_received(_source_tag: String, target_index: int, data: Dictionary) -> void:
	if data.has("from_index"):
		InventoryManager.swap_slots(int(data["from_index"]), target_index)
	elif data.has("equipment_slot"):
		EquipmentManager.unequip_to_slot(String(data["equipment_slot"]), target_index)


func _on_sort_pressed() -> void:
	InventoryManager.sort_by_name()


func _on_discard_pressed() -> void:
	var slots: Array = InventoryManager.get_slots()
	if _selected_index < 0 or _selected_index >= slots.size() or slots[_selected_index] == null:
		return
	# 낚싯대/괭이/물뿌리개 같은 도구류는 is_discardable()이 false라
	# discard_item()이 조용히 실패한다 - 실패했을 땐 선택을 그대로 유지해야
	# (버려지지 않았으니 여전히 선택된 상태가 맞음) 계속 눌러도 매번 삐 소리가
	# 난다. 예전엔 성공/실패 상관없이 항상 선택을 풀어버려서, 첫 클릭에서만
	# 소리가 나고 그 다음부터는 선택이 이미 풀려있어 아무 반응이 없었다
	# (사용자 리포트).
	if InventoryManager.discard_item(_selected_index, int(slots[_selected_index]["count"])):
		_selected_index = -1
	else:
		AudioManager.play_sfx(AudioManager.SFX_BEEP)


## 커피/자양강장제 같은 소비 아이템, 레시피 아이템, 책 슬롯을 우클릭하면 바로
## 사용한다(사용자 지시 - 선택 후 버튼을 누르는 대신 우클릭 한 번으로 끝냄,
## "사용"/"배우기" 버튼은 삭제됨). 못 쓰는 아이템(장비/도구 등)이면 조용히
## 무시한다.
func _on_slot_right_clicked(index: int) -> void:
	_use_slot(index)


func _use_slot(index: int) -> void:
	var slots: Array = InventoryManager.get_slots()
	if index < 0 or index >= slots.size() or slots[index] == null:
		return
	var item_id := String(slots[index].get("item_id", ""))
	var category := InventoryManager.get_item_category(item_id)
	if category == "recipe":
		InventoryManager.learn_recipe(index)
		# 레시피 획득 안내 문구가 플레이어 머리 위에 뜨는데(main.gd), 이 창이
		# 화면을 가리고 있으면 아무 의미가 없다(사용자 지시) - 배운 레시피가
		# 실제로 있었는지와 무관하게(이미 다 아는 레시피였어도) 우클릭했다는
		# 사실 자체로 닫아서 항상 결과를 바로 볼 수 있게 한다.
		status_close_requested.emit()
	elif category == "consumable":
		InventoryManager.use_item(index)
	elif category == "book":
		# 책은 레시피와 달리 소비되지 않는다 - 몇 번이든 다시 읽을 수 있는
		# 소장품(inventory_manager.gd: category "book"은 discardable도 아님).
		book_open_requested.emit(item_id)
		status_close_requested.emit()
	elif category == "perfume":
		# 향수(마르가 준 perfume_somewhere_behind_you)도 book처럼 소비되지
		# 않는다 - 우클릭할 때마다 다시 뿌릴 수 있다(사용자 지시).
		InventoryManager.use_perfume(index)
