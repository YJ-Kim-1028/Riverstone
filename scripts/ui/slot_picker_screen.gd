extends Control

## 시작하기/이어하기 공용 세이브 슬롯 선택 화면(SaveManager.SAVE_SLOT_COUNT=3).
## mode="new_game"이면 빈 슬롯만 고를 수 있고(이미 데이터가 있는 슬롯은
## 눌러도 아무 반응 없음 - 실수로 진행 상황을 덮어쓰는 걸 원천 차단하기로
## 사용자 확정: "그냥 있는 슬롯에는 새게임 못만들게하고 이어하기에서 게임
## 슬롯을 삭제할 수 있게 하는 게 더 좋을 거 같아"), mode="continue"면
## 데이터가 있는 슬롯만 고를 수 있다(빈 슬롯을 누르면 삐 소리만 남).
## 이어하기 모드에서만 슬롯마다 "삭제" 버튼이 나타나 - 삭제해서 슬롯을
## 비워야 그 자리에 새 게임을 만들 수 있다.
##
## 문자열로 모드를 주고받는 이유: 이 프로젝트는 크로스 스크립트 참조에서
## 정적 타입/커스텀 enum 타입 대신 이름 기반 호출을 쓰는 관례라(에디터
## 글로벌 클래스 캐시가 오래돼도 항상 동작하도록), 여기서도 enum 대신
## 문자열을 그대로 쓴다.

signal slot_confirmed(slot: int, mode: String)
signal closed

const MODE_NEW_GAME := "new_game"
const MODE_CONTINUE := "continue"

## 이 화면만 기본 엔진 테마 그대로라 "밤티"(다른 화면과 안 어울림) 피드백을
## 받아 추가 - character_creation_screen.gd/각종 confirm_popup.gd와 동일한
## button.png/button_hover.png 9-슬라이스 스타일로 통일.
const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const BUTTON_HOVER_TEXTURE := preload("res://assets/ui/button_hover.png")
const BUTTON_TEXT_COLOR := Color(0.25, 0.15, 0.08)
## title_screen.gd와 동일한 이유 - "disabled" 스타일박스를 안 채우면(이 화면은
## 이어하기에서 빈 슬롯, 새 게임에서 이미 찬 슬롯이 항상 disabled라 자주
## 보임) Godot 기본 테마의 밋밋한 사각형으로 보인다.
const DISABLED_TINT := Color(0.55, 0.55, 0.55)

@onready var _title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var _slot_buttons: Array = [
	$Panel/Margin/VBox/SlotList/SlotRow1/SlotButton,
	$Panel/Margin/VBox/SlotList/SlotRow2/SlotButton,
	$Panel/Margin/VBox/SlotList/SlotRow3/SlotButton,
]
@onready var _delete_buttons: Array = [
	$Panel/Margin/VBox/SlotList/SlotRow1/DeleteButton,
	$Panel/Margin/VBox/SlotList/SlotRow2/DeleteButton,
	$Panel/Margin/VBox/SlotList/SlotRow3/DeleteButton,
]
@onready var _back_button: Button = $Panel/Margin/VBox/BackButton
@onready var _confirm_popup: Control = $SlotDeleteConfirmPopup

var _mode := MODE_NEW_GAME
var _pending_delete_slot := -1
var _is_open := false


func _ready() -> void:
	_set_open(false)
	_back_button.pressed.connect(close)
	_style_button(_back_button)
	for i in _slot_buttons.size():
		var slot := i + 1
		_slot_buttons[i].pressed.connect(_on_slot_pressed.bind(slot))
		_delete_buttons[i].pressed.connect(_on_delete_pressed.bind(slot))
		_style_button(_slot_buttons[i])
		_style_button(_delete_buttons[i])
	_confirm_popup.confirmed.connect(_on_delete_confirmed)


func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _build_button_style(BUTTON_TEXTURE))
	button.add_theme_stylebox_override("hover", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", _build_button_style(BUTTON_HOVER_TEXTURE))
	button.add_theme_stylebox_override("disabled", _build_button_style(BUTTON_TEXTURE, DISABLED_TINT))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_disabled_color", BUTTON_TEXT_COLOR.lerp(Color.BLACK, 0.3))


func _build_button_style(texture: Texture2D, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = tint
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	return style


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open(mode: String) -> void:
	_mode = mode
	_title_label.text = "이어하기" if mode == MODE_CONTINUE else "새로 시작하기"
	_refresh()
	_set_open(true)


func close() -> void:
	_set_open(false)
	closed.emit()


## 익스포트 빌드에서 이 화면(과 새 게임의 character_creation_screen.gd)이
## 좌측 상단에 눌려서 뜨는 문제가 있었다(사용자 리포트, 2026-08-26 - "이어하기
## 했을 때 좌측 상단에 떠서 ui 창이 다 안보이고 뭔가 할 수 없게 돼") - 이 화면의
## 루트는 원래도 전체화면(anchor 0/0/1/1)이라, 열릴 때마다
## set_anchors_and_offsets_preset(PRESET_FULL_RECT)로 강제 재적용하는 걸로
## 실제로 고쳐졌다(자기 자신에게 값을 재대입하는 _refresh_layout() 방식은
## 이 화면에서 재발했다 - 값이 이미 같으면 엔진이 다시 계산을 안 하는 것으로
## 보임). status_screen.gd 등 화면 크기가 작게 고정된 곳에는 이 preset을 쓰면
## 안 된다(전체화면으로 덮어버림) - 이 화면처럼 루트가 원래 전체화면인
## 경우에만 안전하다.
func _set_open(is_open: bool) -> void:
	if is_open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


## _confirm_popup(SlotDeleteConfirmPopup)은 자기 열고 닫힘을 따로 관리한다
## (자기 자신의 _set_open() - "삭제" 버튼을 눌러야만 연다). 그런데 이 팝업이
## 이 화면의 자식으로 같이 들어있어서, 여기서 재귀로 내려가면 매번 그 안의
## 전체화면 Dim까지 STOP으로 덮어써버린다 - Dim은 modulate.a로만 숨겨질 뿐
## mouse_filter는 STOP이 되어, 안 보이는 채로 슬롯 버튼들 위에서 클릭을 전부
## 가로챈다(사용자 리포트, 2026-08-29 - "시작하기/이어하기 둘 다 슬롯 선택
## 화면 안의 버튼이 하나도 안 눌림"). status_screen.gd가 quit_confirm_popup을
## 제외하는 것과 동일한 이유 - 이 팝업 하위는 건드리지 않고 자기 자신에게
## 맡긴다.
func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node == _confirm_popup:
		return
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)


func _refresh() -> void:
	for i in _slot_buttons.size():
		var slot := i + 1
		var button: Button = _slot_buttons[i]
		var delete_button: Button = _delete_buttons[i]
		var has_save := SaveManager.has_save(slot)
		if has_save:
			var summary := SaveManager.get_save_summary(slot)
			var info := tr("%s - %d일차") % [String(summary.get("player_name", "")), int(summary.get("day", 1))]
			button.text = tr("%d번 슬롯\n%s") % [slot, info]
		else:
			button.text = tr("%d번 슬롯\n(비어있음)") % slot
		# 이어하기 모드: 빈 슬롯은 못 고름. 새 게임 모드: 이미 데이터가 있는
		# 슬롯은 못 고름(위 클래스 주석 참고 - 덮어쓰기 대신 명시적 삭제).
		button.disabled = (not has_save) if _mode == MODE_CONTINUE else has_save
		delete_button.visible = _mode == MODE_CONTINUE and has_save


func _on_slot_pressed(slot: int) -> void:
	slot_confirmed.emit(slot, _mode)


func _on_delete_pressed(slot: int) -> void:
	_pending_delete_slot = slot
	_confirm_popup.open_with_message(tr("%d번 슬롯을 삭제하시겠습니까?\n되돌릴 수 없습니다.") % slot)


func _on_delete_confirmed() -> void:
	if _pending_delete_slot > 0:
		SaveManager.delete_save(_pending_delete_slot)
		_refresh()
	_pending_delete_slot = -1
