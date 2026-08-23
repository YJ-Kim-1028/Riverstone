# 주크박스 노래 목록 (`data/jukebox/songs.json`)

레스토랑의 주크박스(`jukebox` Interactable, `restaurant_interior_new.tmx`)에서 고를 수 있는 곡 목록. `JukeboxManager`(scripts/autoload/jukebox_manager.gd)가 부팅 시 읽는다.

## 스키마

```json
"song_id": {
    "id": "song_id (위 키와 동일하게)",
    "name": "주크박스 UI에 표시할 곡 이름",
    "bgm_path": "res://assets/audio/bgm/파일명.mp3",
    "icon": "res://assets/icon/Records.png",
    "icon_index": 0,
    "unlocked_by_default": false,
    "item_id": "구매로 해금하는 경우, data/items/items.json에 등록한 아이템 id"
}
```

- `icon`/`icon_index`: `assets/icon/Records.png`(사용자가 직접 그려 넣음)는 16x16씩 여러 칸이 가로로 이어진 시트 - `icon_index`는 그 칸 순번(0부터, 왼쪽이 0번). `items.json`의 `Tools.png`/`Food.png`와 완전히 동일한 슬라이싱 규칙(`JukeboxManager.get_song_icon_texture()`가 `InventoryManager.get_item_icon_texture()`와 같은 방식으로 자름). 지금은 6곡 미만이라 한 줄(icon_row 생략 = 0번째 줄)만 쓴다 - 더 늘어나면 `icon_row`로 다음 줄도 쓸 수 있음.
- `unlocked_by_default: true`면 처음부터 선택 가능(구매 필요 없음) - `item_id` 없이 이 필드만 있으면 됨.
- `unlocked_by_default`가 없거나 false면 `item_id`가 필수 - 그 아이템을 인벤토리에 소지하고 있어야만(`InventoryManager.has_item`) 주크박스에서 선택 가능해진다. 책과 동일한 방식(소비되지 않고 계속 들고 있어야 해금 상태 유지, `inventory_manager.gd`의 `NON_DISCARDABLE_CATEGORIES`에 `"record"` 포함됨) - 우클릭 등 별도 "배우기" 액션 없이 그냥 갖고 있으면 자동으로 해금된 것으로 취급.

## 현재 상태

`song_nice_to_serve_you` 1개만 채워져 있다 - 기본 레스토랑 브금(`bgm_restaurant.mp3`)을 그대로 가리키며, `Records.png`의 0번 칸 아이콘을 쓰고, 처음부터 무료로 해금되어 있다(사용자 확정 - 상점에는 등록하지 않음).

## 새 곡 추가하는 법 (구매 가능한 곡)

사용자가 `assets/audio/bgm/`에 추가로 넣어둔 곡 2개(`bgm_chiptune.mp3`, `bgm_city_pop.mp3`)는 아래 3곳에 전부 등록해야 실제로 상점에서 사서 주크박스에 쓸 수 있다(책 시스템과 동일한 3단 구조):

1. **`data/items/items.json`**: `category: "record"`인 아이템 신규 등록 (예: `book_*` 아이템들 참고 - `description`은 채우고, `icon`/`icon_index`는 아래처럼 `Records.png`를 그대로 재사용)
2. **`data/shop/shops.json`**: `usher_shop.stock` 배열에 `{"item_id": "...", "price": ..., "purchase_limit": 1}` 추가
3. **`data/jukebox/songs.json`**: 이 파일에 새 곡 항목 추가 - `bgm_path`는 실제 넣어둔 mp3 경로, `item_id`는 1번에서 만든 아이템 id와 동일하게, `icon`은 `res://assets/icon/Records.png`, `icon_index`는 `Records.png`에서 그 곡에 해당하는 칸 번호(1, 2, ...)

`Records.png`의 칸 순서와 `icon_index` 값이 항상 일치해야 한다 - 새 칸을 그려 넣을 때마다 이 파일과 `items.json` 양쪽의 `icon_index`를 같이 맞출 것.
