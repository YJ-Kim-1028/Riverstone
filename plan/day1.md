# Day 1 개발 현황 정리

`game_design/` 기획 문서를 기준으로 구현된 것 / 안 된 것 / 구현하다가 "내용은 있어야 하는데 아직 못 채운 것"을 정리한다.

이 문서는 두 세션에 걸쳐 작성됐다: ① 백엔드(autoload 로직/데이터)를 전부 만든 세션, ② Godot 실행기가 프로젝트에 들어온 뒤 실제로 부팅 검증하고 상호작용 프레임워크 + 최소 UI를 붙인 세션. 아래 "1. 구현 완료" 표와 우선순위는 ②까지 반영된 최신 상태다.

---

## 1. 구현 완료

전부 `scripts/autoload/`의 autoload 싱글톤이며, `project.godot`에 의존성 순서대로 등록되어 있다.

| 시스템 | 기획 문서 | 파일 | 비고 |
| --- | --- | --- | --- |
| 시간 | time.md | `time_manager.gd` | 09:00~24:00, 실시간 1초=게임 1분, 강제취침 |
| 날씨 | weather.md | `weather_manager.gd` | 5일 내 첫비, 4일 무강수 강제비, 살인대기 3일 강제비 |
| NPC 데이터/호감도 | npc.md, affection.md | `npc_manager.gd` | 13명 데이터(`data/npc/*.json`), 호감도, 대사 선택, 스케줄→좌표 변환 |
| 인벤토리 | inventory.md | `inventory_manager.gd` | 슬롯/스택/퀵슬롯/선물/레시피 학습 (`data/items/items.json`) |
| 경제 | economy.md | `economy_manager.gd` | 소지금, 집·인벤토리 확장 비용 |
| 요리 | cooking.md | `cooking_manager.gd` | 레시피 매칭, 쥐약, 도감용 제작횟수 (`data/cooking/recipes.json`) |
| 레스토랑 | restaurant.md | `restaurant_manager.gd` | 요리대 3개, 방문객 큐, 서빙, 수익 반영 |
| 상점 | shop.md | `shop_manager.gd` | 승계 규칙, 온라인 전환, 익일 배송 (`data/shop/shops.json`, id는 맵의 `shop_id` 프로퍼티와 통일) |
| 도감 | collection.md | `collection_manager.gd` | 추억의 물건/레시피 등록, 잠금 처리 |
| 공포(살인) | 02_horror/murder_system.md, stalker.md | `murder_manager.gd` | 살인 조건 검사, 알리바이 생성, 플레이어 독살 |
| 공포(연출) | 02_horror/horror_events.md, email.md | `horror_event_manager.gd` | 노크 이벤트, 세이지 경고, 스토커 이메일 콘텐츠, 사칭 메일 |
| 엔딩 | ending.md | `murder_manager.gd`(통합) | 진실/체포/공범 3종, 중복 방지 |
| 세이브 | save.md | `save_manager.gd` | 3슬롯 JSON, 자동저장(취침/맵이동), 위 시스템 전부 연동 |
| 게임 전역 상태 | (문서 없음, 인프라) | `game_manager.gd` | 플레이어 이름, 플레이시간, 현재 맵 |
| 맵/좌표/월드 상호작용 | (인프라) | `home_map.gd`(`WorldMap`) | tmx 파싱(Spawn/Warp/**Interactable**), Spawn 좌표 전역 인덱스 |
| NPC 월드 배치 | (인프라) | `npc_world_manager.gd`, `npc_sprite.gd` | 스케줄 기반 NPC 스폰/이동/제거 (정지 스프라이트) |
| 플레이어 이동/상호작용 | controls.md 일부 | `player/player.gd` | WASD 이동 + **E 상호작용 키** |
| 월드 상호작용 라우팅 | (인프라) | `main.gd` | E로 계산대/요리대/레스토랑 오픈사인/침대/컴퓨터/책장 감지 → 각 시스템 호출 |
| UI - HUD | ui.md 일부 | `scripts/ui/hud.gd` | 날짜/요일/시간/날씨/골드 상시 표시 |
| UI - 인벤토리 | ui.md 일부 | `scripts/ui/inventory_screen.gd`, `inventory_slot.gd` | I키 토글, 아이콘/이름/설명/수량, 정렬, 버리기 |
| UI - 상점 | ui.md 일부 | `scripts/ui/shop_screen.gd` | 계산대 상호작용으로 열림, 목록+구매+골드 표시 |

---

## 2. 완전히 손 안 댄 시스템

### 2-1. UI 시스템 (`ui.md`) — **일부 구현**
HUD/인벤토리/상점 3개 화면은 만들었다. 아직 없는 것: 이메일함, 도감(책장) 화면, 요리 화면, 상태창(호감도 탭), 대화창. 아래 4번 우선순위 참고.

### 2-2. 오디오 시스템 (`audio.md`) — **미착수**
`audio_manager.gd`는 여전히 빈 스텁. 그리고 프로젝트에 오디오 에셋(bgm/sfx)이 **한 개도 없다** (`assets/` 밑에 audio 폴더 자체가 없음). 로직을 짜도 재생할 소리 파일이 없는 상태 — 에셋 확보가 선행되어야 함.

### 2-3. 이메일 시스템 본체 (`email.md`, 01_systems) — **부분 미착수**
스토커 이메일/사칭 메일의 "내용 결정 로직"은 `horror_event_manager.gd`에 이미 있다. 하지만:
- 일반 NPC가 보내는 이메일(안부/초대/감사 등, `data/npc/*.json`의 `emails` 필드)을 실제로 "오늘 보낼지 말지" 판단하는 로직이 없음
- 받은 메일을 보관/열람하는 인박스(`EmailManager` 같은 것) 자체가 없음
- 레스토랑 초대장 발송 로직 없음 (`RestaurantManager.invite_npc()`는 이미 있지만, 이걸 호출하는 "메일 작성 UI"가 없음)
- 컴퓨터 상호작용(`computer_interacted` 신호)은 연결만 돼 있고 받는 화면이 없음

### 2-4. 조작(`controls.md`) — **이동/상호작용/인벤토리까지 구현**
WASD, E, I까지 됐다. 남은 것: ESC로 전체 메뉴 열기(지금은 인벤토리/상점 화면이 열려 있을 때만 ESC로 닫힘), TAB 상태창, M 지도(선택 사항이라 우선순위 낮음).

### 2-5. 농사/축산/낚시 — **기획 문서 자체가 없음**
`inventory.md`에 씨앗·물뿌리개·낚싯대·양동이 같은 아이템은 있지만, "밭을 갈고 씨앗을 심고 수확하는" 농사 시스템이나 "낚시 미니게임", "동물을 키우는" 축산 시스템을 다루는 기획 문서(`farming.md`, `fishing.md` 등)가 `game_design/` 안에 없다. 상점 데이터에도 `planned_stock`으로만 남겨둔 상태 (`data/shop/README.md` 참고). `cowshed_interior.tmx`에 `door1~4_open` 상호작용 오브젝트는 이미 맵에 있지만 연결 안 함. 구현하려면 먼저 기획이 필요함.

---

## 3. 구현하다가 "일단 만들어는 뒀지만 내용은 비어있는" 것

시스템(코드)은 있는데, 그 안에 들어갈 구체적인 스토리/밸런스 콘텐츠가 기획 문서에 없어서 못 채운 부분들. `data/*/README.md`에 각각 더 자세히 적어뒀다.

| 항목 | 위치 | 상태 |
| --- | --- | --- |
| NPC 일상 잡담 (요일×호감도별) | `data/npc/<id>.json`의 `dialogue.daily` | 13명 전부 빈 배열 |
| NPC 이메일 본문 (안부/초대/감사/스토리/기념일) | `data/npc/<id>.json`의 `emails` | 13명 전부 빈 배열/객체 |
| 사칭 이메일(죽은 NPC 명의) | `data/horror/impersonation_emails.json` | 플로라 1명만 채움, 나머지 12명 없음 |
| 선물 아이템 카탈로그 | `data/items/items.json` | 0개 (마르의 잡화점이 뭘 파는지 기획에 없음) |
| 완성 요리 판매 상세(선호도 대응 요리)는 있지만, 상점별 재료/도구/가구 가격 | `data/shop/shops.json` | 쥐약(1000G) 외엔 가격 정보가 문서에 없어서 전부 `planned_stock` |
| 레시피 실제 습득 경로 (어떤 NPC가 몇 호감도에 주는지, 서점 가격) | `data/cooking/README.md` | 레시피 아이템(`recipe_*`)은 만들어뒀지만 지급 로직 없음 |
| NPC 스프라이트 애니메이션 프레임 매핑 | `scripts/npc/npc_sprite.gd` | 16x32 프레임 10개 중 항상 0번(정지 포즈)만 사용 — 상태별 프레임 정보가 없음 |
| 플레이어 스프라이트 | `scripts/player/player.gd` | 여전히 색깔 사각형 placeholder |
| 도감 전체 수집 보상 | `game_design/01_systems/collection.md` 원문에 "추후 결정"이라 명시 | 신호(`full_memento_collection_achieved`)만 발생, 보상 없음 |
| 장식품(가구 외 데코) | economy.md에 항목만 언급 | 카탈로그 없음 |
| 디버프/버프 아이템 실제 효과 실행 | 이샤의 디버프 해제템, 모카의 커피(이동속도+10%, 3분) | 데이터(이름/효과 설명)는 있지만 실제 상태이상/버프 시스템이 없어서 효과가 발동하지 않음 |
| 엔딩 연출 콘텐츠 | 어셔 동거 이후 반복 대사("아침 인사", "청소" 등), 엔딩 컷신 | 신호만 발생, 대사/연출 없음 |

---

## 4. 우선순위 제안 (갱신)

**완료됨** ~~1. Interactable 레이어 파싱 + 상호작용 프레임워크~~ / ~~조작(E, I)~~ / ~~최소 UI(HUD/인벤토리/상점)~~

**다음 순위 — 핵심 루프 마무리**
1. **요리대 UI** — 재료 2개 선택 + 쥐약 확인 팝업 (`cooking_station_interacted` 신호는 이미 옴, `RestaurantManager.cook_and_serve()`도 이미 있음)
2. **컴퓨터 UI** — 최소한 온라인샵(이미 죽은 NPC 상점의 온라인 구매)이라도 먼저, 이메일함은 이메일 시스템 본체가 필요
3. **책장(도감) UI** — `CollectionManager.register_memento()` 연결
4. **플레이어 스프라이트** (지금은 사각형이라 게임처럼 안 보임)
5. NPC 대화 트리거 — `NPCManager.get_daily_dialogue()`/`get_milestone_dialogue()`를 실제로 보여주는 대화창 (NPC를 향해 E?)
6. **이메일 시스템 본체** — 인박스 + 일반 NPC 이메일 발송 판단 로직 (스토커 이메일 로직은 이미 있음)

**콘텐츠 채우기 (스토리 작가/기획자 작업)**
7. NPC 일상 대사, 이메일 본문, 사칭 메일 12명분
8. 선물 아이템 카탈로그, 나머지 상점 가격, 레시피 습득 경로
9. NPC 애니메이션 프레임 매핑 (몇 번 프레임이 어떤 자세인지)

**오디오/추가 콘텐츠/폴리시**
10. 오디오 에셋 확보 + `AudioManager` 구현
11. 농사/축산/낚시 시스템 (기획 문서부터 필요)
12. 버프/디버프 상태이상 시스템
13. 도감 완주 보상, 엔딩 연출, 장식품

---

## 5. 참고 — 구현하며 임의로 해석/결정한 것들

기획 문서에 정확한 수치·규칙이 없어서 이번 구현 과정에서 직접 정한 것들. 나중에 다르게 바꾸고 싶으면 해당 파일만 고치면 된다.

- 스토커 이메일 초반/중반/후반 전환 기준: 살인 발생 횟수 (`horror_event_manager.gd`)
- 세이지 경고 대사 발동 조건: "비가 오고 있고 대기 중인 살해 대상이 있는 날" (스토커 위치 조건은 제외)
- NPC 알리바이 문장: 실제 스케줄 토큰을 장소 이름으로 번역해서 생성 (문서 예시 대사와 정확히 일치하지는 않음)
- 요리 가격: `economy.md` 표 값을 그대로 사용 (임의값 아님, 확정 데이터)
- 쥐약 외 상점 물품 가격: 문서에 없어서 전부 비워둠 (임의 숫자를 지어내지 않음)

자세한 근거는 각 `data/*/README.md`에 더 적혀 있다.

---

## 6. 오늘 진행 사항 (Godot 실행기 반입 이후)

Godot 실행기(`Godot_v4.7.1`)가 `Game` 폴더 안에 들어오면서, 그동안 실행 검증을 못 했던 코드를 처음으로 헤드리스(`--headless --path . --quit` 등)로 실제 부팅해봤다.

### 발견 및 수정한 버그 3개 (전부 이번 세션 이전부터 있었던, 아무도 실행해본 적 없는 버그)

1. **타일셋 `columns` 파싱 버그** (`home_map.gd`) — 헬퍼 함수 호출 순서 때문에 XML 파서 커서가 엉뚱한 태그로 이동한 뒤 `columns` 속성을 읽어서 항상 0으로 처리됨 → 타일 렌더링 시 `Modulo by zero` 에러가 맵 하나당 수백 개씩 발생.
2. **`class_name` 전역 클래스 캐시 문제** (`npc_world_manager.gd`, `inventory_screen.gd`) — Godot 에디터를 실제로 연 적이 없어서 `.godot/global_script_class_cache.cfg`가 새로 추가한 클래스(`NPCSprite`, `InventorySlot`)를 모름 → 이런 클래스를 타입으로 참조하는 코드가 파싱 실패. **캐시가 오래돼도 항상 동작하도록**, 새로 추가하는 크로스-스크립트 참조는 정적 타입 캐스팅 대신 `.call()`/`.connect("signal_name", ...)` 같은 이름 기반 런타임 호출로 통일했다.
3. **Spawn/Warp 좌표가 단 한 번도 실제로 로드된 적이 없었음** (`home_map.gd`, 가장 심각) — Tiled의 Spawn 지점은 자식 태그 없는 self-closing XML 태그(`<object .../>`)인데, Godot의 `XMLParser`는 이런 태그에 대해 종료 이벤트를 별도로 안 준다. 좌표 저장 로직이 그 종료 이벤트에서만 실행되도록 짜여 있어서, **플레이어 워프도 NPC 좌표 계산도 지금까지 항상 조용히 실패하고 있었다.** self-closing 태그는 시작 이벤트에서 바로 저장하도록 고쳤다.

수정 후 헤드리스로 부팅 + 게임 시간 실제로 수십 분 흘려봐도(`--quit-after` 프레임 수 조절) 에러 0개.

### Interactable 레이어 연결

사용자가 Tiled에 이미 만들어둔 오브젝트 이름을 그대로 스캔해서 확인:
- 모든 상점 내부: `cash_register` (+ `shop_id` 커스텀 프로퍼티, 예: `marr_shop`)
- `restaurant_interior.tmx`: `restaurant_cooking1/2/3`, `restaurant_open`
- `home_interior.tmx`: `sleep`(침대), `computer`, `collection`(책장)
- `cowshed_interior.tmx`: `door1~4_open` (아직 미연결, 축산 시스템 없음)

`WorldMap`에 `Interactable` 레이어 파싱(+ 커스텀 프로퍼티 지원)을 추가하고, `player.gd`에 E키 감지, `main.gd`에 오브젝트 이름 → 시스템 호출 라우팅을 만들었다. `data/shop/shops.json`의 상점 id를 내가 임의로 쓰던 이름(`general`, `farm`...) 대신 맵에 이미 있는 `shop_id` 프로퍼티 값(`marr_shop`, `flora_shop`...)으로 통일해서, 맵과 데이터가 이름으로 어긋날 일이 없게 했다.

### UI 3종 제작

`scenes/ui/`, `scripts/ui/`에 HUD / 인벤토리 화면 / 상점 화면을 만들고 `main.tscn`의 `UI`(CanvasLayer) 밑에 배치했다. 인벤토리에 아이템을 실제로 넣고, 상점을 실제로 열어서 목록이 채워지는 것까지 헤드리스로 확인했지만 **시각적으로 예쁜지는 확인 못 했다** (아래 7번 참고).

---

## 7. 테스트 방법

1. `Godot_v4.7.1-stable_win64.exe` 실행
2. 프로젝트 매니저에서 "가져오기(Import)" → `Game` 폴더의 `project.godot` 선택 → 열기
3. 에디터 상단 **▶ (재생)** 버튼 클릭 (또는 F5) — `main.tscn`이 메인 씬으로 지정돼 있어서 바로 실행됨
4. 조작: **WASD** 이동 · **E** 상호작용(계산대/요리대/레스토랑 오픈사인/침대/컴퓨터/책장) · **I** 인벤토리 열기/닫기 · **ESC** 열린 창 닫기

시작 위치는 Home 맵 연못 근처. 플레이어는 아직 색깔 사각형(스프라이트 미적용)이다.

**시작 골드 0G / 인벤토리 빈 상태 관련**: 상점에서 바로 구매를 테스트해보려면 골드가 필요하다. 에디터 하단 **디버거 탭 → Remote(원격)** 트리에서 실행 중인 `EconomyManager`/`InventoryManager` autoload 노드를 찾아 값을 직접 바꿔서 테스트할 수 있다.

**파일 위치 / 직접 수정하는 법**
- `scenes/ui/*.tscn` = 화면 생김새(배치/크기/색/텍스처). 에디터에서 더블클릭해 열면 2D 뷰에서 노드를 드래그하거나 우측 Inspector에서 속성을 바로 조정 가능. 좌표는 시각적으로 확인 안 하고 짠 값이라 어색할 수 있음 — 여기서 자유롭게 조정하면 됨.
- `scripts/ui/*.gd` = 화면의 동작(버튼을 누르면 무슨 일이 일어나는지). 에디터의 스크립트 탭이나 아무 텍스트 에디터로 수정 가능.
- 씬(.tscn)과 스크립트(.gd)가 분리돼 있어서, 생김새만 바꾸고 싶으면 .tscn만, 동작만 바꾸고 싶으면 .gd만 건드리면 됨.

**검증 상태**: 헤드리스 부팅 + 아이템을 실제로 넣고 인벤토리/상점 화면을 열어서 그리드/목록이 에러 없이 채워지는 것까지는 확인함. 배치가 보기 좋은지, 프레임 이미지가 잘 늘어나는지 같은 시각적인 부분은 못 봐서 직접 확인 필요.

---

## 8. 사용자가 직접 해야 하는 것

- **직접 플레이 테스트** — 위 "7. 테스트 방법"대로 실행해서 UI 배치/이동/상호작용이 실제로 괜찮은지 확인. 어색한 부분 알려주면 조정.
- **UI 비주얼 조정** — `scenes/ui/*.tscn`을 에디터에서 열어 위치/크기/색 등을 눈으로 보면서 다듬기 (내가 좌표를 보지 않고 짰기 때문).
- **콘텐츠 결정/작성** (3번 표 + `data/*/README.md` 참고):
  - NPC 일상 대사, 이메일 본문, 사칭 메일 12명분
  - 마르 잡화점 선물 아이템 목록, 나머지 상점(씨앗/도구/가구/커피/디버프템/가축/여물/미끼) 가격
  - 어떤 NPC가 어떤 레시피를 몇 호감도에 주는지 / 서점 가격
  - 도감 전체 수집 보상 내용
- **에셋 준비**:
  - 오디오 파일(bgm/sfx) — 프로젝트에 현재 하나도 없음
  - 플레이어 스프라이트
  - NPC 스프라이트의 프레임별(걷기/앉기/서기 등) 매핑 정보 — 지금은 항상 0번 프레임(정지)만 사용 중
- **기획 문서 추가 필요**: 농사/축산/낚시를 실제 미니게임으로 만들려면 그 규칙을 정하는 기획 문서(`farming.md`, `fishing.md` 등)부터 필요함 — 지금 `game_design/`에는 없음.
- **우선순위/방향 결정**: "4. 우선순위 제안"에서 다음에 뭘 먼저 만들지(요리 UI vs 컴퓨터 UI vs 도감 UI 등) 알려주면 그 순서로 진행.
