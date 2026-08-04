extends Node
class_name MagicBlade

## 满蓄力后由攻击键触发的魔法之刃。
## 动画继续复用普攻帧，但伤害、范围、音效和特效均独立处理。

signal released
signal finished

@export var damage: int = 150
@export var hit_frame: int = 5
@export var forward_offset: float = 50.0

@onready var player: CharacterBody2D = get_parent()
@onready var animation: PlayerAnimation = player.get_node("PlayerAnimation")
@onready var hit_area: Area2D = player.get_node("MagicBladeArea")

var _busy := false
var _damage_dealt := false
var _physics_ticks_since_release := 0
const MAGIC_SFX_PATH := "res://assets/sound_effects/magic_1.mp3"


func _ready() -> void:
	hit_area.monitoring = false
	hit_area.monitorable = false
	animation.attack_finished.connect(_on_attack_finished)


func try_release() -> bool:
	if _busy or not animation.can_release_magic_blade():
		return false

	_busy = true
	_damage_dealt = false
	_physics_ticks_since_release = 0
	var facing_right := animation.sprite.flip_h
	hit_area.position.x = forward_offset if facing_right else -forward_offset
	# 提前开启一帧，让物理系统有时间收集重叠目标。
	hit_area.monitoring = true

	animation.request_magic_blade()
	AudioManager.play_game_sfx(MAGIC_SFX_PATH)
	released.emit()
	return true


func is_busy() -> bool:
	return _busy


func _physics_process(_delta: float) -> void:
	if not _busy or _damage_dealt:
		return

	_physics_ticks_since_release += 1
	# monitoring 开启后至少等待一次完整物理更新，再读取重叠列表。
	if _physics_ticks_since_release >= 2 and animation.get_current_frame() >= hit_frame:
		_apply_damage()


func _apply_damage() -> void:
	_damage_dealt = true
	var hit_count := 0
	for area in hit_area.get_overlapping_areas():
		if area is Enemy:
			(area as Enemy).take_damage(damage)
			hit_count += 1
	hit_area.monitoring = false
	print("魔法之刃释放：命中 %d 个目标，伤害 %d" % [hit_count, damage])


func _on_attack_finished() -> void:
	if not _busy:
		return
	# 极端掉帧跳过判定帧时，仍保证结算一次伤害。
	if not _damage_dealt:
		_apply_damage()
	_busy = false
	hit_area.monitoring = false
	finished.emit()
