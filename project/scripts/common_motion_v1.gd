extends RefCounted
## One evaluator for real module CCD and authoritative body advancement.
## Finite search may HOLD. Conservative envelopes never authorize a hit.
const MAX_NODES = 8192
const MAX_DEPTH = 48
const POSITION_TOLERANCE = 0.0005
const NUMERIC_PADDING = 0.0000001

static func pose(body: Dictionary, seconds: float) -> Dictionary:
	# Opt-in only for the private drill owner: all queries and advancement use
	# one canonical local curve until a real impulse/force/component change.
	# Legacy owners have no anchor fields and execute the identical old path.
	if body.has("chrono_motion_anchor"):
		return pose(body.chrono_motion_anchor, float(body.chrono_motion_offset) + seconds)
	var acceleration: Vector2 = body.get("acceleration", Vector2.ZERO)
	var alpha: float = body.get("alpha", 0.0)
	return {"position": body.position + body.velocity * seconds + acceleration * (0.5 * seconds * seconds),
		"velocity": body.velocity + acceleration * seconds,
		"angle": body.angle + body.angular_velocity * seconds + 0.5 * alpha * seconds * seconds,
		"angular_velocity": body.angular_velocity + alpha * seconds}

static func sample(body: Dictionary, lever: Vector2, seconds: float) -> Dictionary:
	var state = pose(body, seconds)
	var arm = lever.rotated(state.angle)
	return {"position": state.position + arm,
		"velocity": state.velocity + Vector2(-arm.y, arm.x) * state.angular_velocity}

static func advance(body: Dictionary, seconds: float) -> void:
	var state = pose(body, seconds)
	for key in ["position", "velocity", "angle", "angular_velocity"]: body[key] = state[key]
	if body.has("chrono_motion_anchor"): body.chrono_motion_offset += seconds

static func _bounds(body: Dictionary, lever: Vector2, seconds: float) -> Dictionary:
	var acceleration: Vector2 = body.get("acceleration", Vector2.ZERO)
	var angular = absf(body.angular_velocity) + absf(body.get("alpha", 0.0)) * seconds
	return {"speed": body.velocity.length() + acceleration.length() * seconds + lever.length() * angular,
		"accel": acceleration.length() + lever.length() * (absf(body.get("alpha", 0.0)) + angular * angular)}

static func _relative(a: Dictionary, arm_a: Vector2, b: Dictionary, arm_b: Vector2, seconds: float) -> Dictionary:
	var first = sample(a, arm_a, seconds); var second = sample(b, arm_b, seconds)
	return {"position": first.position - second.position, "velocity": first.velocity - second.velocity}

static func _inside(value: Dictionary, radius: float) -> bool:
	return value.position.length_squared() <= radius * radius and value.position.dot(value.velocity) < 0.0

static func sweep(a: Dictionary, arm_a: Vector2, b: Dictionary, arm_b: Vector2, radius: float, seconds: float) -> Dictionary:
	if seconds < 0.0 or radius <= 0.0 or not is_finite(seconds) or not is_finite(radius): return {"state": "invalid"}
	var first = _relative(a, arm_a, b, arm_b, 0.0)
	if _inside(first, radius): return _hit(0.0, first, 0.0)
	if seconds == 0.0: return {"state": "miss"}
	var ba = _bounds(a, arm_a, seconds); var bb = _bounds(b, arm_b, seconds)
	var speed: float = ba.speed + bb.speed; var accel: float = ba.accel + bb.accel
	if speed == 0.0: return {"state": "miss"}
	# Exact proof for initially overlapping, separating linear centers.
	if accel == 0.0 and first.position.length_squared() <= radius * radius and first.position.dot(first.velocity) >= 0.0:
		return {"state": "miss"}
	var stack: Array = [{"a": 0.0, "b": seconds, "depth": 0}]
	var nodes = 0; var unresolved = -1.0
	while not stack.is_empty():
		nodes += 1
		if nodes > MAX_NODES: return {"state": "unresolved", "reason": "node_budget", "nodes": nodes, "at": minf(unresolved, stack.back().a) if unresolved >= 0.0 else float(stack.back().a)}
		var item: Dictionary = stack.pop_back()
		var lo: float = item.a; var hi: float = item.b; var mid = (lo + hi) * 0.5
		var left = _relative(a, arm_a, b, arm_b, lo)
		var right = _relative(a, arm_a, b, arm_b, hi)
		var center = _relative(a, arm_a, b, arm_b, mid)
		var span = hi - lo
		if _segment_distance(left.position, right.position) > radius + accel * span * span / 8.0 + NUMERIC_PADDING: continue
		# Proven all-separating intervals need no collision impulse, including
		# post-impact overlap. A later approaching interval is still searched.
		var distance_bound = center.position.length() + speed * span * 0.5
		var radial_rate_bound = speed * speed + distance_bound * accel
		if center.position.dot(center.velocity) - radial_rate_bound * span * 0.5 > 0.0: continue
		if _inside(left, radius):
			if unresolved >= 0.0 and speed * (lo - unresolved) > POSITION_TOLERANCE: return {"state": "unresolved", "reason": "earlier_root", "at": unresolved}
			return _hit(lo, left, unresolved if unresolved >= 0.0 else lo)
		if speed * span <= POSITION_TOLERANCE * 0.125 or int(item.depth) >= MAX_DEPTH:
			var at = mid if _inside(center, radius) else (hi if _inside(right, radius) else -1.0)
			if at >= 0.0:
				var earliest = unresolved if unresolved >= 0.0 else lo
				if speed * (at - earliest) > POSITION_TOLERANCE: return {"state": "unresolved", "reason": "earlier_root", "at": earliest}
				return _hit(at, center if at == mid else right, earliest)
			if unresolved < 0.0: unresolved = lo
			continue
		stack.append({"a": mid, "b": hi, "depth": int(item.depth) + 1})
		stack.append({"a": lo, "b": mid, "depth": int(item.depth) + 1})
	if unresolved >= 0.0: return {"state": "unresolved", "reason": "grazing_or_resting_contact", "at": unresolved}
	return {"state": "miss"}

static func _hit(at: float, value: Dictionary, earliest: float) -> Dictionary:
	var offset: Vector2 = value.position
	return {"state": "hit", "seconds": at, "normal": offset.normalized() if offset.length_squared() > 0.0 else Vector2.LEFT,
		"distance": offset.length(), "bracket_seconds": [earliest, at]}

static func _segment_distance(a: Vector2, b: Vector2) -> float:
	var delta = b - a
	if delta.length_squared() == 0.0: return a.length()
	return (a + delta * clampf(-a.dot(delta) / delta.length_squared(), 0.0, 1.0)).length()

static func ray_circle(origin: Vector2, direction: Vector2, center: Vector2, radius: float) -> float:
	var offset = origin - center
	var c = offset.length_squared() - radius * radius
	if c <= 0.0: return 0.0
	var b = offset.dot(direction); var discriminant = b * b - c
	if discriminant < 0.0: return -1.0
	var at = -b - sqrt(discriminant)
	return at if at >= 0.0 else -1.0
