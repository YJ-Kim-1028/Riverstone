# 병원
- 집 주인 : 이샤(isha)

## 기본 기능

- 디버프 해제 아이템 구매

---

## 계산대
플레이어는 계산대와 상호작용함으로서 물품을 구매할 수 있다. 

---

# Object Layer
Tiled에 제작된 Object Layer 설명

## Warp
* hospital_out : 병원 밖으로 이동

## Spawn
* hospital_enterance : 플레이어가 병원 안으로 이동했을 때, 생성되는 위치
* hospital_working : 집의 주인이 서 있는 위치. 해당 위치에 집 주인 NPC가 서있을 때만 구매가 가능.
* hospital_lying : 병원에 치료받으러 온 NPC가 누워있는 위치.
* hospital_sitting : 병원에 진료보러 온 NPC가 앉아있는 위치.

## Interactable
* cash_register : 플레이어가 해당 위치와 상호작용 시, 구매 창을 띄워줌. 구매 목록은 shop_id로 확인.