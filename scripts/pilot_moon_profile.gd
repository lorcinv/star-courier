extends RefCounted
## New Moon content only. Uses unchanged pilot-v3 physics, energy and CCD.
## A compressed arcade flight; neither astronomical distance nor lunar gravity.
## Author only NEW offers. Restore committed routes verbatim, never via route().
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const CONTROL_VERSION = Extreme.CONTROL_VERSION
const ROUTE_PROFILE = "moon-surface-v1"
const ROUTE_KIND = "moon"
const DESTINATION_ID = "moon-regolith-airlock"
const DISTANCE = 900.0
const DESTINATION_Y = -125.0
const AIRLOCK_METERS_PER_PIXEL = 9.0 / 64.0
const AIRLOCK_CAPTURE_NATIVE = Vector2(244.0, 392.0)
const INGRESS_Y = -126.40625
const SURFACE_Y = -91.8125
# Source-inscribed circles: all sampled discs sit inside genuinely opaque alpha.
# They are a disclosed approximation, not a complete silhouette collision mask.
const HARDWARE_NATIVE = [
	["roof-left", 150.0, 282.0, 22.0], ["roof-middle-left", 210.0, 282.0, 32.0],
	["roof-middle", 270.0, 280.0, 38.0], ["roof-middle-right", 330.0, 278.0, 46.0],
	["roof-back", 400.0, 268.0, 55.0], ["deck-left", 104.0, 502.0, 24.0],
	["deck-middle-left", 202.0, 518.0, 40.0], ["deck-middle", 270.0, 516.0, 47.0],
	["deck-middle-right", 336.0, 500.0, 36.0], ["deck-back", 402.0, 500.0, 40.0],
	["back-wall-upper", 444.0, 362.0, 60.0], ["back-wall-middle", 444.0, 412.0, 63.0],
	["back-wall-lower", 448.0, 464.0, 76.0], ["outer-back-middle", 588.0, 434.0, 64.0]]

static func route(base_route: Dictionary = {}) -> Dictionary:
	var result = Extreme.route(base_route)
	result.merge({
		"route_profile": ROUTE_PROFILE, "route_kind": ROUTE_KIND,
		"destination_id": DESTINATION_ID,
		"name": "城市货站 → 月面收件舱", "destination_name": "月面收件舱",
		"distance": DISTANCE, "destination_y": DESTINATION_Y,
		"delivery_radius": 9.0, "max_delivery_speed": 24.0,
		"time_limit": 95.0, "deadline": 64.0,
		"background_route": "ascent", "background_ground_y_m": 0.0,
		"moon_schema": 1, "moon_surface_y": SURFACE_Y,
		"moon_approach_start": 560.0, "moon_clear_approach_start": 805.0,
		"moon_receiver": {"id": DESTINATION_ID, "entrance_side": "left",
			"capture_plane_x": DISTANCE, "capture_center_y": DESTINATION_Y,
			"capture_radius": 9.0, "ingress_center_y": INGRESS_Y,
			"conservative_ingress_half_height": 6.1875,
			"fully_transparent_ingress_y_min": -132.875,
			"fully_transparent_ingress_y_max": -119.9375,
			"ingress_reference_x": 882.5625,
			"surface_y": SURFACE_Y, "surface_contact_native": [217.0, 628.0],
			"art_profile": "moon-airlock-pixel-v1", "meters_per_native_pixel": AIRLOCK_METERS_PER_PIXEL,
			"capture_anchor_native": [244.0, 392.0], "capture_radius_native": 64.0,
			"texture_size_native": [688.0, 688.0],
			"visual_bounds": [871.3125, -172.53125, 86.90625, 80.71875],
			"sprite_top_left": [865.6875, -180.125],
			"hardware_model": "source-inscribed CCD circles; not full opaque silhouette",
			"hardware_hazard_ids": []},
		# Presentation/QA landmarks only. The v3 solver never reads these to steer.
		"moon_landmarks": [
			{"id": "orbital-handoff", "x": 560.0, "y": -150.0},
			{"id": "north-crag-dodge", "x": 650.0, "y": -152.0},
			{"id": "south-crag-dodge", "x": 765.0, "y": -143.0},
			{"id": "airlock-lineup", "x": 845.0, "y": INGRESS_Y},
			{"id": DESTINATION_ID, "x": DISTANCE, "y": INGRESS_Y}],
		"moon_render_requirements": {"minimum_forward_m": 80.0,
			"lookahead_seconds": 3.5, "vertical_padding_m": 6.0,
			"full_hazard_bounds_above_hud": true,
			"physical_geometry_from_saved_hazards": true,
			"clear_receiver_preview_from_x": 805.0},
		"risk": "真实升空后，绕开两组月面岩脊，再下降至左开口收件舱；收件限速 24 m/s。",
		"moon_hint": "轨道段之后，W/S 仍负责升降。岩脊上方可绕行，矿石可选钻切；为最后下降留电。"
	}, true)
	# Preserve the existing four ascent gates and their eight physical circles.
	# Snap presentation heading too: all newly saved content round-trips through JSON.
	for gate in result.pilot_gates:
		gate.heading = snappedf(float(gate.heading), 1.0 / 1024.0)
	for hazard in result.hazards:
		hazard.destructible = false
	# Two low outcrops, not a new sequence of narrow paired gates. All circles
	# exist from configure() onward. A full upper route remains open without drill.
	result.hazards.append(_solid("north-crag-main", 650.0, -112.0, 15.0, "crag", 0))
	result.hazards.append(_solid("north-crag-shoulder", 675.0, -105.0, 10.0, "crag", 0))
	result.hazards.append(_ore("north-ore", 646.0, -143.0, 3.0, 0))
	result.hazards.append(_solid("south-crag-main", 765.0, -101.0, 16.0, "crag", 1))
	result.hazards.append(_solid("south-crag-shoulder", 789.0, -101.0, 10.0, "crag", 1))
	result.hazards.append(_ore("south-ore", 758.0, -133.0, 3.0, 1))
	# Register actual source roof/deck/back-wall cores, never an invented aperture.
	# Internal capture radius and straight ingress clearance are distinct values.
	# Feet contact metadata mounts the artwork; it creates no invisible floor.
	for sample in HARDWARE_NATIVE:
		var at = Vector2(DISTANCE, DESTINATION_Y) + (Vector2(sample[1], sample[2]) - AIRLOCK_CAPTURE_NATIVE) * AIRLOCK_METERS_PER_PIXEL
		var id = "airlock-" + str(sample[0])
		var hardware = _solid(id, at.x, at.y, float(sample[3]) * AIRLOCK_METERS_PER_PIXEL, "airlock", -1)
		hardware.source_circle_native = [sample[1], sample[2], sample[3]]
		result.hazards.append(hardware)
		result.moon_receiver.hardware_hazard_ids.append(id)
	return result

static func _solid(id: String, x: float, y: float, radius: float, role: String, group: int) -> Dictionary:
	return {"id": id, "x": x, "y": y, "radius": radius, "type": "rock",
		"health": 1000000.0, "mass": 1000000.0, "destructible": false,
		"moon": true, "moon_role": role, "moon_group": group}

static func _ore(id: String, x: float, y: float, radius: float, group: int) -> Dictionary:
	return {"id": id, "x": x, "y": y, "radius": radius, "type": "rock",
		"health": 80.0, "mass": 20.0, "destructible": true,
		"moon": true, "moon_role": "ore", "moon_group": group}

static func is_moon_route(data: Dictionary) -> bool:
	for key in ["route_profile", "control_version", "pilot_profile", "route_kind", "destination_id"]:
		if not data.get(key) is String: return false
	return data.route_profile == ROUTE_PROFILE and data.control_version == CONTROL_VERSION and data.pilot_profile == CONTROL_VERSION and data.route_kind == ROUTE_KIND and data.destination_id == DESTINATION_ID

static func starter_design() -> Array:
	return Extreme.starter_design()

static func starter_launcher() -> Array:
	return Extreme.starter_launcher()

## Read-only gate for saved content. Never repairs, reauthors, defaults, or changes
## a route. Partial Moon markers must fail here rather than use legacy v3 fallback.
static func has_moon_markers(data: Dictionary) -> bool:
	for key in data:
		if (key is String or key is StringName) and (key == "moon" or key.begins_with("moon_")): return true
	for key in ["route_profile", "destination_id"]:
		if data.get(key) is String and data[key].begins_with("moon-"): return true
	if data.get("route_kind") is String and data.route_kind == ROUTE_KIND: return true
	for collection in ["hazards", "pilot_gates"]:
		if not data.get(collection) is Array: continue
		for item in data[collection]:
			if not item is Dictionary: continue
			for key in item:
				if (key is String or key is StringName) and (key == "moon" or key.begins_with("moon_")): return true
	return false

static func validation_error(data: Dictionary) -> String:
	if not _json_finite(data): return "月球航线包含无效数据。"
	var identity = {"control_version": CONTROL_VERSION, "pilot_profile": CONTROL_VERSION,
		"mode": "pilot", "route_profile": ROUTE_PROFILE, "route_kind": ROUTE_KIND,
		"destination_id": DESTINATION_ID, "background_route": "ascent", "pilot_overdrive": "mounted-output"}
	for key in identity:
		if not data.get(key) is String or data[key] != identity[key]: return "月球航线标识不一致。"
	if not _integer(data.get("moon_schema")) or data.moon_schema != 1: return "月球航线版本无效。"
	if _has_foreign_markers(data): return "月球与虫洞航线记录混杂，暂时无法出发。"
	for key in ["name", "destination_name", "risk", "moon_hint"]:
		if not _label(data.get(key)): return "月球航线说明无效。"
	for key in ["weight", "required", "battery_capacity_multiplier"]:
		if data.has(key) and (not _number(data[key]) or float(data[key]) <= 0.0): return "月球货物参数无效。"
	for key in ["id", "rep", "seed", "reward"]:
		if data.has(key) and (not _integer(data[key]) or float(data[key]) < 0.0): return "月球委托编号或费用无效。"
	if data.has("id") and int(data.id) != 4: return "月球委托航线编号不一致。"
	if data.has("contract_id"):
		if not _label(data.contract_id): return "月球委托编号无效。"
		for key in ["id", "rep", "reward", "weight", "required"]:
			if not data.has(key): return "月球货物记录不完整。"
	for key in ["distance", "delivery_radius", "time_limit", "deadline", "boundary_y", "pilot_battery_multiplier", "pilot_energy_tariff", "pilot_net_force_limit", "lookahead_seconds"]:
		if not _number(data.get(key)) or float(data[key]) <= 0.0: return "月球航段参数无效。"
	for key in ["max_delivery_speed", "variation", "pilot_drag", "pilot_cruise_speed", "pilot_boost_speed", "pilot_vertical_speed"]:
		if not _number(data.get(key)) or float(data[key]) < 0.0: return "月球驾驶参数无效。"
	for key in ["destination_y", "gravity", "pilot_altitude", "pilot_climb_start", "pilot_climb_end", "background_ground_y_m", "moon_surface_y", "moon_approach_start", "moon_clear_approach_start"]:
		if not _number(data.get(key)): return "月球航段坐标无效。"
	if not _numbers(data.get("wind"), 2): return "月球风力记录无效。"
	if float(data.pilot_climb_end) <= float(data.pilot_climb_start) or float(data.pilot_climb_end) >= float(data.moon_approach_start): return "月球爬升段边界无效。"
	if float(data.moon_approach_start) >= float(data.moon_clear_approach_start) or float(data.moon_clear_approach_start) >= float(data.distance): return "月球进近边界无效。"
	if float(data.distance) > 100000.0 or float(data.boundary_y) > 10000.0: return "月球航段范围无效。"
	if absf(float(data.destination_y)) + float(data.delivery_radius) >= float(data.boundary_y): return "月球收件舱超出航段边界。"
	if not data.get("moon_receiver") is Dictionary: return "月球收件舱记录缺失。"
	var receiver: Dictionary = data.moon_receiver
	for key in ["id", "entrance_side", "art_profile", "hardware_model"]:
		if not _label(receiver.get(key)): return "月球收件舱标识无效。"
	if receiver.id != DESTINATION_ID or receiver.entrance_side != "left" or receiver.art_profile != "moon-airlock-pixel-v1": return "月球收件舱标识不一致。"
	for key in ["capture_plane_x", "capture_center_y", "capture_radius", "ingress_center_y", "conservative_ingress_half_height", "fully_transparent_ingress_y_min", "fully_transparent_ingress_y_max", "ingress_reference_x", "surface_y", "meters_per_native_pixel", "capture_radius_native"]:
		if not _number(receiver.get(key)): return "月球收件舱尺寸无效。"
	for key in ["surface_contact_native", "capture_anchor_native", "texture_size_native", "sprite_top_left"]:
		if not _numbers(receiver.get(key), 2): return "月球收件舱注册坐标无效。"
	if not _numbers(receiver.get("visual_bounds"), 4): return "月球收件舱画面范围无效。"
	if receiver.capture_plane_x != data.distance or receiver.capture_center_y != data.destination_y or receiver.capture_radius != data.delivery_radius or receiver.surface_y != data.moon_surface_y: return "月球收件舱与航线坐标不一致。"
	if receiver.meters_per_native_pixel != AIRLOCK_METERS_PER_PIXEL or receiver.capture_anchor_native != [244.0, 392.0] or receiver.texture_size_native != [688.0, 688.0] or receiver.surface_contact_native != [217.0, 628.0] or receiver.capture_radius_native != 64.0: return "月球收件舱源图注册不一致。"
	# The saved capture volume, art and source-inscribed hardware share one scale.
	# Changing both route/receiver radii cannot bypass the fixed native registration.
	if receiver.capture_radius != receiver.capture_radius_native * receiver.meters_per_native_pixel: return "月球收件舱尺寸与源图不一致。"
	var origin = [float(data.distance) - 244.0 * AIRLOCK_METERS_PER_PIXEL, float(data.destination_y) - 392.0 * AIRLOCK_METERS_PER_PIXEL]
	if receiver.sprite_top_left != origin or receiver.visual_bounds != [origin[0] + 40.0 * AIRLOCK_METERS_PER_PIXEL, origin[1] + 54.0 * AIRLOCK_METERS_PER_PIXEL, 86.90625, 80.71875]: return "月球收件舱画面注册不一致。"
	if receiver.surface_y != origin[1] + 628.0 * AIRLOCK_METERS_PER_PIXEL or receiver.ingress_center_y != float(data.destination_y) - 1.40625 or receiver.conservative_ingress_half_height != 6.1875 or receiver.fully_transparent_ingress_y_min != float(data.destination_y) - 7.875 or receiver.fully_transparent_ingress_y_max != float(data.destination_y) + 5.0625 or receiver.ingress_reference_x != origin[0] + 120.0 * AIRLOCK_METERS_PER_PIXEL: return "月球收件舱入口注册不一致。"
	if not data.get("hazards") is Array or data.hazards.size() != 28 or not receiver.get("hardware_hazard_ids") is Array or receiver.hardware_hazard_ids.size() != 14: return "月球碰撞记录不完整。"
	var ids: Dictionary = {}; var hardware_ids: Array = []; var roles = {"crag": 0, "ore": 0, "airlock": 0}
	for index in range(data.hazards.size()):
		var hazard: Variant = data.hazards[index]
		if not hazard is Dictionary: return "月球碰撞记录无效。"
		for key in ["x", "y", "radius", "mass", "health"]:
			if not _number(hazard.get(key)): return "月球碰撞坐标无效。"
		for key in ["cooldown", "strength", "range", "damage", "fire_interval"]:
			if hazard.has(key) and not _number(hazard[key]): return "月球碰撞附加参数无效。"
		for key in ["tracking", "conductive", "pilot_gate"]:
			if hazard.has(key) and not hazard[key] is bool: return "月球碰撞标记无效。"
		if not Vector2(float(hazard.x), float(hazard.y)).is_finite() or not is_finite(float(hazard.radius) + absf(float(hazard.x)) + absf(float(hazard.y))): return "月球碰撞坐标超出数值范围。"
		if float(hazard.radius) <= 0.0 or float(hazard.mass) <= 0.0 or float(hazard.health) <= 0.0 or not hazard.get("destructible") is bool or not hazard.get("type") is String or hazard.type != "rock": return "月球碰撞参数无效。"
		# This schema contains static circles with unambiguous x/y coordinates.
		if hazard.has("position") or hazard.has("velocity"): return "月球静态碰撞记录不一致。"
		if index < 8:
			if not (hazard.get("pilot_gate") is bool and hazard.pilot_gate) or not _integer(hazard.get("gate_index")) or int(hazard.gate_index) != index / 2 or hazard.destructible or hazard.has("moon"): return "月球爬升障碍记录不一致。"
			continue
		if not _label(hazard.get("id")) or ids.has(hazard.id) or not (hazard.get("moon") is bool and hazard.moon) or not _integer(hazard.get("moon_group")) or not hazard.get("moon_role") is String or not roles.has(hazard.moon_role): return "月球障碍标识无效。"
		ids[hazard.id] = true; roles[hazard.moon_role] += 1
		if hazard.moon_role == "ore":
			if not hazard.destructible or hazard.health != 80.0 or hazard.mass != 20.0: return "月球矿石参数无效。"
		elif hazard.destructible: return "月球岩脊或收件舱不可钻切。"
		if hazard.moon_role != "airlock" and float(hazard.x) + float(hazard.radius) >= float(data.moon_clear_approach_start): return "月球末段进近被障碍占用。"
		if hazard.moon_role == "airlock":
			var sample_index: int = hardware_ids.size()
			if sample_index >= HARDWARE_NATIVE.size(): return "月球收件舱碰撞数量无效。"
			var source: Array = HARDWARE_NATIVE[sample_index]
			if hazard.id != "airlock-" + str(source[0]) or not _numbers(hazard.get("source_circle_native"), 3) or hazard.source_circle_native != [source[1], source[2], source[3]]: return "月球收件舱碰撞注册无效。"
			if hazard.x != origin[0] + float(source[1]) * AIRLOCK_METERS_PER_PIXEL or hazard.y != origin[1] + float(source[2]) * AIRLOCK_METERS_PER_PIXEL or hazard.radius != float(source[3]) * AIRLOCK_METERS_PER_PIXEL: return "月球收件舱碰撞坐标不一致。"
			hardware_ids.append(hazard.id)
	if roles != {"crag": 4, "ore": 2, "airlock": 14} or receiver.hardware_hazard_ids != hardware_ids: return "月球障碍与收件舱引用不一致。"
	if not data.get("pilot_gates") is Array or data.pilot_gates.size() != 4: return "月球爬升指引记录无效。"
	for index in range(4):
		var gate: Variant = data.pilot_gates[index]
		if not gate is Dictionary: return "月球爬升指引记录无效。"
		for key in ["x", "y", "half_gap", "heading", "lane_offset"]:
			if not _number(gate.get(key)): return "月球爬升指引坐标无效。"
		if not _integer(gate.get("index")) or gate.index != index or float(gate.half_gap) <= 0.0: return "月球爬升指引编号无效。"
	if not data.get("moon_landmarks") is Array or data.moon_landmarks.size() != 5: return "月球参考航点记录无效。"
	var previous_x = -INF
	for landmark in data.moon_landmarks:
		if not landmark is Dictionary or not _label(landmark.get("id")) or not _number(landmark.get("x")) or not _number(landmark.get("y")): return "月球参考航点坐标无效。"
		if float(landmark.x) <= previous_x: return "月球参考航点顺序无效。"
		previous_x = float(landmark.x)
	if not data.get("moon_render_requirements") is Dictionary: return "月球画面要求记录无效。"
	var requirements: Dictionary = data.moon_render_requirements
	for key in ["minimum_forward_m", "lookahead_seconds", "vertical_padding_m", "clear_receiver_preview_from_x"]:
		if not _number(requirements.get(key)) or float(requirements[key]) <= 0.0: return "月球画面范围记录无效。"
	for key in ["full_hazard_bounds_above_hud", "physical_geometry_from_saved_hazards"]:
		if not requirements.get(key) is bool or not requirements[key]: return "月球画面几何要求不完整。"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) >= -9223372036854775808.0 and float(value) < 9223372036854775808.0 and float(value) == floor(float(value))

static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not _number(number): return false
	return true

static func _label(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 240 and not value.contains("\n") and not value.contains("\r")

static func _json_finite(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not _json_finite(value[key], depth + 1): return false
		return true
	if value is Array:
		for item in value:
			if not _json_finite(item, depth + 1): return false
		return true
	return value == null or value is String or value is bool or _number(value)

static func _has_foreign_markers(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if key == "wormhole" or key.begins_with("wormhole_") or key == "otherworld" or key.begins_with("otherworld_"): return true
			if _has_foreign_markers(value[key]): return true
	elif value is Array:
		for item in value:
			if _has_foreign_markers(item): return true
	return false
