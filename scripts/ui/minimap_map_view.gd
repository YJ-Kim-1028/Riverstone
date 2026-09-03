extends Control

## 스타듀밸리식 미니맵(사용자 지시, 2026-08-30 - "전체 맵을 연결해서 보여주고
## 내가 지금 있는 곳을 위치로 찍어주는 걸 원했다") - 야외 6곳(Home, plaza1~5)을
## 사용자가 직접 이미지 편집 프로그램/Tiled로 손수 이어붙여 만든 단일 그림
## (assets/map_thumbnails/minimap.png)을 배경으로 깔고, 점 하나로 현재 위치를
## 찍는다. 코드가 6장을 격자로 자동 배치하던 이전 버전은 폐기 - 실제 문 위치로
## 자동 배치하면 순환 경로(Home-plaza1-plaza2-plaza4-Home)가 기하학적으로 안
## 맞아 겹치는 문제가 있었고(레벨 디자인이 이어붙는 평면으로 설계된 게 아님),
## 사용자가 직접 자연스럽게 이어 그리는 쪽이 훨씬 나은 결과가 나왔다.
##
## MAP_LAYOUT은 완성된 minimap.png 안에서 각 지역이 정확히 어디 있는지(왼쪽
## 위 좌표 + 크기)를 나타낸다 - 사용자가 각 조각을 원본 크기 그대로(리사이즈
## 없이) 배치했다고 하여, assets/map_thumbnails/<map_id>.png 원본 캡처본과
## 대조해서 좌표를 추정했다(2026-08-30). 픽셀 완전 정확은 아니고 눈대중 추정이라
## 마커가 살짝 어긋나 보이면 이 표의 숫자만 조정하면 된다.

const MINIMAP_TEXTURE_PATH := "res://assets/map_thumbnails/minimap.png"

## map_id -> Rect2(minimap.png 안에서의 위치, 크기). 크기는 원본 캡처
## (assets/map_thumbnails/<map_id>.png) 그대로라고 가정한 값.
const MAP_LAYOUT := {
	"plaza5": Rect2(0, 0, 256, 272),
	"plaza4": Rect2(260, -20, 384, 512),
	## plaza4-Home 사이 연결 지역(사용자 지시, 2026-08-30 - 원래 미니맵 연결
	## 그림용으로 그렸던 자리에 실제 맵으로 승격됨). plaza4 오른쪽 끝(644)과
	## Home 왼쪽 끝(1056) 사이 틈(412px)이 plaza6 실제 크기(416x512, plaza6.tmx
	## 26x32칸)랑 거의 일치해서 그 틈을 그대로 채우도록 배치 - 어긋나 보이면
	## 좌표만 조정하면 됨.
	"plaza6": Rect2(644, -10, 416, 512),
	"Home": Rect2(1056, 0, 640, 512),
	"plaza2": Rect2(296, 492, 768, 384),
	"plaza1": Rect2(1064, 482, 512, 384),
	"plaza3": Rect2(1054, 866, 448, 384),
}

## 플레이어 위치 마커 - 빨간 점 대신 플레이어 얼굴 스프라이트를 그대로 오려서
## 쓴다(사용자 지시, 2026-08-30). 정면(아래 방향) idle 프레임의 위쪽 절반(머리)만
## 크롭한다. HD 헤어스타일 시트(player_hd_<style>.png)가 있으면 player.gd가 실제
## 인게임 캐릭터를 그릴 때 쓰는 것과 같은 파일에서 바로 크롭해서 쓴다(사용자 지시,
## 2026-09-03 - "인게임에서 픽셀 계산하고 잘라서 어쩌고 하는 게 있다면 그건
## 지워줘" - 예전 CharacterAppearance 마커 리컬러 합성은 실제 헤어스타일과
## 안 맞는 낡은 모습을 보여주고 있었다). HD 파일이 없는 방어적 상황에서만 그
## 구형 합성으로 폴백한다. 테두리/원 없이 이미지만 그린다(사용자 지시 - "프레임
## 안에 사진이 있으니까 이상해보여").
const FACE_FRAME_SIZE := Vector2i(16, 16)
## HD 시트(32x64)는 구형 프레임(16x32)의 정확히 2배 크기라 크롭 좌표도 그대로
## 2배(위 여백 보정도 3px -> 6px).
const HD_FACE_FRAME_SIZE := Vector2i(32, 32)
const FACE_DISPLAY_SIZE := 5.0

var _background_texture: Texture2D = load(MINIMAP_TEXTURE_PATH) as Texture2D
var _face_texture: Texture2D
var _player_world_pos := Vector2.ZERO
var _player_marker_visible := false


func _get_face_texture() -> Texture2D:
	if _face_texture != null:
		return _face_texture
	var hd_path := PlayerController.resolve_hd_sprite_path(GameManager.hd_hairstyle_id)
	if ResourceLoader.exists(hd_path):
		var hd_sheet := (load(hd_path) as Texture2D).get_image()
		var face := hd_sheet.get_region(Rect2i(0, 6, HD_FACE_FRAME_SIZE.x, HD_FACE_FRAME_SIZE.y))
		_face_texture = ImageTexture.create_from_image(face)
		return _face_texture
	var composite: Image = CharacterAppearance.build_current_composite_sheet()
	if composite == null:
		return null
	## 프레임 맨 위 3px 정도는 머리 위 여백(투명)이라 그대로 크롭하면 얼굴이
	## 박스 중앙보다 아래로 쳐져 보인다(사용자 리포트, 2026-08-30 - "실제보다
	## 남쪽으로 찍히는 거 같아") - 그만큼 아래에서부터 크롭해서 얼굴 내용물이
	## 박스 중앙에 오게 보정한다.
	var face := composite.get_region(Rect2i(0, 3, FACE_FRAME_SIZE.x, FACE_FRAME_SIZE.y))
	_face_texture = ImageTexture.create_from_image(face)
	return _face_texture


func refresh(current_map_id: String, player: Node2D) -> void:
	_player_marker_visible = false
	var resolved := _resolve_marker(current_map_id, player)
	if not resolved.is_empty():
		_player_world_pos = resolved["world_pos"]
		_player_marker_visible = true
	queue_redraw()


## 야외 맵이면 그 맵 안에서 플레이어의 실제 좌표를 그대로 쓰고, 실내 맵이면
## (플레이어 좌표를 알 방법이 없으므로) 그 실내로 이어지는 야외 쪽 문 위치를
## 대신 찍는다.
func _resolve_marker(current_map_id: String, player: Node2D) -> Dictionary:
	if MAP_LAYOUT.has(current_map_id):
		if player == null:
			return {}
		return {"area_map_id": current_map_id, "world_pos": _map_to_image_pos(current_map_id, player.position)}
	var graph: Dictionary = WorldMap.get_map_graph()
	for outdoor_id in MAP_LAYOUT:
		for warp in graph.get(outdoor_id, []):
			if String(warp.get("target_map", "")) != current_map_id:
				continue
			var door_pos := Vector2(warp.get("position", Vector2.ZERO))
			return {"area_map_id": outdoor_id, "world_pos": _map_to_image_pos(outdoor_id, door_pos)}
	return {}


## 실제 맵 좌표(native_pos, 0~해당 맵 크기 범위)를 minimap.png 전체 좌표계로
## 변환한다. MAP_LAYOUT의 크기가 원본 캡처 크기와 다르면(사용자가 살짝 리사이즈
## 했다면) 그 비율만큼 같이 보정한다.
func _map_to_image_pos(map_id: String, native_pos: Vector2) -> Vector2:
	var rect: Rect2 = MAP_LAYOUT[map_id]
	return rect.position + native_pos


func _draw() -> void:
	if _background_texture == null:
		return
	var image_size := _background_texture.get_size()
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return
	var scale_factor: float = min(size.x / image_size.x, size.y / image_size.y)
	var draw_offset := (size - image_size * scale_factor) / 2.0
	draw_texture_rect(_background_texture, Rect2(draw_offset, image_size * scale_factor), false)
	## 현재 위치 영역 틴트/테두리는 없앴다(사용자 지시, 2026-08-31 - "노랑색
	## 뿌연색 강조효과... 너무 밤티야, 그냥 없애줭") - 플레이어 얼굴 마커만으로
	## 위치를 표시한다.
	if _player_marker_visible:
		var face := _get_face_texture()
		if face != null:
			var marker_pos := draw_offset + _player_world_pos * scale_factor
			var half := FACE_DISPLAY_SIZE / 2.0
			draw_texture_rect(face, Rect2(marker_pos - Vector2(half, half), Vector2(FACE_DISPLAY_SIZE, FACE_DISPLAY_SIZE)), false)
