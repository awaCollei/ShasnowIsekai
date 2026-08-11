extends CanvasLayer
class_name InteractionSystem

# 交互选项数据
var options: Array[Dictionary] = []
var selected_index: int = 0
var is_visible: bool = false

# UI 位置参数：间距只作用于角色外轮廓，不参与世界坐标换算。
@export var right_gap: float = 14.0
@export var debug_position: bool = false

# UI 组件引用
@onready var options_container: VBoxContainer = $VBoxContainer
@onready var option_scene: PackedScene = preload("res://ui/interaction_option.tscn")

# 输入处理
var input_cooldown: float = 0.0
const INPUT_COOLDOWN_TIME: float = 0.15

var player_ref: Player
var _last_debug_position := Vector2.ZERO
var _has_debug_position := false

func _ready() -> void:
	# 初始隐藏；玩家缓存后，后续只在失效时重新查找。
	options_container.visible = false
	player_ref = find_player_node(get_tree().root)
	set_process_input(true)

func _process(delta: float) -> void:
	if input_cooldown > 0.0:
		input_cooldown -= delta

	# CanvasLayer 下的 Control 使用视口坐标，位置需随玩家的画布坐标更新。
	if is_visible:
		update_position()

func _input(event: InputEvent) -> void:
	if not is_visible or options.is_empty() or input_cooldown > 0.0:
		return
	# 背包 / 箱子界面打开时拒绝交互输入，防止误操作（如挨着传送门时意外触发）。
	if _is_inventory_open():
		return

	# W/S（ui_up/ui_down）选择选项。
	if event.is_action_pressed("ui_up"):
		select_previous()
		input_cooldown = INPUT_COOLDOWN_TIME
	elif event.is_action_pressed("ui_down"):
		select_next()
		input_cooldown = INPUT_COOLDOWN_TIME
	elif event.is_action_pressed("interact"):
		execute_selected()

func _is_inventory_open() -> bool:
	var inventory_ui := get_node_or_null("/root/InventoryUI")
	return inventory_ui != null and inventory_ui.visible

func add_option(id: String, text: String, target: Node) -> void:
	for option in options:
		if option.id == id:
			return

	options.append({
		"id": id,
		"text": text,
		"target": target
	})
	update_ui()

	if options.size() == 1:
		show_ui()
	else:
		update_selection()

func remove_option(id: String) -> void:
	var removed_index := -1
	for i in range(options.size() - 1, -1, -1):
		if options[i].id == id:
			removed_index = i
			options.remove_at(i)
			break

	if removed_index == -1:
		return

	if options.is_empty():
		hide_ui()
		update_ui()
		return

	# 删除当前选项之前的项时，保持原来指向的选项不变。
	if removed_index < selected_index:
		selected_index -= 1
	selected_index = clampi(selected_index, 0, options.size() - 1)
	update_ui()
	update_selection()

func show_ui() -> void:
	is_visible = true
	options_container.visible = true
	selected_index = 0
	update_selection()
	update_position()

func hide_ui() -> void:
	is_visible = false
	options_container.visible = false

func update_ui() -> void:
	# 先移出旧节点，避免 queue_free 延迟期间影响新选项的索引。
	for child in options_container.get_children():
		options_container.remove_child(child)
		child.queue_free()

	for i in range(options.size()):
		var option_ui := option_scene.instantiate() as InteractionOption
		options_container.add_child(option_ui)
		option_ui.set_text(options[i].text)
		option_ui.set_index(i)
		option_ui.selected.connect(_on_option_selected)

	if is_visible:
		update_selection()

func update_selection() -> void:
	for i in range(options_container.get_child_count()):
		var option_ui := options_container.get_child(i) as InteractionOption
		if option_ui:
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

	var target: Node = options[selected_index].target
	if target and target.has_method("interact"):
		target.interact()

func _on_option_selected(index: int) -> void:
	selected_index = index
	execute_selected()

func update_position() -> void:
	if not is_instance_valid(player_ref):
		player_ref = find_player_node(get_tree().root)
	if not player_ref:
		return

	# get_screen_transform() 是视口到窗口的变换，不是世界坐标到 CanvasLayer 的变换。
	# 玩家自身的 get_global_transform_with_canvas() 才能正确包含 Camera2D 的画布变换。
	var player_canvas_position := player_ref.get_global_transform_with_canvas().origin
	var player_bounds := _get_player_canvas_bounds(player_ref)
	var list_height: float = max(options_container.size.y, options_container.get_combined_minimum_size().y)
	var right_edge := player_bounds.end.x if player_bounds.size.x > 0.0 else player_canvas_position.x
	var vertical_center := player_bounds.get_center().y if player_bounds.size.y > 0.0 else player_canvas_position.y

	options_container.position = Vector2(
		right_edge + right_gap,
		vertical_center - list_height * 0.5
	)

	# 可选的低频定位日志，方便检查相机或分辨率变化下的坐标链路。
	if debug_position and (not _has_debug_position or _last_debug_position.distance_to(options_container.position) > 8.0):
		print("[InteractionSystem] player canvas=", player_canvas_position,
			" bounds=", player_bounds, " ui=", options_container.position)
		_last_debug_position = options_container.position
		_has_debug_position = true

func _get_player_canvas_bounds(player: Player) -> Rect2:
	var player_sprite := player.get_node_or_null("Sprite2D") as Sprite2D
	if player_sprite and player_sprite.texture:
		return _transform_rect(player_sprite.get_global_transform_with_canvas(), player_sprite.get_rect())

	# 没有 Sprite2D 时退回玩家原点，不影响正常场景的定位逻辑。
	return Rect2(player.get_global_transform_with_canvas().origin, Vector2.ZERO)

func _transform_rect(transform: Transform2D, rect: Rect2) -> Rect2:
	var corners: Array[Vector2] = [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y)
	]
	var bounds := Rect2(transform * corners[0], Vector2.ZERO)
	for corner in corners:
		bounds = bounds.expand(transform * corner)
	return bounds

func find_player_node(node: Node) -> Player:
	if node is Player:
		return node

	for child in node.get_children():
		var result := find_player_node(child)
		if result:
			return result
	return null
