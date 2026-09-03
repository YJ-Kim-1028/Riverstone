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

## HD 프로토타입 전용(player.gd HD_HAIRSTYLES 참고) - 이게 설정돼 있으면
## _draw()가 구형 레이어 4장 대신 이 텍스처 한 장(몸+머리 합성 완료본)만
## south idle 프레임으로 그린다(사용자 지시, 2026-09-02 - 옷장 미리보기도
## HD 반영). 옷/장신구는 HD 프로토타입에 아직 레이어가 없어서 이 모드일 땐
## 같이 안 그림 - 실제 게임 속 모습(player.gd)과 동일하게 맞추기 위함.
var _hd_texture: Texture2D = null
## 옷(player.gd HD_OUTFITS) 오버레이 - _hd_texture(헤어) 아래(몸통 담당)에
## 그린다. null이면 그냥 안 그림("옷 없음").
var _hd_outfit_texture: Texture2D = null
## 눈(player.gd HD_EYE_STYLES) 오버레이 - _hd_texture 위(맨 위)에 그린다.
var _hd_eye_texture: Texture2D = null


## 각 텍스처는 이미 프레임 하나(16x32, region (0,0,16,32) = 정면 정지)로
## 잘라진 AtlasTexture를 넘겨받는다 - 자르는 건 호출부(character_creation_screen.gd)
## 책임이다. 신발은 더 이상 별도 레이어가 아니다 - outfit 그림에 이미 신발이
## 그려져 있어서(사용자 지시, 2026-08-10) 따로 합성하면 덮어씌워짐.
func set_layers(body: Texture2D, outfit: Texture2D, hair: Texture2D, accessory: Texture2D) -> void:
	_hd_texture = null
	_hd_outfit_texture = null
	_hd_eye_texture = null
	_body_texture = body
	_outfit_texture = outfit
	_hair_texture = hair
	_accessory_texture = accessory
	queue_redraw()


## texture는 player_hd_<style>.png 전체 시트(몸+머리 합성 완료본, south가
## 첫 그룹) 그대로 넘겨받는다 - 크롭은 여기서 south idle(첫 칸)만 한다.
func set_hd_texture(texture: Texture2D) -> void:
	_hd_texture = texture
	queue_redraw()


## texture는 player_outfit_<style>.png 전체 시트(목 아래만 그려진 오버레이,
## south가 첫 그룹) 그대로 넘겨받는다 - null이면 옷 없음.
func set_hd_outfit_texture(texture: Texture2D) -> void:
	_hd_outfit_texture = texture
	queue_redraw()


## texture는 player_eyes_<style>.png 전체 시트(눈만 그려진 오버레이, south가
## 첫 그룹) 그대로 넘겨받는다 - null이면 눈 없음.
func set_hd_eye_texture(texture: Texture2D) -> void:
	_hd_eye_texture = texture
	queue_redraw()


func _draw() -> void:
	if _hd_texture != null:
		_draw_hd()
		return
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


## HD_FRAME_WIDTH*PlayerController.HD_SCALE가 "구형 16x32 기준 화면 크기와
## 같아지는" 배율이라(player.gd 참고), FRAME_WIDTH/HEIGHT 자리에 그 값을
## 넣으면 구형 미리보기와 동일한 체감 크기가 나온다 - HD_SCALE이 나중에
## 바뀌어도(1.3배 확대 등) 이 미리보기가 자동으로 따라간다.
func _draw_hd() -> void:
	var effective_width := PlayerController.HD_FRAME_WIDTH * PlayerController.HD_SCALE
	var effective_height := PlayerController.HD_FRAME_HEIGHT * PlayerController.HD_SCALE
	var draw_size := Vector2(effective_width, effective_height) * preview_scale
	var anchor_y := size.y / 2.0 + draw_size.y / 2.0 if vertical_center else size.y - FEET_MARGIN
	var feet := Vector2(size.x / 2.0, anchor_y)
	var dest := Rect2(feet + Vector2(-draw_size.x / 2.0, -draw_size.y), draw_size)
	## south 그룹의 idle 프레임(그룹 0의 0번째 칸) = 시트 맨 앞 32x64.
	var region := Rect2(0, 0, PlayerController.HD_FRAME_WIDTH, PlayerController.HD_FRAME_HEIGHT)
	## 순서 중요: 기본값은 아웃핏(팔다리몸통) -> 헤어(목 위만, _hd_texture) -
	## player.gd build_hd_composite_texture()의 정면(남쪽) 기본 순서와 맞춘다.
	## 이 미리보기는 항상 정면(south idle)만 그리므로, 파라의 헤어샵
	## special_hair(HD_HAIRSTYLES_FIXED_COLOR)일 땐 순서를 뒤집어 옷이 항상
	## 보이게 한다(사용자 리포트, 2026-09-04 - "거울에서만 뒤덮은거였다" - 실제
	## 게임 속 캐릭터는 정상인데 옷장/캐릭터생성 거울 미리보기만 이 함수를 따로
	## 써서 놓쳤던 경우).
	var hair_on_top: bool = not (GameManager.hd_hairstyle_id in PlayerController.HD_HAIRSTYLES_FIXED_COLOR)
	if hair_on_top and _hd_outfit_texture != null:
		draw_texture_rect_region(_hd_outfit_texture, dest, region)
	draw_texture_rect_region(_hd_texture, dest, region)
	if not hair_on_top and _hd_outfit_texture != null:
		draw_texture_rect_region(_hd_outfit_texture, dest, region)
	if _hd_eye_texture != null:
		draw_texture_rect_region(_hd_eye_texture, dest, region)
