extends RefCounted
## Test-only transport. Numeric report JSON is human-readable evidence, never the
## bit-exact numeric replay authority. Original report bytes are hash-bound here.
const SCHEMA = "protected-bird-numeric-witness-v2"
const REVISION = "protected-bird-v5-ray-fix-v1"
const SIMULATOR_SHA256 = "9f6f304aa59e45c893622da22d4d4b1a9518774de10642e1c99565e6d63a0586"
const SWEEP_SHA256 = "c091012c078d26e77f756a1e13322184f767ec82eb5591d739d413fb44dece4f"
const KEYS = ["schema", "physics_revision", "simulator_sha256", "sweep_sha256", "report_sha256", "energy_binary64_le", "hp_binary64_le"]

static func bits(value: float) -> String:
	return PackedFloat64Array([value]).to_byte_array().hex_encode()

static func snapshot(energy: float, hp: float, report_bytes: PackedByteArray) -> Dictionary:
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(report_bytes)
	return {"schema": SCHEMA, "physics_revision": REVISION, "simulator_sha256": SIMULATOR_SHA256,
		"sweep_sha256": SWEEP_SHA256, "report_sha256": hash.finish().hex_encode(),
		"energy_binary64_le": bits(energy), "hp_binary64_le": bits(hp)}

static func valid_hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length: return false
	for code in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

static func matches(energy: float, hp: float, report_bytes: PackedByteArray, expected: Variant) -> bool:
	if not is_finite(energy) or not is_finite(hp) or not expected is Dictionary or expected.size() != KEYS.size(): return false
	for key in KEYS:
		if not expected.has(key) or not expected[key] is String: return false
	if not valid_hex(expected.energy_binary64_le, 16) or not valid_hex(expected.hp_binary64_le, 16): return false
	if not valid_hex(expected.report_sha256, 64): return false
	var actual = snapshot(energy, hp, report_bytes)
	for key in KEYS:
		if expected[key] != actual[key]: return false
	return true
