extends SceneTree
const FixtureIO = preload("res://tests/fixtures/protected_bird_v1/fixture_io.gd")
const Sim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const Bird = preload("res://scripts/pilot_protected_bird_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Sweep = preload("res://scripts/wildlife_sweep_v1.gd")
var checks = 0
var failures = 0

func _init() -> void:
	var constructor_error = Bird.validation_error(Bird.route({}, "CHRONOLOGY", 42))
	if not constructor_error.is_empty():
		check(false, "Native route prerequisite: " + constructor_error)
		quit(1); return
	ordinary_collision_precedes_bird()
	ray_precedes_body()
	accelerator_source()
	power_circuit_negatives()
	rotation_contact()
	bounded_rotation_regressions()
	spin_obstacle_precedes_bird()
	print("PROTECTED_BIRD_CHRONOLOGY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func fixture(design: Array):
	var sim = Sim.new(); sim.configure(design, [], Bird.route({}, "CHRONOLOGY", 42), 42)
	check(sim.status == "running", "Fixture configured")
	sim.obstacles.clear(); sim.route.pilot_drag = 0.0
	for body in sim.bodies: body.position += Vector2(1090, -150)
	for p in sim.parts.values(): p.wormhole_visits = {"morning-mosslight": true}
	sim.wildlife.active = true; sim.wildlife.activated = true; sim.wildlife.state = "healthy"
	sim.wildlife.activation_tick = 0; sim.wildlife.position = Vector2(1100, -150); sim.wildlife.velocity = Vector2.ZERO
	return sim

func ordinary_collision_precedes_bird() -> void:
	var sim = fixture([Extreme.part(1, "cargo", 0)])
	sim.body_for_part(1).position = Vector2(1094, -150); sim.body_for_part(1).velocity = Vector2(1200, 0)
	sim.obstacles.append({"position": Vector2(1096, -150), "radius": 0.5, "health": 1000000.0,
		"type": "rock", "velocity": Vector2.ZERO, "mass": 1000000.0, "conductive": true})
	sim.step(1.0 / 120.0)
	check(sim.parts[1].hp < 100.0 and sim.telemetry.swept_contacts > 0, "Earlier ordinary obstacle is physically resolved")
	check(sim.first_harm.is_empty() and sim.wildlife.hp == 8.0, "Discarded pre-impact chord cannot falsely injure bird")
	check(sim.wildlife_error.is_empty(), "Earlier collision resweeps without wildlife error")

func ray_precedes_body() -> void:
	var sim = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "lance", 1, 0, {"param": 12.0}), Extreme.part(3, "battery", -1)])
	var body: Dictionary = sim.body_for_part(1)
	body.position += Vector2(1099, -150) - sim.part_world_position(2)
	body.velocity = Vector2(120, 0)
	sim.step(1.0 / 120.0)
	check(not sim.first_harm.is_empty() and sim.first_harm.source.action_kind == "lance" and sim.first_harm.substep_fraction == 0.0, "Paid action-time ray wins first harm before movement")
	check(sim.wildlife.damage_transitions >= 2 and sim.wildlife_result().harms.size() == 1, "Later real shell contact changes HP without duplicate cause")

func accelerator_source() -> void:
	var design = [Extreme.part(1, "cargo", 0), Extreme.part(2, "accelerator", 1, 0, {"param": 20.0, "target": 4}), Extreme.part(3, "battery", -1), Extreme.part(4, "armor", 2)]
	var sim = fixture(design)
	sim.wildlife.position = sim.part_world_position(4) + Vector2(1.4, 0)
	sim.step(1.0 / 120.0)
	check(sim.parts[2].spent and sim.parts[2].body_id != sim.parts[4].body_id, "Paid accelerator launches real loaded module")
	check(not sim.first_harm.is_empty() and sim.first_harm.source.part_id == 4 and sim.first_harm.source.action_kind == "contact", "Actual launched armor is source, never accelerator ray")
	check(sim.telemetry.energy_used > 0.0 and sim.telemetry.ammo_cost > 0.0, "Inherited energy/ammo costs retained")

func power_circuit_negatives() -> void:
	for mode in ["miswired", "cut", "empty"]:
		var design = [Extreme.part(1, "cargo", 0), Extreme.part(2, "drill", 1, 0, {"input_a": 99999 if mode == "miswired" else -1}), Extreme.part(3, "battery", -1)]
		var sim = fixture(design)
		if mode == "cut": sim._detach(2); sim._rebuild_bodies()
		if mode == "empty": sim.parts[3].energy = 0.0
		sim.wildlife.position = sim.part_world_position(2) + Vector2(0.83, 0)
		sim.step(1.0 / 120.0)
		check(sim.first_harm.is_empty() and sim.telemetry.drill_damage == 0.0, mode + " drill has no paid cut")

func rotation_contact() -> void:
	# A real connected armor chain rotates into the animal. No beam stress
	# exemption is invented; all modules use their ordinary known material.
	var design = [Extreme.part(1, "cargo", 0)]
	for i in range(1, 5): design.append(Extreme.part(i + 1, "armor", i))
	var sim = fixture(design)
	var body: Dictionary = sim.body_for_part(1)
	body.angular_velocity = 20.0
	var tip: Dictionary = sim.parts[5]
	var angle_at_half = body.angle + body.angular_velocity / 240.0
	var tip_at_half: Vector2 = body.position + tip.local_pos.rotated(angle_at_half)
	var outward: Vector2 = tip.local_pos.rotated(angle_at_half).normalized()
	sim.wildlife.position = tip_at_half + outward * 0.795
	var probe = {"fixture": "connected-cargo-and-four-armor", "dt": 1.0 / 120.0,
		"body_position": [body.position.x, body.position.y], "body_angle": body.angle,
		"velocity": [body.velocity.x, body.velocity.y], "angular_velocity": body.angular_velocity,
		"mass": body.mass, "inertia": body.inertia,
		"bird_position": [sim.wildlife.position.x, sim.wildlife.position.y], "bird_velocity": [0.0, 0.0],
		"bird_radius": sim.wildlife.radius, "bird_hp": sim.wildlife.hp,
		"midpoint_witness": [tip_at_half.x, tip_at_half.y],
		"midpoint_distance": tip_at_half.distance_to(sim.wildlife.position),
		"real_combined_radius": 0.43 * tip.scale + float(sim.wildlife.radius), "parts": []}
	for part in body.parts:
		var verdict = Sweep.solve(body.position, body.position + body.velocity / 120.0,
			body.angle, body.angle + body.angular_velocity / 120.0, part.local_pos,
			sim.wildlife.position, sim.wildlife.position, 0.43 * part.scale + float(sim.wildlife.radius))
		probe.parts.append({"id": part.id, "type": part.type, "local_pos": [part.local_pos.x, part.local_pos.y],
			"local_angle": part.local_angle, "scale": part.scale, "hp": part.hp, "sweep": verdict})
	sim.step(1.0 / 120.0)
	probe.error = sim.wildlife_error; probe.harm = sim.first_harm.duplicate(true)
	probe.after_bird_hp = sim.wildlife.hp
	_write_evidence("user://protected_bird_v1/chronology/rotation-probe-latest.json", probe)
	print("ROTATION_PROBE ", JSON.stringify(probe, "", true, true))
	if not sim.wildlife_error.is_empty():
		print("ROTATING_CONTACT_FAILURE ", JSON.stringify({"error": sim.wildlife_error, "wildlife": sim.wildlife, "body": {"position": str(body.position), "velocity": str(body.velocity), "angle": body.angle, "angular_velocity": body.angular_velocity}, "events": sim.events, "ccd_rounds": sim.telemetry.get("ccd_event_rounds", 0)}, "", true, true))
	check(sim.wildlife_error.is_empty(), "Real rotating-body contact is bounded and resolved")
	check(not sim.first_harm.is_empty() and sim.first_harm.source.action_kind == "contact", "Rotating actual module produces honest harm")

func bounded_rotation_regressions() -> void:
	var com = Vector2(1090, -150)
	var lever = Vector2(2.3720932006835938, 0.0)
	var bird = Vector2(1093.1561279296875, -149.7363739013672)
	var first = Sweep.solve(com, com, 0.0, 20.0 / 120.0, lever, bird, bird, 0.805)
	check(first.state == "hit" and first.distance <= 0.805, "Captured high-spin regression has an actual inside witness")
	check(first.get("nodes", Sweep.MAX_NODES + 1) > 0 and first.get("nodes", Sweep.MAX_NODES + 1) <= Sweep.MAX_NODES, "Captured rotating root has an explicit bounded iteration count")
	if first.state == "hit":
		check((20.0 / 120.0) * lever.length() * (float(first.bracket[1]) - float(first.bracket[0])) <= Sweep.ROOT_POSITION_TOLERANCE, "Rotation root bracket obeys declared world-travel tolerance")
	for i in range(4):
		check(Sweep.solve(com, com, 0.0, 20.0 / 120.0, lever, bird, bird, 0.805) == first, "Captured extreme sweep exactly replays")
	var half_angle = 10.0 / 120.0
	var outside_bird = com + (lever + Vector2(0.806, 0.0)).rotated(half_angle)
	var miss = Sweep.solve(com, com, 0.0, 20.0 / 120.0, lever, outside_bird, outside_bird, 0.805)
	check(miss.state == "miss" and miss.get("nodes", Sweep.MAX_NODES + 1) <= Sweep.MAX_NODES, "Neighboring real high-spin near miss stays harmless and bounded")
	for omega in [40.0, 120.0, 480.0, 2400.0]:
		var angle = omega / 120.0
		var at = com + (lever + Vector2(0.79, 0.0)).rotated(minf(angle * 0.5, PI * 0.5))
		var sweep = Sweep.solve(com, com, 0.0, angle, lever, at, at, 0.805)
		check(sweep.state == "hit" and sweep.distance <= 0.805 and sweep.get("nodes", Sweep.MAX_NODES + 1) <= Sweep.MAX_NODES, "Higher finite rotation finds genuine contact without a speed clamp")

func spin_obstacle_precedes_bird() -> void:
	var design = [Extreme.part(1, "cargo", 0)]
	for i in range(1, 5): design.append(Extreme.part(i + 1, "armor", i))
	var sim = fixture(design)
	var body: Dictionary = sim.body_for_part(1)
	body.angular_velocity = 20.0
	var lever: Vector2 = sim.parts[5].local_pos
	sim.wildlife.position = Vector2(1093.1561279296875, -149.7363739013672)
	var obstacle_at: Vector2 = body.position + lever.rotated(0.02) + Vector2.UP.rotated(0.02) * -0.62
	sim.obstacles.append({"position": obstacle_at, "radius": 0.2, "health": 1000000.0,
		"type": "rock", "velocity": Vector2.ZERO, "mass": 1000000.0, "conductive": true})
	sim.step(1.0 / 120.0)
	check(sim.parts[5].hp < 150.0 and sim.telemetry.swept_contacts > 0, "Earlier obstacle meets rotating limb before its bounded bird root")
	check(sim.first_harm.is_empty() and sim.wildlife.hp == 8.0 and sim.wildlife_error.is_empty(), "Earlier rotating impact changes remaining path; old bird chord is discarded")

func _write_evidence(path: String, value: Variant) -> void:
	var written = FixtureIO.write_json(path, value)
	if not written.ok:
		failures += 1
		push_error("FIXTURE_EVIDENCE_WRITE_FAILED " + written.error)
