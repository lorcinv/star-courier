extends RefCounted
## New bounded route identity. No Main/Economy registration is made here.
const VERSION = "pilot-pirate-drill-v1"
const ENCOUNTER_SCHEMA = "pirate-orbit-encounter-v1"
const ASCENT_SCHEMA = "pirate-ascent-encounter-v1"
const Actor = preload("res://scripts/pirate_actor_reconstructed_v1.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const V = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const COURIER_TYPES = ["cargo", "beam", "battery", "thruster", "armor", "coupler", "shield", "valve", "collision", "delay", "and_gate", "or_gate", "not_gate", "drill"]
const LAUNCHER_TYPES = ["spring", "battery", "beam"]

static func route(base: Dictionary = {}) -> Dictionary:
	var result = Extreme.route(base)
	var definition = Actor.example_definition()
	definition.id = "orbit_bumper_1"; definition.x = 35.0; definition.y = -4.0; definition.vy = 0.0625
	result.merge({"control_version": VERSION, "pilot_profile": VERSION, "mode": "pilot",
		"name": "近轨道试航 → 收货平台", "destination_name": "近轨道收货平台",
		"distance": 90.0, "destination_y": 0.0, "delivery_radius": 7.0, "max_delivery_speed": 14.0,
		"boundary_y": 25.0, "time_limit": 40.0, "deadline": 24.0, "pilot_altitude": 0.0,
		"pilot_cruise_speed": 8.0, "pilot_boost_speed": 12.0, "pilot_vertical_speed": 4.0,
		"hazards": [{"x": 50.0, "y": 0.0, "type": "rock", "radius": 0.5, "health": 80.0, "mass": 20.0}],
		"pilot_gates": [], "pirate_encounter": {"schema": ENCOUNTER_SCHEMA, "definition": definition, "warning_ticks": [180, 600]}}, true)
	return result

static func ascent_route(base: Dictionary = {}) -> Dictionary:
	# Fresh authored route. The original Extreme/Ascent factories and every old
	# saved order stay unchanged. Preserve their actual150m path and four gates.
	var result = Extreme.route(base)
	var definition = Actor.example_definition()
	definition.id = "ascent_bumper_1"; definition.x = 550.0; definition.y = -160.0; definition.vy = 0.03125
	result.merge({"control_version": VERSION, "pilot_profile": VERSION,
		"name": "城市升空 → 近轨护航收货站", "destination_name": "近轨护航收货站",
		"distance": 650.0, "deadline": 50.0,
		"pirate_encounter": {"schema": ASCENT_SCHEMA, "definition": definition, "warning_ticks": [3840,4320]}}, true)
	# Heading is display metadata only; steering derives its own continuous
	# path tangent. Author this NEW route's metadata on an exact binary grid so
	# ordinary durable JSON preserves it. No old route or physical gate moves.
	for gate in result.pilot_gates:
		gate.heading = snappedf(float(gate.heading), 1.0 / 1024.0)
	# A quiet185m segment follows the last inherited gate at465m. The single
	# drillable rock and coasting solid pirate use the already-reviewed owners.
	result.hazards.append({"x":585.0,"y":-150.0,"type":"rock","radius":0.5,"health":80.0,"mass":20.0})
	return result

static func shield_drill_design() -> Array:
	var design = Extreme.starter_design()
	for p in design:
		if p.id == 5:
			p.type = "drill"; p.param = 0.0; p.input_a = -2
	design.append(Extreme.part(9,"shield",-2,0))
	return design

static func preflight(design: Variant, launcher: Variant, data: Variant) -> Dictionary:
	if not _input_tree([design, launcher, data], 0, [0]): return V.fail("pirate_input_value_bound")
	var checked = route_error(data)
	if not checked.is_empty(): return V.fail(checked)
	checked = _design_error(design, COURIER_TYPES, true)
	if not checked.is_empty(): return V.fail(checked)
	checked = _design_error(launcher, LAUNCHER_TYPES, false)
	if not checked.is_empty(): return V.fail(checked)
	return {"ok": true, "control_version": VERSION}

static func route_error(data: Variant) -> String:
	if not _input_tree(data, 0, [0]): return "pirate_route_value_bound"
	if not data is Dictionary or data.get("control_version") != VERSION or data.get("pilot_profile") != VERSION or data.get("mode") != "pilot": return "pirate_route_identity"
	for key in ["wormhole_portal", "ecology", "traffic", "traffic_definition", "world_events", "events", "bird_route", "interceptors", "enemy_schedule"]:
		if data.has(key): return "unsupported_pirate_route_event:" + key
	var encounter_value: Variant = data.get("pirate_encounter")
	var ascent = encounter_value is Dictionary and encounter_value.get("schema") == ASCENT_SCHEMA
	if not data.get("hazards") is Array or data.hazards.size() > 64 or not data.get("pilot_gates", []) is Array or (not ascent and not data.get("pilot_gates", []).is_empty()): return "pirate_route_hazards"
	for h in data.hazards:
		if not h is Dictionary or h.get("type", "rock") != "rock": return "unsupported_pirate_hazard"
		for key in h:
			if not key in (["x", "y", "velocity", "radius", "health", "mass", "type", "destructible"] + (["pilot_gate", "gate_index"] if ascent else [])): return "unsupported_pirate_hazard_field:" + str(key)
		for key in ["x", "y"]:
			if not _number(h.get(key, 0.0), -10000.0, 10000.0): return "pirate_hazard_coordinate"
		var velocity: Variant = h.get("velocity", [0.0,0.0])
		if not velocity is Array or velocity.size() != 2 or not _number(velocity[0], -100.0, 100.0) or not _number(velocity[1], -100.0, 100.0): return "pirate_hazard_velocity"
		for key in ["radius", "health", "mass"]:
			if not _number(h.get(key), 0.001, 1000000.0): return "pirate_hazard_scalar"
		if h.has("destructible") and not h.destructible is bool: return "pirate_hazard_flag"
	for key in ["distance", "delivery_radius", "max_delivery_speed", "boundary_y", "time_limit"]:
		if not _number(data.get(key), 0.001, 10000.0): return "pirate_route_scalar:" + key
	if not _number(data.get("destination_y"), -10000.0, 10000.0): return "pirate_route_destination"
	# Both QA orbit and the inherited fictional ascent use real paid nozzles,
	# with no new gravity/traffic/portal subsystem.
	if data.get("gravity") != 0.0 or data.get("wind") != [0.0, 0.0] or data.get("variation") != 0.0 or (not ascent and data.get("pilot_altitude") != 0.0): return "unsupported_pirate_environment"
	for key in ["pilot_drag", "pilot_cruise_speed", "pilot_boost_speed", "pilot_vertical_speed", "pilot_net_force_limit", "pilot_battery_multiplier", "pilot_energy_tariff"]:
		if not _number(data.get(key), 0.0, 100.0): return "pirate_profile_scalar:" + key
	var encounter: Variant = data.get("pirate_encounter")
	if not V.exact(encounter, ["schema", "definition", "warning_ticks"]) or not encounter.schema in [ENCOUNTER_SCHEMA, ASCENT_SCHEMA]: return "pirate_encounter_shape"
	var actor = Actor.configure(encounter.definition)
	if not actor.ok: return actor.error
	if not encounter.warning_ticks is Array or encounter.warning_ticks.size() > 2: return "pirate_warning_schedule"
	var prior = -331
	for tick in encounter.warning_ticks:
		if not V.integer(tick, 0, 1200000) or int(tick) <= prior + 330: return "pirate_warning_schedule"
		prior = int(tick)
	if ascent: return _ascent_error(data)
	return ""

static func _design_error(design: Variant, allowed: Array, courier: bool) -> String:
	var prefix = "courier" if courier else "launcher"
	if not design is Array or design.size() > 192 or (courier and design.is_empty()): return "pirate_" + prefix + "_size"
	var ids: Dictionary = {}; var sockets: Dictionary = {}; var cargo = 0
	for p in design:
		if not p is Dictionary or not p.get("type") in allowed: return "unsupported_pirate_" + prefix + "_device"
		if not V.integer(p.get("id"), 0, 1000000) or ids.has(int(p.id)): return "pirate_" + prefix + "_identity"
		ids[int(p.id)] = true
		if not V.integer(p.get("x"), -100, 100) or not V.integer(p.get("y"), -100, 100) or not V.integer(p.get("rot", 0), 0, 3): return "pirate_" + prefix + "_socket"
		var socket = "%d:%d" % [int(p.x), int(p.y)]
		if sockets.has(socket): return "pirate_" + prefix + "_overlap"
		sockets[socket] = true
		if not _number(p.get("param"), -100000.0, 100000.0): return "pirate_" + prefix + "_parameter"
		for key in ["input_a", "input_b", "target"]:
			if not V.integer(p.get(key, -1), -2, 1000000): return "pirate_" + prefix + "_control"
		if p.type == "cargo": cargo += 1
	if courier and cargo != 1: return "pirate_exactly_one_cargo"
	return ""

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func _input_tree(value: Variant, depth: int, nodes: Array) -> bool:
	nodes[0] += 1
	if depth > 24 or nodes[0] > 12000: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING: return value.length() <= 4096
		TYPE_ARRAY:
			if value.size() > 256: return false
			for child in value:
				if not _input_tree(child, depth + 1, nodes): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 128: return false
			for key in value:
				if not (key is String or key is StringName) or str(key).length() > 128 or not _input_tree(value[key], depth + 1, nodes): return false
			return true
	return false

static func _ascent_error(data: Dictionary) -> String:
	# This branch accepts the newly authored immutable physics configuration,
	# not arbitrary gate metadata or a silently retagged legacy route. Economy
	# metadata, weight, research capacity and seed remain separate caller data.
	var authored = ascent_route()
	for key in ["distance","destination_y","delivery_radius","max_delivery_speed","boundary_y","time_limit","gravity","wind","variation","pilot_drag","pilot_cruise_speed","pilot_boost_speed","pilot_vertical_speed","pilot_net_force_limit","pilot_battery_multiplier","pilot_energy_tariff","pilot_altitude","pilot_climb_start","pilot_climb_end","lookahead_seconds","hazards","pilot_gates","pirate_encounter"]:
		if not data.has(key) or not _authored_equal(data[key], authored[key]): return "pirate_ascent_authoring:" + key
	return ""

static func _authored_equal(value: Variant, expected: Variant) -> bool:
	# Input was already bounded by _input_tree. This authored-route boundary
	# permits JSON's integer-to-float transport only for exactly equal numbers.
	# It neither repairs the caller nor touches typed native snapshot encoding.
	if (value is int or value is float) and (expected is int or expected is float):
		return is_finite(float(value)) and is_finite(float(expected)) and value == expected
	if typeof(value) != typeof(expected): return false
	if expected is Array:
		if value.size() != expected.size(): return false
		for i in expected.size():
			if not _authored_equal(value[i], expected[i]): return false
		return true
	if expected is Dictionary:
		if value.size() != expected.size(): return false
		for key in expected:
			if not value.has(key) or not _authored_equal(value[key], expected[key]): return false
		return true
	return value == expected
