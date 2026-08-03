extends Node2D

@onready var label: Label = $Label

func show_damage(amount: int, world_pos: Vector2) -> void:
	label.text = str(amount)
	global_position = world_pos

	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "global_position:y", world_pos.y - 60.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
