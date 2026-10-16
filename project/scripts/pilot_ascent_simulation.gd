extends "res://scripts/pilot_simulation.gd"
## Additive pilot-v2: paid route-tangent propulsion, genuine changing attitude,
## finite route-specific storage. All 25 devices, sockets, CCD and work accounting
## remain inherited. No path-position or path-velocity assignments are made.
const AscentProfile = preload("res://scripts/pilot_ascent_profile.gd")
const ASCENT_VERSION = "pilot-v2"

func configure(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> void:
	super.configure(design, launcher, route_data, random_seed)
	# The v1 configure deliberately stamps its own version. Restore this protocol
	# explicitly after it returns so snapshots never mislabel new trajectories.
	route.mode = AscentProfile.MODE
	route.control_version = ASCENT_VERSION
	route.pilot_profile = ASCENT_VERSION
	_refresh_telemetry()

func _new_part(raw: Dictionary) -> Dictionary:
	var p = super._new_part(raw)
	if p.type == "battery":
		var factor = float(route.get("pilot_battery_multiplier", AscentProfile.BATTERY_MULTIPLIER))
		if not is_finite(factor): factor = AscentProfile.BATTERY_MULTIPLIER
		factor = clampf(factor, 1.0, AscentProfile.BATTERY_MULTIPLIER)
		# super already applies the separate, bounded station-research multiplier.
		p.capacity *= factor
		p.energy = p.capacity
	return p

func _plan_pilot_forces(b: Dictionary) -> void:
	_planned_bodies[b.id] = true
	var engines: Array = []
	for p in b.parts:
		if p.type == "thruster" and p.alive and _enabled(p) and _available_energy(b, p.id) > EPS: engines.append(p)
	if engines.is_empty(): return
	var speed = float(route.get("pilot_boost_speed", AscentProfile.BOOST_SPEED)) if pilot_boost else float(route.get("pilot_cruise_speed", AscentProfile.CRUISE_SPEED))
	var tangent = AscentProfile.path_tangent(cargo_position().x, route)
	var normal = Vector2(-tangent.y, tangent.x)
	var steer = float(pilot_axis_q) / 1000.0 * float(route.get("pilot_vertical_speed", AscentProfile.VERTICAL_SPEED))
	var wanted_velocity = tangent * speed + normal * steer
	# Forward assistance follows heading only. Being above/below the lane never
	# adds an invisible restoring force: W/S must negotiate the gate offsets.
	var delta: Vector2 = wanted_velocity - b.velocity
	var desired = (tangent * delta.dot(tangent) / 1.25 + normal * delta.dot(normal) / 0.62) * b.mass
	var net_limit = maxf(0.0, float(route.get("pilot_net_force_limit", AscentProfile.NET_FORCE_LIMIT)))
	desired = desired.limit_length(net_limit)
	var cargo_angle: float = b.angle
	for p in b.parts:
		if p.type == "cargo": cargo_angle += p.local_angle; break
	var wanted_heading = tangent.angle() + atan2(steer, maxf(1.0, speed)) * 0.35
	var heading_error = wrapf(wanted_heading - cargo_angle, -PI, PI)
	var desired_torque = (heading_error * 7.0 - b.angular_velocity * 4.5) * b.inertia
	var lever_scale = 1.0
	for p in engines: lever_scale = maxf(lever_scale, p.local_pos.length())
	var forces: Dictionary = {}
	var divisor = float(engines.size())
	for p in engines:
		forces[p.id] = Vector2.ZERO
		# Counter-torque can require a small paid forward impulse when nozzles
		# cannot reverse. Give attitude enough weight to settle the level approach.
		divisor += 3.0 * p.local_pos.length_squared() / (lever_scale * lever_scale)
	var rate = 0.95 / maxf(1.0, divisor)
	for iteration in range(32):
		var force_sum = Vector2.ZERO
		var torque_sum = 0.0
		for p in engines:
			force_sum += forces[p.id]
			torque_sum += p.local_pos.rotated(b.angle).cross(forces[p.id])
		var force_error: Vector2 = force_sum - desired
		var torque_error: float = 3.0 * (torque_sum - desired_torque) / (lever_scale * lever_scale)
		for p in engines:
			var lever: Vector2 = p.local_pos.rotated(b.angle)
			var next: Vector2 = forces[p.id] - (force_error + Vector2(-lever.y, lever.x) * torque_error) * rate
			forces[p.id] = _project_nozzle(next, b.angle + p.local_angle, p.param * p.output_factor * (1.0 if pilot_boost else 0.85))
	var net = Vector2.ZERO
	for force in forces.values(): net += force
	# This throttle governor limits actual allocated nozzle forces. It neither
	# changes the beam's strength nor prevents damage from other devices/impacts.
	var scale = minf(1.0, net_limit / maxf(EPS, net.length()))
	for id in forces: forces[id] *= scale
	_planned_forces.merge(forces, true)

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	var pos = cargo_position()
	var b = _cargo_body()
	var velocity: Vector2 = b.get("velocity", Vector2.ZERO)
	telemetry.control_version = ASCENT_VERSION
	telemetry.speed = velocity.length()
	telemetry.altitude = -pos.y
	telemetry.target_altitude = float(route.get("pilot_altitude", AscentProfile.ALTITUDE))
	telemetry.route_heading = AscentProfile.path_heading(pos.x, route)
	telemetry.ship_heading = float(b.get("angle", 0.0))
	telemetry.lane_y = AscentProfile.path_y(pos.x, route)
	telemetry.lane_offset = pos.y - telemetry.lane_y
	telemetry.flight_phase = "city" if pos.x < float(route.get("pilot_climb_start", AscentProfile.CLIMB_START)) else ("climb" if pos.x < float(route.get("pilot_climb_end", AscentProfile.CLIMB_END)) else "approach")
	telemetry.lookahead_seconds = maxf(3.0, float(route.get("lookahead_seconds", AscentProfile.LOOKAHEAD_SECONDS)))
	telemetry.lookahead_m = maxf(40.0, velocity.length() * telemetry.lookahead_seconds)
	telemetry.predict_x = pos.x + velocity.x * telemetry.lookahead_seconds
	telemetry.predict_y = pos.y + velocity.y * telemetry.lookahead_seconds
	telemetry.battery_capacity = 0.0
	for p in parts.values():
		if p.alive and p.type == "battery": telemetry.battery_capacity += p.capacity
	telemetry.pilot_battery_multiplier = float(route.get("pilot_battery_multiplier", AscentProfile.BATTERY_MULTIPLIER))
	telemetry.pilot_energy_tariff = float(route.get("pilot_energy_tariff", AscentProfile.ENERGY_TARIFF))
	telemetry.next_gate_index = -1
	telemetry.next_gate_distance = -1.0
	telemetry.next_gate_y = float(route.get("destination_y", -AscentProfile.ALTITUDE))
	telemetry.next_gate_time = -1.0
	telemetry.next_gate_altitude = -float(route.get("destination_y", -AscentProfile.ALTITUDE))
	telemetry.next_gate_heading = 0.0
	telemetry.next_gate_direction = 0
	telemetry.next_gate_dx = 0.0
	telemetry.next_gate_dy = 0.0
	telemetry.next_gate_half_gap = 0.0
	for gate in route.get("pilot_gates", []):
		if float(gate.x) <= pos.x - 2.0: continue
		var dx = float(gate.x) - pos.x
		var expected_y = pos.y + AscentProfile.path_y(float(gate.x), route) - AscentProfile.path_y(pos.x, route)
		var error = float(gate.y) - expected_y
		telemetry.next_gate_index = int(gate.index)
		telemetry.next_gate_distance = dx
		telemetry.next_gate_y = float(gate.y)
		telemetry.next_gate_time = maxf(0.0, dx) / maxf(0.5, velocity.x)
		telemetry.next_gate_altitude = -float(gate.y)
		telemetry.next_gate_heading = float(gate.get("heading", 0.0))
		telemetry.next_gate_direction = int(signf(error)) if absf(error) > 1.0 else 0
		telemetry.next_gate_dx = dx
		telemetry.next_gate_dy = float(gate.y) - pos.y
		telemetry.next_gate_half_gap = float(gate.half_gap)
		break
