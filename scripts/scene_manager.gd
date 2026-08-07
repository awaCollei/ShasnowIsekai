extends Node

signal scene_change_started(scene_id: String)
signal scene_changed(scene_id: String)

const MAP_SCREEN_SCENE: PackedScene = preload("res://ui/map_screen.tscn")

# 保留旧代码可能使用的实例引用；Autoload 名称本身不能作为类型标注。
static var instance

# 注册表中的当前场景 ID
var current_scene: String = "base"
var _map_screen: CanvasLayer = null


func _ready() -> void:
	instance = self
	get_tree().scene_changed.connect(_on_tree_scene_changed)
	call_deferred("_sync_current_scene")


func get_current_scene() -> String:
	return current_scene


# 保留旧接口；仅更新场景信息，不重置正在游玩的 sub_scene。
func set_scene_info(scene_id: String) -> void:
	if not SceneRegistry.has_scene(scene_id):
		return
	current_scene = scene_id
	var active_scene := get_tree().current_scene
	if not active_scene:
		return
	for node in active_scene.find_children("*", "Player", true, false):
		var player := node as Player
		if player:
			player.set_scene_info(scene_id)


func change_to_scene(scene_id: String, zone_id: String = "") -> bool:
	if not SceneRegistry.has_scene(scene_id):
		push_error("未注册的场景 ID: %s" % scene_id)
		return false

	var info := SceneRegistry.get_scene_info(scene_id)
	if not zone_id.is_empty():
		SaveManager.current_zone_id = zone_id
	var scene_path: String = info.get("scene_path", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("场景资源不存在: %s" % scene_path)
		return false

	# 当前地图离开前先把敌人位置、HP 和空地图状态写入运行时快照。
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.capture_current_enemy_map()

	var previous_scene := current_scene
	var was_paused := get_tree().paused
	current_scene = scene_id
	scene_change_started.emit(scene_id)
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		current_scene = previous_scene
		get_tree().paused = was_paused
		push_error("切换场景失败: %s（错误码 %d）" % [scene_path, error])
		return false

	if save_manager:
		save_manager.current_scene_path = scene_path
		save_manager.is_in_game = true
	return true


func open_map() -> void:
	if is_instance_valid(_map_screen):
		return
	_map_screen = MAP_SCREEN_SCENE.instantiate() as CanvasLayer
	get_tree().root.add_child(_map_screen)
	_map_screen.tree_exited.connect(_on_map_closed)


func _on_map_closed() -> void:
	_map_screen = null


func _on_tree_scene_changed() -> void:
	if not _sync_current_scene():
		return
	_apply_scene_defaults()
	scene_changed.emit(current_scene)
	# 新场景及其 WorldScene._ready() 已完成，再由 SaveManager 延后一帧写入自动存档。
	SaveManager.request_auto_save("切换场景：%s" % current_scene)


func _sync_current_scene() -> bool:
	var active_scene := get_tree().current_scene
	if not active_scene:
		current_scene = ""
		return false
	var scene_id := SceneRegistry.find_scene_id_by_path(active_scene.scene_file_path)
	if scene_id.is_empty():
		current_scene = ""
		return false
	current_scene = scene_id
	return true


func _apply_scene_defaults() -> void:
	var active_scene := get_tree().current_scene
	if not active_scene or not SceneRegistry.has_scene(current_scene):
		return

	var info := SceneRegistry.get_scene_info(current_scene)
	var default_sub_scene: String = info.get("default_sub_scene", "")
	for node in active_scene.find_children("*", "Player", true, false):
		var player := node as Player
		if not player:
			continue
		player.set_scene_info(current_scene)
		if not default_sub_scene.is_empty():
			player.current_sub_scene = default_sub_scene
