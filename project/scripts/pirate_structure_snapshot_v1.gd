extends RefCounted
## Strict structural schema-2 validator and atomic staged commit.
const V = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const Base = preload("res://scripts/pirate_candidate_snapshot_v1.gd")

class Stage extends RefCounted:
	var state: Dictionary = {}
	func _get(property: StringName) -> Variant: return state.get(str(property))
	func _set(property: StringName, value: Variant) -> bool:
		state[str(property)] = value
		return true

static func restore(owner, base_text: Variant, extra: Variant) -> Dictionary:
	if not base_text is String: return V.fail("structural_base_type")
	var staged: Variant = Stage.new()
	var decoded = Base.restore(staged, base_text)
	if not decoded.ok: return decoded
	# No typed assignment or live mutation occurs while validating. The base
	# graph decoder writes only to the disposable dynamic staging object.
	for key in Base.FIELDS:
		if typeof(staged.get(key)) != typeof(owner.get(key)): return V.fail("structural_base_field_type:" + key)
	var checked = validate(staged, extra)
	if not checked.ok: return checked
	for key in Base.FIELDS: owner.set(key, staged.get(key))
	owner.parts = staged.parts; owner.bodies = staged.bodies; owner._bodies_by_id = staged._bodies_by_id
	owner.chrono_stress = extra.fields; owner.chrono_stress_dirty = extra.dirty; owner.chrono_pending_breaks = extra.pending
	return {"ok": true}

static func validate(base, extra: Variant) -> Dictionary:
	if not V.exact(extra, ["fields", "dirty", "pending"]) or not extra.fields is Dictionary or not extra.dirty is Dictionary or not extra.pending is Array:
		return V.fail("invalid_structural_types")
	if not V.real(base.chrono_fraction, 0.0, 1.0) or not V.real(base._tick_dt, 0.0, INF) or base._tick_dt <= 0.0:
		return V.fail("structural_clock")
	if base.parts.size() > 192 or extra.fields.size() > base.bodies.size() or extra.pending.size() > base.parts.size(): return V.fail("structural_size")
	for id in base.parts:
		var p: Variant = base.parts[id]
		if not id is int or id < 0 or not p is Dictionary or p.get("id") != id or not p.get("type") is String:
			return V.fail("structural_part_identity")
		if not p.get("alive") is bool or not p.get("delivered") is bool: return V.fail("structural_part_flags")
		if not V.real(p.get("hp"), -INF, INF) or not V.real(p.get("max_hp"), 0.0, INF) or p.max_hp <= 0.0 or p.hp > p.max_hp:
			return V.fail("structural_part_hp")
		if not V.real(p.get("strength"), 0.0, INF): return V.fail("structural_part_strength")
	var components: Dictionary = {}
	for body in base.bodies:
		var ids: Array = []
		for p in body.parts: ids.append(int(p.id))
		ids.sort()
		var key = JSON.stringify(ids).sha256_text()
		if components.has(key): return V.fail("structural_duplicate_component")
		components[key] = ids
	var reservations: Dictionary = {}
	for r in base.chrono_reservations:
		if not r is Dictionary or not r.get("intent_id") is String or reservations.has(r.intent_id): return V.fail("structural_reservation_identity")
		if not r.get("source_id") is int or not base.parts.has(r.source_id) or base.parts[r.source_id].type != "thruster": return V.fail("structural_reservation_source")
		if not r.get("binding_revision") is int or not r.get("body_id") is int or not r.get("live") is bool or not r.get("binding_parts") is Array: return V.fail("structural_reservation_binding")
		if r.binding_parts.is_empty():
			# A later actual coupler action can cut a paid source's control path
			# before the first field bind. Retain that never-applied tombstone;
			# do not invent a binding or refund its already paid motor interval.
			if r.binding_revision != 0 or r.body_id != -1 or r.live or not V.real(r.get("work_j"), 0.0, 0.0) or not V.real(r.get("impulse_ns"), 0.0, 0.0) or not V.real(r.get("torque"), 0.0, 0.0): return V.fail("structural_unbound_reservation")
		elif r.binding_revision < 1 or r.body_id < 0 or not _ids(r.binding_parts, base.parts) or not r.binding_parts.has(r.source_id): return V.fail("structural_reservation_binding")
		if not V.real(r.get("paid_start_fraction"), 0.0, 0.0) or not V.real(r.get("paid_end_fraction"), 1.0, 1.0): return V.fail("structural_paid_window")
		for name in ["reserved_j", "work_cap_j", "work_j", "impulse_cap_ns", "impulse_ns", "refund_j", "additional_debit_j"]:
			if not V.real(r.get(name), 0.0, INF): return V.fail("structural_reservation_scalar:" + name)
		if r.work_j > r.work_cap_j or r.impulse_ns > r.impulse_cap_ns or r.refund_j != 0.0 or r.additional_debit_j != 0.0: return V.fail("structural_reservation_budget")
		if not r.get("force") is Vector2 or not r.force.is_finite() or not V.real(r.get("torque"), -INF, INF): return V.fail("structural_reservation_force")
		reservations[r.intent_id] = r
	for key in extra.fields:
		var field: Variant = extra.fields[key]
		if not key is String or not components.has(key) or not V.exact(field, ["members", "signature", "beams", "edges"]): return V.fail("structural_field_identity")
		if not _ids(field.members, base.parts) or field.members != components[key] or JSON.stringify(field.members).sha256_text() != key: return V.fail("structural_field_members")
		if not field.beams is Array or not field.edges is Array or field.beams.size() > field.members.size() or field.edges.size() > 192 * 4: return V.fail("structural_field_arrays")
		var signature = _signature(field.signature, field.members, reservations)
		if not signature.ok: return signature
		var edge_seen: Dictionary = {}; var sums: Dictionary = {}; var loads: Dictionary = {}
		for edge in field.edges:
			if not V.exact(edge, ["a", "b", "force"]) or not edge.a is int or not edge.b is int or edge.a == edge.b or not field.members.has(edge.a) or not field.members.has(edge.b): return V.fail("structural_edge_reference")
			if not edge.force is Vector2 or not edge.force.is_finite() or not is_finite(edge.force.length()): return V.fail("structural_edge_force")
			var edge_key = "%d:%d" % [mini(edge.a, edge.b), maxi(edge.a, edge.b)]
			if edge_seen.has(edge_key): return V.fail("structural_duplicate_edge")
			edge_seen[edge_key] = true
			for id in [edge.a, edge.b]:
				loads[id] = maxf(float(loads.get(id, 0.0)), edge.force.length())
				sums[id] = float(sums.get(id, 0.0)) + edge.force.length()
		var seen: Dictionary = {}
		for beam in field.beams:
			if not V.exact(beam, ["id", "load", "rate", "anchor_hp", "anchor_fraction"]) or not beam.id is int or not field.members.has(beam.id) or seen.has(beam.id): return V.fail("structural_beam_reference")
			var p: Dictionary = base.parts[beam.id]
			if p.type != "beam": return V.fail("structural_beam_type")
			if not V.real(beam.load, 0.0, INF) or not V.real(beam.rate, 0.0, INF) or not V.real(beam.anchor_hp, 0.0, p.max_hp) or not V.real(beam.anchor_fraction, 0.0, base.chrono_fraction): return V.fail("structural_beam_scalar")
			if beam.load != maxf(float(loads.get(beam.id, 0.0)), float(sums.get(beam.id, 0.0)) * 0.5) or beam.rate != maxf(0.0, beam.load - p.strength) * 6.0: return V.fail("structural_beam_load_rule")
			seen[beam.id] = true
		for id in field.members:
			if base.parts[id].type == "beam" and not seen.has(id): return V.fail("structural_missing_beam")
	for key in extra.dirty:
		if not key is String or not extra.fields.has(key) or not extra.dirty[key] is bool or not extra.dirty[key]: return V.fail("structural_dirty_reference")
	var pending: Dictionary = {}
	for id in extra.pending:
		if not id is int or not base.parts.has(id) or pending.has(id): return V.fail("structural_pending_reference")
		if base.parts[id].type != "beam" or base.parts[id].hp > 0.0: return V.fail("structural_pending_state")
		pending[id] = true
	return {"ok": true}

static func _ids(value: Variant, parts: Dictionary) -> bool:
	if not value is Array or value.is_empty() or value.size() > parts.size(): return false
	var previous = -1
	for id in value:
		if not id is int or id <= previous or not parts.has(id): return false
		previous = id
	return true

static func _signature(value: Variant, members: Array, reservations: Dictionary) -> Dictionary:
	if not value is String: return V.fail("structural_signature_type")
	var parser = JSON.new()
	if parser.parse(value) != OK or not parser.data is Array: return V.fail("structural_signature_format")
	var seen: Dictionary = {}; var canonical: Array = []
	for item in parser.data:
		if not item is Array or item.size() != 2 or not item[0] is String or not reservations.has(item[0]) or seen.has(item[0]): return V.fail("structural_signature_reference")
		var r: Dictionary = reservations[item[0]]
		# A terminal field may describe a source just exhausted before return.
		# It must refer to that actual paid binding, not necessarily a live one.
		if not V.integer(item[1], 0, 2147483647) or item[1] != r.binding_revision or not members.has(r.source_id) or r.binding_parts != members: return V.fail("structural_signature_binding")
		seen[item[0]] = true
		canonical.append([item[0], int(item[1])])
	if JSON.stringify(canonical) != value: return V.fail("structural_signature_format")
	return {"ok": true}
