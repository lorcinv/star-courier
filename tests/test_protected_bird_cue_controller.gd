extends SceneTree
## Recorded-command real-solver + Main/World/HUD projection regression.
## Synthetic authored order/keyboard fixture. No native-play or fairness claim.
const Sim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const Offer = preload("res://scripts/protected_bird_offer_v1.gd")
const Profile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Receipt = preload("res://scripts/flight_receipt.gd")
var passed: int = 0
var failed: int = 0
var game

func _initialize() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty(): printerr("Isolated XDG_DATA_HOME required."); quit(2); return
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS ",label)
	else: failed += 1; push_error("FAIL " + label)
func read_fixture(path: String) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null:
		check(false,"cannot open recorded fixture: " + path); return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text()); file.close()
	if not parsed is Dictionary:
		check(false,"recorded fixture is not a dictionary: " + path); return {}
	for key in ["design","launcher","commands"]:
		if not parsed.get(key) is Array:
			check(false,"recorded fixture lacks array: " + key); return {}
	if not parsed.get("route") is Dictionary or not parsed.has("seed") or not parsed.has("completed_command_ticks"):
		check(false,"recorded fixture lacks route/timing identity"); return {}
	return parsed
func state(sim) -> PackedByteArray:
	var result: Dictionary = {}
	for property in sim.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var name_value: String = property.name
		var value: Variant = sim.get(name_value)
		if value is RandomNumberGenerator: result[name_value] = {"seed":value.seed,"state":value.state}
		elif value is Dictionary or value is Array: result[name_value] = value.duplicate(true)
		else: result[name_value] = value
	return var_to_bytes(result)
func ledger() -> PackedByteArray:
	var result: Dictionary = {}
	for key in ["credits","reputation","day","jobs_today","deliveries","workshop_tier","inventory","settled_ids","history","story_state","review_state"]:
		var value: Variant = game.economy.get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return var_to_bytes(result)
func drive(command: Dictionary) -> void:
	game._clear_pilot_input()
	for pair in [[KEY_W,int(command.axis_q)<0],[KEY_S,int(command.axis_q)>0],[KEY_SHIFT,bool(command.boost)],[KEY_SPACE,bool(command.active)]]:
		if pair[1]:
			var event = InputEventKey.new(); event.keycode = pair[0]; event.physical_keycode = pair[0]; event.pressed = true
			game._unhandled_key_input(event)
func refresh() -> bool:
	var before: PackedByteArray = state(game.sim)
	game._process(0.0)
	var bird = game.world.flight_nodes.protected_bird
	return before == state(game.sim) and game.hud.state.flight.protected_bird_advice == bird.advisory_state() and bird.cue_state().active == bird.advisory_state().active

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game); game.set_process(false)
	game.world.set_process(false); game.world.assembly_feedback.set_process(false)
	await process_frame
	var initial_ledger = ledger()
	for kind in ["safe","harm"]:
		var source: Dictionary = read_fixture("res://tests/fixtures/protected_bird_controller/commercial-replay-" + kind + ".json")
		if source.is_empty(): continue # Record failure and finish/quit; never hang on a failed open.
		var authored: Dictionary = Offer.create_new_offer({"version":Offer.POLICY,"world_seed":420,"introduced_day":0},5,"human_courier")
		check(authored.ok,"real authored D5-A fixture validates")
		var order: Dictionary = authored.offer; order.battery_capacity_multiplier = 1.0
		check(Profile.same_value(Offer.canonical_route(order),source.route),"fixture reuses frozen canonical commercial route")
		game._configure_flight(true,source.design,source.launcher,order,true)
		check(game.page == "flight" and not game.pilot_resume_blocked,"trial Main configures real v5 route")
		if game.page != "flight" or game.sim == null: continue
		game.launch_age = 1.35; game.launch_transfer_remaining = 0.0; game.frame_accum = 0.0
		var twin = Sim.new(); twin.configure(source.design,source.launcher,game.sim.route.duplicate(true),int(source.seed))
		var timeline = Timeline.new(); check(timeline.restore(source.commands,int(source.completed_command_ticks)),"frozen " + kind + " command timeline validates")
		var saw_approach: bool = false; var saw_retired: bool = false; var retirement_before_gate: bool = false
		var projection_read_only: bool = true; var world_hud_agree: bool = true; var harm_feedback: bool = false
		var raw_event_preserved: bool = false
		while game.pilot_completed_ticks < int(source.completed_command_ticks) and game.sim.status == "running":
			var command: Dictionary = timeline.state_at(game.pilot_completed_ticks)
			drive(command); game._step_flight()
			twin.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active)); twin.step(1.0/60.0)
			if not game.sim.wildlife.activated: continue
			var before: PackedByteArray = state(game.sim)
			world_hud_agree = refresh() and world_hud_agree
			projection_read_only = projection_read_only and before == state(game.sim)
			var layer = game.world.flight_nodes.protected_bird
			var active: bool = layer.advisory_state().active
			if active: saw_approach = true
			if game.sim.wildlife.damage_transitions > 0:
				harm_feedback = harm_feedback or layer.debug_snapshot().new_hp_notices > 0
			if not active and game.sim.wildlife.state == "healthy" and game.sim.status == "running":
				if not saw_retired: retirement_before_gate = game.sim.cargo_position().x < 1140.0
				saw_retired = true
				world_hud_agree = world_hud_agree and game.world.flight_nodes.cues.protected_bird_path.is_empty() and not game.hud.flight_labels.events.text.contains(Receipt.BIRD_DIRECTION_COPY)
			for event in game.sim.events:
				if str(event).ends_with(Receipt.BIRD_DIRECTION_COPY): raw_event_preserved = true
		check(game.sim.status == "success" and game.pilot_completed_ticks == int(source.completed_command_ticks),kind + " real recorded flight still reaches identical terminal tick")
		check(projection_read_only and world_hud_agree,kind + " Main passes exact sampled advice and observation never writes simulator fields")
		check(state(game.sim) == state(twin),kind + " full real-solver state equals untouched deterministic twin")
		check(saw_approach and raw_event_preserved,kind + " actual activation still creates visible guidance and unchanged historical event")
		if kind == "safe":
			check(saw_retired and retirement_before_gate,"safe whole-craft pass retires advice before next required gate")
			check(game.sim.wildlife.hp == 8.0 and game.sim.first_harm.is_empty(),"safe flight remains healthy with no harm fact")
		else:
			check(harm_feedback and not game.sim.first_harm.is_empty(),"real contact retains injury feedback and full harm fact")
		var report_events: Array = game._flight_report_events()
		check(report_events.any(func(event): return str(event).ends_with(Receipt.BIRD_DIRECTION_COPY)),kind + " report history keeps original directional event")
		check(ledger() == initial_ledger,kind + " read-only trial projection leaves financial/review ledgers unchanged")
		check(refresh(),kind + " repeated terminal projection remains read-only")
		check(not game.world.flight_nodes.protected_bird.cue_state().active,"terminal cannot resurrect guidance")
		game.world.leave_flight(); game.page = "hub"
	game.queue_free(); await process_frame
	print("PROTECTED_BIRD_CUE_CONTROLLER passed=%d failed=%d total=%d" % [passed,failed,passed+failed])
	quit(1 if failed else 0)
