extends RefCounted
class_name SceneRegistry

# 所有可通过地图前往的场景都在此注册。
# 每个场景自己的 tscn 必须包含 Player；玩家出生位置直接由 tscn 决定。
const SCENES: Dictionary = {
	"base": {
		"display_name": "房车营地",
		"scene_path": "res://scenes/base.tscn",
		"default_sub_scene": "outdoor",
		"description": "房车与周边营地。",
		"map_position": Vector2(0.30, 0.58),
	},
	"city1": {
		"display_name": "临海市",
		"scene_path": "res://scenes/city1.tscn",
		"default_sub_scene": "outdoor",
		"description": "临海市",
		"map_position": Vector2(0.30, 0.58),
	}
}


static func has_scene(scene_id: String) -> bool:
	return SCENES.has(scene_id)


static func get_scene_info(scene_id: String) -> Dictionary:
	return SCENES.get(scene_id, {}).duplicate(true)


static func get_all_scenes() -> Dictionary:
	return SCENES.duplicate(true)


static func find_scene_id_by_path(scene_path: String) -> String:
	for scene_id: String in SCENES:
		if SCENES[scene_id].get("scene_path", "") == scene_path:
			return scene_id
	return ""
