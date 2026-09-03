extends Control

## 장비 탭 왼쪽의 플레이어 미리보기 - 월드에서 보이는 것과 항상 같게 보이도록,
## player.gd가 쓰는 HD 헤어스타일 시트(player_hd_<style>.png, south idle
## 프레임)를 그대로 그린다(사용자 지시, 2026-09-03 - "인게임에서 픽셀 계산하고
## 잘라서 어쩌고 하는 게 있다면 그건 지워줘" - CharacterAppearance의 구형
## 마커 리컬러 합성은 HD 시트가 있으면 더 이상 쓰지 않는다). HD 파일이 없는
## 방어적 상황에서만 그 구형 합성으로 폴백한다. 캐싱해두되, 옷장(wardrobe_screen.gd)에서
## 외형을 바꾸면 GameManager.appearance_changed로 캐시를 무효화한다.

const FEET_MARGIN := 8.0

var _cached_texture: Texture2D = null
var _hd_mode := false


func _ready() -> void:
	_hd_mode = ResourceLoader.exists(PlayerController.hd_sprite_path(PlayerController.HD_SPRITE_DEFAULT_STYLE))
	GameManager.appearance_changed.connect(_invalidate_cache)


func _invalidate_cache() -> void:
	_cached_texture = null
	queue_redraw()


func _draw() -> void:
	if _hd_mode:
		_draw_hd()
		return
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


## south 그룹 idle 프레임(시트 맨 앞 32x64) - character_preview.gd의 _draw_hd()와
## 같은 계산(HD_FRAME_WIDTH*HD_SCALE이 구형 16x32 기준 화면 크기와 맞도록 잡힌 값).
## 헤어 시트 자체가 이제 목 위만 그려진 오버레이라(사용자 지시, 2026-09-03 -
## "hair with_skin + 눈 + 옷만 하기로 했잖아"), player.gd와 같은
## build_hd_composite_texture()로 옷+헤어+눈을 합쳐서 그려야 몸이 보인다
## (사용자 리포트, 2026-09-03 - "탭 눌렀을 때 내 캐릭터가... 머리만 떠").
func _draw_hd() -> void:
	if _cached_texture == null:
		_cached_texture = PlayerController.build_hd_composite_texture()
	var effective_width := PlayerController.HD_FRAME_WIDTH * PlayerController.HD_SCALE
	var effective_height := PlayerController.HD_FRAME_HEIGHT * PlayerController.HD_SCALE
	var feet := Vector2(size.x / 2.0, size.y - FEET_MARGIN)
	var dest := Rect2(
		feet + Vector2(-effective_width / 2.0, -effective_height),
		Vector2(effective_width, effective_height)
	)
	var region := Rect2(0, 0, PlayerController.HD_FRAME_WIDTH, PlayerController.HD_FRAME_HEIGHT)
	draw_texture_rect_region(_cached_texture, dest, region)


func _build_texture() -> Texture2D:
	var composite := CharacterAppearance.build_current_composite_sheet()
	if composite == null:
		return PlayerController.TEMP_NPC_SPRITE
	return ImageTexture.create_from_image(composite)
