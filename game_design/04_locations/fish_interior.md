# 낚시가게
- 집 주인 : 로시(roshi), 마린(marin)

## 기본 기능

- 낚시대 구매 (딱 한번만 구매 가능)
- 미끼 구매 (도트를 찍지 않아 추후 추가 예정 ...)

---

## 계산대
플레이어는 계산대와 상호작용함으로서 낚시대를 구매할 수 있다. 

---

# Object Layer
Tiled에 제작된 Object Layer 설명

## Warp
* fish_out : 낚시가게 밖으로 이동

## Spawn
* fish_enterance : 플레이어가 낚시가게 안으로 이동했을 때, 생성되는 위치
* fish_working : 집의 주인이 서 있는 위치. 해당 위치에 집 주인 NPC가 서있을 때만 구매가 가능.

## Interactable
* cash_register : 플레이어가 해당 위치와 상호작용 시, 구매 창을 띄워줌. 구매 목록은 shop_id로 확인.