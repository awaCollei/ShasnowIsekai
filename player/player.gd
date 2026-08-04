extends CharacterBody2D

const SPEED = 100.0
const RUN_SPEED = 400.0

@onready var basic_attack: BasicAttack = $BasicAttack
@onready var animation: PlayerAnimation = $PlayerAnimation

# ==========================
# 疾跑系统
# ==========================
var is_running := false
var last_direction := 0.0
var last_press_time := -1.0
const DOUBLE_TAP_TIME := 0.3
var was_direction_pressed := false

# ==========================
# 子场景属性
# ==========================
@export var current_scene: String = "base"
@export var current_sub_scene: String = "outdoor"

func _ready() -> void:
	# 加入 player 组，供 PlotlineManager 等系统查找
	add_to_group("player")

	# 获取当前场景
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		current_scene = scene_manager.get_current_scene()

func set_scene_info(scene: String) -> void:
	current_scene = scene

# ==========================
# 传送
# ==========================
func teleport_to(destination: Vector2) -> void:
	global_position = destination
	var camera := get_node_or_null("Camera2D") as PlayerCamera
	if camera:
		camera.smooth_move_to(destination)

func _physics_process(delta: float) -> void:
	# 普攻输入
	if Input.is_action_just_pressed("attack"):
		basic_attack.try_attack()

	# 吟唱输入
	if Input.is_action_just_pressed("chant"):
		animation.request_chant()
	elif Input.is_action_just_released("chant"):
		animation.request_chant_release()

	# 普攻 / 吟唱期间禁止移动
	if basic_attack.is_busy() or animation.is_chanting():
		velocity.x = 0.0
		move_and_slide()
		return

	var direction := Input.get_axis("ui_left", "ui_right")

	# ======================
	# 始终疾跑检测
	# ======================
	var always_run := false
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		always_run = settings.always_run

	# ======================
	# 双击检测
	# ======================
	var pressed := direction != 0.0

	if pressed and not was_direction_pressed:
		handle_run_input(direction)

	was_direction_pressed = pressed

	# ======================
	# 移动
	# ======================
	if direction != 0.0:
		var effective_running := is_running or always_run
		var current_speed = RUN_SPEED if effective_running else SPEED
		velocity.x = direction * current_speed
		animation.set_flip_h(direction > 0.0)

		if effective_running:
			animation.request_run()
		else:
			animation.request_walk()
	else:
		# 停止移动
		velocity.x = 0.0
		# 攻击 / 吟唱动画正在播放时，不要让自动 idle 打断它
		if not animation.is_attacking() and not animation.is_chanting():
			animation.request_idle()
		# 松开方向键退出疾跑
		is_running = false

	move_and_slide()

# ==========================
# 双击检测
# ==========================
func handle_run_input(direction: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# 同方向快速再次按下
	if direction == last_direction:
		if now - last_press_time <= DOUBLE_TAP_TIME:
			is_running = true

	last_direction = direction
	last_press_time = now
