extends Area2D
class_name Portal

# 传送门属性
@export var portal_id: String = ""  # 传送门唯一标识
@export var target_portal_ids: Array[String] = []  # 目标传送门ID列表
@export var sub_scene: String = ""  # 所在子场景（留空表示所有子场景）

# 显示相关（可选）
@export var visible_texture: Texture2D  # 显示的纹理，如果为空则不显示
@export var portal_name: String = ""  # 传送门名称，用于交互显示

# 组件引用
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# 状态
var player_ref: Player = null

func _ready() -> void:
	# 设置显示
	if visible_texture and sprite:
		sprite.texture = visible_texture
		sprite.visible = true
	else:
		if sprite:
			sprite.visible = false
	
	# 添加到传送门组
	add_to_group("portals")
	
	# 连接信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_ref = body
		if can_interact():
			add_interaction_options()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_ref = null
		remove_interaction_options()

func can_interact() -> bool:
	if not player_ref:
		return false
	if sub_scene == "":
		return true
	return player_ref.current_sub_scene == sub_scene

func add_interaction_options() -> void:
	var interaction_system = find_interaction_system()
	if not interaction_system or not interaction_system.has_method("add_option"):
		return
	
	for tid in target_portal_ids:
		var target_portal = find_portal_by_id(tid)
		if not target_portal:
			continue
		var option_text = target_portal.portal_name if target_portal.portal_name else "传送到 " + tid
		var proxy = PortalTarget.new()
		proxy.portal_ref = self
		proxy.target_id = tid
		proxy.name = "PortalTarget_" + tid
		add_child(proxy)
		interaction_system.add_option("portal_" + portal_id + "_" + tid, option_text, proxy)

func remove_interaction_options() -> void:
	var interaction_system = find_interaction_system()
	if interaction_system and interaction_system.has_method("remove_option"):
		for tid in target_portal_ids:
			interaction_system.remove_option("portal_" + portal_id + "_" + tid)
	# 清理代理节点
	for child in get_children():
		if child is PortalTarget:
			child.queue_free()

func find_interaction_system() -> Node:
	var root = get_tree().root
	return find_interaction_system_node(root)

func find_interaction_system_node(node: Node) -> Node:
	if node is InteractionSystem:
		return node
	for child in node.get_children():
		var result = find_interaction_system_node(child)
		if result:
			return result
	return null

func find_portal_by_id(id: String) -> Portal:
	var portals = get_tree().get_nodes_in_group("portals")
	for portal in portals:
		if portal is Portal and portal.portal_id == id:
			return portal
	return null

func teleport_to_id(target_id: String) -> void:
	if not player_ref:
		return
	
	var target_portal = find_portal_by_id(target_id)
	if not target_portal:
		return
	
	# 先移除当前传送门的交互选项
	remove_interaction_options()
	
	# 改变玩家子场景为目标传送门所在的子场景
	player_ref.current_sub_scene = target_portal.sub_scene
	
	# 传送到目标位置
	player_ref.global_position = target_portal.global_position
	
	# 平滑移动镜头
	var camera = player_ref.get_node_or_null("Camera2D")
	if camera and camera.has_method("smooth_move_to"):
		camera.smooth_move_to(target_portal.global_position)
	
	# 手动触发目标传送门的交互检查
	target_portal.player_ref = player_ref
	if target_portal.can_interact():
		target_portal.add_interaction_options()
	
	print("玩家传送到: ", target_portal.portal_id)


# 传送门代理节点，用于区分不同的目标传送门选项
class PortalTarget extends Node:
	var portal_ref: Portal
	var target_id: String
	
	func interact() -> void:
		portal_ref.teleport_to_id(target_id)
