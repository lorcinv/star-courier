extends RefCounted
## Additive registry for pilot-v3 only. Every legacy entry is returned unchanged.
const Legacy = preload("res://scripts/parts.gd")
const DRILL_POWER = 60.0
const DRILL_DAMAGE_RATE = 100.0
const DRILL_HEAD_OFFSET = 0.30
const DRILL_HEAD_RADIUS = 0.18

static func catalog() -> Dictionary:
	var result = Legacy.catalog()
	result.drill = {"name": "接触钻头", "category": "武器", "price": 65, "mass": 1.8, "energy": 0.0,
		"description": "消耗 60 J/s 驱动前端钻头，仅切割实际接触的可破坏障碍；每秒最多造成 100 HP 损伤。不能穿透实体关卡塔。", "model": "contact_drill"}
	return result

static func parameter_schema(kind: String) -> Dictionary:
	return Legacy.parameter_schema(kind)

static func defaults(kind: String) -> float:
	return Legacy.defaults(kind)

static func sanitize_parameter(kind: String, value: Variant) -> float:
	return Legacy.sanitize_parameter(kind, value)

static func controls(kind: String) -> Dictionary:
	if kind == "drill":
		return {"accepts_target": false, "inputs": 1, "default_behavior": "未接输入时自动运行；接线后由输入控制", "signal_rule": "供电与控制仅来自同一存活连接组件"}
	return Legacy.controls(kind)

static func cargo_spec() -> Dictionary:
	return Legacy.cargo_spec()

static func launcher_types() -> Array:
	return Legacy.launcher_types()
