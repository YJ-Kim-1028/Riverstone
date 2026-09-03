extends Control

## 상태창 - TAB으로 열고 닫기(ESC로도 닫힘), 다른 모달과 동일하게
## main.gd._update_ui_blocking()에서 이동차단/시간정지 대상이 된다
## (controls.md: 장비/NPC 호감도/게임 설정 3탭). 탭 전환 버튼은 창 오른쪽에
## 배치한다(사용자 지시). 맨 아래 게임 종료 아이콘은 패널이 아니라 바로
## quit_confirm_popup을 여는 액션 버튼 - _panels/_show_tab 대상이 아니다.
## 자동저장은 취침/맵 이동 시에만 일어나므로(save.md), 그냥 종료하면 그 사이
## 진행 상황이 날아간다 - 확인 팝업에서 "예"를 누르면 현재 슬롯에 한 번
## 저장한 뒤 종료한다.

@onready var _equipment_panel: Control = $Background/Margin/HBox/ContentArea/EquipmentPanel
@onready var _affection_panel: Control = $Background/Margin/HBox/ContentArea/AffectionPanel
@onready var _settings_panel: Control = $Background/Margin/HBox/ContentArea/SettingsPanel
@onready var _equipment_tab_button: TextureButton = $Background/Margin/HBox/TabButtons/EquipmentTabButton
@onready var _affection_tab_button: TextureButton = $Background/Margin/HBox/TabButtons/AffectionTabButton
@onready var _settings_tab_button: TextureButton = $Background/Margin/HBox/TabButtons/SettingsTabButton
@onready var _end_tab_button: TextureButton = $Background/Margin/HBox/TabButtons/EndTabButton
@onready var _close_button: TextureButton = $Background/CloseButton
@onready var _quit_confirm_popup: Control = $QuitConfirmPopup

## equipment_panel.gd에서 책 우클릭 시 올라오는 요청을 main.gd까지 그대로
## 중계한다 - book_screen을 열 수 있는 건 UI 트리 전체에 접근하는 main.gd뿐이라
## (collection_interacted 등 다른 화면 열기 신호와 동일한 패턴).
signal book_open_requested(item_id: String)

var _panels: Array = []
var _is_open := false
## main.gd가 _ready()에서 채워준다(main.gd만 UI 트리 전체를 알아서 다른 화면이
## 열려있는지 판단할 수 있음 - equipment_panel.gd의 book_open_requested와 같은
## 중계 패턴). TAB 키는 이 화면이 직접 듣는 전역 단축키라, 컴퓨터(메일) 등
## 다른 화면이 이미 열려있어도 그 위에 그대로 열려버리는 문제가 있었다(사용자
## 리포트, 2026-08-27 - "메일 열어서 메일을 클릭했는데 마치 장비창이 열린
## 거처럼 갑자기 감자씨앗의 설명이 떠").
var _open_blocked_check: Callable = Callable()


func set_open_blocked_check(check: Callable) -> void:
	_open_blocked_check = check


## QuitConfirmPopup은 원래 전체화면 딤을 깔도록 설계됐지만(quit_confirm_popup.tscn
## 루트가 anchor 0/0/1/1), 이 상태창(StatusScreen) 자신이 화면 전체가 아니라
## 가운데 고정된 작은 박스(240x144, clip_contents=true)라서 그 안에 자식으로
## 있는 한 딤도 그 작은 박스 크기로만 잘려 보인다 - TAB 메뉴를 거쳐 열든
## (기존 경로) ESC로 단독으로 열든(신규 경로, 2026-09-01) 마찬가지 문제라서,
## 열 때마다 이 상태창 밖(같은 부모인 UI CanvasLayer)으로 잠깐 옮겨서 진짜
## 전체화면으로 뜨게 하고, 닫히면 제자리로 돌려놓는다. 이렇게 하면 두 경로가
## 완전히 같은 코드를 타서 별도 "단독으로 열었는지" 상태를 안 들고 있어도 된다.
func open_quit_confirm() -> void:
	var ui_layer := get_parent()
	remove_child(_quit_confirm_popup)
	ui_layer.add_child(_quit_confirm_popup)
	_quit_confirm_popup.open()


func is_quit_confirm_open() -> bool:
	return _quit_confirm_popup.modulate.a > 0.0


func _on_quit_confirm_canceled() -> void:
	var ui_layer := _quit_confirm_popup.get_parent()
	if ui_layer == self:
		return
	ui_layer.remove_child(_quit_confirm_popup)
	add_child(_quit_confirm_popup)


func _ready() -> void:
	_set_open(false)
	_panels = [_equipment_panel, _affection_panel, _settings_panel]
	_equipment_tab_button.pressed.connect(_show_tab.bind(0))
	_affection_tab_button.pressed.connect(_show_tab.bind(1))
	_settings_tab_button.pressed.connect(_show_tab.bind(2))
	_end_tab_button.pressed.connect(open_quit_confirm)
	_quit_confirm_popup.confirmed.connect(_on_quit_confirmed)
	_quit_confirm_popup.canceled.connect(_on_quit_confirm_canceled)
	_close_button.pressed.connect(close)
	_equipment_panel.status_close_requested.connect(close)
	_equipment_panel.book_open_requested.connect(func(item_id: String) -> void: book_open_requested.emit(item_id))


## TAB만 여기서 따로 처리한다(_unhandled_input이 아니라 _input) - 이 창 안의
## 버튼(탭 전환 버튼 등)을 한 번 클릭하면 그 버튼이 키보드 포커스를 갖게
## 되는데, Godot은 포커스 있는 컨트롤이 있으면 Tab 키를 "다음 포커스로 이동"
## 용으로 먼저 소비해버려서 _unhandled_input까지 아예 안 내려온다 - 그래서
## "열 때는 되는데 닫으려고 다시 누르면 가끔 안 먹힌다"는 증상이 났다(사용자
## 리포트, 2026-08-27). _input은 포커스 처리보다 먼저 불려서 항상 확실히
## 받고, set_input_as_handled()로 그 뒤 포커스 이동에 안 넘어가게 막는다.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		AudioManager.play_sfx(AudioManager.SFX_UI_TAB)
		toggle()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _is_open:
		close()


func toggle() -> void:
	if _is_open:
		close()
	elif _open_blocked_check.is_valid() and _open_blocked_check.call():
		return
	else:
		open()


func open() -> void:
	## 주의: 이 화면은 원래 전체화면이 아니라 가운데 고정 크기 박스로 설계된
	## 창이다 - slot_picker_screen.gd처럼 set_anchors_and_offsets_preset(PRESET_FULL_RECT)를
	## 넣었더니 오히려 화면 전체를 덮어버리는 새 버그가 생겼다(사용자 리포트,
	## 2026-08-26 - "tab 누르면 나오는 창이 전체 화면을 다 덮어버렸는데") -
	## 그 호출은 여기 넣으면 안 됨.
	_set_open(true)
	_show_tab(0)


func close() -> void:
	_set_open(false)


## computer_screen.gd/shop_screen.gd와 동일한 이유/동일한 수정(사용자 리포트,
## 2026-08-27) - 자기 값을 자기에게 재대입하는 방식은 값이 이미 같으면
## 엔진이 재계산을 안 해서 효과가 없었다. 이 화면의 루트는 가운데 고정 크기
## 박스(anchor 0.5/0.5/0.5/0.5)라 PRESET_FULL_RECT는 못 쓰고(그 실수는 이미
## 한 번 겪음 - 위 open() 주석 참고), 크기는 유지한 채 진짜로 다시 가운데
## 정렬시키는 PRESET_CENTER + KEEP_SIZE를 쓴다.
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


## QuitConfirmPopup은 자기 열고 닫기를 스스로 관리한다(자기 자신의 _set_open()
## - 종료 아이콘을 눌러야만 연다). 그런데 이 팝업이 status_screen의 자식이라
## 여기서 재귀로 내려가면 매번 그 안의 Dim(화면 전체를 덮는 반투명 배경)까지
## STOP으로 덮어써버린다 - Dim은 modulate.a로만 숨겨질 뿐 visible은 항상
## true라 계속 화면을 덮고 있고, mouse_filter가 STOP이 되는 순간 그 위에 있는
## 다른 버튼(탭 전환, 장비 슬롯 등)의 클릭을 다 가로채버린다(사용자 리포트,
## 2026-08-27 - "탭 열고 닫았다가 하면 탭에 있는 다른 버튼들이 안눌리잖아").
## 이 팝업 하위는 건드리지 않고 자기 자신에게 맡긴다.
func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node == _quit_confirm_popup:
		return
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _show_tab(index: int) -> void:
	for i in _panels.size():
		_panels[i].visible = i == index
	if index == 0:
		_equipment_panel.refresh()
	elif index == 1:
		_affection_panel.refresh()


func _on_quit_confirmed() -> void:
	SaveManager.save_game(SaveManager.current_slot)
	get_tree().quit()
