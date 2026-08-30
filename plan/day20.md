# Day 20

day19(포트폴리오 준비) 다음 세션 - day17/18에서 이어진 친구 플레이테스트 실전편. 친구가 내보낸 exe를 직접 받아서 실행했는데 맵이 아예 안 뜨는 사고로 시작해서, 원인 진단 → 코드 수정 → 재검증까지 한 번에 처리. 이어서 친구가 정리해서 보내온 45개 피드백을 분류하고, 그중 일부(NPC 대화 횟수, 초상화 세분화, 폰트 두께)를 실제로 파고듦.

## 익스포트 빌드에서 맵이 아예 안 뜨던 버그 (세션 전반)

에디터 Play에서는 멀쩡한데 내보낸 exe에서는 맵이 통째로 안 보이는 문제. 원인이 두 겹이었음:

### 원인 1 - export_filter="all_resources"여도 원시 파일은 안 들어감
- `.tmx`(맵)/`.tsx`(타일셋)/`.json`(NPC·요리·작물 등 거의 모든 데이터)은 Godot이 import를 거치지 않는 원시 파일이라, "모든 리소스 내보내기" 모드여도 자동 포함이 안 됨
- `export_presets.cfg`의 `include_filter`가 비어 있었던 게 원인 - `"*.json, *.tmx, *.tsx"`로 채움
- 처음엔 `.tmx`/`.json`만 채우고 `.tsx`(타일셋)를 빠뜨려서 "맵은 로드되는데 타일이 하나도 안 그려짐" 상태로 한 번 더 헤맴 - `home_map.gd`가 맵마다 별도로 `.tsx`를 열어서 타일 그림/충돌 정보를 읽어오는 구조라는 걸 다시 확인하고 추가

### 원인 2 - `.png` 존재 확인에 `FileAccess.file_exists()`를 잘못 씀 (진짜 원인)
- `include_filter`를 다 채운 뒤에도 여전히 맵이 안 뜨는 게 재현됨 - 헤드리스로 pck 안의 `home_map.gd`를 직접 돌려서 재현/역추적
- `home_map.gd:_find_tileset_image()`가 타일셋 이미지(`.png`) 존재 확인에 `FileAccess.file_exists()`를 쓰고 있었음 - `.png`는 import되는 리소스라 내보낸 빌드엔 원본이 pck에 안 들어가고 `.ctex`+리맵으로만 존재해서, 이 확인이 **빌드에서만 항상 false**가 됨(에디터에서는 true라 재현 불가). 그 결과 `_add_tileset()`이 빈 텍스처로 중간에 `return`해서 타일이 하나도 안 그려짐
- `ResourceLoader.exists()`로 교체(리맵을 따라감). 같은 오타를 `affection_panel.gd`의 NPC 아이콘 로딩에서도 발견해 같이 수정
- 규칙 정리: `.tmx`/`.tsx`/`.json`(원시 파일) → `FileAccess.file_exists()`, `.png`/`.mp3`/`.ogg`/`.tres`(import 리소스) → `ResourceLoader.exists()`. 나머지 30여 곳은 이미 규칙대로였고 이 두 곳만 예외였음
- 검증: 내보낸 pck에서 `WorldMap`을 실제로 인스턴스화해 24개 맵 전부 타일 생성 확인(Home 1858칸, plaza2 2114칸 등), NPC json 13개/데이터 json 27개 전부 파싱 성공까지 재확인

### 부수 발견 - 메일창 닫기 버튼도 day18과 같은 계열의 export 전용 앵커 버그
- `mail_app.tscn`의 `CloseButton`만 오른쪽 기준 앵커(`anchor_left/right=1.0`)라, 부모 크기가 0인 채로 굳으면 혼자 왼쪽으로 튀어나옴(`BackButton`은 앵커 0이라 멀쩡)
- day18에서 정리한 해법 그대로 - `mail_app.gd`의 `open()`에서 `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` 호출
- **아직 못 끝낸 것**: 같은 구조(오른쪽 기준 CloseButton)인 화면이 더 있음 - `cooking_screen`/`serving_screen`/`storage_screen`/`online_shop_panel`은 아직 이 처리가 없음. `kitchen_screen`/`fishing_screen`은 과거에 "FULL_RECT 넣었더니 문제 생김"이라 일부러 안 넣은 기록이 있어 일괄 적용은 보류

이상 4개 파일(`export_presets.cfg`, `home_map.gd`, `affection_panel.gd`, `mail_app.gd`) + 피드백 정리 문서까지 **커밋 완료**.

## 친구 플레이테스트 피드백 45개 정리

`plan/playtest_feedback_01.md` 신규 작성 - 원본 번호(1~45) 유지한 채 버그/추가 콘텐츠/단순 요청/방향성 의견/제외로 분류.

- 버그 10건, 추가 콘텐츠 11건, 단순 요청 22건, 방향성 의견 2건(28/33), 제외 1건(17 - 유저 행동 양상이라 대응 안 하기로 확정)
- 사용자가 3번/17번/43번 원문 의도를 정정: 17번 제외, 43번은 "레스토랑 닫으면 조리기구 상호작용 자체가 막힘 - 요리창 대신 재료 빼는 모션만 되면 좋겠다"는 뜻(단순 요청으로 재분류, 다만 재료를 넣어둔 채 닫으면 영구히 못 꺼내는 상태인지는 확인 필요), 3번은 "대화를 여러 번 걸 수 있게"가 아니라 "초상화를 더 보고 싶어서 하루 3개 정도 대화 풀이 돌아갔으면"이라는 뜻
- 묶어서 봐야 할 두 덩어리 표시: 2/6/10(모달이 제대로 안 닫힘, 같은 뿌리로 추정), 5/21/29(상호작용 판정 범위 - 5는 너무 넓음, 21은 너무 좁음, 정반대 증상이라 범위만 조정하면 한쪽이 깨짐)

## 3번(NPC 초상화 더 보고 싶다) 관련 조사 - 아직 미구현

- `data/npc/*.json`의 `dialogue.daily`를 전수 집계: low/mid/high 평균 줄 수 1.39/1.64/1.79, `emotion` 태그 비율 5.1%/6.0%/15.4% - 대화 풀/줄 수/회전 로직/줄 단위 표정 전환 전부 이미 코드에 있고, 막고 있는 건 `npc_world_manager.gd:164`(오늘 대화한 NPC를 상호작용 대상에서 완전히 제외) 한 줄뿐이라는 것까지 확인
- 스타듀밸리 방식(대화 횟수가 아니라 한 대화 안에서 `$h`/`$s`/`$a` 같은 토큰으로 표정을 여러 번 전환)과 비교 설명, 이 프로젝트의 `emotion` 필드가 이미 같은 걸 할 수 있다고 정리
- 사용자가 "감정이 너무 세 보여서 항상 넣기 부담스럽다"고 지적 - `dialogue_screen.gd`가 `emotion` 없는 줄은 직전 표정을 유지한다는 것(매 줄 안 넣어도 됨), 그리고 `happy`/`angry`만 있고 중간 강도가 없는 게 진짜 문제라는 데 합의
- **결론**: 하루 대화 횟수를 늘리는 건 `_talked_today`가 세이브에 저장되는 구조라 세이브 구조 변경에 해당(CLAUDE.md상 사용자 승인 필요) - 착수 전 확인 필요한 상태로 보류. 표정 세분화(아래) 쪽을 먼저 가는 쪽으로 무게가 실림

## 초상화 세분화(옅은 미소/언짢음) - 에셋 대기 중

- 현재 NPC당 최대 4종(`default`/`happy`/`sad`/`angry`), 중간 강도가 없어서 일상 대사 대부분이 무표정 아니면 급발진하듯 `happy`로 점프하는 구조였음
- `smile`(옅은 미소, `happy` 있는 11명 대상)/`annoyed`(언짢음, `angry` 있는 9명 대상) 키 이름과 대상 NPC 목록까지 확정. 마르/세이지/라마(rama)는 CLAUDE.md에 명시된 "감정 표현 제한" 대상이라 제외
- 코드 수정은 필요 없음(`_update_portrait()`가 `portraits` 딕셔너리를 그대로 조회) - **그림 22장(스마일 11 + 언짢음 9)이 먼저 나와야 진행 가능**, `assets/`는 Claude 수정 금지라 그림은 사용자가 작업

## 폰트가 너무 얇다는 피드백 - 원인 진단 및 수정, 커밋은 보류

- 처음엔 "볼드가 필요한가" 싶었지만, 실제 원인은 **크기 대비 안티에일리어싱**: UI 텍스트가 4~7px로 쓰이는데 픽셀 폰트(Galmuri11)에 그레이스케일 안티에일리어싱이 걸려 있어서 획 가장자리가 반투명 회색으로 뭉개짐 - 하드엣지인 픽셀아트 옆이라 더 도드라짐
- `assets/fonts/Galmuri/Galmuri11.ttf.import`의 `antialiasing`을 끄는 건 `assets/` 파일이라 사용자에게 직접 승인받고 진행(`1→0`), `theme/ui_theme.tres`엔 `FontVariation`으로 감싸 `variation_embolden=0.6` 추가
- 헤드리스로 동일 설정(320×180, nearest 필터)의 BEFORE/AFTER 비교 스크린샷을 실제 렌더링해서 확인 - BEFORE는 회색으로 뭉개져 4~5px에서 거의 안 읽히는 수준, AFTER는 또렷하고 두꺼움
- **사용자가 "내일 보자"고 해서 커밋 안 하고 작업 트리에 보류 중** - 에디터에서 직접 확인 후 엠볼든 강도(현재 0.6) 조절 여지 있음

## 다음 세션 우선순위

1. 폰트 수정(antialiasing 끔 + embolden 0.6) 에디터에서 직접 확인 → 통과하면 커밋, 강도 조절 필요하면 수치만 조정
2. 초상화 `smile`/`annoyed` 그림 22장 준비되면 `portraits` 딕셔너리에 키 추가 + 해당 대사 태깅
3. NPC 하루 대화 3회 건 - `_talked_today` 세이브 구조를 실제로 어떻게 바꿀지(bool→횟수) 사용자 승인 받고 착수
4. 남은 export 전용 앵커 버그(`cooking_screen`/`serving_screen`/`storage_screen`/`online_shop_panel`) - 실제로 어긋나는지 빌드에서 확인 후 `mail_app.gd`와 같은 방식으로 수정
5. `plan/playtest_feedback_01.md`의 🐛 버그 10건부터 우선순위 정해서 착수 - 특히 2/6/10(모달 안 닫힘), 5/21/29(상호작용 판정) 두 묶음은 따로따로 고치면 재발할 가능성이 높다고 표시해둔 상태
6. 43번(레스토랑 닫으면 조리기구 상호작용 불가) - 재료를 넣어둔 채 닫으면 영구히 못 꺼내는 상태인지부터 확인, 맞다면 버그 쪽으로 격상
7. (백로그) UI 화면 18개가 전부 `_apply_mouse_filter_recursive`/`_set_open` 등 열고 닫는 로직을 각자 복붙해서 갖고 있음 - 그래서 같은 계열 버그(내장 팝업 예외 처리 누락 등)가 화면마다 따로 재발함(2026-08-29, shop_screen/kitchen_screen/slot_picker_screen에서 각각 다른 실수로 발견). 공용 유틸 함수(또는 `ModalScreen` 베이스 클래스)로 묶는 리팩토링 후보 - 지금 당장은 아니고 UI 안정화 이후 별도로 시간 잡고 진행
