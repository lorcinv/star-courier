extends RefCounted
## Injectable fixed-tick chronology. Real courier control/circuit/graph state
## stays in its existing simulation owner; this is not another game model.
const Motion = preload("res://scripts/common_motion_v1.gd")
const MAX_EVENTS = 256

static func run(owner, dt: float) -> Dictionary:
	var fraction = 0.0
	for ordinal in range(MAX_EVENTS):
		owner._chrono_rebuild()
		owner._chrono_fields()
		var entities: Array = owner._chrono_entities()
		var boundary: Dictionary = owner._chrono_force_boundary(dt * (1.0 - fraction))
		var horizon: float = boundary.seconds
		var due: bool = owner._chrono_emission_due()
		if due: horizon = 0.0
		var hit = _next_contact(entities, horizon)
		if hit.get("state", "") == "unresolved": return _hold(owner, fraction, hit.get("reason", "unresolved_contact"))
		if hit.get("state", "") == "hit":
			var seconds: float = hit.seconds
			_advance(owner, entities, seconds)
			fraction += seconds / dt
			owner.chrono_fraction = fraction
			var event = _impulse(hit)
			event.tick = owner.pilot_tick - 1; event.fraction = fraction; event.ordinal = ordinal; event.phase = 0
			owner._chrono_contact(event)
			if not owner._chrono_commit_actor(fraction): return _hold(owner, fraction, owner.chrono_error)
			continue
		if due:
			var emitted: Dictionary = owner._chrono_emit()
			if not emitted.ok: return _hold(owner, fraction, emitted.get("error", "emission_failed"))
			for ray in emitted.get("intents", []):
				var target = nearest_ray(entities, ray)
				owner._chrono_ray(ray, target, ordinal)
			continue
		_advance(owner, entities, horizon)
		fraction = 1.0 if horizon == dt * (1.0 - fraction) else fraction + horizon / dt
		owner.chrono_fraction = fraction
		owner._chrono_exhaust(boundary.ids)
		if not owner._chrono_commit_actor(fraction): return _hold(owner, fraction, owner.chrono_error)
		if fraction == 1.0: return {"ok": true, "fraction": fraction, "events": ordinal + 1}
	return _hold(owner, fraction, "event_budget")

static func _advance(owner, entities: Array, seconds: float) -> void:
	owner._chrono_apply_resources(seconds)
	for entity in entities: Motion.advance(entity.body, seconds)

static func _next_contact(entities: Array, seconds: float) -> Dictionary:
	var earliest: Dictionary = {}
	for ai in range(entities.size()):
		for bi in range(ai + 1, entities.size()):
			var a: Dictionary = entities[ai]; var b: Dictionary = entities[bi]
			if a.fixed and b.fixed: continue
			for p in a.modules:
				for q in b.modules:
					var solved = Motion.sweep(a.body, p.lever, b.body, q.lever, p.radius + q.radius, seconds)
					if solved.state in ["invalid", "unresolved"]:
						return {"state": "unresolved", "reason": "%s:%s:%s" % [a.key, b.key, solved.get("reason", solved.state)]}
					if solved.state != "hit": continue
					var key = "%s:%08d:%s:%08d" % [a.key, p.id, b.key, q.id]
					if earliest.is_empty() or solved.seconds < earliest.seconds or (solved.seconds == earliest.seconds and key < earliest.key):
						earliest = solved; earliest.a = a; earliest.b = b; earliest.p = p; earliest.q = q; earliest.key = key
	return earliest

static func _impulse(hit: Dictionary) -> Dictionary:
	var a: Dictionary = hit.a.body; var b: Dictionary = hit.b.body
	var arm_a: Vector2 = hit.p.lever.rotated(a.angle); var arm_b: Vector2 = hit.q.lever.rotated(b.angle)
	var va: Vector2 = a.velocity + Vector2(-arm_a.y, arm_a.x) * a.angular_velocity
	var vb: Vector2 = b.velocity + Vector2(-arm_b.y, arm_b.x) * b.angular_velocity
	var normal: Vector2 = hit.normal
	var relative = (va - vb).dot(normal)
	var ia = 0.0 if hit.a.fixed else 1.0 / a.mass
	var ib = 0.0 if hit.b.fixed else 1.0 / b.mass
	var ra = 0.0 if hit.a.fixed else pow(arm_a.cross(normal), 2.0) / a.inertia
	var rb = 0.0 if hit.b.fixed else pow(arm_b.cross(normal), 2.0) / b.inertia
	var impulse = -1.08 * minf(0.0, relative) / (ia + ib + ra + rb)
	if not hit.a.fixed:
		a.velocity += normal * impulse * ia
		a.angular_velocity += arm_a.cross(normal * impulse) / a.inertia
	if not hit.b.fixed:
		b.velocity -= normal * impulse * ib
		b.angular_velocity -= arm_b.cross(normal * impulse) / b.inertia
	return {"a": hit.a, "b": hit.b, "p": hit.p, "q": hit.q, "relative": relative,
		"impulse_ns": impulse, "normal": normal, "witness_distance": hit.distance}

static func nearest_ray(entities: Array, ray: Dictionary) -> Dictionary:
	var target: Dictionary = {}
	for entity in entities:
		if not str(ray.get("source_id", "")).is_empty() and entity.get("source_id", "") == ray.source_id: continue
		for module in entity.modules:
			var center = Motion.sample(entity.body, module.lever, 0.0).position
			var distance = _frozen_ray_circle(ray, center, module.radius)
			var key = "%s:%08d" % [entity.key, module.id]
			if distance < 0.0 or distance > ray.range_m: continue
			if target.is_empty() or distance < target.distance or (distance == target.distance and key < target.key):
				target = {"entity": entity, "module": module, "distance": distance, "key": key}
	return target

static func _frozen_ray_circle(ray: Dictionary, center: Vector2, radius: float) -> float:
	# Preserve the helper's scalar-double frozen origin/direction, instead of
	# casting the ray to Vector2 and renormalizing it onto a different line.
	var x: float = ray.origin_x - float(center.x); var y: float = ray.origin_y - float(center.y)
	var dx: float = ray.dir_x; var dy: float = ray.dir_y
	var c = x * x + y * y - radius * radius
	if c <= 0.0: return 0.0
	var aa = dx * dx + dy * dy; var bb = x * dx + y * dy
	if aa <= 0.0: return -1.0
	var discriminant = bb * bb - aa * c
	if discriminant < 0.0: return -1.0
	var distance = (-bb - sqrt(discriminant)) / aa
	return distance if distance >= 0.0 else -1.0

static func _hold(owner, fraction: float, reason: String) -> Dictionary:
	owner.chrono_fraction = fraction
	owner.chrono_error = reason
	return {"ok": false, "held": true, "fraction": fraction, "error": reason}

## Positive mechanical work only. Braking cannot refund or create budget.
static func positive_work(power: float, slope: float, seconds: float) -> float:
	if seconds <= 0.0: return 0.0
	if slope == 0.0: return maxf(0.0, power) * seconds
	var root = clampf(-power / slope, 0.0, seconds)
	var start = root if slope > 0.0 else 0.0
	var end = seconds if slope > 0.0 else root
	if power + slope * ((start + end) * 0.5) <= 0.0: return 0.0
	return maxf(0.0, power * (end - start) + 0.5 * slope * (end * end - start * start))
