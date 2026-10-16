extends SceneTree
const FixtureIO = preload("res://tests/fixtures/protected_bird_v1/fixture_io.gd")
## Actual D5-A commercial 2.4-weight offer. Scripted control witness only.
## Native keyboard/readability remains untested; original 1.0 fixtures stay separate.
const Sim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const BirdProfile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Replay = preload("res://scripts/protected_bird_replay_v1.gd")
const Facts = preload("res://scripts/protected_bird_facts_v1.gd")
var checks = 0
var failures = 0

func _init() -> void:
	if "--replay" in OS.get_cmdline_user_args(): replay_saved()
	else:
		run_route(false)
		run_route(true)
	var expected_checks = 17 if "--replay" in OS.get_cmdline_user_args() else 13
	if checks < expected_checks: check(false, "Required safe/harm cases did not finish their expected assertions")
	print("PROTECTED_BIRD_COMMERCIAL_ROUTES checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func guidance(sim, harm: bool) -> int:
	var pos: Vector2 = sim.cargo_position()
	var offset = 0.0
	for gate in sim.route.pilot_gates:
		if pos.x < float(gate.x) + 6.5: offset = float(gate.lane_offset); break
	if pos.x > 980.0 and pos.x < 1120.0: offset = 0.0 if harm else 7.0
	var normal = Ascent.path_tangent(pos.x, sim.route).orthogonal() * -1.0
	var body: Dictionary = sim._cargo_body()
	var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var lateral = velocity.dot(normal)
	var acceleration = float(sim.route.pilot_net_force_limit) / maxf(1.0, float(body.get("mass", 10.2)))
	var preview = lateral * (0.45 + absf(lateral) / (2.0 * acceleration * 0.9))
	var error = Ascent.path_y(pos.x, sim.route) + offset - pos.y - preview
	return int(signf(error)) * 1000 if absf(error) > 0.9 else 0

func run_route(harm: bool) -> void:
	var route = BirdProfile.route({"id": 3, "rep": 7, "weight": 2.4, "reward": 340, "required": 90.0}, "D5-A", 670371318)
	route.battery_capacity_multiplier = 1.0
	var design = Extreme.starter_design(); var launcher = Extreme.starter_launcher()
	var sim = Sim.new(); sim.configure(design, launcher, route, 670371318)
	check(sim.status == "running" and not sim.wildlife.is_empty(), "Native route configured: " + sim.wildlife_error)
	if sim.status != "running" or sim.wildlife.is_empty(): return
	var timeline = Timeline.new()
	var axis = 0; var ticks = 0; var min_clearance = INF
	var initial_energy: float = sim.total_energy()
	var checkpoints: Array = []
	var prior_phase = "waiting"
	for tick in range(6000):
		if tick % 12 == 0: axis = guidance(sim, harm)
		var command = {"axis_q": axis, "boost": false, "active": false}
		timeline.record(tick, command)
		sim.set_pilot_input(axis, false, false); sim.step(1.0 / 60.0)
		ticks = tick + 1
		if sim.wildlife.active:
			for p in sim.parts.values():
				if p.alive and not p.delivered:
					min_clearance = minf(min_clearance, sim.part_world_position(p.id).distance_to(sim.wildlife.position) - 0.43 * p.scale - float(sim.wildlife.radius))
		var phase = "harmed" if not sim.first_harm.is_empty() else ("active" if sim.wildlife.activated else "waiting")
		if phase != prior_phase:
			checkpoints.append({"phase": phase, "ticks": ticks, "result": sim.wildlife_result(), "position": [sim.cargo_position().x, sim.cargo_position().y]})
			prior_phase = phase
		if sim.status != "running": break
	var report = {"witness": "harm" if harm else "safe", "weight": 2.4, "contract_id": "D5-A", "seed": 670371318, "status": sim.status, "elapsed": sim.elapsed,
		"ticks": ticks, "physics_tick": sim.pilot_tick, "initial_energy": initial_energy, "energy_remaining": sim.total_energy(),
		"energy_used": sim.telemetry.energy_used, "station_energy": sim.telemetry.wormhole_energy_used,
		"launcher_energy": sim.telemetry.launch_energy, "integrity": sim.ship_integrity(),
		"minimum_sampled_full_craft_clearance": min_clearance if is_finite(min_clearance) else null,
		"wildlife_error": sim.wildlife_error, "wildlife_hp": sim.wildlife.hp, "wildlife_state": sim.wildlife.state,
		"activation_tick": sim.wildlife.activation_tick, "activation_fraction": sim.wildlife.activation_fraction,
		"facts": sim.wildlife_result(), "checkpoints": checkpoints}
	check(sim.status == "success", "From-rest starter delivers through full known bird route")
	check(sim.wildlife_error.is_empty() and sim.wormhole_events.size() == 1, "Exactly one finite valid portal/encounter")
	check(not sim.wildlife_result().is_empty() and sim.wildlife_result().get("harms", []).size() == (1 if harm else 0), "Expected actual harm/safe factual outcome")
	if not harm: check(sim.wildlife.hp == 8.0 and min_clearance > 0.0, "Lower corridor gives whole craft positive sampled clearance")
	check(Facts.validation_error(sim.wildlife_result(), route, sim.source_registry).is_empty(), "Full-route result validates against saved realization")
	check(sim.total_energy() >= 0.0 and sim.telemetry.energy_used <= initial_energy + sim.telemetry.wormhole_energy_used + sim.telemetry.launch_energy + 0.001, "Witness uses finite paid energy")
	var name = "harm" if harm else "safe"
	_write_evidence("user://protected_bird_v1/commercial_2_4/commercial-route-" + name + ".json", report)
	var snapshot = Replay.snapshot(route, design, launcher, 670371318, ticks, timeline.snapshot())
	_write_evidence("user://protected_bird_v1/commercial_2_4/commercial-replay-" + name + ".json", snapshot)
	print("BIRD_COMMERCIAL_ROUTE ", JSON.stringify(report))

func replay_saved() -> void:
	for name in ["safe", "harm"]:
		var path = "user://protected_bird_v1/commercial_2_4/commercial-replay-" + name + ".json"
		var snapshot_read = FixtureIO.read_json(path)
		var report_read = FixtureIO.read_json("user://protected_bird_v1/commercial_2_4/commercial-route-" + name + ".json")
		if not snapshot_read.ok or not report_read.ok:
			check(false, "Missing or unreadable freshly generated full-route witness " + name)
			print("FIXTURE_REPLAY_READ_FAILED ", [snapshot_read, report_read]); continue
		var snapshot: Dictionary = snapshot_read.data
		var report: Dictionary = report_read.data
		var replay = Replay.restore(snapshot)
		check(replay.ok, "Full saved route replays without normalization")
		if not replay.ok: print("REPLAY_ERROR ", replay); continue
		var sim = replay.simulator
		check(sim.paused and sim.status == report.status and sim.pilot_tick == int(report.physics_tick), "Terminal replay is exact and paused")
		check(BirdProfile.same_value(sim.wildlife_result(), report.facts), "Terminal replay reconstructs identical single harm/empty result")
		check(sim.total_energy() == float(report.energy_remaining) and sim.wildlife.hp == float(report.wildlife_hp), "Terminal replay HP and paid energy match")
		for checkpoint in report.checkpoints:
			var partial = snapshot.duplicate(true)
			partial.completed_command_ticks = int(checkpoint.ticks)
			partial.commands = partial.commands.filter(func(c): return int(c.tick) <= int(checkpoint.ticks))
			var resumed = Replay.restore(partial)
			check(resumed.ok, "Encounter checkpoint reconstructs")
			if not resumed.ok: continue
			check(BirdProfile.same_value(resumed.simulator.wildlife_result(), checkpoint.result), "Checkpoint harm is reconstructed once")
			var old_hp: float = resumed.simulator.wildlife.hp
			resumed.simulator.step(0.5)
			check(resumed.simulator.paused and resumed.simulator.wildlife.hp == old_hp, "Checkpoint remains paused without historical damage")

func _write_evidence(path: String, value: Variant) -> void:
	var written = FixtureIO.write_json(path, value)
	if not written.ok:
		failures += 1
		push_error("FIXTURE_EVIDENCE_WRITE_FAILED " + written.error)
