extends RefCounted
## Chunked exact native-value transport. Existing value codec remains unchanged.
## Blocks retain Vector2 versus Array, integer dictionary keys and infinity
## sensor sentinels. All real physical state is validated finite before load.
const V = preload("res://vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const Actor = preload("res://scripts/pirate_actor_reconstructed_v1.gd")
const VERSION = "pirate-candidate-native-snapshot-2"
const FIELDS = ["status", "elapsed", "events", "incidents", "_incident_keys", "effects", "telemetry", "route", "seed_value", "_next_id", "_body_id", "_accumulator",
	"_initial_value", "_initial_cargo_hp", "_initial_mass", "_initial_cargo_count", "_graph_dirty", "_origin", "launcher_origin", "_settlement_finalized", "_split_limit_noted",
	"pilot_tick", "pilot_axis_q", "pilot_boost", "pilot_active", "_tick_dt", "_planned_forces", "_planned_bodies", "_motion_bodies", "_motion_parts", "_motion_hazards",
	"_source_forces", "_shield_spent", "_shield_valve_spent", "_paid_drills", "_sources_live", "_skip_inherited_sweeps", "_load_edges",
	"pirate", "pirate_body", "chrono_fraction", "chrono_error", "chrono_paused", "chrono_trace", "chrono_reservations", "chrono_command", "_chrono_due", "_chrono_hazards",
	"_chrono_planning_source", "_chrono_consumed", "links", "obstacles", "launcher_parts"]

static func save(owner) -> Dictionary:
	var blocks: Array = []
	for key in FIELDS:
		var packet = V.pack_json(_lift(owner.get(key)), VERSION)
		if packet.is_empty(): return {"ok": false, "error": "snapshot_field_bound:" + key}
		blocks.append({"key": key, "packet": packet})
	var ids = owner.parts.keys(); ids.sort()
	for id in ids:
		var packet = V.pack_json(_lift(owner.parts[id]), VERSION)
		if packet.is_empty(): return {"ok": false, "error": "snapshot_part_bound"}
		blocks.append({"key": "part:%d" % id, "packet": packet})
	for body in owner.bodies:
		var copy: Dictionary = body.duplicate(false)
		copy.parts = []
		for p in body.parts: copy.parts.append(int(p.id))
		var packet = V.pack_json(_lift(copy), VERSION)
		if packet.is_empty(): return {"ok": false, "error": "snapshot_body_bound"}
		blocks.append({"key": "body:%d" % body.id, "packet": packet})
	return {"ok": true, "json": JSON.stringify({"schema": VERSION, "blocks": blocks})}

static func restore(owner, text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > 4000000: return {"ok": false, "error": "snapshot_size"}
	var parser = JSON.new()
	if parser.parse(text) != OK or not V.exact(parser.data, ["schema", "blocks"]) or parser.data.schema != VERSION:
		return {"ok": false, "error": "unsupported_candidate_snapshot"}
	if not parser.data.blocks is Array or parser.data.blocks.size() > 512: return {"ok": false, "error": "snapshot_blocks"}
	var decoded: Dictionary = {}; var new_parts: Dictionary = {}; var new_bodies: Array = []
	for block in parser.data.blocks:
		if not V.exact(block, ["key", "packet"]) or not block.key is String or decoded.has(block.key): return {"ok": false, "error": "duplicate_snapshot_block"}
		var unpacked = V.unpack_json(block.packet, VERSION)
		if not unpacked.ok: return unpacked
		var native = _lower(unpacked.value)
		if not native.ok: return native
		decoded[block.key] = native.value
		if block.key.begins_with("part:"):
			if not native.value is Dictionary or not native.value.get("id") is int or block.key != "part:%d" % native.value.id: return {"ok": false, "error": "snapshot_part_identity"}
			new_parts[native.value.id] = native.value
		elif block.key.begins_with("body:"):
			if not native.value is Dictionary or not native.value.get("id") is int or block.key != "body:%d" % native.value.id: return {"ok": false, "error": "snapshot_body_identity"}
			new_bodies.append(native.value)
		elif not block.key in FIELDS: return {"ok": false, "error": "unknown_snapshot_field"}
	for key in FIELDS:
		if not decoded.has(key): return {"ok": false, "error": "missing_snapshot_field:" + key}
	var pirate = Actor.restore(decoded.pirate)
	if not pirate.ok: return pirate
	if not decoded.pilot_tick is int or decoded.pilot_tick != pirate.state.last_tick + 1: return {"ok": false, "error": "snapshot_clock_mismatch"}
	var seen: Dictionary = {}
	for body in new_bodies:
		if not _valid_body(body) or not body.get("parts") is Array: return {"ok": false, "error": "invalid_snapshot_body"}
		var linked: Array = []
		for id in body.parts:
			if not new_parts.has(id) or seen.has(id): return {"ok": false, "error": "snapshot_graph_reference"}
			var p: Dictionary = new_parts[id]
			if p.get("body_id") != body.id or not p.get("local_pos") is Vector2 or not p.local_pos.is_finite(): return {"ok": false, "error": "snapshot_part_body"}
			linked.append(p); seen[id] = true
		body.parts = linked
	if not _valid_body(decoded.pirate_body) or decoded.pirate_body.hp != pirate.state.hp \
		or decoded.pirate_body.mass != 6.0 or decoded.pirate_body.position != Vector2(pirate.state.x, pirate.state.y) \
		or decoded.pirate_body.velocity != Vector2(pirate.state.vx, pirate.state.vy): return {"ok": false, "error": "snapshot_pirate_body"}
	# Apply only after the entire graph and actor have been checked.
	for key in FIELDS: owner.set(key, decoded[key])
	owner.parts = new_parts; owner.bodies = new_bodies; owner._bodies_by_id = {}
	for body in new_bodies: owner._bodies_by_id[body.id] = body
	return {"ok": true}

static func _valid_body(body: Variant) -> bool:
	if not body is Dictionary: return false
	for key in ["position", "velocity"]:
		if not body.get(key) is Vector2 or not body[key].is_finite(): return false
	for key in ["angle", "angular_velocity", "mass", "inertia"]:
		if not typeof(body.get(key)) == TYPE_FLOAT or not is_finite(body[key]): return false
	return body.mass > 0.0 and body.inertia > 0.0

static func _lift(value: Variant) -> Variant:
	if value is StringName: return ["string_name", str(value)]
	if value is Vector2: return ["vector2", float(value.x), float(value.y)]
	if value is Dictionary:
		var pairs: Array = []
		for key in value: pairs.append([_lift(key), _lift(value[key])])
		return ["dictionary", pairs]
	if value is Array:
		var values: Array = []
		for child in value: values.append(_lift(child))
		return ["array", values]
	if typeof(value) == TYPE_FLOAT and is_inf(value): return ["infinity", 1 if value > 0.0 else -1]
	return ["value", value]

static func _lower(value: Variant) -> Dictionary:
	if not value is Array or value.is_empty() or not value[0] is String: return {"ok": false, "error": "invalid_native_tag"}
	if value[0] == "vector2":
		if value.size() != 3 or not V.real(value[1], -1.0e20, 1.0e20) or not V.real(value[2], -1.0e20, 1.0e20): return {"ok": false, "error": "invalid_native_vector"}
		return {"ok": true, "value": Vector2(value[1], value[2])}
	if value.size() != 2: return {"ok": false, "error": "invalid_native_shape"}
	if value[0] == "string_name":
		if not value[1] is String: return {"ok": false, "error": "invalid_native_string_name"}
		return {"ok": true, "value": StringName(value[1])}
	if value[0] == "value":
		if value[1] is Array or value[1] is Dictionary: return {"ok": false, "error": "invalid_native_scalar"}
		return {"ok": true, "value": value[1]}
	if value[0] == "infinity":
		if not value[1] in [-1, 1]: return {"ok": false, "error": "invalid_infinity"}
		return {"ok": true, "value": INF if value[1] == 1 else -INF}
	if not value[1] is Array: return {"ok": false, "error": "invalid_native_container"}
	if not value[0] in ["array", "dictionary"]: return {"ok": false, "error": "unknown_native_tag"}
	var array: Array = []; var dictionary: Dictionary = {}
	for item in value[1]:
		if value[0] == "array":
			var child = _lower(item)
			if not child.ok: return child
			array.append(child.value)
		elif value[0] == "dictionary":
			if not item is Array or item.size() != 2: return {"ok": false, "error": "invalid_native_pair"}
			var key = _lower(item[0]); var child = _lower(item[1])
			if not key.ok or not child.ok: return {"ok": false, "error": "invalid_native_pair"}
			if not (key.value is String or key.value is StringName or key.value is int) or dictionary.has(key.value): return {"ok": false, "error": "invalid_native_key"}
			dictionary[key.value] = child.value
		else: return {"ok": false, "error": "unknown_native_tag"}
	return {"ok": true, "value": array if value[0] == "array" else dictionary}
