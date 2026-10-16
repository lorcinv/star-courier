extends RefCounted
## Pure read-only presentation projection; never calls the simulation owner.
const VERSION := "pirate-view-model-v1"
const RAY_SCHEMA := "pirate-presentation-ray-v1"
const TEXELS_PER_METRE := 60.0
const BODY_RADIUS_M := 1.5
const MAX_RAYS := 2
const MAX_TICK := 1000000000
# These are visual hold durations measured only against authoritative ticks.
const PULSE_TICKS := 12.0
const IMPACT_TICKS := 18.0
const RAY_KEYS := ["schema", "event_id", "intent_id", "source_id", "tick", "fraction", "origin_x", "origin_y", "dir_x", "dir_y", "range_m", "outcome", "hit_distance_m", "target_key"]

static func compose(actor: Variant, clock: Variant, world_to_view: Transform2D, logical_pixel: float, ray_records: Variant = [], actor_id: String = "", reduced_motion: bool = false) -> Dictionary:
	if not _valid_clock(clock): return _fail("invalid_authoritative_clock")
	if not _valid_mapping(world_to_view) or not _number(logical_pixel, 0.01, 1000.0): return _fail("invalid_coordinate_mapping")
	if not _valid_actor(actor): return _fail("invalid_actor_view")
	var center := Vector2(float(actor.x), float(actor.y))
	var muzzle := world_to_view * Vector2(float(actor.left_muzzle_x), float(actor.left_muzzle_y))
	var state: String = "disabled" if actor.disabled else "charges-%d" % int(actor.shots_remaining)
	var body_transform := Transform2D(world_to_view.x / TEXELS_PER_METRE, world_to_view.y / TEXELS_PER_METRE, world_to_view * center)
	var frame := {"ok": true, "schema": VERSION, "body_state": state, "body_transform": body_transform,
		"solid": true, "live_muzzle": muzzle, "logical_pixel": logical_pixel,
		"warning": {}, "rays": [], "rejected_cues": [], "reduced_motion": reduced_motion}
	var w: Dictionary = actor.warning
	if not actor.disabled and int(actor.shots_remaining) > 0 and not w.is_empty():
		if not _valid_warning(w):
			frame.rejected_cues.append("invalid_warning")
		else:
			var now: float = float(clock.tick) + float(clock.fraction)
			# Closed/future/stale warning data never invents a live cue.
			if w.phase in ["warning", "ready"] and now >= float(w.locked_tick) and now <= float(w.due_tick):
				var origin := world_to_view * Vector2(float(w.origin_x), float(w.origin_y))
				var target := world_to_view * Vector2(float(w.target_x), float(w.target_y))
				var delta := origin - muzzle
				var link_length: float = minf(delta.length(), 32.0 * logical_pixel)
				var link_end: Vector2 = muzzle + delta.normalized() * link_length if delta.length() > 0.001 else muzzle
				frame.warning = {"event_id": w.event_id, "origin": origin, "target": target,
					"live_muzzle": muzzle, "link_end": link_end,
					"progress": clampf((now - float(w.locked_tick)) / float(w.due_tick - w.locked_tick), 0.0, 1.0),
					"phase": w.phase}
	if not ray_records is Array or ray_records.size() > MAX_RAYS:
		frame.rejected_cues.append("invalid_ray_collection")
		return frame
	var seen: Dictionary = {}
	for record in ray_records:
		if not _valid_ray(record, actor_id):
			frame.rejected_cues.append("invalid_or_incomplete_ray")
			continue
		if seen.has(record.intent_id):
			# Ambiguous duplicate identities suppress all ray effects.
			frame.rays.clear(); frame.rejected_cues.append("duplicate_ray_identity"); return frame
		seen[record.intent_id] = true
		var age: float = (float(clock.tick) - float(record.tick)) + (float(clock.fraction) - float(record.fraction))
		if age < 0.0 or age >= IMPACT_TICKS: continue
		var distance: float = float(record.hit_distance_m) if record.outcome == "hit" else float(record.range_m)
		var start_world := Vector2(float(record.origin_x), float(record.origin_y))
		# Preserve the owner's scalar frozen geometry: never aim at a live body.
		var end_world := Vector2(float(record.origin_x) + float(record.dir_x) * distance, float(record.origin_y) + float(record.dir_y) * distance)
		frame.rays.append({"intent_id": record.intent_id, "origin": world_to_view * start_world,
			"end": world_to_view * end_world, "outcome": record.outcome,
			"pulse": age < PULSE_TICKS, "impact": record.outcome == "hit",
			"alpha": 1.0 if reduced_motion else clampf(1.0 - age / IMPACT_TICKS, 0.0, 1.0)})
	return frame

static func _valid_actor(a: Variant) -> bool:
	if not a is Dictionary or a.get("ok") != true: return false
	for k in ["x", "y", "left_muzzle_x", "left_muzzle_y"]:
		if not a.has(k) or not _number(a[k], -1.0e9, 1.0e9): return false
	if not _number(a.get("hp"), 0.0, 1.0e9) or not a.get("disabled") is bool or not a.get("solid") is bool or not a.solid: return false
	if a.disabled != (float(a.hp) == 0.0) or not _integer(a.get("shots_remaining"), 0, 2) or not _integer(a.get("spent_mj"), 0, 36000): return false
	if not a.get("warning") is Dictionary: return false
	return absf(float(a.left_muzzle_x) - (float(a.x) - BODY_RADIUS_M)) <= 0.000001 and absf(float(a.left_muzzle_y) - float(a.y)) <= 0.000001

static func _valid_clock(c: Variant) -> bool:
	return c is Dictionary and _integer(c.get("tick"), 0, MAX_TICK) and _number(c.get("fraction"), 0.0, 1.0) and c.get("paused") is bool

static func _valid_warning(w: Dictionary) -> bool:
	if not w.get("event_id") is String or w.event_id.is_empty() or not w.get("phase") in ["warning", "ready", "cancelled", "emitted"]: return false
	if not _integer(w.get("locked_tick"), 0, MAX_TICK) or not _integer(w.get("due_tick"), 1, MAX_TICK) or w.due_tick <= w.locked_tick: return false
	for k in ["origin_x", "origin_y", "target_x", "target_y"]:
		if not _number(w.get(k), -1.0e9, 1.0e9): return false
	if not _direction(w): return false
	var dx: float = float(w.target_x) - float(w.origin_x)
	var dy: float = float(w.target_y) - float(w.origin_y)
	var length: float = sqrt(dx * dx + dy * dy)
	if length < 0.5 or length > 1.0e6: return false
	return absf(dx / length - float(w.dir_x)) < 0.000001 and absf(dy / length - float(w.dir_y)) < 0.000001

static func _valid_ray(r: Variant, actor_id: String) -> bool:
	if not r is Dictionary or r.size() != RAY_KEYS.size() or actor_id.is_empty(): return false
	for k in RAY_KEYS:
		if not r.has(k): return false
	if r.schema != RAY_SCHEMA or r.source_id != actor_id or not r.intent_id is String or r.intent_id.is_empty(): return false
	if not r.event_id is String or r.event_id.is_empty() or r.intent_id != r.event_id + "/shot": return false
	if not _integer(r.tick, 0, MAX_TICK) or not _number(r.fraction, 0.0, 1.0): return false
	if not _number(r.origin_x, -1.0e9, 1.0e9) or not _number(r.origin_y, -1.0e9, 1.0e9) or not _direction(r): return false
	if not _number(r.range_m, 0.5, 1.0e6): return false
	if r.outcome == "hit": return _number(r.hit_distance_m, 0.0, float(r.range_m)) and r.target_key is String and not r.target_key.is_empty()
	return r.outcome == "miss" and r.hit_distance_m == null and r.target_key == null

static func _direction(v: Dictionary) -> bool:
	return _number(v.get("dir_x"), -1.0, 1.0) and _number(v.get("dir_y"), -1.0, 1.0) and absf(float(v.dir_x) * float(v.dir_x) + float(v.dir_y) * float(v.dir_y) - 1.0) < 0.000001

static func _valid_mapping(t: Transform2D) -> bool:
	for v in [t.x, t.y, t.origin]:
		if not v.is_finite(): return false
	var sx: float = t.x.length()
	var sy: float = t.y.length()
	return sx >= 0.001 and sx <= 100000.0 and absf(sx - sy) <= maxf(0.00001, sx * 0.000001) and absf(t.x.dot(t.y)) <= maxf(0.00001, sx * sy * 0.000001)

static func _number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= low and float(v) <= high

static func _integer(v: Variant, low: int, high: int) -> bool:
	return _number(v, float(low), float(high)) and float(v) == floor(float(v))

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
