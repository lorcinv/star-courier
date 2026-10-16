extends RefCounted
## Production full-power protocol. Older committed dispatches retain v1/v2.
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Expanded = preload("res://scripts/parts_expanded.gd")
const CONTROL_VERSION = "pilot-v3"
const MODE = "pilot"
const BOOST_PITCH = 0.61
const IMPACT_ABSORB_FRACTION = 0.65
const IMPACT_ABSORB_LIMIT = 24.0
const IMPACT_JOULES_PER_HP = 1.5

static func route(base_route: Dictionary = {}) -> Dictionary:
	var result = Ascent.route(base_route)
	result.control_version = CONTROL_VERSION
	result.pilot_profile = CONTROL_VERSION
	result.pilot_overdrive = "mounted-output"
	return result

static func starter_design() -> Array:
	return Ascent.starter_design()

static func starter_launcher() -> Array:
	return Ascent.starter_launcher()

static func reinforced_design() -> Array:
	# Eight real 28 N engines, two cells, five unchanged 32 N beams. Dense socket
	# paths distribute force; there is no special hull/strength multiplier.
	var result = starter_design()
	for p in result:
		if p.id == 8: p.type = "battery"; p.x = -2; p.y = 0; p.param = 300.0
	var next = 20
	for x in [-2, -1, 2]:
		for y in [-1, 1]:
			result.append(part(next, "thruster", x, y, {"param": 28.0})); next += 1
	result.append(part(26, "beam", -3, -1))
	result.append(part(27, "beam", -3, 0))
	result.append(part(28, "beam", -3, 1))
	return result

static func part(id: int, kind: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var p = {"id": id, "type": kind, "x": x, "y": y, "rot": 0, "param": Expanded.defaults(kind), "input_a": -1, "input_b": -1, "target": -1}
	p.merge(extra, true)
	return p
