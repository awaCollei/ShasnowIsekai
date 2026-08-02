extends Node2D

# 预加载纹理
var rv_texture_indoor: Texture2D = preload("res://assets/base/rv.png")
var rv_texture_outdoor: Texture2D = preload("res://assets/base/rv2.png")

# 节点引用
@onready var rv_sprite: Sprite2D = $RV
@onready var player: CharacterBody2D = $Player
@onready var near_bg: Sprite2D = $NearBackground
@onready var far_bg: Sprite2D = $FarBackground

# 远背景视差系数（0 = 不动，1 = 跟玩家完全同步）
@export var far_bg_parallax: float = 0.8

# 背景初始位置基准
var _far_bg_base_pos: Vector2

func _ready() -> void:
	# 初始设置RV纹理
	update_rv_texture()
	_far_bg_base_pos = far_bg.position

func _process(_delta: float) -> void:
	# 持续检查玩家子场景并更新RV纹理
	update_rv_texture()
	# 视差：远背景根据玩家X坐标偏移
	_update_parallax()

func update_rv_texture() -> void:
	if not player or not rv_sprite:
		return
	
	# 根据玩家的sub_scene设置对应的纹理
	if player.current_sub_scene == "indoor":
		rv_sprite.texture = rv_texture_indoor
	else:
		rv_sprite.texture = rv_texture_outdoor

func _update_parallax() -> void:
	if not player or not far_bg:
		return
	# 远背景根据玩家位移按比例偏移，模拟深度视差
	var player_offset_x: float = player.global_position.x - _far_bg_base_pos.x
	far_bg.position.x = _far_bg_base_pos.x + player_offset_x * far_bg_parallax