extends CharacterBody2D
class_name Character

## 角色基类 — 所有地图角色的公共父类。
## 提供移动、方向、动画等基础功能，供 Player 和剧情 NPC 使用。

signal movement_finished

## 角色 ID，对应 characters.json 中的 key
@export var character_id: String = ""

## 移动速度（默认值，会被角色数据覆盖）
@export var walk_speed: float = 100.0
@export var run_speed: float = 400.0

var facing_right: bool = true
var _move_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: CharacterAnimation = _find_anim_node()


func _find_anim_node() -> CharacterAnimation:
	for child in get_children():
		if child is CharacterAnimation:
			return child
	return null


## 从角色数据初始化外观和动画
func initialize(id: String) -> void:
	character_id = id
	var data := CharacterDatabase.get_character(id)
	if data.is_empty():
		push_error("Character: 找不到角色数据: " + id)
		return

	walk_speed = data.get("walk_speed", walk_speed)
	run_speed = data.get("run_speed", run_speed)

	if anim:
		anim.initialize(id)
		if anim.has_animation("idle"):
			anim.play_animation("idle")


# ==========================
# 方向
# ==========================

## 设置角色朝向（"left" / "right"）
func set_direction(dir: String) -> void:
	if dir == "left":
		facing_right = false
	elif dir == "right":
		facing_right = true
	if anim:
		anim.set_flip_h(facing_right)


# ==========================
# 移动
# ==========================

## 传送到目标位置
func teleport_to(pos: Vector2) -> void:
	global_position = pos


## 移动到目标位置
## move_type: "walk" | "run" | "translate" | "teleport"
func move_to(target: Vector2, move_type: String = "walk") -> void:
	match move_type:
		"teleport":
			teleport_to(target)
		"walk", "run":
			await _move_with_anim(target, move_type)
		"translate":
			await _move_linear(target, walk_speed)
		_:
			await _move_with_anim(target, "walk")


func _move_with_anim(target: Vector2, move_type: String) -> void:
	if anim:
		anim.play_animation(move_type)

	var speed := run_speed if move_type == "run" else walk_speed
	var dist := global_position.distance_to(target)
	var duration := dist / speed

	# 根据目标方向翻转
	if target.x > global_position.x:
		set_direction("right")
	elif target.x < global_position.x:
		set_direction("left")

	if _move_tween and _move_tween.is_running():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", target, duration)

	await _move_tween.finished

	if anim:
		anim.play_animation("idle")
	movement_finished.emit()


func _move_linear(target: Vector2, speed: float) -> void:
	var dist := global_position.distance_to(target)
	var duration := dist / speed

	if _move_tween and _move_tween.is_running():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", target, duration)

	await _move_tween.finished
	movement_finished.emit()


## 取消当前移动
func cancel_move() -> void:
	if _move_tween and _move_tween.is_running():
		_move_tween.kill()