extends SceneTree
## Real main.tscn controller/save migration fixture. Run headless in an isolated
## XDG home. Input handlers are invoked synchronously, not native OS key events;
## test_pilot_input_lifecycle.gd separately covers Godot event routing.
const V1Profile = preload("res://scripts/pilot_profile.gd")
const V1Sim = preload("res://scripts/pilot_simulation.gd")
const Profile = preload("res://scripts/pilot_ascent_profile.gd")
const Sim = preload("res://scripts/pilot_ascent_simulation.gd")
const Econ = preload("res://scripts/economy.gd")
const Parts = preload("res://scripts/parts.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const EXPECTED_CHECKS = 87
var passed: int = 0
var failed: int = 0
var game

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS ", label)
	else: failed += 1; push_error("FAIL " + label)

func settle(frames: int = 4) -> void:
	for i in frames: await process_frame

func dispose() -> void:
	if is_instance_valid(game): game.queue_free(); await settle()
	game = null

func clear_save() -> void:
	for name in ["savegame.json", "savegame.backup.json", "savegame.tmp"]:
		if FileAccess.file_exists("user://" + name): DirAccess.remove_absolute("user://" + name)

func fresh(erase: bool = true) -> void:
	await dispose()
	if erase: clear_save()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); game.set_process(false)
	# Historical v2 controller fixture. New-default migration is covered separately.
	game.economy.enable_ascent_mode(); game.render()
	await settle()
	if is_instance_valid(root.gui_get_focus_owner()): root.gui_get_focus_owner().release_focus()

func saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))

func write_fixture(value: Dictionary) -> void:
	var file = FileAccess.open("user://savegame.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", true, true)); file.close()
	if FileAccess.file_exists("user://savegame.backup.json"): DirAccess.remove_absolute("user://savegame.backup.json")

func difference(a: Variant, b: Variant, path: String = "state") -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if a == b else "%s: %.17f != %.17f (f64 %s != %s)" % [path, float(a), float(b), PackedFloat64Array([float(a)]).to_byte_array().hex_encode(), PackedFloat64Array([float(b)]).to_byte_array().hex_encode()]
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return path + ": key count differs"
		for key in a:
			if not b.has(key): return path + ": missing " + str(key)
			var result = difference(a[key], b[key], path + "." + str(key))
			if not result.is_empty(): return result
		return ""
	if a is Array and b is Array:
		if a.size() != b.size(): return path + ": array size differs"
		for i in a.size():
			var result = difference(a[i], b[i], path + "[%d]" % i)
			if not result.is_empty(): return result
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]

func same(a: Variant, b: Variant, label: String) -> void:
	var result = difference(a, b)
	check(result.is_empty(), label + ("" if result.is_empty() else " | " + result))

func state(sim) -> Dictionary:
	var result: Dictionary = {"status": sim.status, "elapsed": sim.elapsed, "pilot_tick": sim.pilot_tick,
		"accumulator": sim._accumulator, "telemetry": sim.telemetry.duplicate(true),
		"bodies": sim.bodies.duplicate(true), "parts": sim.parts.values().duplicate(true),
		"launcher": sim.launcher_parts.duplicate(true), "obstacles": sim.obstacles.duplicate(true),
		"links": sim.links.duplicate(true), "effects": sim.effects.duplicate(true),
		"events": sim.events.duplicate(true), "incidents": sim.incidents.duplicate(true),
		"rng_state": sim._rng.state, "seed": sim.seed_value, "graph_dirty": sim._graph_dirty,
		"settlement_finalized": sim._settlement_finalized}
	# Only immediate held-key HUD state is neutralized by controller pause/resume.
	for key in ["pilot_axis_q", "pilot_boost", "pilot_active"]: result.telemetry.erase(key)
	return result

func neutral() -> bool:
	return game._pilot_input_state() == Timeline.neutral() and game.sim.pilot_axis_q == 0 and not game.sim.pilot_boost and not game.sim.pilot_active

func drive(command: Dictionary) -> void:
	game._clear_pilot_input()
	var keys: Array = []
	if int(command.axis_q) < 0: keys.append(KEY_W)
	elif int(command.axis_q) > 0: keys.append(KEY_S)
	if command.boost: keys.append(KEY_SHIFT)
	if command.active: keys.append(KEY_SPACE)
	for code in keys:
		var event = InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = true
		game._unhandled_key_input(event)

func accept_first(label: String) -> void:
	var available: Array = game.economy.available_contracts()
	check(not available.is_empty() and game.economy.accept_contract(str(available[0].contract_id)).ok, label)
	# This fixture targets replay/physics; acceptance UI has its own input suite.
	var cid:String=game.economy.active_contract_id
	game.economy.mark_story_seen(cid,cid+"/accept")

func labels_contain(text: String) -> bool:
	for node in game.hud.content.find_children("*", "Label", true, false):
		if node.text.contains(text): return true
	return false

func test_frozen_sources() -> void:
	# Baselines from the pre-ascent commit. A v2 edit must never change old replay code.
	var hashes = {
		"simulation.gd": "582e188f09949cb969a4f0a73dbd97d58f2df38ec17f76568eb229ecfecf369e",
		"pilot_simulation.gd": "81b7d5bdb4514663d3d89c0ae7cf7a510344d53cecfcf05f205ae97af727acd6",
		"pilot_profile.gd": "41031fc568aa5aa2c37c023b5b162ff9f24dd3db97e2fd6dec14dadb207132dd"}
	for name in hashes: check(FileAccess.get_sha256("res://scripts/" + name) == hashes[name], name + " remains byte-identical to pre-ascent replay baseline")

func test_profile_json() -> void:
	# A single ULP in a generated obstacle used to escape earlier replay fixtures.
	# Compare the full route, including later gates and raw hazard coordinates.
	var route: Dictionary = Profile.route()
	var roundtrip = route.duplicate(true)
	for i in 16: roundtrip = JSON.parse_string(JSON.stringify(roundtrip, "", true, true))
	same(route, roundtrip, "complete v2 profile retains exact numbers through 16 full-precision JSON round trips")

func test_v1_migration() -> void:
	await dispose(); clear_save()
	# Genuine v1 fixture: construct v1 routes and run the original simulator. Never
	# create a v2 dispatch and relabel it, which would leave v2 tuning in the save.
	var old = Econ.new(); old.enable_pilot_mode()
	var craft: Array = V1Profile.starter_design(); var pad: Array = V1Profile.starter_launcher()
	craft[3].param = 9.0; craft[3].input_a = V1Profile.COCKPIT_SIGNAL
	old.starter_stock(craft, pad)
	var id: String = str(old.available_contracts()[0].contract_id)
	check(old.accept_contract(id).ok and old.begin_dispatch(craft, pad).ok, "historical fixture commits a genuine pilot-v1 dispatch")
	var route: Dictionary = old.in_flight.route.duplicate(true); route.seed = old.in_flight.seed
	var original = V1Sim.new(); original.configure(craft, pad, route, int(route.seed))
	var timeline = Timeline.new()
	var commands: Array = [
		{"tick": 0, "axis_q": 0, "boost": false, "active": false},
		{"tick": 8, "axis_q": -1000, "boost": true, "active": true},
		{"tick": 29, "axis_q": 1000, "boost": true, "active": false},
		{"tick": 51, "axis_q": 0, "boost": false, "active": true},
		{"tick": 77, "axis_q": -1000, "boost": false, "active": true}]
	check(timeline.restore(commands, 96), "historical fixture has a valid nontrivial sparse timeline")
	for tick in 96:
		var command = timeline.state_at(tick)
		original.set_pilot_input(command.axis_q, command.boost, command.active); original.step(1.0 / 60.0)
	check(original.status == "running" and original.pilot_tick == 192 and original.telemetry.energy_used > 20.0, "historical fixture is genuinely in flight with paid thrust at 96 completed ticks")
	old.in_flight.ticks = 96; old.in_flight.elapsed = original.elapsed; old.in_flight.input_commands = timeline.snapshot()
	check(old.save_state(craft, pad, {"reduced_motion": true}), "historical v1 dispatch serializes through the real save API")
	var disk: Dictionary = saved(); var expected = state(original)
	check(disk.flight_mode == "pilot-v1" and disk.in_flight.control_version == "pilot-v1" and disk.in_flight.route.pilot_profile == "pilot-v1", "v1 disk fixture has genuine version and profile markers")
	check(float(disk.in_flight.route.distance) == 128.0 and not disk.in_flight.route.has("pilot_battery_multiplier") and not disk.in_flight.route.has("pilot_energy_tariff"), "v1 disk fixture contains original route and no v2 capacity/tariff fields")
	await fresh(false)
	check(game.economy.flight_mode == "pilot-v2" and game.page == "flight" and not game.pilot_resume_blocked, "explicit v2 fixture migrates future orders while resuming the old in-flight dispatch")
	check(game.sim.get_script() == V1Sim and game.flight_order.control_version == "pilot-v1", "genuine v1 dispatch selects the frozen original simulator")
	check(game.paused and neutral() and game.pilot_completed_ticks == 96, "v1 restore pauses with neutral held keys at the exact completed tick")
	same(state(game.sim), expected, "v1 JSON reconstruction is exact across bodies, parts, pad, energy, HP, hazards, RNG and telemetry")
	same(game.pilot_timeline.snapshot(), commands, "v1 restore preserves every sparse command boundary")
	same(game.economy.in_flight, disk.in_flight, "_ready migration does not rewrite the committed v1 snapshot")
	same(game.design, craft, "_ready preserves custom v1 workshop layout, thrust tuning and cockpit wire")
	same(game.launcher, pad, "_ready preserves the historical launcher")
	check(game.sim.parts[3].capacity == 300.0 and game.sim.route.distance == 128.0, "v1 replay retains original 300 J cells and 128 m route")
	check(game.economy.active_contract().control_version == "pilot-v1" and game.economy.available_contracts()[0].control_version == "pilot-v2", "migration leaves in-flight contract v1 and converts only future available orders")
	check(game.economy.estimate_delivery(game.economy.active_contract(), {"energy_used": 1000.0}, 1.0, false).energy == 180, "old in-flight settlement retains 0.18 credits/J after global mode migration")
	original.set_pilot_input(0, false, false); original.step(1.0 / 60.0)
	game._set_paused(false); game._step_flight()
	same(state(game.sim), state(original), "first resumed v1 tick is exactly the original simulator's neutral continuation")
	game.abort_flight()
	check(game.report.energy_tariff == .18 and game.report.energy == ceili(float(game.sim.telemetry.energy_used) * .18), "v1 controller settlement uses original tariff and actual energy")
	check(game.economy.jobs_today == 1 and game.economy.settled_ids.has(id), "migrated v1 dispatch settles its original ID once")
	accept_first("a new available order can be accepted after v1 settlement")
	game.start_flight(false)
	check(game.sim.get_script() == Sim and game.flight_order.control_version == "pilot-v2" and neutral(), "same controller starts the next accepted formal order in v2")
	check(game.sim.parts[3].capacity == 6000.0 and game.flight_order.pilot_energy_tariff == .025, "next order uses v2 capacity and tariff without rewriting old craft tuning")
	same(game.design, craft, "legacy-to-v2 transition never replaces the player's customized assembly")
	check(saved().in_flight.control_version == "pilot-v2" and saved().in_flight.route.pilot_profile == "pilot-v2", "next formal dispatch persists the v2 protocol and profile")
	game.abort_flight(); await dispose()

func test_workshop_capacity() -> void:
	await fresh()
	game.navigate("workshop"); game.selected_id = 3; game.render(); await settle()
	check(game.economy.flight_mode == "pilot-v2" and game.hud.state.control_version == "pilot-v2", "historical fixture and workshop explicitly select the ascent protocol")
	check(Parts.catalog().battery.energy == 300.0 and game.catalog.battery.energy == 300.0, "global parts database retains the original 300 J battery specification")
	check(game.hud.state.catalog.battery.energy == 6000.0 and game.hud.state.selectedpart.spec.energy == 6000.0, "v2 workshop catalog and selected battery expose 20 x 300 = 6000 J")
	check(game.hud.state.ship_stats.energy == 6000.0 and labels_contain("储能 6000 J"), "actual craft energy and visible workshop summary agree at 6000 J")
	check(str(game.hud.state.selectedpart.default_behavior).contains("电芯容量 6000 J") and labels_contain("电芯容量 6000 J"), "selected battery's rendered inspector states its actual 6000 J capacity")
	accept_first("capacity fixture accepts a default v2 order")
	game.render(); game.hud._act("dispatch", null)
	check(game.hud.dispatch_confirmation_open and game.hud.state.energy_tariff == .025 and labels_contain("能源 ¥0.025 / J"), "rendered v2 dispatch confirmation quotes the same 0.025 credits/J as settlement")
	game.hud._dismiss_dispatch()
	var money: int = game.economy.credits
	game.start_flight(true)
	check(game.sim.parts[3].capacity == 6000.0 and game.sim.parts[3].energy == 6000.0 and game.sim.telemetry.battery_capacity == 6000.0, "default flight physically starts with the same 6000 J craft cell advertised in workshop")
	check(game.sim.launcher_parts[1].capacity == 6000.0 and game.sim.launcher_parts[1].energy < 6000.0, "ground cell also has finite v2 capacity and actually pays the launcher charge")
	check(game.flight_order.pilot_energy_tariff == .025 and game.economy.estimate_delivery(game.flight_order, {"energy_used": 1000.0}, 1.0, false).energy == 25, "default v2 route prices actual joules at 0.025 credits/J")
	game.abort_flight()
	check(game.economy.credits == money and game.economy.jobs_today == 0 and game.economy.in_flight.is_empty(), "capacity trial launch and abort charge no money or daily dispatch")
	check(game.economy.cancel_accepted().ok and game.economy.close_day().ok, "capacity fixture finishes its accepted order before night research")
	var cost: int = game.economy.research_cost()
	game._action("upgrade", null)
	check(game.economy.research == 1 and game.economy.credits == money - cost, "controller purchases one real 15 percent research upgrade for its exact cost")
	game.navigate("workshop"); game.selected_id = 3; game.render(); await settle()
	check(is_equal_approx(game.hud.state.ship_stats.energy, 6900.0) and labels_contain("储能 6900 J"), "research adds 15 percent to the actual v2 workshop energy total")
	check(str(game.hud.state.selectedpart.default_behavior).contains("电芯容量 6900 J") and labels_contain("电芯容量 6900 J"), "selected battery inspector renders research-adjusted 6900 J")
	check(game.hud.state.catalog.battery.energy == 6000.0 and Parts.catalog().battery.energy == 300.0, "research does not repeatedly multiply catalog or frozen base specifications")
	check(game.economy.next_day().ok, "research fixture advances to the next dispatch day")
	accept_first("research fixture accepts a next-day v2 order")
	game.start_flight(true)
	check(is_equal_approx(game.sim.parts[3].capacity, 6900.0) and is_equal_approx(game.sim.parts[3].energy, 6900.0) and is_equal_approx(game.sim.telemetry.battery_capacity, 6900.0), "research-adjusted simulation starts with exactly the capacity shown in workshop")
	check(is_equal_approx(game.flight_order.battery_capacity_multiplier, 1.15) and game.flight_order.pilot_battery_multiplier == 20.0, "route snapshots station research separately from versioned 20x cell scaling")
	game.abort_flight(); await dispose()

func guidance(sim) -> int:
	# Test-only observer: changes held keyboard commands, never physics state.
	var pos: Vector2 = sim.cargo_position(); var offset = 0.0
	for gate in sim.route.get("pilot_gates", []):
		if pos.x < float(gate.x) + 6.5: offset = float(gate.lane_offset); break
	var normal = Profile.path_tangent(pos.x, sim.route).orthogonal() * -1.0
	var body: Dictionary = sim._cargo_body()
	var lateral_speed = Vector2(body.get("velocity", Vector2.ZERO)).dot(normal)
	var acceleration = float(sim.route.get("pilot_net_force_limit", 30.0)) / maxf(1.0, float(body.get("mass", 10.2)))
	var preview = lateral_speed * (.45 + absf(lateral_speed) / (2.0 * acceleration * .9))
	var error = Profile.path_y(pos.x, sim.route) + offset - pos.y - preview
	return int(signf(error)) * 1000 if absf(error) > .9 else 0

func test_v2_snapshot_and_settlement() -> void:
	await fresh(); accept_first("replay fixture accepts a fresh v2 order")
	# Nondefault persisted values catch regeneration from current profile defaults.
	var order: Dictionary = game.economy.active_contract()
	order.distance = 543.0; order.pilot_energy_tariff = .03125; order.lookahead_seconds = 4.0
	game.render(); game.hud._act("dispatch", null)
	check(game.hud.dispatch_confirmation_open and game.hud.state.energy_tariff == .03125 and labels_contain("能源 ¥0.03125 / J"), "rendered dispatch confirmation preserves a saved nondefault tariff")
	game.hud._dismiss_dispatch()
	var id: String = str(order.contract_id); var money: int = game.economy.credits
	game.start_flight(true)
	var trial_route: Dictionary = game.flight_order.duplicate(true)
	var trial_start = state(game.sim); var held_axis = 0
	for tick in 4200:
		if game.sim.status != "running": break
		if tick % 12 == 0: held_axis = guidance(game.sim)
		drive({"axis_q": held_axis, "boost": false, "active": tick >= 120 and tick < 180})
		game._step_flight()
	var total_ticks: int = game.pilot_completed_ticks
	var commands: Array = game.pilot_timeline.snapshot()
	var trial_end: Dictionary = state(game.sim)
	check(game.sim.status == "success" and total_ticks > 1000 and total_ticks < 4200, "trial completes a real upward delivery using controller-driven keyboard states")
	check(commands.size() > 10 and trial_end.telemetry.energy_used > 1000 and -game.sim.cargo_position().y > 140.0, "trial records meaningful steering, actual energy consumption and real altitude gain")
	check(game.economy.credits == money and game.economy.in_flight.is_empty() and game.economy.active_contract().status == "accepted", "successful trial physics never creates a debit or committed dispatch")
	game.finish_flight()
	var trial_report: Dictionary = game.report.duplicate(true)
	check(trial_report.success and trial_report.trial and game.economy.credits == money and game.economy.jobs_today == 0 and game.economy.settled_ids.is_empty(), "successful trial report remains free and consumes no formal settlement ID")
	check(game.economy.last_trials.has(id) and saved().last_trials.has(id), "trial result is persisted without settling the contract")
	game.start_flight(false)
	check(game.page == "flight" and not game.trial and game.economy.credits == money, "formal launch follows the trial without an up-front debit")
	var formal_route: Dictionary = game.flight_order.duplicate(true)
	var comparable_trial = trial_route.duplicate(true); var comparable_formal = formal_route.duplicate(true)
	comparable_trial.erase("status"); comparable_formal.erase("status")
	same(comparable_formal, comparable_trial, "trial and formal use identical route, profile, research, tariff and seed")
	same(state(game.sim), trial_start, "trial and formal start from exactly identical physical state")
	var launch: Dictionary = saved().in_flight
	check(launch.control_version == "pilot-v2" and launch.route.control_version == "pilot-v2" and launch.route.pilot_profile == "pilot-v2", "formal disk snapshot preserves all v2 identity markers")
	check(launch.route.distance == 543.0 and launch.route.pilot_energy_tariff == .03125 and launch.route.lookahead_seconds == 4.0 and launch.route.pilot_battery_multiplier == 20.0, "formal disk snapshot preserves custom route/tariff and versioned battery settings")
	check(int(launch.ticks) == 0 and launch.input_commands == JSON.parse_string(JSON.stringify([{"tick": 0, "axis_q": 0, "boost": false, "active": false}])), "formal launch persists its neutral command before the first physics tick")
	var replay = Timeline.new(); check(replay.restore(commands, total_ticks), "full successful trial command history is replayable")
	for tick in 137: drive(replay.state_at(tick)); game._step_flight()
	var expected: Dictionary = state(game.sim)
	game._on_focus_exited()
	var checkpoint: Dictionary = saved().in_flight
	check(int(checkpoint.ticks) == 137 and game.paused and neutral(), "focus checkpoint saves exactly 137 completed v2 ticks and clears held keys")
	same(checkpoint.route, launch.route, "checkpoint retains original dispatch route/profile/tariff without regeneration")
	await fresh(false)
	check(game.sim.get_script() == Sim and game.paused and neutral() and game.pilot_completed_ticks == 137 and not game.pilot_resume_blocked, "v2 save resumes in the correct simulator at its exact paused tick")
	same(state(game.sim), expected, "custom v2 JSON checkpoint exactly reconstructs physical and accounting state")
	same(game.economy.in_flight, checkpoint, "v2 _ready migration preserves the complete committed checkpoint")
	same(game.flight_order, formal_route, "v2 restored flight retains original route, profile, tariff and random seed")
	check(game.economy.active_contract().pilot_energy_tariff == .03125 and game.sim.route.distance == 543.0 and game.sim.route.lookahead_seconds == 4.0, "restore retains nondefault saved billing and flight parameters")
	game._set_paused(false)
	for tick in range(137, total_ticks):
		if game.sim.status != "running": break
		drive(replay.state_at(tick)); game._step_flight()
	check(game.sim.status == "success" and game.pilot_completed_ticks == total_ticks, "resumed formal dispatch succeeds on exactly the same final command tick as trial")
	same(state(game.sim), trial_end, "identical input yields exact trial/formal terminal physics after a real disk restart")
	same(game.pilot_timeline.snapshot(), commands, "resumed formal dispatch retains the complete identical successful input timeline")
	game.finish_flight()
	var after: int = game.economy.credits
	check(game.report.success and not game.report.trial and game.economy.jobs_today == 1 and game.economy.deliveries == 1, "controller records one successful formal delivery")
	check(game.report.energy_tariff == .03125 and game.report.energy == ceili(float(trial_end.telemetry.energy_used) * .03125), "formal settlement charges actual identical joules at the preserved custom tariff")
	check(after == money + int(game.report.profit) and game.report.profit == trial_report.estimated_profit, "formal credit delta exactly matches trial estimate and settled net profit")
	check(game.economy.in_flight.is_empty() and saved().in_flight.is_empty() and game.economy.settled_ids.has(id), "settlement atomically persists a unique ID and clears the completed checkpoint")
	var history: Array = game.economy.history.duplicate(true)
	game.finish_flight()
	var duplicate: Dictionary = game.economy.settle_contract(id, game.sim.telemetry, game.sim.elapsed, true)
	check(duplicate.get("duplicate", false) and game.economy.credits == after and game.economy.jobs_today == 1 and game.economy.deliveries == 1, "duplicate finish and duplicate settlement cannot add money or delivery counts")
	same(game.economy.history, history, "duplicate settlement cannot add another report to history")
	await fresh(false)
	check(game.page == "hub" and game.economy.in_flight.is_empty() and game.economy.credits == after and game.economy.jobs_today == 1, "settled v2 run reloads with the same money/count and no dispatch resurrection")
	check(game.economy.settled_ids.has(id) and game.economy.last_settlement.energy_tariff == .03125, "unique settlement ID and original tariff survive final reload")
	duplicate = game.economy.settle_contract(id, trial_end.telemetry, trial_end.elapsed, true)
	check(duplicate.get("duplicate", false) and game.economy.credits == after, "duplicate settlement remains blocked after a disk restart")
	print("ASCENT_CONTROLLER_DELIVERY ticks=%d commands=%d joules=%.9f tariff=%.5f profit=%d" % [total_ticks, commands.size(), trial_end.telemetry.energy_used, .03125, game.economy.last_settlement.profit])
	await dispose()

func test_conflicting_version() -> void:
	await fresh(); accept_first("version-conflict fixture accepts a v2 order")
	game.start_flight(false); game._step_flight(); game.save_game()
	var valid: Dictionary = saved()
	await dispose()
	var consistent = valid.duplicate(true)
	consistent.in_flight.simulation_version = "pilot-v2"
	write_fixture(consistent); await fresh(false)
	check(not game.pilot_resume_blocked and game.sim.get_script() == Sim, "matching optional simulation_version alias remains readable")
	await dispose()
	var conflict = valid.duplicate(true)
	conflict.in_flight.simulation_version = "pilot-v1"
	write_fixture(conflict)
	var original_bytes = FileAccess.get_file_as_bytes("user://savegame.json")
	await fresh(false)
	check(game.pilot_resume_blocked, "supported but conflicting v1 simulation/v2 control markers fail closed")
	var money: int = game.economy.credits; var jobs: int = game.economy.jobs_today
	game._set_paused(false); game._process(2.0); game.abort_flight()
	check(not game.save_game() and FileAccess.get_file_as_bytes("user://savegame.json") == original_bytes, "conflicting supported-version snapshot keeps exact original disk bytes")
	check(game.economy.credits == money and game.economy.jobs_today == jobs and not game.economy.in_flight.is_empty(), "conflicting supported-version snapshot cannot advance or settle the dispatch")
	await dispose()

func run() -> void:
	root.size = Vector2i(1280, 800)
	test_frozen_sources()
	test_profile_json()
	await test_v1_migration()
	await test_workshop_capacity()
	await test_v2_snapshot_and_settlement()
	await test_conflicting_version()
	await dispose()
	if passed + failed != EXPECTED_CHECKS: check(false, "every planned ascent-controller assertion ran: expected %d, saw %d" % [EXPECTED_CHECKS, passed + failed])
	print("ASCENT_CONTROLLER passed=%d failed=%d native_input=false" % [passed, failed])
	quit(1 if failed else 0)
