extends RefCounted
## pilot-v2 is a fictional short ascent lane, not a scale model of orbit.
## Frozen v1 snapshots continue to use pilot_profile.gd and pilot_simulation.gd.
const MODE = "pilot"
const CONTROL_VERSION = "pilot-v2"
const COCKPIT_SIGNAL = -2
const COMMAND_HZ = 60
const AXIS_SCALE = 1000
const PHYSICS_HZ = 120
const CRUISE_SPEED = 18.0
const BOOST_SPEED = 22.0
const VERTICAL_SPEED = 5.0
const LOOKAHEAD_SECONDS = 3.5
const BATTERY_MULTIPLIER = 20.0
const ENERGY_TARIFF = 0.025
const NET_FORCE_LIMIT = 30.0
const DISTANCE = 520.0
const ALTITUDE = 150.0
const CLIMB_START = 35.0
const CLIMB_END = 410.0

static func route(base_route: Dictionary = {}) -> Dictionary:
	var result = base_route.duplicate(true)
	result.merge({"mode": MODE, "control_version": CONTROL_VERSION, "pilot_profile": CONTROL_VERSION,
		"name": "城市升空 → 晨星轨道站", "destination_name": "晨星轨道站", "distance": DISTANCE,
		"destination_y": -ALTITUDE, "delivery_radius": 9.0, "max_delivery_speed": 24.0,
		"boundary_y": 230.0, "time_limit": 70.0, "deadline": 48.0, "gravity": 0.0, "wind": [0.0, 0.0],
		"variation": 0.0, "pilot_drag": 0.025, "pilot_cruise_speed": CRUISE_SPEED,
		"pilot_boost_speed": BOOST_SPEED, "pilot_vertical_speed": VERTICAL_SPEED,
		"pilot_net_force_limit": NET_FORCE_LIMIT, "pilot_battery_multiplier": BATTERY_MULTIPLIER,
		"pilot_energy_tariff": ENERGY_TARIFF, "pilot_altitude": ALTITUDE,
		"pilot_climb_start": CLIMB_START, "pilot_climb_end": CLIMB_END,
		"lookahead_seconds": LOOKAHEAD_SECONDS, "hazards": [], "pilot_gates": []}, true)
	# Real paired circular towers with 20 m of open space. Gates are 110–135 m
	# apart: 5+ seconds at nominal boost, independent of camera zoom/lookahead.
	var xs = [105.0, 220.0, 330.0, 465.0]
	var offsets = [-9.0, 7.0, -7.0, 0.0]
	for i in range(xs.size()):
		# Binary sub-millimetre authored coordinates survive Godot's JSON parser
		# exactly, including the circular hazard centers derived below. The route
		# tangent remains continuous; this only fixes static gate placement.
		var y = snappedf(path_y(xs[i], result) + offsets[i], 1.0 / 1024.0)
		result.pilot_gates.append({"x": xs[i], "y": y, "half_gap": 10.0, "index": i,
			"lane_offset": offsets[i], "heading": path_heading(xs[i], result)})
		for side in [-1.0, 1.0]:
			result.hazards.append({"x": xs[i], "y": y + side * 15.0, "radius": 5.0,
				"type": "rock", "health": 1000000.0, "mass": 1000000.0, "pilot_gate": true, "gate_index": i})
	return result

static func path_y(x: float, data: Dictionary = {}) -> float:
	var a = float(data.get("pilot_climb_start", CLIMB_START))
	var b = float(data.get("pilot_climb_end", CLIMB_END))
	var u = clampf((x - a) / maxf(1.0, b - a), 0.0, 1.0)
	return -float(data.get("pilot_altitude", ALTITUDE)) * u * u * (3.0 - 2.0 * u)

static func path_slope(x: float, data: Dictionary = {}) -> float:
	var a = float(data.get("pilot_climb_start", CLIMB_START))
	var b = float(data.get("pilot_climb_end", CLIMB_END))
	var u = clampf((x - a) / maxf(1.0, b - a), 0.0, 1.0)
	return -float(data.get("pilot_altitude", ALTITUDE)) * 6.0 * u * (1.0 - u) / maxf(1.0, b - a)

static func path_heading(x: float, data: Dictionary = {}) -> float:
	return atan(path_slope(x, data))

static func path_tangent(x: float, data: Dictionary = {}) -> Vector2:
	return Vector2(1.0, path_slope(x, data)).normalized()

static func starter_design() -> Array:
	# Same eight IDs, cells and module types as v1. Parameters stay inside PartsDB.
	var design = preload("res://scripts/pilot_profile.gd").starter_design()
	for p in design:
		if p.type == "thruster": p.param = 28.0
	return design

static func starter_launcher() -> Array:
	# 20 J keeps the single 32 N ground support intact even on the heaviest job.
	return preload("res://scripts/pilot_profile.gd").starter_launcher()
