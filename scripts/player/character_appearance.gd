extends RefCounted
class_name CharacterAppearance

## 캐릭터 생성 화면(character_creation_screen.gd)과 실제 인게임 플레이어(player.gd)가
## "같은 원본 그림 + 같은 마커 리컬러 로직"을 공유하기 위한 정적 유틸리티. 오토로드가
## 아니라 WorldMap처럼 class_name 정적 함수 모음이다 - 인스턴스 상태가 없다.
##
## 마커 색/시트 경로는 character_creation_screen.gd에 있던 값을 그대로(변경 없이)
## 옮겨온 것이다 - 실측 확인된 값이므로 절대 임의로 바꾸지 말 것.

const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32

const BODY_PATH := "res://assets/player/body/player_body.png"
const HAIR_SHEET_PATH := "res://assets/player/hair/player_hair.png"
const OUTFIT_SHEET_PATH := "res://assets/player/outfit/player_outfit.png"
const ACCESSORY_SHEET_PATH := "res://assets/player/accessory/player_accessory.png"

const HAIR_MARKER_COLORS: Array[Color] = [
	Color(0xD8 / 255.0, 0xD8 / 255.0, 0xD8 / 255.0),
	Color(0x9A / 255.0, 0x9A / 255.0, 0x9A / 255.0),
	Color(0x56 / 255.0, 0x56 / 255.0, 0x56 / 255.0),
]

const SKIN_MARKER_COLORS: Array[Color] = [
	Color(0xD6 / 255.0, 0xD6 / 255.0, 0xD6 / 255.0),
	Color(0xA8 / 255.0, 0xA8 / 255.0, 0xA8 / 255.0),
	Color(0x72 / 255.0, 0x72 / 255.0, 0x72 / 255.0),
]
const SKIN_LIGHT_DELTA := 46.0 / 255.0
const SKIN_DARK_DELTA := 54.0 / 255.0

const EYE_MARKER_COLOR := Color(1.0, 0.0, 1.0)
const CHEEK_MARKER_COLOR := Color(0.0, 1.0, 0x66 / 255.0)

## character_creation_screen.gd의 OUTFIT_MARKER_COLORS와 동일(2026-08-09,
## player_outfit.png 재작업으로 2색→3색, 마커도 피부와 같은 D6/A8/72로 변경 -
## 두 파일 다 같이 갱신해야 하는 중복 상수).
const OUTFIT_MARKER_COLORS: Array[Color] = [
	Color(0xD6 / 255.0, 0xD6 / 255.0, 0xD6 / 255.0),
	Color(0xA8 / 255.0, 0xA8 / 255.0, 0xA8 / 255.0),
	Color(0x72 / 255.0, 0x72 / 255.0, 0x72 / 255.0),
]

const ACCESSORY_MARKER_COLOR := Color(0x9A / 255.0, 0x9A / 255.0, 0x9A / 255.0)

## 도구 사용 포즈 프레임(12~15, 몸/옷 시트에만 2026-08-12 추가) - 머리/장신구는
## 새로 그리지 않고 같은 방향 idle 프레임(0/3/6/9)을 그대로 유지하기로 했다
## (팔 동작과 안 겹치는 부위라 필요 없음). 헤어/장신구 시트 폭이 그대로 192라
## 이 열이 비어있으므로, 아래에서 idle 열 픽셀을 그대로 복사해 채운다.
const USE_FRAME_TO_IDLE_FRAME := {12: 0, 13: 3, 14: 6, 15: 9}


## 원본에 표식으로 그려둔 정확히 마커 색들만 찾아 같은 순서의 팔레트 색으로 그대로
## 바꿔치기한다 - 고른 색이 곧 결과색(자동 명도 계산 없음). image를 직접 수정한다.
static func recolor_image(image: Image, markers: Array[Color], palette: Array[Color]) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			for i in markers.size():
				if pixel.is_equal_approx(markers[i]):
					var target := palette[i]
					image.set_pixel(x, y, Color(target.r, target.g, target.b, pixel.a))
					break


## 기준색 채널마다 delta를 더하고(0~1로 clamp) 밝음/어둠 톤을 만든다.
static func offset_brightness(color: Color, delta: float) -> Color:
	return Color(
		clampf(color.r + delta, 0.0, 1.0),
		clampf(color.g + delta, 0.0, 1.0),
		clampf(color.b + delta, 0.0, 1.0),
		color.a
	)


## 몸 시트 전체(192x32, 12프레임)를 로드해 피부 3단계 + 눈 + 뺨을 리컬러해서 돌려준다.
## 에셋 파일이 없으면 null.
static func build_body_layer(skin_color: Color, eye_color: Color, cheek_color: Color) -> Image:
	var image := _load_image(BODY_PATH)
	if image == null:
		return null
	var skin_palette: Array[Color] = [
		offset_brightness(skin_color, SKIN_LIGHT_DELTA),
		skin_color,
		offset_brightness(skin_color, -SKIN_DARK_DELTA),
	]
	recolor_image(image, SKIN_MARKER_COLORS, skin_palette)
	recolor_image(image, [EYE_MARKER_COLOR], [eye_color])
	recolor_image(image, [CHEEK_MARKER_COLOR], [cheek_color])
	return image


## 옷은 0번줄부터 이미 실제 스타일이라("없음" 개념 없음) 항상 레이어를 돌려준다.
static func build_outfit_layer(index: int, colors: Array[Color]) -> Image:
	return _build_row_layer(OUTFIT_SHEET_PATH, index, OUTFIT_MARKER_COLORS, colors)


## 0번(대머리)이면 레이어 없음(null) - 몸 스프라이트가 이미 맨머리를 그리고 있어서
## 덧그릴 게 없다는 뜻. 그 외엔 해당 줄을 리컬러해서 돌려준다.
static func build_hair_layer(index: int, colors: Array[Color]) -> Image:
	if index <= 0:
		return null
	return _build_row_layer(HAIR_SHEET_PATH, index, HAIR_MARKER_COLORS, colors)


## 0번("없음")이면 레이어 없음(null). 그 외엔 해당 줄을 리컬러해서 돌려준다.
static func build_accessory_layer(index: int, color: Color) -> Image:
	if index <= 0:
		return null
	return _build_row_layer(ACCESSORY_SHEET_PATH, index, [ACCESSORY_MARKER_COLOR], [color])


## 4개 레이어를 몸→옷→머리→장신구 순으로 알파 합성해 NPC 스프라이트와 같은
## 형식(192x32, 12프레임)의 한 장으로 합친다 - 이 결과가 실제 인게임에 쓰이는 최종
## 스프라이트다. 몸 레이어를 못 만들면(에셋 파일 없음) null - 호출부가 플레이스홀더로
## 폴백해야 한다. 신발은 더 이상 별도 레이어가 아니다 - outfit 그림에 이미
## 신발이 그려져 있어서(사용자 지시, 2026-08-10) 따로 합성하면 덮어씌워진다.
static func build_composite_sheet(
	skin_color: Color, eye_color: Color, cheek_color: Color,
	hair_index: int, hair_colors: Array[Color],
	outfit_index: int, outfit_colors: Array[Color],
	accessory_index: int, accessory_color: Color
) -> Image:
	var body := build_body_layer(skin_color, eye_color, cheek_color)
	if body == null:
		return null
	var result := Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8)
	_blend_layer(result, body)
	_blend_layer(result, build_outfit_layer(outfit_index, outfit_colors))
	var hair := build_hair_layer(hair_index, hair_colors)
	_blend_layer(result, hair)
	var accessory := build_accessory_layer(accessory_index, accessory_color)
	_blend_layer(result, accessory)
	_carry_over_use_pose_layers(result, hair, accessory)
	return result


## GameManager에 저장된 현재 외형 값을 읽어 build_composite_sheet()를 호출한다.
## player.gd와 player_preview.gd(TAB 장비 탭 미리보기) 둘 다 "지금 저장된 외형"을
## 그대로 합성해서 쓰는 같은 호출부라 여기로 모았다.
static func build_current_composite_sheet() -> Image:
	var hair_colors: Array[Color] = [
		Color(GameManager.hair_color_1), Color(GameManager.hair_color_2), Color(GameManager.hair_color_3),
	]
	var outfit_colors: Array[Color] = [
		Color(GameManager.outfit_color_1), Color(GameManager.outfit_color_2), Color(GameManager.outfit_color_3),
	]
	return build_composite_sheet(
		Color(GameManager.skin_color), Color(GameManager.eye_color), Color(GameManager.cheek_color),
		int(GameManager.hair_id), hair_colors,
		int(GameManager.outfit_id), outfit_colors,
		int(GameManager.accessory_id), Color(GameManager.accessory_color)
	)


static func _build_row_layer(path: String, index: int, markers: Array[Color], palette: Array[Color]) -> Image:
	var sheet := _load_image(path)
	if sheet == null:
		return null
	var region := Rect2i(0, index * FRAME_HEIGHT, sheet.get_width(), FRAME_HEIGHT)
	if region.position.y + region.size.y > sheet.get_height():
		return null
	var row_image := sheet.get_region(region)
	recolor_image(row_image, markers, palette)
	return row_image


static func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	return texture.get_image()


## 표준 "src over dst" 알파 합성 - src의 완전 투명 픽셀은 dst를 그대로 둔다. src가
## null이면(해당 레이어 없음, 예: 대머리) 아무것도 하지 않는다.
static func _blend_layer(dst: Image, src: Image) -> void:
	if src == null:
		return
	for y in mini(dst.get_height(), src.get_height()):
		for x in mini(dst.get_width(), src.get_width()):
			var s := src.get_pixel(x, y)
			if s.a > 0.0:
				_blend_pixel(dst, x, y, s)


## 사용 포즈 열(위 상수)에 머리/장신구가 비어 보이지 않도록, 같은 방향 idle
## 열의 픽셀을 그대로 복사해 채운다. 결과 이미지 폭이 아직 확장 전(192)이면
## 사용 포즈 열 자체가 없다는 뜻이라 조용히 넘어간다(방어적 - 몸/옷 에셋이
## 아직 안 늘어난 상태에서도 에러 없이 동작).
static func _carry_over_use_pose_layers(result: Image, hair: Image, accessory: Image) -> void:
	for use_frame in USE_FRAME_TO_IDLE_FRAME:
		var use_x: int = int(use_frame) * FRAME_WIDTH
		if use_x + FRAME_WIDTH > result.get_width():
			return
		var idle_x: int = int(USE_FRAME_TO_IDLE_FRAME[use_frame]) * FRAME_WIDTH
		_blend_region(result, hair, idle_x, use_x)
		_blend_region(result, accessory, idle_x, use_x)


## src의 [src_x, src_x+FRAME_WIDTH) 열만 떼어 dst의 [dst_x, dst_x+FRAME_WIDTH)
## 열 위에 알파 합성한다. _blend_layer와 같은 픽셀 단위 로직(_blend_pixel)을
## 공유한다.
static func _blend_region(dst: Image, src: Image, src_x: int, dst_x: int) -> void:
	if src == null:
		return
	for y in mini(dst.get_height(), src.get_height()):
		for x in FRAME_WIDTH:
			if src_x + x >= src.get_width():
				continue
			var s := src.get_pixel(src_x + x, y)
			if s.a > 0.0:
				_blend_pixel(dst, dst_x + x, y, s)


static func _blend_pixel(dst: Image, x: int, y: int, s: Color) -> void:
	if s.a >= 1.0:
		dst.set_pixel(x, y, s)
		return
	var d := dst.get_pixel(x, y)
	var out_a := s.a + d.a * (1.0 - s.a)
	if out_a <= 0.0:
		dst.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
		return
	var out_r := (s.r * s.a + d.r * d.a * (1.0 - s.a)) / out_a
	var out_g := (s.g * s.a + d.g * d.a * (1.0 - s.a)) / out_a
	var out_b := (s.b * s.a + d.b * d.a * (1.0 - s.a)) / out_a
	dst.set_pixel(x, y, Color(out_r, out_g, out_b, out_a))
