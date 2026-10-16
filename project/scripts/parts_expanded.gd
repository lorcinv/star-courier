extends RefCounted
## Additive registry for pilot-v3 only. Every legacy entry is returned unchanged.
const Legacy = preload("res://scripts/parts.gd")
const HEATER_POWER = 40.0
const HEATER_PROTECTION = 0.8
const AIRBRAKE_DRAG_MULTIPLIER = 24.0
const SOLID_THRUST=28.0
const SOLID_BURN_SECONDS=12.0
const SOLID_DRY_MASS=0.8
const SOLID_FUEL_MASS=1.0
const SOLID_REFILL_COST=20.0
const DRILL_POWER = 60.0
const DRILL_DAMAGE_RATE = 100.0
const DRILL_HEAD_OFFSET = 0.30
const DRILL_HEAD_RADIUS = 0.18

static func catalog() -> Dictionary:
	var result = Legacy.catalog()
	result.drill = {"name": "接触钻头", "category": "武器", "price": 65, "mass": 1.8, "energy": 0.0,
		"description": "消耗 60 J/s 驱动前端钻头，仅切割实际接触的可破坏障碍；每秒最多造成 100 HP 损伤。不能穿透实体关卡塔。", "model": "contact_drill"}
	result.heater = {"name":"货舱保温模块", "category":"保护", "price":45, "mass":0.8, "energy":0.0, "description":"直接连接货物，冷区按40 J/s实际供电，最多减轻80%冷损；暖区不耗电，断电或分离失效，不防碰撞。", "model":"cargo_heater"}
	result.airbrake = {"name":"气动刹车板", "category":"飞行", "price":35, "mass":0.7, "energy":0.0, "description":"Q选择后按住空格展开，靠空气阻力减速，不耗推进电量；真空无效，偏心安装会扭转船体，过强减速可能伤货。", "model":"airbrake"}
	result.solid_booster={"name":"固体助推器","category":"飞行","price":60,"mass":1.8,"energy":0.0,"description":"Q选择/空格一次点火，沿装配箭头28N持续12秒，不能关停；燃料1kg烧尽后剩0.8kg壳，可分离。满罐补充20元按消耗结算，不耗电；偏心会旋转，不能矢量刹车。","model":"solid_booster"}
	return result

static func parameter_schema(kind: String) -> Dictionary:
	return Legacy.parameter_schema(kind)

static func defaults(kind: String) -> float:
	return Legacy.defaults(kind)

static func sanitize_parameter(kind: String, value: Variant) -> float:
	return Legacy.sanitize_parameter(kind, value)

static func controls(kind: String) -> Dictionary:
	if kind == "solid_booster":return {"accepts_target":false,"inputs":1,"default_behavior":"按键一次点火，燃烧不可停止","signal_rule":"Q选择/空格点火；方向固定，不参与WASD矢量控制"}
	if kind == "airbrake":return {"accepts_target":false,"inputs":1,"default_behavior":"驾驶装配默认按住展开；可改为自动","signal_rule":"Q选择，空格按住；真空无效果"}
	if kind == "heater":return {"accepts_target":false,"inputs":1,"default_behavior":"默认自动；仅冷区真实付电后保护","signal_rule":"须直接连接货物且供电，断开即失效"}
	if kind == "drill":
		return {"accepts_target": false, "inputs": 1, "default_behavior": "未接输入时自动运行；接线后由输入控制", "signal_rule": "供电与控制仅来自同一存活连接组件"}
	return Legacy.controls(kind)

static func cargo_spec() -> Dictionary:
	return Legacy.cargo_spec()

static func launcher_types() -> Array:
	return Legacy.launcher_types()
