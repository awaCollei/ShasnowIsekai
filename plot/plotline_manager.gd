extends Node

## 剧情管理器 — Autoload 单例
## 提供 chat_start / chat / chat_end 等剧情演出方法。
## 剧情脚本放在 res://plotline/ 下，由 play_plot() 按需加载。

# ==========================
# 信号
# ==========================
signal plot_started
signal plot_ended

# ==========================
# 状态
# ==========================
var is_playing: bool = false    # 是否正在播放剧情
var _chat_ui = null              # ChatUI 实例
var _chat_ui_scene = preload("res://plot/chat_ui.tscn")
var _black_sui = null            # BlackScreen 实例
var _black_sui_scene = preload("res://plot/black_screen.tscn")

# 任务书
var quest_book: Dictionary = {}           # 从 script.json 加载的任务书
var _quest_completed: Dictionary = {}     # 已完成的任务 { quest_id: true }


func _ready() -> void:
	_load_quest_book()


# ==========================
# 剧情播放
# ==========================

## 加载并播放指定剧情脚本（如 "1_1"）
func play_plot(plot_id: String) -> void:
	if is_playing:
		push_warning("PlotlineManager: 已有剧情正在播放")
		return

	var path := "res://plotline/%s.gd" % plot_id
	if not ResourceLoader.exists(path):
		push_error("PlotlineManager: 找不到剧情脚本: " + path)
		return

	var plot_script = load(path).new()
	if not plot_script.has_method("play"):
		push_error("PlotlineManager: 剧情脚本缺少 play() 方法: " + path)
		return

	is_playing = true
	plot_started.emit()

	# 添加剧情脚本到场景树以便使用 await
	add_child(plot_script)
	await plot_script.play()
	plot_script.queue_free()

	# 确保清理
	if is_playing:
		chat_end()
	is_playing = false
	plot_ended.emit()


# ==========================
# 对话方法
# ==========================

## 开始对话：显示聊天UI
func chat_start() -> void:
	if _chat_ui and _chat_ui.visible:
		push_warning("PlotlineManager: chat_start() 被重复调用，已忽略")
		return
	_ensure_chat_ui()
	_chat_ui.show_ui()

## 显示一句话，等待玩家确认后返回
## speaker: 说话者名称
## text: 对话文本
## illustrations: 立绘名称数组，0~2个元素
## direction: 立绘方向，可选 "left", "right", "face_to_face", "back_to_back"
##           单人时有效值为 "left"/"right"，默认为 "left"
##           双人时有效值为 "face_to_face"/"back_to_back"，默认为 "face_to_face"
func chat(speaker: Variant, text: String, illustrations: Array = [], direction: String = "auto") -> void:
	_ensure_chat_ui()
	
	# 解析 speaker 参数
	var display_name: String
	var character_id: String
	
	if typeof(speaker) == TYPE_STRING:
		# 如果是字符串，显示名和角色ID都用它
		display_name = speaker
		character_id = speaker
	elif typeof(speaker) == TYPE_ARRAY and speaker.size() >= 2:
		# 如果是数组（元组），第一个是显示名，第二个是角色ID
		display_name = str(speaker[0])
		character_id = str(speaker[1])
	else:
		# 无效参数，报错并回退
		push_error("PlotlineManager: 无效的 speaker 参数类型: %s" % typeof(speaker))
		display_name = "Unknown"
		character_id = "unknown"
	
	# 自动选择方向
	var final_direction = direction
	if direction == "auto":
		if illustrations.size() >= 2:
			final_direction = "face_to_face"
		else:
			final_direction = "left"
	
	# 验证方向参数
	var valid_directions = ["left", "right", "face_to_face", "back_to_back"]
	if not final_direction in valid_directions:
		push_warning("PlotlineManager: 无效的方向参数 '%s'，已回退为 'left'" % final_direction)
		final_direction = "left"
	
	# 单人时限制有效方向
	if illustrations.size() < 2 and final_direction in ["face_to_face", "back_to_back"]:
		push_warning("PlotlineManager: 单人立绘不支持 '%s' 方向，已回退为 'left'" % final_direction)
		final_direction = "left"
	
	_chat_ui.set_speaker(display_name)
	_chat_ui.set_illustrations(illustrations, character_id)
	_chat_ui.set_illustration_direction(final_direction)
	_chat_ui.set_text(text)
	await _chat_ui.advance_confirmed


## 结束对话：关闭聊天UI
func chat_end() -> void:
	if _chat_ui:
		_chat_ui.hide_ui()


# ==========================
# 黑屏过渡方法
# ==========================

## 淡入黑屏，await 后表示过渡完成
func black_fade_in(duration: float = 0.5) -> void:
	_ensure_black_ui()
	await _black_sui.fade_in(duration)

## 淡出黑屏，await 后表示过渡完成
func black_fade_out(duration: float = 0.5) -> void:
	if _black_sui:
		await _black_sui.fade_out(duration)

## 在黑屏上显示居中文本，等待玩家确认后自动清除
func show_black_text(text: String) -> void:
	_ensure_black_ui()
	_black_sui.set_text(text)
	_black_sui.set_can_advance(true)
	await _black_sui.advance_confirmed
	_black_sui.clear_text()


# ==========================
# 任务进度
# ==========================

## 标记指定 ID 的任务为已完成
func mark_quest_completed(quest_id: String) -> void:
	_quest_completed[quest_id] = true


## 查询指定 ID 的任务是否已完成
func is_quest_completed(quest_id: String) -> bool:
	return _quest_completed.get(quest_id, false)


## 获取所有已完成任务的 ID 列表
func get_completed_quests() -> Array:
	var result: Array = []
	for key in _quest_completed:
		if _quest_completed[key]:
			result.append(key)
	return result


## 导出当前任务进度（供存档系统调用）
func get_quest_progress() -> Dictionary:
	return _quest_completed.duplicate()


## 导入任务进度（供存档系统调用）
func set_quest_progress(data: Dictionary) -> void:
	_quest_completed = data.duplicate()


## 重置所有任务进度
func reset_quest_progress() -> void:
	_quest_completed.clear()


## 根据章节 ID 获取该章节的任务列表（从 script.json 中读取）
func get_quests_in_chapter(chapter_id: String) -> Array:
	if not quest_book.has("chapters"):
		return []
	for chapter in quest_book["chapters"]:
		if str(chapter.get("id", "")) == chapter_id:
			return chapter.get("acts", [])
	return []


# ==========================
# 角色演出（地图角色，非立绘）
# ==========================

## 在地图上创建一个角色（剧情 NPC），返回 Character 实例
func create_character(character_id: String, position: Vector2) -> Character:
	var char := Character.new()
	char.name = "PlotChar_" + character_id

	# 创建必要的子节点
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	char.add_child(sprite)

	var anim := CharacterAnimation.new()
	anim.name = "CharacterAnimation"
	char.add_child(anim)

	# 添加到当前场景
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(char)

	# 初始化（必须在 add_child 之后，因为 @onready 依赖场景树）
	char.initialize(character_id)
	char.global_position = position
	return char


## 让角色移动到目标位置，await 完成后返回
## move_type: "walk" | "run" | "translate" | "teleport"
func character_move(character: Character, target: Vector2, move_type: String = "walk") -> void:
	if not is_instance_valid(character):
		push_error("PlotlineManager: 角色已失效，无法移动")
		return
	await character.move_to(target, move_type)


## 设置角色朝向（"left" / "right"）
func character_set_direction(character: Character, direction: String) -> void:
	if not is_instance_valid(character):
		push_error("PlotlineManager: 角色已失效，无法设置方向")
		return
	character.set_direction(direction)


## 销毁地图上的角色
func destroy_character(character: Character) -> void:
	if is_instance_valid(character):
		character.queue_free()


# ==========================
# 玩家操作锁定
# ==========================

## 锁定玩家操作（移动、攻击、菜单等）
func lock_player() -> void:
	_disable_player_controls()

## 解锁玩家操作
func unlock_player() -> void:
	_restore_player_controls()

# ==========================
# 内部
# ==========================

func _ensure_chat_ui() -> void:
	if _chat_ui:
		return
	_chat_ui = _chat_ui_scene.instantiate()
	get_tree().root.add_child(_chat_ui)


func _ensure_black_ui() -> void:
	if _black_sui:
		return
	_black_sui = _black_sui_scene.instantiate()
	get_tree().root.add_child(_black_sui)


func _disable_player_controls() -> void:
	# 禁用玩家移动、攻击、菜单
	var player = _get_player()
	if player:
		player.set_physics_process(false)
		player.set_process(false)

	# 禁止暂停菜单
	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_key_input(false)


func _restore_player_controls() -> void:
	var player = _get_player()
	if player:
		player.set_physics_process(true)
		player.set_process(true)

	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu and not pause_menu.is_open:
		pause_menu.set_process_unhandled_key_input(true)


func _load_quest_book() -> void:
	var file := FileAccess.open("res://plotline/script.json", FileAccess.READ)
	if file == null:
		push_error("PlotlineManager: 无法加载任务书 script.json")
		return
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("PlotlineManager: script.json 解析失败")
		return
	quest_book = json.data


func _get_player():
	# 从场景树中查找玩家节点
	var tree := get_tree()
	if not tree:
		return null

	# 尝试从当前场景组中查找
	var players := tree.get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]

	# 回退：递归查找 Player
	var root := tree.root
	for child in root.get_children():
		if child is CanvasLayer or child is Node and child == self:
			continue
		var found = _find_player_recursive(child)
		if found:
			return found
	return null


func _find_player_recursive(node: Node):
	if node is Player:
		return node
	for child in node.get_children():
		var found = _find_player_recursive(child)
		if found:
			return found
	return null
