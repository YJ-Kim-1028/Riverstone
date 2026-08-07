# 서점
- 집 주인 : 어셔(usher)

## 기본 기능

- 레시피 구매
- 음악 구매

---

## 계산대
플레이어는 계산대와 상호작용함으로서 기본 레시피 몇 가지와 음악을 구매할 수 있다. 

---

# Object Layer
Tiled에 제작된 Object Layer 설명

## Warp
* book_out : 서점 밖으로 이동

## Spawn
* book_enterance : 플레이어가 서점 안으로 이동했을 때, 생성되는 위치
* book_working : 집의 주인이 서 있는 위치. 해당 위치에 집 주인 NPC가 서있을 때만 구매가 가능.
* book_looking : 서점을 놀러온 NPC가 서있는 위치.

## Interactable
* cash_register : 플레이어가 해당 위치와 상호작용 시, 구매 창을 띄워줌. 구매 목록은 shop_id로 확인.