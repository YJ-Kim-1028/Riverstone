extends Node

## Owns runtime audio playback and mixing. BGM auto-switches between the
## day track, the night track (from NIGHT_BGM_START_HOUR, matching
## LightingLayer.DUSK_START_HOUR), and the restaurant track - the restaurant
## track is tied to being on RESTAURANT_MAP_ID (GameManager.current_map_id),
## not to RestaurantManager.is_open, so the day/night switch never fires
## while the player is inside the restaurant (사용자 확정: 레스토랑 맵에서는
## 영업 여부와 무관하게 밤 브금으로 안 바뀜). Rain SFX loops on top of
## whatever BGM is playing whenever WeatherManager.is_raining() and the
## player is outdoors (실내에서는 weather_overlay.gd처럼 날씨 연출을 꺼서
## 시각 효과와 맞춘다). 실내에서 비가 올 때는 대신 SFX_INTERIOR_RAIN이
## 브금 위에 얹힌다(_update_interior_rain_sfx). 파도 소리(SFX_WAVE)는 바다가 있는 맵(WAVE_MAP_IDS -
## plaza3~5)에 있을 때만 날씨/실내 여부와 무관하게 켜진다 - 브금/비와 동시에
## 겹쳐도 안 시끄럽게 훨씬 조용한 배경음 취급(WAVE_SFX_TARGET_VOLUME_DB).
## 강 소리(SFX_POND)는 plaza1/2에서 플레이어가 실제 Pond 타일(Water는 바다라
## 파도 소리 담당이라 일부러 제외 - WorldMap.get_distance_to_nearest_pond)에
## 가까워질수록 볼륨이 점점 커지는 방식 - on/off가 아니라 매 프레임 거리
## 기반으로 갱신된다(_update_pond_sfx).
const BGM_MAIN := "res://assets/audio/bgm/bgm_main.mp3"
const BGM_NIGHT := "res://assets/audio/bgm/bgm_night.mp3"
const BGM_RESTAURANT := "res://assets/audio/bgm/bgm_restaurant.mp3"
const BGM_FADE_SECONDS := 1.0
## 이전엔 "실제 플레이 중 설정 슬라이더를 늘 40%까지 내려 듣는다"는 피드백을
## 반영해 기본값 자체를 -14.1dB(원본 대비 약 20%)까지 낮춰뒀었는데, 그 뒤
## 다시 너무 작다는 피드백으로 "원본 대비 50% 감소"로 재확정(사용자 지시)
## = 20*log10(0.5) ≈ -6.0dB. 이후 다시 "지금보다(그 -6.0dB 기준으로) 40%
## 더 줄여줘"(사용자 지시) = -6.0 + 20*log10(0.6) ≈ -10.44dB(원본 대비로는
## 약 30%). 슬라이더 상한(150%, set_bgm_volume 참고)은 그대로 유지 - 더
## 키우고 싶으면 슬라이더로 조절 가능.
const BGM_TARGET_VOLUME_DB := -10.44
const NIGHT_BGM_START_HOUR := 17
## main.gd의 RESTAURANT_SIGN_MAP_ID와 같은 값이어야 한다.
const RESTAURANT_MAP_ID := "restaurant_interior"

## sfx_rain2로 확정(사용자 확정 - 기존 sfx_rain.mp3보다 낫다고 판단해 교체,
## 원본 mp3는 삭제함). wav→mp3 일괄 재변환(사용자 작업)으로 확장자가 다시
## mp3로 바뀜.
const SFX_RAIN := "res://assets/audio/sfx/sfx_rain2.mp3"
const RAIN_SFX_FADE_SECONDS := 1.0
## 볼륨 감소 0%(사용자 확정, 40%로 줄였더니 거의 안 들려서 되돌림) - 감쇠 없이
## 0dB(원본 그대로)로 재생한다.
const RAIN_SFX_TARGET_VOLUME_DB := 0.0
## sfx_rain.mp3 파일 끝부분에 페이드아웃이 들어있어서(사용자 확정: 루프마다
## 소리가 죽었다 살아나는 게 어색함), 파일의 loop를 그대로 쓰지 않고 끝나기
## RAIN_LOOP_TRIM_SECONDS 전에 직접 처음으로 되감아 그 페이드아웃 구간을
## 재생하지 않고 건너뛴다.
const RAIN_LOOP_TRIM_SECONDS := 4.5

## 바다가 있는 맵(plaza3~5, game_design/04_locations 확인)에서만 파도 소리를
## 켠다 - 날씨/실내와는 무관하게 순수 맵 기준.
const SFX_WAVE := "res://assets/audio/sfx/sfx_plaza345_wave.mp3"
const WAVE_MAP_IDS: Array[String] = ["plaza3", "plaza4", "plaza5"]
const WAVE_SFX_FADE_SECONDS := 1.5
## 브금+비+파도가 한꺼번에 겹쳐도 안 시끄럽게, 브금/비보다 훨씬 조용한
## 배경음 취급으로 낮게 잡음(사용자 확정 취지) = 20*log10(0.35) ≈ -9.1dB.
## 임의 결정 - 실제로 들어보고 더 조정 필요할 수 있음.
const WAVE_SFX_TARGET_VOLUME_DB := -9.1

## plaza1/2의 강에 가까이 갈수록 sfx_pond가 커진다(사용자 지시) - y좌표를
## 맵마다 손으로 맞추는 대신, WorldMap.get_distance_to_nearest_pond()로 실제
## Pond 타일까지의 거리를 구해서 계산한다(plaza2처럼 강이 대각선이어도 정확함,
## 사용자 지시로 y좌표 방식에서 변경). Water(바다) 타일은 일부러 안 본다 -
## plaza4처럼 Water가 있는 맵까지 강 소리가 겹쳐 들리면 파도 소리랑 같이
## 어지럽다는 사용자 지시(get_distance_to_nearest_pond 자체가 Pond 레이어만 봄).
const POND_MAP_IDS: Array[String] = ["plaza1", "plaza2"]
## 가장 가까운 Pond 타일에서 이 거리(px) 밖이면 안 들림, 타일에 붙으면(거리 0)
## 최대 볼륨. 원래 120px(사용자가 준 "-120부터 들리면 될 듯" 기준)이었는데
## 너무 가까이 가야만 들린다는 피드백으로 300px까지 늘렸다가, 이번엔 너무
## 멀리서도 들린다는 피드백으로 200px로 재조정(사용자 확정).
const POND_FADE_DISTANCE := 200.0
const SFX_POND := "res://assets/audio/sfx/sfx_pond.mp3"
## 감쇠 없이 원본 그대로.
const POND_SFX_TARGET_VOLUME_DB := 0.0
const POND_SFX_SILENT_DB := -40.0

## 실내에서 비가 올 때 브금 위에 얹히는 빗소리(사용자 요청) - 바깥의
## SFX_RAIN과 달리 실내(_is_indoor)일 때만 켜지고, 실외에서는 기존
## SFX_RAIN이 그대로 담당한다. rain2.wav처럼 끝에 페이드아웃이 있다는
## 리포트가 없어서 wave와 같은 엔진 기본 loop를 쓴다.
const SFX_INTERIOR_RAIN := "res://assets/audio/sfx/sfx_interior_rain.mp3"
const INTERIOR_RAIN_SFX_FADE_SECONDS := 1.0
## 처음엔 실외 SFX_RAIN과 동일하게 0dB(감쇠 없음)로 뒀는데 실내에서 너무
## 크게 들린다는 피드백으로 -9.1dB(파도/강 소리와 동일 감쇠)로 낮춤. 계속
## 크거나 작으면 이 값만 조정하면 됨.
const INTERIOR_RAIN_SFX_TARGET_VOLUME_DB := -9.1

## 사용자가 assets/audio/sfx/에 넣어준 UI/이벤트 단발성 효과음들 - 전부
## play_sfx()로 재생한다(페이드/루프/거리감쇠 같은 상태 관리가 필요 없는
## 소리들). 파일이 없으면(아직 안 넣었으면) play_sfx()가 조용히 넘어간다.
const SFX_BELL := "res://assets/audio/sfx/sfx_bell.mp3"
const SFX_BUBBLE := "res://assets/audio/sfx/sfx_bubble.mp3"
const SFX_CLICK := "res://assets/audio/sfx/sfx_click.mp3"
const SFX_COLLECTION_MOVE := "res://assets/audio/sfx/sfx_collection_move.mp3"
const SFX_COLLECTION_OPEN := "res://assets/audio/sfx/sfx_collection_open.mp3"
## 도감 효과음 2개(open/move)가 너무 작다는 피드백으로 20%(선형) 키움(사용자
## 지시) = 20*log10(1.2) ≈ +1.6dB.
const SFX_COLLECTION_VOLUME_DB := 1.6
const SFX_DRINKING := "res://assets/audio/sfx/sfx_drinking.mp3"
const SFX_FISHING_APPEAR := "res://assets/audio/sfx/sfx_fishing.mp3"
const SFX_UI_SLOT_IN := "res://assets/audio/sfx/sfx_ui_slot_in.mp3"
const SFX_UI_TAB := "res://assets/audio/sfx/sfx_ui_tab.mp3"
## 실내/실외 경계를 넘을 때(main.gd._load_map()가 이전 맵과 새 맵의
## "_interior" 여부가 다를 때만 재생).
const SFX_DOOR := "res://assets/audio/sfx/sfx_door.mp3"
## 조리 중(냄비/프라이팬/믹서기) 소리 - play_cooking_sfx()가 duration_seconds가
## 지나면 재생 중이어도 강제로 멈춘다(사용자 지시: "프로그레스바 100% 차기
## 전까지"만). data/cooking/cooking_stations.json의 tool_name("냄비"/
## "프라이팬"/"믹서기")으로 고른다.
const SFX_POT := "res://assets/audio/sfx/sfx_pot.mp3"
const SFX_PAN := "res://assets/audio/sfx/sfx_pan.mp3"
const SFX_MIXER := "res://assets/audio/sfx/sfx_mixer.mp3"
## 완성대(serving_screen) 상호작용 시. 사용자가 파일을 wav에서 mp3로
## 교체했다(구 sfx_dish.wav는 삭제됨) - 경로도 같이 갱신.
const SFX_DISH := "res://assets/audio/sfx/sfx_dish.mp3"
## 여물 급여 성공 시(LivestockManager.perform_feed) - 이미 오늘 줬다는
## 중복 실패에는 재생하지 않는다(사용자 지시).
const SFX_FEEDING := "res://assets/audio/sfx/sfx_feeding.mp3"
## 여물 급여 시 동물 종류별 울음소리 - SFX_FEEDING(먹는 소리)에 겹쳐서 같이
## 재생한다(사용자 지시).
const SFX_COW := "res://assets/audio/sfx/sfx_cow.mp3"
const SFX_PIG := "res://assets/audio/sfx/sfx_pig.mp3"
## 손님이 식사를 마치고 떠나며 실제로 돈을 낼 때(RestaurantManager.npc_departed,
## paid_amount > 0) - 서빙 전에 쫓겨난 손님(paid_amount == 0)에는 재생하지 않는다.
const SFX_COIN := "res://assets/audio/sfx/sfx_coin.mp3"
## 플레이어 발소리 - home_map.gd의 FLAT_LAYERS "Path"/"Ground" 타일 판정에 따라
## _on_player_footstep()이 걸음 박자(player.gd의 footstep 신호)마다 한 번씩 재생한다.
## Path 전용 음원(sfx_footstep_path.ogg)이 이상하게 들린다는 사용자 피드백으로
## Path도 그냥 Ground 소리를 재사용하도록 통일함(사용자 지시) - 안 쓰는
## sfx_footstep_path.ogg는 코드에서 완전히 뺐다.
const SFX_FOOTSTEP_GROUND := "res://assets/audio/sfx/sfx_footstep_ground.ogg"
const SFX_FOOTSTEP_INTERIOR := "res://assets/audio/sfx/sfx_footstep_interior.ogg"
## 실내 발소리가 다른 발소리보다 작게 들린다는 피드백(사용자 지시) - Path
## 발소리 때 했던 것과 같은 방식으로 이 플레이어에만 볼륨을 더한다.
const SFX_FOOTSTEP_INTERIOR_VOLUME_DB := 5.0
## 경작지에 물 줄 때(FarmingManager.perform_water) - 사용자 지시.
const SFX_WATERING_CAN := "res://assets/audio/sfx/sfx_watering_can.mp3"
## 괭이질할 때(FarmingManager.perform_till) - 사용자 지시.
const SFX_DIGGING := "res://assets/audio/sfx/sfx_digging.mp3"
## 씨앗 심을 때(FarmingManager.perform_plant) - 사용자 지시(파일 이름은
## "harvest"지만 실제로는 심기에 쓴다).
const SFX_HARVEST := "res://assets/audio/sfx/sfx_harvest.mp3"
## 자원에서 아이템을 얻을 때 공용(사용자 지시) - 작물 수확(FarmingManager.
## perform_harvest), 소/돼지에게서 우유·고기 획득(LivestockManager.perform_milk/
## perform_slaughter) 전부 여기.
const SFX_ITEM_PICKING := "res://assets/audio/sfx/sfx_item_picking.mp3"
## 추억의 물건을 받을 때(NPCManager.memento_received) - 사용자 지시.
const SFX_MEMORY := "res://assets/audio/sfx/sfx_memory.mp3"
## NPC에게 선물을 줄 때(InventoryManager.gift_given) - 사용자 지시.
const SFX_GIFT := "res://assets/audio/sfx/sfx_gift.mp3"
## 실패 피드백 전용(사용자 지시 - 예전 play_beep() 합성음 대신 이 파일).
## 조리/구매 "성공" 쪽은 SFX_POSITIVE_BEEP - 합성음 생성기(play_beep/
## _generate_tone)는 이제 호출부가 하나도 안 남아서 완전히 삭제했다.
const SFX_BEEP := "res://assets/audio/sfx/sfx_beep.mp3"
## 조리/구매 등 "성공" 피드백 전용(사용자 지시 - 예전 play_beep(660.0, 0.1)
## 합성음 대신 이 파일).
const SFX_POSITIVE_BEEP := "res://assets/audio/sfx/sfx_positive_beep.mp3"

## 상태창(TAB) 설정 탭의 볼륨 슬라이더가 조작하는 오디오 버스 2개 - bgm은
## 브금 하나, sfx는 비/파도/강 등 나머지 배경음 전부를 묶는다(사용자가
## "브금/빗소리 등"으로 뭉뚱그려 요청한 범위). 버스 볼륨은 기존 플레이어별
## volume_db(위 TARGET 상수들, 서로간 상대 밸런스)를 그대로 둔 채 그 위에
## 곱해지는 마스터 조절 역할이라, 슬라이더를 만지지 않는 한(기본 100%,
## 0dB) 기존 밸런스는 전혀 안 바뀐다.
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"
## SaveData(3슬롯)와 무관한 사용자 환경설정이라 세이브 파일이 아니라 별도
## user:// 설정 파일에 저장한다(CLAUDE.md "SaveData 구조 변경 금지" 준수).
const AUDIO_SETTINGS_PATH := "user://audio_settings.cfg"

var _bgm_volume := 1.0
var _sfx_volume := 1.0

var _bgm_player: AudioStreamPlayer
var _current_bgm_path := ""

var _rain_player: AudioStreamPlayer
var _rain_active := false
var _rain_loop_length := 0.0
var _is_indoor := false

var _wave_player: AudioStreamPlayer
var _wave_active := false

var _pond_player: AudioStreamPlayer
var _player: Node = null
var _world_map: WorldMap = null

var _interior_rain_player: AudioStreamPlayer
var _interior_rain_active := false

## "Path"/"Ground"(둘 다 같은 소리 재생)/실내 바닥을 밟는 동안 반복 재생하는
## 발소리 - 임포트된 오디오 파일의 loop 설정을 켜는 대신(assets/ 임포트
## 세팅은 건드리지 않음), 한 클립이 끝날 때마다 이 스크립트에서 다시
## play()해서 이어붙인다. Path/Ground와 실내를 각각의 플레이어로 나눠서
## 표면이 바뀌는 순간 서로 안 겹치고 바로 전환되게 한다.
var _ground_footstep_player: AudioStreamPlayer
var _interior_footstep_player: AudioStreamPlayer

## main.gd가 set_player()를 호출하기 전(타이틀/슬롯선택/캐릭터생성 화면 등
## 아직 실제 게임 플레이가 시작되기 전)에는 BGM/비/파도 소리를 켜지 않는다.
## 오토로드는 씬과 무관하게 게임 부팅 즉시 _ready()가 돌기 때문에, 이 가드가
## 없으면 타이틀 화면만 떠 있는 상태에서도 WeatherManager가 그날 날씨를
## 굴려서(20% 확률) 비 소리가 나버린다(사용자 리포트: "시작하자마자 빗소리").
var _game_started := false


func _ready() -> void:
	_ensure_audio_buses()
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = BUS_BGM
	add_child(_bgm_player)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = BUS_SFX
	add_child(_rain_player)
	_wave_player = AudioStreamPlayer.new()
	_wave_player.bus = BUS_SFX
	add_child(_wave_player)
	_pond_player = AudioStreamPlayer.new()
	_pond_player.bus = BUS_SFX
	add_child(_pond_player)
	_interior_rain_player = AudioStreamPlayer.new()
	_interior_rain_player.bus = BUS_SFX
	add_child(_interior_rain_player)
	_ground_footstep_player = AudioStreamPlayer.new()
	_ground_footstep_player.bus = BUS_SFX
	add_child(_ground_footstep_player)
	_interior_footstep_player = AudioStreamPlayer.new()
	_interior_footstep_player.bus = BUS_SFX
	_interior_footstep_player.volume_db = SFX_FOOTSTEP_INTERIOR_VOLUME_DB
	add_child(_interior_footstep_player)
	_load_volume_settings()
	GameManager.map_changed.connect(_on_map_changed)
	TimeManager.hour_changed.connect(_on_hour_changed)
	WeatherManager.weather_changed.connect(_on_weather_changed)
	SaveManager.game_loaded.connect(_on_game_loaded)
	RestaurantManager.npc_arrived.connect(_on_npc_arrived)
	RestaurantManager.npc_departed.connect(_on_npc_departed)
	ShopManager.item_purchased.connect(_on_item_purchased)
	FishingManager.fishing_ended.connect(_on_fishing_ended)
	NPCManager.memento_received.connect(_on_memento_received)
	InventoryManager.gift_given.connect(_on_gift_given)
	# InventoryManager.recipe_learned가 아니라 CookingManager.recipe_learned에
	# 연결해야 한다 - Inventory 쪽은 레시피 아이템을 "쓸 때마다"(이미 아는
	# 레시피라도) 발생하고, Cooking 쪽만 "진짜 처음 배울 때"만 발생한다.
	# via_item으로 그중에서도 "아이템으로 배운 경우"만 다시 걸러진다
	# (_on_recipe_learned 참고).
	CookingManager.recipe_learned.connect(_on_recipe_learned)
	_is_indoor = GameManager.current_map_id.ends_with("_interior")


## main.gd가 한 번 호출해서 넘겨준다(hud.gd의 set_player()와 같은 이유 -
## 강 근접도를 계산하려면 플레이어 좌표가 필요한데 AudioManager는 HomeMap
## 아래의 플레이어를 직접 찾을 수 없다). 실제 게임 플레이가 시작되는
## 시점이기도 해서 _game_started를 여기서 켜고, 그동안 밀려있던 BGM/날씨
## 효과음을 이제야 처음 재생한다(_ready 참고 - 그 전까지는 타이틀 화면 등
## 아직 시작 전이라 아무 소리도 내면 안 된다).
func set_player(player: Node) -> void:
	_player = player
	_player.footstep.connect(_on_player_footstep)
	_game_started = true
	play_bgm(_get_target_bgm())
	_update_rain_sfx()
	_update_wave_sfx()
	_update_interior_rain_sfx()


## main.gd가 한 번 호출해서 넘겨준다 - get_distance_to_nearest_pond() 조회에 쓴다.
func set_world_map(world_map: WorldMap) -> void:
	_world_map = world_map


func _get_target_bgm() -> String:
	if GameManager.current_map_id == RESTAURANT_MAP_ID:
		return BGM_RESTAURANT
	return BGM_NIGHT if TimeManager.current_hour >= NIGHT_BGM_START_HOUR else BGM_MAIN


func _on_map_changed(map_id: String) -> void:
	_is_indoor = map_id.ends_with("_interior")
	play_bgm(_get_target_bgm())
	_update_rain_sfx()
	_update_wave_sfx()
	_update_interior_rain_sfx()
	# 맵이 바뀌면 새 맵 표면 판정이 나올 때까지 한 프레임 정도 이전 맵 소리가
	# 이어질 수 있다 - 미리 꺼서 그 틈을 없앤다.
	_ground_footstep_player.stop()
	_interior_footstep_player.stop()


func _on_hour_changed(_hour: int) -> void:
	play_bgm(_get_target_bgm())


func _on_weather_changed(_weather: WeatherManager.Weather) -> void:
	_update_rain_sfx()
	_update_interior_rain_sfx()


func _on_game_loaded(_slot: int) -> void:
	_is_indoor = GameManager.current_map_id.ends_with("_interior")
	# "이어하기"는 아직 타이틀 화면에 떠있는 동안(씬 전환 전) 이 신호부터
	# 먼저 쏜다 - set_player()가 실제로 불리기 전까진 소리를 내지 않는다.
	if not _game_started:
		return
	play_bgm(_get_target_bgm())
	_update_rain_sfx()
	_update_wave_sfx()
	_update_interior_rain_sfx()


## 아직 assets/audio/bgm/에 실제 파일이 없으면 조용히 아무것도 안 하고
## 넘어간다 - 나중에 파일이 추가된 뒤 다시 켜면(씬 재시작) 정상 재생된다.
func play_bgm(path: String) -> void:
	if path == _current_bgm_path:
		return
	if not ResourceLoader.exists(path):
		return
	_current_bgm_path = path
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	var tween := create_tween()
	if _bgm_player.playing:
		tween.tween_property(_bgm_player, "volume_db", -40.0, BGM_FADE_SECONDS)
	tween.tween_callback(func() -> void:
		_bgm_player.stream = stream
		_bgm_player.volume_db = -40.0
		_bgm_player.play()
	)
	tween.tween_property(_bgm_player, "volume_db", BGM_TARGET_VOLUME_DB, BGM_FADE_SECONDS)


func _update_rain_sfx() -> void:
	var should_play := WeatherManager.is_raining() and not _is_indoor
	if should_play == _rain_active:
		return
	_rain_active = should_play
	if should_play:
		_fade_in_rain()
	else:
		_fade_out_rain()


## sfx_rain.mp3가 아직 없으면(bgm과 마찬가지로) 조용히 넘어간다. 파일 자체의
## loop는 꺼두고(끝의 페이드아웃까지 재생돼버리므로) _process()에서 직접
## 끝나기 전에 되감는다.
func _fade_in_rain() -> void:
	if not ResourceLoader.exists(SFX_RAIN):
		return
	if _rain_player.stream == null:
		var stream: AudioStream = load(SFX_RAIN)
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = false
		_rain_player.stream = stream
		_rain_loop_length = stream.get_length()
	_rain_player.volume_db = -40.0
	_rain_player.play()
	var tween := create_tween()
	tween.tween_property(_rain_player, "volume_db", RAIN_SFX_TARGET_VOLUME_DB, RAIN_SFX_FADE_SECONDS)


func _fade_out_rain() -> void:
	if not _rain_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_rain_player, "volume_db", -40.0, RAIN_SFX_FADE_SECONDS)
	tween.tween_callback(_rain_player.stop)


## sfx_rain.mp3 재생분이 끝의 페이드아웃 구간에 들어가기 전에 처음으로
## 되감아 이어붙인다 - AudioStreamPlayer.loop 방식은 파일 끝까지 그대로
## 재생하고 나서야 되감기 때문에 페이드아웃을 건너뛸 수 없어 직접 처리한다.
func _process(_delta: float) -> void:
	if _rain_player.playing and _rain_loop_length > 0.0:
		var loop_point := maxf(_rain_loop_length - RAIN_LOOP_TRIM_SECONDS, 0.1)
		if _rain_player.get_playback_position() >= loop_point:
			_rain_player.seek(0.0)
	_update_pond_sfx()
	# 걸음 박자에 맞춰 재생만 트리거하고 멈추는 건 여기서 처리 - 안 그러면
	# 멈춘 뒤에도 마지막에 튀어나온 발소리 클립이 끝까지 재생되어 이어진다.
	if _player == null or not _player.is_moving():
		_ground_footstep_player.stop()
		_interior_footstep_player.stop()


## 강 소리는 켜짐/꺼짐이 아니라 물 타일까지의 거리에 따라 볼륨이 계속
## 바뀌어야 해서(rain/wave처럼 한 번 트리거되는 Tween 방식이 아니라) 매
## 프레임 직접 계산한다.
func _update_pond_sfx() -> void:
	if not POND_MAP_IDS.has(GameManager.current_map_id) or _player == null or _world_map == null:
		if _pond_player.playing:
			_pond_player.stop()
		return
	var distance := _world_map.get_distance_to_nearest_pond(_player.position)
	var ratio := clampf(1.0 - distance / POND_FADE_DISTANCE, 0.0, 1.0)
	if ratio <= 0.0:
		if _pond_player.playing:
			_pond_player.stop()
		return
	if not _pond_player.playing:
		if not ResourceLoader.exists(SFX_POND):
			return
		if _pond_player.stream == null:
			var stream: AudioStream = load(SFX_POND)
			if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
				stream.loop = true
			_pond_player.stream = stream
		_pond_player.play()
	_pond_player.volume_db = lerpf(POND_SFX_SILENT_DB, POND_SFX_TARGET_VOLUME_DB, ratio)


## player.gd의 footstep 신호(걷기 프레임이 토글되는 시점 = 발이 땅에 닿는
## 박자)에 맞춰서만 표면을 검사하고 한 번 재생한다 - 매 프레임 위치로 검사하면
## Path 한 칸처럼 좁은 경계에서 Path/Ground 판정이 프레임마다 뒤집혀 소리가
## 잘리고 다시 시작되길 반복해 이상하게 들렸다. 걸음 박자 시점에만 검사하면
## 그 사이의 경계 왕복은 무시되고, 발소리도 실제 걸음 리듬과 맞아떨어진다.
func _on_player_footstep() -> void:
	if _player == null or _world_map == null:
		return
	match _world_map.get_footstep_surface(_player.position):
		"Path", "Ground":
			_play_footstep_once(_ground_footstep_player, SFX_FOOTSTEP_GROUND)
		_:
			_play_footstep_once(_interior_footstep_player, SFX_FOOTSTEP_INTERIOR)


func _play_footstep_once(player: AudioStreamPlayer, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	if player.stream == null:
		player.stream = load(path)
	player.play()


func _update_interior_rain_sfx() -> void:
	var should_play := WeatherManager.is_raining() and _is_indoor
	if should_play == _interior_rain_active:
		return
	_interior_rain_active = should_play
	if should_play:
		_fade_in_interior_rain()
	else:
		_fade_out_interior_rain()


## sfx_interior_rain.mp3가 아직 없으면(다른 사운드들과 마찬가지로) 조용히
## 넘어간다.
func _fade_in_interior_rain() -> void:
	if not ResourceLoader.exists(SFX_INTERIOR_RAIN):
		return
	if _interior_rain_player.stream == null:
		var stream: AudioStream = load(SFX_INTERIOR_RAIN)
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = true
		_interior_rain_player.stream = stream
	_interior_rain_player.volume_db = -40.0
	_interior_rain_player.play()
	var tween := create_tween()
	tween.tween_property(_interior_rain_player, "volume_db", INTERIOR_RAIN_SFX_TARGET_VOLUME_DB, INTERIOR_RAIN_SFX_FADE_SECONDS)


func _fade_out_interior_rain() -> void:
	if not _interior_rain_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_interior_rain_player, "volume_db", -40.0, INTERIOR_RAIN_SFX_FADE_SECONDS)
	tween.tween_callback(_interior_rain_player.stop)


func _update_wave_sfx() -> void:
	var should_play := WAVE_MAP_IDS.has(GameManager.current_map_id)
	if should_play == _wave_active:
		return
	_wave_active = should_play
	if should_play:
		_fade_in_wave()
	else:
		_fade_out_wave()


## rain과 달리 파일 끝에 페이드아웃이 있다는 리포트가 아직 없어서, 엔진 기본
## loop를 그대로 쓴다(잘리는 게 티 나면 rain처럼 수동 되감기로 바꾸면 됨).
func _fade_in_wave() -> void:
	if not ResourceLoader.exists(SFX_WAVE):
		return
	if _wave_player.stream == null:
		var stream: AudioStream = load(SFX_WAVE)
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = true
		_wave_player.stream = stream
	_wave_player.volume_db = -40.0
	_wave_player.play()
	var tween := create_tween()
	tween.tween_property(_wave_player, "volume_db", WAVE_SFX_TARGET_VOLUME_DB, WAVE_SFX_FADE_SECONDS)


func _fade_out_wave() -> void:
	if not _wave_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_wave_player, "volume_db", -40.0, WAVE_SFX_FADE_SECONDS)
	tween.tween_callback(_wave_player.stop)


## 예전 sfx_bell 파일이 다른 효과음보다 크다는 피드백으로 20%(선형) 낮췄던
## 값(-1.9dB)이었으나, 사용자가 sfx_bell 파일 자체를 새로 교체하면서 그
## 보정이 새 파일 음량과 안 맞아 오히려 너무 작게 들린다는 리포트로 일단
## 0(보정 없음)으로 되돌림 - 새 파일 기준으로 다시 들어보고 필요하면 조정.
const SFX_BELL_VOLUME_DB := 0.0


func _on_npc_arrived(_station_index: int, _npc_id: String) -> void:
	play_sfx(SFX_BELL, SFX_BELL_VOLUME_DB)


func _on_npc_departed(_station_index: int, _npc_id: String, paid_amount: int) -> void:
	if paid_amount > 0:
		play_sfx(SFX_COIN)


## 상점 구매(현장/온라인/축산 전부 ShopManager.item_purchased 하나로 합쳐져
## 있음)가 성공할 때마다 - 지금까지는 모달 공통 클릭음(main.gd._input())만
## 나서 다른 버튼 클릭이랑 구분이 안 됐다는 사용자 피드백으로 추가.
func _on_item_purchased(_shop_id: String, _item_id: String, _price: int) -> void:
	play_sfx(SFX_COIN)


func _on_fishing_ended(result: Dictionary) -> void:
	if bool(result.get("success", false)):
		play_sfx(SFX_BUBBLE)


func _on_memento_received(_npc_id: String) -> void:
	play_sfx(SFX_MEMORY)


func _on_gift_given(_npc_id: String, _item_id: String) -> void:
	play_sfx(SFX_GIFT)


## 추억의 물건과 같은 소리 재사용(사용자 지시 - "습득"이라는 점에서 같은
## 부류). via_item이 false(냄비 조합으로 우연히 알게 된 경우)면 재생하지
## 않는다 - 이미 냄비 완성 연출(색 플래시+효과음)이 있어서 겹치면 어색하다는
## 사용자 지시. 조합 발견 쪽은 전용 연출이 생기면 그때 다시 검토(백로그).
func _on_recipe_learned(_recipe_id: String, via_item: bool) -> void:
	if via_item:
		play_sfx(SFX_MEMORY)


## 단발성 효과음 재생 - 파일이 없으면(아직 안 넣었으면) 조용히 넘어간다.
## SFX 버스를 타서 설정 탭의 효과음 볼륨 슬라이더에 반응한다. volume_db는
## 개별 효과음이 유독 크거나 작을 때만 쓴다(기본 0 = 감쇠 없음).
func play_sfx(path: String, volume_db: float = 0.0) -> void:
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.bus = BUS_SFX
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## 조리 중(냄비/프라이팬) 효과음 - duration초가 지나면 재생 중이어도 강제로
## 멈춘다(사용자 지시). tool_name이 냄비/프라이팬이 아니면 조용히 무시한다.
func play_cooking_sfx(tool_name: String, duration: float) -> void:
	var path := ""
	match tool_name:
		"냄비":
			path = SFX_POT
		"프라이팬":
			path = SFX_PAN
		"믹서기":
			path = SFX_MIXER
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.bus = BUS_SFX
	var stream: AudioStream = load(path)
	# 효과음 클립 자체 길이가 duration(예: 15초)보다 짧으면 한 번 재생하고
	# 끝나서 나머지 시간은 조용해지는 문제(사용자 리포트) - loop를 켜서
	# duration이 끝날 때까지 계속 이어붙게 한다.
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	player.stream = stream
	add_child(player)
	player.play()
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	)


## BUS_BGM/BUS_SFX가 없으면(첫 실행 등) 만들고 Master로 보낸다. 프로젝트
## 오디오 버스 리소스를 따로 안 만들고 코드로 보장하는 이유는, 이 프로젝트가
## Godot 에디터를 거의 거치지 않고 헤드리스로만 검증되는 워크플로우라
## (day1 기록 참고) 리소스 파일에 의존하면 깨지기 쉬워서다.
func _ensure_audio_buses() -> void:
	for bus_name in [BUS_BGM, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


## 상태창(TAB) 설정 탭 슬라이더가 읽는 현재 값(0.0~1.0).
func get_bgm_volume() -> float:
	return _bgm_volume


func get_sfx_volume() -> float:
	return _sfx_volume


## 브금은 150%까지 허용한다(사용자 지시 - 새 기본값이 이미 예전보다 조용해진
## 만큼, 더 키우고 싶을 때를 위한 여유). 효과음은 그대로 0~100%.
const BGM_VOLUME_MAX := 1.5


func set_bgm_volume(value: float) -> void:
	_bgm_volume = clampf(value, 0.0, BGM_VOLUME_MAX)
	_apply_bus_volume(BUS_BGM, _bgm_volume)
	_save_volume_settings()


func set_sfx_volume(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, _sfx_volume)
	_save_volume_settings()


func _apply_bus_volume(bus_name: String, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, percent <= 0.0)
	if percent > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(percent))


## SaveData(3슬롯)와 별개인 사용자 환경설정이라 SaveManager를 거치지 않고
## 자체 파일에 저장/로드한다(CLAUDE.md "SaveData 구조 변경 금지" 준수).
func _load_volume_settings() -> void:
	var config := ConfigFile.new()
	if config.load(AUDIO_SETTINGS_PATH) == OK:
		_bgm_volume = clampf(config.get_value("audio", "bgm_volume", 1.0), 0.0, BGM_VOLUME_MAX)
		_sfx_volume = clampf(config.get_value("audio", "sfx_volume", 1.0), 0.0, 1.0)
	_apply_bus_volume(BUS_BGM, _bgm_volume)
	_apply_bus_volume(BUS_SFX, _sfx_volume)


func _save_volume_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "bgm_volume", _bgm_volume)
	config.set_value("audio", "sfx_volume", _sfx_volume)
	config.save(AUDIO_SETTINGS_PATH)
