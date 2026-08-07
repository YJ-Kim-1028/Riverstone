@tool
extends Node2D
class_name WorldMap

const DEFAULT_MAP_PATH := "res://assets/map/Home.tmx"
const TILE_SIZE := 16
const WARP_RADIUS := 12.0
const INTERACT_RADIUS := 12.0
const NON_PLAYER_WARP_NAME := "room_in_general"
const SPAWN_ALIASES := {
	"hospital_in": "hospital_enterance",
	"plaza4_enterance": "plaza4_enterance_home",
	"restaurant_enterace_backyard": "restaurant_enterance_backyard",
}
const WARP_OVERRIDES := {
	"farm_interior:farm_out": {"target_map": "plaza2", "target_spawn": "farm_exit"},
}

## game_design/04_locations/01_overview.md의 "Water/Pond 레이어 - 물결 효과
## 적용 필요" TODO - 시도해봤지만(위치 이동 → 어지러움, 전체 밝기 펄스 → 타일
## 경계가 네모나게 도드라짐, 반짝임 점만 깜빡 → 효과가 안 보이는데 타일마다
## 셰이더 재질이 붙어서 배칭이 깨져 렉만 생김) 결과가 안 좋아서 포기함(사용자
## 확정, 2026-08-03). 나중에 다시 시도하면 타일 단위 Sprite2D 구조 자체가
## 배칭을 막는다는 점부터 고려해야 한다.

## 3단계 분류.
## 1) FLAT: 평평해서 캐릭터를 가릴 높이가 없는 바닥류 - 항상 캐릭터보다
##    뒤(고정 z). Water/Pond는 한때 "가려지는 쪽"이었는데, 캐릭터 스프라이트가
##    세로로 길어서(32px) 막힌 칸 바로 옆(특히 대각선 모서리)에 서면 위쪽
##    몸이 그 그림에 덮여 파묻힌 것처럼 보인다는 피드백으로 옮겼었다.
##    Buildings도 같은 이유로 여기 있었는데, 그 파묻힘 현상의 진짜 원인이
##    "충돌 검사가 발밑 한 점만 본다"는 버그였다는 게 밝혀져서(플레이어
##    좌우 가장자리도 검사하도록 고침, PlayerController._is_blocked_at)
##    3)번(Y-sort)으로 되돌렸다 - 건물은 담장/가구 같은 다른 세로 오브젝트랑
##    실제 화면 위치로 비교돼야 지붕이 담장에 가려지지 않는다.
const FLAT_LAYERS := {
	"Carpet": true, "Tile": true, "Deco_under": true, "Ground": true,
	"Path": true, "Farmable": true, "Water": true, "Pond": true,
}
## 2) ALWAYS_FRONT: 순수 연출용 오버레이(캐릭터 앞뒤 개념이 없는 그림)만
##    여기 넣는다 - Y-sort 대상이 아니고 항상 맨 위, 고정 z. 원래 "Light"를
##    여기 넣었었는데, Home.tmx의 Light 레이어를 까보니 실제로는 순수 빛
##    효과가 아니라 가로등 몸체/부시 같은 물리적 오브젝트(밑동에
##    collision=true)라서 3)번(Y-sort)으로 옮겼다 - 지금은 빈 목록.
const ALWAYS_FRONT_LAYERS := {}
## 3) 위 둘 다 아닌 나머지 전부(Wall/Pillar/Furniture/FurnitureBehind/
##    2ndFloor/Deco_above/TreeBehind/Deco/Wall_Deco/Door/Tree/Light 등, 목록에
##    없는 레이어도 포함) - 세로로 긴 물건들이라 Y-sort로 캐릭터랑 실제
##    화면상 위치를 비교해서 앞/뒤를 정한다 (player.gd가 y_sort_enabled로
##    같은 그룹에 들어와서 비교됨).
const FLAT_Z_INDEX := -1
const Y_SORT_Z_INDEX := 0
const ALWAYS_FRONT_Z_INDEX := 1
## 레이어 동점 처리용 - 실제 칸 크기(16px)보다 훨씬 작아서 진짜 위치 차이에는
## 영향을 주지 않는다.
const LAYER_PRIORITY_EPSILON := 0.01
## 벽/건물/울타리 같은 막힌 오브젝트는 "충돌이 멈추는 좌표"와 "앞/뒤가
## 뒤바뀌는 좌표"가 지금까지 정확히 같은 값(타일 경계선)이었다 - 그래서
## 플레이어가 그 경계에 딱 붙어 서면(상호작용하려고 벽 앞에 서는 경우 등)
## 부동소수점/프레임 단위 오차로 어느 쪽으로도 판정될 수 있는 애매한 지점이
## 됐다(레스토랑 팻말 앞에서 계속 앞뒤가 뒤집히던 문제 등). Godot 물리엔진의
## "safe margin"과 같은 개념으로, 앞/뒤 전환 기준선을 충돌 경계선보다 이만큼
## 앞(작은 y)으로 당겨서, 충돌이 허용하는 가장 가까운 위치에서도 항상 확실히
## "플레이어가 앞"으로 판정되게 한다.
const SORT_SAFE_MARGIN := 4.0
## NPC 경로탐색(find_path)에서 시작/끝 좌표가 막힌 칸에 딱 걸쳐 있을 때(스폰
## 좌표가 충돌 타일 경계 근처인 경우 등) 주변을 나선형으로 훑어서 가장 가까운
## 빈 칸을 대신 찾아주는 탐색 반경(칸 단위).
const PATHFIND_SEARCH_RADIUS := 6

## Every loadable map, keyed by the id used in Warp target_map/spawn lookups.
## Shared with main.gd (player warps) and NPCManager (schedule -> world
## position resolution) so there is one source of truth for map paths.
const MAP_PATHS := {
	"Home": "res://assets/map/Home.tmx",
	"plaza1": "res://assets/map/plaza1.tmx",
	"plaza2": "res://assets/map/plaza2.tmx",
	"plaza3": "res://assets/map/plaza3.tmx",
	"plaza4": "res://assets/map/plaza4.tmx",
	"plaza5": "res://assets/map/plaza5.tmx",
	"book_interior": "res://assets/interior/book_interior.tmx",
	"cafe_interior": "res://assets/interior/cafe_interior.tmx",
	"cowshed_interior": "res://assets/interior/cowshed_interior.tmx",
	"farm_interior": "res://assets/interior/farm_interior.tmx",
	"fish_interior": "res://assets/interior/fish_interior.tmx",
	"furniture_interior": "res://assets/interior/furniture_interior.tmx",
	"general_interior": "res://assets/interior/general_interior.tmx",
	"home_interior": "res://assets/interior/home_interior.tmx",
	"hospital_interior": "res://assets/interior/hospital_interior.tmx",
	"pasture_interior": "res://assets/interior/pasture_interior.tmx",
	"police_interior": "res://assets/interior/police_interior.tmx",
	"restaurant_interior": "res://assets/interior/restaurant_interior_new.tmx",
	"shrine_interior": "res://assets/interior/shrine_interior.tmx",
	"temple_interior": "res://assets/interior/temple_interior.tmx",
}

@export_file("*.tmx") var map_path := DEFAULT_MAP_PATH

var _map_size := Vector2i.ZERO
var _tilesets: Array[Dictionary] = []
var _spawns: Dictionary = {}
var _warps: Array[Dictionary] = []
var _interactables: Array[Dictionary] = []
var _ysort_anchors: Array[Dictionary] = []
var _blocked_cells: Dictionary = {}
## "Door" 레이어(cowshed_interior.tmx 등)의 칸별 타일 노드 - cell(Vector2i) ->
## Sprite2D. LivestockManager의 외양간 문 여닫기(toggle_door)가 이 타일을
## 숨기고/다시 보이는 데 쓴다. Door 레이어가 없는 맵에서는 항상 비어있다.
var _door_tiles: Dictionary = {}
var _layer_gids: Dictionary = {}
## 레이어이름 -> Tiled에서의 visible 여부. "Farmable"처럼 숨김 처리된 순수
## 데이터 레이어(밭 칸 표시용, 실제로 화면에 그릴 그림이 아님)의 GID는 읽어야
## 하지만 타일을 만들면 안 되므로, 렌더링 단계에서 이 값으로 걸러낸다
## (Warp/Spawn/YSortAnchor 같은 objectgroup은 애초에 타일을 안 만드니 상관없음).
var _layer_visibility: Dictionary = {}
var _light_source_positions: Array[Vector2] = []
## "레이어이름:칸x:칸y" -> 기준 행 (YSortAnchor 오브젝트 레이어에서 계산됨,
## _compute_anchor_bottom_rows() 참고). 여러 행에 걸친 오브젝트(나무/가로등/건물
## 등)의 Y-sort 기준이 되는 유일한 소스 - 앵커가 없는 칸은 자기 행(cell.y)을
## 그대로 기준으로 쓴다(_create_tile 참고).
var _anchor_layer_bottom_row: Dictionary = {}
## NPC 걷기용 경로탐색 격자 - load_map()마다 _blocked_cells를 그대로 반영해서
## 다시 만든다(맵마다 막힌 칸이 다르므로). find_path() 참고.
var _astar := AStarGrid2D.new()


func _ready() -> void:
	load_map(map_path)


func load_map(next_map_path: String) -> void:
	if not FileAccess.file_exists(next_map_path):
		push_error("Map file could not be found: %s" % next_map_path)
		return
	map_path = next_map_path
	_clear_tiles()
	_tilesets.clear()
	_spawns.clear()
	_warps.clear()
	_interactables.clear()
	_ysort_anchors.clear()
	_blocked_cells.clear()
	_door_tiles.clear()
	_layer_gids.clear()
	_layer_visibility.clear()
	_light_source_positions.clear()
	_anchor_layer_bottom_row.clear()

	var parser := XMLParser.new()
	if parser.open(map_path) != OK:
		push_error("Map XML could not be opened: %s" % map_path)
		return

	var layer_name := ""
	var layer_is_visible := true
	var reading_data := false
	var object_group := ""
	var current_object: Dictionary = {}
	while parser.read() == OK:
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			_match_element(parser, layer_is_visible, reading_data, object_group, current_object)
			layer_name = _next_layer_name(parser, layer_name)
			layer_is_visible = _next_layer_visibility(parser, layer_is_visible)
			if parser.get_node_name() == "layer":
				_layer_visibility[layer_name] = layer_is_visible
			reading_data = _is_layer_data(parser)
			object_group = _next_object_group(parser, object_group)
			current_object = _next_object(parser, object_group, current_object)
			# Self-closing <object .../> tags (every Spawn point - they have no
			# child <properties>) never produce a NODE_ELEMENT_END, so they'd
			# never reach _store_object() below. Finalize them immediately.
			if parser.get_node_name() == "object" and parser.is_empty():
				_store_object(object_group, current_object)
				current_object = {}
		elif node_type == XMLParser.NODE_TEXT and reading_data:
			_store_layer_gids(parser.get_node_data(), layer_name)
			reading_data = false
		elif node_type == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "object":
				_store_object(object_group, current_object)
				current_object = {}
			elif parser.get_node_name() == "objectgroup":
				object_group = ""
	# "YSortAnchor" 오브젝트 레이어(기획자가 Tiled에서 세로로 2칸 이상 이어진
	# 그림마다 직접 그려주는 사각형)를 전체 레이어를 다 읽은 뒤 한꺼번에
	# 계산한다(레이어 하나씩 바로 만들면 아직 안 읽은 다른 레이어 데이터를
	# 볼 수 없다).
	_anchor_layer_bottom_row = _compute_anchor_bottom_rows()
	# 같은 칸(또는 같은 행)에 서로 다른 레이어의 타일이 겹쳐 있으면(예: 장식품
	# 레이어와 그 밑 가구 레이어가 같은 행에 있는 경우) Y-sort 기준값이
	# 완전히 같아져서 어느 게 앞으로 그려질지 정해져 있지 않게 된다 - 맵
	# 파일에 나중에 나오는 레이어(보통 나중에 덧그린 장식)가 항상 이기도록
	# 레이어마다 아주 작은 우선순위 값을 더한다(_create_tile 참고).
	var layer_order: Dictionary = {}
	for stored_layer_name in _layer_gids:
		layer_order[stored_layer_name] = layer_order.size()
	for stored_layer_name in _layer_gids:
		if not _layer_visibility.get(stored_layer_name, true):
			continue
		_create_layer_tiles(stored_layer_name, layer_order[stored_layer_name])
	_compute_light_source_positions()
	_rebuild_pathfinding_grid()


func get_map_size() -> Vector2i:
	return _map_size


## "Light" 레이어의 가로등(밑동만 collision=true, 그 위로 기둥/등롱이 이어진
## 모양) 각각의 맨 윗칸 중심 좌표 - 실제 등불이 켜지는 지점(등롱 위치)이라
## 가로등 불빛(PointLight2D 등)을 여기 놓으면 된다. 밑동(collision 좌표)에
## 놓으면 빛이 바닥에서 나는 것처럼 보여서 안 된다.
func get_light_source_positions() -> Array[Vector2]:
	return _light_source_positions


## 맵 타일 위에 겹쳐 그리는 오버레이 스프라이트(레스토랑 팻말의 OPEN/CLOSE
## 그림 등, main.gd가 읽기 전용 맵 파일 대신 그림으로 갈아 끼우는 경우)가
## 원본 타일과 정확히 같은 Y-sort 기준을 쓰도록 돌려주는 조회 함수. 원본
## 타일이 앵커로 묶여서 자기 행이 아닌 더 아래 행을 기준으로 정렬되는 경우
## (예: 벽 타일 위에 그려진 팻말이 벽 전체의 맨 아래 행을 물려받는 경우)
## 오버레이도 그 값을 그대로 따라가게 한다 - layer_name은 오버레이가 덮고
## 있는 원본 타일이 속한 레이어(팻말이면 그 팻말이 얹힌 "Wall" 등)를 넘겨야
## 한다. 원본 타일보다 아주 살짝 더 앞에 그려지도록(레이어 우선순위 합보다
## 확실히 큰 값) 더해서, 오버레이가 원본 타일을 완전히 가린다.
func get_tile_sort_y(cell: Vector2i, layer_name: String) -> float:
	var key := "%s:%d:%d" % [layer_name, cell.x, cell.y]
	var sort_row: int = _anchor_layer_bottom_row.get(key, cell.y)
	return float(sort_row) * TILE_SIZE + TILE_SIZE - SORT_SAFE_MARGIN + 1.0


## 타일셋에서 collision=true로 표시된 타일이 차지한 칸인지 확인한다.
## player.gd가 이동하기 전에 다음 위치를 이걸로 확인해서 충돌을 처리한다.
## 맵 타일 범위 밖(칸 데이터가 아예 없는 칸)은 무조건 막힌 것으로 처리한다 -
## 그렇지 않으면 맵 가장자리(예: 마지막 줄 바로 다음, 존재하지 않는 칸)는
## _blocked_cells에 아무 기록이 없어서 "안 막힘"으로 잘못 판정되고, 캐릭터가
## 벽이 있는 문 옆이라도 맵 맨 끝까지 밀려나면 그 없는 칸을 타고 옆으로
## 자유롭게 빠져나갈 수 있었다.
func is_cell_blocked(world_position: Vector2) -> bool:
	var cell := Vector2i(int(world_position.x) / TILE_SIZE, int(world_position.y) / TILE_SIZE)
	var map_columns := int(_map_size.x / TILE_SIZE)
	var map_rows := int(_map_size.y / TILE_SIZE)
	if cell.x < 0 or cell.y < 0 or cell.x >= map_columns or cell.y >= map_rows:
		return true
	return _blocked_cells.has(cell)


## Water/Pond 레이어 소속 칸인지 - 낚시 캐스팅 판정(바라보는 방향 앞 칸이
## 물인지)에 쓴다. is_cell_blocked()는 벽/가구까지 다 막힌 것으로 보므로
## "물인지"는 따로 구분해야 한다. _layer_gids는 load_map()이 끝난 뒤에도
## 다음 로드 전까지 유지되므로(_compute_light_source_positions()가 이미
## 같은 방식으로 "Light" 레이어를 읽는 선례가 있음) 별도 캐시 없이 바로 조회한다.
func is_water_cell(world_position: Vector2) -> bool:
	var cell := Vector2i(int(world_position.x) / TILE_SIZE, int(world_position.y) / TILE_SIZE)
	var map_columns := int(_map_size.x / TILE_SIZE)
	var index := cell.y * map_columns + cell.x
	for layer_name in ["Water", "Pond"]:
		var gids: Array = _layer_gids.get(layer_name, [])
		if index >= 0 and index < gids.size() and int(gids[index]) != 0:
			return true
	return false


## "Farmable" 레이어 소속 칸인지 - FarmingManager가 괭이질 가능 여부 판정에
## 쓴다. is_water_cell()과 완전히 같은 방식(_layer_gids 조회), 레이어 1개만 본다.
func is_farmable_cell(world_position: Vector2) -> bool:
	var cell := Vector2i(int(world_position.x) / TILE_SIZE, int(world_position.y) / TILE_SIZE)
	var map_columns := int(_map_size.x / TILE_SIZE)
	var index := cell.y * map_columns + cell.x
	var gids: Array = _layer_gids.get("Farmable", [])
	return index >= 0 and index < gids.size() and int(gids[index]) != 0


## AudioManager가 발소리 재생/전환에 쓴다("Path" 밟으면 sfx_footstep,
## "Ground" 밟으면 sfx_groundFootstep, 사용자 지시) - is_water_cell()과 동일한
## _layer_gids 조회 방식. 두 레이어 다 없는 칸(실내 바닥 등)이면 "".
func get_footstep_surface(world_position: Vector2) -> String:
	var cell := Vector2i(int(world_position.x) / TILE_SIZE, int(world_position.y) / TILE_SIZE)
	var map_columns := int(_map_size.x / TILE_SIZE)
	var index := cell.y * map_columns + cell.x
	for layer_name in ["Path", "Ground"]:
		var gids: Array = _layer_gids.get(layer_name, [])
		if index >= 0 and index < gids.size() and int(gids[index]) != 0:
			return layer_name
	return ""


## 이 맵에서 가장 가까운 Pond 칸까지 실제 거리(px) - AudioManager가 강/연못
## 근접도에 따라 소리 볼륨을 계산하는 데 쓴다(사용자 지시: 맵별로 y좌표를
## 손으로 맞추는 대신 실제 물 타일 위치 기준으로). Water(바다)는 일부러 뺐다 -
## 바다는 이미 파도 소리가 따로 있어서(plaza4처럼 Water 없이 Pond만 있는
## 맵도 있지만, Water가 있는 맵에서까지 강 소리가 같이 들리면 파도 소리랑
## 겹쳐 시끄럽다는 사용자 지시). 이 맵에 Pond 타일이 하나도 없으면 INF.
func get_distance_to_nearest_pond(world_position: Vector2) -> float:
	var map_columns := int(_map_size.x / TILE_SIZE)
	if map_columns <= 0:
		return INF
	var nearest := INF
	var gids: Array = _layer_gids.get("Pond", [])
	for index in gids.size():
		if int(gids[index]) == 0:
			continue
		var cell := Vector2i(index % map_columns, index / map_columns)
		var cell_center := Vector2(cell) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
		nearest = minf(nearest, world_position.distance_to(cell_center))
	return nearest


func get_spawn_position(spawn_name: String) -> Vector2:
	var resolved_name: String = String(SPAWN_ALIASES.get(spawn_name, spawn_name))
	return _spawns.get(resolved_name, Vector2.INF)


## plaza1~5처럼 한 맵에 목적지별 입구가 여러 개 있는 경우, 이 맵 안에서
## target_map_id로 이어지는 워프(트리거 위치 + 도착할 맵에서의 target_spawn
## 이름, 플레이어 워프와 완전히 같은 규칙)를 찾는다. 일치하는 게 없으면 빈
## Dictionary를 반환한다 - 맵 그래프가 완전히 연결되어 있다는 전제(모든 워프에
## target_spawn이 정확히 있음) 하에 정상적인 경로 상에서는 항상 찾아져야 하고,
## 못 찾으면 그 자체가 데이터 버그다(더 이상 "기본 문"으로 조용히 대체하지
## 않는다). 일치하는 워프가 여러 개면 맨 처음 찾은 것을 쓴다.
func get_warp_for_target_map(target_map_id: String) -> Dictionary:
	if target_map_id.is_empty():
		return {}
	for warp in _warps:
		if String(warp.get("target_map", "")) == target_map_id:
			return warp
	return {}


## Interactable과 동일하게 점(반경 판정)/사각형(범위 판정) 둘 다 지원한다.
func get_warp_at(world_position: Vector2) -> Dictionary:
	for warp in _warps:
		var size: Vector2 = warp.get("size", Vector2.ZERO)
		if size.x > 0.0 and size.y > 0.0:
			var rect := Rect2(warp["position"] - size / 2.0, size)
			if rect.has_point(world_position):
				return warp
		elif world_position.distance_to(warp["position"]) <= WARP_RADIUS:
			return warp
	return {}


## Returns the nearest Interactable object (계산대/요리대/침대/컴퓨터/책장 등)
## within range, e.g. {"name": "cash_register", "position": ..., "shop_id": "marr_shop"}.
## Custom properties (like cash_register's shop_id) ride along same as Warp's
## target_map does.
##
## Point objects (Tiled width/height both 0 - computer/collection/cooking
## stations 등 대부분) keep the original "player center 기준 반경 안" 판정.
## Rectangle objects (width/height 있는 경우 - 예: 침대를 실제 크기로 늘린
## sleep) 대신 그 사각형 범위 안에 있는지로 판정해서, 넓게 그려진 오브젝트의
## 가장자리에서도 정상적으로 인식되게 한다.
func get_interactable_at(world_position: Vector2) -> Dictionary:
	for interactable in _interactables:
		var size: Vector2 = interactable.get("size", Vector2.ZERO)
		if size.x > 0.0 and size.y > 0.0:
			var rect := Rect2(interactable["position"] - size / 2.0, size)
			if rect.has_point(world_position):
				return interactable
		elif world_position.distance_to(interactable["position"]) <= INTERACT_RADIUS:
			return interactable
	return {}


## 외양간 문(door1_open~4 등, get_interactable_at()이 돌려주는 것과 같은
## Dictionary) 바로 위 1칸에 걸쳐 있는 "Door" 레이어 타일을 열고/닫는다(사용자
## 지시: 상호작용 오브젝트 사각형과 같은 가로 폭만큼, 그 한 칸 위). 열면 그
## 타일들을 숨기고 충돌도 풀어서 실제로 지나갈 수 있게 하고, 닫으면 되돌린다.
## Door 레이어에 해당 칸이 없으면(다른 맵의 문 등) 충돌만 토글하고 조용히
## 넘어간다.
func set_door_open(door_interactable: Dictionary, open: bool) -> void:
	var size: Vector2 = door_interactable.get("size", Vector2.ZERO)
	if size.x <= 0.0:
		return
	var top_left: Vector2 = (door_interactable.get("position", Vector2.ZERO) as Vector2) - size / 2.0
	# Tiled에서 손으로 배치한 오브젝트라 좌표가 칸 경계에 딱 맞지 않는 경우가
	# 있다(예: cowshed_interior.tmx의 door2_open은 y=143.409로, 16px 격자
	# 기준 그대로 int()(버림)하면 143.409/16=8.96이 8로 잘려 한 칸 위(row7,
	# 문 그림이 없는 빈 칸)를 잘못 골랐다 - round()로 가장 가까운 칸에 맞춘다.
	var row := roundi(top_left.y / TILE_SIZE) - 1
	var col_start := roundi(top_left.x / TILE_SIZE)
	var col_count := maxi(int(round(size.x / TILE_SIZE)), 1)
	for col in range(col_start, col_start + col_count):
		var cell := Vector2i(col, row)
		var tile: Sprite2D = _door_tiles.get(cell)
		if tile != null:
			tile.visible = not open
		if open:
			_blocked_cells.erase(cell)
		else:
			_blocked_cells[cell] = true


## 정적 타일(레이어)이 아니라 런타임에 동적으로 배치되는 오브젝트(외양간 소/
## 돼지 등, LivestockManager가 스폰/해제할 때 호출)가 차지하는 칸을 막고/
## 푼다 - _create_tile()이 타일셋 collision 속성으로 채우는 _blocked_cells를
## 그대로 재사용한다. center는 그 오브젝트의 중심 좌표, size는 실제 차지하는
## 픽셀 크기(칸 단위로 반올림).
func set_area_blocked(center: Vector2, size: Vector2, blocked: bool) -> void:
	var top_left: Vector2 = center - size / 2.0
	var col_start := roundi(top_left.x / TILE_SIZE)
	var row_start := roundi(top_left.y / TILE_SIZE)
	var col_count := maxi(roundi(size.x / TILE_SIZE), 1)
	var row_count := maxi(roundi(size.y / TILE_SIZE), 1)
	for row in range(row_start, row_start + row_count):
		for col in range(col_start, col_start + col_count):
			var cell := Vector2i(col, row)
			if blocked:
				_blocked_cells[cell] = true
			else:
				_blocked_cells.erase(cell)


## Reads only the Spawn object layer of a .tmx file (no tile rendering, no
## node instance needed) - lets other systems (NPCManager) resolve exact
## coordinates on maps that aren't currently loaded/visible.
static func parse_spawns(source_map_path: String) -> Dictionary:
	var spawns: Dictionary = {}
	if not FileAccess.file_exists(source_map_path):
		push_error("Map file could not be found: %s" % source_map_path)
		return spawns
	var parser := XMLParser.new()
	if parser.open(source_map_path) != OK:
		push_error("Map XML could not be opened: %s" % source_map_path)
		return spawns
	var object_group := ""
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "objectgroup":
			object_group = ""
			continue
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name() == "objectgroup":
			object_group = parser.get_named_attribute_value_safe("name")
		elif parser.get_node_name() == "object" and object_group == "Spawn":
			# Tiled rectangle objects store x/y as the top-left corner, not the
			# center - width/height are 0 for plain point objects, so this is a
			# no-op until an object actually gets resized into a rectangle.
			var x := parser.get_named_attribute_value_safe("x").to_float()
			var y := parser.get_named_attribute_value_safe("y").to_float()
			var width := parser.get_named_attribute_value_safe("width").to_float()
			var height := parser.get_named_attribute_value_safe("height").to_float()
			spawns[parser.get_named_attribute_value_safe("name")] = Vector2(x + width / 2.0, y + height / 2.0)
	return spawns


## Reads only the Warp object layer of a .tmx file (no tile rendering, no node
## instance needed) - mirrors _store_object()'s Warp handling exactly (same
## target_map/target_name/target_spawn/WARP_OVERRIDES/NON_PLAYER_WARP_NAME
## rules) so the static map graph (get_map_graph()) matches what a live-loaded
## WorldMap's _warps would contain for this map.
static func parse_warps(source_map_path: String) -> Array[Dictionary]:
	var warps: Array[Dictionary] = []
	if not FileAccess.file_exists(source_map_path):
		push_error("Map file could not be found: %s" % source_map_path)
		return warps
	var parser := XMLParser.new()
	if parser.open(source_map_path) != OK:
		push_error("Map XML could not be opened: %s" % source_map_path)
		return warps
	var object_group := ""
	var current_object: Dictionary = {}
	while parser.read() == OK:
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "object":
				_finish_warp_object(source_map_path, object_group, current_object, warps)
				current_object = {}
			elif parser.get_node_name() == "objectgroup":
				object_group = ""
			continue
		if node_type != XMLParser.NODE_ELEMENT:
			continue
		match parser.get_node_name():
			"objectgroup":
				object_group = parser.get_named_attribute_value_safe("name")
			"object":
				if object_group == "Warp":
					var x := parser.get_named_attribute_value_safe("x").to_float()
					var y := parser.get_named_attribute_value_safe("y").to_float()
					var width := parser.get_named_attribute_value_safe("width").to_float()
					var height := parser.get_named_attribute_value_safe("height").to_float()
					current_object = {
						"name": parser.get_named_attribute_value_safe("name"),
						"position": Vector2(x + width / 2.0, y + height / 2.0),
						"size": Vector2(width, height),
					}
					if parser.is_empty():
						_finish_warp_object(source_map_path, object_group, current_object, warps)
						current_object = {}
			"property":
				if object_group == "Warp" and not current_object.is_empty():
					current_object[parser.get_named_attribute_value_safe("name")] = parser.get_named_attribute_value_safe("value")
	return warps


static func _finish_warp_object(source_map_path: String, object_group: String, object: Dictionary, out_warps: Array[Dictionary]) -> void:
	if object_group != "Warp" or object.is_empty() or object["name"] == NON_PLAYER_WARP_NAME:
		return
	var target_map := String(object.get("target_map", object.get("target_name", "")))
	var target_spawn := String(object.get("target_spawn", ""))
	var override_key := "%s:%s" % [source_map_path.get_file().get_basename(), object["name"]]
	var warp_override: Dictionary = WARP_OVERRIDES.get(override_key, {})
	if not warp_override.is_empty():
		target_map = warp_override["target_map"]
		target_spawn = warp_override["target_spawn"]
	if target_map.is_empty():
		return
	out_warps.append({
		"name": object["name"],
		"position": object["position"],
		"size": object.get("size", Vector2.ZERO),
		"target_map": target_map,
		"target_spawn": target_spawn,
	})


## MAP_PATHS의 모든 맵에 대해 parse_warps()를 한 번씩 호출해 만든 전체 맵 연결
## 그래프(map_id -> 그 맵의 Warp 배열). 지형은 런타임에 안 바뀌므로 세션 내내
## 한 번만 계산해서 캐싱한다.
static var _map_graph_cache: Dictionary = {}


static func get_map_graph() -> Dictionary:
	if _map_graph_cache.is_empty():
		for map_id in MAP_PATHS:
			_map_graph_cache[map_id] = parse_warps(String(MAP_PATHS[map_id]))
	return _map_graph_cache


## 맵 그래프 위에서 BFS로 최단 경로를 구해 from_map_id를 제외하고 to_map_id를
## 포함한 순서(NPC가 실제로 거쳐가야 할 맵 id들)를 반환한다. 같은 맵이면 빈
## 배열. 그래프가 항상 완전히 연결되어 있어야 한다는 전제라 정상 상황에서
## 도달 불가능한 경우는 없어야 하며, 그런 경우가 생기면 빈 배열을 반환한다
## (호출한 쪽이 그 자체를 맵 데이터 문제로 알아채야 함).
static func find_map_route(from_map_id: String, to_map_id: String) -> Array[String]:
	if from_map_id == to_map_id or from_map_id.is_empty() or to_map_id.is_empty():
		return []
	var graph := get_map_graph()
	if not graph.has(from_map_id):
		return []
	var visited := {from_map_id: true}
	var came_from: Dictionary = {}
	var queue: Array[String] = [from_map_id]
	var queue_index := 0
	while queue_index < queue.size():
		var current: String = queue[queue_index]
		queue_index += 1
		if current == to_map_id:
			var route: Array[String] = []
			var step := to_map_id
			while step != from_map_id:
				route.push_front(step)
				step = String(came_from[step])
			return route
		for warp in graph.get(current, []):
			var next_map := String(warp.get("target_map", ""))
			if next_map.is_empty() or visited.has(next_map):
				continue
			visited[next_map] = true
			came_from[next_map] = current
			queue.append(next_map)
	return []


## 화면에 안 보이는 맵을 NPC가 지나가는 데 걸리는 실제 거리를 구하기 위해, 그
## 맵을 씬 트리에 붙이지 않고 임시로 한 번 로드해서 find_path()를 돌린다 -
## 렌더링/실제 게임 로직에는 전혀 관여하지 않고 오직 경로 길이 측정용이라
## add_child가 필요 없다(이번 세션 내내 진단 스크립트들에서 검증된 방식과 동일).
## 경로를 못 찾으면 0.0을 반환하고, 호출한 쪽이 "즉시 도착"으로 처리해야 한다.
static func compute_path_length(map_path: String, from_position: Vector2, to_position: Vector2) -> float:
	var temp_map := new()
	temp_map.load_map(map_path)
	var path := temp_map.find_path(from_position, to_position)
	temp_map.free()
	if path.size() < 2:
		return 0.0
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	return length


## path 위에서 시작점부터 traveled_distance(px)만큼 이동한 지점과, 거기서부터
## 끝까지 남은 경로(그 지점을 새 첫 지점으로 포함)를 반환한다({"position":
## Vector2, "remaining": PackedVector2Array}). 화면 밖에서 지나가던 NPC가 있는
## 맵에 플레이어가 들어왔을 때, 문에서부터 처음부터 다시 걷는 것처럼 보이지
## 않고 실제 진행률만큼 이미 지나온 지점부터 걷는 모습을 보여주기 위함.
static func advance_along_path(path: PackedVector2Array, traveled_distance: float) -> Dictionary:
	if path.size() == 0:
		return {"position": Vector2.ZERO, "remaining": PackedVector2Array()}
	if path.size() == 1 or traveled_distance <= 0.0:
		return {"position": path[0], "remaining": path}
	var traveled := 0.0
	for i in path.size() - 1:
		var segment_length := path[i].distance_to(path[i + 1])
		if traveled + segment_length >= traveled_distance:
			var t := (traveled_distance - traveled) / segment_length if segment_length > 0.0 else 0.0
			var point: Vector2 = path[i].lerp(path[i + 1], t)
			var remaining := PackedVector2Array([point])
			for j in range(i + 1, path.size()):
				remaining.append(path[j])
			return {"position": point, "remaining": remaining}
		traveled += segment_length
	var last: Vector2 = path[path.size() - 1]
	return {"position": last, "remaining": PackedVector2Array([last])}


## compute_path_length()처럼 map_path를 임시로 한 번 로드해서 실제 경로를 구한
## 뒤, advance_along_path()로 그 경로 위에서 traveled_distance만큼 이동한
## 지점만 반환한다 - 화면에 안 보이는 맵에서 "진행 중이던 이동의 진짜 현재
## 위치"를 계산할 때 쓴다(예: 이동 도중 스케줄이 또 바뀌어 재경로해야 하는
## 경우). 경로를 못 찾으면 from_position을 그대로 반환한다.
static func compute_point_along_path(map_path: String, from_position: Vector2, to_position: Vector2, traveled_distance: float) -> Vector2:
	var temp_map := new()
	temp_map.load_map(map_path)
	var path := temp_map.find_path(from_position, to_position)
	temp_map.free()
	if path.is_empty():
		return from_position
	return advance_along_path(path, traveled_distance)["position"]


func _match_element(parser: XMLParser, _visible: bool, _reading: bool, object_group: String, current_object: Dictionary) -> void:
	match parser.get_node_name():
		"map":
			_map_size = Vector2i(
				parser.get_named_attribute_value_safe("width").to_int() * TILE_SIZE,
				parser.get_named_attribute_value_safe("height").to_int() * TILE_SIZE
			)
		"tileset":
			_add_tileset(parser)
		"property":
			if not current_object.is_empty() and (object_group == "Warp" or object_group == "Interactable" or object_group == "YSortAnchor"):
				current_object[parser.get_named_attribute_value_safe("name")] = parser.get_named_attribute_value_safe("value")


func _next_layer_name(parser: XMLParser, current_name: String) -> String:
	if parser.get_node_name() != "layer":
		return current_name
	return parser.get_named_attribute_value_safe("name")


func _next_layer_visibility(parser: XMLParser, current_value: bool) -> bool:
	if parser.get_node_name() != "layer":
		return current_value
	return parser.get_named_attribute_value_safe("visible") != "0"


## Tiled의 visible 플래그와 무관하게 항상 읽는다 - "Farmable"처럼 순수 데이터용
## 레이어는 화면엔 안 그리지만(렌더링 단계에서 _layer_visibility로 걸러냄) GID
## 자체는 게임 로직이 조회할 수 있어야 한다.
func _is_layer_data(parser: XMLParser) -> bool:
	return parser.get_node_name() == "data"


func _next_object_group(parser: XMLParser, current_group: String) -> String:
	if parser.get_node_name() == "objectgroup":
		return parser.get_named_attribute_value_safe("name")
	return current_group


func _next_object(parser: XMLParser, object_group: String, current_object: Dictionary) -> Dictionary:
	if parser.get_node_name() != "object" or object_group.is_empty():
		return current_object
	var x := parser.get_named_attribute_value_safe("x").to_float()
	var y := parser.get_named_attribute_value_safe("y").to_float()
	var width := parser.get_named_attribute_value_safe("width").to_float()
	var height := parser.get_named_attribute_value_safe("height").to_float()
	return {
		"name": parser.get_named_attribute_value_safe("name"),
		"position": Vector2(x + width / 2.0, y + height / 2.0),
		"size": Vector2(width, height),
	}


func _add_tileset(parser: XMLParser) -> void:
	var source := parser.get_named_attribute_value_safe("source")
	if source.is_empty():
		return
	var tileset_path := map_path.get_base_dir().path_join(source)
	var tileset_parser := XMLParser.new()
	if tileset_parser.open(tileset_path) != OK:
		push_error("Tileset XML could not be opened: %s" % tileset_path)
		return
	while tileset_parser.read() == OK:
		if tileset_parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if tileset_parser.get_node_name() == "tileset":
			# Must read "columns" before _find_tileset_image() advances this
			# same parser past the <tileset> element looking for <image>.
			var columns := tileset_parser.get_named_attribute_value_safe("columns").to_int()
			var image_path := _find_tileset_image(tileset_parser, tileset_path)
			var texture := load(image_path) as Texture2D
			if texture != null:
				_tilesets.append({
					"first_gid": parser.get_named_attribute_value_safe("firstgid").to_int(),
					"columns": columns,
					"texture": texture,
					"blocked_local_ids": _read_blocked_tile_ids(tileset_parser),
				})
			return


func _find_tileset_image(tileset_parser: XMLParser, tileset_path: String) -> String:
	while tileset_parser.read() == OK:
		if tileset_parser.get_node_type() == XMLParser.NODE_ELEMENT and tileset_parser.get_node_name() == "image":
			var declared_path := tileset_path.get_base_dir().path_join(tileset_parser.get_named_attribute_value_safe("source"))
			if FileAccess.file_exists(declared_path):
				return declared_path
			var fallback_path := tileset_path.get_basename() + ".png"
			if FileAccess.file_exists(fallback_path):
				push_warning("Using tileset image fallback: %s" % fallback_path)
				return fallback_path
			push_error("Tileset image could not be found: %s" % declared_path)
			return ""
	return ""


## Tiled 타일셋 편집기에서 타일 하나하나에 붙인 커스텀 bool 속성
## `collision`을 읽어서, 막혀야 하는 로컬 타일 id 집합을 만든다. 한 레이어
## 안에 막히는/안 막히는 타일이 섞인 경우(나무 밑동은 막히고 잎은 안 막힘)를
## 위한 것 - 막아야 할 타일에만 collision=true가 붙어있다는 전제.
## _find_tileset_image()가 <image>까지 읽고 반환한 바로 그 parser를 이어받아
## 계속 읽으므로, <tileset> 안에서 <image> 다음에 오는 <tile> 블록들만 본다.
func _read_blocked_tile_ids(tileset_parser: XMLParser) -> Dictionary:
	var blocked: Dictionary = {}
	var current_tile_id := -1
	while tileset_parser.read() == OK:
		if tileset_parser.get_node_type() == XMLParser.NODE_ELEMENT_END and tileset_parser.get_node_name() == "tileset":
			break
		if tileset_parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if tileset_parser.get_node_name() == "tile":
			current_tile_id = tileset_parser.get_named_attribute_value_safe("id").to_int()
		elif tileset_parser.get_node_name() == "property" and current_tile_id >= 0:
			if tileset_parser.get_named_attribute_value_safe("name") == "collision" \
					and tileset_parser.get_named_attribute_value_safe("value") == "true":
				blocked[current_tile_id] = true
	return blocked


func _store_object(object_group: String, object: Dictionary) -> void:
	if object.is_empty():
		return
	if object_group == "Spawn":
		_spawns[object["name"]] = object["position"]
	elif object_group == "Warp" and object["name"] != NON_PLAYER_WARP_NAME:
		var target_map := String(object.get("target_map", object.get("target_name", "")))
		var target_spawn := String(object.get("target_spawn", ""))
		var override_key := "%s:%s" % [map_path.get_file().get_basename(), object["name"]]
		var warp_override: Dictionary = WARP_OVERRIDES.get(override_key, {})
		if not warp_override.is_empty():
			target_map = warp_override["target_map"]
			target_spawn = warp_override["target_spawn"]
		if not target_map.is_empty():
			_warps.append({
				"name": object["name"],
				"position": object["position"],
				"size": object.get("size", Vector2.ZERO),
				"target_map": target_map,
				"target_spawn": target_spawn,
			})
	elif object_group == "Interactable":
		_interactables.append(object)
	elif object_group == "YSortAnchor":
		_ysort_anchors.append(object)


func _store_layer_gids(csv_data: String, layer_name: String) -> void:
	var gid_strings := csv_data.strip_edges().split(",", false)
	var map_columns := int(_map_size.x / TILE_SIZE)
	var map_rows := int(_map_size.y / TILE_SIZE)
	if gid_strings.size() != map_columns * map_rows:
		push_error("Map layer has an unexpected tile count: %s" % map_path)
		return
	var gids: Array[int] = []
	gids.resize(gid_strings.size())
	for index in gid_strings.size():
		gids[index] = gid_strings[index].strip_edges().to_int()
	_layer_gids[layer_name] = gids


func _create_layer_tiles(layer_name: String, layer_priority: int) -> void:
	var gids: Array = _layer_gids[layer_name]
	for index in gids.size():
		var gid: int = gids[index]
		if gid != 0:
			_create_tile(gid, index, layer_name, layer_priority)


## 앵커의 "layer" 커스텀 속성을 쉼표 기준으로 나눠 배열로 돌려준다(앞뒤
## 공백 제거). 속성이 없으면 빈 배열 - "제한 없음, 겹치는 레이어 전부 적용"
## 이라는 뜻이다.
func _anchor_allowed_layers(anchor: Dictionary) -> Array:
	var raw := String(anchor.get("layer", ""))
	if raw.is_empty():
		return []
	var layers: Array = []
	for part in raw.split(","):
		var trimmed := part.strip_edges()
		if not trimmed.is_empty():
			layers.append(trimmed)
	return layers


## "YSortAnchor" 오브젝트 레이어를 읽는다 - 기획자가 Tiled에서 세로로 2칸
## 이상 이어진 그림(나무, 건물, 가구 등) 하나하나를 그 그림 전체를 감싸는
## 사각형으로 직접 표시해두면, 그 사각형이 덮는 칸 전부가 사각형의 아랫변을
## Y-sort 기준으로 그대로 쓰게 한다. 반환값은 "레이어이름:칸x:칸y" -> 기준행.
func _compute_anchor_bottom_rows() -> Dictionary:
	var map_columns := int(_map_size.x / TILE_SIZE)
	var map_rows := int(_map_size.y / TILE_SIZE)
	# 앵커 두 개가 같은 칸을 같이 주장하는 경우(나무 캐노피 한 귀퉁이가 가로등
	# 밑동과 화면상 겹치는 등)를 가려내기 위해, 먼저 모든 앵커의 주장을 후보로만
	# 모아둔다("레이어:칸x:칸y" -> 후보 배열) - 대부분의 칸은 후보가 1개뿐이라
	# 그대로 채택되고, 2개 이상 겹칠 때만 아래에서 진짜 주인을 가린다.
	var candidates: Dictionary = {}
	for anchor in _ysort_anchors:
		var size: Vector2 = anchor.get("size", Vector2.ZERO)
		if size.x <= 0.0 or size.y <= 0.0:
			continue
		var top_left: Vector2 = anchor["position"] - size / 2.0
		# 시작 칸도 끝 칸(-0.5 보정)과 대칭으로 "+0.5 후 floor"로 보정한다 -
		# 손으로 그린 사각형의 윗변이 타일 경계보다 살짝 위(예: 240.0이어야
		# 하는데 239.977)에서 끝나면, 보정 없이는 그 경계 칸(15행)이 아니라
		# 한 칸 위(14행)부터 시작하는 것으로 잘못 계산돼 옆 오브젝트(팻말 등)의
		# 칸까지 이 앵커가 침범하는 문제가 있었다.
		var start_col := int(top_left.x + 0.5) / TILE_SIZE
		var start_row := int(top_left.y + 0.5) / TILE_SIZE
		var end_col := int(top_left.x + size.x - 0.5) / TILE_SIZE
		# end_row는 end_col과 같은 방식(-0.5 보정 후 floor)으로 이미 "마지막으로
		# 걸치는 행"을 정확히 구한다. 예전엔 이 값을 그대로 안 쓰고 별도로
		# "+0.5 후 -1" 공식을 다시 계산했는데, 손으로 그린 사각형처럼 아랫변이
		# 타일 경계에 딱 맞지 않는(소수점 높이) 경우 대부분 실제보다 한 칸 위
		# 행을 기준으로 삼는 버그가 있었다(나무처럼 세로 길이가 16의 배수가
		# 아닌 오브젝트에서 발생, 가로등처럼 우연히 경계 근처였던 것들은 안
		# 드러났었다). end_row를 그대로 재사용해서 이 불일치를 없앤다.
		var end_row := int(top_left.y + size.y - 0.5) / TILE_SIZE
		# 앵커에 "layer" 커스텀 속성(쉼표로 여러 개 나열 가능, 예: "Furniture" 나
		# "FurnitureBehind,Furniture")이 있으면 그 레이어(들)에만 이 앵커를
		# 적용한다 - 다른 앵커와 우연히 겹칠 때(나무 옆 울타리, 벽 옆 기둥
		# 상판 등) 기하학적 추측만으로는 진짜 주인을 못 가리는 경우를 위한
		# 탈출구다. 비워두면(대부분의 경우) 지금처럼 겹치는 모든 레이어를
		# 훑어서 자동으로 판단한다.
		var allowed_layers := _anchor_allowed_layers(anchor)
		for layer_name in _layer_gids:
			if FLAT_LAYERS.has(layer_name) or ALWAYS_FRONT_LAYERS.has(layer_name):
				continue
			if not allowed_layers.is_empty() and not allowed_layers.has(layer_name):
				continue
			var gids: Array = _layer_gids[layer_name]
			for col in range(start_col, end_col + 1):
				if not _column_has_content(gids, map_columns, map_rows, col, start_row, end_row):
					continue
				for row in range(start_row, end_row + 1):
					var key := "%s:%d:%d" % [layer_name, col, row]
					if not candidates.has(key):
						candidates[key] = []
					candidates[key].append({"bottom_row": end_row, "start_row": start_row, "gids": gids, "col": col, "anchor": anchor})

	var bottoms: Dictionary = {}
	for key in candidates:
		var options: Array = candidates[key]
		if options.size() == 1:
			bottoms[key] = options[0]["bottom_row"]
			continue
		# 여기부터는 실제로 앵커 두 개가 겹치는 칸이다 - 이 칸이 어느 오브젝트의
		# "끝"인지(자기 시작행부터 끝행까지 이 레이어에 전부 그림이 있고, 바로
		# 다음 칸은 비어있는지)로 진짜 주인을 가린다. 나무 캐노피처럼 바로 다음
		# 칸에도 그림이 이어지는 쪽이나, 장식품 하나가 벽 앵커의 끝 행과
		# 우연히 겹치기만 하는 쪽(자기 시작행부터는 안 채워져 있음)은 여기서
		# 걸러지고, 가로등 밑동처럼 앵커 범위 전체가 실제로 이 레이어로 꽉 찬
		# 쪽이 이긴다.
		var picked = null
		for option in options:
			if _anchor_owns_column(option["gids"], map_columns, map_rows, option["col"], option["start_row"], option["bottom_row"]):
				picked = option
				break
		# 레이어 하나만으로는 확실한 주인이 없는 경우 - 장식장(desk1)처럼
		# 장식품(Deco, 위쪽 절반)과 몸체(Furniture, 아래쪽 절반)가 겹쳐서
		# 레이어 하나로는 자기 범위 전체를 못 채우지만, 이 앵커가 쓸 수 있는
		# 레이어를 전부 합쳐서 보면 자기 범위 전체가 실제로 꽉 차는 경우를
		# 위한 것이다. 벽(Wall)이 자기 장식(Deco)까지 같이 챙기면서도 옆
		# 책상(desk1)의 장식은 안 뺏어오게 하려고 필요했다 - 벽은 합쳐봐도
		# 책상의 장식품 행까지 이어져서(바로 다음 칸이 안 비어서) 탈락하고,
		# desk1은 자기 범위(장식품+몸체) 전체가 꽉 차면서 정확히 끝나서 통과한다.
		if picked == null:
			var best_area := INF
			for option in options:
				if not _anchor_owns_column_combined(option["anchor"], option["col"], option["start_row"], option["bottom_row"], map_columns, map_rows):
					continue
				var anchor_size: Vector2 = option["anchor"].get("size", Vector2.ZERO)
				var area: float = anchor_size.x * anchor_size.y
				if area < best_area:
					best_area = area
					picked = option
		# 이 레이어만 봐서는 둘 다 주인이 아닌 경우(예: 장식장 위 장식품처럼
		# 벽 앵커와 장식장 앵커 양쪽 범위에 다 걸치지만, 그 칸 자체는 벽의
		# 끝도 장식장의 끝도 아닌 경우) - 같은 칸에서 "다른" 레이어라도 확실히
		# 자기 것으로 증명된 앵커들만 추려서(진짜 오브젝트에 가까운 쪽들),
		# 그중에서도 사각형이 가장 작은(가장 구체적인/폭 좁은) 앵커를 고른다.
		# 벽처럼 옆으로 넓게 퍼진 앵커는 우연히 다른 작은 오브젝트 위를 지나갈
		# 확률이 높고, 장식장처럼 좁은 앵커일수록 그 자리의 진짜 주인일
		# 가능성이 높기 때문이다.
		if picked == null:
			var best_area := INF
			for option in options:
				if not _anchor_owns_any_layer(option["anchor"], option["start_row"], option["bottom_row"], map_columns, map_rows):
					continue
				var anchor_size: Vector2 = option["anchor"].get("size", Vector2.ZERO)
				var area: float = anchor_size.x * anchor_size.y
				if area < best_area:
					best_area = area
					picked = option
		if picked == null:
			picked = options[options.size() - 1]
		bottoms[key] = picked["bottom_row"]
	return bottoms


## 이 레이어에 이 칸 범위(start_row~end_row) 안에 그림이 하나라도 있는지.
func _column_has_content(gids: Array, map_columns: int, map_rows: int, col: int, start_row: int, end_row: int) -> bool:
	if col < 0 or col >= map_columns:
		return false
	for row in range(max(start_row, 0), min(end_row, map_rows - 1) + 1):
		if int(gids[row * map_columns + col]) != 0:
			return true
	return false


## 이 레이어가 이 칸에서 앵커의 "진짜 주인"인지 판정한다 - 앵커의 시작행부터
## 끝행까지 전부 이 레이어에 그림이 실제로 있어야(=앵커 범위 전체가 이
## 오브젝트로 꽉 차야) 하고, 그 바로 한 칸 더 남쪽은 비어있어야(=오브젝트가
## 정확히 여기서 끝나야) 인정한다. 끝 행 하나만 보고 판정하면, 장식품(가구
## 위에 놓인 접시 등) 타일 하나가 우연히 다른(무관한) 앵커의 끝 행과 같은
## 행에 있을 때 그 무관한 앵커가 진짜 주인으로 잘못 인정돼버리는 문제가
## 있었다 - 시작행부터 끝행까지 전부 채워져 있는지 확인하면 이런 "우연히
## 한 칸만 걸치는" 경우를 걸러낼 수 있다. 앵커 두 개가 같은 칸을 같이 주장할
## 때만(_compute_anchor_bottom_rows 참고) 쓰이는 판정이라, 앵커 하나가 옆
## 열까지 폭넓게 덮는 정상적인 경우(나무 캐노피가 기둥 열보다 위로 짧게
## 끝나는 등)에는 영향을 주지 않는다.
func _anchor_owns_column(gids: Array, map_columns: int, map_rows: int, col: int, start_row: int, end_row: int) -> bool:
	if col < 0 or col >= map_columns or end_row < 0 or end_row >= map_rows:
		return false
	for row in range(max(start_row, 0), end_row + 1):
		if int(gids[row * map_columns + col]) == 0:
			return false
	var next_row := end_row + 1
	if next_row >= map_rows:
		return true
	return int(gids[next_row * map_columns + col]) == 0


## _anchor_owns_column()과 같은 판정인데, 레이어 하나가 아니라 이 앵커가 쓸 수
## 있는 레이어(있으면 layer 속성 목록, 없으면 전부) 전체를 "합쳐서" 본다 -
## 장식장(desk1)처럼 장식품(Deco)이 윗부분, 몸체(Furniture)가 아랫부분을
## 채우는 식으로 레이어 하나만으로는 자기 범위를 못 채우지만 합치면 꽉 차는
## 오브젝트를 위한 것이다. 벽(Wall)이 자기 장식(Deco)까지 챙기면서도 옆에
## 있는 책상의 장식은 안 뺏어오게 하는 데도 쓰인다 - 벽은 합쳐도 책상의
## 장식품 행까지 이어져서(바로 다음 칸이 안 비어서) 탈락하고, 책상은 자기
## 범위 전체가 정확히 꽉 차고 끝나서 통과한다.
func _anchor_owns_column_combined(anchor: Dictionary, col: int, start_row: int, end_row: int, map_columns: int, map_rows: int) -> bool:
	if col < 0 or col >= map_columns or end_row < 0 or end_row >= map_rows:
		return false
	var allowed := _anchor_allowed_layers(anchor)
	for row in range(max(start_row, 0), end_row + 1):
		if not _any_layer_has_tile(allowed, col, row, map_columns):
			return false
	var next_row := end_row + 1
	if next_row >= map_rows:
		return true
	return not _any_layer_has_tile(allowed, col, next_row, map_columns)


## allowed가 비어있으면 FLAT/ALWAYS_FRONT를 뺀 전체 레이어, 아니면 그 목록만
## 대상으로 이 칸에 그림이 하나라도 있는지 확인한다.
func _any_layer_has_tile(allowed: Array, col: int, row: int, map_columns: int) -> bool:
	for layer_name in _layer_gids:
		if FLAT_LAYERS.has(layer_name) or ALWAYS_FRONT_LAYERS.has(layer_name):
			continue
		if not allowed.is_empty() and not allowed.has(layer_name):
			continue
		var gids: Array = _layer_gids[layer_name]
		if int(gids[row * map_columns + col]) != 0:
			return true
	return false


## 이 앵커가 "자기 범위 안 어딘가에서" 확실한 주인인 레이어를 하나라도
## 갖고 있는지 확인한다 - 분쟁이 난 그 칸(col) 하나만 보지 않고 앵커의
## 전체 열 범위를 다 훑는다. 기둥(가운데 기둥 몸통 열만 여러 행이 꽉 차고,
## 양옆 상판 열은 한 행만 있는 모양)처럼, 분쟁이 난 칸(상판)만 보면 이
## 앵커가 주인이 아닌 것처럼 보이지만 실제로는 몸통 열에서 이미 확실한
## 진짜 오브젝트라고 증명된 경우, 그 "증명된 진짜임"을 상판 열에도 그대로
## 인정해줘야 한다 - 그렇지 않으면 위쪽 벽 앵커처럼 옆으로 넓게 걸쳐있는
## 무관한 앵커에게 상판 칸을 뺏겨서 기둥 전체가 벽의 얕은 기준을 물려받고
## 항상 플레이어 뒤로만 그려지는 문제가 생긴다.
func _anchor_owns_any_layer(anchor: Dictionary, start_row: int, end_row: int, map_columns: int, map_rows: int) -> bool:
	var size: Vector2 = anchor.get("size", Vector2.ZERO)
	var top_left: Vector2 = anchor["position"] - size / 2.0
	var start_col := int(top_left.x + 0.5) / TILE_SIZE
	var end_col := int(top_left.x + size.x - 0.5) / TILE_SIZE
	for layer_name in _layer_gids:
		if FLAT_LAYERS.has(layer_name) or ALWAYS_FRONT_LAYERS.has(layer_name):
			continue
		var gids: Array = _layer_gids[layer_name]
		for col in range(start_col, end_col + 1):
			if _anchor_owns_column(gids, map_columns, map_rows, col, start_row, end_row):
				return true
	return false


## "Light" 레이어만 따로 훑어서 가로등 각각의 맨 윗칸(등롱 위치)을 찾는다.
func _compute_light_source_positions() -> void:
	var gids: Array = _layer_gids.get("Light", [])
	if gids.is_empty():
		return
	var map_columns := int(_map_size.x / TILE_SIZE)
	var map_rows := int(_map_size.y / TILE_SIZE)
	for col in map_columns:
		var run_start := -1
		for row in map_rows + 1:
			var has_tile: bool = row < map_rows and int(gids[row * map_columns + col]) != 0
			if has_tile:
				if run_start == -1:
					run_start = row
			elif run_start != -1:
				# 벽걸이 조명처럼 한 칸짜리 단독 조명도 포함해야 해서, 이어진
				# 칸이 있으면(몇 칸이든, tree-like 여부와 상관없이) 그 맨 위
				# 칸을 빛 위치로 기록한다.
				_light_source_positions.append(
					Vector2(col, run_start) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
				)
				run_start = -1


## NPC 걷기용 경로탐색 격자를 이 맵의 _blocked_cells 그대로 다시 만든다.
## 손으로 그리는 내비게이션 메시가 따로 필요 없다 - 이미 충돌 판정에 쓰던
## 데이터를 재활용한다.
func _rebuild_pathfinding_grid() -> void:
	var map_columns := int(_map_size.x / TILE_SIZE)
	var map_rows := int(_map_size.y / TILE_SIZE)
	_astar.clear()
	if map_columns <= 0 or map_rows <= 0:
		return
	_astar.region = Rect2i(0, 0, map_columns, map_rows)
	_astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	# 이 파일이 원래 쓰던 타일 중심 좌표 관례(_create_tile의 cell_center 등)와
	# 맞추기 위한 보정 - 안 맞추면 get_point_path()가 칸의 좌상단 좌표를
	# 돌려줘서 NPC가 타일 경계에서 살짝 어긋난 위치로 걷게 된다.
	_astar.offset = Vector2.ONE * TILE_SIZE * 0.5
	# NPC 스프라이트가 4방향(상하좌우) 걷기 프레임만 갖고 있어서, 대각선으로
	# 이동하면 화면상으로는 대각선으로 미끄러지는데 애니메이션은 직선 방향
	# 걷기를 보여줘서 부자연스럽다 - 그래서 대각선 이동 자체를 막아 항상
	# 4방향 격자로만 경로를 구한다.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	for cell in _blocked_cells:
		if _astar.is_in_boundsv(cell):
			_astar.set_point_solid(cell, true)


## NPC가 from_position에서 to_position까지 걸어갈 경로(타일 중심 좌표들)를
## 구한다. 시작/끝이 막힌 칸이면 가장 가까운 빈 칸으로 보정하고, 그래도 갈 수
## 없으면 빈 배열을 돌려준다 - 경로탐색은 "되면 좋고 안 되면 그냥 순간이동"인
## 보조 기능이라, 호출하는 쪽은 빈 배열을 받으면 반드시 즉시 이동으로
## 대체해야 한다(NPC가 못 찾겠다고 그 자리에 멈춰버리면 안 된다).
func find_path(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var from_cell := _nearest_walkable_cell(_world_to_cell(from_position))
	var to_cell := _nearest_walkable_cell(_world_to_cell(to_position))
	if from_cell == Vector2i(-1, -1) or to_cell == Vector2i(-1, -1):
		return PackedVector2Array()
	return _astar.get_point_path(from_cell, to_cell, true)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x) / TILE_SIZE, int(world_position.y) / TILE_SIZE)


## cell이 막혀있으면(스폰 좌표가 충돌 타일 경계 근처인 경우 등) 주변을
## 나선형으로 훑어 가장 가까운 빈 칸을 찾는다. PATHFIND_SEARCH_RADIUS 안에서
## 못 찾거나 맵 범위 밖이면 Vector2i(-1,-1)을 돌려준다.
func _nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	if _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
		return cell
	for radius in range(1, PATHFIND_SEARCH_RADIUS + 1):
		for offset in _ring_offsets(radius):
			var candidate := cell + offset
			if _astar.is_in_boundsv(candidate) and not _astar.is_point_solid(candidate):
				return candidate
	return Vector2i(-1, -1)


## 정사각형 반지름 radius(체비쇼프 거리 기준)의 테두리 칸들만 돌려준다.
func _ring_offsets(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if maxi(absi(x), absi(y)) == radius:
				offsets.append(Vector2i(x, y))
	return offsets


func _create_tile(gid: int, index: int, layer_name: String, layer_priority: int) -> void:
	var tileset := _get_tileset(gid)
	if tileset.is_empty():
		return
	var local_tile_id := gid - int(tileset["first_gid"])
	var columns := int(tileset["columns"])
	var atlas := AtlasTexture.new()
	atlas.atlas = tileset["texture"]
	atlas.region = Rect2((local_tile_id % columns) * TILE_SIZE, (local_tile_id / columns) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var tile := Sprite2D.new()
	tile.texture = atlas
	tile.add_to_group(&"_map_tile")
	var map_columns := int(_map_size.x / TILE_SIZE)
	var cell := Vector2i(index % map_columns, index / map_columns)
	var cell_center := Vector2(cell) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
	if FLAT_LAYERS.has(layer_name):
		tile.position = cell_center
		tile.z_index = FLAT_Z_INDEX
	elif ALWAYS_FRONT_LAYERS.has(layer_name):
		tile.position = cell_center
		tile.z_index = ALWAYS_FRONT_Z_INDEX
	else:
		# Y-sort 비교 기준을 플레이어(발밑=position.y)와 맞추기 위해 노드
		# position 자체를 이 칸이 속한 덩어리의 가장 아래 행 바닥선으로
		# 옮기고, 그려지는 그림은 원래 칸 자리 그대로 보이도록 offset으로
		# 되돌린다 (세로로 이어진 칸이 없으면 자기 행의 바닥선과 같다).
		# 서로 다른 레이어의 타일이 같은 칸/같은 행에 겹쳐 있으면(예: 장식품 +
		# 그 자리의 가구) sort_y가 완전히 같아져서 Y-sort로 앞/뒤가 안 정해지는
		# 경우가 생긴다 - 맵 파일에 나중에 나오는 레이어가 항상 이기도록 아주
		# 작은(픽셀 격자보다 훨씬 작은) 우선순위 값을 더해 동점을 없앤다.
		# 앵커가 이 칸/레이어를 덮으면 그 기준행을 쓰고, 없으면(앵커가 필요
		# 없는 1행짜리 오브젝트 등) 자기 행을 그대로 쓴다. SORT_SAFE_MARGIN만큼
		# 기준선을 앞으로 당겨서, 충돌이 허용하는 가장 가까운 위치(벽에 딱
		# 붙어 선 경우 등)에서도 항상 확실히 플레이어가 앞으로 판정되게 한다.
		var anchor_key := "%s:%d:%d" % [layer_name, cell.x, cell.y]
		var sort_row: int = _anchor_layer_bottom_row.get(anchor_key, cell.y)
		var sort_y := float(sort_row) * TILE_SIZE + TILE_SIZE - SORT_SAFE_MARGIN + layer_priority * LAYER_PRIORITY_EPSILON
		tile.position = Vector2(cell_center.x, sort_y)
		tile.offset = Vector2(0, cell_center.y - sort_y)
		tile.z_index = Y_SORT_Z_INDEX
	add_child(tile)
	if layer_name == "Door":
		_door_tiles[cell] = tile
	var blocked_local_ids: Dictionary = tileset.get("blocked_local_ids", {})
	if blocked_local_ids.has(local_tile_id):
		_blocked_cells[cell] = true


func _get_tileset(gid: int) -> Dictionary:
	for index in range(_tilesets.size() - 1, -1, -1):
		if gid >= int(_tilesets[index]["first_gid"]):
			return _tilesets[index]
	return {}


## 그룹으로 걸러서 지우는 이유: Player/RestaurantSign이 이제 Y-sort 때문에
## 이 노드의 자식으로 들어와 있는데, get_children()을 그냥 다 지우면 맵을
## 새로 불러올 때마다 그것들도 같이 사라진다 - 실제로 매 프레임 새로 그리는
## 타일들만 그룹으로 태그해서 그것들만 지운다.
## 타일은 항상 이 노드의 직접 자식이라(_create_tile 참고), get_tree() 전체
## 탐색 대신 자기 자식만 훑는다 - compute_path_length()처럼 씬 트리에 안 붙은
## 임시 WorldMap 인스턴스에서도(get_tree()가 null이라) 문제없이 동작해야 한다.
func _clear_tiles() -> void:
	for tile in get_children():
		if tile.is_in_group(&"_map_tile"):
			tile.free()
