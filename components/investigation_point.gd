extends Area2D
class_name InvestigationPoint

# 调查点属性
@export var investigation_id: String = ""  # 调查点唯一标识
@export var message: String = ""  # 调查时显示的消息
@export var sub_scene: String = ""  # 所在子场景（留空表示所有子场景）
@export var investigation_name: String = ""  # 调查点名称，用于交互显示
@export var cooldown_time: float = 2.0  # 调查冷却时间（秒）

# 组件引用
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D

# 状态
var player_ref: Player = null
var _last_interact_time: float = 0.0  # 上次调查时间


func _ready() -> void:
	# 设置显示
	if sprite:
		sprite.visible = true

	# 连接信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_ref = body
		if can_interact():
			add_interaction_option()


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_ref = null
		remove_interaction_option()


func can_interact() -> bool:
	if not player_ref:
		return false
	if sub_scene == "":
		return true
	return player_ref.current_sub_scene == sub_scene


func add_interaction_option() -> void:
	var interaction_system = find_interaction_system()
	if interaction_system and interaction_system.has_method("add_option"):
		var option_text = investigation_name if investigation_name else "调查"
		interaction_system.add_option("investigation_" + investigation_id, option_text, self)


func remove_interaction_option() -> void:
	var interaction_system = find_interaction_system()
	if interaction_system and interaction_system.has_method("remove_option"):
		interaction_system.remove_option("investigation_" + investigation_id)


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


func interact() -> void:
	if message == "":
		return
	
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_interact_time < cooldown_time:
		return
	_last_interact_time = now
	
	MessageDisplayManager.show_info_message(message)
