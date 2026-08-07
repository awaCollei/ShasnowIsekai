extends Node2D
class_name RoomGenerator

## 建筑坐标约定：本节点 (0, 0) 是建筑左下角，也是 1 楼地板表面。
## Godot 的 Y 轴向下，因此第 N 层地板为 y = -(N - 1) * floor_pitch。

signal room_entered(floor_index: int, room_index: int)

@export_group("Building")
@export_range(1, 20, 1) var floor_count: int = 3
@export_range(100.0, 10000.0, 10.0) var building_width: float = 3200.0
@export_range(100.0, 1000.0, 10.0) var room_height: float = 400.0
@export_range(0.0, 200.0, 1.0) var floor_separator_height: float = 50.0
@export_range(200.0, 2000.0, 1.0) var stairwell_width: float = 792.0

@export_group("Rooms")
@export_range(2, 20, 1) var max_rooms_per_floor: int = 5
@export var unseen_color := Color(0.0, 0.0, 0.0, 1.0)
@export var revealed_room_color := Color("252535")

@export_group("Placement")
## 楼梯传送门相对本层地板表面的高度；正数表示向上。
@export var stair_portal_height: float = 80.0

@export_group("Textures")
@export var outer_wall_texture: Texture2D
@export var interior_wall_texture: Texture2D
@export var floor_texture: Texture2D
@export_range(1.0, 100.0, 1.0) var wall_width: float = 32.0

var room_registry: Array[Dictionary] = []
var generated_rooms: Array[Dictionary] = []
var zone_id := "0,2"
var zone_state: Dictionary = {}

const AIR_WALL_SCENE: PackedScene = preload("res://components/wall.tscn")
const TEXTURED_WALL_SCENE: PackedScene = preload("res://components/textured_wall.tscn")
const PORTAL_SCENE: PackedScene = preload("res://components/portal.tscn")
const LAYOUT_VERSION := 2
const GROUND_ENTRANCE_HEIGHT := 240.0

var floor_pitch: float:
	get:
		return room_height + floor_separator_height


func _ready() -> void:
	register_rooms()


## width 的单位是像素，不再是“槽位数量”。地图子类可以覆写此表。
func register_rooms() -> void:
	room_registry = [
		{"id": "stairwell", "scene": "res://rooms/city1/stairwell.tscn", "weight": 0.0},
		{"id": "empty", "scene": "res://rooms/city1/empty.tscn", "width": 640.0, "weight": 3.0},
		{"id": "room1", "scene": "res://rooms/city1/room1.tscn", "width": 823.0, "weight": 1.0},
		{"id": "room2", "scene": "res://rooms/city1/room2.tscn", "width": 1222.0, "weight": 1.0},
	]


func room_probability(room: Dictionary, _floor_index: int) -> float:
	return maxf(0.0, float(room.get("weight", 1.0)))


func generate(state: Dictionary, id: String) -> void:
	zone_id = id
	zone_state = state
	_clear_generated_building()

	var layouts: Array = zone_state.get("rooms", [])
	if not _layout_is_current(layouts):
		layouts = _create_layout()
		zone_state["rooms"] = layouts
		zone_state["room_layout_version"] = LAYOUT_VERSION

	for floor_index in range(floor_count):
		var row: Array = layouts[floor_index]
		for room_index in range(row.size()):
			_spawn_room(row[room_index], floor_index, room_index)
		_add_floor_separator(floor_index)
		_add_stair_portal(floor_index)

	_add_outer_walls()


func floor_sub_scene(floor_index: int) -> String:
	return "outdoor" if floor_index == 0 else "floor%d" % (floor_index + 1)


func floor_y(floor_index: int) -> float:
	return -float(floor_index) * floor_pitch


## 供地图脚本生成敌人使用。返回的是生成器局部坐标。
func get_enemy_spawn_candidates(height_above_floor: float) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for room in generated_rooms:
		if String(room.get("id", "")) == "stairwell":
			continue
		var width := float(room["width"])
		if width <= 200.0:
			continue
		candidates.append({
			"position": Vector2(float(room["x"]) + randf_range(100.0, width - 100.0), floor_y(int(room["floor"])) - height_above_floor),
			"floor": int(room["floor"]),
			"room_index": int(room["room_index"]),
			"sub_scene": floor_sub_scene(int(room["floor"])),
		})
	return candidates


func _clear_generated_building() -> void:
	for child in get_children():
		child.free()
	generated_rooms.clear()


func _layout_is_current(layouts: Array) -> bool:
	if int(zone_state.get("room_layout_version", 0)) != LAYOUT_VERSION:
		return false
	if layouts.size() != floor_count:
		return false
	for row in layouts:
		if not row is Array or row.is_empty() or row.size() > max_rooms_per_floor:
			return false
		if not row[0] is Dictionary:
			return false
		if String(row[0].get("id", "")) != "stairwell":
			return false
		if not is_equal_approx(float(row[0].get("width_px", 0.0)) , stairwell_width):
			return false
		var total_width := 0.0
		for data in row:
			if not data is Dictionary or not data.has("width_px") or not _room_id_exists(String(data.get("id", ""))):
				return false
			total_width += float(data["width_px"])
		if not is_equal_approx(total_width, building_width):
			return false
	return true


func _create_layout() -> Array:
	var result: Array = []
	for floor_index in range(floor_count):
		var row: Array = []
		var used_width := 0.0
		var first_width := stairwell_width
		row.append({"id": "stairwell", "width_px": first_width, "entered": false})
		used_width += first_width

		while used_width < building_width and row.size() < max_rooms_per_floor:
			var remaining := building_width - used_width
			var selected := _choose_room(floor_index, remaining)
			if selected.is_empty():
				break
			var width := minf(float(selected.get("width", remaining)), remaining)
			row.append({"id": String(selected.get("id", "empty")), "width_px": width, "entered": false})
			used_width += width

		if used_width < building_width:
			# 最后一间吸收余量，保证每层严格等宽，不留下边界裂缝。
			if row.size() == 1:
				row.append({"id": "empty", "width_px": building_width - used_width, "entered": false})
			else:
				row[row.size() - 1]["width_px"] = float(row[row.size() - 1]["width_px"]) + building_width - used_width
		result.append(row)
	return result


func _choose_room(floor_index: int, remaining_width: float) -> Dictionary:
	var choices: Array[Dictionary] = []
	var total := 0.0
	for room in room_registry:
		if String(room.get("id", "")) == "stairwell":
			continue
		if float(room.get("width", 0.0)) > remaining_width:
			continue
		var weight := room_probability(room, floor_index)
		if weight > 0.0:
			choices.append(room)
			total += weight
	if choices.is_empty():
		return {}
	var pick := randf() * total
	for room in choices:
		pick -= room_probability(room, floor_index)
		if pick <= 0.0:
			return room
	return choices.back()


func _spawn_room(data: Dictionary, floor_index: int, room_index: int) -> void:
	var room_id := String(data.get("id", "empty"))
	var width := float(data.get("width_px", 640.0))
	var x := _room_x(floor_index, room_index)
	var baseline_y := floor_y(floor_index)
	var room_root := Node2D.new()
	room_root.name = "Room_F%d_%02d_%s" % [floor_index + 1, room_index + 1, room_id]
	room_root.position = Vector2(x, baseline_y)
	add_child(room_root)

	var background := Polygon2D.new()
	background.name = "Background"
	background.polygon = PackedVector2Array([
		Vector2(0.0, -room_height), Vector2(width, -room_height),
		Vector2(width, 0.0), Vector2.ZERO,
	])
	background.color = revealed_room_color
	background.z_index = -10
	room_root.add_child(background)

	var room_scene := _find_room_scene(room_id)
	if room_scene:
		var instance := room_scene.instantiate()
		instance.name = "Content"
		room_root.add_child(instance)
		_apply_sub_scene(instance, floor_sub_scene(floor_index))

	# 每间房拥有自己右侧的无碰撞贴图墙；外墙由 _add_outer_walls 单独创建。
	if room_index < (zone_state["rooms"][floor_index] as Array).size() - 1:
		_add_interior_wall(room_root, width)

	var trigger := Area2D.new()
	trigger.name = "RevealTrigger"
	var trigger_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width, room_height)
	trigger_shape.position = Vector2(width * 0.5, -room_height * 0.5)
	trigger_shape.shape = rectangle
	trigger.add_child(trigger_shape)
	trigger.body_entered.connect(_on_room_entered.bind(floor_index, room_index, room_root))
	room_root.add_child(trigger)

	if not bool(data.get("entered", false)):
		var cover := Polygon2D.new()
		cover.name = "UnseenCover"
		cover.polygon = background.polygon
		cover.color = unseen_color
		cover.z_index = 10
		room_root.add_child(cover)

	generated_rooms.append({
		"floor": floor_index,
		"room_index": room_index,
		"id": room_id,
		"x": x,
		"width": width,
		"entered": bool(data.get("entered", false)),
	})


func _room_x(floor_index: int, room_index: int) -> float:
	var x := 0.0
	var row: Array = zone_state["rooms"][floor_index]
	for index in range(room_index):
		x += float(row[index].get("width_px", 0.0))
	return x


func _on_room_entered(body: Node2D, floor_index: int, room_index: int, room_root: Node2D) -> void:
	if not body is Player:
		return
	var layouts: Array = zone_state.get("rooms", [])
	if floor_index >= layouts.size() or room_index >= layouts[floor_index].size():
		return
	layouts[floor_index][room_index]["entered"] = true
	zone_state["rooms"] = layouts
	var cover := room_root.get_node_or_null("UnseenCover")
	if cover:
		cover.queue_free()
	room_entered.emit(floor_index, room_index)


func _add_interior_wall(room_root: Node2D, room_width: float) -> void:
	var wall := TEXTURED_WALL_SCENE.instantiate() as TexturedWall
	if not wall:
		return
	wall.position = Vector2(room_width - wall_width, -room_height)
	wall.wall_size = Vector2(wall_width, room_height)
	if interior_wall_texture:
		wall.wall_texture = interior_wall_texture
	room_root.add_child(wall)


func _add_floor_separator(floor_index: int) -> void:
	var separator = TextureRect.new() if floor_texture else ColorRect.new()
	separator.name = "Floor_F%d" % (floor_index + 1)
	separator.position = Vector2(0.0, floor_y(floor_index))
	separator.size = Vector2(building_width, floor_separator_height)
	separator.z_index = 20
	if separator is TextureRect:
		separator.texture = floor_texture
		separator.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		separator.stretch_mode = TextureRect.STRETCH_TILE
	else:
		separator.color = Color("514c67")
	add_child(separator)


func _add_outer_walls() -> void:
	var top_y := floor_y(floor_count - 1) - room_height
	var total_height := -top_y
	# 左墙在一楼保留入口，否则玩家从建筑外无法进入第一个楼梯间。
	_add_outer_wall(Vector2(0.0, top_y), Vector2(wall_width, maxf(1.0, total_height - GROUND_ENTRANCE_HEIGHT)))
	_add_outer_wall(Vector2(building_width - wall_width, top_y), Vector2(wall_width, total_height))


func _add_outer_wall(wall_position: Vector2, size: Vector2) -> void:
	var wall := AIR_WALL_SCENE.instantiate() as Wall
	if not wall:
		return
	wall.position = wall_position
	wall.wall_size = size
	wall.use_top_left_origin = true
	wall.visible_texture = outer_wall_texture
	wall.z_index = 30
	add_child(wall)


func _add_stair_portal(floor_index: int) -> void:
	var portal := PORTAL_SCENE.instantiate() as Portal
	if not portal:
		return
	var row: Array = zone_state["rooms"][floor_index]
	var actual_stairwell_width := float(row[0].get("width_px", building_width))
	portal.position = Vector2(actual_stairwell_width * 0.5, floor_y(floor_index) - stair_portal_height)
	portal.portal_id = _portal_id(floor_index)
	portal.sub_scene = floor_sub_scene(floor_index)
	portal.portal_name = "%d 楼楼梯" % (floor_index + 1)
	for target_floor in range(floor_count):
		if target_floor != floor_index:
			portal.target_portal_ids.append(_portal_id(target_floor))
	add_child(portal)


func _portal_id(floor_index: int) -> String:
	return "zone_%s_floor_%d" % [zone_id.replace(",", "_"), floor_index + 1]


func _room_id_exists(room_id: String) -> bool:
	for room in room_registry:
		if String(room.get("id", "")) == room_id:
			return true
	return false


func _find_room_scene(room_id: String) -> PackedScene:
	for room in room_registry:
		if String(room.get("id", "")) != room_id:
			continue
		var path := String(room.get("scene", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


## 将楼层 sub_scene 下发给 Portal、Wall、调查点等已有组件。
func _apply_sub_scene(root: Node, value: String) -> void:
	for property in root.get_property_list():
		if String(property.get("name", "")) == "sub_scene":
			root.set("sub_scene", value)
			break
	for child in root.get_children():
		_apply_sub_scene(child, value)
