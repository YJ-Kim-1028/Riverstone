extends Node2D

## Shows a plated-dish sprite on the table ("restaurant_dishN" Spawn point in
## restaurant_interior.tmx) the moment a dish is served, and removes it once
## the NPC finishes eating (RestaurantManager.npc_departed). Positions are
## read once via WorldMap.parse_spawns() rather than depending on a live
## WorldMap instance, same trick NPCManager uses for its schedule spawns -
## this layer only matters on the "restaurant_interior" map, which may not
## even be the currently loaded one.

const RESTAURANT_MAP_ID := "restaurant_interior"
## player.tscn/npc_sprite.tscn 둘 다 z_index=0이고, home_map.gd의
## Y_SORT_Z_INDEX(타일 쪽 Y-sort 대상)도 0이다 - 처음에 8을 썼던 건 확인 없이
## 넘겨짚은 잘못된 값이었다(사용자 리포트로 재확인, 실제로는 플레이어/NPC 모두
## 0). z_index만 맞춘다고 되는 게 아니라, 이 레이어 자체가 HomeMap 밖에 있어서
## Y-sort 그룹이 달라 실제 위치와 무관하게 항상 한쪽으로 고정되어 그려지는
## 근본 문제가 있었다 - 그래서 스프라이트를 이 레이어의 자식이 아니라, npc_sprite
## 처럼 실제 로드된 WorldMap(HomeMap)의 자식으로 붙여서 Y-sort 그룹 자체에
## 참여시킨다(_ensure_sprite 참고).
const DISH_Z_INDEX := 0
## 접시가 놓인 책상(desk1~3)은 YSortAnchor로 2행이 묶여서 Y-sort 기준이 자기
## 칸(7행, 접시 스폰 y=112)이 아니라 앵커 전체의 맨 아래 행(8행, y=128~144
## 구간)이다 - 접시 위치를 그대로 position으로 쓰면 책상보다 "뒤"로 취급돼서
## 책상 밑에 파묻힌 것처럼 보였다(사용자 리포트). 책상 타일이 실제로 그려지는
## 레이어 이름 - restaurant_interior_new.tmx 확인 결과 desk 타일들은 전부
## "Furniture" 레이어에 있다.
const DESK_LAYER_NAME := "Furniture"

## 손님이 떠나며 실제로 돈을 낼 때(paid_amount > 0) "restaurant_seatN" 자리
## 위로 띄우는 "+금액" 텍스트(사용자 지시 - NPC 머리 위에 표시). 접시 스프라이트와
## 달리 Y-sort 대상이 아니라 항상 맨 앞에 떠서 위로 사라지는 연출이라
## Y_SORT_Z_INDEX(0)보다 높은 값을 쓴다.
const PAID_TEXT_Z_INDEX := 2
const PAID_TEXT_HEAD_OFFSET := Vector2(0, -20)
const PAID_TEXT_RISE_DISTANCE := 12.0
const PAID_TEXT_DURATION := 0.9
const PAID_TEXT_FONT_SIZE := 6
const PAID_TEXT_COLOR := Color(1.0, 0.85, 0.2)
## 수익 표시가 배경이랑 잘 안 구분된다는 지적(사용자 지시, 2026-09-01 -
## 플레이테스트 31번, 검은 테두리 + 노란 글씨로) - 프로젝트 기존 관례와
## 동일한 두께(hud.tscn 등).
const PAID_TEXT_OUTLINE_COLOR := Color(0, 0, 0, 1)
const PAID_TEXT_OUTLINE_SIZE := 2

var _active_sprites: Dictionary = {}
var _dish_spawns: Dictionary = {}


func _ready() -> void:
	_dish_spawns = WorldMap.parse_spawns(String(WorldMap.MAP_PATHS[RESTAURANT_MAP_ID]))
	RestaurantManager.dish_served.connect(_on_dish_served)
	RestaurantManager.npc_departed.connect(_on_npc_departed)
	GameManager.map_changed.connect(_on_map_changed)
	_reconcile()


func _on_dish_served(_station_index: int, _npc_id: String, _dish: Dictionary) -> void:
	_reconcile()


func _on_npc_departed(station_index: int, _npc_id: String, paid_amount: int) -> void:
	if paid_amount > 0 and GameManager.current_map_id == RESTAURANT_MAP_ID:
		_spawn_paid_text(station_index, paid_amount)
	_remove_sprite(station_index)


## 서빙 즉시(호감도 반영)가 아니라 손님이 떠나는 이 순간에 실제로 돈을 받으므로
## (RestaurantManager 참고), 시각 효과도 여기서 함께 띄운다.
func _spawn_paid_text(station_index: int, paid_amount: int) -> void:
	var seat_position: Vector2 = _dish_spawns.get("restaurant_seat%d" % (station_index + 1), Vector2.INF)
	if seat_position == Vector2.INF:
		return
	var label := Label.new()
	label.text = "+%d" % paid_amount
	label.add_theme_font_size_override("font_size", PAID_TEXT_FONT_SIZE)
	label.add_theme_color_override("font_color", PAID_TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", PAID_TEXT_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", PAID_TEXT_OUTLINE_SIZE)
	label.z_index = PAID_TEXT_Z_INDEX
	label.position = seat_position + PAID_TEXT_HEAD_OFFSET
	var home_map := get_parent().get_node_or_null("HomeMap")
	if home_map != null:
		home_map.add_child(label)
	else:
		add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0, -PAID_TEXT_RISE_DISTANCE), PAID_TEXT_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, PAID_TEXT_DURATION)
	tween.chain().tween_callback(label.queue_free)


func _on_map_changed(_map_id: String) -> void:
	_reconcile()


func _reconcile() -> void:
	if GameManager.current_map_id != RESTAURANT_MAP_ID:
		for station_index in _active_sprites.keys().duplicate():
			_remove_sprite(station_index)
		return
	for station_index in RestaurantManager.STATION_COUNT:
		var dish := RestaurantManager.get_station_dish(station_index)
		if dish.is_empty():
			_remove_sprite(station_index)
		else:
			_ensure_sprite(station_index, dish)


func _ensure_sprite(station_index: int, dish: Dictionary) -> void:
	if _active_sprites.has(station_index):
		return
	var spawn_name := "restaurant_dish%d" % (station_index + 1)
	var position: Vector2 = _dish_spawns.get(spawn_name, Vector2.INF)
	if position == Vector2.INF:
		push_warning("No dish spawn point found: %s" % spawn_name)
		return
	var texture := CookingManager.get_recipe_icon_texture(String(dish.get("id", "")))
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = DISH_Z_INDEX
	var home_map := get_parent().get_node_or_null("HomeMap")
	if home_map != null:
		# main.gd._update_restaurant_sign()의 팻말 오버레이와 정확히 같은
		# 트릭 - Y-sort 비교용 position은 책상 앵커의 실제 아랫변으로 옮기고,
		# 화면에 그려지는 자리는 offset으로 원래 접시 스폰 좌표로 되돌린다.
		var cell := Vector2i(int(position.x) / WorldMap.TILE_SIZE, int(position.y) / WorldMap.TILE_SIZE)
		var sort_y: float = home_map.get_tile_sort_y(cell, DESK_LAYER_NAME)
		sprite.position = Vector2(position.x, sort_y)
		sprite.offset = Vector2(0, position.y - sort_y)
		home_map.add_child(sprite)
	else:
		sprite.position = position
		add_child(sprite)
	_active_sprites[station_index] = sprite


func _remove_sprite(station_index: int) -> void:
	var sprite: Sprite2D = _active_sprites.get(station_index)
	if sprite != null:
		sprite.queue_free()
		_active_sprites.erase(station_index)
