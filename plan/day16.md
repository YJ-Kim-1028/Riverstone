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

## 다음 세션 우선순위

1. **사용자가 `day15_test_cases.md` 보고 직접 테스트** (엔딩 3종, 상점 승계, 알리바이/소문 메일)
2. 테스트 중 나온 버그 수정
3. 백로그 중 우선순위 있는 것부터

## 확인 필요 (사용자)

- 체포 엔딩용 스폰 4개 (`arrest_scene_player/poli/usher/victim`) `book_interior.tmx`에 찍혔는지
- `usher_home_standing` 스폰이 `home_interior.tmx`/`_2.tmx`/`_3.tmx` 3개 파일 다 찍혔는지
- 총소리/나이프드롭 사운드 파일(`sfx_gunshot.mp3`, `sfx_knife_drop.mp3`) 넣었는지 (안 넣어도 에러 없이 스킵됨)
- **호감도 30 이벤트용 스폰 24개(NPC당 2개씩) - 아직 하나도 안 찍힘.** 안 찍힌 이벤트는 에러 없이 조용히 스킵되고 다음 기회에 재시도됨. 표는 아래 "호감도 30 이벤트" 섹션 참고

## 확실한 미완성 (TODO)

- 추억의 물건 아이콘 없음 — `inventory_manager.gd`의 `_register_memento_items()`가 `"icon": ""`로 하드코딩, `assets/img/`에 이미지 자체도 없음. 13장 그려서 경로 연결 필요
- 도감 특별 보상(`collection_reward()`) — CLAUDE.md에 이미 명시된 대로 의도적으로 빈 함수, 기획 미정
- 엔딩 크레딧 화면 없음 — 3종 엔딩 컷신 끝나면 바로 평소 플레이로 복귀, 별도 크레딧/타이틀 연출 없음
- 사칭 이메일(`impersonation_emails.json`)이 NPC별 개별 내용 없이 `default`/`default_2` 공용 문구만 있음(기획자 작성 예정 항목이라 의도된 상태)
- 괭이질 "다시 갈면 맨땅으로 되돌리기" 기능 — 예전 버그(의도치 않게 되돌아감)는 고쳐졌고 지금은 이미 갈아둔 빈 땅에 괭이질하면 그냥 무시됨. 되돌리기 자체를 기능으로 원하는지 사용자 확인 필요

## 호감도 30 이벤트 (heart_event_30)

사용자 지시(2026-08-24) - "모든 NPC가 호감도 30쯤에 이벤트가 있으면 좋겠어... 컷씬 + 이벤트 -> 스듀식으로". 기존 `affection_events`(가장 빠른 게 60~80대)와 별개의 신규 필드/시스템. 폴리는 비중이 큰 NPC라 제외(사용자 지시), 나머지 12명 전부 적용.

### 트리거 조건 (`main.gd`의 `_maybe_trigger_heart_event(map_id)`, 맵 진입마다 자동 검사)

맵을 새로 불러올 때마다(`_load_map()` 끝에서 호출) 살아있는 NPC 전원을 순회하며 아래를 전부 만족하는 첫 NPC 하나만 트리거한다(한 번에 하나, 나머지는 다음 맵 진입 때 재검사):

1. NPC가 살아있음
2. 그 NPC json에 `heart_event_30` 필드가 존재
3. `NPCManager.has_shown_heart_event()`로 아직 이 이벤트를 본 적 없음(1회성, 세이브에 기록됨)
4. 호감도 ≥ 30
5. `NPCManager.get_current_schedule_state(npc_id) == anchor_state` - "지금 이 시간대엔 이 NPC가 정말 근무/활동 중인가"를 확인하는 시간대 필터. 로시(비 오는 날만 등장)나 마린(평일 저녁 `plaza5_standing`만 해당, 주말 스케줄엔 그 시간에 이 상태가 없음)처럼 항상 뜨지 않는 NPC는 자연스럽게 그 조건이 맞는 순간까지 대기하게 됨
6. `anchor_state`가 실제로 가리키는 맵(`NPCManager.resolve_state_position()`)이 방금 플레이어가 들어온 맵과 일치
7. 다른 컷신(살인 발견/엔딩/공범 메일 대기) 진행 중이 아님, 이미 다른 30 이벤트 재생 중도 아님

전부 만족하면 **E 키 없이 자동으로** 컷신이 시작된다.

### 재생 흐름 (`_play_heart_event()`)

- 데이터에 `scene_map_id`가 없으면: NPC의 평소 근무 위치가 곧 씬 장소(대부분의 NPC 해당)
- `scene_map_id`가 anchor 위치의 실제 맵과 다르면(벨제/플로라만 해당 - "같이 나가자" 연출): `lead_out_lines`를 먼저 보여준 뒤(평소처럼 밝은 화면에서), 페이드아웃 → `_load_map()`으로 목적지 맵 이동 → 이어서 아래 공통 흐름
- (공통) 화면이 까만 동안 플레이어를 `player_spawn` 위치로, NPC 분신(임시 복제 스프라이트, 실제 NPC는 그동안 숨김 처리)을 `npc_spawn` 위치로 배치
- 페이드인 → 대사 재생 (`emote` 필드가 있으면 대사 열리기 0.6초 전에 말풍선 이모트 먼저 표시 - 세이지만 해당)
- 페이드아웃 → 분신 제거, 숨겨뒀던 실제 NPC 스프라이트 복원 → 페이드인 → 완료 처리(재발동 안 함)
- `npc_spawn`/`player_spawn` 중 하나라도 tmx에 없으면(아직 안 찍었으면) 아무 일도 안 일어나고 **에러 없이 조용히 스킵**됨

### 필요한 스폰 지점 (사용자가 직접 tmx에 배치, 이름 그대로 정확히)

| NPC | npc_spawn | player_spawn | 맵 파일 | 비고 |
|---|---|---|---|---|
| 벨제 | `belje_heart_npc` | `belje_heart_player` | `plaza2.tmx` | 목장 정문 앞 바깥쪽. 리드아웃 대사는 원래 근무지(pasture_interior)에서 뜸 |
| 플로라 | `flora_heart_npc` | `flora_heart_player` | `plaza2.tmx` | 집 앞 텃밭 자리. 리드아웃 대사는 원래 근무지(farm_interior)에서 뜸 |
| 이샤 | `isha_heart_npc` | `isha_heart_player` | `hospital_interior.tmx` | |
| 라마 | `lama_heart_npc` | `lama_heart_player` | `temple_interior.tmx` | |
| 마르 | `marr_heart_npc` | `marr_heart_player` | `general_interior.tmx` | |
| 모카 | `mocha_heart_npc` | `mocha_heart_player` | `cafe_interior.tmx` | |
| 로시 | `roshi_heart_npc` | `roshi_heart_player` | `fish_interior.tmx` | 비 오는 날(평일) 또는 주말에만 트리거 가능 |
| 세이지 | `sage_heart_npc` | `sage_heart_player` | `shrine_interior.tmx` | |
| 셰퍼드 | `shepherd_heart_npc` | `shepherd_heart_player` | `pasture_interior.tmx` | |
| 어셔 | `usher_heart_npc` | `usher_heart_player` | `book_interior.tmx` | |
| 우디 | `woody_heart_npc` | `woody_heart_player` | `furniture_interior.tmx` | |
| 마린 | `marin_heart_npc` | `marin_heart_player` | `plaza5.tmx` | 기존 `plaza5_standing` 근처. 평일 18시대만 트리거 가능(주말 스케줄엔 없음) |

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
