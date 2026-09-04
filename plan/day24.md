# Day 24

day23(HD 캐릭터 커스터마이징 파이프라인 완성, 황금 도구/안부 메일/레스토랑
자동 초대) 다음 세션.

## 일상 대사 반복 허용 (특수 대사만 하루 1회 제한)

- 기존: NPC와 한 번 대화하면(`NPCManager.talk()`가 `_talked_today`에 기록) 그날은
  더 이상 말을 걸 수 없었음(`npc_world_manager.gd`의 `get_nearest_talkable_npc()`가
  `has_talked_today()`로 아예 필터링) - 호감도 중복 방지가 목적이었는데, 부수
  효과로 일상 잡담도 하루 딱 한 번밖에 못 봤음.
- 사용자 지시(2026-09-05): "일상 대사는 같은 말 계속 걸어도 계속 똑같은
  패턴으로 나와도 될 거 같아... 그냥 호감도는 처음 1번만 올려주고, 대사는
  계속 보여주는 식. 단, 오늘 본 대사가 특수한 대사일경우 하루에 한번만."
- 구현: `NPCManager`에 새 필드 `_special_dialogue_shown_today`(npc_id -> bool)
  추가. `get_daily_dialogue()`가 호출될 때마다 기본값 `true`(특수 대사로 간주)로
  시작해서, 함수가 실제로 요일/호감도 잡담 로테이션(비/공포 대화, 메일 반응,
  세이지 운세 포함)까지 정상 도달했을 때만 맨 마지막에 `false`로 내림 - 그
  사이에 있는 조기 return 분기들(애도/알리바이, 용의자 소문, 호감도 마일스톤,
  세이지 전용 트리거 3종, 파트너 사망 반응)은 전부 일회성이라 손 안 대도
  기본값 `true`가 자연히 적용됨.
  - `has_special_dialogue_shown_today(npc_id)` getter 추가.
  - `npc_world_manager.gd`의 `get_nearest_talkable_npc()`가 필터 기준을
    `has_talked_today()` → `has_special_dialogue_shown_today()`로 교체(선물
    중 필터 우회하는 `ignore_talked_today` 파라미터는 그대로 유지, 의미만
    "특수 대사 봤어도 선물은 가능"으로 갱신).
  - `NPCManager.talk()`(호감도 하루 1회 제한)은 그대로 - 이 함수가 대화 자체를
    막는 게 아니라 애초에 재대화 자체는 이제 `get_nearest_talkable_npc()`
    통과 여부로만 결정되므로, `talk()`을 여러 번 불러도 두 번째부터는 그냥
    조용히 호감도만 안 오르고 넘어감.
  - 세이브 스키마에 `special_dialogue_shown_today` 필드 추가(NPC별 상태에),
    기존 세이브는 필드 없으면 기본 `false`(막힘 없음)로 폴백.
- **후속 수정**: 실전 테스트해보니 재대화할 때마다 랜덤 로테이션으로 다른
  잡담이 나와서 어색했음(사용자 지시 - "요일 대사 돌아가면서 보여주는 게
  아니라 그 날 보여주기로 지정된 대사를 계속 보여주는 게 나을 거 같아").
  `_daily_dialogue_cache`(npc_id -> 오늘 처음 뽑힌 최종 대사, 메일 반응/세이지
  운세 등 이미 붙은 것까지 포함) 추가 - `get_daily_dialogue()`가 일상 잡담
  분기에 도달하면 이 캐시부터 확인해서, 있으면 그대로 재생하고 없으면 새로
  뽑아서 캐시에 저장. `_on_day_changed()`에서 비움. 세이브에도 같이 저장(중간
  저장 후 재접속해도 같은 대사 유지).

## NPC 먹는 동작 구현 완료

- 13명 전원의 `Eating/south.gif`(6프레임, 사용자가 직접 제공) 처리 -
  `assets/npc/pixellab/build_eating_sheet.ps1` 신규 작성(원본 캔버스 크기가
  NPC마다 제각각 - 64x64/84x84/60x60 - 이라 가로 32px 중앙 정렬 + 세로 64px
  하단 정렬 크롭으로 일반화, 64px보다 작은 원본은 위쪽에 투명 패딩). 결과물은
  `assets/npc/sprite/<정상 시트 파일명에서 Sprite→Eating>.png`(예:
  `woodyEating.png`, 라마는 `ramaEating.png`, 모카는 `mokaEating.png` - 정상
  시트 파일명 표기가 NPC마다 달라서 npc_id로 못 유도하고 기존 sprite 경로를
  치환해서 재사용).
- `npc_sprite.gd`: `start_eating()`/`stop_eating()`/`is_eating()` 추가.
  `_apply_npc_id()`가 sprite_path를 치환해 이 시트를 같이 로드(없으면 조용히
  무시, 기존 앉은 정지 자세 유지). `_update_animation()`이 먹는 중이면 다른
  애니메이션보다 우선해서 6프레임 루프(EATING_FRAME_INTERVAL=0.35초 간격)를
  재생.
- `npc_world_manager.gd`: `RestaurantManager.dish_served` → `start_eating()`,
  `npc_departed` → `stop_eating()`(정상 종료든 서빙 전 퇴장이든 안전하게
  무시됨) 연결. 먹는 도중 맵을 나갔다 다시 들어오면(스프라이트 재생성) 좌석의
  `dish`가 아직 남아있으면 `start_eating()`을 다시 걸어 상태를 복원.
- `EATING_DURATION_MINUTES=30`(게임분=현실 30초) 동안 자동으로 재생되다가
  손님이 떠날 때 원래 모습으로 복귀.

## 배포 전/후 확인할 것

- [x] **NPC 먹는 동작** - 13명 전원(벨제/셰퍼드 포함) 사용자 확인 완료
  (2026-09-05). 벨제는 84x84 캔버스 크롭 오프셋 버그(모자 잘림) 수정 후 재확인.
- [x] 특수 대사(마일스톤/알리바이/세이지 트리거 등)를 본 날은 정말로 그 NPC와
  재대화가 막히는지, 반대로 일상 잡담만 본 날은 여러 번 계속 말 걸리는지 실전
  확인. **사용자 확인 완료(2026-09-05).**
- [x] 선물하기가 여전히 특수 대사를 본 뒤에도 막히지 않는지(`ignore_talked_today`
  경로) 재확인. **사용자 확인 완료(2026-09-05).**
- [x] 세이지 운세(하루 1회, `_fortune_offered_day`)는 일상 로테이션에 얹혀
  나가므로 재대화 자체는 막히지 않음 - 운세 자체가 두 번 안 나오는지 확인.
  버그 발견 및 수정(아래 섹션 참고) → **사용자 확인 완료(2026-09-05) - "운세
  이제 하루에 한번만 볼 수 있어".**

## 버그: 세이지 운세 중복 출력

- 사용자 리포트(2026-09-05): "운세 중복으로 나와".
- 원인: 일상 대사 캐싱(`_daily_dialogue_cache`, 위 섹션) 도입 때 세이지
  운세 제안+선택지를 캐시에 **같이** 구워 넣었음(`picked.append_array(fortune_lines)`
  한 뒤에 캐시 저장). 캐시는 "오늘 하루 같은 대사 반복"이 목적이라, 첫 대화에서
  운세가 한 번 붙어 캐시된 뒤로는 그날 세이지에게 다시 말 걸 때마다 캐시된
  배열(운세 포함)이 그대로 다시 재생돼 운세가 매번 나왔음.
- 수정: 캐시에는 일상 잡담 원본만 저장하고, 세이지 운세는 캐시 히트/미스와
  무관하게 매번 별도로 `_build_fortune_offer_lines()`를 호출해서 붙이도록
  분리. `_build_fortune_offer_lines()` 자체가 `_fortune_offered_day`로 하루
  1회만 실제 내용을 돌려주므로(이미 오늘 물어봤으면 빈 배열) 결과적으로
  운세는 오늘 첫 대화 때만 붙고, 재대화 때는 일상 잡담만 반복된다.

## 마르의 향수(perfume_somewhere_behind_you) - 선물 불가 + 셀프 사용

- 사용자 지시(2026-09-05): "마르가 호감도 선물로 준 향수는 아무에게도
  선물해서는 안되고 내가 뿌릴 수 있어야 하는데" → 이어서 "일회용도 아니고
  계속 사용할 수 있어야돼 사용한다고 없어지면 안 돼". 효과는 "일정 시간 동안
  금색 향 이펙트"로 사용자 확인.
- `data/items/items.json`: `category`를 `"gift"` → `"perfume"`으로 변경(NPC
  기프팅 흐름(main.gd `_npc_interact_prompt`/`_is_holding_gift`/
  `_on_interact_pressed`, `InventoryManager.give_gift`/`give_gift_from_hand`)이
  전부 `category=="gift"` 문자열 비교라 자동으로 선물 대상에서 빠짐). `slot`/
  `gift_affection` 필드는 더 이상 안 쓰여서 제거, `scent_color: "gold"`는
  이펙트 색으로 재사용.
- `inventory_manager.gd`: `CATEGORY_STACK_LIMITS`/`NON_DISCARDABLE_CATEGORIES`에
  `"perfume"` 추가(1개, 버릴 수 없음 - memento/record와 동일 취급). 새 함수
  `use_perfume(slot_index)` 추가 - `use_item()`과 같은 `item_used` 신호를
  쓰지만 아이템을 **소모하지 않는다**(사용자 지시).
- `equipment_panel.gd`: `_use_slot()`에 `category == "perfume"` 분기 추가 →
  `InventoryManager.use_perfume(index)` 호출(book과 동일 패턴, 우클릭).
- `player.gd`: npc_sprite.gd의 향수 파티클 시스템(SCENT_* 상수/궤도 애니메이션)을
  플레이어 쪽에 그대로 이식. `apply_scent(color_name)` 호출 시 게임 내 5시간
  (`SCENT_DURATION_MINUTES=300`, 사용자 지시로 60→300 조정) 동안 금색 꽃
  파티클 3개가 플레이어를 따라다니고, 다 쓰기 전에 또 뿌리면 남은 시간만
  갱신(스택 안 됨). `TimeManager.minute_passed`에 맞춰 카운트다운.
- `main.gd`: `_on_item_used()`에 `"perfume_somewhere_behind_you"` 분기 추가 →
  `player.apply_scent("gold")` + 안내 문구("좋은 향기가 나." - 사용자 지시로
  "은은한 향이 감돈다."에서 수정).
- **참고**: NPC가 선물로 준 음반(record_*)은 원래부터 `category: "record"`라
  (사용자가 별도로 우려한 "npc들이 호감도 선물로 준 음반들도 선물이 가능해서는
  안 돼"는) 애초에 위 기프팅 흐름을 못 타서 이미 선물 불가 상태였음 - 추가
  수정 불필요, 확인만 함.

## 보관함(상자) 화면 툴팁 누락 수정

- 사용자 리포트(2026-09-05): "보관함 상자에서는 툴팁이 안떠". 원인:
  아이템 이름/설명 툴팁은 화면마다 각자 구현하는 구조인데(engine 기본
  tooltip_text는 4배 확대 캔버스와 좌표계가 안 맞아서 안 씀 - equipment_panel.gd
  참고), `storage_screen.gd`/`storage_screen.tscn`에는 애초에 이 Tooltip
  노드/로직 자체가 없었음(장비창(TAB)에만 있던 기능, 보관함 화면은 처음부터
  빠져 있었음 - 리그레션 아님).
  - `storage_screen.tscn`: equipment_panel.tscn과 동일한 `Tooltip`
    PanelContainer + `Label`(+ StyleBoxFlat_tooltip 스타일) 노드를 루트에 추가.
  - `storage_screen.gd`: `_tooltip_for()`/`_show_tooltip()`/`_hide_tooltip()`을
    equipment_panel.gd와 동일하게 구현, `_rebuild_grid()`(가방/상자 양쪽 슬롯)에
    `mouse_entered`/`mouse_exited` 연결 + `tooltip_text` 메타 설정.
    `_set_open()`이 자기 자신 재귀로 mouse_filter를 STOP/IGNORE 덮어쓸 때
    Tooltip만 다시 IGNORE로 되돌림(CLAUDE.md UI 모달 체크리스트 3번).

## 인벤토리(장비창) 툴팁이 오른쪽 끝에서 잘리는 버그 수정

- 사용자 리포트(2026-09-05): "인벤에서 툴팁이 잘려서 보여 우측에 아이콘
  범위에 들어가면 그렇게 되나봐". z_index로 먼저 시도했으나 효과 없었음 -
  진짜 원인은 `status_screen.tscn`의 `ContentArea`(장비/호감도/설정 탭
  내용을 담는 컨테이너, 폭 170px)가 `clip_contents=true`라 그 안에 있던
  Tooltip이 오른쪽 탭 아이콘 쪽 경계에서 하드 클리핑됐던 것 - z_index는
  clip_contents를 못 넘어선다.
- 수정: Tooltip 노드 자체를 `equipment_panel.tscn`에서 `status_screen.tscn`
  루트(그 클리핑 바깥)로 옮김. `equipment_panel.gd`는 `tooltip_requested`/
  `tooltip_hide_requested` 신호만 쏘고, `status_screen.gd`가 `show_tooltip()`/
  `hide_tooltip()`으로 대신 그린다. 탭 전환 시(`_show_tab()`)에도 이제 안
  숨겨지므로 직접 `hide_tooltip()` 호출 추가.

## 전설의 동상(legend_statue) - 낚시가게 교환 아이템

- 사용자 지시(2026-09-05): 전설의 물고기를 낚으면 낚시가게에서 `legend_statue`
  (가구, Home/홈인테리어 배치 가능)를 교환할 수 있게. 처음엔 "누적 100마리
  낚으면 골드로 구매 가능"으로 잘못 구현했다가, "돈 주고 사는 게 아니라
  전설 물고기 100마리로 교환해야 하는 시스템이야"로 정정됨 - 누적 카운터
  전부 제거하고 실제 인벤토리 소모 방식으로 재구현.
  - `items.json`: `legend_statue`(category furniture, world_sprite
    `assets/img/fishing/legend_statue.png` 37x64, footprint 2x1 - 세로
    오버행으로 충돌은 맨 밑 16px만, 기존 가구 시스템 그대로 재사용).
  - `shop_manager.gd`: `buy()`에 `LEGEND_STATUE_ITEM_ID` 특수 분기 →
    `_buy_legend_statue()` - 골드 대신 `InventoryManager`의 legendary_fish
    100개를 직접 소모. 부족하면 `REASON_NOT_ENOUGH_FISH`.
  - `shop_screen.gd`: 가격 표시도 동전+골드 대신 물고기 아이콘+"100"으로
    override.
  - 해금 조건은 "황금 낚싯대를 받은 뒤부터"(사용자 지시 - "황금 낚시대
    받고난 이후부터 보여야지") - `_is_release_unlocked()`에
    `requires_golden_fishing_rod` 체크 추가, 인벤토리/장착뿐 아니라 보관함도
    확인(사용자 지시 - "보관함에 있을수도 있잖아") -
    `StorageBoxManager.has_item_anywhere()` 신규 추가.
  - 물귀신(GHOST_VANISH) 연출이 같은 자리(plaza3)에서 낚시할 때마다 자주
    끼어들어 거슬린다는 피드백(사용자 지시 - "물귀신... 하루에 2번만 뜨게
    해줘") - `fishing_manager.gd`에 `GHOST_BITE_DAILY_LIMIT=2` 추가.
  - 테스트용으로 `_roll_species()`를 잠깐 100% 확률로 바꿔뒀다가(사용자 지시)
    테스트 완료 후 원래 가중치 방식(LEGENDARY_FISH_WEIGHT=6, 다른 어종과
    확률 배분)으로 되돌림(2026-09-05).
  - 슬롯 3 세이브 파일에 테스트용으로 legendary_fish 100개(99+1, 스택
    한도 때문에 두 칸)를 직접 넣어둠 - 실제 낚시로 모은 게 아니라는 점 참고.

## 무덤(Grave) 레이어 - Home.tmx

- 사용자 지시(2026-09-05): Home.tmx에 무덤 3기(35~37열, 6~7행, 각 16x32px)를
  직접 그려둠 - NPC가 죽을 때마다(단, 죽은 다음날부터) 하나씩 드러나게.
  사망 가능 NPC 최대 3명과 무덤 3기가 대응.
  - `home_map.gd`: `TOGGLEABLE_TILE_LAYERS`에 `"Grave"` 추가(기존 베리 덤불
    지우기/되돌리기 메커니즘 재사용), `GRAVE_CELL_GROUPS` 상수로 3기 좌표
    하드코딩. `_refresh_graves()`가 `NPCManager.get_dead_npc_ids()` 중
    `death_day < TimeManager.current_day`(어제 이전 사망)인 수만큼만 앞에서
    부터 드러냄. `load_map()` 끝과 `TimeManager.day_changed`(Home에 계속
    있다가 취침하는 경우 대비) 양쪽에서 호출.
  - **버그 발견 및 수정**: Home.tmx의 "Grave" 레이어가 Tiled에서
    `visible="0"`으로 꺼져 있었음 - 기존 코드는 안 보이는 레이어의 타일
    자체를 아예 안 만들어서(`_layer_visibility` 게이트), erase/restore
    대상 데이터가 하나도 안 쌓여 무덤이 절대 안 나타났음(사용자 리포트 -
    "이미 죽은 경우에는 무덤 안보여?... 안보이는뎀"). `TOGGLEABLE_TILE_LAYERS`
    소속 레이어는 Tiled의 visible 값과 무관하게 항상 실제로 그리도록
    수정(기본 숨김은 `_refresh_graves()`가 담당).

## 배포 전 최종 확인 목록 (2026-09-05 세션 마지막 구간, 전부 미확인)

- [x] 인벤토리(장비창) 오른쪽 끝 근처 아이템 툴팁이 이제 안 잘리는지.
  **사용자 확인 완료(2026-09-05).**
- [x] 전설의 동상 - 황금 낚싯대 받은 뒤에만 낚시가게에 뜨는지(보관함에
  넣어놔도 인식되는지), 물고기 100개 소모하고 정상 지급되는지, 100개
  미만이면 실패 메시지가 뜨는지. **사용자 확인 완료(2026-09-05).**
- [x] 물귀신 연출이 하루 2번까지만 뜨는지. **사용자 확인 완료(2026-09-05).**
- [x] 무덤이 죽은 다음날부터 하나씩 드러나는지(이미 죽은 세이브로도 확인).
  **사용자 확인 완료(2026-09-05).**
- [x] 전설 물고기 아이콘이 다시 그린 대로 잘 보이는지.
  **사용자 확인 완료(2026-09-05).**
- [x] 전설 물고기 100% 출현 확률(테스트용)을 원래 낮은 확률(가중치 방식)로
  복구. **완료(2026-09-05).**

## 버그: 온라인샵 닫기 버튼이 익스포트 빌드에서 코인 표시와 겹침

- 사용자 리포트(2026-09-05): "배포하면 닫기 버튼이 계속 컴퓨터 좌측이 아니라
  코인이랑 겹쳐서 보여" - 메일함은 멀쩡한데 온라인샵만 그럼.
- 원인: day18에 메일함(mail_app.gd)에서 이미 겪었던 것과 완전히 같은 버그
  (오른쪽 기준 앵커를 쓰는 CloseButton이, 부모 크기가 아직 0인 순간에
  앵커가 먼저 굳어버리는 익스포트 빌드 전용 문제 - 에디터 Play에서는 재현
  안 됨) - 그때 mail_app.gd의 `open()`엔 `set_anchors_and_offsets_preset
  (PRESET_FULL_RECT)` 수정이 들어갔는데, 나중에 추가된 online_shop_panel.gd에는
  같은 수정이 빠져 있었음.
- 수정: `online_shop_panel.gd`의 `refresh()`(창이 열릴 때마다 호출됨) 맨 앞에
  동일한 `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` 추가.
- **에디터에서 재현 안 되는 버그라 확인 못 함 - 다음 익스포트 때 재확인 필요.**

## 우디 사망 후 온라인 가구점 관련 수정 모음

- **머리색 무채색 절충안**: `recolor_grayscale_to_hue()`가 목표색 채도가
  낮을 때(검/흰/회색)만 곱연산 방식으로 자동 전환(사용자 지시 - "절충안으로
  해보자"). 채도 있는 색은 기존 hue-injection 그대로.
- **온라인샵 house_upgrade 아이콘 안 보임**: `online_shop_panel.gd`의
  `_build_row()`에 livestock/인벤토리 확장/집 확장 특수 처리가 아예
  빠져있었음(오프라인 shop_screen.gd엔 있었음) - 포팅해서 해결.
- **온라인샵 색상 선택 창 없음**: 가구 살 때 색 고르는 UI 자체가 온라인샵엔
  없었음 - 오프라인 상점의 색상 선택 UI 전체(팔레트/미리보기/구매·취소
  버튼)를 온라인샵 창에 새로 포팅(사용자가 "오프샵과 동일한 색상 선택 창을
  그대로 포팅" 선택). 작은 창이라 1/3 축소 배율 재사용. computer_screen.gd의
  mouse_filter 재귀에서 이 서브 팝업을 skip하도록 처리(체크리스트 4번).
  전설의 동상(legend_statue) 가격 표시(물고기 아이콘+100)도 같이 포팅.
- **가구용 망치 반복 지급 버그**: "이미 받았는지"를 인벤토리 보유 개수로
  판정했는데, 이 망치는 손 장착 도구라 장착 중이면 인벤토리에서 안 잡혀서
  매번 다시 지급됐음(사용자 리포트 - "우디가 갑자기 영혼만 나와서 망치
  계속 줌") - `ShopManager`에 영구 플래그(`_furniture_hammer_granted`)
  추가해서 대체.
- **죽은 우디가 망치 대사 하는 문제**: 온라인 전환은 주인이 죽어야만
  일어나는데, 망치 지급 대사는 생사 확인 없이 항상 그 NPC 초상화로
  떴음(사용자 지시 - "죽은 우디 영혼이 주는건 좀 이상하지 않아?") -
  `main.gd._on_furniture_hammer_granted()`가 `NPCManager.is_alive()`를
  확인해서, 죽었으면 대사 없이 "가구용 망치를 손에 넣었다" 메시지만 띄움.
- **배송 실패 시 주문 소멸 버그**: 인벤토리가 꽉 차서 배송 실패하면
  `push_warning`만 남기고 `_pending_deliveries`를 통째로 비워서 그 주문이
  영구히 사라졌음(사용자 리포트 - "배송된다고 하고 인벤 가득 차있으면
  어떻게 돼") - 성공한 것만 빼고 실패분은 큐에 남겨 다음날 재시도하도록 수정.
  안내 문구도 "주문했습니다. 다음 날 배송 되오니 내일이 오기 전 인벤토리를
  비워주세요."로 변경(사용자 지시).

## 배포 전 최종 확인 목록 (2026-09-05 세션, 이 구간은 전부 미확인)

- [ ] 머리색 절충안 - 검은색 고르면 진짜 까맣게 나오는지, 다른 색은 기존과
  동일하게 나오는지.
- [x] 온라인샵에서 우디 사망 후 가구/집 확장/색상 선택 전체 플로우
  (아이콘·색상 창·망치 1회 지급·죽은 NPC 대사 안 뜨는지). **사용자 확인
  완료(2026-09-05) - "온라인샵 확인햇어".**
- [ ] 낚시가게(로시/마린) 둘 다 사망 후 온라인에서 legend_statue 가격/구매.
- [ ] 인벤토리 꽉 찬 채로 온라인 주문 → 다음날 재시도되는지.
