extends Control

## 캐릭터 생성 화면의 미리보기 - player_preview.gd(장비 탭 미리보기)와 같은
## 기법(_draw()로 발밑 기준점에 맞춰 그림)이지만, 레이어를 여러 장(몸→옷→
## 머리→장신구 순서로 겹쳐 그림) 합성한다는 점이 다르다. 정면(아래) 정지
## 포즈 한 프레임만 보여준다 - 애니메이션 미리보기는 아님.

const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
const FEET_MARGIN := 8.0
## 미리보기를 실제 게임 크기보다 크게 보여준다(사용자가 잘 보이게). 원래
## 3.0이었는데, 발밑 공간에 피부/눈동자 색 팔레트를 두기로 하면서(사용자
## 확정) 캐릭터를 더 작게 줄여 그 공간을 확보함.
const PREVIEW_SCALE := 1.8

var _body_texture: Texture2D = null
var _shoe_texture: Texture2D = null
var _outfit_texture: Texture2D = null
var _hair_texture: Texture2D = null
var _accessory_texture: Texture2D = null


## 각 텍스처는 이미 프레임 하나(16x32, region (0,0,16,32) = 정면 정지)로
## 잘라진 AtlasTexture를 넘겨받는다 - 자르는 건 호출부(character_creation_screen.gd)
## 책임이다.
func set_layers(body: Texture2D, shoe: Texture2D, outfit: Texture2D, hair: Texture2D, accessory: Texture2D) -> void:
	_body_texture = body
	_shoe_texture = shoe
	_outfit_texture = outfit
	_hair_texture = hair
	_accessory_texture = accessory
	queue_redraw()


func _draw() -> void:
	var draw_size := Vector2(FRAME_WIDTH, FRAME_HEIGHT) * PREVIEW_SCALE
	var feet := Vector2(size.x / 2.0, size.y - FEET_MARGIN)
	var dest := Rect2(feet + Vector2(-draw_size.x / 2.0, -draw_size.y), draw_size)
	var region := Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
	# 순서 중요: 몸(맨살) -> 신발(발) -> 옷(다리까지 덮음) -> 머리 -> 장신구,
	# 나중에 그릴수록 위에 겹쳐 보인다.
	for texture in [_body_texture, _shoe_texture, _outfit_texture, _hair_texture, _accessory_texture]:
		if texture != null:
			draw_texture_rect_region(texture, dest, region)
