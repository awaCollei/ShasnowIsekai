extends Node

## 在不销毁世界场景的情况下叠加回合制战斗；这样可以保留敌人实例、玩家位置与剧情状态。
signal battle_started(player_first: bool, enemy_count: int)
signal battle_finished(victory: bool)

const BATTLE_SCENE: PackedScene = preload("res://combat/battle_scene.tscn")

@export var join_radius: float = 720.0
@export_range(1, 6, 1) var enemies_per_wave: int = 3

var is_in_battle := false
var _battle_scene: BattleScene
var _participants: Array[Node] = []
var _old_process_modes: Dictionary = {}
var _world_scene: Node = null
var _world_process_mode := Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	get_tree().scene_changed.connect(_on_world_scene_changed)


func begin_battle(player: Player, initiator: Enemy, player_first: bool) -> bool:
	if is_in_battle or not is_instance_valid(player) or not is_instance_valid(initiator):
		return false
	if player.is_dead or initiator.hp <= 0 or not initiator.battle_enabled:
		return false

	var enemies := _collect_nearby_enemies(player, initiator)
	if enemies.is_empty():
		return false

	# 将触发时的地图 ID 一并固定下来，避免 deferred 与切图交错时拿到目标地图背景。
	var active_scene := get_tree().current_scene
	var scene_id := SceneRegistry.find_scene_id_by_path(active_scene.scene_file_path) if active_scene else ""
	if scene_id.is_empty() and active_scene:
		scene_id = active_scene.scene_file_path.get_file().get_basename()

	# area_entered 和敌人命中帧都可能位于物理回调中。这里只同步占位防止重复触发，
	# 实际冻结 CollisionObject 和创建战斗场景统一延迟到安全帧执行。
	is_in_battle = true
	call_deferred("_start_battle_deferred", player, enemies, player_first, scene_id)
	return true


func _start_battle_deferred(player: Player, requested_enemies: Array[Enemy], player_first: bool, scene_id: String) -> void:
	var current_world := get_tree().current_scene
	if not is_in_battle or not is_instance_valid(player) or player.is_dead or not player.is_inside_tree():
		_cancel_pending_battle()
		return
	if not is_instance_valid(current_world) or not current_world.is_ancestor_of(player):
		_cancel_pending_battle()
		return

	var enemies: Array[Enemy] = []
	for enemy in requested_enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree() and current_world.is_ancestor_of(enemy) and enemy.hp > 0 and enemy.battle_enabled:
			enemies.append(enemy)
	if enemies.is_empty():
		_cancel_pending_battle()
		return

	# 防止局外吟唱留下的临时预扣在冻结玩家后阻塞技能消费。
	player.cancel_magic_chant()
	_participants.assign(enemies)
	_participants.append(player)
	_freeze_world_participants()

	_battle_scene = BATTLE_SCENE.instantiate() as BattleScene
	if not _battle_scene:
		_restore_world_participants()
		is_in_battle = false
		_participants.clear()
		push_error("回合制战斗场景根节点必须是 BattleScene")
		return
	get_tree().root.add_child(_battle_scene)
	_battle_scene.battle_resolved.connect(_on_battle_resolved)
	_battle_scene.tree_exited.connect(_on_battle_scene_exited.bind(_battle_scene))
	_battle_scene.setup(player, enemies, player_first, enemies_per_wave, scene_id)
	battle_started.emit(player_first, enemies.size())


func _cancel_pending_battle() -> void:
	is_in_battle = false
	_participants.clear()


func _collect_nearby_enemies(player: Player, initiator: Enemy) -> Array[Enemy]:
	var result: Array[Enemy] = [initiator]
	var active_scene := get_tree().current_scene
	if not active_scene:
		return result
	for node in active_scene.find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if not enemy or enemy == initiator or enemy.hp <= 0 or not enemy.battle_enabled:
			continue
		if enemy.global_position.distance_to(initiator.global_position) > join_radius:
			continue
		# 有 sub_scene 的敌人只和处于同一子区域的玩家一起参战。
		var enemy_sub_scene = enemy.get("sub_scene")
		if enemy_sub_scene != null and String(enemy_sub_scene) != player.current_sub_scene:
			continue
		result.append(enemy)
	# 近处敌人优先进入前一波，保证波次顺序稳定。
	result.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position)
	)
	return result


func _freeze_world_participants() -> void:
	# 冻结整个世界，避免参战半径外的 AI 在战斗菜单期间继续追击或造成伤害。
	_world_scene = get_tree().current_scene
	if is_instance_valid(_world_scene):
		_world_process_mode = _world_scene.process_mode
		_world_scene.process_mode = Node.PROCESS_MODE_DISABLED
	_old_process_modes.clear()
	for node in _participants:
		if is_instance_valid(node):
			_old_process_modes[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED


func _restore_world_participants() -> void:
	if is_instance_valid(_world_scene):
		_world_scene.process_mode = _world_process_mode
	_world_scene = null
	for node in _old_process_modes:
		if is_instance_valid(node):
			node.process_mode = int(_old_process_modes[node])
	_old_process_modes.clear()


func _on_battle_resolved(victory: bool, defeated_enemies: Array[Enemy]) -> void:
	_restore_world_participants()
	if victory:
		for enemy in defeated_enemies:
			if is_instance_valid(enemy):
				enemy.die()
	is_in_battle = false
	_battle_scene = null
	_participants.clear()
	battle_finished.emit(victory)
	if victory:
		# defeated_enemies 已结算为 0 HP，下一帧捕获地图时会正确记录已清理状态。
		SaveManager.request_auto_save("战斗胜利")


func _on_battle_scene_exited(scene: BattleScene) -> void:
	if scene != _battle_scene or not is_in_battle:
		return
	# 脚本异常或外部释放战斗场景时也必须解除世界冻结。
	_restore_world_participants()
	is_in_battle = false
	_battle_scene = null
	_participants.clear()


func _on_world_scene_changed() -> void:
	if not is_in_battle:
		return
	var old_battle := _battle_scene
	_restore_world_participants()
	is_in_battle = false
	_battle_scene = null
	_participants.clear()
	if is_instance_valid(old_battle):
		old_battle.queue_free()
