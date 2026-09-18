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

## 플레이테스트 피드백 2차(plan/playtest_feedback_02.md) - 버그 4건 수정

- **#12 취침 후 이동속도 디버프 안 풀림**: 취침(`TimeManager._advance_day()`)이
  분을 하나씩 흘리지 않고 다음날 09:00로 바로 건너뛰어서 `player.gd`의
  `_on_minute_passed()` 카운트다운이 한 번도 안 불렸다 - 향수가 안 풀리던
  것과 똑같은 원인. 향수 초기화 핸들러(`_on_day_changed_clear_scent`)를
  `_on_day_changed_reset_effects`로 확장해서 `clear_debuff()`도 같이
  호출하도록 수정(버프는 하루가 지나도 유지, 디버프만 정리).
- **#15 기상 시 메일 알림 안 뜸**: 평소 취침(침대 상호작용)은 `_load_map()`을
  안 불러서, 그 끝에 붙어있던 `_maybe_show_mail_reminder()`가 기상 시점엔
  아예 한 번도 실행되지 않았다(집 안을 나갔다 들어와야만 뒤늦게 떴음).
  `_play_sleep_transition()` 끝에서 `_is_sleep_transition_playing = false`
  직후 명시적으로 호출하도록 수정.
- **#3 조리대에서 "먼저 레스토랑을 열자"가 안 뜸**(최초 리포트는 "튜토리얼
  안내"로 오해했다가 "조리대 사용 불가능할 때 원래 뜨던 안내"로 재확인)**:
  2026-08-29 피드백#43 수정 때 서빙대(`SERVING_AREA_PREFIX`)는
  `RESTAURANT_NOT_READY_MESSAGE`를 그대로 유지했지만 조리대
  (`KITCHEN_STATION_PREFIX`)는 이 안내가 같이 빠져서, 레스토랑이 닫혀있고
  조리 중인 것도 없을 때 E를 눌러도 아무 반응이 없었다 - 서빙대와 동일한
  안내를 복원.
  - **후속 버그 발견 및 수정**: 복원한 메시지를 실제로 테스트해보니 여전히
    "레스토랑 닫혀있으면 아예 조리대랑 상호작용이 안되네"(사용자 리포트) -
    원인은 매 프레임 도는 `_process()`의 프롬프트 갱신 로직이
    `_message_timer`를 안 보고 무조건 `hide_interaction_prompt()`를 불러서,
    `_show_temporary_message()`가 띄운 메시지가 뜨자마자 바로 다음 프레임에
    지워지고 있었음. 그 hide 호출도 `_message_timer <= 0.0`일 때만 실행되게
    가드 추가.
- **#1 미니맵 내 위치 마커 안 보임**: 원인은 버그가 아니라 크기 - 얼굴
  스프라이트 크롭 마커가 5px라 사실상 안 보였다(사용자 확인 - "너무 작아서
  안보인다는 거였어"). `minimap_map_view.gd`의 초상화 크롭 로직을 통째로
  걷어내고 어두운 테두리가 있는 노란 원(반지름 4px) 마커로 교체.
- **#13 메일 작성 시 한글 마지막 글자가 본문으로 샘**: 제목(LineEdit)에서
  한글 조합 중 마우스로 바로 본문(TextEdit)을 클릭하면, 아직 커밋 안 된
  마지막 조합 글자가 제목에서 사라지고 본문 쪽으로 새어 들어갔다(스페이스바를
  한 번 더 눌러 조합을 먼저 끝내면 정상 동작한다는 것도 같은 원인을 가리킴)
  - Godot IME 조합 커밋이 포커스 전환 뒤에 도착하면서 생기는 엔진 타이밍
  문제로 추정. `mail_compose_panel.gd`에 완화 조치 추가: 두 필드
  모두 `focus_entered`에서 포커스를 한 프레임 놓았다 다시 잡아서, 새던
  커밋이 새 필드를 오염시키기 전에 정리되게 함. **엔진 레벨 타이밍 이슈라
  실제 한글 IME로 재현 확인 필요(자동화 테스트로 검증 불가) - 사용자 확인
  대기 중.**
- #6(울타리 충돌)은 사용자가 직접 수정 완료.

## 플레이테스트 피드백 2차 - 나머지 처리분

- **#4 읽은 메일 글자색**: `mail_list_panel.gd` - 제목 라벨 색을 읽음
  상태(수신함 한정)면 회색(READ_TITLE_COLOR)으로 뺌.
- **#11 수신함 New 배지**: 요청함 배지(`_refresh_request_notify_icon`)와
  완전히 같은 패턴을 InboxButton에도 추가(`mail_app.tscn`에 NotifyIcon
  노드 복제, `mail_app.gd`에 `_refresh_inbox_notify_icon()`).
- **#14 물뿌리개 대상 칸 하이라이트**: 이미 어제(2026-09-04, 커밋
  c49111af)에 `_update_farm_tile_highlight()`의 장비 체크에 watering_can/
  골든 워터링캔이 추가되어 해결돼 있었음 - 추가 조치 불필요.
- **#9 레스토랑 상태 메시지 표시시간**: `_show_temporary_message()`에
  duration 파라미터 추가(기본 2초 유지), 개점 실패/자동 마감/만석 3개
  메시지만 RESTAURANT_STATUS_MESSAGE_DURATION(4초)로 연장.
- **#7 비 효과 눈부심**: `main.tscn`의 Rain CPUParticles2D에
  `modulate = Color(1,1,1,0.6)` 추가. 정확한 수치는 임시값 - 실제로 보고
  더 조정 필요할 수 있음.
- **#2 옷별 도구 사용 포즈 없음**: 원인 파악 완료 - HD 캐릭터 시스템은
  옷마다 정지/걷기 프레임만 있고 도구 사용 포즈 자체가 없음
  (`player.gd._update_hd_animation()`에 "프로토타입 단계라 도구 포즈는
  일단 무시" 주석으로 이미 알려진 갭). 사용자가 PixelLab으로 옷별 4방향
  범용 "도구 쥐는 손 포즈"를 추가로 뽑기로 함 - 그림 받으면 HD 애니메이션
  프레임 그룹 확장 + tool_overlay 연결 작업 필요(미착수).
- **#16 화분 거슬림 / #8 외곽선 불일치 / #5 아침 SFX**: 코드 검색으로는
  특정 못함(맵 배치 오브젝트, 스프라이트 자산 감사, 신규 오디오 에셋 필요)
  - 재현/자료 확보 후 진행.

## 외양간 여물통 - 급여 상태에 따라 빈/찬 그림 전환

- 사용자 지시(2026-09-05): cowshed_interior.tmx에 "furniture_empty"
  레이어로 4칸 빈 여물통을 그려둠(현재 visible=false로 꺼둔 상태) - 매일
  아침 비워진 그림으로 리셋되고, 그 칸 동물에게 여물을 주면 원래(가득 찬)
  그림이 드러나야 함. 무덤(Grave)/베리 덤불과 완전히 같은
  "지우기/되돌리기로 아래 원본 그림 드러내기" 패턴 재사용.
  - `home_map.gd`: `TOGGLEABLE_TILE_LAYERS`에 `"furniture_empty"` 추가
    (Tiled visible 플래그 무관하게 항상 실제로 그리게 함 - Grave와 동일
    이유).
  - `LivestockManager`가 이미 300줄 규칙을 넘어서 있어서(사용자 기능
    추가 전부터 358줄) 새 `scripts/autoload/livestock_trough.gd`
    (RefCounted, 오토로드 아님)로 여물통 로직을 분리 -
    player.gd/player_tool_overlay.gd와 같은 이유.
  - `LivestockTrough.refresh_for_map()`이 `WorldMap.find_toggleable_
    clusters("furniture_empty")`로 그려진 칸을 자동 스캔(BerryBushManager와
    동일 - 좌표를 따로 안 찍어도 됨)하고, 각 클러스터를 가장 가까운
    칸(spot1~4)에 1:1 매칭(칸마다 개별 동작 - 사용자 확인).
  - `perform_feed()` 성공 시 그 칸의 여물통만 지워서(가득 찬 그림 노출),
    재입장/자정 통과 시 `fed_day == 오늘`로 다시 계산해서 자동으로
    맞춰짐(외양간에 계속 서서 자정을 넘기는 드문 경우 대비 day_changed
    훅도 추가).
  - **버그 발견 및 수정(2026-09-14)**: 사용자 리포트 - "여물통 안 줘도 항상
    차있는데". 원인은 `cowshed_interior.tmx`에 실제로 그려진 레이어 이름이
    `Furniture_empty`(대문자 F)인데 `home_map.gd`의 `TOGGLEABLE_TILE_LAYERS`와
    `livestock_trough.gd`의 `TROUGH_LAYER_NAME`은 소문자 `furniture_empty`로
    되어 있어서 대소문자가 안 맞았던 것 - Tiled에서 꺼둔(`visible="0"`) 레이어를
    강제로 그리는 예외 목록에 안 걸려 빈 여물통 타일 자체가 생성되지 않고
    항상 가득 찬 그림만 보였음(Grave 때와 동일한 부류의 버그, 다만 이번엔
    이름 철자 불일치). 두 상수를 `Furniture_empty`로 맞춰 수정.
    **사용자 확인 완료(2026-09-14) - "웅 잘 들어간다".**

## 코너 슬라이드 어시스트 (모서리/좁은 틈 자동 밀어주기)

- 사용자 지시(2026-09-05): "충돌 구간에 막히면 절대 앞으로 가지 않는데...
  대부분의 게임들이 충돌 구간 옆으로 미끄러지듯 밀어내는 효과를 주잖아...
  그 효과가 없어서 맵을 다닐 때 너무 많이 걸려." Plan 모드로 조사/설계 후
  구현(계획 파일: `C:\Users\code1\.claude\plans\linked-doodling-map.md`).
  - 기존 대각선 입력 축분리 슬라이드(`_move_with_collision`)는 이미 있었지만,
    한 방향 키만 눌러서 벽 모서리/울타리 틈에 픽셀 단위로 어긋나게 접근할
    때 도와주는 로직이 전혀 없었던 게 "걸리는" 느낌의 실제 원인.
  - `player.gd`: `_move_with_collision()`에 `delta: float` 파라미터 추가
    (호출부 `_physics_process`도 `_delta` 같이 넘기게 수정), 단일 축 입력이
    막힌 프레임에 `_apply_corner_slide_assist()` 호출.
  - `_corner_assist_open_sign()` - 막힌 축과 수직인 두 방향을
    `CORNER_ASSIST_PROBE_DISTANCE`(8px = 반 타일) 안에서 확인해서 어느 쪽이
    열려있는지 판단(둘 다 막히면 진짜 코너로 보고 어시스트 끔, 둘 다
    열려있으면 가장 가까운 타일 중심 쪽으로 편향).
  - `_apply_corner_slide_assist()` - 판단된 방향으로
    `CORNER_ASSIST_NUDGE_SPEED`(40px/s)만큼 미세 이동, 기존
    `_is_blocked_at()`으로 검증 후에만 반영, 같은 프레임에 원래 진행 방향도
    재검사해서 통과했으면 바로 전진까지 이어지게 함.
  - 헤드리스 `--check-only`로 문법 검증 완료(`tile_center` 타입 추론 에러
    한 건 발견해서 수정 - `float` 명시). 두 상수(8.0/40.0)는 임시값 - 실제
    게임에서 걸어보고 조정 필요.
  - **버그 발견 및 수정**: 사용자 리포트 - "오히려 중앙으로 몰아버리는데...
    비어있는 길쪽으로 가야지". 원인은 `_corner_assist_open_sign()`이 순수
    옆 칸(수직 오프셋만)만 검사했던 것 - 넓은 벽에 그냥 똑바로 부딪혀도
    좌우 옆 칸은 원래 열린 바닥이라 "둘 다 열림"으로 잘못 판정되어 벽에
    막힐 때마다 타일 중심으로 끌려갔음. 옆으로 비킨 지점이 아니라 "옆으로
    비킨 뒤 진행 방향으로도 더 갈 수 있는지"(대각선 지점)를 검사하도록
    수정 - 벽이 옆으로도 이어져 있으면 이 대각선 지점도 막힌 채라 어시스트가
    안 걸리고, 진짜 틈/모서리일 때만 걸리게 됨.
  - **사용자 확인 완료(2026-09-14) - "다 확인했어"** (울타리 틈/문/외양간
    통로, 완전히 막힌 코너, 벽에 똑바로 부딪힐 때, 튜토리얼 walk_to() 컷신
    전부 포함).

## 캐릭터 크기 축소 (HD_SCALE/HD_VISUAL_BOOST 부스트 제거)

- 사용자 리포트(2026-09-14): 플레이테스트에서 "캐릭터가 너무 크다"는 피드백.
- 적용 범위·정도 확인(AskUserQuestion): 플레이어+NPC 둘 다(기존처럼 같은
  배율 공유해서 상대적 크기 비율 유지), 배율 0.6 → 0.5 내외로 확실히 축소.
- `player.gd`의 `HD_SCALE`(플레이어 HD 스프라이트 배율)과 `npc_sprite.gd`의
  `HD_VISUAL_BOOST`(고해상도 NPC 전용 추가 배율, 13명 전원이 고해상도라
  사실상 전 NPC에 적용됨)는 원래 같은 부스트 값(1.2)을 공유하도록 설계돼
  있었음(2026-09-02 결정 - "1.3배로 키웠다가 생각보다 크다는 피드백으로
  1.2로 낮춤"). 이번엔 그 부스트 자체를 1.2 → 1.0(=부스트 없음, 순수
  정규화 크기)으로 낮춤 - `HD_SCALE`은 `0.5*1.2`→`0.5*1.0`(=0.5),
  `HD_VISUAL_BOOST`는 `1.2`→`1.0`. 두 상수 다 다른 곳(character_preview.gd/
  player_preview.gd 등)에서 값으로 참조만 하고 하드코딩한 곳이 없어서 이
  두 줄만 바꾸면 미리보기 화면들도 자동으로 같이 축소됨.
- **후속 조정**: 1.0으로 실제로 보니 "너무 작다"는 피드백(사용자 지시,
  2026-09-14) - 1.0 → 1.1로 재조정(`HD_SCALE`은 `0.5*1.1`=0.55,
  `HD_VISUAL_BOOST`는 `1.1`). 기존 1.2보다는 작고 1.0보다는 큰 절충값.
- **사용자 확인 완료(2026-09-14) - "이정도가 괜찮네"** (1.1로 최종 확정).

## 마린 스프라이트 시트 재조립 (PixelLab 재수출 반영)

- 사용자 지시(2026-09-14): "마린 이미지 바꿨는데 다시 임포트해줭 지금 예전거로
  되어있다" - `assets/npc/pixellab/marin/`의 PixelLab 원본(Idle/rotations,
  Idle/animations/Walking, Eating, 새 Drinking 폴더까지)을 통째로 재수출해뒀는데,
  실제 게임이 읽는 완성 시트(`assets/npc/sprite/marinSprite.png`,
  `marinEating.png`)는 예전 버전 그대로라 반영이 안 됐던 것.
- 걷기/정지 시트(`marinSprite.png`, 36칸=4방향×[정지1+걷기8], 1152x64)를
  원본에서 다시 조립하는 스크립트가 지금까지 없었음(Eating만
  `build_eating_sheet.ps1`이 있었음) - 새로 `build_walking_sheet.ps1` 작성.
  크롭 규칙은 `build_eating_sheet.ps1`과 완전히 동일하게 재사용(가로 32px
  중앙 정렬, 세로는 원본이 64px 이하면 하단 정렬, 64px보다 크면 y=10 고정
  오프셋 크롭) - 정지 프레임 원본이 정확히 64x64(=CellH)라 크롭이 전혀 안
  걸리는 것도 이 규칙이 원래 이 시트를 만들 때 쓰였다는 정황과 맞아떨어짐.
  다른 NPC도 나중에 같은 식으로 재수출하면 재사용 가능(사용자 지시로
  일회성이 아니라 재사용 가능한 스크립트로 작성).
- CLAUDE.md 자산 교체 규칙대로 기존 파일을 `marinSprite_old.png`/
  `marinEating_old.png`로 백업해두고 새로 조립한 시트로 덮어씀.
- Eating 시트도 소스 GIF(`Eating/south.gif`)가 같이 재수출돼 있어서
  기존 `build_eating_sheet.ps1`로 같이 재조립.
- 새로 추가된 `Idle/animations/Drinking/` 폴더는 아직 게임에 연결되지 않은
  원본 상태 그대로 둠(사용자가 별도로 요청하기 전까지는 손 안 댐 - 어떤
  상황에 쓸 포즈인지 확인 필요).
- **미확인 - 실제 게임에서 마린 스프라이트가 새 디자인으로 보이는지(걷기/정지/
  먹는 동작 전부), 크롭이 어색하지 않은지 확인 필요.**

## 다국어 지원(한/영/일/중) 1단계 - 번역 시스템 구축 + 파일럿

- 사용자 지시(2026-09-14): "다국어지원도 하고싶어" → 대상 언어 영/일/중 확정,
  "AI가 다 드래프트해줘" 방식으로 진행. 규모가 매우 커서(스크립트 76개 한국어
  약 1064줄 + `.tscn` 88곳, NPC 13명 372KB + 공포 이메일 등) Plan 모드로
  설계 승인 받고 진행(계획 파일: `C:\Users\code1\.claude\plans\
  expressive-twirling-fern.md`). **이번 세션은 "시스템 구축 + 파일럿"까지만** -
  13명 전원 번역은 다음 세션들에서 배치로.
- **UI 텍스트**: Godot 내장 TranslationServer 사용, 단 CSV 자동 임포트 대신
  `data/localization/strings.json`(원문 한국어를 키로) + `Translation.
  add_message()`/`TranslationServer.add_translation()`을 런타임에 직접
  호출하는 방식 채택(`Localizer._load_ui_translations()`) - 헤드리스 환경(에디터
  없이 CSV 재임포트 불가)에서도 확실히 동작하는 공식 스크립트 API만 써서
  신뢰성을 높임. `Control.auto_translate_mode`가 기본 켜짐이라 `.tscn`에 박힌
  텍스트/`label.text = "..."`로 설정한 문자열 둘 다 코드 수정 없이 자동
  번역됨 - 서식 문자열(`"%d일차" % 변수`)만 `tr("%d일차") % 변수`처럼 명시적으로
  감싸야 함(main.gd 3곳 수정, 다른 서식 문자열은 아직 미착수).
  - **버그 발견 및 수정**: `TranslationServer.set_locale("ko")`인데도 영어
    번역이 나오는 버그 발견(`tr()` 테스트 중) - `project.godot`에
    `internationalization/locale/fallback` 설정이 아예 없어서 Godot 엔진
    내장 기본 폴백(`"en"`)으로 떨어지고 있었음. `project.godot`에
    `[internationalization] locale/fallback="ko"` 추가해서 해결 - 안 그러면
    번역이 하나도 없는 한국어 플레이 중에도 카탈로그에 등록된 다른 언어
    문자열이 새어 나올 뻔했음(실제 플레이엔 치명적인 회귀였을 버그).
- **폰트**: Galmuri(한글+라틴 전용)는 일본어/중국어 글자가 없어서, **Ark Pixel
  Font**(TakWolf/ark-pixel-font, SIL OFL 1.1 - 상업적 사용 무료, 한/중/일 지원
  픽셀체, GitHub 공식 릴리스 2026.09.01에서 12px proportional TTF 다운로드)를
  `assets/fonts/ArkPixel/`에 추가(ja/zh_cn 두 파일만, 라이선스 파일도 같이
  보관). `Localizer.apply_font_for_language()`가 `ThemeDB.get_project_theme()`
  (프로젝트 전역 Theme 리소스 하나)의 `default_font`를 언어에 맞춰 직접
  교체 - 개별 노드 오버라이드 없이 전체 UI에 한 번에 반영됨(헤드리스로 실측
  검증 완료 - 4개 언어 전부 올바른 폰트 리소스로 전환 확인).
- **NPC/공포 이메일 JSON**: 기존 `data/npc/*.json`/`data/horror/*.json`은
  전혀 안 건드림 - 같은 폴더에 `marin.en.json`/`marin.ja.json`/`marin.zh.json`
  같은 언어별 형제 파일을 새로 추가하고, 로드 시점에 한국어 구조를 기준으로
  재귀 병합(`Localizer.merge_json()`). `type`/`item_id`/`emotion`/
  `requires_alive`/`affection`/`id`/`threshold`는 번역 금지 목록(DENYLIST_KEYS) -
  특히 `requires_alive`(다른 NPC의 id 문자열)를 잘못 번역하면 죽은 NPC 분기가
  영구히 깨짐. 배열은 길이가 정확히 같아야 병합되고, 다르면 그 배열 전체를
  한국어로 폴백(부분 스플라이스 안 함 - 조용히 틀린 서사가 나오는 것보다
  안전한 쪽 선택). 스키마 규칙은 `data/npc/README.md`에 문서화.
  - `npc_manager.gd`: `_load_definition()`에 병합 삽입,
    `_load_all_definitions()`가 언어 형제 파일(`*.en.json` 등)을 NPC 정의
    파일로 중복 로드하지 않도록 필터 추가, `reload_for_language()` 진입점 추가.
  - `horror_event_manager.gd`: `_load_json()`에 병합 삽입,
    `reload_for_language()` 진입점 추가.
  - **버그 발견 및 수정(번역 파일 자체의 버그)**: 헤드리스로 `marin.json` vs
    `marin.en.json`을 실제로 병합 테스트해보니 `dialogue.daily.목.high[1].lines`
    배열 길이가 한국어 1개/영어 2개로 어긋나 있어서 그 항목 전체가 조용히
    한국어로 폴백되고 있었음(번역 드래프트 에이전트가 한 문장을 두 줄로
    나눠 쓴 실수) - 한 줄로 합쳐서 수정. 이후 마린 2개 파일 + 공포 이메일
    1개 파일 × 3언어 = 총 6개 형제 파일 전부 구조 일치 재검증 완료(전용
    헤드리스 diff 스크립트로 재귀 검사, 전부 통과).
- **언어 상태 저장**: 새 `scripts/autoload/localization.gd`
  (`extends RefCounted`, `class_name Localizer`) - 오토로드 아님(CLAUDE.md가
  못박은 6개 오토로드 목록을 안 늘리려고 `home_map.gd`의 `class_name WorldMap`
  정적 유틸리티 패턴 재사용, NPCManager/HorrorEventManager 둘 다에서 공통으로
  불러야 해서 어느 한쪽 소유로 못 둠). `user://language_settings.cfg`에
  저장(`audio_manager.gd`의 `AUDIO_SETTINGS_PATH`와 동일 패턴 - SaveData
  3슬롯과 무관한 전역 설정이라 세이브 파일 건드리지 않음). `game_manager.gd`
  `_ready()` 맨 앞에서 `Localizer.load_saved_language()` 한 줄만 호출(이미
  301줄로 한도 걸린 파일이라 로직은 전부 `Localizer`에).
- **언어 설정 화면**: `scripts/ui/language_settings_screen.gd`(기존
  "준비 중입니다" 자리표시자)를 실제로 채움 - `OptionButton`으로 한국어/
  English/日本語/中文 선택, 바꾸면 `Localizer.save_language()` +
  `NPCManager.reload_for_language()` + `HorrorEventManager.reload_for_language()`
  호출. 타이틀 화면에서만 열리는 기존 동선(`title_screen.gd`) 그대로 유지 -
  게임 중 전환 가능하게 할지는 미정.
- **이번에 채운 번역 분량(파일럿)**: 핵심 UI 문자열 32개(main.gd의 상태
  메시지 상수들, 타이틀/설정/메일함/상점 라벨 등) + NPC 1명(`marin`) 전체
  JSON + 공포 스토커 이메일 1파일(`stalker_emails.json`) - 전부 영/일/중
  3언어. 나머지 12명 NPC + 다른 공포/책/튜토리얼 콘텐츠 + 나머지 UI 문자열은
  미착수(다음 세션들에서 배치로 진행 예정).
- **검증**: 헤드리스로 (1) 프로젝트 전체 부팅(타이틀 화면 씬트리 포함) 무에러
  확인, (2) `Localizer.merge_json()`을 실제 marin.json+marin.en.json에 돌려서
  denylist/플레이스홀더/중첩 choice 트리 전부 정상 병합 확인, (3) `tr()`가
  4개 언어 전부에서 정확한 문자열 반환하는지 확인, (4) 폰트가 언어별로 정확한
  리소스로 스왑되는지 확인. **main.tscn은 세이브 없이 헤드리스로 띄우면
  자동저장이 덮어써서(CLAUDE.md 경고) 직접 못 띄워봄 - 사용자가 에디터에서
  실제로 언어 전환 확인 필요.**
  - 헤드리스 검증 과정에서 `class_name Localizer`가 처음엔 전역 클래스
    캐시(`.godot/global_script_class_cache.cfg`)에 안 잡혀서 모든 참조가
    "not declared" 파싱 에러였음 - `--headless --editor --quit`로 에디터
    모드 1회 실행해서 캐시를 재생성해야 했음(단순 `--headless --quit`로는
    파일시스템 재스캔이 안 일어남). 참고용으로 기록.
- 중국어 zh 파일 번역 에이전트가 남긴 참고사항: 다른 NPC 이름의 중국어
  표기(로시→罗西, 세이지→赛姬, 이샤→伊莎, 벨제→贝尔杰, 셰퍼드→谢泼德,
  어셔→厄舍, 라마→喇嘛, 폴리→波利)는 임시로 정한 것이라, 다른 NPC들 번역할
  때 공용 표기 목록으로 정리해서 일관성 맞춰야 함.
- **사이드 이펙트 발견 및 되돌림**: 폰트 재임포트용으로 돌린
  `--headless --editor --quit`가 의도치 않게 `assets/player/pixellab/clothes/
  plain2/preview_player_plain2.png`(오늘 낮에 사용자가 언급했던 손 든 포즈
  참고용 미리보기 파일)까지 같이 재임포트해서 바이트가 바뀌어버림(픽셀
  내용은 아마 동일하겠지만 재인코딩됨) - 세션 시작 시점엔 깨끗했던 파일이라
  `git checkout`으로 커밋된 버전으로 되돌려서 정리함. 다국어 기능과는 무관.
- **버그 리포트 및 수정(2026-09-14) - "언어설정에 한국어밖에 없어"**:
  헤드리스로 직접 씬을 띄워서 확인해보니 그 시점 코드 자체는 4개 항목이
  전부 정상적으로 들어가 있었음(에디터/Play 세션이 코드 변경 전 상태로
  캐싱되어 있었을 가능성) - 그런데 이어서 "버튼 디자인이 너무 못생겼엉"
  피드백도 받아서, 원인 규명보다 UI 자체를 이 프로젝트에 전례가 전혀 없는
  네이티브 `OptionButton`(드롭다운) 대신 `quit_confirm_popup.gd` 등 기존
  팝업들과 완전히 같은 방식(평범한 `Button` 4개, `toggle_mode` + 공유
  `ButtonGroup`으로 라디오 버튼처럼 동작)으로 교체 - 두 문제를 한 번에
  해결. 패널도 4개 버튼이 한 줄에 들어가도록 120x60 → 170x70으로 확대.
  헤드리스로 씬 인스턴스화 + 버튼 클릭 시뮬레이션까지 끝까지 검증(영어
  버튼 클릭 → `Localizer.current_language`가 "en"으로 바뀌고 나머지 버튼은
  자동으로 눌림 해제되는 것 확인).
- **버그 리포트 및 수정(2026-09-14) - "버튼 디자인이 너무 못생겼엉 ㅠㅠㅠ ...
  디자인 버튼 디자인 씌워줘"**: 처음에 "이 프로젝트에 Button 커스텀
  스타일이 없다"고 잘못 판단했음 - 실제로는 `quit_confirm_popup.gd` 등
  팝업 전부가 `.tscn`엔 기본 Button만 두고 `_ready()`에서
  `button.png`/`button_hover.png` 9-슬라이스 텍스처를
  `add_theme_stylebox_override()`로 코드로 입히는 공용 패턴이 있었는데,
  `.tscn`만 보고 넘어가서 놓쳤음(.gd를 안 열어봄). 동일한
  `_style_button()`/`_build_button_style()` 패턴을 language_settings_screen.gd에도
  그대로 이식 - toggle 버튼이라 pressed 상태도 hover 텍스처를 써서 현재
  선택된 언어가 계속 밝게 남아 선택 표시를 겸하게 함.
- **버그 리포트 및 수정(2026-09-14) - "시작하기 이런거 다 번역이 안되어잇음"**:
  Godot 커뮤니티에 잘 알려진 문제 - `TranslationServer.set_locale()`만으로는
  이미 같은 씬트리 안에 살아있는(언어 팝업 뒤의 타이틀 화면 버튼들 같은)
  Control의 표시 문자열이 즉시 안 갱신되는 경우가 있음. `Localizer.
  save_language()`에 `_notify_translation_changed()`를 추가해서
  `NOTIFICATION_TRANSLATION_CHANGED`를 트리 전체(`get_tree().root`)에
  명시적으로 강제 재전파하도록 보강.
  - **버그 발견 및 수정(문법 에러)**: `NOTIFICATION_TRANSLATION_CHANGED`가
    `Node`(Control 계열) 소속 상수인데 `Localizer`는 `RefCounted`라 그냥
    쓰면 "not declared" 파싱 에러 - `Node.NOTIFICATION_TRANSLATION_CHANGED`로
    완전한 경로를 써서 해결.
  - **부수적으로 발견한 사실**: 헤드리스 테스트 중 이전 자동 테스트들이
    실제 `user://language_settings.cfg`(개발 PC의 진짜 유저 설정 파일)에
    "en"을 저장해둔 채로 남아있었음(GameManager._ready()가 자동으로 이
    저장된 언어를 불러오는 게 정상 동작임을 이걸로 역으로 확인함) - 사용자가
    실제로 게임을 켰을 때 의도치 않게 영어로 시작하지 않도록 그 파일을
    삭제해서 정리함(한국어 기본값으로 복귀).
- **버그 리포트 및 수정(2026-09-14) - "새로시작하기, 2번슬롯 이런거 영어로
  하나도 번역이 안되어있는데"**: 실제 버그가 아니라 파일럿 범위 밖이었을
  뿐(계획대로 32개 핵심 문자열만 채운 상태 - 세이브 슬롯 선택 화면
  `slot_picker_screen`은 아예 포함 안 돼 있었음). 사용자가 타이틀 화면
  바로 다음 화면에서 곧장 부딪힌 것이라 즉시 커버 - `slot_picker_screen.gd`의
  서식 문자열 4곳(`%s - %d일차`/`%d번 슬롯\n%s`/`%d번 슬롯\n(비어있음)`/
  `%d번 슬롯을 삭제하시겠습니까?\n되돌릴 수 없습니다.`)을 `tr()`로 감싸고,
  `strings.json`에 이 4개 + "새로 시작하기"/"삭제" 문자열 추가. 헤드리스로
  4개 언어 전부 정상 치환 확인.
- **사용자 지시(2026-09-14) - "엥? 뭔.. 다 해줘"**: 화면 하나씩 발견되는 대로
  채우는 대신, 이번엔 UI 텍스트 전체를 한 번에 채워달라는 요청 - 병렬
  에이전트 5개로 화면 그룹을 나눠서 진행(온보딩/설정/팝업, 상점/메일,
  요리/낚시, 상태창/인벤토리/도감/옷장, main.gd+HUD+미니맵). 각 에이전트가
  자기 담당 파일에서 서식 문자열은 `tr()`로 감싸고(코드 수정), 나머지는
  `strings_group{A..E}.json`(공유 파일 동시 쓰기 충돌 방지용 임시 파일)에
  번역 추가.
  - 결과: 새 문자열 164개, 총 카탈로그 203개. 5개 그룹 결과를 헤드리스
    스크립트로 병합하면서 자동으로 충돌 검출 - **8개 키가 그룹 간 서로 다른
    번역으로 충돌**했음(캐릭터 생성 화면과 옷장 화면 양쪽에 같은 헤어스타일/
    눈 이름이 있는데 두 에이전트가 서로 다르게 번역함 - 예: "단발"을 한쪽은
    "Bob", 다른 쪽은 "Bob Cut"으로. 레스토랑 여닫기 확인 문구의 중국어
    표현도 두 군데서 다르게 나옴). 전부 직접 검토해서 하나로 통일(같은
    헤어스타일이 화면마다 다른 이름으로 보이면 안 되니까) - 8개 전부 수동
    확정 후 최종 병합, 재검증까지 완료.
  - 코드 수정된 파일: `scripts/main.gd`(서식 문자열 5곳 - 레시피 습득/부활
    확인·성공/도구 상호작용 프롬프트 2곳/아이템 획득 토스트, 공포 컷신 독백
    7줄도 포함 - main.gd에 하드코딩된 플레이어 혼잣말이라 NPC 대사 아님),
    `scripts/ui/hud.gd`(버프/디버프 툴팁, 날짜/요일/시간 라벨),
    `scripts/ui/shop_screen.gd`/`online_shop_panel.gd`(색상 선택/배치 프롬프트),
    `scripts/ui/mail_compose_panel.gd`/`mail_detail_panel.gd`(초대장 제목/본문,
    보상 표시), `scripts/ui/fishing_screen.gd`(인벤토리 가득 참),
    `scripts/ui/memento_toast.gd`(아이템 획득 토스트). 나머지(캐릭터 생성/
    팝업/HUD 상호작용 프롬프트 등 대부분)는 순수 리터럴이라 코드 수정 없이
    카탈로그 추가만으로 자동 번역됨.
  - **알려진 잔여 격차(에이전트가 스스로 발견해서 보고)**: HUD 시계의
    요일 부분("월"/"화"...)은 `TimeManager.WEEKDAY_NAMES`가 원래 한국어
    고정이라, 날짜 템플릿은 번역돼도 요일 글자는 계속 한국어로 나옴 -
    이번 범위 밖(TimeManager 자체를 안 건드림). `livestock_confirm_popup.gd`의
    `open_with_message()`는 실제로 어디서도 호출 안 되는 죽은 코드로
    보임(방어적으로 카탈로그는 채워둠).
  - 헤드리스로 최종 병합본 재검증: 전체 프로젝트 무에러 부팅 + 충돌
    해결된 8개 키를 포함한 샘플을 4개 언어 전부에서 재확인, 미등록 문자열은
    여전히 한국어로 안전하게 폴백되는 것도 확인.
- **미확인 - 실제 게임/에디터에서**: **에디터를 완전히 재시작한 뒤** 타이틀
  화면에서 언어 버튼 4개로 전환이 실제로 되는지(위 버그 리포트들이
  "코드 바뀌기 전 상태가 남아있는 Play 세션"이었을 가능성이 있어서 재시작이
  특히 중요함), 이제 캐릭터 생성/상점/메일/요리/낚시/상태창/인벤토리/옷장/
  HUD까지 폭넓게 번역되는지, 마린과 대화/메일로 번역된 대사가 나오는지,
  일본어/중국어 폰트로 바뀐 UI가 박스를 벗어나거나 잘리는 곳이 없는지,
  한국어로 되돌렸을 때 기존과 100% 동일한지. 아직 카탈로그에 없는 문자열은
  자동으로 한국어 그대로 나오니(에러 아님) 발견되는 대로 알려주시면 계속
  채워나가겠습니다.
