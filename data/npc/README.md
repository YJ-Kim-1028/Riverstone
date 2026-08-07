# NPC 데이터 (`data/npc/*.json`)

`NPCManager` (scripts/autoload/npc_manager.gd)가 이 폴더의 `*.json`을 전부 읽어 NPC 정의로 사용한다.
`game_design/01_systems/npc.md`, `game_design/03_npcs/*.md`, `game_design/03_npcs/schedule.md`를 기반으로 이미 채워져 있는 필드와, 스토리 작성 시 채워야 할 필드가 섞여 있다.

## 이미 채워진 필드 (기획 문서 그대로)

* `id`, `name`, `name_en`, `gender`, `age`, `job`, `npc_type`(`normal`/`story`/`stalker`), `can_die`, `is_stalker`
* `personality`, `preferred_food`, `disliked_food`, `special_notes`
* `memento_item` — 호감도 100 추억의 물건과 그 대사(있는 경우)
* `portraits`, `sprite` — 실제 asset 경로 (일부 NPC는 표정 에셋이 없어 다른 표정 파일을 재사용하도록 되어 있음. 기획 문서와 동일)
* `schedule` — `mon_wed_thu` / `tue_fri` / `weekend` 3개 그룹. 각 그룹은 `visible_only_when_raining`(로시처럼 비 오는 날만 등장하는 경우 `true`)과 `entries`(`{"time","state"}` 목록, 시간순)로 구성. 월~금이 통째로 같은 스케줄인 NPC(로시/마린/마르)는 `mon_wed_thu`와 `tue_fri`에 동일한 내용을 넣어뒀다.
* `affection_events` — 호감도 임계값 이벤트. `lines`는 기획 문서에 실제로 적혀 있던 대사만 넣었고, 문서에 대사가 없는 이벤트는 `lines: []`로 비워둠(예: 우디 80).
* `story_dialogue` — 호감도가 아니라 특정 사건(독살 발각, 첫 살인 이후 등)에 묶인 대사. 해당 내용이 문서에 있는 마르/폴리/세이지만 채워져 있고 나머지는 `{}`.

## `affection_events` / `story_dialogue` — 대사는 "순서대로" 보여짐

이 두 필드의 `lines`는 랜덤 풀이 아니라 **하나로 이어지는 대사 시퀀스**다.
호감도 임계값을 넘거나(`affection_events`) 특정 사건이 트리거되면(`story_dialogue`), `lines` 배열을 처음부터 끝까지 순서대로 한 번 보여주면 된다. 여러 줄인 이유는 "랜덤으로 그중 하나"가 아니라 한 번의 대화 장면이 여러 문장으로 나뉘어 있기 때문이다.
`NPCManager.get_milestone_dialogue(npc_id, threshold)`가 이 배열을 그대로 반환한다.

## `dialogue.daily` — 대사는 "랜덤으로 하나" 보여짐

구조: `dialogue.daily.<mon_wed_thu|tue_fri|weekend>.<low|mid|high>` = **대사 묶음의 배열**.

```json
"low": [
    ["오늘 날씨 좋네.", "그치?"],
    ["요즘 장사가 잘 돼."]
]
```

* 바깥 배열 = 그날 나올 수 있는 잡담 후보들의 **풀(pool)**. 이 중 하나를 매번 랜덤으로 뽑는다.
* 안쪽 배열 = 그 한 번의 대화가 여러 줄일 경우, 화면에 **순서대로** 출력할 줄들.
* 즉 "안쪽은 순서대로, 바깥쪽은 랜덤"이다.

`NPCManager.get_daily_dialogue(npc_id)`가 이 규칙대로 동작한다:
1. 현재 요일 그룹(`get_weekday_group`)과 현재 호감도 구간(`get_affection_tier`)에 맞는 풀을 찾는다.
   구간 기준은 npc.md 예시를 따름 — `low` = 호감도 50 미만(일상 이야기), `mid` = 50~99(자기 이야기/타인 긍정), `high` = 100 이상(NPC 간 복잡한 관계 이야기).
2. 아무 NPC나 한 명이라도 죽었다면(`has_horror_mode_started()`), `dialogue.horror_conversation` 풀도 여기에 합쳐진다. (npc.md: "사망한 NPC 이외 NPC들의 대사 목록에 Horror_conversation이 추가된다")
3. 합쳐진 풀에서 무작위로 하나를 뽑되, 직전에 뽑았던 것과 같으면 다시 뽑아 **바로 연속으로 같은 대사가 반복되지 않게** 한다.
4. 뽑힌 대사 묶음(줄 배열)을 그대로 반환 — 호출하는 쪽(대사창 UI)이 이 배열을 순서대로 출력하면 된다.

`dialogue.horror_conversation`도 같은 모양(대사 묶음의 배열)으로 채우면 된다.

## `emails` — 카테고리별 의미와 트리거 방식

컴퓨터 이메일함 UI(수신함 목록)가 메일마다 "제목"을 따로 보여줘야 해서, 모든 이메일 항목은 `{"title": "...", "lines": [...]}` 형태다 (2026-07-30 결정 — 예전엔 `lines` 배열만 있었음).

`greeting` / `event_invite` / `gift_thanks`는 `dialogue.daily`와 동일하게 **랜덤 풀**(이메일 항목의 배열)이다. 이메일 시스템(`email.md`, `EmailManager`)이 "오늘 이 NPC가 이런 종류의 메일을 보내기로 했다"고 판단하면, 해당 카테고리 풀에서 하나를 랜덤으로 뽑아 보내면 된다.

```json
"greeting": [
    {"title": "안부 인사~", "lines": ["오늘 날씨 좋네.", "그치?"]},
    {"title": "요즘 어때?", "lines": ["요즘 장사가 잘 돼."]}
]
```

* `greeting` (안부 인사) — 특별한 이유 없이 보내는 일상적인 안부 메일. 가장 기본적인 필러(filler) 메일.
* `event_invite` (이벤트 초대) — NPC가 레스토랑 방문이나 특정 이벤트에 플레이어를 초대할 때 보내는 메일. "오늘은 이 NPC를 초대 손님으로 등장시킨다" 같은 시스템 판단이 트리거이며, 실제 문구는 이 풀에서 랜덤으로 고른다.
* `gift_thanks` (선물 감사) — 플레이어가 선물/요리를 준 이후, 그에 대한 반응으로 보내는 메일. 역시 문구 자체는 이 풀에서 랜덤으로 고르되, 트리거는 "최근 선물을 받았는가"라는 조건이다.

`story_progress`와 `special_day`는 반대로 **랜덤이 아니라 트리거 이름으로 찾아 쓰는 객체**다 (`affection_events`/`story_dialogue`와 같은 성격 — 특정 시점에 고정적으로 등장해야 하는 내용이라 무작위로 섞이면 안 된다). 값은 풀이 아니라 `{"title": "...", "lines": [...]}` 객체 하나다.

```json
"story_progress": {
    "first_murder_occurred": {"title": "...", "lines": ["...", "..."]},
    "second_murder_occurred": {"title": "...", "lines": ["...", "..."]}
},
"special_day": {
    "player_birthday": {"title": "...", "lines": ["...", "..."]}
}
```

* `story_progress` (스토리 진행) — 특정 스토리/공포 이벤트가 발생했을 때만 보내는 메일. 키 이름을 트리거 식별자로 쓰고, `lines`는 순서대로 보여줄 줄 배열.
* `special_day` (특별한 날 축하) — 특정 날짜/기념일에만 보내는 메일. 키 이름을 그 날 식별자로 쓴다. (아직 게임 내 캘린더/기념일 규칙이 없어서 `EmailManager`가 이 카테고리를 실제로 발송하지는 않음 - 규칙이 정해지면 연결 예정.)

현재 13명 전부 각 카테고리가 빈 배열/객체(`[]`/`{}`)라 이 문서의 모양과 무관하게 유효하다 - 실제로 채울 때 위 모양대로 채우면 됨.

## 호감도 증감 (`affection.md`)

* `talk(npc_id)` +1, `give_gift(npc_id)` +3, `send_email(npc_id)` +3
* `feed(npc_id, food_name)` — `food_name`을 해당 NPC의 `preferred_food`/`disliked_food`와 대조해서 자동으로 좋아하는 재료(+5) / 싫어하는 재료(-5) / 그 외 일반(+1)을 판정한다. 어떤 걸 좋아하고 싫어하는지 직접 판단해서 호출할 필요 없음.
* 범위는 항상 0~150으로 clamp. NPC가 사망하면(`is_alive() == false`) 이 함수들은 전부 아무 효과가 없다 — 기존 호감도는 그대로 유지되고 더 이상 오르내리지 않는다(`affection.md`의 "NPC 사망" 규칙).
* `affection_events`에 정의된 임계값을 처음 넘는 순간 자동으로 "완료 처리"되고 `affection_event_triggered(npc_id, threshold)` 신호가 발생한다. 임계값이 `memento`(추억의 물건) 타입이면 `memento_received(npc_id)`도 함께 발생한다. 한 번 완료된 이벤트는 호감도가 나중에 떨어져도 다시 취소되지 않는다.
* `has_completed_event(npc_id, threshold)` — 특정 임계값 이벤트가 이미 일어났는지 조회.

## NPCManager가 제공하는 것 / 제공하지 않는 것

`NPCManager`는 이 JSON을 로드하고 호감도(0~150) 증감, 사망 처리, 호감도 임계값 이벤트 완료 트래킹(추억의 물건 포함), 호감도 120 살해 대상 후보 등록(스토리 NPC·스토커 제외, 이미 죽은 NPC가 1명 이하일 때), 그리고 위에서 설명한 대사 선택 규칙(`get_milestone_dialogue`, `get_daily_dialogue`, `get_affection_tier`)까지 담당한다.
실제 대사창 UI, 이메일 발송 UI, 살인 실행 로직은 각각 UI 시스템 / `email.md` / `02_horror/murder_system.md` 구현 시 이 데이터와 `NPCManager`의 신호(`affection_changed`, `affection_event_triggered`, `memento_received`, `npc_died`, `murder_candidate_registered`)를 갖다 쓰면 된다.
