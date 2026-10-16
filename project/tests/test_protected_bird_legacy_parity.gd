extends SceneTree
const NewSim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const OldSim = preload("res://scripts/pilot_wormhole_simulation.gd")
const Bird = preload("res://scripts/pilot_protected_bird_profile.gd")
const Old = preload("res://scripts/pilot_wormhole_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
var checks = 0
var failures = 0

func _init() -> void:
	var a = NewSim.new(); var b = OldSim.new()
	a.configure(Extreme.reinforced_design(), [], Bird.route({}, "PARITY", 42), 42)
	b.configure(Extreme.reinforced_design(), [], Old.route(), 42)
	for tick in range(120):
		var axis = 0 if tick < 60 else -1000
		a.set_pilot_input(axis, true, false); b.set_pilot_input(axis, true, false)
		a.step(1.0 / 60.0); b.step(1.0 / 60.0)
		for id in a.parts:
			check(a.part_world_position(id) == b.part_world_position(id), "Pre-portal position parity")
			check(a.parts[id].hp == b.parts[id].hp and a.parts[id].energy == b.parts[id].energy, "Pre-portal HP/power parity")
		check(a.telemetry.energy_used == b.telemetry.energy_used and a.status == b.status, "Pre-portal costs/status parity")
	check(not a.wildlife.activated and a.first_harm.is_empty(), "Before activation no ecology mutation")
	# Identical ordinary obstacle collision after fixture placement, before bird
	# activation. The profile's ore omission has no influence on this event.
	a = NewSim.new(); b = OldSim.new()
	var design = [Extreme.part(1, "cargo", 0)]
	a.configure(design, [], Bird.route({}, "PARITY", 42), 42)
	b.configure(design, [], Old.route(), 42)
	for sim in [a, b]:
		sim.body_for_part(1).position = Vector2(104.0, -7.728515625)
		sim.body_for_part(1).velocity = Vector2(120.0, 0.0)
		sim.step(1.0 / 120.0)
	check(a.parts[1].hp == b.parts[1].hp and a.part_world_position(1) == b.part_world_position(1), "Ordinary real gate collision parity")
	check(a.body_for_part(1).get("velocity") == b.body_for_part(1).get("velocity"), "Ordinary impulse remains frozen")
	print("PROTECTED_BIRD_LEGACY_PARITY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
