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


func _ready() -> void:
	visible = false
	_panels = [_equipment_panel, _affection_panel, _settings_panel]
	_equipment_tab_button.pressed.connect(_show_tab.bind(0))
	_affection_tab_button.pressed.connect(_show_tab.bind(1))
	_settings_tab_button.pressed.connect(_show_tab.bind(2))
	_end_tab_button.pressed.connect(_quit_confirm_popup.open)
	_quit_confirm_popup.confirmed.connect(_on_quit_confirmed)
	_close_button.pressed.connect(close)
	_equipment_panel.status_close_requested.connect(close)
	_equipment_panel.book_open_requested.connect(func(item_id: String) -> void: book_open_requested.emit(item_id))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		AudioManager.play_sfx(AudioManager.SFX_UI_TAB)
		toggle()
	elif event.keycode == KEY_ESCAPE and visible:
		close()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_show_tab(0)


func close() -> void:
	visible = false


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
