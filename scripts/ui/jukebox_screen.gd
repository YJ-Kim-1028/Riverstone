extends Control

## 레스토랑의 jukebox Interactable(restaurant_interior_new.tmx)로 여는 곡 선택
## UI. computer_screen.gd/book_screen.gd와 같은 열고 닫기 방식(ESC 전용,
## modulate.a로 열고 닫기) - 화면 하단에 고정 배치한다(사용자 지시,
## dialogue_screen.tscn과 같은 anchor 방식).
##
## character_creation_screen.gd의 머리/옷 고르는 화살표(왼쪽/오른쪽으로 넘기며
## 선택)와 같은 UX(사용자 지시: "나도 그렇게 할거야") - 다만 저건 "완료" 버튼을
## 눌러야 확정되는 반면, 여기는 화살표를 누르는 즉시 그 곡이 선택되어 바로
## 재생된다(주크박스는 별도 확정 단계가 필요 없는 즉시성 UX가 더 자연스럽다는
## 판단). JukeboxManager.get_unlocked_song_ids()가 돌려주는 목록만 순환 대상 -
## 아직 해금 안 된 곡(음반을 안 산 곡)은 화살표로도 안 보인다.

@onready var _prev_button: TextureButton = $Background/Margin/HBox/PrevButton
@onready var _next_button: TextureButton = $Background/Margin/HBox/NextButton
@onready var _icon: TextureRect = $Background/Margin/HBox/Icon
@onready var _name_label: Label = $Background/Margin/HBox/NameLabel

var _is_open := false
var _song_ids: Array = []
var _index := 0


func _ready() -> void:
	_prev_button.pressed.connect(func() -> void: _cycle(-1))
	_next_button.pressed.connect(func() -> void: _cycle(1))
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()


func open() -> void:
	_song_ids = JukeboxManager.get_unlocked_song_ids()
	if _song_ids.is_empty():
		return
	var current_id := JukeboxManager.get_current_song_id()
	_index = maxi(_song_ids.find(current_id), 0)
	_refresh_display()
	_set_open(true)


func close() -> void:
	_set_open(false)


func _cycle(direction: int) -> void:
	if _song_ids.size() <= 1:
		return
	_index = wrapi(_index + direction, 0, _song_ids.size())
	JukeboxManager.select_song(String(_song_ids[_index]))
	_refresh_display()
	AudioManager.play_sfx(AudioManager.SFX_COLLECTION_MOVE, AudioManager.SFX_COLLECTION_VOLUME_DB)


func _refresh_display() -> void:
	var song := JukeboxManager.get_song(String(_song_ids[_index]))
	_name_label.text = String(song.get("name", ""))
	_icon.texture = JukeboxManager.get_song_icon_texture(String(_song_ids[_index]))


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
	_apply_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


func _apply_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_apply_mouse_filter_recursive(child, filter)
