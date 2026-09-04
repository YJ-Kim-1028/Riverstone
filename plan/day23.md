# Day 23

day22(마르/어셔 선물 아이디어, 튜토리얼 컷신 마무리) 다음 세션. 오늘은 플레이어
HD 캐릭터 커스터마이징 파이프라인을 실질적으로 완성했다 - 룩8~10/스페셜 헤어
4종 등록, 옷장 UI 정리(라벨/색 제한), 온라인샵(키라의 의상샵/파라의 헤어샵) 레이아웃
통일. 그리고 "황금 도구" 신규 아이템, 안부 메일 재설계, 레스토랑 자동 초대,
호감도 수치 튜닝을 새로 구현했다. 마지막엔 큰 버그 두 건(드래프트 재빌드 누락
반복, 옷장 머리색 저장 필드 오타)을 실제로 찾아 고쳤다.

## 황금 도구 (플로라/로시/마린 호감도 50 선물)

- `golden_fishing_rod`/`golden_watering_can` 아이템 추가(Tools.png 14/15번 칸,
  기존에 그려져 있던 실제 아트 재사용).
- 황금 물뿌리개: `FarmingManager.perform_water()`가 장착 아이템 체크해서 중심 칸
  +주변 3x3 전체에 물을 준다(`GOLDEN_WATERING_CAN_ITEM_ID`).
- 황금 낚싯대: `FishingManager.can_start_fishing()`이 골든 낚싯대도 인정,
  `_roll_species()`가 골든 낚싯대 + `plaza3`(GHOST_BITE_MAP_ID)일 때만
  `legendary_fish`를 낮은 확률(가중치 6, 약 5~6%)로 풀에 추가. 그 외 조건에선
  절대 안 나옴. `SPECIES_DIFFICULTY`에 `legendary_fish: {appear:0.45, hits:10}`
  추가(사용자 지시 - 다른 어종보다 훨씬 어렵게).
- 로시/마린 중 한 명한테만 황금 낚싯대가 나가야 해서(요청: "한 명이 받으면 남은
  쪽은 안 나오게") `npc_manager.gd`의 `_check_affection_events()`에 새 필드
  `requires_not_shown`(반대 개념의 게이트 - 대상이 "이미 보여줬으면" 이 이벤트를
  영구 스킵) 추가.
  - **버그 발견·수정**: 처음엔 `has_shown_event()`(대사로 실제 소비된 시점)로
    체크했는데, 호감도가 둘 다 거의 동시에 임계값을 넘으면(예: 디버그로 전체
    호감도 일괄 상승) 아직 둘 다 대사를 안 봐서 서로를 못 막고 둘 다 지급되는
    버그가 실제로 발생함(사용자 리포트). `has_completed_event()`(임계값 넘은
    시점, 같은 틱 안에서도 먼저 처리된 쪽이 즉시 기록됨) 기준으로 교체해서 해결.
    이미 버그가 발생했던 세이브 3번은 로시 쪽 `pending_milestone`을 직접
    지워서 패치(백업: `save_slot_3.json.manual_backup_before_roshi_fix`).
- 마린의 기존 threshold 50 음반 선물 이벤트는 65로 밀림(황금 낚싯대 자리 확보) -
  본인이 직접 65로 재조정.

## 안부 메일 재설계 (마일스톤 방식)

- 기존: 호감도 80 + 7일 쿨다운 + 하루 최대 2명 랜덤 추첨(2026-08-15 설계) - 실제로는
  4일차 이후 15일 동안 스토커 메일 말고 거의 아무것도 안 오는 문제 발견(세이브
  3번, 19일차 기준 우디만 80 넘음).
- `EmailManager`: `GREETING_THRESHOLDS = [20, 40, 75]` 3단계 마일스톤으로 교체.
  NPC별 `emails.greeting` 풀(3개)을 순서대로 그 임계값에서 발송, 하루 상한/쿨다운
  없음(여러 단계를 한번에 넘으면 그날 한꺼번에 옴). `_greeting_stage_sent`로
  진행도 저장(세이브 필드: `last_greeting_day` → `greeting_stage_sent`로 교체).
- 반복 배달 요청 사이클당 인원 2명 → 1명(`RECURRING_NPC_COUNT_PER_CYCLE`).

## 레스토랑 자동 초대

- `_generate_daily_visitors()`가 호감도 최저 2명(`AUTO_LOW_AFFECTION_INVITE_COUNT`)을
  스케줄 무관하게 매일 자동으로 오늘 방문객에 포함(`_lowest_affection_npc_ids()`).
  수동 초대(최대 1명) + 자동 2명 = 좌석 수(3)와 정확히 일치.

## 호감도 수치 튜닝

- 대화 +1 → +2, 선물 +3 → +5, 레스토랑 보통 식사 +1 → +3 (사용자 지시로 순차 조정).
  좋아하는 음식(+5)/싫어하는 음식(-5)/메일(+3)/요청 완료(+3)는 그대로.

## HD 캐릭터 커스터마이징 마무리

- **룩8/9/10** 엔진 시트 빌드 + `HD_OUTFITS`/라벨/`kira_clothing_shop` 등록 완료.
- **파라의 헤어샵 신설**(`para_hair_shop`, `♥ 파라의 헤어샵`, 온라인 전용) -
  special_hair1~4(사용자가 직접 만든 헤어, 얼굴 없음 프롬프트로 생성) 등록.
  `ShopManager`에 `HD_HAIRSTYLE_ITEM_PREFIX`/`is_hd_hairstyle_unlocked()` 등
  옷 해금 시스템과 동일 구조로 추가. 기본 7종 헤어는 항상 해금, special_hair는
  구매해야 함(`DEFAULT_UNLOCKED_HD_HAIRSTYLES`).
- special_hair는 실제 색(초록/파랑 등)으로 그려진 시트라 리컬러 대상에서 제외
  (`HD_HAIRSTYLES_FIXED_COLOR`) - 옷장/캐릭터생성 미리보기, 실제 게임 캐릭터
  둘 다 적용.
- **레이어 순서 버그**: special_hair 일부가 몸통 전체를 덮을 만큼 커서 정면에서
  옷이 하나도 안 보이는 문제 → 정면(남쪽)만 헤어 위에 옷을 얹도록 방향별 분기
  추가. 처음엔 전체 스타일에 적용했다가, 기존 7종 헤어의 정교하게 맞춰둔 옷깃
  경계가 드러나며 빈 공간처럼 보이는 회귀가 생겨(사용자 리포트) **special_hair만**
  적용하도록 범위 축소 완료. 옷장/캐릭터생성 미리보기(`character_preview.gd`)는
  `player.gd`와 별개 렌더 경로라 이 로직이 따로 빠져 있었던 것도 발견해서 동기화.
- 온라인샵 세로 스크롤바를 상점창과 동일한 스타일로 통일 + `RowsMargin` 여백
  추가(버튼과 안 겹치게). **주의**: `RowsMargin`에 `size_flags_horizontal = 3`을
  안 넣으면 가로 스크롤 카드 목록(의상샵/헤어샵)이 확 좁아지는 회귀가 있었음 -
  이미 고쳐서 커밋됨, 재발 시 이 플래그부터 확인.
- 옷장 라벨 "헤어스타일:", "옷:", "눈:" 프리픽스 제거(값만 표시).

## 버그 수정 - 특히 중요

1. **옷장 머리색이 실제 게임 캐릭터에 반영 안 되던 버그** (가장 중요) -
   `wardrobe_screen.gd`의 `_write_target_to_game_manager()`가
   `GameManager.set("%s_color" % target, ...)`로 필드명을 자동 생성하는데,
   "머리" 탭의 target이 `"hair"`라서 `GameManager.hair_color`라는 **존재하지
   않는 필드**에 쓰고 있었음(실제 필드는 `hair_color_1/2/3` 세 개). `Object.set()`은
   없는 필드에 조용히 아무 일도 안 해서 에러도 안 남 - 옷장 미리보기는 로컬
   변수로 바로 그려서 정상으로 보였지만, 실제 캐릭터(`player.gd`가 읽는
   `GameManager.hair_color_2`)는 절대 안 바뀌었음. `target == "hair"`일 때
   `hair_color_1/2/3`을 전부 채우도록 수정 - 사용자가 직접 재현/확인 완료.
2. **엔진 시트 재빌드 누락이 반복적으로 발생** - 드래프트(`preview_player_*.png`,
   편집용 원본)를 수정한 뒤 `build_engine_sheet_from_draft.ps1`로 다시 빌드하는
   걸 깜빡하면 게임에는 옛날 버전이 계속 반영됨(Godot는 최종 엔진 시트 파일
   변경만 감지, 드래프트 변경은 전혀 모름). 오늘 이걸로 실제 눈에 띄는 버그가
   두 번 발생: (1) 단발+룩3 조합에서 걷는 애니메이션 중 옷깃-머리 사이에 1px
   틈(룩3 옷깃 바운스 애니메이션이 드래프트엔 있는데 엔진 시트엔 없었음),
   (2) 애니메 눈 수정 후 게임에 반영 안 됨. 세션 마무리 시점에 전체
   드래프트/엔진시트 mtime을 일괄 스캔해서 stale 6개(단발/묶은머리/곱슬단발/
   숏컷/트윈테일/룩4)를 추가로 발견해 한꺼번에 재빌드함. **다음 세션에서 캐릭터
   외형 관련 이상이 보이면 제일 먼저 드래프트 vs 엔진시트 mtime부터 비교할 것.**
3. 구매(옷/헤어 등) 직후 골드만 빠지고 게임을 끄면 아무것도 못 받는 문제 -
   `SaveManager`가 `ShopManager.item_purchased` 신호 구독해서 구매 즉시 자동
   저장하도록 추가. 옷장 닫을 때도 저장 추가(`wardrobe_screen.gd close()`).
   **주의**: 세이브 3번에서 실제로 이 버그로 룩2~10/헤어1~4 구매 기록이 전부
   날아간 적 있음(재구매 필요) - 복구 불가.
4. 황금 물뿌리개 장착 시 "E 물주기" 프롬프트가 안 뜨던 버그 - `FarmingManager.
   get_available_action()`/main.gd 밭 타일 하이라이트가 `"watering_can"`
   문자열만 체크하고 골든 버전을 안 봐서 발생. 둘 다 골든 버전도 인정하도록 수정.
5. `JukeboxManager.is_unlocked()`가 구매 기록(`ShopManager.get_purchase_count`)만
   보고 있어서, 선물로 받는 음반(어셔 "Be with you", 마린 "The day after you
   came" - 인벤토리엔 들어가지만 상점 구매가 아님)이 영원히 "잠김" 상태가 될
   뻔했음 - 처음엔 인벤토리 보유 여부만 추가로 봤는데, 그 뒤 사용자가 "Be with
   you"를 보관함(storage box)에 넣어놔서 인벤토리 밖으로 나가자 다시 재생이
   막히는 걸 실제로 겪음("들고 있지 않으니까 재생을 못한다"). 최종 수정: 선물
   받는 순간(`NPCManager.npc_gift_item_triggered`) `JukeboxManager`가
   `_gift_unlocked_item_ids`에 영구 기록 - 이후 어디에 두든(보관함 등) 재생
   가능. 구매 기록/인벤토리 보유 체크도 하위 호환으로 같이 유지. 세이브 3번은
   `record_be_with_you`를 소급으로 영구 해금 처리해둠(백업:
   `save_slot_3.json.manual_backup_before_jukebox_fix`).

## 자잘한 수정

- "Be with you" BGM 볼륨 개별 보정(+3dB, `AudioManager.BGM_VOLUME_OFFSETS_DB`).
- "The day after you came" 음반 아이콘 재조정(Records.png row0 col7, 사용자가
  직접 그림).
- 1번 디버그 키(호감도 테스트용)가 우디 한 명만 올리던 걸 전체 NPC로 확장.
- 황금 낚싯대 아이템 설명 텍스트 수정("낚시가게 앞 바다에서 사용한다면...?").

## 할 일 / 아이디어 (다음 세션)

- **라마/세이지 호감도 50 선물 음반** (사용자 아이디어, 2026-09-04) - 어셔/마린
  패턴과 동일하게(threshold 50 affection_event, 새 record 아이템, songs.json
  등록) 착수 예정. 곡 컨셉/Stable Audio 프롬프트까지 이미 확정:
  - **라마(스님)**: "능청스러운 땡중" 톤(순수 경건한 불경이 아니라, 진지한
    척하지만 사실 안 그런 캐릭터 반영). 프롬프트: `Lo-fi lounge groove with
    warm Buddhist chant textures and moktak percussion. Playful, sly swing
    rhythm, mid tempo, instrumental, no vocals, seamless loop.`
  - **세이지(무녀)**: 신사 이미지 안 섞고 순수 크리스마스 캐롤풍으로(사용자
    지시 - "벨이 쨍 울리니까"). 프롬프트: `Bright Christmas carol
    instrumental. Cheerful bells and sleigh bells over acoustic guitar and
    soft strings, mid-slow tempo, no vocals, seamless loop.`
  - 이후 세션(2026-09-05)에서 완료: 제목 확정(`record_the_heart_sutra_remix`/
    `record_we_are_all_christmas`), mp3 생성/배치, 대사는 사용자가 직접
    JSON에 작성. **음반 브금 최종 확인 완료(2026-09-05) - "음반 브금도
    확인햇어".**
- **강아지/고양이 펫 시스템** (사용자 아이디어, 2026-09-04) - 아직 구체 스펙
  없음(입양 방식, 마당/집 안 배치, 먹이/애정도, 산책 등 어디까지 만들지 미정).
  착수 전 범위부터 사용자와 정해야 함.
- **NPC 먹는 동작 추가** - 지금은 레스토랑에서 서빙받은 NPC가 자리에 앉아서
  가만히 있다가(`RestaurantManager.EATING_DURATION_MINUTES` 동안) 떠남 -
  `npc_sprite.gd`에 별도 먹는 애니메이션/포즈가 없음. 실제로 음식을 먹는
  모션(또는 최소한 정적 포즈라도 식사 중임을 보여주는 연출)을 추가할 것
  (사용자 지시, 2026-09-04).

## 배포 전/후 반드시 확인할 것 (QA 체크리스트)

- [x] **황금 도구 전체 플로우 실전 테스트** - 플로라/로시/마린 호감도 50 달성 →
  선물 대사/지급 확인, 로시·마린 중 하나만 받는지(상호 배제) 재확인, 황금
  물뿌리개 3x3 급수, 황금 낚싯대로 plaza3에서 전설의 물고기(낮은 확률) 확인.
  **사용자 확인 완료(2026-09-05) - "황금도구 다 받는거확인햇어".**
- [x] **안부 메일 마일스톤(20/40/75)**이 실제 여러 날에 걸쳐 정상 발송되는지 -
  특히 여러 NPC가 동시에 임계값을 넘었을 때 그날 한꺼번에 여러 통 오는 게
  의도대로 자연스러운지. **사용자 확인 완료(다음날 세션).**
- [x] **레스토랑 자동 초대 2명**이 매일 실제로 방문하는지, 수동 초대 1명과
  합쳐 좌석 3개가 자연스럽게 도는지. **사용자 확인 완료(다음날 세션).**
- [ ] **온라인샵 스크롤/레이아웃** - 의상샵/헤어샵 가로 카드 스크롤이 잘리거나
  버튼이 스크롤바에 가려지지 않는지, 세로 스크롤 있는 다른 상점(가구점 등)도
  같이 확인(공용 스타일 함수라 회귀 가능성).
- [ ] **UI 모달 mouse_filter 체크리스트**(CLAUDE.md) - 오늘 `online_shop_panel.tscn`에
  `RowsMargin` 노드를 새로 추가했음. 새 자식 노드라 열고 닫을 때 mouse_filter가
  제대로 재귀 적용되는지 한 번 열었다 닫고 다른 곳 클릭이 씹히지 않는지 확인.
- [x] **캐릭터 외형 전 조합 순회 확인** - 오늘 stale 엔진시트 버그가 실제로
  발견된 게 룩3/애니메 눈뿐이라, 아직 못 찾은 다른 조합(다른 헤어x다른 옷)에도
  같은 문제(걷기 애니메이션 중 순간적으로 어긋나는 부분)가 남아있을 수 있음.
  **사용자 확인 완료(2026-09-05) - "헤어스타일 의상 조합도 확인햇고".**
- [x] **세이브 마이그레이션** - `email.md`의 `last_greeting_day` 필드가
  `greeting_stage_sent`로 교체됨. 기존(오늘 이전) 세이브 파일을 불러오면 안부
  메일 진행도가 0부터 다시 시작함(정상 - 기존 필드는 그냥 무시됨, 에러 없음).
  **사용자 확인 완료(2026-09-04) - 마이그레이션 불필요, 그냥 넘어가기로 함**
  ("어차피 나 아니면 모르잖아" - 플레이어 본인만 쓰는 세이브라 문제 없음).
- [x] special_hair 4종의 몸(with_skin) 경계가 옷과 자연스럽게 맞물리는지 -
  걷기 애니메이션 8프레임 전부 육안 확인(기본 헤어처럼 바운스 미스매치가 있을
  수 있음). **사용자 확인 완료(2026-09-05) - "스페셜 헤어도 잘 나와".**
