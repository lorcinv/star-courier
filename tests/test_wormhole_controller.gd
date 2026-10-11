extends SceneTree
## Production main.tscn integration with synthetic Godot/controller key input.
## Headless only: no native input, human-playability, rendered-art or hardware-FPS claim.
## Prior progression receipts are explicitly synthetic; both v4 deliveries use
## the real solver, unmodified commercial weights and a test-only steering guide.
const Profile = preload("res://scripts/pilot_wormhole_profile.gd")
const Sim = preload("res://scripts/pilot_wormhole_simulation.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const V3Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const V2Sim = preload("res://scripts/pilot_ascent_simulation.gd")
const Pilot = preload("res://scripts/pilot_profile.gd")
const V1Sim = preload("res://scripts/pilot_simulation.gd")
const Econ = preload("res://scripts/economy.gd")
const Stories = preload("res://scripts/courier_stories.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const EXPECTED_CHECKS = 238
var passed: int = 0
var failed: int = 0
var game
var measurements: Array = []

func _initialize() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("This save-writing fixture requires an isolated XDG_DATA_HOME."); quit(2); return
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1; print("PASS ", label)
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
	# Unknown/missing/conflicting persisted protocols now stop before the normal
	# scene exists. Do not turn that deliberate recovery-only boot into a Nil call.
	if is_instance_valid(game.world):
		game.world.set_process(false)
		game.world.assembly_feedback.set_process(false)
	await settle()
	if is_instance_valid(root.gui_get_focus_owner()): root.gui_get_focus_owner().release_focus()

func recovery_only() -> bool:
	return game.economy.review_load_blocked and game.world == null and game.hud == null and game.sim == null and game.courier_input == null and game.get_child_count() == 1 and game.get_child(0) is Label and not game.is_processing_input() and not game.is_processing_unhandled_key_input()

func saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))

func write_fixture(data: Dictionary) -> void:
	var file = FileAccess.open("user://savegame.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true)); file.close()
	if FileAccess.file_exists("user://savegame.backup.json"): DirAccess.remove_absolute("user://savegame.backup.json")

func difference(a: Variant, b: Variant, path: String = "state") -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if a == b else "%s: %.17f != %.17f (f64 %s != %s)" % [path, float(a), float(b), PackedFloat64Array([float(a)]).to_byte_array().hex_encode(), PackedFloat64Array([float(b)]).to_byte_array().hex_encode()]
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return path + ": key count differs"
		for k in a:
			if not b.has(k): return path + ": missing " + str(k)
			var result = difference(a[k], b[k], path + "." + str(k))
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
	var error = difference(a, b)
	check(error.is_empty(), label + ("" if error.is_empty() else " | " + error))

func state(sim) -> Dictionary:
	# Capture every script variable, including inherited CCD/circuit caches, RNG,
	# portal visits, attempted/denied anchors, component graph and station reserve.
	var result: Dictionary = {}
	for property in sim.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var name: String = property.name
		if name in ["pilot_axis_q", "pilot_boost", "pilot_active"]: continue
		var value: Variant = sim.get(name)
		if value is RandomNumberGenerator: result[name] = {"seed": value.seed, "state": value.state}
		elif value is Dictionary or value is Array: result[name] = value.duplicate(true)
		else: result[name] = value
	# Only immediate held-key feedback is intentionally neutralized on resume.
	for k in ["pilot_axis_q", "pilot_boost", "pilot_active", "overdrive"]: result.telemetry.erase(k)
	# Accepted versus committed is commercial metadata, never physical state.
	result.route.erase("status")
	return result

func ledger() -> Dictionary:
	return {"credits": game.economy.credits, "reputation": game.economy.reputation,
		"jobs": game.economy.jobs_today, "deliveries": game.economy.deliveries,
		"inventory": game.economy.inventory.duplicate(true), "settled": game.economy.settled_ids.duplicate(true),
		"history": game.economy.history.duplicate(true), "story": game.economy.story_state.duplicate(true)}

func key(code: int, pressed: bool = true, routed: bool = false) -> void:
	var event = InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	if routed: Input.parse_input_event(event)
	elif pressed: game._unhandled_key_input(event)
	else: game._input(event)

func drive(command: Dictionary) -> void:
	game._clear_pilot_input()
	if int(command.axis_q) < 0: key(KEY_W)
	elif int(command.axis_q) > 0: key(KEY_S)
	if command.boost: key(KEY_SHIFT)
	if command.active: key(KEY_SPACE)

func neutral() -> bool:
	return game._pilot_input_state() == Timeline.neutral() and game.sim.pilot_axis_q == 0 and not game.sim.pilot_boost and not game.sim.pilot_active

func labels_contain(text: String) -> bool:
	for node in game.hud.content.find_children("*", "Label", true, false):
		if node.text.contains(text): return true
	return false

func conversation_text(data: Dictionary) -> String:
	var result: String = str(data.get("title", "")) + " " + str(data.get("route_hint", ""))
	for line in data.get("lines", []): result += " " + str(line.text)
	return result

func accept(id: String) -> void:
	check(game.economy.accept_contract(id).ok, "real economy accepts " + id)
	game.economy.mark_story_seen(id, id + "/accept")
	game.render()
	# Complete the existing loading scene via its real skip action.
	game._action("skip_loading_scene", null)

func unlock_day_three() -> void:
	# Economy-only setup for the first four jobs. Never reported as flight evidence.
	for day in [1, 2]:
		for order in game.economy.contracts.duplicate(true):
			var id: String = order.contract_id
			var accepted: bool = game.economy.accept_contract(id).ok
			game.economy.mark_story_seen(id, id + "/accept"); game.economy.mark_cargo_loaded(id)
			var launched: bool = game.economy.begin_dispatch(game.design, game.launcher).ok
			var result: Dictionary = game.economy.settle_contract(id, {"integrity": 1.0, "energy_used": 0.0}, 22.0, true)
			game.economy.mark_story_seen(id, id + "/result"); game.economy.mark_story_seen(id, id + "/return")
			check(accepted and launched and result.ok, "synthetic prior-progress receipt " + id)
		check(game.economy.close_day().ok and game.economy.next_day().ok, "synthetic progression closes day %d" % day)
	check(game.economy.day == 3 and game.economy.reputation == 8 and game.economy.contracts[1].contract_id == "D3-B", "four synthetic prior receipts expose the real day-three offer")
	var order: Dictionary = game.economy.contracts[1]
	check(order.control_version == Profile.CONTROL_VERSION and order.route_profile == Profile.ROUTE_PROFILE and order.weight == 3.72 and order.reward == 395 and order.deadline == 75.0, "first real wormhole offer is canonical heavy 3.72, 395 credits and 75 seconds")
	accept("D3-B")

func authored_standard() -> void:
	# A newly authored day-four boundary selects route three as its standard offer.
	# Advance the real empty business days so the next-day review watermark also
	# advances. Directly editing only `day` creates an invalid saved ledger now.
	var advanced: bool = true
	while game.economy.day < 4 and advanced:
		advanced = game.economy.close_day().ok and game.economy.next_day().ok
	game.economy.reputation = 8; game.economy.contracts = []
	game.economy.ensure_contracts()
	var order: Dictionary = game.economy.contracts[0]
	check(advanced and order.contract_id == "D4-A" and order.control_version == Profile.CONTROL_VERSION and order.weight == 2.4 and order.reward == 340 and order.deadline == 72.0, "real authoring boundary exposes standard 2.4, 340 credits and 72 seconds")
	accept("D4-A")

func test_frozen_sources() -> void:
	var hashes = {
		"simulation.gd": "582e188f09949cb969a4f0a73dbd97d58f2df38ec17f76568eb229ecfecf369e",
		"pilot_simulation.gd": "81b7d5bdb4514663d3d89c0ae7cf7a510344d53cecfcf05f205ae97af727acd6",
		"pilot_profile.gd": "41031fc568aa5aa2c37c023b5b162ff9f24dd3db97e2fd6dec14dadb207132dd",
		"parts.gd": "1a92c0202b022e3090d50097145743cd65e3d002b9b5b20bd187f1faa1321b2b",
		"pilot_ascent_profile.gd": "a8235b741aeddbad5442856a87115a1bf069d3f1b81d1e0ba063fdcd8183f004",
		"pilot_ascent_simulation.gd": "ff2eb35b770f17eeaecd78ae302dc134e6e9260260a37022b6e198e046ae4d87",
		"pilot_extreme_profile.gd": "9bf3a7ed3f1d01300272cae7caa80ac20e2c1fe69e78c44cbc6129c953a51184",
		"pilot_extreme_simulation.gd": "28fc509a2c88fd3e3f89b78ab454e42128bd4b0b6e5118feb6971f74a377b266"}
	for name in hashes: check(FileAccess.get_sha256("res://scripts/" + name) == hashes[name], "frozen replay source remains byte-identical: " + name)

func test_preflight_and_protocol() -> void:
	await fresh(); unlock_day_three()
	game.navigate("workshop"); game.selected_id = 3; game.render(); await settle()
	check(game.economy.flight_mode == "pilot-v3" and game.hud.state.control_version == Profile.CONTROL_VERSION, "active order selects v4 presentation while future workshop default stays v3")
	check(game.hud._pilot_mode() and game.hud._ascent_mode() and game.hud._extreme_mode() and game.hud._wormhole_mode(), "v4 HUD selects the complete paid pilot/ascent/extreme control protocol")
	check(game.hud.state.catalog.battery.energy == 6000.0 and game.hud.state.ship_stats.energy == 6000.0 and labels_contain("电芯容量 6000 J"), "v4 workshop shows real 6000 J onboard battery capacity")
	var route: Dictionary = game.economy.trial_route()
	var quote: Dictionary = game.hud.state.wormhole_preflight
	check(quote.ok and quote.energy_source == "station" and not quote.separate_settlement_debit and is_equal_approx(quote.estimated_j, 61.72), "heavy starting-island quote declares external 61.72 J included in the one energy bill")
	check(quote.station_capacity_j == 2000.0 and quote.max_centered_body_diameter_m == 25.75 and is_equal_approx(quote.estimated_credits, 61.72 * .025), "station capacity, net aperture and saved tariff agree with authored route")
	game.hud._act("dispatch", null)
	check(game.hud.dispatch_confirmation_open and labels_contain("预计通行 61.7 J") and labels_contain("驿站储能 2.00 kJ") and labels_contain("能源 ¥0.025 / J"), "actual dispatch confirmation discloses station estimate and real combined-bill tariff")
	game.hud._dismiss_dispatch(); game._action("trial", null)
	check(game.sim.get_script() == Sim and game._is_pilot_flight() and game.hud._wormhole_mode(), "actual trial action selects the v4 simulator, input recorder and HUD")
	check(game.sim.parts[3].capacity == 6000.0 and game.sim.telemetry.battery_capacity == 6000.0 and game.sim._station_remaining == 2000.0, "configured solver separates real onboard capacity from finite station reserve")
	var initial: Dictionary = state(game.sim)
	check(initial.size() == 47 and initial.has("_motion_parts") and initial.has("_attempted_anchors") and initial.has("_rng"), "exact replay snapshot covers all inherited and portal runtime state")
	var normal: Array = game.design.duplicate(true)
	var connected: Array = normal.duplicate(true); connected.append(Extreme.part(80, "drill", 2, 0))
	var disconnected: Array = connected.duplicate(true)
	disconnected.append(Extreme.part(81, "battery", 10, 0)); disconnected.append(Extreme.part(82, "beam", 11, 0)); disconnected.append(Extreme.part(83, "shield", 17, 5))
	var wide: Array = normal.duplicate(true)
	for x in range(2, 23): wide.append(Extreme.part(90 + x, "beam", x, 0))
	for fixture in [{"name": "connected drill", "design": connected, "count": 1}, {"name": "three disconnected islands", "design": disconnected, "count": 3}, {"name": "oversized connected hull", "design": wide, "count": 1}]:
		game.design = fixture.design.duplicate(true)
		var before: Dictionary = {"ledger": ledger(), "design": game.design.duplicate(true), "launcher": game.launcher.duplicate(true), "route": route.duplicate(true), "sim": state(game.sim)}
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://savegame.json")
		var measured: Dictionary = game._wormhole_preflight(route)
		var real = Sim.new(); real.configure(game.design, game.launcher, route, int(route.seed))
		var bound: float = 0.0
		for body in real.bodies: bound = maxf(bound, 2.0 * real._body_bound(body))
		check(measured.estimated_bodies == real.bodies.size() and real.bodies.size() == fixture.count, fixture.name + ": quote counts actual solver adjacency islands")
		check(is_equal_approx(measured.estimated_j, float(route.wormhole_portal.base_energy_j) * real.bodies.size() + float(route.wormhole_portal.energy_j_per_kg) * real.total_mass()), fixture.name + ": quote uses real cargo-weighted solver mass")
		# Solver Vector2 geometry uses single precision; replay below is exact.
		check(absf(measured.starting_body_diameter_m - bound) < .00002 and measured.fits_starting_outline == (bound <= 25.75), fixture.name + ": quote matches complete COM-centered solver hull including drill tip")
		same({"ledger": ledger(), "design": game.design, "launcher": game.launcher, "route": route, "sim": state(game.sim)}, before, fixture.name + ": quote has no physical, graph, route, story or economic side effects")
		check(FileAccess.get_file_as_bytes("user://savegame.json") == bytes, fixture.name + ": quote does not write the save")
	game.design = normal
	await dispose()

func test_old_accepted_presentation() -> void:
	for spec in [{"profile": Pilot, "sim": V1Sim, "method": "enable_pilot_mode", "version": "pilot-v1", "capacity": 300.0}, {"profile": Ascent, "sim": V2Sim, "method": "enable_ascent_mode", "version": "pilot-v2", "capacity": 6000.0}, {"profile": Extreme, "sim": V3Sim, "method": "enable_extreme_mode", "version": "pilot-v3", "capacity": 6000.0}]:
		await dispose(); clear_save()
		var old = Econ.new(); old.call(spec.method)
		var craft: Array = spec.profile.starter_design(); var pad: Array = spec.profile.starter_launcher()
		old.starter_stock(craft, pad); old.story_state = Stories.initial_state(7421); old.enable_story_mode()
		var id: String = old.available_contracts()[0].contract_id
		check(old.accept_contract(id).ok, "genuine old accepted fixture " + spec.version)
		old.mark_story_seen(id, id + "/accept"); old.mark_cargo_loaded(id)
		var accepted: Dictionary = old.active_contract().duplicate(true)
		check(old.save_state(craft, pad, {"reduced_motion": true}), "old accepted route saves before any launch " + spec.version)
		await fresh(false)
		same(game.economy.active_contract(), accepted, "bootstrap preserves complete accepted historical order " + spec.version)
		game.navigate("workshop"); game.selected_id = 3; game.render(); await settle()
		check(game.economy.flight_mode == "pilot-v3" and game.hud.state.control_version == spec.version and game.hud.state.catalog.battery.energy == spec.capacity and game.hud.state.ship_stats.energy == spec.capacity, "old accepted workshop retains its own battery and controls " + spec.version)
		check(game.hud._ascent_mode() == (spec.version != "pilot-v1") and game.hud._extreme_mode() == (spec.version == "pilot-v3") and not game.hud._wormhole_mode() and game.hud.state.wormhole_preflight.is_empty(), "old accepted HUD never inherits v4 or a station quote " + spec.version)
		game._action("trial", null)
		check(game.sim.get_script() == spec.sim and game.sim.parts[3].capacity == spec.capacity, "first launch of accepted old order selects frozen simulator " + spec.version)
		check(game.hud.flight_labels.controls.text.contains("全功率" if spec.version == "pilot-v3" else "冲刺"), "old saved controls preserve boost/overdrive semantics " + spec.version)
		var original = spec.sim.new(); original.configure(craft, pad, game.flight_order, int(game.flight_order.seed))
		for tick in 37:
			var command: Dictionary = {"axis_q": -1000 if tick >= 9 and tick < 19 else 0, "boost": tick < 25, "active": tick >= 28}
			drive(command); game._step_flight(); original.set_pilot_input(command.axis_q, command.boost, command.active); original.step(1.0 / 60.0)
		same(state(game.sim), state(original), "v4-aware controller reproduces genuine old solver state exactly " + spec.version)
		game.abort_flight()
		check(game.economy.jobs_today == 0 and game.economy.in_flight.is_empty(), "old accepted trial remains free " + spec.version)
	await dispose()

func test_input_lifecycle() -> void:
	await fresh(); authored_standard(); game._action("dispatch", null)
	for code in [KEY_W, KEY_SHIFT, KEY_SPACE]: key(code, true, true)
	await settle(1); game._step_flight()
	check(game._pilot_input_state() == {"axis_q": -1000, "boost": true, "active": true} and game.sim.pilot_axis_q == -1000 and game.sim.pilot_boost and game.sim.pilot_active, "synthetic Godot event routing delivers all three held v4 commands")
	check(game.pilot_timeline.snapshot()[0].boost and game.pilot_timeline.snapshot()[0].active and game.pilot_completed_ticks == 1, "v4 held commands enter the actual sparse input history")
	key(KEY_W, false, true); key(KEY_SHIFT, false, true); key(KEY_SPACE, false, true); await settle(1)
	check(game._pilot_input_state() == Timeline.neutral(), "release path clears keys through Godot input routing")
	drive({"axis_q": 1000, "boost": true, "active": true}); game._step_flight(); key(KEY_P)
	check(game.paused and neutral(), "P pause clears every held v4 command and immediate overdrive state")
	var before: Dictionary = state(game.sim); game._process(.25)
	same(state(game.sim), before, "paused production process does not advance or consume energy")
	key(KEY_SHIFT); key(KEY_SPACE)
	check(neutral(), "new pilot presses are ignored while paused")
	key(KEY_P); game._step_flight()
	check(not game.paused and neutral() and game.pilot_timeline.state_at(2) == Timeline.neutral(), "resume records a fresh neutral command rather than sticky keys")
	drive({"axis_q": -1000, "boost": true, "active": true}); game._step_flight(); game._on_focus_exited()
	check(game.paused and neutral() and int(saved().in_flight.ticks) == 4, "focus loss saves exact completed tick and clears v4 held commands")
	key(KEY_SHIFT)
	check(neutral(), "focus-lost window cannot accumulate hidden input")
	game._on_focus_entered(); game._set_paused(false)
	game.hud.settings_open = true; game._process(0.0); key(KEY_W); key(KEY_SPACE)
	check(game.paused and neutral(), "settings modal pauses v4 and captures steering/active input")
	game.hud.settings_open = false; game._process(0.0)
	check(not game.paused and neutral(), "closing settings restores the prior running state with neutral commands")
	game._action("pause", null)
	check(game.paused and neutral(), "HUD pause action uses the same v4 input clear path")
	await dispose()

func guidance(sim) -> int:
	# Existing deterministic fixture guide, not a production autopilot. It only
	# chooses held W/S states; no position, velocity, force, energy or HP is changed.
	var pos: Vector2 = sim.cargo_position(); var offset: float = 0.0
	for gate in sim.route.pilot_gates:
		if pos.x < float(gate.x) + 6.5: offset = float(gate.lane_offset); break
	if pos.x > 980.0 and pos.x < 1090.0: offset = -6.0
	var normal = Ascent.path_tangent(pos.x, sim.route).orthogonal() * -1.0
	var body: Dictionary = sim._cargo_body()
	var lateral: float = Vector2(body.get("velocity", Vector2.ZERO)).dot(normal)
	var acceleration: float = float(sim.route.pilot_net_force_limit) / maxf(1.0, float(body.get("mass", 10.2)))
	var preview: float = lateral * (.45 + absf(lateral) / (2.0 * acceleration * .9))
	var error: float = Ascent.path_y(pos.x, sim.route) + offset - pos.y - preview
	return int(signf(error)) * 1000 if absf(error) > .9 else 0

func checkpoint_restart(expected: Dictionary, tick: int, transits: int, label: String) -> void:
	game._on_focus_exited()
	var snapshot: Dictionary = saved().in_flight
	check(game.paused and neutral() and int(snapshot.ticks) == tick, label + ": real focus checkpoint stores exact completed command tick")
	await fresh(false)
	check(not game.pilot_resume_blocked and game.sim.get_script() == Sim and game.paused and neutral() and game.pilot_completed_ticks == tick, label + ": JSON restart restores v4 paused and neutral at exact tick")
	same(state(game.sim), expected, label + ": every physical/accounting/cache/event/reserve value reconstructs exactly")
	same(game.economy.in_flight, snapshot, label + ": bootstrap leaves the committed route/input snapshot unchanged")
	check(game.sim.wormhole_events.size() == transits and game.sim._station_remaining == expected._station_remaining, label + ": portal event count and exact station reserve survive restart")
	check(game.launch_age == 1.35 and game.launch_countdown == 0 and game.launch_transfer_remaining == 0 and game.launch_sfx_played and game.world.launch_transfer_progress == 1, label + ": resume does not repeat transfer, charge or ignition")
	game._process(.25)
	same(state(game.sim), expected, label + ": paused rendering does not step, recharge or repeat transit")
	game._on_focus_entered(); game._set_paused(false)

func test_real_delivery(heavy: bool) -> void:
	await fresh()
	if heavy: unlock_day_three()
	else: authored_standard()
	var id: String = game.economy.active_contract_id
	var before: Dictionary = ledger(); var money: int = game.economy.credits
	var route: Dictionary = game.economy.active_contract().duplicate(true)
	game._action("trial", null)
	var trial_route: Dictionary = game.flight_order.duplicate(true)
	var initial: Dictionary = state(game.sim); var initial_energy: float = game.sim.total_energy()
	var cargo_mass: float = game.sim.parts[1].mass; var total_mass: float = game.sim.total_mass()
	check(is_equal_approx(cargo_mass, 11.16 if heavy else 7.2) and is_equal_approx(total_mass, 18.36 if heavy else 14.4) and game.sim.bodies.size() == 1, "actual %s commercial cargo and one-cell starter mass reach the real solver" % ("heavy" if heavy else "standard"))
	var axis: int = 0; var portal_tick: int = -1; var portal_before: Dictionary = {}; var portal_after: Dictionary = {}
	var minimum_ore_clearance: float = INF; var phases: Dictionary = {}; var minimum_energy: float = initial_energy
	for tick in range(6000):
		if game.sim.status != "running": break
		if tick % 12 == 0: axis = guidance(game.sim)
		if portal_tick < 0 and game.sim.cargo_position().x > 594.0: portal_before = state(game.sim)
		drive({"axis_q": axis, "boost": false, "active": false}); game._step_flight()
		phases[game.sim.telemetry.wormhole_phase] = true
		minimum_energy = minf(minimum_energy, game.sim.total_energy())
		if portal_tick < 0 and not game.sim.wormhole_events.is_empty(): portal_tick = game.pilot_completed_ticks; portal_after = state(game.sim)
		for part in game.sim.parts.values():
			if part.alive: minimum_ore_clearance = minf(minimum_ore_clearance, game.sim.part_world_position(part.id).distance_to(Vector2(1080, -150)) - 3.0 - .43 * part.scale)
	var ticks: int = game.pilot_completed_ticks; var commands: Array = game.pilot_timeline.snapshot()
	var terminal: Dictionary = state(game.sim)
	var label: String = "heavy" if heavy else "standard"
	check(game.sim.status == "success" and ticks > 2500 and ticks < 6000 and game.sim.elapsed < route.deadline, label + ": real headless controller guide completes the authored route before its actual deadline")
	check(phases.has("ascent") and phases.has("space") and phases.has("otherworld") and portal_tick > 1 and game.sim.wormhole_events.size() == 1, label + ": actual flight traverses ascent, space and otherworld with one discrete portal event")
	check(commands.size() > 10 and game.sim.telemetry.energy_used > 3000.0 and minimum_energy > 1000.0 and minimum_ore_clearance > 0.0, label + ": meaningful steering spends finite onboard energy and safely dodges real ore")
	check(game.sim.ship_integrity() == 1.0 and game.sim.telemetry.structure_damage == 0.0 and game.sim.parts.values().all(func(p): return p.alive and p.hp == p.max_hp), label + ": baseline eight-part build finishes undamaged without free hardware")
	var station: float = game.sim.telemetry.wormhole_energy_used
	check(is_equal_approx(station, 25.0 + 2.0 * total_mass) and game.sim._station_remaining == 2000.0 - station, label + ": one island consumes exactly its mass-priced finite station reserve")
	check(is_equal_approx(game.sim.telemetry.energy_used, initial_energy - game.sim.total_energy() + game.sim.telemetry.launch_energy + station), label + ": total billed energy conserves actual ship, launcher and station draws once")
	same(ledger(), before, label + ": complete trial flight changes no money, dispatch quota or story")
	check(game.economy.in_flight.is_empty() and game.economy.active_contract().status == "accepted", label + ": successful trial never commits a dispatch")
	game.finish_flight()
	var trial_report: Dictionary = game.report.duplicate(true)
	check(trial_report.success and trial_report.trial and trial_report.energy_j == terminal.telemetry.energy_used and trial_report.wormhole_energy_j == station and trial_report.wormhole_transits == 1 and trial_report.wormhole_station_remaining == terminal._station_remaining, label + ": actual trial report carries measured total, station subtotal, component count and reserve")
	check(game.hud.content.find_children("WormholeEnergySubtotal", "Label", true, false).size() == 1 and labels_contain("已含在本次耗能中"), label + ": trial HUD explains station energy as one included subtotal")
	same(ledger(), before, label + ": saving trial report remains financially and narratively inert")
	var replay = Timeline.new(); check(replay.restore(commands, ticks), label + ": actual trial input timeline is valid for formal replay")
	game._action("dispatch", null)
	var formal_route: Dictionary = game.flight_order.duplicate(true); formal_route.erase("status"); trial_route.erase("status")
	same(formal_route, trial_route, label + ": actual trial and formal dispatch use identical saved route/seed/tariff/weight")
	same(state(game.sim), initial, label + ": formal start exactly matches trial physics and station charge")
	check(saved().in_flight.control_version == Profile.CONTROL_VERSION and int(saved().in_flight.ticks) == 0 and saved().in_flight.input_commands.size() == 1, label + ": formal launch commits v4 neutral timeline before any physics tick")
	# The heavy/default first offer restarts at both immediate crossing boundaries.
	# Standard independently repeats the full identical real command timeline.
	for tick in range(ticks):
		if heavy and tick == portal_tick - 1:
			same(state(game.sim), portal_before, "formal immediately-before-portal state equals the actual trial")
			await checkpoint_restart(portal_before, portal_tick - 1, 0, "immediately before portal")
		if heavy and tick == portal_tick:
			same(state(game.sim), portal_after, "formal crossing command exactly matches the actual trial event")
			await checkpoint_restart(portal_after, portal_tick, 1, "immediately after portal")
		if game.sim.status != "running": break
		drive(replay.state_at(tick)); game._step_flight()
	check(game.sim.status == "success" and game.pilot_completed_ticks == ticks, label + ": formal succeeds on the same exact completed tick as trial")
	same(state(game.sim), terminal, label + ": identical input reproduces every terminal physical/cache/event/energy/reserve value")
	same(game.pilot_timeline.snapshot(), commands, label + ": formal retained the full exact sparse command history")
	game.finish_flight()
	var report: Dictionary = game.report.duplicate(true)
	check(report.success and not report.trial and report.energy == ceili(float(terminal.telemetry.energy_used) * float(route.pilot_energy_tariff)), label + ": formal bill rounds total measured energy exactly once")
	check(report.wormhole_energy_j == station and report.energy_j == terminal.telemetry.energy_used and report.wormhole_transits == 1 and report.wormhole_station_remaining == terminal._station_remaining, label + ": formal receipt preserves measured station subtotal without a second debit")
	check(report.profit == trial_report.estimated_profit and game.economy.credits == money + report.profit and game.economy.jobs_today == int(before.jobs) + 1 and game.economy.deliveries == int(before.deliveries) + 1, label + ": quoted profit, credit delta and unique successful delivery agree")
	check(report.route_context.route_profile == Profile.ROUTE_PROFILE and report.route_context.destination_name == route.destination_name and game.economy.story_state.committed_contract_ids[id].route_context.destination_name == route.destination_name, label + ": financial and story receipts retain actual otherworld destination")
	check(conversation_text(game.economy.story_conversation(id, "result")).contains(route.destination_name), label + ": actual result conversation names the correct destination")
	check(game.hud.content.find_children("WormholeEnergySubtotal", "Label", true, false).size() == 1 and labels_contain("已含在能源消耗中"), label + ": formal HUD shows one included station subtotal")
	var once: Dictionary = ledger(); game.finish_flight()
	var duplicate: Dictionary = game.economy.settle_contract(id, terminal.telemetry, terminal.elapsed, true)
	check(duplicate.get("duplicate", false), label + ": duplicate formal settlement is rejected")
	same(ledger(), once, label + ": duplicate finish cannot change money, count, inventory, history or story")
	check(saved().in_flight.is_empty() and saved().settled_ids.has(id), label + ": one atomic save clears dispatch and persists unique settlement")
	game.economy.mark_story_seen(id, id + "/result")
	check(game.economy.close_day().ok and game.economy.next_day().ok and game.save_game(), label + ": original receipt persists through the next authoring boundary")
	var after: Dictionary = ledger(); await fresh(false)
	check(game.economy.in_flight.is_empty() and game.economy.credits == after.credits and conversation_text(game.economy.story_conversation(id, "return")).contains(route.destination_name), label + ": disk reload retains original otherworld return after contracts rotate")
	duplicate = game.economy.settle_contract(id, terminal.telemetry, terminal.elapsed, true)
	check(duplicate.get("duplicate", false) and game.economy.credits == after.credits and game.economy.history.size() == after.history.size(), label + ": unique settlement remains guarded after next-day restart")
	var measured: Dictionary = {"case": label, "scope": "headless synthetic controller input, automated test-only guide", "weight": route.weight, "cargo_mass": cargo_mass, "ship_mass": total_mass, "ticks": ticks, "commands": commands.size(), "seconds": terminal.elapsed, "deadline": route.deadline, "portal_command_tick": portal_tick, "portal_physics_tick": terminal.wormhole_events[0].tick, "portal_energy": station, "total_energy": terminal.telemetry.energy_used, "remaining_ship_energy": initial_energy - (terminal.telemetry.energy_used - terminal.telemetry.launch_energy - station), "minimum_ore_clearance": minimum_ore_clearance, "integrity": terminal.telemetry.integrity, "profit": report.profit}
	measurements.append(measured); print("WORMHOLE_CONTROLLER_DELIVERY ", JSON.stringify(measured))
	await dispose()

func corrupted(route: Dictionary, kind: String) -> Dictionary:
	var result: Dictionary = route.duplicate(true)
	match kind:
		"unknown version": result.control_version = "pilot-v99"; result.pilot_profile = "pilot-v99"
		"mismatched profile": result.pilot_profile = "pilot-v3"
		"unknown content": result.route_profile = "wormhole-otherworld-v99"
		"unknown schema": result.wormhole_schema = 2
		"bad entry": result.wormhole_portal.entry = [600.0]
		"invalid reserve": result.wormhole_portal.station_energy_j = "2000"
		"missing protocol": result.erase("control_version"); result.erase("pilot_profile")
	return result

func test_malformed_fail_closed() -> void:
	await fresh(); authored_standard(); game._action("dispatch", null)
	for tick in 7: game._step_flight()
	check(game.save_game(), "valid v4 dispatch provides a real seven-tick corruption fixture")
	var valid: Dictionary = saved(); await dispose()
	var kinds: Array[String] = ["unknown version", "mismatched profile", "unknown content", "unknown schema", "bad entry", "invalid reserve", "missing protocol"]
	for kind in kinds:
		await fresh(); authored_standard()
		var active: Dictionary = corrupted(game.economy.active_contract(), kind)
		var index: int = game.economy.contracts.find(game.economy.active_contract())
		game.economy.contracts[index] = active
		var before: Dictionary = ledger(); var bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://savegame.json")
		game.start_flight(true); game.start_flight(false); game._configure_flight(true, game.design, game.launcher, active)
		check(not game.economy.route_validation_error(active).is_empty() and game.sim == null and game.page != "flight" and game.economy.in_flight.is_empty(), kind + ": trial, formal and direct configure fail before launching")
		check(FileAccess.get_file_as_bytes("user://savegame.json") == bytes and game._wormhole_preflight(active).is_empty(), kind + ": failed launch preserves saved bytes and emits no plausible station quote")
		same(ledger(), before, kind + ": invalid launch never charges, consumes quota or advances story")
		await dispose()
		var fixture: Dictionary = valid.duplicate(true)
		fixture.in_flight.route = corrupted(fixture.in_flight.route, kind)
		fixture.in_flight.control_version = fixture.in_flight.route.get("control_version", "")
		for i in fixture.contracts.size():
			if fixture.contracts[i].contract_id == fixture.in_flight.contract_id: fixture.contracts[i] = corrupted(fixture.contracts[i], kind)
		write_fixture(fixture); bytes = FileAccess.get_file_as_bytes("user://savegame.json")
		await fresh(false); before = ledger()
		if kind in ["unknown version", "missing protocol"]:
			check(recovery_only(), kind + ": invalid JSON resume stops before normal world, HUD, input or solver construction")
		else:
			check(game.pilot_resume_blocked and game.sim == null and is_instance_valid(game.world), kind + ": known malformed JSON resume never selects autonomous or old solver")
		game._set_paused(false); game._process(2.0); game.start_flight(true); game.abort_flight(); game.finish_flight()
		var result: Dictionary = game.economy.settle_contract(str(fixture.in_flight.contract_id), {"integrity": 1.0, "energy_used": 125.0}, 1.0, true)
		check(not result.ok and not game.save_game() and not game.economy.in_flight.is_empty(), kind + ": blocked dispatch cannot launch, settle or save over its evidence")
		same(ledger(), before, kind + ": all blocked recovery actions retain money, history and story")
		check(FileAccess.get_file_as_bytes("user://savegame.json") == bytes, kind + ": malformed original save remains byte-identical")
		await dispose()
	var conflict: Dictionary = valid.duplicate(true); conflict.in_flight.simulation_version = "pilot-v3"
	write_fixture(conflict); var bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://savegame.json")
	await fresh(false)
	check(recovery_only() and not game.save_game() and FileAccess.get_file_as_bytes("user://savegame.json") == bytes, "conflicting supported v3 simulation/v4 control markers also fail closed without overwrite")
	await dispose()

func run() -> void:
	root.size = Vector2i(1280, 800)
	test_frozen_sources()
	await test_preflight_and_protocol()
	await test_old_accepted_presentation()
	await test_input_lifecycle()
	await test_real_delivery(true)
	await test_real_delivery(false)
	await test_malformed_fail_closed()
	await dispose(); clear_save()
	if EXPECTED_CHECKS > 0 and passed + failed != EXPECTED_CHECKS: check(false, "all planned assertions ran: expected %d, saw %d" % [EXPECTED_CHECKS, passed + failed])
	print("WORMHOLE_CONTROLLER passed=%d failed=%d total=%d native_input=false" % [passed, failed, passed + failed])
	quit(1 if failed else 0)
