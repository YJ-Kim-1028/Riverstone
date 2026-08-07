# 공포 시스템 데이터 (`data/horror/`)

`MurderManager`(`scripts/autoload/murder_manager.gd`)와 `HorrorEventManager`(`scripts/autoload/horror_event_manager.gd`)가 읽는다. `02_horror/*.md` 4개 문서와 `01_systems/ending.md`(진실/체포/공범 엔딩)를 기반으로 한다.

## 구현한 것

**`MurderManager`**
* 호감도 120을 처음 넘은 순서대로 대기열을 쌓고(`NPCManager.murder_candidate_registered`), 매일 오후 10시(`TimeManager.minute_passed`)에 murder_system.md의 조건을 그대로 검사한다: 비가 오는가, 대기열의 다음 대상이 살아있는가, **플레이어·스토커·피해자 세 명 모두 서로 다른 맵에 있는가**(`NPCManager.get_npc_world_position()`으로 계산). 조건이 안 맞으면 그날은 넘어가고 다음 날 다시 검사한다.
* 대기 중인 대상이 있는 한 `WeatherManager.set_murder_pending(true)`를 계속 걸어둬서, 지난번에 만든 "살인 대기 중이면 3일 이내 강제 비" 규칙과 자동으로 연결된다.
* 살인이 일어나면 그 순간 살아있는 모든 NPC의 스케줄 상태를 스냅샷으로 저장해둔다 — `describe_alibi(npc_id, 사건번호)`가 여기서 "오후 10시에는 OO에 있었다고 말한다"를 만들어낸다. 문서의 예시 대사(이샤/셰퍼드/로시)는 지금 만들어둔 `schedule.json` 데이터와 정확히 들어맞지 않아서(문서가 나중에 확정된 스케줄과 별개로 쓰인 예시로 보임) 그대로 베끼지 않고, 실제 스케줄 데이터를 장소 이름으로 번역하는 방식으로 구현했다.
* "피해자의 집"이라는 구체적인 맵이 실제로 없다(04_locations에 NPC 개인 주거 공간이 없음) — 그래서 시체 발견 장소는 `"피해자의 집"`이라는 문자열로만 남기고, 실제로 피해자/스토커를 그 맵으로 "이동"시키는 처리는 하지 않았다. 어차피 사망 순간 `NPCWorldManager`가 화면에서 지워버리므로 실질적인 차이는 없다.

**엔딩 3종 (`ending.md`)**
* **진실 엔딩** — 플레이어가 독약으로 스토커(어셔) 본인을 죽이면 즉시 발동. 이후 살인/스토커 이메일 전부 중단.
* **체포 엔딩** — 대기열에는 원래 최대 2명(실제 희생자)까지가 아니라 **3명까지** 등록되도록 바꿨다. 2명이 죽은 뒤 3번째 대상에 대해서도 여느 때처럼 비/오후10시/맵 분리 조건이 충족되면, 실제로 죽이는 대신 **경찰이 개입해 3번째 대상은 살고 스토커가 그 자리에서 자결**한다(`usher_death_method = "self_killed"`). 이 부분은 `NPCManager.is_murder_candidate()`가 원래 "이미 1명만 죽은 경우"로 후보 등록을 막고 있어서 구조적으로 불가능했는데, ending.md를 반영하며 그 제한을 풀고 대신 `MurderManager`가 대기열 길이(최대 3)로 캡을 관리하도록 옮겼다.
* **공범 엔딩** — 플레이어의 독살 대상이 스토커가 아니라 무고한 NPC일 경우. 체포→위증→석방→동거 플래그를 전부 세운다.
* 세 엔딩은 `MurderManager.get_achieved_ending()`(`""`/`"truth"`/`"arrest"`/`"accomplice"`)으로 하나만 기록되며, 하나라도 달성되면 이후 살인 진행 자체를 멈춰서 "엔딩 중복 달성 불가능" 규칙을 지킨다. 마을 생활 콘텐츠(요리/상점/호감도 등) 자체는 계속 이용 가능 — 애초에 그쪽 시스템들은 엔딩 여부를 신경 쓰지 않게 만들어져 있다.

**`HorrorEventManager`**
* 첫 살인 이후 매일 밤(`TimeManager.night_events_enabled`, 22시) 플레이어가 `home_interior`에 있으면 30% 확률로 노크 이벤트.
* 세이지의 경고 대사(`get_sage_warning_lines()`) — "살인 조건을 충족하는 날"을 "비가 오고 있고 아직 처리 안 된 대상이 있는 날"로 해석했다. 스토커의 위치까지는 세이지가 알 방법이 없어서 그 조건은 제외했다.
* NPC 사망 다음날 사망자 명의 이메일(`impersonation_email_ready`) — `data/horror/impersonation_emails.json`에서 내용을 가져온다.

## 임의로 해석한 부분 (문서에 정확한 규칙이 없던 곳)

* **스토커 이메일 초반/중반/후반 전환 시점** — `stalker.md`는 톤이 3단계로 바뀐다고만 하고 언제 바뀌는지는 안 정해뒀다. 스토커가 실제로 저지른 살인 수(0/1/2)를 기준으로 삼았다 (`HorrorEventManager.get_stalker_email_stage()`). 다른 기준(예: 날짜, 어셔와의 호감도)이 낫다고 판단되면 이 함수만 바꾸면 된다.
* **"살인 조건을 충족하는 날"(세이지)** — 위에서 설명한 대로 스토커 위치 조건은 제외.

## 아직 못 채운 것

* `data/horror/impersonation_emails.json` — email.md에 예시가 딱 하나(플로라)뿐이라 나머지 12명은 비어있다. 실제로 그 NPC가 죽었을 때 어떤 말투로 사칭 메일을 보낼지는 스토리 작가가 채워야 할 부분.
* 실제 이메일함 UI, 초상화 회색 처리, 레스토랑 액자 붉게 변하는 연출, 노크 소리 재생, 엔딩 컷신/크레딧 — 전부 화면/오디오 쪽이라 로직(신호 발생)까지만 만들고 실제 표현은 안 만들었다. `NPCManager.npc_died`, `HorrorEventManager.knock_event_triggered`, `impersonation_email_ready`, `MurderManager.truth_ending_triggered`/`arrest_ending_triggered`/`accomplice_ending_triggered` 신호를 구독하면 된다.
