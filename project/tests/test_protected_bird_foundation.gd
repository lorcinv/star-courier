extends SceneTree
const Sim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const BirdProfile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Facts = preload("res://scripts/protected_bird_facts_v1.gd")
const Sweep = preload("res://scripts/wildlife_sweep_v1.gd")
const Replay = preload("res://scripts/protected_bird_replay_v1.gd")
var checks = 0
var failures = 0

func _init() -> void:
	var constructor_error = BirdProfile.validation_error(BirdProfile.route({}, "D4-A", 42))
	if not constructor_error.is_empty():
		check(false, "Native route prerequisite: " + constructor_error)
		quit(1); return
	profile_tests()
	sweep_tests()
	contact_tests()
	attribution_tests()
	weapon_tests()
	edge_tests()
	discontinuity_tests()
	replay_tests()
	print("PROTECTED_BIRD_FOUNDATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func profile_tests() -> void:
	var route = BirdProfile.route({}, "D4-A", 42)
	check(BirdProfile.validation_error(route).is_empty(), "Known profile validates")
	check(route.hazards.size() == 14 and not route.hazards.any(func(h): return h.get("wormhole_ore", false)), "Ore collider absent; real portal/final gate retained")
	check(BirdProfile.validation_error(JSON.parse_string(JSON.stringify(route))).is_empty(), "JSON roundtrip preserves known route")
	for path in ["mass", "radius", "max_hp", "seed"]:
		var changed = route.duplicate(true); changed.ecology[path] = NAN
		check(not BirdProfile.validation_error(changed).is_empty(), "Nonfinite event rejected: " + path)
	for value in [42.5, -1, INF]:
		var changed = route.duplicate(true); changed.seed = value
		check(not BirdProfile.validation_error(changed).is_empty(), "Invalid realized seed rejected")
	var changed = route.duplicate(true); changed.ecology.position = [1080.0, -150.0]
	check(not BirdProfile.validation_error(changed).is_empty(), "Hidden bird retarget rejected")
	changed = route.duplicate(true); changed.ecology.bird_hits = 1
	check(not BirdProfile.validation_error(changed).is_empty(), "Unknown event fields rejected")
	changed = route.duplicate(true); changed.hazards[0].position = [1120.0, -153.0]
	check(not BirdProfile.validation_error(changed).is_empty(), "Hidden hazard position override rejected")
	changed = route.duplicate(true); changed.control_version = "pilot-v4-wormhole"
	check(not BirdProfile.validation_error(changed).is_empty(), "Old protocol cannot instantiate v5")
	var sim = Sim.new(); sim.configure(Extreme.starter_design(), [], changed, 42)
	check(sim.status == "failed" and sim.wildlife_result().is_empty(), "Malformed route fails before bird exists")

func sweep_tests() -> void:
	var hit = Sweep.solve(Vector2(-100, 0), Vector2(100, 0), 0, 0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.805)
	check(hit.state == "hit" and absf(hit.time - 0.495975) < 0.00001, "Fast translation is swept")
	var miss = Sweep.solve(Vector2(-100, 0.81), Vector2(100, 0.81), 0, 0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.805)
	check(miss.state == "miss", "Epsilon outside circle is a true near miss")
	var tangent = Sweep.solve(Vector2(-2, 1), Vector2(2, 1), 0, 0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 1.0)
	check(tangent.state == "hit" and absf(tangent.normal.dot(Vector2.RIGHT)) < 0.000001, "Exact linear tangent has no closing normal velocity")
	var rotating = Sweep.solve(Vector2.ZERO, Vector2.ZERO, -PI * 0.5, PI * 0.5, Vector2(2, 0), Vector2(2, 0), Vector2(2, 0), 0.5)
	check(rotating.state == "hit" and rotating.distance <= 0.5, "Rotating limb reaches a real circle")
	var outside = Sweep.solve(Vector2.ZERO, Vector2.ZERO, -PI, PI, Vector2(2, 0), Vector2(2.51, 0), Vector2(2.51, 0), 0.5)
	check(outside.state == "miss", "Inflated rotation hull alone cannot cause harm")
	var turns = Sweep.solve(Vector2.ZERO, Vector2.ZERO, 0, PI * 24.0, Vector2(2, 0), Vector2(0, 2), Vector2(0, 2), 0.3)
	check(turns.state == "hit" and turns.distance <= 0.3 and turns.time < 1.0 / 24.0, "Multiple rotations find first real overlap")

## Explicit fixtures isolate physics. They are not evidence of playable input.
func fixture(design: Array = []) -> Variant:
	var sim = Sim.new()
	var actual = design if not design.is_empty() else [Extreme.part(1, "cargo", 0)]
	sim.configure(actual, [], BirdProfile.route({}, "D4-A", 42), 42)
	check(sim.status == "running" and sim.wildlife_error.is_empty(), "Fixture configured")
	# Test-only local geometry/power isolation. Saved route remains canonical.
	sim.obstacles.clear(); sim.route.gravity = 0.0; sim.route.pilot_drag = 0.0
	sim.wildlife.active = true; sim.wildlife.activated = true; sim.wildlife.state = "healthy"
	sim.wildlife.activation_tick = 0; sim.wildlife.position = Vector2(1100, -150); sim.wildlife.velocity = Vector2.ZERO
	for b in sim.bodies: b.position += Vector2(1090, -150)
	for p in sim.parts.values(): p.wormhole_visits = {"morning-mosslight": true}
	return sim

func contact_tests() -> void:
	var sim = fixture()
	var body: Dictionary = sim.body_for_part(1)
	body.position = Vector2(1099, -150); body.velocity = Vector2(120, 0)
	var before_hp: float = sim.parts[1].hp
	var momentum: Vector2 = body.velocity * body.mass
	sim.step(1.0 / 120.0)
	check(sim.wildlife.hp == 0.0 and sim.first_harm.source.part_id == 1, "Real swept body contact creates clamped first harm")
	check(body.velocity.x > 100.0 and sim.parts[1].hp == before_hp, "Small bird neither wall-stops ship nor damages its hull")
	check((body.velocity * body.mass + sim.wildlife.velocity * sim.wildlife.mass - momentum).length() < 0.001, "Real simulator contact conserves linear momentum")
	check(sim.first_harm.physics_tick == 1 and sim.first_harm.substep_fraction > 0.0, "Fact uses 120 Hz tick and within-tick event position")
	var original = sim.first_harm.duplicate(true)
	sim.step(1.0 / 60.0)
	check(sim.wildlife.damage_transitions == 1 and sim.first_harm == original, "Dead body cannot cause a second harm")
	for mode in ["miss", "separating", "gentle", "tangent"]:
		var safe = fixture(); var b: Dictionary = safe.body_for_part(1)
		b.position = Vector2(1099.19, -150)
		b.velocity = Vector2(1, 0)
		if mode == "miss": b.position = Vector2(1099, -149.19); b.velocity = Vector2(120, 0)
		elif mode == "separating": b.position = Vector2(1099.2, -150); b.velocity = Vector2(-5, 0)
		elif mode == "tangent": b.position = Vector2(1099, -149.195); b.velocity = Vector2(120, 0)
		safe.step(1.0 / 120.0)
		check(safe.first_harm.is_empty() and safe.wildlife.hp == 8.0, mode + " creates no harm")
		check(safe.wildlife_error.is_empty(), mode + " resolves without infinite zero-time loop")
	var paused = fixture(); var at: Vector2 = paused.wildlife.position
	paused.set_paused(true); paused.step(1.0); paused.step(1.0)
	check(paused.pilot_tick == 0 and paused.wildlife.position == at and paused.first_harm.is_empty(), "Pause freezes wildlife and facts")

func attribution_tests() -> void:
	var sim = fixture(); sim.pilot_tick = 1; sim._action_ordinal = 1
	check(sim._damage_wildlife(0.0, sim._source(sim.parts[1], "contact")) == 0.0 and sim.first_harm.is_empty(), "Zero HP loss creates no fact")
	sim._damage_wildlife(0.25, {"owner_kind": "environment"})
	check(sim.wildlife.hp == 7.75 and sim.first_harm.is_empty(), "Non-courier damage does not blame player")
	sim._damage_wildlife(0.5, sim._source(sim.parts[1], "contact"))
	check(sim.first_harm.hp_before == 7.75 and sim.first_harm.hp_after == 7.25 and sim.first_harm.hp_delta == 0.5, "Fact records real transition after other damage")
	var original = sim.first_harm.duplicate(true)
	sim._damage_wildlife(1.0, sim._source(sim.parts[1], "contact"))
	check(sim.first_harm == original and sim.wildlife_result().harms.size() == 1, "Repeated damage stays one cause")
	check(Facts.validation_error(sim.wildlife_result(), sim.route, sim.source_registry).is_empty(), "Canonical result validates against registry")
	for key in ["hp_delta", "physics_tick", "event_id", "source"]:
		var bad = sim.wildlife_result()
		if key == "source": bad.harms[0].source.part_id = 99999
		elif key == "event_id": bad.harms[0][key] = "wrong"
		else: bad.harms[0][key] = -1
		check(not Facts.validation_error(bad, sim.route, sim.source_registry).is_empty(), "Fact tampering rejected: " + key)
	var future = sim.wildlife_result(); future.schema = "protected-bird-harm-v99"
	check(Facts.classify(future) == "unsupported", "Future fact remains unsupported")
	var clone = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "splitter", 1), Extreme.part(3, "battery", 2)])
	clone.pilot_tick = 1
	clone._split_module(clone.parts[2], clone.parts[3], clone.body_for_part(2), 1.0 / 120.0)
	var child_id = int(clone._next_id) - 1
	check(child_id > 3 and clone.source_registry.has(child_id) and clone.parts[child_id].origin_part_id == 3, "Split child has deterministic actual ID and launch lineage")
	clone._damage_wildlife(0.5, clone._source(clone.parts[child_id], "contact"))
	check(clone.first_harm.source.part_id == child_id and clone.first_harm.source.origin_part_id == 3, "Split source records actual and original part")

func weapon_tests() -> void:
	for kind in ["lance", "arc"]:
		var sim = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, kind, 1, 0, {"param": 12.0}), Extreme.part(3, "battery", -1)])
		sim.step(1.0 / 120.0)
		check(not sim.first_harm.is_empty() and sim.first_harm.source.action_kind == kind and sim.telemetry.energy_used > 0.0, "Paid " + kind + " hits real bird")
		var blocked = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, kind, 1, 0, {"param": 12.0}), Extreme.part(3, "battery", -1)])
		blocked.obstacles.append({"position": Vector2(1095, -150), "radius": 1.0, "health": 100.0, "type": "rock", "velocity": Vector2.ZERO, "mass": 20.0, "conductive": true})
		blocked.step(1.0 / 120.0)
		check(blocked.first_harm.is_empty() and blocked.obstacles[0].health < 100.0, "Closer obstacle occludes " + kind)
		var unpowered = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, kind, 1, 0, {"param": 12.0})])
		unpowered.step(1.0 / 120.0)
		check(unpowered.first_harm.is_empty(), "No paid power means no " + kind + " harm")
	var bomb = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "bomb", 1, 0, {"param": 5.0})])
	bomb.wildlife.position = bomb.part_world_position(2) + Vector2(4, 0)
	bomb.trigger(2); bomb.step(1.0 / 120.0)
	check(not bomb.parts[2].alive and bomb.first_harm.source.action_kind == "bomb" and bomb.first_harm.source.part_id == 2, "Consumed bomb retains real source")
	var outside = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "bomb", 1, 0, {"param": 5.0})])
	outside.wildlife.position = outside.part_world_position(2) + Vector2(5.376, 0)
	outside.trigger(2); outside.step(1.0 / 120.0)
	check(outside.first_harm.is_empty(), "Outside real bomb falloff is harmless")
	for powered in [false, true]:
		var design = [Extreme.part(1, "cargo", 0), Extreme.part(2, "drill", 1)]
		if powered: design.append(Extreme.part(3, "battery", -1))
		var drill = fixture(design)
		drill.wildlife.position = drill.part_world_position(2) + Vector2(0.83, 0)
		drill.step(1.0 / 120.0)
		check(drill.first_harm.is_empty() != powered, "Drill only cuts with paid tip contact")
		if powered: check(drill.first_harm.source.action_kind == "drill" and drill.telemetry.drill_contacts == 1, "Drill wins tip contact and spends once per tick")

func discontinuity_tests() -> void:
	var sim = Sim.new(); sim.configure([Extreme.part(1, "cargo", 0)], [], BirdProfile.route({}, "D4-A", 42), 42)
	var b: Dictionary = sim.body_for_part(1)
	b.position = Vector2(599.9, -150); b.velocity = Vector2(24, 0)
	sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1 and sim.wildlife.activated, "Actual cargo portal crossing activates bird once")
	check(sim.wildlife.activation_fraction > 0.0 and sim.wildlife.position.x > 1119.97, "Activation advances only remaining substep")
	check(sim.first_harm.is_empty(), "Portal skipped gap produces no phantom contact")
	sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1, "No duplicate portal activation")
	var leading = Sim.new(); leading.configure([Extreme.part(1, "cargo", 0), Extreme.part(2, "armor", 3)], [], BirdProfile.route({}, "D4-A", 42), 42)
	var detached: Dictionary = leading.body_for_part(2)
	detached.position = Vector2(599.9, -150); detached.velocity = Vector2(24, 0)
	leading.step(1.0 / 120.0)
	check(leading.wormhole_events.size() == 1 and not leading.wildlife.activated, "Detached non-cargo cannot activate early")
	var tele = fixture(); var tb: Dictionary = tele.body_for_part(1)
	var delta: Vector2 = tele.wildlife.position - tb.position
	check(not tele.destination_clear(tb, delta) and tele.first_harm.is_empty(), "Live bird blocks teleport destination without HP loss")
	check(tele.destination_clear(tb, delta + Vector2(20, 0)), "Bird only in skipped teleport gap does not block")

func replay_tests() -> void:
	var route = BirdProfile.route({}, "D4-A", 42)
	var design = Extreme.starter_design(); var launcher = Extreme.starter_launcher()
	var commands = [{"tick": 0, "axis_q": 0, "boost": false, "active": false}]
	var sim = Sim.new(); sim.configure(design, launcher, route, 42)
	for i in range(12): sim.step(1.0 / 60.0)
	var replay = Replay.restore(Replay.snapshot(route, design, launcher, 42, 12, commands))
	check(replay.ok and replay.simulator.paused, "Resume reconstructs and starts paused")
	if replay.ok:
		check(replay.simulator.pilot_tick == 24 and replay.completed_command_ticks == 12, "Physics ticks differ from command checkpoint")
		check(replay.simulator.wildlife_result() == sim.wildlife_result() and replay.simulator.cargo_position() == sim.cargo_position() and replay.simulator.total_energy() == sim.total_energy(), "Exact saved inputs reconstruct state and facts")
		var at: Vector2 = replay.simulator.cargo_position(); replay.simulator.step(1.0)
		check(at == replay.simulator.cargo_position(), "Paused restore cannot advance on stale frame")
	var injected = Replay.snapshot(route, design, launcher, 42, 12, commands); injected.wildlife_result = {"bird_hits": 12}
	check(not Replay.restore(injected).ok, "Stored presentation/harm copies cannot enter replay")
	var future = Replay.snapshot(route, design, launcher, 42, 12, commands); future.control_version = "pilot-v99"
	var opaque = Replay.restore(future)
	check(not opaque.ok and opaque.state == "unsupported" and opaque.opaque == future, "Future replay remains opaque and unmodified")

func edge_tests() -> void:
	# A detached courier part really moves into the animal; the launcher module
	# and unrelated damage counters cannot substitute for this physical source.
	var detached = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "armor", 3)])
	var projectile: Dictionary = detached.body_for_part(2)
	projectile.position = Vector2(1099, -150); projectile.velocity = Vector2(120, 0)
	detached.step(1.0 / 120.0)
	check(not detached.first_harm.is_empty() and detached.first_harm.source.part_id == 2 and detached.first_harm.source.origin_part_id == 2, "Detached body reports contacting module")
	var split = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "splitter", 1), Extreme.part(3, "battery", 2)])
	split._split_module(split.parts[2], split.parts[3], split.body_for_part(2), 1.0 / 120.0)
	var child_id = int(split._next_id) - 1
	var child: Dictionary = split.body_for_part(child_id)
	child.position = Vector2(1099, -150); child.velocity = Vector2(120, 0)
	split.step(1.0 / 120.0)
	check(not split.first_harm.is_empty() and split.first_harm.source.part_id == child_id and split.first_harm.source.origin_part_id == 3, "Actual split-body collision retains lineage")
	for powered in [false, true]:
		var shield = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "shield", -1, 0, {"input_a": -1 if powered else 99999}), Extreme.part(3, "battery", -2)])
		var b: Dictionary = shield.body_for_part(1)
		b.position += Vector2(1099, -150) - shield.part_world_position(1)
		b.velocity = Vector2(120, 0)
		var hp: float = shield.parts[1].hp; var energy: float = shield.total_energy()
		shield.step(1.0 / 120.0)
		check(not shield.first_harm.is_empty() and shield.parts[1].hp == hp and shield.total_energy() == energy and shield.telemetry.impact_shield_energy == 0.0, "Shield does not erase bird harm or add bird collision drain")
	var shield_miss = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "shield", -1), Extreme.part(3, "battery", -2)])
	shield_miss.wildlife.position = shield_miss.part_world_position(1) + Vector2(0.81, 0)
	shield_miss.step(1.0 / 120.0)
	check(shield_miss.first_harm.is_empty() and shield_miss.wildlife.hp == 8.0, "Shield visual range creates no invisible kill radius")
	var unrelated = fixture()
	unrelated.pilot_tick = 1
	unrelated._damage_part(unrelated.parts[1], 0.5, "attack")
	unrelated._effect("arc", unrelated.wildlife.position, unrelated.wildlife.position + Vector2.ONE, 0.1)
	unrelated.telemetry.bird_hits = 100
	unrelated.telemetry.swept_contacts = 100
	check(unrelated.wildlife.hp == 8.0 and unrelated.wildlife_result().harms.is_empty(), "Attack incidents, effects and legacy counters cannot create bird facts")
	# A closer detached module occludes both ray types and preserves ordinary
	# graph-following arc behavior. Wildlife is not an extra conductive node.
	for kind in ["lance", "arc"]:
		var blocked = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, kind, 1, 0, {"param": 12.0}), Extreme.part(3, "battery", -1), Extreme.part(4, "armor", 5)])
		var armor_hp: float = blocked.parts[4].hp
		blocked.step(1.0 / 120.0)
		check(blocked.first_harm.is_empty() and blocked.parts[4].hp < armor_hp, "Detached module occludes " + kind)
	var arc = fixture([Extreme.part(1, "cargo", 0), Extreme.part(2, "arc", 1, 0, {"param": 12.0}), Extreme.part(3, "battery", -1)])
	arc.obstacles.append({"position": Vector2(1095, -150), "radius": 0.5, "health": 100.0, "type": "rock", "velocity": Vector2.ZERO, "mass": 20.0, "conductive": true})
	arc.obstacles.append({"position": Vector2(1096, -148), "radius": 0.5, "health": 100.0, "type": "rock", "velocity": Vector2.ZERO, "mass": 20.0, "conductive": true})
	arc.step(1.0 / 120.0)
	check(arc.obstacles[0].health < 100.0 and arc.obstacles[1].health < 100.0 and arc.first_harm.is_empty(), "Ordinary conductive chain remains intact without bird bridge")
	# Exercise replay pre-constructor rejection rather than inherited sanitizing.
	var route = BirdProfile.route({}, "D4-A", 42)
	var commands = [{"tick": 0, "axis_q": 0, "boost": false, "active": false}]
	for mode in ["type", "param", "unknown", "missing", "fractional"]:
		var design = Extreme.starter_design()
		if mode == "type": design[0].type = "future_bird_cannon"
		elif mode == "param": design[0].param = 999.0
		elif mode == "unknown": design[0].owner_kind = "environment"
		elif mode == "missing": design[0].erase("rot")
		else: design[0].id = 0.5
		check(not Replay.restore(Replay.snapshot(route, design, [], 42, 0, commands)).ok, "Strict replay rejects " + mode + " instead of normalizing")
	for mode in ["missing", "mixed", "gap", "heading"]:
		var changed = route.duplicate(true)
		if mode == "missing": changed.erase("hazards")
		elif mode == "mixed": changed.moon_schema = 1
		elif mode == "gap": changed.pilot_gates[0].half_gap = 999.0
		else: changed.pilot_gates[0].heading += 0.01
		check(not BirdProfile.validation_error(changed).is_empty(), "Fixed route rejects " + mode)
