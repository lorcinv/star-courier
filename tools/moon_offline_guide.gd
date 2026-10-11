extends RefCounted
## OFFLINE QA ONLY. Never preload this from runtime/controller/HUD code.
## Reads actual state and saved landmarks, emits only released/W/S commands.
## No edits to position, velocity, route, energy, health, force or pilot solver.
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")

static func target_y(x: float, route: Dictionary) -> float:
	# During the shared ascent, follow the existing test guide's gate targets.
	if x < float(route.moon_approach_start):
		var offset = 0.0
		for gate in route.pilot_gates:
			if x < float(gate.x) + 6.5:
				offset = float(gate.lane_offset)
				break
		return Ascent.path_y(x, route) + offset
	var previous: Dictionary = route.moon_landmarks[0]
	for landmark in route.moon_landmarks:
		if x <= float(landmark.x):
			var u = clampf((x - float(previous.x)) / maxf(1.0, float(landmark.x) - float(previous.x)), 0.0, 1.0)
			return lerpf(float(previous.y), float(landmark.y), u)
		previous = landmark
	return float(route.destination_y)

static func command_axis(sim) -> int:
	var pos: Vector2 = sim.cargo_position()
	var tangent = Ascent.path_tangent(pos.x, sim.route)
	var normal = Vector2(-tangent.y, tangent.x)
	var body: Dictionary = sim._cargo_body()
	var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var lateral_speed = velocity.dot(normal)
	var acceleration = float(sim.route.pilot_net_force_limit) / maxf(1.0, float(body.get("mass", 10.2)))
	var stopping_preview = lateral_speed * (0.45 + absf(lateral_speed) / (2.0 * acceleration * 0.9))
	var error = target_y(pos.x, sim.route) - pos.y - stopping_preview
	return int(signf(error)) * 1000 if absf(error) > 0.9 else 0
