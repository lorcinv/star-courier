extends "res://scripts/pilot_extreme_simulation.gd"
## Additive staged protocol. The existing v3 chronological solver remains intact.
## Portal crossings are discrete CCD events, ordered with ordinary contacts.
const Wormhole = preload("res://scripts/pilot_wormhole_profile.gd")
var wormhole_events: Array = []
var _station_remaining: float = 0.0
var _portal_ready: bool = false
var _denied_keys: Dictionary = {}
var _attempted_anchors: Dictionary = {}

func configure(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> void:
	_portal_ready = false; _station_remaining = 0.0
	wormhole_events.clear(); _denied_keys.clear(); _attempted_anchors.clear()
	var error = Wormhole.validation_error(route_data)
	if not error.is_empty():
		# Do not feed malformed route arithmetic into inherited spawn/telemetry.
		# The caller retains its original snapshot and must block resume/save.
		super.configure([], [], Wormhole.route(), random_seed)
		route.control_version = Wormhole.CONTROL_VERSION; route.pilot_profile = Wormhole.CONTROL_VERSION
		status = "failed"; _log(error); _finalize_recovery(); _refresh_telemetry(); return
	super.configure(design, launcher, route_data, random_seed)
	route.control_version = Wormhole.CONTROL_VERSION
	route.pilot_profile = Wormhole.CONTROL_VERSION
	_station_remaining = float(route.wormhole_portal.station_energy_j)
	_portal_ready = true
	_refresh_telemetry()

func _tick(dt: float) -> void:
	_attempted_anchors.clear()
	super._tick(dt)

func _next_contact(used_drills: Dictionary) -> Dictionary:
	var ordinary = super._next_contact(used_drills)
	if not _portal_ready: return ordinary
	var portal: Dictionary = route.wormhole_portal
	var entry = Vector2(float(portal.entry[0]), float(portal.entry[1]))
	var best: Dictionary = {}
	for body in bodies:
		if _body_used_portal(body, str(portal.id)) or _attempted_anchors.has(_anchor_id(body)): continue
		var start: Vector2 = _motion_bodies.get(body.id, {}).get("position", body.position)
		var finish: Vector2 = body.position
		if start.x > entry.x + EPS or finish.x < entry.x or finish.x <= start.x + EPS: continue
		var fraction = clampf((entry.x - start.x) / (finish.x - start.x), 0.0, 1.0)
		var anchor: int = _anchor_id(body)
		# An attempted crossing outside the visible disk is ordinary local flight.
		if absf(start.lerp(finish, fraction).y - entry.y) > float(portal.aperture_radius): continue
		var candidate = {"p": anchor, "q": -1, "h": -1, "time": fraction,
			"normal": Vector2.LEFT, "wormhole": true}
		if best.is_empty() or fraction < float(best.time) or (fraction == float(best.time) and anchor < int(best.p)):
			best = candidate
	# A physical collision wins a tie. The portal never erases a pending impact.
	if best.is_empty() or (not ordinary.is_empty() and float(ordinary.time) <= float(best.time)):
		return ordinary
	return best

func _try_collinear_contacts(hit: Dictionary) -> bool:
	return false if hit.get("wormhole", false) else super._try_collinear_contacts(hit)

func _apply_swept_impulse(hit: Dictionary) -> void:
	if not hit.get("wormhole", false):
		super._apply_swept_impulse(hit); return
	var body = body_for_part(int(hit.p))
	if body.is_empty(): return
	_attempted_anchors[_anchor_id(body)] = true
	var portal: Dictionary = route.wormhole_portal
	var portal_id = str(portal.id)
	if _body_used_portal(body, portal_id): return
	var radius = _body_bound(body)
	var entry = Vector2(float(portal.entry[0]), float(portal.entry[1]))
	# Conservatively fit the complete circumscribed hull, including the drill tip.
	# The supported large craft bound is explicit; never move clipped components.
	if absf(body.position.y - entry.y) + radius + float(portal.margin) > float(portal.aperture_radius):
		_deny(body, "too_large_or_off_center", "未进入虫洞：请对准洞口，或缩小飞船轮廓。"); return
	var exit_position = Vector2(float(portal.exit[0]), float(portal.exit[1]))
	var target = exit_position + Vector2(radius + float(portal.margin), body.position.y - entry.y)
	if not _safe_exit(body, target, radius, float(portal.exit_lookahead)):
		_deny(body, "exit_blocked", "出口被挡住了，本次无法通行。"); return
	var cost = float(portal.base_energy_j) + body.mass * float(portal.energy_j_per_kg)
	if not is_finite(cost) or cost > _station_remaining + EPS:
		_deny(body, "station_empty", "驿站通行电量不足，本次无法过洞。"); return
	var from: Vector2 = body.position
	body.position = target
	var ids: Array = []
	for p in body.parts:
		if not p.alive or p.delivered: continue
		var visited: Dictionary = p.get("wormhole_visits", {}).duplicate(true)
		visited[portal_id] = true; p.wormhole_visits = visited; ids.append(int(p.id))
		# The inherited receiver must sweep only the actual exit-side trajectory.
		_motion_parts[p.id] = _part_position(p)
	ids.sort()
	_station_remaining = maxf(0.0, _station_remaining - cost)
	telemetry.energy_used += cost
	telemetry.wormhole_energy_used = float(telemetry.get("wormhole_energy_used", 0.0)) + cost
	var event = {"portal_id": portal_id, "tick": pilot_tick, "part_ids": ids,
		"from": [from.x, from.y], "to": [target.x, target.y], "energy_j": cost}
	wormhole_events.append(event)
	_log("已通过晨星虫洞。")
	_effect("wormhole", target, from, 0.35)

func _safe_exit(body: Dictionary, target: Vector2, radius: float, seconds: float) -> bool:
	# A circumscribed body disk encloses every possible rotation during lookahead.
	# This intentionally rejects tight exits; it does not grant immunity afterward.
	var expanded = radius + float(route.wormhole_portal.margin)
	var finish: Vector2 = target + body.velocity * seconds
	if minf(target.x, finish.x) - expanded < -30.0: return false
	if maxf(absf(target.y), absf(finish.y)) + expanded > float(route.get("boundary_y", 80.0)): return false
	for hi in range(obstacles.size()):
		var hazard: Dictionary = obstacles[hi]
		if hazard.health <= 0.0 or hazard.type == "gravity": continue
		var at: Vector2 = _motion_hazards[hi] if hi < _motion_hazards.size() else hazard.position
		var relative: Vector2 = target - at
		var relative_finish: Vector2 = finish - at - hazard.get("velocity", Vector2.ZERO) * seconds
		var clearance: float = expanded + hazard.radius
		if relative.length() <= clearance or _segment_circle_t(relative, relative_finish, clearance) >= 0.0: return false
	for other in bodies:
		if other.id == body.id: continue
		var relative: Vector2 = target - other.position
		var relative_finish: Vector2 = finish - other.position - other.velocity * seconds
		var clearance = expanded + _body_bound(other)
		if relative.length() <= clearance or _segment_circle_t(relative, relative_finish, clearance) >= 0.0: return false
	return true

func _body_bound(body: Dictionary) -> float:
	var radius = 0.0
	for p in body.parts:
		if p.alive and not p.delivered:
			radius = maxf(radius, p.local_pos.length() + (0.48 if p.type == "drill" else 0.43) * p.scale)
	return radius

func _body_used_portal(body: Dictionary, id: String) -> bool:
	for p in body.parts:
		if p.get("wormhole_visits", {}).has(id): return true
	return false

func _anchor_id(body: Dictionary) -> int:
	var id = 2147483647
	for p in body.parts:
		if p.alive and not p.delivered: id = mini(id, int(p.id))
	return id

func _deny(body: Dictionary, reason: String, message: String) -> void:
	var key = "%s:%s" % [_anchor_id(body), reason]
	if not _denied_keys.has(key):
		_denied_keys[key] = true; _log(message)
	telemetry.wormhole_last_denial = reason

func _check_status() -> void:
	if _portal_ready:
		var portal: Dictionary = route.wormhole_portal
		for p in parts.values():
			if p.type != "cargo" or not p.alive or p.delivered: continue
			# Actual traversal is a delivery prerequisite; flying across the unused
			# coordinate gap or using a mounted teleporter cannot fake an arrival.
			if _part_position(p).x >= float(portal.exit[0]) and not p.get("wormhole_visits", {}).has(str(portal.id)):
				status = "failed"; _log("错过了虫洞，未能到达苔光驿站。"); return
	super._check_status()

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	telemetry.control_version = Wormhole.CONTROL_VERSION
	telemetry.wormhole_transits = wormhole_events.size()
	telemetry.wormhole_station_remaining = _station_remaining
	telemetry.wormhole_energy_used = float(telemetry.get("wormhole_energy_used", 0.0))
	telemetry.wormhole_max_body_diameter = 0.0
	telemetry.wormhole_phase = "ascent"
	if not _portal_ready: return
	var portal: Dictionary = route.wormhole_portal
	telemetry.wormhole_max_body_diameter = 2.0 * (float(portal.aperture_radius) - float(portal.margin))
	var transited_cargo = false
	for p in parts.values():
		if p.type == "cargo" and p.get("wormhole_visits", {}).has(str(portal.id)):
			transited_cargo = true; break
	if transited_cargo:
		telemetry.wormhole_phase = "otherworld"
	elif cargo_position().x >= float(route.get("pilot_climb_end", 410.0)):
		telemetry.wormhole_phase = "space"
