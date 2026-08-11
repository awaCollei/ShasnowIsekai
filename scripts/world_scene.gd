extends Node2D
class_name WorldScene

## 所有可游玩地图的通用基类。
## 地图只需按约定放置 Player；RV、FarBackground、Enemies 均为可选节点。

@export_group("Scene Nodes")
@export var player_path: NodePath = ^"Player"
@export var rv_sprite_path: NodePath = ^"RV"
@export var far_background_path: NodePath = ^"FarBackground"
@export var enemy_container_path: NodePath = ^"Enemies"

@export_group("RV")
@export var rv_indoor_texture: Texture2D = preload("res://assets/rv.png")
@export var rv_outdoor_texture: Texture2D = preload("res://assets/rv2.png")
@export var rv_indoor_sub_scene: String = "indoor"

@export_group("Parallax")
## 0 表示远景固定，1 表示远景完全跟随相机。
@export_range(0.0, 1.0, 0.01) var far_bg_parallax: float = 0.82

@export_group("Combat Feedback")
@export var damage_number_scene: PackedScene = preload("res://ui/damage_number.tscn")
@export var damage_number_offset: Vector2 = Vector2(0.0, -60.0)

var player: Player = null
var rv_sprite: Sprite2D = null
var far_background: Node2D = null
var camera: Camera2D = null

var _far_bg_base_position: Vector2
var _camera_base_x: float = 0.0
var _last_rv_sub_scene: String = ""


func _ready() -> void:
	_resolve_common_nodes()
	_initialize_common_visuals()

	# 有地图快照时完整恢复（包括“0 个敌人”的已清理状态）；首次进入才执行默认刷新。
	var restored := false if has_method("uses_zone_state") else SaveManager.restore_enemy_map(self)
	if not restored:
		_spawn_scene_entities()
		# 立即登记运行时状态，避免未保存时往返地图造成重复刷新。
		SaveManager.capture_enemy_map(self)
	_bind_existing_enemies()
	# _ready 时 SceneManager.scene_changed 尚未必完成，直接由当前路径解析 ID。
	var inventory_scene_id := SceneRegistry.find_scene_id_by_path(scene_file_path)
	InventoryManager.restore_scene_drops(inventory_scene_id)

	# 多态扩展点：子场景只覆写自己需要的部分。
	_trigger_scene_plot()
	_on_world_ready()


func _process(_delta: float) -> void:
	_update_parallax()
	_update_rv_texture_if_needed()


func _resolve_common_nodes() -> void:
	player = get_node_or_null(player_path) as Player
	rv_sprite = get_node_or_null(rv_sprite_path) as Sprite2D
	far_background = get_node_or_null(far_background_path) as Node2D
	if player:
		camera = player.get_node_or_null("Camera2D") as Camera2D
	else:
		push_warning("WorldScene 缺少 Player: %s" % scene_file_path)


func _initialize_common_visuals() -> void:
	if far_background:
		_far_bg_base_position = far_background.position
	if camera:
		_camera_base_x = camera.global_position.x
	_update_rv_texture_if_needed(true)


func _update_rv_texture_if_needed(force: bool = false) -> void:
	if not player or not rv_sprite:
		return
	if not force and _last_rv_sub_scene == player.current_sub_scene:
		return

	_last_rv_sub_scene = player.current_sub_scene
	if player.current_sub_scene == rv_indoor_sub_scene:
		if rv_indoor_texture:
			rv_sprite.texture = rv_indoor_texture
	elif rv_outdoor_texture:
		rv_sprite.texture = rv_outdoor_texture


## 兼容原 base.gd 和存档恢复逻辑使用的公开方法。
func update_rv_texture() -> void:
	_update_rv_texture_if_needed(true)


func _update_parallax() -> void:
	if not camera or not far_background:
		return
	var camera_offset_x: float = camera.global_position.x - _far_bg_base_position.x
	far_background.position.x = _far_bg_base_position.x + camera_offset_x * far_bg_parallax


## 通用敌人生成入口。敌人默认放入 Enemies 节点；没有该节点时放在场景根节点。
func spawn_enemy(enemy_scene: PackedScene, spawn_position: Vector2, parent: Node = null) -> Enemy:
	if not enemy_scene:
		push_error("spawn_enemy: 敌人场景为空")
		return null

	var instance := enemy_scene.instantiate()
	var enemy := instance as Enemy
	if not enemy:
		push_error("spawn_enemy: 场景根节点不是 Enemy")
		instance.free()
		return null

	var target_parent := parent
	if not target_parent and not enemy_container_path.is_empty():
		target_parent = get_node_or_null(enemy_container_path)
	if not target_parent:
		target_parent = self

	target_parent.add_child(enemy)
	# spawn_position 的公开约定是世界坐标，避免 Enemies 容器带变换时发生偏移。
	enemy.global_position = spawn_position
	_connect_enemy_feedback(enemy)
	return enemy


## 编辑器中直接放在 tscn 里的敌人也自动获得通用战斗反馈。
func _bind_existing_enemies() -> void:
	for node in find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if enemy:
			_connect_enemy_feedback(enemy)


func _connect_enemy_feedback(enemy: Enemy) -> void:
	var callback := _on_enemy_damage_taken.bind(enemy)
	if not enemy.damage_taken.is_connected(callback):
		enemy.damage_taken.connect(callback)


func _on_enemy_damage_taken(amount: int, enemy: Enemy) -> void:
	if not damage_number_scene or not is_instance_valid(enemy):
		return
	var instance := damage_number_scene.instantiate()
	var damage_number := instance as Node2D
	if not damage_number:
		push_error("伤害数字场景的根节点必须继承 Node2D")
		instance.free()
		return
	add_child(damage_number)
	if damage_number.has_method("show_damage"):
		damage_number.show_damage(amount, enemy.global_position + damage_number_offset)


# ---- 子场景多态钩子 ----

## 生成本地图独有的训练木桩、敌人、NPC 等。
func _spawn_scene_entities() -> void:
	pass


## 检查并触发本地图独有的剧情。
func _trigger_scene_plot() -> void:
	pass


## 其他需要在通用初始化完成后执行的场景逻辑。
func _on_world_ready() -> void:
	pass
