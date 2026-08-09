extends RefCounted
class_name MapState

const WIDTH := 7
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
	return data

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
