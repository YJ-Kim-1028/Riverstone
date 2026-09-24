# Day 29

day28(브금 전면 교체, itch.io 출시 준비 논의) 다음 세션. 이번 세션은 **게임 제목 확정**.

## 게임 제목 확정: Nightshade Meadow

- 처음엔 스타듀밸리와 비슷한 제목(StarryValley 등)을 원했으나, 너무 가까우면
  모방작/사칭으로 보이고 이름 중복 가능성도 커서 "X Valley" 틀만 참고하기로 함.
- Valley/Hollow는 골짜기·분지 지형이라 나무와 풀이 대부분인 맵에 안 맞음
  → Grove/Meadow/Glade 등 숲·풀밭 단어로 전환.
- **Nightshade**: 가지과 식물 통칭. 독초(벨라도나)와 농작물(토마토/감자/가지)의
  이중의미 - 독이 든 음식 시스템과도 연결. 다만 독초 이미지가 강해 공포를
  일찍 암시할 수 있다는 점은 감수하기로 함.
- **Meadow**: 풀밭. 가장 평화롭고 힐링 느낌. 맵에 강/호수/바다가 있지만
  농사·목축 중심이라 Meadow로 충분하다고 판단.
- WebSearch로 "Nightshade Meadow" 동명 게임 없음 확인(정확 일치 보장은
  아님 - 정식 등록 전 itch.io/Steam 검색창에서 직접 재확인 필요).
- 표기: **Nightshade Meadow** (S 소문자).

## 변경한 파일

- `project.godot`: `config/name` "Riverstone" → "Nightshade Meadow"
- `export_presets.cfg`: `export_path` → `./NightshadeMeadow.exe`,
  `application/product_name` → "Nightshade Meadow"

## 타이틀 화면 이미지 교체 + 게임 아이콘

- 기존 타이틀 배경(`assets/ui/bg_mainmenu.png`)은 하늘+구름뿐이라 Meadow와
  안 맞았고, 로고(`logo.png`)엔 "Riverstone" 글자가 있었음 → GPT로 새 배경/
  로고/아이콘 생성 후 교체(기존 파일은 `_old`/`_old2`로 보관).
- 새 배경: 바다/강/언덕/집이 있는 16:9 픽셀아트 풍경. 위쪽 가운데가 비어 있어 로고 자리 확보.
- 새 로고: "NightShade Meadow"(S 대문자로 나왔지만 사용자가 상관없다고 함).
  배경이 검고 흐릿함 - 투명 PNG인지 미확인, 타이틀 화면에서 검은 사각형이
  보이면 재요청 필요.
- 새 아이콘: `assets/ui/icon.png`(보라 열매+잎, 크림색 라운드 사각형).
  `project.godot`의 `config/icon`, `export_presets.cfg`의 `application/icon`
  에 연결.
- `scenes/ui/title_screen.tscn`의 Logo 노드를 키움: 160x32 → 186x62
  (offset_left/right -93/93, top/bottom 0/62). 버튼 컬럼이 y=61부터 시작하므로
  더 키우면 겹침.
- 새 이미지의 `.import` 파일은 Godot 에디터를 열면 재생성됨.

## 머리색 명도 계산 변경

- `character_appearance.gd`의 `recolor_grayscale_to_hue()`: 원본 픽셀 명도를
  그대로 쓰던 방식(검정이 회색으로 나오던 원인)을 `목표색 명도 x (픽셀 명도 /
  대상 픽셀 평균 명도)`로 교체(사용자 지시 - "고른색 명도 반영해서"). 무채색
  전용 곱연산 분기 삭제. 사용자 확인: "훨씬 낫다".
- 한계: 검정은 음영이 전부 0이라 납작해짐, 아주 밝은 색은 하이라이트가 1.0에서
  잘릴 수 있음.

## 번역/키 설정 관련 수정

- 조리기구 이름(냄비/프라이팬/도마/믹서기): 표시만 `tr()`(main.gd, kitchen_screen.gd),
  `tool_name` 데이터는 효과음 매칭 키라 그대로. strings.json에 4개 추가.
- "베리를 땄다." 등 `berry_bush_manager.gd` 메시지 `tr()` 적용.
- **행동키 프롬프트**: `player.gd show_interaction_prompt()`가 `tr(text)` 후 "E "
  접두를 현재 행동키 이름으로 치환(호출부가 8개 파일에 흩어져 있어 한 곳에서
  처리). 대화창 힌트(`dialogue_screen.gd`)도 행동키 이름 사용.
- 퀘스트: `data/requests/requests.*.json`, `recurring_templates.*.json`(en/ja/zh)
  신규, `email_manager.gd` 로더 두 곳에 `Localizer.apply_language()` 연결.
- 번역 일괄 정리: scripts/ 전체에서 `tr()` 없는 한국어 표시 문자열 11개 파일
  수정, strings.json 새 키 약 100개. 상수라 `tr()` 못 쓴 곳(shop_manager/
  collection_manager/weather_manager)과 main.gd 임시 메시지는 Label 자동
  번역에 의존 - 영어로 플레이해서 한국어가 보이면 그 자리 수정 필요.
- 온라인 샵: 옷/헤어 구매는 즉시 해금이라 "인벤토리를 비워주세요" 대신
  "구매했습니다."(`online_shop_panel.gd _purchase_success_message`).
- 미결: 주크박스 음반이 실제로 인벤토리에 들어오는지(코드상으론 즉시 해금) 사용자
  확인 필요.

## 다음 세션에서 할 일

- [ ] 타이틀 화면 실제 확인 (로고 배경 투명 여부, 로고 크기/버튼 겹침)
- [ ] itch.io/Steam에서 제목 중복 직접 재확인
- [ ] itch.io 커버 이미지/스크린샷 제작 (아트워크 먼저, 로고 얹기)
- [ ] itch.io 페이지 텍스트(소개 문구, 태그, 가격 정책) 작성
- [x] `plan/playtest_feedback_01.md`, `02.md` - 사용자 확정: 남은 항목(1차 버그 9/14/19,
  26 안내, 42 밸런스, 2차 5/7/8/14/16 등)은 더 하지 않기로 함
- [ ] itch.io 업로드 시 AI 콘텐츠(Sounds) 공개 체크
- [x] 새 브금 16개 인게임 청취 확인 (사용자 확인 완료)
- [ ] Game Jolt/스토브인디 계정 개설 여부 결정
