extends "res://scripts/simulation.gd"
## pilot-v1: physical vector nozzles, graph-bound cockpit signal, swept circle CCD.
## Autonomous saves must continue to instantiate simulation.gd, never this subclass.
const Profile = preload("res://scripts/pilot_profile.gd")
const CONTROL_VERSION = "pilot-v1"
const COCKPIT_SIGNAL = -2
const GIMBAL_LIMIT = deg_to_rad(90.0)
const GIMBAL_RATE = deg_to_rad(240.0)
const CCD_ANGLE = 0.12
var pilot_tick: int = 0
var pilot_axis_q: int = 0
var pilot_boost: bool = false
var pilot_active: bool = false
var _planned_forces: Dictionary = {}
var _motion_bodies: Dictionary = {}
var _motion_parts: Dictionary = {}
var _motion_hazards: Array = []
var _planned_bodies: Dictionary = {}
var _tick_dt: float = FIXED_DT

func configure(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> void:
	pilot_tick = 0; pilot_axis_q = 0; pilot_boost = false; pilot_active = false
	_planned_forces.clear(); _motion_bodies.clear(); _motion_parts.clear(); _motion_hazards.clear()
	_planned_bodies.clear()
	super.configure(design, launcher, route_data, random_seed)
	route.mode = Profile.MODE; route.control_version = CONTROL_VERSION
	telemetry.assist_energy_used = 0.0; telemetry.swept_contacts = 0
	for b in bodies:
		if not destination_clear(b, Vector2.ZERO):
			status = "failed"
			_log("起飞取消：飞行器整体出生空间或前方安全距离不足。")
			break
	if status != "running": _finalize_recovery()
	_refresh_telemetry()

## One quantized, held command per external 1/60 s command tick. Negative means up.
## Both fixed 1/120 s physics substeps see the exact same integers and booleans.
func set_pilot_input(axis_q: int, boost: bool = false, active: bool = false) -> void:
	pilot_axis_q = clampi(axis_q, -1000, 1000)
	pilot_boost = boost; pilot_active = active

func _tick(dt: float) -> void:
	pilot_tick += 1; _tick_dt = dt; _planned_bodies.clear(); _planned_forces.clear()
	_motion_bodies.clear(); _motion_parts.clear(); _motion_hazards.clear()
	for b in bodies: _motion_bodies[b.id] = {"position": b.position, "angle": b.angle}
	for p in parts.values():
		if p.alive and not p.delivered: _motion_parts[p.id] = _part_position(p)
		if p.type == "thruster": p.pilot_force = Vector2.ZERO; p.pilot_throttle = 0.0
	for h in obstacles: _motion_hazards.append(h.position)
	super._tick(dt)
	for b in bodies:
		if not b.position.is_finite() or not b.velocity.is_finite() or not is_finite(b.angle) or not is_finite(b.angular_velocity):
			status = "failed"; _log("飞行状态超出有限数值范围，安全结束本次试飞。")
			_finalize_recovery(); _refresh_telemetry(); return

func _read_wire(receiver: Dictionary, source_id: int, snapshot: Dictionary = {}) -> bool:
	if source_id == COCKPIT_SIGNAL:
		if not pilot_active: return false
		for p in parts.values():
			if p.type == "cargo" and _same_circuit(receiver, p): return true
		return false
	return super._read_wire(receiver, source_id, snapshot)

func _enabled(p: Dictionary) -> bool:
	if p.input_a == COCKPIT_SIGNAL:
		return p.alive and not p.delivered and (p.forced_signal or _read_wire(p, COCKPIT_SIGNAL))
	return super._enabled(p)

func _update_signals(dt: float) -> void:
	super._update_signals(dt)
	# Logic gates already use _read_wire. Generic forwarders also accept the sentinel.
	for p in parts.values():
		if p.alive and not p.delivered and p.input_a == COCKPIT_SIGNAL and not p.type in ["and_gate", "or_gate", "not_gate", "delay"]:
			p.signal = _read_wire(p, COCKPIT_SIGNAL) or p.forced_signal

func _act(p: Dictionary, b: Dictionary, dt: float, rising: bool) -> void:
	if p.type == "thruster":
		if _contains_cargo(b):
			if not _planned_bodies.has(b.id): _plan_pilot_forces(b)
		else:
			# A detached running engine keeps its last nozzle angle, with no remote pilot authority.
			_planned_forces[p.id] = Vector2.RIGHT.rotated(b.angle + p.local_angle + float(p.get("gimbal_angle", 0.0))) * p.param * p.output_factor
		_apply_vector_nozzle(p, b, dt)
		return
	var before: Vector2 = b.position
	super._act(p, b, dt, rising)
	if p.type == "teleporter" and b.position != before:
		# Teleportation deliberately skips the transit path. CCD starts at its safe exit.
		var delta: Vector2 = b.position - before
		if _motion_bodies.has(b.id): _motion_bodies[b.id].position += delta
		for q in b.parts:
			if _motion_parts.has(q.id): _motion_parts[q.id] += delta

func _contains_cargo(b: Dictionary) -> bool:
	for p in b.parts:
		if p.type == "cargo" and p.alive and not p.delivered: return true
	return false

func _plan_pilot_forces(b: Dictionary) -> void:
	_planned_bodies[b.id] = true
	var engines: Array = []
	for p in b.parts:
		if p.type == "thruster" and p.alive and _enabled(p) and _available_energy(b, p.id) > EPS: engines.append(p)
	if engines.is_empty(): return
	var target_speed = float(route.get("pilot_boost_speed", Profile.BOOST_SPEED)) if pilot_boost else float(route.get("pilot_cruise_speed", Profile.CRUISE_SPEED))
	var desired = Vector2((target_speed - b.velocity.x) * b.mass / 1.8,
		(float(pilot_axis_q) / 1000.0 * float(route.get("pilot_vertical_speed", Profile.VERTICAL_SPEED)) - b.velocity.y) * b.mass / 0.85)
	# Speed targets only request forces. They cannot edit position or velocity.
	# No reverse thrust outside a nozzle's mechanical ±90-degree cone.
	var cargo_angle: float = b.angle
	for p in b.parts:
		if p.type == "cargo": cargo_angle += p.local_angle; break
	var desired_torque: float = (-wrapf(cargo_angle, -PI, PI) * 8.0 - b.angular_velocity * 5.0) * b.inertia
	var lever_scale = 1.0
	for p in engines: lever_scale = maxf(lever_scale, p.local_pos.length())
	var forces: Dictionary = {}
	var divisor: float = float(engines.size())
	for p in engines:
		forces[p.id] = Vector2.ZERO
		divisor += p.local_pos.length_squared() / (lever_scale * lever_scale)
	var learning_rate = 0.95 / maxf(1.0, divisor)
	# Projected gradient allocation in force/torque space. Each iteration keeps every
	# nozzle inside its real force limit and installation-relative gimbal cone.
	for iteration in range(28):
		var force_sum = Vector2.ZERO
		var torque_sum = 0.0
		for p in engines:
			force_sum += forces[p.id]
			torque_sum += p.local_pos.rotated(b.angle).cross(forces[p.id])
		var force_error: Vector2 = force_sum - desired
		var torque_error: float = (torque_sum - desired_torque) / (lever_scale * lever_scale)
		for p in engines:
			var lever: Vector2 = p.local_pos.rotated(b.angle)
			var next: Vector2 = forces[p.id] - (force_error + Vector2(-lever.y, lever.x) * torque_error) * learning_rate
			var max_force: float = p.param * p.output_factor * (1.0 if pilot_boost else 0.72)
			forces[p.id] = _project_nozzle(next, b.angle + p.local_angle, max_force)
	_planned_forces.merge(forces, true)

func _project_nozzle(force: Vector2, mounted_angle: float, limit: float) -> Vector2:
	if force.length_squared() < EPS or limit <= 0.0: return Vector2.ZERO
	var relative = wrapf(force.angle() - mounted_angle, -PI, PI)
	var direction = Vector2.RIGHT.rotated(mounted_angle + clampf(relative, -GIMBAL_LIMIT, GIMBAL_LIMIT))
	return direction * clampf(force.dot(direction), 0.0, limit)

func _apply_vector_nozzle(p: Dictionary, b: Dictionary, dt: float) -> void:
	var planned: Vector2 = _planned_forces.get(p.id, Vector2.ZERO)
	if planned.length_squared() <= EPS: return
	var target_angle = clampf(wrapf(planned.angle() - b.angle - p.local_angle, -PI, PI), -GIMBAL_LIMIT, GIMBAL_LIMIT)
	var old_gimbal = float(p.get("gimbal_angle", 0.0))
	var gimbal = move_toward(old_gimbal, target_angle, GIMBAL_RATE * dt)
	var request = planned.length() * pow(maxf(0.0, cos(target_angle - gimbal)), 2.0)
	var budget = _available_energy(b, p.id)
	for valve in b.parts:
		if valve.alive and valve.type == "valve" and _same_circuit(p, valve) and (valve.target == p.id or (valve.target < 0 and _linked(valve.id, p.id))):
			budget = minf(budget, valve.param * dt if _enabled(valve) else 0.0)
	if budget <= EPS: return
	var ratio = 1.0
	if _nozzle_energy(p, b, request, old_gimbal, gimbal, 1.0, dt) > budget:
		var low = 0.0; var high = 1.0
		for iteration in range(24):
			var middle = (low + high) * 0.5
			if _nozzle_energy(p, b, request, old_gimbal, gimbal, middle, dt) <= budget: low = middle
			else: high = middle
		ratio = low
	var energy = _nozzle_energy(p, b, request, old_gimbal, gimbal, ratio, dt)
	_consume(b, energy, p.id, dt)
	p.gimbal_angle = lerpf(old_gimbal, gimbal, ratio)
	# Under a restrictive valve, slew and force share ONE exact energy budget.
	# Work uses the final partial-slew direction, so low energy cannot add free work.
	var direction = Vector2.RIGHT.rotated(b.angle + p.local_angle + p.gimbal_angle)
	var force = direction * request * ratio
	b.force += force; b.torque += p.local_pos.rotated(b.angle).cross(force)
	p.pilot_force = force; p.pilot_throttle = request * ratio / maxf(EPS, p.param * p.output_factor)
	var servo_cost = absf(gimbal - old_gimbal) * 0.08 + 0.04 * dt
	telemetry.assist_energy_used = float(telemetry.get("assist_energy_used", 0.0)) + servo_cost * ratio

func _nozzle_energy(p: Dictionary, b: Dictionary, request: float, old_gimbal: float, new_gimbal: float, ratio: float, dt: float) -> float:
	var direction = Vector2.RIGHT.rotated(b.angle + p.local_angle + lerpf(old_gimbal, new_gimbal, ratio))
	var lever: float = p.local_pos.rotated(b.angle).cross(direction)
	var projected_speed: float = b.velocity.dot(direction) + b.angular_velocity * lever
	projected_speed += dt * (b.force.dot(direction) / b.mass + b.torque * lever / b.inertia)
	var impulse = request * ratio * dt
	var work = impulse * projected_speed + 0.5 * impulse * impulse * (1.0 / b.mass + lever * lever / b.inertia)
	var servo = (absf(new_gimbal - old_gimbal) * 0.08 + 0.04 * dt) * ratio
	return maxf(request * ratio * 1.5 * dt, work) + servo

func _collisions() -> void:
	# Drag is a stated environmental force, never free velocity regulation.
	# Integrating its dissipative impulse here preserves the legacy integrator intact.
	var drag = maxf(0.0, float(route.get("pilot_drag", 0.0)))
	for b in bodies:
		var before: float = 0.5 * b.mass * b.velocity.length_squared()
		b.velocity *= exp(-drag * _tick_dt / maxf(EPS, b.mass))
		telemetry.heat += before - 0.5 * b.mass * b.velocity.length_squared()
	var contacts: Array = []
	for b in bodies:
		for p in b.parts:
			if not p.alive or p.delivered: continue
			for hi in range(obstacles.size()):
				var h = obstacles[hi]
				if h.health <= 0.0 or h.type == "gravity": continue
				var hit = _sweep_modules(p, {}, h, hi)
				if not hit.is_empty(): contacts.append(hit)
	for ai in range(bodies.size()):
		for bi in range(ai + 1, bodies.size()):
			var a = bodies[ai]; var b = bodies[bi]
			for p in a.parts:
				for q in b.parts:
					if not p.alive or not q.alive: continue
					var hit = _sweep_modules(p, q, {}, -1)
					if not hit.is_empty(): contacts.append(hit)
	contacts.sort_custom(func(a, b): return a.time < b.time)
	var stopped: Dictionary = {}
	for hit in contacts:
		var p: Dictionary = parts[hit.p]
		var a = body_for_part(p.id)
		if not p.alive or a.is_empty() or stopped.has(a.id): continue
		var q: Dictionary = parts.get(hit.q, {})
		var b = body_for_part(q.id) if not q.is_empty() else {}
		if not b.is_empty() and stopped.has(b.id): continue
		_rewind_body(a, hit.time)
		if not b.is_empty(): _rewind_body(b, hit.time)
		var normal: Vector2 = hit.normal
		var other_velocity: Vector2 = _part_velocity(q) if not q.is_empty() else obstacles[hit.h].get("velocity", Vector2.ZERO)
		var relative: float = (_part_velocity(p) - other_velocity).dot(normal)
		_mark_contact(a)
		if not b.is_empty(): _mark_contact(b)
		if relative < 0.0:
			var arm: Vector2 = p.local_pos.rotated(a.angle)
			var denominator: float = 1.0 / a.mass + pow(arm.cross(normal), 2.0) / a.inertia
			var other_arm = Vector2.ZERO
			if not b.is_empty():
				other_arm = q.local_pos.rotated(b.angle)
				denominator += 1.0 / b.mass + pow(other_arm.cross(normal), 2.0) / b.inertia
			var impulse: float = -1.08 * relative / denominator
			a.velocity += normal * impulse / a.mass
			a.angular_velocity += arm.cross(normal * impulse) / a.inertia
			if not b.is_empty():
				b.velocity -= normal * impulse / b.mass
				b.angular_velocity -= other_arm.cross(normal * impulse) / b.inertia
			var damage: float = 0.5 * p.mass * relative * relative * 0.45
			_damage_part(p, damage, "collision")
			if not q.is_empty(): _damage_part(q, 0.5 * q.mass * relative * relative * 0.45, "collision")
			else: obstacles[hit.h].health -= damage * 0.6
		stopped[a.id] = true
		if not b.is_empty(): stopped[b.id] = true
		telemetry.swept_contacts = int(telemetry.get("swept_contacts", 0)) + 1
	# Resolve initial overlap and any remaining resting contacts with legacy solver.
	super._collisions()

func _sweep_modules(p: Dictionary, q: Dictionary, h: Dictionary, hi: int) -> Dictionary:
	var a = body_for_part(p.id)
	var b = body_for_part(q.id) if not q.is_empty() else {}
	var angle_a = _swept_angle(a)
	var angle_b = _swept_angle(b)
	var steps = clampi(int(ceil(maxf(absf(angle_a), absf(angle_b)) / CCD_ANGLE)), 1, 128)
	var inflation = p.local_pos.length() * (1.0 - cos(minf(PI, absf(angle_a) / steps) * 0.5))
	if not q.is_empty(): inflation += q.local_pos.length() * (1.0 - cos(minf(PI, absf(angle_b) / steps) * 0.5))
	if absf(angle_a) / steps > PI: inflation += p.local_pos.length() * 2.0
	if not q.is_empty() and absf(angle_b) / steps > PI: inflation += q.local_pos.length() * 2.0
	var radius: float = 0.43 * p.scale + (0.43 * q.scale if not q.is_empty() else h.radius) + inflation
	for i in range(steps):
		var t0 = float(i) / steps; var t1 = float(i + 1) / steps
		var a0 = _trajectory(p, t0); var a1 = _trajectory(p, t1)
		var b0: Vector2 = _trajectory(q, t0) if not q.is_empty() else _hazard_trajectory(h, hi, t0)
		var b1: Vector2 = _trajectory(q, t1) if not q.is_empty() else _hazard_trajectory(h, hi, t1)
		var fraction = _segment_circle_t(a0 - b0, a1 - b1, radius)
		if fraction >= 0.0:
			var normal = (a0.lerp(a1, fraction) - b0.lerp(b1, fraction)).normalized()
			if normal.length_squared() < EPS: normal = Vector2.LEFT
			return {"p": p.id, "q": q.get("id", -1), "h": hi, "time": lerpf(t0, t1, fraction), "normal": normal}
	return {}

func _swept_angle(b: Dictionary) -> float:
	return b.angle - float(_motion_bodies[b.id].angle) if not b.is_empty() and _motion_bodies.has(b.id) else 0.0

func _trajectory(p: Dictionary, fraction: float) -> Vector2:
	var b = body_for_part(p.id)
	if not b.is_empty() and _motion_bodies.has(b.id):
		var start: Dictionary = _motion_bodies[b.id]
		return start.position.lerp(b.position, fraction) + p.local_pos.rotated(lerpf(start.angle, b.angle, fraction))
	return _motion_parts.get(p.id, _part_position(p)).lerp(_part_position(p), fraction)

func _hazard_trajectory(h: Dictionary, index: int, fraction: float) -> Vector2:
	return _motion_hazards[index].lerp(h.position, fraction) if index >= 0 and index < _motion_hazards.size() else h.position

func _segment_circle_t(start: Vector2, finish: Vector2, radius: float) -> float:
	var delta = finish - start
	var c = start.length_squared() - radius * radius
	if c <= 0.0:
		# Existing penetration is solved below; tangent/away-moving pairs are no hit.
		return 0.0 if start.dot(delta) < -EPS else -1.0
	var aa = delta.length_squared()
	if aa <= 0.000000000001: return -1.0
	var bb = 2.0 * start.dot(delta)
	var discriminant = bb * bb - 4.0 * aa * c
	if discriminant < 0.0: return -1.0
	var t = (-bb - sqrt(discriminant)) / (2.0 * aa)
	return t if t >= 0.0 and t <= 1.0 else -1.0

func _rewind_body(b: Dictionary, time: float) -> void:
	if _motion_bodies.has(b.id):
		var start: Dictionary = _motion_bodies[b.id]
		b.position = start.position.lerp(b.position, maxf(0.0, time - 0.00001))
		b.angle = lerpf(start.angle, b.angle, maxf(0.0, time - 0.00001))
	else:
		b.position -= b.velocity * _tick_dt * (1.0 - time)
		b.angle -= b.angular_velocity * _tick_dt * (1.0 - time)

func destination_clear(body: Dictionary, displacement: Vector2) -> bool:
	if not super.destination_clear(body, displacement): return false
	var exit_time = 0.22
	for p in body.parts:
		if not p.alive or p.delivered: continue
		var at = _part_position(p) + displacement
		var radius: float = 0.43 * p.scale + 0.08
		var finish: Vector2 = at + _part_velocity(p) * exit_time
		if maxf(absf(at.y), absf(finish.y)) + radius > float(route.get("boundary_y", 80.0)) or at.x < -30.0: return false
		for h in obstacles:
			if h.health <= 0.0 or h.type == "gravity": continue
			if at.distance_to(h.position) < radius + h.radius: return false
			var h_finish: Vector2 = h.position + h.get("velocity", Vector2.ZERO) * exit_time
			if _segment_circle_t(at - h.position, finish - h_finish, radius + h.radius) >= 0.0: return false
		for other in bodies:
			if other.id == body.id: continue
			for q in other.parts:
				if not q.alive or q.delivered: continue
				var q_at = _part_position(q)
				var q_finish = q_at + _part_velocity(q) * exit_time
				if at.distance_to(q_at) < radius + 0.43 * q.scale: return false
				if _segment_circle_t(at - q_at, finish - q_finish, radius + 0.43 * q.scale) >= 0.0: return false
	return true

func _check_status() -> void:
	# Receiver entrance is swept too. A valid crossing is captured even if the
	# remainder of a very fast step would leave the finite reception circle.
	var x = float(route.get("distance", 144.0))
	var y = float(route.get("destination_y", 0.0))
	var radius = float(route.get("delivery_radius", 6.0))
	for p in parts.values():
		if p.type != "cargo" or not p.alive or p.delivered or not _motion_parts.has(p.id): continue
		var start: Vector2 = _motion_parts[p.id]
		var finish = _part_position(p)
		if start.x < x and finish.x >= x and finish.x > start.x + EPS:
			var fraction = (x - start.x) / (finish.x - start.x)
			var crossing = start.lerp(finish, fraction)
			if absf(crossing.y - y) <= radius:
				if _part_velocity(p).length() > float(route.get("max_delivery_speed", 10.0)):
					status = "failed"; _log("抵达速度过高，收货平台拒收。"); return
				var b = body_for_part(p.id)
				if not b.is_empty(): b.position += crossing - finish + Vector2(EPS, 0.0)
	super._check_status()

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	var b = _cargo_body()
	var velocity: Vector2 = b.get("velocity", Vector2.ZERO)
	telemetry.control_version = CONTROL_VERSION; telemetry.pilot_tick = pilot_tick
	telemetry.pilot_axis_q = pilot_axis_q; telemetry.pilot_boost = pilot_boost; telemetry.pilot_active = pilot_active
	telemetry.forward_speed = velocity.x; telemetry.vertical_speed = velocity.y
	telemetry.lookahead_m = maxf(22.0, absf(velocity.x) * float(route.get("lookahead_seconds", Profile.LOOKAHEAD_SECONDS)))
	telemetry.route_progress = clampf(cargo_position().x / maxf(1.0, float(route.get("distance", 144.0))), 0.0, 1.0)
	telemetry.next_gate_distance = -1.0; telemetry.next_gate_y = 0.0
	for gate in route.get("pilot_gates", []):
		if float(gate.x) > cargo_position().x - 1.0:
			telemetry.next_gate_distance = float(gate.x) - cargo_position().x
			telemetry.next_gate_y = float(gate.y)
			break
