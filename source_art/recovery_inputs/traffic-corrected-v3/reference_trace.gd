extends SceneTree
## Integration reference: real helper calls, explicitly supplied external commits.
## No collision detection, impulse resolution or courier simulation is implemented.
const A = preload("ground_traffic_actor_v1.gd")
const B = preload("ground_traffic_bundle_v1.gd")
const V = preload("ground_traffic_value_v1.gd")
const OLD = preload("baseline_v3/ground_traffic_actor_v1.gd")
var failures: Array = []
var stages: Array = []
var checkpoints: Array = []
var source_ids: Dictionary = {0: "author_seed_42"}
var output: String
var legal_snapshots: int = 0
var false_rejections: Array = []

func _init() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("FAIL " + message)

func run() -> void:
	output = OS.get_environment("SC_GROUND_QA_DIR")
	var initial: Dictionary = A.configure(B.author(42, B.fresh_definition()).bundle).state
	var s: Dictionary = initial
	stage("00 authored", {}, s, {"kind": "author", "seed": 42}, [])
	var request := {"warning_request": {"request_id": "reference_0", "target_x": 132.0, "target_y": -8.0}, "cancel_warning": false}
	var result := step(s, 0, request)
	stage("01 warning begins", s, result.state, {"kind": "input_command", "command": request}, result.intents)
	s = result.state
	var before: Dictionary = s
	for tick in range(1, 180):
		result = step(s, tick)
		require(result.intents.is_empty(), "no force during full 180-tick warning")
		s = result.state
	stage("02 final warning interval", before, s, {"kind": "sequential_ticks", "first": 1, "last": 179}, [])
	var warning_checkpoint: Dictionary = s.duplicate(true)
	result = step(s, 180)
	require(result.state.charges.size() == 1 and result.state.actors.back().fuel_mj == 59000, "first command reserves 1000mJ")
	stage("03 first finite force intent", s, result.state, {"kind": "tick", "tick": 180}, result.intents)
	s = result.state
	# These are authority fixtures, not values produced by a hidden solver.
	var collision_a := make_commit(s, 0.5, s.actors.back().x, -14.0, 3.0, 0.0, 14)
	result = external_commit(s, collision_a, "external/contact_A")
	stage("04 supplied contact A", s, result.state, {"kind": "external_collision_fixture", "id": "external/contact_A", "commit": collision_a, "solver_implemented": false}, result.intents)
	s = result.state
	result = step(s, 181)
	require(result.state.charges.back().cost_mj == 3009 and result.state.actors.back().fuel_mj == 55991, "post-contact payment uses saved 3m/s motion")
	stage("05 second intent uses contact A", s, result.state, {"kind": "tick", "tick": 181, "velocity_source": "external/contact_A"}, result.intents)
	s = result.state
	var at_contact := sample_segment(s, 181, 0.75, 0.75)
	var collision_b := make_commit(s, 0.75, at_contact.end.x, at_contact.end.y, -1.5, 0.25, 0)
	result = external_commit(s, collision_b, "external/contact_B")
	require(result.state.warning.reason == "actor_destroyed" and result.state.warning.terminal_motion.revision == 2, "death bound to contact B")
	stage("06 supplied lethal contact B", s, result.state, {"kind": "external_collision_fixture", "id": "external/contact_B", "commit": collision_b, "solver_implemented": false}, result.intents)
	s = result.state
	var glide := sample_segment(s, 181, 0.75, 1.0)
	require(glide.hp == 0 and glide.end.x < glide.start.x and glide.end.y > glide.start.y, "wreck slides on retained saved velocity")
	stage("07 retained wreck glides", s, s, {"kind": "existing_linear_segment_query", "source": "external/contact_B", "segment": glide}, [])
	var later_pose := sample_segment(s, 181, 0.875, 0.875)
	var later := make_commit(s, 0.875, later_pose.end.x, later_pose.end.y, -1.5, 0.25, 0)
	result = external_commit(s, later, "external/same_tick_owner_checkpoint")
	stage("08 legal later same-tick wreck rebase", s, result.state, {"kind": "external_owner_checkpoint", "commit": later}, result.intents)
	s = result.state
	result = step(s, 182)
	require(result.intents.is_empty() and result.state.charges.size() == 2, "dead source does not charge or fire again")
	stage("09 wreck survives next tick", s, result.state, {"kind": "tick", "tick": 182}, result.intents)
	s = result.state
	var encoded: Dictionary = A.save_json(s)
	require(encoded.ok, "save trace snapshot")
	var loaded: Dictionary = A.load_json(encoded.json)
	require(loaded.ok and V.typed_hash(loaded.state) == V.typed_hash(s), "snapshot preserves all typed bits")
	write_file("RESTORE_POINT.json", encoded.json)
	stage("10 snapshot restored", s, loaded.state, {"kind": "typed_snapshot_round_trip", "bytes": encoded.json.to_utf8_buffer().size()}, [])
	var uninterrupted := step(s, 183)
	var resumed := step(loaded.state, 183)
	require(V.typed_hash(uninterrupted) == V.typed_hash(resumed), "resumed next step equals uninterrupted output")
	stage("11 restored continuation", loaded.state, resumed.state, {"kind": "tick", "tick": 183, "comparison": "uninterrupted twin"}, resumed.intents)
	# Separate branch: exact same completed warning, then an external high-speed commit.
	source_ids = {0: "author_seed_42"}
	s = warning_checkpoint
	var fast := make_commit(s, 1.0, s.actors.back().x, -14.0, 60.0, 0.0, 25)
	result = external_commit(s, fast, "external/denial_branch_contact")
	stage("B0 supplied high-speed source", s, result.state, {"kind": "branch_from_stage_02", "external_commit": fast, "solver_implemented": false}, result.intents)
	s = result.state
	result = step(s, 180)
	require(result.state.warning.reason == "resource_exhausted" and result.state.warning.denied_cost_mj == 60009, "unaffordable reservation is refused")
	require(result.state.charges.is_empty() and result.state.actors.back().fuel_mj == 60000, "refusal consumes no resource and emits no force")
	stage("B1 unaffordable intent refused", s, result.state, {"kind": "tick", "tick": 180, "velocity_source": "external/denial_branch_contact"}, result.intents)
	legal_matrix(initial, warning_checkpoint)
	geometry(initial.bundle)
	write_file("TRACE.json", JSON.stringify({"stages": stages, "scope": "helper integration reference; external fixture commits; no collision solver"}, "  ", true, true))
	write_file("LEGAL_SNAPSHOTS.json", JSON.stringify({"checks": legal_snapshots, "false_rejections": false_rejections, "matrix": checkpoints}, "  ", true, true))
	var report := {"suite": "corrected-v3-finite-integration-reference", "passed": failures.is_empty(), "failures": failures,
		"stage_count": stages.size(), "legal_snapshot_checks": legal_snapshots, "false_rejections": false_rejections,
		"fixture_solver_implemented": false, "baseline_game_checked": false, "final_state_hash": V.typed_hash(resumed.state)}
	write_file("REPORT.json", JSON.stringify(report, "  ", true, true))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func step(s: Dictionary, tick: int, command: Variant = null) -> Dictionary:
	var before := V.typed_hash(s)
	var r: Dictionary = A.advance(s, tick, true, command)
	require(r.ok, "advance tick " + str(tick) + ": " + str(r.get("error", "")))
	if not r.ok:
		return {"ok": false, "state": s, "intents": []}
	require(V.typed_hash(s) == before, "advance leaves its input unchanged")
	var reserved: int = 0
	var forces: int = 0
	for intent in r.intents:
		if intent.kind == "actor_force_intent":
			forces += 1
			reserved += intent.reserved_energy_mj
			require(intent.actor_id == s.actors.back().id and intent.source_id == s.actors.back().source_id, "force source identity")
			require(intent.tick == tick and intent.impulse_limit_ns == 1.0 and sqrt(intent.fx_n * intent.fx_n + intent.fy_n * intent.fy_n) <= 120.000000000001, "finite per-tick intent")
	require(r.state.charges.size() == s.charges.size() + forces, "force count equals new reservations")
	require(r.state.actors.back().spent_mj - s.actors.back().spent_mj == reserved, "debit equals emitted reservations")
	require(s.actors.back().fuel_mj - r.state.actors.back().fuel_mj == reserved, "fuel conserved across command")
	legal(r.state, "tick " + str(tick))
	return r

func make_commit(s: Dictionary, fraction: float, x: float, y: float, vx: float, vy: float, hp: int) -> Dictionary:
	return {"actor_id": s.actors.back().id, "tick": s.last_tick, "fraction": fraction,
		"revision": s.actors.back().revision + 1, "x": x, "y": y, "vx": vx, "vy": vy, "hp": hp}

func external_commit(s: Dictionary, commit: Dictionary, identity: String) -> Dictionary:
	var before := V.typed_hash(s)
	var r: Dictionary = A.rebase(s, commit)
	require(r.ok, identity + ": " + str(r.get("error", "")))
	if not r.ok:
		return {"ok": false, "state": s, "intents": []}
	require(V.typed_hash(s) == before, "rebase leaves input unchanged")
	require(V.typed_hash(r.state.actors.back().last_commit) == V.typed_hash(commit), "stored commit exactly matches supplied source")
	require(r.state.actors.back().fuel_mj == s.actors.back().fuel_mj and r.state.charges == s.charges, "external motion commit does not rewrite resource history")
	for index in range(s.actors.size() - 1):
		require(V.typed_hash(r.state.actors[index]) == V.typed_hash(s.actors[index]), "unrelated actor unchanged by patrol commit")
	source_ids[commit.revision] = identity
	legal(r.state, identity)
	return r

func sample_segment(s: Dictionary, tick: int, start: float, end: float) -> Dictionary:
	var before := V.typed_hash(s)
	var r: Dictionary = A.segment(s, s.actors.back().id, tick, start, end)
	require(r.ok, "saved segment query")
	require(V.typed_hash(s) == before, "segment query does not mutate state")
	return r

func legal(s: Dictionary, name: String) -> void:
	legal_snapshots += 1
	var old_result: Dictionary = OLD.restore_snapshot(s)
	var current: Dictionary = A.restore_snapshot(s)
	if old_result.ok and not current.ok:
		var filename := "FALSE_REJECTION_%d.json" % false_rejections.size()
		write_file(filename, V.pack_json(s, "snapshot"))
		false_rejections.append({"name": name, "error": current.error, "snapshot": filename})
		require(false, "new false rejection at " + name + ": " + current.error)
	require(old_result.ok and current.ok, "native generated snapshot accepted in both implementations: " + name)
	if not current.ok:
		return
	var saved: Dictionary = A.save_json(s)
	var restored: Dictionary = A.load_json(saved.json)
	require(restored.ok and V.typed_hash(s) == V.typed_hash(restored.state), "lossless valid snapshot: " + name)
	if s.warning != null:
		for motion in [s.warning.origin_motion, s.warning.terminal_motion]:
			if motion != null:
				require(source_ids.has(motion.revision), "warning has an input source")
		for charge in s.charges:
			require(source_ids.has(charge.motion.revision), "charge has an input source")

func stage(name: String, before: Dictionary, after: Dictionary, cause: Dictionary, intents: Array) -> void:
	legal(after, name)
	var differences := difference(before, after)
	var record := {"name": name, "cause": cause, "intents": intents, "differences": differences,
		"before_hash": V.typed_hash(before), "after_hash": V.typed_hash(after), "sources": sources_for(after)}
	stages.append(record)
	print("STAGE " + name)
	for d in differences:
		print("  " + d.path + ": " + JSON.stringify(d.before) + " -> " + JSON.stringify(d.after))
	print("  cause " + JSON.stringify(cause, "", true, true))
	print("  intents " + JSON.stringify(intents, "", true, true))
	write_file("STAGE_%02d.json" % (stages.size() - 1), V.pack_json(after, "snapshot"))

func sources_for(s: Dictionary) -> Dictionary:
	var out := {"actor_revision": s.actors.back().revision, "actor_input": source_ids.get(s.actors.back().revision, "missing"), "paid": []}
	if s.warning != null:
		out["warning_origin"] = source_ids.get(s.warning.origin_motion.revision, "missing")
		if s.warning.terminal_motion != null:
			out["terminal"] = source_ids.get(s.warning.terminal_motion.revision, "missing")
	for charge in s.charges:
		out.paid.append({"tick": charge.tick, "cost_mj": charge.cost_mj, "input": source_ids.get(charge.motion.revision, "missing")})
	return out

func flatten(value: Variant, path: String, out: Dictionary) -> void:
	if value is Dictionary:
		if value.is_empty(): out[path] = {"type": "Dictionary", "value": "empty"}
		for key in value: flatten(value[key], path + "." + str(key), out)
	elif value is Array:
		if value.is_empty(): out[path] = {"type": "Array", "value": "empty"}
		for i in value.size(): flatten(value[i], path + "[" + str(i) + "]", out)
	elif typeof(value) == TYPE_FLOAT:
		out[path] = {"type": "float64", "decimal": var_to_str(value), "bits_le": V.float_bits(value)}
	else:
		out[path] = {"type": type_string(typeof(value)), "value": value}

func difference(before: Dictionary, after: Dictionary) -> Array:
	var lhs: Dictionary = {}
	var rhs: Dictionary = {}
	flatten(before, "$", lhs)
	flatten(after, "$", rhs)
	var keys: Array = lhs.keys()
	for key in rhs:
		if not keys.has(key): keys.append(key)
	keys.sort()
	var result: Array = []
	for key in keys:
		if lhs.get(key) != rhs.get(key): result.append({"path": key, "before": lhs.get(key), "after": rhs.get(key)})
	return result

func legal_matrix(initial: Dictionary, warned: Dictionary) -> void:
	var tiny: float = "0100000000000000".hex_decode().decode_double(0)
	var below_one: float = "ffffffffffffef3f".hex_decode().decode_double(0)
	for fraction in [0.0, tiny, 0.75, below_one, 1.0]:
		source_ids = {0: "author_seed_42"}
		var s: Dictionary = A.advance(initial, 0, true, {"warning_request": {"request_id": "matrix_0", "target_x": 132.0, "target_y": -8.0}, "cancel_warning": false}).state
		s = step(s, 1).state
		var c := make_commit(s, fraction, s.actors.back().x, -14.0, -1.5, 0.25, 0)
		s = external_commit(s, c, "matrix/death").state
		c = make_commit(s, fraction, c.x, c.y, c.vx, c.vy, 0)
		s = external_commit(s, c, "matrix/equal_time_wreck").state
		if fraction < 1.0:
			var pose := sample_segment(s, 1, 1.0, 1.0)
			c = make_commit(s, 1.0, pose.end.x, pose.end.y, c.vx, c.vy, 0)
			s = external_commit(s, c, "matrix/endpoint_wreck").state
		s = step(s, 2).state
		c = make_commit(s, 0.0, s.actors.back().x, s.actors.back().y, c.vx, c.vy, 0)
		s = external_commit(s, c, "matrix/next_tick_zero").state
		checkpoints.append({"case": "legal_death_endpoint_aliases", "death_fraction_bits": V.float_bits(fraction), "final_hash": V.typed_hash(s)})
	# A pre-existing explicit cancellation remains the cause after later damage.
	source_ids = {0: "author_seed_42"}
	var cancelled: Dictionary = step(warned, 180, {"warning_request": null, "cancel_warning": true}).state
	var dead_commit := make_commit(cancelled, 0.5, cancelled.actors.back().x, -14.0, 0.0, 0.0, 0)
	cancelled = external_commit(cancelled, dead_commit, "matrix/damage_after_explicit_cancel").state
	require(cancelled.warning.reason == "explicit_cancel", "later damage does not rewrite prior cancellation cause")
	checkpoints.append({"case": "damage_after_explicit_cancel", "final_hash": V.typed_hash(cancelled)})
	# Rejected mutation from the prior audit must remain rejected.
	var s: Dictionary = A.advance(initial, 0, true, {"warning_request": {"request_id": "negative_0", "target_x": 132.0, "target_y": -8.0}, "cancel_warning": false}).state
	source_ids = {0: "author_seed_42"}
	s = step(s, 1).state
	var c := make_commit(s, 0.75, s.actors.back().x, -14.0, 0.0, 0.0, 0)
	s = external_commit(s, c, "negative/death").state
	var a: Dictionary = s.actors.back()
	c = make_commit(s, 0.25, a.x, a.y, a.vx, a.vy, 0)
	a.revision = c.revision
	a.last_commit = c
	a.anchor_fraction = 0.25
	require(OLD.restore_snapshot(s).ok and not A.restore_snapshot(s).ok, "known invalid time rewind stays rejected")

func geometry(bundle: Dictionary) -> void:
	var report: Dictionary = B.initial_clearance_report(bundle, 1.0)
	require(report.ok and report.reference_bypass_clear and report.direct_reference_path_blocked and report.bodies_separate, "360m reference has a blocked direct path and an open static detour")
	require(report.bypass_clearance_m >= 3.75, "reference craft has at least 3.75m spare clearance")
	for body in bundle.actors:
		require(body.x + body.radius_m + 1.0 < 170.0, "final 170..340m segment is past all initial circles")
	var example := {"route_length_m": 360.0, "axes": "+x right, +y down", "seed": 42, "craft_radius_m": 1.0,
		"gate_x_reference_only": [85.0, 185.0, 275.0], "actors": bundle.actors,
		"detour_points": [[20.0, -8.0], [98.0, -20.0], [150.0, -20.0], [170.0, -8.0], [340.0, -8.0]],
		"direct_points": [[20.0, -8.0], [340.0, -8.0]], "clearance": report,
		"scope": "static initial circles only; no baseline colliders, moving-contact guarantee, real craft or final art"}
	write_file("GEOMETRY.json", JSON.stringify(example, "  ", true, true))
	write_file("GEOMETRY_TYPED.json", V.pack_json(example, "reference_geometry"))

func write_file(name: String, text: String) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(text)
	file.close()
