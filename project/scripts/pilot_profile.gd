extends RefCounted
## Versioned balancing for the controllable city → orbital-station slice only.
## Never apply this profile while replaying an autonomous-v5 snapshot.
const MODE = "pilot"
const CONTROL_VERSION = "pilot-v1"
const COCKPIT_SIGNAL = -2
const COMMAND_HZ = 60
const AXIS_SCALE = 1000
const PHYSICS_HZ = 120
const CRUISE_SPEED = 4.8
const BOOST_SPEED = 7.2
const VERTICAL_SPEED = 1.8
const GIMBAL_DEGREES = 90.0
const GIMBAL_SLEW_DEGREES = 240.0
const LOOKAHEAD_SECONDS = 3.5

static func route(base_route: Dictionary = {}) -> Dictionary:
	var result = base_route.duplicate(true)
	result.merge({"mode": MODE, "control_version": CONTROL_VERSION, "pilot_profile": CONTROL_VERSION,
		"name": "城市 → 轨道站", "destination_name": "晨星轨道站", "distance": 128.0,
		"destination_y": 0.0, "delivery_radius": 6.0, "max_delivery_speed": 10.0,
		"boundary_y": 22.0, "time_limit": 65.0, "deadline": 42.0, "gravity": 0.0, "wind": [0.0, 0.0],
		"variation": 0.0, "pilot_drag": 0.025, "pilot_cruise_speed": CRUISE_SPEED,
		"pilot_boost_speed": BOOST_SPEED, "pilot_vertical_speed": VERTICAL_SPEED,
		"lookahead_seconds": LOOKAHEAD_SECONDS, "hazards": [], "pilot_gates": []}, true)
	# Empty orbital flight lanes are bounded by pairs of physical circular structures.
	# Their gap is 5.2 metres high, with over four seconds between gates at cruise.
	var xs = [28.0, 58.0, 88.0, 111.0]
	var ys = [-1.7, 1.7, -1.7, 0.0]
	for i in range(xs.size()):
		result.pilot_gates.append({"x": xs[i], "y": ys[i], "half_gap": 2.6, "index": i})
		for side in [-1.0, 1.0]:
			result.hazards.append({"x": xs[i], "y": ys[i] + side * 6.6, "radius": 4.0,
				"type": "rock", "health": 1000000.0, "mass": 1000000.0, "pilot_gate": true, "gate_index": i})
	return result

static func starter_design() -> Array:
	return [_part(1, "cargo", 0, 0), _part(2, "beam", 1, -1), _part(3, "battery", -1, 0),
		_part(4, "thruster", 0, -1, 12.0), _part(5, "armor", 1, 0),
		_part(6, "thruster", 0, 1, 12.0), _part(7, "beam", 1, 1), _part(8, "coupler", -1, 1)]

static func starter_launcher() -> Array:
	return [_part(1001, "spring", 0, 0, 20.0), _part(1002, "battery", -1, 0), _part(1003, "beam", 1, 0)]

static func _part(id: int, kind: String, x: int, y: int, value: float = -1.0) -> Dictionary:
	var data = preload("res://scripts/parts.gd")
	return {"id": id, "type": kind, "x": x, "y": y, "rot": 0,
		"param": data.defaults(kind) if value < 0.0 else value, "input_a": -1, "input_b": -1, "target": -1}
