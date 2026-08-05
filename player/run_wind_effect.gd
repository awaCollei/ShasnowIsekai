extends Node2D
class_name RunWindEffect

## 疾跑时的程序化破风线。
## 不依赖贴图：生成半透明白色短条，并让它们朝角色身后快速划过。

@export_group("生成")
@export_range(4.0, 40.0, 1.0) var streaks_per_second: float = 18.0
@export_range(4, 40, 1) var max_streaks: int = 18
@export var spawn_x_range := Vector2(-10.0, 30.0)
@export var spawn_y_range := Vector2(-72.0, 72.0)

@export_group("外观")
@export var streak_color := Color(1.0, 1.0, 1.0, 0.58)
@export var length_range := Vector2(30.0, 50.0)
@export var width_range := Vector2(0.4, 1.2)
@export var lifetime_range := Vector2(0.18, 0.34)
@export var drift_speed_range := Vector2(90.0, 150.0)
@export_range(0.01, 0.5, 0.01) var fade_in_time: float = 0.16
@export_range(0.01, 0.8, 0.01) var fade_out_time: float = 0.10


class WindStreak:
	var position := Vector2.ZERO
	var length: float = 40.0
	var width: float = 2.0
	var speed: float = 120.0
	var life: float = 0.0
	var lifetime: float = 0.25
	var slope: float = 0.0


var _active := false
var _facing_right := true
var _effect_alpha := 0.0
var _spawn_accumulator := 0.0
var _streaks: Array[WindStreak] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 3
	visible = false
	set_process(false)
	_rng.randomize()


func set_running(active: bool, facing_right: bool) -> void:
	set_facing(facing_right)
	if _active == active:
		return

	_active = active
	_spawn_accumulator = 0.0
	if _active:
		visible = true
		set_process(true)
		# 不在启动瞬间批量生成；生成密度会随淡入强度自然提升。
	elif not _streaks.is_empty() or _effect_alpha > 0.0:
		set_process(true)


func set_facing(facing_right: bool) -> void:
	if _facing_right == facing_right:
		return
	_facing_right = facing_right
	# 转身时清掉旧方向的风线，避免两组线条交叉。
	_streaks.clear()
	_spawn_accumulator = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _active:
		_effect_alpha = minf(1.0, _effect_alpha + delta / fade_in_time)
		# 启动阶段由疏到密地生成，避免第一帧突然冒出一组白条。
		var density := EffectTools.smoothstep(0.0, 1.0, _effect_alpha)
		_spawn_accumulator += delta * streaks_per_second * density
		while _spawn_accumulator >= 1.0 and _streaks.size() < max_streaks:
			_spawn_accumulator -= 1.0
			_spawn_streak()
		# 满容量时不积压生成额度，避免长时间疾跑后瞬间补满。
		if _streaks.size() >= max_streaks:
			_spawn_accumulator = minf(_spawn_accumulator, 1.0)
	else:
		_effect_alpha = maxf(0.0, _effect_alpha - delta / fade_out_time)

	var direction := 1.0 if _facing_right else -1.0
	for i in range(_streaks.size() - 1, -1, -1):
		var streak := _streaks[i]
		streak.life += delta
		streak.position.x -= direction * streak.speed * delta
		if streak.life >= streak.lifetime:
			_streaks.remove_at(i)

	if not _active and _effect_alpha <= 0.0 and _streaks.is_empty():
		visible = false
		set_process(false)

	queue_redraw()


func _spawn_streak() -> void:
	if _streaks.size() >= max_streaks:
		return

	var direction := 1.0 if _facing_right else -1.0
	var streak := WindStreak.new()
	streak.position = Vector2(
		direction * _rng.randf_range(spawn_x_range.x, spawn_x_range.y),
		_rng.randf_range(spawn_y_range.x, spawn_y_range.y)
	)
	streak.length = _rng.randf_range(length_range.x, length_range.y)
	streak.width = _rng.randf_range(width_range.x, width_range.y)
	streak.speed = _rng.randf_range(drift_speed_range.x, drift_speed_range.y)
	streak.lifetime = _rng.randf_range(lifetime_range.x, lifetime_range.y)
	streak.slope = _rng.randf_range(-5.0, 5.0)
	_streaks.append(streak)


func _draw() -> void:
	if _effect_alpha <= 0.001:
		return

	var direction := 1.0 if _facing_right else -1.0
	for streak in _streaks:
		var progress := clampf(streak.life / streak.lifetime, 0.0, 1.0)
		# 每根风条先柔和显现，再逐渐拖淡；比正弦曲线的突然亮起更自然。
		var appear := EffectTools.smoothstep(0.0, 0.28, progress)
		var disappear := 1.0 - EffectTools.smoothstep(0.48, 1.0, progress)
		var life_alpha := appear * disappear
		var alpha := streak_color.a * _effect_alpha * life_alpha
		var tail := streak.position - Vector2(direction * streak.length, streak.slope)
		var outer_color := EffectTools.with_alpha(streak_color, alpha * 0.22)
		var core_color := EffectTools.with_alpha(streak_color, alpha)
		# 宽而淡的外层 + 窄而亮的内芯，形成半透明白色破风条。
		draw_line(tail, streak.position, outer_color, streak.width * 2.8, true)
		draw_line(tail.lerp(streak.position, 0.18), streak.position, core_color, streak.width, true)
