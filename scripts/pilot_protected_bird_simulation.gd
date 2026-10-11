extends "res://scripts/pilot_ascent_simulation.gd"
## Private pilot-v5-protected-bird. Frozen v3 mechanics copied verbatim except
## the explicitly owned chronological loop and source-aware weapon boundaries.
## Inherits v2 so the copied v3 resting fallback cannot run v3 CCD twice.
const BirdProfile = preload("res://scripts/pilot_protected_bird_profile.gd")
const BirdContact = preload("res://scripts/wildlife_contact_v1.gd")
const BirdSweep = preload("res://scripts/wildlife_sweep_v1.gd")
const BirdDesign = preload("res://scripts/protected_bird_design_v1.gd")
const BirdFacts = preload("res://scripts/protected_bird_facts_v1.gd")
const VERSION = "pilot-v5-protected-bird"
const CONTACT_SLOP = 0.001
const POSE_TOLERANCE = 0.0005
var wildlife: Dictionary = {}
var source_registry: Dictionary = {}
var first_harm: Dictionary = {}
var wildlife_error: String = ""
var paused: bool = false
var _route_valid: bool = false
var _wild_start = Vector2.ZERO
var _tick_fraction: float = 0.0
var _action_ordinal: int = 0
var _in_collision_loop: bool = false
var wormhole_events: Array = []
var _station_remaining: float = 0.0
var _portal_ready: bool = false
var _denied_keys: Dictionary = {}
var _attempted_anchors: Dictionary = {}
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Expanded = preload("res://scripts/parts_expanded.gd")
const EXTREME_VERSION = "pilot-v3"
var _source_forces: Dictionary = {}
var _shield_spent: Dictionary = {}
var _shield_valve_spent: Dictionary = {}
var _paid_drills: Dictionary = {}
var _sources_live = false
var _skip_inherited_sweeps = false
var _load_edges: Array = []

func configure(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> void:
	wildlife.clear(); source_registry.clear(); first_harm.clear(); wildlife_error = ""
	paused = false; _route_valid = false; _portal_ready = false; _station_remaining = 0.0
	wormhole_events.clear(); _denied_keys.clear(); _attempted_anchors.clear()
	_tick_fraction = 0.0; _action_ordinal = 0; _in_collision_loop = false
	_sources_live = false
	_source_forces.clear(); _shield_spent.clear(); _shield_valve_spent.clear(); _paid_drills.clear(); _load_edges.clear()
	var error = BirdProfile.validation_error(route_data)
	if error.is_empty(): error = BirdDesign.validation_error(design, launcher)
	if error.is_empty() and random_seed != int(route_data.seed): error = "保护鸟模拟种子与已保存实现不一致。"
	if not error.is_empty():
		super.configure([], [], BirdProfile.route(), random_seed)
		route.control_version = VERSION; route.pilot_profile = VERSION
		status = "failed"; wildlife_error = error; _log(error); _finalize_recovery(); _refresh_telemetry(); return
	super.configure(design.slice(0, MAX_SIM_PARTS), launcher, route_data, random_seed)
	route.control_version = VERSION; route.pilot_profile = VERSION
	if design.size() > MAX_SIM_PARTS:
		status = "failed"; _log("保护鸟试飞取消：蓝图超过 192 个模块的安全上限。"); _finalize_recovery()
	for p in parts.values():
		p.owner_kind = "courier"; p.origin_part_id = int(p.id)
		_register_source(p)
	var event: Dictionary = route.ecology
	wildlife = {"event_id": event.event_id, "entity_id": event.entity_id, "species_id": event.species_id,
		"position": Vector2(float(event.position[0]), float(event.position[1])),
		"velocity": Vector2(float(event.velocity[0]), float(event.velocity[1])),
		"mass": float(event.mass), "radius": float(event.radius), "hp": float(event.max_hp),
		"state": "waiting", "active": false, "activated": false, "activation_tick": -1,
		"activation_fraction": 0.0, "hurt_ticks": 0, "fall_ticks": 0, "damage_transitions": 0}
	_station_remaining = float(route.wormhole_portal.station_energy_j)
	_portal_ready = true; _route_valid = true
	_refresh_telemetry()

func step(dt: float) -> void:
	if paused: return
	super.step(dt)

func set_paused(value: bool) -> void:
	paused = value

func _new_part(raw: Dictionary) -> Dictionary:
	if raw.get("type", "") != "drill": return super._new_part(raw)
	var safe = raw.duplicate(true); safe.type = "beam"
	var p = super._new_part(safe)
	var spec = Expanded.catalog().drill
	p.type = "drill"; p.mass = spec.mass; p.price = spec.price
	p.hp = 60.0; p.max_hp = 60.0; p.strength = 90.0; p.param = 0.0
	p.input_a = int(raw.get("input_a", -1)); p.input_b = -1; p.target = -1
	p.drill_power_ratio = 0.0
	return p

func _tick(dt: float) -> void:
	_attempted_anchors.clear(); _tick_fraction = 0.0; _action_ordinal = 0
	if not wildlife.is_empty():
		_wild_start = wildlife.position
		wildlife.hurt_ticks = maxi(0, int(wildlife.hurt_ticks) - 1)
		if wildlife.state == "hurt" and wildlife.hurt_ticks == 0: wildlife.state = "injured"
	_sources_live = false
	_source_forces.clear(); _shield_spent.clear(); _shield_valve_spent.clear(); _paid_drills.clear()
	for p in parts.values():
		if p.type == "drill": p.drill_power_ratio = 0.0
	super._tick(dt)
	_sources_live = false
	if not wildlife.is_empty():
		if wildlife.state == "falling":
			wildlife.fall_ticks += 1
			if wildlife.fall_ticks >= 48: wildlife.state = "gone"
		elif wildlife.active:
			var bounds: Array = route.ecology.bounds
			var at: Vector2 = wildlife.position
			if at.x < float(bounds[0]) or at.y < float(bounds[1]) or at.x > float(bounds[2]) or at.y > float(bounds[3]) or pilot_tick - int(wildlife.activation_tick) >= int(route.ecology.max_active_ticks):
				wildlife.active = false; wildlife.state = "departed"
	_refresh_telemetry()

func _rebuild_bodies() -> void:
	super._rebuild_bodies()
	if not _sources_live: return
	# The inherited rebuild carries already-accumulated force into child bodies
	# by module mass. It is prepaid common acceleration, not a continuing force
	# transmitted across the now-cut socket. Match that exact integrated field.
	_source_forces.clear()
	for b in bodies:
		for p in b.parts: _source_forces[p.id] = p.get("old_force", Vector2.ZERO)

func _act(p: Dictionary, b: Dictionary, dt: float, rising: bool) -> void:
	_action_ordinal += 1
	_sources_live = true
	if p.type == "drill":
		var cost = Expanded.DRILL_POWER * dt * p.output_factor
		var ratio = _consume(b, cost, p.id, dt)
		p.drill_power_ratio = ratio * p.output_factor
		_paid_drills[p.id] = {"ratio": ratio, "output": p.output_factor}
		telemetry.drill_energy_used = float(telemetry.get("drill_energy_used", 0.0)) + cost * ratio
		return
	var before: Vector2 = b.get("force", Vector2.ZERO)
	super._act(p, b, dt, rising)
	_source_forces[p.id] = _source_forces.get(p.id, Vector2.ZERO) + b.get("force", Vector2.ZERO) - before

func _consume(b: Dictionary, desired: float, consumer_id: int, dt: float, rate_limit: bool = true) -> float:
	if not rate_limit or desired <= EPS or parts.get(consumer_id, {}).get("type", "") != "shield":
		return super._consume(b, desired, consumer_id, dt, rate_limit)
	# An impact can hit several modules in one tick. Each valve/consumer pair
	# has one tick budget shared by those contacts AND shielded attack damage.
	# Untargeted adjacent consumers keep the legacy per-module rate contract.
	var allowed = desired; var valves: Array = []
	for valve in b.parts:
		if not valve.alive or valve.delivered or valve.type != "valve" or not _same_circuit(parts[consumer_id], valve): continue
		if valve.target != consumer_id and not (valve.target < 0 and _linked(valve.id, consumer_id)): continue
		var key = "%d:%d" % [valve.id, consumer_id]
		valves.append(key)
		var budget = maxf(0.0, valve.param * dt - float(_shield_valve_spent.get(key, 0.0))) if _enabled(valve) else 0.0
		allowed = minf(allowed, budget)
	var used = allowed * super._consume(b, allowed, consumer_id, dt, false)
	for id in valves: _shield_valve_spent[id] = float(_shield_valve_spent.get(id, 0.0)) + used
	return used / desired

func _paid_drill_ratio(p: Dictionary) -> float:
	if not p.alive or p.delivered or not _paid_drills.has(p.id): return 0.0
	var paid: Dictionary = _paid_drills[p.id]
	# A splitter may copy module fields after this motor was charged. New clones
	# have no paid entry; the surviving original retains only its reduced output.
	return float(paid.ratio) * minf(float(paid.output), p.output_factor)

func _plan_pilot_forces(b: Dictionary) -> void:
	if not pilot_boost:
		super._plan_pilot_forces(b)
		return
	_planned_bodies[b.id] = true
	var engines: Array = []
	var output = 0.0
	for p in b.parts:
		if p.type == "thruster" and p.alive and _enabled(p) and _available_energy(b, p.id) > EPS:
			engines.append(p); output += p.param * p.output_factor
	if engines.is_empty(): return
	var heading = AscentProfile.path_heading(cargo_position().x, route) + float(pilot_axis_q) / 1000.0 * Extreme.BOOST_PITCH
	# No speed target and no fixed global force cap in overdrive. Allocation can
	# trade some forward thrust for real attitude torque, subject to every nozzle.
	var desired = Vector2.RIGHT.rotated(heading) * output
	var cargo_angle: float = b.angle
	for p in b.parts:
		if p.type == "cargo": cargo_angle += p.local_angle; break
	var error = wrapf(heading - cargo_angle, -PI, PI)
	var torque: float = (error * 7.0 - b.angular_velocity * 4.5) * b.inertia
	var lever_scale = 1.0
	for p in engines: lever_scale = maxf(lever_scale, p.local_pos.length())
	var forces: Dictionary = {}
	var divisor = float(engines.size())
	for p in engines:
		forces[p.id] = Vector2.ZERO
		divisor += 3.0 * p.local_pos.length_squared() / (lever_scale * lever_scale)
	var rate = 0.95 / maxf(1.0, divisor)
	for iteration in range(40):
		var force_sum = Vector2.ZERO; var torque_sum = 0.0
		for p in engines:
			force_sum += forces[p.id]
			torque_sum += p.local_pos.rotated(b.angle).cross(forces[p.id])
		var force_error: Vector2 = force_sum - desired
		var torque_error = 3.0 * (torque_sum - torque) / (lever_scale * lever_scale)
		for p in engines:
			var lever: Vector2 = p.local_pos.rotated(b.angle)
			var next: Vector2 = forces[p.id] - (force_error + Vector2(-lever.y, lever.x) * torque_error) * rate
			forces[p.id] = _project_nozzle(next, b.angle + p.local_angle, p.param * p.output_factor)
	_planned_forces.merge(forces, true)

func _damage_part(p: Dictionary, amount: float, source: String) -> void:
	# The frozen integrator invokes its old all-body-force beam rule. v3 replaces
	# that rule below at the same fixed tick, never by modifying beam strength.
	if source == "stress": return
	if source == "attack" and p.alive and not p.delivered and amount > 0.0:
		var residual = amount; var attacked_body = body_for_part(p.id)
		for shield in attacked_body.get("parts", []):
			if shield.type == "shield" and shield.alive and _enabled(shield) and _same_circuit(p, shield):
				residual *= 1.0 - _consume(attacked_body, residual * 1.5, shield.id, _tick_dt)
				if residual <= EPS: return
		_record_damage_incident(p, residual, source)
		p.hp -= residual
		if p.hp <= 0.0: _destroy(p)
		return
	if source != "collision" or not p.alive or p.delivered or amount <= 0.0:
		super._damage_part(p, amount, source); return
	var remaining = amount
	var absorb_remaining = amount * Extreme.IMPACT_ABSORB_FRACTION
	var b = body_for_part(p.id)
	for shield in b.get("parts", []):
		if shield.type != "shield" or not shield.alive or not _enabled(shield) or not _same_circuit(p, shield): continue
		var limit = maxf(0.0, Extreme.IMPACT_ABSORB_LIMIT * shield.output_factor - float(_shield_spent.get(shield.id, 0.0)))
		var desired = minf(absorb_remaining, limit)
		if desired <= EPS: continue
		var before = float(telemetry.energy_used)
		var absorbed = desired * _consume(b, desired * Extreme.IMPACT_JOULES_PER_HP, shield.id, _tick_dt)
		remaining -= absorbed; absorb_remaining -= absorbed
		_shield_spent[shield.id] = float(_shield_spent.get(shield.id, 0.0)) + absorbed
		telemetry.impact_absorbed = float(telemetry.get("impact_absorbed", 0.0)) + absorbed
		telemetry.impact_shield_energy = float(telemetry.get("impact_shield_energy", 0.0)) + float(telemetry.energy_used) - before
	super._damage_part(p, remaining, source)

func _collisions() -> void:
	_in_collision_loop = true
	_tick_fraction = 0.0
	# Action-time graph rebuilds assign fresh body IDs. Reconstruct the true
	# integration start BEFORE collision drag; split/teleport spawn is not a ray.
	for body in bodies:
		if not _motion_bodies.has(body.id):
			_motion_bodies[body.id] = {"position": body.position - body.velocity * _tick_dt,
				"angle": body.angle - body.angular_velocity * _tick_dt}
	if _live_bird():
		_wild_start = wildlife.position
		wildlife.position += wildlife.velocity * _tick_dt
	_update_load_paths()
	for p in parts.values():
		if p.type == "drill": p.drill_power_ratio = _paid_drill_ratio(p)
	var original_motion = _motion_bodies.duplicate(true)
	var original_hazards = _motion_hazards.duplicate()
	var drag = maxf(0.0, float(route.get("pilot_drag", 0.0)))
	for b in bodies:
		var before: float = 0.5 * b.mass * b.velocity.length_squared()
		b.velocity *= exp(-drag * _tick_dt / maxf(EPS, b.mass))
		telemetry.heat += before - 0.5 * b.mass * b.velocity.length_squared()
	var remaining = 1.0
	var used_drills: Dictionary = {}
	var budget = clampi(parts.size() * 2 + bodies.size() * 8, 32, 256)
	var exhausted = true
	for event_index in range(budget):
		var hit = _next_contact(used_drills)
		if hit.is_empty(): exhausted = false; break
		telemetry.ccd_event_rounds = int(telemetry.get("ccd_event_rounds", 0)) + 1
		if hit.get("unresolved", false):
			_fail_wildlife(str(hit.get("reason", "unresolved_contact")))
			break
		var fraction = clampf(float(hit.time), 0.0, 1.0)
		_tick_fraction += remaining * fraction
		_action_ordinal += 1
		if _live_bird(): wildlife.position = _wild_start.lerp(wildlife.position, fraction)
		# Advance ALL bodies to the common event time before applying an impulse.
		# Subsequent sweeps use the changed motion, including already-hit bodies.
		for b in bodies:
			var start: Dictionary = _motion_bodies.get(b.id, {"position": b.position - b.velocity * _tick_dt * remaining, "angle": b.angle - b.angular_velocity * _tick_dt * remaining})
			b.position = start.position.lerp(b.position, fraction)
			b.angle = lerpf(start.angle, b.angle, fraction)
		for hi in range(obstacles.size()):
			if hi < _motion_hazards.size(): _motion_hazards[hi] = _motion_hazards[hi].lerp(obstacles[hi].position, fraction)
		var p: Dictionary = parts[hit.p]
		if hit.get("wildlife", false):
			if hit.get("cut", false):
				used_drills[p.id] = true
				var dealt = _damage_wildlife(Expanded.DRILL_DAMAGE_RATE * _tick_dt * _paid_drill_ratio(p), _source(p, "drill"))
				telemetry.drill_damage += dealt; telemetry.drill_contacts += 1
			else: _apply_wildlife_contact(hit)
		elif hit.get("wormhole", false):
			_apply_portal(hit)
		elif hit.get("cut", false):
			used_drills[p.id] = true
			var h: Dictionary = obstacles[hit.h]
			var damage = minf(h.health, Expanded.DRILL_DAMAGE_RATE * _tick_dt * p.drill_power_ratio)
			h.health -= damage
			telemetry.drill_damage += damage; telemetry.drill_contacts += 1
			if p.cooldown <= 0.0:
				_effect("drill", _part_position(p) + Vector2.RIGHT.rotated(body_for_part(p.id).angle + p.local_angle) * Expanded.DRILL_HEAD_OFFSET * p.scale, _motion_hazards[hit.h], 0.12)
				p.cooldown = 0.08
		else:
			if not _try_collinear_contacts(hit): _apply_swept_impulse(hit)
		if _graph_dirty: _rebuild_bodies()
		remaining *= 1.0 - fraction
		if _live_bird():
			_wild_start = wildlife.position
			wildlife.position += wildlife.velocity * _tick_dt * remaining
		for b in bodies:
			_motion_bodies[b.id] = {"position": b.position, "angle": b.angle}
			b.position += b.velocity * _tick_dt * remaining
			b.angle += b.angular_velocity * _tick_dt * remaining
		if remaining <= 0.00000001: exhausted = false; break
	if exhausted:
		# A pathological dense contact pile consumes the bounded event budget.
		# Hold its last resolved poses for this remaining substep; never tunnel
		# through unchecked geometry or alter velocities to hide the overflow.
		for b in bodies:
			b.position = _motion_bodies[b.id].position; b.angle = _motion_bodies[b.id].angle
		if _live_bird(): wildlife.position = _wild_start
		telemetry.ccd_budget_holds = int(telemetry.get("ccd_budget_holds", 0)) + 1
	# The frozen resting-overlap fallback is still useful. Disable only its
	# duplicate CCD/drag for this call; all geometry and damage stay enabled.
	_skip_inherited_sweeps = true
	var saved_drag: Variant = route.get("pilot_drag", null)
	route.pilot_drag = 0.0
	super._collisions()
	if saved_drag == null: route.erase("pilot_drag")
	else: route.pilot_drag = saved_drag
	_skip_inherited_sweeps = false
	_motion_bodies = original_motion; _motion_hazards = original_hazards
	_in_collision_loop = false; _tick_fraction = 1.0

func _sweep_modules(p: Dictionary, q: Dictionary, h: Dictionary, hi: int) -> Dictionary:
	if _skip_inherited_sweeps: return {}
	return super._sweep_modules(p, q, h, hi)

func _next_ordinary_contact(used_drills: Dictionary) -> Dictionary:
	var contacts: Array = []; var bounds: Dictionary = {}
	for b in bodies:
		var radius = 0.0
		for p in b.parts:
			if p.alive and not p.delivered: radius = maxf(radius, p.local_pos.length() + (0.48 if p.type == "drill" else 0.43) * p.scale)
		b.extreme_bound_radius = radius
		var start: Vector2 = _motion_bodies.get(b.id, {}).get("position", b.position - b.velocity * _tick_dt)
		bounds[b.id] = Rect2(start, Vector2.ZERO).expand(b.position).grow(radius + 0.00002)

	for b in bodies:
		for p in b.parts:
			if not p.alive or p.delivered: continue
			for hi in range(obstacles.size()):
				var h = obstacles[hi]
				if h.health <= 0.0 or h.type == "gravity": continue
				var h_start: Vector2 = _motion_hazards[hi] if hi < _motion_hazards.size() else h.position
				if not bounds[b.id].intersects(Rect2(h_start, Vector2.ZERO).expand(h.position).grow(h.radius + 0.05), true): continue
				var hit = _sweep_modules(p, {}, h, hi)
				if not hit.is_empty(): contacts.append(hit)
				if p.type != "drill" or used_drills.has(p.id) or p.drill_power_ratio <= EPS or h.get("pilot_gate", false) or not h.get("destructible", true): continue
				var cut = _sweep_cutter(p, h, hi)
				if not cut.is_empty(): cut.cut = true; cut.q = -1; contacts.append(cut)
	for ai in range(bodies.size()):
		for bi in range(ai + 1, bodies.size()):
			if not bounds[bodies[ai].id].intersects(bounds[bodies[bi].id], true): continue
			for p in bodies[ai].parts:
				for q in bodies[bi].parts:
					if not p.alive or not q.alive or p.delivered or q.delivered: continue
					var hit = _sweep_modules(p, q, {}, -1)
					if not hit.is_empty(): contacts.append(hit)
	if contacts.is_empty(): return {}
	contacts.sort_custom(func(a, b):
		if a.time != b.time: return a.time < b.time
		if bool(a.get("cut", false)) != bool(b.get("cut", false)): return bool(a.get("cut", false))
		if a.p != b.p: return a.p < b.p
		if a.q != b.q: return a.q < b.q
		return a.h < b.h)
	return contacts[0]

func _apply_swept_impulse(hit: Dictionary) -> void:
	var p: Dictionary = parts[hit.p]
	var a = body_for_part(p.id)
	var q: Dictionary = parts.get(hit.q, {})
	var b = body_for_part(q.id) if not q.is_empty() else {}
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
	telemetry.swept_contacts = int(telemetry.get("swept_contacts", 0)) + 1

## A simultaneous collinear pile is a contact-constraint problem, not hundreds
## of repeated pairwise impacts at t=0. Solve each free-body chain in linear
## time with mass-weighted isotonic pooling. Multi-body pools are inelastic:
## every update is a momentum-conserving collision impulse, with no speed cap
## and no increase in kinetic energy. Isolated two-body hits retain restitution.
func _try_collinear_contacts(seed: Dictionary) -> bool:
	if seed.q < 0: return false
	var axis: Vector2 = seed.normal
	var all_contacts: Array = []; var contacts: Array = []; var nodes: Dictionary = {}
	var neighbors: Dictionary = {}; var seed_present = false
	for ai in range(bodies.size()):
		for bi in range(ai + 1, bodies.size()):
			var a: Dictionary = bodies[ai]; var b: Dictionary = bodies[bi]
			if a.position.distance_squared_to(b.position) > pow(float(a.get("extreme_bound_radius", 1.0)) + float(b.get("extreme_bound_radius", 1.0)) + 0.00002, 2.0): continue
			for p in a.parts:
				for q in b.parts:
					if not p.alive or not q.alive or p.delivered or q.delivered: continue
					var offset = _part_position(p) - _part_position(q)
					if offset.length() > 0.43 * (p.scale + q.scale) + 0.00002: continue
					var normal = offset.normalized()
					all_contacts.append({"p": p.id, "q": q.id, "h": -1, "time": 0.0, "normal": normal, "relative": (_part_velocity(p) - _part_velocity(q)).dot(normal)})
					if (p.id == seed.p and q.id == seed.q) or (q.id == seed.p and p.id == seed.q): seed_present = true
					if not neighbors.has(a.id): neighbors[a.id] = []
					if not neighbors.has(b.id): neighbors[b.id] = []
					if not neighbors[a.id].has(b.id): neighbors[a.id].append(b.id)
					if not neighbors[b.id].has(a.id): neighbors[b.id].append(a.id)
	# Only the touching island containing the actual seed may handle its event.
	# An unrelated oblique/resting cluster cannot veto or substitute for it.
	if not seed_present: return false
	var connected: Dictionary = {parts[seed.p].body_id: true}
	var queue: Array = [parts[seed.p].body_id]
	while not queue.is_empty():
		var id = queue.pop_front()
		for next in neighbors.get(id, []):
			if not connected.has(next): connected[next] = true; queue.append(next)
	for hit in all_contacts:
		var p: Dictionary = parts[hit.p]; var q: Dictionary = parts[hit.q]
		if not connected.has(p.body_id): continue
		var a = body_for_part(p.id); var b = body_for_part(q.id)
		if absf(hit.normal.dot(axis)) < 0.99999: return false
		if absf(p.local_pos.rotated(a.angle).cross(axis)) > 0.00001 or absf(q.local_pos.rotated(b.angle).cross(axis)) > 0.00001: return false
		contacts.append(hit); nodes[a.id] = a; nodes[b.id] = b
	if contacts.size() < 2: return false
	var ordered = nodes.values()
	ordered.sort_custom(func(a, b): return a.position.dot(axis) < b.position.dot(axis))
	var indices: Dictionary = {}
	for i in range(ordered.size()): indices[ordered[i].id] = i
	var adjacent: Dictionary = {}
	for hit in contacts:
		var ia: int = indices[parts[hit.p].body_id]; var ib: int = indices[parts[hit.q].body_id]
		if absi(ia - ib) != 1: return false
		adjacent[mini(ia, ib)] = true
	var first = 0
	while first < ordered.size():
		var last = first
		while adjacent.has(last): last += 1
		if last == first + 1:
			for hit in contacts:
				if parts[hit.p].body_id in [ordered[first].id, ordered[last].id] and parts[hit.q].body_id in [ordered[first].id, ordered[last].id]:
					_apply_swept_impulse(hit); break
		elif last > first + 1:
			var pools: Array = []; var incoming_momentum: Dictionary = {}
			for i in range(first, last + 1):
				var b: Dictionary = ordered[i]
				incoming_momentum[i] = b.velocity.dot(axis) * b.mass
				pools.append({"first": i, "last": i, "mass": b.mass, "momentum": incoming_momentum[i]})
				while pools.size() >= 2:
					var right: Dictionary = pools[-1]; var left: Dictionary = pools[-2]
					if left.momentum / left.mass <= right.momentum / right.mass: break
					pools.pop_back(); pools.pop_back()
					pools.append({"first": left.first, "last": right.last, "mass": left.mass + right.mass, "momentum": left.momentum + right.momentum})
			for pool in pools:
				var velocity: float = pool.momentum / pool.mass
				for i in range(pool.first, pool.last + 1):
					var b: Dictionary = ordered[i]
					b.velocity += axis * (velocity - b.velocity.dot(axis))
			var transmitted: Dictionary = {}; var cumulative = 0.0
			for i in range(first, last):
				var b: Dictionary = ordered[i]
				cumulative -= b.velocity.dot(axis) * b.mass - float(incoming_momentum[i])
				transmitted[i] = maxf(0.0, cumulative)
			for hit in contacts:
				var at = mini(indices[parts[hit.p].body_id], indices[parts[hit.q].body_id])
				if at < first or at >= last or float(transmitted.get(at, 0.0)) <= EPS: continue
				var p: Dictionary = parts[hit.p]; var q: Dictionary = parts[hit.q]
				# A resting edge can transmit a real impulse through a pile even
				# with zero initial approach speed. Sensors observe that contact;
				# impact HP damage still uses actual pre-impact approach speed.
				_mark_contact(body_for_part(p.id)); _mark_contact(body_for_part(q.id))
				if hit.relative < 0.0:
					_damage_part(p, 0.5 * p.mass * hit.relative * hit.relative * 0.45, "collision")
					_damage_part(q, 0.5 * q.mass * hit.relative * hit.relative * 0.45, "collision")
				telemetry.swept_contacts += 1
			telemetry.ccd_contact_pools = int(telemetry.get("ccd_contact_pools", 0)) + 1
		first = last + 1
	return true

func _sweep_cutter(p: Dictionary, h: Dictionary, hi: int) -> Dictionary:
	var b = body_for_part(p.id)
	var angle = _swept_angle(b)
	var lever: Vector2 = p.local_pos + Vector2.RIGHT.rotated(p.local_angle) * Expanded.DRILL_HEAD_OFFSET * p.scale
	var steps = clampi(int(ceil(absf(angle) / CCD_ANGLE)), 1, 128)
	var inflation = lever.length() * (1.0 - cos(minf(PI, absf(angle) / steps) * 0.5))
	if absf(angle) / steps > PI: inflation += lever.length() * 2.0
	var real_radius: float = h.radius + Expanded.DRILL_HEAD_RADIUS * p.scale
	for i in range(steps):
		var t0 = float(i) / steps; var t1 = float(i + 1) / steps
		var a0 = _cutter_position(p, t0); var a1 = _cutter_position(p, t1)
		var h0 = _hazard_trajectory(h, hi, t0); var h1 = _hazard_trajectory(h, hi, t1)
		var fraction = 0.0 if a0.distance_squared_to(h0) <= pow(real_radius + inflation, 2.0) else _segment_circle_t(a0 - h0, a1 - h1, real_radius + inflation)
		if fraction < 0.0: continue
		var time = lerpf(t0, t1, fraction)
		if inflation > 0.0000001:
			# Conservative hull inflation is not permission to damage a near miss.
			# Refine on the actual rotating cutter arc, then locate first overlap.
			var lo = t0; var hi_t = t1
			for refinement in range(18):
				var left = (2.0 * lo + hi_t) / 3.0; var right = (lo + 2.0 * hi_t) / 3.0
				if _cutter_distance_squared(p, h, hi, left) < _cutter_distance_squared(p, h, hi, right): hi_t = right
				else: lo = left
			var nearest = (lo + hi_t) * 0.5
			if _cutter_distance_squared(p, h, hi, t0) <= real_radius * real_radius: nearest = t0
			elif _cutter_distance_squared(p, h, hi, t1) < _cutter_distance_squared(p, h, hi, nearest): nearest = t1
			if _cutter_distance_squared(p, h, hi, nearest) > real_radius * real_radius: continue
			lo = t0; hi_t = nearest
			for refinement in range(18):
				var middle = (lo + hi_t) * 0.5
				if _cutter_distance_squared(p, h, hi, middle) <= real_radius * real_radius: hi_t = middle
				else: lo = middle
			time = hi_t
		var start_angle = float(_motion_bodies.get(b.id, {}).get("angle", b.angle))
		var direction = Vector2.RIGHT.rotated(lerpf(start_angle, b.angle, time) + p.local_angle)
		if (_hazard_trajectory(h, hi, time) - _trajectory(p, time)).dot(direction) <= 0.0: continue
		return {"p": p.id, "h": hi, "time": time, "point": _cutter_position(p, time)}
	return {}

func _cutter_distance_squared(p: Dictionary, h: Dictionary, hi: int, time: float) -> float:
	return _cutter_position(p, time).distance_squared_to(_hazard_trajectory(h, hi, time))

func _cutter_position(p: Dictionary, fraction: float) -> Vector2:
	var b = body_for_part(p.id)
	var start_angle = float(_motion_bodies.get(b.id, {}).get("angle", b.angle))
	return _trajectory(p, fraction) + Vector2.RIGHT.rotated(lerpf(start_angle, b.angle, fraction) + p.local_angle) * Expanded.DRILL_HEAD_OFFSET * p.scale

func _update_load_paths() -> void:
	_load_edges.clear()
	for b in bodies:
		var demand: Dictionary = {}; var actual = Vector2.ZERO
		for p in b.parts: actual += _source_forces.get(p.id, Vector2.ZERO)
		for p in b.parts:
			var r: Vector2 = p.local_pos.rotated(b.angle)
			var angular: Vector2 = Vector2(-r.y, r.x) * float(b.get("torque", 0.0)) / b.inertia - r * b.angular_velocity * b.angular_velocity
			demand[p.id] = actual * p.mass / b.mass + angular * p.mass - _source_forces.get(p.id, Vector2.ZERO)
			p.load = 0.0
		var edges: Array = []
		for link in links:
			if demand.has(link.a) and demand.has(link.b): edges.append(link)
		var solution = solve_socket_forces(demand, edges)
		var sum_load: Dictionary = {}
		for edge in solution:
			var force: Vector2 = edge.force
			_load_edges.append(edge)
			for id in [edge.a, edge.b]:
				parts[id].load = maxf(parts[id].load, force.length())
				sum_load[id] = float(sum_load.get(id, 0.0)) + force.length()
		for p in b.parts:
			p.load = maxf(p.load, float(sum_load.get(p.id, 0.0)) * 0.5)
			telemetry.peak_socket_load = maxf(float(telemetry.get("peak_socket_load", 0.0)), p.load)
			if p.type == "beam" and p.load > p.strength:
				var damage = (p.load - p.strength) * _tick_dt * 6.0
				telemetry.structure_damage = float(telemetry.get("structure_damage", 0.0)) + minf(p.hp, damage)
				super._damage_part(p, damage, "stress")

## Unit-stiffness socket-network equilibrium. A grounded graph Laplacian solves
## minimum squared edge force, sharing parallel paths. Deterministic conjugate
## gradients need at most 2N iterations; N is bounded by MAX_SIM_PARTS=192.
## Inputs must be one connected component with zero-sum node force demand.
static func solve_socket_forces(demand: Dictionary, edges: Array) -> Array:
	var ids = demand.keys(); ids.sort()
	if ids.size() <= 1 or edges.is_empty(): return []
	var index: Dictionary = {}
	for i in range(ids.size()): index[ids[i]] = i
	var indexed: Array = []
	for edge in edges: indexed.append(Vector2i(index[edge.a], index[edge.b]))
	var n = ids.size() - 1
	var x: Array = []; var r: Array = []; var direction: Array = []
	var rr = 0.0
	for i in range(n):
		x.append(Vector2.ZERO); r.append(demand[ids[i]]); direction.append(r[i]); rr += r[i].length_squared()
	var tolerance = maxf(1.0, rr) * 0.000000000000000001
	for iteration in range(ids.size() * 2):
		if rr <= tolerance: break
		var applied: Array = []; applied.resize(n); applied.fill(Vector2.ZERO)
		for edge in indexed:
			var delta: Vector2 = (direction[edge.x] if edge.x < n else Vector2.ZERO) - (direction[edge.y] if edge.y < n else Vector2.ZERO)
			if edge.x < n: applied[edge.x] += delta
			if edge.y < n: applied[edge.y] -= delta
		var denominator = 0.0
		for i in range(n): denominator += direction[i].dot(applied[i])
		if denominator <= 0.000000000000000001: break
		var alpha = rr / denominator; var next_rr = 0.0
		for i in range(n):
			x[i] += direction[i] * alpha; r[i] -= applied[i] * alpha; next_rr += r[i].length_squared()
		var beta = next_rr / rr
		for i in range(n): direction[i] = r[i] + direction[i] * beta
		rr = next_rr
	x.append(Vector2.ZERO)
	var result: Array = []
	for edge in edges: result.append({"a": edge.a, "b": edge.b, "force": x[index[edge.a]] - x[index[edge.b]]})
	return result

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	telemetry.control_version = Extreme.CONTROL_VERSION
	telemetry.overdrive = pilot_boost
	telemetry.thrust_requested = 0.0; telemetry.thrust_actual = 0.0
	for p in parts.values():
		if p.alive and p.type == "thruster":
			telemetry.thrust_requested += _planned_forces.get(p.id, Vector2.ZERO).length()
			telemetry.thrust_actual += p.get("pilot_force", Vector2.ZERO).length()
	for key in ["drill_energy_used", "drill_damage", "drill_contacts", "impact_absorbed", "impact_shield_energy", "peak_socket_load", "structure_damage", "ccd_budget_holds", "ccd_contact_pools", "ccd_event_rounds"]:
		if not telemetry.has(key): telemetry[key] = 0.0

	telemetry.control_version = VERSION
	telemetry.wormhole_transits = wormhole_events.size()
	telemetry.wormhole_station_remaining = _station_remaining
	telemetry.wormhole_energy_used = float(telemetry.get("wormhole_energy_used", 0.0))
	telemetry.wormhole_phase = "ascent"
	telemetry.wildlife_error = wildlife_error
	if _portal_ready:
		telemetry.wormhole_max_body_diameter = 2.0 * (float(route.wormhole_portal.aperture_radius) - float(route.wormhole_portal.margin))
		telemetry.wormhole_phase = "otherworld" if wildlife.get("activated", false) else ("space" if cargo_position().x >= float(route.get("pilot_climb_end", 410.0)) else "ascent")
	if _route_valid:
		telemetry.wildlife_result = wildlife_result()
		telemetry.wildlife_hp = float(wildlife.get("hp", 8.0))
		telemetry.wildlife_state = str(wildlife.get("state", "waiting"))


func _next_portal_contact(ordinary: Dictionary) -> Dictionary:
	if not _portal_ready: return ordinary
	var portal: Dictionary = route.wormhole_portal
	var entry = Vector2(float(portal.entry[0]), float(portal.entry[1]))
	var best: Dictionary = {}
	for body in bodies:
		if _body_used_portal(body, str(portal.id)) or _attempted_anchors.has(_anchor_id(body)): continue
		var start: Vector2 = _motion_bodies.get(body.id, {}).get("position", body.position)
		var finish: Vector2 = body.position
		if start.x > entry.x + EPS or finish.x < entry.x or finish.x <= start.x + EPS: continue
		var fraction = clampf((entry.x - start.x) / (finish.x - start.x), 0.0, 1.0)
		var anchor: int = _anchor_id(body)
		# An attempted crossing outside the visible disk is ordinary local flight.
		if absf(start.lerp(finish, fraction).y - entry.y) > float(portal.aperture_radius): continue
		var candidate = {"p": anchor, "q": -1, "h": -1, "time": fraction,
			"normal": Vector2.LEFT, "wormhole": true}
		if best.is_empty() or fraction < float(best.time) or (fraction == float(best.time) and anchor < int(best.p)):
			best = candidate
	# A physical collision wins a tie. The portal never erases a pending impact.
	if best.is_empty() or (not ordinary.is_empty() and float(ordinary.time) <= float(best.time)):
		return ordinary
	return best


func _apply_portal(hit: Dictionary) -> void:
	var body = body_for_part(int(hit.p))
	if body.is_empty(): return
	_attempted_anchors[_anchor_id(body)] = true
	var portal: Dictionary = route.wormhole_portal
	var portal_id = str(portal.id)
	if _body_used_portal(body, portal_id): return
	var radius = _body_bound(body)
	var entry = Vector2(float(portal.entry[0]), float(portal.entry[1]))
	# Conservatively fit the complete circumscribed hull, including the drill tip.
	# The supported large craft bound is explicit; never move clipped components.
	if absf(body.position.y - entry.y) + radius + float(portal.margin) > float(portal.aperture_radius):
		_deny(body, "too_large_or_off_center", "未进入虫洞：请对准洞口，或缩小飞船轮廓。"); return
	var exit_position = Vector2(float(portal.exit[0]), float(portal.exit[1]))
	var target = exit_position + Vector2(radius + float(portal.margin), body.position.y - entry.y)
	if not _safe_exit(body, target, radius, float(portal.exit_lookahead)):
		_deny(body, "exit_blocked", "出口被挡住了，本次无法通行。"); return
	var cost = float(portal.base_energy_j) + body.mass * float(portal.energy_j_per_kg)
	if not is_finite(cost) or cost > _station_remaining + EPS:
		_deny(body, "station_empty", "驿站通行电量不足，本次无法过洞。"); return
	var from: Vector2 = body.position
	body.position = target
	var ids: Array = []
	for p in body.parts:
		if not p.alive or p.delivered: continue
		var visited: Dictionary = p.get("wormhole_visits", {}).duplicate(true)
		visited[portal_id] = true; p.wormhole_visits = visited; ids.append(int(p.id))
		# The inherited receiver must sweep only the actual exit-side trajectory.
		_motion_parts[p.id] = _part_position(p)
	ids.sort()
	_station_remaining = maxf(0.0, _station_remaining - cost)
	telemetry.energy_used += cost
	telemetry.wormhole_energy_used = float(telemetry.get("wormhole_energy_used", 0.0)) + cost
	var event = {"portal_id": portal_id, "tick": pilot_tick, "part_ids": ids,
		"from": [from.x, from.y], "to": [target.x, target.y], "energy_j": cost}
	wormhole_events.append(event)
	if _contains_cargo(body): _activate_wildlife()
	_log("已通过晨星虫洞。")
	_effect("wormhole", target, from, 0.35)


func _safe_exit(body: Dictionary, target: Vector2, radius: float, seconds: float) -> bool:
	# A circumscribed body disk encloses every possible rotation during lookahead.
	# This intentionally rejects tight exits; it does not grant immunity afterward.
	var expanded = radius + float(route.wormhole_portal.margin)
	var finish: Vector2 = target + body.velocity * seconds
	if _live_bird():
		var relative: Vector2 = target - wildlife.position
		var relative_finish: Vector2 = finish - wildlife.position - wildlife.velocity * seconds
		var clearance: float = expanded + float(wildlife.radius)
		if relative.length() <= clearance or _segment_circle_t(relative, relative_finish, clearance) >= 0.0: return false
	if minf(target.x, finish.x) - expanded < -30.0: return false
	if maxf(absf(target.y), absf(finish.y)) + expanded > float(route.get("boundary_y", 80.0)): return false
	for hi in range(obstacles.size()):
		var hazard: Dictionary = obstacles[hi]
		if hazard.health <= 0.0 or hazard.type == "gravity": continue
		var at: Vector2 = _motion_hazards[hi] if hi < _motion_hazards.size() else hazard.position
		var relative: Vector2 = target - at
		var relative_finish: Vector2 = finish - at - hazard.get("velocity", Vector2.ZERO) * seconds
		var clearance: float = expanded + hazard.radius
		if relative.length() <= clearance or _segment_circle_t(relative, relative_finish, clearance) >= 0.0: return false
	for other in bodies:
		if other.id == body.id: continue
		var relative: Vector2 = target - other.position
		var relative_finish: Vector2 = finish - other.position - other.velocity * seconds
		var clearance = expanded + _body_bound(other)
		if relative.length() <= clearance or _segment_circle_t(relative, relative_finish, clearance) >= 0.0: return false
	return true

func _body_bound(body: Dictionary) -> float:
	var radius = 0.0
	for p in body.parts:
		if p.alive and not p.delivered:
			radius = maxf(radius, p.local_pos.length() + (0.48 if p.type == "drill" else 0.43) * p.scale)
	return radius

func _body_used_portal(body: Dictionary, id: String) -> bool:
	for p in body.parts:
		if p.get("wormhole_visits", {}).has(id): return true
	return false

func _anchor_id(body: Dictionary) -> int:
	var id = 2147483647
	for p in body.parts:
		if p.alive and not p.delivered: id = mini(id, int(p.id))
	return id

func _deny(body: Dictionary, reason: String, message: String) -> void:
	var key = "%s:%s" % [_anchor_id(body), reason]
	if not _denied_keys.has(key):
		_denied_keys[key] = true; _log(message)
	telemetry.wormhole_last_denial = reason

func _check_status() -> void:
	if _portal_ready:
		var portal: Dictionary = route.wormhole_portal
		for p in parts.values():
			if p.type != "cargo" or not p.alive or p.delivered: continue
			# Actual traversal is a delivery prerequisite; flying across the unused
			# coordinate gap or using a mounted teleporter cannot fake an arrival.
			if _part_position(p).x >= float(portal.exit[0]) and not p.get("wormhole_visits", {}).has(str(portal.id)):
				status = "failed"; _log("错过了虫洞，未能到达苔光驿站。"); return
	super._check_status()

func _register_source(p: Dictionary) -> void:
	source_registry[int(p.id)] = {"owner_kind": str(p.get("owner_kind", "")), "origin_part_id": int(p.get("origin_part_id", -1)), "part_type": str(p.type)}

func _source(p: Dictionary, action: String) -> Dictionary:
	return {"owner_kind": str(p.get("owner_kind", "")), "part_id": int(p.id),
		"origin_part_id": int(p.get("origin_part_id", -1)), "part_type": str(p.type), "action_kind": action}

func _split_module(p: Dictionary, target: Dictionary, b: Dictionary, dt: float) -> void:
	super._split_module(p, target, b, dt)
	for q in parts.values():
		if not source_registry.has(int(q.id)): _register_source(q)

func _live_bird() -> bool:
	return not wildlife.is_empty() and bool(wildlife.get("active", false)) and float(wildlife.get("hp", 0.0)) > 0.0

func _activate_wildlife() -> void:
	if wildlife.is_empty() or wildlife.activated: return
	wildlife.active = true; wildlife.activated = true; wildlife.state = "healthy"
	wildlife.activation_tick = pilot_tick; wildlife.activation_fraction = _tick_fraction
	_wild_start = wildlife.position
	_log("保护鸟穿越 · 从下方绕行")

func wildlife_result() -> Dictionary:
	return BirdFacts.result(route, pilot_tick, first_harm) if _route_valid and wildlife_error.is_empty() else {}

func _damage_wildlife(requested: float, source: Dictionary) -> float:
	if not _live_bird() or not is_finite(requested) or requested <= 0.0: return 0.0
	var before: float = wildlife.hp
	var after = maxf(0.0, before - requested)
	var delta = before - after
	if delta <= 0.0: return 0.0
	wildlife.hp = after; wildlife.damage_transitions += 1
	wildlife.hurt_ticks = 36
	wildlife.state = "hurt" if after > 0.0 else "falling"
	if after <= 0.0: wildlife.active = false; wildlife.fall_ticks = 0
	# Physical mutation and ownership are separate: an explicit non-courier
	# source may hurt the animal but can never manufacture a courier cause.
	if first_harm.is_empty() and source.get("owner_kind") == "courier":
		var at: Vector2 = wildlife.position
		var candidate = {"schema": BirdFacts.SCHEMA, "control_version": VERSION,
			"contract_id": route.contract_id, "event_id": wildlife.event_id, "entity_id": wildlife.entity_id,
			"species_id": wildlife.species_id, "harm_id": wildlife.entity_id + "/first-harm",
			"physics_tick": pilot_tick, "substep_fraction": _tick_fraction,
			"action_ordinal": maxi(1, _action_ordinal), "position": [at.x, at.y],
			"source": source.duplicate(true), "hp_before": before, "hp_after": after, "hp_delta": delta}
		var error = BirdFacts.validation_error(BirdFacts.result(route, pilot_tick, candidate), route, source_registry)
		if not error.is_empty(): _fail_wildlife("invalid_harm_source: " + error)
		else: first_harm = candidate
	return delta

func _fail_wildlife(reason: String) -> void:
	if wildlife_error.is_empty(): wildlife_error = reason; _log("保护鸟模拟未通过有限接触检查：" + reason)
	status = "failed"

func _next_contact(used_drills: Dictionary) -> Dictionary:
	var best = _next_portal_contact(_next_ordinary_contact(used_drills))
	if not _live_bird(): return best
	for body in bodies:
		for p in body.parts:
			if not p.alive or p.delivered: continue
			for cutting in [true, false]:
				if cutting and (p.type != "drill" or used_drills.has(p.id) or _paid_drill_ratio(p) <= EPS): continue
				var hit = _sweep_wildlife(p, cutting)
				if hit.get("unresolved", false):
					if best.is_empty() or float(hit.time) < float(best.time): best = hit
					continue
				if hit.is_empty(): continue
				if best.is_empty() or float(hit.time) < float(best.time): best = hit
				elif float(hit.time) == float(best.time):
					# Physical collision wins portal tie; paid cutter wins shell tie.
					if best.get("unresolved", false) or best.get("wormhole", false) or (cutting and not best.get("cut", false)): best = hit
					elif bool(hit.get("cut", false)) == bool(best.get("cut", false)) and int(hit.p) < int(best.p): best = hit
	return best

func _sweep_wildlife(p: Dictionary, cutting: bool) -> Dictionary:
	var body = body_for_part(p.id)
	var start: Dictionary = _motion_bodies[body.id]
	var lever: Vector2 = p.local_pos
	var radius: float = 0.43 * p.scale
	if cutting:
		lever += Vector2.RIGHT.rotated(p.local_angle) * Expanded.DRILL_HEAD_OFFSET * p.scale
		radius = Expanded.DRILL_HEAD_RADIUS * p.scale
	var swept = BirdSweep.solve(start.position, body.position, float(start.angle), body.angle,
		lever, _wild_start, wildlife.position, radius + float(wildlife.radius))
	if swept.state in ["invalid", "unresolved"]: return {"unresolved": true, "reason": swept.get("reason", "sweep"), "time": float(swept.get("a", 0.0))}
	if swept.state != "hit": return {}
	if cutting:
		var u: float = swept.time
		var angle = lerpf(float(start.angle), body.angle, u)
		var shell = start.position.lerp(body.position, u) + p.local_pos.rotated(angle)
		if (_wild_start.lerp(wildlife.position, u) - shell).dot(Vector2.RIGHT.rotated(angle + p.local_angle)) <= 0.0: return {}
	return {"p": p.id, "q": -1, "h": -1, "time": swept.time, "normal": swept.normal,
		"wildlife": true, "cut": cutting, "initial_overlap": swept.initial_overlap}

func _apply_wildlife_contact(hit: Dictionary) -> void:
	if not _live_bird(): return
	var p: Dictionary = parts[hit.p]
	var body = body_for_part(p.id)
	var arm: Vector2 = p.local_pos.rotated(body.angle)
	var relative: Vector2 = body.position - wildlife.position + arm
	var radius: float = 0.43 * p.scale + wildlife.radius
	if relative.length() > radius + POSE_TOLERANCE:
		_fail_wildlife("narrowphase_pose_mismatch"); return
	var normal: Vector2 = relative.normalized() if relative.length_squared() > 0.000000000001 else hit.normal
	var solved = BirdContact.solve(body.mass, body.inertia, body.velocity, body.angular_velocity,
		arm, wildlife.velocity, normal, wildlife.hp)
	if not solved.ok: _fail_wildlife(solved.reason); return
	body.velocity += solved.ship_velocity_delta; body.angular_velocity += solved.ship_angular_velocity_delta
	wildlife.velocity += solved.bird_velocity_delta
	_mark_contact(body)
	telemetry.wildlife_contacts = int(telemetry.get("wildlife_contacts", 0)) + 1
	_damage_wildlife(solved.hp_delta, _source(p, "contact"))
	# Separate real contact geometrically; do not suppress this part for a whole
	# tick, because a rotating part can legitimately return later in the tick.
	var correction = maxf(0.0, radius - relative.length()) + CONTACT_SLOP
	var inverse_sum: float = 1.0 / body.mass + 1.0 / float(wildlife.mass)
	body.position += normal * correction * (1.0 / body.mass) / inverse_sum
	wildlife.position -= normal * correction * (1.0 / float(wildlife.mass)) / inverse_sum

func destination_clear(body: Dictionary, displacement: Vector2) -> bool:
	if not super.destination_clear(body, displacement): return false
	if not _live_bird(): return true
	# Full rotating-body bound at destination and its declared clearance window.
	# There is deliberately no sweep through the skipped teleport gap.
	var centre: Vector2 = body.position + displacement
	var relative: Vector2 = centre - wildlife.position
	var finish: Vector2 = relative + (body.velocity - wildlife.velocity) * 0.22
	var clearance = _body_bound(body) + float(wildlife.radius) + 0.08
	return relative.length() > clearance and _segment_circle_t(relative, finish, clearance) < 0.0

func _ray_circle(origin: Vector2, direction: Vector2, centre: Vector2, radius: float) -> float:
	# V5 owns this correction. All callers pass a unit direction; inherited
	# beam/probe resolution dispatches here too, so occluders and wildlife use
	# one consistent forward half-ray. Old protocol helpers remain frozen.
	var offset = centre - origin
	var along = offset.dot(direction)
	var perpendicular_sq = offset.length_squared() - along * along
	if perpendicular_sq > radius * radius: return INF
	var half_chord = sqrt(maxf(0.0, radius * radius - perpendicular_sq))
	# along+radius is only a bounding test: the actual far root may still be
	# negative for a wholly-behind off-axis circle. Never clamp that to a hit.
	if along + half_chord < 0.0: return INF
	return maxf(0.0, along - half_chord)

func _fire_ray(p: Dictionary, reach: float, damage: float, chain: bool) -> void:
	# Ordinary beam damage/chain logic is inherited; the v5-owned forward-root
	# query applies to every candidate. Bird must be strictly nearer than every
	# live obstacle/detached module. Equal distances remain occluded.
	if not _live_bird(): super._fire_ray(p, reach, damage, chain); return
	var body = body_for_part(p.id)
	var origin = _part_position(p)
	var direction = Vector2.RIGHT.rotated(body.angle + p.local_angle)
	var nearest = reach
	for h in obstacles:
		if h.health <= 0.0 or h.type == "gravity": continue
		nearest = minf(nearest, _ray_circle(origin, direction, h.position, h.radius))
	for other in bodies:
		if other.id == body.id: continue
		for q in other.parts:
			if q.alive and not q.delivered: nearest = minf(nearest, _ray_circle(origin, direction, _part_position(q), 0.43 * q.scale))
	var distance = _ray_circle(origin, direction, wildlife.position, wildlife.radius)
	if distance >= nearest: super._fire_ray(p, reach, damage, chain); return
	_damage_wildlife(damage, _source(p, "arc" if chain else "lance"))
	if p.cooldown <= 0.0:
		_effect("arc" if chain else "lance", origin, origin + direction * distance, 0.12)
		p.cooldown = 0.09

func _explode(p: Dictionary) -> void:
	# Capture source before old implementation consumes/destroys this bomb.
	var source = _source(p, "bomb")
	var centre = _part_position(p)
	var radius = maxf(0.5, p.param)
	var strength = 95.0 * p.output_factor
	var bird_damage = 0.0
	if _live_bird():
		var distance: float = wildlife.position.distance_to(centre)
		if distance < radius + float(wildlife.radius): bird_damage = strength * maxf(0.0, 1.0 - distance / (radius + float(wildlife.radius)))
	super._explode(p)
	_damage_wildlife(bird_damage, source)
