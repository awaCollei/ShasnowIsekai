extends WorldScene

## 房车营地场景：这里只保留本地图独有的内容。

const TRAINING_DUMMY_SCENE: PackedScene = preload("res://enemies/training_dummy.tscn")
const INTRO_PLOT_ID: String = "0-1"

@export var training_dummy_position: Vector2 = Vector2(-800.0, 640.0)

func _spawn_scene_entities() -> void:
	spawn_enemy(TRAINING_DUMMY_SCENE, training_dummy_position)


func _trigger_scene_plot() -> void:
	if not PlotlineManager.is_quest_completed(INTRO_PLOT_ID):
		PlotlineManager.play_plot(INTRO_PLOT_ID)
