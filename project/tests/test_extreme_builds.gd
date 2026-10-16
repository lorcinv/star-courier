extends SceneTree
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Profile = preload("res://scripts/pilot_extreme_profile.gd")
const Expanded = preload("res://scripts/parts_expanded.gd")
const Parts = preload("res://scripts/parts.gd")
const Probe = preload("res://tools/extreme_build_probe.gd")
const V2Sim = preload("res://scripts/pilot_ascent_simulation.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
var assertions = 0
var failures: Array = []

func _initialize() -> void:
	_test_registry()
	_test_comparisons()
	_test_load_paths()
	_test_controls_energy()
	_test_drill()
	_test_advanced_contacts()
	_test_multiple_contacts()
	_test_contact_budget_recovery()
	_test_contact_pool_islands()
	_test_impact_shield()
	_test_exit_and_replay()
	_test_all_device_functions()
	_test_frozen_sources()
	if failures.is_empty(): print("PASS: %d pilot-v3 extreme-build assertions" % assertions); quit(0)
	else:
		for failure in failures: printerr("FAIL: ", failure)
		printerr("%d/%d extreme-build assertions failed" % [failures.size(), assertions]); quit(1)

func _check(value: bool, title: String) -> void:
	assertions += 1
	if not value: failures.append(title)

func _part(id: int, kind: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	return Profile.part(id, kind, x, y, extra)

func _open_route() -> Dictionary:
	return Probe.open_route()

func _sim(design: Array = [], r: Dictionary = {}):
	var s = Sim.new(); s.configure(Profile.starter_design() if design.is_empty() else design, [], _open_route() if r.is_empty() else r, 42)
	return s

func _advance(s, seconds: float, axis: int = 0, boost: bool = false, active: bool = false) -> void:
	for i in range(roundi(seconds * 120.0)):
		s.set_pilot_input(axis, boost, active); s.step(1.0 / 120.0)

func _test_registry() -> void:
	_check(Parts.catalog().size() == 25 and Expanded.catalog().size() == 26, "expanded registry adds one drill without replacing25 modules")
	for kind in Parts.catalog():
		_check(Parts.catalog()[kind] == Expanded.catalog()[kind] and Parts.parameter_schema(kind) == Expanded.parameter_schema(kind) and Parts.controls(kind) == Expanded.controls(kind), "legacy registry semantics unchanged: " + kind)
	var s = _sim([_part(1, "cargo", 0), _part(2, "drill", 1, 0, {"input_a": -2})])
	_check(s.parts[2].type == "drill" and s.parts[2].input_a == -2 and s.parts[2].mass == 1.8, "drill instantiates as real separate controlled module")
	_check(Expanded.DRILL_HEAD_OFFSET + Expanded.DRILL_HEAD_RADIUS <= 0.5, "visible72px drill cutter fits1m cell")
	_check(s.route.control_version == "pilot-v3" and s.telemetry.control_version == "pilot-v3", "v3 stamps correct route and telemetry")

func _test_comparisons() -> void:
	var standard = Probe.run_build(Profile.starter_design(), true, 3.0)
	var eight = Probe.run_build(Profile.reinforced_design(), true, 3.0)
	print("EXTREME_STANDARD ", JSON.stringify(standard)); print("EXTREME_EIGHT ", JSON.stringify(eight))
	_check(eight.peak_thrust > 210.0 and eight.speed > standard.speed * 1.8 and eight.speed > 30.0, "eight real thrusters accelerate substantially beyond standard and old22m/s governor")
	_check(eight.energy_used > standard.energy_used * 6.0 and eight.mass > standard.mass, "extra acceleration pays extra joules and module mass")
	_check(eight.structure_damage == 0.0 and eight.body_count == 1 and eight.integrity == 1.0, "reinforced paths survive without changing32N beams")
	_check(eight.max_energy_error < 0.02 and standard.max_energy_error < 0.02, "overdrive kinetic plus stored energy never manufactures energy")
	var exhausted = Probe.run_build(Profile.reinforced_design(), true, 8.0)
	_check(exhausted.energy_remaining < 0.001 and exhausted.speed < 35.0, "overdrive exhausts actual cells and then coasts")
	var beginner = Probe.run_build(Profile.starter_design(), false)
	var heavy = Probe.run_build(Profile.reinforced_design(), false)
	_check(beginner.peak_thrust <= 31.0 and heavy.peak_thrust <= 31.0 and heavy.speed < beginner.speed, "ordinary assistance stays beginner safe and mass remains a cost")
	var up = Probe.run_build(Profile.reinforced_design(), true, 1.0, -1000)
	_check(up.vertical_speed < -3.0, "overdrive upward input produces real paid upward acceleration")

func _test_load_paths() -> void:
	var demand = {1: Vector2(60, 0), 2: Vector2.ZERO, 3: Vector2(-60, 0)}
	var chain = Sim.solve_socket_forces(demand, [{"a": 1, "b": 2}, {"a": 2, "b": 3}])
	_check(chain.size() == 2 and absf(chain[0].force.x - 60.0) < 0.0001 and absf(chain[1].force.x - 60.0) < 0.0001, "analytic series bridge transmits60N through both sockets")
	var parallel = Sim.solve_socket_forces({1: Vector2(60, 0), 2: Vector2.ZERO, 3: Vector2.ZERO, 4: Vector2(-60, 0)}, [{"a": 1, "b": 2}, {"a": 2, "b": 4}, {"a": 1, "b": 3}, {"a": 3, "b": 4}])
	var exact = true
	for edge in parallel: exact = exact and absf(edge.force.length() - 30.0) < 0.0001
	_check(exact, "analytic equal parallel paths each transmit30N, below unchanged32N rating")
	var reverse = Sim.solve_socket_forces(demand, [{"a": 3, "b": 2}, {"a": 2, "b": 1}])
	_check(absf(reverse[0].force.x + 60.0) < 0.0001, "edge orientation changes force sign rather than magnitude")
	var r = _open_route(); r.weight = 4.0
	var weak = _sim([_part(1, "cargo", 0), _part(2, "beam", -1), _part(3, "battery", -2), _part(4, "thruster", -2, -1, {"param": 40.0}), _part(5, "thruster", -2, 1, {"param": 40.0})], r)
	_advance(weak, 0.5, 0, true)
	_check(weak.telemetry.structure_damage > 40.0 and not weak.parts[2].alive and weak.bodies.size() > 1, "single overloaded32N bridge actually fractures and splits powered islands")
	var sever = _sim([_part(1, "cargo", 0), _part(2, "thruster", 1, 0, {"param": 40.0}), _part(3, "coupler", -1, 0, {"target": 1, "input_a": -2}), _part(4, "battery", -2), _part(5, "beam", -3)])
	_advance(sever, 1.0 / 120.0, 0, true, true)
	var consistent = sever.bodies.size() == 2
	for body in sever.bodies:
		var force = Vector2.ZERO
		for p in body.parts: force += sever._source_forces.get(p.id, Vector2.ZERO)
		consistent = consistent and force.distance_to(body.force) < 0.0001
	_check(consistent, "thrust-before-coupler split preserves source sums equal to force actually integrated in each island")
	var rotating = _sim(); rotating.bodies[0].angular_velocity = 15.0; _advance(rotating, 0.1)
	_check(rotating.telemetry.structure_damage > 0.0, "centrifugal load still damages structure without net thrust")
	var stationary = _sim(); _advance(stationary, 0.01)
	for p in stationary.parts.values():
		if p.type == "beam": _check(p.strength == 32.0, "v3 never raises32N beam rating")

func _test_controls_energy() -> void:
	var none = _sim([_part(1, "cargo", 0)]); _advance(none, 1.0, -1000, true)
	_check(none.bodies[0].velocity == Vector2.ZERO, "no engine grants no overdrive")
	var empty = _sim()
	for p in empty.parts.values(): p.energy = 0.0
	empty.bodies[0].velocity = Vector2(3, -2); empty.bodies[0].angular_velocity = 0.1
	_advance(empty, 0.5, 1000, true)
	_check(empty.bodies[0].velocity == Vector2(3, -2) and empty.bodies[0].angular_velocity == 0.1, "empty cells produce no free thrust or attitude correction")
	var valved = Profile.starter_design()
	valved.append(_part(20, "valve", 2, -1, {"target": 4, "param": 0.05})); valved.append(_part(21, "valve", 2, 1, {"target": 6, "param": 0.05}))
	var limited = _sim(valved); _advance(limited, 1.0, -1000, true)
	_check(limited.telemetry.energy_used <= 0.10001 and limited.telemetry.energy_used > 0.09, "overdrive honors circuit-local valve budget including servos")
	var disconnected = _sim([_part(1, "cargo", 0), _part(2, "thruster", 1, 0, {"param": 40.0}), _part(3, "battery", 5)])
	_advance(disconnected, 1.0, 0, true)
	_check(disconnected.body_for_part(1).velocity == Vector2.ZERO and disconnected.telemetry.energy_used == 0.0, "disconnected battery cannot energize overdrive")
	var disabled = _sim([_part(1, "cargo", 0), _part(2, "thruster", 1, 0, {"input_a": -2}), _part(3, "battery", -1)])
	_advance(disabled, 0.3, 0, true, false)
	_check(disabled.telemetry.thrust_actual == 0.0, "disabled cockpit-wired engine does not boost")
	var asymmetric = _sim([_part(1, "cargo", 0), _part(2, "battery", -1), _part(3, "thruster", 0, 1, {"param": 40.0})])
	_advance(asymmetric, 0.3, 0, true)
	_check(absf(asymmetric.bodies[0].angular_velocity) > 0.05 and asymmetric.telemetry.energy_used > 0.0, "asymmetric engine produces actual torque and paid attitude motion")

func _drill_fixture(active: bool = true, angle: int = 0):
	var s = _sim([_part(1, "cargo", 0), _part(2, "battery", -1), _part(3, "drill", 1, 0, {"input_a": -2, "rot": angle})])
	s.obstacles.append({"position": s.part_world_position(3) + Vector2(1.255, 0), "radius": 0.8, "health": 80.0, "mass": 20.0, "type": "rock", "velocity": Vector2.ZERO})
	s.set_pilot_input(0, false, active)
	return s

func _test_drill() -> void:
	var on = _drill_fixture(); _advance(on, 1.0, 0, false, true)
	var off = _drill_fixture(false); _advance(off, 1.0)
	_check(on.obstacles[0].health <= 0.0001 and on.telemetry.drill_damage > 79.9 and absf(on.telemetry.energy_used - 60.0) < 0.001, "powered contact drill cuts80HP for real60J motor cost")
	_check(off.obstacles[0].health == 80.0 and off.telemetry.energy_used == 0.0, "disabled drill does not damage or draw power")
	var reverse = _drill_fixture(true, 2); _advance(reverse, 0.3, 0, false, true)
	_check(reverse.obstacles[0].health == 80.0, "backward drill cannot damage obstacle ahead of hull")
	var side = _drill_fixture(); side.obstacles[0].position = side.part_world_position(3) + Vector2(0, 1.255); _advance(side, 0.3, 0, false, true)
	_check(side.obstacles[0].health == 80.0, "drill is a forward contact head rather than surrounding aura")
	var dry = _drill_fixture(); dry.parts[2].energy = 0.0; _advance(dry, 0.3, 0, false, true)
	_check(dry.obstacles[0].health == 80.0, "empty drill circuit cannot cut")
	var split = _drill_fixture(); split._cut(1, 3); _advance(split, 0.3, 0, false, true)
	_check(split.obstacles[0].health == 80.0 and split.telemetry.energy_used == 0.0, "separated drill loses cockpit signal and other-island battery")
	var tower = _drill_fixture(); tower.obstacles[0].pilot_gate = true; tower.obstacles[0].health = 1000000.0; _advance(tower, 1.0, 0, false, true)
	_check(tower.obstacles[0].health == 1000000.0, "drill cannot erase a millionHP gate tower")
	var fast = _drill_fixture(); fast.obstacles[0].position += Vector2(3.0, 0); fast.bodies[0].velocity = Vector2(1000, 0); _advance(fast, 1.0 / 120.0, 0, false, true)
	_check(fast.telemetry.drill_contacts > 0 and fast.telemetry.drill_damage <= 100.0 / 120.0 + 0.0001 and fast.telemetry.swept_contacts > 0, "high-speed swept drill pays bounded contact damage and still collides with surviving rock")
	var distant = _drill_fixture(); distant.obstacles[0].position += Vector2(4, 0)
	distant.obstacles.append({"position": distant.part_world_position(3) + Vector2(2, 0), "radius": 0.5, "health": 1000000.0, "mass": 1000000.0, "type": "rock", "velocity": Vector2.ZERO, "pilot_gate": true})
	distant.bodies[0].velocity = Vector2(1000, 0); _advance(distant, 1.0 / 120.0, 0, false, true)
	_check(distant.obstacles[0].health == 80.0, "earlier solid hull impact prevents cutting unreachable obstacle behind it")
	var limited = _drill_fixture(); limited.parts[2].energy = 0.25; _advance(limited, 1.0 / 120.0, 0, false, true)
	_check(absf(limited.telemetry.drill_damage - 100.0 / 240.0) < 0.0001 and limited.total_energy() == 0.0, "partial circuit energy proportionally bounds cutter damage")
	var bounded = _drill_fixture(); bounded.obstacles[0].health = 1000000.0; _advance(bounded, 5.0, 0, false, true)
	_check(bounded.effects.size() <= 2 and bounded.telemetry.drill_damage < 501.0, "sustained drill effects and per-second damage remain bounded")

func _test_advanced_contacts() -> void:
	var s = _sim([_part(1, "cargo", 0), _part(2, "drill", 5, 0, {"rot": 1}), _part(3, "battery", 6)])
	var a = s.body_for_part(1); var b = s.body_for_part(2)
	a.position = -s.parts[1].local_pos; a.velocity = Vector2(1000, 0)
	b.position = Vector2(3, -5) - s.parts[2].local_pos; b.velocity = Vector2(0, 600)
	s.obstacles.append({"position": Vector2(3, 0), "radius": 0.1, "health": 0.5, "type": "rock", "velocity": Vector2.ZERO})
	_advance(s, 1.0 / 120.0)
	_check(s.telemetry.swept_contacts > 0 and not s.parts[1].alive and s.telemetry.drill_damage == 0.0, "late drill on separate body cannot erase earlier cargo collision with same rock")
	var cut = _drill_fixture(); cut.obstacles[0].position += Vector2(3, 0); cut.obstacles[0].health = 0.5
	cut.bodies[0].velocity = Vector2(1000, 0); _advance(cut, 1.0 / 120.0, 0, false, true)
	_check(cut.obstacles[0].health == 0.0 and cut.telemetry.swept_contacts == 0 and cut.parts[3].alive, "early contact cutter can actually clear a sufficiently weak rock before hull arrives")
	var rotating = _drill_fixture(); var p = rotating.parts[3]; var body = rotating.body_for_part(3)
	rotating._motion_bodies[body.id] = {"position": body.position, "angle": 0.0}
	body.angle = 0.1
	var centre: Vector2 = body.position
	var radius: float = (p.local_pos + Vector2(0.3, 0)).length()
	var h = {"position": centre + Vector2.RIGHT.rotated(0.05) * (radius + 0.18 + 0.1 + 0.0003), "radius": 0.1, "health": 80.0, "type": "rock", "velocity": Vector2.ZERO}
	_check(rotating._sweep_cutter(p, h, -1).is_empty(), "conservative rotating-arc inflation cannot turn a true near miss into cutting damage")
	h.position = centre + Vector2.RIGHT.rotated(0.05) * (radius + 0.18 + 0.1 - 0.005)
	_check(not rotating._sweep_cutter(p, h, -1).is_empty(), "rotating cutter catches true intermediate contact even when both endpoints miss")
	var split = _sim([_part(1, "cargo", 0), _part(2, "battery", -1), _part(3, "drill", 1), _part(4, "splitter", 1, 1, {"target": 3, "input_a": -2})])
	split.trigger(4); _advance(split, 1.0 / 120.0)
	var unpaid_clone = false
	for q in split.parts.values():
		if q.type == "drill" and q.id != 3: unpaid_clone = q.drill_power_ratio == 0.0
	_check(unpaid_clone and absf(split.parts[3].drill_power_ratio - 0.5) < 0.0001 and absf(split.telemetry.drill_energy_used - 0.5) < 0.0001, "same-tick splitter cannot duplicate prepaid drill power; original output is halved")
	var many: Array = []
	for i in range(193): many.append(_part(i + 1, "cargo" if i == 0 else "beam", i))
	var bounded = _sim(many)
	_check(bounded.status == "failed" and bounded.parts.size() == 192, "oversized blueprint is safely rejected before unbounded solver work")

func _test_multiple_contacts() -> void:
	# Large HP is fixture-only: isolate collision geometry rather than destruction.
	var s = _sim([_part(1, "cargo", 0), _part(2, "armor", 4), _part(3, "armor", 8)])
	for p in s.parts.values(): p.hp = 1.0e12; p.max_hp = 1.0e12
	var a = s.body_for_part(1); var b = s.body_for_part(2); var c = s.body_for_part(3)
	a.position = Vector2(0, 0); b.position = Vector2(3, 0); c.position = Vector2(6, 0)
	a.velocity = Vector2(1000, 0); c.velocity = Vector2(-1000, 0)
	var momentum: Vector2 = s.total_momentum(); _advance(s, 1.0 / 120.0)
	_check(s.telemetry.swept_contacts >= 2 and a.position.x < b.position.x and b.position.x < c.position.x, "three-body opposing1000m/s contact resolves all bodies without tunneling through stopped participant")
	_check(s.total_momentum().distance_to(momentum) < 0.01 and int(s.telemetry.get("ccd_budget_holds", 0)) == 0, "multi-contact impulses conserve momentum within tolerance without exhausting bounded event solver")
	var pinball = _sim([_part(1, "cargo", 0)])
	pinball.parts[1].hp = 1.0e12; pinball.parts[1].max_hp = 1.0e12
	for x in [0.7, -0.9]: pinball.obstacles.append({"position": Vector2(x, 0), "velocity": Vector2.ZERO, "radius": 0.1, "mass": 1000000.0, "health": 1.0e12, "type": "rock"})
	pinball.bodies[0].velocity = Vector2(1000, 0); _advance(pinball, 1.0 / 120.0)
	_check(pinball.telemetry.swept_contacts >= 2 and pinball.cargo_position().x < 0.18 and pinball.cargo_position().x > -0.38 and pinball.bodies[0].velocity.x > 0.0, "same body resweeps after first impact and bounces off second hazard in remaining substep")
	var gone = _sim([_part(1, "cargo", 0), _part(2, "armor", 4)])
	for p in gone.parts.values(): p.hp = 1.0e12; p.max_hp = 1.0e12
	gone.body_for_part(1).position = Vector2(0, 0); gone.body_for_part(2).position = Vector2(-2, 0)
	for body in gone.bodies: body.velocity = Vector2(1000, 0)
	gone.obstacles.append({"position": Vector2(3, 0), "velocity": Vector2.ZERO, "radius": 0.1, "mass": 20.0, "health": 1.0, "type": "rock"})
	_advance(gone, 1.0 / 120.0)
	_check(gone.obstacles[0].health <= 0.0 and gone.telemetry.swept_contacts >= 1, "first impact destroys weak obstacle during chronological solve")
	# An entirely separate lane isolates the stale-hazard case from valid body-body recoil.
	var cross = _sim([_part(1, "cargo", 0), _part(2, "armor", 4)])
	for p in cross.parts.values(): p.hp = 1.0e12; p.max_hp = 1.0e12
	cross.body_for_part(1).position = Vector2(0, 0); cross.body_for_part(2).position = Vector2(3, -5)
	cross.body_for_part(1).velocity = Vector2(1000, 0); cross.body_for_part(2).velocity = Vector2(0, 700)
	cross.obstacles.append({"position": Vector2(3, 0), "velocity": Vector2.ZERO, "radius": 0.1, "mass": 20.0, "health": 1.0, "type": "rock"})
	_advance(cross, 1.0 / 120.0)
	_check(cross.parts[2].hp == 1.0e12 and cross.body_for_part(2).velocity == Vector2(0, 700), "later separate body receives no phantom collision from obstacle destroyed earlier")
	var fractured = _sim([_part(1, "cargo", 0), _part(2, "armor", 1)])
	fractured.parts[1].hp = 1.0e12; fractured.parts[1].max_hp = 1.0e12; fractured.parts[2].hp = 0.01
	var body = fractured.bodies[0]; var velocity = Vector2(300, 0); body.velocity = velocity
	var cargo_at: Vector2 = fractured.part_world_position(1)
	var arm: Vector2 = fractured.parts[2].local_pos; var cargo_arm: Vector2 = fractured.parts[1].local_pos
	var contact_time: float = fractured._segment_circle_t(Vector2(-0.6, -0.3), Vector2(1.9, -0.3), 0.53)
	var normal = (Vector2(-0.6, -0.3) + velocity / 120.0 * contact_time).normalized()
	var impulse: float = -1.08 * velocity.dot(normal) / (1.0 / body.mass + pow(arm.cross(normal), 2.0) / body.inertia)
	var linear: Vector2 = velocity + normal * impulse / body.mass
	var omega: float = arm.cross(normal * impulse) / body.inertia
	var point_velocity: Vector2 = linear + Vector2(-cargo_arm.y, cargo_arm.x) * omega
	var event_position = cargo_at + velocity / 120.0 * contact_time
	var expected = event_position + point_velocity / 120.0 * (1.0 - contact_time)
	fractured.obstacles.append({"position": fractured.part_world_position(2) + Vector2(0.6, 0.3), "velocity": Vector2.ZERO, "radius": 0.1, "health": 1.0e12, "type": "rock"})
	_advance(fractured, 1.0 / 120.0)
	_check(not fractured.parts[2].alive and fractured.cargo_position().distance_to(expected) < 0.0001, "impact-destroyed module is rebuilt immediately and remaining cargo follows its own point momentum")
	var twice = _sim([_part(1, "cargo", 0), _part(2, "armor", 1)])
	twice.parts[1].hp = 1.0e12; twice.parts[1].max_hp = 1.0e12; twice.parts[2].hp = 0.01; twice.bodies[0].velocity = velocity
	twice.obstacles.append({"position": twice.part_world_position(2) + Vector2(0.6, 0.3), "velocity": Vector2.ZERO, "radius": 0.1, "health": 1.0e12, "type": "rock"})
	twice.obstacles.append({"position": event_position.lerp(expected, 0.5), "velocity": Vector2.ZERO, "radius": 0.03, "health": 1.0e12, "type": "rock"})
	_advance(twice, 1.0 / 120.0)
	_check(not twice.parts[2].alive and twice.telemetry.swept_contacts >= 2 and twice.cargo_position().distance_to(expected) > 0.01, "newly split cargo island is swept against another hazard in same remaining substep")

func _test_contact_budget_recovery() -> void:
	var pile = Probe.contact_budget_probe(24, 8)
	print("EXTREME_CONTACT_RECOVERY ", JSON.stringify(pile))
	_check(pile.status == "running" and pile.finite and pile.ordered and pile.contacts > 0, "dense24-body contact probe actually runs and preserves finite body order")
	_check(pile.budget_holds == 0 and pile.contacts_per_tick[0] > 0 and pile.contacts_per_tick[-1] == 0, "former zero-time pile resolves then recovers on following steps without budget holds")
	_check(pile.momentum_error < 0.01 and pile.final_kinetic <= pile.initial_kinetic + 0.01, "simultaneous contact pooling conserves momentum and cannot create kinetic energy")
	_check(pile.event_rounds_per_tick.max() < pile.event_round_limit_per_tick, "active constraint contacts remain within a smaller bounded number of chronological event rounds")

func _test_contact_pool_islands() -> void:
	var design: Array = []
	for i in range(26): design.append(_part(i + 1, "cargo" if i == 0 else "armor", (i % 8) * 3, (i / 8) * 3))
	var s = _sim(design)
	for i in range(26):
		var p: Dictionary = s.parts[i + 1]; p.hp = 1.0e12; p.max_hp = 1.0e12
		var b = s.body_for_part(i + 1)
		if i < 24: b.position = Vector2(i * 0.861, 0); b.velocity = Vector2(1000 if i % 2 == 0 else -1000, 0)
		else: b.position = Vector2(100, 100) + Vector2(0.516, 0.688) * (i - 24)
	var remote_a: Vector2 = s.part_world_position(25); var remote_b: Vector2 = s.part_world_position(26)
	_advance(s, 1.0 / 120.0)
	var first_contacts = s.telemetry.swept_contacts
	_advance(s, 1.0 / 120.0)
	_check(s.telemetry.ccd_contact_pools > 0 and s.telemetry.ccd_budget_holds == 0 and first_contacts > 0 and s.telemetry.swept_contacts == first_contacts, "unrelated oblique touching island cannot disable dense-chain recovery")
	_check(s.part_world_position(25) == remote_a and s.part_world_position(26) == remote_b and s.body_for_part(25).velocity == Vector2.ZERO and s.body_for_part(26).velocity == Vector2.ZERO and s.parts[25].hp == 1.0e12 and s.parts[26].hp == 1.0e12, "pooling preserves unrelated resting island position, velocity and HP")
	var sensors = _sim([_part(1, "cargo", 0), _part(2, "collision", 3), _part(3, "collision", 6)])
	for p in sensors.parts.values(): p.hp = 1.0e12; p.max_hp = 1.0e12
	for i in range(3): sensors.body_for_part(i + 1).position = Vector2(i * 0.86001, 0)
	sensors.body_for_part(1).velocity = Vector2(30, 0); _advance(sensors, 1.0 / 120.0)
	_check(sensors.body_for_part(3).velocity.x > 20.0 and sensors.parts[2].next_contact and sensors.parts[3].next_contact, "resting rear contact edge marks sensor when it transmits a real pooled impulse")
	_advance(sensors, 1.0 / 120.0)
	_check(sensors.parts[2].signal and sensors.parts[3].signal, "both impulse-chain collision switches emit their real next-tick signal")
	var false_seed = _sim([_part(1, "cargo", 0), _part(2, "armor", 3), _part(3, "armor", 6), _part(4, "armor", 9), _part(5, "armor", 12)])
	var positions = [Vector2(0, 0), Vector2(3, 0), Vector2(100, 0), Vector2(100.86, 0), Vector2(101.72, 0)]
	for i in range(5): false_seed.body_for_part(i + 1).position = positions[i]
	var claimed = false_seed._try_collinear_contacts({"p": 1, "q": 2, "normal": Vector2.LEFT, "h": -1, "time": 0.0})
	_check(not claimed and false_seed.telemetry.swept_contacts == 0 and false_seed.telemetry.ccd_contact_pools == 0, "unrelated chain cannot claim to resolve a physically noncontacting seed")

func _shield_fixture(active: bool = true):
	var s = _sim([_part(1, "cargo", 0), _part(2, "shield", -1, 1, {"input_a": -2}), _part(3, "battery", -1)])
	s.set_pilot_input(0, false, active)
	return s

func _test_impact_shield() -> void:
	var on = _shield_fixture(); on._damage_part(on.parts[1], 20.0, "collision")
	var off = _shield_fixture(false); off._damage_part(off.parts[1], 20.0, "collision")
	_check(absf(on.parts[1].hp - 93.0) < 0.0001 and off.parts[1].hp == 80.0 and absf(on.telemetry.energy_used - 19.5) < 0.0001, "impact shield absorbs65percent with residualHP damage and1.5J perHP")
	var cap = _shield_fixture(); cap._damage_part(cap.parts[1], 100.0, "collision")
	_check(cap.parts[1].hp == 24.0 and cap.telemetry.impact_absorbed == 24.0, "single shield burst is capped24HP instead of invulnerability")
	var dry = _shield_fixture(); dry.parts[3].energy = 6.0; dry._damage_part(dry.parts[1], 20.0, "collision")
	_check(dry.parts[1].hp == 84.0 and dry.total_energy() == 0.0, "partial shield charge buys only4HP absorption")
	var split = _shield_fixture(); split._cut(2, 3); split._damage_part(split.parts[1], 20.0, "collision")
	_check(split.parts[1].hp == 80.0 and split.telemetry.energy_used == 0.0, "immediate disconnected shield cannot borrow power or protect cargo")
	var repeated = _shield_fixture(); repeated._damage_part(repeated.parts[1], 20.0, "collision"); repeated._damage_part(repeated.parts[1], 20.0, "collision")
	_check(absf(repeated.parts[1].hp - 84.0) < 0.0001 and repeated.telemetry.impact_absorbed == 24.0, "multiple contacts share one shield24HP tick budget")
	var valved = _sim([_part(1, "cargo", 0), _part(2, "shield", 1), _part(3, "battery", -1), _part(4, "valve", 1, 1, {"target": 2, "param": 0.0})])
	valved._damage_part(valved.parts[1], 20.0, "collision")
	_check(valved.parts[1].hp == 80.0 and valved.telemetry.energy_used == 0.0, "zero-power shield valve blocks absorption")
	var rate = _sim([_part(1, "cargo", 0), _part(2, "shield", 1), _part(3, "battery", -1), _part(4, "valve", 1, 1, {"target": 2, "param": 120.0})])
	rate._damage_part(rate.parts[1], 20.0, "collision"); rate._damage_part(rate.parts[2], 20.0, "collision"); rate._damage_part(rate.parts[1], 1.0, "attack")
	_check(absf(rate.telemetry.energy_used - 1.0) < 0.0001 and absf(rate.telemetry.impact_absorbed - 2.0 / 3.0) < 0.0001, "same-tick multi-module impacts and attack share one120J/s shield-valve budget")
	var shared = _sim([_part(1, "cargo", 0), _part(2, "valve", 1, 0, {"param": 120.0}), _part(3, "shield", 1, -1), _part(4, "shield", 1, 1), _part(5, "battery", -1)])
	shared._damage_part(shared.parts[1], 20.0, "collision"); shared._damage_part(shared.parts[1], 20.0, "collision")
	_check(absf(shared.telemetry.energy_used - 2.0) < 0.0001, "untargeted valve preserves legacy per-consumer rate while each shield shares its own repeated-hit budget")
	var attack_cut = _sim([_part(1, "cargo", 0), _part(2, "beam", 1), _part(3, "shield", 2), _part(4, "battery", 3)])
	attack_cut._cut(2, 3); attack_cut._damage_part(attack_cut.parts[1], 20.0, "attack")
	_check(attack_cut.parts[1].hp == 80.0 and attack_cut.telemetry.energy_used == 0.0, "attack shield also respects immediate victim-to-shield circuit cut before body rebuild")
	var physics_on = _shield_fixture(); var physics_off = _shield_fixture(false)
	for s in [physics_on, physics_off]:
		s.obstacles.append({"position": s.part_world_position(1) + Vector2(1.2, 0), "radius": 0.5, "health": 1000000.0, "mass": 1000000.0, "type": "rock", "velocity": Vector2.ZERO})
		s.bodies[0].velocity = Vector2(5, 0)
	_advance(physics_on, 0.2, 0, false, true); _advance(physics_off, 0.2)
	_check(physics_on.telemetry.swept_contacts > 0 and physics_on.parts[1].hp > physics_off.parts[1].hp and physics_on.parts[1].hp < 100.0, "powered shield changes actual collision damage but cannot remove contact")
	_check(physics_on.bodies[0].velocity == physics_off.bodies[0].velocity and physics_on.bodies[0].angular_velocity == physics_off.bodies[0].angular_velocity, "shield on/off retains identical real impulse and angular knockback")
	var legacy = V2Sim.new(); legacy.configure([_part(1, "cargo", 0), _part(2, "shield", 1), _part(3, "battery", -1)], [], _open_route(), 42)
	legacy._damage_part(legacy.parts[1], 20.0, "collision")
	_check(legacy.parts[1].hp == 80.0 and legacy.telemetry.energy_used == 0.0, "frozen v2 shield remains attack-only")

func _test_exit_and_replay() -> void:
	var design = [_part(1, "cargo", 0), _part(2, "teleporter", 1, 0, {"param": 8.0, "input_a": -2}), _part(3, "battery", 2)]
	var jump = _sim(design); jump.bodies[0].velocity = Vector2(100, 0)
	jump.obstacles.append({"position": jump.part_world_position(3) + Vector2(18, 0), "radius": 0.2, "health": 100.0, "type": "rock", "velocity": Vector2.ZERO})
	_check(not jump.destination_clear(jump.bodies[0], Vector2(8, 0)), "high-speed teleport exit checks full0.22s clearance")
	var before: Vector2 = jump.cargo_position(); _advance(jump, 1.0 / 120.0, 0, false, true)
	_check(jump.cargo_position().x < before.x + 2.0 and jump.telemetry.energy_used == 0.0, "blocked teleport neither jumps nor spends charge")
	var snapshot = JSON.parse_string(JSON.stringify({"design": Profile.reinforced_design(), "route": _open_route(), "seed": 42}))
	var a = _sim(Profile.reinforced_design()); var b = Sim.new(); b.configure(snapshot.design, [], snapshot.route, snapshot.seed)
	for tick in range(300):
		var axis = -1000 if tick < 40 else 0
		a.set_pilot_input(axis, tick < 150); b.set_pilot_input(axis, tick < 150)
		a.step(1.0 / 60.0); b.step(1.0 / 120.0); b.step(1.0 / 120.0)
	_check(a.cargo_position() == b.cargo_position() and a.telemetry == b.telemetry and a.events == b.events, "v3 JSON build replay and60Hz/two120Hz stepping are exact")
	var ordinary = _sim(); var previous = V2Sim.new(); previous.configure(Profile.starter_design(), [], _open_route(), 42)
	for tick in range(180):
		var axis = -1000 if tick < 60 else (1000 if tick < 120 else 0)
		ordinary.set_pilot_input(axis, false); previous.set_pilot_input(axis, false)
		ordinary.step(1.0 / 60.0); previous.step(1.0 / 60.0)
	_check(ordinary.cargo_position() == previous.cargo_position() and ordinary.bodies[0].velocity == previous.bodies[0].velocity and ordinary.telemetry.energy_used == previous.telemetry.energy_used, "ordinary no-contact assistance is bit-exact with v2 motion and paid energy")

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

func _test_frozen_sources() -> void:
	_check(FileAccess.get_sha256("res://scripts/simulation.gd") == "582e188f09949cb969a4f0a73dbd97d58f2df38ec17f76568eb229ecfecf369e", "frozen source unchanged: simulation")
	_check(FileAccess.get_sha256("res://scripts/pilot_simulation.gd") == "81b7d5bdb4514663d3d89c0ae7cf7a510344d53cecfcf05f205ae97af727acd6", "frozen source unchanged: pilot_simulation")
	_check(FileAccess.get_sha256("res://scripts/pilot_profile.gd") == "41031fc568aa5aa2c37c023b5b162ff9f24dd3db97e2fd6dec14dadb207132dd", "frozen source unchanged: pilot_profile")
	_check(FileAccess.get_sha256("res://scripts/pilot_ascent_simulation.gd") == "ff2eb35b770f17eeaecd78ae302dc134e6e9260260a37022b6e198e046ae4d87", "frozen source unchanged: pilot_ascent_simulation")
	_check(FileAccess.get_sha256("res://scripts/pilot_ascent_profile.gd") == "a8235b741aeddbad5442856a87115a1bf069d3f1b81d1e0ba063fdcd8183f004", "frozen source unchanged: pilot_ascent_profile")
	_check(FileAccess.get_sha256("res://scripts/parts.gd") == "1a92c0202b022e3090d50097145743cd65e3d002b9b5b20bd187f1faa1321b2b", "frozen source unchanged: parts")
