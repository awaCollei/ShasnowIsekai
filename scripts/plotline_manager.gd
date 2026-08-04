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

## 开始对话：显示聊天UI，禁用玩家控制
func chat_start() -> void:
	if _chat_ui and _chat_ui.visible:
		push_warning("PlotlineManager: chat_start() 被重复调用，已忽略")
		return
	_ensure_chat_ui()
	_disable_player_controls()
	_chat_ui.show_ui()

## 显示一句话，等待玩家确认后返回
## speaker: 说话者名称
## text: 对话文本
## illustrations: 立绘名称数组，0~2个元素
## direction: 立绘方向，可选 "left", "right", "face_to_face", "back_to_back"
##           单人时有效值为 "left"/"right"，默认为 "left"
##           双人时有效值为 "face_to_face"/"back_to_back"，默认为 "face_to_face"
func chat(speaker: String, text: String, illustrations: Array = [], direction: String = "auto") -> void:
	_ensure_chat_ui()
	
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
	
	# 双人时限制有效方向
	if illustrations.size() >= 2 and final_direction in ["left", "right"]:
		push_warning("PlotlineManager: 双人立绘不支持 '%s' 方向，已回退为 'face_to_face'" % final_direction)
		final_direction = "face_to_face"
	
	_chat_ui.set_speaker(speaker)
	_chat_ui.set_illustrations(illustrations, speaker)
	_chat_ui.set_illustration_direction(final_direction)
	_chat_ui.set_text(text)
	await _chat_ui.advance_confirmed


## 结束对话：关闭聊天UI，恢复玩家控制
func chat_end() -> void:
	if _chat_ui:
		_chat_ui.hide_ui()
	_restore_player_controls()


# ==========================
# 内部
# ==========================

func _ensure_chat_ui() -> void:
	if _chat_ui:
		return
	_chat_ui = _chat_ui_scene.instantiate()
	get_tree().root.add_child(_chat_ui)


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


func _get_player():
	# 从场景树中查找玩家节点
	var tree := get_tree()
	if not tree:
		return null

	# 尝试从当前场景组中查找
	var players := tree.get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]

	# 回退：查找 CharacterBody2D
	var root := tree.root
	for child in root.get_children():
		if child is CanvasLayer or child is Node and child == self:
			continue
		var found = _find_player_recursive(child)
		if found:
			return found
	return null


func _find_player_recursive(node: Node):
	if node is CharacterBody2D and node.has_method("teleport_to"):
		return node
	for child in node.get_children():
		var found = _find_player_recursive(child)
		if found:
			return found
	return null
