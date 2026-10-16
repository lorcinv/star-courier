extends SceneTree
const Sim = preload("res://scripts/pilot_ascent_simulation.gd")
const Profile = preload("res://scripts/pilot_ascent_profile.gd")
const V1Sim = preload("res://scripts/pilot_simulation.gd")
const V1Profile = preload("res://scripts/pilot_profile.gd")
const Parts = preload("res://scripts/parts.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
var failures: Array = []
var assertions = 0

func _initialize() -> void:
	_test_profile_and_delivery()
	_test_neutral_requires_steering()
	_test_physical_controls()
	_test_energy_and_causality()
	_test_safety_and_devices()
	_test_all_device_functions()
	_test_json_replay()
	_test_frozen_v1()
	if failures.is_empty():
		print("PASS: %d pilot-v2 ascent assertions" % assertions); quit(0)
	else:
		for failure in failures: printerr("FAIL: ", failure)
		printerr("%d/%d pilot-v2 ascent assertions failed" % [failures.size(), assertions]); quit(1)

func _check(value: bool, title: String) -> void:
	assertions += 1
	if not value: failures.append(title)

func _part(id: int, kind: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var p = {"id": id, "type": kind, "x": x, "y": y, "rot": 0, "param": Parts.defaults(kind), "input_a": -1, "input_b": -1, "target": -1}
	p.merge(extra, true); return p

func _open_route() -> Dictionary:
	var r = Profile.route()
	r.hazards = []; r.pilot_gates = []; r.distance = 3000.0; r.boundary_y = 3000.0
	r.pilot_altitude = 0.0; r.destination_y = 0.0; r.time_limit = 120.0; r.pilot_drag = 0.0
	return r

func _sim(design: Array = [], r: Dictionary = {}, pad: bool = false):
	var s = Sim.new()
	s.configure(Profile.starter_design() if design.is_empty() else design, Profile.starter_launcher() if pad else [], _open_route() if r.is_empty() else r, 42)
	return s

func _advance(s, seconds: float, axis: int = 0, boost: bool = false, active: bool = false) -> void:
	for i in range(roundi(seconds * 60.0)):
		s.set_pilot_input(axis, boost, active); s.step(1.0 / 60.0)

## TEST-ONLY keyboard observer. Never call this from the live flight loop.
## It generates only released/up/down states that native OS keys can reproduce.
static func binary_guidance(s) -> int:
	var pos: Vector2 = s.cargo_position()
	var offset = 0.0
	for gate in s.route.get("pilot_gates", []):
		if pos.x < float(gate.x) + 6.5:
			offset = float(gate.lane_offset); break
	var normal = Profile.path_tangent(pos.x, s.route).orthogonal() * -1.0
	var body: Dictionary = s._cargo_body()
	var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var lateral_speed = velocity.dot(normal)
	var acceleration = float(s.route.get("pilot_net_force_limit", 30.0)) / maxf(1.0, float(body.get("mass", 10.2)))
	var stopping_preview = lateral_speed * (0.45 + absf(lateral_speed) / (2.0 * acceleration * 0.9))
	var error = Profile.path_y(pos.x, s.route) + offset - pos.y - stopping_preview
	return int(signf(error)) * 1000 if absf(error) > 0.9 else 0

func _run_keyboard(weight: float, boost: bool = false) -> Dictionary:
	var s = _sim([], Profile.route({"weight": weight}), true)
	var timeline = Timeline.new()
	var peak_speed = 0.0; var climb_heading = 0.0; var arrival_heading = 0.0; var arrival_vy = 0.0
	var held_axis = 0
	var checkpoints = {}; var minimum_energy = s.total_energy(); var max_net_force = 0.0
	for tick in range(4200):
		if tick % 12 == 0: held_axis = binary_guidance(s)
		var axis = held_axis
		timeline.record(tick, {"axis_q": axis, "boost": boost, "active": false})
		s.set_pilot_input(axis, boost); s.step(1.0 / 60.0)
		if tick in [59, 179, 299]: checkpoints[str((tick + 1) / 60)] = {"speed": s.telemetry.speed, "vx": s.telemetry.forward_speed, "x": s.cargo_position().x}
		peak_speed = maxf(peak_speed, s.telemetry.speed)
		minimum_energy = minf(minimum_energy, s.total_energy())
		for b in s.bodies: max_net_force = maxf(max_net_force, b.force.length())
		if s.cargo_position().x > 140.0 and s.cargo_position().x < 340.0: climb_heading = minf(climb_heading, s.telemetry.ship_heading)
		if s.cargo_position().x > 480.0 and s.status == "running": arrival_heading = s.telemetry.ship_heading; arrival_vy = s.telemetry.vertical_speed
		if s.status != "running": break
	print("ASCENT weight=%.2f boost=%s status=%s time=%.3f altitude=%.3f peak=%.3f energy_used=%.3f remaining=%.3f integrity=%.3f headings=%.3f/%.3f arrival_vy=%.3f net=%.3f input_events=%d checkpoints=%s" % [weight, boost, s.status, s.elapsed, -s.cargo_position().y, peak_speed, s.telemetry.energy_used, s.total_energy(), s.ship_integrity(), climb_heading, arrival_heading, arrival_vy, max_net_force, timeline.commands.size(), JSON.stringify(checkpoints)])
	if s.status != "success": print("ASCENT events: ", s.events)
	return {"sim": s, "timeline": timeline.snapshot(), "peak_speed": peak_speed, "climb_heading": climb_heading, "arrival_heading": arrival_heading, "arrival_vy": arrival_vy, "minimum_energy": minimum_energy, "max_net_force": max_net_force, "checkpoints": checkpoints}

func _test_profile_and_delivery() -> void:
	var p = Profile.route({"weight": 1.55, "reward": 220})
	_check(Profile.route(p) == p, "route adaptation is idempotent")
	_check(p.weight == 1.55 and p.reward == 220, "ascent profile preserves customer and commercial fields")
	_check(Profile.starter_design().size() == 8, "starter remains eight fixed modules")
	_check(Profile.path_y(0.0) == 0.0 and Profile.path_y(520.0) == -150.0, "route rises a genuine150m in finite520m lane")
	_check(Profile.path_heading(0.0) == 0.0 and Profile.path_heading(450.0) == 0.0 and Profile.path_heading(220.0) < -0.5, "smooth route contains city departure, diagonal climb and level approach")
	for weight in [1.0, 1.55, 4.34]:
		var run = _run_keyboard(weight)
		var s = run.sim
		_check(s.status == "success", "binary W/S delivers weight %.2f" % weight)
		_check(s.ship_integrity() > 0.99 and s.parts[2].alive and s.parts[7].alive, "cargo and physical32N beams survive weight %.2f" % weight)
		_check(s.elapsed < 48.0, "standard deadline covers weight %.2f" % weight)
		_check(-s.cargo_position().y >= 143.0 and -s.cargo_position().y <= 157.0, "actual delivered altitude matches150m weight %.2f" % weight)
		_check(run.climb_heading < -0.35 and absf(run.arrival_heading) < 0.15 and absf(run.arrival_vy) < 1.0, "actual attitude climbs then levels weight %.2f" % weight)
		_check(run.peak_speed > V1Profile.CRUISE_SPEED * 3.0, "actual speed exceeds3x v1 weight %.2f" % weight)
		_check(run.minimum_energy > 100.0 and s.telemetry.energy_used < s.telemetry.battery_capacity + 20.0001, "finite battery completes weight %.2f" % weight)
		_check(run.max_net_force <= 33.0, "actual nozzle force stays safe for fixed beams weight %.2f" % weight)
		_check(s.route.control_version == "pilot-v2" and s.telemetry.control_version == "pilot-v2", "subclass restores version after parent configuration")
		if weight == 1.0:
			_check(run.checkpoints["1"].speed > 4.0 and run.checkpoints["3"].speed > 8.0 and run.checkpoints["5"].speed > 12.0, "launch is measurably responsive after1/3/5 seconds")
			DirAccess.make_dir_recursive_absolute("/tmp/courier-ascent")
			var f = FileAccess.open("/tmp/courier-ascent/keyboard-standard.json", FileAccess.WRITE)
			f.store_string(JSON.stringify({"control_version": "pilot-v2", "seed": 42, "weight": 1.0, "commands": run.timeline, "terminal_time": s.elapsed}, "  "))
	var boosted = _run_keyboard(1.55, true)
	_check(boosted.sim.status == "success" and boosted.peak_speed > 21.0, "boost uses actual22m/s trajectory and heavy delivery")
	var hud = _sim([], Profile.route(), true)
	_advance(hud, 5.0)
	_check(hud.telemetry.lookahead_seconds >= 3.0 and hud.telemetry.next_gate_time > 0.0 and hud.telemetry.next_gate_altitude > 0.0, "HUD receives3s prediction and gate time/altitude")

func _test_neutral_requires_steering() -> void:
	var neutral = _sim([], Profile.route({"weight": 1.0}), true)
	_advance(neutral, 70.0)
	print("ASCENT NEUTRAL status=%s time=%.3f position=%s integrity=%.3f incidents=%s" % [neutral.status, neutral.elapsed, neutral.cargo_position(), neutral.ship_integrity(), str(neutral.incidents)])
	_check(neutral.status != "success" and not neutral.incidents.is_empty(), "visible physical gates require an actual W/S correction; neutral does not deliver")

func _test_physical_controls() -> void:
	var up = _sim(); var down = _sim()
	_advance(up, 1.0, -1000); _advance(down, 1.0, 1000)
	_check(up.telemetry.vertical_speed < -1.0 and down.telemetry.vertical_speed > 1.0, "W/S causes immediate opposite physical steering")
	_check(up.telemetry.ship_heading < -0.02 and down.telemetry.ship_heading > 0.02, "W/S changes actual ship attitude through paid torque")
	var normal = _sim(); var boost = _sim()
	_advance(normal, 12.0); _advance(boost, 12.0, 0, true)
	_check(normal.telemetry.speed > 17.0 and boost.telemetry.speed > 21.0, "actual cruise and boost attain their targets")
	_check(boost.telemetry.energy_used > normal.telemetry.energy_used + 500.0, "higher kinetic speed costs real extra energy")
	var light = _sim(); var heavy = _sim([], _open_route().merged({"weight": 4.34}, true))
	_advance(light, 2.0); _advance(heavy, 2.0)
	_check(light.telemetry.speed > heavy.telemetry.speed + 1.0, "more cargo mass genuinely slows acceleration")
	var weak_design = Profile.starter_design()
	for p in weak_design:
		if p.type == "thruster": p.param = 4.0
	var weak = _sim(weak_design); _advance(weak, 2.0)
	_check(weak.telemetry.speed < light.telemetry.speed * 0.5, "real lower engine parameters reduce acceleration")
	var reverse_design = Profile.starter_design()
	for p in reverse_design:
		if p.type == "thruster": p.rot = 2
	var reverse = _sim(reverse_design); _advance(reverse, 5.0)
	_check(reverse.telemetry.forward_speed < 0.5, "reversed engines cannot supply magical forward force")
	var fixed = _sim(); var split = _sim()
	for tick in range(240):
		fixed.set_pilot_input(-750, tick > 100, tick % 20 < 10); fixed.step(1.0 / 60.0)
		split.set_pilot_input(-750, tick > 100, tick % 20 < 10); split.step(1.0 / 120.0); split.step(1.0 / 120.0)
	_check(fixed.cargo_position() == split.cargo_position() and fixed.telemetry == split.telemetry, "60Hz command equals two identical120Hz physics steps")

func _test_energy_and_causality() -> void:
	var bare = _sim([_part(1, "cargo", 0)])
	_advance(bare, 4.0, -1000, true)
	_check(bare.cargo_position() == Vector2.ZERO and bare.bodies[0].velocity == Vector2.ZERO, "missing engines grant no cruise, climb or torque")
	var dead = _sim()
	for p in dead.parts.values(): p.energy = 0.0
	_advance(dead, 3.0, -1000, true)
	_check(dead.bodies[0].velocity == Vector2.ZERO and dead.bodies[0].angular_velocity == 0.0, "empty battery grants no force or attitude control")
	dead.bodies[0].velocity = Vector2(12.0, -4.0); dead.bodies[0].angular_velocity = 0.4
	_advance(dead, 1.0, 1000, true)
	_check(dead.bodies[0].velocity == Vector2(12.0, -4.0) and dead.bodies[0].angular_velocity == 0.4, "empty craft coasts without invisible lane capture or damping")
	var s = _sim(); var initial = s.total_energy(); var max_error = 0.0; var finite = true
	for tick in range(2400):
		s.set_pilot_input(-1000 if tick % 240 < 120 else 1000, tick % 400 < 200); s.step(1.0 / 60.0)
		var kinetic = 0.0
		for b in s.bodies:
			kinetic += 0.5 * b.mass * b.velocity.length_squared() + 0.5 * b.inertia * b.angular_velocity * b.angular_velocity
			finite = finite and b.position.is_finite() and b.velocity.is_finite() and is_finite(b.angular_velocity)
		max_error = maxf(max_error, kinetic + s.total_energy() - initial)
	_check(initial == 6000.0 and max_error < 0.02, "kinetic plus stored energy never exceeds finite6000J initial budget")
	_check(finite and s.total_energy() >= 0.0 and s.telemetry.assist_energy_used > 0.0, "changing high-speed commands remain finite and pay servo work")
	var valved = Profile.starter_design()
	valved.append(_part(40, "valve", 2, -1, {"target": 4, "param": 0.05}))
	valved.append(_part(41, "valve", 2, 1, {"target": 6, "param": 0.05}))
	var limited = _sim(valved); _advance(limited, 2.0, -1000, true)
	_check(limited.telemetry.energy_used <= 0.20001 and limited.telemetry.energy_used > 0.18, "real valve budgets include both nozzle work and gimbal servo")
	for kind in ["empty", "missing", "reversed"]:
		var design = Profile.starter_design()
		if kind == "missing": design = design.filter(func(p): return p.type != "thruster")
		if kind == "reversed":
			for p in design:
				if p.type == "thruster": p.rot = 2
		var failed_ship = _sim(design, Profile.route(), true)
		if kind == "empty":
			for p in failed_ship.parts.values(): p.energy = 0.0
		_advance(failed_ship, 70.0)
		_check(failed_ship.status == "failed", kind + " engine/energy case cannot complete by route assistance")

func _test_safety_and_devices() -> void:
	var r = _open_route(); r.hazards = [{"x": 3.0, "y": 0.0, "radius": 0.1, "health": 1000000.0}]
	var fast = _sim([_part(1, "cargo", 0)], r)
	fast.bodies[0].velocity = Vector2(1000.0, 0.0); fast.step(1.0 / 120.0)
	_check(fast.telemetry.swept_contacts > 0 and (fast.cargo_position().x < 3.0 or not fast.parts[1].alive), "inherited swept CCD catches high-speed impact")
	r.hazards = [{"x": 0.0, "y": 0.0, "radius": 1.0}]
	var blocked = _sim([_part(1, "cargo", 0)], r)
	_check(blocked.status == "failed" and blocked.elapsed == 0.0, "inherited spawn overlap protection rejects unsafe launch")
	var design = [_part(1, "cargo", 0), _part(2, "teleporter", 1, 0, {"param": 8.0, "input_a": -2}), _part(3, "battery", 2)]
	var jump = _sim(design)
	jump.bodies[0].velocity = Vector2(22.0, 0.0)
	jump.obstacles.append({"position": jump.part_world_position(3) + Vector2(12.0, 0.0), "radius": 0.2, "health": 100.0, "type": "rock", "velocity": Vector2.ZERO})
	_check(not jump.destination_clear(jump.bodies[0], Vector2(8.0, 0.0)), "teleporter rejects boosted immediate exit collision")
	var clear = _sim(design); var before: Vector2 = clear.cargo_position()
	_advance(clear, 1.0 / 60.0, 0, false, true)
	_check(clear.cargo_position().x > before.x + 7.99 and absf(clear.telemetry.energy_used - 25.0) < 0.001, "cockpit-wired teleporter retains real25J function")
	var shield = _sim([_part(1, "cargo", 0), _part(2, "shield", 1, 0, {"input_a": -2}), _part(3, "battery", -1)])
	shield.set_pilot_input(0, false, true); shield._damage_part(shield.parts[1], 20.0, "attack")
	_check(shield.parts[1].hp == 100.0 and shield.telemetry.energy_used == 30.0, "cockpit signal still drives inherited paid shield")
	var armored_route = _open_route(); armored_route.hazards = [{"x": 10.0, "y": 0.0, "type": "turret", "cooldown": 0.0, "range": 20.0}]
	var armored = _sim([_part(1, "cargo", 0), _part(2, "battery", -1), _part(3, "armor", 1)], armored_route)
	armored.step(1.0 / 120.0)
	_check(armored.parts[3].hp < 150.0 and armored.parts[1].hp == 100.0, "armor protects cargo only by physically intercepting attack ray")
	_check(Parts.catalog().size() == 25, "all25 module definitions remain available")

func _test_all_device_functions() -> void:
	# Exercise the inherited functions through the NEW simulator, not just the
	# catalog. Propulsion, battery, valve, beam, armor, shield and teleport are
	# covered above; these fixtures cover the remaining distinct device paths.
	var cut = _sim([_part(1, "cargo", 0), _part(2, "coupler", 1, 0, {"target": 3, "input_a": -2}), _part(3, "battery", 2), _part(4, "or_gate", 3, 0, {"input_a": -2})])
	_advance(cut, 1.0 / 60.0, 0, false, true)
	_check(cut.bodies.size() == 2 and not cut._read_wire(cut.parts[4], -2), "coupler separates physical graph and cockpit signal cannot cross cut")
	var turn = _sim([_part(1, "cargo", 0), _part(2, "rotator", 1, 0, {"target": 3, "param": 90.0}), _part(3, "battery", 2)])
	_advance(turn, 1.0)
	_check(absf(turn.parts[3].local_angle - PI / 2.0) < 0.001 and turn.telemetry.energy_used > 0.0, "rotator retains paid target rotation")
	var spring = _sim([_part(1, "cargo", 0), _part(2, "spring", 1, 0, {"target": 3, "param": 12.0}), _part(3, "battery", 2)])
	_advance(spring, 0.5); spring.trigger(2); spring.step(1.0 / 120.0)
	_check(spring.bodies.size() == 2 and spring.total_momentum().length() < 0.001 and absf(spring.telemetry.energy_used - 12.0) < 0.001, "spring stores finite energy and separates with conserved momentum")
	var damp = _sim([_part(1, "cargo", 0), _part(2, "damper", 1)])
	damp.bodies[0].angular_velocity = 2.0; _advance(damp, 0.5)
	_check(damp.bodies[0].angular_velocity < 1.0 and damp.telemetry.heat > 0.0, "damper dissipates rotation into heat")
	var accelerator = _sim([_part(1, "cargo", 2), _part(2, "accelerator", 1, 0, {"target": 1, "param": 6.0}), _part(3, "battery", 0)])
	accelerator.step(1.0 / 120.0)
	_check(accelerator.bodies.size() == 2 and accelerator.body_for_part(1).velocity.x > 0.0 and accelerator.body_for_part(2).velocity.x < 0.0 and accelerator.total_momentum().length() < 0.001 and accelerator.telemetry.energy_used > 0.0, "accelerator ejects real cargo with paid energy and opposite recoil")
	for kind in ["shrink", "enlarge"]:
		var ring = _sim([_part(1, "cargo", 0), _part(2, kind, 1, 0, {"target": 3}), _part(3, "battery", 2)])
		var mass = ring.total_mass(); var energy = ring.total_energy(); ring.step(1.0 / 120.0)
		_check(ring.parts[3].scale != 1.0 and ring.total_mass() == mass and ring.total_energy() == energy, kind + " changes physical size without manufacturing mass or energy")
	var split = _sim([_part(1, "cargo", 0), _part(2, "splitter", 1, 0, {"target": 3}), _part(3, "battery", 2)])
	var split_mass = split.total_mass(); var split_energy = split.total_energy(); split.trigger(2); split.step(1.0 / 120.0)
	_check(split.parts.size() == 4 and absf(split.total_mass() - split_mass) < 0.001 and absf(split.total_energy() - split_energy + 10.0) < 0.001, "splitter partitions mass and6000J capacity after actual10J cost")
	var bomb = _sim([_part(1, "cargo", 0), _part(2, "bomb", 1, 0, {"param": 4.0}), _part(3, "armor", -1)])
	bomb.trigger(2); bomb.step(1.0 / 120.0)
	_check(not bomb.parts[2].alive and bomb.parts[1].hp < 100.0, "bomb consumes itself and damages friendly physical cargo")
	var logic = _sim([_part(1, "cargo", 0), _part(2, "not_gate", 1), _part(3, "and_gate", 2, 0, {"input_a": 2, "input_b": 2}), _part(4, "or_gate", 3, 0, {"input_a": 2}), _part(5, "delay", 4, 0, {"input_a": 2, "param": 0.2}), _part(6, "collision", -1)])
	_advance(logic, 0.05)
	_check(logic.parts[2].signal and logic.parts[3].signal and logic.parts[4].signal and not logic.parts[5].signal and not logic.parts[6].signal, "NOT/AND/OR truth values, delay wait and collision self-filter retain distinct behavior")
	_advance(logic, 0.25); _check(logic.parts[5].signal, "delay outputs queued rising edge after its real delay")
	var contact_route = _open_route(); contact_route.hazards = [{"x": 4.0, "y": 0.0, "radius": 0.5}]
	var contact = _sim([_part(1, "cargo", 0), _part(2, "collision", 1)], contact_route)
	contact.bodies[0].velocity = Vector2(4.0, 0.0)
	var switched = false
	for tick in range(120):
		contact.step(1.0 / 120.0); switched = switched or contact.parts[2].signal
	_check(switched, "collision switch outputs real external contact signal")
	var probe_route = _open_route(); probe_route.hazards = [{"x": 4.0, "y": 0.0, "radius": 0.5}]
	var probe = _sim([_part(1, "cargo", 0), _part(2, "probe", 1, 0, {"param": 6.0})], probe_route)
	_advance(probe, 0.1)
	_check(probe.parts[2].signal and probe.parts[2].distance < 6.0, "probe reports actual nearest directional geometry")
	for weapon in ["lance", "arc"]:
		var r = _open_route(); r.hazards = [{"x": 6.0, "y": 0.0, "radius": 0.6}, {"x": 6.0, "y": 1.4, "radius": 0.6}]
		var s = _sim([_part(1, "cargo", 0), _part(2, "battery", 1), _part(3, weapon, 2)], r); _advance(s, 0.3)
		_check(s.obstacles[0].health < 80.0 and s.telemetry.energy_used > 0.0 and ((s.obstacles[1].health < 80.0) == (weapon == "arc")), weapon + " retains paid directional damage and distinct conductive chaining")
	for enemy in ["turret", "tracker"]:
		var r = _open_route(); r.hazards = [{"type": enemy, "x": 8.0, "y": -4.0, "cooldown": 0.01}]
		var s = _sim([_part(1, "cargo", 0), _part(2, "battery", 1), _part(3, "decoy", 1, 1)], r); _advance(s, 0.04)
		_check(s.obstacles[0].last_target_id == (3 if enemy == "tracker" else 1), "decoy selectively redirects " + enemy)
	var overloaded_route = _open_route(); overloaded_route.pilot_net_force_limit = 80.0
	var overloaded = _sim([], overloaded_route); _advance(overloaded, 1.0, 0, true)
	_check(not overloaded.parts[2].alive or not overloaded.parts[7].alive, "physical32N beams still break if actual force governor is raised")

func _test_json_replay() -> void:
	var r = Profile.route({"weight": 1.55})
	var source = _sim([], r, true); var timeline = Timeline.new(); var ticks = 0; var held_axis = 0
	for tick in range(4200):
		if tick % 12 == 0: held_axis = binary_guidance(source)
		var command = {"axis_q": held_axis, "boost": false, "active": tick % 100 < 50}
		timeline.record(tick, command); source.set_pilot_input(command.axis_q, command.boost, command.active); source.step(1.0 / 60.0)
		ticks = tick + 1
		if source.status != "running": break
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify({"route": r, "design": Profile.starter_design(), "launcher": Profile.starter_launcher(), "commands": timeline.snapshot(), "ticks": ticks}))
	var copy = Sim.new(); var replay = Timeline.new()
	copy.configure(snapshot.design, snapshot.launcher, snapshot.route, 42)
	_check(replay.restore(snapshot.commands, snapshot.ticks), "sparse binary command timeline survives JSON checkpoint")
	for tick in range(snapshot.ticks):
		var command = replay.state_at(tick); copy.set_pilot_input(command.axis_q, command.boost, command.active); copy.step(1.0 / 60.0)
	_check(source.status == "success" and source.cargo_position() == copy.cargo_position() and source.telemetry == copy.telemetry and source.events == copy.events, "JSON route, build and60Hz input replay gives exact terminal equality")

func _test_frozen_v1() -> void:
	var hashes = {"res://scripts/pilot_profile.gd": "41031fc568aa5aa2c37c023b5b162ff9f24dd3db97e2fd6dec14dadb207132dd", "res://scripts/pilot_simulation.gd": "81b7d5bdb4514663d3d89c0ae7cf7a510344d53cecfcf05f205ae97af727acd6", "res://scripts/simulation.gd": "582e188f09949cb969a4f0a73dbd97d58f2df38ec17f76568eb229ecfecf369e"}
	for path in hashes: _check(FileAccess.get_sha256(path) == hashes[path], "frozen replay source bytes preserved: " + path.get_file())
	var v1 = V1Sim.new(); v1.configure(V1Profile.starter_design(), [], V1Profile.route(), 42)
	_check(v1.route.control_version == "pilot-v1" and v1.total_energy() == 300.0 and v1.route.distance == 128.0, "explicit v1 simulator retains old route and300J balancing")
