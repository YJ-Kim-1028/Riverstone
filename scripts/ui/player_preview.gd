extends Control

## 장비 탭 왼쪽의 플레이어 미리보기 - 월드에서 보이는 것과 항상 같게 보이도록,
## player.gd와 같은 CharacterAppearance 합성 결과(아래를 보는 정지 프레임)를
## 그려온다(사용자 지시). 프레임 상수는 PlayerController(player.gd)에서 그대로
## 가져온다. 외형은 세션 중 안 바뀌므로(재커스터마이즈 기능 없음) 첫 _draw()에서
## 한 번만 합성해 캐싱한다.

const FEET_MARGIN := 8.0

var _cached_texture: Texture2D = null


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
