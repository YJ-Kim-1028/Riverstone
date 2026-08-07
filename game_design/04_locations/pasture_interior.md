# 목장 가게
- 집 주인 : 벨제(belje), 셰퍼드(shepherd)

## 기본 기능

- 돼지, 소, 여물 구매
- 양동이 구매 (딱 한번만 구매 가능)

---

## 계산대
플레이어는 계산대와 상호작용함으로서 물품을 구매할 수 있다. 

---

# Object Layer
Tiled에 제작된 Object Layer 설명

## Warp
* pasture_out : 목장 가게 밖으로 이동

## Spawn
* pasture_enterance : 플레이어가 목장 가게 안으로 이동했을 때, 생성되는 위치
* pasture_working : 집의 주인이 서 있는 위치. 해당 위치에 집 주인 NPC가 서있을 때만 구매가 가능.
* pasture_looking : 목장 가게를 놀러온 NPC가 구경하는 위치.

## Interactable
* cash_register : 플레이어가 해당 위치와 상호작용 시, 구매 창을 띄워줌. 구매 목록은 shop_id로 확인.