extends Node
class_name BasicAttack

signal attack_started
signal attack_ended

@onready var player: CharacterBody2D = get_parent()
@onready var sprite: Sprite2D = player.get_node("Sprite2D")
@onready var attack_area: Area2D = player.get_node("AttackArea")

var attack_frames: Array[Texture2D] = []
const ANIM_INTERVAL: float = 0.025
const HIT_FRAME_START: int = 4
const HIT_FRAME_END: int = 17
const COOLDOWN_TIME: float = 1
const DAMAGE: int = 10

enum State { IDLE, ATTACKING, COOLDOWN }
var state: State = State.IDLE
var current_frame: int = 0
var anim_timer: float = 0.0
var cooldown_timer: float = 0.0
var hit_enemies: Array = []

func _ready() -> void:
	for i in range(1, 33):
		var path = "res://assets/shasnow/basic_attack/basic_attack_%d.png" % i
		var tex = load(path)
		if tex:
			attack_frames.append(tex)

	attack_area.monitoring = false
	attack_area.monitorable = false
	attack_area.area_entered.connect(_on_attack_area_entered)

func is_busy() -> bool:
	return state == State.ATTACKING or state == State.COOLDOWN

func try_attack() -> bool:
	if state == State.COOLDOWN:
		return false
	# IDLE 或 ATTACKING 都可以触发（后者会打断当前动画）
	_start_attack()
	return true

func _start_attack() -> void:
	state = State.ATTACKING
	current_frame = 0
	anim_timer = 0.0
	hit_enemies.clear()
	_update_hitbox()
	if not attack_frames.is_empty():
		sprite.texture = attack_frames[0]
	attack_started.emit()

func _process(delta: float) -> void:
	match state:
		State.ATTACKING:
			_process_attack(delta)
		State.COOLDOWN:
			_process_cooldown(delta)

func _process_attack(delta: float) -> void:
	if attack_frames.is_empty():
		_end_attack()
		return

	anim_timer += delta
	if anim_timer >= ANIM_INTERVAL:
		anim_timer -= ANIM_INTERVAL
		current_frame += 1
		if current_frame >= attack_frames.size():
			_end_attack()
		else:
			sprite.texture = attack_frames[current_frame]
			_update_hitbox()

func _update_hitbox() -> void:
	var hit_active := current_frame >= HIT_FRAME_START and current_frame <= HIT_FRAME_END
	attack_area.monitoring = hit_active
	# 攻击区域方向跟随角色朝向（flip_h = true 表示面朝右）
	attack_area.position.x = 25.0 if sprite.flip_h else -25.0

func _end_attack() -> void:
	attack_area.monitoring = false
	state = State.COOLDOWN
	cooldown_timer = 0.0

func _process_cooldown(delta: float) -> void:
	cooldown_timer += delta
	if cooldown_timer >= COOLDOWN_TIME:
		state = State.IDLE
		attack_ended.emit()

func _on_attack_area_entered(area: Area2D) -> void:
	if area is Enemy and not hit_enemies.has(area):
		hit_enemies.append(area)
		area.take_damage(DAMAGE)
