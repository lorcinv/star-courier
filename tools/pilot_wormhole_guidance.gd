extends RefCounted
## Exact restored standard route guide, extracted without changing its inputs or formula.
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")

static func guidance(sim, drill: bool = false) -> int:
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

