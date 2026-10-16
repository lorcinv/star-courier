extends Node2D
## Read-only, tick-sampled presentation for one explicitly validated v5 entity.
## No simulation writes, evidence authoring, wall clock, collider or particles.
const Profile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Advice = preload("res://scripts/protected_bird_advice_2d.gd")
const UP = preload("res://assets/2d_v5/protected_birds/mosslight-protected-bird-wings-up.png")
const DOWN = preload("res://assets/2d_v5/protected_birds/mosslight-protected-bird-wings-down.png")
const HURT = preload("res://assets/2d_v5/protected_birds/mosslight-protected-bird-hurt.png")
const FONT = preload("res://assets/fonts/ChineseSans.otf")
const ANCHOR = Vector2(32, 32)
const REFERENCE_CORE_RADIUS_PX = 12.0
const RADIUS_M = 0.375
const MAX_CHILDREN = 4
const FLAP_HALF_TICKS = 14
const NOTICE_TICKS = 72
const ROUTE_POINTS = [Vector2(1060, -143), Vector2(1100, -143), Vector2(1140, -146)]
const INK = Color("d5efd0")
const HURT_INK = Color("f0ca96")

var reduced_motion: bool = false
var _bird: Sprite2D
var _marker: Label
var _edge: Label
var _path: Label
var _enabled: bool = false
var _identity: Dictionary = {}
var _saved_route: Dictionary = {}
var _origin: Vector2 = Vector2.ZERO
var _cell: float = 72.0
var _sample: Dictionary = {}
var _last_tick: int = -1
var _notice_until: int = -1
var _new_hp_notices: int = 0
var _view: Rect2
var _zoom: float = 1.0
var _have_view: bool = false
var _pose: String = "wings-down"
var _actual_visible: bool = false
var _fully_visible: bool = false
var _actual_bounds: Rect2
var _frozen: bool = false
var _advice_active: bool = false
var _opaque_centers: Dictionary = {}
var _hud_occluders: Array = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false); set_physics_process(false)
	_ensure_nodes()

func _ensure_nodes() -> void:
	if is_instance_valid(_bird): return
	for pair in [["wings-up", UP], ["wings-down", DOWN], ["hurt", HURT]]:
		var pixels = []
		var source: Image = pair[1].get_image()
		for y in source.get_height():
			for x in source.get_width():
				if source.get_pixel(x,y).a > 0.0: pixels.append(Vector2(x + 0.5,y + 0.5) - ANCHOR)
		_opaque_centers[pair[0]] = pixels
	_bird = Sprite2D.new(); _bird.name = "RegisteredProtectedBird"
	_bird.centered = false; _bird.offset = -ANCHOR
	_bird.texture = DOWN; _bird.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bird.set_meta("native_torso_anchor", ANCHOR)
	_bird.set_meta("physical_radius_m", RADIUS_M)
	_bird.set_meta("generated_raster", true)
	add_child(_bird)
	_marker = _label("ProtectionMarker", 18)
	_edge = _label("OffscreenProtectionNotice", 18)
	_path = _label("LowerPassageNotice", 16)
	_path.text = "从下方绕行"
	_hide_nodes()

func _label(label_name: String, font_size: int) -> Label:
	var label = Label.new(); label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color("182732"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color("182732"))
	add_child(label)
	return label

static func accepts_route(route: Variant) -> bool:
	return route is Dictionary and Profile.same_value(route.get("control_version"), Profile.CONTROL_VERSION) and Profile.validation_error(route).is_empty()

func configure(sim, new_origin: Vector2, new_cell: float, _restoring: bool = false) -> bool:
	leave_flight(); _ensure_nodes()
	if sim == null or not accepts_route(sim.route) or not new_origin.is_finite() or not is_finite(new_cell) or new_cell <= 0.0 or new_cell > 10000.0: return false
	_origin = new_origin; _cell = new_cell
	# IDs are copied for matching only. Never expose or mutate the saved record.
	_identity = {"contract_id":sim.route.contract_id, "event_id":sim.route.ecology.event_id,
		"entity_id":sim.route.ecology.entity_id, "species_id":sim.route.ecology.species_id,
		"seed":sim.route.seed, "sim_instance":sim.get_instance_id()}
	_saved_route = sim.route.duplicate(true)
	_enabled = true
	if not _valid_snapshot(sim): leave_flight(); return false
	_baseline(sim)
	_bird.scale = Vector2.ONE * _cell * RADIUS_M / REFERENCE_CORE_RADIUS_PX
	_bird.set_meta("entity_id", _identity.entity_id)
	# Baseline every configure, including live retries and restored hurt states.
	# Historical HP loss is never interpreted as a new injury notice.
	return true

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _nonnegative_integer(value: Variant) -> bool:
	return value is int and value >= 0

func _valid_snapshot(sim) -> bool:
	if sim == null or sim.get_instance_id() != _identity.sim_instance: return false
	if not sim.route is Dictionary or not Profile.same_value(sim.route, _saved_route): return false
	if sim.route.get("control_version") != Profile.CONTROL_VERSION or sim.route.get("route_profile") != Profile.ROUTE_PROFILE: return false
	if sim.route.get("contract_id") != _identity.contract_id or sim.route.get("seed") != _identity.seed: return false
	if not sim.route.get("ecology") is Dictionary: return false
	if not Profile.same_value(sim.route.ecology, Profile.event_definition(_identity.contract_id, _identity.seed)): return false
	if not sim.wildlife_error is String or not sim.wildlife_error.is_empty(): return false
	if not _nonnegative_integer(sim.pilot_tick) or not sim.status is String or sim.status not in ["running", "success", "failed"]: return false
	if not sim.wildlife is Dictionary or sim.wildlife.is_empty(): return false
	var bird: Dictionary = sim.wildlife
	for key in ["event_id", "entity_id", "species_id"]:
		if not Profile.same_value(bird.get(key), _identity[key]): return false
	for key in ["position", "velocity"]:
		if not bird.get(key) is Vector2 or not bird[key].is_finite(): return false
	for key in ["radius", "mass", "hp"]:
		if not _finite_number(bird.get(key)): return false
	if float(bird.radius) != RADIUS_M or float(bird.mass) != 0.125 or float(bird.hp) < 0.0 or float(bird.hp) > 8.0: return false
	if not bird.get("active") is bool or not bird.get("activated") is bool: return false
	if not bird.get("state") is String or bird.state not in ["waiting", "healthy", "hurt", "injured", "falling", "gone", "departed"]: return false
	for key in ["damage_transitions", "hurt_ticks", "fall_ticks"]:
		if not _nonnegative_integer(bird.get(key)): return false
	if bird.hurt_ticks > 36 or bird.fall_ticks > 48: return false
	if not bird.get("activation_tick") is int or not _finite_number(bird.get("activation_fraction")): return false
	if float(bird.activation_fraction) < 0.0 or float(bird.activation_fraction) > 1.0: return false
	if bird.activated:
		if bird.activation_tick < 0 or bird.activation_tick > sim.pilot_tick or bird.state == "waiting": return false
	else:
		if bird.active or bird.state != "waiting" or bird.activation_tick != -1 or bird.hp != 8.0 or bird.damage_transitions != 0: return false
	if bird.active != (bird.state in ["healthy", "hurt", "injured"]): return false
	if bird.state in ["falling", "gone"] and bird.hp != 0.0: return false
	if bird.state in ["healthy", "hurt", "injured"] and bird.hp <= 0.0: return false
	return true

func _baseline(sim) -> void:
	_sample = sim.wildlife.duplicate(true)
	_sample["flight_status"] = sim.status
	_last_tick = sim.pilot_tick
	_notice_until = -1
	_advice_active = Advice.active(sim.status, _sample, sim.get("bodies"))

func update_from_sim(sim, world_view: Rect2, logical_zoom: float, paused_visual: bool = false, hud_occluders: Array = []) -> void:
	if not _enabled: return
	if not _valid_snapshot(sim): leave_flight(); return
	if not world_view.position.is_finite() or not world_view.size.is_finite() or world_view.size.x <= 0.0 or world_view.size.y <= 0.0 or not is_finite(logical_zoom) or logical_zoom <= 0.0: return
	_frozen = paused_visual or sim.paused
	# Pause freezes the material sample and tick-derived animation. Native HUD
	# occlusion and resize may still reflow labels without advancing that sample.
	if sim.pilot_tick < _last_tick: return # Resume/retry must explicitly configure.
	if sim.pilot_tick > _last_tick and not _frozen:
		var next: Dictionary = sim.wildlife
		if next.damage_transitions < _sample.damage_transitions or float(next.hp) > float(_sample.hp): leave_flight(); return
		if float(next.hp) < float(_sample.hp) and next.damage_transitions > _sample.damage_transitions:
			_notice_until = sim.pilot_tick + NOTICE_TICKS
			_new_hp_notices += 1
		_sample = next.duplicate(true); _sample["flight_status"] = sim.status; _last_tick = sim.pilot_tick
		_advice_active = Advice.active(sim.status, _sample, sim.get("bodies"))
	if not _frozen:
		_sample["flight_status"] = sim.status
		if sim.status != "running": _advice_active = false
	if hud_occluders.size() > 32: leave_flight(); return
	for region in hud_occluders:
		if not region is Rect2 or not region.position.is_finite() or not region.size.is_finite(): leave_flight(); return
	_hud_occluders = hud_occluders.duplicate()
	_view = world_view; _zoom = logical_zoom; _have_view = true
	_render()

func _render() -> void:
	_hide_nodes()
	_actual_visible = false; _fully_visible = false; _actual_bounds = Rect2()
	if not _enabled or _sample.is_empty() or not _sample.activated: return
	if _sample.state not in ["healthy", "hurt", "injured", "falling"]: return
	var bird_at: Vector2 = _origin + _sample.position * _cell
	_bird.position = bird_at
	var moving: Vector2 = _sample.velocity
	_bird.flip_h = moving.x > 0.001
	_bird.rotation = clampf(atan2(moving.y, maxf(0.001, absf(moving.x))) * (1.0 if _bird.flip_h else -1.0), -0.38, 0.38) if moving.length_squared() > 0.000001 else 0.0
	var hurt: bool = _sample.state in ["hurt", "injured", "falling"]
	_pose = "hurt" if hurt else ("wings-down" if reduced_motion or ((_last_tick - int(_sample.activation_tick)) / FLAP_HALF_TICKS) % 2 == 0 else "wings-up")
	_bird.texture = HURT if hurt else (DOWN if _pose == "wings-down" else UP)
	_bird.modulate = Color.WHITE
	if _sample.state == "falling": _bird.modulate.a = clampf(1.0 - float(_sample.fall_ticks) / 48.0, 0.0, 1.0)
	_bird.visible = _bird.modulate.a > 0.0
	_actual_bounds = _raster_bounds()
	_fully_visible = _bird.visible and _rect_clear(_actual_bounds)
	_actual_visible = _fully_visible or (_bird.visible and _view.intersects(_actual_bounds) and _opaque_center_in_view())
	_marker.text = "保护鸟受伤了" if _notice_until >= _last_tick else ("保护鸟 · 请绕行" if _advice_active else "保护鸟")
	_marker.add_theme_color_override("font_color", HURT_INK if _notice_until >= _last_tick else INK)
	_marker.scale = Vector2.ONE / _zoom
	_marker.visible = _actual_visible and _place_label(_marker, bird_at + Vector2(0, -30.0) / _zoom)
	# Edge text helps anticipation, but is never counted as creature visibility.
	if _advice_active and (not _fully_visible or not _marker.visible):
		_edge.text = ("保护鸟在前方 →" if bird_at.x > _view.get_center().x else "← 保护鸟在后方") + "  从下方绕行"
		_edge.scale = Vector2.ONE / _zoom
		var inset: Rect2 = _view.grow(-28.0 / _zoom)
		var edge_at = Vector2(clampf(bird_at.x, inset.position.x, inset.end.x), clampf(bird_at.y, inset.position.y + 28.0 / _zoom, inset.end.y))
		_edge.visible = _place_label(_edge, edge_at)
	if _advice_active:
		var waypoint: Vector2 = _origin + ROUTE_POINTS[0] * _cell
		_path.scale = Vector2.ONE / _zoom
		_path.visible = _point_clear(waypoint) and _place_label(_path, waypoint + Vector2(0, 20.0) / _zoom)
	visible = true

func _place_label(label: Label, anchor: Vector2) -> bool:
	label.reset_size()
	var size_world: Vector2 = label.get_combined_minimum_size() / _zoom
	var inset: float = 12.0 / _zoom
	var start = Vector2(clampf(anchor.x - size_world.x * 0.5, _view.position.x + inset, maxf(_view.position.x + inset, _view.end.x - size_world.x - inset)), clampf(anchor.y - size_world.y, _view.position.y + inset, maxf(_view.position.y + inset, _view.end.y - size_world.y - inset)))
	var options = [start]
	for region in _hud_occluders:
		options.append(Vector2(start.x, region.position.y - size_world.y - inset))
		options.append(Vector2(start.x, region.end.y + inset))
		options.append(Vector2(region.position.x - size_world.x - inset, start.y))
		options.append(Vector2(region.end.x + inset, start.y))
	var best: Vector2 = start
	var distance: float = INF
	for at in options:
		if _rect_clear(Rect2(at,size_world)) and at.distance_squared_to(start) < distance:
			best = at; distance = at.distance_squared_to(start)
	if not is_finite(distance): return false
	label.position = best
	return true

func _rect_clear(rect: Rect2) -> bool:
	if not _view.encloses(rect): return false
	for region in _hud_occluders:
		if region.intersects(rect): return false
	return true

func _point_clear(point: Vector2) -> bool:
	if not _view.has_point(point): return false
	for region in _hud_occluders:
		if region.has_point(point): return false
	return true

func _raster_bounds() -> Rect2:
	var bounds: Rect2 = Rect2(15, 6, 40, 35) if _pose == "wings-up" else (Rect2(16, 15, 39, 27) if _pose == "hurt" else Rect2(15, 18, 40, 27))
	var points = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	var first: Vector2 = points[0] - ANCHOR
	if _bird.flip_h: first.x = -first.x
	var result = Rect2(_bird.transform * first, Vector2.ZERO)
	for point in points:
		var local: Vector2 = point - ANCHOR
		if _bird.flip_h: local.x = -local.x
		result = result.expand(_bird.transform * local)
	return result

func _opaque_center_in_view() -> bool:
	# Only partial-boundary frames need this bounded cached source-alpha check.
	# A transparent AABB corner or edge notice never counts as the creature.
	for point in _opaque_centers.get(_pose, []):
		var local: Vector2 = point
		if _bird.flip_h: local.x = -local.x
		if _point_clear(_bird.transform * local): return true
	return false

func cue_state() -> Dictionary:
	# A single lower-path suggestion. It neither asserts universal clearance nor
	# selects a target, traces weapons or creates evidence of contact.
	var active: bool = _enabled and _advice_active
	var points = []
	if active:
		for point in ROUTE_POINTS:
			var at: Vector2 = _origin + point * _cell
			if _rect_clear(Rect2(at - Vector2.ONE * 9.0 / _zoom,Vector2.ONE * 18.0 / _zoom)): points.append(point)
	return {"active":active, "entity_id":str(_identity.get("entity_id", "")), "points":points, "zoom":_zoom}

func advisory_state() -> Dictionary:
	# Main forwards this exact sampled decision to HUD; no second geometry test.
	return {"active":_advice_active} if _enabled else {}

func _hide_nodes() -> void:
	for node in [_bird, _marker, _edge, _path]:
		if is_instance_valid(node): node.hide()
	visible = false

func leave_flight() -> void:
	_enabled = false; _identity.clear(); _saved_route.clear(); _sample.clear(); _hud_occluders.clear(); _last_tick = -1
	_notice_until = -1; _new_hp_notices = 0; _have_view = false; _frozen = false; _advice_active = false
	_actual_visible = false; _fully_visible = false; _actual_bounds = Rect2()
	_view = Rect2(); _pose = "wings-down"; _zoom = 1.0
	_hide_nodes()

func debug_snapshot() -> Dictionary:
	return {"enabled":_enabled, "entity_id":str(_identity.get("entity_id", "")), "tick":_last_tick,
		"pose":_pose, "position_m":_sample.get("position", Vector2.ZERO), "velocity_mps":_sample.get("velocity", Vector2.ZERO),
		"hp":_sample.get("hp", 0.0), "state":_sample.get("state", ""), "new_hp_notices":_new_hp_notices,
		"notice_until_tick":_notice_until, "creature_visible":_actual_visible, "creature_fully_visible":_fully_visible,
		"creature_bounds_world_px":_actual_bounds, "edge_notice_visible":_edge.visible if is_instance_valid(_edge) else false,
		"marker_visible":_marker.visible if is_instance_valid(_marker) else false,
		"projected_torso_diameter_logical_px":2.0 * RADIUS_M * _cell * _zoom,
		"full_body_with_marker":_fully_visible and is_instance_valid(_marker) and _marker.visible, "marker_text":_marker.text if is_instance_valid(_marker) else "",
		"sprite_alpha":_bird.modulate.a if is_instance_valid(_bird) else 0.0,
		"nodes":get_child_count(), "materials":0, "particles":0, "cached_alpha_poses":_opaque_centers.size(), "hud_occluder_count":_hud_occluders.size(), "physical_radius_m":RADIUS_M,
		"advice_active":_advice_active, "torso_anchor_native":ANCHOR, "origin":_origin, "cell":_cell, "frozen":_frozen}
