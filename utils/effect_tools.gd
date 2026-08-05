extends RefCounted
class_name EffectTools

## 程序化 2D 特效共用的无状态数学辅助函数。


static func smoothstep(from: float, to: float, value: float) -> float:
	if is_equal_approx(from, to):
		return 0.0 if value < from else 1.0
	var x := clampf((value - from) / (to - from), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func ease_out(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func quadratic_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var x := clampf(t, 0.0, 1.0)
	var ab := a.lerp(b, x)
	var bc := b.lerp(c, x)
	return ab.lerp(bc, x)


static func with_alpha(base: Color, alpha: float) -> Color:
	return Color(base.r, base.g, base.b, clampf(alpha, 0.0, 1.0))
