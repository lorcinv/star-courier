extends SceneTree
## Expected IO failures are returned as data. No suppressed engine diagnostics.
const FixtureIO = preload("res://tests/fixtures/protected_bird_v1/fixture_io.gd")
var checks = 0
var failures = 0

func _init() -> void:
	var root = "user://protected_bird_v1/io_failure/"
	var payload = {"fixture": "checked-write", "count": 3.5, "unicode": "保护鸟"}
	var nested = root + "created/parents/observation.json"
	var saved = FixtureIO.write_json(nested, payload)
	check(saved.ok, "Nested writable parent directories are created and output is closed")
	var loaded = FixtureIO.read_json(nested)
	check(loaded.ok and loaded.data == payload, "Successful evidence write is readable as exact JSON data")
	var content = JSON.stringify(payload, "\t", true, true).to_utf8_buffer()
	var bytes = FixtureIO.read_bytes(nested)
	check(bytes.ok and bytes.bytes == content, "Writer preserves exact UTF-8 JSON serialization")
	var blocker = root + "parent-file"
	check(FixtureIO.write_text(blocker, "KEEP EXACTLY").ok, "Failure fixture owns a harmless user-data blocking file")
	var failed = FixtureIO.write_json(blocker + "/child/observation.json", payload)
	check(not failed.ok and failed.stage == "parent_is_file", "Unwritable parent is a checked failure, never success")
	var preserved = FixtureIO.read_bytes(blocker)
	check(preserved.ok and preserved.bytes == "KEEP EXACTLY".to_utf8_buffer(), "Failed evidence write leaves blocking file unchanged")
	check(not FileAccess.file_exists(blocker + "/child/observation.json"), "Failed write cannot leave a fake successful observation")
	var directory_target = root + "created/parents"
	failed = FixtureIO.write_json(directory_target, payload)
	check(not failed.ok and failed.stage == "target_is_directory", "Directory target is rejected without null FileAccess dereference")
	failed = FixtureIO.write_json("res://tests/fixtures/protected_bird_v1/must-not-exist.json", payload)
	check(not failed.ok and failed.stage == "write_path", "Source resource writes are rejected before filesystem access")
	failed = FixtureIO.write_json(root + "../escaped.json", payload)
	check(not failed.ok and failed.stage == "write_path", "Traversal cannot escape the evidence namespace")
	var missing = FixtureIO.read_json(root + "missing.json")
	check(not missing.ok and missing.stage == "read_open", "Missing replay witness is a checked read failure")
	check(FixtureIO.write_text(root + "invalid.json", "not-json").ok, "Malformed JSON fixture is a checked user-data write")
	var invalid = FixtureIO.read_json(root + "invalid.json")
	check(not invalid.ok and invalid.stage == "parse_json", "Malformed replay witness is rejected before dictionary use")
	check(FixtureIO.write_text(root + "array.json", "[]").ok, "Wrong-root fixture is a checked user-data write")
	invalid = FixtureIO.read_json(root + "array.json")
	check(not invalid.ok and invalid.stage == "json_root", "Replay reader rejects non-dictionary JSON roots")
	print("PROTECTED_BIRD_FIXTURE_IO checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
