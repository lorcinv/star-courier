extends RefCounted
## No accepted gameplay replay/route protocol is registered by this helper.
const V = preload("ground_traffic_value_v1.gd")
const VERSION := "ground-traffic-foundation-v1"
const DEFINITION := "ground-traffic-fresh-v1"
const SCENARIO := "city-360-between-gates-85-185"
const ACTOR_KEYS := ["id", "source_id", "role", "x", "y", "vx", "vy", "mass_kg", "radius_m", "hp", "fuel_mj"]
const BUNDLE_KEYS := ["helper", "seed", "scenario", "traffic_count", "patrol_enabled", "warning_ticks", "active_ticks", "max_force_n", "minimum_cost_mj", "actors"]

static func fresh_definition() -> Dictionary:
	return {"definition": DEFINITION, "scenario": SCENARIO, "traffic_count": 2, "patrol_enabled": true}

static func author(explicit_seed: Variant, fresh: Dictionary) -> Dictionary:
	if not V.integer(explicit_seed, 0, 2147483646):
		return {"ok": false, "error": "invalid_seed", "bundle": {}}
	if not V.bounded_json(fresh) or not V.exact(fresh, ["definition", "scenario", "traffic_count", "patrol_enabled"]) \
		or fresh.definition != DEFINITION or fresh.scenario != SCENARIO \
		or not V.integer(fresh.traffic_count, 0, 2) or not fresh.patrol_enabled is bool:
		return {"ok": false, "error": "invalid_fresh_definition", "bundle": {}}
	var seed_value: int = int(explicit_seed)
	var stream: int = seed_value + 1
	var actors: Array = []
	for i in int(fresh.traffic_count):
		stream = _next(stream)
		var x: float = (124.0 if i == 0 else 134.0) + float(stream % 4001) / 1000.0
		actors.append(_actor(seed_value, "traffic_%d" % i, x, -8.0 if i == 0 else -6.5,
			80.0 if i == 0 else 100.0, 1.5 if i == 0 else 1.75, 30 if i == 0 else 40, 0))
	if fresh.patrol_enabled:
		stream = _next(stream)
		actors.append(_actor(seed_value, "patrol", 106.0 + float(stream % 4001) / 1000.0,
			-14.0, 60.0, 1.25, 25, 60000))
	return {"ok": true, "error": "", "bundle": {
		"helper": VERSION, "seed": seed_value, "scenario": SCENARIO,
		"traffic_count": int(fresh.traffic_count), "patrol_enabled": fresh.patrol_enabled,
		"warning_ticks": 180, "active_ticks": 120, "max_force_n": 120.0,
		"minimum_cost_mj": 1000, "actors": actors,
	}}

static func restore(saved: Variant) -> Dictionary:
	# Intentionally never calls author or _next. Stored physical bits survive.
	if not V.bounded_json(saved) or not V.exact(saved, BUNDLE_KEYS) or saved.helper != VERSION or saved.scenario != SCENARIO \
		or not V.integer(saved.seed, 0, 2147483646) or not V.integer(saved.traffic_count, 0, 2) \
		or not saved.patrol_enabled is bool or not saved.actors is Array \
		or saved.actors.size() != int(saved.traffic_count) + int(saved.patrol_enabled) \
		or not V.integer(saved.warning_ticks, 180, 180) or not V.integer(saved.active_ticks, 120, 120) \
		or not V.integer(saved.minimum_cost_mj, 1000, 1000) or not V.real(saved.max_force_n, 120.0, 120.0):
		return {"ok": false, "error": "invalid_bundle", "bundle": {}}
	var copy: Dictionary = saved.duplicate(true)
	for key in ["seed", "traffic_count", "warning_ticks", "active_ticks", "minimum_cost_mj"]:
		copy[key] = int(copy[key])
	for i in copy.actors.size():
		var a: Variant = copy.actors[i]
		var role: String = "traffic_%d" % i if i < copy.traffic_count else "patrol"
		var identifier := _id(copy.seed, role)
		if not V.exact(a, ACTOR_KEYS) or a.id != identifier or a.source_id != identifier or a.role != role:
			return {"ok": false, "error": "invalid_actor_identity", "bundle": {}}
		var civilian: bool = role != "patrol"
		var first: bool = role == "traffic_0"
		var xmin: float = (124.0 if first else 134.0) if civilian else 106.0
		var y: float = (-8.0 if first else -6.5) if civilian else -14.0
		var mass: float = (80.0 if first else 100.0) if civilian else 60.0
		var radius: float = (1.5 if first else 1.75) if civilian else 1.25
		var hp: int = (30 if first else 40) if civilian else 25
		if not V.real(a.x, xmin, xmin + 4.0) or not V.real(a.y, y, y) \
			or not V.real(a.vx, 0.0, 0.0) or not V.real(a.vy, 0.0, 0.0) \
			or not V.real(a.mass_kg, mass, mass) or not V.real(a.radius_m, radius, radius) \
			or not V.integer(a.hp, hp, hp) or not V.integer(a.fuel_mj, 0 if civilian else 60000, 0 if civilian else 60000):
			return {"ok": false, "error": "invalid_actor_realization", "bundle": {}}
		a.hp = int(a.hp)
		a.fuel_mj = int(a.fuel_mj)
	return {"ok": true, "error": "", "bundle": copy}

static func save_json(saved: Variant) -> Dictionary:
	var result := restore(saved)
	return {"ok": true, "json": V.pack_json(result.bundle, "bundle")} if result.ok else result

static func load_json(text: Variant) -> Dictionary:
	var decoded := V.unpack_json(text, "bundle")
	return restore(decoded.value) if decoded.ok else decoded

static func _actor(seed_value: int, role: String, x: float, y: float, mass: float, radius: float, hp: int, fuel: int) -> Dictionary:
	return {"id": _id(seed_value, role), "source_id": _id(seed_value, role), "role": role,
		"x": x, "y": y, "vx": 0.0, "vy": 0.0, "mass_kg": mass, "radius_m": radius,
		"hp": hp, "fuel_mj": fuel}

static func initial_clearance_report(saved: Variant, craft_radius_m: Variant) -> Dictionary:
	var restored := restore(saved)
	if not restored.ok:
		return restored
	if not V.real(craft_radius_m, 0.1, 1.0):
		return V.fail("unsupported_reference_craft_radius")
	var actors: Array = restored.bundle.actors
	var minimum_bypass: float = INF
	var minimum_pair: float = INF
	var minimum_launch: float = INF
	var minimum_arrival: float = INF
	var direct_blocked: bool = false
	# An analytic reference detour, not authored baseline collider or HUD clearance.
	var points := [[20.0, -8.0], [98.0, -20.0], [150.0, -20.0], [170.0, -8.0]]
	for i in actors.size():
		var a: Dictionary = actors[i]
		minimum_launch = minf(minimum_launch, a.x - a.radius_m - craft_radius_m - 20.0)
		minimum_arrival = minf(minimum_arrival, 340.0 - a.x - a.radius_m - craft_radius_m)
		for j in range(i + 1, actors.size()):
			var b: Dictionary = actors[j]
			minimum_pair = minf(minimum_pair, sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)) - a.radius_m - b.radius_m)
		for j in 3:
			minimum_bypass = minf(minimum_bypass, _point_segment_distance(a.x, a.y, points[j], points[j + 1]) - a.radius_m - craft_radius_m)
		if _point_segment_distance(a.x, a.y, [98.0, -8.0], [150.0, -8.0]) <= a.radius_m + craft_radius_m:
			direct_blocked = true
	return {"ok": true, "initial_body_count": actors.size(), "direct_reference_path_blocked": direct_blocked,
		"bypass_clearance_m": minimum_bypass if not actors.is_empty() else null,
		"body_separation_m": minimum_pair if actors.size() > 1 else null,
		"launch_clearance_m": minimum_launch if not actors.is_empty() else null,
		"arrival_clearance_m": minimum_arrival if not actors.is_empty() else null,
		"reference_bypass_clear": minimum_bypass > 0.0, "bodies_separate": minimum_pair > 0.0,
		"launch_clear": minimum_launch > 0.0, "arrival_clear": minimum_arrival > 0.0,
		"baseline_colliders_checked": false, "future_motion_clearance_checked": false}

static func _point_segment_distance(x: float, y: float, a: Array, b: Array) -> float:
	var dx: float = b[0] - a[0]
	var dy: float = b[1] - a[1]
	var parameter: float = clampf(((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
	return sqrt(pow(x - a[0] - parameter * dx, 2) + pow(y - a[1] - parameter * dy, 2))

static func _id(seed_value: int, role: String) -> String:
	return "ground-traffic-foundation-v1/%d/%s" % [seed_value, role]

static func _next(value: int) -> int:
	var n: int = (value ^ (value << 13)) & 0xffffffff
	n = (n ^ (n >> 17)) & 0xffffffff
	return (n ^ (n << 5)) & 0xffffffff
