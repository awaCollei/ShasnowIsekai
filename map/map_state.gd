extends RefCounted
class_name MapState

const WIDTH := 7
const HEIGHT := 5
const BASE_ZONE := "0,2"
const VERSION := 2
const TYPE_NAMES := {"office":"写字楼", "hospital":"医院", "residential":"住宅区", "market":"市场", "shop":"商店", "camp":"营地", "garage":"车库"}

static func create_new() -> Dictionary:
	var zones := {}
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var city_types := ["office", "hospital", "residential", "market"]
	# 规则：先保证每种类型至少出现一次，再填充剩余格子。
	var pool := city_types.duplicate()
	for i in range(WIDTH * HEIGHT - 1 - pool.size()): pool.append(city_types[rng.randi_range(0, city_types.size() - 1)])
	pool.shuffle(); var index := 0
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var id := "%d,%d" % [x, y]
			var is_base := id == BASE_ZONE
			var type = "camp" if is_base else pool[index]
			if not is_base: index += 1
			zones[id] = _new_zone("base" if is_base else "city1", type, is_base)
	return {"version": VERSION, "width": WIDTH, "height": HEIGHT, "zones": zones}

static func _new_zone(scene: String, region_type: String, visited := false) -> Dictionary:
	return {"scene":scene, "region":scene, "region_type":region_type, "discovered":visited, "entered":visited, "visit_count":1 if visited else 0, "rooms":[], "enemies":[], "enemy_initialized":false}

static func ensure(data: Dictionary) -> Dictionary:
	if data.is_empty() or not data.has("zones") or not data["zones"] is Dictionary: return create_new()
	data["version"] = VERSION; data["width"] = WIDTH; data["height"] = HEIGHT
	for id in data["zones"]:
		var zone: Dictionary = data["zones"][id]
		if not zone.has("scene"): zone["scene"] = "base" if id == BASE_ZONE else "city1"
		if not zone.has("region_type"):
			var legacy_type := String(zone.get("region", "office"))
			zone["region_type"] = "office" if legacy_type == "city1" else legacy_type
		if not zone.has("enemies"): zone["enemies"] = []
		if not zone.has("rooms"): zone["rooms"] = []
		if not zone.has("visit_count"): zone["visit_count"] = 1 if zone.get("entered", false) else 0
		data["zones"][id] = zone
	return data

static func zone_id(x: int, y: int) -> String: return "%d,%d" % [x, y]
static func get_zone(data: Dictionary, id: String) -> Dictionary: return data.get("zones", {}).get(id, {})
static func type_name(region_type: String) -> String: return TYPE_NAMES.get(region_type, "未知区域")
static func set_zone(data: Dictionary, id: String, zone: Dictionary) -> void:
	if not data.has("zones"): data["zones"] = {}
	data["zones"][id] = zone
