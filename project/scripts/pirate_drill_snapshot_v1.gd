extends RefCounted
## Private drill schema; every base and extra field is staged before commit.
const Structure = preload("res://scripts/pilot_pirate_structure_candidate_v1.gd")
const Base = preload("res://scripts/pirate_candidate_snapshot_v1.gd")
const V = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const Motion = preload("res://scripts/common_motion_v1.gd")
const VERSION = "pirate-drill-native-snapshot-2"
const FIELDS = ["chrono_contact_plans", "chrono_drills", "chrono_cut_fields", "chrono_pending_obstacles", "chrono_pair_plans", "chrono_cut_dirty", "chrono_drill_damage_base", "chrono_drill_loss_base"]
const RESERVATION = ["source_id", "activation", "reserved_j", "paid_ratio", "paid_output", "effective_output", "paid_start_fraction", "paid_end_fraction", "live", "body_id", "binding_parts", "binding_revision", "target_index", "motor_applied_j", "contact_seconds", "damage_hp", "exposure_completed_seconds", "exposure_completed_damage", "exposure_anchor_fraction", "exposure_rate", "lost_seconds_bound", "refund_j", "additional_debit_j"]

static func save(owner, base: Dictionary) -> Dictionary:
	if not base.ok: return base
	var blocks: Array = []
	for field in FIELDS:
		if field in ["chrono_pair_plans", "chrono_contact_plans"]:
			for key in owner.get(field):
				var packet = V.pack_json(Base._lift(owner.get(field)[key]), VERSION)
				if packet.is_empty(): return V.fail("drill_plan_snapshot_bound")
				blocks.append({"key": ("pair:" if field == "chrono_pair_plans" else "contact:") + key, "packet": packet})
		else:
			var packet = V.pack_json(Base._lift(owner.get(field)), VERSION)
			if packet.is_empty(): return V.fail("drill_field_snapshot_bound:" + field)
			blocks.append({"key": field, "packet": packet})
	return {"ok": true, "json": JSON.stringify({"schema": VERSION, "base": base.json, "blocks": blocks})}

static func restore(owner, text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > 6000000: return V.fail("drill_snapshot_size")
	var parser = JSON.new()
	if parser.parse(text) != OK or not V.exact(parser.data, ["schema", "base", "blocks"]) or parser.data.schema != VERSION or not parser.data.base is String or not parser.data.blocks is Array or parser.data.blocks.size() > 512: return V.fail("drill_snapshot_shape")
	var staged = Structure.new()
	var base_result = staged.load_candidate_json(parser.data.base)
	if not base_result.ok: return base_result
	var extra: Dictionary = {"chrono_pair_plans": {}, "chrono_contact_plans": {}}
	for block in parser.data.blocks:
		if not V.exact(block, ["key", "packet"]) or not block.key is String: return V.fail("drill_block_shape")
		var unpacked = V.unpack_json(block.packet, VERSION)
		if not unpacked.ok: return unpacked
		var decoded = Base._lower(unpacked.value)
		if not decoded.ok: return decoded
		if block.key.begins_with("pair:") or block.key.begins_with("contact:"):
			var field = "chrono_pair_plans" if block.key.begins_with("pair:") else "chrono_contact_plans"
			var key: String = block.key.substr(5 if field == "chrono_pair_plans" else 8)
			if extra[field].has(key): return V.fail("drill_duplicate_pair")
			extra[field][key] = decoded.value
		elif block.key in FIELDS and not block.key in ["chrono_pair_plans", "chrono_contact_plans"] and not extra.has(block.key): extra[block.key] = decoded.value
		else: return V.fail("drill_duplicate_or_unknown_field")
	if not V.exact(extra, FIELDS): return V.fail("drill_missing_field")
	var checked = validate(staged, extra)
	if not checked.ok: return checked
	for field in Base.FIELDS: owner.set(field, staged.get(field))
	owner.parts = staged.parts; owner.bodies = staged.bodies; owner._bodies_by_id = staged._bodies_by_id
	owner.chrono_stress = staged.chrono_stress; owner.chrono_stress_dirty = staged.chrono_stress_dirty; owner.chrono_pending_breaks = staged.chrono_pending_breaks
	for field in FIELDS: owner.set(field, extra[field])
	return {"ok": true}

static func validate(base, extra: Dictionary) -> Dictionary:
	for field in ["chrono_drills", "chrono_cut_fields", "chrono_pair_plans", "chrono_contact_plans", "chrono_cut_dirty"]:
		if not extra[field] is Dictionary: return V.fail("drill_field_type")
	if not extra.chrono_pending_obstacles is Array or not V.real(extra.chrono_drill_damage_base, 0.0, INF) or not V.real(extra.chrono_drill_loss_base, 0.0, INF): return V.fail("drill_state_type")
	if not _finite(extra) or extra.chrono_drills.size() > base.parts.size() or extra.chrono_pair_plans.size() > 480: return V.fail("drill_state_bound")
	for index in base.obstacles.size():
		var h: Variant = base.obstacles[index]
		if not h is Dictionary or not V.real(h.get("health"), -INF, INF) or not V.real(h.get("radius"), 0.0, INF) or h.radius <= 0.0 or not h.get("position") is Vector2 or not h.position.is_finite(): return V.fail("drill_obstacle_state")
	for id in extra.chrono_drills:
		var r: Variant = extra.chrono_drills[id]
		if not id is int or not base.parts.has(id) or base.parts[id].type != "drill" or not V.exact(r, RESERVATION) or r.source_id != id: return V.fail("drill_source")
		for field in ["reserved_j", "paid_ratio", "paid_output", "effective_output", "motor_applied_j", "contact_seconds", "damage_hp", "exposure_completed_seconds", "exposure_completed_damage", "exposure_rate", "lost_seconds_bound"]:
			if not V.real(r[field], 0.0, INF): return V.fail("drill_scalar:" + field)
		if not r.live is bool or not r.body_id is int or not r.binding_revision is int or not r.binding_parts is Array or not r.target_index is int: return V.fail("drill_binding_type")
		if r.paid_ratio > 1.0 or r.effective_output > r.paid_ratio * r.paid_output or r.motor_applied_j > r.reserved_j or r.contact_seconds > base._tick_dt or r.lost_seconds_bound > base._tick_dt or r.exposure_completed_seconds > r.contact_seconds or r.exposure_completed_damage > r.damage_hp: return V.fail("drill_paid_cap")
		if not V.real(r.paid_start_fraction, 0.0, 0.0) or not V.real(r.paid_end_fraction, 1.0, 1.0) or not V.real(r.exposure_anchor_fraction, 0.0, base.chrono_fraction) or not V.real(r.refund_j, 0.0, 0.0) or not V.real(r.additional_debit_j, 0.0, 0.0): return V.fail("drill_paid_window")
		if r.reserved_j != 60.0 * base._tick_dt * r.paid_output * r.paid_ratio or r.damage_hp > 100.0 * base._tick_dt * r.paid_output * r.paid_ratio: return V.fail("drill_payment_rule")
		if not base._paid_drills.has(id) or r.paid_ratio != base._paid_drills[id].ratio or r.paid_output != base._paid_drills[id].output: return V.fail("drill_original_payment")
		if not V.exact(r.activation, ["kind", "controller_ids"]) or not r.activation.kind in ["forced_tick", "continuous_tick", "wire_tick", "cockpit_tick"] or not r.activation.controller_ids is Array: return V.fail("drill_activation")
		if r.activation.kind in ["forced_tick", "continuous_tick"] and not r.activation.controller_ids.is_empty(): return V.fail("drill_activation_ids")
		var prior_controller = -1
		for controller in r.activation.controller_ids:
			if not controller is int or controller <= prior_controller or not base.parts.has(controller): return V.fail("drill_controller")
			prior_controller = controller
		var previous = -1
		for member in r.binding_parts:
			if not member is int or member <= previous or not base.parts.has(member): return V.fail("drill_members")
			previous = member
		if r.binding_parts.is_empty():
			if r.live or r.binding_revision != 0 or r.body_id != -1 or r.motor_applied_j != 0.0 or r.contact_seconds != 0.0 or r.damage_hp != 0.0: return V.fail("drill_unbound")
		elif r.binding_revision < 1 or r.body_id < 0 or not r.binding_parts.has(id): return V.fail("drill_binding")
		if r.live:
			if not base._bodies_by_id.has(r.body_id) or not base.parts[id].alive or base.parts[id].delivered: return V.fail("drill_live_body")
			var members: Array = []
			for p in base._bodies_by_id[r.body_id].parts: members.append(int(p.id))
			members.sort()
			if members != r.binding_parts: return V.fail("drill_live_members")
		if r.target_index < -1 or r.target_index >= base.obstacles.size() or (r.target_index == -1 and r.exposure_rate != 0.0) or r.exposure_rate > 100.0 * r.effective_output: return V.fail("drill_target")
	for index in extra.chrono_cut_fields:
		var f: Variant = extra.chrono_cut_fields[index]
		if not _obstacle(index, base) or not V.exact(f, ["obstacle_index", "signature", "sources", "rate", "anchor_hp", "anchor_fraction"]) or f.obstacle_index != index or not f.sources is Array or f.sources.is_empty() or not f.signature is String: return V.fail("drill_cut_field")
		if not V.real(f.rate, 0.0, INF) or f.rate <= 0.0 or not V.real(f.anchor_hp, 0.0, INF) or not V.real(f.anchor_fraction, 0.0, base.chrono_fraction): return V.fail("drill_cut_scalar")
		var total = 0.0; var seen: Dictionary = {}
		for source in f.sources:
			if not source is Array or source.size() != 3 or not source[0] is int or not extra.chrono_drills.has(source[0]) or seen.has(source[0]): return V.fail("drill_cut_source")
			var r: Dictionary = extra.chrono_drills[source[0]]
			if source[1] != r.binding_revision or source[2] != r.exposure_rate or r.target_index != index: return V.fail("drill_cut_binding")
			seen[source[0]] = true; total += source[2]
		if total != f.rate or var_to_bytes(f.sources).hex_encode() != f.signature: return V.fail("drill_cut_rate")
	for index in extra.chrono_pending_obstacles:
		if not _obstacle(index, base) or base.obstacles[index].health > 0.0: return V.fail("drill_pending")
	for index in extra.chrono_cut_dirty:
		if not _obstacle(index, base) or extra.chrono_cut_dirty[index] != true: return V.fail("drill_dirty")
	for key in extra.chrono_pair_plans:
		var p: Variant = extra.chrono_pair_plans[key]
		if not _plan_shape(p): return V.fail("drill_pair_shape")
		if not key is String or not p is Dictionary or not p.get("ok") == true or not p.get("source_id") is int or not extra.chrono_drills.has(p.source_id) or not _obstacle(p.get("obstacle_index"), base): return V.fail("drill_pair_identity")
		if not p.get("pair") is String or not p.get("signature") is String or key != p.pair + ":" + p.signature or p.pair != "%d:%d" % [p.source_id, p.obstacle_index]: return V.fail("drill_pair_key")
		if not V.real(p.get("start_fraction"), 0.0, base.chrono_fraction) or not V.real(p.get("valid_until"), p.start_fraction, 1.0) or not p.get("boundaries") is Array or p.boundaries.size() > 64 or not V.integer(p.get("nodes"), 0, 4097): return V.fail("drill_pair_clock")
		for name in ["windows", "unknown"]:
			if not p.get(name) is Array or p[name].size() > 64: return V.fail("drill_intervals")
			var end = p.start_fraction
			for interval in p[name]:
				if not interval is Array or interval.size() != 2 or not V.real(interval[0], end, 1.0) or not V.real(interval[1], interval[0], 1.0) or interval[1] <= interval[0]: return V.fail("drill_interval_range")
				end = interval[1]
	if extra.chrono_contact_plans.size() > 400: return V.fail("drill_contact_plan_size")
	for key in extra.chrono_contact_plans:
		var p: Variant = extra.chrono_contact_plans[key]
		if not key is String or not V.exact(p,["a","b","p","q","origin","fraction","state","reason","normal","distance","bracket"]): return V.fail("drill_contact_plan_shape")
		if not p.a is String or not p.b is String or not p.p is int or not p.q is int or key != "%s:%d|%s:%d" % [p.a,p.p,p.b,p.q]: return V.fail("drill_contact_plan_identity")
		if not V.real(p.origin,0.0,base.chrono_fraction) or not V.real(p.fraction,p.origin,1.0) or not p.state in ["hit","unresolved"] or not p.reason is String or not p.normal is Vector2 or not p.normal.is_finite() or not V.real(p.distance,0.0,INF) or not p.bracket is Array: return V.fail("drill_contact_plan_scalar")
		if p.state == "hit":
			if p.bracket.size()!=2 or not V.real(p.bracket[0],p.origin,p.fraction) or not V.real(p.bracket[1],p.fraction,p.fraction) or p.normal.length_squared()==0.0: return V.fail("drill_contact_plan_witness")
		elif not p.bracket.is_empty(): return V.fail("drill_contact_plan_unknown")
	var all: Array = []
	for body in base.bodies: all.append({"body":body,"active":true})
	all.append({"body":base.pirate_body,"active":true})
	for index in base._chrono_hazards.size(): all.append({"body":base._chrono_hazards[index],"active":base.obstacles[index].health>0.0})
	for item in all:
		var body: Dictionary = item.body
		if not body.has("chrono_motion_anchor"): continue
		var anchor: Variant = body.chrono_motion_anchor
		if not V.exact(anchor, ["position", "velocity", "angle", "angular_velocity", "acceleration", "alpha"]) or not _finite(anchor): return V.fail("drill_anchor_shape")
		for key in ["position", "velocity", "acceleration"]:
			if not anchor[key] is Vector2: return V.fail("drill_anchor_vector")
		for key in ["angle", "angular_velocity", "alpha"]:
			if not V.real(anchor[key], -INF, INF): return V.fail("drill_anchor_scalar")
		if not V.real(body.get("chrono_motion_start_fraction"),0.0,1.0) or not V.real(body.get("chrono_motion_sample_fraction"),body.chrono_motion_start_fraction,1.0) or not V.real(body.get("chrono_motion_offset"),0.0,base._tick_dt) or not V.integer(body.get("chrono_motion_revision"),1,100000) or not body.get("chrono_motion_tick") is int or body.chrono_motion_tick<0 or body.chrono_motion_tick>base.pilot_tick-1: return V.fail("drill_anchor_clock")
		if body.chrono_motion_tick==base.pilot_tick-1 and body.chrono_motion_sample_fraction>base.chrono_fraction: return V.fail("drill_anchor_future")
		if item.active and (body.chrono_motion_tick!=base.pilot_tick-1 or body.chrono_motion_sample_fraction!=base.chrono_fraction): return V.fail("drill_live_anchor_clock")
		if body.chrono_motion_offset != (body.chrono_motion_sample_fraction-body.chrono_motion_start_fraction)*base._tick_dt: return V.fail("drill_anchor_offset")
		var pose = Motion.pose(anchor, body.chrono_motion_offset)
		for key in ["position", "velocity", "angle", "angular_velocity"]:
			if body[key] != pose[key]: return V.fail("drill_anchor_pose")
	return {"ok": true}

static func _obstacle(index: Variant, base) -> bool:
	return index is int and index >= 0 and index < base.obstacles.size()

static func _finite(value: Variant, depth: int = 0) -> bool:
	if depth > 24: return false
	if value is float: return is_finite(value)
	if value is Vector2: return value.is_finite()
	if value is Array:
		for item in value:
			if not _finite(item, depth + 1): return false
	elif value is Dictionary:
		for key in value:
			if not _finite(key, depth + 1) or not _finite(value[key], depth + 1): return false
	return true

static func _plan_shape(plan: Variant) -> bool:
	# Literal geometry keys are String; metadata attached through GDScript dot
	# assignment is StringName. Preserve that own-produced typed wire exactly.
	var strings = ["ok", "windows", "unknown", "boundaries", "nodes"]
	var names = ["pair", "source_id", "obstacle_index", "signature", "start_fraction", "valid_until"]
	if not plan is Dictionary: return false
	if plan.has("diagnostic"): strings.append("diagnostic")
	if plan.size() != strings.size() + names.size(): return false
	for key in plan:
		if typeof(key) == TYPE_STRING:
			if not key in strings: return false
		elif typeof(key) == TYPE_STRING_NAME:
			if not str(key) in names: return false
		else: return false
	for key in strings + names:
		if not plan.has(key): return false
	return true
