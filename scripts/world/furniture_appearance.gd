extends RefCounted
class_name FurnitureAppearance

## 가구/바닥장식/벽장식 그림에 표식으로 그려둔 마커 색을 구매 시 고른 색으로
## 치환하는 정적 유틸리티. character_appearance.gd와 완전히 같은 역할을 가구
## 쪽에서 수행한다 - 오토로드가 아니라 class_name 정적 함수 모음(인스턴스
## 상태 없음). 마커 치환 자체(recolor_image)는 CharacterAppearance의 것을
## 그대로 호출해서 로직 중복을 피하지만, 밝음/어둠 계산 방식은 캐릭터
## 피부(offset_brightness, 고정값 더하기)와 다르다 - 아래 색1 설명 참고.
##
## 마커 규칙(사용자가 실제로 그림에 쓴 값, 실측 확인됨 - 임의로 바꾸지 말 것):
## - 색1: 회색 3단계(D6D6D6/A8A8A8/727272) - 기준색 1개만 고르면 D6D6D6(가장
##   밝은 마커)에 고른 색을 그대로 넣고, A8A8A8/727272는 거기서 점점 어둡게만
##   나간다(피부처럼 "중간 마커=기준색, 밝음/어둠 둘 다 계산"이 아님). 이유:
##   실제 그림에서 D6D6D6가 차지하는 면적이 압도적으로 넓은데(예: desk.png는
##   색1의 90% 이상) 기존엔 그 자리에 "고른 색 + 밝게"가 들어가서, 화면에
##   가장 많이 보이는 부분이 원래 고른 색보다 항상 밝게 나와 전체적으로
##   뿌옇게 느껴졌다(사용자 리포트/직접 진단). 가장 넓은 면적을 차지하는
##   마커에 고른 색 원본을 그대로 배정하면 이 문제가 근본적으로 해결된다.
## - 색2: 마젠타(FF00FF) - 명암 계산 없이 고른 색 그대로 플랫 치환.
## - 색3: 형광녹색(00FF66) - 색2와 동일하게 플랫 치환.
## 그림마다 실제로 쓰는 마커가 다르다(마젠타까지만 쓰고 색3은 안 쓴 그림도
## 있고, 색1 없이 색2만 쓴 그림도 있음 - vase2~4 등) - detect_present_markers()가
## 그림을 스캔해서 마커 3종을 각각 있는지 없는지 자동으로 판정한다
## (items.json에 별도 필드 없음, 사용자 확정).

const COLOR1_MARKERS: Array[Color] = [
	Color(0xD6 / 255.0, 0xD6 / 255.0, 0xD6 / 255.0),
	Color(0xA8 / 255.0, 0xA8 / 255.0, 0xA8 / 255.0),
	Color(0x72 / 255.0, 0x72 / 255.0, 0x72 / 255.0),
]
## D6D6D6(가장 넓은 면적) = 고른 색 그대로. A8A8A8/727272는 거기서 검은색
## 쪽으로 비율만 섞어(Color.lerp) 점점 더 어두운 그림자 단계를 만든다 - 두
## 번의 시행착오(46/54 고정값 더하기 → 20/24 → 10/12로 계속 낮춤) 끝에,
## "밝게 만들기"가 아니라 "어느 마커에 원본 색을 배정하느냐"가 진짜 원인
## 이었다는 걸 사용자가 직접 짚어냈다(위 색1 설명 참고). 이제 어둡게만
## 가므로 원본이 아무리 밝은 색이어도(예: Birch #D8BE95) 과다노출될 일이
## 없다.
const COLOR1_MID_MIX := 0.18
const COLOR1_DARK_MIX := 0.38

## CharacterAppearance.EYE_MARKER_COLOR와 동일한 값(다른 이미지 파일이라 충돌
## 걱정 없음, 이름만 가구 맥락에 맞게 새로 정의).
const COLOR2_MARKER := Color(1.0, 0.0, 1.0)
## CharacterAppearance.CHEEK_MARKER_COLOR와 동일한 값.
const COLOR3_MARKER := Color(0.0, 1.0, 0x66 / 255.0)


## 그림을 열어 마커 색 3종이 각각 실제로 있는지 따로따로 판정한다
## ([색1 있음, 색2 있음, 색3 있음]). 파일이 없으면 [false, false, false].
##
## 색2/색3만 쓰고 색1은 건너뛴 그림(예: vase2~4 - 마젠타만 있고 회색 3단계는
## 없음)이 실제로 있어서(사용자 리포트: "꽃병 2,3,4는 색1 고르는게 없을텐데
## 왜 항상 보이는거야") 예전처럼 "가장 높은 단계까지 개수로 뭉뚱그리는" 방식
## (있으면 1, 색2까지 있으면 2...)으로는 색1이 없는데도 색1 슬롯이 뜨는
## 오작동이 생겼다 - 마커별로 독립적으로 있는지만 보고, 없는 자리는 UI에서
## 아예 건너뛴다(shop_screen.gd._build_color_slot_rows() 참고).
static func detect_present_markers(path: String) -> Array[bool]:
	var image := _load_image(path)
	var present: Array[bool] = [false, false, false]
	if image == null:
		return present
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			if not present[0]:
				for marker in COLOR1_MARKERS:
					if pixel.is_equal_approx(marker):
						present[0] = true
						break
			if not present[1] and pixel.is_equal_approx(COLOR2_MARKER):
				present[1] = true
			if not present[2] and pixel.is_equal_approx(COLOR3_MARKER):
				present[2] = true
			if present[0] and present[1] and present[2]:
				return present
	return present


## colors.size()만큼 순서대로 색1(자동 명암)/색2(플랫)/색3(플랫)을 적용한 새
## Image를 반환한다(원본을 건드리지 않고 복사본에 적용 - _load_image()가 매번
## 새 Image를 만들어주므로 별도 duplicate() 불필요). 원본 파일이 없으면 null.
static func build_recolored_image(path: String, colors: Array[Color]) -> Image:
	var image := _load_image(path)
	if image == null:
		return null
	if colors.size() >= 1:
		var color1_palette: Array[Color] = [
			colors[0],
			colors[0].lerp(Color.BLACK, COLOR1_MID_MIX),
			colors[0].lerp(Color.BLACK, COLOR1_DARK_MIX),
		]
		CharacterAppearance.recolor_image(image, COLOR1_MARKERS, color1_palette)
	if colors.size() >= 2:
		CharacterAppearance.recolor_image(image, [COLOR2_MARKER], [colors[1]])
	if colors.size() >= 3:
		CharacterAppearance.recolor_image(image, [COLOR3_MARKER], [colors[2]])
	return image


## character_appearance.gd._load_image()와 동일한 패턴(리소스 캐시 텍스처를
## 통해 Image를 얻음) - 매 호출마다 원본 리소스와 독립된 새 Image를 돌려준다.
static func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	return texture.get_image()
