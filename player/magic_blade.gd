extends Node2D
class_name MagicBlade

## 满蓄力后由攻击键触发的魔法之刃。
## 动画继续复用普攻帧，但伤害、范围、音效和释放特效均在此独立处理。

signal released
signal finished

@export_group("战斗")
@export var damage: int = 150
@export var mp_cost: float = 30.0
@export var hit_frame: int = 5
@export var forward_offset: float = 50.0

@export_group("释放特效")
@export var body_center_offset := Vector2(0.0, -12.0)
@export var magic_color := Color(0.30, 0.78, 1.0, 1.0)
@export var highlight_color := Color(0.82, 0.96, 1.0, 1.0)
@export_range(0.2, 2.0, 0.05) var effect_intensity := 1.0
@export_range(0.1, 2.0, 0.01) var release_duration := 0.82

@onready var player: Player = get_parent()
@onready var animation: PlayerAnimation = player.get_node("PlayerAnimation")
@onready var hit_area: Area2D = player.get_node("MagicBladeArea")

var _busy := false
var _damage_dealt := false
var _physics_ticks_since_release := 0
var _effect_active := false
var _effect_time := 0.0
var _facing_right := true

const MAGIC_SFX_PATH := "res://assets/sound_effects/magic_1.mp3"


func _ready() -> void:
	z_index = 4
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow_material
	visible = false
	set_process(false)

	hit_area.monitoring = false
	hit_area.monitorable = false
	animation.attack_finished.connect(_on_attack_finished)


func try_release() -> bool:
	if _busy or not animation.can_release_magic_blade():
		return false

	# 到达满吟唱后才把预扣缓冲结算为真实 MP 消耗。
	if not player.commit_magic_chant():
		return false

	_busy = true
	_damage_dealt = false
	_physics_ticks_since_release = 0
	_facing_right = animation.sprite.flip_h
	hit_area.position.x = forward_offset if _facing_right else -forward_offset
	# 提前开启一帧，让物理系统有时间收集重叠目标。
	hit_area.monitoring = true

	animation.request_magic_blade()
	_start_release_effect()
	AudioManager.play_game_sfx(MAGIC_SFX_PATH)
	released.emit()
	return true


func is_busy() -> bool:
	return _busy


func cancel() -> void:
	# 统一锁定玩家时中止魔法之刃释放，避免 _busy 残留永久卡住移动。
	_busy = false
	_damage_dealt = false
	hit_area.monitoring = false
	_stop_release_effect()


func _process(delta: float) -> void:
	if not _effect_active:
		return
	_effect_time += delta
	if _effect_time >= release_duration:
		_stop_release_effect()
	else:
		queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _busy or _damage_dealt:
		return

	_physics_ticks_since_release += 1
	# monitoring 开启后至少等待一次完整物理更新，再读取重叠列表。
	if _physics_ticks_since_release >= 2 and animation.get_current_frame() >= hit_frame:
		_apply_damage()


func _start_release_effect() -> void:
	_effect_active = true
	_effect_time = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func _stop_release_effect() -> void:
	_effect_active = false
	_effect_time = 0.0
	visible = false
	set_process(false)
	queue_redraw()


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
	_stop_release_effect()
	finished.emit()


func _draw() -> void:
	if not _effect_active:
		return
	_draw_blade_release(effect_intensity)


func _draw_blade_release(alpha: float) -> void:
	var t := clampf(_effect_time / release_duration, 0.0, 1.0)
	var direction := 1.0 if _facing_right else -1.0
	var origin := body_center_offset + Vector2(direction * 12.0, -8.0)
	var burst := sin(clampf(t / 0.42, 0.0, 1.0) * PI)
	var tail_fade := 1.0 - EffectTools.smoothstep(0.52, 1.0, t)

	# 主刀光跟随普攻的上劈起手、向前下方斜落：朝右为 ↘，朝左自动镜像为 ↙。
	var slash_start := origin + Vector2(-direction * 40.0, -40.0)
	var slash_control := origin + Vector2(direction * 54.0, -38.0)
	var slash_end := origin + Vector2(direction * 100.0, 66.0)
	var slash_progress := EffectTools.ease_out(minf(t / 0.40, 1.0))
	var slash_points := PackedVector2Array()
	# 保留足够采样点，让刀光刚出现时两端也能平滑收束，而不是画成短矩形。
	var sample_count := maxi(6, int(ceil(28.0 * slash_progress)))
	for i in sample_count:
		var point_t := slash_progress * float(i) / float(sample_count - 1)
		slash_points.append(EffectTools.quadratic_bezier(slash_start, slash_control, slash_end, point_t))

	# 用渐细带状面代替固定宽度折线，两端收束后不会出现整齐的截断面。
	for layer in 5:
		var width := 22.0 - float(layer) * 4.0
		var layer_alpha := alpha * burst * (0.10 + float(layer) * 0.11)
		var layer_color := highlight_color if layer >= 3 else magic_color
		_draw_tapered_slash(slash_points, EffectTools.with_alpha(layer_color, layer_alpha), width)

	var base_angle := 0.0 if _facing_right else PI
	# 次级冲击波保持在近战距离内，避免抢过斜劈刀光。
	var shock_radius := lerpf(20.0, 145.0, EffectTools.ease_out(t))
	draw_arc(origin, shock_radius, base_angle - 0.72, base_angle + 0.72, 32, EffectTools.with_alpha(highlight_color, alpha * tail_fade * 0.28), 2.0, true)
	draw_arc(origin, shock_radius * 0.78, base_angle - 0.52, base_angle + 0.52, 26, EffectTools.with_alpha(magic_color, alpha * tail_fade * 0.20), 3.0, true)

	for i in 18:
		var spread := lerpf(-0.72, 0.72, float(i) / 17.0)
		var ray_direction := Vector2.from_angle(base_angle + spread)
		var ray_length := (90.0 + float((i * 37) % 95)) * EffectTools.ease_out(t)
		var ray_start := origin + ray_direction * ray_length * 0.32
		var ray_end := origin + ray_direction * ray_length
		var ray_alpha := alpha * tail_fade * (0.22 + float(i % 3) * 0.10)
		draw_line(ray_start, ray_end, EffectTools.with_alpha(highlight_color, ray_alpha), 1.0 + float(i % 2), true)
		draw_circle(ray_end, 1.5 + float(i % 3), EffectTools.with_alpha(magic_color, ray_alpha), true, -1.0, true)

	# 释放瞬间的中心白闪。
	var flash := 1.0 - EffectTools.smoothstep(0.0, 0.20, t)
	for i in range(5, 0, -1):
		draw_circle(origin, float(i) * 13.0, EffectTools.with_alpha(highlight_color, alpha * flash * 0.035 * float(6 - i)), true, -1.0, true)


func _draw_tapered_slash(points: PackedVector2Array, color: Color, max_width: float) -> void:
	if points.size() < 2 or max_width <= 0.0:
		return
	# 刀光展开前所有采样点会重合，不向渲染器提交零面积多边形。
	if points[0].distance_squared_to(points[points.size() - 1]) < 0.0001:
		return

	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var last_index := points.size() - 1

	for i in points.size():
		var previous := points[maxi(0, i - 1)]
		var next := points[mini(last_index, i + 1)]
		var tangent := (next - previous).normalized()
		if tangent.is_zero_approx():
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x)
		var progress := float(i) / float(last_index)
		# 指数小于 1，只在靠近两端的位置快速收尖，中段仍保持原有厚度。
		# 首尾显式归零，避免 sin(PI) 的浮点误差留下极细的平端。
		var taper := 0.0 if i == 0 or i == last_index else pow(maxf(0.0, sin(progress * PI)), 0.36)
		var half_width := max_width * 0.5 * taper
		left_edge.append(points[i] + normal * half_width)
		right_edge.append(points[i] - normal * half_width)

	var ribbon := PackedVector2Array()
	ribbon.append_array(left_edge)
	for i in range(right_edge.size() - 1, -1, -1):
		ribbon.append(right_edge[i])

	if ribbon.size() >= 3:
		draw_colored_polygon(ribbon, color)
