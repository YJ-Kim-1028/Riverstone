extends Control

## 캐릭터 생성 화면의 미리보기 - player_preview.gd(장비 탭 미리보기)와 같은
## 기법(_draw()로 발밑 기준점에 맞춰 그림)이지만, 레이어를 여러 장(몸→옷→
## 머리→장신구 순서로 겹쳐 그림) 합성한다는 점이 다르다. 정면(아래) 정지
## 포즈 한 프레임만 보여준다 - 애니메이션 미리보기는 아님.

const FRAME_WIDTH := 16
const FRAME_HEIGHT := 32
const FEET_MARGIN := 8.0
## 미리보기를 실제 게임 크기보다 크게 보여준다(사용자가 잘 보이게). 캐릭터
## 생성 화면은 발밑에 피부/눈동자 색 팔레트를 두느라 1.8로 줄여 썼지만
## (원래 3.0), 옷장 화면은 캐릭터가 오른쪽에 단독으로 배치돼 그 제약이 없어
## export로 인스턴스마다 다르게 줄 수 있게 뺐다(사용자 지시, 2026-08-30).
@export var preview_scale := 1.8
## 캐릭터 생성 화면은 발밑 기준(false, 기본값) - 밑에 팔레트가 있어서
## 그림이 바닥에 서 있는 느낌이어야 자연스럽다. 옷장은 거울 정중앙에 서 있는
## 느낌을 원해서(사용자 지시, 2026-08-30 - "가로 세로 기준으로 가운데에
## 있지 않아") 세로도 중앙 정렬하는 옵션을 인스턴스별로 켤 수 있게 뺐다.
@export var vertical_center := false

var _body_texture: Texture2D = null
var _outfit_texture: Texture2D = null
var _hair_texture: Texture2D = null
var _accessory_texture: Texture2D = null


## 각 텍스처는 이미 프레임 하나(16x32, region (0,0,16,32) = 정면 정지)로
## 잘라진 AtlasTexture를 넘겨받는다 - 자르는 건 호출부(character_creation_screen.gd)
## 책임이다. 신발은 더 이상 별도 레이어가 아니다 - outfit 그림에 이미 신발이
## 그려져 있어서(사용자 지시, 2026-08-10) 따로 합성하면 덮어씌워짐.
func set_layers(body: Texture2D, outfit: Texture2D, hair: Texture2D, accessory: Texture2D) -> void:
	_body_texture = body
	_outfit_texture = outfit
	_hair_texture = hair
	_accessory_texture = accessory
	queue_redraw()


func _draw() -> void:
	var draw_size := Vector2(FRAME_WIDTH, FRAME_HEIGHT) * preview_scale
	var anchor_y := size.y / 2.0 + draw_size.y / 2.0 if vertical_center else size.y - FEET_MARGIN
	var feet := Vector2(size.x / 2.0, anchor_y)
	var dest := Rect2(feet + Vector2(-draw_size.x / 2.0, -draw_size.y), draw_size)
	var region := Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
	# 순서 중요: 몸(맨살) -> 옷(신발까지 포함해서 다리를 덮음) -> 머리 -> 장신구,
	# 나중에 그릴수록 위에 겹쳐 보인다.
	for texture in [_body_texture, _outfit_texture, _hair_texture, _accessory_texture]:
		if texture != null:
			draw_texture_rect_region(texture, dest, region)
