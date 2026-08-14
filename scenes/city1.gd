extends WorldScene

## city1 使用区域(zone)状态；scene 只决定该区域的背景和房间资源。
const INTRO_PLOT_ID: String = "1_1"
const SLIME_SCENE: PackedScene = preload("res://enemies/slime.tscn")
const DEFAULT_CITY_ZONE := "1,2"

## 敌人系统仍在早期阶段：暂时只用数量、生命和伤害倍率表达区域星级。
const ENEMY_STAR_RULES := {
	1: {"extra_count": 0, "hp_multiplier": 1.0, "damage_multiplier": 1.0},
	2: {"extra_count": 1, "hp_multiplier": 1.35, "damage_multiplier": 1.20},
	3: {"extra_count": 2, "hp_multiplier": 1.75, "damage_multiplier": 1.45},
}

@export_group("Building Placement")
## 建筑左下角 / 1 楼地板表面的世界坐标。
@export var building_origin: Vector2 = Vector2(-700.0, 735.0)
@export var enemy_height_above_floor: float = 40.0

@export_group("Building Resources")
@export var outer_wall_texture: Texture2D
@export var interior_wall_texture: Texture2D
@export var floor_texture: Texture2D

var room_generator: RoomGenerator
var current_zone_state: Dictionary = {}
var active_zone_id: String = DEFAULT_CITY_ZONE


## WorldScene 据此跳过旧版 scene-level 敌人快照，统一使用 zone 状态。
func uses_zone_state() -> bool:
	return true


func _spawn_scene_entities() -> void:
	_prepare_zone_state()
	_create_room_generator()
	room_generator.generate(current_zone_state, active_zone_id)

	if current_zone_state.get("enemies", []).is_empty() and not bool(current_zone_state.get("enemy_initialized", false)):
		_spawn_zone_enemies()
		current_zone_state["enemy_initialized"] = true
	else:
		_restore_zone_enemies()
	_write_zone_state()


func _prepare_zone_state() -> void:
	var map_state := SaveManager.runtime_map_state
	if map_state.is_empty():
		SaveManager.runtime_map_state = MapState.create_new()
		map_state = SaveManager.runtime_map_state
	var zones: Dictionary = map_state.get("zones", {})
	active_zone_id = SaveManager.current_zone_id
	var requested_zone: Dictionary = zones.get(active_zone_id, {})
	# 直接从地点列表进入 city1 时，current_zone_id 可能仍指向出生点。
	if active_zone_id.is_empty() or String(requested_zone.get("scene", "")) != "city1":
		active_zone_id = DEFAULT_CITY_ZONE
	SaveManager.current_zone_id = active_zone_id
	current_zone_state = zones.get(active_zone_id, {})
	if current_zone_state.is_empty():
		current_zone_state = {
			"scene": "city1", "region": "city1", "region_type": "office", "star": 1, "discovered": true,
			"entered": true, "rooms": [], "enemies": [], "enemy_initialized": false,
		}
		zones[active_zone_id] = current_zone_state
		map_state["zones"] = zones
	current_zone_state["discovered"] = true
	current_zone_state["entered"] = true


func _create_room_generator() -> void:
	if room_generator and is_instance_valid(room_generator):
		room_generator.queue_free()
	room_generator = RoomGenerator.new()
	room_generator.position = building_origin
	room_generator.outer_wall_texture = outer_wall_texture
	room_generator.interior_wall_texture = interior_wall_texture
	room_generator.floor_texture = floor_texture
	add_child(room_generator)


func _spawn_zone_enemies() -> void:
	var candidates := room_generator.get_enemy_spawn_candidates(enemy_height_above_floor)
	candidates.shuffle()
	var count := mini(_roll_enemy_count(), candidates.size())
	var saved: Array = []
	for index in range(count):
		var candidate: Dictionary = candidates[index]
		var world_position: Vector2 = room_generator.to_global(candidate["position"])
		var enemy := spawn_enemy(SLIME_SCENE, world_position)
		if not enemy:
			continue
		_apply_enemy_star_strength(enemy, true)
		enemy.sub_scene = String(candidate["sub_scene"])
		saved.append({
			"scene_path": SLIME_SCENE.resource_path,
			"position": world_position,
			"floor": int(candidate["floor"]),
			"room_index": int(candidate["room_index"]),
			"sub_scene": enemy.sub_scene,
			"hp": enemy.max_hp,
			"max_hp": enemy.max_hp,
		})
	current_zone_state["enemies"] = saved


func _restore_zone_enemies() -> void:
	for raw in current_zone_state.get("enemies", []):
		if not raw is Dictionary:
			continue
		var packed := load(String(raw.get("scene_path", SLIME_SCENE.resource_path))) as PackedScene
		if not packed:
			continue
		var enemy := spawn_enemy(packed, raw.get("position", Vector2.ZERO))
		if enemy:
			_apply_enemy_star_strength(enemy, false)
			enemy.max_hp = maxi(1, int(raw.get("max_hp", enemy.max_hp)))
			enemy.hp = clampi(int(raw.get("hp", enemy.max_hp)), 1, enemy.max_hp)
			enemy.sub_scene = String(raw.get("sub_scene", "outdoor"))


func _roll_enemy_count() -> int:
	var value := randf()
	var base_count: int
	if value < 0.20:
		base_count = 0
	elif value < 0.60:
		base_count = 1
	elif value < 0.90:
		base_count = 2
	else:
		base_count = 3
	var rule: Dictionary = ENEMY_STAR_RULES[int(current_zone_state["star"])]
	return base_count + int(rule["extra_count"])


func _apply_enemy_star_strength(enemy: Enemy, scale_health: bool) -> void:
	var rule: Dictionary = ENEMY_STAR_RULES[int(current_zone_state["star"])]
	if scale_health:
		enemy.max_hp = maxi(1, roundi(float(enemy.max_hp) * float(rule["hp_multiplier"])))
		enemy.hp = enemy.max_hp
	# 当前 city1 只有 Slime；保留基类字段同步，方便后续敌人重构前观察效果。
	enemy.battle_damage *= float(rule["damage_multiplier"])
	if enemy is Slime:
		(enemy as Slime).attack_damage *= float(rule["damage_multiplier"])


func capture_zone_state() -> void:
	if not room_generator or current_zone_state.is_empty():
		return
	var enemies: Array = []
	for node in find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if enemy and enemy.hp > 0:
			enemies.append({
				"scene_path": enemy.scene_file_path,
				"position": enemy.global_position,
				"sub_scene": enemy.sub_scene,
				"hp": enemy.hp,
				"max_hp": enemy.max_hp,
			})
	current_zone_state["enemies"] = enemies
	current_zone_state["entered"] = true
	_write_zone_state()


func _write_zone_state() -> void:
	var zones: Dictionary = SaveManager.runtime_map_state.get("zones", {})
	zones[active_zone_id] = current_zone_state
	SaveManager.runtime_map_state["zones"] = zones


func _on_world_ready() -> void:
	# 正常路径已在 _spawn_scene_entities 完成；仅兼容热重载或旧初始化顺序。
	if room_generator == null:
		_prepare_zone_state()
		_create_room_generator()
		if room_generator:
			room_generator.generate(current_zone_state, active_zone_id)
	capture_zone_state()
