extends Control
class_name PlayerStatusHUD

## 屏幕底部背对背 HP/MP HUD。实际值由 Player 提供，本节点仅负责平滑显示。
@export var bar_width := 360.0
@export var bar_height := 24.0
@export var bottom_margin := 34.0
@export var hp_buffer_delay := 0.45
@export var hp_buffer_speed := 90.0

var player: Player
var _hp_buffer := 1.0
var _hp_delay_left := 0.0
var _effect_time := 0.0

const HP_COLOR := Color(0.93, 0.18, 0.30, 0.55)
const HP_BUFFER_COLOR := Color(1.0, 0.73, 0.30, 0.42)
const MP_COLOR := Color(0.28, 0.58, 1.0, 0.55)
const MP_BUFFER_COLOR := Color(0.69, 0.46, 1.0, 0.42)
const BACK_COLOR := Color(0.025, 0.018, 0.06, 0.16)
const GLASS_COLOR := Color(0.30, 0.20, 0.48, 0.16)
const LINE_COLOR := Color(0.86, 0.78, 1.0, 0.92)
const SOFT_GLOW_COLOR := Color(0.60, 0.42, 1.0, 0.12)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func bind(target: Player) -> void:
	player = target
	_hp_buffer = player.get_hp_ratio()
	player.hp_changed.connect(_on_hp_changed)
	player.mp_changed.connect(_on_mp_changed)
	set_process(true)
	queue_redraw()


func hide_animated() -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position:y", position.y + 60.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(self, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func show_animated() -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position:y", position.y - 60.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	set_process(true)
	queue_redraw()


func _on_hp_changed(_hp: float, _max_hp: float) -> void:
	var ratio := player.get_hp_ratio()
	if ratio < _hp_buffer:
		_hp_delay_left = hp_buffer_delay
	else:
		_hp_buffer = ratio
	queue_redraw()


func _on_mp_changed(_mp: float, _max_mp: float, _reserved: float) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not player:
		return
	_effect_time += delta
	var target := player.get_hp_ratio()
	if _hp_delay_left > 0.0:
		_hp_delay_left -= delta
	elif _hp_buffer > target:
		_hp_buffer = maxf(target, _hp_buffer - hp_buffer_speed * delta / maxf(player.max_hp, 1.0))
	# 流光、呼吸描边和能量微粒需要连续刷新，但不参与任何数值计算。
	queue_redraw()


func _draw() -> void:
	if not player:
		return
	var center_x := size.x * 0.5
	var y := size.y - bottom_margin - bar_height
	var gap := 10.0
	var effective_width := minf(bar_width, maxf(100.0, (size.x - 60.0) * 0.5))
	var hp_rect := Rect2(center_x - gap - effective_width, y, effective_width, bar_height)
	var mp_rect := Rect2(center_x + gap, y, effective_width, bar_height)
	var hp_ratio := player.get_hp_ratio()
	var mp_visible_ratio := player.get_visible_mp() / maxf(player.max_mp, 1.0)
	var mp_total_ratio := player.mp / maxf(player.max_mp, 1.0)

	# 背对背：先绘制克制的玻璃外发光，再绘制半透明底板与资源层。
	_draw_glass_back(hp_rect)
	_draw_glass_back(mp_rect)
	_draw_right_anchored_fill(hp_rect, _hp_buffer, HP_BUFFER_COLOR)
	_draw_right_anchored_fill(hp_rect, hp_ratio, HP_COLOR)
	_draw_left_anchored_fill(mp_rect, mp_total_ratio, MP_BUFFER_COLOR)
	_draw_left_anchored_fill(mp_rect, mp_visible_ratio, MP_COLOR)
	_draw_hp_vital_effect(hp_rect, hp_ratio)
	_draw_fill_highlights(mp_rect, mp_visible_ratio, false, MP_COLOR)
	_draw_mana_motes(mp_rect, mp_visible_ratio)
	var low_hp_pulse := (0.5 + 0.5 * sin(_effect_time * 7.0)) if hp_ratio <= 0.25 else 0.0
	draw_rect(hp_rect.grow(2.0 + low_hp_pulse * 2.0), Color(1.0, 0.20, 0.32, 0.22 * low_hp_pulse), false, 2.0)
	draw_rect(hp_rect, LINE_COLOR, false, 1.6)
	draw_rect(mp_rect, LINE_COLOR, false, 1.6)
	draw_line(hp_rect.position + Vector2(3, 3), Vector2(hp_rect.end.x - 3, hp_rect.position.y + 3), Color(1, 1, 1, 0.26), 1.0)
	draw_line(mp_rect.position + Vector2(3, 3), Vector2(mp_rect.end.x - 3, mp_rect.position.y + 3), Color(1, 1, 1, 0.26), 1.0)

	# 中央菱形、外侧尖角与分段刻度。
	var c := Vector2(center_x, y + bar_height * 0.5)
	var core_pulse := 1.0 + sin(_effect_time * 2.6) * 0.08
	var diamond := PackedVector2Array([c + Vector2(0, -17) * core_pulse, c + Vector2(9, 0) * core_pulse, c + Vector2(0, 17) * core_pulse, c + Vector2(-9, 0) * core_pulse])
	draw_circle(c, 19.0 + sin(_effect_time * 2.6) * 2.0, SOFT_GLOW_COLOR, true)
	draw_colored_polygon(diamond, BACK_COLOR)
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), LINE_COLOR, 2.0, true)
	for i in range(1, 6):
		var offset := effective_width * float(i) / 6.0
		draw_line(Vector2(center_x - gap - offset, y + bar_height - 5), Vector2(center_x - gap - offset, y + bar_height), LINE_COLOR * Color(1, 1, 1, 0.45), 1.0)
		draw_line(Vector2(center_x + gap + offset, y + bar_height - 5), Vector2(center_x + gap + offset, y + bar_height), LINE_COLOR * Color(1, 1, 1, 0.45), 1.0)
	_draw_end_cap(Vector2(hp_rect.position.x, c.y), -1.0)
	_draw_end_cap(Vector2(mp_rect.end.x, c.y), 1.0)

	var font := ThemeDB.fallback_font
	var font_size := 18
	var hp_text := "HP %d/%d" % [roundi(player.hp), roundi(player.max_hp)]
	var mp_text := "MP %d/%d" % [roundi(player.get_visible_mp()), roundi(player.max_mp)]
	draw_string(font, Vector2(hp_rect.end.x - 118, y - 7), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.92, 0.95))
	draw_string(font, Vector2(mp_rect.position.x + 8, y - 7), mp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.90, 0.94, 1))


func _draw_glass_back(rect: Rect2) -> void:
	# 多层低透明描边模拟柔和外发光，避免使用昂贵的全屏模糊。
	for i in range(3, 0, -1):
		draw_rect(rect.grow(float(i) * 3.0), Color(SOFT_GLOW_COLOR, SOFT_GLOW_COLOR.a / float(i)), false, float(i) * 2.0)
	draw_rect(rect, BACK_COLOR, true)
	draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4)), GLASS_COLOR, true)


func _draw_hp_vital_effect(rect: Rect2, ratio: float) -> void:
	var fill_width := rect.size.x * clampf(ratio, 0.0, 1.0)
	if fill_width <= 1.0:
		return
	var fill_left := rect.end.x - fill_width
	# HP 不使用横向扫光，改为整段同步呼吸，左右不会产生错位感。
	var breathe := 0.045 + (0.025 + (1.0 - ratio) * 0.055) * (0.5 + 0.5 * sin(_effect_time * (2.8 + (1.0 - ratio) * 2.2)))
	draw_rect(Rect2(fill_left, rect.position.y + 2.0, fill_width, rect.size.y * 0.30), Color(1, 1, 1, 0.13), true)
	draw_rect(Rect2(fill_left, rect.position.y + 2.0, fill_width, rect.size.y - 4.0), Color(1.0, 0.48, 0.56, breathe), true)
	# 实际生命值端点做轻微竖向脉冲，受伤后位置变化也更容易被察觉。
	var edge_alpha := 0.34 + 0.20 * sin(_effect_time * 4.2)
	draw_line(Vector2(fill_left, rect.position.y + 3.0), Vector2(fill_left, rect.end.y - 3.0), Color(1.0, 0.78, 0.82, edge_alpha), 2.0, true)


func _draw_fill_highlights(rect: Rect2, ratio: float, right_anchored: bool, color: Color) -> void:
	var fill_width := rect.size.x * clampf(ratio, 0.0, 1.0)
	if fill_width <= 1.0:
		return
	var fill_left := rect.end.x - fill_width if right_anchored else rect.position.x
	# 玻璃纵向反光。
	draw_rect(Rect2(fill_left, rect.position.y + 2.0, fill_width, rect.size.y * 0.30), Color(1, 1, 1, 0.15), true)
	# 一道缓慢扫过填充区域的窄流光，仅用于表现，不驱动数值。
	var travel := fposmod(_effect_time * 78.0, fill_width + 46.0) - 23.0
	var shimmer_x := fill_left + travel
	var shimmer := Rect2(shimmer_x, rect.position.y + 2.0, 18.0, rect.size.y - 4.0)
	var clipped_left := maxf(shimmer.position.x, fill_left)
	var clipped_right := minf(shimmer.end.x, fill_left + fill_width)
	if clipped_right > clipped_left:
		draw_rect(Rect2(clipped_left, shimmer.position.y, clipped_right - clipped_left, shimmer.size.y), Color(color.lightened(0.65), 0.20), true)


func _draw_mana_motes(rect: Rect2, ratio: float) -> void:
	var fill_width := rect.size.x * clampf(ratio, 0.0, 1.0)
	if fill_width < 8.0:
		return
	for i in 7:
		var phase := fposmod(float(i) / 7.0 + _effect_time * (0.16 + float(i % 3) * 0.025), 1.0)
		var x := rect.position.x + phase * fill_width
		var y := rect.position.y + rect.size.y * (0.28 + 0.44 * (0.5 + 0.5 * sin(_effect_time * 2.1 + float(i) * 1.7)))
		var alpha := sin(phase * PI) * 0.55
		draw_circle(Vector2(x, y), 1.0 + float(i % 2), Color(0.85, 0.92, 1.0, alpha), true)


func _draw_right_anchored_fill(rect: Rect2, ratio: float, color: Color) -> void:
	var width := rect.size.x * clampf(ratio, 0.0, 1.0)
	draw_rect(Rect2(rect.end.x - width, rect.position.y, width, rect.size.y), color, true)


func _draw_left_anchored_fill(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)), color, true)


func _draw_end_cap(point: Vector2, direction: float) -> void:
	var points := PackedVector2Array([
		point + Vector2(direction * 15, -bar_height * 0.5),
		point + Vector2(direction * 25, 0),
		point + Vector2(direction * 15, bar_height * 0.5),
		point,
	])
	draw_colored_polygon(points, BACK_COLOR)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), LINE_COLOR, 2.0, true)
