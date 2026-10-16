extends SceneTree
## Isolated, explicit offline QA: no scene, production HUD, economy or save writes.
const Moon = preload("res://scripts/pilot_moon_profile.gd")
const Guide = preload("res://tools/moon_offline_guide.gd")
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
var failures: Array = []
var assertions = 0
var report = {"schema": 1, "scope": "isolated headless content + frozen real pilot-v3 solver; NOT native gameplay or runtime integration", "cases": [], "replay": [], "profile_checks": [], "altered_builds": []}

func _initialize() -> void:
	_test_profile()
	if not "--profile-only" in OS.get_cmdline_user_args():
		_test_actual_routes()
		_test_altered_builds()
		_test_ccd_and_capture()
	report.assertions = assertions
	report.failures = failures
	report.status = "PASS" if failures.is_empty() else "FAIL"
	report.engine = Engine.get_version_info().string
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file = FileAccess.open(argument.trim_prefix("--output="), FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	for failure in failures: printerr("FAIL: ", failure)
	print("%s: %d Moon content assertions; %d failed" % [report.status, assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)

func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _same(a[i], b[i]): return false
		return true
	return a == b

func _test_profile() -> void:
	var source = {"id": 4, "contract_id": "QA-MOON-A", "weight": 2.8, "reward": 410, "required": 85.0, "rep": 10, "client": "existing", "cargo": "existing", "story": "existing"}
	var before = source.duplicate(true)
	var route = Moon.route(source)
	_check(source == before, "content authoring leaves base offer untouched")
	for key in source: _check(route[key] == source[key], "preserved commercial field: " + key)
	_check(Moon.route(route) == route, "new-content authoring is idempotent")
	_check(route.control_version == "pilot-v3" and route.pilot_profile == "pilot-v3", "Moon uses original physics/replay version")
	_check(route.route_profile == "moon-surface-v1" and route.route_kind == "moon" and route.destination_id == "moon-regolith-airlock", "distinct route/kind/destination identity")
	_check(not Moon.is_moon_route(Extreme.route()), "missing Moon identity never reclassifies saved ascent")
	_check(route.distance == 900.0 and route.destination_y == -125.0, "bounded compressed 900m route with lower receiver")
	var old = Extreme.route()
	for key in ["gravity", "wind", "variation", "pilot_drag", "pilot_cruise_speed", "pilot_boost_speed", "pilot_vertical_speed", "pilot_net_force_limit", "pilot_battery_multiplier", "pilot_energy_tariff", "pilot_altitude", "pilot_climb_start", "pilot_climb_end"]:
		_check(route[key] == old[key], "unchanged paid controller/environment field: " + key)
	_check(Moon.starter_design() == Extreme.starter_design() and Moon.starter_launcher() == Extreme.starter_launcher(), "identical eight-part starter and actual physical shop launcher")
	_check(Moon.starter_design().size() == 8, "ordinary starter remains eight parts")
	_check(route.pilot_gates.size() == 4, "Moon appends no narrow paired gates")
	for i in range(4):
		for key in ["x", "y", "half_gap", "lane_offset"]:
			_check(route.pilot_gates[i][key] == old.pilot_gates[i][key], "unchanged ascent gate%d %s" % [i, key])
	for i in range(8):
		for key in ["x", "y", "radius", "health", "mass", "pilot_gate", "gate_index"]:
			_check(route.hazards[i][key] == old.hazards[i][key], "unchanged ascent collision%d %s" % [i, key])
	_check(Ascent.path_y(0.0, route) == 0.0 and Ascent.path_y(520.0, route) == -150.0, "same real city/cloud ascent starts at shop height")
	_check(Ascent.path_tangent(650.0, route) == Vector2.RIGHT and Ascent.path_tangent(900.0, route) == Vector2.RIGHT, "lunar solver tangent stays level; W/S must supply descent")
	var ores = 0; var crags = 0
	for h in route.hazards:
		_check(float(h.x) - float(h.radius) > 80.0, "no obstacle is born at the launch craft")
		if h.get("moon_role", "") == "ore":
			ores += 1
			_check(h.destructible and h.health == 80.0 and not h.get("pilot_gate", false), "optional finite ore uses actual drill path")
		elif h.get("moon", false): _check(not h.destructible, "Moon immutable rock/hardware cannot be drilled")
		if h.get("moon_role", "") == "crag": crags += 1
	_check(ores == 2 and crags == 4, "two lower outcrops each have optional finite ore")
	var clear_approach = true
	for h in route.hazards:
		if h.get("moon_role", "") != "airlock":
			clear_approach = clear_approach and float(h.x) + float(h.radius) < float(route.moon_clear_approach_start)
	_check(clear_approach, "last95m has no crag or ore")
	_check(route.moon_receiver.entrance_side == "left", "explicit side-entry receiver")
	_check(_same(route, JSON.parse_string(JSON.stringify(route))), "complete new-route geometry survives JSON numeric value equality")
	report.profile_checks = {"route": route, "starter_design": Moon.starter_design(), "starter_launcher": Moon.starter_launcher()}

func _make(route: Dictionary, design: Array = [], pad: bool = true):
	var sim = Sim.new()
	sim.configure(Moon.starter_design() if design.is_empty() else design, Moon.starter_launcher() if pad else [], route, 42)
	return sim

func _state(sim) -> Dictionary:
	return {"status": sim.status, "elapsed": sim.elapsed, "position": sim.cargo_position(), "telemetry": sim.telemetry.duplicate(true), "parts": sim.parts.duplicate(true), "bodies": sim.bodies.duplicate(true), "obstacles": sim.obstacles.duplicate(true), "events": sim.events.duplicate(true)}

func _step(sim, command: Dictionary, split: bool = false) -> void:
	sim.set_pilot_input(command.axis_q, command.boost, command.active)
	if split:
		sim.step(1.0 / 120.0); sim.step(1.0 / 120.0)
	else: sim.step(1.0 / 60.0)

func _test_actual_routes() -> void:
	for weight in ([2.8] if "--diagnose-standard" in OS.get_cmdline_user_args() else [2.8, 4.34]):
		var heavy = weight == 4.34
		var route = Moon.route({"id": 4, "weight": weight, "reward": 465 if heavy else 410, "required": 85.0, "rep": 10})
		if heavy: route.deadline = 67.0 # Existing new-heavy-offer +3s convention.
		var result = _run_route(route, Moon.starter_design(), "heavy-one-cell" if heavy else "standard-one-cell", true)
		if not heavy:
			_check(result.status == "success" and result.elapsed <= route.deadline, "standard2.8 ordinary one-cell ship delivers within deadline")
		if result.status == "success":
			_check(result.integrity == 1.0 and result.swept_contacts == 0, "guided %s completes without collision damage" % result.label)
			_check(result.energy_remaining > 100.0 and result.energy_used > 100.0, "guided %s consumes finite energy with measured reserve" % result.label)
			_check(result.orbit_y < -140.0 and result.final_position[1] > result.orbit_y + 12.0, "guided %s genuinely descends after orbital segment" % result.label)
			_check(result.last_pre_capture_speed <= 24.0, "guided %s obeys receiver speed condition by real motion" % result.label)
		elif heavy:
			var two_cells = Moon.starter_design()
			two_cells.append(Extreme.part(20, "battery", -2, 0))
			var extra = _run_route(route, two_cells, "heavy-earned-spare-cell", false)
			_check(extra.status == "success", "if heavy one-cell cannot finish, disclosed real spare-cell build can")

func _run_route(route: Dictionary, design: Array, label: String, check_replay: bool) -> Dictionary:
	var sim = _make(route, design)
	var timeline = Timeline.new()
	var initial_energy: float = sim.total_energy()
	var initial_mass: float = sim.total_mass()
	var orbit_y = 0.0; var axis = 0; var ticks = 0; var peak_speed = 0.0
	var last_pre_capture_speed = 0.0; var last_pre_capture_vertical_speed = 0.0
	var checkpoints: Array = []
	var sampled_ascent = false; var sampled_approach = false
	var energy_excess = 0.0
	for tick in range(roundi(float(route.time_limit) * 60.0) + 2):
		if tick % 12 == 0: axis = Guide.command_axis(sim)
		var command = {"axis_q": axis, "boost": false, "active": false}
		timeline.record(tick, command)
		last_pre_capture_speed = float(sim.telemetry.speed)
		last_pre_capture_vertical_speed = float(sim.telemetry.vertical_speed)
		_step(sim, command)
		ticks = tick + 1
		peak_speed = maxf(peak_speed, float(sim.telemetry.speed))
		if sim.cargo_position().x > 520.0 and orbit_y == 0.0: orbit_y = sim.cargo_position().y
		var kinetic = 0.0
		for body in sim.bodies:
			kinetic += 0.5 * float(body.mass) * body.velocity.length_squared() + 0.5 * float(body.inertia) * body.angular_velocity * body.angular_velocity
		energy_excess = maxf(energy_excess, kinetic + sim.total_energy() - initial_energy - float(sim.telemetry.launch_energy))
		var checkpoint_name = ""
		if not sampled_ascent and sim.cargo_position().x >= 210.0:
			sampled_ascent = true; checkpoint_name = "ascent"
		elif not sampled_approach and sim.cargo_position().x >= 730.0:
			sampled_approach = true; checkpoint_name = "lunar-approach"
		if check_replay and not checkpoint_name.is_empty():
			# Offline pause means no integration calls. Input release is explicitly
			# applied at resume and recorded in both paths; no native UI claim.
			var paused_state = _state(sim)
			for idle_frame in range(120): pass
			_check(_state(sim) == paused_state, label + " offline pause advances no physics: " + checkpoint_name)
			checkpoints.append({"name": checkpoint_name, "ticks": ticks, "state": paused_state, "commands": timeline.snapshot()})
			axis = 0 # Next command is a recorded release, not an invisible correction.
		if sim.status != "running": break
	var result = {"label": label, "weight": route.weight, "reward": route.reward, "deadline": route.deadline, "required_integrity_percent": route.required,
		"control_version": sim.telemetry.control_version, "route_profile": sim.route.route_profile,
		"design": design, "launcher": Moon.starter_launcher(), "seed": 42,
		"initial_mass_kg": initial_mass, "initial_ship_energy_j": initial_energy,
		"launch_energy_j": sim.telemetry.launch_energy, "status": sim.status,
		"elapsed": sim.elapsed, "ticks": ticks, "final_position": [sim.cargo_position().x, sim.cargo_position().y],
		"orbit_y": orbit_y, "final_speed": sim.telemetry.speed, "final_speed_note": "terminal capture marks cargo delivered, so inherited telemetry is zero; this is not arrival speed",
		"last_pre_capture_speed": last_pre_capture_speed, "last_pre_capture_vertical_speed": last_pre_capture_vertical_speed, "peak_speed": peak_speed,
		"energy_used": sim.telemetry.energy_used, "energy_remaining": sim.total_energy(),
		"energy_tariff": route.pilot_energy_tariff, "integrity": sim.ship_integrity(),
		"swept_contacts": sim.telemetry.swept_contacts, "ccd_budget_holds": sim.telemetry.get("ccd_budget_holds", 0),
		"max_kinetic_plus_stored_excess_j": energy_excess,
		"ammo_cost": sim.telemetry.ammo_cost, "repair_cost": sim.telemetry.repair_cost, "lost_cost": sim.telemetry.lost_cost,
		"timeline": timeline.snapshot(), "input_policy": "offline actual-state W/release/S observer at5Hz, 60Hz commands; no boost/active"}
	var income = int(int(route.reward) * clampf(float(route.deadline) / maxf(sim.elapsed, float(route.deadline)), 0.35, 1.0) * clampf(sim.ship_integrity() * 100.0 / float(route.required), 0.0, 1.0)) if sim.status == "success" else 0
	var energy_fee = int(ceil(float(sim.telemetry.energy_used) * float(route.pilot_energy_tariff)))
	result.balance_probe = {"read_only_estimate": true, "income": income, "energy_fee": energy_fee,
		"profit": income - energy_fee - int(ceil(sim.telemetry.ammo_cost)) - int(ceil(sim.telemetry.repair_cost)) - int(ceil(sim.telemetry.lost_cost))}
	report.cases.append(result)
	print("MOON %s status=%s time=%.4f energy=%.4f reserve=%.4f integrity=%.4f contacts=%d" % [label, sim.status, sim.elapsed, sim.telemetry.energy_used, sim.total_energy(), sim.ship_integrity(), sim.telemetry.swept_contacts])
	_check(energy_excess < 0.02, label + " creates no unbudgeted kinetic/storage energy")
	if check_replay:
		for checkpoint in checkpoints:
			var snapshot: Dictionary = JSON.parse_string(JSON.stringify({"design": design, "launcher": Moon.starter_launcher(), "route": route, "seed": 42, "ticks": checkpoint.ticks, "commands": checkpoint.commands}))
			var replay = Sim.new(); var saved_commands = Timeline.new()
			replay.configure(snapshot.design, snapshot.launcher, snapshot.route, int(snapshot.seed))
			_check(saved_commands.restore(snapshot.commands, int(snapshot.ticks)), label + " restores sparse commands at " + checkpoint.name)
			for tick in range(int(snapshot.ticks)): _step(replay, saved_commands.state_at(tick), true)
			# JSON changes unused authored integer metadata (e.g. gate_index0)
			# to float0.0. Compare exact numeric VALUES recursively; no epsilon,
			# ignored keys, state rewriting or simulation correction is allowed.
			var prefix_exact = _same(_state(replay), checkpoint.state) and replay.telemetry == checkpoint.state.telemetry and replay.cargo_position() == checkpoint.state.position
			if not prefix_exact: print("REPLAY DIFF ", label, " ", checkpoint.name, " ", _first_diff(checkpoint.state, _state(replay)))
			_check(prefix_exact, label + " exact JSON/two120Hz replay at " + checkpoint.name)
			for tick in range(int(snapshot.ticks), ticks): _step(replay, timeline.state_at(tick), true)
			var final_exact = _same(_state(sim), _state(replay)) and sim.telemetry == replay.telemetry and sim.cargo_position() == replay.cargo_position()
			_check(final_exact, label + " exact continued replay from " + checkpoint.name)
			report.replay.append({"label": label, "checkpoint": checkpoint.name, "ticks": checkpoint.ticks, "position": [checkpoint.state.position.x, checkpoint.state.position.y], "prefix_exact": prefix_exact, "final_exact": final_exact, "pause_scope": "offline no-step suspension; recorded release at resume, not native scene pause", "comparison": "all recursive values exact; JSON int/float metadata value equivalence; direct exact telemetry and cargo position; no numeric tolerance"})
	return result

func _test_altered_builds() -> void:
	for kind in ["empty-cell", "no-engines", "reversed-engines", "disconnected-cell", "one-engine"]:
		var design = Moon.starter_design()
		if kind == "no-engines": design = design.filter(func(p): return p.type != "thruster")
		if kind == "one-engine": design = design.filter(func(p): return p.id != 6)
		for part in design:
			if kind == "reversed-engines" and part.type == "thruster": part.rot = 2
			if kind == "disconnected-cell" and part.type == "battery": part.x = -6
		var sim = _make(Moon.route({"weight": 2.8}), design, false)
		if kind == "empty-cell":
			for part in sim.parts.values(): part.energy = 0.0
		for tick in range(600):
			sim.set_pilot_input(-1000, false, false); sim.step(1.0 / 60.0)
			if sim.status != "running": break
		var finite = true
		for body in sim.bodies: finite = finite and body.position.is_finite() and body.velocity.is_finite() and is_finite(body.angle)
		_check(finite and sim.status != "success", kind + " remains physical/finite with no automatic completion")
		if kind in ["empty-cell", "no-engines", "disconnected-cell"]:
			_check(sim.telemetry.energy_used == 0.0 and sim._cargo_body().velocity == Vector2.ZERO, kind + " no invisible lift or connected power")
		report.altered_builds.append({"label": kind, "scope": "10s no-pad causality sanity, not a whole-route success requirement", "status": sim.status, "elapsed": sim.elapsed, "position": [sim.cargo_position().x, sim.cargo_position().y], "speed": sim.telemetry.speed, "energy_used": sim.telemetry.energy_used, "integrity": sim.ship_integrity(), "finite": finite, "design": design})

func _test_ccd_and_capture() -> void:
	# Synthetic initial conditions are restricted to these explicit collision
	# unit fixtures. Successful full flights above contain no body assignments.
	var route = Moon.route({"weight": 2.8})
	var crag: Dictionary = route.hazards[8]
	var collision = _make(route, [Extreme.part(1, "cargo", 0)], false)
	collision.bodies[0].position = Vector2(crag.x - crag.radius - 5.0, crag.y)
	collision.bodies[0].velocity = Vector2(1800.0, 0.0)
	collision.step(1.0 / 120.0)
	_check(collision.telemetry.swept_contacts > 0, "genuine lunar circle reaches chronological CCD at extreme test speed")
	for speed in [18.0, 100.0]:
		var capture = _make(route, [Extreme.part(1, "cargo", 0)], false)
		capture.bodies[0].position = Vector2(route.distance - 0.05, route.destination_y)
		capture.bodies[0].velocity = Vector2(speed, 0.0)
		capture.step(1.0 / 120.0)
		_check(capture.status == ("success" if speed == 18.0 else "failed"), "actual Moon receiver speed test %.0f" % speed)

func _first_diff(a: Variant, b: Variant, path: String = "root") -> String:
	if a == b: return ""
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): return path + "." + str(key) + " missing"
			if a[key] != b[key]: return _first_diff(a[key], b[key], path + "." + str(key))
	if a is Array and b is Array:
		if a.size() != b.size(): return path + " array size differs"
		for i in range(a.size()):
			if a[i] != b[i]: return _first_diff(a[i], b[i], path + "[" + str(i) + "]")
	return path + " " + str(a) + " <> " + str(b) + " types " + str(typeof(a)) + "/" + str(typeof(b))
