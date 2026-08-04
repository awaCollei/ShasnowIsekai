extends Node

# 存档槽位数量
const MAX_SLOTS: int = 5

# 存档文件路径前缀
const SAVE_PATH_PREFIX: String = "user://save_slot_"

# 存档数据结构
class SaveData:
	var slot: int
	var scene_path: String          # 当前场景路径
	var player_position: Vector2     # 玩家位置
	var player_sub_scene: String     # 玩家子场景
	var timestamp: String            # 保存时间
	var quest_progress: Dictionary = {}  # 任务进度
	var has_data: bool = false

# 当前是否在游戏中（非主菜单）
var is_in_game: bool = false

# 当前使用的存档槽位
var current_slot: int = -1

# 当前场景路径（由场景切换时更新）
var current_scene_path: String = ""


func _ready() -> void:
	pass


# 保存游戏到指定槽位
func save_game(slot: int) -> bool:
	var data := _collect_save_data(slot)
	if data == null:
		return false

	var config := ConfigFile.new()
	config.set_value("save", "scene_path", data.scene_path)
	config.set_value("save", "player_position_x", data.player_position.x)
	config.set_value("save", "player_position_y", data.player_position.y)
	config.set_value("save", "player_sub_scene", data.player_sub_scene)
	config.set_value("save", "timestamp", data.timestamp)

	# 保存任务进度
	for quest_id in data.quest_progress:
		if data.quest_progress[quest_id]:
			config.set_value("quests", quest_id, true)

	var err := config.save(_get_slot_path(slot))
	if err != OK:
		push_error("保存失败: 槽位 %d, 错误码 %d" % [slot, err])
		return false

	current_slot = slot
	current_scene_path = data.scene_path
	return true


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
	data.timestamp = config.get_value("save", "timestamp", "")
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

	current_slot = slot
	current_scene_path = info.scene_path

	# 关闭暂停菜单
	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.is_open:
		pause_menu.close()

	# 切换场景
	var err := get_tree().change_scene_to_file(info.scene_path)
	if err != OK:
		push_error("无法加载场景: %s" % info.scene_path)
		return

	is_in_game = true

	# 等待场景加载完成后恢复玩家位置
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_player(info)
	_restore_quest_progress(info)


# 开始新游戏
func start_new_game() -> void:
	current_slot = -1
	current_scene_path = "res://base/base.tscn"

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
	is_in_game = false
	current_slot = -1
	current_scene_path = ""

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
	for i in range(1, MAX_SLOTS + 1):
		if dir.file_exists(_get_slot_path(i)):
			return true
	return false


# ---- 内部方法 ----

func _get_slot_path(slot: int) -> String:
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
	else:
		data.player_position = Vector2.ZERO
		data.player_sub_scene = "outdoor"

	# 时间戳
	var dt := Time.get_datetime_dict_from_system()
	data.timestamp = "%d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]

	# 收集任务进度
	var plot_mgr = get_node_or_null("/root/PlotlineManager")
	if plot_mgr:
		data.quest_progress = plot_mgr.get_quest_progress()

	return data


func _find_player() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null

	# 递归查找 CharacterBody2D 类型的玩家
	var players := scene.find_children("*", "CharacterBody2D", true, false)
	for p in players:
		if p.has_method("set_scene_info"):
			return p
	return null


func _restore_player(info: SaveData) -> void:
	var player := _find_player()
	if player:
		player.global_position = info.player_position
		if player.get("current_sub_scene") != null:
			player.current_sub_scene = info.player_sub_scene
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
