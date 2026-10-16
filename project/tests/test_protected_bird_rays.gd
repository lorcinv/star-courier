extends SceneTree
const FixtureIO = preload("res://tests/fixtures/protected_bird_v1/fixture_io.gd")
## Paid weapon regression. Ordinary shrink acts before a cockpit-gated shot;
## fixture placement isolates ray geometry, never authorizes in-game harm.
const Sim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const Legacy = preload("res://scripts/pilot_wormhole_simulation.gd")
const Bird = preload("res://scripts/pilot_protected_bird_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
var checks = 0
var failures = 0
var observed: Array = []

func _init() -> void:
	var repro = "--repro" in OS.get_cmdline_user_args()
	for kind in ["lance", "arc"]:
		paid_case(kind, "behind_bird", Vector2(-0.35, 0.35), false)
		paid_case(kind, "behind_rock", Vector2(6, 0), true)
		paid_case(kind, "behind_module", Vector2(6, 0), true)
		if repro: continue
		paid_case(kind, "forward_bird", Vector2(6, 0.35), true)
		paid_case(kind, "tangent", Vector2(6, 0.375), true)
		paid_case(kind, "outside_tangent", Vector2(6, 0.376), false)
		paid_case(kind, "inside", Vector2(0, 0.2), true)
		paid_case(kind, "exact_range", Vector2(8.375, 0), false)
		paid_case(kind, "within_range", Vector2(8.374, 0), true)
		paid_case(kind, "beyond_range", Vector2(8.376, 0), false)
		paid_case(kind, "near_rock", Vector2(6, 0), false)
		paid_case(kind, "equal_rock", Vector2(6, 0), false)
		paid_case(kind, "unpowered", Vector2(6, 0), false)
		paid_case(kind, "gated", Vector2(6, 0), false)
		ordinary_beam(kind)
	if not repro: query_controls()
	check(observed.size() == (6 if repro else 28), "All paid observation cases completed")
	_write_evidence("user://protected_bird_v1/rays/ray-observations-latest.json", observed)
	print("PROTECTED_BIRD_RAYS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func fixture(kind: String, extra_module: bool = false):
	var design = [Extreme.part(1, "cargo", 0), Extreme.part(2, "battery", -1),
		Extreme.part(3, "shrink", -2, 0, {"target": 4, "param": 0.2}),
		Extreme.part(4, kind, -3, 0, {"param": 8.0, "input_a": -2})]
	if extra_module: design.append(Extreme.part(5, "armor", -6))
	var sim = Sim.new(); sim.configure(design, [], Bird.route({}, "RAY-BOUNDARY", 42), 42)
	check(sim.status == "running" and sim.wildlife_error.is_empty(), kind + " valid design configured")
	sim.obstacles.clear(); sim.route.gravity = 0.0; sim.route.pilot_drag = 0.0
	for body in sim.bodies: body.position += Vector2(1090, -150)
	for part in sim.parts.values(): part.wormhole_visits = {"morning-mosslight": true}
	sim.set_pilot_input(0, false, false)
	var energy: float = sim.total_energy()
	sim.step(1.0 / 120.0)
	check(sim.parts[4].scale == 0.2 and sim.total_energy() == energy and sim.first_harm.is_empty(), kind + " ordinary shrink completes with gated emitter off")
	var body: Dictionary = sim.body_for_part(4)
	body.position += Vector2(1100, -150) - sim.part_world_position(4)
	sim.wildlife.active = true; sim.wildlife.activated = true; sim.wildlife.state = "healthy"
	sim.wildlife.activation_tick = sim.pilot_tick; sim.wildlife.velocity = Vector2.ZERO
	return sim

func rock(at: Vector2, radius: float) -> Dictionary:
	return {"position": at, "radius": radius, "health": 100.0, "type": "rock",
		"velocity": Vector2.ZERO, "mass": 1000000.0, "conductive": false}

func paid_case(kind: String, mode: String, offset: Vector2, expected_harm: bool) -> void:
	var sim = fixture(kind, mode == "behind_module")
	var origin: Vector2 = sim.part_world_position(4)
	sim.wildlife.position = origin + offset
	if mode == "behind_rock": sim.obstacles.append(rock(origin + Vector2(-4, 4), 5.0))
	if mode == "near_rock": sim.obstacles.append(rock(origin + Vector2(4, 0), 0.5))
	if mode == "equal_rock": sim.obstacles.append(rock(sim.wildlife.position, sim.wildlife.radius))
	if mode == "behind_module": sim.body_for_part(5).position += origin + Vector2(-0.4, 0.4) - sim.part_world_position(5)
	var minimum_clearance = INF
	for part in sim.parts.values(): minimum_clearance = minf(minimum_clearance, sim.part_world_position(part.id).distance_to(sim.wildlife.position) - 0.43 * part.scale - sim.wildlife.radius)
	if mode != "inside": check(minimum_clearance > 0.0, kind + ":" + mode + " all actual shells clear bird before shot")
	if mode == "unpowered": sim.parts[2].energy = 0.0
	var energy: float = sim.total_energy()
	var candidate_distance: float = sim._ray_circle(origin, Vector2.RIGHT, sim.wildlife.position, sim.wildlife.radius)
	sim.set_pilot_input(0, false, mode != "gated"); sim.step(1.0 / 120.0)
	var paid = mode != "unpowered" and mode != "gated"
	check((sim.total_energy() < energy) == paid, kind + ":" + mode + " shot obeys actual power and cockpit circuit")
	check(sim.wildlife_error.is_empty(), kind + ":" + mode + " no simulation failure")
	check((not sim.first_harm.is_empty()) == expected_harm and (sim.wildlife.hp < 8.0) == expected_harm, kind + ":" + mode + " actual forward-ray outcome")
	if expected_harm:
		check(not sim.first_harm.is_empty() and sim.first_harm.source.part_id == 4 and sim.first_harm.source.action_kind == kind and sim.first_harm.substep_fraction == 0.0, kind + ":" + mode + " honest paid source at action time")
		check(absf(float(sim.wildlife.hp) - (8.0 - 35.0 / 120.0)) < 0.000001 and sim.wildlife.damage_transitions == 1, kind + ":" + mode + " one finite beam decrement only")
	if mode == "behind_rock": check(sim.obstacles[0].health == 100.0, kind + " wholly behind rock is neither occluder nor beam target")
	if mode == "behind_module": check(sim.parts[5].hp == 150.0, kind + " wholly behind detached module is neither occluder nor target")
	if mode in ["near_rock", "equal_rock"]: check(sim.obstacles[0].health < 100.0, kind + ":" + mode + " real solid occlusion wins")
	observed.append({"kind": kind, "case": mode, "origin": [origin.x, origin.y], "bird_offset": [offset.x, offset.y],
		"scale": sim.parts[4].scale, "minimum_pre_shot_shell_clearance": minimum_clearance,
		"query_distance": candidate_distance if is_finite(candidate_distance) else "INF", "energy_paid": energy - sim.total_energy(),
		"bird_hp": sim.wildlife.hp, "harm": sim.first_harm.duplicate(true), "error": sim.wildlife_error,
		"obstacle_hp": sim.obstacles[0].health if not sim.obstacles.is_empty() else null,
		"detached_hp": sim.parts[5].hp if mode == "behind_module" else null})

func ordinary_beam(kind: String) -> void:
	var sim = fixture(kind)
	var origin: Vector2 = sim.part_world_position(4)
	sim.wildlife.active = false
	sim.obstacles = [rock(origin + Vector2(-4, 4), 5.0), rock(origin + Vector2(6, 0), 0.375)]
	sim.set_pilot_input(0, false, true); sim.step(1.0 / 120.0)
	check(sim.obstacles[0].health == 100.0 and sim.obstacles[1].health < 100.0, kind + " inherited v5 ordinary beam uses the same forward query")
	check(sim.first_harm.is_empty() and sim.wildlife.hp == 8.0, kind + " ordinary beam invents no wildlife cause")

func query_controls() -> void:
	var sim = Sim.new(); var old = Legacy.new()
	for case in [
		[Vector2(-0.35, 0.35), 0.375, INF], [Vector2(-4, 4), 5.0, INF], [Vector2(-0.4, 0.4), 0.43, INF],
		[Vector2(0.35, 0.35), 0.375, 0.215370879821637], [Vector2(6, 0.375), 0.375, 6.0],
		[Vector2(6, 0.376), 0.375, INF], [Vector2(-0.1, 0.0), 0.375, 0.0], [Vector2.ZERO, 0.375, 0.0]]:
		var distance: float = sim._ray_circle(Vector2.ZERO, Vector2.RIGHT, case[0], case[1])
		check(is_inf(distance) if is_inf(case[2]) else absf(distance - case[2]) < 0.00001, "Forward circle query boundary " + str(case[0]))
	check(old._ray_circle(Vector2.ZERO, Vector2.RIGHT, Vector2(-0.35, 0.35), 0.375) == 0.0, "Frozen v4 protocol helper retains its original output")

func _write_evidence(path: String, value: Variant) -> void:
	var written = FixtureIO.write_json(path, value)
	if not written.ok:
		failures += 1
		push_error("FIXTURE_EVIDENCE_WRITE_FAILED " + written.error)
