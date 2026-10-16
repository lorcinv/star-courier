extends RefCounted
## Private, explicit v5 profile. Its fixed ecology realization never samples RNG.
## Portal geometry/energy and inherited validators copied from frozen v4; v4 is not called to validate v5.
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const CONTROL_VERSION = "pilot-v5-protected-bird"
const ROUTE_PROFILE = "mosslight-protected-bird-v1"
const GENERATOR_VERSION = "protected-bird-offers-v1"
const SPECIES_ID = "mosslight_leafwing"
const ECOLOGY_SCHEMA = "protected-bird-route-v1"
const PORTAL_SCHEMA = 1
const APERTURE_RADIUS = 13.0
const APERTURE_MARGIN = 0.125

static func route(base_route: Dictionary = {}, contract_id: String = "BIRD-TEST", realized_seed: int = 1) -> Dictionary:
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
	result.pilot_gates.append({"x": 1140.0, "y": -146.0, "half_gap": 10.0,
		"index": 5, "lane_offset": 4.0, "heading": 0.0, "otherworld": true})
	for side in [-1.0, 1.0]:
		result.hazards.append({"x": 1140.0, "y": -146.0 + side * 15.0,
			"radius": 5.0, "type": "rock", "health": 1000000.0,
			"mass": 1000000.0, "pilot_gate": true, "otherworld": true})
	result.contract_id = contract_id
	result.seed = realized_seed
	result.ecology_schema = ECOLOGY_SCHEMA
	result.ecology_generator = GENERATOR_VERSION
	result.ecology = event_definition(contract_id, realized_seed)
	result.risk += " 苔光保护鸟会在出口前方穿越，请从下方绕行。"
	return result

static func event_definition(contract_id: String, realized_seed: int) -> Dictionary:
	var event_id = contract_id + "/protected-pass/0"
	return {"schema": ECOLOGY_SCHEMA, "seed": realized_seed, "event_id": event_id,
		"entity_id": event_id + "/bird/0", "species_id": SPECIES_ID,
		"activation": "first-live-cargo-portal-transit", "position": [1120.0, -153.0],
		"velocity": [-3.0, 0.5], "mass": 0.125, "radius": 0.375, "max_hp": 8.0,
		"bounds": [1015.0, -165.0, 1160.0, -125.0], "max_active_ticks": 4800}

static func validation_error(data: Variant) -> String:
	if not data is Dictionary: return "保护鸟航线必须是对象。"
	if not same_value(data.get("control_version"), CONTROL_VERSION) or not same_value(data.get("route_profile"), ROUTE_PROFILE):
		return "虫洞航线协议不匹配。"
	if not same_value(data.get("wormhole_schema"), PORTAL_SCHEMA) or not data.get("wormhole_portal") is Dictionary:
		return "虫洞航线结构无效。"
	var inherited_error = _inherited_validation_error(data)
	if not inherited_error.is_empty(): return inherited_error
	for key in ["distance", "destination_y", "boundary_y"]:
		if not _finite_number(data.get(key)): return "航段边界无效。"
	if float(data.distance) <= 0.0 or float(data.distance) > 100000.0 or float(data.boundary_y) <= 0.0 or float(data.boundary_y) > 10000.0:
		return "航段边界无效。"
	if absf(float(data.destination_y)) >= float(data.boundary_y): return "收件台超出航段边界。"
	var portal: Dictionary = data.wormhole_portal
	if not portal.get("id") is String or portal.id.is_empty(): return "虫洞标识缺失。"
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
	return _ecology_validation_error(data)

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

## Only one authored realization is supported in this slice. Geometry checking
## reads saved values; it does not re-author offers or consume a random stream.
static func _ecology_validation_error(data: Dictionary) -> String:
	var required_keys = ["mode", "control_version", "pilot_profile", "name", "destination_name", "distance", "destination_y", "delivery_radius", "max_delivery_speed", "boundary_y", "time_limit", "deadline", "gravity", "wind", "variation", "pilot_drag", "pilot_cruise_speed", "pilot_boost_speed", "pilot_vertical_speed", "pilot_net_force_limit", "pilot_battery_multiplier", "pilot_energy_tariff", "pilot_altitude", "pilot_climb_start", "pilot_climb_end", "lookahead_seconds", "hazards", "pilot_gates", "pilot_overdrive", "route_profile", "route_kind", "background_route", "otherworld_background", "wormhole_schema", "wormhole_portal", "risk", "wormhole_hint", "route_story_hook", "contract_id", "seed", "ecology_schema", "ecology_generator", "ecology"]
	var optional_keys = ["id", "rep", "weight", "reward", "required", "battery_capacity_multiplier"]
	for key in required_keys:
		if not data.has(key): return "保护鸟航线缺少字段。"
	for key in data:
		# Native Dictionary dot assignments use StringName keys; JSON uses String.
		# Accept either key representation without converting/mutating saved data.
		if not (key is String or key is StringName): return "保护鸟航线有未知字段。"
		var key_text = str(key)
		if not key_text in required_keys and not key_text in optional_keys: return "保护鸟航线有未知字段。"
	for key in ["name", "destination_name", "risk", "wormhole_hint", "route_story_hook"]:
		if not data[key] is String or data[key].length() > 4096: return "保护鸟航线文本无效。"
	for pair in [["mode", "pilot"], ["pilot_profile", CONTROL_VERSION], ["route_kind", "wormhole"], ["background_route", "ascent"], ["pilot_overdrive", "mounted-output"], ["otherworld_background", "mosslight"], ["ecology_schema", ECOLOGY_SCHEMA], ["ecology_generator", GENERATOR_VERSION]]:
		if not same_value(data.get(pair[0]), pair[1]): return "保护鸟航线身份或协议无效。"
	if not data.get("contract_id") is String or data.contract_id.is_empty() or data.contract_id.length() > 160: return "保护鸟委托标识无效。"
	if not _finite_integer(data.get("seed")) or float(data.seed) < 0.0 or float(data.seed) > 2147483647.0: return "保护鸟航线种子无效。"
	if not data.get("ecology") is Dictionary: return "保护鸟事件缺失。"
	# The definition is a fixed constant realization, independent of all mutable
	# route state. This comparison rejects extra keys and position overrides.
	if not same_value(data.ecology, event_definition(data.contract_id, int(data.seed))): return "保护鸟事件实现无效。"
	var portal = {"id": "morning-mosslight", "entry": [600.0, -150.0], "exit": [1000.0, -150.0], "aperture_radius": 13.0, "margin": 0.125, "exit_lookahead": 0.22, "station_energy_j": 2000.0, "base_energy_j": 25.0, "energy_j_per_kg": 2.0}
	if not same_value(data.wormhole_portal, portal): return "保护鸟虫洞实现被修改。"
	for pair in [["distance", 1240.0], ["destination_y", -150.0], ["boundary_y", 260.0], ["variation", 0.0]]:
		if not same_value(data.get(pair[0]), pair[1]): return "保护鸟固定航段被修改。"
	if data.hazards.size() != 14 or data.pilot_gates.size() != 6: return "保护鸟固定几何数量无效。"
	for i in range(4):
		var x: float = [105.0, 220.0, 330.0, 465.0][i]
		var y: float = [-22.728515625, -66.5, -139.4326171875, -150.0][i]
		# Compare the saved original ascent coordinates, not runtime path functions.
		var gate: Dictionary = data.pilot_gates[i]
		var expected_heading: float = preload("res://scripts/pilot_ascent_profile.gd").path_heading(x)
		if not _finite_number(gate.get("heading")) or absf(float(gate.heading) - expected_heading) > 0.000000000001: return "保护鸟升空朝向无效。"
		if not same_value(gate.get("x"), x) or not same_value(gate.get("y"), y) or not same_value(gate.get("half_gap"), 10.0) or not same_value(gate.get("lane_offset"), [-9.0, 7.0, -7.0, 0.0][i]): return "保护鸟升空几何无效。"
	for i in range(data.hazards.size()):
		var h: Dictionary = data.hazards[i]
		var keys = ["x", "y", "radius", "type", "health", "mass", "pilot_gate"]
		if i < 8: keys.append("gate_index")
		elif i < 12: keys.append("destructible"); keys.append("wormhole_hardware")
		else: keys.append("otherworld")
		if not exact_keys(h, keys): return "保护鸟障碍有未知字段。"
		var x = 0.0; var y = 0.0
		if i < 8:
			var gate: Dictionary = data.pilot_gates[i / 2]
			x = float(gate.x); y = float(gate.y) + (-15.0 if i % 2 == 0 else 15.0)
			if not same_value(h.gate_index, i / 2): return "保护鸟障碍编号无效。"
		elif i < 12:
			x = 600.0 if i < 10 else 1000.0; y = -150.0 + (-18.0 if i % 2 == 0 else 18.0)
			if not same_value(h.destructible, false) or not same_value(h.wormhole_hardware, true): return "保护鸟虫洞硬件无效。"
		else:
			x = 1140.0; y = -146.0 + (-15.0 if i % 2 == 0 else 15.0)
			if not same_value(h.otherworld, true): return "保护鸟终点门无效。"
		for pair in [["x", x], ["y", y], ["radius", 5.0], ["health", 1000000.0], ["mass", 1000000.0], ["type", "rock"], ["pilot_gate", true]]:
			if not same_value(h.get(pair[0]), pair[1]): return "保护鸟障碍实现被修改。"
	for i in range(data.pilot_gates.size()):
		var gate: Dictionary = data.pilot_gates[i]
		var keys = ["x", "y", "half_gap", "index", "lane_offset", "heading"]
		if i == 4: keys.append("wormhole_entry")
		if i == 5: keys.append("otherworld")
		if not exact_keys(gate, keys) or not same_value(gate.index, i): return "保护鸟引导门无效。"
		if i >= 4:
			var expected = {"x": 600.0 if i == 4 else 1140.0, "y": -150.0 if i == 4 else -146.0, "half_gap": 13.0 if i == 4 else 10.0, "index": i, "lane_offset": 0.0 if i == 4 else 4.0, "heading": 0.0}
			expected["wormhole_entry" if i == 4 else "otherworld"] = true
			if not same_value(gate, expected): return "保护鸟终段引导门被修改。"
	return ""

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func same_value(a: Variant, b: Variant) -> bool:
	if _finite_number(a) and _finite_number(b): return float(a) == float(b)
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if not exact_keys(a, b.keys()): return false
		for key in b:
			if not same_value(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not same_value(a[i], b[i]): return false
		return true
	return a == b
