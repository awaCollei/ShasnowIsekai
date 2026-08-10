extends Node2D
class_name RoomGenerator

## 建筑坐标约定：本节点 (0, 0) 是建筑左下角，也是 1 楼地板表面。
## Godot 的 Y 轴向下，因此第 N 层地板为 y = -(N - 1) * floor_pitch。

signal room_entered(floor_index: int, room_index: int)

@export_group("Building")
@export_range(1, 20, 1) var floor_count: int = 6
## 同一 zone 内存在多个建筑生成器时必须分别设置稳定值。
@export var building_instance_id: String = "main"
@export_range(100.0, 10000.0, 10.0) var building_width: float = 3200.0
@export_range(100.0, 1000.0, 10.0) var room_height: float = 450.0
@export_range(0.0, 200.0, 1.0) var floor_separator_height: float = 50.0
@export_range(200.0, 2000.0, 1.0) var stairwell_width: float = 953.0

@export_group("Rooms")
@export_range(2, 20, 1) var max_rooms_per_floor: int = 5
@export_range(0.0, 100.0, 1.0) var room_gap: float = 30.0  # 新增：房间之间的间隔
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
var scene_id := ""
var zone_type := ""
var building_config: Dictionary = {}
var building_config_available := false

const AIR_WALL_SCENE: PackedScene = preload("res://components/wall.tscn")
const TEXTURED_WALL_SCENE: PackedScene = preload("res://components/textured_wall.tscn")
const PORTAL_SCENE: PackedScene = preload("res://components/portal.tscn")
const INVESTIGATION_POINT_SCENE: PackedScene = preload("res://components/investigation_point.tscn")
const CHEST_SCENE: PackedScene = preload("res://components/chest.tscn")
const LAYOUT_VERSION := 4
const GROUND_ENTRANCE_HEIGHT := 240.0
const ROOMS_JSON_PATH := "res://building/rooms.json"

var floor_pitch: float:
	get:
		return room_height + floor_separator_height


func _ready() -> void:
	# 配置依赖区域状态，因此在 generate() 中加载，而不是在节点 ready 时加载。
	pass


## 从 rooms.json 加载房间配置，动态计算纹理路径和图片宽度。地图子类可以覆写此函数。
func register_rooms() -> void:
	room_registry.clear()
	building_config_available = false
	if scene_id.is_empty() or zone_type.is_empty():
		return
	var file := FileAccess.open(ROOMS_JSON_PATH, FileAccess.READ)
	if not file:
		push_error("无法读取房间配置: %s" % ROOMS_JSON_PATH)
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		push_error("房间配置 JSON 解析失败: %s" % ROOMS_JSON_PATH)
		return

	if not json.data is Dictionary:
		push_error("房间配置根节点必须是对象")
		return
	var root: Dictionary = json.data
	var scene_data: Dictionary = root.get(scene_id, {})
	var zone_data: Dictionary = scene_data.get(zone_type, {})
	if zone_data.is_empty():
		return
	building_config = zone_data
	var raw_rooms: Array = zone_data.get("rooms", [])

	if raw_rooms.is_empty():
		push_error("房间配置为空: %s / %s" % [scene_id, zone_type])
		return

	room_registry.clear()
	for raw in raw_rooms:
		if not raw is Dictionary:
			continue
		var room: Dictionary = raw.duplicate(true)
		var room_id := String(raw.get("id", ""))

		# 动态拼接纹理路径: res://assets/{场景}/{区域类型}/{ID}.png
		room["texture"] = "res://assets/%s/%s/%s.png" % [scene_id, zone_type, room_id]

		# 动态计算 width：加载纹理获取图片宽度
		var tex := load(room["texture"]) as Texture2D
		if tex:
			room["width"] = float(tex.get_width())
		else:
			push_warning("无法加载房间纹理: %s，使用默认宽度" % room["texture"])
			room["width"] = 640.0

		# 将 JSON 数组形式的 position 转为 Vector2
		for pt in room.get("investigation_points", []):
			_convert_relative_position(pt)
		for chest_data in room.get("chests", []):
			_convert_relative_position(chest_data)

		room_registry.append(room)

	building_config_available = not room_registry.is_empty() and not _find_room_by_id("楼梯间").is_empty()
	if not building_config_available:
		push_warning("区域没有完整建筑配置，跳过生成: %s / %s" % [scene_id, zone_type])


func _convert_relative_position(data) -> void:
	if data is Dictionary and data.has("position") and data["position"] is Array:
		var arr: Array = data["position"]
		if arr.size() >= 2:
			data["position"] = Vector2(float(arr[0]), float(arr[1]))

func room_probability(room: Dictionary, _floor_index: int) -> float:
	return maxf(0.0, float(room.get("weight", 1.0)))


func generate(state: Dictionary, id: String) -> void:
	zone_id = id
	zone_state = state
	scene_id = String(state.get("scene", "city1"))
	zone_type = String(state.get("region_type", ""))
	register_rooms()
	_clear_generated_building()
	if not building_config_available:
		return
	_apply_building_config()

	var layouts: Array = zone_state.get("rooms", [])
	if not _layout_is_current(layouts):
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

	# 最顶上添加一层 floor separator
	_add_floor_separator(floor_count)

	_add_outer_walls()


func has_building_config() -> bool:
	return building_config_available


func floor_sub_scene(floor_index: int) -> String:
	return "outdoor" if floor_index == 0 else "floor%d" % (floor_index + 1)


func floor_y(floor_index: int) -> float:
	return -float(floor_index) * floor_pitch


## 供地图脚本生成敌人使用。返回的是生成器局部坐标。
func get_enemy_spawn_candidates(height_above_floor: float) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for room in generated_rooms:
		if String(room.get("id", "")) == "楼梯间":
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
	if String(zone_state.get("room_layout_scene", "")) != scene_id or String(zone_state.get("room_layout_zone_type", "")) != zone_type:
		return false
	if layouts.size() != floor_count:
		return false
	for row in layouts:
		if not row is Array or row.is_empty() or row.size() > max_rooms_per_floor:
			return false
		if not row[0] is Dictionary:
			return false
		if String(row[0].get("id", "")) != "楼梯间":
			return false
		if not is_equal_approx(float(row[0].get("width_px", 0.0)) , stairwell_width):
			return false
		var total_width := 0.0
		for data in row:
			if not data is Dictionary or not data.has("width_px") or not _room_id_exists(String(data.get("id", ""))):
				return false
			total_width += float(data["width_px"])
		# 考虑间隔的总宽度
		var total_gaps := float(row.size() - 1) * room_gap
		if not is_equal_approx(total_width + total_gaps, building_width):
			return false
	return true


func _create_layout() -> Array:
	var result: Array = []
	# 找到楼梯间房间数据
	var stairwell_room := _find_room_by_id("楼梯间")
	var stairwell_id := String(stairwell_room.get("id", "楼梯间"))
	var empty_room := _find_room_by_id("空房间")
	var empty_id := String(empty_room.get("id", "空房间"))
	
	for floor_index in range(floor_count):
		var row: Array = []
		var used_width := 0.0  # 房间宽度总和，不含间隔
		var first_width := stairwell_width
		row.append({"id": stairwell_id, "role": "stairwell", "width_px": first_width, "entered": false})
		used_width += first_width

		# 可用宽度 = 建筑总宽 - 间隔总和
		while used_width < building_width and row.size() < max_rooms_per_floor:
			var gaps_so_far := float(row.size()) * room_gap  # 已有房间之间的间隔
			var remaining := building_width - used_width - gaps_so_far
			if remaining <= 0:
				break
			var selected := _choose_room(floor_index, remaining)
			if selected.is_empty():
				break
			var width: float
			if String(selected.get("id", "")) == "空房间":
				width = minf(minf(float(selected.get("width", remaining)), _empty_room_max_width(remaining)), remaining)
			else:
				width = float(selected.get("width", remaining))
			row.append({"id": String(selected.get("id", "空房间")), "width_px": width, "entered": false})
			used_width += width

		# 处理剩余宽度：空房间的最大宽度按本建筑动态计算，必要时分成多个槽位。
		# 选择下一间时要预留新间隔；实际填充时只扣除已有的间隔，避免
		# 在“剩余宽度小于一个间隔”时留下未填充的尾部。
		var remaining := building_width - used_width - float(row.size()) * room_gap
		while remaining > 0.0 and row.size() < max_rooms_per_floor:
			var empty_width := minf(remaining, _empty_room_max_width(remaining))
			row.append({"id": empty_id, "width_px": empty_width, "entered": false})
			used_width += empty_width
			remaining = building_width - used_width - float(row.size()) * room_gap

		# 只要还存在可用宽度，就由最后一个槽位吸收它。这里使用
		# (房间数 - 1) 个间隔，而不是 row.size() 个，确保布局精确填满。
		remaining = building_width - used_width - float(row.size() - 1) * room_gap
		if remaining > 0.0 and not row.is_empty():
			row[row.size() - 1]["width_px"] = float(row[row.size() - 1]["width_px"]) + remaining
		result.append(row)
	return result


func _choose_room(floor_index: int, remaining_width: float) -> Dictionary:
	var choices: Array[Dictionary] = []
	var total := 0.0
	for room in room_registry:
		if String(room.get("id", "")) == "楼梯间":
			continue
		if String(room.get("id", "")) != "空房间" and float(room.get("width", 0.0)) > remaining_width:
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
	var room_id := String(data.get("id", "空房间"))
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

	_create_room_content(room_root, room_id, floor_index, room_index, width)

	# 只在非最右侧房间添加右墙，但墙壁现在在间隔区域中
	var row: Array = zone_state["rooms"][floor_index]
	if room_index < row.size() - 1:
		_add_interior_wall(room_root, width)

	var trigger := Area2D.new()
	trigger.name = "RevealTrigger"
	var trigger_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	# 触发区域保持房间宽度，但稍微缩小边缘
	var trigger_width := width - wall_width * 0.5
	var trigger_height := room_height - wall_width * 0.5
	rectangle.size = Vector2(trigger_width, trigger_height)
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
		"role": String(data.get("role", "")),
		"x": x,
		"width": width,
		"entered": bool(data.get("entered", false)),
	})


func _find_room_data(room_id: String) -> Dictionary:
	for room in room_registry:
		if String(room.get("id", "")) == room_id:
			return room
	return {}


func _create_room_content(room_root: Node2D, room_id: String, floor_index: int, room_index: int, room_width: float) -> void:
	var room_data := _find_room_data(room_id)
	if room_data.is_empty():
		return

	var content := Node2D.new()
	content.name = "Content"
	room_root.add_child(content)

	var sub := floor_sub_scene(floor_index)

	var texture_path := String(room_data.get("texture", ""))
	if not texture_path.is_empty():
		var sprite := Sprite2D.new()
		sprite.name = "RoomImage"
		sprite.texture = load(texture_path) as Texture2D
		sprite.position = Vector2(room_width * 0.5, -225.0)
		# 空房间缩窄时裁剪贴图，两侧等量裁切以保持居中
		if String(room_data.get("id", "")) == "空房间":
			var natural_width := float(room_data.get("width", 938.0))
			if room_width < natural_width:
				var tex := sprite.texture
				if tex:
					var half_diff := (tex.get_width() - room_width) / 2.0
					sprite.region_enabled = true
					sprite.region_rect = Rect2(half_diff, 0, room_width, tex.get_height())
		content.add_child(sprite)

	for pt in room_data.get("investigation_points", []):
		if not pt is Dictionary:
			continue
		var ip := INVESTIGATION_POINT_SCENE.instantiate() as InvestigationPoint
		if not ip:
			continue
		ip.position = pt.get("position", Vector2.ZERO)
		ip.investigation_id = String(pt.get("investigation_id", ""))
		ip.message = String(pt.get("message", ""))
		ip.investigation_name = String(pt.get("investigation_name", ""))
		ip.sub_scene = sub
		content.add_child(ip)

	var room_chests: Array = room_data.get("chests", [])
	for chest_index in range(room_chests.size()):
		var raw_chest = room_chests[chest_index]
		if not raw_chest is Dictionary:
			continue
		var chest := CHEST_SCENE.instantiate() as Chest
		if not chest:
			continue
		chest.position = raw_chest.get("position", Vector2.ZERO)
		var generated_type := String(raw_chest.get("type", ""))
		chest.chest_id = _dynamic_chest_id(room_id, generated_type, floor_index, room_index, chest_index)
		chest.chest_type = generated_type
		chest.display_name = String(raw_chest.get("name", "箱子"))
		chest.capacity = maxi(1, int(raw_chest.get("capacity", 24)))
		chest.infinite_storage = bool(raw_chest.get("infinite", false))
		chest.sub_scene = sub
		content.add_child(chest)


func _dynamic_chest_id(room_id: String, chest_type: String, floor_index: int, room_index: int, chest_index: int) -> String:
	# 长度前缀编码不会像简单 replace 那样让 `1,2` 与 `1_2` 发生碰撞。
	# room/type/region/layout 纳入身份后，布局或配置改变不会误用旧种类箱子的内容。
	var identity_parts: Array[String] = [
		scene_id, zone_id, zone_type, building_instance_id,
		str(LAYOUT_VERSION), room_id, chest_type,
		str(floor_index), str(room_index), str(chest_index),
	]
	var encoded: Array[String] = []
	for part in identity_parts:
		encoded.append("%d:%s" % [part.length(), part])
	return "dyn_chest|" + "|".join(encoded)


func _room_x(floor_index: int, room_index: int) -> float:
	var x := 0.0
	var row: Array = zone_state["rooms"][floor_index]
	# 房间位置 = 之前所有房间宽度 + 之前所有间隔
	for index in range(room_index):
		x += float(row[index].get("width_px", 0.0))
		x += room_gap  # 每个房间后面跟一个间隔
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
	# 墙壁现在放置在房间右边缘 + 间隔的一半位置
	wall.position = Vector2(room_width + room_gap * 0.5 - wall_width * 0.5, -room_height)
	wall.wall_size = Vector2(wall_width, room_height)
	if interior_wall_texture:
		wall.wall_texture = interior_wall_texture
	wall.z_index = 5
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
	# 左墙在一楼保留入口
	_add_outer_wall(Vector2(0.0, top_y), Vector2(wall_width, maxf(1.0, total_height - GROUND_ENTRANCE_HEIGHT)))
	# 右墙从顶部到底部
	_add_outer_wall(Vector2(building_width - wall_width, top_y), Vector2(wall_width, total_height))


func _add_outer_wall(wall_position: Vector2, size: Vector2) -> void:
	# 碰撞墙（不可见）
	var wall := AIR_WALL_SCENE.instantiate() as Wall
	if not wall:
		return
	wall.position = wall_position
	wall.wall_size = size
	wall.use_top_left_origin = true
	wall.z_index = 30
	add_child(wall)

	# 视觉墙：用 TextureRect 平铺
	if outer_wall_texture:
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
	if not portal:
		return
	var portal_pos: Array = building_config.get("portal_positions", [])
	if portal_pos.size() >= 2:
		portal.position = Vector2(float(portal_pos[0]), floor_y(floor_index) + float(portal_pos[1]))
	else:
		var row: Array = zone_state["rooms"][floor_index]
		var actual_stairwell_width := float(row[0].get("width_px", building_width))
		portal.position = Vector2(actual_stairwell_width * 0.25, floor_y(floor_index) - stair_portal_height)
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


func _room_id_exists(room_id: String) -> bool:
	for room in room_registry:
		if String(room.get("id", "")) == room_id:
			return true
	return false


func _apply_building_config() -> void:
	floor_count = maxi(1, int(building_config.get("floor_count", floor_count)))
	var stairwell := _find_room_by_id("楼梯间")
	# 楼梯间宽度优先使用配置，否则取楼梯间贴图的自然宽度。
	if building_config.has("stairwell_width"):
		stairwell_width = float(building_config["stairwell_width"])
	elif stairwell.has("width"):
		stairwell_width = float(stairwell["width"])


func _empty_room_max_width(remaining_width: float) -> float:
	# 空房间不再依赖固定宽度；上限随建筑剩余空间和可用房间槽位变化。
	var configured := float(building_config.get("empty_room_max_width", 0.0))
	if configured > 0.0:
		return configured
	var slots := maxi(1, max_rooms_per_floor - 1)
	var calculated := (building_width - stairwell_width - float(slots) * room_gap) / float(slots)
	return maxf(1.0, calculated)


func _find_room_by_id(room_id: String) -> Dictionary:
	for room in room_registry:
		if String(room.get("id", "")) == room_id:
			return room
	return {}
