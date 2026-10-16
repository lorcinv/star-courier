extends RefCounted
## Test-only evidence IO. Runtime simulation and golden fixture bytes stay untouched.
const OUTPUT_ROOT = "user://protected_bird_v1/"
const GOLDEN_ROOT = "res://tests/fixtures/protected_bird_v1/"

static func failure(stage: String, path: String, code: int = FAILED) -> Dictionary:
	return {"ok": false, "error": "%s: %s (%s)" % [stage, path, error_string(code)], "stage": stage, "code": code}

static func allowed_path(path: String, writing: bool) -> bool:
	if ".." in path.split("/"): return false
	return path.begins_with(OUTPUT_ROOT) or (not writing and path.begins_with(GOLDEN_ROOT))

static func read_bytes(path: String) -> Dictionary:
	if not allowed_path(path, false): return failure("read_path", path, ERR_INVALID_PARAMETER)
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return failure("read_open", path, FileAccess.get_open_error())
	var length = file.get_length()
	var bytes = file.get_buffer(length)
	var code = file.get_error()
	file.close()
	if code != OK and code != ERR_FILE_EOF: return failure("read_bytes", path, code)
	if bytes.size() != length: return failure("short_read", path, ERR_FILE_CANT_READ)
	return {"ok": true, "bytes": bytes}

static func read_json(path: String) -> Dictionary:
	var loaded = read_bytes(path)
	if not loaded.ok: return loaded
	var parser = JSON.new()
	var code = parser.parse(loaded.bytes.get_string_from_utf8())
	if code != OK: return failure("parse_json", path, code)
	if not parser.data is Dictionary: return failure("json_root", path, ERR_INVALID_DATA)
	return {"ok": true, "data": parser.data}

static func write_json(path: String, value: Variant) -> Dictionary:
	return write_text(path, JSON.stringify(value, "\t", true, true))

static func write_text(path: String, content: String) -> Dictionary:
	if not allowed_path(path, true): return failure("write_path", path, ERR_INVALID_PARAMETER)
	var parent = ProjectSettings.globalize_path(path.get_base_dir())
	# A file in place of any parent directory is an expected testable failure.
	var ancestor = parent
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor): return failure("parent_is_file", path, ERR_CANT_CREATE)
		var next = ancestor.get_base_dir()
		if next == ancestor: break
		ancestor = next
	var code = DirAccess.make_dir_recursive_absolute(parent)
	if code != OK: return failure("create_parent", path, code)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return failure("target_is_directory", path, ERR_CANT_CREATE)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return failure("write_open", path, FileAccess.get_open_error())
	file.store_string(content)
	code = file.get_error()
	if code == OK:
		file.flush()
		code = file.get_error()
	file.close()
	if code != OK: return failure("write_flush", path, code)
	# Reopen only after close, then compare exact UTF-8 bytes rather than parsed JSON.
	var verified = read_bytes(path)
	if not verified.ok: return verified
	if verified.bytes != content.to_utf8_buffer(): return failure("write_readback", path, ERR_FILE_CORRUPT)
	return {"ok": true, "path": path, "bytes": verified.bytes.size()}
