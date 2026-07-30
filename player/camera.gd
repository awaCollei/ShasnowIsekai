extends Camera2D
class_name PlayerCamera

# 传送时镜头移动的总时长；角色位置不会被这个过程延迟。
@export_range(0.05, 3.0, 0.05) var teleport_pan_duration: float = 0.5
# 用于自动识别“直接修改玩家 global_position”的传送，正常行走不会触发镜头平移。
@export var teleport_distance_threshold: float = 128.0
@export var debug_teleport_pan: bool = false

var target_position: Vector2 = Vector2.ZERO
var is_smoothing: bool = false

var _pan_tween: Tween
var _last_follow_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	# 与玩家脱离父节点变换，避免玩家传送时 Camera2D 先被父节点瞬移。
	top_level = true

	var parent_node := get_parent() as Node2D
	if parent_node:
		target_position = parent_node.global_position
		global_position = target_position
		_last_follow_position = target_position
	else:
		target_position = global_position
		_last_follow_position = global_position

func _process(_delta: float) -> void:
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return

	var follow_position := parent_node.global_position
	var moved_distance := follow_position.distance_to(_last_follow_position)

	if not is_smoothing:
		if moved_distance > teleport_distance_threshold:
			# 兼容外部直接设置玩家 global_position 的传送逻辑。
			smooth_move_to(follow_position)
			if debug_teleport_pan:
				print("[PlayerCamera] detected teleport, pan to ", follow_position)
		else:
			# 普通移动时镜头继续紧跟玩家，不引入额外延迟。
			global_position = follow_position

	_last_follow_position = follow_position

func smooth_move_to(new_position: Vector2) -> void:
	if _pan_tween != null:
		_pan_tween.kill()

	target_position = new_position
	is_smoothing = true
	_pan_tween = create_tween()
	_pan_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_pan_tween.tween_property(self, "global_position", target_position, teleport_pan_duration)
	_pan_tween.finished.connect(_on_pan_finished)

	if debug_teleport_pan:
		print("[PlayerCamera] pan start: ", global_position, " -> ", target_position,
			" (", teleport_pan_duration, "s)")

func _on_pan_finished() -> void:
	global_position = target_position
	is_smoothing = false
	_pan_tween = null

	if debug_teleport_pan:
		print("[PlayerCamera] pan finished at ", target_position)

func set_target(target: Node2D) -> void:
	if target:
		smooth_move_to(target.global_position)
