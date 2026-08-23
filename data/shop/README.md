# 상점 카탈로그 (`data/shop/shops.json`)

`ShopManager` (scripts/autoload/shop_manager.gd)가 부팅 시 읽는다. 8개 상점(잡화점/농가게/목장가게/낚시가게/가구점/서점/병원/카페)을 `04_locations`에서 확인한 실제 운영 NPC로 등록해뒀다.

**상점 id는 `data/npc/README.md`가 아니라 실제 Tiled 맵을 따른다.** 각 상점 tmx의 `Interactable` 레이어에 있는 `cash_register` 오브젝트가 이미 `shop_id` 커스텀 프로퍼티(예: `marr_shop`)를 갖고 있어서, 그 값을 그대로 이 파일의 키로 썼다. `main.gd`가 플레이어가 계산대와 상호작용할 때 이 프로퍼티를 읽어 `ShopManager`에 그대로 넘긴다 — 맵 쪽과 데이터 쪽이 이름으로 어긋날 일이 없다. `map_id`는 참고용(어느 씬에 대응하는지)으로만 같이 적어뒀다.

## 지금 실제로 살 수 있는 것 — 쥐약 하나뿐이다

`shop.md`/`economy.md` 어디에도 재료 씨앗, 도구, 가구, 커피, 디버프 해제 아이템, 가축, 여물, 미끼, 레시피, 선물의 **구체적인 가격**이 없다. `economy.md`가 가격표를 준 건 레스토랑 요리(`data/cooking/recipes.json`에 이미 반영)와 쥐약(1000G)뿐이다. 그래서 각 상점의 `stock`(실제 구매 가능 목록)에는 **가격이 확실한 것만** 넣었고, 나머지는 `planned_stock`(문서상 이 상점이 팔아야 하는 것의 목록, 가격 없음이라 구매 불가)으로만 남겨뒀다.

새 상품을 팔 수 있게 하려면 해당 상점의 `stock` 배열에 아래 형태로 추가하면 된다:
```json
{"item_id": "watering_can", "price": 300, "purchase_limit": 1}
```
`purchase_limit`은 선택 필드(0 또는 생략 = 무제한). `item_id`는 `data/items/items.json`에 이미 있는 아이템이어야 한다.

**가축(소/돼지)은 인벤토리 아이템이 아니다.** `planned_stock`에 `livestock:cow`처럼 적어뒀지만, 이건 가방에 들어가는 물건이 아니라 외양간에 배치되는 동물이라 아직 없는 축산 시스템의 몫이다. `ShopManager.buy()`는 현재 `item_id`가 `data/items/items.json`에 실제로 등록된 경우만 처리하므로, 가축을 실제로 팔려면 축산 시스템을 만들 때 `buy()`에 `livestock:` 접두사를 다르게 처리하는 분기를 추가해야 한다.

## 순차 공개 상품 (`unlocks_after` / `unlock_delay_days`)

어셔의 책(`usher_shop`)처럼 "한 권씩 순서대로 풀리는" 상품은 `stock` 항목에 아래 두 필드를 추가하면 된다:
```json
{"item_id": "book_perfect_alibi", "price": 200, "purchase_limit": 1, "unlocks_after": "book_beyond_the_door", "unlock_delay_days": 3}
```
* `unlocks_after` — 이 항목이 등장하려면 먼저 구매되어 있어야 하는 선행 `item_id`. 아직 안 샀으면 목록에서 아예 빠진다(`purchase_limit` 초과 항목과 동일하게 숨김 처리).
* `unlock_delay_days` — 선행 항목을 구매한 날(`TimeManager.current_day`)로부터 최소 며칠이 지나야 하는지. 두 조건(구매 + 경과일) 모두 만족해야 `get_stock()`에 나타난다.
* 언제 구매했는지는 `ShopManager._purchase_days`(SaveData의 `purchase_days`)가 아이템별로 기록한다 - 재구매해도 최초 구매일을 유지한다.
* 두 필드가 없으면 기존과 동일하게 항상 노출(다른 상점 전부 이 필드 없이 그대로 동작).

## 상점 승계 (`get_shop_mode`)

`shop.md`를 읽어보면 "승계 규칙이 있는 상점(벨제/셰퍼드, 마린/로시)"과 "승계 규칙이 없는 나머지 상점(사망 즉시 온라인 전환)"이 서로 다른 절로 나뉘어 있지만, 실제 판정 로직은 동일하다 — **`owner_npc_ids` 중 한 명이라도 살아있으면 평소처럼 대면 구매(`in_person`), 전원 사망하면 온라인(`online`)**. 1인 상점은 그 한 명이 곧 "전원"이라 같은 규칙으로 자연스럽게 처리된다. 그래서 상점마다 승계 방식을 별도로 태그하지 않고 `owner_npc_ids` 배열 하나로 통일했다.

## 온라인 전환 시 구매

`get_shop_mode()`가 `"online"`이면 `buy()`는 즉시 결제하고 다음날 오전 9시(`TimeManager.day_changed`, 매일 정확히 그 시각에 발동)에 자동으로 인벤토리에 넣어준다. 그 시점에 가방이 꽉 차 있으면 배송이 실패하고 경고만 남는다 — `memento_received`/`ShopManager` 이전에도 같은 방식으로 처리한 예외 상황이라 동일하게 맞췄다.

## 쥐약

`marr_shop`(잡화점)에 `purchase_limit: 1`로 등록되어 있어 자동으로 "1회 구매, 재판매 불가"가 지켜진다. 사용 여부는 `CookingManager.has_used_rat_poison()`이 별도로 추적하고(구매와 사용은 다른 개념), 두 정보 모두 세이브에 남는다.

## 월드 상호작용

`main.gd`가 계산대(`cash_register`)와 상호작용하면 그 오브젝트의 `shop_id` 프로퍼티를 읽어 `shop_interacted(shop_id)` 신호를 쏜다. 실제 구매 UI(상품 목록을 보여주고 고르는 화면)는 아직 없어서, 지금은 이 신호를 받아 화면을 띄우는 쪽이 없는 상태 — UI 작업 때 이 신호를 구독하면 된다.
