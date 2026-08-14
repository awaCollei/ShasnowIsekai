extends RefCounted
class_name SceneRegistry

const REGISTRY_PATH := "res://map/scene_registry.json"
static var _scenes: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _scenes.is_empty(): return
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary: _scenes = parsed

static func has_scene(scene_id: String) -> bool:
	_ensure_loaded(); return _scenes.has(scene_id)

static func get_scene_info(scene_id: String) -> Dictionary:
	_ensure_loaded(); return _scenes.get(scene_id, {}).duplicate(true)

static func get_all_scenes() -> Dictionary:
	_ensure_loaded(); return _scenes.duplicate(true)

static func get_scene_ids() -> Array[String]:
	_ensure_loaded(); var result: Array[String] = []
	for id in _scenes: result.append(id)
	return result

static func find_scene_id_by_path(scene_path: String) -> String:
	_ensure_loaded()
	for id in _scenes:
		if _scenes[id].get("scene_path", "") == scene_path: return id
	return ""

static func _find_region_type(region_type: String) -> Dictionary:
	for scene_id in _scenes:
		var info: Dictionary = _scenes[scene_id]
		if not info is Dictionary: continue
		for rt in info.get("region_types", []):
			if rt.get("id", "") == region_type: return rt
	return {}

static func type_name(region_type: String) -> String:
	_ensure_loaded()
	return _find_region_type(region_type).get("name", "未知区域")

static func type_icon(region_type: String) -> String:
	_ensure_loaded()
	return _find_region_type(region_type).get("icon", "❓")

static func get_region_types(scene_id: String) -> Array:
	_ensure_loaded()
	var info: Dictionary = _scenes.get(scene_id, {})
	var raw: Array = info.get("region_types", [])
	var result: Array = []
	for rt in raw:
		if rt is Dictionary: result.append(rt.duplicate())
	return result

static func region_description(region_type: String) -> String:
	_ensure_loaded()
	return _find_region_type(region_type).get("description", "一片尚待探索的区域。")
