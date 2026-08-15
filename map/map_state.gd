extends RefCounted
class_name MapState

const WIDTH := 7
const HEIGHT := 6
const BASE_ID := "base"
const VERSION := 6

## 每张 7×6 区域地图的固定星级配额；总数必须等于 WIDTH * HEIGHT。
const STAR_COUNTS := {
	1: 21,
	2: 14,
	3: 7,
}

static func create_new() -> Dictionary:
	var zones := {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	var region_types := SceneRegistry.get_region_types("city1")
	var city_types: Array[String] = []
	var weighted_pool: Array[String] = []
	for rt in region_types:
		city_types.append(rt.id)
		var w: int = rt.get("weight", 10)
		for _i in range(w):
			weighted_pool.append(rt.id)
	
	var total_cells := WIDTH * HEIGHT
	var star_types := STAR_COUNTS.keys()  # [1, 2, 3]
	var type_count := city_types.size()
	
	# 检查是否可行
	var min_required := type_count * star_types.size()  # 每种类型×每个星级
	assert(min_required <= total_cells, "区域类型太多，无法保证每种类型每个星级至少一个")
	
	# 创建配对的单元格列表
	var cells: Array[Dictionary] = []
	
	# 第一步：为每种类型×每个星级创建必需的配对
	for type_id in city_types:
		for star in star_types:
			cells.append({"type": type_id, "star": star})
	
	# 第二步：填充剩余格子
	var remaining_count := total_cells - cells.size()
	
	# 统计每种星级已经使用了多少个
	var star_used: Dictionary = {}
	for star in star_types:
		star_used[star] = type_count  # 每种类型已经用了1个该星级
	
	# 创建剩余星级的池
	var remaining_stars: Array[int] = []
	for star in star_types:
		var remaining := int(STAR_COUNTS[star]) - int(star_used[star])
		for _i in range(remaining):
			remaining_stars.append(star)
	
	# 随机打乱剩余星级
	remaining_stars.shuffle()
	
	# 为剩余格子分配类型和星级
	for i in range(remaining_count):
		var type_id = weighted_pool[rng.randi_range(0, weighted_pool.size() - 1)]
		var star = remaining_stars[i] if i < remaining_stars.size() else 1
		cells.append({"type": type_id, "star": star})
	
	# 打乱所有单元格
	cells.shuffle()
	
	# 验证：统计每种类型×星级的数量
	var verification: Dictionary = {}
	for type_id in city_types:
		verification[type_id] = {}
		for star in star_types:
			verification[type_id][star] = 0
	
	for cell in cells:
		var type_id = cell["type"]
		var star = cell["star"]
		if verification.has(type_id) and verification[type_id].has(star):
			verification[type_id][star] += 1
	
	# 最终验证
	for type_id in city_types:
		for star in star_types:
			assert(verification[type_id][star] >= 1, 
				"类型 %s 缺少星级 %d (当前数量: %d)" % [type_id, star, verification[type_id][star]])
	
	# 生成地图
	var index := 0
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var id := "%d,%d" % [x, y]
			var cell = cells[index]
			zones[id] = _new_zone("city1", cell["type"], cell["star"])
			index += 1
	
	var base := _new_zone("base", "camp", 1, true)
	return {
		"version": VERSION, 
		"width": WIDTH, 
		"height": HEIGHT, 
		"loot_seed": rng.randi(), 
		"base": base, 
		"zones": zones
	}

static func _new_zone(scene: String, region_type: String, star: int, visited := false) -> Dictionary:
	return {
		"scene": scene, 
		"region": scene, 
		"region_type": region_type, 
		"star": star, 
		"discovered": visited, 
		"entered": visited, 
		"visit_count": 1 if visited else 0, 
		"rooms": [], 
		"enemies": [], 
		"enemy_initialized": false
	}

static func ensure(data: Dictionary) -> Dictionary:
	# 版本不匹配时重新生成地图
	if data.is_empty() or not data.has("zones") or not data["zones"] is Dictionary or int(data.get("version", 0)) != VERSION:
		return create_new()
	data["width"] = WIDTH
	data["height"] = HEIGHT
	return data

static func zone_id(x: int, y: int) -> String: 
	return "%d,%d" % [x, y]

static func get_zone(data: Dictionary, id: String) -> Dictionary:
	if id == BASE_ID: 
		return data.get("base", {})
	return data.get("zones", {}).get(id, {})

static func set_zone(data: Dictionary, id: String, zone: Dictionary) -> void:
	if id == BASE_ID:
		data["base"] = zone
	else:
		if not data.has("zones"): 
			data["zones"] = {}
		data["zones"][id] = zone

static func type_name(region_type: String) -> String: 
	return SceneRegistry.type_name(region_type)
