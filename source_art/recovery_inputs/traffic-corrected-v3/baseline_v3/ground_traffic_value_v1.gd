extends RefCounted
## Strict value boundaries shared only by the isolated foundation.

const MAX_TICK := 10000000

static func bounded_json(value: Variant) -> bool:
	# One shared native-input guard, before any recursive duplicate or hash.
	# Cycles terminate at the depth boundary; no graph copying is attempted.
	return _bounded_json(value, 0, [0])

static func _bounded_json(value: Variant, depth: int, nodes: Array) -> bool:
	nodes[0] += 1
	if depth > 24 or nodes[0] > 4096:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_INT:
			return value >= -2147483648 and value <= 2147483647
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return value.length() <= 512
		TYPE_ARRAY:
			if value.is_typed() or value.size() > 256:
				return false
			for child in value:
				if not _bounded_json(child, depth + 1, nodes):
					return false
			return true
		TYPE_DICTIONARY:
			if value.is_typed() or value.size() > 64:
				return false
			for key in value:
				if typeof(key) != TYPE_STRING or key.length() > 64 or not _bounded_json(value[key], depth + 1, nodes):
					return false
			return true
	return false

static func exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for actual_key in value:
		if typeof(actual_key) != TYPE_STRING:
			return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func integer(value: Variant, lo: int, hi: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= lo and value <= hi and value == floor(value)

static func real(value: Variant, lo: float, hi: float) -> bool:
	# Realized physical scalars are binary64, never Vector2 or integer metadata.
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value >= lo and value <= hi

static func request_id(value: Variant) -> bool:
	return value is String and value.length() >= 1 and value.length() <= 48 and value.is_valid_identifier()

static func fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}

static func float_bits(value: float) -> String:
	return PackedFloat64Array([value]).to_byte_array().hex_encode()

static func typed_tree(value: Variant) -> Variant:
	return _typed_tree(value) if bounded_json(value) else null

static func _typed_tree(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var pairs: Array = []
		for key in keys:
			pairs.append([key, _typed_tree(value[key])])
		return ["dictionary", pairs]
	if value is Array:
		var items: Array = []
		for child in value:
			items.append(_typed_tree(child))
		return ["array", items]
	if typeof(value) == TYPE_FLOAT:
		return ["float64", float_bits(value)]
	return [type_string(typeof(value)), value]

static func typed_hash(value: Variant) -> String:
	var tree: Variant = typed_tree(value)
	return "" if tree == null else JSON.stringify(tree).sha256_text()

static func pack_json(value: Variant, kind: String) -> String:
	# Decimal JSON is not the exact-physics transport. The tags preserve type and
	# little-endian IEEE754 bits, including signed zero and adjacent doubles.
	var tree: Variant = typed_tree(value)
	return "" if tree == null else JSON.stringify({"format": "ground-traffic-binary64-json-v1", "kind": kind, "data": tree})

static func unpack_json(text: Variant, kind: String) -> Dictionary:
	if not text is String or text.to_utf8_buffer().size() > 65536:
		return fail("invalid_snapshot_json")
	var parser := JSON.new()
	if parser.parse(text) != OK or not exact(parser.data, ["format", "kind", "data"]) \
		or parser.data.format != "ground-traffic-binary64-json-v1" or parser.data.kind != kind:
		return fail("invalid_snapshot_json")
	return _decode_wire(parser.data.data, 0, [0])

static func _decode_wire(encoded: Variant, depth: int, budget: Array) -> Dictionary:
	budget[0] += 1
	if depth > 24 or budget[0] > 4096 or not encoded is Array or encoded.size() != 2 or not encoded[0] is String:
		return fail("invalid_typed_wire")
	var tag: String = encoded[0]
	var value: Variant = encoded[1]
	if tag == "Nil":
		return {"ok": true, "value": null} if value == null else fail("invalid_nil_wire")
	if tag == "bool":
		return {"ok": true, "value": value} if value is bool else fail("invalid_bool_wire")
	if tag == "int":
		return {"ok": true, "value": int(value)} if integer(value, -2147483648, 2147483647) else fail("invalid_int_wire")
	if tag == "String":
		return {"ok": true, "value": value} if value is String and value.length() <= 512 else fail("invalid_string_wire")
	if tag == "float64":
		if not value is String or value.length() != 16:
			return fail("invalid_float_wire")
		for character in value:
			if not character in "0123456789abcdef":
				return fail("invalid_float_wire")
		var decoded: float = value.hex_decode().decode_double(0)
		return {"ok": true, "value": decoded} if is_finite(decoded) else fail("nonfinite_float_wire")
	if not value is Array or value.size() > 256:
		return fail("invalid_container_wire")
	if tag == "array":
		var array: Array = []
		for child in value:
			var decoded := _decode_wire(child, depth + 1, budget)
			if not decoded.ok:
				return decoded
			array.append(decoded.value)
		return {"ok": true, "value": array}
	if tag == "dictionary":
		var dictionary: Dictionary = {}
		for pair in value:
			if not pair is Array or pair.size() != 2 or not pair[0] is String or pair[0].length() > 64 or dictionary.has(pair[0]):
				return fail("invalid_dictionary_wire")
			var decoded := _decode_wire(pair[1], depth + 1, budget)
			if not decoded.ok:
				return decoded
			dictionary[pair[0]] = decoded.value
		return {"ok": true, "value": dictionary}
	return fail("unknown_wire_tag")
