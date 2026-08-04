extends Node2D

# 预加载纹理
var rv_texture_indoor: Texture2D = preload("res://assets/base/rv.png")
var rv_texture_outdoor: Texture2D = preload("res://assets/base/rv2.png")

# 预加载训练木桩场景
var training_dummy_scene: PackedScene = preload("res://enemies/training_dummy.tscn")

# 预加载伤害数字场景
var damage_number_scene: PackedScene = preload("res://ui/damage_number.tscn")

# 节点引用
@onready var rv_sprite: Sprite2D = $RV
@onready var player: CharacterBody2D = $Player
@onready var near_bg: Sprite2D = $NearBackground
@onready var far_bg: Sprite2D = $FarBackground
@onready var camera: Camera2D = $Player/Camera2D

# 远背景视差系数（0 = 不动，1 = 跟玩家完全同步）
@export var far_bg_parallax: float = 0.8

# 背景初始位置基准
var _far_bg_base_pos: Vector2

func _ready() -> void:
	# 初始设置RV纹理
	update_rv_texture()
	_far_bg_base_pos = far_bg.position

	# 生成训练木桩
	_spawn_training_dummy()
	PlotlineManager.play_plot("1_1")

func _spawn_training_dummy() -> void:
	var dummy: Enemy = training_dummy_scene.instantiate()
	dummy.position = Vector2(-800, 640)
	dummy.damage_taken.connect(_on_enemy_damage_taken.bind(dummy))
	add_child(dummy)

func _on_enemy_damage_taken(amount: int, enemy: Enemy) -> void:
	var dmg_node: Node2D = damage_number_scene.instantiate()
	add_child(dmg_node)
	dmg_node.show_damage(amount, enemy.global_position + Vector2(0, -60))

func _process(_delta: float) -> void:
	# 视差：远背景根据玩家X坐标偏移
	call_deferred("_update_parallax")
	# 持续检查玩家子场景并更新RV纹理
	update_rv_texture()

func update_rv_texture() -> void:
	if not player or not rv_sprite:
		return
	
	# 根据玩家的sub_scene设置对应的纹理
	if player.current_sub_scene == "indoor":
		rv_sprite.texture = rv_texture_indoor
	else:
		rv_sprite.texture = rv_texture_outdoor

func _update_parallax() -> void:
	if not camera or not far_bg:
		return
	# 远背景根据玩家位移按比例偏移
	var camera_offset_x: float = camera.global_position.x - _far_bg_base_pos.x
	far_bg.position.x = _far_bg_base_pos.x + camera_offset_x * far_bg_parallax
