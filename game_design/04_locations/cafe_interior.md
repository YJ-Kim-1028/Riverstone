# 카페
- 집 주인 : 모카(mocha)

## 기본 기능

- 버프 아이템 구매

---

## 계산대
플레이어는 계산대와 상호작용함으로서 커피를 구매할 수 있다. 

---

# Object Layer
Tiled에 제작된 Object Layer 설명

## Warp
* cafe_out : 카페 밖으로 이동

## Spawn
* cafe_enterance : 플레이어가 카페 안으로 이동했을 때, 생성되는 위치
* cafe_working : 집의 주인이 서 있는 위치. 해당 위치에 집 주인 NPC가 서있을 때만 구매가 가능.
* cafe_looking : 카페를 놀러온 NPC가 빵을 구경하는 위치.
* cafe_standing : 카페를 놀러온 NPC가 병아리를 구경하는 위치.
* cafe_sitting : 카페를 놀러온 NPC가 앉아있는 위치.

## Interactable
* cash_register : 플레이어가 해당 위치와 상호작용 시, 구매 창을 띄워줌. 구매 목록은 shop_id로 확인.