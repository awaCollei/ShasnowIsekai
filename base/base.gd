extends Node2D

# 预加载纹理
var rv_texture_indoor: Texture2D = preload("res://assets/base/rv.png")
var rv_texture_outdoor: Texture2D = preload("res://assets/base/rv2.png")

# 节点引用
@onready var rv_sprite: Sprite2D = $RV
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	# 初始设置RV纹理
	update_rv_texture()

func _process(_delta: float) -> void:
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