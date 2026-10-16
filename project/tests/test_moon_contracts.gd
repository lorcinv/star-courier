extends SceneTree
## Headless direct-method + real frozen-solver coverage. Never native UI/input QA.
## Save/reload runs only in isolated XDG state; guidance is an offline observer.
const Econ = preload("res://scripts/economy.gd")
const Stories = preload("res://scripts/courier_stories.gd")
const Moon = preload("res://scripts/pilot_moon_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Pilot = preload("res://scripts/pilot_profile.gd")
const Wormhole = preload("res://scripts/pilot_wormhole_profile.gd")
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const WormholeSim = preload("res://scripts/pilot_wormhole_simulation.gd")
const Guide = preload("res://tools/moon_offline_guide.gd")
const PriorGuide = preload("res://tools/pilot_wormhole_guidance.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Parts = preload("res://scripts/parts_expanded.gd")
var passed = 0
var failed = 0
var flights: Array = []

func _initialize() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("Moon contracts require isolated XDG_DATA_HOME."); quit(2); return
	clear_save()
	test_thresholds(); test_existing_orders(); test_quotes_and_receipts()
	test_invalid_routes(); test_stories(); test_old_save_versions()
	if not "--data-only" in OS.get_cmdline_user_args(): test_natural_progression()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file = FileAccess.open(argument.trim_prefix("--output="), FileAccess.WRITE)
			if file: file.store_string(JSON.stringify({"scope": "HEADLESS offline observer and real solvers; no native-input claim", "passed": passed, "failed": failed, "flights": flights}, "\t", true, true))
	clear_save()
	print("MOON_CONTRACTS passed=%d failed=%d total=%d" % [passed, failed, passed + failed])
	quit(1 if failed else 0)

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error("FAIL " + label)

func equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not equal(a[index], b[index]): return false
		return true
	return a == b

func same(a: Variant, b: Variant, label: String) -> void: check(equal(a, b), label)
func clear_save() -> void:
	for name in ["savegame.json", "savegame.backup.json", "savegame.tmp"]:
		if FileAccess.file_exists("user://" + name): DirAccess.remove_absolute("user://" + name)
func craft() -> Array: return Extreme.starter_design()
func pad() -> Array: return Extreme.starter_launcher()
func disk() -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func shop(day: int = 4, reputation: int = 10, stories: bool = true):
	var e = Econ.new(); e.day = day; e.reputation = reputation; e.enable_extreme_mode()
	e.starter_stock(craft(), pad())
	if stories: e.story_state = Stories.initial_state(7421); e.enable_story_mode()
	return e
func moon_order() -> Dictionary: return shop().contracts[1].duplicate(true)
func ledger(e) -> Dictionary:
	return {"credits": e.credits, "reputation": e.reputation, "jobs": e.jobs_today, "deliveries": e.deliveries,
		"research": e.research, "inventory": e.inventory.duplicate(true), "settled": e.settled_ids.duplicate(true), "history": e.history.duplicate(true)}
func telemetry() -> Dictionary:
	return {"integrity": 1.0, "energy_used": 5538.60545992396, "ammo_cost": 2.0, "repair_cost": 3.0, "lost_cost": 4.0}
func text_of(conversation: Dictionary) -> String:
	var text = str(conversation.get("title", "")) + " " + str(conversation.get("route_hint", ""))
	for line in conversation.get("lines", []): text += " " + str(line.text)
	return text

func test_thresholds() -> void:
	for day in [1, 3, 4, 5, 9]:
		for reputation in [0, 7, 9, 10, 12]:
			var e = shop(day, reputation, false)
			check(e.contracts.size() == 2 and e.contracts[0].contract_id != e.contracts[1].contract_id, "two unique offers at each threshold")
			for order in e.contracts:
				var expected = order.id == 4 and day >= 4 and reputation >= 10
				check(Moon.is_moon_route(order) == expected, "only new day-four rep-ten ID4 becomes Moon")
				check(Econ.route_validation_error(order).is_empty(), "every authored offer validates: " + Econ.route_validation_error(order))
				if expected:
					var heavy = order.variant == "重货件"
					check(order.control_version == "pilot-v3" and order.weight == (4.34 if heavy else 2.8) and order.reward == (465 if heavy else 410) and order.deadline == (67.0 if heavy else 64.0), "canonical exact Moon commercial fields")
			var catalog = e.routes()[4]
			check(catalog.control_version == "pilot-v3" and not catalog.has("route_profile") and catalog.distance == 520.0 and catalog.weight == 2.8 and catalog.reward == 410, "catalog remains old v3 ID4")
			var before = e.contracts.duplicate(true)
			for ignored in range(3): e.ensure_contracts(); e.enable_extreme_mode(); e.available_contracts()
			same(e.contracts, before, "repeated reads do not author a new route")
	var day4 = shop(4, 12)
	check(day4.contracts[0].id == 3 and day4.contracts[0].control_version == Wormhole.CONTROL_VERSION and day4.contracts[1].id == 4, "natural day four pairs standard wormhole with heavy Moon")
	var earlier = shop(3, 12); var existing = earlier.contracts.duplicate(true)
	earlier.day = 4; earlier.ensure_contracts(); earlier.enable_extreme_mode()
	same(earlier.contracts, existing, "crossing time threshold never retrofits a saved day-three offer")
	for mode in ["autonomous-v5", "pilot-v1", "pilot-v2"]:
		var e = Econ.new(); e.flight_mode = mode; e.day = 5; e.reputation = 12; e.ensure_contracts()
		for order in e.contracts: check(not Moon.has_moon_markers(order), "legacy authoring mode remains outside Moon content")

func test_existing_orders() -> void:
	for version in ["", "pilot-v1", "pilot-v2", "pilot-v3", Wormhole.CONTROL_VERSION]:
		for status in ["available", "accepted", "in_flight", "settled"]:
			clear_save(); var e = Econ.new(); e.flight_mode = "pilot-v3"; e.day = 4; e.reputation = 12
			var order: Dictionary = e._autonomous_routes()[3 if version == Wormhole.CONTROL_VERSION else 4]
			match version:
				"pilot-v1": order = Pilot.route(order)
				"pilot-v2": order = Ascent.route(order)
				"pilot-v3": order = Extreme.route(order)
				Wormhole.CONTROL_VERSION: order = Wormhole.route(order)
			order.contract_id = "D4-B"; order.status = status; order.weight = 4.34; order.reward = 465
			e.contracts = [order]; e.active_contract_id = "D4-B" if status in ["accepted", "in_flight"] else ""
			if status == "in_flight":
				e.in_flight = {"contract_id": order.contract_id, "route": order.duplicate(true), "design": craft(), "launcher": pad(), "seed": 413, "ticks": 17, "elapsed": 17.0 / 60.0, "input_commands": [{"tick": 0, "axis_q": 0, "boost": false, "active": false}]}
				if not version.is_empty(): e.in_flight.control_version = version
			if status == "settled": e.settled_ids[order.contract_id] = {"success": true, "profit": 17, "route": order.name}
			var original = {"orders": e.contracts.duplicate(true), "flight": e.in_flight.duplicate(true), "settled": e.settled_ids.duplicate(true)}
			e.ensure_contracts()
			same(e.contracts, original.orders, "new-author boundary never touches existing " + version + "/" + status)
			check(e.save_state(craft(), pad(), {}), "old status/version persists")
			var bytes = FileAccess.get_file_as_bytes("user://savegame.json")
			var reloaded = Econ.new(); reloaded.load_state(); reloaded.ensure_contracts()
			same(reloaded.contracts, original.orders, "read-only load preserves old offers exactly")
			same(reloaded.in_flight, original.flight, "read-only load preserves old snapshots exactly")
			same(reloaded.settled_ids, original.settled, "read-only load preserves old receipts exactly")
			check(FileAccess.get_file_as_bytes("user://savegame.json") == bytes, "read-only load never rewrites saved bytes")
			# Historical explicit upgrades of AVAILABLE v1/v2/autonomous offers are
			# pre-existing policy. Committed routes and existing v3/v4 are immutable.
			if status != "available" or version in ["pilot-v3", Wormhole.CONTROL_VERSION]:
				reloaded.enable_extreme_mode()
				same(reloaded.contracts, original.orders, "production extreme bootstrap preserves committed/current offers")
	var moon = shop(5, 10, false); var authored = moon.contracts.duplicate(true)
	for method in ["enable_pilot_mode", "enable_ascent_mode", "enable_extreme_mode"]:
		moon.call(method); same(moon.contracts, authored, "explicit mode calls cannot downgrade existing Moon content")

func test_quotes_and_receipts() -> void:
	clear_save(); var e = shop(); var cid: String = e.contracts[1].contract_id
	check(e.accept_contract(cid).ok and e.mark_cargo_loaded(cid).ok, "Moon acceptance and ordinary cargo loading")
	var before = ledger(e); var story = e.story_state.duplicate(true)
	var route = e.trial_route(); var quote = e.estimate_delivery(e.active_contract(), telemetry(), 60.0, true)
	check(quote.income == 465 and quote.energy == 139 and quote.ammo == 2 and quote.repairs == 3 and quote.lost == 4 and quote.profit == 317, "Moon uses single existing rounded energy and normal costs")
	same(ledger(e), before, "Moon trial/estimate has no real cost or reward")
	same(e.story_state, story, "Moon trial grants no story reward")
	check(e.begin_dispatch(craft(), pad()).ok, "Moon formal dispatch commits")
	check(e.in_flight.control_version == "pilot-v3" and e.in_flight.ticks == 0 and e.in_flight.input_commands == [{"tick": 0, "axis_q": 0, "boost": false, "active": false}], "Moon reuses exact existing 60Hz v3 input protocol")
	var formal = e.in_flight.route.duplicate(true); formal.seed = e.in_flight.seed; route.status = "in_flight"
	same(formal, route, "trial and formal route/design economics share same committed inputs")
	e.in_flight.ticks = 1320; e.in_flight.elapsed = 22.0
	e.in_flight.input_commands.append({"tick": 670, "axis_q": -1000, "boost": false, "active": false})
	var snapshot = e.in_flight.duplicate(true); var roundtrip = snapshot.duplicate(true)
	for index in range(12):
		roundtrip = JSON.parse_string(JSON.stringify(roundtrip, "", true, true))
		same(roundtrip, snapshot, "repeated complete Moon JSON checkpoint has exact numeric values")
		check(roundtrip.route.weight == 4.34 and Econ.route_validation_error(roundtrip.route).is_empty(), "canonical heavy payload and explicit Moon validity survive reload")
	check(e.save_state(craft(), pad(), {}), "Moon saves using existing atomic v5 format")
	var restored = Econ.new(); restored.load_state(); restored.enable_extreme_mode(); restored.enable_story_mode()
	same(restored.in_flight, snapshot, "Moon checkpoint route/seed/timeline untouched on bootstrap")
	same(restored.contracts, e.contracts, "available and in-flight Moon offers untouched on bootstrap")
	check(disk().version == 5 and Econ.SAVE_VERSION == 5, "Moon content does not change save version")
	var result = restored.settle_contract(cid, telemetry(), 60.0, true)
	check(result.ok and result.story_advanced and result.report.profit == quote.profit and restored.credits == before.credits + quote.profit, "actual unique settlement applies precisely quoted profit")
	check(result.report.control_version == "pilot-v3" and result.report.route_context.route_profile == Moon.ROUTE_PROFILE and result.report.route_context.destination_id == Moon.DESTINATION_ID and result.report.route_context.route_kind == "moon", "financial receipt persists physics and independent lunar destination identity")
	check(restored.jobs_today == 1 and restored.deliveries == 1 and restored.settled_ids.size() == 1 and restored.history.size() == 1, "Moon uses one existing quota and one receipt")
	var committed = ledger(restored); story = restored.story_state.duplicate(true)
	check(restored.settle_contract(cid, telemetry(), 1.0, false).get("duplicate", false), "duplicate contradictory Moon receipt rejected")
	same(ledger(restored), committed, "duplicate never pays or charges twice")
	same(restored.story_state, story, "duplicate never advances story twice")
	var returned = restored.story_conversation(cid, "return")
	check(restored.close_day().ok and restored.next_day().ok and restored.save_state(craft(), pad(), {}), "Moon receipt persists across next-day deletion of source contract")
	var next = Econ.new(); next.load_state(); next.enable_extreme_mode(); next.enable_story_mode()
	same(next.settled_ids, restored.settled_ids, "next-day restart keeps exact financial receipts")
	same(next.story_conversation(cid, "return"), returned, "next-day restart keeps exact Moon return and identity")
	var failure = shop(); cid = failure.contracts[1].contract_id
	failure.accept_contract(cid); failure.mark_cargo_loaded(cid); failure.begin_dispatch(craft(), pad())
	before = ledger(failure); result = failure.settle_contract(cid, telemetry(), 90.0, false)
	check(result.ok and result.report.income == 0 and result.report.profit == -148 and failure.deliveries == 0 and failure.jobs_today == 1 and failure.reputation == 9, "failed Moon route pays only its actual costs and ordinary rep penalty")
	check(text_of(failure.story_conversation(cid, "result")).contains("还没收到"), "Moon failure cannot claim arrival")
	var failed_ledger = ledger(failure)
	check(failure.mark_story_seen(cid, cid + "/result") and failure.mark_story_seen(cid, cid + "/return"), "Moon failure result/return can each be skipped")
	same(ledger(failure), failed_ledger, "skipping never grants refund/reward")
	check(failure.pending_story_returns().is_empty(), "consumed Moon return leaves pending queue")

func test_invalid_routes() -> void:
	var valid = moon_order(); check(Econ.route_validation_error(valid).is_empty(), "full Moon content validates")
	var cases: Array = []
	for key in ["control_version", "pilot_profile", "mode", "route_profile", "route_kind", "destination_id", "moon_schema", "moon_receiver", "moon_landmarks", "moon_render_requirements", "hazards", "pilot_gates", "distance", "weight", "reward"]:
		for bad in [null, true, "bad", [], {}]:
			var order = valid.duplicate(true); order[key] = bad; cases.append(order)
	for key in ["moon_schema", "moon_receiver", "destination_id", "pilot_gates", "weight"]:
		var order = valid.duplicate(true); order.erase(key); cases.append(order)
	for bad in [NAN, INF, -INF, -1.0, 0.0]:
		var order = valid.duplicate(true); order.weight = bad; cases.append(order)
	for key in ["wormhole", "wormhole_schema", "wormhole_portal", "otherworld_background"]:
		var order = valid.duplicate(true); order[key] = null; cases.append(order)
	for key in ["moon_receiver", "moon_schema", "moon_landmarks", "moon_render_requirements"]:
		var order = Extreme.route({"contract_id": "D4-B", "id": 4, "rep": 10}); order[key] = false; cases.append(order)
	for key in ["route_kind", "destination_id"]:
		for bad in [null, true, [], {}]:
			var order = Extreme.route({"contract_id": "D4-B", "id": 4, "rep": 10}); order[key] = bad; cases.append(order)
	var mixed = Wormhole.route({"contract_id": "D4-B", "id": 3, "rep": 7}); mixed.moon_schema = 1; cases.append(mixed)
	mixed = valid.duplicate(true); mixed.hazards[8].wormhole_hardware = false; cases.append(mixed)
	mixed = valid.duplicate(true); mixed.hazards[8].otherworld = true; cases.append(mixed)
	mixed = Extreme.route({"contract_id": "D4-B", "id": 4, "rep": 10}); mixed.hazards[0].moon = false; cases.append(mixed)
	for key in ["x", "radius", "mass", "health", "destructible", "type", "moon", "moon_group", "moon_role", "id"]:
		var order = valid.duplicate(true); order.hazards[8][key] = {}; cases.append(order)
	for key in ["damage", "cooldown", "tracking", "pilot_gate", "position"]:
		var order = valid.duplicate(true); order.hazards[8][key] = "bad"; cases.append(order)
	for mutate in ["wrong-id", "huge-position", "duplicate", "source", "capture", "capture-art-scale", "ingress", "counts", "references", "landmark", "gate", "bool-number", "future"]:
		var order = valid.duplicate(true)
		match mutate:
			"wrong-id": order.id = 3
			"huge-position": order.hazards[8].x = 1.0e100
			"duplicate": order.hazards[9].id = order.hazards[8].id
			"source": order.hazards[14].source_circle_native[0] += 1.0
			"capture": order.moon_receiver.capture_plane_x += 1.0
			"capture-art-scale": order.delivery_radius = 18.0; order.moon_receiver.capture_radius = 18.0
			"ingress": order.moon_receiver.ingress_center_y += 1.0
			"counts": order.hazards.append(order.hazards[14].duplicate(true))
			"references": order.moon_receiver.hardware_hazard_ids[0] = "missing"
			"landmark": order.moon_landmarks[2].x = -20.0
			"gate": order.pilot_gates[0].x = "bad"
			"bool-number": order.moon_schema = true
			"future": order.route_profile = "moon-surface-v2"
		cases.append(order)
	for order in cases:
		order.status = "available"
		var before = order.duplicate(true)
		check(not Econ.route_validation_error(order).is_empty(), "malformed/partial/mixed Moon record fails closed")
		# Binary comparison also handles NaN fixtures without coercing them through JSON.
		check(var_to_bytes(order) == var_to_bytes(before), "validation never rewrites invalid content")
		var e = shop(4, 12, false); e.contracts = [order]; e.enable_extreme_mode()
		check(not e.accept_contract("D4-B").ok, "invalid Moon offer cannot accept")
		e.contracts[0].status = "accepted"; e.active_contract_id = "D4-B"
		var before_ledger = ledger(e)
		check(e.trial_route().is_empty() and not e.begin_dispatch(craft(), pad()).ok and e.in_flight.is_empty(), "invalid Moon trial/formal dispatch blocked before solver")
		same(ledger(e), before_ledger, "invalid record cannot alter credits or quota")
	clear_save(); var e = shop(); e.contracts[1].moon_receiver = {"invalid": true}
	check(e.save_state(craft(), pad(), {}), "malformed but JSON-safe route is retained for inspection, never silently repaired")
	var saved_bytes = FileAccess.get_file_as_bytes("user://savegame.json")
	var reloaded = Econ.new(); reloaded.load_state(); reloaded.enable_extreme_mode(); reloaded.enable_story_mode()
	same(reloaded.contracts[1], e.contracts[1], "load/bootstrap keeps exact malformed Moon record")
	check(not reloaded.accept_contract("D4-B").ok and FileAccess.get_file_as_bytes("user://savegame.json") == saved_bytes, "restored malformed Moon content blocks use while preserving original bytes")
	for profile in [Pilot, Ascent, Extreme, Wormhole]: check(Econ.route_validation_error(profile.route()).is_empty(), "all original known protocols remain valid without Moon markers")

func test_stories() -> void:
	for id in Stories.IDS:
		for node in [0, 1, 3]:
			var state = Stories.initial_state(7421); state.roster[id].story_node = node
			var cid = id + "-" + str(node)
			var order = Moon.route({"contract_id": cid, "status": "available", "appearance_id": id})
			var bound = Stories.bind_contract(state, order, 4, 1)
			var accept = Stories.conversation_for(bound.state, bound.contract, "accept")
			check(accept.lines.size() == (3 if node == 0 else 2), "Moon first/repeat beats stay brief")
			check(text_of(accept).contains("月面收件舱") and not text_of(accept).contains("虫洞") and not text_of(accept).contains("星港"), "Moon request names its own destination for every identity")
			same(accept.actor, Stories.actor_metadata(bound.state.contract_bindings[cid]), "Moon copy preserves species/seed/accessory/portrait/voice")
			for success in [true, false]:
				bound.contract.status = "settled"
				var committed = Stories.commit_settlement(bound.state, bound.contract, {"contract_id": cid, "success": success})
				check(committed.advanced and committed.state.pending_returns == [cid], "Moon adds exactly one pending return")
				var receipt: Dictionary = committed.state.committed_contract_ids[cid]
				check(receipt.route_context.route_profile == Moon.ROUTE_PROFILE and receipt.route_context.destination_id == Moon.DESTINATION_ID and receipt.route_context.route_kind == "moon", "story receipt preserves independent Moon identity")
				for beat in ["result", "return"]:
					var historical = Stories.conversation_for(committed.state, {"contract_id": cid}, beat)
					check(text_of(historical).contains("月面收件舱") and not text_of(historical).contains("虫洞") and not text_of(historical).contains("星港"), "historical Moon beat remains lunar without source order")
					if beat == "result": check(historical.title == "月面回执", "Moon result carries distinct title")
					var misleading = Extreme.route({"contract_id": cid})
					same(Stories.conversation_for(committed.state, misleading, beat), historical, "committed receipt wins over later misleading route")
				var roundtrip = Stories.normalize_state(JSON.parse_string(JSON.stringify(committed.state, "", true, true)))
				same(roundtrip, committed.state, "all Moon identity/pending/context values survive story normalization")
				var seen = Stories.mark_seen(roundtrip, cid, cid + "/return")
				check(seen.pending_returns.is_empty() and Stories.pending_return_conversations(seen).is_empty(), "Moon skipped return never reappears")
			var old = bound.state.duplicate(true); old.committed_contract_ids[cid] = {"success": true}; old.pending_returns = [cid]
			check(Stories.conversation_for(old, bound.contract, "result").title == "星港回执", "legacy success-only receipt is not retrofitted to Moon")
			same(Stories.normalize_state(old).committed_contract_ids[cid], {"success": true}, "old receipt remains value-equivalent")
	var bound = Stories.bind_contract(Stories.initial_state(), Moon.route({"contract_id": "context", "status": "available"}), 4, 1)
	bound.contract.status = "settled"
	var valid = Stories.commit_settlement(bound.state, bound.contract, {"contract_id": "context", "success": true}).state
	for key in ["route_kind", "destination_id"]:
		for bad in [null, false, [], {}, "wrong"]:
			var value = valid.duplicate(true); value.committed_contract_ids.context.route_context[key] = bad
			var normalized = Stories.normalize_state(value)
			same(normalized.committed_contract_ids.context, {"success": true}, "bad Moon receipt identity discarded without rewriting old semantics")
			check(normalized.pending_returns == ["context"], "invalid optional context never discards valid pending return")

func test_old_save_versions() -> void:
	var e = Econ.new()
	for version in [1, 2, 3, 4, 5]:
		clear_save(); var old = shop(3, 12, false); old.save_state(craft(), pad(), {})
		var value = disk(); value.version = version
		if version < 5: value.erase("workshop_tier")
		var file = FileAccess.open("user://savegame.json", FileAccess.WRITE); file.store_string(JSON.stringify(value, "", true, true)); file.close()
		var bytes = FileAccess.get_file_as_bytes("user://savegame.json")
		var loaded = Econ.new(); var parsed = loaded.load_state()
		check(not parsed.is_empty(), "old save version still loads " + str(version))
		if version >= 2: same(loaded.contracts, value.contracts, "old saved ID4 cannot become Moon on load")
		check(FileAccess.get_file_as_bytes("user://savegame.json") == bytes, "old-version load leaves disk bytes intact")
		check(loaded.workshop_tier == 0, "Moon adds no free workshop migration")
	check(e._valid_save({"version": 5, "workshop_tier": 0, "design": [], "launcher": []}), "current save envelope unchanged")

func state_of(sim) -> Dictionary:
	return {"status": sim.status, "elapsed": sim.elapsed, "position": sim.cargo_position(), "telemetry": sim.telemetry.duplicate(true), "parts": sim.parts.duplicate(true), "bodies": sim.bodies.duplicate(true), "obstacles": sim.obstacles.duplicate(true), "events": sim.events.duplicate(true)}

func actual_flight(e, snapshot: Dictionary, checkpoint: bool) -> Dictionary:
	var route: Dictionary = snapshot.route
	var sim = WormholeSim.new() if route.control_version == Wormhole.CONTROL_VERSION else Sim.new()
	sim.configure(snapshot.design, snapshot.launcher, route, int(snapshot.seed))
	var timeline = Timeline.new(); var axis = 0; var captured = false; var replay
	for tick in range(roundi(float(route.time_limit) * 60.0) + 2):
		if sim.status != "running": break
		if tick % 12 == 0: axis = Guide.command_axis(sim) if Moon.is_moon_route(route) else PriorGuide.guidance(sim)
		var command = {"axis_q": axis, "boost": false, "active": false}
		timeline.record(tick, command); sim.set_pilot_input(axis, false, false); sim.step(1.0 / 60.0)
		if replay != null:
			replay.set_pilot_input(axis, false, false); replay.step(1.0 / 120.0); replay.step(1.0 / 120.0)
		if checkpoint and not captured and sim.cargo_position().x >= 730.0:
			captured = true; e.in_flight.ticks = tick + 1; e.in_flight.elapsed = sim.elapsed; e.in_flight.input_commands = timeline.snapshot()
			var before = e.in_flight.duplicate(true); var paused = state_of(sim)
			check(e.save_state(craft(), pad(), {}), "real Moon checkpoint uses economy atomic save during lunar approach")
			var restored = Econ.new(); restored.load_state(); restored.enable_extreme_mode(); restored.enable_story_mode()
			# Godot JSON may canonicalize the redundant accumulated elapsed float by
			# one ULP. Compare the complete snapshot to its actual disk values, and
			# all authoritative replay fields directly to the pre-save inputs.
			same(restored.in_flight, disk().in_flight, "complete loaded checkpoint preserves exact persisted values")
			for key in ["contract_id", "route", "design", "launcher", "seed", "ticks", "control_version", "input_commands"]:
				same(restored.in_flight[key], before[key], "real pre-save replay input remains exact: " + key)
			check(roundi(float(restored.in_flight.elapsed) * 60.0) == int(before.ticks), "diagnostic elapsed still agrees with authoritative completed ticks")
			check(Econ.route_validation_error(restored.in_flight.route).is_empty(), "loaded real Moon snapshot validates before configuring frozen v3")
			same(state_of(sim), paused, "headless save/no-step pause cannot advance real physics")
			replay = Sim.new(); replay.configure(restored.in_flight.design, restored.in_flight.launcher, restored.in_flight.route, int(restored.in_flight.seed))
			var saved_commands = Timeline.new()
			check(saved_commands.restore(restored.in_flight.input_commands, int(restored.in_flight.ticks)), "production saved sparse input is accepted by existing replay protocol")
			for replay_tick in range(int(restored.in_flight.ticks)):
				var saved = saved_commands.state_at(replay_tick)
				replay.set_pilot_input(saved.axis_q, saved.boost, saved.active); replay.step(1.0 / 120.0); replay.step(1.0 / 120.0)
			same(state_of(replay), state_of(sim), "Moon prefix replay equals all state values exactly, without tolerance")
			axis = 0 # A recorded release at resume, applied equally to both paths.
	if checkpoint:
		check(captured and replay != null, "real Moon flight reaches saved lunar approach")
		if replay != null: same(state_of(replay), state_of(sim), "continued saved Moon replay exactly matches full terminal state")
	sim.finalize_settlement()
	return {"status": sim.status, "elapsed": sim.elapsed, "telemetry": sim.telemetry.duplicate(true), "reserve": sim.total_energy(), "position": [sim.cargo_position().x, sim.cargo_position().y], "input_commands": timeline.snapshot()}

func test_natural_progression() -> void:
	clear_save(); var e = shop(1, 0); var identity = e.story_state.roster.duplicate(true)
	check(e.credits == 260 and e.reputation == 0 and e.day == 1 and e.research == 0, "fresh default shop starts with no injected progress or energy")
	for day in range(1, 5):
		check(e.day == day and e.contracts.size() == 2 and e.reputation == (day - 1) * 4, "natural next day and reputation arise only from prior real settlements")
		for slot in ["A", "B"]:
			var cid = "D%d-%s" % [day, slot]
			check(e.accept_contract(cid).ok and e.mark_cargo_loaded(cid).ok, "natural acceptance/loading " + cid)
			e.mark_story_seen(cid, cid + "/accept")
			var dispatch = e.begin_dispatch(craft(), pad())
			check(dispatch.ok, "natural formal dispatch " + cid)
			if not dispatch.ok: return
			var snapshot: Dictionary = dispatch.snapshot.duplicate(true)
			var is_moon = Moon.is_moon_route(snapshot.route)
			check(is_moon == (day == 4 and slot == "B"), "Moon only first appears in natural day-four heavy slot")
			var result = actual_flight(e, snapshot, is_moon)
			check(result.status == "success" and result.telemetry.integrity == 1.0 and result.elapsed <= snapshot.route.deadline, "real guided intact timely delivery " + cid)
			var quote = e.estimate_delivery(snapshot.route, result.telemetry, result.elapsed, result.status == "success")
			var before = e.credits
			var settled = e.settle_contract(cid, result.telemetry, result.elapsed, result.status == "success")
			check(settled.ok and settled.report.reputation == 2 and e.credits == before + quote.profit, "real receipt pays exact ordinary metered costs " + cid)
			check(not e.settle_contract(cid, result.telemetry, result.elapsed, true).ok and e.credits == before + quote.profit, "natural duplicate cannot create money " + cid)
			if is_moon:
				check(snapshot.route.weight == 4.34 and snapshot.route.reward == 465 and result.reserve > 100.0 and e.research == 0, "natural heavy Moon succeeds with real untouched one-cell starter and finite reserve")
				check(settled.report.energy == int(ceil(result.telemetry.energy_used * .025)), "Moon real energy bill is unique and metered")
			flights.append({"id": cid, "seed": snapshot.seed, "route_profile": snapshot.route.get("route_profile", ""), "control_version": snapshot.route.control_version, "weight": snapshot.route.weight, "result": result, "receipt": settled.report, "credits": e.credits})
		check(e.close_day().ok, "natural close day " + str(day))
		if day == 1:
			check(e.workshop_upgrade(1).ok and e.buy_part("battery", Parts.catalog().battery).ok, "natural earned workshop and spare battery purchases keep original three-day path")
		if day == 2: check(e.buy_part("beam", Parts.catalog().beam).ok, "natural earned spare beam purchase")
		check(e.next_day().ok, "natural open next day " + str(day))
	check(e.day == 5 and e.reputation == 16 and e.deliveries == 8 and e.settled_ids.size() == 8 and e.history.size() == 8, "eight real deliveries finish natural four-day economic progression")
	for id in Stories.IDS: check(e.story_state.roster[id].appearance_seed == identity[id].appearance_seed and e.story_state.roster[id].accessory_id == identity[id].accessory_id, "all four identities persist through real route progression")
	var returned = e.story_conversation("D4-B", "return")
	check(returned.title == "又见面了" and text_of(returned).contains("月面收件舱"), "real Moon delivery leaves correct next-day return")
	check(e.save_state(craft(), pad(), {}), "natural post-Moon day-five checkpoint persists")
	var next = Econ.new(); next.load_state(); next.enable_extreme_mode(); next.enable_story_mode()
	same(next.settled_ids, e.settled_ids, "natural ledger remains exact after final restart")
	same(next.story_conversation("D4-B", "return"), returned, "natural Moon pending return remains exact after restart")
	print("HEADLESS NATURAL MOON: day=%d rep=%d credits=%d receipts=%d; offline W/release/S observer, NOT native input" % [e.day, e.reputation, e.credits, e.settled_ids.size()])
