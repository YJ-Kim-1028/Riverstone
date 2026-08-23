# 가구/바닥장식/벽장식 필드 (`data/items/items.json`, `category: "furniture"`/`"floor_decor"`/`"wall_decor"`)

가구점(`woody_shop`)에서 사서 자유 배치하는 아이템들의 추가 필드. 세 카테고리 모두 스키마는 완전히 동일하고, 배치 규칙만 다르다.

| 카테고리 | 담당 매니저 | 배치 가능한 맵 | 특이사항 |
| --- | --- | --- | --- |
| `furniture` | `FurnitureManager`(scripts/autoload/furniture_manager.gd) | `Home`(마당) + `home_interior`(집 내부) | 다른 가구와 겹칠 수 없고, 이동을 막는다 |
| `floor_decor` | `FloorDecorManager`(scripts/autoload/floor_decor_manager.gd) | `Home` + `home_interior` (가구와 동일) | 다른 바닥장식과만 겹침 판정, 가구/이동을 막지 않는다(러그/카펫 위에 가구를 놓을 수 있고 밟고 지나다닐 수 있음) |
| `wall_decor` | `WallDecorManager`(scripts/autoload/wall_decor_manager.gd) | `home_interior`만(`Wall` 레이어가 있는 유일한 배치 가능 맵) | 실제 `Wall` 타일 칸에만 설치 가능(`WorldMap.is_wall_cell()`), 이동 차단 로직 자체를 안 씀(벽은 원래 항상 막혀있음) |

## 회수(가구용 망치)

세 카테고리 전부 회수(E키)는 `furniture_hammer`(가구용 망치, `category: "tool"`)를 손에 장착하고 있을 때만 동작한다(`main.gd._is_furniture_hammer_equipped()`) - 그냥 지나갈 때마다 "E 가구 회수" 프롬프트가 뜨는 게 거슬린다는 사용자 피드백으로 추가됨. 망치는 `woody_shop`에서 `furniture`/`floor_decor`/`wall_decor` 중 아무거나 하나라도 처음 사면 자동으로 선물 지급된다(`ShopManager._grant_furniture_hammer_if_needed()`) - 상점에 별도로 등록되어 팔리는 아이템이 아니다. 도구 카테고리라 한번 받으면 버릴 수 없다.

## 스키마 (기존 아이템 필드에 추가되는 것만, 세 카테고리 공통)

```json
"item_id": {
    "category": "furniture",
    "slot": "hand",
    "stack_limit": 1,
    "icon": "res://assets/img/furniture/item_id_icon.png",
    "icon_index": 0,
    "icon_color": "",
    "world_sprite": "res://assets/img/furniture/item_id.png",
    "footprint_width": 1,
    "footprint_height": 1,
    "overhang_below": false,
    "emits_light": false
}
```

- `slot: "hand"` - 필수. 없으면 손에 장착 자체가 안 돼서 설치할 방법이 없다.
- `stack_limit: 1` - 보관 상자와 동일하게 한 번에 하나씩만 들고 설치한다.
- `footprint_width`/`footprint_height` - 바닥(또는 벽)에서 실제로 판정에 쓰이는 칸 수(타일 단위, 16px = 1칸). **그림 크기가 아니라 판정 칸 수**다 - 그림은 이보다 위/아래로 더 길게 그릴 수 있다(아래 `world_sprite` 참고). `wall_decor`는 관례상 대부분 1~3칸 가로로만 쓰지만 코드 자체는 footprint 크기에 제한이 없고, `floor_decor`는 카펫처럼 여러 칸이어도 된다.
- `world_sprite` - 설치된 모습 전용 텍스처. 파일이 없으면(`ResourceLoader.exists()` 실패) `icon_color`로 채운 자리표시자(가로 `footprint_width*16`, 세로 `footprint_height*16`)를 대신 그린다 - 그림 없이도 바로 테스트 가능.
- `icon`/`icon_color` - 인벤토리/상점용 16x16 아이콘. `icon_color`가 비어있지 않으면 그 색 단색 아이콘이 `icon`보다 우선 적용되므로, 실제 아이콘 그림을 쓰려면 `icon_color`를 반드시 빈 문자열로 둬야 한다. `icon`은 16x16 그림 1장짜리 "시트"로 취급되어 `icon_index`(기본 0)로 잘라 쓴다 - 이미지 자체가 정확히 16x16이면(예: `candle.png`) `world_sprite`와 같은 파일을 `icon`에도 그대로 재사용할 수 있다(별도 아이콘 안 그려도 됨).
- `overhang_below`(기본 false) - 그림이 footprint보다 세로로 길 때 어느 쪽으로 튀어나오는지. 기본은 위로 튀어나오지만(등받이 있는 의자 등), `bed`처럼 충돌이 그림 위쪽(머리맡)에 있고 그림이 아래로 튀어나와야 하면 `true`로 둔다. `furniture` 카테고리에서만 읽는다(floor_decor/wall_decor는 아직 이 필드를 안 씀).
- `emits_light`(기본 false) - true면 배치 시 그 자리에 실제 조명(`PointLight2D`, 가로등과 동일 시스템)이 켜진다. 마당에 놓으면 가로등처럼 밤에만 밝아지고, 집 안에 놓으면 방 전등처럼 항상 켜져 있다.

## 그림 그려서 줄 때 규격

- **아이콘**: 16x16px 1장(인벤토리/상점 목록용). 없어도 `icon_color`로 자리표시자가 나온다.
- **설치 모습(`world_sprite`)**: 가로는 반드시 `footprint_width * 16` px 정확히(가로 오버행 없음). 세로는 `footprint_height * 16` px 이상이면 됨 - `overhang_below`가 false(기본)면 위로, true면 아래로 더 길게 그릴 수 있다. **충돌 판정이 있는 쪽 가장자리를 이미지 캔버스의 그쪽 끝에 딱 붙여서** 그리면(기본은 아래쪽/발밑) 판정 칸 정렬은 코드가 알아서 계산한다. `floor_decor`는 오버행 없이 항상 `footprint*16` 크기 그대로 쓴다(바닥에 딱 붙는 평면 그림이라 튀어나올 이유가 없음).
- **색상 커스터마이징**: 회색 3단계(`D6D6D6`/`A8A8A8`/`727272`, 명암 자동 계산)/마젠타(`FF00FF`, 플랫)/형광녹색(`00FF66`, 플랫) 마커로 칠한 부분은 상점에서 구매할 때 사용자가 직접 색을 고를 수 있다(그림에 마커가 없으면 그 아이템은 커스터마이징 없이 바로 구매됨) - 자세한 내용은 `scripts/world/furniture_appearance.gd` 참고.
- 회전은 지원하지 않는다(사용자 확정) - 그린 방향 그대로 한 방향으로만 배치된다.

## 현재 상태 (2026-08-10)

실제로 그려진 그림이 전부 `assets/img/furniture/` 한 폴더에 있다(카테고리와 무관하게) - `floor_decor`/`wall_decor` 폴더는 만들어만 두고 실제로는 안 쓰는 중. 전부 `woody_shop`(가구점) stock에 등록되어 구매/배치 가능.

- `furniture`(20개): `chair`, `sofa`, `display_table`, `bookshelf_33`/`bookshelf_23`/`bookshelf_22`(책장 3종, 아이콘 공유), `cabinet_23`, `kitchen_cabinet`(수납장 2종, 아이콘 공유), `jukebox`, `glass_display_shelf`, `blinder`, `drink_fridge`, `stove`, `desk`, `vase_1`~`vase_4`(꽃병 4종, 아이콘 공유), `bed`(`overhang_below: true`), `iron_cabinet`, `flowerpot`(아직 자리표시자 그림 없음).
- `furniture`(조명 5개, `emits_light: true`): `light`, `standing_light`, `candle`(아이콘도 `candle.png` 재사용), `shrine_light`, `temple_light`.
- `floor_decor`(4개): `round_carpet`, `rect_carpet`, `rect_carpet_2`(아이콘 그림 아직 없음, `icon_color` 자리표시자), `welcome_carpet`.
- `wall_decor`(1개): `memo`(3x2, footprint 크기가 그림과 정확히 일치 - 벽 6칸이 다 `Wall` 타일이어야 설치 가능).

미사용 상태로 남아있는 `assets/img/furniture/carpet.png`/`carpet_icon.png`는 여전히 어떤 아이템에도 연결되어 있지 않다.

## 새 가구/바닥장식/벽장식 추가하는 법

1. `data/items/items.json`에 `category: "furniture"`/`"floor_decor"`/`"wall_decor"` 아이템 추가(위 스키마 그대로)
2. `data/shop/shops.json`의 `woody_shop.stock`에 `{"item_id": "...", "price": ...}` 추가
3. 그림 준비되면 `world_sprite`/`icon` 경로에 파일 채우기 - 코드 변경 불필요
