extends RefCounted
class_name MapState

const WIDTH := 6
const HEIGHT := 6
const BASE_ID := "base"
const VERSION := 3

static func create_new() -> Dictionary:
	var zones := {}
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var city_types := ["office", "hospital", "residential", "market"]
	# 规则：先保证每种类型至少出现一次，再填充剩余格子。
	var pool := city_types.duplicate()
	for i in range(WIDTH * HEIGHT - pool.size()): pool.append(city_types[rng.randi_range(0, city_types.size() - 1)])
	pool.shuffle(); var index := 0
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var id := "%d,%d" % [x, y]
			zones[id] = _new_zone("city1", pool[index])
			index += 1
	var base := _new_zone("base", "camp", true)
	return {"version": VERSION, "width": WIDTH, "height": HEIGHT, "base": base, "zones": zones}

static func _new_zone(scene: String, region_type: String, visited := false) -> Dictionary:
	return {"scene":scene, "region":scene, "region_type":region_type, "discovered":visited, "entered":visited, "visit_count":1 if visited else 0, "rooms":[], "enemies":[], "enemy_initialized":false}

static func ensure(data: Dictionary) -> Dictionary:
	if data.is_empty() or not data.has("zones") or not data["zones"] is Dictionary: return create_new()
	data["version"] = VERSION; data["width"] = WIDTH; data["height"] = HEIGHT

	# 迁移：旧版 "0,2" 是基地格子，移到独立的 base 字段
	if not data.has("base"):
		var legacy: Dictionary = data["zones"].get("0,2", {})
		if legacy.get("scene", "") == "base":
			data["base"] = legacy.duplicate(true)
			# 将 "0,2" 替换为普通城区，保持 region_type 随机
			data["zones"]["0,2"] = _new_zone("city1", _random_city_type())
		else:
			data["base"] = _new_zone("base", "camp", true)
	# 确保 base 字段完整性
	var base: Dictionary = data["base"]
	base["scene"] = "base"; base["region"] = "base"; base["region_type"] = "camp"
	if not base.has("discovered"): base["discovered"] = true
	if not base.has("entered"): base["entered"] = true
	if not base.has("visit_count"): base["visit_count"] = 1
	if not base.has("rooms"): base["rooms"] = []
	if not base.has("enemies"): base["enemies"] = []
	if not base.has("enemy_initialized"): base["enemy_initialized"] = false
	data["base"] = base

	# 确保 zones 中恰好有 36 个城区格子
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var id := "%d,%d" % [x, y]
			if not data["zones"].has(id):
				data["zones"][id] = _new_zone("city1", _random_city_type())

	for id in data["zones"]:
		var zone: Dictionary = data["zones"][id]
		if not zone.has("scene"): zone["scene"] = "city1"
		if not zone.has("region_type"):
			var legacy_type := String(zone.get("region", "office"))
			zone["region_type"] = "office" if legacy_type == "city1" else legacy_type
		if not zone.has("enemies"): zone["enemies"] = []
		if not zone.has("rooms"): zone["rooms"] = []
		if not zone.has("visit_count"): zone["visit_count"] = 1 if zone.get("entered", false) else 0
		data["zones"][id] = zone
	return data

static func _random_city_type() -> String:
	var types := ["office", "hospital", "residential", "market"]
	return types[randi() % types.size()]

static func zone_id(x: int, y: int) -> String: return "%d,%d" % [x, y]

static func get_zone(data: Dictionary, id: String) -> Dictionary:
	if id == BASE_ID: return data.get("base", {})
	return data.get("zones", {}).get(id, {})

static func set_zone(data: Dictionary, id: String, zone: Dictionary) -> void:
	if id == BASE_ID:
		data["base"] = zone
	else:
		if not data.has("zones"): data["zones"] = {}
		data["zones"][id] = zone

static func type_name(region_type: String) -> String: return SceneRegistry.type_name(region_type)
