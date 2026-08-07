# 아이템 카탈로그 (`data/items/items.json`)

`InventoryManager` (scripts/autoload/inventory_manager.gd)가 부팅 시 이 파일을 읽어 아이템 카탈로그로 쓴다.
`game_design/01_systems/inventory.md`의 "아이템 종류" 목록에 있는 재료(13) / 도구(3) / 가구(3) / 쥐약(1), 총 20개가 이미 채워져 있다.

## 아직 안 채워진 카테고리

* **`gift`(선물)** — 마르의 잡화점에서 파는 구체적인 선물 아이템 목록이 어떤 기획 문서에도 아직 없어서, `items.json`에는 하나도 안 넣었다. `shop.md`/`marr.json`을 구체화할 때 이 스키마 그대로 추가하면 됨.
* **`dish`(완성 요리)** — 요리는 만들어지는 즉시 서빙되고 인벤토리에 들어가지 않아서("미리 만들어 둘 수 없다"), `items.json`에 넣지 않았다. 요리 자체의 이름/가격은 `data/cooking/recipes.json`이 갖고 있다.
* `recipe_<id>` (레시피 획득 아이템, 13종)는 `cooking.md` 구현 때 이미 추가했다 — 자세한 내용은 `data/cooking/README.md` 참고.

새 아이템을 추가할 때 필드는: `id`(파일의 key와 동일하게), `name`(한글 표시명), `category`, `subtype`(선택, 정보용), `description`, `icon`(에셋이 없으면 `""`).

## `category`가 스택/버림 규칙을 전부 결정한다

`inventory.md`의 규칙표가 카테고리 단위였기 때문에, 개별 아이템마다 수량 제한을 적지 않고 `InventoryManager`의 `CATEGORY_STACK_LIMITS`/`NON_DISCARDABLE_CATEGORIES` 상수 테이블에서 카테고리로 결정하도록 만들었다. 새 아이템은 `category`만 정확히 넣으면 스택 한도와 버림 가능 여부가 자동으로 맞춰진다.

| category | 최대 스택 | 버릴 수 있음 |
| --- | --- | --- |
| material (재료·씨앗 포함) | 99 | O |
| dish (완성 요리) | 99 | O |
| furniture (가구) | 99 | O |
| gift (선물) | 5 | O |
| tool (도구) | 1 | X |
| rat_poison (쥐약) | 1 | X |
| memento (추억의 물건) | 1 | X |
| recipe (레시피) | 1 | X |
| quest_item (퀘스트 아이템, 아직 구체 아이템 없음) | 1 | X |

## `memento_*` 아이템은 파일에 없다 — 런타임에 자동 생성됨

추억의 물건 13종은 `items.json`에 직접 적지 않았다. 대신 `InventoryManager._register_memento_items()`가 부팅 시 `NPCManager`가 로드한 13개 `data/npc/<id>.json`의 `memento_item.name`/`description`을 그대로 읽어 `memento_<npc_id>` 아이템(예: `memento_belje`)을 자동으로 카탈로그에 등록한다. 이름/설명을 두 군데서 따로 관리하지 않기 위한 선택이며, NPC 쪽 내용을 고치면 인벤토리 쪽도 자동으로 같이 바뀐다.

또한 `NPCManager.memento_received` 신호를 구독해서, 호감도 100 달성으로 NPC가 물건을 건네는 순간 자동으로 `add_item("memento_<npc_id>", 1)`을 호출한다. **단, 그 시점에 인벤토리가 가득 차 있으면 지급이 실패하고 경고만 출력된다** — `inventory.md`가 이 예외 상황을 규정하지 않아서, 별도의 "칸 무시하고 무조건 지급" 같은 로직은 만들지 않았다. 추억의 물건을 절대 놓치지 않게 하고 싶다면 별도로 알려주면 그 규칙을 추가하겠다.

## InventoryManager가 제공하는 것

* `add_item` / `remove_item`(시스템용, 버림 제한 무시) / `discard_item`(플레이어용, 버림 제한 적용) / `has_item` / `get_item_count` / `find_slot_index`
* `sort_by_name()` — 이름순 정렬 (기획 문서에 있는 유일한 정렬 방식)
* `expand_slots()` — 10→15→...→30, 5칸씩. 결제 로직은 없음(그건 `shop.md` 몫) — 상점 시스템이 결제를 확인한 뒤 이 함수만 호출하면 됨
* 퀵슬롯 8칸: `assign_quick_slot` / `get_quick_slot_item` / `clear_quick_slot` — 아이템 id로 저장하므로 `sort_by_name()`으로 슬롯이 뒤섞여도 퀵슬롯이 깨지지 않는다
* `give_gift(npc_id, slot_index)` — 하루 1회 제한(`TimeManager.day_changed`에 맞춰 매일 초기화), `gift` 카테고리인지 확인, 소모 후 `NPCManager.give_gift()` 호출까지 한 번에 처리
* `learn_recipe(slot_index)` — 레시피 아이템을 소모하고 `recipe_learned` 신호 발생. 실제로 "배운 레시피 목록"에 등록하는 건 아직 없는 요리/도감 시스템 몫
* `remove_memento(npc_id)` — 도감에 등록되면 추억의 물건을 자동 삭제하는 규칙을 위한 훅. 아직 없는 도감 시스템이 호출하면 됨
