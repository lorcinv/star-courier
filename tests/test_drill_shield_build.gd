extends SceneTree
## Focused actual-build gameplay gate; no stronger parts or physics overrides.
const Probe = preload("res://tools/drill_approach_probe.gd")
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Open = preload("res://tools/extreme_build_probe.gd")
var assertions = 0
var failures: Array = []

func _initialize() -> void:
	var on = Probe.run_fixture()
	_check(Probe.design().size() == 22 and absf(on.initial_mass - 25.5) < 0.0001 and on.initial_energy == 12000.0, "legal22-module craft pays25.5kg and two finite6000J cells")
	var real_sizes = true; var beams = 0
	for p in on.modules:
		real_sizes = real_sizes and p.scale == 1.0
		if p.type == "beam": beams += 1
	_check(real_sizes and beams == 5, "actual1-cell collision sizes and five ordinary beams retained")
	_check(on.obstacle_hp == 0.0 and on.drill_alive and absf(on.drill_hp - 14.073) < 0.0001, "four-shield drill survives18m/s and clears80HP rock")
	_check(on.cargo_hp == 100.0 and on.structure_damage == 0.0 and on.body_count == 1 and on.ccd_budget_holds == 0, "successful cutter keeps cargo and real connected structure")
	_check(absf(on.impact_absorbed - 85.293) < 0.0001 and absf(on.shield_energy - 127.9395) < 0.0001, "real shields pay127.9395J for capped65percent collision absorption")
	_check(absf(on.first_hit.velocity[0] + 1.44) < 0.0001 and on.hull_contacts == 1, "successful cutter still takes the actual backward collision impulse")
	var off = Probe.run_fixture(18.0, false, true)
	_check(off.obstacle_hp > 0.7 and off.clearance.is_empty() and off.drill_damage == 0.0, "same motor-off craft remains blocked rather than shield-only clearance")
	_check(absf(off.first_hit.velocity[0] - on.first_hit.velocity[0]) < 0.00001 and off.first_hit.drill_hp == on.first_hit.drill_hp, "motor on does not hide first-hit velocity or damage")
	var unshielded = Probe.run_fixture(18.0, true, false, "rock", false, 0.2)
	_check(not unshielded.drill_alive and unshielded.shield_energy == 0.0 and absf(unshielded.first_hit.velocity[0] - on.first_hit.velocity[0]) < 0.00001, "shield-off loses actual60HP drill with the same impulse")
	var slow = Probe.run_fixture(5.0, true, true, "rock", false, 1.5)
	_check(slow.obstacle_hp == 0.0 and slow.drill_hp > 50.0 and slow.cargo_hp == 100.0, "moderate approach also gives useful sustained cutting")
	var gate = Probe.run_fixture(18.0, true, true, "gate", false, 0.2)
	_check(gate.drill_damage == 0.0 and gate.obstacle_hp > 999900.0 and gate.hull_contacts > 0 and gate.clearance.is_empty(), "noncuttable gate remains solid and causes real impact")
	var no_hit = Probe.run_fixture(18.0, true, true, "no_hit", false, 0.5)
	_check(no_hit.hull_contacts == 0 and no_hit.drill_damage == 0.0 and no_hit.shield_energy == 0.0 and no_hit.drill_hp == 60.0 and absf(no_hit.drill_energy - 30.0) < 0.0001, "empty lane has no invented cutting or shielding but pays motor idle cost")
	var empty = Probe.run_fixture(18.0, true, true, "rock", false, 0.2, 0.25)
	_check(empty.drill_damage == 0.0 and not empty.drill_alive and empty.charge == 0.0 and absf(empty.energy_used - 0.25) < 0.0001, "expired finite power cannot run cutter or grant shield protection")
	var fast = Probe.run_fixture(34.0, true, true, "rock", false, 0.2)
	_check(not fast.drill_alive and absf(fast.impact_absorbed - 96.0) < 0.0001 and absf(fast.shield_energy - 144.0) < 0.0001, "34m/s exceeds four real24HP budgets and destroys drill")
	var exit_boost = Probe.run_fixture(18.0, true, true, "rock", true)
	_check(exit_boost.drill_alive and exit_boost.cargo_hp == 100.0 and exit_boost.velocity[0] > 29.0 and exit_boost.charge < 0.001 and exit_boost.energy_used <= 12000.01, "realShift after clearance accelerates living craft until finite cells exhaust")
	_check(exit_boost.structure_damage == 0.0 and exit_boost.ccd_budget_holds == 0 and exit_boost.body_count == 1, "reinforced escape needs no stress immunity or CCD hold")
	_check(_direct_parity(on), "probe matches unmodified productionSim with identical initial conditions")
	var course = Probe.run_course()
	_check(not course.initial_speed_fixture and course.initial_speed == 0.0 and course.first_hit.time > 19.0 and course.first_hit.velocity_before_tick[0] > 17.9 and course.first_hit.velocity_before_tick[0] < 18.01, "from-rest course really reaches cruise using engines before contact")
	_check(course.obstacle_hp <= 0.0 and course.drill_alive and course.cargo_hp == 100.0 and course.drill_damage > 0.0 and course.charge > 6000.0, "self-accelerated cutter clears real80HP rock and retains useful charge")
	var course_off = Probe.run_course(false, true)
	_check(course_off.obstacle_hp > 0.0 and course_off.clearance.is_empty() and course_off.drill_damage == 0.0 and course_off.drill_alive, "self-accelerated motor-off control remains genuinely blocked")
	_check(absf(course_off.first_hit.velocity_before_tick[0] - course.first_hit.velocity_before_tick[0]) < 0.0001 and absf(course_off.first_hit.drill_hp - course.first_hit.drill_hp) < 0.001, "from-rest cutter advantage has same pre-impact motion and shield damage")
	print("DRILL_BUILD_COURSE ", JSON.stringify({"impact_time": course.first_hit.time, "approach_speed": course.first_hit.velocity_before_tick[0], "clearance_time": course.clearance.get("time", -1.0), "drill_hp": course.drill_hp, "cargo_hp": course.cargo_hp, "charge": course.charge, "motor_off_rock_hp": course_off.obstacle_hp}))
	if failures.is_empty(): print("PASS: %d real drill/shield build assertions" % assertions); quit(0)
	else:
		for failure in failures: printerr("FAIL: ", failure)
		printerr("%d/%d drill/shield build assertions failed" % [failures.size(), assertions]); quit(1)

func _direct_parity(expected: Dictionary) -> bool:
	var sim = Sim.new(); sim.configure(Probe.design(), [], Open.open_route(), 42)
	# Same disclosed test-only initial condition as run_fixture; no later writes.
	sim.bodies[0].velocity = Vector2(18.0, 0.0)
	sim.obstacles.append({"position": sim.part_world_position(40) + Vector2(2.23, 0.0), "radius": 0.8,
		"health": 80.0, "mass": 20.0, "type": "rock", "velocity": Vector2.ZERO, "pilot_gate": false, "destructible": true})
	for tick in range(480): sim.set_pilot_input(0, false, false); sim.step(1.0 / 120.0)
	var actual = Probe.snapshot(sim)
	for key in actual:
		if actual[key] != expected[key]: return false
	return true

func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)
