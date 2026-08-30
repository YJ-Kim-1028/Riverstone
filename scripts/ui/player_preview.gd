extends Control

## 장비 탭 왼쪽의 플레이어 미리보기 - 월드에서 보이는 것과 항상 같게 보이도록,
## player.gd와 같은 CharacterAppearance 합성 결과(아래를 보는 정지 프레임)를
## 그려온다(사용자 지시). 프레임 상수는 PlayerController(player.gd)에서 그대로
## 가져온다. 합성은 비용이 있어서 _draw()마다 새로 하지 않고 캐싱해두되,
## 옷장(wardrobe_screen.gd)에서 외형을 바꾸면 GameManager.appearance_changed로
## 캐시를 무효화한다(재커스터마이즈 기능이 생기기 전엔 세션 중 안 바뀌어서
## 최초 1회만 합성하면 됐었음).

const FEET_MARGIN := 8.0

var _cached_texture: Texture2D = null


func _ready() -> void:
	GameManager.appearance_changed.connect(_invalidate_cache)


func _invalidate_cache() -> void:
	_cached_texture = null
	queue_redraw()


func _draw() -> void:
	if _cached_texture == null:
		_cached_texture = _build_texture()
	var frame_index: int = PlayerController.IDLE_FRAME[Vector2i(0, 1)]
	var region := Rect2(
		frame_index * PlayerController.FRAME_WIDTH, 0,
		PlayerController.FRAME_WIDTH, PlayerController.FRAME_HEIGHT
	)
	var feet := Vector2(size.x / 2.0, size.y - FEET_MARGIN)
	var dest := Rect2(
		feet + Vector2(-PlayerController.FRAME_WIDTH / 2.0, -PlayerController.FRAME_HEIGHT),
		Vector2(PlayerController.FRAME_WIDTH, PlayerController.FRAME_HEIGHT)
	)
	draw_texture_rect_region(_cached_texture, dest, region)


func _build_texture() -> Texture2D:
	var composite := CharacterAppearance.build_current_composite_sheet()
	if composite == null:
		return PlayerController.TEMP_NPC_SPRITE
	return ImageTexture.create_from_image(composite)
