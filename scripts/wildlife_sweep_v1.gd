extends RefCounted
## Pure real-arc circle CCD. Chord inflation is pruning only, never a damage hit.
## Unresolved bounded search is explicit; callers must hold/fail, not tunnel.
const VERSION = "protected-bird-sweep-v1"
const MAX_NODES = 8192
const MAX_DEPTH = 48
const ROOT_FRACTION_TOLERANCE = 0.0000000001
const NUMERIC_PADDING = 0.0000001
const ROOT_POSITION_TOLERANCE = 0.0005

static func solve(com0: Vector2, com1: Vector2, angle0: float, angle1: float,
		lever: Vector2, bird0: Vector2, bird1: Vector2, radius: float) -> Dictionary:
	for v in [com0, com1, lever, bird0, bird1]:
		if not v.is_finite(): return {"state": "invalid", "reason": "nonfinite_vector"}
	if not is_finite(angle0) or not is_finite(angle1) or not is_finite(radius) or radius <= 0.0:
		return {"state": "invalid", "reason": "invalid_scalar"}
	var start: Vector2 = com0 - bird0
	var finish: Vector2 = com1 - bird1
	var r0 = relative(start, finish, angle0, angle1, lever, 0.0)
	if r0.length_squared() <= radius * radius:
		return _hit(0.0, r0, 0.0, 0.0, true)
	if absf(angle1 - angle0) <= 0.000000000001 or lever.length_squared() <= 0.000000000001:
		var r1 = relative(start, finish, angle0, angle1, lever, 1.0)
		return _linear(r0, r1, radius)
	var stack: Array = [{"a": 0.0, "b": 1.0, "depth": 0}]
	var nodes = 0
	var unresolved_start = -1.0
	var speed_bound = (finish - start).length() + absf(angle1 - angle0) * lever.length()
	while not stack.is_empty():
		nodes += 1
		if nodes > MAX_NODES: return {"state": "unresolved", "reason": "node_budget", "nodes": nodes, "a": unresolved_start if unresolved_start >= 0.0 else float(stack.back().a)}
		var item: Dictionary = stack.pop_back()
		var a: float = item.a; var b: float = item.b
		var left = relative(start, finish, angle0, angle1, lever, a)
		var right = relative(start, finish, angle0, angle1, lever, b)
		var angle_span = absf(angle1 - angle0) * (b - a)
		var deviation = minf(2.0 * lever.length(), lever.length() * angle_span * angle_span / 8.0)
		if segment_distance(left, right) > radius + deviation + NUMERIC_PADDING: continue
		if left.length_squared() <= radius * radius:
			if unresolved_start >= 0.0 and speed_bound * (a - unresolved_start) > ROOT_POSITION_TOLERANCE: return {"state": "unresolved", "reason": "earlier_uncertain_root", "a": unresolved_start}
			return _hit(a, left, unresolved_start if unresolved_start >= 0.0 else a, b, false, nodes)
		var middle = (a + b) * 0.5
		var mid = relative(start, finish, angle0, angle1, lever, middle)
		# Stop by bounded POSSIBLE WORLD TRAVEL, not only a sub-float fraction.
		# At x~1100 Vector2 distance has a finite plateau near the real root.
		# Chasing that plateau to 1e-10 fractions can exhaust 8192 nodes before
		# an obvious genuine crossing. A leaf spans <=1/8 the declared .5mm
		# root tolerance, and still requires an evaluated actual-inside witness.
		if speed_bound * (b - a) <= ROOT_POSITION_TOLERANCE * 0.125 or b - a <= ROOT_FRACTION_TOLERANCE or int(item.depth) >= MAX_DEPTH:
			# A hit requires an actual point on the true rotation curve. There is no
			# ternary/unimodal assumption and no inflation-only positive verdict.
			var inside = middle if mid.length_squared() <= radius * radius else (b if right.length_squared() <= radius * radius else -1.0)
			if inside >= 0.0:
				var earliest = unresolved_start if unresolved_start >= 0.0 else a
				if speed_bound * (inside - earliest) > ROOT_POSITION_TOLERANCE: return {"state": "unresolved", "reason": "earlier_uncertain_root", "a": unresolved_start}
				return _hit(inside, mid if inside == middle else right, earliest, inside, false, nodes)
			# A tiny numerical band immediately before a real root is allowed to
			# remain uncertain while searching for an ACTUAL inside witness. Its
			# total possible travel is bounded before accepting that later witness.
			# A near miss with no inside witness can never turn into a damage hit.
			if unresolved_start < 0.0: unresolved_start = a
			continue
		# LIFO right then left preserves earliest-event ordering, including
		# multiple rotations and translation+rotation with several local minima.
		stack.append({"a": middle, "b": b, "depth": int(item.depth) + 1})
		stack.append({"a": a, "b": middle, "depth": int(item.depth) + 1})
	if unresolved_start >= 0.0: return {"state": "unresolved", "reason": "grazing_numeric_interval", "a": unresolved_start, "nodes": nodes}
	return {"state": "miss", "nodes": nodes}

static func relative(start: Vector2, finish: Vector2, angle0: float, angle1: float, lever: Vector2, u: float) -> Vector2:
	return start.lerp(finish, u) + lever.rotated(lerpf(angle0, angle1, u))

static func segment_distance(a: Vector2, b: Vector2) -> float:
	var delta = b - a
	if delta.length_squared() <= 0.000000000001: return a.length()
	return (a + delta * clampf(-a.dot(delta) / delta.length_squared(), 0.0, 1.0)).length()

static func _linear(a: Vector2, b: Vector2, radius: float) -> Dictionary:
	var delta = b - a
	var aa: float = delta.length_squared()
	if aa <= 0.000000000001: return {"state": "miss"}
	var bb: float = 2.0 * a.dot(delta)
	var cc: float = a.length_squared() - radius * radius
	var disc = bb * bb - 4.0 * aa * cc
	if disc < 0.0: return {"state": "miss"}
	var u = (-bb - sqrt(disc)) / (2.0 * aa)
	if u < 0.0 or u > 1.0: return {"state": "miss"}
	return _hit(u, a.lerp(b, u), u, u, false, 1)

static func _hit(u: float, r: Vector2, lo: float, hi: float, overlap: bool, nodes: int = 0) -> Dictionary:
	return {"state": "hit", "time": u, "normal": r.normalized() if r.length_squared() > 0.000000000001 else Vector2.LEFT,
		"distance": r.length(), "bracket": [lo, hi], "initial_overlap": overlap, "nodes": nodes}
