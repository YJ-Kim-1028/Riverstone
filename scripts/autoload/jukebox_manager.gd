extends Node

## 레스토랑 주크박스(jukebox Interactable) 상태 - data/jukebox/songs.json의 곡
## 목록을 읽고, 지금 선택된 곡을 추적한다. 해금 여부는 ShopManager의 구매
## 기록(purchase_counts)으로 판정한다 - 음반을 인벤토리에 들고 있어야만
## 해금되는 게 아니라 "한 번이라도 산 적 있으면" 영구 해금(사용자 지시,
## 2026-08-10: "음원은 아이템으로 갖고있어도 할 게 없잖아 그냥 구매하면
## 템창은 안달라지고 주크박스에서 틀 수 있는것만 많아져야지"). 음반 구매
## 자체가 인벤토리에 아무것도 남기지 않도록 ShopManager.buy()도 is_record_item()
## 으로 감지해 특수 처리한다. 선택된 곡 id만 SaveManager를 통해 저장한다
## (get_save_data 참고).

signal song_selected(song_id: String)

const SONGS_PATH := "res://data/jukebox/songs.json"
const DEFAULT_SONG_ID := "song_nice_to_serve_you"
## inventory_manager.gd의 get_item_icon_texture()와 동일한 16x16 그리드 슬라이싱
## 규칙 - 사용자가 assets/icon/Records.png에 곡마다 16x16 한 칸씩 순서대로
## 그려뒀다(icon_index = 0번째 곡부터).
const ICON_GRID_SIZE := 16

var _songs: Dictionary = {}
var _current_song_id := DEFAULT_SONG_ID


func _ready() -> void:
	_load_songs()


func get_song_ids() -> Array:
	return _songs.keys()


func get_song(song_id: String) -> Dictionary:
	return _songs.get(song_id, {})


## Records.png(또는 그에 준하는 시트)에서 icon_index번째 16x16 칸을 잘라 돌려준다.
## icon/icon_index가 없으면(아직 아이콘을 안 넣었으면) null - jukebox_screen.gd가
## 조용히 빈 아이콘으로 표시한다.
func get_song_icon_texture(song_id: String) -> Texture2D:
	var song := get_song(song_id)
	var icon_path := String(song.get("icon", ""))
	if icon_path.is_empty() or not song.has("icon_index") or not ResourceLoader.exists(icon_path):
		return null
	var sheet := load(icon_path) as Texture2D
	if sheet == null:
		return null
	var column := int(song["icon_index"])
	var row := int(song.get("icon_row", 0))
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(column * ICON_GRID_SIZE, row * ICON_GRID_SIZE, ICON_GRID_SIZE, ICON_GRID_SIZE)
	return atlas


func is_unlocked(song_id: String) -> bool:
	var song := get_song(song_id)
	if song.is_empty():
		return false
	if bool(song.get("unlocked_by_default", false)):
		return true
	var item_id := String(song.get("item_id", ""))
	return not item_id.is_empty() and ShopManager.get_purchase_count(item_id) > 0


func get_unlocked_song_ids() -> Array:
	return get_song_ids().filter(is_unlocked)


## ShopManager.buy()가 이 item_id를 인벤토리에 넣지 않고 구매 기록만 남기는
## 특수 항목으로 처리해야 하는지 판단하는 데 쓴다 - songs.json의 item_id
## 필드들과 대조(단일 진실 공급원이 songs.json이라, 새 곡이 추가돼도 여기를
## 따로 고칠 필요가 없다).
func is_record_item(item_id: String) -> bool:
	for song in _songs.values():
		if String((song as Dictionary).get("item_id", "")) == item_id:
			return true
	return false


func get_current_song_id() -> String:
	return _current_song_id


## 주크박스 UI의 화살표로 곡을 바꿀 때 호출한다 - 해금되지 않은 곡은 무시한다.
func select_song(song_id: String) -> bool:
	if not is_unlocked(song_id):
		return false
	_current_song_id = song_id
	song_selected.emit(song_id)
	return true


## audio_manager.gd가 레스토랑 맵의 브금 경로를 물을 때 쓴다 - 선택된 곡이
## 해금 해제 상태(예: 팔았던 레코드를 억지로 지운 세이브 편집 등 예외적인
## 경우)가 되면 기본곡으로 자동 대체한다.
func get_current_bgm_path() -> String:
	if not is_unlocked(_current_song_id):
		_current_song_id = DEFAULT_SONG_ID
	return String(get_song(_current_song_id).get("bgm_path", ""))


func get_save_data() -> Dictionary:
	return {"selected_song_id": _current_song_id}


func load_save_data(data: Dictionary) -> void:
	_current_song_id = String(data.get("selected_song_id", DEFAULT_SONG_ID))


func _load_songs() -> void:
	var file := FileAccess.open(SONGS_PATH, FileAccess.READ)
	if file == null:
		push_error("Jukebox song catalog could not be opened: %s" % SONGS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Jukebox song catalog is not valid JSON: %s" % SONGS_PATH)
		return
	_songs = parsed
