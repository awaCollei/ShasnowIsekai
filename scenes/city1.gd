extends WorldScene

const INTRO_PLOT_ID: String = "1_1"

@export var training_dummy_position: Vector2 = Vector2(-800.0, 640.0)

const SLIME_SCENE: PackedScene = preload("res://enemies/slime.tscn")

func _spawn_scene_entities() -> void:
	# 四只史莱姆位于同一集群：进入战斗后按 BattleManager 配置拆成 3 + 1 两波。
	for spawn_x in [900.0, 1080.0, 1260.0, 1440.0]:
		spawn_enemy(SLIME_SCENE, Vector2(spawn_x, 700.0))
