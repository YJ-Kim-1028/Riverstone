extends Node

## Coordinates high-level game state that doesn't belong to any single
## system: the player's display name, accumulated play time, and which map
## is currently loaded. SaveManager needs current_map_id to know where to
## resume the player; main.gd is expected to call set_current_map() on
## every map load/warp.

signal map_changed(map_id: String)
## 캐릭터 생성 화면이 아니라 인게임 옷장(wardrobe_screen.gd)에서 외형을 다시
## 바꿀 때 쏜다 - player.gd(월드 스프라이트)와 player_preview.gd(TAB 장비
## 탭 미리보기)가 각자 캐싱해둔 합성 텍스처를 다시 만들어야 한다는 신호.
signal appearance_changed

const DEFAULT_PLAYER_NAME := "Player"
## title_screen.md 캐릭터 생성 화면이 생기기 전까지 mail_compose_panel.gd가
## 초대장 문구에 임시로 박아 쓰던 값과 동일 - 이제 실제 화면이 생겼으니 그
## 자리표시자 대신 이 필드를 참조하게 바꿨다.
const DEFAULT_RESTAURANT_NAME := "우리 레스토랑"

var player_name := DEFAULT_PLAYER_NAME
var restaurant_name := DEFAULT_RESTAURANT_NAME
var play_time_seconds := 0.0
var current_map_id := ""
## 캐릭터 생성 화면에서 고른 외형. 전부 한 장짜리 시트(player_hair.png/
## player_outfit.png/player_shoes.png/player_accessory.png)에서 고른 "줄 번호"를
## 문자열로 담는다(hair_id는 "0"=대머리, accessory_id는 "0"=없음, outfit_id/
## shoe_id는 "없음" 개념이 없어서 "0"도 그냥 첫 번째 정식 스타일).
var hair_id := ""
var outfit_id := ""
var shoe_id := ""
var accessory_id := ""
## 피부색/눈동자색 - hair_color_1/2/3와 같은 형식(HTML 헥스 문자열). 색상환
## (SVSquare+HueStrip)에서 자유롭게 고른 색을 그대로 담는다 - 고정 목록
## 인덱스가 아니다(사용자 확정: 프리셋 방식에서 자유 색상 선택으로 변경).
var skin_color := "f8e7da"
var eye_color := "38b57a"
## 볼터치 - 위와 같은 형식. 실제 기획 기본값을 아직 못 받아서 임시값.
var cheek_color := "f4a6b3"
## 머리 시트에 표식으로 그려둔 색1/색2/색3(#D8D8D8/#9A9A9A/#565656 원본
## 표식과 같은 순서)을 사용자가 어떤 색으로 바꿨는지 - HTML 헥스 문자열
## (예: "9a9a9a"). 표식 색 그대로면 리컬러가 안 일어난 것과 동일.
var hair_color_1 := "d8d8d8"
var hair_color_2 := "9a9a9a"
var hair_color_3 := "565656"
## 옷 시트에 표식으로 그려둔 색1/색2/색3(#D6D6D6/#A8A8A8/#727272, 2026-08-09
## player_outfit.png 재작업으로 2색→3색)을 사용자가 어떤 색으로 바꿨는지 -
## "상의"/"하의"/"포인트"라는 UI 이름표가 붙어있지만 실제로는 그림 속 부위가
## 아니라 이 마커 3개에 대응한다(사용자 확정).
var outfit_color_1 := "d6d6d6"
var outfit_color_2 := "a8a8a8"
var outfit_color_3 := "727272"
## 신발 시트(player_shoes.png)에 그려둔 마커(#9A9A9A) 색.
var shoe_color := "9a9a9a"
## 장신구 시트(player_accessory.png)에 그려둔 마커(#9A9A9A) 색.
var accessory_color := "9a9a9a"
## TimeManager.is_running과 같은 이유의 같은 문제 - 오토로드라 부팅 즉시
## _process가 돌아서, 타이틀/캐릭터생성 화면에 머무는 동안에도 플레이타임이
## 쌓이면 안 된다. main.gd._ready()가 실제 게임플레이 시작 시점에
## start_play_timer()를 호출해야 카운트가 시작된다.
var _play_timer_running := false


## Godot의 전역 random 함수(randi()/randf()/randi_range() 등)는 randomize()를
## 한 번 호출해주기 전까지 항상 같은 고정 시드로 시작한다 - 그래서 이걸 아무도
## 호출한 적 없던 지금까지는, 낚시 어종 추첨/요일별 대사 선정/날씨 굴림/이메일
## 발송 확률/만능 레시피 무작위 선택 등 이 프로젝트의 모든 랜덤 로직이 실행할
## 때마다(엔진을 새로 켤 때마다) 항상 똑같은 결과만 내고 있었다(사용자 리포트 -
## recipe_random이 매번 "피쉬앤칩스"만 나옴). GameManager가 project.godot
## 오토로드 목록 맨 앞이라 가장 먼저 실행되므로, 다른 어떤 랜덤 로직보다도
## 먼저 여기서 한 번 시드를 흩뿌린다.
func _ready() -> void:
	randomize()


func _process(delta: float) -> void:
	if _play_timer_running:
		play_time_seconds += delta


func start_play_timer() -> void:
	_play_timer_running = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_debug_give_test_ingredients()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		_debug_kill_random_npc()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		_debug_queue_murder_candidates()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_debug_grant_soul_crystal()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_debug_reset_restaurant_frame_blood()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		HorrorEventManager.debug_trigger_knock_event()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		MurderManager.debug_force_commit_murder()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		MurderManager.debug_force_truth_ending()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		MurderManager.debug_force_accomplice_ending()
	## 원래 F8이었으나 Godot 에디터 기본 단축키(정지)와 겹쳐 게임까지 입력이
	## 안 왔다(사용자 리포트, 2026-08-26 - "F8 체포엔딩이랫는데 이거 종료라서
	## 종료만 되는데?"). Ctrl+F8로 한 번 옮겼는데도 여전히 잘 안 된다는
	## 후속 리포트로, F1(예전 호감도 디버그 키 - 다 체크했다고 삭제된 자리)로
	## 옮긴다.
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		MurderManager.debug_force_arrest_ending()
	## 우디 호감도 50 옷장 이벤트 테스트용(사용자 지시, 2026-08-30) - F키가
	## 전부 차서 숫자키로 뺌. debug_set_affection()은 F8 자리에 있던 그
	## 기존 함수를 그대로 재사용.
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1:
		NPCManager.debug_set_affection("woody", NPCManager.get_affection("woody") + 10)
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_2:
		EconomyManager.add_income(10000)


func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN


## Debug-only (F9, editor/debug builds only): fills the inventory with a
## batch of raw cooking materials plus rat poison, so the cooking screen can
## be tested without grinding out fishing/farming/foraging first. Covers at
## least one raw ingredient per cooking_stations.json tool (냄비/프라이팬/
## 도마/믹서기) so every station's drag-and-drop flow can be tried.
func _debug_give_test_ingredients() -> void:
	for item_id in ["corn", "potato", "pork", "beef", "salmon", "mackerel", "squid", "lettuce", "berry", "milk"]:
		InventoryManager.add_item(item_id, 5)
	InventoryManager.add_item("rat_poison", 1)


## Debug-only (F7, editor/debug builds only): 제단 부활 테스트용(사용자 지시,
## 2026-08-25) - 실제 살인이 자연 발생하길 기다리지 않고, 스토리 NPC/스토커를
## 제외한 살아있는 NPC 중 무작위로 한 명을 즉시 죽인다. RevivalManager.
## get_revivable_victim_ids()가 바로 후보로 잡아준다. F4처럼 살해 사건 기록
## (MurderManager._cases 등)은 안 남기고 순수하게 is_alive만 뒤집는다 - 부활
## 대상 목록 테스트가 목적이라 그걸로 충분하다.
func _debug_kill_random_npc() -> void:
	var candidates: Array = []
	for npc_id in NPCManager.get_all_ids():
		if NPCManager.is_alive(npc_id) and not NPCManager.is_story_npc(npc_id) and not NPCManager.is_stalker(npc_id):
			candidates.append(npc_id)
	if candidates.is_empty():
		return
	NPCManager.kill_npc(String(candidates.pick_random()))


## Debug-only (F4, editor/debug builds only): murder_system.md 테스트용 -
## 스토리 NPC/스토커를 제외한 살아있는 NPC 전원의 호감도를 120(MURDER_CANDIDATE_AFFECTION)
## 으로 끌어올려 살해 대상 대기열에 한 번에 등록한다. 그 이후 조건(비/오후10시/
## 플레이어·스토커·피해자 맵 분리)은 정상 플레이와 동일하게 자연 발생을
## 기다려야 한다 - 비는 대기 중인 대상이 있으면 3일 이내 강제로 오게 되어
## 있어서(WeatherManager.set_murder_pending) 오래 걸리진 않는다.
## Debug-only (F6, editor/debug builds only): 도감 13개를 다 모으고 엔딩까지
## 보지 않아도 지급 컷신부터 바로 테스트할 수 있게 실제 지급 신호를 강제로
## 흘려보낸다(사용자 지시, 2026-08-25) - 조건 판정만 건너뛸 뿐 이후 흐름은
## 실전과 동일해서, 다음 취침/기절 시 plaza5 비행 컷신이 그대로 재생되고
## 그 컷신이 끝나야 실제로 인벤토리에 들어온다.
func _debug_grant_soul_crystal() -> void:
	RevivalManager.debug_force_grant_soul_crystal()


func _debug_queue_murder_candidates() -> void:
	for npc_id in NPCManager.get_all_ids():
		if not NPCManager.is_alive(npc_id) or NPCManager.is_story_npc(npc_id) or NPCManager.is_stalker(npc_id):
			continue
		NPCManager.debug_set_affection(npc_id, NPCManager.MURDER_CANDIDATE_AFFECTION)


## Debug-only (F12, editor/debug builds only): 레스토랑 액자 이벤트가 이미
## 소비된 상태여도 다시 볼 수 있게 리셋한다 - 누른 뒤 레스토랑을 나갔다 다시
## 들어오면 뜬다.
func _debug_reset_restaurant_frame_blood() -> void:
	HorrorEventManager.debug_reset_restaurant_frame_blood_trigger()


func set_current_map(map_id: String) -> void:
	if map_id == current_map_id:
		return
	current_map_id = map_id
	map_changed.emit(map_id)


func get_save_data() -> Dictionary:
	return {
		"player_name": player_name,
		"restaurant_name": restaurant_name,
		"play_time_seconds": play_time_seconds,
		"current_map_id": current_map_id,
		"hair_id": hair_id,
		"hair_color_1": hair_color_1,
		"hair_color_2": hair_color_2,
		"hair_color_3": hair_color_3,
		"skin_color": skin_color,
		"eye_color": eye_color,
		"cheek_color": cheek_color,
		"outfit_color_1": outfit_color_1,
		"outfit_color_2": outfit_color_2,
		"outfit_color_3": outfit_color_3,
		"shoe_color": shoe_color,
		"accessory_color": accessory_color,
		"outfit_id": outfit_id,
		"shoe_id": shoe_id,
		"accessory_id": accessory_id,
	}


func load_save_data(data: Dictionary) -> void:
	player_name = String(data.get("player_name", DEFAULT_PLAYER_NAME))
	restaurant_name = String(data.get("restaurant_name", DEFAULT_RESTAURANT_NAME))
	play_time_seconds = float(data.get("play_time_seconds", 0.0))
	current_map_id = String(data.get("current_map_id", ""))
	hair_id = String(data.get("hair_id", ""))
	hair_color_1 = String(data.get("hair_color_1", "d8d8d8"))
	hair_color_2 = String(data.get("hair_color_2", "9a9a9a"))
	hair_color_3 = String(data.get("hair_color_3", "565656"))
	skin_color = String(data.get("skin_color", "f8e7da"))
	eye_color = String(data.get("eye_color", "38b57a"))
	cheek_color = String(data.get("cheek_color", "f4a6b3"))
	outfit_color_1 = String(data.get("outfit_color_1", "d6d6d6"))
	outfit_color_2 = String(data.get("outfit_color_2", "a8a8a8"))
	outfit_color_3 = String(data.get("outfit_color_3", "727272"))
	shoe_color = String(data.get("shoe_color", "9a9a9a"))
	accessory_color = String(data.get("accessory_color", "9a9a9a"))
	outfit_id = String(data.get("outfit_id", ""))
	shoe_id = String(data.get("shoe_id", ""))
	accessory_id = String(data.get("accessory_id", ""))
