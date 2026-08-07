extends StaticBody2D
class_name Wall

## 有碰撞的空气墙。visible_texture 为空时不可见；建筑外墙可为它指定 wall.png。
@export var sub_scene: String = ""
@export var visible_texture: Texture2D
@export var wall_color: Color = Color.WHITE
@export var wall_size: Vector2 = Vector2(20.0, 20.0)
## false 保持旧场景以节点中心为原点；生成建筑时使用左上角原点。
@export var use_top_left_origin: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _last_active := true


func _ready() -> void:
	_configure_geometry()
	add_to_group("walls")
	_update_active_state()


func _process(_delta: float) -> void:
	_update_active_state()


func _configure_geometry() -> void:
	if collision_shape and collision_shape.shape is RectangleShape2D:
		# 场景资源中的 Shape 可能被多个实例共享，修改前先复制。
		collision_shape.shape = collision_shape.shape.duplicate()
		(collision_shape.shape as RectangleShape2D).size = wall_size
		collision_shape.position = wall_size * 0.5 if use_top_left_origin else Vector2.ZERO
	if sprite:
		sprite.texture = visible_texture
		sprite.modulate = wall_color
		sprite.centered = not use_top_left_origin
		sprite.region_enabled = visible_texture != null
		if sprite.region_enabled:
			sprite.region_rect = Rect2(Vector2.ZERO, wall_size)


func _update_active_state() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var active := player == null or sub_scene.is_empty() or player.current_sub_scene == sub_scene
	if active == _last_active and is_node_ready():
		# 首帧仍需同步 visible_texture，因此仅跳过稳定状态。
		if collision_shape and collision_shape.disabled == not active:
			return
	_last_active = active
	if collision_shape:
		collision_shape.set_deferred("disabled", not active)
	if sprite:
		sprite.visible = active and visible_texture != null
