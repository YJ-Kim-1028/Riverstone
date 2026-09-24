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

## 추가 수정 (같은 세션 후반)

- **음반 실물 지급**: 상점에서 산 음반도 인벤토리에 실물로 들어옴 - `shop_manager.gd`
  `buy()`의 음반 전용 분기/`_buy_jukebox_record()` 삭제(일반 구매 경로 사용, 온라인은
  배송). 8월 10일 "구매 시 인벤토리 안 들어감" 지시를 사용자가 되돌림. 주크박스
  해금은 `purchase_counts` 기반이라 인벤토리 보유와 무관하게 영구 유지. 이미 산 세이브의
  음반은 인벤토리에 안 들어온 상태 그대로.
- **나이프**: `shops.json` small_knife에 `purchase_limit: 1` (벨제 상점에서 1회 구매 후 목록에서 사라짐).
- **어셔 책 번역**: `data/books/books.en/ja/zh.json` 신규(10권, 페이지 수 원본과 동일),
  `book_manager.gd` 로더에 `Localizer.apply_language()` 연결.
- **NPC 근무 자리 방향**: `npc_world_manager.gd`에 `_face_down_if_working()` 추가 -
  같은 맵 도착/맵 간 이동 도착 시 스케줄 상태가 `_working`으로 끝나면 정면을 봄.
  게임 시작 시 이미 서 있는 NPC는 이 경로를 안 거칠 수 있음(보이면 추가 수정 필요).
- **인벤토리 툴팁 잘림**: `status_screen.tscn` 루트의 `clip_contents`를 `Background`로
  옮기고 툴팁 라벨에 최소 너비 100 + 자동 줄바꿈(보관함 수정과 동일). 사용자 확인 완료.

## 스페인어(es) 추가

- 사용자 결정: 스페인어권 시장 고려해 출시 전에 한 번에 추가(원어민 검수 없음은 en/ja/zh와 동일).
- Galmuri11-Bold에 스페인어 악센트/¿¡ 글리프 전부 있음(Godot `has_char`로 확인) - 폰트 교체 불필요.
- `Localizer.SUPPORTED_LANGUAGES`에 "es" 추가, 언어 설정 화면에 Español 버튼(`EsButton`) 추가 +
  패널 폭 170 -> 210. 언어 코드 순서 = 버튼 배열 순서(ko,en,ja,zh,es).
- 번역 파일 신규 23개 `*.es.json`(NPC 13, items, recipes, shops, books, requests,
  recurring_templates, furniture descriptions, tutorial, stalker_emails, animals) +
  `strings.json` 308개 키 전부에 `es` 추가. en 파일과 구조/배열 길이/자리표시자 일치 검증 통과.
- 중남미 중립 스페인어, 용어집: papa/maíz/lechuga/cerdo/res/salmón/caballa/calamar/bayas 등.
  마르=usted, 나머지 tú. 성별은 한국어 원본 기준(en 파일이 틀린 곳이 있음: 우디는 여성, 마린은 남성).
- 어셔 책 제목은 books.es/items.es/usher.es 모두 동일하게 통일.
- **en 파일 오류(미수정)**: `strings.json` 장소/이름 `%s` 순서(키 "…%s에서 %s를 본…")와
  `roshi.en.json` witness_seen이 코드 인자 순서(장소, 사람)와 반대라 영어에서 이름/장소가 뒤바뀜.
- 레스토랑 4시 종료 문구: 표시 시간은 4초였으나 문/NPC 근처에서 다른 프롬프트 갱신이 지워서
  짧게 보였음 -> `player.gd` `show_held_message()`로 임시 메시지 표시 중에는 hide/show 무시.
  (`hide_interaction_prompt(force)`는 맵 이동 시에만 강제 해제.)

## 스크린샷용 HUD 숨김

- `game_manager.gd`에 Ctrl+H로 `UI/HUD` 토글(`_toggle_hud_visibility`) 추가. NPC/문 근처 "E ..."
  프롬프트는 HUD가 아니라 그대로 나옴 - 상호작용 대상 없는 자리에서 찍을 것.
- 커버는 실내보다 바깥 풍경에 레스토랑 외관이 보이는 구도 추천(썸네일에서 읽힘).

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
