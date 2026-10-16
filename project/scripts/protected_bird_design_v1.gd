extends RefCounted
## Validate the new replay protocol before inherited constructors normalize data.
const ProfileV5 = preload("res://scripts/pilot_protected_bird_profile.gd")
const Expanded = preload("res://scripts/parts_expanded.gd")
const KEYS = ["id", "type", "x", "y", "rot", "param", "input_a", "input_b", "target"]

static func validation_error(design: Variant, launcher: Variant) -> String:
	if not design is Array or design.is_empty() or design.size() > 192 or not launcher is Array or launcher.size() > 192: return "design_count"
	for index in range(2):
		var collection: Array = design if index == 0 else launcher
		var ids: Dictionary = {}
		for p in collection:
			if not p is Dictionary or not ProfileV5.exact_keys(p, KEYS): return "part_keys"
			if not p.type is String or (p.type != "cargo" and not Expanded.catalog().has(p.type)): return "unknown_part_type"
			if index == 1 and not p.type in Expanded.launcher_types(): return "launcher_part_type"
			if not ProfileV5._finite_integer(p.id) or float(p.id) < 0.0 or float(p.id) > 2147483647.0 or ids.has(int(p.id)): return "part_id"
			ids[int(p.id)] = true
			for key in ["x", "y", "rot", "input_a", "input_b", "target"]:
				if not ProfileV5._finite_integer(p[key]) or absf(float(p[key])) > 1000000.0: return "part_integer"
			if int(p.rot) < 0 or int(p.rot) > 3: return "part_rotation"
			if int(p.input_a) < -2 or int(p.input_b) < -2 or int(p.target) < -1: return "part_reference"
			var controls: Dictionary = Expanded.controls(p.type)
			if int(controls.inputs) < 1 and int(p.input_a) != -1: return "part_ignored_input"
			if int(controls.inputs) < 2 and int(p.input_b) != -1: return "part_ignored_input"
			if not controls.accepts_target and int(p.target) != -1: return "part_ignored_target"
			if not ProfileV5._finite_number(p.param) or float(p.param) != Expanded.sanitize_parameter(p.type, p.param): return "part_parameter_normalization"
	return ""
