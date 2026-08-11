extends Node2D
class_name RVWorld

## 房车是跨地图共享的移动小世界。其掉落物和敌人不属于当前地面场景。
const STORAGE_ID := "rv"

@export var enemy_container_path: NodePath = ^"Enemies"

func _ready() -> void:
	InventoryManager.restore_scene_drops(STORAGE_ID)
	_restore_enemies()

func capture_state() -> void:
	var enemies: Array = []
	for node in find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if enemy and is_instance_valid(enemy) and enemy.hp > 0:
			enemies.append({
				"scene_path": enemy.scene_file_path,
				"position": enemy.global_position,
				"sub_scene": enemy.sub_scene,
				"hp": enemy.hp,
				"max_hp": enemy.max_hp,
			})
	SaveManager.runtime_enemy_maps[STORAGE_ID] = {"initialized": true, "enemies": enemies}

func _restore_enemies() -> void:
	var state: Dictionary = SaveManager.runtime_enemy_maps.get(STORAGE_ID, {})
	if state.is_empty():
		return
	for raw in state.get("enemies", []):
		if not raw is Dictionary:
			continue
		var packed := load(String(raw.get("scene_path", ""))) as PackedScene
		if not packed:
			continue
		var enemy := packed.instantiate() as Enemy
		if not enemy:
			continue
		get_node(enemy_container_path).add_child(enemy)
		enemy.global_position = raw.get("position", Vector2.ZERO)
		enemy.max_hp = maxi(1, int(raw.get("max_hp", enemy.max_hp)))
		enemy.hp = clampi(int(raw.get("hp", enemy.max_hp)), 1, enemy.max_hp)
		enemy.sub_scene = String(raw.get("sub_scene", "rv_indoor"))

func _exit_tree() -> void:
	capture_state()
