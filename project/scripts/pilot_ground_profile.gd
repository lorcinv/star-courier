extends RefCounted
## Authored low-altitude depot lane using the unmodified pilot-v3 physics protocol.
## route_profile is content identity; control_version is replay/physics identity.
## Call route() only when creating a NEW contract, never on an in-flight snapshot.
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const ROUTE_PROFILE = "ground-city-v1"
const CONTROL_VERSION = Extreme.CONTROL_VERSION
const DISTANCE = 360.0
const ALTITUDE = 8.0
const CLIMB_START = 35.0
const CLIMB_END = 165.0
const GATE_RADIUS = 5.0
const HALF_GAP = 7.5

static func route(base_route: Dictionary = {}) -> Dictionary:
	var result = base_route.duplicate(true)
	# Every physical lane value is persisted. No controller needs a special case
	# for route_profile. The shallow rise and gate offsets produce actual paid
	# motion; there is no path snap, teleport, hidden lift, floor or speed clamp.
	result.merge({
		"mode": "pilot", "control_version": CONTROL_VERSION,
		"pilot_profile": CONTROL_VERSION, "pilot_overdrive": "mounted-output",
		"route_profile": ROUTE_PROFILE, "route_kind": "ground",
		"name": "城市货站 → 屋顶收件台", "destination_name": "屋顶收件台",
		"distance": DISTANCE, "destination_y": -ALTITUDE,
		"delivery_radius": 7.0, "max_delivery_speed": 24.0,
		"boundary_y": 45.0, "time_limit": 50.0, "deadline": 32.0,
		"gravity": 0.0, "wind": [0.0, 0.0], "variation": 0.0,
		"pilot_drag": 0.025, "pilot_cruise_speed": 18.0,
		"pilot_boost_speed": 22.0, "pilot_vertical_speed": 5.0,
		"pilot_net_force_limit": 30.0, "pilot_battery_multiplier": 20.0,
		"pilot_energy_tariff": 0.025, "pilot_altitude": ALTITUDE,
		"pilot_climb_start": CLIMB_START, "pilot_climb_end": CLIMB_END,
		"lookahead_seconds": 3.5, "background_route": "city",
		"background_ground_y_m": 0.0,
		"risk": "低空货站通道 · 上下避让实体障碍 · 收件限速 24 m/s",
		"hazards": [], "pilot_gates": []
	}, true)
	# Three alternating clearances, >= 90 m apart, then 85 m of level approach.
	# Binary coordinates preserve the JSON snapshot exactly; heading is merely
	# presentation metadata, while the solver derives its tangent from the fields.
	var xs = [85.0, 185.0, 275.0]
	var offsets = [-7.0, 6.0, -6.0]
	for i in range(xs.size()):
		var y = snappedf(Ascent.path_y(xs[i], result) + offsets[i], 1.0 / 1024.0)
		var heading = snappedf(Ascent.path_heading(xs[i], result), 1.0 / 1024.0)
		result.pilot_gates.append({
			"x": xs[i], "y": y, "half_gap": HALF_GAP, "index": i,
			"lane_offset": offsets[i], "heading": heading
		})
		for side in [-1.0, 1.0]:
			result.hazards.append({
				"x": xs[i], "y": y + side * (HALF_GAP + GATE_RADIUS),
				"radius": GATE_RADIUS, "type": "rock",
				"health": 1000000.0, "mass": 1000000.0,
				"pilot_gate": true, "gate_index": i
			})
	return result

static func is_ground_route(data: Dictionary) -> bool:
	return str(data.get("route_profile", "")) == ROUTE_PROFILE

static func path_y(x: float, data: Dictionary) -> float:
	return Ascent.path_y(x, data)

static func path_heading(x: float, data: Dictionary) -> float:
	return Ascent.path_heading(x, data)

static func path_tangent(x: float, data: Dictionary) -> Vector2:
	return Ascent.path_tangent(x, data)

static func starter_design() -> Array:
	return Extreme.starter_design()

static func starter_launcher() -> Array:
	return Extreme.starter_launcher()
