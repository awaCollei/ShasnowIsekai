extends Node2D
class_name RoomGenerator

## 建筑坐标约定：本节点 (0, 0) 是建筑左下角，也是 1 楼地板表面。
## Godot 的 Y 轴向下，因此第 N 层地板为 y = -(N - 1) * floor_pitch。

signal room_entered(floor_index: int, room_index: int)

@export_group("Building")
@export var floor_count: int = 6
## 同一 zone 内存在多个建筑生成器时必须分别设置稳定值。
@export var building_instance_id: String = "main"
@export var building_width: float = 3200.0
@export var room_height: float = 450.0
@export var floor_separator_height: float = 50.0

@export_group("Rooms")
@export var max_rooms_per_floor: int = 5
@export var room_gap: float = 30.0
@export var unseen_color := Color(0.0, 0.0, 0.0, 1.0)
@export var revealed_room_color := Color("252535")

@export_group("Textures")
@export var outer_wall_texture: Texture2D
@export var interior_wall_texture: Texture2D
@export var floor_texture: Texture2D
@export var wall_width: float = 32.0

var room_registry: Dictionary = {}
var generated_rooms: Array[Dictionary] = []
var zone_id := "0,2"
var zone_state: Dictionary = {}
var scene_id := ""
var zone_type := ""
var building_config: Dictionary = {}

const AIR_WALL_SCENE: PackedScene = preload("res://components/wall.tscn")
const TEXTURED_WALL_SCENE: PackedScene = preload("res://components/textured_wall.tscn")
const PORTAL_SCENE: PackedScene = preload("res://components/portal.tscn")
const INVESTIGATION_POINT_SCENE: PackedScene = preload("res://components/investigation_point.tscn")
const CHEST_SCENE: PackedScene = preload("res://components/chest.tscn")
const LAYOUT_VERSION := 5
const GROUND_ENTRANCE_HEIGHT := 240.0
const ROOMS_JSON_PATH := "res://building/rooms.json"

var floor_pitch: float:
	get:
		return room_height + floor_separator_height


## JSON 只描述房间内容；房间宽度始终取对应贴图的原始宽度。
func register_rooms() -> void:
	room_registry.clear()
	var file := FileAccess.open(ROOMS_JSON_PATH, FileAccess.READ)
	var root: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	building_config = root[scene_id][zone_type]
	for raw: Dictionary in building_config["rooms"]:
		var room := raw.duplicate(true)
		var room_id: String = room["id"]
		var texture := load("res://assets/%s/%s/%s.png" % [scene_id, zone_type, room_id]) as Texture2D
		room["texture"] = texture
		room["width"] = float(texture.get_width())
		for point: Dictionary in room["investigation_points"]:
			point["position"] = _position_from_json(point["position"])
		for chest: Dictionary in room["chests"]:
			chest["position"] = _position_from_json(chest["position"])
		room_registry[room_id] = room


func _position_from_json(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func generate(state: Dictionary, id: String) -> void:
	zone_id = id
	zone_state = state
	scene_id = state["scene"]
	zone_type = state["region_type"]
	register_rooms()
	_apply_building_config()
	_clear_generated_building()

	var layouts: Array = zone_state["rooms"]
	if (
		layouts.is_empty()
		or not zone_state.has("room_layout_version")
		or zone_state["room_layout_version"] != LAYOUT_VERSION
		or zone_state["room_layout_scene"] != scene_id
		or zone_state["room_layout_zone_type"] != zone_type
	):
		layouts = _create_layout()
		zone_state["rooms"] = layouts
		zone_state["room_layout_version"] = LAYOUT_VERSION
		zone_state["room_layout_scene"] = scene_id
		zone_state["room_layout_zone_type"] = zone_type

	for floor_index in range(floor_count):
		var row: Array = layouts[floor_index]
		for room_index in range(row.size()):
			_spawn_room(row[room_index], floor_index, room_index)
		if floor_index > 0:
			_add_floor_separator(floor_index)
		_add_stair_portal(floor_index)

	_add_floor_separator(floor_count)
	_add_outer_walls()


func floor_sub_scene(floor_index: int) -> String:
	return "outdoor" if floor_index == 0 else "floor%d" % (floor_index + 1)


func floor_y(floor_index: int) -> float:
	return -float(floor_index) * floor_pitch


## 供地图脚本生成敌人使用。返回的是生成器局部坐标。
func get_enemy_spawn_candidates(height_above_floor: float) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for room in generated_rooms:
		if room["id"] == "楼梯间":
			continue
		var width: float = room["width"]
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


func _create_layout() -> Array:
	var result: Array = []
	var stairwell_width := _room_width("楼梯间")
	var empty_room_width := _room_width("空房间")
	for _floor_index in range(floor_count):
		var row: Array = [{"id": "楼梯间", "entered": false}]
		var used_width := stairwell_width

		# 空房间只负责尾部补齐，不参与随机选择。
		while row.size() < max_rooms_per_floor - 1:
			var empty_slots_after := max_rooms_per_floor - row.size() - 1
			var selected = _choose_room(
				building_width - used_width,
				empty_slots_after,
				empty_room_width,
			)
			if selected == null:
				break
			row.append({"id": selected["id"], "entered": false})
			used_width += room_gap + float(selected["width"])

		# 连续空房间中只有最右侧最后一间允许小于贴图原始宽度。
		var remaining := building_width - used_width
		var empty_count := _empty_room_count(remaining, max_rooms_per_floor - row.size(), empty_room_width)
		for empty_index in range(empty_count):
			var width := empty_room_width
			if empty_index == empty_count - 1:
				width = remaining - float(empty_count) * room_gap - float(empty_count - 1) * empty_room_width
			row.append({"id": "空房间", "width": width, "entered": false})

		# 打乱非楼梯间房间，使空房间不会总是出现在最右侧。
		var non_stairwell := row.slice(1)
		non_stairwell.shuffle()
		for i in range(non_stairwell.size()):
			row[i + 1] = non_stairwell[i]

		result.append(row)
	return result


func _empty_room_count(remaining: float, available_slots: int, empty_room_width: float) -> int:
	if remaining == 0.0:
		return 0
	var full_slot_width := room_gap + empty_room_width
	for count in range(1, available_slots + 1):
		var minimum := float(count - 1) * full_slot_width + room_gap
		if remaining > minimum and remaining <= float(count) * full_slot_width:
			return count
	return -1


func _choose_room(
	available_width: float,
	empty_slots_after: int,
	empty_room_width: float,
) -> Variant:
	var choices: Array[Dictionary] = []
	var total := 0.0
	for room: Dictionary in room_registry.values():
		if room["id"] == "楼梯间" or room["id"] == "空房间":
			continue
		var remaining_after := available_width - room_gap - float(room["width"])
		if _empty_room_count(remaining_after, empty_slots_after, empty_room_width) < 0:
			continue
		var weight: float = room["weight"]
		if weight > 0.0:
			choices.append(room)
			total += weight
	if choices.is_empty():
		return null

	var pick := randf() * total
	var index := 0
	while true:
		var room := choices[index]
		var weight: float = room["weight"]
		if pick < weight:
			return room
		pick -= weight
		index += 1
	return null

func _spawn_room(data: Dictionary, floor_index: int, room_index: int) -> void:
	var room_id: String = data["id"]
	var width := float(data["width"]) if room_id == "空房间" else _room_width(room_id)
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

	_create_room_content(room_root, room_id, floor_index, room_index, width)

	var row: Array = zone_state["rooms"][floor_index]
	if room_index < row.size() - 1:
		_add_interior_wall(room_root, width)

	var trigger := Area2D.new()
	trigger.name = "RevealTrigger"
	var trigger_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width - wall_width * 0.5, room_height - wall_width * 0.5)
	trigger_shape.position = Vector2(width * 0.5, -room_height * 0.5)
	trigger_shape.shape = rectangle
	trigger.add_child(trigger_shape)
	trigger.body_entered.connect(_on_room_entered.bind(floor_index, room_index, room_root))
	room_root.add_child(trigger)

	if not data["entered"]:
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
	})


func _create_room_content(room_root: Node2D, room_id: String, floor_index: int, room_index: int, room_width: float) -> void:
	var room_data: Dictionary = room_registry[room_id]
	var content := Node2D.new()
	content.name = "Content"
	room_root.add_child(content)

	var sprite := Sprite2D.new()
	sprite.name = "RoomImage"
	sprite.texture = room_data["texture"] as Texture2D
	sprite.position = Vector2(room_width * 0.5, -room_height * 0.5)
	if room_id == "空房间" and room_width < float(sprite.texture.get_width()):
		var crop_left := (float(sprite.texture.get_width()) - room_width) * 0.5
		sprite.region_enabled = true
		sprite.region_rect = Rect2(crop_left, 0.0, room_width, float(sprite.texture.get_height()))
	content.add_child(sprite)

	var sub := floor_sub_scene(floor_index)
	for point: Dictionary in room_data["investigation_points"]:
		var investigation := INVESTIGATION_POINT_SCENE.instantiate() as InvestigationPoint
		investigation.position = point["position"]
		investigation.investigation_id = point["investigation_id"]
		investigation.message = point["message"]
		investigation.investigation_name = point["investigation_name"]
		investigation.sub_scene = sub
		content.add_child(investigation)

	var room_chests: Array = room_data["chests"]
	for chest_index in range(room_chests.size()):
		var chest_data: Dictionary = room_chests[chest_index]
		var chest := CHEST_SCENE.instantiate() as Chest
		chest.position = chest_data["position"]
		chest.chest_id = _dynamic_chest_id(room_id, chest_data["type"], floor_index, room_index, chest_index)
		chest.chest_type = chest_data["type"]
		chest.star_level = int(zone_state["star"])
		chest.display_name = chest_data["name"]
		chest.sub_scene = sub
		content.add_child(chest)


func _dynamic_chest_id(room_id: String, chest_type: String, floor_index: int, room_index: int, chest_index: int) -> String:
	var identity_parts: Array[String] = [
		scene_id, zone_id, zone_type, building_instance_id,
		str(LAYOUT_VERSION), room_id, chest_type,
		str(floor_index), str(room_index), str(chest_index),
	]
	var encoded: Array[String] = []
	for part in identity_parts:
		encoded.append("%d:%s" % [part.length(), part])
	return "dyn_chest|" + "|".join(encoded)


func _room_width(room_id: String) -> float:
	return float(room_registry[room_id]["width"])


func _room_x(floor_index: int, room_index: int) -> float:
	var x := 0.0
	var row: Array = zone_state["rooms"][floor_index]
	for index in range(room_index):
		var data: Dictionary = row[index]
		x += float(data["width"]) if data["id"] == "空房间" else _room_width(data["id"])
		x += room_gap
	return x


func _on_room_entered(body: Node2D, floor_index: int, room_index: int, room_root: Node2D) -> void:
	if not body is Player:
		return
	zone_state["rooms"][floor_index][room_index]["entered"] = true
	var cover := room_root.get_node_or_null("UnseenCover")
	if cover:
		cover.queue_free()
	room_entered.emit(floor_index, room_index)


func _add_interior_wall(room_root: Node2D, room_width: float) -> void:
	var wall := TEXTURED_WALL_SCENE.instantiate() as TexturedWall
	wall.position = Vector2(room_width + room_gap * 0.5 - wall_width * 0.5, -room_height)
	wall.wall_size = Vector2(wall_width, room_height)
	wall.wall_texture = interior_wall_texture
	wall.z_index = 5
	room_root.add_child(wall)


func _add_floor_separator(floor_index: int) -> void:
	var separator := TextureRect.new()
	separator.name = "Floor_F%d" % (floor_index + 1)
	separator.position = Vector2(0.0, floor_y(floor_index))
	separator.size = Vector2(building_width, floor_separator_height)
	separator.z_index = 20
	separator.texture = floor_texture
	separator.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	separator.stretch_mode = TextureRect.STRETCH_TILE
	add_child(separator)


func _add_outer_walls() -> void:
	var top_y := floor_y(floor_count - 1) - room_height - 50
	var total_height := -top_y
	_add_outer_wall(Vector2(-wall_width, top_y), Vector2(wall_width, total_height - GROUND_ENTRANCE_HEIGHT))
	_add_outer_wall(Vector2(building_width, top_y), Vector2(wall_width, total_height))


func _add_outer_wall(wall_position: Vector2, size: Vector2) -> void:
	var wall := AIR_WALL_SCENE.instantiate() as Wall
	wall.position = wall_position
	wall.wall_size = size
	wall.use_top_left_origin = true
	wall.z_index = 30
	add_child(wall)

	var visual := TextureRect.new()
	visual.name = "OuterWallVisual"
	visual.texture = outer_wall_texture
	visual.position = wall_position
	visual.size = size
	visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visual.stretch_mode = TextureRect.STRETCH_TILE
	visual.z_index = 29
	add_child(visual)


func _add_stair_portal(floor_index: int) -> void:
	var portal := PORTAL_SCENE.instantiate() as Portal
	var portal_position: Array = building_config["portal_positions"]
	portal.position = Vector2(float(portal_position[0]), floor_y(floor_index) + float(portal_position[1]))
	portal.portal_id = _portal_id(floor_index)
	portal.sub_scene = floor_sub_scene(floor_index)
	portal.portal_name = "前往%d 楼" % (floor_index + 1)
	if floor_index < floor_count - 1:
		portal.target_portal_ids.append(_portal_id(floor_index + 1))
	if floor_index > 0:
		portal.target_portal_ids.append(_portal_id(floor_index - 1))
	add_child(portal)


func _portal_id(floor_index: int) -> String:
	return "zone_%s_floor_%d" % [zone_id.replace(",", "_"), floor_index + 1]


func _apply_building_config() -> void:
	floor_count = int(building_config["floor_count"])
	building_width = float(building_config["building_width"])
