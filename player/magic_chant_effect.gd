extends Node2D
class_name MagicChantEffect

signal charge_changed(progress: float)

## 无贴图的吟唱特效。
## 后续有正式素材时，可保留这里的运动逻辑，只替换 _draw() 中的程序化图形。

@export_group("定位")
## 角色面朝右时的手部位置；面朝左时会自动镜像 X。
@export var hand_offset_right := Vector2(48.0, -20.0)
@export var body_center_offset := Vector2(0.0, -12.0)
@export var ground_offset := Vector2(0.0, 88.0)

@export_group("外观")
@export var magic_color := Color(0.30, 0.78, 1.0, 1.0)
@export var highlight_color := Color(0.82, 0.96, 1.0, 1.0)
@export_range(0.2, 2.0, 0.05) var intensity := 1.0
@export_range(8, 48, 1) var mote_count := 28

const TAU_F := TAU
const FADE_IN_TIME := 0.28
const FADE_OUT_TIME := 0.42
const CHARGE_TIME := 2.4

var _active := false
var _facing_right := true
var _time := 0.0
var _charge := 0.0
var _visibility := 0.0
var _motes: Array[Dictionary] = []


func _ready() -> void:
	z_index = 4
	# 加法混合让程序化线条叠加成真正的发光效果，而不是盖住角色。
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow_material
	visible = false
	set_process(false)
	_build_motes()


func start(facing_right: bool) -> void:
	_facing_right = facing_right
	if not _active:
		_active = true
		visible = true
		_time = 0.0
		_charge = 0.0
		charge_changed.emit(_charge)
	set_process(true)
	queue_redraw()


func stop() -> void:
	_active = false
	# 普通松开吟唱保留柔和淡出。
	if _visibility > 0.0:
		set_process(true)


func consume_charge() -> void:
	# 魔法之刃接管释放表现后，吟唱节点只负责立即收起蓄力特效。
	_active = false
	_visibility = 0.0
	_charge = 0.0
	charge_changed.emit(_charge)
	visible = false
	set_process(false)
	queue_redraw()


func is_fully_charged() -> bool:
	return _active and _charge >= 1.0


func get_charge() -> float:
	return _charge


func set_facing(facing_right: bool) -> void:
	_facing_right = facing_right


func _process(delta: float) -> void:
	_time += delta
	if _active:
		_visibility = minf(1.0, _visibility + delta / FADE_IN_TIME)
		var previous_charge := _charge
		var charge_limit := 1.0
		var character := get_parent()
		if character and character.has_method("get_magic_chant_progress_limit"):
			charge_limit = character.get_magic_chant_progress_limit()
		# 正常速度推进，但绝不越过当前实际 MP 可承担的进度。
		# MP 不足时停在上限；自然恢复提高上限后，进度会自动继续。
		_charge = minf(charge_limit, _charge + delta / CHARGE_TIME)
		if not is_equal_approx(previous_charge, _charge):
			charge_changed.emit(_charge)
	else:
		_visibility = maxf(0.0, _visibility - delta / FADE_OUT_TIME)
		if _visibility <= 0.0:
			_charge = 0.0
			visible = false
			set_process(false)
	queue_redraw()


func _build_motes() -> void:
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE
	for i in mote_count:
		_motes.append({
			"phase": rng.randf(),
			"angle": rng.randf_range(0.0, TAU_F),
			"radius": rng.randf_range(72.0, 155.0),
			"height": rng.randf_range(-88.0, 72.0),
			"speed": rng.randf_range(0.34, 0.66),
			"size": rng.randf_range(1.2, 3.2),
			"curl": rng.randf_range(-1.0, 1.0),
		})


func _draw() -> void:
	if _visibility <= 0.001:
		return

	var alpha := _visibility * intensity
	var hand := _get_hand_position()
	_draw_ground_circle(alpha)
	_draw_body_aura(alpha)
	_draw_converging_motes(hand, alpha)
	_draw_hand_focus(hand, alpha)
	_draw_charge_bar(alpha)


func _get_hand_position() -> Vector2:
	return Vector2(hand_offset_right.x if _facing_right else -hand_offset_right.x, hand_offset_right.y)


func _draw_ground_circle(alpha: float) -> void:
	var pulse := 1.0 + sin(_time * 2.4) * 0.035
	var appear := EffectTools.ease_out(_visibility)
	# 压扁圆环，制造位于地面的透视魔法阵。
	# 透视方向保持固定；只有各层线条和符文在法阵平面内自转。
	draw_set_transform(ground_offset, 0.0, Vector2(pulse * appear, 0.30 * pulse * appear))
	_draw_arc_segments(Vector2.ZERO, 108.0, _time * 0.7, 0.58, 10, EffectTools.with_alpha(magic_color, alpha * 0.36), 2.0)
	_draw_arc_segments(Vector2.ZERO, 82.0, -_time * 1.05, 0.42, 8, EffectTools.with_alpha(highlight_color, alpha * 0.30), 1.4)
	draw_arc(Vector2.ZERO, 58.0, 0.0, TAU_F, 64, EffectTools.with_alpha(magic_color, alpha * 0.16), 1.0, true)

	# 环上的符文刻度；粗细交替，比占位文字更适合之后替换为符文 PNG。
	for i in 16:
		var angle := TAU_F * float(i) / 16.0 - _time * 0.32
		var inner := 91.0 if i % 2 == 0 else 96.0
		var outer := 104.0 if i % 2 == 0 else 101.0
		var a := Vector2.from_angle(angle) * inner
		var b := Vector2.from_angle(angle) * outer
		draw_line(a, b, EffectTools.with_alpha(highlight_color, alpha * (0.34 if i % 2 == 0 else 0.20)), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body_aura(alpha: float) -> void:
	var breathe := 1.0 + sin(_time * 2.0) * 0.06
	var center := body_center_offset

	# 三层柔和光晕。无贴图阶段用多层透明圆模拟径向渐变。
	for i in range(5, 0, -1):
		var radius := (34.0 + i * 12.0) * breathe
		var layer_alpha := alpha * 0.012 * float(6 - i) * (0.45 + _charge * 0.55)
		draw_circle(center, radius, EffectTools.with_alpha(magic_color, layer_alpha), true, -1.0, true)

	# 绕身体旋转的断续弧线。
	_draw_arc_segments(center, 67.0 * breathe, _time * 0.85, 0.34, 7, EffectTools.with_alpha(magic_color, alpha * 0.23), 1.6)
	_draw_arc_segments(center, 83.0 * breathe, -_time * 0.55, 0.20, 5, EffectTools.with_alpha(highlight_color, alpha * 0.14), 1.0)

	# 缓慢上升的火花。
	for i in 12:
		var phase := fposmod(float(i) / 12.0 + _time * (0.10 + float(i % 3) * 0.018), 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (43.0 + sin(_time * 1.7 + i * 2.1) * 23.0) * (0.75 + phase * 0.25)
		var y := 78.0 - phase * 184.0
		var spark_alpha := sin(phase * PI) * alpha * 0.62
		var p := center + Vector2(x, y)
		draw_circle(p, 1.0 + float(i % 3) * 0.55, EffectTools.with_alpha(highlight_color, spark_alpha), true, -1.0, true)


func _draw_converging_motes(hand: Vector2, alpha: float) -> void:
	for i in _motes.size():
		var mote: Dictionary = _motes[i]
		var travel: float = fposmod(float(mote.phase) + _time * float(mote.speed), 1.0)
		var t := EffectTools.smoothstep(0.0, 1.0, travel)
		var angle: float = float(mote.angle) + _time * (0.32 + float(mote.curl) * 0.22)
		var source := body_center_offset + Vector2(cos(angle) * float(mote.radius), float(mote.height) + sin(angle) * 25.0)
		# 二次曲线制造旋涡，而不是直线吸入。
		var tangent := Vector2(-(hand - source).y, (hand - source).x).normalized()
		var control := source.lerp(hand, 0.55) + tangent * float(mote.curl) * 42.0 * (1.0 - t)
		var position := EffectTools.quadratic_bezier(source, control, hand, t)
		var previous_t := maxf(0.0, t - 0.055)
		var previous := EffectTools.quadratic_bezier(source, control, hand, previous_t)
		var mote_alpha := sin(travel * PI) * alpha * (0.38 + _charge * 0.45)
		var width: float = float(mote.size)
		draw_line(previous, position, EffectTools.with_alpha(magic_color, mote_alpha * 0.45), width * 1.8, true)
		draw_line(previous.lerp(position, 0.45), position, EffectTools.with_alpha(highlight_color, mote_alpha), width * 0.65, true)
		draw_circle(position, width * 0.75, EffectTools.with_alpha(highlight_color, mote_alpha), true, -1.0, true)


func _draw_hand_focus(hand: Vector2, alpha: float) -> void:
	var pulse := 1.0 + sin(_time * 7.0) * 0.09
	var power := (0.55 + _charge * 0.45) * pulse

	# 手心能量核与外层光晕。
	for i in range(6, 0, -1):
		var r := (7.0 + float(i) * 4.2) * power
		draw_circle(hand, r, EffectTools.with_alpha(magic_color, alpha * 0.022 * float(7 - i)), true, -1.0, true)
	draw_circle(hand, 7.0 * power, EffectTools.with_alpha(highlight_color, alpha * 0.88), true, -1.0, true)
	draw_circle(hand, 3.0 * power, EffectTools.with_alpha(Color.WHITE, alpha), true, -1.0, true)

	# 交错旋转的小型聚能环。
	_draw_arc_segments(hand, 21.0 * power, _time * 2.6, 0.28, 5, EffectTools.with_alpha(highlight_color, alpha * 0.72), 1.8)
	_draw_arc_segments(hand, 29.0 * power, -_time * 1.8, 0.18, 4, EffectTools.with_alpha(magic_color, alpha * 0.48), 1.2)

	# 星芒：正式素材可直接在此换成 Star 纹理。
	var ray := 16.0 + _charge * 11.0 + sin(_time * 8.0) * 2.0
	draw_line(hand - Vector2(ray, 0.0), hand + Vector2(ray, 0.0), EffectTools.with_alpha(highlight_color, alpha * 0.42), 1.0, true)
	draw_line(hand - Vector2(0.0, ray), hand + Vector2(0.0, ray), EffectTools.with_alpha(highlight_color, alpha * 0.42), 1.0, true)


func _draw_charge_bar(alpha: float) -> void:
	# 进度条嵌入角色上方的魔法刻度框；满蓄力时会产生呼吸高亮。
	var left := Vector2(-62.0, -128.0)
	var right := Vector2(62.0, -128.0)
	var fill_right := left.lerp(right, _charge)
	var full_pulse := (0.65 + sin(_time * 9.0) * 0.25) if _charge >= 1.0 else 0.0

	draw_line(left, right, EffectTools.with_alpha(magic_color, alpha * 0.20), 10.0, true)
	draw_line(left, right, EffectTools.with_alpha(Color(0.01, 0.04, 0.08), alpha * 0.75), 6.0, true)
	if _charge > 0.001:
		draw_line(left, fill_right, EffectTools.with_alpha(magic_color, alpha * (0.48 + full_pulse * 0.20)), 7.0, true)
		draw_line(left, fill_right, EffectTools.with_alpha(highlight_color, alpha * (0.75 + full_pulse * 0.25)), 2.2, true)

	# 五段刻度与两端菱形，使它看起来属于魔法阵而不是普通 UI。
	for i in 6:
		var x := lerpf(left.x, right.x, float(i) / 5.0)
		var tick_alpha := 0.68 if _charge + 0.001 >= float(i) / 5.0 else 0.20
		draw_line(Vector2(x, left.y - 5.0), Vector2(x, left.y + 5.0), EffectTools.with_alpha(highlight_color, alpha * tick_alpha), 1.2, true)
	_draw_diamond(left - Vector2(7.0, 0.0), 5.0, EffectTools.with_alpha(magic_color, alpha * 0.55))
	_draw_diamond(right + Vector2(7.0, 0.0), 5.0 + full_pulse * 2.0, EffectTools.with_alpha(highlight_color, alpha * (0.55 + full_pulse)))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
		center + Vector2(0.0, -radius),
	])
	draw_polyline(points, color, 1.5, true)


func _draw_arc_segments(center: Vector2, radius: float, rotation: float, coverage: float, count: int, color: Color, width: float) -> void:
	var step := TAU_F / float(count)
	var arc_length := step * coverage
	for i in count:
		var start := rotation + float(i) * step
		draw_arc(center, radius, start, start + arc_length, 8, color, width, true)
