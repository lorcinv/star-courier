extends "res://scripts/pilot_ascent_simulation.gd"
## pilot-v3 adds overdrive, source/socket stress, contact drill, impact shield
## and chronological CCD. Free-flight work/logic/circuits/assistance stay inherited.
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
	_sources_live = false
	_source_forces.clear(); _shield_spent.clear(); _shield_valve_spent.clear(); _paid_drills.clear(); _load_edges.clear()
	super.configure(design.slice(0, MAX_SIM_PARTS), launcher, route_data, random_seed)
	if design.size() > MAX_SIM_PARTS:
		status = "failed"
		_log("极限试飞取消：蓝图超过 192 个模块的安全上限。")
		_finalize_recovery()
	route.control_version = Extreme.CONTROL_VERSION
	route.pilot_profile = Extreme.CONTROL_VERSION
	_refresh_telemetry()

func _new_part(raw: Dictionary) -> Dictionary:
	if raw.get("type", "") not in ["drill","heater","airbrake","solid_booster"]: return super._new_part(raw)
	var safe = raw.duplicate(true); safe.type = "beam"
	var p = super._new_part(safe)
	var kind:String=str(raw.type)
	var spec = Expanded.catalog()[kind]
	p.type = kind; p.mass = spec.mass; p.price = spec.price
	p.hp = 60.0; p.max_hp = 60.0; p.strength = 90.0; p.param = 0.0
	p.input_a = int(raw.get("input_a", -1)); p.input_b = -1; p.target = -1
	p.drill_power_ratio = 0.0
	if kind=="solid_booster":
		p.solid_fuel_fraction=1.0; p.solid_lit=false; p.solid_throttle=0.0
	return p

func _tick(dt: float) -> void:
	_sources_live = false
	_source_forces.clear(); _shield_spent.clear(); _shield_valve_spent.clear(); _paid_drills.clear()
	for p in parts.values():
		if p.type == "drill": p.drill_power_ratio = 0.0
	super._tick(dt)
	_sources_live = false
	_update_solid_mass()

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
	_sources_live = true
	if p.type == "solid_booster":
		_apply_solid_booster(p,b,dt)
		return
	if p.type == "heater": return # Paid only at actual cold-exposure update.
	if p.type == "airbrake":
		_apply_airbrake(p,b,dt)
		return
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

func _air_density_drag(position:Vector2)->float:
	if route.has("ascent_layers"):
		return float(load("res://scripts/delivery_ascent_environment_v1.gd").at(route,position).drag)
	return maxf(0.0,float(route.get("pilot_drag",0.0)))

func _apply_airbrake(p:Dictionary,b:Dictionary,dt:float)->void:
	var density:float=_air_density_drag(_part_position(p))
	if density<=0.0:return
	var lever:Vector2=p.local_pos.rotated(b.angle)
	var local_velocity:Vector2=b.velocity+Vector2(-lever.y,lever.x)*float(b.angular_velocity)
	if local_velocity.length_squared()<=EPS:return
	var direction:Vector2=local_velocity.normalized()
	var inverse_mass:float=1.0/maxf(EPS,float(b.mass))+pow(lever.cross(direction),2)/maxf(EPS,float(b.inertia))
	var count:int=0
	for module in b.parts:
		if module.alive and module.type=="airbrake":count+=1
	# Bound one tick's dissipative impulse; never reverse local flow or add energy.
	var coefficient:float=minf(density*Expanded.AIRBRAKE_DRAG_MULTIPLIER*float(p.output_factor),0.5/(maxf(EPS,dt)*inverse_mass*maxi(1,count)))
	var force:Vector2=-local_velocity*coefficient
	b.force+=force;b.torque+=lever.cross(force)
	_source_forces[p.id]=_source_forces.get(p.id,Vector2.ZERO)+force
	telemetry.airbrake_work=float(telemetry.get("airbrake_work",0.0))+maxf(0.0,-force.dot(local_velocity)*dt)
	telemetry.airbrake_active_seconds=float(telemetry.get("airbrake_active_seconds",0.0))+dt
	p.airbrake_force=force

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
		var fraction = clampf(float(hit.time), 0.0, 1.0)
		# Advance ALL bodies to the common event time before applying an impulse.
		# Subsequent sweeps use the changed motion, including already-hit bodies.
		for b in bodies:
			var start: Dictionary = _motion_bodies.get(b.id, {"position": b.position - b.velocity * _tick_dt * remaining, "angle": b.angle - b.angular_velocity * _tick_dt * remaining})
			b.position = start.position.lerp(b.position, fraction)
			b.angle = lerpf(start.angle, b.angle, fraction)
		for hi in range(obstacles.size()):
			if hi < _motion_hazards.size(): _motion_hazards[hi] = _motion_hazards[hi].lerp(obstacles[hi].position, fraction)
		var p: Dictionary = parts[hit.p]
		if hit.get("cut", false):
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

func _sweep_modules(p: Dictionary, q: Dictionary, h: Dictionary, hi: int) -> Dictionary:
	if _skip_inherited_sweeps: return {}
	return super._sweep_modules(p, q, h, hi)

func _next_contact(used_drills: Dictionary) -> Dictionary:
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

# Solid fuel is independent stored propellant, never electric charge.
func _enabled(p:Dictionary)->bool:
	if p.type=="solid_booster" and bool(p.get("solid_lit",false)):
		return p.alive and not p.delivered and float(p.get("solid_fuel_fraction",0.0))>EPS
	return super._enabled(p)

func _apply_solid_booster(p:Dictionary,b:Dictionary,dt:float)->void:
	var remaining:float=clampf(float(p.get("solid_fuel_fraction",0.0)),0.0,1.0)
	p.solid_throttle=0.0
	if remaining<=EPS:return
	if not bool(p.get("solid_lit",false)):
		p.solid_lit=true;_log("固体助推器 #%d 点火：不可关停，燃料最多12秒。"%int(p.id))
	var fraction:float=minf(remaining,dt/Expanded.SOLID_BURN_SECONDS)
	var material:float=clampf(float(p.output_factor),0.0,1.0)
	var throttle:float=fraction*Expanded.SOLID_BURN_SECONDS/maxf(EPS,dt)
	var force:Vector2=Vector2.RIGHT.rotated(float(b.angle)+float(p.local_angle))*Expanded.SOLID_THRUST*material*throttle
	var lever:Vector2=p.local_pos.rotated(b.angle)
	b.force+=force;b.torque+=lever.cross(force)
	_source_forces[p.id]=_source_forces.get(p.id,Vector2.ZERO)+force
	p.solid_fuel_fraction=maxf(0.0,remaining-fraction);p.solid_throttle=throttle*material
	telemetry.solid_fuel_used=float(telemetry.get("solid_fuel_used",0.0))+fraction*material*Expanded.SOLID_FUEL_MASS
	telemetry.solid_impulse=float(telemetry.get("solid_impulse",0.0))+force.length()*dt
	var previous_fuel_cost:float=float(telemetry.get("solid_fuel_cost",0.0))
	var raw_fuel_cost:float=float(telemetry.get("solid_fuel_cost_raw",0.0))+fraction*material*Expanded.SOLID_REFILL_COST
	telemetry.solid_fuel_cost_raw=raw_fuel_cost
	# Preserve unrounded accumulation; normalize only the new fuel contribution.
	# This prevents exact partial/full charges crossing ceil by floating noise.
	var fuel_cost:float=snappedf(raw_fuel_cost,0.000000001)
	telemetry.ammo_cost=float(telemetry.get("ammo_cost",0.0))-previous_fuel_cost+fuel_cost
	telemetry.solid_fuel_cost=fuel_cost
	if float(p.solid_fuel_fraction)<=EPS:
		p.solid_fuel_fraction=0.0;p.solid_throttle=0.0
		_log("固体助推器 #%d 燃尽：只剩壳体，不可再次点火。"%int(p.id))

func _update_solid_mass()->void:
	# Only changed components. Removed propellant carries its local velocity;
	# thrust accounts for exhaust reaction. Preserve every surviving point's
	# world pose/velocity and the world's accumulated force moment.
	for b in bodies:
		var changed:bool=false
		for p in b.parts:
			if p.type!="solid_booster":continue
			var next:float=(Expanded.SOLID_DRY_MASS+Expanded.SOLID_FUEL_MASS*float(p.get("solid_fuel_fraction",1.0)))*float(p.output_factor)
			if absf(float(p.mass)-next)>EPS:p.mass=next;changed=true
		if not changed:continue
		var mass:float=0.0;var local_centre:Vector2=Vector2.ZERO
		for p in b.parts:mass+=float(p.mass);local_centre+=p.local_pos*float(p.mass)
		local_centre/=maxf(EPS,mass)
		var shift:Vector2=local_centre.rotated(b.angle)
		b.position+=shift;b.velocity+=Vector2(-shift.y,shift.x)*float(b.angular_velocity)
		b.torque=float(b.get("torque",0.0))-shift.cross(b.get("force",Vector2.ZERO))
		var inertia:float=0.0
		for p in b.parts:
			p.local_pos-=local_centre
			inertia+=float(p.mass)*(p.local_pos.length_squared()+1.0/6.0)
		b.mass=mass;b.inertia=maxf(EPS,inertia)
