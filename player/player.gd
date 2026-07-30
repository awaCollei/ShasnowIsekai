extends CharacterBody2D

const SPEED = 400.0
const ANIM_INTERVAL = 0.1

@onready var sprite: Sprite2D = $Sprite2D

var walk_frames: Array[Texture2D] = []
var tex_stand: Texture2D = preload("res://assets/shasnow/stand_1.png")

var anim_timer := 0.0
var current_frame := 0
var is_moving := false  # 记录是否在移动

# 子场景属性
@export var current_scene: String = "base"
@export var current_sub_scene: String = "outdoor"

func _ready() -> void:
	for i in range(1, 7):
		var path = "res://assets/shasnow/walk_%d.png" % i
		var texture = load(path)
		if texture:
			walk_frames.append(texture)
		else:
			push_error("无法加载: ", path)
	
	if walk_frames.is_empty():
		walk_frames = [tex_stand]
	
	# 初始显示站立
	sprite.texture = tex_stand
	
	# 从场景管理器获取当前场景信息
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		current_scene = scene_manager.get_current_scene()

func set_scene_info(scene: String) -> void:
	current_scene = scene

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")

	if direction != 0.0:
		velocity.x = direction * SPEED
		sprite.flip_h = direction > 0.0
		
		# 如果是刚切换为移动状态，立即显示第一帧
		if not is_moving:
			is_moving = true
			current_frame = 0
			sprite.texture = walk_frames[current_frame]
			anim_timer = 0.0
		
		# 行走动画计时
		anim_timer += delta
		if anim_timer >= ANIM_INTERVAL:
			anim_timer -= ANIM_INTERVAL
			current_frame = (current_frame + 1) % walk_frames.size()
			sprite.texture = walk_frames[current_frame]
	else:
		velocity.x = 0.0
		sprite.texture = tex_stand
		anim_timer = 0.0
		current_frame = 0
		is_moving = false

	move_and_slide()