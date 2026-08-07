# Save System

## 개요

게임은 JSON 기반 SaveData를 사용한다.

* 저장 슬롯 : 3개
* 자동 저장
  * 취침 시
  * 맵 이동 시
* 수동 저장
  * 집 내부 침대에서 가능

---

## SaveData 구조

### Player

저장해야 하는 데이터

* 이름
* 소지금
* 현재 날짜
* 현재 시간
* 현재 요일
* 현재 맵
* 플레이 시간
* 인벤토리
* 메일함

---

### Player Progress

* 집 레벨
* 해금된 레시피
* 도감 진행도

---

### NPC

모든 NPC는 다음 정보를 저장한다.

* 호감도
* 생존 여부
* 현재 위치
* 오늘 대화 여부
* 오늘 선물 여부
* 추억의 물건 획득 여부

---

### Horror

공포 시스템 관련 데이터

* 살해 당한 npc들
* 첫 번째 살인 발생 여부
* 두 번째 살인 발생 여부
* 경찰 체포 여부
* 스토커 살해 여부
* 공범 엔딩 달성 여부
* 스토커 동거 상태 여부
* 어셔 사망 방식 (player_killed / self_killed)

---

### Restaurant

* 오늘 방문한 손님
* 초대한 NPC

---

### World

* 날씨
* 맵 상태
* 배치한 가구
* 건물 위치

---

## Save Example

```json
{
  "player_name": "Player",
  "money": 15000,
  "day": 12,
  "map": "home",
  "play_time": 3600,

  "npc": {
    "mar": {
      "affection": 50,
      "alive": true
    }
  },

  "horror": {
    "stalker_id": "usher",
    "murder_count": 1
  }
}
```

---

## 규칙

* SaveData 구조는 사용자 승인 없이 변경할 수 없다.
* 저장 데이터는 하위 호환성을 유지해야 한다.
* 새로운 시스템 추가 시 SaveData 영향 여부를 반드시 검토한다.
* 모든 저장 데이터는 JSON으로 관리한다.
* 삭제된 NPC도 SaveData에서는 기록을 유지한다.
