extends Camera2D
class_name PlayerCamera

# 传送时镜头移动的总时长；角色位置不会被这个过程延迟。
@export_range(0.05, 3.0, 0.05) var teleport_pan_duration: float = 0.5
# 用于自动识别"直接修改玩家 global_position"的传送，正常行走不会触发镜头平移。
@export var teleport_distance_threshold: float = 128.0
@export var debug_teleport_pan: bool = false

# 镜头偏移量：让角色在画面中偏下（正值使镜头向上偏移）
@export var camera_offset: Vector2 = Vector2(0, -50)

const PAN_RETARGET_EPSILON: float = 0.01
# 指数衰减的速度因子系数，保证经过 pan_duration 后几乎追上目标。
const SMOOTH_FACTOR: float = 4.6

var target_position: Vector2 = Vector2.ZERO
var is_smoothing: bool = false

var _last_follow_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	# 与玩家脱离父节点变换，避免玩家传送时 Camera2D 先被父节点瞬移。
	top_level = true

	var parent_node := get_parent() as Node2D
	if parent_node:
		target_position = parent_node.global_position + camera_offset
		global_position = target_position
		_last_follow_position = parent_node.global_position
	else:
		target_position = global_position
		_last_follow_position = global_position

func _process(delta: float) -> void:
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return

	var follow_position := parent_node.global_position
	var moved_distance := follow_position.distance_to(_last_follow_position)

	if is_smoothing:
		# 平滑期间：若再次发生传送（仍可检测到），重新锁定目标
		if moved_distance > teleport_distance_threshold:
			smooth_move_to(follow_position)
		elif moved_distance > PAN_RETARGET_EPSILON:
			# 玩家普通移动时，只更新目标位置，镜头继续平滑追赶
			target_position = follow_position + camera_offset

		# 用指数衰减平滑移动，避免 Tween 反复重建带来的抖动
		_smooth_follow(delta)
	else:
		if moved_distance > teleport_distance_threshold:
			# 检测到传送，进入平滑过渡
			smooth_move_to(follow_position)
			if debug_teleport_pan:
				print("[PlayerCamera] detected teleport, pan to ", follow_position)
		else:
			# 普通移动：直接紧跟玩家（带偏移）
			target_position = follow_position + camera_offset
			global_position = target_position

	_last_follow_position = follow_position

func _smooth_follow(delta: float) -> void:
	# 基于时间的指数衰减：每帧按比例接近目标，比例由 delta 和设定时长决定
	var speed := SMOOTH_FACTOR / teleport_pan_duration
	var weight = clamp(1.0 - exp(-delta * speed), 0.0, 1.0)
	global_position = global_position.lerp(target_position, weight)

	# 足够近时直接归位，结束平滑状态
	if global_position.distance_to(target_position) < 0.5:
		global_position = target_position
		is_smoothing = false
		if debug_teleport_pan:
			print("[PlayerCamera] pan finished at ", target_position)

func smooth_move_to(new_position: Vector2) -> void:
	target_position = new_position + camera_offset
	_last_follow_position = new_position
	is_smoothing = true

	if debug_teleport_pan:
		print("[PlayerCamera] pan start: ", global_position, " -> ", target_position,
				" (", teleport_pan_duration, "s)")

func set_target(target: Node2D) -> void:
	if target:
		smooth_move_to(target.global_position)
		# 保持与玩家位置的基准同步，避免返回时误判传送
		var parent_node := get_parent() as Node2D
		if parent_node:
			_last_follow_position = parent_node.global_position
