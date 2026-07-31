extends Camera2D
class_name PlayerCamera

# 传送时镜头移动的总时长；角色位置不会被这个过程延迟。
@export_range(0.05, 3.0, 0.05) var teleport_pan_duration: float = 0.5
# 用于自动识别“直接修改玩家 global_position”的传送，正常行走不会触发镜头平移。
@export var teleport_distance_threshold: float = 128.0
@export var debug_teleport_pan: bool = false

# 传送动画期间，镜头目标每帧跟随玩家；不会因为玩家移动而瞬移到目标点。
const PAN_RETARGET_EPSILON: float = 0.01

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

    if is_smoothing:
        # 传送后的玩家可能已经开始移动。无论是普通移动还是再次传送，
        # 都只更新补间终点，从当前镜头位置重新平滑追向新终点，不瞬移。
        if moved_distance > PAN_RETARGET_EPSILON:
            _retarget_pan(follow_position)
    else:
        if moved_distance > teleport_distance_threshold:
            # 兼容外部直接设置玩家 global_position 的传送逻辑。
            smooth_move_to(follow_position)
            if debug_teleport_pan:
                print("[PlayerCamera] detected teleport, pan to ", follow_position)
        else:
            # 普通移动时镜头继续紧跟玩家，不引入额外延迟。
            target_position = follow_position
            global_position = follow_position

    _last_follow_position = follow_position

func _retarget_pan(new_position: Vector2) -> void:
    if new_position.distance_to(target_position) <= PAN_RETARGET_EPSILON:
        return

    # Tween 没有可变终点；重建 Tween，但保留当前 global_position，
    # 因此重定向过程仍然连续，不会跳到旧传送门或新玩家位置。
    if _pan_tween != null:
        _pan_tween.kill()
    _pan_tween = null
    target_position = new_position
    # 重定向可能发生在玩家持续移动时。线性补间避免每帧重启缓动造成
    # 镜头在缓动起点反复减速，仍保持平滑且能持续追上玩家。
    _start_pan_tween(false)

func _start_pan_tween(use_eased_transition: bool = true) -> void:
    _pan_tween = create_tween()
    if use_eased_transition:
        _pan_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
    else:
        _pan_tween.set_trans(Tween.TRANS_LINEAR)
    _pan_tween.tween_property(self, "global_position", target_position, teleport_pan_duration)
    _pan_tween.finished.connect(_on_pan_finished)

func smooth_move_to(new_position: Vector2) -> void:
    if _pan_tween != null:
        _pan_tween.kill()

    target_position = new_position
    # smooth_move_to 可能是在玩家刚被传送的同一帧调用；把基准同步到
    # 新位置，避免下一次 _process 把这次已处理的传送误判成玩家移动。
    _last_follow_position = new_position
    is_smoothing = true
    _start_pan_tween()

    if debug_teleport_pan:
        print("[PlayerCamera] pan start: ", global_position, " -> ", target_position,
            " (", teleport_pan_duration, "s)")

func _on_pan_finished() -> void:
    # Tween 已经把镜头连续移动到终点；不再用一次赋值把镜头瞬移到目标。
    is_smoothing = false
    _pan_tween = null

    if debug_teleport_pan:
        print("[PlayerCamera] pan finished at ", target_position)

func set_target(target: Node2D) -> void:
    if target:
        smooth_move_to(target.global_position)
        # set_target 也可能只是让镜头看向一个独立目标，不能把玩家
        # 当成“刚传送后已移动”；传送调用则保留 smooth_move_to 的基准。
        var parent_node := get_parent() as Node2D
        if parent_node:
            _last_follow_position = parent_node.global_position
