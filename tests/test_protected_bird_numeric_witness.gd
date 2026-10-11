extends SceneTree
const Numeric = preload("res://tests/fixtures/protected_bird_v1/numeric_witness_v2.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _init() -> void:
	var energy: float = "51ef1e40e650a740".hex_decode().decode_double(0)
	var next: float = "52ef1e40e650a740".hex_decode().decode_double(0)
	var next_hp: float = "0100000000000000".hex_decode().decode_double(0)
	var report = '{"energy_remaining":2984.4497079531798,"wildlife_hp":0.0}'.to_utf8_buffer()
	var expected = Numeric.snapshot(energy, 0.0, report)
	var unchanged = JSON.stringify(expected, "", true, true)
	var parsed: Dictionary = JSON.parse_string(unchanged)
	check(Numeric.bits(energy) == "51ef1e40e650a740", "Known native terminal energy is decoded losslessly")
	check(Numeric.bits(next) == "52ef1e40e650a740", "Next binary64 value differs by exactly one low bit")
	check(next != energy and next - energy == pow(2.0, -41.0), "The counterexample is exactly one ULP")
	check(Numeric.matches(energy, 0.0, report, expected), "Native witness accepts its exact generating state")
	check(expected == parsed, "String-encoded numeric witness survives JSON unchanged")
	check(Numeric.matches(energy, 0.0, report, parsed), "Parsed exact witness accepts matching native state")
	check(not Numeric.matches(next, 0.0, report, expected), "A genuine one-ULP replay energy mismatch is rejected")
	check(not Numeric.matches(energy, next_hp, report, expected), "A genuine one-ULP HP mismatch is rejected")
	check(not Numeric.matches(energy, 0.0, report + " ".to_utf8_buffer(), expected), "One changed report byte is rejected")
	for key in ["report_sha256", "simulator_sha256", "sweep_sha256", "physics_revision", "schema"]:
		var bad = expected.duplicate(true); bad[key] = str(bad[key]) + "0"
		check(not Numeric.matches(energy, 0.0, report, bad), "Tampered witness identity/hash is rejected: " + key)
	var missing = expected.duplicate(true); missing.erase("hp_binary64_le")
	check(not Numeric.matches(energy, 0.0, report, missing), "Missing witness field is rejected")
	var extra = expected.duplicate(true); extra.override = true
	check(not Numeric.matches(energy, 0.0, report, extra), "Unknown witness field is rejected")
	var wrong_type = expected.duplicate(true); wrong_type.energy_binary64_le = energy
	check(not Numeric.matches(energy, 0.0, report, wrong_type), "Numeric field cannot replace lossless string encoding")
	var uppercase = expected.duplicate(true); uppercase.energy_binary64_le = expected.energy_binary64_le.to_upper()
	check(not Numeric.matches(energy, 0.0, report, uppercase), "Noncanonical uppercase encoding is rejected")
	var nonhex = expected.duplicate(true); nonhex.energy_binary64_le = "51ef1e40e650a74z"
	check(not Numeric.matches(energy, 0.0, report, nonhex), "Invalid hex is rejected")
	check(not Numeric.matches(INF, 0.0, report, expected), "Nonfinite energy is rejected")
	check(not Numeric.matches(energy, NAN, report, expected), "Nonfinite HP is rejected")
	var decimal: Dictionary = JSON.parse_string(report.get_string_from_utf8())
	check(Numeric.bits(decimal.energy_remaining) == "52ef1e40e650a740", "Pinned Godot4.6.3 decimal-parser counterexample is retained")
	check(not Numeric.matches(decimal.energy_remaining, 0.0, report, expected), "Parsed decimal cannot substitute for exact replay authority")
	check(JSON.stringify(expected, "", true, true) == unchanged, "Negative validation never mutates witness")
	check(not Numeric.matches(energy, 0.0, report, []), "Nonobject witness is rejected")
	print("PROTECTED_BIRD_NUMERIC_WITNESS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
