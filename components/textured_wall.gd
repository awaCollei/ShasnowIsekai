extends Node2D
class_name TexturedWall

## 仅用于房间之间的墙面贴图，不提供碰撞。
## 空气墙请使用 components/wall.tscn。
@export var wall_texture: Texture2D = preload("res://assets/city1/wall.png")
@export var wall_size: Vector2 = Vector2(32.0, 400.0)


func _ready() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if not sprite:
		return
	sprite.texture = wall_texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, wall_size)
