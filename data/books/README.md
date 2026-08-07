# 어셔의 책 내용 (`data/books/books.json`)

서점(`usher_shop`)에서 파는 책 10종의 실제 본문. `data/items/items.json`의 `book_*` 아이템 id와 1:1로 대응한다.

`BookManager`(scripts/autoload/book_manager.gd)가 부팅 시 읽는다. 인벤토리에서 책 아이템을 우클릭하면(category `"book"`) 소비되지 않고 `book_screen`(도감 UI와 같은 계열의 책 UI)이 열려 이 내용을 보여준다.

## 스키마

```json
"book_id": {
    "title": "표시용 제목 (items.json의 name과 보통 동일)",
    "author": "어셔",
    "pages": [
        "1페이지 본문. \\n으로 줄바꿈.",
        "2페이지 본문...",
        "..."
    ]
}
```

`pages`는 배열이며, 책 UI의 이전/다음 버튼으로 한 페이지씩 넘어간다. 페이지 수는 자유(1개도 가능, 여러 개도 가능).

## 현재 상태

`book_beyond_the_door`("문 너머에는") 1개만 예시로 3페이지 채워뒀다(Claude가 임의로 작성 - 게임 스토리/사건과 무관한 순수 창작 분위기 글이라 안전하게 예시로만 쓸 것). 나머지 9권은 `["TODO: 기획자 작성 예정"]`으로 비워뒀으니 원하는 내용으로 그대로 교체하면 된다.

새 책을 추가할 때는 `data/items/items.json`에 `book_*` 아이템도 같이 추가하고 `data/shop/shops.json`의 `usher_shop.stock`에도 등록해야 실제로 구매 가능해진다(기존 10권이 그렇게 되어 있다).
