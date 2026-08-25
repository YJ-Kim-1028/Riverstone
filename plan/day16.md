# Day 16

day15 후반 세션에서 이어짐(day15.md엔 반영 안 된 내용 - 아래가 최신).

## 이번 세션 진행 내용

- event_invite 메일 제목 중복 수정
- 2차 살인 이후: 마르 지목 소문(`suspicion_talk_2`, 8명) + 알리바이 리마인더 메일(벨제/모카/셰퍼드/어셔)
- 독약 살해: 서빙 당일 안 죽고 다음날 사망 처리되도록 변경
- **엔딩 3종 컷신 완성** (진실/공범/체포) - 자세한 흐름은 `data/horror/endings.json` + `main.gd`의 `_play_*_ending_sequence()` 참고
- 공범 엔딩: 컷신 중단 후 재접속해도 이어보기 되는 안전장치
- 공범 엔딩 이후 어셔 저녁 스케줄(집으로 "퇴근", 집 레벨 1/2/3 대응)
- 상점 승계 버그 수정 - 벨제/셰퍼드, 마린/로시 중 실제 운영자(벨제/마린)와 보조(셰퍼드/로시) 방향 헷갈려서 상점이 비던 문제
- 테스트 케이스 문서 작성: `plan/day15_test_cases.md`
- 마린/로시 daily 대사에 기존 고티어(축구 미련/죄책감) 소재를 low/mid 티어로 일부 재배치
- **호감도 30 이벤트(`heart_event_30`) 시스템 신규 구현** - 스듀식 컷신, 13명 중 폴리 제외 12명 적용. 자세한 내용은 아래 "확인 필요"와 대사집 참고
- **요청함(퀘스트) 시스템 신규 구현** (2026-08-25, 별도 세션) - 컴퓨터 메일함에 수신함/발신함/초대내역과 분리된 "요청함" 탭 추가. `data/requests/requests.json`(고정 튜토리얼 요청 11개: 마을 인사/낚싯대/수입/작물 3종/축산 2종/생선 3종/서빙) + `data/requests/recurring_templates.json`(2~3일마다 NPC 2명이 선호 재료 배달 요청, 실제 인벤토리 소모) + 가구 배달 요청(10일차부터 희귀 확률). 반복/가구 요청만 4일 기한 있음(고정 요청은 기한 없음). 구현: `email_manager.gd`(objective_type: total_income/lifetime_item_count/lifetime_dishes_served/deliver_item/greet_all_npcs), `mail_list_panel.gd`/`mail_detail_panel.gd`(완료 버튼, 보상 표시, 만료 회색 처리, 진행률 문구)
- **추억의 물건 마일스톤 놓침 방지 안전장치** (2026-08-25) - 호감도 100 대사(추억의 물건)가 3일 이상 대화로 소비 안 되면 그 NPC가 "줄 게 있다"는 메일을 1회만 보냄(`npc_manager.gd`의 `memento_reminder_ready` 신호, NPC 13명 전원 `emails.memento_reminder` 추가). 도감 완성 보상 논의 중 나온 파생 기능
- **도감 완성 보상 방향 확정** (2026-08-25, 미구현) - "추억의 물건 13개 다 모으면 죽은 NPC(피해자 한정, 어셔 제외) 한 명 부활" - 엔딩 이후 지급, 부활한 NPC는 호감도 0/사건 기억 없이 재시작. 남은 결정: (1) 3개 엔딩 전부 대상인지 특정 엔딩 한정인지, (2) 2명 사망 시 부활 대상을 플레이어가 고르는 UI. `collection_reward()`는 아직 빈 함수로 유지 중

## 다음 세션 우선순위 (2026-08-25 갱신 - 스폰/아이콘 준비 다 끝나서 실질적으로 테스트만 남음)

1. **사용자가 직접 플레이 테스트** (`day15_test_cases.md` 기준 + 호감도 30 이벤트 12명 전부 - 이제 준비가 다 끝났으니 이것도 같이 확인). Claude Code는 게임 창을 직접 조작할 수 있는 도구가 없어서 이 부분은 대신할 수 없음
2. 테스트 중 나온 버그 수정
3. 백로그 중 우선순위 있는 것부터

## 확인 필요 (사용자) — 2026-08-25 전부 확인 완료

- ~~체포 엔딩용 스폰 4개~~ - `book_interior.tmx`에 전부 있음
- ~~`usher_home_standing` 스폰~~ - `home_interior.tmx`/`_2.tmx`/`_3.tmx` 3개 다 있음
- ~~총소리/나이프드롭 사운드 파일~~ - `assets/audio/sfx/`에 둘 다 있음
- ~~호감도 30 이벤트용 스폰~~ - 아래 "필요한 스폰 지점" 표 기준으로 전부 찍혀있음(사용자가 직접 작성 완료, 스폰 위치 관련 세부 조정도 이번 세션에 같이 반영함)

## 확실한 미완성 (TODO)

- ~~추억의 물건 아이콘 없음~~ — 2026-08-25 완료: 사용자가 `assets/icon/memento.png`(16x16 13칸 한 줄, 벨제/플로라/이샤/라마/마린/마르/모카/폴리/로시/세이지/셰퍼드/어셔/우디 순) 직접 그림. `inventory_manager.gd`의 `_register_memento_items()`에 `MEMENTO_ICON_INDEX` 매핑으로 연결(인벤토리/장비창/우편 등 `get_item_icon_texture()` 쓰는 곳 전부 자동 적용). 도감 화면(`collection_screen.gd`)도 예전엔 "아이콘 없어서 슬롯 배경만" 쓰던 걸 레시피처럼 실제 그림 표시하도록 같이 수정
- 도감 특별 보상(`collection_reward()`) — CLAUDE.md에 이미 명시된 대로 의도적으로 빈 함수, 기획 미정
- 엔딩 크레딧 화면 없음 — 3종 엔딩 컷신 끝나면 바로 평소 플레이로 복귀, 별도 크레딧/타이틀 연출 없음
- 사칭 이메일(`impersonation_emails.json`)이 NPC별 개별 내용 없이 `default`/`default_2` 공용 문구만 있음(기획자 작성 예정 항목이라 의도된 상태)
- ~~괭이질 "다시 갈면 맨땅으로 되돌리기" 기능~~ — 2026-08-25 재확인: 이미 구현/완료됨(`farming_manager.gd`의 `perform_untill()` + `main.gd`의 `"untill"` 분기). 갈아둔 빈 땅에 괭이 다시 쓰면 흙 스프라이트가 지워지고, `Farmable`은 순수 데이터 레이어라 밑에 깔린 `Ground` 레이어(잔디)가 그대로 드러나 원래 풀밭으로도 자연히 복귀함. 이 TODO 문구는 stale이었음

## 호감도 30 이벤트 (heart_event_30)

사용자 지시(2026-08-24) - "모든 NPC가 호감도 30쯤에 이벤트가 있으면 좋겠어... 컷씬 + 이벤트 -> 스듀식으로". 기존 `affection_events`(가장 빠른 게 60~80대)와 별개의 신규 필드/시스템. 폴리는 비중이 큰 NPC라 제외(사용자 지시), 나머지 12명 전부 적용.

### 트리거 조건 (`main.gd`의 `_find_matching_heart_event(map_id)`)

맵을 새로 불러올 때마다 살아있는 NPC 전원을 순회하며 아래를 전부 만족하는 첫 NPC 하나만 매칭한다(한 번에 하나, 나머지는 다음 맵 진입 때 재검사):

1. NPC가 살아있음
2. 그 NPC json에 `heart_event_30` 필드가 존재
3. `NPCManager.has_shown_heart_event()`로 아직 이 이벤트를 본 적 없음(1회성, 세이브에 기록됨)
4. 호감도 ≥ 30
5. `NPCManager.get_current_schedule_state(npc_id) == anchor_state` - "지금 이 시간대엔 이 NPC가 정말 근무/활동 중인가"를 확인하는 시간대 필터. 로시(비 오는 날만 등장)처럼 항상 뜨지 않는 NPC는 자연스럽게 그 조건이 맞는 순간까지 대기하게 됨
6. `anchor_state`가 실제로 가리키는 맵(`NPCManager.resolve_state_position()`)이 방금 플레이어가 들어온 맵과 일치
7. 다른 컷신(살인 발견/엔딩/공범 메일 대기) 진행 중이 아님, 이미 다른 30 이벤트 재생 중도 아님

매칭되면 **E 키 없이 자동으로** 컷신이 시작된다. 매칭 판정 자체는 `_prepare_heart_event()`(비-이동형, 암전 중)와 `_maybe_trigger_heart_event()`(이동형 폴백, 화면 밝아진 뒤) 둘 다 `_find_matching_heart_event()`를 공유해서 쓴다.

### 재생 흐름 - 두 갈래(2026-08-25 재구성)

**비-이동형(대부분, `scene_map_id` 없거나 anchor 위치와 같음)** - `_prepare_heart_event()` → `_run_pending_heart_event()`:
- `_load_map()`이 그 맵 자체의 입장 페이드아웃 직후, **아직 화면이 까만 동안** NPC 숨김 + 분신을 `npc_spawn`에 미리 배치해둔다(사용자 지시, 2026-08-25 - "들어갈 때 페이드에서 이미 다 있어야지, 들어가고 나서 또 페이드하는 게 아니라")
- 그 상태로 `_load_map()`의 원래 페이드인이 진행 → 화면이 밝아지는 순간 이미 분신이 그 자리에 서있는 것처럼 보임
- 플레이어는 문에서 `player_spawn`까지 **`player.walk_to()`로 직접 걸어감**(암전 없이, 화면이 보이는 채로 - 사용자 지시 2026-08-25)
- 도착하면 대사 재생 (`emote` 필드가 있으면 0.6초 먼저 말풍선 - 세이지만 해당)
- 페이드아웃 → 분신 제거, 실제 NPC 복원 → 페이드인 → 완료 처리(재발동 안 함)
- **주의**: `npc_spawn`이 그 NPC의 실제 평소 위치(anchor_state 스폰)와 다르면, 분신 배치 자체는 암전 중이라 안 보이지만 그 이후 플레이어가 걸어다니는 동안 "원래 자리엔 없고 다른 자리에 서있다"는 게 보임 - 위 스폰 표에서 라마/세이지/로시처럼 anchor 스폰을 그대로 재사용한 경우는 애초에 문제 없고, 마르/이샤/모카/셰퍼드/어셔/우디/마린처럼 전용 `_heart_npc` 스폰을 쓰는 경우는 그 위치가 실제로 자연스러운 곳인지(같은 방/건물 안 등) 확인 필요

**이동형(벨제/플로라만, `scene_map_id`가 anchor 위치의 실제 맵과 다름 - "같이 나가자" 연출)** - `_play_heart_event()`:
- `lead_out_lines`를 원래 근무지에서 먼저 보여줌(평소처럼 밝은 화면에서)
- 페이드아웃 → `_load_map()`으로 목적지 맵 이동 → **아직 화면이 까만 동안** 분신을 `npc_spawn`에 배치 → 페이드인
- 이후 흐름은 비-이동형과 동일(대사 → 페이드아웃 → 원복 → 페이드인)

`npc_spawn`/`player_spawn` 중 하나라도 tmx에 없으면(아직 안 찍었으면) 아무 일도 안 일어나고 **에러 없이 조용히 스킵**됨(다음 기회에 재시도)

### 필요한 스폰 지점 (사용자가 직접 tmx에 배치, 이름 그대로 정확히)

| NPC | npc_spawn | player_spawn | 맵 파일 | 비고 |
|---|---|---|---|---|
| 벨제 | `belje_heart_npc` | `belje_heart_player` | `plaza2.tmx` | 목장 정문 앞 바깥쪽. 리드아웃 대사는 원래 근무지(pasture_interior)에서 뜸 |
| 플로라 | `flora_heart_npc` | `flora_heart_player` | `plaza2.tmx` | 집 앞 텃밭 자리. 리드아웃 대사는 원래 근무지(farm_interior)에서 뜸 |
| 이샤 | `isha_heart_npc` | `isha_heart_player` | `hospital_interior.tmx` | |
| 라마 | ~~`lama_heart_npc`~~ → `temple_sitting`(기존 스폰 재사용, 2026-08-25) | `lama_heart_player` | `temple_interior.tmx` | npc_spawn만 필요, player_spawn은 여전히 새로 찍어야 함 |
| 마르 | `marr_heart_npc` | `marr_heart_player` | `general_interior.tmx` | |
| 모카 | `mocha_heart_npc` | `mocha_heart_player` | `cafe_interior.tmx` | |
| 로시 | ~~`roshi_heart_npc`~~ → `fish_standing`(기존 스폰 재사용, 2026-08-25) | `roshi_heart_player` | `plaza3.tmx` (표 원래 기재였던 `fish_interior.tmx`는 오기 - `fish_sitting` 스폰 자체가 plaza3에 있음) | 비 오는 날(평일) 또는 주말에만 트리거 가능. player_spawn(`roshi_heart_player`)은 `plaza3.tmx`에 찍어야 함 |
| 세이지 | ~~`sage_heart_npc`~~ → `shrine_sitting`(기존 스폰 재사용, 2026-08-25) | `sage_heart_player` | `shrine_interior.tmx` | player_spawn만 새로 찍으면 됨 |
| 셰퍼드 | `shepherd_heart_npc` | `shepherd_heart_player` | `pasture_interior.tmx` | |
| 어셔 | `usher_heart_npc` | `usher_heart_player` | `book_interior.tmx` | |
| 우디 | `woody_heart_npc` | `woody_heart_player` | `furniture_interior.tmx` | |
| 마린 | `marin_heart_npc`(기존 그대로 유지, 재사용 아님) | `marin_heart_player` | `fish_interior.tmx` (plaza5에서 fish_interior로 트리거 자체를 옮김) | anchor_state를 `plaza5_standing`→`fish_working`으로 변경 - 평일 09~18시/21시 이후 + 주말 21시 이후로 트리거 가능 범위가 넓어짐(예전엔 평일 18시대만). npc_spawn/player_spawn 둘 다 `fish_interior.tmx`에 찍혀 있음(확인 완료) |

### 대사 파일 위치

전부 `data/npc/<id>.json`의 `heart_event_30.lines` 필드 - 직접 그 파일에서 수정하면 됨.

| NPC | 파일:줄 |
|---|---|
| 벨제 | `data/npc/belje.json:72` |
| 플로라 | `data/npc/flora.json:69` |
| 이샤 | `data/npc/isha.json:69` |
| 라마 | `data/npc/lama.json:68` |
| 마르 | `data/npc/marr.json:67` |
| 모카 | `data/npc/mocha.json:41` |
| 로시 | `data/npc/roshi.json:64` |
| 세이지 | `data/npc/sage.json:64` |
| 셰퍼드 | `data/npc/shepherd.json:70` |
| 어셔 | `data/npc/usher.json:67` |
| 우디 | `data/npc/woody.json:72` |
| 마린 | `data/npc/marin.json:64` |

## 백로그 (계속 이월)

- 살인 씬 재테스트 (이번 테스트 라운드에서 같이 확인될 듯)
- `farming.md` 기획 문서
- 청소 콘텐츠(기획 문서 선행 필요)
- 장식품 카탈로그
- NPC 스케줄 랜덤 이동 재설계
- (필요시) 디버그용 "강제 비" 키 — 사용자가 테스트하다 필요하면 요청하기로 함
