extends RefCounted
## Canonical simulation/route/fact boundary only. No ledger, economy or UI writes.
const ProfileV5 = preload("res://scripts/pilot_protected_bird_profile.gd")
const Expanded = preload("res://scripts/parts_expanded.gd")
const REGISTRY_KEYS = ["owner_kind", "origin_part_id", "part_type"]
const SCHEMA = "protected-bird-harm-v1"
const RESULT_KEYS = ["schema", "control_version", "route_profile", "contract_id", "event_id", "entity_id", "physics_ticks", "harms"]
const HARM_KEYS = ["schema", "control_version", "contract_id", "event_id", "entity_id", "species_id", "harm_id", "physics_tick", "substep_fraction", "action_ordinal", "position", "source", "hp_before", "hp_after", "hp_delta"]
const SOURCE_KEYS = ["owner_kind", "part_id", "origin_part_id", "part_type", "action_kind"]
const ACTIONS = ["contact", "drill", "lance", "arc", "bomb"]

static func result(data: Dictionary, physics_ticks: int, first_harm: Dictionary) -> Dictionary:
	var event: Dictionary = data.ecology
	return {"schema": SCHEMA, "control_version": ProfileV5.CONTROL_VERSION,
		"route_profile": ProfileV5.ROUTE_PROFILE, "contract_id": data.contract_id,
		"event_id": event.event_id, "entity_id": event.entity_id,
		"physics_ticks": physics_ticks, "harms": [] if first_harm.is_empty() else [first_harm.duplicate(true)]}

static func classify(value: Variant) -> String:
	if not value is Dictionary: return "malformed"
	if not value.get("schema") is String or not value.get("control_version") is String: return "malformed"
	if not ProfileV5.same_value(value.schema, SCHEMA) or not ProfileV5.same_value(value.control_version, ProfileV5.CONTROL_VERSION): return "unsupported"
	return "known"

static func validation_error(value: Variant, data: Variant, registry: Variant) -> String:
	if classify(value) != "known": return "unsupported_or_malformed_wildlife_result"
	var route_error = ProfileV5.validation_error(data)
	if not route_error.is_empty(): return "invalid_route: " + route_error
	var registry_error = registry_validation_error(registry)
	if not registry_error.is_empty(): return registry_error
	if not ProfileV5.exact_keys(value, RESULT_KEYS): return "result_keys"
	var event: Dictionary = data.ecology
	for pair in [["route_profile", ProfileV5.ROUTE_PROFILE], ["contract_id", data.contract_id], ["event_id", event.event_id], ["entity_id", event.entity_id]]:
		if not ProfileV5.same_value(value.get(pair[0]), pair[1]): return "result_identity"
	if not _integer(value.physics_ticks, 0, 72000): return "result_tick"
	if not value.harms is Array or value.harms.size() > 1: return "harm_count"
	if value.harms.is_empty(): return ""
	var fact: Variant = value.harms[0]
	if not fact is Dictionary or not ProfileV5.exact_keys(fact, HARM_KEYS): return "harm_keys"
	for pair in [["schema", SCHEMA], ["control_version", ProfileV5.CONTROL_VERSION], ["contract_id", data.contract_id], ["event_id", event.event_id], ["entity_id", event.entity_id], ["species_id", ProfileV5.SPECIES_ID], ["harm_id", event.entity_id + "/first-harm"]]:
		if not ProfileV5.same_value(fact.get(pair[0]), pair[1]): return "harm_identity"
	if not _integer(fact.physics_tick, 1, int(value.physics_ticks)) or not _integer(fact.action_ordinal, 1, 2048): return "harm_order"
	if not _number(fact.substep_fraction, 0.0, 1.0): return "harm_fraction"
	if not fact.position is Array or fact.position.size() != 2: return "harm_position"
	for number in fact.position:
		if not _number(number, -1000000.0, 1000000.0): return "harm_position"
	for key in ["hp_before", "hp_after", "hp_delta"]:
		if not _number(fact[key], 0.0, 8.0): return "harm_hp"
	if float(fact.hp_delta) <= 0.0 or float(fact.hp_before) <= float(fact.hp_after): return "harm_no_loss"
	if absf(float(fact.hp_before) - float(fact.hp_after) - float(fact.hp_delta)) > 0.000000001: return "harm_delta"
	var source: Variant = fact.source
	if not source is Dictionary or not ProfileV5.exact_keys(source, SOURCE_KEYS): return "source_keys"
	if not ProfileV5.same_value(source.owner_kind, "courier") or not source.part_type is String or not source.action_kind is String or not source.action_kind in ACTIONS: return "source_kind"
	if not _integer(source.part_id, 0, 2147483647) or not _integer(source.origin_part_id, 0, 2147483647): return "source_id"
	if not registry.has(int(source.part_id)): return "source_unregistered"
	var registered: Dictionary = registry[int(source.part_id)]
	for key in ["owner_kind", "origin_part_id", "part_type"]:
		if not ProfileV5.same_value(source[key], registered.get(key)): return "source_lineage"
	if not registry.has(int(source.origin_part_id)): return "source_missing_origin"
	var origin: Dictionary = registry[int(source.origin_part_id)]
	if not ProfileV5.same_value(origin.owner_kind, "courier") or not ProfileV5.same_value(origin.origin_part_id, source.origin_part_id) or not ProfileV5.same_value(origin.part_type, source.part_type): return "source_bad_origin"
	if source.action_kind != "contact" and source.action_kind != source.part_type: return "source_action_type"
	return ""

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return ProfileV5._finite_integer(value) and float(value) >= minimum and float(value) <= maximum

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return ProfileV5._finite_number(value) and float(value) >= minimum and float(value) <= maximum

## Runtime registry is bounded and reconstructed from validated design/splits;
## no unchecked Variant-to-Dictionary casts or raw identity comparisons.
static func registry_validation_error(registry: Variant) -> String:
	if not registry is Dictionary or registry.is_empty() or registry.size() > 192: return "registry_container"
	for id in registry:
		if not id is int or not _integer(id, 0, 2147483647): return "registry_id"
		var entry: Variant = registry[id]
		if not entry is Dictionary or not ProfileV5.exact_keys(entry, REGISTRY_KEYS): return "registry_entry"
		if not ProfileV5.same_value(entry.owner_kind, "courier"): return "registry_owner"
		if not _integer(entry.origin_part_id, 0, 2147483647): return "registry_origin_id"
		if not entry.part_type is String or (entry.part_type != "cargo" and not Expanded.catalog().has(entry.part_type)): return "registry_part_type"
	for id in registry:
		var entry: Dictionary = registry[id]
		if not registry.has(int(entry.origin_part_id)): return "registry_missing_origin"
		var origin: Dictionary = registry[int(entry.origin_part_id)]
		if not ProfileV5.same_value(origin.origin_part_id, entry.origin_part_id) or not ProfileV5.same_value(origin.part_type, entry.part_type): return "registry_bad_origin"
	return ""
