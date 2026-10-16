extends "res://scripts/pilot_pirate_drill_candidate_v1.gd"
## Minimum standard simulator facade. Explicitly unregistered until lane review.
const Encounter = preload("res://scripts/pirate_encounter_profile_v1.gd")
const ReceiverQuery = preload("res://scripts/receiver_motion_query_v1.gd")
const RayReceipt = preload("res://scripts/pirate_ray_receipt_v1.gd")
const ROUTE_CANDIDATE = "unregistered-pirate-route-candidate-2"
var configuration_result: Dictionary = {"ok": false, "error": "not_configured"}
var route_ray_records: Array = []
var route_terminal: Dictionary = {}
var route_region_plans: Dictionary = {}

static func preflight(design: Variant, launcher: Variant, route_data: Variant, random_seed: int = 1) -> Dictionary:
	var checked = Encounter.preflight(design, launcher, route_data)
	if not checked.ok: return checked
	# All caller-owned containers and RNG inputs are isolated. This probe has
	# no economy authority; its launch preparation is disposable simulation.
	var probe = preload("res://scripts/pilot_pirate_drill_candidate_v1.gd").new()
	var result = probe.configure_candidate(design.duplicate(true), launcher.duplicate(true), route_data.duplicate(true), route_data.pirate_encounter.definition.duplicate(true), random_seed)
	if not result.ok: return {"ok": false, "error": "pirate_launch_clearance", "events": probe.events.duplicate(true)}
	var overlap = _pirate_spawn_error(probe)
	if not overlap.is_empty(): return {"ok": false, "error": overlap}
	return {"ok": true, "control_version": Encounter.VERSION}

static func prepare_flight(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> Dictionary:
	var checked = Encounter.preflight(design, launcher, route_data)
	if not checked.ok: return checked
	var candidate = load("res://scripts/pilot_pirate_route_candidate_v1.gd").new()
	candidate.configure(design, launcher, route_data, random_seed)
	if not candidate.configuration_result.ok: return candidate.configuration_result.duplicate(true)
	# Parent may retain this exact uncommitted instance through begin_dispatch
	# and durable dispatch save, avoiding a validation/configure gap.
	return {"ok": true, "simulation": candidate, "control_version": Encounter.VERSION}

func configure(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> void:
	configuration_result = Encounter.preflight(design, launcher, route_data)
	if not configuration_result.ok:
		status = "held"; chrono_error = configuration_result.error; return
	route_ray_records.clear(); route_terminal.clear(); route_region_plans.clear()
	configuration_result = super.configure_candidate(design.duplicate(true), launcher.duplicate(true), route_data.duplicate(true), route_data.pirate_encounter.definition.duplicate(true), random_seed)
	if configuration_result.ok:
		var overlap = _pirate_spawn_error(self)
		if not overlap.is_empty(): configuration_result = {"ok": false, "error": overlap}
	if not configuration_result.ok:
		configuration_result = {"ok": false, "error": configuration_result.get("error", "pirate_launch_clearance"), "events": events.duplicate(true)}
		status = "held"; chrono_error = configuration_result.error
	route.control_version = Encounter.VERSION; route.pilot_profile = Encounter.VERSION
	_refresh_telemetry()

func _tick(dt: float) -> void:
	route_region_plans.clear()
	# Authored requests are deterministic functions of the saved initial route
	# and the actual replayed cargo state. No renderer/timer issues commands.
	chrono_command = Actor.neutral_command()
	if pilot_tick in route.pirate_encounter.warning_ticks and pirate.hp > 0.0:
		var target = cargo_position()
		var predicted = Actor._sample(pirate, pilot_tick + 330, 0.0)
		var dx: float = float(target.x) - (predicted.x - pirate.definition.radius_m)
		var dy: float = float(target.y) - predicted.y
		var distance = sqrt(dx * dx + dy * dy)
		if distance >= 0.5 and distance <= pirate.definition.range_m:
			chrono_command.warning_request = {"request_id": "route_lock_%d" % pilot_tick, "target_x": float(target.x), "target_y": float(target.y)}
	super._tick(dt)

func _run_chronology(dt: float) -> Dictionary:
	for r in chrono_reservations:
		r.paid_start_fraction = 0.0; r.paid_end_fraction = 1.0
	return DrillClock.run(self, dt, self)

func _route_boundary() -> Dictionary:
	var cargo: Dictionary = {}
	for p in parts.values():
		if p.type == "cargo": cargo = p; break
	if cargo.is_empty() or not cargo.alive: return {"state": "hit", "kind": "cargo_dead", "fraction": chrono_fraction, "bracket_fraction": [chrono_fraction, chrono_fraction]}
	if cargo.delivered: return {"state": "hit", "kind": "delivered", "fraction": chrono_fraction, "bracket_fraction": [chrono_fraction, chrono_fraction]}
	var body = body_for_part(cargo.id)
	if body.is_empty(): return {"state": "unresolved", "reason": "receiver_missing_cargo_body", "fraction": chrono_fraction}
	var result: Dictionary = {"state": "miss", "fraction": 2.0}
	for kind in ["receiver", "left", "right", "top", "bottom"]:
		var key = str(cargo.id) + ":" + str(cargo.local_pos) + ":" + _chrono_component_key(body) + ":" + str(body.chrono_motion_revision) + ":" + str(body.chrono_motion_start_fraction) + ":" + kind
		if not route_region_plans.has(key):
			var found = ReceiverQuery.first(body, cargo.local_pos, kind, route, _tick_dt)
			if found.state == "unresolved": found["fraction"] = found.at
			if found.state != "miss": found["kind"] = kind
			route_region_plans[key] = found
		var found: Dictionary = route_region_plans[key]
		if found.state == "miss": continue
		if found.fraction < chrono_fraction:
			return {"state": "unresolved", "reason": "receiver_event_precedes_clock", "fraction": chrono_fraction}
		if found.fraction < result.fraction: result = found.duplicate(true)
	# Timeout's exact absolute clock is independent of body/event partitions.
	var limit: float = route.time_limit / _tick_dt - float(pilot_tick - 1)
	if limit <= 1.0:
		limit = maxf(0.0, limit)
		if limit < result.fraction: result = {"state": "hit", "kind": "timeout", "fraction": limit, "bracket_fraction": [limit, limit]}
	if result.get("kind") == "receiver":
		result["cargo_curve_key"] = _drill_entity_curve_key({"kind":"courier", "body":body})
	return result

func _route_commit(event: Dictionary, ordinal: int) -> void:
	if status != "running": return
	var cargo: Dictionary = {}
	for p in parts.values():
		if p.type == "cargo": cargo = p; break
	var kind: String = event.kind
	# Re-read state AFTER all physical events at this same represented time.
	if cargo.is_empty() or not cargo.alive: kind = "cargo_dead"
	elif kind == "receiver":
		var at = _part_position(cargo)
		if not ReceiverQuery.inside(at, "receiver", route): chrono_error = "receiver_commit_witness_mismatch"; status = "held"; return
		if _part_velocity(cargo).length() > route.max_delivery_speed: kind = "receiver_speed"
		else:
			_recover_cargo_hardware(cargo)
			cargo.world_pos = at; cargo.world_velocity = Vector2.ZERO; cargo.delivered = true; cargo.body_id = -1
			_clear_control_state(cargo); _detach(cargo.id)
			telemetry.delivered_count = 1; telemetry.delivered = true
			_log("货箱 %d 已由平台接收。" % cargo.id)
	status = "success" if kind in ["receiver", "delivered"] else "failed"
	route_terminal = {"kind": kind, "tick": pilot_tick - 1, "fraction": chrono_fraction, "phase": 3, "bracket_fraction": event.bracket_fraction.duplicate(), "ordinal": ordinal}
	chrono_trace.append(route_terminal.duplicate(true))
	if status == "failed": _log({"cargo_dead": "部分货物损毁，委托失败。", "receiver_speed": "抵达速度过高，收货平台拒收。", "timeout": "货物未全部抵达，委托超时。"}.get(kind, "货物偏离收货区，委托失败。"))
	else: _log("全部货物自动投递成功。")
	_route_stop_sources()

func _route_stop_sources() -> void:
	if pilot_tick == 0: return
	for r in chrono_reservations: r.live = false
	for r in chrono_drills.values(): r.live = false; _drill_select(r, -1, 0.0)
	_chrono_rebuild(); _chrono_fields()

func abort_flight() -> Dictionary:
	if status != "running": return {"ok": false, "error": "flight_not_running"}
	status = "failed"
	route_terminal = {"kind": "abort", "tick": maxi(0, pilot_tick - 1), "fraction": chrono_fraction, "phase": 3, "bracket_fraction": [chrono_fraction, chrono_fraction], "ordinal": -1}
	_route_stop_sources(); _log("配送已主动中止。")
	_refresh_telemetry()
	return {"ok": true}

func finalize_settlement() -> Dictionary:
	# Only the existing recovery/cost calculation; never credits/contracts.
	if status in ["success", "failed"]: return super.finalize_settlement()
	return telemetry

func _chrono_ray(ray: Dictionary, target: Dictionary, ordinal: int) -> void:
	route_ray_records.append(RayReceipt.capture(ray, target))
	super._chrono_ray(ray, target, ordinal)

func pirate_presentation() -> Dictionary:
	var tick = maxi(0, pilot_tick - 1)
	var fraction = chrono_fraction if pilot_tick > 0 else 0.0
	return {"actor_view": Actor.view(pirate, tick, fraction), "clock": {"tick": tick, "fraction": fraction, "paused": chrono_paused or status != "running"}, "ray_records": route_ray_records.duplicate(true), "actor_id": pirate.definition.id}

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	telemetry.control_version = Encounter.VERSION; telemetry.review_candidate = ROUTE_CANDIDATE
	telemetry.route_terminal = route_terminal.duplicate(true)

const RouteSnapshot = preload("res://scripts/pirate_route_snapshot_v1.gd")
func save_candidate_json() -> Dictionary:
	return RouteSnapshot.save(self, super.save_candidate_json())

func load_candidate_json(text: String) -> Dictionary:
	return RouteSnapshot.restore(self, text)

func _route_guard_local_boundary(observed: Dictionary, at: float, forces: Array, beams: Array, deaths: Array, entities: Array) -> String:
	if observed.get("state") != "hit" or observed.get("kind") != "receiver" or at >= observed.fraction or at < observed.bracket_fraction[0]: return ""
	var cargo_body = _cargo_body()
	if cargo_body.is_empty(): return "receiver_missing_cargo_body"
	for index in forces:
		var body = body_for_part(chrono_reservations[index].source_id)
		if not body.is_empty() and body.id == cargo_body.id: return "receiver_local_force_order_bracket"
	for id in beams:
		var body = body_for_part(id)
		if not body.is_empty() and body.id == cargo_body.id: return "receiver_local_break_order_bracket"
	if not deaths.is_empty():
		var current: Dictionary = {}
		for entity in entities: current[_drill_entity_curve_key(entity)] = true
		for plan in chrono_contact_plans.values():
			if plan.state != "hit" or not current.has(plan.a) or not current.has(plan.b) or not observed.cargo_curve_key in [plan.a, plan.b]: continue
			if maxf(plan.bracket[0], observed.bracket_fraction[0]) > minf(plan.bracket[1], observed.bracket_fraction[1]): continue
			for index in deaths:
				var prefix = "obstacle:" + str(index) + ":"
				if plan.a.begins_with(prefix) or plan.b.begins_with(prefix): return "receiver_competing_death_order_bracket"
	return ""

static func _pirate_spawn_error(sim) -> String:
	# The inherited ordinary-obstacle clearance runs before this actor exists.
	# Check every real courier and anchored-pad circle after actual configuration
	# without advancing, charging, reconstructing geometry or editing callers.
	var center: Vector2 = sim.pirate_body.position
	for p in sim.parts.values():
		if not p.alive: continue
		if _spawn_circle_overlaps(sim._part_position(p), 0.43 * p.scale, center, sim.pirate.definition.radius_m): return "pirate_launch_courier_overlap"
	for p in sim.launcher_parts:
		if p.alive and _spawn_circle_overlaps(p.world_pos, 0.43 * p.scale, center, sim.pirate.definition.radius_m): return "pirate_launch_pad_overlap"
	return ""

static func _spawn_circle_overlaps(a: Vector2, ar: float, b: Vector2, br: float) -> bool:
	var dx = float(a.x) - float(b.x); var dy = float(a.y) - float(b.y)
	# Reject either exact scalar overlap or the actual binary32 CCD overlap.
	# Clearance must not admit a state the authoritative contact predicate
	# already regards as overlapping merely because subtraction rounded.
	var radius_squared = (ar + br) * (ar + br)
	return dx * dx + dy * dy <= radius_squared or (a - b).length_squared() <= radius_squared
