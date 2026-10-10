extends SceneTree
## Regression guardrails for editor schemas, physical circuits, and replenishment.
const Sim = preload("res://scripts/simulation.gd")
const Parts = preload("res://scripts/parts.gd")
class WithoutIncidents extends "res://scripts/simulation.gd":
	func _record_damage_incident(_part: Dictionary, _amount: float, _source: String) -> void: pass

var failures: Array = []
var count = 0

func _initialize() -> void:
	_test_schemas()
	_test_destroyed_controls()
	_test_circuit_boundaries()
	_test_launcher_circuit_boundaries()
	_test_single_replacement_charge()
	_test_recovery_settlement()
	_test_energy_work()
	_test_station_charger()
	_test_damage_incidents()
	_test_incident_shields()
	_test_incidents_leave_physics_unchanged()
	if failures.is_empty():
		print("PASS: %d module invariant assertions" % count)
		quit(0)
	else:
		for failure in failures: printerr("FAIL: ", failure)
		printerr("%d/%d module invariant assertions failed" % [failures.size(), count])
		quit(1)

func _check(condition: bool, title: String) -> void:
	count += 1
	if not condition: failures.append(title)

func _close(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance

func _p(id: int, type: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var p = {"id": id, "type": type, "x": x, "y": y}
	p.merge(extra, true)
	return p

func _sim(design: Array, launcher: Array = [], route: Dictionary = {}) -> RefCounted:
	var config = {"distance": 1000.0, "time_limit": 90.0, "hazards": []}
	config.merge(route, true)
	var s = Sim.new()
	s.configure(design, launcher, config, 19)
	return s

func _advance(s, seconds: float) -> void:
	for _i in range(int(ceil(seconds * 120.0))): s.step(Sim.FIXED_DT)

func _kinetic(s) -> float:
	var result = 0.0
	for b in s.bodies:
		result += 0.5 * b.mass * b.velocity.length_squared() + 0.5 * b.inertia * b.angular_velocity * b.angular_velocity
	return result

func _test_schemas() -> void:
	for kind in Parts.catalog():
		var schema = Parts.parameter_schema(kind)
		var controls = Parts.controls(kind)
		var fields_valid = true
		for key in ["label", "unit", "min", "max", "step", "editable", "default", "value_type"]:
			fields_valid = fields_valid and schema.has(key)
		_check(fields_valid and schema.value_type == "float" and schema.step > 0.0 and schema.min <= schema.default and schema.default <= schema.max, kind + " has a complete bounded parameter schema")
		_check(controls.inputs >= 0 and controls.inputs <= 2 and controls.has("accepts_target") and controls.has("default_behavior") and controls.has("signal_rule"), kind + " has explicit control metadata")
		_check(_close(Parts.sanitize_parameter(kind, INF), schema.default) and _close(Parts.sanitize_parameter(kind, NAN), schema.default), kind + " rejects nonfinite parameters")
	_check(not Parts.parameter_schema("beam").editable and _close(Parts.sanitize_parameter("beam", 999999.0), 32.0), "beam strength is a fixed specification")
	_check(_close(Parts.sanitize_parameter("thruster", 999999.0), 40.0) and _close(Parts.sanitize_parameter("thruster", -12.0), 0.0), "thruster raw parameters are range-clamped")
	_check(_close(Parts.sanitize_parameter("delay", "5"), 0.5), "nonnumeric raw parameters use a safe default")
	var s = _sim([_p(1, "cargo", 0), _p(2, "beam", 1, 0, {"param": 999999.0}), _p(3, "battery", 2, 0, {"param": 1e12}), _p(4, "decoy", 3, 0, {"param": 1e12})])
	_check(_close(s.parts[2].strength, 32.0) and _close(s.parts[2].param, 32.0), "raw save cannot alter physical beam strength")
	_check(_close(s.parts[3].energy, 300.0) and _close(s.parts[3].capacity, 300.0) and _close(s.parts[4].param, 1.0), "fixed battery and decoy specifications reject save exploits")
	var raw = _sim([_p(1, "cargo", 0, 0, {"input_a": 2, "target": 2}), _p(2, "not_gate", 1, 0, {"input_b": 1}), _p(3, "unknown_part", 2)])
	_check(raw.parts[1].input_a == -1 and raw.parts[1].target == -1 and raw.parts[2].input_b == -1, "unsupported raw control ports are discarded")
	_check(raw.parts[3].type == "beam", "unknown saved module becomes safe catalog beam")
	var runtime = _sim([_p(1, "cargo", 0), _p(2, "battery", 1), _p(3, "thruster", 2)])
	runtime.parts[3].param = INF
	runtime.step(Sim.FIXED_DT)
	_check(_close(runtime.parts[3].param, 12.0) and is_finite(runtime.bodies[0].velocity.x), "runtime nonfinite controls are sanitized before actuation")

func _test_destroyed_controls() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "battery", 1), _p(3, "thruster", 2, 0, {"input_a": 4}), _p(4, "not_gate", 3)])
	s.step(Sim.FIXED_DT)
	_check(s.parts[4].signal and s._enabled(s.parts[3]), "connected live logic source enables actuator")
	s.parts[4].forced_signal = true
	s.parts[4].delay_queue = [{"time": 1.0, "value": true}]
	s._destroy(s.parts[4])
	_check(not s.parts[4].signal and not s.parts[4].active and not s.parts[4].forced_signal and s.parts[4].delay_queue.is_empty(), "destruction clears signal, actuation, trigger and queued output immediately")
	_check(not s._enabled(s.parts[4]) and not s._enabled(s.parts[3]), "destroyed source cannot remain enabled or power a downstream actuator")
	var used = s.telemetry.energy_used
	s.step(Sim.FIXED_DT)
	_check(_close(s.telemetry.energy_used, used) and not s.parts[3].active, "downstream actuator spends no energy after its source is destroyed")
	var d = _sim([_p(1, "cargo", 0), _p(2, "thruster", 1), _p(3, "battery", 2)])
	var body = d.body_for_part(2)
	d._destroy(d.parts[3])
	_check(_close(d._consume(body, 10.0, 2, Sim.FIXED_DT), 0.0), "destroyed battery cannot supply energy before the graph rebuild")
	var v = _sim([_p(1, "cargo", 0), _p(2, "thruster", 1), _p(3, "battery", 2), _p(4, "valve", 2, 1, {"target": 2, "param": 0.0})])
	body = v.body_for_part(2)
	v._destroy(v.parts[4])
	_check(_close(v._consume(body, 1.0, 2, Sim.FIXED_DT), 1.0), "destroyed valve no longer controls surviving actuators")

func _test_circuit_boundaries() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "battery", 1), _p(3, "thruster", 2, 0, {"input_a": 4}), _p(4, "not_gate", 3)])
	s.step(Sim.FIXED_DT)
	s._cut(3, 4)
	_check(not s._enabled(s.parts[3]), "wire disconnects immediately when its socket path is cut")
	s._rebuild_bodies()
	_check(s.parts[4].alive and s.parts[4].signal and not s._enabled(s.parts[3]), "living separated logic cannot behave like a radio controller")
	var p = _sim([_p(1, "cargo", 0), _p(2, "thruster", 1), _p(3, "coupler", 2), _p(4, "battery", 3)])
	var old_body = p.body_for_part(2)
	p._cut(3, 4)
	_check(not p._can_supply(old_body, 1.0, 2, Sim.FIXED_DT) and _close(p._consume(old_body, 1.0, 2, Sim.FIXED_DT), 0.0), "electricity disconnects before stale body membership can lend remote energy")
	_check(_close(p.parts[4].energy, 300.0), "isolated battery retains its energy")
	var same_tick = _sim([_p(1, "cargo", 0), _p(2, "coupler", 1, 0, {"target": 3}), _p(3, "not_gate", 2), _p(4, "thruster", -1, 0, {"input_a": 3}), _p(5, "battery", -2)])
	same_tick.trigger(2)
	same_tick.step(Sim.FIXED_DT)
	_check(same_tick.bodies.size() == 2 and not same_tick.parts[4].active and _close(same_tick.telemetry.energy_used, 0.0), "earlier cut disables later actuator within the same simulation tick")
	var gate = _sim([_p(1, "cargo", 0), _p(2, "or_gate", 1, 0, {"input_a": 3}), _p(3, "not_gate", 4)])
	_advance(gate, 0.05)
	_check(gate.parts[3].signal and not gate.parts[2].signal, "logic gates also reject separated inputs")

func _test_launcher_circuit_boundaries() -> void:
	var pad = [_p(10, "not_gate", 0), _p(11, "beam", 1), _p(12, "spring", 5, 0, {"input_a": 10, "param": 20.0}), _p(13, "battery", 4), _p(14, "beam", 6)]
	var s = _sim([_p(1, "cargo", 0)], pad)
	_check(s.launcher_parts[0].signal and _close(s.telemetry.launch_energy, 0.0) and _close(s.telemetry.energy_used, 0.0), "launcher actuators cannot read a separate component's logic")
	pad[2].input_a = -1
	pad.append(_p(15, "valve", 5, 1, {"input_a": 10, "target": 12, "param": 120.0}))
	var v = _sim([_p(1, "cargo", 0)], pad)
	_check(_close(v.telemetry.launch_energy, 0.0), "launcher valve cannot be opened by disconnected logic")

func _test_single_replacement_charge() -> void:
	var s = _sim([_p(1, "cargo", -1), _p(2, "battery", 0), _p(3, "accelerator", 1, 0, {"target": 4}), _p(4, "beam", 2)])
	s.step(Sim.FIXED_DT)
	_check(_close(s.telemetry.ammo_cost, 10.0), "noncargo accelerator ammunition is billed at its exact item price")
	s.parts[4].hp *= 0.5
	s._refresh_telemetry()
	_check(_close(s.telemetry.repair_cost, 0.0), "consumed ammunition is not simultaneously billed for repair")
	s._destroy(s.parts[4])
	s._destroy(s.parts[4])
	_check(_close(s.telemetry.ammo_cost, 10.0) and _close(s.telemetry.lost_cost, 0.0), "ammunition destruction cannot double-bill its replacement")
	var bomb = _sim([_p(1, "cargo", 0), _p(2, "bomb", 4, 0, {"param": 0.5})])
	bomb.trigger(2); bomb.step(Sim.FIXED_DT)
	_check(_close(bomb.telemetry.ammo_cost, 35.0) and _close(bomb.telemetry.lost_cost, 0.0), "consumed explosive is charged once as ammunition")
	var split = _sim([_p(1, "cargo", 0), _p(2, "splitter", 1, 0, {"target": 3}), _p(3, "battery", 2)])
	split.trigger(2); split.step(Sim.FIXED_DT)
	split._destroy(split.parts[3]); split._destroy(split.parts[4])
	_check(_close(split.telemetry.lost_cost, 45.0), "lost split halves sum to exactly one original item's value")

func _test_recovery_settlement() -> void:
	var pad = [_p(10, "beam", 0), _p(11, "battery", -1)]
	var s = _sim([_p(1, "cargo", 0), _p(2, "beam", -1), _p(3, "battery", 5), _p(4, "armor", 8)], pad, {"distance": 10.0})
	s.parts[2].hp *= 0.5
	s.parts[3].hp *= 0.5
	s.body_for_part(1).position += Vector2(10.01, 0.0) - s.cargo_position()
	s.body_for_part(4).position = Vector2(11.0, 0.0)
	s.step(Sim.FIXED_DT)
	_check(s.status == "success" and s.telemetry.settlement_finalized, "automatic completion finalizes recovery accounting")
	_check(s.parts[2].recovered and s.parts[2].delivered and s.body_for_part(2).is_empty(), "platform captures hardware attached to received cargo")
	_check(s.parts[4].recovered and s.parts[4].replacement_kind.is_empty(), "intact detached hardware in the receive zone can be recovered")
	_check(not s.parts[3].recovered and s.parts[3].replacement_kind == "lost" and _close(s.telemetry.lost_cost, 45.0), "surviving hardware abandoned outside the receive zone is billed for replacement")
	_check(_close(s.telemetry.repair_cost, 2.0), "repairs charge only surviving recovered hardware, not lost damaged units")
	_check(s.telemetry.recovered_count == 4 and s.telemetry.unrecovered_count == 1 and s.telemetry.replenished_count == 1, "recovery counts include intact launcher and exactly one replacement")
	var snapshot = s.telemetry.duplicate(true)
	s.finalize_settlement(); s.finalize_settlement()
	_check(s.telemetry == snapshot, "repeated settlement finalization never bills or counts twice")
	var aborted = _sim([_p(1, "cargo", 0), _p(2, "beam", 1)])
	aborted.finalize_settlement()
	_check(not aborted.telemetry.settlement_finalized and _close(aborted.telemetry.lost_cost, 0.0), "finalization cannot terminate or bill an ongoing flight")
	aborted.status = "failed"
	aborted.finalize_settlement()
	_check(aborted.telemetry.settlement_finalized and _close(aborted.telemetry.lost_cost, 45.0), "operator-aborted flight uses the same unrecovered replacement accounting")
	var timed_out = _sim([_p(1, "cargo", 0), _p(2, "beam", 1)], [], {"time_limit": 0.01})
	_advance(timed_out, 0.1)
	_check(timed_out.status == "failed" and _close(timed_out.telemetry.lost_cost, 45.0), "timeout also bills missing intact components")

func _test_energy_work() -> void:
	var low = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "thruster", -2, 0, {"param": 12.0})])
	var high = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "thruster", -2, 0, {"param": 40.0})])
	low.step(Sim.FIXED_DT); high.step(Sim.FIXED_DT)
	_check(high.telemetry.energy_used > low.telemetry.energy_used * 3.0, "larger thrust consumes proportionally more energy at launch")
	_advance(high, 6.0)
	_check(high.total_energy() >= -Sim.EPS and high.telemetry.energy_used <= 300.001, "maximum thrust cannot spend beyond finite stored battery energy")
	_check(_kinetic(high) <= high.telemetry.energy_used + 0.01, "thruster kinetic output cannot exceed consumed battery energy")
	var fast = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "thruster", -2, 0, {"param": 40.0})])
	fast.bodies[0].velocity = Vector2(30.0, 0.0)
	var before = _kinetic(fast)
	fast.step(Sim.FIXED_DT)
	_check(_kinetic(fast) - before <= fast.telemetry.energy_used + 0.01 and fast.telemetry.energy_used > 9.0, "high-speed thrust pays actual added kinetic work")
	var torque = _sim([_p(1, "cargo", 0), _p(2, "battery", -1), _p(3, "thruster", 0, 1, {"param": 40.0}), _p(4, "thruster", -1, 1, {"param": 40.0})])
	_advance(torque, 1.0)
	_check(_kinetic(torque) <= torque.telemetry.energy_used + 0.05, "multiple off-centre thrusters also pay their combined translational and rotational work")

func _test_station_charger() -> void:
	var pad = [_p(10, "beam", 0), _p(11, "battery", -1)]
	var s = _sim([_p(1, "cargo", 0), _p(2, "battery", -1)], pad, {"battery_capacity_multiplier": 1.3})
	_check(_close(s.parts[2].energy, 390.0) and _close(s.parts[2].capacity, 390.0), "station charger upgrade increases finite initial flight-cell capacity")
	_check(_close(s.launcher_parts[1].energy, 390.0) and _close(s.launcher_parts[1].capacity, 390.0), "station charger upgrade applies to the anchored launcher's cells")
	s.parts[2].energy = 12.0
	s.step(Sim.FIXED_DT)
	_check(_close(s.parts[2].energy, 12.0), "charger upgrade never replenishes energy during flight")
	var bounded = _sim([_p(1, "cargo", 0), _p(2, "battery", -1)], pad, {"battery_capacity_multiplier": 999.0})
	_check(_close(bounded.parts[2].capacity, 435.0) and _close(bounded.launcher_parts[1].capacity, 435.0), "charger upgrade is bounded to the three researched levels")
	var finite = _sim([_p(1, "cargo", 0), _p(2, "battery", -1)], [], {"battery_capacity_multiplier": INF})
	_check(_close(finite.parts[2].energy, 300.0), "nonfinite charger multiplier falls back to ordinary finite storage")
	pad.append(_p(12, "spring", 1, 0, {"param": 20.0}))
	var prepared = _sim([_p(1, "cargo", 0)], pad, {"battery_capacity_multiplier": 1.45})
	_check(_close(prepared.telemetry.energy_used, 20.0) and _close(prepared.launcher_parts[1].energy, 415.0), "research-enhanced launcher still pays every joule consumed")

func _test_damage_incidents() -> void:
	var design = [_p(1, "cargo", 0), _p(2, "beam", 1), _p(3, "armor", 2)]
	var s = _sim(design)
	s.elapsed = 1.25
	s._damage_part(s.parts[2], 12.5, "collision")
	_check(s.incidents.size() == 1 and s.incidents[0] == {"elapsed": 1.25, "id": 2, "type": "beam", "source": "collision", "amount": 12.5}, "incident captures exact first unabsorbed damage, module identity, source and simulation time")
	_check(_close(s.parts[2].hp, 32.5) and "#2" in str(s.events.back()) and "碰撞" in str(s.events.back()) and "1.2500s" in str(s.events.back()), "first-hit event identifies exact module and a precise timestamp without changing damage")
	var first = s.incidents[0].duplicate(true)
	var event_count = s.events.size()
	s.elapsed = 2.0
	s._damage_part(s.parts[2], 3.0, "collision")
	_check(s.incidents.size() == 1 and s.incidents[0] == first and s.events.size() == event_count, "repeated same-source damage cannot replace or spam the first incident")
	s._damage_part(s.parts[2], 4.0, "attack")
	_check(s.incidents.size() == 2 and s.incidents[1].source == "attack" and s.incidents[1].elapsed == 2.0, "different damage sources on one module each keep their first incident")
	s._damage_part(s.parts[3], 200.0, "collision")
	_check(s.incidents.size() == 3 and s.incidents[2].id == 3 and not s.parts[3].alive, "fatal hit is recorded before module destruction")
	s._damage_part(s.parts[3], 20.0, "attack")
	s._damage_part(s.parts[1], 0.0, "collision")
	s._damage_part(s.parts[1], -5.0, "collision")
	s.parts[1].delivered = true
	s._damage_part(s.parts[1], 20.0, "attack")
	_check(s.incidents.size() == 3, "dead, delivered, zero-damage and negative-damage calls produce no incident")
	s.configure(design, [], {"distance": 1000.0}, 19)
	_check(s.incidents.is_empty(), "configure clears incident history")
	s._damage_part(s.parts[2], 1.0, "collision")
	_check(s.incidents.size() == 1 and s.incidents[0].elapsed == 0.0 and s.incidents[0].amount == 1.0, "configure also resets incident deduplication keys")

func _test_incident_shields() -> void:
	var s = _sim([_p(1, "cargo", 0), _p(2, "shield", 1), _p(3, "battery", 2)])
	var event_count = s.events.size()
	s._damage_part(s.parts[1], 20.0, "attack")
	_check(s.incidents.is_empty() and s.events.size() == event_count and _close(s.parts[1].hp, 100.0) and _close(s.parts[3].energy, 270.0), "fully shielded hit consumes the same power but creates no false damage incident")
	s.parts[3].energy = 6.0
	s._damage_part(s.parts[1], 20.0, "attack")
	_check(s.incidents.size() == 1 and _close(s.incidents[0].amount, 16.0) and _close(s.parts[1].hp, 84.0), "partially shielded hit records only the actual unabsorbed HP damage")

func _test_incidents_leave_physics_unchanged() -> void:
	var design = [_p(1, "cargo", 0), _p(2, "armor", 1), _p(3, "battery", -1), _p(4, "thruster", -2)]
	var route = {"distance": 60.0, "time_limit": 40.0, "hazards": [{"x": 8.0, "y": 0.2, "radius": 0.8}]}
	var instrumented = Sim.new()
	var reference = WithoutIncidents.new()
	instrumented.configure(design, [], route, 19)
	reference.configure(design, [], route, 19)
	_advance(instrumented, 4.0); _advance(reference, 4.0)
	_check(not instrumented.incidents.is_empty() and reference.incidents.is_empty(), "differential fixture exercises actual collision incidents")
	var unchanged = instrumented.status == reference.status and instrumented.elapsed == reference.elapsed and instrumented.telemetry == reference.telemetry
	unchanged = unchanged and instrumented.cargo_position().is_equal_approx(reference.cargo_position()) and instrumented.total_momentum().is_equal_approx(reference.total_momentum())
	for id in instrumented.parts:
		unchanged = unchanged and instrumented.parts[id].hp == reference.parts[id].hp and instrumented.parts[id].alive == reference.parts[id].alive
	_check(unchanged, "incident recording leaves forces, outcomes, damage, momentum, energy and settlement telemetry identical")
