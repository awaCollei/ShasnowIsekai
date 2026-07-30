extends Camera2D
class_name PlayerCamera

# 平滑移动参数
@export var smooth_speed: float = 5.0
@export var offset_smoothing: bool = true

# 目标位置
var target_position: Vector2 = Vector2.ZERO
var is_smoothing: bool = false

func _ready() -> void:
	# 初始位置
	target_position = global_position

func _process(delta: float) -> void:
	if is_smoothing:
		# 平滑移动到目标位置
		global_position = global_position.lerp(target_position, smooth_speed * delta)
		
		# 检查是否到达目标
		if global_position.distance_to(target_position) < 1.0:
			global_position = target_position
			is_smoothing = false

func smooth_move_to(new_position: Vector2) -> void:
	target_position = new_position
	is_smoothing = true

func set_target(target: Node2D) -> void:
	if target:
		target_position = target.global_position
		is_smoothing = true