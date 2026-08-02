extends CharacterBody2D

const SPEED = 100.0
const RUN_SPEED = 400.0
const ANIM_INTERVAL = 0.04
const RUN_ANIM_INTERVAL = 0.04

@onready var sprite: Sprite2D = $Sprite2D

var walk_frames: Array[Texture2D] = []
var run_frames: Array[Texture2D] = []
var tex_stand: Texture2D = preload("res://assets/shasnow/stand/stand_1.png")
var anim_timer := 0.0
var current_frame := 0
var is_moving := false

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
	# 加载行走动画
	for i in range(1, 25):
		var path = "res://assets/shasnow/walk/walk_%d.png" % i
		var texture = load(path)
		if texture:
			walk_frames.append(texture)
		else:
			push_error("无法加载: " + path)
	
	# 加载疾跑动画
	for i in range(1, 17):
		var path = "res://assets/shasnow/run/run_%d.png" % i
		var texture = load(path)
		if texture:
			run_frames.append(texture)
	
	# 如果没有疾跑动画
	if run_frames.is_empty():
		run_frames = walk_frames.duplicate()
		print("警告: 未找到疾跑动画，使用行走动画替代")
	
	if walk_frames.is_empty():
		walk_frames = [tex_stand]
	
	sprite.texture = tex_stand
	
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
	var direction := Input.get_axis("ui_left", "ui_right")
	
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
		var current_speed = RUN_SPEED if is_running else SPEED
		velocity.x = direction * current_speed
		sprite.flip_h = direction > 0.0
		
		# 刚开始移动
		if not is_moving:
			is_moving = true
			current_frame = 0
			if is_running:
				sprite.texture = run_frames[current_frame]
			else:
				sprite.texture = walk_frames[current_frame]
			anim_timer = 0.0
		
		# 动画播放
		anim_timer += delta
		var interval = RUN_ANIM_INTERVAL if is_running else ANIM_INTERVAL
		var frames = run_frames if is_running else walk_frames
		
		if anim_timer >= interval:
			anim_timer -= interval
			current_frame = (current_frame + 1) % frames.size()
			sprite.texture = frames[current_frame]
	else:
		# 停止移动
		velocity.x = 0.0
		sprite.texture = tex_stand
		anim_timer = 0.0
		current_frame = 0
		is_moving = false
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
			# 切换疾跑动画
			if is_moving:
				current_frame = 0
				sprite.texture = run_frames[current_frame]
	
	last_direction = direction
	last_press_time = now