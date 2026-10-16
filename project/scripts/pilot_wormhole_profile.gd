extends RefCounted
## New dispatches only. Existing routes and pilot-v1/v2/v3 replays stay frozen.
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const CONTROL_VERSION = "pilot-v4-wormhole"
const ROUTE_PROFILE = "wormhole-otherworld-v1"
const PORTAL_SCHEMA = 1
const APERTURE_RADIUS = 13.0
const APERTURE_MARGIN = 0.125

static func route(base_route: Dictionary = {}) -> Dictionary:
	var result = Extreme.route(base_route)
	result.merge({
		"control_version": CONTROL_VERSION, "pilot_profile": CONTROL_VERSION,
		"route_profile": ROUTE_PROFILE, "route_kind": "wormhole",
		"name": "城市货站 → 晨星虫洞 → 苔光驿站", "destination_name": "苔光驿站",
		"distance": 1240.0, "destination_y": -150.0,
		"boundary_y": 260.0, "time_limit": 100.0, "deadline": 72.0,
		"background_route": "ascent", "otherworld_background": "mosslight",
		"wormhole_schema": PORTAL_SCHEMA,
		"wormhole_portal": {"id": "morning-mosslight", "entry": [600.0, -150.0],
			"exit": [1000.0, -150.0], "aperture_radius": APERTURE_RADIUS,
			"margin": APERTURE_MARGIN, "exit_lookahead": 0.22,
			"station_energy_j": 2000.0, "base_energy_j": 25.0, "energy_j_per_kg": 2.0},
		"risk": "先升空，再对准虫洞；整体轮廓须装入 25.75 m 净口径。收件限速 24 m/s。",
		"wormhole_hint": "通行使用驿站储能，按实际能耗计费；离洞后继续驶向收件灯。",
		"route_story_hook": "苔光驿站等着这箱补给。过洞后沿着亮着的收件灯走，别忘了留电。"
	}, true)
	# Entry and exit hardware remain genuine v3 collision geometry.
	for x in [600.0, 1000.0]:
		for side in [-1.0, 1.0]:
			result.hazards.append({"x": x, "y": -150.0 + side * 18.0,
				"radius": 5.0, "type": "rock", "health": 1000000.0,
				"mass": 1000000.0, "pilot_gate": true, "destructible": false,
				"wormhole_hardware": true})
	result.pilot_gates.append({"x": 600.0, "y": -150.0, "half_gap": 13.0,
		"index": 4, "lane_offset": 0.0, "heading": 0.0, "wormhole_entry": true})
	# Finite ore on the optional direct line; 6 m above is a clear dodge path.
	result.hazards.append({"x": 1080.0, "y": -150.0, "radius": 3.0,
		"health": 120.0, "mass": 20.0, "type": "rock", "destructible": true,
		"otherworld": true, "wormhole_ore": true})
	result.pilot_gates.append({"x": 1140.0, "y": -146.0, "half_gap": 10.0,
		"index": 5, "lane_offset": 4.0, "heading": 0.0, "otherworld": true})
	for side in [-1.0, 1.0]:
		result.hazards.append({"x": 1140.0, "y": -146.0 + side * 15.0,
			"radius": 5.0, "type": "rock", "health": 1000000.0,
			"mass": 1000000.0, "pilot_gate": true, "otherworld": true})
	return result

static func validation_error(data: Dictionary) -> String:
	if str(data.get("control_version", "")) != CONTROL_VERSION or str(data.get("route_profile", "")) != ROUTE_PROFILE:
		return "虫洞航线协议不匹配。"
	if data.get("wormhole_schema") != PORTAL_SCHEMA or not data.get("wormhole_portal") is Dictionary:
		return "虫洞航线结构无效。"
	var inherited_error = _inherited_validation_error(data)
	if not inherited_error.is_empty(): return inherited_error
	for key in ["distance", "destination_y", "boundary_y"]:
		if not _finite_number(data.get(key)): return "航段边界无效。"
	if float(data.distance) <= 0.0 or float(data.distance) > 100000.0 or float(data.boundary_y) <= 0.0 or float(data.boundary_y) > 10000.0:
		return "航段边界无效。"
	if absf(float(data.destination_y)) >= float(data.boundary_y): return "收件台超出航段边界。"
	var portal: Dictionary = data.wormhole_portal
	if str(portal.get("id", "")).is_empty(): return "虫洞标识缺失。"
	for key in ["entry", "exit"]:
		if not portal.get(key) is Array or portal[key].size() != 2: return "虫洞坐标无效。"
		for number in portal[key]:
			if not _finite_number(number) or absf(float(number)) > 100000.0: return "虫洞坐标无效。"
	for key in ["aperture_radius", "margin", "exit_lookahead", "station_energy_j", "base_energy_j", "energy_j_per_kg"]:
		if not _finite_number(portal.get(key)) or float(portal[key]) < 0.0: return "虫洞参数无效。"
	if float(portal.aperture_radius) <= float(portal.margin) or float(portal.aperture_radius) > 64.0:
		return "虫洞口径无效。"
	for key in ["entry", "exit"]:
		if float(portal[key][0]) < 0.0 or absf(float(portal[key][1])) + float(portal.aperture_radius) + float(portal.margin) >= float(data.boundary_y):
			return "虫洞口超出航段边界。"
	if float(portal.exit_lookahead) < 0.22 or float(portal.exit_lookahead) > 1.0: return "虫洞落点检查时长无效。"
	if float(portal.exit[0]) <= float(portal.entry[0]) + 4.0 * float(portal.aperture_radius): return "虫洞两端间距不足。"
	if float(data.get("distance", 0.0)) <= float(portal.exit[0]) + 4.0 * float(portal.aperture_radius): return "虫洞与收件区间距不足。"
	return ""

## Validate before inherited configure constructs parts, vectors or telemetry.
## This reads only: no default insertion, normalization, geometry changes or caps.
static func _inherited_validation_error(data: Dictionary) -> String:
	var positive = ["weight", "time_limit", "deadline", "delivery_radius", "pilot_energy_tariff",
		"battery_capacity_multiplier", "pilot_battery_multiplier", "required"]
	var nonnegative = ["max_delivery_speed", "variation", "pilot_drag", "pilot_cruise_speed",
		"pilot_boost_speed", "pilot_vertical_speed", "pilot_net_force_limit", "lookahead_seconds", "reward"]
	var signed = ["gravity", "pilot_altitude", "pilot_climb_start", "pilot_climb_end", "background_ground_y_m"]
	for key in positive + nonnegative + signed:
		if not data.has(key): continue # Omission keeps the exact inherited default.
		if not _finite_number(data[key]): return "航线参数无效。"
		if key in positive and float(data[key]) <= 0.0: return "航线参数必须大于零。"
		if key in nonnegative and float(data[key]) < 0.0: return "航线参数不能小于零。"
	for key in ["id", "rep", "seed"]:
		if data.has(key) and not _finite_integer(data[key]): return "航线编号无效。"
	if data.has("wind") and not _finite_vector(data.wind): return "航线风力无效。"
	for collection in ["hazards", "pilot_gates"]:
		if not data.has(collection): continue
		if not data[collection] is Array: return "航线障碍数据无效。"
		for item in data[collection]:
			if not item is Dictionary: return "航线障碍数据无效。"
			if collection == "hazards":
				if not _valid_hazard(item): return "航线障碍参数无效。"
			elif not _valid_pilot_gate(item): return "航线指引参数无效。"
	return ""

static func _finite_integer(value: Variant) -> bool:
	if value is int: return true
	if not value is float or not is_finite(value): return false
	# This is the native integer domain, not a gameplay speed or build cap.
	return value >= -9223372036854775808.0 and value < 9223372036854775808.0 and value == floor(value)

static func _finite_vector(value: Variant) -> bool:
	# Preserve every vector representation consumed by the frozen _vector helper.
	if value is Vector2 or value is Vector3: return value.is_finite()
	if value is Array:
		return value.size() >= 2 and _finite_number(value[0]) and _finite_number(value[1]) and Vector2(float(value[0]), float(value[1])).is_finite()
	if value is Dictionary:
		return _finite_number(value.get("x", 0.0)) and _finite_number(value.get("y", 0.0)) and Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0))).is_finite()
	return _finite_number(value) and Vector2(float(value), 0.0).is_finite()

static func _valid_hazard(hazard: Dictionary) -> bool:
	# x/y are evaluated eagerly by inherited configure even with explicit position.
	for key in ["x", "y", "radius", "mass", "health", "cooldown", "strength", "range", "damage", "fire_interval"]:
		if hazard.has(key) and not _finite_number(hazard[key]): return false
	for key in ["position", "velocity"]:
		if hazard.has(key) and not _finite_vector(hazard[key]): return false
	if not _finite_vector([hazard.get("x", 18.0), hazard.get("y", 0.0)]): return false
	if hazard.has("mass") and float(hazard.mass) <= 0.0: return false
	for key in ["radius", "range", "damage", "fire_interval"]:
		if hazard.has(key) and float(hazard[key]) < 0.0: return false
	if hazard.has("type") and not (hazard.type is String or hazard.type is StringName): return false
	for key in ["tracking", "conductive", "pilot_gate", "destructible", "wormhole_hardware", "otherworld"]:
		if hazard.has(key) and not hazard[key] is bool: return false
	return true

static func _valid_pilot_gate(gate: Dictionary) -> bool:
	for key in ["x", "y", "index", "half_gap"]:
		if not gate.has(key) or not _finite_number(gate[key]): return false
	if not _finite_vector([gate.x, gate.y]) or not _finite_integer(gate.index) or float(gate.half_gap) < 0.0: return false
	for key in ["heading", "lane_offset"]:
		if gate.has(key) and not _finite_number(gate[key]): return false
	return true

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func transit_quote(data: Dictionary, total_mass: float, connected_bodies: int = 1) -> Dictionary:
	if not validation_error(data).is_empty() or not is_finite(total_mass) or total_mass < 0.0 or connected_bodies < 1:
		return {"ok": false}
	var portal: Dictionary = data.wormhole_portal
	var joules = float(portal.base_energy_j) * connected_bodies + float(portal.energy_j_per_kg) * total_mass
	var tariff = float(data.get("pilot_energy_tariff", 0.025))
	if not is_finite(joules) or not is_finite(tariff): return {"ok": false}
	tariff = clampf(tariff, 0.001, 0.18)
	return {"ok": true, "energy_source": "station", "estimated_j": joules,
		"station_capacity_j": float(portal.station_energy_j),
		"max_centered_body_diameter_m": 2.0 * (float(portal.aperture_radius) - float(portal.margin)), "estimated_credits": joules * tariff,
		"estimated_bodies": connected_bodies, "separate_settlement_debit": false,
		"text": "预计通行 %.1f J（约 %.2f 信用点，合并计入能耗）；驿站储能 %.0f J，不扣飞船电池。分离后按实际过洞组件数计费。" % [joules, joules * tariff, float(portal.station_energy_j)]}
