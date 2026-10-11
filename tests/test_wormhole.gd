extends SceneTree
const Sim = preload("res://scripts/pilot_wormhole_simulation.gd")
const Profile = preload("res://scripts/pilot_wormhole_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
var failures: Array = []
var assertions = 0

func _initialize() -> void:
	if "--drill-only" in OS.get_cmdline_user_args():
		for motor in [true, false]: route_run(drill_design(motor, true), true, motor)
	elif "--shield-off" in OS.get_cmdline_user_args():
		route_run(drill_design(true, false), true, true)
	elif "--course" in OS.get_cmdline_user_args():
		_route_delivery()
	elif "--edge" in OS.get_cmdline_user_args():
		_profile(); _inherited_validation(); _transfer(); _rejections(); _separation(); _replay(); _preportal_parity()
	else:
		_profile(); _inherited_validation(); _transfer(); _rejections(); _separation(); _replay(); _preportal_parity(); _route_delivery()
	if failures.is_empty():
		print("DIAGNOSTIC ONLY: no assertions requested" if assertions == 0 else "PASS: %d staged wormhole assertions" % assertions); quit(0)
	else:
		for error in failures: printerr("FAIL: ", error)
		printerr("FAILED: %d/%d" % [failures.size(), assertions]); quit(1)

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)

func flat_route() -> Dictionary:
	var route = Profile.route()
	route.hazards = []; route.pilot_gates = []; route.pilot_drag = 0.0
	route.pilot_altitude = 0.0; route.destination_y = 0.0; route.distance = 320.0
	route.boundary_y = 500.0; route.wormhole_portal.entry = [20.0, 0.0]; route.wormhole_portal.exit = [200.0, 0.0]
	return route

func fixture(design: Array = [], route: Dictionary = {}):
	var sim = Sim.new()
	sim.configure([Extreme.part(1, "cargo", 0), Extreme.part(2, "battery", -1)] if design.is_empty() else design, [], flat_route() if route.is_empty() else route, 42)
	return sim

func initial_at(sim, x: float, velocity: Vector2 = Vector2(600.0, 0.0)) -> void:
	for body in sim.bodies: body.position.x += x; body.velocity = velocity

func _profile() -> void:
	var route = Profile.route({"contract_id": "D7-A", "client": "阿堇", "reward": 340})
	check(Profile.validation_error(route).is_empty(), "new profile is valid")
	check(Profile.route(route) == route, "new route authoring is idempotent")
	check(route.client == "阿堇" and route.contract_id == "D7-A" and route.reward == 340, "contract identity and commercial values preserved")
	check(route.control_version == "pilot-v4-wormhole", "new replay protocol has explicit identity")
	var quote = Profile.transit_quote(route, 10.2)
	check(quote.ok and quote.energy_source == "station" and absf(quote.estimated_j - 45.4) < 0.000001 and quote.station_capacity_j == 2000.0 and quote.max_centered_body_diameter_m == 25.75 and not quote.separate_settlement_debit, "preflight quote identifies finite station source and one combined debit")
	check(not Profile.transit_quote(route, NAN).ok, "nonfinite quote rejected")
	check(route.pilot_altitude == 150.0 and route.wormhole_portal.entry[0] > route.pilot_climb_end, "physical ascent precedes space and portal")
	var invalid = flat_route(); invalid.wormhole_portal.exit[0] = 21.0
	check(not Profile.validation_error(invalid).is_empty(), "overlapping portal endpoints rejected")
	invalid = flat_route(); invalid.wormhole_portal.aperture_radius = NAN
	check(not Profile.validation_error(invalid).is_empty(), "nonfinite portal rejected")
	for field in ["distance", "boundary_y", "destination_y"]:
		for malformed in [NAN, INF, -INF, "bad", null]:
			invalid = flat_route(); invalid[field] = malformed
			check(not Profile.validation_error(invalid).is_empty(), "malformed %s rejected before arithmetic" % field)
			var blocked = fixture([], invalid)
			check(blocked.status == "failed" and blocked.parts.is_empty() and is_finite(blocked.telemetry.energy_used), "malformed %s never initializes flight" % field)
	for endpoint in ["entry", "exit"]:
		for axis_index in [0, 1]:
			for malformed in [NAN, INF, "bad"]:
				invalid = flat_route(); invalid.wormhole_portal[endpoint][axis_index] = malformed
				check(not Profile.validation_error(invalid).is_empty(), "malformed portal %s axis%d rejected" % [endpoint, axis_index])
				check(fixture([], invalid).status == "failed", "malformed portal fails closed")
	var frozen = preload("res://scripts/pilot_extreme_profile.gd").route()
	check(frozen.control_version == "pilot-v3" and not frozen.has("wormhole_portal"), "frozen v3 profile untouched")

func _transfer() -> void:
	var sim = fixture(); initial_at(sim, 19.0)
	var before = sim.total_energy(); var initial_hp = sim.parts[1].hp
	var offset: Vector2 = sim.part_world_position(1) - sim.part_world_position(2)
	sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1 and sim.cargo_position().x > 204.0, "swept 600m/s event crosses aperture without tunnelling")
	check(sim.body_for_part(1).velocity == Vector2(600.0, 0.0), "momentum and velocity preserved")
	check(sim.total_energy() == before and sim.parts[1].hp == initial_hp, "onboard stored energy and HP preserved")
	check((sim.part_world_position(1) - sim.part_world_position(2)).is_equal_approx(offset), "rigid shape and structural offset preserved")
	check(absf(sim.telemetry.energy_used - (25.0 + sim.total_mass() * 2.0)) < 0.00001, "finite external station draw booked once")
	check(sim.telemetry.wormhole_station_remaining == 2000.0 - sim.telemetry.energy_used, "station reserve conserved")
	check(sim.telemetry.wormhole_phase == "otherworld", "actual transit marks otherworld state")
	check(sim.telemetry.energy_remaining == sim.total_energy(), "HUD onboard battery remaining excludes station reserve")
	var energy = sim.telemetry.energy_used
	# A disclosed fixture sends the same body across the same portal again.
	sim.body_for_part(1).position.x = 19.0
	sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1 and sim.telemetry.energy_used == energy, "same body cannot double transit or double bill")
	# A real graph rebuild must not erase visit history.
	sim._cut(1, 2); sim._rebuild_bodies()
	for body in sim.bodies: body.position.x = 19.0
	sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1, "cut fragments retain traversal lineage despite new body IDs")
	var splitting = fixture([Extreme.part(1, "cargo", -1), Extreme.part(2, "battery", 1), Extreme.part(3, "splitter", 0)])
	initial_at(splitting, 19.0); splitting.step(1.0 / 120.0)
	var station_before = splitting._station_remaining
	splitting._split_module(splitting.parts[3], splitting.parts[2], splitting.body_for_part(3), 1.0 / 120.0)
	var all_visited = true
	for p in splitting.parts.values(): all_visited = all_visited and p.get("wormhole_visits", {}).has("morning-mosslight")
	check(splitting.parts.size() == 4 and all_visited and splitting._station_remaining == station_before, "splitter clones inherit portal lineage without recharging station")

func _rejections() -> void:
	var wide: Array = []
	for x in range(-14, 15): wide.append(Extreme.part(x + 15, "cargo" if x == 0 else "armor", x))
	var sim = fixture(wide); initial_at(sim, 19.0, Vector2(300.0, 0.0)); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.is_empty() and sim.telemetry.get("wormhole_last_denial", "") == "too_large_or_off_center", "overlength craft is explicitly rejected as a whole")
	check(sim.bodies.size() == 1 and sim.telemetry.energy_used == 0.0, "oversize rejection does not cut body or bill")
	var route = flat_route(); route.hazards = [{"x": 202.0, "y": 0.0, "radius": 1.0, "health": 100.0}]
	sim = fixture([], route); initial_at(sim, 19.0); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.is_empty() and sim.telemetry.get("wormhole_last_denial", "") == "exit_blocked", "occupied exit rejects safely")
	route = flat_route(); route.hazards = [{"x": 260.0, "y": 0.0, "radius": 1.0, "health": 100.0}]
	sim = fixture([], route); initial_at(sim, 19.0); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.is_empty(), "600m/s exit trajectory checks future obstacle rather than spawn point only")
	route = flat_route(); route.wormhole_portal.station_energy_j = 1.0
	sim = fixture([], route); initial_at(sim, 19.0); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.is_empty() and sim.telemetry.get("wormhole_last_denial", "") == "station_empty" and sim.total_energy() == 6000.0, "empty station cannot borrow or replenish onboard energy")
	# Spin and pre-existing damage survive the jump unchanged.
	sim = fixture(); initial_at(sim, 19.0)
	sim.body_for_part(1).angle = 0.35; sim.body_for_part(1).angular_velocity = 2.0
	sim.parts[1].hp = 71.0
	sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1 and absf(sim.body_for_part(1).angle - (0.35 + 2.0 / 120.0)) < 0.00001 and sim.body_for_part(1).angular_velocity == 2.0 and sim.parts[1].hp == 71.0, "rotation, spin and pre-existing damage preserved")
	# No grace period: a later ordinary impact remains fully physical.
	route = flat_route(); route.distance = 1000.0
	route.hazards = [{"x": 400.0, "y": 0.0, "radius": 0.8, "health": 1000000.0}]
	sim = fixture([], route); initial_at(sim, 19.0); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 1, "clear near exit allows transfer even when a later rock exists")
	for tick in range(50): sim.step(1.0 / 120.0)
	check(sim.telemetry.swept_contacts > 0 and sim.parts[1].hp < 100.0, "post-exit impacts retain collision damage with no invulnerability")
	# A hazard before entry wins chronologically and is never skipped by a portal.
	route = flat_route(); route.hazards = [{"x": 19.0, "y": 0.0, "radius": 0.8, "health": 1000000.0}]
	sim = fixture([], route); initial_at(sim, 16.0); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.is_empty() and sim.telemetry.swept_contacts > 0, "physical impact before portal is resolved first")
	# Reaching otherworld coordinates without the portal never authorizes delivery.
	sim = fixture(); initial_at(sim, 205.0, Vector2.ZERO); sim.step(1.0 / 120.0)
	check(sim.status == "failed" and not sim.telemetry.delivered, "mounted-teleporter or bypass arrival cannot fake route completion")

func _separation() -> void:
	var sim = fixture([Extreme.part(1, "cargo", 0, -3), Extreme.part(2, "armor", 0, 3)])
	var mass = sim.total_mass()
	initial_at(sim, 19.0); sim.step(1.0 / 120.0)
	check(sim.wormhole_events.size() == 2 and sim.bodies.size() == 2, "two detached islands each transit once without welding")
	check(sim.total_mass() == mass and sim.body_for_part(1).velocity == sim.body_for_part(2).velocity, "detached bodies retain mass and momentum")
	check(sim.part_world_position(1).distance_to(sim.part_world_position(2)) > 5.9, "independent exit clearance avoids overlap")

func state(sim) -> Dictionary:
	var bodies: Array = []
	for b in sim.bodies: bodies.append([b.id, b.position, b.velocity, b.angle, b.angular_velocity])
	var modules: Array = []
	for p in sim.parts.values(): modules.append([p.id, p.hp, p.energy, p.alive, p.get("wormhole_visits", {})])
	return {"bodies": bodies, "modules": modules, "events": sim.wormhole_events, "energy": sim.telemetry.energy_used, "remaining": sim._station_remaining, "status": sim.status}

func _replay() -> void:
	var route = flat_route(); route.pilot_altitude = 0.0
	var design = Extreme.starter_design()
	var a = fixture(design, route); var timeline = Timeline.new()
	for tick in range(300):
		var command = {"axis_q": 0, "boost": false, "active": tick % 30 < 15}
		timeline.record(tick, command); a.set_pilot_input(0, false, command.active); a.step(1.0 / 60.0)
		if tick == 200:
			var paused = state(a).duplicate(true); a.step(0.0)
			check(state(a) == paused, "zero-step pause does not consume energy or retrigger portal")
	var stored: Dictionary = JSON.parse_string(JSON.stringify({"route": route, "design": design, "commands": timeline.snapshot(), "ticks": 300}))
	var b = fixture(stored.design, stored.route); var restored = Timeline.new()
	check(restored.restore(stored.commands, 300), "sparse timeline restores integer commands")
	for tick in range(300):
		var command = restored.state_at(tick); b.set_pilot_input(command.axis_q, command.boost, command.active); b.step(1.0 / 60.0)
	check(a.wormhole_events.size() == 1, "replay fixture really includes a portal crossing")
	check(state(a) == state(b), "JSON route and inputs replay exact portal event, pose, HP, energy and reserve")
	var before = state(a).duplicate(true)
	a.configure(design, [], route, 42)
	for tick in range(300):
		var command = restored.state_at(tick); a.set_pilot_input(command.axis_q, command.boost, command.active); a.step(1.0 / 60.0)
	check(state(a) == before, "restart clears station and traversal state before deterministic replay")

func guidance(sim, drill: bool = false) -> int:
	var pos: Vector2 = sim.cargo_position()
	var offset = 0.0
	for gate in sim.route.pilot_gates:
		if pos.x < float(gate.x) + 6.5:
			offset = float(gate.lane_offset); break
	# Local direct-line ore has a wide optional lane above it.
	if pos.x > 980.0 and pos.x < 1090.0: offset = 0.0 if drill else -6.0
	var normal = Ascent.path_tangent(pos.x, sim.route).orthogonal() * -1.0
	var body: Dictionary = sim._cargo_body()
	var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var lateral = velocity.dot(normal)
	var acceleration = float(sim.route.pilot_net_force_limit) / maxf(1.0, float(body.get("mass", 10.2)))
	var preview = lateral * (0.45 + absf(lateral) / (2.0 * acceleration * 0.9))
	var actual_y = pos.y
	if drill and pos.x > 980.0 and pos.x < 1090.0 and sim.parts[40].alive: actual_y = sim.part_world_position(40).y
	var error = Ascent.path_y(pos.x, sim.route) + offset - actual_y - preview
	return int(signf(error)) * 1000 if absf(error) > (0.08 if drill and pos.x > 980.0 and pos.x < 1090.0 else 0.9) else 0

func drill_design(motor: bool = true, shields: bool = true) -> Array:
	var build = Extreme.reinforced_design()
	build.append(Extreme.part(39, "beam", 2, 0))
	build.append(Extreme.part(40, "drill", 3, 0, {"input_a": -2}))
	for mount in [[41, 0, -2], [42, 1, -2], [43, 0, 2], [44, 1, 2]]:
		build.append(Extreme.part(mount[0], "shield", mount[1], mount[2], {"input_a": -1 if shields else 999999}))
	return build

func route_run(design: Array, drill: bool, motor: bool = true) -> Dictionary:
	var sim = Sim.new()
	var pad = Extreme.starter_launcher()
	if drill: pad[0].param = 18.0 # Legal spring setting: heavy nose build stays below the real32N beam load.
	sim.configure(design, pad, Profile.route({"weight": 1.0}), 42)
	var axis = 0; var min_ore_distance = INF; var initial_energy = sim.total_energy()
	for tick in range(6000):
		if tick % (3 if drill and sim.cargo_position().x > 980.0 and sim.cargo_position().x < 1090.0 else 12) == 0: axis = guidance(sim, drill)
		var ore_alive = false
		for hazard in sim.obstacles:
			if hazard.get("wormhole_ore", false) and hazard.health > 0.0: ore_alive = true
		sim.set_pilot_input(axis, false, drill and motor and ore_alive and sim.cargo_position().x > 1030.0); sim.step(1.0 / 60.0)
		for p in sim.parts.values():
			if ore_alive and p.alive: min_ore_distance = minf(min_ore_distance, sim.part_world_position(p.id).distance_to(Vector2(1080.0, -150.0)) - 3.0 - 0.43 * p.scale)
		if sim.status != "running": break
	var ore_health = -1.0
	for hazard in sim.obstacles:
		if hazard.get("wormhole_ore", false): ore_health = hazard.health
	var result = {"status": sim.status, "time": sim.elapsed, "transits": sim.wormhole_events.size(),
		"integrity": sim.ship_integrity(), "initial_energy": initial_energy, "remaining": sim.total_energy(),
		"energy_used": sim.telemetry.energy_used, "launcher_energy": sim.telemetry.launch_energy, "portal_energy": sim.telemetry.wormhole_energy_used,
		"ore_health": ore_health, "minimum_ore_clearance": min_ore_distance,
		"drill_damage": sim.telemetry.drill_damage, "shield_energy": sim.telemetry.impact_shield_energy,
		"drill_energy": sim.telemetry.drill_energy_used, "structure_damage": sim.telemetry.structure_damage,
		"drill_alive": sim.parts.get(40, {}).get("alive", false), "drill_hp": sim.parts.get(40, {}).get("hp", 0.0)}
	print("WORMHOLE_ROUTE ", JSON.stringify(result)); if sim.status != "success": print("EVENTS ", sim.events)
	return result

func _route_delivery() -> void:
	var standard = route_run(Extreme.starter_design(), false)
	check(standard.status == "success" and standard.transits == 1, "paid from-rest starter ascends, enters wormhole, dodges ore and reaches receiver")
	check(standard.integrity == 1.0 and standard.minimum_ore_clearance > 0.0 and standard.ore_health == 120.0, "starter safe dodge does not require drill or damage ore")
	var funded = route_run(drill_design(), true)
	check(funded.status == "success" and funded.transits == 1 and funded.ore_health <= 0.0, "funded drill/shield craft clears actual route ore and delivers")
	check(funded.drill_damage > 0.0 and funded.shield_energy > 0.0 and funded.drill_energy > 0.0 and funded.integrity == 1.0, "drill and shield advantage pays real energy and preserves cargo")
	check(funded.remaining >= 0.0 and funded.energy_used <= funded.initial_energy + funded.portal_energy + funded.launcher_energy + 0.001, "route stays within finite ship and station ledger")
	var motor_off = route_run(drill_design(false, true), true, false)
	check(motor_off.drill_damage == 0.0 and motor_off.ore_health > 0.0 and motor_off.status == "failed", "same direct nose build with motor off remains blocked by real ore")

func _preportal_parity() -> void:
	var route = Profile.route(); route.hazards = []; route.pilot_gates = []
	var a = Sim.new(); a.configure(Extreme.reinforced_design(), [], route, 42)
	var b = preload("res://scripts/pilot_extreme_simulation.gd").new()
	b.configure(Extreme.reinforced_design(), [], route, 42)
	var equal = true
	for tick in range(120):
		var axis = 0 if tick < 60 else -1000
		a.set_pilot_input(axis, true); b.set_pilot_input(axis, true)
		a.step(1.0 / 60.0); b.step(1.0 / 60.0)
		for id in a.parts:
			equal = equal and a.part_world_position(id) == b.part_world_position(id) and a.parts[id].hp == b.parts[id].hp and a.parts[id].energy == b.parts[id].energy
		equal = equal and a.telemetry.energy_used == b.telemetry.energy_used
	check(equal and a.wormhole_events.is_empty(), "pre-portal paid controls, overdrive, stress, HP and energy are exactly v3")

func _all_finite(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Vector2 or value is Vector3: return value.is_finite()
	if value is Dictionary:
		for item in value.values():
			if not _all_finite(item): return false
	if value is Array:
		for item in value:
			if not _all_finite(item): return false
	return true

func _reject_inherited(route: Dictionary, label: String) -> void:
	check(not Profile.validation_error(route).is_empty(), label + " rejected before inherited configure")
	var sim = fixture([], route)
	check(sim.status == "failed" and sim.parts.is_empty() and sim.bodies.is_empty(), label + " never initializes any craft parts")
	check(_all_finite(sim.telemetry) and sim.total_energy() == 0.0, label + " cannot leak NaN or infinite telemetry")

func _inherited_validation() -> void:
	var scalar_fields = ["weight", "time_limit", "deadline", "delivery_radius", "max_delivery_speed",
		"pilot_energy_tariff", "variation", "gravity", "pilot_drag", "pilot_cruise_speed", "pilot_boost_speed",
		"pilot_vertical_speed", "pilot_net_force_limit", "lookahead_seconds", "pilot_altitude",
		"pilot_climb_start", "pilot_climb_end", "battery_capacity_multiplier", "pilot_battery_multiplier",
		"required", "reward", "background_ground_y_m", "id", "rep", "seed"]
	for field in scalar_fields:
		for malformed in [NAN, INF, -INF, "4", true, null, [], {}]:
			var route = flat_route(); route[field] = malformed
			_reject_inherited(route, "malformed inherited " + field)
	for field in ["weight", "time_limit", "deadline", "delivery_radius", "pilot_energy_tariff", "battery_capacity_multiplier", "pilot_battery_multiplier", "required"]:
		for bad in [0.0, -1.0]:
			var route = flat_route(); route[field] = bad
			_reject_inherited(route, "nonpositive inherited " + field)
	for field in ["max_delivery_speed", "variation", "pilot_drag", "pilot_cruise_speed", "pilot_boost_speed", "pilot_vertical_speed", "pilot_net_force_limit", "lookahead_seconds", "reward"]:
		var route = flat_route(); route[field] = -1.0
		_reject_inherited(route, "negative inherited " + field)
	for field in ["id", "rep", "seed"]:
		var route = flat_route(); route[field] = 1.5
		_reject_inherited(route, "fractional integer " + field)
	for field in ["hazards", "pilot_gates"]:
		for bad in [null, true, 2.0, {}, "bad", [null], [3.0], [[]]]:
			var route = flat_route(); route[field] = bad
			_reject_inherited(route, "malformed collection " + field)
	for field in ["x", "y", "radius", "mass", "health", "cooldown", "strength", "range", "damage", "fire_interval"]:
		for bad in [NAN, INF, "3", true, null]:
			var hazard = {"position": [100.0, 100.0]}; hazard[field] = bad
			var route = flat_route(); route.hazards = [hazard]
			_reject_inherited(route, "malformed hazard " + field)
	for field in ["radius", "mass", "range", "damage", "fire_interval"]:
		var hazard = {}; hazard[field] = -1.0
		var route = flat_route(); route.hazards = [hazard]
		_reject_inherited(route, "negative hazard " + field)
	var zero_mass = flat_route(); zero_mass.hazards = [{"mass": 0.0}]
	_reject_inherited(zero_mass, "zero hazard mass")
	for bad_vector in [null, "bad", true, [], [0.0], [NAN, 0.0], [0.0, INF], {"x": NAN}, {"y": "bad"}, Vector2(INF, 0.0), Vector3(0.0, NAN, 0.0)]:
		var wind_route = flat_route(); wind_route.wind = bad_vector
		_reject_inherited(wind_route, "malformed wind")
		for field in ["position", "velocity"]:
			var hazard = {}; hazard[field] = bad_vector
			var route = flat_route(); route.hazards = [hazard]
			_reject_inherited(route, "malformed hazard vector " + field)
	for field in ["x", "y", "index", "half_gap", "heading", "lane_offset"]:
		for bad in [NAN, INF, "3", true, null]:
			var gate = {"x": 30.0, "y": 0.0, "index": 0, "half_gap": 5.0}; gate[field] = bad
			var route = flat_route(); route.pilot_gates = [gate]
			_reject_inherited(route, "malformed gate " + field)
	for field in ["x", "y", "index", "half_gap"]:
		var gate = {"x": 30.0, "y": 0.0, "index": 0, "half_gap": 5.0}; gate.erase(field)
		var route = flat_route(); route.pilot_gates = [gate]
		_reject_inherited(route, "missing gate " + field)
	for patch in [{"index": 0.5}, {"half_gap": -1.0}]:
		var gate = {"x": 30.0, "y": 0.0, "index": 0, "half_gap": 5.0}; gate.merge(patch, true)
		var route = flat_route(); route.pilot_gates = [gate]
		_reject_inherited(route, "invalid gate integer or clearance")
	# Every inherited optional field can remain omitted; defaults are not inserted.
	var omitted = flat_route()
	for field in scalar_fields + ["wind", "hazards", "pilot_gates"]: omitted.erase(field)
	var omitted_before = JSON.stringify(omitted, "", true, true)
	check(Profile.validation_error(omitted).is_empty(), "omitted optional scalar/vector/container fields retain inherited defaults")
	check(JSON.stringify(omitted, "", true, true) == omitted_before, "optional validation does not insert fields")
	var default_sim = fixture([], omitted)
	check(default_sim.status == "running" and default_sim.parts[1].mass == 3.0 and _all_finite(default_sim.telemetry), "omitted weight retains default1 and baseline3kg cargo")
	# Preserve legitimate legacy vector formats, signed forces and zero controls.
	for vector in [0.0, [1.0, -2.0], {"x": 1.0, "y": -2.0}, Vector2(1.0, -2.0), Vector3(1.0, -2.0, 3.0)]:
		var custom = flat_route(); custom.wind = vector; custom.gravity = -0.1; custom.pilot_altitude = -10.0
		custom.pilot_net_force_limit = 0.0; custom.pilot_drag = 0.0; custom.max_delivery_speed = 0.0
		custom.pilot_cruise_speed = 100000.0; custom.pilot_boost_speed = 200000.0
		custom.hazards = [{"position": vector, "velocity": vector, "health": 0.0, "cooldown": -1.0, "strength": -6.0, "radius": 0.0}]
		custom.pilot_gates = [{"x": 30.0, "y": -1.0, "index": 3.0, "half_gap": 0.0, "heading": -0.125, "lane_offset": -1.0}]
		var before = JSON.stringify(custom, "", true, true)
		check(Profile.validation_error(custom).is_empty() and JSON.stringify(custom, "", true, true) == before, "valid custom geometry and finite high speed settings preserved without a new cap")
		var sim = fixture([], custom)
		check(sim.status == "running" and not sim.parts.is_empty() and _all_finite(sim.telemetry), "valid custom route still configures finite physics")
	var standard = Profile.route({"id": 3, "weight": 2.4, "reward": 340, "required": 90.0, "rep": 7})
	var heavy = Profile.route({"id": 3, "weight": 3.72, "reward": 395, "required": 90.0, "rep": 7}); heavy.deadline = 75.0
	var routes = [Profile.route(), flat_route(), standard, heavy]
	var old_hashes = ["152795d4258d23e82243ed8a4f30f0bd2116e205a3327fc2064a3efacd9217b5", "b3b08d3da8e9b8242302cb4a35cd0b4ddf7575d61ccd5f47cecd490e74c453d6", "340e37f2845b342b2b0364492126ca3cf217c238a82d3ffaec5c202488315626", "07c9de24780d5ab140c24b7d4e50e04d194a1252a42f5cd744f0b8ba8f717d83"]
	for i in range(routes.size()):
		var serialized = JSON.stringify(routes[i], "", true, true)
		check(serialized.sha256_text() == old_hashes[i], "valid authored route bytes match pre-revision baseline%d" % i)
		check(Profile.validation_error(routes[i]).is_empty() and JSON.stringify(routes[i], "", true, true) == serialized, "validator leaves valid authored route%d byte-identical" % i)
