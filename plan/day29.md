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
