extends RefCounted
## Bounded, simulator-only replay interface. No save/ledger/economy integration.
## Stored telemetry, warnings and historical harm copies are never inputs.
const Simulator = preload("res://scripts/pilot_protected_bird_simulation.gd")
const ProfileV5 = preload("res://scripts/pilot_protected_bird_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Design = preload("res://scripts/protected_bird_design_v1.gd")
const SCHEMA = "protected-bird-replay-v1"
const KEYS = ["schema", "control_version", "route", "design", "launcher", "seed", "completed_command_ticks", "commands"]

static func snapshot(data: Dictionary, design: Array, launcher: Array, seed: int, completed_ticks: int, commands: Array) -> Dictionary:
	return {"schema": SCHEMA, "control_version": ProfileV5.CONTROL_VERSION,
		"route": data.duplicate(true), "design": design.duplicate(true), "launcher": launcher.duplicate(true),
		"seed": seed, "completed_command_ticks": completed_ticks, "commands": commands.duplicate(true)}

static func restore(value: Variant) -> Dictionary:
	if not value is Dictionary: return {"ok": false, "state": "malformed", "error": "replay_object"}
	if not value.get("schema") is String or not value.get("control_version") is String: return {"ok": false, "state": "malformed", "error": "replay_identity_type"}
	if not ProfileV5.same_value(value.schema, SCHEMA) or not ProfileV5.same_value(value.control_version, ProfileV5.CONTROL_VERSION):
		return {"ok": false, "state": "unsupported", "opaque": value.duplicate(true)}
	if not ProfileV5.exact_keys(value, KEYS): return {"ok": false, "state": "malformed", "error": "replay_keys"}
	if not value.route is Dictionary or not ProfileV5.validation_error(value.route).is_empty(): return {"ok": false, "state": "malformed", "error": "replay_route"}
	var design_error = Design.validation_error(value.design, value.launcher)
	if not design_error.is_empty(): return {"ok": false, "state": "malformed", "error": design_error}
	if not ProfileV5._finite_integer(value.seed) or float(value.seed) < 0.0 or float(value.seed) > 2147483647.0 or int(value.seed) != int(value.route.seed):
		return {"ok": false, "state": "malformed", "error": "replay_seed"}
	if not ProfileV5._finite_integer(value.completed_command_ticks) or float(value.completed_command_ticks) < 0.0 or float(value.completed_command_ticks) > 6000.0:
		return {"ok": false, "state": "malformed", "error": "replay_tick"}
	# Bound and type-check raw commands before the frozen timeline can cast.
	if not value.commands is Array or value.commands.is_empty() or value.commands.size() > 6001: return {"ok": false, "state": "malformed", "error": "replay_commands"}
	for command in value.commands:
		if not command is Dictionary or not ProfileV5.exact_keys(command, ["tick", "axis_q", "boost", "active"]): return {"ok": false, "state": "malformed", "error": "replay_command_keys"}
		if not ProfileV5._finite_integer(command.tick) or float(command.tick) < 0.0 or float(command.tick) > float(value.completed_command_ticks): return {"ok": false, "state": "malformed", "error": "replay_command_tick"}
		if not ProfileV5._finite_integer(command.axis_q) or absf(float(command.axis_q)) > 1000.0 or not command.boost is bool or not command.active is bool: return {"ok": false, "state": "malformed", "error": "replay_command_state"}
	var timeline = Timeline.new()
	if not timeline.restore(value.commands, int(value.completed_command_ticks)): return {"ok": false, "state": "malformed", "error": "replay_commands"}
	var sim = Simulator.new()
	sim.configure(value.design, value.launcher, value.route, int(value.seed))
	for command_tick in range(int(value.completed_command_ticks)):
		if sim.status != "running": return {"ok": false, "state": "malformed", "error": "replay_past_terminal"}
		var state: Dictionary = timeline.state_at(command_tick)
		sim.set_pilot_input(int(state.axis_q), bool(state.boost), bool(state.active))
		sim.step(1.0 / 60.0)
	if not sim.wildlife_error.is_empty(): return {"ok": false, "state": "invalid_simulation", "error": sim.wildlife_error}
	# Historical cosmetic rays/hit flashes must not restart on resume. HP, hurt
	# state and simulation clocks remain reconstructed, authoritative state.
	sim.effects.clear()
	sim.set_paused(true)
	return {"ok": true, "state": "paused", "simulator": sim, "completed_command_ticks": int(value.completed_command_ticks)}
