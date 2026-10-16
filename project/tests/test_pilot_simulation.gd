extends SceneTree
const Sim = preload("res://scripts/pilot_simulation.gd")
const Legacy = preload("res://scripts/simulation.gd")
const Profile = preload("res://scripts/pilot_profile.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array = []
var count: int = 0

func _initialize() -> void:
	_test_profile_delivery()
	_test_keyboard_delivery()
	_test_commands_and_energy()
	_test_physical_build_contrast()
	_test_existing_devices()
	_test_cockpit_graph()
	_test_continuous_collision()
	_test_safe_spawn_and_teleport()
	_test_json_roundtrip()
	_test_budget_and_long_run()
	_test_legacy_isolation()
	if failures.is_empty():
		print("PASS: %d pilot-v1 physics assertions" % count); quit(0)
	else:
		for failure in failures: printerr("FAIL: ", failure)
		printerr("%d/%d pilot assertions failed" % [failures.size(), count]); quit(1)

func _check(ok: bool, title: String) -> void:
	count += 1
	if not ok: failures.append(title)

func _p(id: int, type: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var result = {"id": id, "type": type, "x": x, "y": y, "rot": 0, "param": Parts.defaults(type), "input_a": -1, "input_b": -1, "target": -1}
	result.merge(extra, true)
	return result

func _route(hazards: Array = []) -> Dictionary:
	return {"distance": 1000.0, "boundary_y": 1000.0, "time_limit": 120.0, "hazards": hazards, "pilot_drag": 0.0}

func _sim(design: Array = [], route: Dictionary = {}) -> RefCounted:
	var s = Sim.new()
	s.configure(Profile.starter_design() if design.is_empty() else design, [], _route() if route.is_empty() else route, 42)
	return s

func _advance(s, seconds: float, axis_q: int = 0, boost: bool = false, active: bool = false) -> void:
	for i in range(int(seconds * 60.0)):
		s.set_pilot_input(axis_q, boost, active); s.step(1.0 / 60.0)

func _route_command(s) -> int:
	var target = 0.0
	var pos: Vector2 = s.cargo_position()
	for gate in s.route.pilot_gates:
		if pos.x < gate.x + 4.0:
			target = gate.y; break
	var vy: float = s.telemetry.vertical_speed
	var wanted_velocity = clampf((target - pos.y) * 1.0 - vy * 0.4, -1.8, 1.8)
	return int(round(wanted_velocity / 1.8 * 1000.0))

func _test_profile_delivery() -> void:
	var s = Sim.new(); var replay = Sim.new()
	var r = Profile.route({"weight": 1.0, "reward": 100.0})
	s.configure(Profile.starter_design(), Profile.starter_launcher(), r, 27)
	replay.configure(Profile.starter_design(), Profile.starter_launcher(), r, 27)
	var commands: Array = []
	for frame in range(3900):
		var command = _route_command(s)
		commands.append(command)
		s.set_pilot_input(command, false, false); s.step(1.0 / 60.0)
		if s.status != "running": break
	for command in commands:
		replay.set_pilot_input(command, false, false); replay.step(1.0 / 60.0)
	print("PILOT ROUTE: status=%s time=%.3f position=%s energy=%.3f cargo=%.3f bodies=%d" % [s.status, s.elapsed, s.cargo_position(), s.total_energy(), s.ship_integrity(), s.bodies.size()])
	if s.status != "success": print("PILOT EVENTS: ", s.events)
	_check(s.status == "success", "symmetric starter completes city→station with actual steering")
	_check(s.elapsed >= 25.0 and s.elapsed <= 40.0, "first route lasts 25–40 seconds")
	_check(s.ship_integrity() >= 0.99, "properly steered starter preserves cargo")
	_check(s.total_energy() > 5.0, "route retains steering reserve on finite 300J battery")
	_check(s.telemetry.energy_used <= 320.0001, "route cannot spend more than craft300J plus pad20J")
	_check(s.cargo_position() == replay.cargo_position() and s.telemetry == replay.telemetry and s.events == replay.events, "integer command replay gives exact terminal parity")
	_check(s.telemetry.lookahead_m >= 22.0, "camera receives at least useful 22m preview distance")
	_check(r.reward == 100.0 and r.weight == 1.0, "profile preserves commercial order fields")


func _test_keyboard_delivery() -> void:
	for extra_armor in [0, 2, -1]:
		var design = Profile.starter_design()
		for i in range(extra_armor): design.append(_p(50 + i, "armor", -2 if i == 0 else 2, 0))
		var s = Sim.new()
		s.configure(design, Profile.starter_launcher(), Profile.route({"weight": 1.55 if extra_armor == -1 else 1.0}), 42)
		for frame in range(3900):
			var pos: Vector2 = s.cargo_position()
			var target = 0.0
			for gate in s.route.pilot_gates:
				if pos.x < gate.x + 4.0: target = gate.y; break
			var forecast: float = pos.y + s.telemetry.vertical_speed * 0.85
			var delta: float = target - forecast
			var axis: int = int(signf(delta)) * 1000 if absf(delta) > 0.32 else 0
			s.set_pilot_input(axis); s.step(1.0 / 60.0)
			if s.status != "running": break
		print("KEYBOARD armor=%d status=%s time=%.3f energy=%.3f integrity=%.3f" % [extra_armor, s.status, s.elapsed, s.total_energy(), s.ship_integrity()])
		_check(s.status == "success" and s.ship_integrity() > 0.99, "binary keyboard commands deliver armor+%d build" % extra_armor)
		_check(s.elapsed < 42.0, "42s deadline covers armor+%d delivery" % extra_armor)

func _test_commands_and_energy() -> void:
	var idle = _sim([_p(1, "cargo", 0)])
	_advance(idle, 2.0, -1000, true, true)
	_check(idle.cargo_position().length() < 0.00001, "bare cargo never gains magical cruise or steering")
	var dead = _sim()
	for p in dead.parts.values(): p.energy = 0.0
	_advance(dead, 2.0, -1000, true)
	_check(dead.cargo_position().length() < 1.0, "dead battery provides neither cruise nor steering")
	_check(dead.bodies[0].velocity.length() < 0.00001, "energy-dead craft remains motionless from rest")
	var live = _sim(); _advance(live, 1.0, -1000)
	_check(live.telemetry.vertical_speed < -0.5 and live.telemetry.forward_speed > 0.3, "up command uses real vectored force")
	_check(live.telemetry.assist_energy_used > 0.0 and live.total_energy() < 300.0, "vector servo and exhaust consume battery")
	for p in live.parts.values(): p.energy = 0.0
	_advance(live, 1.0 / 60.0, -1000)
	_check(live.parts[4].pilot_force == Vector2.ZERO and live.parts[4].pilot_throttle == 0.0, "exhaust telemetry clears immediately when battery empties")
	var normal = _sim(); var boost = _sim()
	_advance(normal, 5.0); _advance(boost, 5.0, 0, true)
	_check(boost.telemetry.forward_speed > normal.telemetry.forward_speed + 0.3, "boost increases attainable thrust speed")
	_check(boost.telemetry.energy_used > normal.telemetry.energy_used, "boost spends additional finite energy")
	var fixed = _sim(); var doubled = _sim()
	for i in range(120):
		fixed.set_pilot_input(-333, i > 50, i % 20 < 10); fixed.step(1.0 / 60.0)
		doubled.set_pilot_input(-333, i > 50, i % 20 < 10); doubled.step(1.0 / 120.0); doubled.step(1.0 / 120.0)
	_check(fixed.cargo_position() == doubled.cargo_position() and fixed.telemetry == doubled.telemetry, "60Hz held command equals its two fixed120Hz substeps")
	fixed.set_pilot_input(-5000)
	_check(fixed.pilot_axis_q == -1000 and fixed.pilot_tick == 240, "quantization clamps and integer physical ticks are explicit")

func _test_physical_build_contrast() -> void:
	var light = _sim()
	var heavy_design = Profile.starter_design()
	for i in range(4): heavy_design.append(_p(30 + i, "armor", -2, i - 2))
	var heavy = _sim(heavy_design)
	_advance(light, 1.0, -1000); _advance(heavy, 1.0, -1000)
	_check(absf(light.telemetry.vertical_speed) > absf(heavy.telemetry.vertical_speed) + 0.1, "heavy connected armor build responds more slowly")
	var reverse_design = Profile.starter_design()
	for raw in reverse_design:
		if raw.type == "thruster": raw.rot = 2
	var reverse = _sim(reverse_design); _advance(reverse, 2.0)
	_check(reverse.telemetry.forward_speed < 0.01, "reverse-mounted nozzles cannot secretly push forward")
	var offset = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "thruster", -1, 1)])
	_advance(offset, 0.4, -1000)
	_check(absf(offset.bodies[0].angular_velocity) > 0.03, "bad offset layout produces uncompensated physical torque")
	var limited = Profile.starter_design()
	limited.append(_p(40, "valve", 2, -1, {"target": 4, "param": 0.0}))
	limited.append(_p(41, "valve", 2, 1, {"target": 6, "param": 0.0}))
	var closed = _sim(limited); _advance(closed, 2.0, -1000, true)
	_check(closed.bodies[0].velocity.length() < 0.0001, "closed actual circuit valves disable both nozzle force and servo")

func _test_existing_devices() -> void:
	var damper = _sim([_p(1, "cargo", 0), _p(2, "damper", 1)])
	damper.bodies[0].angular_velocity = 2.0
	_advance(damper, 1.0)
	_check(absf(damper.bodies[0].angular_velocity - 2.0 * exp(-2.5)) < 0.001 and damper.telemetry.heat > 0.0, "damper dissipates actual angular motion into heat without free propulsion")
	var rotator = _sim([_p(1, "cargo", 0), _p(2, "rotator", 1, 0, {"target": 3, "param": 90.0}), _p(3, "battery", 2)])
	_advance(rotator, 1.0)
	_check(absf(rotator.parts[3].local_angle - PI * 0.5) < 0.001 and rotator.telemetry.energy_used > 0.0, "rotator retains distinct paid target-orientation function")
	var shield = _sim([_p(1, "cargo", 0), _p(2, "shield", 1, 0, {"input_a": -2}), _p(3, "battery", -1)])
	shield.set_pilot_input(0, false, true)
	shield._damage_part(shield.parts[1], 20.0, "attack")
	_check(shield.parts[1].hp == 100.0 and absf(shield.total_energy() - 270.0) < 0.001, "Space-wired shield actually pays30J to absorb20 attack damage")
	shield._damage_part(shield.parts[1], 20.0, "collision")
	_check(shield.parts[1].hp == 80.0 and absf(shield.total_energy() - 270.0) < 0.001, "shield does not absorb physical impact")
	var armor = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "armor", 1)], _route([{"position": Vector2(10.0, 0.0), "type": "turret", "cooldown": 0.0, "range": 20.0}]))
	armor.step(1.0 / 120.0)
	_check(armor.parts[3].hp < 150.0 and armor.parts[1].hp == 100.0, "armor protects only by intercepting the real attack ray")
	var gates = _sim([_p(1, "cargo", 0), _p(2, "and_gate", 1, 0, {"input_a": -2, "input_b": -2}), _p(3, "not_gate", -1, 0, {"input_a": -2})])
	_advance(gates, 1.0 / 60.0, 0, false, true)
	_check(gates.parts[2].signal and not gates.parts[3].signal, "cockpit source works through both AND inputs and NOT inversion")
	_advance(gates, 1.0 / 60.0)
	_check(not gates.parts[2].signal and gates.parts[3].signal, "releasing Space restores normal graph truth values")

func _test_cockpit_graph() -> void:
	var design = [_p(1, "cargo", 0), _p(2, "coupler", 1, 0, {"target": 3, "input_a": -2}),
		_p(3, "battery", 2), _p(4, "or_gate", 3, 0, {"input_a": -2}),
		_p(5, "delay", 0, 1, {"input_a": -2, "param": 0.1}), _p(6, "bomb", 0, -1)]
	var s = _sim(design)
	_advance(s, 0.05)
	_check(s.bodies.size() == 1 and not s.parts[2].active, "cockpit-wired coupler waits while Space is released")
	_advance(s, 0.05, 0, false, true)
	_check(s.bodies.size() == 2, "cockpit rising edge cuts actual targeted connection")
	_check(not s._read_wire(s.parts[4], -2), "cockpit broadcast stops immediately across a cut")
	_check(s.parts[6].alive and not s.parts[6].spent, "Space does not trigger unwired active devices")
	_advance(s, 0.15, 0, false, true)
	_check(s.parts[5].signal, "cockpit signal passes through real delay logic")
	_check(not s.parts[4].signal, "detached OR gate sees false cockpit source")

func _test_continuous_collision() -> void:
	var fast = _sim([_p(1, "cargo", 0)], _route([{"position": Vector2(3.0, 0.0), "radius": 0.1, "health": 1000000.0}]))
	fast.bodies[0].velocity = Vector2(1000.0, 0.0)
	fast.step(1.0 / 120.0)
	_check(int(fast.telemetry.swept_contacts) > 0, "swept circle catches thin gate skipped by both endpoint samples")
	_check(fast.cargo_position().x < 3.0 or not fast.parts[1].alive, "high speed cannot tunnel through a solid obstacle")
	var near = _sim([_p(1, "cargo", 0)], _route([{"position": Vector2(3.0, 0.65), "radius": 0.1}]))
	near.bodies[0].velocity = Vector2(1000.0, 0.0); near.step(1.0 / 120.0)
	_check(near.parts[1].hp == 100.0 and int(near.telemetry.swept_contacts) == 0, "CCD preserves close but clear near misses")
	var opposing = _sim([_p(1, "cargo", 0), _p(2, "armor", 8)])
	opposing.body_for_part(1).velocity = Vector2(1000.0, 0.0)
	opposing.body_for_part(2).velocity = Vector2(-1000.0, 0.0)
	opposing.step(1.0 / 120.0)
	_check(int(opposing.telemetry.swept_contacts) > 0, "independent modules moving through each other receive swept collision")
	var rotating = _sim([_p(1, "cargo", 0), _p(2, "beam", 1), _p(3, "armor", 2)])
	var rotating_body = rotating.bodies[0]
	var arm = rotating.parts[3].local_pos
	var midpoint: Vector2 = rotating_body.position + arm.rotated(PI * 0.5)
	rotating.obstacles.append({"position": midpoint, "radius": 0.1, "health": 1000000.0, "type": "rock", "velocity": Vector2.ZERO})
	rotating_body.angular_velocity = PI * 120.0
	rotating.step(1.0 / 120.0)
	_check(int(rotating.telemetry.swept_contacts) > 0, "angular arc sweep catches a mid-rotation obstacle")

func _test_safe_spawn_and_teleport() -> void:
	var blocked = _sim([_p(1, "cargo", 0)], _route([{"position": Vector2.ZERO, "radius": 1.0}]))
	_check(blocked.status == "failed" and blocked.elapsed == 0.0, "overlapping spawn is rejected before flight")
	var design = [_p(1, "cargo", 0), _p(2, "teleporter", 1, 0, {"param": 8.0, "input_a": -2}), _p(3, "battery", 2)]
	var clear = _sim(design, _route([{"position": Vector2(4.0, 0.0), "radius": 0.3}]))
	var before: Vector2 = clear.cargo_position()
	_advance(clear, 1.0 / 60.0, 0, false, true)
	_check(clear.cargo_position().x > before.x + 7.99 and clear.parts[1].hp == 100.0, "teleport intentionally skips transit obstacles without false CCD hit")
	_check(absf(clear.telemetry.energy_used - 25.0) < 0.001, "teleport spends its normal finite25J")
	var exit = _sim(design)
	exit.bodies[0].velocity = Vector2(10.0, 0.0)
	var exit_at: Vector2 = exit.part_world_position(3) + Vector2(9.8, 0.0)
	exit.obstacles.append({"position": exit_at, "radius": 0.2, "health": 100.0, "type": "rock", "velocity": Vector2.ZERO})
	_check(not exit.destination_clear(exit.bodies[0], Vector2(8.0, 0.0)), "teleporter rejects immediate high-speed exit collision")

func _test_json_roundtrip() -> void:
	var original_route = Profile.route({"weight": 1.55, "reward": 220})
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(original_route))
	var source = Sim.new(); var restored = Sim.new()
	source.configure(Profile.starter_design(), Profile.starter_launcher(), original_route, 42)
	restored.configure(JSON.parse_string(JSON.stringify(Profile.starter_design())), JSON.parse_string(JSON.stringify(Profile.starter_launcher())), decoded, 42)
	_check(restored.status == "running" and restored.obstacles[0].position == source.obstacles[0].position, "disk JSON retains hazard positions and safe spawn")
	for frame in range(480):
		var axis = -1000 if frame < 60 else (1000 if frame > 380 else 0)
		source.set_pilot_input(axis, false, frame % 80 < 40); source.step(1.0 / 60.0)
		restored.set_pilot_input(axis, false, frame % 80 < 40); restored.step(1.0 / 60.0)
	_check(source.cargo_position() == restored.cargo_position() and source.telemetry == restored.telemetry and source.events == restored.events, "serialized route/design/commands restore exact physical parity")
	_check(Profile.route(original_route) == original_route, "route adaptation is idempotent")

func _test_budget_and_long_run() -> void:
	var s = _sim()
	var max_budget_error = 0.0
	var finite = true
	for frame in range(2400):
		var command = int(round(sin(float(frame) * 0.011) * 1000.0))
		s.set_pilot_input(command, frame % 240 < 90, false); s.step(1.0 / 60.0)
		var kinetic = 0.0
		for b in s.bodies:
			kinetic += 0.5 * b.mass * b.velocity.length_squared() + 0.5 * b.inertia * b.angular_velocity * b.angular_velocity
			finite = finite and b.position.is_finite() and b.velocity.is_finite() and is_finite(b.angular_velocity)
		max_budget_error = maxf(max_budget_error, kinetic + s.total_energy() - 300.0)
	_check(max_budget_error < 0.005, "whole craft kinetic plus remaining energy never exceeds initial300J")
	_check(finite and s.total_energy() >= 0.0, "40s changing-command run remains finite with nonnegative battery")
	var valved = Profile.starter_design()
	valved.append(_p(40, "valve", 2, -1, {"target": 4, "param": 0.05}))
	valved.append(_p(41, "valve", 2, 1, {"target": 6, "param": 0.05}))
	var limited = _sim(valved)
	_advance(limited, 2.0, -1000, true)
	_check(limited.telemetry.energy_used <= 0.20001 and limited.telemetry.energy_used > 0.18, "partial gimbal and propulsion share one exact valve flow budget")
	var receiver = _sim([_p(1, "cargo", 0)], {"distance": 3.0, "delivery_radius": 0.5, "max_delivery_speed": 2000.0, "boundary_y": 1000.0})
	receiver.bodies[0].velocity = Vector2(1000.0, 0.0); receiver.step(1.0 / 120.0)
	_check(receiver.status == "success", "swept receiver catches valid fast crossing outside endpoint circle")
	var too_fast = _sim([_p(1, "cargo", 0)], {"distance": 3.0, "delivery_radius": 0.5, "max_delivery_speed": 10.0, "boundary_y": 1000.0})
	too_fast.bodies[0].velocity = Vector2(1000.0, 0.0); too_fast.step(1.0 / 120.0)
	_check(too_fast.status == "failed", "swept receiver still enforces actual entrance speed limit")

func _test_legacy_isolation() -> void:
	var legacy = Legacy.new()
	legacy.configure(Profile.starter_design(), [], _route(), 42)
	_check(not legacy.telemetry.has("control_version") and not legacy.has_method("set_pilot_input"), "old simulation remains isolated from pilot protocol")
