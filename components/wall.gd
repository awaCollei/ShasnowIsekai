extends StaticBody2D
class_name Wall

# 墙壁属性
@export var sub_scene: String = ""  # 所在子场景（留空表示所有子场景都阻挡）
@export var visible_texture: Texture2D  # 显示的纹理（可选）
@export var wall_color: Color = Color.WHITE  # 颜色

# 组件引用
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# 设置显示
	if visible_texture and sprite:
		sprite.texture = visible_texture
		sprite.visible = true
		sprite.modulate = wall_color
	else:
		if sprite:
			sprite.visible = false
	
	# 添加到墙壁组
	add_to_group("walls")

func _process(_delta: float) -> void:
	# 根据玩家的sub_scene决定是否激活
	var player = find_player_node()
	if player:
		var should_active = (sub_scene == "" or player.current_sub_scene == sub_scene)
		if collision_shape:
			collision_shape.disabled = not should_active
		if sprite:
			sprite.visible = should_active

func find_player_node() -> CharacterBody2D:
	var root = get_tree().root
	return find_player_node_recursive(root)

func find_player_node_recursive(node: Node) -> CharacterBody2D:
	if node is CharacterBody2D and node.has_method("set_scene_info"):
		return node
	for child in node.get_children():
		var result = find_player_node_recursive(child)
		if result:
			return result
	return null
