extends RefCounted
## Read-only presentation predicate. No prediction, solver call, or safety claim.
## The v5 route proceeds along +X. Advice can re-arm on later closing motion.
const Expanded = preload("res://scripts/parts_expanded.gd")
const REAR_CLEARANCE_M: float = 0.25
const SHELL_RADIUS_M: float = 0.43 # Actual v5 module contact shell, before scale.
const MAX_PARTS: int = 192

static func active(status: String, bird: Dictionary, bodies: Variant) -> bool:
	if status != "running" or not bird.get("activated", false) or bird.get("state", "") not in ["healthy", "hurt", "injured"]: return false
	# Old isolated presentation fixtures have no craft. Unknown geometry cannot
	# establish that the whole craft passed, so retain the existing advice.
	if not bodies is Array or bodies.size() > MAX_PARTS: return true
	if not bird.get("position") is Vector2 or not bird.position.is_finite() or not bird.get("velocity") is Vector2 or not bird.velocity.is_finite(): return true
	if not _number(bird.get("radius")) or float(bird.radius) <= 0.0: return true
	var connected: Array = []
	var part_count: int = 0
	for body in bodies:
		if not body is Dictionary or not body.get("parts") is Array: return true
		part_count += body.parts.size()
		if part_count > MAX_PARTS: return true
		var cargo: bool = false
		for part in body.parts:
			if not part is Dictionary or not part.get("alive") is bool or not part.get("delivered") is bool: return true
			if part.get("type") == "cargo" and part.alive and not part.delivered: cargo = true
		if cargo: connected.append(body)
	# Detached debris without cargo cannot be steered by the pilot. Its physics,
	# possible future contacts and harm facts are entirely untouched.
	for body in connected:
		if not body.get("position") is Vector2 or not body.position.is_finite() or not body.get("velocity") is Vector2 or not body.velocity.is_finite(): return true
		if not _number(body.get("angle")) or not _number(body.get("angular_velocity")): return true
		for part in body.parts:
			if not part.alive or part.delivered: continue
			if not part.get("local_pos") is Vector2 or not part.local_pos.is_finite() or not _number(part.get("scale")) or float(part.scale) <= 0.0: return true
			var lever: Vector2 = part.local_pos.rotated(float(body.angle))
			if not _passed(bird, body, lever, SHELL_RADIUS_M * float(part.scale)): return true
			# Include the drill's real head even while unfunded. This is a
			# conservative footprint, not a claim that its cutter is activated.
			if part.get("type") == "drill":
				if not _number(part.get("local_angle")): return true
				var head: Vector2 = lever + Vector2.RIGHT.rotated(float(body.angle) + float(part.local_angle)) * Expanded.DRILL_HEAD_OFFSET * float(part.scale)
				if not _passed(bird, body, head, Expanded.DRILL_HEAD_RADIUS * float(part.scale)): return true
	return false

static func _passed(bird: Dictionary, body: Dictionary, lever: Vector2, radius: float) -> bool:
	var relative: Vector2 = body.position + lever - bird.position
	var relative_velocity: Vector2 = body.velocity + Vector2(-lever.y, lever.x) * float(body.angular_velocity) - bird.velocity
	if not relative.is_finite() or not relative_velocity.is_finite() or not is_finite(radius) or not is_finite(relative.dot(relative_velocity)): return false
	# All physical circles must clear the bird's forward edge plus a small rear
	# gap. Both axial and radial motion must be non-closing at this sampled tick;
	# angular velocity is included for each actual module/head center.
	return relative.x - radius > float(bird.radius) + REAR_CLEARANCE_M and relative_velocity.x >= 0.0 and relative.dot(relative_velocity) >= 0.0

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
