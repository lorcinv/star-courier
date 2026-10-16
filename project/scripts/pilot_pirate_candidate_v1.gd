extends "res://scripts/pilot_extreme_simulation.gd"
## REVIEW-ONLY. Direct construction in tests, never registered in Main.
## Consumes actual frozen courier design/control/circuit/graph implementations.
const Actor = preload("res://scripts/pirate_actor_reconstructed_v1.gd")
const Chronology = preload("res://scripts/pirate_chronology_v1.gd")
const Motion = preload("res://scripts/common_motion_v1.gd")
const Snapshot = preload("res://scripts/pirate_candidate_snapshot_v1.gd")
const CANDIDATE = "unregistered-pirate-chronology-candidate-2"
const REBUILD_PART_FIELDS = ["world_pos", "world_angle", "world_velocity", "old_angular_velocity", "old_force", "local_pos", "local_angle", "body_id"]
const SUPPORTED_PARTS = ["cargo", "beam", "battery", "thruster", "armor", "coupler", "shield", "valve", "collision", "delay", "and_gate", "or_gate", "not_gate"]
var pirate: Dictionary = {}
var pirate_body: Dictionary = {}
var chrono_fraction = 0.0
var chrono_error = ""
var chrono_paused = false
var chrono_trace: Array = []
var chrono_reservations: Array = []
var chrono_command: Dictionary = {"warning_request": null, "cancel_warning": false}
var _chrono_due: Array = []
var _chrono_hazards: Array = []
var _chrono_planning_source = -1
var _chrono_consumed = 0.0

func configure_candidate(design: Array, launcher: Array, route_data: Dictionary, definition: Dictionary, random_seed: int = 1) -> Dictionary:
	var checked = Actor.configure(definition)
	if not checked.ok: return checked
	for p in design:
		if not _chrono_supports_part(p.get("type", "")): return {"ok": false, "error": "unsupported_candidate_device:" + str(p.get("type", ""))}
	for h in route_data.get("hazards", []):
		if h.get("type", "rock") in ["gravity", "pirate", "tracker", "turret"]: return {"ok": false, "error": "unsupported_candidate_hazard"}
	if route_data.has("wormhole_portal") or route_data.has("ecology"): return {"ok": false, "error": "unsupported_candidate_route_event"}
	pirate = {}; pirate_body = {}; chrono_error = ""; chrono_fraction = 0.0; chrono_paused = false
	chrono_trace.clear(); chrono_reservations.clear(); _chrono_due.clear(); _chrono_hazards.clear()
	chrono_command = Actor.neutral_command()
	super.configure(design, launcher, route_data, random_seed)
	# Explicitly mark this object's telemetry only. No route protocol is added.
	pirate = checked.state
	pirate_body = {"id": -1, "position": Vector2(pirate.x, pirate.y), "velocity": Vector2(pirate.vx, pirate.vy),
		"angle": 0.0, "angular_velocity": 0.0, "mass": 6.0, "inertia": 6.75, "acceleration": Vector2.ZERO, "alpha": 0.0, "hp": pirate.hp}
	for h in obstacles:
		_chrono_hazards.append({"position": h.position, "velocity": h.velocity, "angle": 0.0, "angular_velocity": 0.0,
			"acceleration": Vector2.ZERO, "alpha": 0.0, "mass": h.mass, "inertia": 1.0})
	_refresh_telemetry()
	return {"ok": status == "running", "candidate": CANDIDATE}

func _chrono_supports_part(kind: Variant) -> bool:
	return kind in SUPPORTED_PARTS

func _chrono_after_paid_action(_part: Dictionary, _body: Dictionary, _dt: float, _activation: Dictionary, _consumed_j: float) -> void:
	pass

func step(dt: float) -> void:
	if chrono_paused or not chrono_error.is_empty(): return
	super.step(dt)

func set_paused(value: bool) -> void:
	chrono_paused = value
	if value: set_pilot_input(0, false, false)

func set_pirate_command(command: Dictionary) -> void:
	chrono_command = command.duplicate(true)

func _tick(dt: float) -> void:
	if pirate.is_empty(): chrono_error = "candidate_not_configured"; return
	var next = Actor.advance(pirate, pilot_tick, true, chrono_command)
	if not next.ok: chrono_error = next.error; return
	pirate = next.state; _chrono_due.clear()
	for notice in next.intents:
		if notice.kind == "shot_due": _chrono_due.append(notice.event_id)
	chrono_command = Actor.neutral_command()
	pilot_tick += 1; _tick_dt = dt; chrono_fraction = 0.0
	_planned_bodies.clear(); _planned_forces.clear(); _motion_bodies.clear(); _motion_parts.clear(); _motion_hazards.clear()
	_sources_live = false; _source_forces.clear(); _shield_spent.clear(); _shield_valve_spent.clear(); _paid_drills.clear(); _load_edges.clear()
	chrono_reservations.clear(); chrono_trace.clear()
	if _graph_dirty: _chrono_rebuild()
	for body in bodies:
		_motion_bodies[body.id] = {"position": body.position, "angle": body.angle}
		body.force = Vector2.ZERO; body.torque = 0.0
		# Legacy environmental drag is a once-per-tick dissipative kick, with no
		# collision splitting able to replay it or spend a resource again.
		var kinetic: float = 0.5 * body.mass * body.velocity.length_squared()
		body.velocity *= exp(-maxf(0.0, float(route.get("pilot_drag", 0.0))) * dt / body.mass)
		telemetry.heat += kinetic - 0.5 * body.mass * body.velocity.length_squared()
	for h in obstacles: _motion_hazards.append(h.position)
	for effect in effects: effect.ttl -= dt
	effects = effects.filter(func(effect): return effect.ttl > 0.0)
	for p in parts.values():
		if not p.alive or p.delivered: continue
		_motion_parts[p.id] = _part_position(p)
		p.param = PartData.sanitize_parameter(p.type, p.param)
		p.contact = p.next_contact; p.next_contact = false; p.previous_signal = p.signal
		p.cooldown = maxf(0.0, p.cooldown - dt)
		if p.type == "thruster": p.pilot_force = Vector2.ZERO; p.pilot_throttle = 0.0
	_update_signals(dt)
	_charge_springs(dt)
	var ids = parts.keys(); ids.sort()
	for id in ids:
		var p: Dictionary = parts[id]
		if not p.alive or p.delivered: continue
		var body = body_for_part(id)
		if body.is_empty(): continue
		p.active = _enabled(p)
		var rising: bool = p.active and not p.get("was_active", false)
		p.was_active = p.active
		if p.active:
			var activation = _chrono_activation(p)
			_chrono_planning_source = int(id); _chrono_consumed = 0.0
			var before: Vector2 = body.force
			super._act(p, body, dt, rising)
			_chrono_after_paid_action(p, body, dt, activation, _chrono_consumed)
			if p.type == "thruster":
				var force: Vector2 = body.force - before
				var servo = float(telemetry.assist_energy_used) - float(telemetry.get("chrono_previous_servo", 0.0))
				telemetry.chrono_previous_servo = telemetry.assist_energy_used
				chrono_reservations.append({"source_id": int(id), "intent_id": "%d:%d" % [pilot_tick - 1, id], "force": force,
					"reserved_j": _chrono_consumed, "work_cap_j": maxf(0.0, _chrono_consumed - servo),
					"impulse_cap_ns": force.length() * dt, "work_j": 0.0, "impulse_ns": 0.0,
					"live": true, "refund_j": 0.0, "additional_debit_j": 0.0, "body_id": -1, "torque": 0.0,
					"binding_parts": [], "binding_revision": 0, "activation": activation})
			_chrono_planning_source = -1
		p.forced_signal = false
		if _graph_dirty: _chrono_rebuild()
	_sources_live = false
	var result = _run_chronology(dt)
	for i in obstacles.size(): obstacles[i].position = _chrono_hazards[i].position
	elapsed = (float(pilot_tick - 1) + result.fraction) * dt
	if not result.ok:
		# Held is a terminal review gate, not a skipped interval. Callers must not
		# continue ticks or present a successful flight after this explicit stop.
		status = "held"; _refresh_telemetry(); return
	_refresh_telemetry()
	# Existing receiver/economy code is intentionally not claimed as integrated:
	# this finite test seam records physics, without completing or settling jobs.

func _run_chronology(dt: float) -> Dictionary:
	return Chronology.run(self, dt)

func _consume(body: Dictionary, desired: float, consumer_id: int, dt: float, rate_limit: bool = true) -> float:
	var ratio = super._consume(body, desired, consumer_id, dt, rate_limit)
	if consumer_id == _chrono_planning_source: _chrono_consumed += desired * ratio
	return ratio

func _chrono_rebuild() -> void:
	if not _graph_dirty: return
	_sources_live = false
	# The frozen graph builder renumbers/reconstructs EVERY body. Preserve the
	# frame and cached part values for components whose physical membership did
	# not change; a remote death must not reconstruct their COM/inertia/moment.
	var unchanged: Dictionary = {}
	for body in bodies:
		var cached: Dictionary = {}
		for p in body.parts:
			var fields: Dictionary = {}
			for key in REBUILD_PART_FIELDS:
				if p.has(key): fields[key] = p[key]
			cached[int(p.id)] = fields
		unchanged[_chrono_component_key(body)] = {"body": body, "parts": cached}
	_rebuild_bodies()
	for i in bodies.size():
		var key = _chrono_component_key(bodies[i])
		if not unchanged.has(key): continue
		var saved: Dictionary = unchanged[key]
		for p in saved.body.parts:
			for field in REBUILD_PART_FIELDS:
				if saved.parts[p.id].has(field): p[field] = saved.parts[p.id][field]
				else: p.erase(field)
		bodies[i] = saved.body
	_bodies_by_id.clear()
	for body in bodies: _bodies_by_id[int(body.id)] = body
	# Never use the frozen inherited old_force redistribution as continuing
	# propulsion. Original live source identities rebind below after the cut.
	for body in bodies: body.force = Vector2.ZERO; body.torque = 0.0

func _chrono_fields() -> void:
	var environment = _vector(route.get("wind", Vector2.ZERO)) + Vector2(0.0, float(route.get("gravity", 0.0)))
	for body in bodies:
		body.acceleration = environment; body.alpha = 0.0; body.force = Vector2.ZERO; body.torque = 0.0
	for reservation in chrono_reservations:
		if not reservation.live: continue
		var p: Dictionary = parts.get(reservation.source_id, {})
		if p.is_empty() or not p.alive or p.delivered or not _chrono_activation_connected(p, reservation.activation):
			reservation.live = false; continue
		var body = body_for_part(p.id)
		if body.is_empty(): reservation.live = false; continue
		# Freeze the paid segment's moment, just like its world-space force.
		# An unrelated contact must not introduce an extra torque integration
		# sample. A genuine graph cut rebinds the surviving source once.
		var membership = _chrono_component_ids(body)
		if reservation.binding_parts != membership:
			reservation.binding_parts = membership
			reservation.binding_revision += 1
			reservation.torque = p.local_pos.rotated(body.angle).cross(reservation.force)
		reservation.body_id = body.id
		body.force += reservation.force; body.torque += reservation.torque
	for body in bodies:
		body.acceleration += body.force / body.mass; body.alpha = body.torque / body.inertia

func _chrono_component_ids(body: Dictionary) -> Array:
	var ids: Array = []
	# Include all previous members before a rebuild, including a just-destroyed
	# part. Filtering it early would falsely label the smaller child unchanged.
	for p in body.parts: ids.append(int(p.id))
	ids.sort()
	return ids

func _chrono_component_key(body: Dictionary) -> String:
	return JSON.stringify(_chrono_component_ids(body))

func _chrono_activation(p: Dictionary) -> Dictionary:
	if p.forced_signal: return {"kind": "forced_tick", "controller_ids": []}
	if p.input_a == COCKPIT_SIGNAL:
		var ids: Array = []
		for source in parts.values():
			if source.type == "cargo" and _same_circuit(p, source): ids.append(int(source.id))
		ids.sort()
		return {"kind": "cockpit_tick", "controller_ids": ids}
	if p.input_a >= 0: return {"kind": "wire_tick", "controller_ids": [int(p.input_a)]}
	return {"kind": "continuous_tick", "controller_ids": []}

func _chrono_activation_connected(p: Dictionary, activation: Dictionary) -> bool:
	# Input/trigger activation is sampled once when the reservation is paid.
	# Clearing the one-tick signal cannot revoke an already-authorized impulse.
	# Actual source death or destruction/severing of its required original
	# control path still cancels continuing application immediately.
	if activation.kind in ["forced_tick", "continuous_tick"]: return true
	for id in activation.controller_ids:
		if parts.has(id) and _same_circuit(p, parts[id]): return true
	return false

func _chrono_entities() -> Array:
	var result: Array = []
	for body in bodies:
		var modules: Array = []
		for p in body.parts:
			if p.alive and not p.delivered: modules.append({"id": int(p.id), "lever": p.local_pos, "radius": 0.43 * p.scale, "mass": p.mass})
		result.append({"key": "courier:%08d" % body.id, "kind": "courier", "body": body, "fixed": false, "modules": modules})
	for i in obstacles.size():
		var h: Dictionary = obstacles[i]
		if h.health <= 0.0: continue
		result.append({"key": "obstacle:%08d" % i, "kind": "obstacle", "body": _chrono_hazards[i], "fixed": true,
			"modules": [{"id": i, "lever": Vector2.ZERO, "radius": h.radius, "mass": h.mass}]})
	result.append({"key": "pirate", "kind": "pirate", "source_id": pirate.definition.id, "body": pirate_body, "fixed": false,
		"modules": [{"id": -1, "lever": Vector2.ZERO, "radius": 1.5, "mass": 6.0}]})
	result.sort_custom(func(a, b): return a.key < b.key)
	return result

func _chrono_contact(event: Dictionary) -> void:
	elapsed = (float(event.tick) + event.fraction) * _tick_dt
	var damage_a = 0.225 * event.p.mass * event.relative * event.relative
	var damage_b = 0.225 * event.q.mass * event.relative * event.relative
	if event.a.kind == "courier":
		_mark_contact(event.a.body); _damage_part(parts[event.p.id], damage_a, "collision")
	elif event.a.kind == "pirate": pirate_body.hp = maxf(0.0, pirate_body.hp - damage_a)
	else: obstacles[event.p.id].health -= damage_b * 0.6
	if event.b.kind == "courier":
		_mark_contact(event.b.body); _damage_part(parts[event.q.id], damage_b, "collision")
	elif event.b.kind == "pirate": pirate_body.hp = maxf(0.0, pirate_body.hp - damage_b)
	else: obstacles[event.q.id].health -= damage_a * 0.6
	telemetry.swept_contacts = int(telemetry.get("swept_contacts", 0)) + 1
	chrono_trace.append({"kind": "contact", "tick": event.tick, "fraction": event.fraction, "phase": event.phase,
		"ordinal": event.ordinal, "a": event.a.key, "b": event.b.key, "p": event.p.id, "q": event.q.id,
		"impulse_ns": event.impulse_ns, "relative": event.relative, "witness_distance": event.witness_distance})

func _chrono_commit_actor(fraction: float) -> bool:
	var result = Actor.rebase(pirate, {"actor_id": pirate.definition.id, "tick": pilot_tick - 1, "fraction": fraction,
		"revision": int(pirate.revision) + 1, "x": float(pirate_body.position.x), "y": float(pirate_body.position.y),
		"vx": float(pirate_body.velocity.x), "vy": float(pirate_body.velocity.y), "hp": float(pirate_body.hp)})
	if not result.ok: chrono_error = result.error; return false
	pirate = result.state
	return true

func _chrono_emission_due() -> bool:
	return not _chrono_due.is_empty()

func _chrono_emit() -> Dictionary:
	var id: String = _chrono_due.pop_front()
	var result = Actor.commit_emission(pirate, id, pilot_tick - 1, 0.0)
	if result.ok: pirate = result.state
	return result

func _chrono_ray(ray: Dictionary, target: Dictionary, ordinal: int) -> void:
	elapsed = (float(ray.tick) + ray.fraction) * _tick_dt
	chrono_trace.append({"kind": "ray", "tick": ray.tick, "fraction": ray.fraction, "phase": 1, "ordinal": ordinal,
		"intent_id": ray.intent_id, "target": target.get("key", "miss"), "energy_mj": ray.energy_mj})
	if target.is_empty(): return
	if target.entity.kind == "courier": _damage_part(parts[target.module.id], ray.damage_hp, "attack")
	elif target.entity.kind == "obstacle": obstacles[target.module.id].health -= ray.damage_hp

func _chrono_power(reservation: Dictionary) -> Dictionary:
	var body = _body_by_id(reservation.body_id)
	if body.is_empty(): return {"power": 0.0, "slope": 0.0}
	return {"power": reservation.force.dot(body.velocity) + reservation.torque * body.angular_velocity,
		"slope": reservation.force.dot(body.acceleration) + reservation.torque * body.alpha}

func _chrono_force_boundary(seconds: float) -> Dictionary:
	var first = seconds; var ids: Array = []
	for i in chrono_reservations.size():
		var r: Dictionary = chrono_reservations[i]
		if not r.live: continue
		var limit = seconds; var exhausted = false
		var force: float = r.force.length()
		if force > 0.0:
			var impulse_time = maxf(0.0, r.impulse_cap_ns - r.impulse_ns) / force
			if impulse_time <= limit: limit = impulse_time; exhausted = true
		var power = _chrono_power(r)
		var budget = maxf(0.0, r.work_cap_j - r.work_j)
		if Chronology.positive_work(power.power, power.slope, limit) >= budget:
			var low = 0.0; var high = limit
			for j in range(60):
				var mid = (low + high) * 0.5
				if Chronology.positive_work(power.power, power.slope, mid) <= budget: low = mid
				else: high = mid
			limit = low; exhausted = true
		if limit < first: first = limit; ids = [i] if exhausted else []
		elif limit == first and exhausted: ids.append(i)
	return {"seconds": first, "ids": ids}

func _chrono_apply_resources(seconds: float) -> void:
	for r in chrono_reservations:
		if not r.live: continue
		var power = _chrono_power(r)
		r.work_j += Chronology.positive_work(power.power, power.slope, seconds)
		r.impulse_ns += r.force.length() * seconds

func destination_clear(body: Dictionary, displacement: Vector2) -> bool:
	if not super.destination_clear(body, displacement): return false
	if pirate_body.is_empty(): return true
	var proposed: Dictionary = body.duplicate(false)
	proposed.position = body.position + displacement
	# This is the same explicit coasting clearance horizon used by frozen
	# pilot dispatch; no future thrust is assumed to make an exit safe.
	proposed.acceleration = Vector2.ZERO; proposed.alpha = 0.0
	for p in body.parts:
		if not p.alive or p.delivered: continue
		var radius: float = 0.43 * p.scale + 0.08 + 1.5
		if Motion.sample(proposed, p.local_pos, 0.0).position.distance_to(pirate_body.position) <= radius: return false
		var sweep = Motion.sweep(proposed, p.local_pos, pirate_body, Vector2.ZERO, radius, 0.22)
		if sweep.state != "miss": return false
	return true

func _chrono_exhaust(ids: Array) -> void:
	for i in ids: chrono_reservations[i].live = false

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	telemetry.review_candidate = CANDIDATE
	telemetry.chrono_error = chrono_error
	if not pirate.is_empty():
		telemetry.pirate_hp = pirate.hp; telemetry.pirate_spent_mj = pirate.spent_mj
		telemetry.pirate_courier_billable_j = 0.0

func save_candidate_json() -> Dictionary:
	return Snapshot.save(self)

func load_candidate_json(text: String) -> Dictionary:
	return Snapshot.restore(self, text)
