extends RefCounted
## Bounded first actual region witness on the shared module curve. Not an
## analytic root. Unknown grazing/order certificates hold; no epsilon motion.
const Motion = preload("res://scripts/common_motion_v1.gd")
const MAX_NODES = 4096
const MAX_DEPTH = 48
const U32 = 0.000000059604644775390625

static func inside(position: Vector2, kind: String, route: Dictionary) -> bool:
	match kind:
		"receiver": return position.x >= route.distance and position.distance_to(Vector2(route.distance, route.destination_y)) <= route.delivery_radius
		"left": return position.x < -35.0
		"right": return position.x > route.distance + 30.0
		"top": return position.y < -route.boundary_y
		"bottom": return position.y > route.boundary_y
	return false

static func first(curve: Dictionary, lever: Vector2, kind: String, route: Dictionary, dt: float) -> Dictionary:
	var origin: float = curve.chrono_motion_start_fraction
	var duration: float = (1.0 - origin) * dt
	var initial = _sample(curve, lever, origin, dt)
	if inside(initial.position, kind, route): return _hit(origin, origin, initial)
	if duration <= 0.0: return {"state": "miss"}
	var start = Motion.pose(curve.chrono_motion_anchor, 0.0)
	var anchor: Dictionary = curve.get("chrono_motion_anchor", curve)
	var acceleration: Vector2 = anchor.get("acceleration", Vector2.ZERO)
	var alpha: float = anchor.get("alpha", 0.0)
	var angular = absf(start.angular_velocity) + absf(alpha) * duration
	var speed = _norm(start.velocity) + _norm(acceleration) * duration + _norm(lever) * angular
	if speed == 0.0: return {"state": "miss"}
	var rotating = lever != Vector2.ZERO and (start.angular_velocity != 0.0 or alpha != 0.0)
	var fixed_x = not rotating and start.velocity.x == 0.0 and acceleration.x == 0.0
	var fixed_y = not rotating and start.velocity.y == 0.0 and acceleration.y == 0.0
	# Equality on a structurally constant strict boundary is NOT an exit.
	if kind in ["left", "right"] and fixed_x: return {"state": "miss"}
	if kind in ["top", "bottom"] and fixed_y: return {"state": "miss"}
	if kind == "receiver" and fixed_x and initial.position.x < route.distance: return {"state": "miss"}
	# Native Godot4.6 binary32 operation enclosure. Position coefficients are
	# exact represented inputs; do not charge a global-coordinate32u error for
	# every zero product/add. See the explicit native-libm assumption in docs.
	var angle_bound = absf(anchor.angle) + absf(anchor.angular_velocity) * duration + 0.5 * absf(alpha) * duration * duration
	var lever_norm = _norm(lever)
	var ex = _coordinate_rounding(anchor.position.x, anchor.velocity.x, acceleration.x, duration, lever_norm, angle_bound)
	var ey = _coordinate_rounding(anchor.position.y, anchor.velocity.y, acceleration.y, duration, lever_norm, angle_bound)
	var rounding = {"x":2.0 * ex, "y":2.0 * ey, "radius":2.0 * sqrt(ex * ex + ey * ey)}
	speed /= 1.0 - 16.0 * U32
	var stack: Array = [{"a": origin, "b": 1.0, "depth": 0}]
	var uncertain = -1.0; var nodes = 0
	while not stack.is_empty():
		nodes += 1
		if nodes > MAX_NODES: return {"state": "unresolved", "reason": "receiver_node_budget", "at": uncertain if uncertain >= 0.0 else stack.back().a}
		var item: Dictionary = stack.pop_back()
		var low: float = item.a; var high: float = item.b; var middle = (low + high) * 0.5
		var sample = _sample(curve, lever, middle, dt)
		var reach = speed * dt * (high - low) * 0.5
		if _outside_bound(sample.position, reach, rounding, kind, route, fixed_x, fixed_y): continue
		var left = _sample(curve, lever, low, dt)
		if inside(left.position, kind, route):
			var from = uncertain if uncertain >= 0.0 else low
			return _hit(low, from, left) if speed * dt * (low - from) <= Motion.POSITION_TOLERANCE else {"state": "unresolved", "reason": "receiver_earlier_root", "at": from}
		if speed * dt * (high - low) <= Motion.POSITION_TOLERANCE * 0.125 or item.depth >= MAX_DEPTH:
			var right = _sample(curve, lever, high, dt)
			var at = middle if inside(sample.position, kind, route) else (high if inside(right.position, kind, route) else -1.0)
			if at >= 0.0:
				var from = uncertain if uncertain >= 0.0 else low
				return _hit(at, from, sample if at == middle else right) if speed * dt * (at - from) <= Motion.POSITION_TOLERANCE else {"state": "unresolved", "reason": "receiver_earlier_root", "at": from}
			if uncertain < 0.0: uncertain = low
			continue
		stack.append({"a": middle, "b": high, "depth": int(item.depth) + 1})
		stack.append({"a": low, "b": middle, "depth": int(item.depth) + 1})
	return {"state": "unresolved", "reason": "receiver_grazing_certificate", "at": uncertain} if uncertain >= 0.0 else {"state": "miss"}

static func _outside_bound(p: Vector2, travel: float, rounding: Dictionary, kind: String, route: Dictionary, fixed_x: bool, _fixed_y: bool) -> bool:
	var rx: float = travel + rounding.x; var ry: float = travel + rounding.y
	match kind:
		"receiver":
			var center = Vector2(route.distance, route.destination_y)
			var dx = float(p.x) - float(center.x); var dy = float(p.y) - float(center.y)
			var distance = sqrt(dx * dx + dy * dy)
			# Actual predicate uses binary32 subtraction/products/sqrt. Enclose
			# their relative-distance error, not the distant world coordinates.
			var reach: float = travel + rounding.radius
			var geometry_error = 8.0 * U32 * (distance + reach + float(route.delivery_radius)) / (1.0 - 16.0 * U32)
			return (p.x if fixed_x else p.x + rx) < route.distance or distance - reach - geometry_error > route.delivery_radius
		"left": return p.x - rx >= -35.0
		"right": return p.x + rx <= route.distance + 30.0
		"top": return p.y - ry >= -route.boundary_y
		"bottom": return p.y + ry <= route.boundary_y
	return true

static func _coordinate_rounding(p: float, v: float, a: float, duration: float, lever: float, angle_bound: float) -> float:
	var vt = absf(v) * duration; var at = 0.5 * absf(a) * duration * duration
	var error = 0.0
	if v != 0.0 and duration != 0.0:
		error += 2.0 * U32 * vt
		error += U32 * (absf(p) + vt + error)
	if a != 0.0 and duration != 0.0:
		error += 2.0 * U32 * at
		error += U32 * (absf(p) + vt + at + error)
	if lever != 0.0:
		error += lever * ((U32 + 8.0 * 2.220446049250313e-16) * angle_bound + 8.0 * U32)
		error += U32 * (absf(p) + vt + at + lever + error)
	# Skipped zero operations retain prior error. The tiny additive term also
	# covers subnormal rounding; the multiplier encloses accumulated products.
	return (error + 1.0e-40) / (1.0 - 16.0 * U32)

static func _norm(v: Vector2) -> float:
	return sqrt(float(v.x) * float(v.x) + float(v.y) * float(v.y))

static func _hit(at: float, start: float, sample: Dictionary) -> Dictionary:
	return {"state": "hit", "fraction": at, "bracket_fraction": [start, at], "position": sample.position, "velocity": sample.velocity}

static func _sample(curve: Dictionary, lever: Vector2, fraction: float, dt: float) -> Dictionary:
	return Motion.sample(curve.chrono_motion_anchor, lever, (fraction - curve.chrono_motion_start_fraction) * dt)
