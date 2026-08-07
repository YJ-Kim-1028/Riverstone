# 플레이어의 음식점
- 음식점 주인 : 플레이어

## 기본 기능

- 플레이어의 요리 기능
- NPC의 식사 기능

---

## 요리대

플레이어는 요리대를 통해 요리를 만들 수 있다.
만들어진 요리는 바로 앞에 연결된 식탁에 자동으로 서빙된다.

---

## 오픈 팻말

플레이어는 오픈 팻말을 클릭하여 OPEN / CLOSE 2개의 상태로 변경할 수 있다.

---

# Object Layer
Tiled에 제작된 Object Layer 설명

## Warp
* restaurant_out : 플레이어의 음식점 밖으로 이동
* backyard_in : 음식점 뒷 마당으로 이동

## Spawn
* restaurant_enterance : 플레이어가 음식점 안으로 이동했을 때, 생성되는 위치
* restaurant_enterance_bakcyard : 플레이어가 음식점 뒷 마당에서 음식점으로 이동할 때, 생성되는 위치.
* restaurant_seat1 : NPC가 앉는 식탁 1
* restaurant_seat2 : NPC가 앉는 식탁 2
* restaurant_seat3 : NPC가 앉는 식탁 3

## Interactable
* restaurant_cooking1 : 플레이어가 사용하는 요리대 1
* restaurant_cooking2 : 플레이어가 사용하는 요리대 2
* restaurant_cooking3 : 플레이어가 사용하는 요리대 3
* restaurant_open : 플레이어가 음식점을 열고 닫을 때 상호작용할 수 있는 팻말