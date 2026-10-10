extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array = []
var count = 0

func _initialize() -> void:
	_test_catalog()
	_test_delivery()
	_test_separation()
	_test_torque_and_valve()
	_test_accelerator()
	_test_rings()
	_test_teleport()
	_test_splitter()
	_test_blast_and_shield()
	_test_logic()
	_test_spring_damper()
	_test_weapons_and_enemy()
	_test_launcher_preparation()
	_test_multiple_cargo()
	_test_extra_constraints()
	_test_pad_sensors()
	_test_delivery_bounds_and_variation()
	if failures.is_empty():
		print("PASS: %d deterministic simulation assertions" % count)
		quit(0)
	else:
		for item in failures: printerr("FAIL: ", item)
		printerr("%d/%d assertions failed" % [failures.size(), count])
		quit(1)

func _check(condition: bool, title: String) -> void:
	count += 1
	if not condition: failures.append(title)

func _close(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) < tolerance

func _p(id: int, type: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var p = {"id": id, "type": type, "x": x, "y": y, "rot": 0, "param": Parts.defaults(type), "input_a": -1, "input_b": -1, "target": -1}
	p.merge(extra, true)
	return p

func _sim(design: Array, hazards: Array = []) -> RefCounted:
	var s = Sim.new()
	s.configure(design, [], {"distance": 1000.0, "hazards": hazards, "time_limit": 90.0}, 42)
	return s

func _advance(s, seconds: float) -> void:
	for _i in range(int(ceil(seconds * 120.0))): s.step(1.0 / 120.0)

func _test_catalog() -> void:
	_check(Parts.catalog().size() == 25, "25 catalog parts exactly")
	var models: Array = []
	for item in Parts.catalog().values(): models.append(item.model)
	var unique: Dictionary = {}
	for model in models: unique[model] = true
	_check(unique.size() == 25, "every part has its own model")

func _test_delivery() -> void:
	var design = [_p(1, "cargo", 0), _p(2, "beam", -1), _p(3, "battery", -2), _p(4, "thruster", -3), _p(5, "armor", 1)]
	var s = Sim.new()
	s.configure(design, [_p(10, "spring", 0, 0, {"param": 20.0}), _p(11, "battery", -1), _p(12, "beam", 1)], {"distance": 38.0}, 1)
	_advance(s, 15.0)
	_check(s.status == "success", "starter autonomously delivers without midflight input")
	_check(s.telemetry.energy_used > 0.0 and s.telemetry.delivered, "delivery consumed physical battery energy")
	_check(s.ship_integrity() > 0.99, "safe route preserves cargo")
	var s2 = Sim.new()
	s2.configure(design, [_p(10, "spring", 0, 0, {"param": 20.0}), _p(11, "battery", -1), _p(12, "beam", 1)], {"distance": 38.0}, 1)
	_advance(s2, 15.0)
	_check(_close(s.elapsed, s2.elapsed) and s.cargo_position().is_equal_approx(s2.cargo_position()), "same design and seed reproduce flight")
	var inert = _sim([_p(1, "cargo", 0)])
	_advance(inert, 1.0)
	_check(inert.cargo_position().length() < 0.001 and inert.status == "running", "no scripted progress without forces")

func _test_separation() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "coupler", 1, 0, {"target": 3}), _p(3, "battery", 2)])
	s.launch(Vector2(20.0, 0.0))
	var mass = s.total_mass()
	var momentum = s.total_momentum()
	s.trigger(2); s.step(1.0 / 120.0)
	_check(s.bodies.size() == 2, "coupler creates independent connected components")
	_check(_close(s.total_mass(), mass), "separation conserves mass")
	_check(s.total_momentum().distance_to(momentum) < 0.001, "separation conserves linear momentum")
	s.bodies[0].velocity += Vector2(0.0, 2.0)
	_advance(s, 0.2)
	_check(absf(s.bodies[0].position.y - s.bodies[1].position.y) > 0.1, "separated bodies integrate independently")

func _test_torque_and_valve() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "thruster", 0, 1)])
	_advance(s, 0.2)
	_check(absf(s.bodies[0].angular_velocity) > 0.01, "off-centre thrust generates torque")
	var v = _sim([_p(1, "cargo", 0), _p(2, "battery", 1), _p(3, "valve", 2, 0, {"target": 4, "param": 2.0}), _p(4, "thruster", 3)])
	_advance(v, 1.0)
	_check(_close(v.telemetry.energy_used, 2.0, 0.025), "valve limits joules per second")
	var rotation = _sim([_p(1, "cargo", 0), _p(2, "rotator", 1, 0, {"target": 3, "param": 90.0}), _p(3, "battery", 2)])
	_advance(rotation, 1.0)
	_check(_close(rotation.parts[3].local_angle, PI / 2.0, 0.01), "rotator changes connected target angle")
	var breakable = _sim([_p(1, "cargo", 0), _p(2, "beam", 1), _p(3, "battery", 2), _p(4, "thruster", 3, 0, {"param": 40.0})])
	_advance(breakable, 2.0)
	_check(not breakable.parts[2].alive and breakable.bodies.size() >= 2, "overloaded beam breaks graph")

func _test_accelerator() -> void:
	var s = _sim([_p(1, "cargo", 2), _p(2, "accelerator", 1, 0, {"target": 1, "param": 6.0}), _p(3, "battery", 0)])
	var momentum = s.total_momentum()
	var mass = s.total_mass()
	s.step(1.0 / 120.0)
	_check(s.bodies.size() == 2 and s.parts[2].spent, "accelerator ejects loaded cargo rather than spawning clone")
	_check(s.body_for_part(1).velocity.x > 0.0 and s.body_for_part(2).velocity.x < 0.0, "accelerator has opposite carrier recoil")
	_check(s.total_momentum().distance_to(momentum) < 0.001, "accelerator conserves momentum")
	_check(_close(s.total_mass(), mass), "accelerator conserves mass")
	_check(s.telemetry.energy_used > 0.0, "accelerator pays kinetic energy")

func _test_rings() -> void:
	for kind in ["shrink", "enlarge"]:
		var s = _sim([_p(1, "cargo", 0), _p(2, kind, 1, 0, {"target": 3}), _p(3, "battery", 2)])
		var mass = s.parts[3].mass
		var energy = s.parts[3].energy
		var strength = s.parts[3].strength
		var hp = s.parts[3].hp
		s.step(1.0 / 120.0)
		_check(not _close(s.parts[3].scale, 1.0), kind + " changes collision/visual scale")
		_check(_close(s.parts[3].mass, mass) and _close(s.parts[3].energy, energy) and _close(s.parts[3].strength, strength) and _close(s.parts[3].hp, hp), kind + " preserves mass energy strength and hp")

func _test_teleport() -> void:
	var design = [_p(1, "cargo", 0), _p(2, "teleporter", 1, 0, {"param": 8.0}), _p(3, "battery", 2)]
	var s = _sim(design)
	s.launch(Vector2(6.0, 0.0))
	var velocity = s.bodies[0].velocity
	var before = s.cargo_position()
	s.trigger(2); s.step(1.0 / 120.0)
	_check(s.cargo_position().x - before.x > 7.99, "clear teleport displaces whole component")
	_check(s.bodies[0].velocity.is_equal_approx(velocity), "teleport preserves velocity")
	var blocked = _sim(design)
	var obstacle_at = blocked.part_world_position(3) + Vector2(8.0, 0.0)
	blocked.obstacles.append({"position": obstacle_at, "radius": 0.25, "health": 100.0, "type": "rock", "conductive": true})
	before = blocked.cargo_position()
	blocked.trigger(2); blocked.step(1.0 / 120.0)
	_check(blocked.cargo_position().distance_to(before) < 0.001, "teleport rejects blockage under far end, not only origin")
	_check(_close(blocked.telemetry.energy_used, 0.0), "blocked teleport preserves energy")

func _test_splitter() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "splitter", 1, 0, {"target": 3}), _p(3, "battery", 2)])
	var mass = s.total_mass()
	var energy = s.total_energy()
	s.trigger(2); s.step(1.0 / 120.0)
	_check(s.parts.size() == 4 and s.bodies.size() == 2, "splitter creates separate half-module")
	_check(_close(s.total_mass(), mass) and _close(s.total_energy(), energy - 10.0), "splitter conserves mass and partitions energy after operation cost")
	_check(_close(s.parts[3].strength, 45.0) and _close(s.parts[3].max_hp, 22.5), "splitter divides strength and hp")
	var c = _sim([_p(1, "cargo", 0), _p(2, "splitter", 1, 0, {"target": 1}), _p(3, "battery", 2)])
	c.trigger(2); c.step(1.0 / 120.0)
	_check(c.parts.size() == 3 and _close(c.total_energy(), 300.0), "cargo cannot be duplicated")

func _test_blast_and_shield() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "bomb", 1, 0, {"param": 4.0}), _p(3, "armor", -1)], [{"x": 2.0, "y": 2.0, "radius": 0.5, "health": 100.0}])
	s.trigger(2); s.step(1.0 / 120.0)
	_check(not s.parts[2].alive, "bomb consumes itself")
	_check(s.parts[1].hp < 100.0 and s.obstacles[0].health < 100.0, "blast hurts friendly cargo and enemy")
	var shield = _sim([_p(1, "cargo", 0), _p(2, "shield", 1), _p(3, "battery", 2)])
	shield._damage_part(shield.parts[1], 20.0, "attack")
	_check(_close(shield.parts[1].hp, 100.0) and _close(shield.parts[3].energy, 270.0), "shield converts electricity to attack absorption")
	shield._damage_part(shield.parts[1], 20.0, "collision")
	_check(_close(shield.parts[1].hp, 80.0), "shield cannot absorb collision")

func _test_logic() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "not_gate", 1), _p(3, "and_gate", 2, 0, {"input_a": 2, "input_b": 2}), _p(4, "or_gate", 3, 0, {"input_a": 2}), _p(5, "delay", 4, 0, {"input_a": 2, "param": 0.2}), _p(6, "not_gate", 5, 0, {"input_a": 2}), _p(7, "collision", -1)])
	_advance(s, 0.05)
	_check(s.parts[2].signal and s.parts[3].signal and s.parts[4].signal and not s.parts[6].signal, "AND OR NOT boolean truth tables")
	_check(not s.parts[5].signal, "delay has not fired before wait")
	_check(not s.parts[7].signal, "collision ignores own adjacent sockets")
	_advance(s, 0.25)
	_check(s.parts[5].signal, "delay emits queued rising edge")
	var probe = _sim([_p(1, "cargo", 0), _p(2, "probe", 1, 0, {"param": 6.0})], [{"x": 4.0, "y": 0.0, "radius": 0.5}])
	_advance(probe, 0.1)
	_check(probe.parts[2].signal and probe.parts[2].distance < 6.0, "probe sustained directional nearest-distance signal")
	probe.parts[2].local_angle = PI
	probe.step(1.0 / 120.0)
	_check(not probe.parts[2].signal, "probe does not see behind its arrow")

func _test_spring_damper() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "spring", 1, 0, {"target": 3, "param": 12.0}), _p(3, "battery", 2)])
	_check(_close(s.parts[2].stored_energy, 0.0), "spring begins uncompressed")
	_advance(s, 0.5)
	_check(_close(s.parts[2].stored_energy, 12.0) and _close(s.parts[3].energy, 288.0), "spring compression transfers battery energy")
	s.trigger(2); s.step(1.0 / 120.0)
	_check(s.bodies.size() == 2 and s.total_momentum().length() < 0.001, "spring separates equal/opposite momentum")
	var kinetic = 0.0
	for b in s.bodies: kinetic += 0.5 * b.mass * b.velocity.length_squared()
	_check(_close(kinetic, 12.0, 0.01), "spring converts finite precompressed energy")
	var d = _sim([_p(1, "cargo", 0), _p(2, "damper", 1)])
	d.bodies[0].angular_velocity = 2.0
	_advance(d, 0.5)
	_check(absf(d.bodies[0].angular_velocity) < 1.0 and d.telemetry.heat > 0.0, "damper dissipates rotational kinetic energy")

func _test_weapons_and_enemy() -> void:
	for weapon in ["lance", "arc"]:
		var s = _sim([_p(1, "cargo", 0), _p(2, "battery", 1), _p(3, weapon, 2)], [{"x": 6.0, "y": 0.0, "radius": 0.6}, {"x": 6.0, "y": 1.4, "radius": 0.6}])
		_advance(s, 0.3)
		_check(s.obstacles[0].health < 80.0 and s.telemetry.energy_used > 0.0, weapon + " deals directional paid damage")
		if weapon == "arc": _check(s.obstacles[1].health < 80.0, "arc propagates to nearby conductive target")
		else: _check(_close(s.obstacles[1].health, 80.0), "lance does not splash")
	for kind in ["turret", "tracker"]:
		var s = _sim([_p(1, "cargo", 0), _p(2, "battery", 1), _p(3, "decoy", 1, 1)], [{"type": kind, "x": 8.0, "y": -4.0, "cooldown": 0.01}])
		_advance(s, 0.04)
		_check(s.obstacles[0].last_target_id == (3 if kind == "tracker" else 1), "decoy only affects " + kind + " target selection")

func _test_launcher_preparation() -> void:
	var pad = [_p(10, "spring", 0, 0, {"param": 20.0}), _p(11, "battery", -1), _p(12, "beam", 1)]
	var s = Sim.new()
	s.configure([_p(1, "cargo", 0)], pad, {"distance": 100.0}, 1)
	_check(s.bodies[0].velocity.x > 0.0 and _close(s.telemetry.energy_used, 20.0), "supported pad compresses spring with connected battery")
	_check(_close(s.telemetry.launch_energy, 20.0), "pad launch kinetic energy equals consumed elastic energy")
	var no_power = Sim.new()
	no_power.configure([_p(1, "cargo", 0)], [pad[0], pad[2]], {"distance": 100.0}, 1)
	_check(no_power.bodies[0].velocity.length() < 0.001, "unpowered launcher cannot propel")
	var unsupported = Sim.new()
	unsupported.configure([_p(1, "cargo", 0)], [pad[0], pad[1]], {"distance": 100.0}, 1)
	_check(unsupported.bodies[0].velocity.length() < 0.001, "unsupported launcher cannot propel")
	var heavy = Sim.new()
	heavy.configure([_p(1, "cargo", 0)], pad, {"distance": 100.0, "weight": 2.0}, 1)
	_check(_close(heavy.total_mass(), 6.0) and heavy.bodies[0].velocity.x < s.bodies[0].velocity.x, "order payload weight changes mass and speed")
	var two = Sim.new()
	var double_pad = pad.duplicate(true)
	double_pad.append(_p(13, "spring", 0, 1, {"param": 20.0}))
	two.configure([_p(1, "cargo", 0)], double_pad, {"distance": 100.0}, 1)
	_check(_close(two.telemetry.launch_energy, 40.0) and _close(two.telemetry.energy_used, 40.0), "two springs add finite work, not free quadratic energy")
	var valved = Sim.new()
	var valved_pad = pad.duplicate(true)
	valved_pad.append(_p(14, "valve", 0, 1, {"target": 10, "param": 1.0}))
	valved.configure([_p(1, "cargo", 0)], valved_pad, {"distance": 100.0}, 1)
	_check(_close(valved.telemetry.launch_energy, 2.0, 0.01), "pad power valve caps compression over preparation time")

func _test_multiple_cargo() -> void:
	var s = Sim.new()
	s.configure([_p(1, "cargo", 0), _p(2, "cargo", 4)], [], {"distance": 10.0, "weight": 2.0}, 1)
	_check(s.bodies.size() == 2 and _close(s.total_mass(), 6.0), "payload splits across distinct cargo containers")
	s.body_for_part(1).position.x = 9.99
	s.body_for_part(1).velocity = Vector2(3.0, 0.0)
	s.step(1.0 / 120.0)
	_check(s.telemetry.delivered_count == 1 and s.status == "running", "one delivered cargo cannot complete multi-cargo order")
	_check(s.parts[1].delivered and s.body_for_part(1).is_empty(), "receiving platform safely removes delivered cargo from dynamics")
	s.body_for_part(2).position.x = 9.99
	s.body_for_part(2).velocity = Vector2(3.0, 0.0)
	s.step(1.0 / 120.0)
	_check(s.status == "success" and s.telemetry.delivered_count == 2, "order succeeds after all independent cargo arrive")

func _test_extra_constraints() -> void:
	for kind in ["shrink", "enlarge"]:
		var bad_scale = 2.0 if kind == "shrink" else 0.5
		var s = _sim([_p(1, "cargo", 0), _p(2, kind, 1, 0, {"param": bad_scale, "target": 1})])
		s.step(1.0 / 120.0)
		_check(_close(s.parts[1].scale, 1.0), kind + " cannot invert ring effect with invalid parameter")
	var t = _sim([_p(1, "cargo", 0), _p(2, "teleporter", 1), _p(3, "valve", 2, 0, {"target": 2, "param": 1.0}), _p(4, "battery", 3)])
	var at = t.cargo_position()
	t.trigger(2); t.step(1.0 / 120.0)
	_check(t.cargo_position().distance_to(at) < 0.001 and _close(t.telemetry.energy_used, 0.0), "valve also restricts pulsed teleporter power")
	var pad = [_p(10, "spring", 0, 0, {"param": 20.0}), _p(11, "battery", -1), _p(12, "beam", 1), _p(13, "rotator", 0, 1, {"target": 10, "param": 45.0})]
	var r = Sim.new()
	r.configure([_p(1, "cargo", 0)], pad, {"distance": 100.0}, 1)
	_check(absf(r.bodies[0].velocity.x) < 0.01 and r.bodies[0].velocity.y > 0.0, "powered pad turntable changes physical launch direction")
	var disconnected = _sim([_p(1, "cargo", 0), _p(2, "thruster", 1), _p(3, "battery", 4)])
	_advance(disconnected, 0.2)
	_check(disconnected.body_for_part(1).velocity.length() < 0.001 and _close(disconnected.parts[3].energy, 300.0), "disconnected thruster cannot borrow another component battery")

func _test_pad_sensors() -> void:
	var pad = [_p(10, "spring", 0, 0, {"param": 20.0}), _p(11, "battery", -1), _p(12, "beam", 1), _p(13, "probe", 2, 0, {"param": 2.0}), _p(14, "probe", 2, 1, {"param": 2.0}), _p(15, "collision", 3)]
	var s = Sim.new()
	s.configure([_p(1, "cargo", 0)], pad, {"distance": 100.0}, 1)
	var found: Dictionary = {}
	for p in s.launcher_parts: found[p.id] = p
	_check(found[13].signal and not found[14].signal, "launcher probe uses actual directional craft geometry")
	_check(found[15].signal, "launcher collision switch senses actual hull contact")
	pad[5].y = 2
	s.configure([_p(1, "cargo", 0)], pad, {"distance": 100.0}, 1)
	for p in s.launcher_parts: found[p.id] = p
	_check(not found[15].signal, "launcher collision switch ignores noncontact placements")

func _test_delivery_bounds_and_variation() -> void:
	var s = Sim.new()
	s.configure([_p(1, "cargo", 0)], [], {"distance": 104.0, "delivery_radius": 8.0}, 1)
	s.bodies[0].position = Vector2(129.0, 0.0)
	s.step(1.0 / 120.0)
	_check(s.status != "success" and not s.telemetry.delivered, "receiving zone has finite radius rather than infinite x strip")
	var route = {"distance": 100.0, "variation": 1.0, "hazards": [{"x": 20.0, "y": 2.0}]}
	var a = Sim.new(); var b = Sim.new(); var c = Sim.new()
	a.configure([_p(1, "cargo", 0)], [], route, 2)
	b.configure([_p(1, "cargo", 0)], [], route, 2)
	c.configure([_p(1, "cargo", 0)], [], route, 3)
	_check(a.obstacles[0].position.is_equal_approx(b.obstacles[0].position), "same seed exactly reproduces enabled hazard variation")
	_check(not a.obstacles[0].position.is_equal_approx(c.obstacles[0].position), "different seed produces bounded route variation")
	_check(absf(a.obstacles[0].position.x - 20.0) <= 0.4 and absf(a.obstacles[0].position.y - 2.0) <= 0.25, "hazard variation stays within documented limits")
