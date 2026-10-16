extends SceneTree
## Pure-physics stage. No production scene, renderer, assets, economy or save writes.
## -- --profile-only runs data/legacy-source checks without advancing simulation.
const Ground = preload("res://scripts/pilot_ground_profile.gd")
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
var failures: Array = []
var assertions = 0

func _initialize() -> void:
	_test_profile()
	_test_frozen_sources()
	if not "--profile-only" in OS.get_cmdline_user_args():
		_test_controls_and_energy()
		_test_ccd_and_receiver()
		_test_delivery_and_replay()
	if failures.is_empty():
		print("PASS: %d ground-city-v1 assertions" % assertions); quit(0)
	else:
		for item in failures: printerr("FAIL: ", item)
		printerr("%d/%d ground route assertions failed" % [failures.size(), assertions]); quit(1)

func _check(value: bool, title: String) -> void:
	assertions += 1
	if not value: failures.append(title)

func _same_json_values(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same_json_values(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _same_json_values(a[i], b[i]): return false
		return true
	return a == b

func _test_profile() -> void:
	var commercial = {"id": 0, "contract_id": "D1-A", "weight": 1.55, "reward": 220, "required": 90.0, "client": "existing", "cargo": "existing cargo", "story": "existing story"}
	var source = commercial.duplicate(true)
	var r = Ground.route(commercial)
	_check(commercial == source, "profile authoring never mutates the source contract")
	for key in commercial:
		_check(r[key] == commercial[key], "ground authoring preserves commercial/story field: " + key)
	_check(Ground.route(r) == r, "authoring the same profile twice is idempotent")
	_check(r.route_profile == "ground-city-v1" and r.control_version == "pilot-v3" and r.pilot_profile == "pilot-v3", "content identity is separate from frozen physics identity")
	_check(Ground.is_ground_route(r) and not Ground.is_ground_route(Extreme.route()), "missing route_profile never silently reclassifies old v3 ascent")
	_check(r.background_route == "city" and r.route_kind == "ground", "city presentation never transitions to orbit by horizontal progress")
	_check(r.distance == 360.0 and r.destination_y == -8.0 and r.delivery_radius == 7.0, "new route has its own bounded receiver geometry")
	_check(Ground.path_y(0.0, r) == 0.0 and Ground.path_y(360.0, r) == -8.0, "real path rises only8m in360m")
	_check(Ground.path_heading(0.0, r) == 0.0 and Ground.path_heading(300.0, r) == 0.0, "departure and receiver approach are level")
	var low_altitude = true
	for x in range(361):
		low_altitude = low_altitude and Ground.path_y(float(x), r) >= -8.0 and Ground.path_y(float(x), r) <= 0.0
		low_altitude = low_altitude and Ground.path_y(float(x), r) == Ascent.path_y(float(x), r)
	_check(low_altitude, "entire lane stays low and uses the exact unchanged v3 tangent function")
	_check(r.hazards.size() == 6 and r.pilot_gates.size() == 3, "six ordinary CCD circles form three visible paired gates")
	for i in range(r.pilot_gates.size()):
		var gate: Dictionary = r.pilot_gates[i]
		var above: Dictionary = r.hazards[i * 2]
		var below: Dictionary = r.hazards[i * 2 + 1]
		_check(above.y + above.radius == gate.y - gate.half_gap and below.y - below.radius == gate.y + gate.half_gap, "gate%d metadata matches physical clear gap" % i)
		_check(above.pilot_gate and below.pilot_gate, "gate%d retains v3 non-drillable collision geometry" % i)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(r))
	_check(_same_json_values(restored, r), "complete authored route survives JSON value equality")
	_check(Extreme.route().distance == 520.0 and Extreme.route().destination_y == -150.0, "existing v3 ascent profile is unchanged")

func _open_route() -> Dictionary:
	var r = Ground.route()
	r.hazards = []; r.pilot_gates = []; r.distance = 3000.0; r.boundary_y = 3000.0
	r.pilot_altitude = 0.0; r.destination_y = 0.0; r.time_limit = 120.0; r.pilot_drag = 0.0
	return r

func _sim(design: Array = [], data: Dictionary = {}, pad: bool = false):
	var s = Sim.new()
	s.configure(Ground.starter_design() if design.is_empty() else design,
		Ground.starter_launcher() if pad else [], _open_route() if data.is_empty() else data, 42)
	return s

func _advance(s, seconds: float, axis: int = 0, boost: bool = false, active: bool = false) -> void:
	for tick in range(roundi(seconds * 60.0)):
		s.set_pilot_input(axis, boost, active); s.step(1.0 / 60.0)

func _test_controls_and_energy() -> void:
	var up = _sim(); var down = _sim()
	_advance(up, 1.0, -1000); _advance(down, 1.0, 1000)
	_check(up.telemetry.vertical_speed < -1.0 and down.telemetry.vertical_speed > 1.0, "W/S produces opposite real steering velocities")
	_check(up.telemetry.energy_used > 0.0 and down.telemetry.energy_used > 0.0, "steering and attitude expend connected stored energy")
	var bare = _sim([Extreme.part(1, "cargo", 0)])
	_advance(bare, 0.5, -1000, true)
	_check(bare.cargo_position() == Vector2.ZERO, "route identity grants no free lift or forward motion")
	var empty = _sim()
	for p in empty.parts.values(): p.energy = 0.0
	empty.bodies[0].velocity = Vector2(3, -2); empty.bodies[0].angular_velocity = 0.1
	_advance(empty, 0.5, 1000, true)
	_check(empty.bodies[0].velocity == Vector2(3, -2) and empty.bodies[0].angular_velocity == 0.1, "empty craft coasts without path capture or hidden stabilizer")
	var light = _sim(); var heavy = _sim([], _open_route().merged({"weight": 4.34}, true))
	_advance(light, 2.0); _advance(heavy, 2.0)
	_check(light.telemetry.speed > heavy.telemetry.speed + 1.0, "cargo mass remains a real acceleration cost")
	var reversed_design = Ground.starter_design()
	for p in reversed_design:
		if p.type == "thruster": p.rot = 2
	var reversed = _sim(reversed_design); _advance(reversed, 2.0)
	_check(reversed.telemetry.forward_speed < 0.5, "engine mounting still bounds permitted nozzle directions")
	var cut = _sim([Extreme.part(1, "cargo", 0), Extreme.part(2, "thruster", 1), Extreme.part(3, "battery", 5)])
	_advance(cut, 0.5, 0, true)
	_check(cut.body_for_part(1).velocity == Vector2.ZERO and cut.telemetry.energy_used == 0.0, "disconnected battery cannot energize the cargo engines")
	var gated = _sim([Extreme.part(1, "cargo", 0), Extreme.part(2, "thruster", 1, 0, {"input_a": -2}), Extreme.part(3, "battery", -1)])
	_advance(gated, 0.5, 0, true)
	_check(gated.telemetry.thrust_actual == 0.0, "cockpit circuit disables engine until actual signal is held")
	var ordinary = _sim(); var boosted = _sim()
	_advance(ordinary, 2.0); _advance(boosted, 2.0, 0, true)
	_check(boosted.telemetry.speed > ordinary.telemetry.speed and boosted.telemetry.energy_used > ordinary.telemetry.energy_used, "v3 full mounted-output boost adds real paid speed")

func _test_ccd_and_receiver() -> void:
	var r = Ground.route()
	var gate: Dictionary = r.pilot_gates[0]
	var s = _sim([Extreme.part(1, "cargo", 0)], r)
	s.bodies[0].position = Vector2(gate.x - 8.0, r.hazards[1].y)
	s.bodies[0].velocity = Vector2(1800, 0)
	s.step(1.0 / 120.0)
	_check(s.telemetry.swept_contacts > 0 and s.status != "success", "high-speed gate approach reaches CCD rather than tunneling through circle")
	var safe = _sim([Extreme.part(1, "cargo", 0)], r)
	safe.bodies[0].position = Vector2(r.distance - 0.05, r.destination_y)
	safe.bodies[0].velocity = Vector2(18, 0)
	safe.step(1.0 / 120.0)
	_check(safe.status == "success" and safe.telemetry.delivered_count == 1, "receiver captures a valid swept entry at actual dock altitude")
	var fast = _sim([Extreme.part(1, "cargo", 0)], r)
	fast.bodies[0].position = Vector2(r.distance - 0.05, r.destination_y)
	fast.bodies[0].velocity = Vector2(100, 0)
	fast.step(1.0 / 120.0)
	_check(fast.status == "failed" and not fast.telemetry.delivered, "receiver rejects over-speed crossing without free braking")
	var high = _sim([Extreme.part(1, "cargo", 0)], r)
	high.bodies[0].position = Vector2(r.distance - 0.05, r.destination_y - r.delivery_radius - 1.0)
	high.bodies[0].velocity = Vector2(18, 0)
	high.step(1.0 / 120.0)
	_check(high.status == "running" and not high.telemetry.delivered, "receiver cannot capture a cargo outside its saved vertical aperture")

## TEST-ONLY observer. Emits W/release/S commands, never position/velocity writes.
static func binary_guidance(s) -> int:
	var pos: Vector2 = s.cargo_position()
	var offset = 0.0
	for gate in s.route.get("pilot_gates", []):
		if pos.x < float(gate.x) + 6.5:
			offset = float(gate.lane_offset); break
	var normal = Ground.path_tangent(pos.x, s.route).orthogonal() * -1.0
	var body: Dictionary = s._cargo_body()
	var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var lateral_speed = velocity.dot(normal)
	var acceleration = float(s.route.get("pilot_net_force_limit", 30.0)) / maxf(1.0, float(body.get("mass", 10.2)))
	var stopping_preview = lateral_speed * (0.45 + absf(lateral_speed) / (2.0 * acceleration * 0.9))
	var error = Ground.path_y(pos.x, s.route) + offset - pos.y - stopping_preview
	return int(signf(error)) * 1000 if absf(error) > 0.9 else 0

func _test_delivery_and_replay() -> void:
	for weight in [1.0, 1.55, 4.34]:
		var r = Ground.route({"weight": weight})
		var s = _sim([], r, true); var timeline = Timeline.new()
		var ticks = 0; var axis = 0; var highest_altitude = 0.0; var lowest_altitude = 0.0
		for tick in range(3000):
			if tick % 12 == 0: axis = binary_guidance(s)
			var command = {"axis_q": axis, "boost": false, "active": tick % 120 < 30}
			timeline.record(tick, command)
			s.set_pilot_input(command.axis_q, command.boost, command.active); s.step(1.0 / 60.0)
			ticks = tick + 1
			highest_altitude = maxf(highest_altitude, -s.cargo_position().y)
			lowest_altitude = minf(lowest_altitude, -s.cargo_position().y)
			if s.status != "running": break
		print("GROUND weight=%.2f status=%s time=%.3f x=%.3f y=%.3f energy=%.3f remaining=%.3f integrity=%.3f altitude_range=%.3f..%.3f commands=%d" % [weight, s.status, s.elapsed, s.cargo_position().x, s.cargo_position().y, s.telemetry.energy_used, s.total_energy(), s.ship_integrity(), lowest_altitude, highest_altitude, timeline.commands.size()])
		_check(s.status == "success" and s.elapsed < r.deadline, "ordinary W/S delivery meets deadline at cargo weight %.2f" % weight)
		_check(s.ship_integrity() > 0.99 and s.telemetry.swept_contacts == 0, "guided route clears actual colliders without damage at weight %.2f" % weight)
		_check(highest_altitude < 22.0 and lowest_altitude > -4.0, "actual trajectory stays in low-altitude corridor at weight %.2f" % weight)
		_check(s.telemetry.energy_used > 100.0 and s.total_energy() > 100.0, "successful low-altitude delivery consumes finite real energy at weight %.2f" % weight)
		_check(s.route.route_profile == Ground.ROUTE_PROFILE and s.telemetry.control_version == "pilot-v3", "solver keeps route identity and original physics identity at weight %.2f" % weight)
		if weight != 1.55: continue
		# Deliberately restore the saved route directly. Never call Ground.route()
		# in this replay path, or future content defaults would reinterpret it.
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify({"design": Ground.starter_design(), "launcher": Ground.starter_launcher(), "route": r, "seed": 42, "commands": timeline.snapshot(), "ticks": ticks}))
		var replay = Sim.new(); var commands = Timeline.new()
		replay.configure(snapshot.design, snapshot.launcher, snapshot.route, snapshot.seed)
		_check(commands.restore(snapshot.commands, snapshot.ticks), "ground sparse command timeline survives real JSON checkpoint")
		for tick in range(snapshot.ticks):
			var command: Dictionary = commands.state_at(tick)
			replay.set_pilot_input(command.axis_q, command.boost, command.active)
			replay.step(1.0 / 120.0); replay.step(1.0 / 120.0)
		_check(s.status == replay.status and s.cargo_position() == replay.cargo_position() and s.telemetry == replay.telemetry and s.events == replay.events, "ground JSON replay is exact including60Hz/two120Hz stepping")
	var neutral = _sim([], Ground.route({"weight": 1.0}), true)
	_advance(neutral, 50.0)
	_check(neutral.status != "success" and neutral.telemetry.swept_contacts > 0, "ground route requires real steering through visible alternating gates")

func _test_frozen_sources() -> void:
	var expected = {
		"simulation.gd": "582e188f09949cb969a4f0a73dbd97d58f2df38ec17f76568eb229ecfecf369e",
		"pilot_simulation.gd": "81b7d5bdb4514663d3d89c0ae7cf7a510344d53cecfcf05f205ae97af727acd6",
		"pilot_profile.gd": "41031fc568aa5aa2c37c023b5b162ff9f24dd3db97e2fd6dec14dadb207132dd",
		"pilot_ascent_simulation.gd": "ff2eb35b770f17eeaecd78ae302dc134e6e9260260a37022b6e198e046ae4d87",
		"pilot_ascent_profile.gd": "a8235b741aeddbad5442856a87115a1bf069d3f1b81d1e0ba063fdcd8183f004",
		"pilot_extreme_simulation.gd": "28fc509a2c88fd3e3f89b78ab454e42128bd4b0b6e5118feb6971f74a377b266",
		"pilot_extreme_profile.gd": "9bf3a7ed3f1d01300272cae7caa80ac20e2c1fe69e78c44cbc6129c953a51184",
		"parts.gd": "1a92c0202b022e3090d50097145743cd65e3d002b9b5b20bd187f1faa1321b2b",
		"parts_expanded.gd": "d09c04f27766cf34f7ab4079f7e6566f4d69bf13f846cedee160dd446b29a536",
		"pilot_timeline.gd": "0834bf62b87fddc533ae7f7fe1cf1dd8d3f78d9e7210b68ed9353899cc613628"
	}
	for filename in expected:
		_check(FileAccess.get_sha256("res://scripts/" + filename) == expected[filename], "frozen replay dependency stays byte-identical: " + filename)
