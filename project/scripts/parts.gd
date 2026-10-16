extends RefCounted
## All 25 workshop parts. Values use metres, kilograms, seconds and joules.
## Every part has four structural sockets. Logic wires are configurable routes,
## but both their endpoints must remain on the same living socket-connected body.
const BEAM_STRENGTH = 32.0

static func catalog() -> Dictionary:
	return {
		"battery": _part("高密度电芯", "动力", 45, 2.0, 300.0, "储存有限能量；断开的组件不能借用另一组件的电池。", "cell"),
		"valve": _part("功率阀", "动力", 25, 0.4, 0.0, "将目标模块的能量流率限制为参数 J/s；控制信号关闭时完全断电。", "power_valve"),
		"thruster": _part("推进喷口", "动力", 40, 1.2, 18.0, "沿箭头持续施力；偏离重心的推力产生转矩。推力越大、沿推力方向速度越高，耗电越多。", "thruster"),
		"spring": _part("蓄能弹簧", "机械", 30, 0.6, 0.0, "先用电能压缩至参数指定的弹性能量；释放时分开目标并给两侧等大反向冲量。", "spring"),
		"rotator": _part("角度转台", "机械", 35, 0.8, 4.0, "改变相邻目标模块的朝向；参数为每秒转角（度）。", "turntable"),
		"beam": _part("结构梁", "机械", 10, 0.5, 0.0, "固定承载 32 N 的轻量连接件；过载会断裂，断口分离为独立刚体。", "beam"),
		"coupler": _part("分离扣", "机械", 20, 0.4, 0.0, "上升沿触发后断开与目标的连接；没有替代连接时分成独立刚体。", "separator"),
		"damper": _part("缓冲器", "机械", 25, 0.7, 0.0, "将与目标的相对运动耗散为热；同体时抑制角速度，不会免费产生动能。", "damper"),
		"lance": _part("快子光矛", "武器", 60, 1.0, 28.0, "消耗电能，沿箭头损伤最近命中的目标；参数为射程。", "tachyon_lance"),
		"accelerator": _part("电磁加速器", "武器", 55, 1.5, 18.0, "把相邻目标当弹丸推出；也能发射货物，载体获得动量守恒的反冲。", "accelerator"),
		"arc": _part("电弧发射器", "武器", 60, 1.0, 24.0, "定向命中后，损伤沿导电连接传播；可伤及相连友方模块。", "arc_emitter"),
		"bomb": _part("爆破核", "武器", 35, 0.8, 0.0, "触发后消耗自身；冲击波无差别推开并损伤范围内敌我。参数为半径。", "explosive_core"),
		"armor": _part("装甲板", "防护", 25, 1.4, 0.0, "只保护装甲所在位置；吸收碰撞与攻击，耐久耗尽后破裂。", "armor"),
		"shield": _part("护盾发生器", "防护", 55, 0.8, 0.0, "用电能吸收所在组件遭受的攻击；不能吸收撞击伤害。", "shield"),
		"decoy": _part("诱饵信标", "防护", 20, 0.4, 2.0, "吸引信号追踪敌人；普通炮台和物理障碍不受影响。", "decoy"),
		"shrink": _part("缩小环", "空间", 55, 1.0, 0.0, "缩小目标视觉与碰撞尺寸；不改变质量、能量、承载或耐久。", "shrink_ring"),
		"enlarge": _part("放大环", "空间", 55, 1.0, 0.0, "放大目标视觉与碰撞尺寸；不增加质量、能量、承载或耐久。", "enlarge_ring"),
		"teleporter": _part("位移器", "空间", 80, 1.0, 25.0, "组件沿箭头瞬移参数米；检查整个组件落点，保留线速度和角速度。", "displacer"),
		"splitter": _part("分裂核", "空间", 70, 1.0, 10.0, "将目标模块分成两份，均分质量、能量、强度与耐久；货物不可复制。", "splitter"),
		"probe": _part("距离探头", "逻辑", 25, 0.3, 0.0, "测量箭头方向最近外部物体；距离持续处于参数范围内时输出真。", "distance_probe"),
		"collision": _part("碰撞开关", "逻辑", 15, 0.2, 0.0, "仅对外部接触输出一帧信号；忽略组件自身相邻模块。", "collision_switch"),
		"delay": _part("延时器", "逻辑", 15, 0.2, 0.0, "将输入的每次状态变化排队，参数秒后原样输出。", "delay"),
		"and_gate": _part("与门", "逻辑", 10, 0.2, 0.0, "两个输入都为真才输出真；未接输入按假处理。", "and_gate"),
		"or_gate": _part("或门", "逻辑", 10, 0.2, 0.0, "任意一个输入为真就输出真；未接输入按假处理。", "or_gate"),
		"not_gate": _part("非门", "逻辑", 10, 0.2, 0.0, "反转输入；未接输入按假处理，因此输出真。", "not_gate")
	}

static func cargo_spec() -> Dictionary:
	return _part("委托货物", "货物", 35, 3.0, 0.0, "完整交付目的地；不能被分裂复制。", "cargo_crate")

static func _part(title: String, category: String, price: int, mass: float, energy: float, description: String, model: String) -> Dictionary:
	return {"name": title, "category": category, "price": price, "mass": mass, "energy": energy, "description": description, "model": model}

## A single source of truth for editor controls AND runtime input validation.
## Fixed properties are displayed read-only; a saved raw param cannot change them.
static func parameter_schema(type: String) -> Dictionary:
	match type:
		"battery": return _schema("电池容量", "J", 300.0, 300.0, 1.0, false, 300.0)
		"valve": return _schema("供能上限", "J/s", 0.0, 120.0, 1.0, true, 18.0)
		"thruster": return _schema("目标推力", "N", 0.0, 40.0, 1.0, true, 12.0)
		"spring": return _schema("蓄能上限", "J", 0.0, 60.0, 1.0, true, 14.0)
		"rotator": return _schema("旋转速度", "°/s", -180.0, 180.0, 5.0, true, 45.0)
		"beam": return _schema("承载强度", "N", BEAM_STRENGTH, BEAM_STRENGTH, 1.0, false, BEAM_STRENGTH)
		"damper": return _schema("阻尼系数", "1/s", 0.0, 8.0, 0.1, true, 2.5)
		"lance": return _schema("最大射程", "m", 0.5, 20.0, 0.5, true, 12.0)
		"accelerator": return _schema("弹丸相对速度", "m/s", 0.0, 20.0, 0.5, true, 8.0)
		"arc": return _schema("最大射程", "m", 0.5, 12.0, 0.5, true, 8.0)
		"bomb": return _schema("爆破半径", "m", 0.5, 6.0, 0.5, true, 4.0)
		"armor": return _schema("装甲耐久", "HP", 150.0, 150.0, 1.0, false, 150.0)
		"shield": return _schema("吸收伤害耗能", "J/HP", 1.5, 1.5, 0.1, false, 1.5)
		"decoy": return _schema("信号强度", "倍", 1.0, 1.0, 0.1, false, 1.0)
		"shrink": return _schema("缩小倍率", "倍", 0.2, 1.0, 0.05, true, 0.55)
		"enlarge": return _schema("放大倍率", "倍", 1.0, 3.0, 0.05, true, 1.6)
		"teleporter": return _schema("位移距离", "m", 0.5, 16.0, 0.5, true, 8.0)
		"probe": return _schema("探测阈值", "m", 0.0, 20.0, 0.5, true, 8.0)
		"delay": return _schema("延时时长", "s", 0.0, 5.0, 0.1, true, 0.5)
		"cargo": return _schema("货物耐久", "HP", 100.0, 100.0, 1.0, false, 100.0)
		_: return _schema("无需参数", "", 0.0, 0.0, 1.0, false, 0.0)

static func _schema(label: String, unit: String, minimum: float, maximum: float, step: float, editable: bool, default_value: float) -> Dictionary:
	return {"label": label, "unit": unit, "min": minimum, "max": maximum, "step": step, "editable": editable, "default": default_value, "value_type": "float"}

static func controls(type: String) -> Dictionary:
	var target = type in ["valve", "spring", "rotator", "coupler", "damper", "accelerator", "shrink", "enlarge", "splitter"]
	var inputs = 2 if type in ["and_gate", "or_gate"] else (1 if type in ["valve", "thruster", "spring", "rotator", "coupler", "damper", "lance", "accelerator", "arc", "bomb", "shield", "decoy", "shrink", "enlarge", "teleporter", "splitter", "delay", "not_gate"] else 0)
	var behavior = "始终提供被动属性"
	if type in ["probe", "collision"]: behavior = "自动检测并输出信号"
	elif type in ["delay", "and_gate", "or_gate", "not_gate"]: behavior = "按输入计算信号；未连接输入为假"
	elif type in ["coupler", "bomb", "teleporter", "splitter", "spring"]: behavior = "等待输入上升沿或手动触发"
	elif inputs > 0: behavior = "未接输入时自动运行；接线后由输入控制"
	if type == "spring": behavior += "；自动充能"
	if type == "accelerator": behavior += "；每次装载仅发射一次"
	return {"accepts_target": target, "inputs": inputs, "default_behavior": behavior, "signal_rule": "有线信号和电力仅在同一存活连接组件内传递；断开后输入为假"}

static func sanitize_parameter(type: String, value: Variant) -> float:
	var schema = parameter_schema(type)
	if not schema.editable: return float(schema.default)
	if not (value is float or value is int): return float(schema.default)
	var number = float(value)
	if not is_finite(number): return float(schema.default)
	return clampf(number, float(schema.min), float(schema.max))

static func defaults(type: String) -> float:
	return float(parameter_schema(type).default)

static func launcher_types() -> Array:
	return ["battery", "valve", "thruster", "spring", "rotator", "beam", "accelerator", "probe", "collision", "delay", "and_gate", "or_gate", "not_gate"]
