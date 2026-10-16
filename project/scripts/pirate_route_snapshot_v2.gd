extends RefCounted
## v2 route wrapper only. Stage unchanged drill state before any live write.
## Reject v1 wrapper/schema/profile instead of reinterpreting saved schedules.
const VERSION = "pirate-route-native-snapshot-3"
const Drill = preload("res://scripts/pilot_pirate_drill_candidate_v1.gd")
const DrillSnapshot = preload("res://scripts/pirate_drill_snapshot_v1.gd")
const Base = preload("res://scripts/pirate_candidate_snapshot_v1.gd")
const Profile = preload("res://scripts/pirate_encounter_profile_v2.gd")
const Actor = preload("res://scripts/pirate_actor_reconstructed_v1.gd")
const Ray = preload("res://scripts/pirate_ray_receipt_v1.gd")
const V = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const FIELDS = ["configuration_result", "route_ray_records", "route_terminal", "route_region_plans"]

static func save(owner, base: Dictionary) -> Dictionary:
	if not base.ok: return base
	var extra: Dictionary = {}
	for key in FIELDS: extra[key] = owner.get(key)
	var packet = V.pack_json(Base._lift(extra), VERSION)
	if packet.is_empty(): return V.fail("route_snapshot_bound")
	return {"ok": true, "json": JSON.stringify({"schema": VERSION, "base": base.json, "packet": packet})}

static func restore(owner, text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > 8000000: return V.fail("route_snapshot_size")
	var parser = JSON.new()
	if parser.parse(text) != OK or not V.exact(parser.data, ["schema", "base", "packet"]) or parser.data.schema != VERSION or not parser.data.base is String: return V.fail("route_snapshot_shape")
	var staged = Drill.new()
	var checked = staged.load_candidate_json(parser.data.base)
	if not checked.ok: return checked
	var unpacked = V.unpack_json(parser.data.packet, VERSION)
	if not unpacked.ok: return unpacked
	var lowered = Base._lower(unpacked.value)
	if not lowered.ok: return lowered
	checked = validate(staged, lowered.value)
	if not checked.ok: return checked
	for key in Base.FIELDS: owner.set(key, staged.get(key))
	owner.parts = staged.parts; owner.bodies = staged.bodies; owner._bodies_by_id = staged._bodies_by_id
	for key in ["chrono_stress", "chrono_stress_dirty", "chrono_pending_breaks"] + DrillSnapshot.FIELDS: owner.set(key, staged.get(key))
	for key in FIELDS: owner.set(key, lowered.value[key])
	return {"ok": true}

static func validate(staged, extra: Variant) -> Dictionary:
	if not V.exact(extra, FIELDS) or not DrillSnapshot._finite(extra): return V.fail("route_extra_shape")
	var error = Profile.route_error(staged.route)
	if not error.is_empty(): return V.fail(error)
	# Actor.configure has always canonicalized its three integer budget fields.
	# A JSON route legitimately retains equal floats there. Compare the actor to
	# that same strict definition boundary, without rewriting either saved tree.
	var expected_actor = Actor.configure(staged.route.pirate_encounter.definition)
	if not expected_actor.ok or staged.telemetry.get("control_version") != Profile.VERSION or staged.pirate.definition != expected_actor.state.definition: return V.fail("route_snapshot_identity")
	if not extra.configuration_result is Dictionary or extra.configuration_result.get("ok") != true: return V.fail("route_configuration_result")
	if not Ray.validate(extra.route_ray_records, staged.pirate): return V.fail("route_ray_receipt")
	if not extra.route_terminal is Dictionary or not extra.route_region_plans is Dictionary or extra.route_region_plans.size() > 256: return V.fail("route_owner_fields")
	var terminal: Dictionary = extra.route_terminal
	if not terminal.is_empty():
		if not V.exact(terminal, ["kind", "tick", "fraction", "phase", "bracket_fraction", "ordinal"]) or not terminal.kind in ["receiver", "delivered", "receiver_speed", "cargo_dead", "timeout", "left", "right", "top", "bottom", "abort"]: return V.fail("route_terminal_shape")
		if not terminal.tick is int or terminal.tick != maxi(0, staged.pilot_tick - 1) or not V.real(terminal.fraction, 0.0, 1.0) or terminal.fraction != staged.chrono_fraction or terminal.phase != 3 or not terminal.ordinal is int or not _bracket(terminal.bracket_fraction, terminal.fraction): return V.fail("route_terminal_clock")
		if staged.status != ("success" if terminal.kind in ["receiver", "delivered"] else "failed"): return V.fail("route_terminal_status")
	elif staged.status in ["success", "failed"]: return V.fail("route_missing_terminal")
	for key in extra.route_region_plans:
		var plan: Variant = extra.route_region_plans[key]
		if not key is String or key.length() > 4096 or not plan is Dictionary or not plan.get("state") in ["miss", "hit", "unresolved"]: return V.fail("route_region_plan")
		if plan.state == "miss":
			if not V.exact(plan, ["state"]): return V.fail("route_region_miss")
		elif plan.state == "hit":
			if not V.exact(plan, ["state", "fraction", "bracket_fraction", "position", "velocity", "kind"]) or not plan.position is Vector2 or not plan.velocity is Vector2 or not V.real(plan.fraction, 0.0, 1.0) or not _bracket(plan.bracket_fraction, plan.fraction): return V.fail("route_region_hit")
		else:
			if not V.exact(plan, ["state", "reason", "at", "fraction", "kind"]) or not plan.reason is String or not V.real(plan.fraction, 0.0, 1.0) or plan.at != plan.fraction: return V.fail("route_region_hold")
		if plan.state != "miss" and not plan.kind in ["receiver", "left", "right", "top", "bottom"]: return V.fail("route_region_kind")
	return {"ok": true}

static func _bracket(value: Variant, fraction: float) -> bool:
	return value is Array and value.size() == 2 and V.real(value[0], 0.0, fraction) and V.real(value[1], fraction, fraction)
