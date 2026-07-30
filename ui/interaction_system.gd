extends CanvasLayer
class_name InteractionSystem

# 交互选项数据
var options: Array[Dictionary] = []
var selected_index: int = 0
var is_visible: bool = false

# UI组件引用
@onready var options_container: VBoxContainer = $VBoxContainer
@onready var option_label_scene: PackedScene = preload("res://ui/interaction_option.tscn")

# 输入处理
var input_cooldown: float = 0.0
const INPUT_COOLDOWN_TIME: float = 0.15

func _ready() -> void:
	# 初始隐藏
	options_container.visible = false
	# 连接信号
	set_process_input(true)

func _process(delta: float) -> void:
	# 更新输入冷却
	if input_cooldown > 0:
		input_cooldown -= delta
	
	# 更新UI位置（跟随玩家）
	update_position()

func _input(event: InputEvent) -> void:
	if not is_visible or options.is_empty():
		return
	
	if input_cooldown > 0:
		return
	
	# W/S键选择
	if event.is_action_pressed("ui_up"):
		select_previous()
		input_cooldown = INPUT_COOLDOWN_TIME
	elif event.is_action_pressed("ui_down"):
		select_next()
		input_cooldown = INPUT_COOLDOWN_TIME
	# 交互键
	elif event.is_action_pressed("interact"):
		execute_selected()

func add_option(id: String, text: String, target: Node) -> void:
	# 检查是否已存在
	for option in options:
		if option.id == id:
			return
	
	# 添加新选项
	options.append({
		"id": id,
		"text": text,
		"target": target
	})
	
	# 更新UI
	update_ui()
	
	# 如果这是第一个选项，自动显示
	if options.size() == 1:
		show_ui()

func remove_option(id: String) -> void:
	# 查找并移除选项
	for i in range(options.size() - 1, -1, -1):
		if options[i].id == id:
			options.remove_at(i)
	
	# 更新UI
	update_ui()
	
	# 如果没有选项了，隐藏UI
	if options.is_empty():
		hide_ui()
	else:
		# 调整选中索引
		if selected_index >= options.size():
			selected_index = options.size() - 1
		update_selection()

func show_ui() -> void:
	is_visible = true
	options_container.visible = true
	selected_index = 0
	update_selection()

func hide_ui() -> void:
	is_visible = false
	options_container.visible = false

func update_ui() -> void:
	# 清空现有选项
	for child in options_container.get_children():
		child.queue_free()
	
	# 创建新选项
	for i in range(options.size()):
		var option = options[i]
		var option_ui = option_label_scene.instantiate()
		options_container.add_child(option_ui)
		option_ui.set_text(option.text)
		option_ui.set_index(i)
		option_ui.selected.connect(_on_option_selected)

func update_selection() -> void:
	# 更新所有选项的选中状态
	for i in range(options_container.get_child_count()):
		var option_ui = options_container.get_child(i)
		option_ui.set_selected(i == selected_index)

func select_next() -> void:
	if options.is_empty():
		return
	
	selected_index = (selected_index + 1) % options.size()
	update_selection()

func select_previous() -> void:
	if options.is_empty():
		return
	
	selected_index = (selected_index - 1 + options.size()) % options.size()
	update_selection()

func execute_selected() -> void:
	if options.is_empty() or selected_index >= options.size():
		return
	
	var option = options[selected_index]
	var target = option.target
	
	# 执行目标节点的interact方法
	if target and target.has_method("interact"):
		target.interact()

func _on_option_selected(index: int) -> void:
	selected_index = index
	execute_selected()

func update_position() -> void:
	# 获取玩家位置
	var player = find_player_node(get_tree().root)
	if player:
		# 将玩家世界坐标转换为屏幕坐标，显示在玩家左上方
		options_container.position = get_viewport().get_screen_transform() * player.global_position + Vector2(0, 0)

func find_player_node(node: Node) -> CharacterBody2D:
	# 检查当前节点是否是玩家
	if node is CharacterBody2D and node.has_method("set_scene_info"):
		return node
	
	# 递归查找子节点
	for child in node.get_children():
		var result = find_player_node(child)
		if result:
			return result
	
	return null