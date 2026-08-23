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

구조: `dialogue.daily.<월|화|수|목|금|토|일>.<low|mid|high>` = **대사 묶음의 배열**.
요일 키는 `TimeManager.get_weekday()`가 돌려주는 값 그대로(`"월"`/`"화"`/`"수"`/`"목"`/`"금"`/`"토"`/`"일"`) 7개 전부 따로 있다 - **스케줄(`schedule`)이 쓰는 `mon_wed_thu`/`tue_fri`/`weekend` 3그룹과는 다른 별개의 기준**이다(2026-08-12 사용자 지시 - 잡담이 3그룹으로 묶여 있으니 반복되는 느낌이라는 피드백. 스케줄은 여전히 3그룹 그대로 씀).

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
1. 현재 요일(`TimeManager.get_weekday()`)과 현재 호감도 구간(`get_affection_tier`)에 맞는 풀을 찾는다.
   구간 기준은 npc.md 예시를 따름 — `low` = 호감도 50 미만(일상 이야기), `mid` = 50~99(자기 이야기/타인 긍정), `high` = 100 이상(NPC 간 복잡한 관계 이야기).
2. 아무 NPC나 한 명이라도 죽었다면(`has_horror_mode_started()`), `dialogue.horror_conversation` 풀도 여기에 합쳐진다. (npc.md: "사망한 NPC 이외 NPC들의 대사 목록에 Horror_conversation이 추가된다")
3. 합쳐진 풀에서 무작위로 하나를 뽑되, 직전에 뽑았던 것과 같으면 다시 뽑아 **바로 연속으로 같은 대사가 반복되지 않게** 한다.
4. 뽑힌 대사 묶음(줄 배열)을 그대로 반환 — 호출하는 쪽(대사창 UI)이 이 배열을 순서대로 출력하면 된다.

### 대사 줄의 두 가지 모양 — 일반 줄 / 감정 지정 줄 / 선택지 줄

`dialogue.daily`(및 다른 `lines` 계열 필드)의 안쪽 배열 원소는 세 가지 중 하나다. `dialogue_screen.gd`가 타입을 보고 자동으로 분기한다.

1. **문자열** — 그냥 대사 한 줄. 초상화 감정은 자동으로 `default`(무표정) — 기쁜 대사는 반드시 `{"text","emotion":"happy"}`로 명시 태그해야 웃는 얼굴이 나온다(2026-08-12, 기본값을 happy→default로 변경).
   ```json
   "오늘 날씨 좋네."
   ```
2. **`{"text", "emotion"}` 객체** — 감정을 바꾸고 싶은 줄만 이 모양으로 감싼다. `emotion`은 `happy`/`sad`/`angry`/`default` 중 하나(해당 NPC에 그 표정 그림이 없으면 `portraits`에 정의된 대체 그림이 자동으로 쓰인다).
   ```json
   {"text": "...요즘 좀 힘들어.", "emotion": "sad"}
   ```
   대사 텍스트 안에 `{player_name}`을 쓰면 실제 플레이어 이름(`GameManager.player_name`)으로 치환된다 — NPC가 플레이어를 직접 이름으로 부르게 할 때 쓴다.
3. **`{"type": "choice", "options": [...]}` 객체** — 플레이어에게 선택지를 보여준다. 이 줄에 도달하면 자동 진행이 멈추고, 플레이어가 ▲▼로 옵션을 고르고 E로 확정한다. 각 `option`은:
   * `label` — 선택지에 보여줄 문구.
   * `affection` — 확정 시 호감도에 즉시 더해질 값(음수 가능, 생략하면 0). `NPCManager.apply_dialogue_choice()`가 적용한다.
   * `response` — 확정 직후 이어서 보여줄 줄 배열(위 1·2번과 같은 모양 재사용 가능). 그 NPC와의 대화가 계속 이어지는 것처럼 자연스럽게 연결된다.
   ```json
   [
       "오늘 뭐 하고 지냈어?",
       {
           "type": "choice",
           "options": [
               {"label": "그냥 쉬었어.", "affection": 0, "response": ["나도 그런 날 필요하지."]},
               {"label": "너 생각하면서 지냈어.", "affection": 2, "response": [{"text": "...그런 말은 좀 부끄럽잖아.", "emotion": "happy"}]},
               {"label": "딱히 기억 안 나.", "affection": -1, "response": [{"text": "그렇구나.", "emotion": "sad"}]}
           ]
       }
   ]
   ```
   선택지는 한 대화 묶음 안에 여러 번 나올 수도 있다 (선택 → 응답 → 또 다른 대사 → 다음 선택지, 식으로 이어붙이면 됨).

`dialogue.horror_conversation`도 같은 모양(대사 묶음의 배열)으로 채우면 된다.

## `dialogue.mail_reaction` — 플레이어가 보낸 메일을 언급하는 대사 (2026-08-15 추가)

플레이어가 컴퓨터에서 이 NPC에게 자유 작성 메일을 보내면(`EmailManager.compose_and_send`), 그 NPC와 다음에 대화할 때 오늘의 `dialogue.daily` 후보 풀에 `mail_reaction` 템플릿 하나가 추가로 섞여 들어간다(비 오는 날 `rain_conversation`이 섞이는 것과 같은 방식). 이게 랜덤으로 뽑히면 한 번만 나오고 사라진다(같은 메일을 반복해서 언급하지 않음). 다른 `lines` 계열 필드와 모양은 같지만, 문자열 안에 `"{player_mail_content}"`를 쓰면 플레이어가 실제로 쓴 메일 본문으로 치환된다.

```json
"mail_reaction": [
    ["'{player_mail_content}'라고 보냈더군. 그물 손질하다가 몇 번을 다시 읽었는지 몰라."]
]
```

**주의**: 13명 전부 "이게 뭐야?"처럼 똑같은 되묻기 반응으로 통일하지 말 것(2026-08-15 사용자 지적) — 각 NPC의 기존 화법/성격에 맞는 서로 다른 반응 장치를 쓴다(놀림/되새김/장난/방어/불안/분석/담담함 등, `personality` 필드 참고).

## 대사 작성 원칙 — 호감도로 드러나는 "결핍"

모든 NPC는 무조건 착하고 좋은 사람으로만 쓰지 않는다. 인생을 살면서 누구나 갖는 음침함/결핍(콤플렉스, 외로움, 죄책감, 못난 욕심 등)이 있고, 호감도가 올라갈수록(`mid`→`high`) 그게 조금씩 드러나야 한다 (2026-08-12 사용자 확정, 13명 전원 공통 원칙 — `personality`/`special_notes`에 이미 적힌 성격 결함을 daily 잡담에도 실제로 반영하라는 뜻).

**주의**: 이 결핍은 스토커/공포 세부 설정과는 별개다. 캐릭터 개인의 인간적인 결함(무능감, 죄책감, 외로움, 짝사랑 등)은 `dialogue.daily`의 `mid`/`high`에 자유롭게 써도 되지만, 스토커 정체나 살인 관련 암시는 여전히 `dialogue.horror_conversation`(첫 살인 이후에만 섞이는 풀) 몫이다 — 첫 살인 전까지 공포 요소를 눈치채게 해선 안 된다는 CLAUDE.md 규칙은 그대로 유지.

**쓰는 방식(실제 검증된 톤)**: 감정이나 결핍을 직접 문장으로 선언하지 않는다("나 사실 외로워", "눈치챘나?" 처럼 스스로 짚어주는 것 = 너무 노골적, 오글거림). 대신 사소한 사건을 관찰 → 자기한테 유리하게 과잉해석 → 스스로 김빼며 합리화하고 발 빼는 3단 구조처럼, **본인은 절대 인정 안 하는데 대사만 보면 다 보이는 방식**으로 쓴다. 대놓고 티 내는 행동 묘사(예: 한참 쳐다봤다)도 너무 노골적이라 피한다 — 결핍은 "말버릇처럼 반복되는 패턴"으로 드러나야 자연스럽다.

예시(폴리, 50대 독거 남성 경찰 — 카페 주인 모카에게 갖는 자각 없는 호감):
```json
"모카가 쿠키를 하나 더 얹어주더군. 서비스인가... 다른 손님한테도 다 그러나 모르겠어."
```
감정 단어가 한 번도 안 나오지만 반복되면 그 자체로 캐릭터성이 된다.

## 이메일 작성 시 주의 — "편지니까 이 말 하는 거야" 자기변명 남발 금지

이메일은 말로 못 하는 걸 편지로는 할 수 있다는 게 원칙이지만(위 "대사 작성 원칙" 참고), **그걸 매번 "직접 말하면 ~해서 이렇게 적어보네" 식으로 문장에 직접 설명하면 안 된다** — 폴리·벨제·이샤 이메일에서 이 표현이 반복돼서 사용자가 "이런 톤이 너무 많아"라고 지적함(2026-08-12). 편지라는 매체 자체가 그 효과를 이미 내니까, 왜 편지로 썼는지 매번 정당화하지 말고 그냥 하고 싶은 말을 쓰면 된다.

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
  * 항목에 `"requires_favorite_food": true`를 추가하면, 그 문구는 그 NPC가 실제로 `preferred_food`가 들어간 요리를 서빙받은 날에만 뽑힐 수 있다(`EmailManager._on_dish_served`가 `RestaurantManager.dish_served`를 듣고 매일 기록, `data/cooking/recipes.json`으로 만든 요리의 원재료를 `items.json`의 `base_material`로 역추적해 판정 — `CookingManager.cook()`/`NPCManager.get_food_preference_for_ingredients()` 참고). 태그가 없는 일반 문구는 항상 뽑힐 수 있다. "그 요리 맛있더라" 식으로 특정 메뉴/재료를 직접 언급하는 문구는 반드시 이 태그를 붙일 것 — 안 붙이면 실제로 그 요리를 낸 적이 없어도 뜬금없이 뽑힐 수 있다.
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

`{player_name}`은 이메일 `lines`에서도 쓸 수 있다(`mail_detail_panel.gd`가 `dialogue_screen.gd`와 동일하게 치환, 2026-08-12 추가).

### `story_progress`의 `player_arrival` 트리거 - 새 게임 첫날 환영 메일

`story_progress`는 원래 호러/스토리 이벤트 전용으로 정의됐지만, "플레이어가 마을에 처음 왔을 때 모든 NPC가 환영 메일을 보낸다"는 요청(2026-08-12)도 같은 트리거-키 방식(랜덤 아님, NPC당 한 번)이 정확히 들어맞아서 트리거 이름만 `"player_arrival"`로 추가했다. `EmailManager._is_story_trigger_active()`에서 항상 `true`를 반환하고, `title_screen.gd`가 캐릭터 생성 확정 직후 `EmailManager.send_arrival_emails()`를 호출해 새 게임 첫날 안에 바로 메일함에서 보이게 한다(이 기능 이전의 기존 세이브도 다음 날짜 변경 때 한 번 자연히 받는다). 왜 마을 문화인지/왜 다들 첫날부터 메일을 보내는지는 게임 내에서 설명하지 않기로 함(사용자 지시 - "그냥 게임 요소니까").

이 시점에 아직 다른 12명의 `player_arrival` 내용은 안 채워져 있음(폴리만 완료) - 각 NPC마다 "왜 낯선 사람에게 첫날부터 메일을 보내는지" 나름의 이유를 하나씩 붙여서 채울 것.

## 호감도 증감 (`affection.md`)

* `talk(npc_id)` +1, `give_gift(npc_id)` +3, `send_email(npc_id)` +3
* `feed(npc_id, food_name)` — `food_name`을 해당 NPC의 `preferred_food`/`disliked_food`와 대조해서 자동으로 좋아하는 재료(+5) / 싫어하는 재료(-5) / 그 외 일반(+1)을 판정한다. 어떤 걸 좋아하고 싫어하는지 직접 판단해서 호출할 필요 없음.
* 범위는 항상 0~150으로 clamp. NPC가 사망하면(`is_alive() == false`) 이 함수들은 전부 아무 효과가 없다 — 기존 호감도는 그대로 유지되고 더 이상 오르내리지 않는다(`affection.md`의 "NPC 사망" 규칙).
* `affection_events`에 정의된 임계값을 처음 넘는 순간 자동으로 "완료 처리"되고 `affection_event_triggered(npc_id, threshold)` 신호가 발생한다. 임계값이 `memento`(추억의 물건) 타입이면 `memento_received(npc_id)`도 함께 발생해서 `memento_<npc_id>` 아이템이 인벤토리에 자동으로 들어간다. `gift`(NPC가 플레이어에게 아이템을 선물, 예: 모카의 커피) 타입이면 이벤트에 `item_id` 필드가 있어야 하고, `npc_gift_item_triggered(npc_id, item_id)` 신호가 발생해서 해당 아이템이 인벤토리에 자동으로 들어간다. 한 번 완료된 이벤트는 호감도가 나중에 떨어져도 다시 취소되지 않는다.
* `has_completed_event(npc_id, threshold)` — 특정 임계값 이벤트가 이미 일어났는지 조회.

## NPCManager가 제공하는 것 / 제공하지 않는 것

`NPCManager`는 이 JSON을 로드하고 호감도(0~150) 증감, 사망 처리, 호감도 임계값 이벤트 완료 트래킹(추억의 물건 포함), 호감도 120 살해 대상 후보 등록(스토리 NPC·스토커 제외, 이미 죽은 NPC가 1명 이하일 때), 그리고 위에서 설명한 대사 선택 규칙(`get_milestone_dialogue`, `get_daily_dialogue`, `get_affection_tier`)까지 담당한다.
실제 대사창 UI, 이메일 발송 UI, 살인 실행 로직은 각각 UI 시스템 / `email.md` / `02_horror/murder_system.md` 구현 시 이 데이터와 `NPCManager`의 신호(`affection_changed`, `affection_event_triggered`, `memento_received`, `npc_died`, `murder_candidate_registered`)를 갖다 쓰면 된다.
