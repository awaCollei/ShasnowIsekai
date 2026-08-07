extends Node

# 手动存档槽位数量；自动存档使用独立的 0 号虚拟槽位和文件。
const MAX_SLOTS: int = 5
const AUTO_SAVE_SLOT: int = 0
const AUTO_SAVE_PATH: String = "user://autosave.cfg"

# 存档文件路径前缀
const SAVE_PATH_PREFIX: String = "user://save_slot_"

signal auto_save_completed(success: bool, reason: String)

# 存档数据结构
class SaveData:
	var slot: int
	var scene_path: String          # 当前场景路径
	var player_position: Vector2     # 玩家位置
	var player_sub_scene: String     # 玩家子场景
	var player_hp: float = -1.0      # -1 表示旧存档中不存在该字段
	var player_max_hp: float = -1.0
	var player_mp: float = -1.0
	var player_max_mp: float = -1.0
	var timestamp: String            # 保存时间
	var quest_progress: Dictionary = {}  # 任务进度
	## key 为地图场景路径；即使 enemies 为空也代表该地图已初始化/已清理。
	var enemy_maps: Dictionary = {}
	var has_data: bool = false

# 当前是否在游戏中（非主菜单）
var is_in_game: bool = false

# 当前使用的存档槽位
var current_slot: int = -1

# 当前场景路径（由场景切换时更新）
var current_scene_path: String = ""

## 当前游戏会话的地图敌人快照。切图时先写入这里，正式保存时整体持久化。
var runtime_enemy_maps: Dictionary = {}
var is_loading_game := false
var _auto_save_pending := false


func _ready() -> void:
	pass


# 保存游戏到指定槽位
func save_game(slot: int) -> bool:
	capture_current_enemy_map()
	var data := _collect_save_data(slot)
	if data == null:
		return false

	var config := ConfigFile.new()
	config.set_value("save", "scene_path", data.scene_path)
	config.set_value("save", "player_position_x", data.player_position.x)
	config.set_value("save", "player_position_y", data.player_position.y)
	config.set_value("save", "player_sub_scene", data.player_sub_scene)
	config.set_value("player_status", "hp", data.player_hp)
	config.set_value("player_status", "max_hp", data.player_max_hp)
	config.set_value("player_status", "mp", data.player_mp)
	config.set_value("player_status", "max_mp", data.player_max_mp)
	config.set_value("save", "timestamp", data.timestamp)
	# 整体保存可保留此前访问过的其他地图；空 enemies 数组也是有效状态。
	config.set_value("enemy_maps", "states", data.enemy_maps)

	# 保存任务进度
	for quest_id in data.quest_progress:
		if data.quest_progress[quest_id]:
			config.set_value("quests", quest_id, true)

	var err := config.save(_get_slot_path(slot))
	if err != OK:
		push_error("保存失败: 槽位 %d, 错误码 %d" % [slot, err])
		return false

	# 自动存档不改变玩家当前选择的手动槽位。
	if slot != AUTO_SAVE_SLOT:
		current_slot = slot
	current_scene_path = data.scene_path
	return true


## 请求在当前帧的场景/战斗清理全部完成后自动保存。连续请求会合并为一次。
func request_auto_save(reason: String = "") -> void:
	if not is_in_game or is_loading_game or _auto_save_pending:
		return
	_auto_save_pending = true
	call_deferred("_perform_auto_save", reason)


func _perform_auto_save(reason: String) -> void:
	# 再等一帧，确保 scene_changed 后的玩家、敌人和默认子场景均已初始化。
	await get_tree().process_frame
	_auto_save_pending = false
	if not is_in_game or is_loading_game or not (get_tree().current_scene is WorldScene):
		auto_save_completed.emit(false, reason)
		return
	var success := save_game(AUTO_SAVE_SLOT)
	auto_save_completed.emit(success, reason)
	if success:
		print("自动保存完成：%s" % reason)


func get_auto_save_info() -> SaveData:
	return load_save_info(AUTO_SAVE_SLOT)


## 读取页面使用：自动存档固定在第一项，后面是 1–5 号手动槽位。
func get_all_load_save_infos() -> Array[SaveData]:
	var result: Array[SaveData] = [get_auto_save_info()]
	result.append_array(get_all_save_infos())
	return result


# 从指定槽位加载存档信息
func load_save_info(slot: int) -> SaveData:
	var config := ConfigFile.new()
	var err := config.load(_get_slot_path(slot))

	var data := SaveData.new()
	data.slot = slot

	if err != OK:
		data.has_data = false
		return data

	data.scene_path = config.get_value("save", "scene_path", "")
	data.player_position = Vector2(
		config.get_value("save", "player_position_x", 0.0),
		config.get_value("save", "player_position_y", 0.0)
	)
	data.player_sub_scene = config.get_value("save", "player_sub_scene", "outdoor")
	# 使用 -1 保持旧存档兼容：旧存档读档时由 Player 使用场景默认满状态。
	data.player_hp = float(config.get_value("player_status", "hp", -1.0))
	data.player_max_hp = float(config.get_value("player_status", "max_hp", -1.0))
	data.player_mp = float(config.get_value("player_status", "mp", -1.0))
	data.player_max_mp = float(config.get_value("player_status", "max_mp", -1.0))
	data.timestamp = config.get_value("save", "timestamp", "")
	var saved_enemy_maps = config.get_value("enemy_maps", "states", {})
	data.enemy_maps = saved_enemy_maps.duplicate(true) if saved_enemy_maps is Dictionary else {}
	data.has_data = true

	# 读取任务进度
	var quest_keys := config.get_section_keys("quests")
	if quest_keys != null:
		for key in quest_keys:
			data.quest_progress[key] = config.get_value("quests", key)

	return data


# 加载游戏（切换到存档中的场景）
func load_game(slot: int) -> void:
	var info := load_save_info(slot)
	if not info.has_data:
		push_error("槽位 %d 没有存档数据" % slot)
		return

	current_slot = slot if slot != AUTO_SAVE_SLOT else -1
	current_scene_path = info.scene_path
	runtime_enemy_maps = info.enemy_maps.duplicate(true)
	is_loading_game = true

	# 关闭暂停菜单
	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.is_open:
		pause_menu.close()

	_restore_quest_progress(info)
	# 切换场景
	var err := get_tree().change_scene_to_file(info.scene_path)
	if err != OK:
		is_loading_game = false
		push_error("无法加载场景: %s" % info.scene_path)
		return

	is_in_game = true

	# 等待场景加载完成后恢复玩家位置
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_player(info)
	is_loading_game = false


# 开始新游戏
func start_new_game() -> void:
	is_loading_game = false
	current_slot = -1
	current_scene_path = "res://scenes/base.tscn"
	runtime_enemy_maps.clear()

	# 重置任务进度
	_reset_quest_progress()

	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.is_open:
		pause_menu.close()

	get_tree().paused = false
	get_tree().change_scene_to_file(current_scene_path)
	is_in_game = true


# 返回主菜单
func return_to_main_menu() -> void:
	is_loading_game = false
	_auto_save_pending = false
	is_in_game = false
	current_slot = -1
	current_scene_path = ""
	runtime_enemy_maps.clear()

	# 先关闭暂停菜单
	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.is_open:
		pause_menu.close()

	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


# 删除存档
func delete_save(slot: int) -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false

	var path := _get_slot_path(slot)
	if dir.file_exists(path):
		var err := dir.remove(path)
		if err != OK:
			return false

	if current_slot == slot:
		current_slot = -1
	return true


# 获取所有槽位的存档信息
func get_all_save_infos() -> Array[SaveData]:
	var result: Array[SaveData] = []
	for i in range(1, MAX_SLOTS + 1):
		result.append(load_save_info(i))
	return result


# 检查是否已有存档
func has_any_save() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(AUTO_SAVE_PATH):
		return true
	for i in range(1, MAX_SLOTS + 1):
		if dir.file_exists(_get_slot_path(i)):
			return true
	return false


# ==========================
# 地图敌人快照
# ==========================

## 在离开地图和保存游戏前调用。记录空列表同样表示地图已经清理。
func capture_current_enemy_map() -> void:
	var scene := get_tree().current_scene
	if scene is WorldScene:
		capture_enemy_map(scene as WorldScene)


func capture_enemy_map(world: WorldScene) -> void:
	if not is_instance_valid(world) or world.scene_file_path.is_empty():
		return
	var enemies: Array[Dictionary] = []
	for node in world.find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if not enemy or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var packed_scene_path := enemy.scene_file_path
		if packed_scene_path.is_empty():
			push_warning("无法保存没有 scene_file_path 的敌人: %s" % enemy.name)
			continue
		var state := {
			"scene_path": packed_scene_path,
			"position": enemy.global_position,
			"hp": enemy.hp,
			"max_hp": enemy.max_hp,
		}
		var sub_scene_value = enemy.get("sub_scene")
		if sub_scene_value != null:
			state["sub_scene"] = String(sub_scene_value)
		enemies.append(state)
	runtime_enemy_maps[world.scene_file_path] = {
		"initialized": true,
		"enemies": enemies,
	}


## 返回 true 表示存在该地图记录；即使 enemies 为空，也不会调用地图默认刷新逻辑。
func restore_enemy_map(world: WorldScene) -> bool:
	if not is_instance_valid(world):
		return false
	var map_path := world.scene_file_path
	if map_path.is_empty() or not runtime_enemy_maps.has(map_path):
		return false
	var map_state = runtime_enemy_maps[map_path]
	if not map_state is Dictionary or not bool(map_state.get("initialized", false)):
		return false

	# 存档快照是完整列表，先移除 tscn 中可能预放置的敌人，避免重复。
	for node in world.find_children("*", "Enemy", true, false):
		var existing := node as Enemy
		if existing:
			existing.get_parent().remove_child(existing)
			existing.free()

	var saved_enemies = map_state.get("enemies", [])
	if not saved_enemies is Array:
		push_warning("地图敌人数据格式无效，将按已清理状态恢复: %s" % map_path)
		return true
	for raw_state in saved_enemies:
		if not raw_state is Dictionary:
			continue
		var enemy_scene_path := String(raw_state.get("scene_path", ""))
		if enemy_scene_path.is_empty() or not ResourceLoader.exists(enemy_scene_path):
			push_warning("存档中的敌人场景不存在: %s" % enemy_scene_path)
			continue
		var packed := load(enemy_scene_path) as PackedScene
		if not packed:
			continue
		var enemy := world.spawn_enemy(packed, Vector2.ZERO)
		if not enemy:
			continue
		enemy.global_position = raw_state.get("position", Vector2.ZERO)
		enemy.max_hp = maxi(1, int(raw_state.get("max_hp", enemy.max_hp)))
		enemy.hp = clampi(int(raw_state.get("hp", enemy.max_hp)), 1, enemy.max_hp)
		if raw_state.has("sub_scene") and enemy.get("sub_scene") != null:
			enemy.set("sub_scene", String(raw_state["sub_scene"]))
	return true


## 删除指定地图的敌人快照；下次进入该地图时会重新执行默认刷新。
## scene_id_or_path 可传 SceneRegistry ID（如 city1）或 res:// 场景路径。
func refresh_enemy_map(scene_id_or_path: String, slot: int = -1) -> bool:
	var map_path := scene_id_or_path
	if SceneRegistry.has_scene(scene_id_or_path):
		map_path = String(SceneRegistry.get_scene_info(scene_id_or_path).get("scene_path", ""))
	if map_path.is_empty():
		return false
	runtime_enemy_maps.erase(map_path)

	var target_slot := current_slot if slot < 0 else slot
	if target_slot < 1:
		return true
	var config := ConfigFile.new()
	var error := config.load(_get_slot_path(target_slot))
	if error != OK:
		return false
	var saved_states = config.get_value("enemy_maps", "states", {})
	if saved_states is Dictionary:
		saved_states.erase(map_path)
		config.set_value("enemy_maps", "states", saved_states)
	return config.save(_get_slot_path(target_slot)) == OK


# ---- 内部方法 ----

func _get_slot_path(slot: int) -> String:
	if slot == AUTO_SAVE_SLOT:
		return AUTO_SAVE_PATH
	return SAVE_PATH_PREFIX + str(slot) + ".cfg"


func _collect_save_data(slot: int) -> SaveData:
	var data := SaveData.new()
	data.slot = slot

	# 获取当前场景路径
	var scene := get_tree().current_scene
	if scene == null:
		push_error("无法获取当前场景")
		return null
	data.scene_path = scene.scene_file_path

	# 获取玩家位置
	var player := _find_player()
	if player:
		data.player_position = player.global_position
		data.player_sub_scene = player.get("current_sub_scene") if player.get("current_sub_scene") != null else "outdoor"
		var typed_player := player as Player
		if typed_player:
			# 保存实际 MP，而不是吟唱期间的可视 MP；临时预扣不进入存档。
			data.player_hp = typed_player.hp
			data.player_max_hp = typed_player.max_hp
			data.player_mp = typed_player.mp
			data.player_max_mp = typed_player.max_mp
	else:
		data.player_position = Vector2.ZERO
		data.player_sub_scene = "outdoor"

	# 时间戳
	var dt := Time.get_datetime_dict_from_system()
	data.timestamp = "%d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]
	data.enemy_maps = runtime_enemy_maps.duplicate(true)

	# 收集任务进度
	var plot_mgr = get_node_or_null("/root/PlotlineManager")
	if plot_mgr:
		data.quest_progress = plot_mgr.get_quest_progress()

	return data


func _find_player() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null

	# 递归查找 Player 类型的玩家
	var players := scene.find_children("*", "Player", true, false)
	for p in players:
		if p.has_method("set_scene_info"):
			return p
	return null


func _restore_player(info: SaveData) -> void:
	var player := _find_player()
	if player:
		player.global_position = info.player_position
		# 镜头立即就位，跳过传送平滑过渡
		var camera := player.get_node_or_null("Camera2D") as PlayerCamera
		if camera:
			camera.snap_to(info.player_position)
		if player.get("current_sub_scene") != null:
			player.current_sub_scene = info.player_sub_scene
		var typed_player := player as Player
		if typed_player and (info.player_hp >= 0.0 or info.player_mp >= 0.0):
			typed_player.restore_status(info.player_hp, info.player_max_hp, info.player_mp, info.player_max_mp)
		# 通知 base 更新纹理
		var base := get_tree().current_scene
		if base and base.has_method("update_rv_texture"):
			base.update_rv_texture()


func _restore_quest_progress(info: SaveData) -> void:
	var plot_mgr = get_node_or_null("/root/PlotlineManager")
	if plot_mgr:
		plot_mgr.set_quest_progress(info.quest_progress)


func _reset_quest_progress() -> void:
	var plot_mgr = get_node_or_null("/root/PlotlineManager")
	if plot_mgr:
		plot_mgr.reset_quest_progress()
