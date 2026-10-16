extends RefCounted
## Conservative certified-inside windows on the same authoritative motion curve.
## Boundary uncertainty is retained as lost-cutting-duration, never paid damage.
const Motion = preload("res://scripts/common_motion_v1.gd")
const MAX_NODES = 4096
const MAX_DEPTH = 24
const ROUND_UNIT = 0.000000059604644775390625 # binary32 unit roundoff

static func plan(body: Dictionary, module_lever: Vector2, local_angle: float, scale: float, obstacle: Dictionary, radius: float, duration: float) -> Dictionary:
	if not is_finite(duration) or duration < 0.0 or not is_finite(radius) or radius <= 0.0 or not is_finite(scale) or scale <= 0.0:
		return {"ok": false, "error": "invalid_drill_curve"}
	var head_lever = module_lever + Vector2.RIGHT.rotated(local_angle) * 0.30 * scale
	var context = {"body": body, "obstacle": obstacle, "module": module_lever, "head": head_lever, "angle": local_angle, "radius": radius + 0.18 * scale}
	var windows: Array = []; var unknown: Array = []; var boundaries: Array = []
	if duration == 0.0: return {"ok": true, "windows": windows, "unknown": unknown, "boundaries": boundaries, "nodes": 0}
	if _static(body) and _static(obstacle):
		if _sample(context, 0.0).active: windows.append([0.0, duration])
		return {"ok": true, "windows": windows, "unknown": unknown, "boundaries": boundaries, "nodes": 1}
	var stack: Array = [{"a": 0.0, "b": duration, "depth": 0}]; var nodes = 0
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back(); var a: float = item.a; var b: float = item.b
		nodes += 1
		if nodes > MAX_NODES:
			unknown.append([a, b])
			for remaining in stack: unknown.append([remaining.a, remaining.b])
			break
		var certificate = _certificate(context, a, b)
		if not certificate.ok: return certificate
		if certificate.state == 1: windows.append([a, b]); continue
		if certificate.state == 0: continue
		var left = _point_state(_sample(context, a), certificate.eg, certificate.ef)
		var right = _point_state(_sample(context, b), certificate.eg, certificate.ef)
		if certificate.monotone and left >= 0 and right >= 0:
			if left == right:
				if left == 1: windows.append([a, b])
				continue
			var root = _root(context, a, b, left, right, certificate.eg, certificate.ef)
			if left == 1 and root.a > a: windows.append([a, root.a])
			if right == 1 and b > root.b: windows.append([root.b, b])
			if root.b > root.a: unknown.append([root.a, root.b])
			boundaries.append({"a": root.a, "b": root.b, "before": left, "after": right,
				"witness_a": _sample(context, root.a), "witness_b": _sample(context, root.b)})
			continue
		# Near-tangent/rounding-band intervals with no possible certified inside
		# point earn zero cutting. Ordinary grazing never freezes hull CCD.
		if certificate.g_upper <= certificate.eg or certificate.f_upper <= certificate.ef:
			unknown.append([a, b]); continue
		var mid = (a + b) * 0.5
		if item.depth >= MAX_DEPTH or mid == a or mid == b:
			unknown.append([a, b]); continue
		stack.append({"a": mid, "b": b, "depth": item.depth + 1})
		stack.append({"a": a, "b": mid, "depth": item.depth + 1})
	windows = _merge(windows); unknown = _merge(unknown)
	if windows.size() > 64 or unknown.size() > 64 or boundaries.size() > 64:
		# This is a conservative cutting capability limit, not a hull-contact
		# skip or a timestep hold. Report the full lost-duration upper bound.
		return {"ok": true, "windows": [], "unknown": [[0.0, duration]], "boundaries": [], "nodes": nodes, "diagnostic": "drill_window_output_budget"}
	return {"ok": true, "windows": windows, "unknown": unknown, "boundaries": boundaries, "nodes": nodes}

static func _static(body: Dictionary) -> bool:
	return body.velocity == Vector2.ZERO and body.get("acceleration", Vector2.ZERO) == Vector2.ZERO and body.angular_velocity == 0.0 and body.get("alpha", 0.0) == 0.0

static func _dot(a: Vector2, b: Vector2) -> float:
	return float(a.x) * float(b.x) + float(a.y) * float(b.y)

static func _sample(c: Dictionary, seconds: float) -> Dictionary:
	var head = Motion.sample(c.body, c.head, seconds); var module = Motion.sample(c.body, c.module, seconds)
	var obstacle = Motion.sample(c.obstacle, Vector2.ZERO, seconds); var pose = Motion.pose(c.body, seconds)
	var direction = Vector2.RIGHT.rotated(pose.angle + c.angle)
	var q: Vector2 = obstacle.position - head.position; var qv: Vector2 = obstacle.velocity - head.velocity
	var m: Vector2 = obstacle.position - module.position; var mv: Vector2 = obstacle.velocity - module.velocity
	var g: float = c.radius * c.radius - _dot(q, q); var f = _dot(m, direction)
	return {"g": g, "f": f, "gp": -2.0 * _dot(q, qv),
		"fp": _dot(mv, direction) + pose.angular_velocity * _dot(m, Vector2(-direction.y, direction.x)),
		"q": q, "m": m, "active": g >= 0.0 and f > 0.0}

static func _length(v: Vector2) -> float:
	return sqrt(_dot(v, v))

static func _canonical(body: Dictionary) -> Dictionary:
	return body.get("chrono_motion_anchor", body)

static func _time(body: Dictionary, t: float) -> float:
	return float(body.get("chrono_motion_offset", 0.0)) + t

static func _rounding(body: Dictionary, lever: Vector2, a: float, b: float, extra_angle: float = 0.0) -> Dictionary:
	var curve = _canonical(body)
	var age = maxf(absf(_time(body, a)), absf(_time(body, b)))
	var acceleration: Vector2 = curve.get("acceleration", Vector2.ZERO)
	var position_operands = _length(curve.position) + _length(curve.velocity) * age + 0.5 * _length(acceleration) * age * age
	var velocity_operands = _length(curve.velocity) + _length(acceleration) * age
	var angle_operands = absf(curve.angle) + absf(curve.angular_velocity) * age + 0.5 * absf(curve.get("alpha", 0.0)) * age * age
	var omega = absf(curve.angular_velocity) + absf(curve.get("alpha", 0.0)) * age
	# Follow ALL canonical operands, including cancellation and anchor age.
	# The 32u operation enclosure covers binary32 products/sums, conversion of
	# rotation angle, and trig evaluation; scalar arithmetic is binary64.
	var factor = 32.0 * ROUND_UNIT
	return {"position": factor * (1.0 + position_operands + _length(lever) * (1.0 + angle_operands)),
		"velocity": factor * (1.0 + velocity_operands + _length(lever) * omega * (1.0 + angle_operands)),
		"direction": minf(2.0, factor * (1.0 + angle_operands + absf(extra_angle)))}

static func _velocity(body: Dictionary, t: float) -> Array:
	var curve = _canonical(body); var at = _time(body, t)
	var acc: Vector2 = curve.get("acceleration", Vector2.ZERO)
	return [float(curve.velocity.x) + float(acc.x) * at, float(curve.velocity.y) + float(acc.y) * at]

static func _relative_bounds(c: Dictionary, lever: Vector2, a: float, b: float) -> Dictionary:
	var curve = _canonical(c.body); var hazard = _canonical(c.obstacle)
	var alpha: float = curve.get("alpha", 0.0)
	var omega = maxf(absf(curve.angular_velocity + alpha * _time(c.body, a)), absf(curve.angular_velocity + alpha * _time(c.body, b)))
	var speed = 0.0
	for t in [a, b]:
		var va = _velocity(c.body, t); var vb = _velocity(c.obstacle, t)
		var dx: float = vb[0] - va[0]; var dy: float = vb[1] - va[1]
		speed = maxf(speed, sqrt(dx * dx + dy * dy))
	var aa: Vector2 = curve.get("acceleration", Vector2.ZERO); var ab: Vector2 = hazard.get("acceleration", Vector2.ZERO)
	var ax = float(ab.x) - float(aa.x); var ay = float(ab.y) - float(aa.y)
	# Inflate final double arithmetic, never a downward-rounded Vector2 norm.
	var guard = 1.00000000000001
	return {"v": (speed + _length(lever) * omega) * guard,
		"a": (sqrt(ax * ax + ay * ay) + _length(lever) * (absf(alpha) + omega * omega)) * guard, "omega": omega * guard}

static func _certificate(c: Dictionary, a: float, b: float) -> Dictionary:
	var h = (b - a) * 0.5; var sample = _sample(c, (a + b) * 0.5)
	var head = _relative_bounds(c, c.head, a, b); var module = _relative_bounds(c, c.module, a, b)
	var er_head = _rounding(c.body, c.head, a, b); var er_module = _rounding(c.body, c.module, a, b, c.angle)
	var er_hazard = _rounding(c.obstacle, Vector2.ZERO, a, b)
	var eq: float = er_head.position + er_hazard.position; var em: float = er_module.position + er_hazard.position
	var evq: float = er_head.velocity + er_hazard.velocity; var evm: float = er_module.velocity + er_hazard.velocity
	var q = _length(sample.q) + head.v * h + eq; var m = _length(sample.m) + module.v * h + em
	var bg: float = 2.0 * (head.v * head.v + q * head.a)
	var bf: float = module.a + 2.0 * module.omega * module.v + (absf(_canonical(c.body).get("alpha", 0.0)) + module.omega * module.omega) * m
	var eg: float = 2.0 * (2.0 * q * eq + eq * eq)
	var ef: float = 2.0 * (em * (1.0 + er_module.direction) + m * er_module.direction)
	var egp: float = 2.0 * (q * evq + head.v * eq + eq * evq)
	var efp: float = evm * (1.0 + er_module.direction) + module.v * er_module.direction + module.omega * ef
	var gr: float = (absf(sample.gp) + egp) * h + bg * h * h * 0.5
	var fr: float = (absf(sample.fp) + efp) * h + bf * h * h * 0.5
	for value in [sample.g, sample.f, eg, ef, bg, bf, gr, fr]:
		if not is_finite(value): return {"ok": false, "error": "nonfinite_drill_certificate"}
	var gl: float = sample.g - gr - eg; var gh: float = sample.g + gr + eg
	var fl: float = sample.f - fr - ef; var fh: float = sample.f + fr + ef
	var state = 1 if gl >= 0.0 and fl > 0.0 else (0 if gh < 0.0 or fh <= 0.0 else -1)
	var gs = 1 if sample.gp - bg * h - egp > 0.0 else (-1 if sample.gp + bg * h + egp < 0.0 else 0)
	var fs = 1 if sample.fp - bf * h - efp > 0.0 else (-1 if sample.fp + bf * h + efp < 0.0 else 0)
	var monotone = (gs != 0 and fl > 0.0) or (fs != 0 and gl >= 0.0) or (gs != 0 and gs == fs)
	return {"ok": true, "state": state, "monotone": monotone, "eg": eg, "ef": ef,
		"g_upper": sample.g + gr, "f_upper": sample.f + fr}

static func _point_state(sample: Dictionary, eg: float, ef: float) -> int:
	if sample.g - eg >= 0.0 and sample.f - ef > 0.0: return 1
	if sample.g + eg < 0.0 or sample.f + ef <= 0.0: return 0
	return -1

static func _root(c: Dictionary, a: float, b: float, initial: int, next: int, eg: float, ef: float) -> Dictionary:
	var left = a; var right = b
	for iteration in range(64):
		var mid = (left + right) * 0.5
		if mid == left or mid == right: break
		var state = _point_state(_sample(c, mid), eg, ef)
		if state == initial: left = mid
		elif state == next: right = mid
		else:
			var uncertain_left = mid; var uncertain_right = mid
			for trim in range(48):
				var point = (left + uncertain_left) * 0.5
				if point == left or point == uncertain_left: break
				if _point_state(_sample(c, point), eg, ef) == initial: left = point
				else: uncertain_left = point
			for trim in range(48):
				var point = (uncertain_right + right) * 0.5
				if point == uncertain_right or point == right: break
				if _point_state(_sample(c, point), eg, ef) == next: right = point
				else: uncertain_right = point
			break
	return {"a": left, "b": right}

static func _merge(intervals: Array) -> Array:
	intervals.sort_custom(func(a, b): return a[0] < b[0])
	var result: Array = []
	for interval in intervals:
		if interval[1] <= interval[0]: continue
		if not result.is_empty() and interval[0] <= result.back()[1]: result.back()[1] = maxf(result.back()[1], interval[1])
		else: result.append(interval.duplicate())
	return result
