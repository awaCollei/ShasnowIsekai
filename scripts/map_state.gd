extends RefCounted
class_name MapState

## 大地图与区域状态的纯数据工具。所有随机数只在首次创建时使用，之后由存档复现。
const WIDTH := 7
const HEIGHT := 5
const BASE_ZONE := "0,2"

static func create_new() -> Dictionary:
	var zones := {}
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var id := "%d,%d" % [x, y]
			zones[id] = {
				"scene": "base" if id == BASE_ZONE else "city1",
				"region": "base" if id == BASE_ZONE else "city1",
				"discovered": id == BASE_ZONE,
				"entered": id == BASE_ZONE,
				"rooms": [],
				"enemies": [],
				"enemy_initialized": false
			}
	return {"version": 1, "width": WIDTH, "height": HEIGHT, "zones": zones}

static func ensure(data: Dictionary) -> Dictionary:
	if data.is_empty() or not data.has("zones"):
		return create_new()
	# 兼容上一版只有 region 的区域数据：scene 是 zone 的属性。
	for id in data["zones"]:
		var zone: Dictionary = data["zones"][id]
		if not zone.has("scene"):
			zone["scene"] = "base" if id == BASE_ZONE else "city1"
		if not zone.has("enemies"):
			zone["enemies"] = []
		data["zones"][id] = zone
	return data

static func zone_id(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

static func get_zone(data: Dictionary, id: String) -> Dictionary:
	var zones: Dictionary = data.get("zones", {})
	return zones.get(id, {})

static func set_zone(data: Dictionary, id: String, zone: Dictionary) -> void:
	if not data.has("zones"):
		data["zones"] = {}
	data["zones"][id] = zone
