extends SceneTree
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Profile = preload("res://scripts/pilot_extreme_profile.gd")

static func open_route() -> Dictionary:
	var r = Profile.route()
	r.hazards = []; r.pilot_gates = []; r.distance = 10000.0; r.boundary_y = 10000.0
	r.pilot_altitude = 0.0; r.destination_y = 0.0; r.time_limit = 120.0; r.pilot_drag = 0.0
	return r

static func run_build(design: Array, boost: bool, seconds: float = 5.0, axis: int = 0) -> Dictionary:
	var s = Sim.new(); s.configure(design, [], open_route(), 42)
	var peak_force = 0.0; var checkpoints = {}; var initial = s.total_energy()
	var max_error = 0.0
	for tick in range(roundi(seconds * 60.0)):
		s.set_pilot_input(axis, boost); s.step(1.0 / 60.0)
		peak_force = maxf(peak_force, s.telemetry.thrust_actual)
		var kinetic = 0.0
		for b in s.bodies: kinetic += 0.5 * b.mass * b.velocity.length_squared() + 0.5 * b.inertia * b.angular_velocity * b.angular_velocity
		max_error = maxf(max_error, kinetic + s.total_energy() - initial)
		if tick in [59, 179, 299]: checkpoints[str((tick + 1) / 60)] = {"speed": s.telemetry.speed, "energy": s.telemetry.energy_used, "structure_damage": s.telemetry.structure_damage}
		if s.status != "running": break
	return {"mass": s.telemetry.mass, "speed": s.telemetry.speed, "vertical_speed": s.telemetry.vertical_speed,
		"average_acceleration": s.telemetry.speed / maxf(0.00001, s.elapsed), "energy_used": s.telemetry.energy_used,
		"initial_energy": initial, "energy_remaining": s.total_energy(), "structure_damage": s.telemetry.structure_damage,
		"peak_socket_load": s.telemetry.peak_socket_load, "peak_thrust": peak_force, "integrity": s.ship_integrity(),
		"body_count": s.bodies.size(), "max_energy_error": max_error, "checkpoints": checkpoints, "status": s.status}

static func contact_budget_probe(count: int = 24, ticks: int = 4) -> Dictionary:
	count = clampi(count, 3, 32); ticks = clampi(ticks, 1, 8)
	var design: Array = []
	for i in range(count): design.append(Profile.part(i + 1, "cargo" if i == 0 else "armor", (i % 8) * 3, (i / 8) * 3))
	var s = Sim.new(); s.configure(design, [], open_route(), 42)
	for i in range(count):
		var p: Dictionary = s.parts[i + 1]; p.hp = 1.0e12; p.max_hp = 1.0e12
		var b = s.body_for_part(i + 1); b.position = Vector2(i * 0.861, 0)
		b.velocity = Vector2(1000.0 if i % 2 == 0 else -1000.0, 0)
	var momentum = s.total_momentum(); var maximum_usec = 0; var total_usec = 0
	var initial_kinetic = 0.0
	for b in s.bodies: initial_kinetic += 0.5 * b.mass * b.velocity.length_squared()
	var finite = true; var ordered = true; var durations: Array = []; var contacts_per_tick: Array = []; var holds_per_tick: Array = []; var rounds_per_tick: Array = []
	for tick in range(ticks):
		var previous_contacts = int(s.telemetry.swept_contacts); var previous_holds = int(s.telemetry.get("ccd_budget_holds", 0)); var previous_rounds = int(s.telemetry.get("ccd_event_rounds", 0))
		var start = Time.get_ticks_usec(); s.step(1.0 / 120.0)
		var duration = Time.get_ticks_usec() - start
		maximum_usec = maxi(maximum_usec, duration); total_usec += duration
		durations.append(duration / 1000.0); contacts_per_tick.append(int(s.telemetry.swept_contacts) - previous_contacts); holds_per_tick.append(int(s.telemetry.get("ccd_budget_holds", 0)) - previous_holds); rounds_per_tick.append(int(s.telemetry.get("ccd_event_rounds", 0)) - previous_rounds)
		for i in range(count):
			var b = s.body_for_part(i + 1)
			finite = finite and b.position.is_finite() and b.velocity.is_finite() and is_finite(b.angular_velocity)
			if i > 0: ordered = ordered and s.body_for_part(i).position.x <= b.position.x
	var speed_min = INF; var speed_max = -INF; var final_kinetic = 0.0
	for b in s.bodies: final_kinetic += 0.5 * b.mass * b.velocity.length_squared()
	for b in s.bodies: speed_min = minf(speed_min, b.velocity.x); speed_max = maxf(speed_max, b.velocity.x)
	return {"initial_kinetic": initial_kinetic, "final_kinetic": final_kinetic, "minimum_vx": speed_min, "maximum_vx": speed_max, "bodies": count, "ticks": ticks, "contacts": s.telemetry.swept_contacts,
		"event_round_limit_per_tick": clampi(count * 10, 32, 256), "budget_holds": s.telemetry.get("ccd_budget_holds", 0),
		"finite": finite, "ordered": ordered, "status": s.status, "momentum_error": s.total_momentum().distance_to(momentum),
		"maximum_tick_ms": maximum_usec / 1000.0, "average_tick_ms": float(total_usec) / ticks / 1000.0,
		"tick_ms": durations, "contacts_per_tick": contacts_per_tick, "holds_per_tick": holds_per_tick, "event_rounds_per_tick": rounds_per_tick}

func _initialize() -> void:
	if "--contacts-only" in OS.get_cmdline_user_args():
		print("EXTREME_CONTACT_BUDGET ", JSON.stringify(contact_budget_probe(24, 8)))
		quit(); return
	var report = {}
	for label in ["standard", "eight_thrusters"]:
		var design = Profile.starter_design() if label == "standard" else Profile.reinforced_design()
		for boost in [false, true]:
			report[label + ("_overdrive" if boost else "_cruise")] = run_build(design, boost)
	print("EXTREME_BUILD_PROBE ", JSON.stringify(report))
	quit()
