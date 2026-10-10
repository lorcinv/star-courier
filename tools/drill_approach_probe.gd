extends SceneTree
## Actual pilot-v3 build/route probe. No observer subclass or physics overrides.
## run_fixture alone assigns a disclosed INITIAL speed to compare identical hits;
## run_course starts from rest and obtains every later speed from actual engines.
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Profile = preload("res://scripts/pilot_extreme_profile.gd")
const BuildProbe = preload("res://tools/extreme_build_probe.gd")
const DRILL_ID = 40
const SHIELD_IDS = [41, 42, 43, 44]

static func design(motor_on: bool = true, shields_on: bool = true) -> Array:
	var build = Profile.reinforced_design()
	build.append(Profile.part(DRILL_ID, "drill", 2, 0, {"input_a": -1 if motor_on else -2}))
	for mount in [[41, 0, -2], [42, 1, -2], [43, 0, 2], [44, 1, 2]]:
		build.append(Profile.part(mount[0], "shield", mount[1], mount[2], {"input_a": -1 if shields_on else -2}))
	return build

static func course_route() -> Dictionary:
	var route = BuildProbe.open_route()
	route.name = "真实推进钻切验证航线"; route.distance = 320.0
	route.time_limit = 70.0; route.deadline = 60.0
	route.hazards = [{"x": 220.0, "y": 0.0, "radius": 0.8, "health": 80.0, "mass": 20.0, "type": "rock", "destructible": true}]
	return route

static func run_fixture(initial_speed: float = 18.0, motor_on: bool = true, shields_on: bool = true,
		material: String = "rock", boost_after_clear: bool = false, seconds: float = 4.0, charge: float = 12000.0) -> Dictionary:
	var sim = Sim.new(); sim.configure(design(motor_on, shields_on), [], BuildProbe.open_route(), 42)
	# Test starting condition only. No production path calls this fixture helper.
	sim.bodies[0].velocity = Vector2(initial_speed, 0)
	for p in sim.parts.values():
		if p.type == "battery": p.energy = clampf(charge * 0.5, 0.0, p.capacity)
	var radius = 5.0 if material == "gate" else 0.8
	var at = sim.part_world_position(DRILL_ID) + Vector2(1.0 + 0.43 + radius, 100.0 if material == "no_hit" else 0.0)
	sim.obstacles.append({"position": at, "radius": radius, "health": 1000000.0 if material == "gate" else 80.0,
		"mass": 1000000.0 if material == "gate" else 20.0, "type": "rock", "velocity": Vector2.ZERO,
		"pilot_gate": material == "gate", "destructible": material != "gate"})
	var result = _run(sim, seconds, boost_after_clear)
	result.merge({"initial_speed": initial_speed, "initial_speed_fixture": true, "motor_on": motor_on, "shields_on": shields_on, "material": material})
	return result

static func run_course(motor_on: bool = true, shields_on: bool = true, boost_after_clear: bool = false) -> Dictionary:
	var sim = Sim.new(); sim.configure(design(motor_on, shields_on), [], course_route(), 42)
	var result = _run(sim, 28.0, boost_after_clear, 4.0)
	result.merge({"initial_speed": 0.0, "initial_speed_fixture": false, "motor_on": motor_on, "shields_on": shields_on, "material": "rock"})
	return result

static func _run(sim, seconds: float, boost_after_clear: bool, seconds_after_hit: float = -1.0) -> Dictionary:
	var initial_energy = sim.total_energy(); var initial_mass = sim.total_mass()
	var first_hit: Dictionary = {}; var clearance: Dictionary = {}; var checkpoints: Array = []
	var contact_ticks = 0; var cut_ticks = 0; var first_cut = -1.0; var last_cut = -1.0
	for tick in range(roundi(seconds * 120.0)):
		var old_hits = int(sim.telemetry.swept_contacts)
		var old_cuts = int(sim.telemetry.drill_contacts)
		var velocity_before: Vector2 = sim.body_for_part(1).get("velocity", Vector2.ZERO)
		sim.set_pilot_input(0, boost_after_clear and sim.obstacles[0].health <= 0.0, false)
		sim.step(1.0 / 120.0)
		if int(sim.telemetry.swept_contacts) > old_hits:
			contact_ticks += 1
			if first_hit.is_empty():
				first_hit = snapshot(sim); first_hit.velocity_before_tick = [velocity_before.x, velocity_before.y]
		if int(sim.telemetry.drill_contacts) > old_cuts:
			cut_ticks += 1; last_cut = sim.elapsed
			if first_cut < 0.0: first_cut = sim.elapsed
		if sim.obstacles[0].health <= 0.0 and clearance.is_empty(): clearance = snapshot(sim)
		if tick % 120 == 119: checkpoints.append(snapshot(sim))
		if sim.status != "running": break
		if seconds_after_hit > 0.0 and not first_hit.is_empty() and sim.elapsed >= first_hit.time + seconds_after_hit: break
	var result = snapshot(sim)
	result.merge({"initial_energy": initial_energy, "initial_mass": initial_mass, "first_hit": first_hit,
		"clearance": clearance, "first_cut_tick": first_cut, "last_cut_tick": last_cut, "cut_ticks": cut_ticks,
		"cut_budget_seconds": cut_ticks / 120.0, "hull_contact_ticks": contact_ticks, "checkpoints": checkpoints})
	return result

static func snapshot(sim) -> Dictionary:
	var body = sim.body_for_part(1); var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var modules: Array = []
	for p in sim.parts.values(): modules.append({"id": p.id, "type": p.type, "hp": p.hp, "max_hp": p.max_hp, "alive": p.alive, "scale": p.scale})
	return {"time": sim.elapsed, "status": sim.status, "obstacle_hp": sim.obstacles[0].health,
		"cargo_hp": sim.parts[1].hp, "drill_hp": sim.parts[DRILL_ID].hp, "drill_alive": sim.parts[DRILL_ID].alive,
		"velocity": [velocity.x, velocity.y], "angular_velocity": body.get("angular_velocity", 0.0),
		"charge": sim.total_energy(), "energy_used": sim.telemetry.energy_used, "drill_energy": sim.telemetry.drill_energy_used,
		"drill_damage": sim.telemetry.drill_damage, "drill_contacts": sim.telemetry.drill_contacts,
		"hull_contacts": sim.telemetry.swept_contacts, "impact_absorbed": sim.telemetry.impact_absorbed,
		"shield_energy": sim.telemetry.impact_shield_energy, "structure_damage": sim.telemetry.structure_damage,
		"ccd_budget_holds": sim.telemetry.ccd_budget_holds, "body_count": sim.bodies.size(), "modules": modules}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if "--course" in args:
		print("DRILL_FROM_REST ", JSON.stringify(run_course(not "--motor-off" in args, not "--shields-off" in args, "--boost-exit" in args)))
	else:
		for speed in [5.0, 18.0, 34.0]:
			for control in ["all_on", "motor_off", "shields_off"]:
				print("DRILL_SHIELD_PROBE ", JSON.stringify(run_fixture(speed, control != "motor_off", control != "shields_off")))
	quit(0)
