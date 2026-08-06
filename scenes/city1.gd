extends WorldScene

const INTRO_PLOT_ID: String = "1_1"

@export var training_dummy_position: Vector2 = Vector2(-800.0, 640.0)

const SLIME_SCENE: PackedScene = preload("res://enemies/slime.tscn")

func _spawn_scene_entities() -> void:
	spawn_enemy(SLIME_SCENE, Vector2(900.0, 700.0))
