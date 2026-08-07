# 광장

1. Home.tmx
2. plaza1.tmx
3. plaza2.tmx
4. plaza3.tmx
5. plaza4.tmx
6. plaza5.tmx

# 건물 내부

## 명명 규칙
_interior.tmx 로 끝난다.

## 목록
1. book_interior.tmx : 서점 내부
2. cafe_interior.tmx : 카페 내부
3. cowshed_interior.tmx : 플레이어 소유의 외양간 내부
4. farm_interior.tmx : 농가게 내부
5. fish_interior.tmx : 낚시가게 내부
6. furniture_interior.tmx : 가구점 내부
7. general_interior.tmx : 잡화점 내부
8. home_interior.tmx : 플레이어 소유의 집 내부
9. hospital_interior.tmx : 병원 내부
10. pasture_interior.tmx : 목장가게 내부
11. police_interior.tmx : 경찰서 내부
12. restaurant_interior.tmx : 플레이어 소유의 음식점 내부
13. shrine_interior.tmx : 신당 내부
14. temple_interior.tmx : 절 내부

# 레이어 설명

## Tile Layer
1. Furniture : 가구 레이어
2. Deco : 데코레이션 레이어
3. Wall : 벽 레이어 
4. Wall_Deco : 벽 붙이 데코레이션 레이어
5. Carpet : 카페트 레이어
6. Tile : 바닥 타일 레이어
7. Light : 불빛 레이어 > 불빛 효과 적용 필요
8. Deco_under : 플레이어가 밟고 설 수 있는 데코레이션 레이어 (ex. 방석, 꽃 등)
9. Pillar : 기둥 레이어
10. 2ndFloor : 2층 레이어
11. Deco_above : 플레이어가 밟아서는 안되는 데코레이션 레이어 (ex. 나무)
12. Ground : 기본 풀밭 레이어
13. Path : 길 레이어. npc는 path 레이어 위만을 지나다닐 수 있다.
14. Water : 바다 레이어 > 물결 효과 적용 필요
15. Pond : 연못 레이어 > 물결 효과 적용 필요
16. TreeBehind : 건물 뒤에 있는 나무 레이어 (약간 가려짐)
17. Buildings : 건물 레이어
18. Farmable : 작물 심기가 가능한 레이어

## Object Layer
1. Warp : 다른 곳으로 이동하는 기능 오브젝트 레이어
2. Spawn : NPC의 위치를 지정한 오브젝트 레이어
3. Interactable : 플레이어와 상호작용이 가능한 오브젝트 레이어

### Custom Properties
Object Layer에 있는 Custom Properties에 대한 설명이다.

* target_name : 플레이어가 이동할 맵 이름
* target_spawn : 플레이어가 이동할 맵에 있는 Spawn 지점

* shop_id : 플레이어가 현재 상호작용 중인 가게