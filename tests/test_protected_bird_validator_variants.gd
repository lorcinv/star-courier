extends SceneTree
const FixtureIO = preload("res://tests/fixtures/protected_bird_v1/fixture_io.gd")
## Raw Variant mutation testing, including container-valued identity fields.
## Every rejection must preserve all input bytes and emit zero engine diagnostics.
const ProfileV5 = preload("res://scripts/pilot_protected_bird_profile.gd")
const Facts = preload("res://scripts/protected_bird_facts_v1.gd")
const Replay = preload("res://scripts/protected_bird_replay_v1.gd")
const Design = preload("res://scripts/protected_bird_design_v1.gd")
var checks = 0
var failures = 0
var mutations = 0
var route: Dictionary = {}
var facts: Dictionary = {}
var registry: Dictionary = {}
var replay: Dictionary = {}

func _init() -> void:
	var golden_read = FixtureIO.read_json("res://tests/fixtures/protected_bird_v1/legacy_1_0/pre_validator_hardening/replay-harm.json")
	var report_read = FixtureIO.read_json("res://tests/fixtures/protected_bird_v1/legacy_1_0/pre_validator_hardening/route-harm.json")
	if not golden_read.ok or not report_read.ok:
		failures += 1; push_error("FIXTURE_GOLDEN_READ_FAILED " + str([golden_read, report_read]))
		quit(1); return
	var golden: Dictionary = golden_read.data
	var report: Dictionary = report_read.data
	route = golden.route.duplicate(true); facts = report.facts.duplicate(true)
	for p in golden.design:
		registry[int(p.id)] = {"owner_kind": "courier", "origin_part_id": int(p.id), "part_type": p.type}
	replay = Replay.snapshot(route, golden.design, golden.launcher, int(golden.seed), 0,
		[{"tick": 0, "axis_q": 0, "boost": false, "active": false}])
	var original_route = var_to_bytes(route); var original_facts = var_to_bytes(facts); var original_registry = var_to_bytes(registry)
	check(ProfileV5.validation_error(route).is_empty(), "Golden saved route remains valid")
	check(Facts.validation_error(facts, route, registry).is_empty(), "Golden real-harm result remains valid")
	check(var_to_bytes(route) == original_route and var_to_bytes(facts) == original_facts and var_to_bytes(registry) == original_registry, "Golden validation is byte-preserving")
	var native_route = ProfileV5.route({"weight": 1.0}, "D4-HARM", 42)
	check(ProfileV5.same_value(native_route, route), "Fresh author matches frozen golden route")
	check(ProfileV5.validation_error(native_route).is_empty(), "Native authored route validates before serialization")
	var native_before = var_to_bytes(native_route)
	var native_json: Dictionary = JSON.parse_string(JSON.stringify(native_route, "", true, true))
	check(ProfileV5.validation_error(native_json).is_empty() and ProfileV5.same_value(native_route, native_json), "Native author validates through exact JSON roundtrip")
	check(var_to_bytes(native_route) == native_before, "Native route bytes unchanged by validation and serialization")
	var named_keys: Dictionary = {}
	for key in native_route: named_keys[StringName(str(key))] = native_route[key]
	var names_before = var_to_bytes(named_keys)
	check(ProfileV5.validation_error(named_keys).is_empty() and var_to_bytes(named_keys) == names_before, "Native StringName keys validate without mutation")
	var commercial = ProfileV5.route({"id": 3, "rep": 7, "weight": 2.4, "reward": 340, "required": 90.0}, "D5-A", 670371318)
	commercial.battery_capacity_multiplier = 1.0
	check(ProfileV5.validation_error(commercial).is_empty(), "Actual commercial route validates before serialization")
	var restored = Replay.restore(replay)
	check(restored.ok and restored.simulator.paused, "Valid zero-tick replay remains supported")
	mutate_document("profile", route)
	mutate_document("facts", facts)
	mutate_document("registry", registry)
	mutate_document("replay", replay)
	for root in [null, true, 1, 0.5, "bad", [], Vector2.ZERO, PackedStringArray(["bad"])]:
		reject("profile", root, "root")
		reject("facts", root, "root")
		reject("registry", root, "root")
		reject("replay", root, "root")
	for key in ["mode", "background_route", "pilot_overdrive", "pilot_profile", "route_kind", "ecology_schema", "ecology_generator"]:
		var changed = route.duplicate(true); changed[key] = "other-protocol"
		reject("profile", changed, "wrong required identity " + key)
	for bad_key in [true, 123, Vector2.ZERO]:
		var changed = route.duplicate(true); changed[bad_key] = "bad"
		reject("profile", changed, "unrelated raw key type")
	for key in ["owner_kind", "origin_part_id", "part_type"]:
		var changed = registry.duplicate(true); changed[5].erase(key)
		reject("registry", changed, "missing registry entry field " + key)
	var wrong_registry = registry.duplicate(true); wrong_registry[5].origin_part_id = 99999
	reject("registry", wrong_registry, "missing lineage root")
	wrong_registry = registry.duplicate(true); wrong_registry[5] = []
	reject("registry", wrong_registry, "unchecked registry cast")
	wrong_registry = registry.duplicate(true); wrong_registry[99999] = {"owner_kind": "courier", "origin_part_id": 99998, "part_type": "armor"}
	reject("registry", wrong_registry, "unrelated malformed registry entry still rejected")
	var future = replay.duplicate(true); future.control_version = "pilot-v99"
	var before = var_to_bytes(future); var opaque = Replay.restore(future)
	check(not opaque.ok and opaque.state == "unsupported" and var_to_bytes(opaque.opaque) == before and var_to_bytes(future) == before, "Future string protocol preserved opaque and byte-identical")
	print("PROTECTED_BIRD_VALIDATOR_VARIANTS checks=%d mutations=%d failures=%d" % [checks, mutations, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func mutate_document(kind: String, original: Dictionary) -> void:
	var paths: Array = []
	collect_paths(original, [], paths)
	for path in paths:
		var value: Variant = at_path(original, path)
		for replacement in wrong_types(value):
			# The frozen vector reader intentionally accepts several finite forms
			# for route wind. Exercise malformed representations separately below.
			if (kind == "profile" and path == ["wind"]) or (kind == "replay" and path == ["route", "wind"]): continue
			var changed = original.duplicate(true)
			set_path(changed, path, replacement)
			reject(kind, changed, str(path))
	# Key omission and unknown fields must also be rejected at every Dictionary.
	for path in [[]] + paths:
		var value: Variant = at_path(original, path)
		if not value is Dictionary: continue
		for key in value.keys():
			# A registry may legitimately omit unrelated launch parts; provenance
			# tests below remove the required source/origin instead.
			if kind == "registry" and path.is_empty(): continue
			var changed = original.duplicate(true)
			var target: Dictionary = at_path(changed, path)
			target.erase(key)
			# Core route accepts omission of explicit optional commercial fields.
			if (kind == "profile" and path.is_empty() or kind == "replay" and path == ["route"]) and key in ["weight", "reward", "id", "rep", "required", "battery_capacity_multiplier"]: continue
			reject(kind, changed, str(path) + " missing " + str(key))
		var extra = original.duplicate(true)
		var target: Dictionary = at_path(extra, path)
		target["unexpected-field"] = true
		reject(kind, extra, str(path) + " extra key")
	if kind in ["profile", "replay"]:
		for wind in [null, true, false, "bad", [], [NAN, 0.0], [0.0, INF], {"x": []}, Vector2(INF, 0.0)]:
			var changed = original.duplicate(true)
			set_path(changed, ["wind"] if kind == "profile" else ["route", "wind"], wind)
			reject(kind, changed, "malformed wind")

func reject(kind: String, value: Variant, label: String) -> void:
	mutations += 1
	var before = var_to_bytes(value)
	var route_before = var_to_bytes(route); var facts_before = var_to_bytes(facts); var registry_before = var_to_bytes(registry)
	var rejected = false
	if kind == "profile": rejected = not ProfileV5.validation_error(value).is_empty()
	elif kind == "facts": rejected = not Facts.validation_error(value, route, registry).is_empty()
	elif kind == "registry": rejected = not Facts.validation_error(facts, route, value).is_empty()
	else: rejected = not Replay.restore(value).ok
	check(rejected, kind + " rejected " + label)
	check(var_to_bytes(value) == before and var_to_bytes(route) == route_before and var_to_bytes(facts) == facts_before and var_to_bytes(registry) == registry_before, kind + " input bytes preserved " + label)

func collect_paths(value: Variant, prefix: Array, result: Array) -> void:
	if value is Dictionary:
		for key in value:
			var path = prefix + [key]; result.append(path)
			collect_paths(value[key], path, result)
	elif value is Array:
		for index in range(value.size()):
			var path = prefix + [index]; result.append(path)
			collect_paths(value[index], path, result)

func at_path(root: Variant, path: Array) -> Variant:
	var value: Variant = root
	for key in path: value = value[key]
	return value

func set_path(root: Dictionary, path: Array, value: Variant) -> void:
	var target: Variant = root
	for i in range(path.size() - 1): target = target[path[i]]
	target[path.back()] = value

func wrong_types(value: Variant) -> Array:
	if value is String:
		return [null, true, false, 0, 1.5, [], {}, Vector2.ZERO, PackedStringArray(["bad"])]
	if value is bool:
		return [null, 0, 1, 1.5, "true", [], {}, Vector2.ZERO, PackedByteArray([1])]
	if value is int or value is float:
		return [null, true, false, "bad", [], {}, Vector2.ZERO, NAN, INF, -INF]
	if value is Dictionary:
		return [null, true, false, 0, 1.5, "bad", [], Vector2.ZERO, PackedStringArray(["bad"])]
	if value is Array:
		return [null, true, false, 0, 1.5, "bad", {}, Vector2.ZERO, PackedFloat32Array([0.0])]
	return [null, [], {}]
