extends Enemy
class_name Slime

## 史莱姆：正面/背面分别侦察，锁定后追到玩家离开索敌范围。
@export_group("感知范围")
@export var front_detection_range := 360.0
@export var back_detection_range := 150.0
@export var pursuit_range := 560.0
@export var attack_range := 82.0
@export var vertical_detection_tolerance := 120.0
@export var sub_scene := "outdoor"

@export_group("战斗")
@export var move_speed := 105.0
@export var attack_damage := 12.0
@export var attack_hit_frame := 7
@export var attack_cooldown := 0.8
@export var starts_facing_right := false

@onready var animation: CharacterAnimation = $CharacterAnimation

var _player: Player
var _alerted := false
var _attacking := false
var _hit_dealt := false
var _cooldown_left := 0.0
var _dead := false
var _facing_right := false


func _ready() -> void:
	super._ready()
	_facing_right = starts_facing_right
	animation.add_frame_animation("walk", "res://assets/slime/walk/", "walk_", 11, 0.08, true)
	animation.add_frame_animation("attack", "res://assets/slime/attack/", "attack_", 14, 0.055, false)
	animation.add_frame_animation("death", "res://assets/slime/death/", "death_", 8, 0.09, false)
	animation.animation_finished.connect(_on_animation_finished)
	animation.set_flip_h(_facing_right)
	animation.play_animation("walk")
	_player = get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return

	if _player.is_dead or _player.current_sub_scene != sub_scene:
		_alerted = false
		_attacking = false
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	var offset := _player.global_position - global_position
	var dx := offset.x
	var distance := absf(dx)
	if absf(offset.y) > vertical_detection_tolerance:
		_alerted = false
		_attacking = false
		return

	if not _alerted:
		if _is_in_directional_detection(dx, distance):
			_alerted = true
		else:
			return
	elif distance > pursuit_range:
		_alerted = false
		_attacking = false
		animation.play_animation("walk", false)
		return

	if _attacking:
		if not _hit_dealt and animation.current_frame >= attack_hit_frame:
			_hit_dealt = true
			var still_in_front := (dx >= 0.0) == _facing_right
			if distance <= attack_range * 1.15 and still_in_front:
				_player.take_damage(attack_damage)
		return

	_face_towards(dx)
	if distance <= attack_range and _cooldown_left <= 0.0:
		_start_attack()
	else:
		animation.play_animation("walk", false)
		global_position.x = move_toward(global_position.x, _player.global_position.x, move_speed * delta)


func _is_in_directional_detection(dx: float, distance: float) -> bool:
	var target_is_in_front := (dx >= 0.0) == _facing_right
	return distance <= (front_detection_range if target_is_in_front else back_detection_range)


func _face_towards(dx: float) -> void:
	if absf(dx) < 0.5:
		return
	_facing_right = dx > 0.0
	# 素材默认朝左，因此朝右时水平翻转。
	animation.set_flip_h(_facing_right)


func _start_attack() -> void:
	_attacking = true
	_hit_dealt = false
	_cooldown_left = attack_cooldown
	animation.play_animation("attack")


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "attack" and not _dead:
		_attacking = false
		animation.play_animation("walk")
	elif anim_name == "death":
		queue_free()


func die() -> void:
	if _dead:
		return
	_dead = true
	_alerted = false
	_attacking = false
	monitorable = false
	monitoring = false
	died.emit()
	animation.play_animation("death")
