extends RefCounted
## Copies the accepted owner's ray and actual nearest-hit witness. No raycast.
const SCHEMA = "pirate-presentation-ray-v1"
const V = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const KEYS = ["schema", "event_id", "intent_id", "source_id", "tick", "fraction", "origin_x", "origin_y", "dir_x", "dir_y", "range_m", "outcome", "hit_distance_m", "target_key"]

static func capture(ray: Dictionary, target: Dictionary) -> Dictionary:
	var result = {"schema": SCHEMA}
	for key in ["event_id", "intent_id", "source_id", "tick", "fraction", "origin_x", "origin_y", "dir_x", "dir_y", "range_m"]: result[key] = ray[key]
	result["outcome"] = "miss" if target.is_empty() else "hit"
	result["hit_distance_m"] = null if target.is_empty() else target.distance
	result["target_key"] = null if target.is_empty() else target.key
	return result

static func validate(records: Variant, actor: Dictionary) -> bool:
	if not records is Array or records.size() != actor.emissions.size() or records.size() > 2: return false
	for index in records.size():
		var r: Variant = records[index]; var emitted: Dictionary = actor.emissions[index]
		if not V.exact(r, KEYS) or r.schema != SCHEMA: return false
		for key in ["event_id", "intent_id", "source_id", "tick", "fraction"]:
			if typeof(r[key]) != typeof(emitted[key]) or r[key] != emitted[key]: return false
		var warning: Dictionary = {}
		for item in actor.warnings:
			if item.event_id == r.event_id: warning = item; break
		if warning.is_empty(): return false
		for key in ["origin_x", "origin_y", "dir_x", "dir_y"]:
			if not V.real(r[key], -1.0e9, 1.0e9) or r[key] != warning[key]: return false
		if not V.real(r.range_m, 0.0, 1.0e9) or r.range_m != actor.definition.range_m: return false
		if r.outcome == "miss":
			if r.hit_distance_m != null or r.target_key != null: return false
		elif r.outcome == "hit":
			if not V.real(r.hit_distance_m, 0.0, r.range_m) or not r.target_key is String or r.target_key.is_empty() or r.target_key.length() > 128: return false
		else: return false
	return true
