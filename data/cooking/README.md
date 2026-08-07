# 요리 레시피 카탈로그 (`data/cooking/recipes.json`)

`CookingManager` (scripts/autoload/cooking_manager.gd)가 부팅 시 읽는다. `cooking.md`에 나열된 13개 레시피 + `weird_dish`(괴상한 요리, 매칭 실패 시 fallback) = 14개 항목이 이미 채워져 있다.

각 항목: `name`(한글 표시명), `ingredient_pairs`(재료 조합, 순서 무관 매칭), `price`(판매 가격), `description`.

**`price`는 `economy.md`의 "레스토랑 경제" 표에 적힌 실제 가격을 그대로 옮긴 값이다** (예: 바베큐 200G, 괴상한 요리 20G). 처음엔 이 문서를 읽기 전이라 임의의 숫자로 채워뒀었는데, `shop.md`/`economy.md`를 다시 읽으면서 전부 문서값으로 교체했다.

## 레시피는 "알아야" 만들어진다

`cooking.md`는 재료 조합이 레시피와 일치하면 그 요리가, 아니면 괴상한 요리가 나온다고 하면서 동시에 "레시피 획득"(NPC 호감도 이벤트 / 서점 구매)이라는 별도 절을 두고 있다. 그래서 두 규칙을 다음과 같이 합쳤다: **재료 조합이 어떤 레시피와 일치해도, 그 레시피를 아직 배우지 않았으면 여전히 괴상한 요리가 나온다.** 레시피 습득이 실제로 의미를 갖게 하려는 해석이다. 처음엔 아무 레시피도 모르는 상태(`known_recipe_ids`가 빈 상태)로 시작한다.

레시피를 배우는 경로:
* `data/items/items.json`에 `recipe_<recipe_id>` 아이템 13개를 추가해뒀다(예: `recipe_barbecue`). 인벤토리에서 이 아이템을 `InventoryManager.learn_recipe()`로 배우면(우클릭) `recipe_learned` 신호가 발생하고, `CookingManager`가 이를 구독해 접두사(`recipe_`)를 떼고 자동으로 `known_recipe_ids`에 등록한다.
* 이 레시피 아이템을 "어떤 NPC가 어떤 호감도에서 주는지", "서점에서 얼마에 파는지"는 아직 어떤 문서에도 없어서 정해두지 않았다. `03_npcs`/`shop.md`/`book_interior.md`를 구체화할 때 그 지급 로직(`InventoryManager.add_item("recipe_xxx", 1)` 호출)만 연결하면 된다.
* `CookingManager.learn_recipe(recipe_id)`를 직접 호출하는 경로(예: 서점 구매 UI)도 열려 있다.

## 쥐약

`CookingManager.cook(a, b, use_rat_poison=true)`로 호출하면 재료 2개 소모와 별개로 `rat_poison` 아이템 1개를 추가로 소모하고, 반환되는 dish에 `poisoned: true`가 붙는다. **요리 이름/가격/외형은 독이 없는 것과 완전히 동일하다** (`cooking.md`: "쥐약을 사용한 요리는 일반 음식처럼 보인다") — `dish.name`이 그대로 나가므로 NPC나 UI가 구분할 방법이 없다.

`poisoned` 플래그를 실제로 "그 날 밤 사망"으로 연결하는 로직은 넣지 않았다 — 그건 아직 구현하지 않은 `02_horror/murder_system.md`의 몫이다. 대신 `RestaurantManager`가 독이 든 요리를 서빙하는 순간 `npc_poisoned(npc_id)` 신호를 쏘니, murder_system.md를 구현할 때 이 신호를 구독해서 "오늘 밤 이 NPC를 죽인다"는 예약만 걸면 된다.

## `weird_dish`(괴상한 요리)는 NPC가 무조건 싫어한다

개별 NPC의 `preferred_food`/`disliked_food` 목록과 무관하게, `RestaurantManager`는 `dish.is_weird == true`면 `NPCManager.feed_with_preference(npc_id, DISLIKED)`를 호출해서 항상 -5로 처리한다 (`cooking.md`: "NPC는 괴상한 요리를 비선호"). 이름이 매칭 안 되는 요리라 개별 선호 목록 검사로는 이 규칙을 못 잡기 때문에 별도로 강제했다.

## CookingManager가 제공하는 것 / 제공하지 않는 것

`cook()`은 재료/쥐약 소모, 레시피 매칭, 제작 횟수(`get_craft_count`) 집계까지만 한다. 실제로 어느 요리대에서, 어느 NPC에게 서빙할지는 `RestaurantManager`(`data/cooking/` 밖, `scripts/autoload/restaurant_manager.gd`)의 몫이고, 요리 애니메이션/효과음이나 요리창-도감창 UI 전환은 아직 아무 시스템도 구현하지 않았다.
