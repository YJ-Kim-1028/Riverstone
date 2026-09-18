# Day 25

day24(일상 대사 캐싱, NPC 먹는 동작, 마르 향수, 전설의 동상, 무덤 레이어, 코너
슬라이드 어시스트, 캐릭터 크기 축소, 마린 스프라이트 재조립, 다국어 지원
1단계 - 파일럿) 다음 세션. 이번 세션은 **다국어 지원 2단계** - NPC 전원
영어 번역 + 그동안 빠져있던 데이터 소스들의 i18n 연결.

## NPC 영어 번역 - 나머지 9명 완료

- 사용자 지시(2026-09-15): "언어 파일 번역에 너무 많이 토큰이 들더라고. 그래서
  영어부터 할까 하는데." - 3개 언어 동시가 아니라 영어부터 전원, 이후 세션에서
  일/중 진행하는 방식으로 전환.
- day24까지 마린/폴리만 영/일/중 완료, 마르/세이지는 영어만 있었음. 나머지
  9명(벨제/플로라/이샤/라마/모카/로시/셰퍼드/어셔/우디)은 전혀 번역 안 됨.
- 포크 서브에이전트 3개 병렬 실행(3명씩 담당 - 벨제/플로라/이샤, 라마/모카/로시,
  셰퍼드/어셔/우디)으로 처리 - 메인 대화창에 원문 텍스트를 안 올리고 백그라운드
  에서 파일만 쓰게 해서 토큰 절약(사용자가 우려한 지점 직접 해결).
- **중간에 번역 범위 재조정**: 사용자 지적(2026-09-15) - "모든거 다 번역할
  필요 없고 그냥 대사만 번역하면 되는 거 아니야?", "사용자한테 보여주는거만
  번역하면 되잖아". 3개 포크에 전부 SendMessage로 범위 축소 지시:
  `personality`/`special_notes`/`memento_item.lore_lines`는 코드에서 전혀
  안 읽는 필드라 스킵, `preferred_food`/`disliked_food`는 스킵 정도가 아니라
  **번역하면 실제로 버그가 나는 필드**(아래 항목 참고)라 반드시 한국어 유지.
- 결과: 13명 전원 영어 완료. **마린/폴리/벨제**만 영/일/중 전부 완료, 나머지
  10명(마르/세이지/플로라/이샤/라마/모카/로시/셰퍼드/어셔/우디)은 영어만
  완료 - 일본어/중국어는 다음 세션 몫.

## 버그 발견: preferred_food/disliked_food 번역 시 좋아하는 음식 판정이 깨짐

- `NPCManager.get_food_preference_for_ingredients()`가 NPC json의
  `preferred_food`/`disliked_food`(한국어 재료 이름)를 `items.json`의
  `base_material`(영원히 한국어)과 직접 문자열 비교한다. `items.json`은
  다국어 대상이 아니므로, NPC 쪽 이 필드를 번역하면 그 언어에서 좋아하는/
  싫어하는 음식 판정이 조용히 항상 실패한다.
- 이미 완료돼 있던 파일 중 **`marr.en.json`/`sage.en.json`/`poli.en.json`/
  `poli.ja.json`/`belje.zh.json`** 5개가 이 버그를 갖고 있었음(마린만
  처음부터 정상). 전부 한국어 값으로 되돌려 수동 수정.
- **재발 방지**: `Localizer.DENYLIST_KEYS`(scripts/autoload/localization.gd)에
  `preferred_food`/`disliked_food`/`base_material` 3개 키 추가 - 이제 번역
  파일에 값이 있어도 병합 시 무조건 무시되므로, 다음에 일/중 번역할 때 같은
  실수를 해도 게임이 깨지지 않는다.

## 버그 발견 및 수정: belje.zh.json JSON 문법 오류

- 중국어 번역 중 소 이름("晴天")과 다른 고유명사를 일반 큰따옴표로 감싸서
  JSON 문자열 안에 따옴표가 중첩돼 파싱 자체가 깨져 있었음(`{player_mail_
  content}` 플레이스홀더 주변도 동일 문제). JSON이 깨지면 그 언어 파일
  전체가 통째로 무시된다(개별 줄이 아니라 파일 단위 실패).
- 커브형 따옴표(" ")로 교체해서 수정, 이후 전체 언어 파일 JSON 유효성 재검증
  (전부 통과).

## 아이템/레시피/동물/상점 툴팁 다국어 연결 (기존에 완전히 빠져있던 부분)

- 사용자 리포트(2026-09-15): "영어 번역에 툴팁으로 보이는 것들은 하나도
  번역이 안되어있옹". 확인해보니 NPC 대사와 달리 인벤토리/장비/상점/조리대
  등 화면의 아이템 이름·설명은 전부 `data/items/items.json`(+`data/cooking/
  recipes.json`, `data/animals/animals.json`, `data/shop/shops.json`) 4개
  파일에서 오는데, day24 다국어 1단계 때 이 파일들은 아예 `Localizer`에
  연결이 안 돼 있었음(추억의 물건만 NPC json 경유로 자동 번역되고 있었음).
- 4개 매니저(`InventoryManager`/`CookingManager`/`LivestockManager`/
  `ShopManager`)의 로드 함수에 `Localizer.apply_language()` 한 줄씩 추가,
  각각 `reload_for_language()` 진입점 추가. `language_settings_screen.gd`의
  `_on_language_button_pressed()`에 호출 추가 - **순서 중요**: `InventoryManager`
  가 `NPCManager`보다 반드시 나중이어야 한다(추억의 물건 재등록이 NPC 정의의
  이미 번역된 `memento_item`을 읽어가므로).
- 영어 번역 파일 4개(`items.en.json` 119개, `recipes.en.json` 17개,
  `animals.en.json` 2개, `shops.en.json` 10개) 포크 에이전트로 생성 - name/
  description만 담은 최소 형제 파일(나머지 필드는 생략, 병합 시 자동으로
  한국어 폴백).
- 참고 남길 것: `blinder`(그라인더) → "Grinder", `smoothie`(중간재료) →
  "Smoothie Base"(완성 요리인 스무디들과 구분), `roast_bird`의 한글 이름이
  원래 "치킨"이라 "Chicken"으로 직역함 - 원하면 조정.

## 맵 오브젝트 설명/튜토리얼 대사도 다국어 미연결이었음 - 수정

- 사용자 리포트(2026-09-15): "설명창에 나오는 것들은 번역이 안되어있어...
  마르의 잡화점에서 판매하는 물품들이다. 이런거" - 맵에서 가구/오브젝트
  상호작용했을 때 뜨는 설명(`data/furniture/descriptions.json`, 13개 인테리어
  맵)과 오프닝 튜토리얼 대사(`data/tutorial/intro_dialogue.json`, 폴리와의
  첫 만남)도 완전히 빠져 있었음.
- `main.gd`의 `_load_furniture_descriptions()`/`_load_tutorial_dialogue()`에
  `Localizer.apply_language()` 추가. 이 둘은 main.tscn이 언어 선택 이후에
  새로 인스턴스화되는 구조라(타이틀 화면에서만 언어 전환 가능, 게임 중
  전환 불가) 별도 `reload_for_language()` 연결은 필요 없음.
- 영어 번역 파일 2개(`descriptions.en.json`, `intro_dialogue.en.json`) 직접
  작성 완료, 구조 검증 통과.

## 검증 스크립트

- `verify_translation.js`(세션 스크래치패드, 다음 세션엔 사라져 있을 수 있음 -
  필요하면 재작성) - 한국어 원본과 번역 형제 파일을 비교해서 (1) JSON 유효성,
  (2) 배열 길이 정확히 일치(다르면 `Localizer.merge_json()`이 통째로 한국어
  폴백시키는 규칙), (3) denylist 키 제외 미번역/동일 텍스트 경고를 출력한다.
  DENYLIST_KEYS는 코드와 동일하게 유지할 것(이번에 `base_material` 등 추가한
  걸 스크립트에도 같이 반영해뒀음).

## 미해결 - 도구 사용 포즈 (plain2)

- day24에서 발견한 갭("HD 옷 시스템은 걷기/정지만 있고 도구 사용 포즈가
  없음", `player.gd._update_hd_animation()`이 `tool_overlay`를 아예 안 불러서
  낚싯대 그림도 동작 그림도 안 나옴)이 여전히 재현됨(사용자가 plain2로 직접
  확인).
- 사용자가 `assets/player/pixellab/clothes/plain2/preview_player_plain2.png`
  1행에 방향별 "도구 쥐는 포즈" 4종(기존 정지 4종 옆에 추가, 총 8칸)을
  그려서 저장함(2026-09-15 02:49 갱신 확인).
- **기술적 이슈**: 이 미리보기는 프레임당 64x64px인데, 실제 게임 시트
  (`player_outfit_plain2.png`)는 프레임당 32x64px(가로 절반) - 손을 든
  포즈는 가로로 더 뻗어 있어서 그대로 32px로 자르면 손/팔이 잘릴 가능성이
  있다고 사용자에게 안내함.
- **사용자 결정(2026-09-15)**: "후자로 ㄱㄱ" - 일단 32px로 크롭해서 실제로
  얼마나 잘리는지 먼저 보여준 뒤에 진행 방향 결정하기로 함. **다음 세션에서
  이어서 할 것** - 아직 크롭/구현 착수 전.

## 기타

- 낚시 프롬프트 관련 사용자 질문("E fish인데 취소는 왜 Fishing?") - 코드/
  카탈로그 확인 결과 실제로는 "E Cancel fishing"으로 정상 매핑돼 있음(버그
  아님, 캐시/오인 가능성). 사용자가 "그 번역이 맞는거면 상관 없어"로 종결.
- 벨제 영문 표기 불일치 발견: 기획 문서(`game_design/03_npcs/belje.md`)
  제목은 "벨제 (Belze)"인데, 실제 npc_id/파일명/코드 전체는 "belje"(177곳)로
  굳어져 있고 `name_en` 필드만 "Belze"(11곳). 사용자가 오타 낸 게 아니라
  원래부터 있던 불일치 - 어느 쪽으로 표시 이름을 통일할지 **미결정, 사용자
  응답 대기 중**.
- 세션 중 실제로 보내지 않은 것으로 보이는 이상한 메시지("세션 레이트리밋...
  NPC 번역 포크 6개 실패")가 사용자 메시지 형태로 나타남 - `ListAgents`로
  확인해보니 이번 세션엔 해당 포크들이 존재한 적 없었고, 사용자도 "내가
  뭐라고 했는데?"로 보낸 적 없음을 확인 - 무시하고 넘어감(원인 불명, 다른
  세션/창의 내용이 잘못 섞여 들어온 것으로 추정).

## 다음 세션에서 할 일

- [ ] 도구 사용 포즈(plain2) - 64x64 미리보기를 32x64 실제 프레임에 맞게
  크롭해서 얼마나 잘리는지 확인 → 사용자와 상의 후 실제 구현(새 크롭
  스크립트 필요, `build_walking_sheet.ps1`/`build_eating_sheet.ps1` 패턴
  참고 가능). `player_tool_overlay.gd`/`player.gd._update_hd_animation()`
  연결까지 이어서.
- [ ] 벨제 표시 이름(Belze vs Belje) 사용자 결정 반영.
- [ ] 나머지 10명 NPC 일본어/중국어 번역(포크 병렬 처리 패턴 재사용,
  `preferred_food`/`disliked_food`/`base_material` denylist 이미 코드
  레벨에서 막혀 있으니 안심하고 진행 가능).
- [ ] 이번에 새로 연결한 items/recipes/animals/shops/furniture-descriptions/
  intro-dialogue도 마찬가지로 일본어/중국어 필요.
- [ ] items.en.json 등에서 에이전트가 남긴 이름 판단(그라인더/스무디/치킨)
  검토 후 필요하면 수정.
- [ ] 사용자가 직접: 언어를 English로 바꿔서 인벤토리/상점/조리대 툴팁,
  맵 오브젝트 설명, 오프닝 튜토리얼 대사가 잘 나오는지 실전 확인.
