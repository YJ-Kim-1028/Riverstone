extends Control

## 서점(usher_shop)에서 산 책(category "book") 아이템을 우클릭하면(equipment_panel.gd
## -> status_screen.gd 중계) 열리는 책 읽기 화면. collection_screen.gd와 같은
## 배경(frame_book.png)/열고 닫는 방식("항상 visible=true, modulate.a로 열고
## 닫기")/닫기 방식(버튼 없이 ESC 전용)을 그대로 따른다. 내용은 BookManager
## (data/books/books.json)에서 그대로 읽어와 보여주기만 한다 - 책 원문은
## 데이터 파일에만 있고 이 스크립트에는 없다.
## 책은 레시피와 달리 소비되지 않으므로(inventory_manager.gd) 몇 번이든 다시
## 열어서 읽을 수 있다.
## frame_book.png 자체가 책을 펼친 그림(왼쪽 페이지/오른쪽 페이지가 따로
## 그려져 있음, collection_screen.gd가 레시피/추억의 물건을 좌우로 나눠 쓰는
## 것과 동일한 그림)이라, 제목/저자 없이 pages 배열을 2개씩 묶어(왼쪽=짝수
## 인덱스, 오른쪽=홀수 인덱스) 한 번에 두 페이지를 보여준다(사용자 지시).

@onready var _left_page_label: Label = $ScaledContent/LeftPageLabel
@onready var _right_page_label: Label = $ScaledContent/RightPageLabel
@onready var _prev_button: TextureButton = $PrevButton
@onready var _next_button: TextureButton = $NextButton

var _is_open := false
var _pages: Array = []
## 몇 번째 "펼침"(왼쪽+오른쪽 페이지 한 쌍)을 보고 있는지 - 실제 페이지
## 인덱스는 _spread_index*2(왼쪽)/_spread_index*2+1(오른쪽).
var _spread_index := 0


func _ready() -> void:
	_prev_button.pressed.connect(func() -> void: _change_spread(-1))
	_next_button.pressed.connect(func() -> void: _change_spread(1))
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open_book(item_id: String) -> void:
	var book := BookManager.get_book(item_id)
	if book.is_empty():
		return
	_pages = (book.get("pages", []) as Array).duplicate()
	if _pages.is_empty():
		_pages = [""]
	_spread_index = 0
	_refresh_spread()
	_set_open(true)
	AudioManager.play_sfx(AudioManager.SFX_COLLECTION_OPEN, AudioManager.SFX_COLLECTION_VOLUME_DB)


func close() -> void:
	_set_open(false)


func _last_spread_index() -> int:
	return (_pages.size() - 1) / 2


func _change_spread(direction: int) -> void:
	var new_index := clampi(_spread_index + direction, 0, _last_spread_index())
	if new_index == _spread_index:
		return
	_spread_index = new_index
	_refresh_spread()
	AudioManager.play_sfx(AudioManager.SFX_COLLECTION_MOVE, AudioManager.SFX_COLLECTION_VOLUME_DB)


func _refresh_spread() -> void:
	var left_index := _spread_index * 2
	var right_index := left_index + 1
	_left_page_label.text = String(_pages[left_index]) if left_index < _pages.size() else ""
	_right_page_label.text = String(_pages[right_index]) if right_index < _pages.size() else ""
	_prev_button.visible = _spread_index > 0
	_next_button.visible = _spread_index < _last_spread_index()


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
	_is_open = is_open
	modulate.a = 1.0 if is_open else 0.0
	# collection_screen.gd와 동일한 이유 - 배경/라벨처럼 목록에서 빠뜨린 컨트롤이
	# 기본값(STOP)으로 남아 닫아도 클릭을 계속 먹는 문제를 막기 위해 서브트리
	# 전체를 재귀로 처리한다.
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
