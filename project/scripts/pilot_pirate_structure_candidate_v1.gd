extends "res://scripts/pilot_pirate_candidate_v1.gd"
## REVIEW-ONLY structure extension; no Main/route version registration.
const StructureClock = preload("res://scripts/pirate_structure_chronology_v1.gd")
const StructureSnapshot = preload("res://scripts/pirate_structure_snapshot_v1.gd")
const Value = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const STRUCTURE_CANDIDATE = "unregistered-pirate-structure-candidate-4"
const STRUCTURE_SNAPSHOT = "pirate-structure-native-snapshot-2"
var chrono_stress: Dictionary = {}
var chrono_stress_dirty: Dictionary = {}
var chrono_pending_breaks: Array = []

func configure_candidate(design: Array, launcher: Array, route_data: Dictionary, definition: Dictionary, random_seed: int = 1) -> Dictionary:
	chrono_stress.clear(); chrono_stress_dirty.clear(); chrono_pending_breaks.clear()
	var result = super.configure_candidate(design, launcher, route_data, definition, random_seed)
	if result.ok: result.candidate = STRUCTURE_CANDIDATE
	return result

func _tick(dt: float) -> void:
	chrono_stress.clear(); chrono_stress_dirty.clear(); chrono_pending_breaks.clear()
	super._tick(dt)

func _run_chronology(dt: float) -> Dictionary:
	for r in chrono_reservations:
		r.paid_start_fraction = 0.0
		r.paid_end_fraction = 1.0
	return StructureClock.run(self, dt)

func _chrono_fields() -> void:
	super._chrono_fields()
	_chrono_refresh_stress()

func _chrono_force_boundary(seconds: float) -> Dictionary:
	# Each actual control reservation is authored once at fraction 0 for this
	# whole tick. Its impulse cap is force.length() * _tick_dt, so its original
	# expiration is exactly fraction 1. Do not reconstruct that time by
	# subtracting accumulated floating-point impulse after unrelated contacts.
	# Physical death/control cuts remain immediate; work may expire earlier.
	var first = seconds; var ids: Array = []
	for i in chrono_reservations.size():
		var r: Dictionary = chrono_reservations[i]
		if not r.live: continue
		var limit = seconds; var exhausted = false
		var expiry = maxf(0.0, (r.paid_end_fraction - chrono_fraction) * _tick_dt)
		if expiry <= limit: limit = expiry; exhausted = true
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

func _chrono_apply_resources_at(seconds: float, fraction: float) -> void:
	super._chrono_apply_resources(seconds)
	for r in chrono_reservations:
		if r.live:
			# Absolute authored interval, not a sum of event-split products. No
			# source can start late or restart within this bounded candidate tick.
			r.impulse_ns = r.impulse_cap_ns * minf(fraction, r.paid_end_fraction) / r.paid_end_fraction

func _chrono_exhaust(ids: Array) -> void:
	for i in ids:
		var r: Dictionary = chrono_reservations[i]
		if r.live: chrono_trace.append({"kind": "paid_force_end", "tick": pilot_tick - 1, "fraction": chrono_fraction,
			"source_id": r.source_id, "impulse_ns": r.impulse_ns, "work_j": r.work_j, "work_cap_j": r.work_cap_j})
	super._chrono_exhaust(ids)

func _stress_key(body: Dictionary) -> String:
	return _chrono_component_key(body).sha256_text()

func _chrono_refresh_stress() -> void:
	var fields: Dictionary = {}
	_load_edges.clear()
	for body in bodies:
		var key = _stress_key(body); var members = _chrono_component_ids(body)
		var sources: Array = []; var forces: Dictionary = {}
		for p in body.parts: forces[p.id] = Vector2.ZERO
		for reservation in chrono_reservations:
			if not reservation.live or reservation.body_id != body.id: continue
			sources.append([reservation.intent_id, reservation.binding_revision])
			forces[reservation.source_id] += reservation.force
		var signature = JSON.stringify(sources)
		var field: Dictionary = chrono_stress.get(key, {})
		if field.is_empty() or field.members != members or field.signature != signature or chrono_stress_dirty.has(key):
			field = _chrono_new_stress_field(body, members, signature, forces)
		fields[key] = field
		_load_edges.append_array(field.edges)
		for beam in field.beams:
			if parts.has(beam.id) and parts[beam.id].alive:
				if parts[beam.id].hp <= 0.0 and not chrono_pending_breaks.has(beam.id): chrono_pending_breaks.append(beam.id)
				parts[beam.id].load = beam.load
				telemetry.peak_socket_load = maxf(float(telemetry.get("peak_socket_load", 0.0)), beam.load)
	chrono_stress = fields; chrono_stress_dirty.clear()

func _chrono_new_stress_field(body: Dictionary, members: Array, signature: String, forces: Dictionary) -> Dictionary:
	# Same documented source-aware load law and unchanged equilibrium solver.
	# Its load field is frozen until the next tick or a real LOCAL impulse,
	# force-budget/control, or component change. HP loss is continuous within it.
	var demand: Dictionary = {}; var actual = Vector2.ZERO
	for force in forces.values(): actual += force
	for p in body.parts:
		var arm: Vector2 = p.local_pos.rotated(body.angle)
		var angular: Vector2 = Vector2(-arm.y, arm.x) * body.torque / body.inertia - arm * body.angular_velocity * body.angular_velocity
		demand[p.id] = actual * p.mass / body.mass + angular * p.mass - forces[p.id]
		p.load = 0.0
	var edges: Array = []
	for edge in links:
		if demand.has(edge.a) and demand.has(edge.b): edges.append(edge)
	var solution = solve_socket_forces(demand, edges)
	var sums: Dictionary = {}
	for edge in solution:
		var magnitude: float = edge.force.length()
		for id in [edge.a, edge.b]:
			parts[id].load = maxf(parts[id].load, magnitude)
			sums[id] = float(sums.get(id, 0.0)) + magnitude
	var beams: Array = []
	for p in body.parts:
		p.load = maxf(p.load, float(sums.get(p.id, 0.0)) * 0.5)
		telemetry.peak_socket_load = maxf(float(telemetry.get("peak_socket_load", 0.0)), p.load)
		if p.type == "beam": beams.append({"id": int(p.id), "load": float(p.load), "rate": maxf(0.0, p.load - p.strength) * 6.0,
			"anchor_hp": float(p.hp), "anchor_fraction": chrono_fraction})
	return {"members": members, "signature": signature, "beams": beams, "edges": solution}

func _chrono_stress_boundary() -> Dictionary:
	var first = 2.0; var ids: Array = []
	for field in chrono_stress.values():
		for beam in field.beams:
			if not parts[beam.id].alive: continue
			var at = chrono_fraction if parts[beam.id].hp <= 0.0 else (beam.anchor_fraction + beam.anchor_hp / (beam.rate * _tick_dt) if beam.rate > 0.0 else 2.0)
			if at < chrono_fraction: at = chrono_fraction
			if at < first: first = at; ids = [beam.id]
			elif at == first: ids.append(beam.id)
	return {"fraction": first, "ids": ids}

func _chrono_apply_stress(fraction: float, scheduled: Array) -> void:
	elapsed = (float(pilot_tick - 1) + fraction) * _tick_dt
	for field in chrono_stress.values():
		for beam in field.beams:
			var p: Dictionary = parts[beam.id]
			if not p.alive or p.delivered: continue
			var hp = maxf(0.0, beam.anchor_hp - beam.rate * _tick_dt * (fraction - beam.anchor_fraction))
			# The already-selected linear HP root is authoritative. Canonicalizing
			# its exact zero is not moving the event or adding an epsilon step.
			if scheduled.has(beam.id): hp = 0.0
			var damage = maxf(0.0, p.hp - hp)
			if damage > 0.0:
				_record_damage_incident(p, damage, "stress")
				telemetry.structure_damage = float(telemetry.get("structure_damage", 0.0)) + damage
			p.hp = hp
			if p.hp == 0.0 and not chrono_pending_breaks.has(p.id): chrono_pending_breaks.append(int(p.id))

func _chrono_stress_due() -> bool:
	for id in chrono_pending_breaks:
		if parts.has(id) and parts[id].alive and parts[id].hp <= 0.0: return true
	return false

func _chrono_break_stress(ordinal: int) -> void:
	chrono_pending_breaks.sort()
	for id in chrono_pending_breaks:
		if not parts.has(id) or not parts[id].alive or parts[id].hp > 0.0: continue
		chrono_trace.append({"kind": "beam_break", "tick": pilot_tick - 1, "fraction": chrono_fraction,
			"phase": 1, "ordinal": ordinal, "source_id": id, "hp": 0.0})
		_destroy(parts[id])
	chrono_pending_breaks.clear()

func _chrono_contact(event: Dictionary) -> void:
	for entity in [event.a, event.b]:
		if entity.kind == "courier": chrono_stress_dirty[_stress_key(entity.body)] = true
	super._chrono_contact(event)

func _chrono_ray(ray: Dictionary, target: Dictionary, ordinal: int) -> void:
	if not target.is_empty() and target.entity.kind == "courier": chrono_stress_dirty[_stress_key(target.entity.body)] = true
	super._chrono_ray(ray, target, ordinal)
	if not chrono_trace.is_empty() and chrono_trace.back().kind == "ray": chrono_trace.back().phase = 2

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	telemetry.review_candidate = STRUCTURE_CANDIDATE
	telemetry.structure_model = "piecewise_constant_local_load_continuous_hp"

func save_candidate_json() -> Dictionary:
	var base = super.save_candidate_json()
	if not base.ok: return base
	var extra = {"fields": chrono_stress, "dirty": chrono_stress_dirty, "pending": chrono_pending_breaks}
	var packet = Value.pack_json(Snapshot._lift(extra), STRUCTURE_SNAPSHOT)
	if packet.is_empty(): return {"ok": false, "error": "structural_snapshot_bound"}
	return {"ok": true, "json": JSON.stringify({"schema": STRUCTURE_SNAPSHOT, "base": base.json, "structure": packet})}

func load_candidate_json(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > 4100000: return {"ok": false, "error": "structural_snapshot_size"}
	var parser = JSON.new()
	if parser.parse(text) != OK or not Value.exact(parser.data, ["schema", "base", "structure"]) or parser.data.schema != STRUCTURE_SNAPSHOT:
		return {"ok": false, "error": "unsupported_structural_snapshot"}
	var wire = Value.unpack_json(parser.data.structure, STRUCTURE_SNAPSHOT)
	if not wire.ok: return wire
	var decoded = Snapshot._lower(wire.value)
	if not decoded.ok or not Value.exact(decoded.value, ["fields", "dirty", "pending"]): return {"ok": false, "error": "invalid_structural_fields"}
	if not decoded.value.fields is Dictionary or not decoded.value.dirty is Dictionary or not decoded.value.pending is Array:
		return {"ok": false, "error": "invalid_structural_types"}
	return StructureSnapshot.restore(self, parser.data.base, decoded.value)
