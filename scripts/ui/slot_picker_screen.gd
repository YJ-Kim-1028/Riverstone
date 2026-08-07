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
## 노드/씬 이름은 원래 목적(새 게임 덮어쓰기 확인)을 따서 지어진 이름 그대로
## 뒀지만, 이제 이 화면에서 쓰는 유일한 용도는 슬롯 삭제 확인이다(덮어쓰기
## 경로 자체가 없어졌음) - save_overwrite_confirm_popup.gd 자체는 메시지를
## 그때그때 받는 범용 확인창이라 내용 변경 없이 그대로 재사용.
@onready var _confirm_popup: Control = $SaveOverwriteConfirmPopup

var _mode := MODE_NEW_GAME
var _pending_delete_slot := -1


func _ready() -> void:
	visible = false
	_back_button.pressed.connect(close)
	for i in _slot_buttons.size():
		var slot := i + 1
		_slot_buttons[i].pressed.connect(_on_slot_pressed.bind(slot))
		_delete_buttons[i].pressed.connect(_on_delete_pressed.bind(slot))
	_confirm_popup.confirmed.connect(_on_delete_confirmed)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open(mode: String) -> void:
	_mode = mode
	_title_label.text = "이어하기" if mode == MODE_CONTINUE else "새로 시작하기"
	_refresh()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _refresh() -> void:
	for i in _slot_buttons.size():
		var slot := i + 1
		var button: Button = _slot_buttons[i]
		var delete_button: Button = _delete_buttons[i]
		var has_save := SaveManager.has_save(slot)
		if has_save:
			var summary := SaveManager.get_save_summary(slot)
			var info := "%s - %d일차" % [String(summary.get("player_name", "")), int(summary.get("day", 1))]
			if _mode == MODE_NEW_GAME:
				button.text = "%d번 슬롯\n%s\n(이어하기에서 삭제 후 이용 가능)" % [slot, info]
			else:
				button.text = "%d번 슬롯\n%s" % [slot, info]
		else:
			button.text = "%d번 슬롯\n(비어있음)" % slot
		# 이어하기 모드: 빈 슬롯은 못 고름. 새 게임 모드: 이미 데이터가 있는
		# 슬롯은 못 고름(위 클래스 주석 참고 - 덮어쓰기 대신 명시적 삭제).
		button.disabled = (not has_save) if _mode == MODE_CONTINUE else has_save
		delete_button.visible = _mode == MODE_CONTINUE and has_save


func _on_slot_pressed(slot: int) -> void:
	slot_confirmed.emit(slot, _mode)


func _on_delete_pressed(slot: int) -> void:
	_pending_delete_slot = slot
	_confirm_popup.open_with_message("%d번 슬롯을 삭제하시겠습니까?\n되돌릴 수 없습니다." % slot)


func _on_delete_confirmed() -> void:
	if _pending_delete_slot > 0:
		SaveManager.delete_save(_pending_delete_slot)
		_refresh()
	_pending_delete_slot = -1
