@tool
extends Node2D
class_name PlayerController

signal interact_pressed
## 걷기 프레임이 토글되는(=발이 땅에 닿는) 시점마다 발생 - AudioManager가
## 매 프레임 위치로 Path/Ground 타일을 검사하는 대신 이 신호를 받은 시점에만
## 검사해서 재생하면, 타일 경계에서 떨림 없이 걸음 박자에 맞춰 발소리가 난다.
signal footstep

## NPC(WALK_SPEED=25, npc_sprite.gd)보다 3배 이상 빨랐던 80에서 낮춤 - 걷기
## 프레임 2장으로 도는 애니메이션이 "덜덜거린다"는 사용자 피드백(2026-08-08,
## WALK_FRAME_INTERVAL 주석 참고). 체감으로 맞추는 값이라 더 조정될 수 있음.
const SPEED := 50.0
const PROMPT_DEFAULT_OFFSET_Y := -46.0
const PROMPT_SCREEN_MARGIN := 2.0
const COLLISION_HALF_WIDTH := 7.0
## 위쪽(북쪽)으로 이동해 오브젝트에 접근할 때만 추가로 두는 여백 - 가구가
## 플레이어보다 북쪽에 있을 때 타일 경계에 딱 붙어 양감이 없어 보인다는
## 지적(사용자 지시, 2026-08-29). 아래/옆으로 이동할 땐 기존과 동일하게
## 타일 경계까지 딱 붙어도 문제 없다고 확인되어 그대로 둔다.
const NORTH_APPROACH_COLLISION_MARGIN := 3.0
## 16x32 캐릭터 프레임 크기에 맞춘 값(NPCSprite와 동일).
const SPRITE_HALF_WIDTH := 8.0
const SPRITE_HEIGHT := 32.0

## 실제로 쓰이는 외형은 CharacterAppearance가 합성한다(_build_appearance_texture()
## 참고) - 이건 몸 에셋 파일이 없는 방어적 상황에서만 쓰는 폴백이다.
const TEMP_NPC_SPRITE := preload("res://assets/npc/sprite/usherSprite.png")
const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
## 프레임 배치는 npc_sprite.gd와 동일(16x32, 한 줄 12칸, 좌/우 전용 정지
## 프레임 포함).
const IDLE_FRAME := {
	Vector2i(0, 1): 0, Vector2i(0, -1): 9,
	Vector2i(-1, 0): 3, Vector2i(1, 0): 6,
}
const WALK_FRAMES := {
	Vector2i(0, 1): [1, 2], Vector2i(0, -1): [10, 11],
	Vector2i(-1, 0): [4, 5], Vector2i(1, 0): [7, 8],
}
## npc_sprite.gd의 값(0.35) 그대로 썼다가, 다리가 너무 빨리 번갈아져서
## "진동하는 것처럼 보인다"는 피드백으로 늘림(SPEED도 같이 낮춤, 위 참고).
const WALK_FRAME_INTERVAL := 0.5

## 고해상도 AI 아트 프로토타입(사용자 지시, 2026-09-02 - "npc 스프라이트 자체만으로
## 움직일수있게해달라는뜻") - npc_sprite.gd와 동일한 레이아웃(32x64, 방향당
## 1정지+8걷기=9칸, DOWN/LEFT/RIGHT/UP 순서)의 시트 하나로 그린다. 이 파일이
## 있으면 CharacterAppearance 합성(옷 포함)을 건너뛰고 이 스프라이트 하나로
## 대체한다 - 옷 레이어는 아직 없고("옷 안입힐거야"), GameManager.hd_hairstyle_id로
## 고른 헤어스타일(HD_HAIRSTYLES) 파일을 불러온다.
const HD_SPRITE_DIR := "res://assets/player/pixellab/"
const HD_SPRITE_DEFAULT_STYLE := "danbal"
## 거울(wardrobe_screen.gd)에서 고를 수 있는 헤어스타일 - player_hd_<style>.png
## 파일 이름과 그대로 대응한다(사용자 지시, 2026-09-02). one-side_tied만 좌우
## 비대칭이라 east/west를 따로 생성했고, 나머지는 east를 반전해서 만들었다.
const HD_HAIRSTYLES: Array[String] = [
	"danbal", "bun", "curl_short_hair", "one-side_tied",
	"shortcut", "straight_long_hair", "twin_tail",
	"special_hair1", "special_hair2", "special_hair3", "special_hair4",
]
## 파라의 헤어샵에서 파는 special_hair1~4는 기본 7종과 달리 회색조가 아니라
## 실제 색(초록/파랑 등)으로 그려진 시트라, 머리색 리컬러(hue 치환)를 걸면
## 색이 깨진다 - 그래서 이 스타일들은 머리색 선택을 무시하고 원본 색 그대로
## 쓴다(사용자 지시, 2026-09-04 - "스페셜 헤어에 있는 것들은... 머리 색깔
## 못바꾸게 해줘").
const HD_HAIRSTYLES_FIXED_COLOR: Array[String] = [
	"special_hair1", "special_hair2", "special_hair3", "special_hair4",
]
## 헤어 위에 겹쳐 그리는 별도 오버레이 레이어(사용자 지시, 2026-09-03 - "그냥
## 게임에 바로 적용해줘봐") - player_hd_<style>.png와 달리 몸을 다시 구울 필요
## 없이, 목 아래만 그려진(머리 부분 투명) player_outfit_<style>.png를 같은
## 프레임 인덱스로 그 위에 얹기만 한다. 옷이 아직 없으면(파일 없음) 조용히
## 아무것도 안 그림 - 옷장에서 "없음"을 고른 것과 같은 상태.
const HD_OUTFIT_DIR := "res://assets/player/pixellab/"
## 신규 캐릭터가 기본으로 입고 시작하는 두 벌(plain, plain2) 뒤에, 온라인 상점
## (키라의 의상샵)에서 구매해야 옷장에서 고를 수 있는 스타일이 이어진다 -
## 어느 게 기본 소유인지는 ShopManager.DEFAULT_UNLOCKED_HD_OUTFITS 참고(사용자
## 지시, 2026-09-03 - "기본으로 착용할 수 있는건 plain1,2 옷만 되고 나머지는
## 온라인 상점에서 구매해야 해금").
const HD_OUTFITS: Array[String] = ["plain", "plain2", "look1", "look2", "look3", "look4", "look5", "look6", "look7", "look8", "look9", "look10"]
## 헤어 위, 제일 위에 겹쳐 그리는 얼굴 오버레이(사용자 지시, 2026-09-03 - "눈도
## 이미 있어 프리뷰도 내가 다 만들어놧고") - 옷과 같은 구조(목/머리 부분만
## 그려진 투명 배경 시트, 같은 프레임 인덱스로 얹기만 함). 기본값은 첫 스타일 -
## 옷과 달리 "없음"이 자연스러운 기본이 아니라서(얼굴에 눈이 없으면 이상해
## 보임) hd_hairstyle_id처럼 항상 뭔가 하나는 끼워져 있는 쪽을 기본으로 한다.
const HD_EYE_DIR := "res://assets/player/pixellab/"
const HD_EYE_STYLES: Array[String] = ["anime_eyes", "droopy_eyes", "fox_eyes", "lash_eyes"]
const HD_FRAME_WIDTH := 32
const HD_FRAME_HEIGHT := 64
const HD_WALK_FRAME_COUNT := 8
const HD_GROUP_SIZE := 1 + HD_WALK_FRAME_COUNT
const HD_DIRECTION_GROUP_INDEX := {
	Vector2i(0, 1): 0, Vector2i(-1, 0): 1, Vector2i(1, 0): 2, Vector2i(0, -1): 3,
}
## 걷기 한 바퀴(8프레임) 전체 길이를 기존 2프레임 걷기 주기(WALK_FRAME_INTERVAL*2
## =1.0초)와 비슷하게 맞춘 값(1.0/8).
const HD_WALK_FRAME_INTERVAL := 0.125
## 0.25로 넣었더니 기존 크기의 절반으로 작게 나온다는 리포트(사용자 지시,
## 2026-09-02 - "엥 모야 왤케 작아?") - 32px 원본 기준 기존 16px와 같은
## 화면 크기로 맞추려면 0.5가 기존과 동일한 크기다. 근데 AI 원본이 캐릭터
## 주변에 여백을 두고 나와서(예전 손그림은 캔버스를 꽉 채워 그림) 0.5로도
## 여전히 작아 보인다는 피드백(사용자 지시, 2026-09-02) - 1.3배로 키웠다가
## "생각보다 크다"는 피드백으로 1.2배로 낮춤(같은 날). npc_sprite.gd의
## HD_VISUAL_BOOST와 같은 배율(플레이어/NPC 크기 통일).
const HD_SCALE := 0.5 * 1.2
## 머리 위 이모지(npc_sprite.gd의 EMOTE_OFFSET/EMOTE_DISPLAY_DURATION과 동일한
## 값) - 첫 번째 살인 비명 반응("!" 뒤 나레이션, main.gd) 등 플레이어 쪽에서도
## 이모지가 필요해져서 추가(사용자 지시, 2026-08-26).
const EMOTE_OFFSET := Vector2(0, -FRAME_HEIGHT - 6)
const EMOTE_DISPLAY_DURATION := 1.0
## 향수(마르가 호감도 선물로 주는 perfume_somewhere_behind_you)를 우클릭해
## 뿌리면 뜨는 파티클 - npc_sprite.gd의 SCENT_* 상수/로직과 동일한 패턴을
## 플레이어 쪽에 그대로 옮겼다(사용자 지시, 2026-09-05).
const SCENT_CENTER := Vector2(0, -FRAME_HEIGHT / 2.0)
const SCENT_COUNT := 3
const SCENT_ORBIT := Vector2(10.0, 6.0)
const SCENT_SPEED := 1.4
const SCENT_TEXTURES := {
	"blue": preload("res://assets/img/scent/ocean_scent.png"),
	"purple": preload("res://assets/img/scent/lilac_scent.png"),
	"white": preload("res://assets/img/scent/light_scent.png"),
	"gold": preload("res://assets/img/scent/gold_scent.png"),
}
## 한 번 뿌리면 이 시간(게임 분) 동안 향이 남는다. 다시 뿌리면(아이템이
## 소모되지 않으므로 몇 번이든 가능) 남은 시간과 무관하게 이 값으로 갱신된다.
## 게임 내 5시간(사용자 지시, 2026-09-05).
const SCENT_DURATION_MINUTES := 300

@onready var _interaction_prompt: Label = $InteractionPrompt
@onready var _interaction_icon: TextureRect = $InteractionIcon
@onready var _sprite: Sprite2D = $Sprite2D
## 도구 사용 포즈 + 손 위치 아이콘 담당(scripts/player/player_tool_overlay.gd) -
## main.gd가 밭갈기/낚시 등 액션 지점에서 이 노드를 직접 start()/stop()한다.
@onready var tool_overlay: PlayerToolOverlay = $ToolOverlay

var _map_size := Vector2i.ZERO
var _movement_enabled := true
var _world_map: WorldMap = null
## 지금 바라보는 방향 - 이동 입력과 별개로 "정면"을 기억해둔다(낚시의 "정면
## 물 타일" 판정, 나중엔 농사 밭 타겟팅 등에도 재사용 가능하도록 낚시 전용
## 이름을 쓰지 않음). 매 프레임 실제 이동 벡터의 우세한 축으로 갱신한다
## (_direction_from_vector, npc_sprite.gd의 같은 함수와 동일한 방식) - 눌린
## 키 자체를 추적하면 대각선 이동 중이거나(예: 우상단 이동인데 위쪽만 보임)
## 서로 반대되는 두 키가 동시에 눌려 상쇄될 때(예: W+S를 같이 눌러 세로
## 이동은 없는데 이후 놓은 순서에 따라 엉뚱한 방향을 보이는 문제) 실제
## 이동 방향과 안 맞는 포즈가 나오는 문제가 있었다. 이동이 없을 때는(제자리
## 정지) 갱신하지 않아 마지막으로 걷던 방향을 그대로 유지한다.
var facing_direction := Vector2i(0, 1)  ## 기본값 아래
var _atlas: AtlasTexture
var _walk_frame_timer := 0.0
var _walk_frame_toggle := false
var _hd_mode := false
var _hd_walk_frame_index := 0

## 이동속도 버프/디버프 - data/npc/mocha.json의 buff_item(이동속도 +30%,
## 3분)처럼 아이템/이벤트가 부여하는 일시적 배율. 게임 시간(TimeManager) 기준
## 분 단위로 줄어든다 - 대화 등으로 시간이 멈추면 이 효과도 같이 멈춰야
## 자연스럽다(NPCSprite와 같은 이유).
var _speed_modifier := 1.0
var _speed_effect_minutes_remaining := 0
var _speed_effect_is_debuff := false

## AudioManager가 발소리를 "실제로 걷고 있을 때만" 재생하는 데 쓴다
## (_update_animation()의 애니메이션 전환과 같은 기준 - 걷기 프레임이 도는
## 동안에만 true).
var _is_moving := false

## 컷신 전용 스크립트 이동(walk_to() 참고) - 0이 아니면 _get_move_direction()이
## 실제 키 입력 대신 이 값을 돌려준다. 그래서 충돌/애니메이션/발소리 등
## _physics_process()의 나머지 로직은 평소 이동과 완전히 동일하게 재사용된다.
var _scripted_move_direction := Vector2.ZERO

var _emote_sprite: Sprite2D
var _emote_timer: Timer

var _scent_sprites: Array[Sprite2D] = []
var _scent_time := 0.0
var _has_scent := false
var _scent_minutes_remaining := 0


func _ready() -> void:
	_sprite.centered = true
	_hd_mode = ResourceLoader.exists(hd_sprite_path(HD_SPRITE_DEFAULT_STYLE))
	if _hd_mode:
		_sprite.scale = Vector2(HD_SCALE, HD_SCALE)
		_sprite.offset = Vector2(0, -HD_FRAME_HEIGHT / 2.0)
	else:
		_sprite.offset = Vector2(0, -FRAME_HEIGHT / 2.0)
	_build_emote_sprite()
	_build_scent_sprites()
	_atlas = AtlasTexture.new()
	if _hd_mode:
		_atlas.atlas = build_hd_composite_texture()
		_atlas.region = Rect2(_hd_idle_index(facing_direction) * HD_FRAME_WIDTH, 0, HD_FRAME_WIDTH, HD_FRAME_HEIGHT)
	else:
		_atlas.atlas = _build_appearance_texture()
		_atlas.region = Rect2(IDLE_FRAME[facing_direction] * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
	_sprite.texture = _atlas
	if not Engine.is_editor_hint():
		TimeManager.minute_passed.connect(_on_minute_passed)
		TimeManager.day_changed.connect(_on_day_changed_clear_scent)
		GameManager.appearance_changed.connect(refresh_appearance)


## GameManager.hd_hairstyle_id가 HD_HAIRSTYLES 밖의 값이거나(잘못된 세이브 등)
## 그 스타일 파일이 아직 없으면 HD_SPRITE_DEFAULT_STYLE로 조용히 폴백한다 -
## 캐릭터가 아예 안 보이는 최악의 상황만 방지.
static func _current_hd_sprite_path() -> String:
	return resolve_hd_sprite_path(GameManager.hd_hairstyle_id)


## static이라 인스턴스 없이도 부를 수 있다 - wardrobe_screen.gd 미리보기가
## 임의의(아직 GameManager에 저장 전인) 스타일 경로를 같은 폴백 규칙으로
## 구해야 해서 여기 로직을 그대로 재사용한다(중복 상수/로직 방지).
static func resolve_hd_sprite_path(style: String) -> String:
	if not (style in HD_HAIRSTYLES) or not ResourceLoader.exists(hd_sprite_path(style)):
		style = HD_SPRITE_DEFAULT_STYLE
	return hd_sprite_path(style)


static func hd_sprite_path(style: String) -> String:
	return "%splayer_hd_%s.png" % [HD_SPRITE_DIR, style]


static func _current_hd_outfit_sprite_path() -> String:
	return resolve_hd_outfit_sprite_path(GameManager.hd_outfit_id)


## ""(없음)이면 오버레이 자체를 안 그린다 - HD_HAIRSTYLES와 달리 "없음"이 유효한
## 선택지다(속옷 상태). GameManager.hd_outfit_id가 HD_OUTFITS 밖이거나 그 파일이
## 없어도 "없음"으로 조용히 폴백한다(캐릭터가 안 보이는 게 아니라 그냥 옷만 안
## 입은 상태가 되므로 hd_sprite_path처럼 기본 스타일로 강제할 필요가 없다).
static func resolve_hd_outfit_sprite_path(outfit: String) -> String:
	if outfit == "" or not (outfit in HD_OUTFITS) or not ResourceLoader.exists(hd_outfit_sprite_path(outfit)):
		return ""
	return hd_outfit_sprite_path(outfit)


static func hd_outfit_sprite_path(outfit: String) -> String:
	return "%splayer_outfit_%s.png" % [HD_OUTFIT_DIR, outfit]


static func _current_hd_eye_sprite_path() -> String:
	return resolve_hd_eye_sprite_path(GameManager.hd_eye_style_id)


## hd_hairstyle_id와 같은 폴백 규칙(HD_HAIRSTYLES 밖이거나 파일이 없으면
## 기본 스타일로) - 눈은 "없음"이 기본이 아니라서 hd_outfit_id 방식과 다르다.
## 다만 명시적으로 ""을 고른 경우(옷장에서 "없음" 선택)는 그대로 존중해서
## 오버레이를 끈다.
static func resolve_hd_eye_sprite_path(style: String) -> String:
	if style == "":
		return ""
	if not (style in HD_EYE_STYLES) or not ResourceLoader.exists(hd_eye_sprite_path(style)):
		style = HD_EYE_STYLES[0]
	return hd_eye_sprite_path(style)


static func hd_eye_sprite_path(style: String) -> String:
	return "%splayer_eyes_%s.png" % [HD_EYE_DIR, style]


## 아웃핏/헤어/눈을 별도 Sprite2D 레이어로 겹쳐 그렸더니, z_index가 다른
## 자식들이 생기면서 월드 Y-sort(가로등 등 오브젝트와 앞뒤 비교)가 깨지는
## 문제가 생겼다(사용자 리포트, 2026-09-03 - "가로등 뒤에 서면 가로등이 목을
## 관통한거처럼 보이잖아") - 플레이어 전체가 다시 Sprite2D 하나(=CanvasItem
## 하나)여야 Y-sort가 정상 동작해서, 세 장을 런타임에 Image.blend_rect()로
## 하나의 텍스처에 합성한다(옛 CharacterAppearance 마커 리컬러 시스템이
## body/outfit/hair/accessory를 합치던 것과 같은 방식).
##
## 방향별로 옷/헤어 순서가 다르다 - 단, 기본 7종 헤어스타일은 옷/헤어 경계가
## 서로 맞물리게(자투리 안 보이게) 딱 맞춰 그려져 있어서 항상 옷 위에 헤어를
## 얹는 원래 순서를 유지해야 한다(정면만 순서를 바꿨더니 "머리랑 옷 사이에
## 빈공간이 생겼다"는 리포트, 2026-09-04 - 정면에서 옷이 헤어의 겹치는 부분
## 위에 그려지면서 그 밑에 있던 옷의 원래 그렸던 자투리 경계가 그대로 드러난
## 것). 파라의 헤어샵 special_hair(HD_HAIRSTYLES_FIXED_COLOR)처럼 앞모습이
## 몸통 전체를 덮을 만큼 큰 스타일만 정면(남쪽)에서 헤어 위에 옷을 얹어 옷이
## 항상 보이게 하고, 나머지는 기존 순서(옷 -> 헤어) 그대로 둔다.
static func build_hd_composite_texture() -> Texture2D:
	var group_width := HD_FRAME_WIDTH * HD_GROUP_SIZE
	var size := Vector2i(group_width * HD_DIRECTION_GROUP_INDEX.size(), HD_FRAME_HEIGHT)
	var composite := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var outfit_path := _current_hd_outfit_sprite_path()
	var outfit_image: Image = (load(outfit_path) as Texture2D).get_image() if outfit_path != "" else null
	## 마커 없이 실측 회색조로만 그려진 시트라, 밝기 보존 hue 치환으로 리컬러
	## 한다(CharacterAppearance.recolor_grayscale_to_hue 참고 - 사용자 지시,
	## 2026-09-03 "1번 해봐 얼마나 부정확한지 보게").
	var hair_image := (load(_current_hd_sprite_path()) as Texture2D).get_image()
	var is_fixed_color_hair: bool = GameManager.hd_hairstyle_id in HD_HAIRSTYLES_FIXED_COLOR
	if not is_fixed_color_hair:
		CharacterAppearance.recolor_grayscale_to_hue(hair_image, Color(GameManager.hair_color_2))
	var south_group_index: int = HD_DIRECTION_GROUP_INDEX[Vector2i(0, 1)]
	for group_index in HD_DIRECTION_GROUP_INDEX.values():
		var region := Rect2i(group_index * group_width, 0, group_width, HD_FRAME_HEIGHT)
		if is_fixed_color_hair and group_index == south_group_index:
			composite.blend_rect(hair_image, region, region.position)
			if outfit_image != null:
				composite.blend_rect(outfit_image, region, region.position)
		else:
			if outfit_image != null:
				composite.blend_rect(outfit_image, region, region.position)
			composite.blend_rect(hair_image, region, region.position)
	var eye_path := _current_hd_eye_sprite_path()
	if eye_path != "":
		var eye_image := (load(eye_path) as Texture2D).get_image()
		CharacterAppearance.recolor_grayscale_to_hue(eye_image, Color(GameManager.eye_color))
		composite.blend_rect(eye_image, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return ImageTexture.create_from_image(composite)


func _hd_group_index(direction: Vector2i) -> int:
	return int(HD_DIRECTION_GROUP_INDEX.get(direction, 0))


func _hd_idle_index(direction: Vector2i) -> int:
	return _hd_group_index(direction) * HD_GROUP_SIZE


func _hd_walk_index(direction: Vector2i, walk_frame: int) -> int:
	return _hd_group_index(direction) * HD_GROUP_SIZE + 1 + (walk_frame % HD_WALK_FRAME_COUNT)


## 캐릭터 생성 화면에서 고른 외형(GameManager에 저장된 색/스타일)을 CharacterAppearance로
## 합성해 NPC 스프라이트와 같은 형식(192x32, 12프레임)의 한 장짜리 텍스처로 돌려준다.
## 몸 레이어를 못 만들면(에셋 파일 없음) TEMP_NPC_SPRITE로 폴백 - 캐릭터가 아예 안 보이는
## 최악의 상황만 방지한다.
func _build_appearance_texture() -> Texture2D:
	var composite := CharacterAppearance.build_current_composite_sheet()
	if composite == null:
		return TEMP_NPC_SPRITE
	return ImageTexture.create_from_image(composite)


## 옷장(wardrobe_screen.gd)에서 외형을 바꿨을 때 GameManager.appearance_changed로
## 호출된다 - 시트를 다시 합성해서 이미 만들어둔 AtlasTexture의 atlas만 바꿔
## 끼운다(region은 그대로라 방향/포즈 프레임 좌표는 안 건드림).
func refresh_appearance() -> void:
	if _hd_mode:
		_atlas.atlas = build_hd_composite_texture()
		return
	_atlas.atlas = _build_appearance_texture()


## 요리창/상점창 등 모달 UI가 열려있는 동안 main.gd가 호출해서 이동을 잠근다.
func set_movement_enabled(enabled: bool) -> void:
	_movement_enabled = enabled


## main.gd가 한 번 호출해서 넘겨준다 - 벽/가구 등 collision=true 타일 충돌
## 체크에 쓰인다 (WorldMap.is_cell_blocked).
func set_world_map(world_map: WorldMap) -> void:
	_world_map = world_map


func show_interaction_prompt(text: String) -> void:
	_interaction_prompt.text = text
	_interaction_prompt.visible = true
	_interaction_icon.visible = false


## icon_path에 실제 그림이 있으면(16x16, ResourceLoader.exists()) 그 아이콘을,
## 없으면 fallback_text(임시 이모지 등)를 대신 보여준다 - 그림이 나중에
## 채워져도 이 함수를 부르는 쪽(main.gd)은 그대로 둬도 된다(사용자 지시,
## 2026-08-29 - 가구 나레이션 프롬프트를 "E 확인" 대신 말풍선 아이콘으로).
func show_interaction_icon(icon_path: String, fallback_text: String) -> void:
	if ResourceLoader.exists(icon_path):
		_interaction_icon.texture = load(icon_path)
		_interaction_icon.visible = true
		_interaction_prompt.visible = false
	else:
		show_interaction_prompt(fallback_text)


func hide_interaction_prompt() -> void:
	_interaction_prompt.visible = false
	_interaction_icon.visible = false


## AudioManager가 발소리 재생 여부를 판단하는 데 쓴다 - 실제로 입력을 받아
## 움직이고 있을 때만 true(정지 중엔 false, 모달 등으로 이동이 잠긴 동안도 false).
func is_moving() -> bool:
	return _is_moving


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# _get_move_direction()이 이미 _movement_enabled를 반영한다(스크립트 이동은
	# 예외) - 여기서 다시 _movement_enabled로 게이트하면 컷신 중 스크립트
	# 이동까지 같이 막혀버린다.
	var move_direction := _get_move_direction()
	var is_moving := move_direction != Vector2.ZERO
	_is_moving = is_moving
	if is_moving:
		_move_with_collision(move_direction * SPEED * _speed_modifier * _delta)
		facing_direction = _direction_from_vector(move_direction)
	_clamp_to_map_bounds()
	_update_animation(_delta, is_moving)


## percent: +0.1이면 이동속도 +10%(버프), -0.3이면 -30%(디버프). 디버프는
## 항상 새로 덮어쓴다. 버프끼리는(예: 세이지 행운 버프 20% 중에 아메리카노
## 10%를 마시는 경우) 더 약한 쪽이 더 강한 쪽을 깎아먹지 않도록, 이미 걸린
## 버프보다 약하거나 같으면 무시한다(사용자 지시, 2026-08-26 - "세이지 버프가
## 있을 때 커피 마셔도 이속 버프 안 생겨.. 여전히 10%야").
func apply_speed_effect(percent: float, duration_minutes: int, is_debuff: bool) -> void:
	if not is_debuff and not _speed_effect_is_debuff and _speed_effect_minutes_remaining > 0:
		if percent <= _speed_modifier - 1.0:
			return
	_speed_modifier = 1.0 + percent
	_speed_effect_minutes_remaining = duration_minutes
	_speed_effect_is_debuff = is_debuff


## 이샤의 디버프 해제 아이템(자양 강장제) 전용 - 지금 걸린 효과가 디버프일
## 때만 지운다. 버프 중에 잘못 마셔서 버프까지 사라지면 안 되기 때문.
func clear_debuff() -> void:
	if _speed_effect_is_debuff:
		_speed_modifier = 1.0
		_speed_effect_minutes_remaining = 0
		_speed_effect_is_debuff = false


## HUD가 버프/디버프 아이콘 표시 여부와 툴팁 내용을 판단하는 데 쓴다. 효과가
## 없으면 빈 Dictionary.
func get_speed_effect_info() -> Dictionary:
	if _speed_effect_minutes_remaining <= 0:
		return {}
	return {
		"percent": _speed_modifier - 1.0,
		"minutes_remaining": _speed_effect_minutes_remaining,
		"is_debuff": _speed_effect_is_debuff,
	}


func _on_minute_passed(_hour: int, _minute: int) -> void:
	if _scent_minutes_remaining > 0:
		_scent_minutes_remaining -= 1
		if _scent_minutes_remaining <= 0:
			_has_scent = false
			for sprite in _scent_sprites:
				sprite.visible = false
	if _speed_effect_minutes_remaining <= 0:
		return
	_speed_effect_minutes_remaining -= 1
	if _speed_effect_minutes_remaining <= 0:
		_speed_modifier = 1.0
		_speed_effect_is_debuff = false


## 축(x/y)을 따로 검사해서, 대각선으로 이동하다 한쪽만 막혀도 나머지 축으로는
## 계속 미끄러지듯 움직일 수 있게 한다 (완전히 막힌 것처럼 뚝 멈추지 않게).
## world_map이 아직 없으면(에디터 프리뷰 등) 충돌 없이 그냥 이동한다.
func _move_with_collision(delta_movement: Vector2) -> void:
	if _world_map == null:
		position += delta_movement
		return
	var next_position := Vector2(position.x + delta_movement.x, position.y)
	if not _is_blocked_at(next_position):
		position.x = next_position.x
	next_position = Vector2(position.x, position.y + delta_movement.y)
	var north_margin := NORTH_APPROACH_COLLISION_MARGIN if delta_movement.y < 0.0 else 0.0
	if not _is_blocked_at(next_position, north_margin):
		position.y = next_position.y


## 발밑 좌표 한 점만 검사하면, 몸통 폭(16px)이 그 점보다 넓어서 발은 아직
## 안 막힌 칸에 있는데 몸통 옆면은 이미 막힌 타일 그림 위로 겹쳐 보이는
## 문제가 있었다(나무/화단 같은 세로로 긴 오브젝트 옆면에서 특히 눈에 띔).
## 발밑 좌우 가장자리도 같이 검사해서 몸통 폭만큼은 막힌 칸에 못 들어가게 한다.
## extra_north_margin은 위로 이동할 때만 호출부(_move_with_collision)가
## NORTH_APPROACH_COLLISION_MARGIN을 넘겨준다 - 실제 검사 지점을 그만큼
## 앞당겨서(더 북쪽으로) 확인하면, 그 여백만큼 남쪽에서 미리 멈추게 된다.
func _is_blocked_at(check_position: Vector2, extra_north_margin: float = 0.0) -> bool:
	var probe_position := Vector2(check_position.x, check_position.y - extra_north_margin)
	if _world_map.is_cell_blocked(Vector2(probe_position.x - COLLISION_HALF_WIDTH, probe_position.y)):
		return true
	if _world_map.is_cell_blocked(Vector2(probe_position.x + COLLISION_HALF_WIDTH, probe_position.y)):
		return true
	return _world_map.is_cell_blocked(probe_position)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _has_scent:
		_scent_time += delta
		for i in _scent_sprites.size():
			var phase := _scent_time * SCENT_SPEED + i * (TAU / SCENT_COUNT)
			_scent_sprites[i].position = SCENT_CENTER + Vector2(cos(phase) * SCENT_ORBIT.x, sin(phase) * SCENT_ORBIT.y)
	if _interaction_prompt.visible or _interaction_icon.visible:
		_keep_prompt_on_screen()


## The prompt normally floats above the player's head. Near a map edge the
## camera can't scroll any further (see set_camera_bounds), so "above head"
## may fall outside the visible view - pull it back down into frame instead
## of letting it render off-screen. 텍스트/아이콘 중 지금 보이는 쪽만 옮긴다
## (show_interaction_icon() 참고 - 둘은 항상 배타적으로 하나만 보임).
func _keep_prompt_on_screen() -> void:
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var half_view_height: float = (get_viewport_rect().size.y / 2.0) / camera.zoom.y
	var view_top_world_y: float = camera.get_screen_center_position().y - half_view_height
	var min_offset_y: float = view_top_world_y - position.y + PROMPT_SCREEN_MARGIN
	if _interaction_prompt.visible:
		_interaction_prompt.position.y = max(PROMPT_DEFAULT_OFFSET_Y, min_offset_y)
	else:
		_interaction_icon.position.y = max(PROMPT_DEFAULT_OFFSET_Y, min_offset_y)


## 실내 맵은 Wall 레이어 충돌이 맵 가장자리보다 몇 칸 안쪽에서 미리 막아주는데,
## 광장 같은 실외 맵은 가장자리를 막는 별도 레이어가 없어서 사각형 경계
## 끝까지 그냥 걸어갈 수 있었다. 거기다 발밑(position)이 맵 경계에 딱
## 붙으면, 발 위로 솟아있는 몸통/머리 부분은 카메라 limit(맵 경계에 고정)
## 밖이라 화면에 아예 안 그려져서 캐릭터가 사라진 것처럼 보였다 - 스프라이트
## 크기만큼 여백을 두고 clamp해서 몸 전체가 항상 경계 안쪽에 있게 한다.
func _clamp_to_map_bounds() -> void:
	if _map_size == Vector2i.ZERO:
		return
	position.x = clamp(position.x, SPRITE_HALF_WIDTH, float(_map_size.x) - SPRITE_HALF_WIDTH)
	position.y = clamp(position.y, SPRITE_HEIGHT, float(_map_size.y))


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		interact_pressed.emit()


## npc_sprite.gd의 _update_animation()과 같은 방식(걷는 중이면 두 걷기 프레임을
## 번갈아, 아니면 정지 프레임) - facing_direction 기준이라 방향키를 안 눌러도
## 마지막으로 보던 방향을 그대로 유지한다.
func _update_animation(delta: float, is_moving: bool) -> void:
	if _hd_mode:
		_update_hd_animation(delta, is_moving)
		return
	if tool_overlay.is_active():
		_set_frame(tool_overlay.get_frame(facing_direction))
		tool_overlay.update_position(facing_direction)
		return
	if is_moving:
		_walk_frame_timer += delta
		if _walk_frame_timer >= WALK_FRAME_INTERVAL:
			_walk_frame_timer -= WALK_FRAME_INTERVAL
			_walk_frame_toggle = not _walk_frame_toggle
			footstep.emit()
		var frames: Array = WALK_FRAMES[facing_direction]
		_set_frame(frames[1] if _walk_frame_toggle else frames[0])
	else:
		_walk_frame_timer = 0.0
		_walk_frame_toggle = false
		_set_frame(IDLE_FRAME[facing_direction])


## _update_animation()의 HD 프로토타입 분기 - tool_overlay(도구 포즈)는 기존
## 16x32 프레임 기준이라 아직 HD 시트와 안 맞는다. 프로토타입 단계라 도구
## 포즈는 일단 무시하고 걷기/정지만 재현한다.
func _update_hd_animation(delta: float, is_moving: bool) -> void:
	if is_moving:
		_walk_frame_timer += delta
		if _walk_frame_timer >= HD_WALK_FRAME_INTERVAL:
			_walk_frame_timer -= HD_WALK_FRAME_INTERVAL
			_hd_walk_frame_index += 1
			## 8프레임 전부에서 매번 울리면 발소리가 실제 걸음(한 걸음=4프레임)보다
			## 4배 잦아진다(사용자 리포트, 2026-09-03 - "발소리가 경박할만큼
			## 자주 들려") - 한 바퀴(8프레임)에 발이 땅에 닿는 지점 2번(0, 4번
			## 프레임)에서만 울려서 구형 2프레임 걷기(WALK_FRAME_INTERVAL*2=1.0초에
			## 2번)와 같은 빈도로 맞춘다.
			if _hd_walk_frame_index % 4 == 0:
				footstep.emit()
		_set_frame(_hd_walk_index(facing_direction, _hd_walk_frame_index))
	else:
		_walk_frame_timer = 0.0
		_hd_walk_frame_index = 0
		_set_frame(_hd_idle_index(facing_direction))


func _set_frame(frame_index: int) -> void:
	if _atlas == null:
		return
	if _hd_mode:
		_atlas.region = Rect2(frame_index * HD_FRAME_WIDTH, 0, HD_FRAME_WIDTH, HD_FRAME_HEIGHT)
	else:
		_atlas.region = Rect2(frame_index * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)


## 스크립트 이동(_scripted_move_direction, walk_to() 참고)은 _movement_enabled와
## 무관하게 항상 우선한다 - 컷신 도중(main.gd가 _movement_enabled를 계속
## false로 눌러두는 동안)에도 walk_to()로 걷는 연출은 끊기면 안 되기 때문
## (사용자 지시, 2026-08-26 - "2차 살인 컷씬이 진행되는 동안 플레이어가
## 움직이면 안될 거 같아"로 main.gd가 _murder_scene_active/_heart_event_active도
## 잠그게 되면서, 그 두 상태 안에서 실행되는 기존 walk_to() 연출까지 같이
## 얼어붙지 않게 여기서 분리함). 키보드 입력만 _movement_enabled로 막는다.
func _get_move_direction() -> Vector2:
	if _scripted_move_direction != Vector2.ZERO:
		return _scripted_move_direction
	if not _movement_enabled:
		return Vector2.ZERO
	var horizontal := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var vertical := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	return Vector2(horizontal, vertical).normalized()


## 컷신에서 키 입력 없이 목표 지점까지 뛰어가게 한다(main.gd의 살인 발견
## 씬 등). _scripted_move_direction을 매 프레임 목표 방향으로 갱신하는
## 방식이라, 충돌/걷기 애니메이션/발소리 전부 평소 이동 로직 그대로 재사용됨.
## 2026-08-16: 처음엔 목표까지 직선으로 밀고 나가는 방식이었는데, 가구 등
## 오브젝트에 걸려서 못 지나가는 버그 발견(사용자 리포트) - NPC 이동에 이미
## 쓰이는 WorldMap.find_path()로 바꿔서 장애물을 실제로 피해가는 경로를
## 구한 뒤, 그 경유점을 순서대로 따라간다.
## RUN_SPEED_MULTIPLIER로 평소보다 빠르게(뛰는 느낌) 움직이고, 경유점 하나당
## SCRIPTED_WALK_TIMEOUT_SECONDS를 넘기면(벽에 낌 등 예외 상황 안전장치)
## 그 경유점은 포기하고 다음으로 넘어간다.
## 2026-08-23: 살인 발견 씬에서 너무 빨리 지나가 상황 파악이 안 된다는
## 사용자 피드백으로 1.8 -> 1.3으로 낮춤.
const RUN_SPEED_MULTIPLIER := 1.3
const SCRIPTED_WALK_ARRIVAL_DISTANCE := 3.0
const SCRIPTED_WALK_TIMEOUT_SECONDS := 10.0

## run=false로 부르면 평소 걷는 속도 그대로 목적지까지 이동한다(사용자 지시,
## 2026-08-26 - "호감도 이벤트때도 개빨라... 실제 걸음 속도랑 똑같이 해야할
## 거 같아. 살인 일어났을 때 황급히 달려가고 그런 거 빼고"). 살인 발견/체포
## 엔딩처럼 급박한 장면은 기본값(run=true)을 그대로 쓰면 된다.
func walk_to(target_position: Vector2, run: bool = true) -> void:
	set_movement_enabled(true)
	var previous_speed_modifier := _speed_modifier
	_speed_modifier = RUN_SPEED_MULTIPLIER if run else 1.0
	var waypoints: PackedVector2Array = _world_map.find_path(position, target_position) if _world_map != null else PackedVector2Array()
	if waypoints.is_empty():
		waypoints = PackedVector2Array([target_position])
	for waypoint in waypoints:
		var elapsed := 0.0
		while position.distance_to(waypoint) > SCRIPTED_WALK_ARRIVAL_DISTANCE and elapsed < SCRIPTED_WALK_TIMEOUT_SECONDS:
			_scripted_move_direction = (waypoint - position).normalized()
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
	_scripted_move_direction = Vector2.ZERO
	_speed_modifier = previous_speed_modifier


## npc_sprite.gd의 같은 이름 함수와 동일한 규칙 - 4방향 스프라이트로 대각선
## 이동까지 눌러 담아야 해서, 더 큰 축을 기준으로 방향을 정한다.
func _direction_from_vector(v: Vector2) -> Vector2i:
	if absf(v.x) > absf(v.y):
		return Vector2i(1, 0) if v.x > 0.0 else Vector2i(-1, 0)
	return Vector2i(0, 1) if v.y > 0.0 else Vector2i(0, -1)


## 현재 바라보는 방향으로 한 칸 앞의 월드 좌표.
func get_facing_tile_position() -> Vector2:
	return position + Vector2(facing_direction) * WorldMap.TILE_SIZE


## 걷지 않고 방향만 target_position 쪽으로 돌린다 - heart_event_30 도착
## 연출에서 옆/뒤를 보고 있던 문제를 고치기 위해 추가(사용자 지시, 2026-08-26).
func face_toward(target_position: Vector2) -> void:
	facing_direction = _direction_from_vector(target_position - position)


## npc_sprite.gd의 _build_emote_sprite()와 동일한 패턴.
func _build_emote_sprite() -> void:
	_emote_sprite = Sprite2D.new()
	_emote_sprite.visible = false
	_emote_sprite.centered = true
	_emote_sprite.position = EMOTE_OFFSET
	_emote_sprite.z_index = 100
	add_child(_emote_sprite)
	_emote_timer = Timer.new()
	_emote_timer.one_shot = true
	_emote_timer.wait_time = EMOTE_DISPLAY_DURATION
	_emote_timer.timeout.connect(func() -> void: _emote_sprite.visible = false)
	add_child(_emote_timer)


## npc_sprite.gd의 show_emote()와 동일 - NPCManager.get_emote_icon_texture()를
## 그대로 재사용해서 새 에셋 없이 플레이어 머리 위에도 이모지를 띄운다.
func show_emote(emote_id: String, duration: float = EMOTE_DISPLAY_DURATION) -> void:
	var texture := NPCManager.get_emote_icon_texture(emote_id)
	if texture == null or _emote_sprite == null:
		return
	_emote_sprite.texture = texture
	_emote_sprite.visible = true
	_emote_timer.wait_time = duration
	_emote_timer.start()


## npc_sprite.gd의 _build_scent_sprites()와 동일한 패턴.
func _build_scent_sprites() -> void:
	for i in SCENT_COUNT:
		var sprite := Sprite2D.new()
		sprite.visible = false
		add_child(sprite)
		_scent_sprites.append(sprite)


## 향수를 우클릭했을 때(equipment_panel.gd → InventoryManager.use_perfume() →
## main.gd._on_item_used()) 호출된다. 이미 향이 있는 상태에서 또 뿌려도
## 아이템이 소모되지 않으므로(use_perfume() 참고) 남은 시간만 새로 갱신된다.
func apply_scent(color_name: String) -> void:
	var texture: Texture2D = SCENT_TEXTURES.get(color_name)
	if texture == null:
		return
	_has_scent = true
	_scent_minutes_remaining = SCENT_DURATION_MINUTES
	for sprite in _scent_sprites:
		sprite.visible = true
		sprite.texture = texture


## 취침(TimeManager._advance_day())은 밤사이 분을 하나씩 흘려보내지 않고
## 다음날 09:00로 바로 건너뛴다 - _on_minute_passed()의 카운트다운이 한 번도
## 안 불려서, 자기 전에 남아있던 향이 자고 일어나도 그대로 남아있었다(사용자
## 리포트, 2026-09-05 - "자고 일어나도 향수가 그대로 있어 자고 일어나면
## 리셋 돼어야 돼"). 하루가 바뀌면 무조건 지운다.
func _on_day_changed_clear_scent(_day: int, _weekday: String) -> void:
	_has_scent = false
	_scent_minutes_remaining = 0
	for sprite in _scent_sprites:
		sprite.visible = false


func set_camera_bounds(map_size: Vector2i) -> void:
	_map_size = map_size
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_size.x
	camera.limit_bottom = map_size.y


## Skips the smoothing catch-up after a teleport so the camera is already
## settled on the new position before the transition fade reveals it.
func snap_camera() -> void:
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
