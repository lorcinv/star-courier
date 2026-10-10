extends RefCounted
## Deterministic, fixed-step planar rigid-body sandbox. No route-specific success script.
## Stored grid coordinates build the socket graph once. After a cut, connected components
## become independent rigid bodies and retain their centre-of-mass momentum.
## Wired control and electricity require a living socket path: no radio or remote batteries.
## A terminal flight replenishes its blueprint: consumed/lost units are charged exactly once;
## only recovered surviving units incur repairs. The anchored launcher is recoverable.
const PartData = preload("res://scripts/parts.gd")
const FIXED_DT = 1.0 / 120.0
const EPS = 0.00001
const MAX_SIM_PARTS = 192
const MAX_EFFECTS = 192
var _split_limit_noted: bool = false
var bodies: Array = []
var _bodies_by_id: Dictionary = {}
var obstacles: Array = []
var launcher_parts: Array = []
var parts: Dictionary = {}
var links: Array = []
var status: String = "running"
var elapsed: float = 0.0
var events: Array = []
## First actual HP damage per module ID/source. Ordered; timestamps are exact simulation time.
var incidents: Array = []
var _incident_keys: Dictionary = {}
var effects: Array = []
var telemetry: Dictionary = {}
var route: Dictionary = {}
var seed_value: int = 0
var _rng = RandomNumberGenerator.new()
var _next_id: int = 1
var _body_id: int = 1
var _accumulator: float = 0.0
var _initial_value: float = 0.0
var _initial_cargo_hp: float = 100.0
var _initial_mass: float = 0.0
var _initial_cargo_count: int = 0
var _graph_dirty: bool = false
var _origin: Vector2 = Vector2.ZERO
var launcher_origin: Vector2 = Vector2.ZERO
var _settlement_finalized: bool = false

func configure(design: Array, launcher: Array, route_data: Dictionary, random_seed: int = 1) -> void:
	bodies.clear(); _bodies_by_id.clear(); obstacles.clear(); parts.clear(); links.clear(); events.clear(); effects.clear(); incidents.clear(); _incident_keys.clear(); _split_limit_noted = false
	route = route_data.duplicate(true)
	seed_value = random_seed
	_rng.seed = random_seed
	_next_id = 1; _body_id = 1; _accumulator = 0.0; elapsed = 0.0
	_initial_value = 0.0; _initial_cargo_hp = 0.0; _initial_mass = 0.0
	_graph_dirty = false; status = "running"; _settlement_finalized = false
	_initial_cargo_count = 0
	for raw in design:
		if raw.get("type", "") == "cargo": _initial_cargo_count += 1
	telemetry = {"energy_used": 0.0, "ammo_cost": 0.0, "repair_cost": 0.0, "lost_cost": 0.0, "integrity": 1.0, "delivered": false, "destroyed_mass": 0.0, "heat": 0.0, "launch_energy": 0.0, "delivered_count": 0, "cargo_count": _initial_cargo_count, "recovered_count": 0, "unrecovered_count": 0, "replenished_count": 0, "settlement_finalized": false, "replenishment_note": "自动按原蓝图补齐：耗用与遗失模块各计费一次，仅维修回收模块。"}
	for raw in design:
		var p = _new_part(raw)
		if p.type == "cargo": p.mass = 3.0 * maxf(0.1, float(route.get("weight", 1.0))) / maxi(1, _initial_cargo_count)
		if parts.has(p.id): p.id = _next_id
		_next_id = maxi(_next_id, int(p.id) + 1)
		parts[p.id] = p
		_initial_value += p.price
		_initial_mass += p.mass
		if p.type == "cargo": _initial_cargo_hp += p.hp
	var all = parts.values()
	for i in range(all.size()):
		for j in range(i + 1, all.size()):
			if absi(all[i].x - all[j].x) + absi(all[i].y - all[j].y) == 1:
				links.append({"a": all[i].id, "b": all[j].id, "strength": minf(all[i].strength, all[j].strength)})
	# Start around the assembled craft's centre of mass, so grid offset cannot cheat range.
	var centre = Vector2.ZERO
	for p in all: centre += Vector2(p.x, p.y) * p.mass
	if _initial_mass > EPS: centre /= _initial_mass
	for p in all: p.world_pos = Vector2(p.x, p.y) - centre
	_rebuild_bodies()
	for raw in route.get("hazards", []):
		var h: Dictionary = raw.duplicate(true)
		h.position = _vector(raw.get("position", Vector2(float(raw.get("x", 18.0)), float(raw.get("y", 0.0)))))
		var variation = float(route.get("variation", 0.0))
		if variation > 0.0: h.position += Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.25, 0.25)) * variation
		h.velocity = _vector(raw.get("velocity", Vector2.ZERO))
		h.mass = maxf(0.1, float(raw.get("mass", 20.0)))
		h.radius = float(raw.get("radius", 1.3))
		h.health = float(raw.get("health", 80.0))
		h.type = str(raw.get("type", "rock"))
		if h.type == "pirate": h.type = "tracker" if raw.get("tracking", false) else "turret"
		h.cooldown = float(raw.get("cooldown", 0.8 + _rng.randf() * 0.4))
		h.conductive = bool(raw.get("conductive", h.type != "gravity"))
		obstacles.append(h)
	_prepare_launcher(launcher)
	if _initial_cargo_hp <= 0.0:
		status = "failed"
		_log("没有货物，发射已取消。")
	else:
		_log("发射：%d 个模块，质量 %.1f kg。" % [parts.size(), total_mass()])
	if status != "running": _finalize_recovery()
	_refresh_telemetry()

func _new_part(raw: Dictionary) -> Dictionary:
	var kind = str(raw.get("type", "beam"))
	if kind != "cargo" and not PartData.catalog().has(kind): kind = "beam"
	var spec: Dictionary = PartData.cargo_spec() if kind == "cargo" else PartData.catalog().get(kind, PartData.catalog().beam)
	var hp = 150.0 if kind == "armor" else (100.0 if kind == "cargo" else 45.0)
	var controls = PartData.controls(kind)
	# Station charger research increases initial storage only, never mid-flight supply.
	var capacity_multiplier = float(route.get("battery_capacity_multiplier", 1.0))
	if not is_finite(capacity_multiplier): capacity_multiplier = 1.0
	capacity_multiplier = clampf(capacity_multiplier, 1.0, 1.45)
	var battery_capacity = float(spec.energy) * capacity_multiplier if kind == "battery" else 0.0
	return {"id": int(raw.get("id", _next_id)), "type": kind, "x": int(raw.get("x", 0)), "y": int(raw.get("y", 0)), "rot": int(raw.get("rot", 0)), "param": PartData.sanitize_parameter(kind, raw.get("param", PartData.defaults(kind))), "input_a": int(raw.get("input_a", -1)) if controls.inputs >= 1 else -1, "input_b": int(raw.get("input_b", -1)) if controls.inputs >= 2 else -1, "target": int(raw.get("target", -1)) if controls.accepts_target else -1, "mass": float(spec.mass), "price": float(spec.price), "hp": hp, "max_hp": hp, "energy": battery_capacity, "capacity": battery_capacity, "strength": PartData.BEAM_STRENGTH if kind == "beam" else 90.0, "scale": 1.0, "base_scale": 1.0, "local_pos": Vector2.ZERO, "local_angle": int(raw.get("rot", 0)) * PI / 2.0, "world_pos": Vector2.ZERO, "world_angle": int(raw.get("rot", 0)) * PI / 2.0, "world_velocity": Vector2.ZERO, "body_id": -1, "alive": true, "delivered": false, "recovered": false, "replacement_kind": "", "signal": false, "previous_signal": false, "active": false, "forced_signal": false, "spent": false, "output_factor": 1.0, "stored_energy": 0.0, "delay_queue": [], "delay_input": false, "contact": false, "next_contact": false, "distance": INF, "load": 0.0, "cooldown": 0.0}

func step(dt: float) -> void:
	if status != "running": return
	_accumulator += clampf(dt, 0.0, 0.5)
	while _accumulator + EPS >= FIXED_DT and status == "running":
		_accumulator -= FIXED_DT
		_tick(FIXED_DT)

func launch(impulse: Vector2) -> void:
	if bodies.is_empty() or impulse.length_squared() < EPS: return
	# A launch pad supplies this external impulse; detached bodies are not propelled twice.
	var b = _cargo_body()
	if b.is_empty(): b = bodies[0]
	var old_speed = b.velocity.length_squared()
	b.velocity += impulse / b.mass
	telemetry.launch_energy += maxf(0.0, 0.5 * b.mass * (b.velocity.length_squared() - old_speed))

func trigger(part_id: int) -> void:
	if parts.has(part_id) and parts[part_id].alive: parts[part_id].forced_signal = true

func total_mass() -> float:
	var value = 0.0
	for p in parts.values():
		if p.alive: value += p.mass
	return value

func total_energy() -> float:
	var value = 0.0
	for p in parts.values():
		if p.alive: value += p.energy + p.stored_energy
	return value

func total_momentum() -> Vector2:
	var value = Vector2.ZERO
	for b in bodies: value += b.velocity * b.mass
	return value

func cargo_position() -> Vector2:
	for p in parts.values():
		if p.type == "cargo" and p.alive and not p.delivered: return _part_position(p)
	for p in parts.values():
		if p.type == "cargo" and p.delivered: return p.world_pos
	return Vector2.ZERO

func ship_integrity() -> float:
	var hp = 0.0
	for p in parts.values():
		if p.type == "cargo" and p.alive: hp += maxf(p.hp, 0.0)
	return clampf(hp / maxf(1.0, _initial_cargo_hp), 0.0, 1.0)

func part_world_position(part_id: int) -> Vector2:
	return _part_position(parts[part_id]) if parts.has(part_id) else Vector2.ZERO

func body_for_part(part_id: int) -> Dictionary:
	if not parts.has(part_id): return {}
	return _body_by_id(int(parts[part_id].body_id))

func destination_clear(body: Dictionary, displacement: Vector2) -> bool:
	for p in body.parts:
		var at = _part_position(p) + displacement
		var radius = 0.43 * p.scale
		for h in obstacles:
			if h.health > 0.0 and h.type != "gravity" and at.distance_to(h.position) < radius + h.radius: return false
		for other in bodies:
			if other.id == body.id: continue
			for q in other.parts:
				if at.distance_to(_part_position(q)) < radius + 0.43 * q.scale: return false
	return true

func _tick(dt: float) -> void:
	if _graph_dirty: _rebuild_bodies()
	elapsed += dt
	for h in obstacles:
		if h.health > 0.0 and h.type != "gravity": h.position += h.get("velocity", Vector2.ZERO) * dt
	for e in effects: e.ttl -= dt
	effects = effects.filter(func(e): return e.ttl > 0.0)
	for p in parts.values():
		if p.alive:
			p.param = PartData.sanitize_parameter(p.type, p.param)
			p.contact = p.next_contact; p.next_contact = false
			p.previous_signal = p.signal
			p.cooldown = maxf(0.0, p.cooldown - dt)
	_update_signals(dt)
	_charge_springs(dt)
	for b in bodies:
		b.force = Vector2.ZERO; b.torque = 0.0
	# Iterate IDs so graph changes do not invalidate a body iterator.
	var action_ids = parts.keys()
	for id in action_ids:
		var p = parts[id]
		if not p.alive or p.delivered: continue
		var b = body_for_part(id)
		if b.is_empty(): continue
		var active = _enabled(p)
		p.active = active
		var rising = active and not p.get("was_active", false)
		p.was_active = active
		if active: _act(p, b, dt, rising)
		p.forced_signal = false
		if _graph_dirty: _rebuild_bodies()
	if _graph_dirty: _rebuild_bodies()
	for b in bodies:
		var accel = _vector(route.get("wind", Vector2.ZERO)) + Vector2(0.0, float(route.get("gravity", 0.0)))
		for h in obstacles:
			if h.type == "gravity" and h.health > 0.0:
				var delta: Vector2 = h.position - b.position
				accel += delta.normalized() * float(h.get("strength", 12.0)) / maxf(1.0, delta.length_squared() * 0.08)
		accel += b.get("force", Vector2.ZERO) / b.mass
		b.velocity += accel * dt
		b.angular_velocity += float(b.get("torque", 0.0)) / b.inertia * dt
		b.position += b.velocity * dt
		b.angle += b.angular_velocity * dt
		# Load is inertial stress through the load-bearing bridge, not hit points by name.
		for p in b.parts:
			p.load = b.get("force", Vector2.ZERO).length() * maxf(0.15, (b.mass - p.mass) / b.mass)
			if p.type == "beam" and p.load > p.strength:
				_damage_part(p, (p.load - p.strength) * dt * 6.0, "stress")
	_collisions()
	_enemy_attacks(dt)
	if _graph_dirty: _rebuild_bodies()
	_refresh_telemetry()
	_check_status()
	if status != "running":
		_finalize_recovery()
		_refresh_telemetry()

func _update_signals(_dt: float) -> void:
	var old: Dictionary = {}
	for p in parts.values(): old[p.id] = p.signal if p.alive and not p.delivered else false
	for p in parts.values():
		if not p.alive or p.delivered:
			_clear_control_state(p)
			continue
		var a = _read_wire(p, p.input_a, old)
		var b = _read_wire(p, p.input_b, old)
		match p.type:
			"probe":
				p.distance = _probe_distance(p)
				p.signal = p.distance <= maxf(0.0, p.param)
			"collision": p.signal = p.contact
			"and_gate": p.signal = a and b
			"or_gate": p.signal = a or b
			"not_gate": p.signal = not a
			"delay":
				if a != p.delay_input:
					p.delay_queue.append({"time": elapsed + maxf(0.0, p.param), "value": a})
					p.delay_input = a
				while not p.delay_queue.is_empty() and p.delay_queue[0].time <= elapsed + EPS:
					p.signal = p.delay_queue.pop_front().value
			_:
				p.signal = a if p.input_a >= 0 else false
		if p.forced_signal: p.signal = true

func _same_circuit(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return false
	if not a.alive or a.delivered or not b.alive or b.delivered: return false
	if a.body_id < 0 or b.body_id < 0 or a.body_id != b.body_id: return false
	# A cut invalidates socket paths immediately, before bodies are rebuilt.
	return _component(a.id).has(b.id) if _graph_dirty else true

func _read_wire(receiver: Dictionary, source_id: int, snapshot: Dictionary = {}) -> bool:
	if not parts.has(source_id) or not _same_circuit(receiver, parts[source_id]): return false
	return bool(snapshot.get(source_id, false)) if not snapshot.is_empty() else bool(parts[source_id].signal)

func _enabled(p: Dictionary) -> bool:
	if not p.alive or p.delivered: return false
	if p.forced_signal: return true
	if p.input_a >= 0: return _read_wire(p, p.input_a)
	return not p.type in ["coupler", "bomb", "teleporter", "splitter", "spring"]

func _clear_control_state(p: Dictionary) -> void:
	p.signal = false; p.previous_signal = false; p.active = false
	p.forced_signal = false; p.was_active = false
	p.contact = false; p.next_contact = false; p.delay_input = false
	p.delay_queue.clear()

func _act(p: Dictionary, b: Dictionary, dt: float, rising: bool) -> void:
	var direction = Vector2.RIGHT.rotated(b.angle + p.local_angle)
	var target = _target(p, b)
	match p.type:
		"thruster":
			var requested = maxf(0.0, p.param) * p.output_factor
			# Pay at least the kinetic work of this impulse, including off-centre torque.
			# Existing forces count so multiple thrusters cannot each ignore the others.
			var lever = p.local_pos.rotated(b.angle).cross(direction)
			var projected_speed = b.velocity.dot(direction) + b.angular_velocity * lever
			projected_speed += dt * (b.force.dot(direction) / b.mass + b.torque * lever / b.inertia)
			var impulse = requested * dt
			var work = impulse * projected_speed + 0.5 * impulse * impulse * (1.0 / b.mass + lever * lever / b.inertia)
			var ratio = _consume(b, maxf(requested * 1.5 * dt, work), p.id, dt)
			var force = direction * requested * ratio
			b.force += force
			b.torque += p.local_pos.rotated(b.angle).cross(force)
		"rotator":
			if not target.is_empty() and _linked(p.id, target.id):
				var ratio = _consume(b, 4.0 * absf(p.param) / 45.0 * dt, p.id, dt)
				target.local_angle += deg_to_rad(p.param) * ratio * dt
		"coupler":
			if rising and not target.is_empty(): _cut(p.id, target.id)
		"spring":
			if rising and not p.spent and not target.is_empty(): _release_spring(p, target)
		"damper": _damp(p, b, target, dt)
		"lance", "arc":
			var cost = (28.0 if p.type == "lance" else 24.0) * dt * p.output_factor
			var ratio = _consume(b, cost, p.id, dt)
			if ratio > EPS: _fire_ray(p, maxf(0.5, p.param), 35.0 * dt * ratio * p.output_factor, p.type == "arc")
		"accelerator":
			if rising and not p.spent and not target.is_empty(): _accelerate(p, target, b, dt)
		"bomb":
			if rising and not p.spent: _explode(p)
		"decoy": p.active = _consume(b, 2.0 * dt, p.id, dt) > 0.99
		"shrink", "enlarge":
			if not target.is_empty() and _linked(p.id, target.id):
				target.scale = (clampf(p.param, 0.2, 1.0) if p.type == "shrink" else clampf(p.param, 1.0, 3.0)) * target.base_scale
		"teleporter":
			if rising:
				var delta = direction * p.param
				if destination_clear(b, delta):
					if _can_supply(b, 25.0, p.id, dt):
						_consume(b, 25.0, p.id, dt)
						b.position += delta
						_log("位移器：完整落点净空，速度保持。")
						_effect("teleport", b.position, b.position - delta, 0.6)
				else: _log("位移失败：目标位置无法容纳整个组件。")
		"splitter":
			if rising and not target.is_empty(): _split_module(p, target, b, dt)

func _target(p: Dictionary, b: Dictionary) -> Dictionary:
	if parts.has(p.target) and parts[p.target].alive and not parts[p.target].delivered and p.target != p.id: return parts[p.target]
	for edge in links:
		var id = edge.b if edge.a == p.id else (edge.a if edge.b == p.id else -1)
		if id >= 0 and parts[id].alive: return parts[id]
	return {}

func _available_energy(b: Dictionary, consumer_id: int = -1) -> float:
	var n = 0.0
	for p in b.parts:
		if not p.alive or p.delivered: continue
		if consumer_id >= 0 and not _same_circuit(parts.get(consumer_id, {}), p): continue
		n += p.energy
	return n

func _consume(b: Dictionary, desired: float, consumer_id: int, dt: float, rate_limit: bool = true) -> float:
	if desired <= EPS: return 1.0
	var allowed = desired
	if rate_limit:
		for valve in b.parts:
			if valve.alive and not valve.delivered and _same_circuit(parts.get(consumer_id, {}), valve) and valve.type == "valve" and (valve.target == consumer_id or (valve.target < 0 and _linked(valve.id, consumer_id))):
				allowed = minf(allowed, maxf(0.0, valve.param) * dt if _enabled(valve) else 0.0)
	var remaining = minf(allowed, _available_energy(b, consumer_id))
	var used = remaining
	for p in b.parts:
		if not _same_circuit(parts.get(consumer_id, {}), p): continue
		var take = minf(p.energy, remaining)
		p.energy -= take; remaining -= take
		if remaining <= EPS: break
	telemetry.energy_used += used
	return used / desired

func _release_spring(p: Dictionary, target: Dictionary) -> void:
	if p.stored_energy <= EPS: return
	var direction = Vector2.RIGHT.rotated(body_for_part(p.id).angle + p.local_angle)
	_cut(p.id, target.id)
	_rebuild_bodies()
	var left = body_for_part(p.id)
	var right = body_for_part(target.id)
	if left.is_empty() or right.is_empty() or left.id == right.id:
		_log("弹簧仍被其他连接锁住，未释放储能。")
		return
	var reduced_mass = left.mass * right.mass / (left.mass + right.mass)
	var relative_speed = (right.velocity - left.velocity).dot(direction)
	var impulse = reduced_mass * (sqrt(relative_speed * relative_speed + 2.0 * p.stored_energy / reduced_mass) - relative_speed)
	left.velocity -= direction * impulse / left.mass
	right.velocity += direction * impulse / right.mass
	p.stored_energy = 0.0; p.spent = true
	_log("弹簧释放：两侧反向运动。")

func _accelerate(p: Dictionary, target: Dictionary, b: Dictionary, dt: float) -> void:
	if target.body_id != b.id or not _linked(p.id, target.id): return
	var cargo_mass = target.mass
	var carrier_mass = b.mass - cargo_mass
	if carrier_mass <= EPS: return
	var relative_speed = maxf(0.0, p.param)
	var reduced_mass = carrier_mass * cargo_mass / (carrier_mass + cargo_mass)
	var energy_need = 0.5 * reduced_mass * relative_speed * relative_speed
	if not _can_supply(b, energy_need, p.id, dt):
		_log("加速器能量不足，弹丸保留。")
		return
	_consume(b, energy_need, p.id, dt)
	var direction = Vector2.RIGHT.rotated(b.angle + p.local_angle)
	_detach(target.id)
	_rebuild_bodies()
	var carrier = body_for_part(p.id)
	var projectile = body_for_part(target.id)
	var impulse = reduced_mass * relative_speed
	carrier.velocity -= direction * impulse / carrier.mass
	projectile.velocity += direction * impulse / projectile.mass
	# Position the loaded object just clear of the muzzle; no replacement ammunition is spawned.
	projectile.position += direction * (0.05 + 0.43 * (p.scale + target.scale))
	p.spent = true
	if target.type != "cargo": _charge_replacement(target, "ammo")
	_log("质量加速器发射 %s，载体承受反冲。" % target.type)

func _damp(p: Dictionary, b: Dictionary, target: Dictionary, dt: float) -> void:
	var rate = maxf(0.0, p.param)
	if target.is_empty() or target.body_id == b.id:
		var before = 0.5 * b.inertia * b.angular_velocity * b.angular_velocity
		b.angular_velocity *= exp(-rate * dt)
		telemetry.heat += before - 0.5 * b.inertia * b.angular_velocity * b.angular_velocity
		return
	var other = body_for_part(target.id)
	if other.is_empty() or b.position.distance_to(other.position) > 5.0: return
	var relative: Vector2 = other.velocity - b.velocity
	var reduced = b.mass * other.mass / (b.mass + other.mass)
	var impulse = relative * reduced * (1.0 - exp(-rate * dt))
	var before = 0.5 * reduced * relative.length_squared()
	b.velocity += impulse / b.mass; other.velocity -= impulse / other.mass
	telemetry.heat += before - 0.5 * reduced * (other.velocity - b.velocity).length_squared()

func _split_module(p: Dictionary, target: Dictionary, b: Dictionary, dt: float) -> void:
	if parts.size() >= MAX_SIM_PARTS:
		if not _split_limit_noted: _log("已达到 192 个动态模块的安全上限，本次分裂未执行。")
		_split_limit_noted = true
		return
	if target.body_id != b.id or not _linked(p.id, target.id): return
	if target.type in ["cargo", "splitter"]:
		_log("分裂拒绝：货物与分裂器不能复制。")
		return
	if target.mass < 0.05 or not _can_supply(b, 10.0, p.id, dt): return
	_consume(b, 10.0, p.id, dt)
	var old_position = _part_position(target)
	var old_velocity = _part_velocity(target)
	var old_angle = body_for_part(target.id).angle + target.local_angle
	for key in ["mass", "energy", "capacity", "hp", "max_hp", "strength", "stored_energy", "price", "output_factor"]: target[key] *= 0.5
	target.base_scale *= sqrt(0.5); target.scale *= sqrt(0.5)
	var clone: Dictionary = target.duplicate(true)
	clone.id = _next_id; _next_id += 1
	clone.body_id = -1
	clone.world_pos = old_position + Vector2(0.0, 1.0).rotated(old_angle) * (0.9 * target.scale + 0.05)
	clone.world_velocity = old_velocity
	clone.world_angle = old_angle
	clone.local_pos = Vector2.ZERO
	clone.spent = true if clone.type in ["splitter", "accelerator", "spring", "bomb"] else clone.spent
	parts[clone.id] = clone
	_graph_dirty = true
	_rebuild_bodies()
	_log("模块分裂：质量、储能、强度与耐久均分，未复制货物。")

func _probe_distance(p: Dictionary) -> float:
	var b = body_for_part(p.id)
	if b.is_empty(): return INF
	var origin = _part_position(p)
	var direction = Vector2.RIGHT.rotated(b.angle + p.local_angle)
	var closest = INF
	for h in obstacles:
		if h.health <= 0.0 or h.type == "gravity": continue
		closest = minf(closest, _ray_circle(origin, direction, h.position, h.radius))
	for other in bodies:
		if other.id == b.id: continue
		for q in other.parts: closest = minf(closest, _ray_circle(origin, direction, _part_position(q), q.scale * 0.43))
	return closest

func _ray_circle(origin: Vector2, direction: Vector2, centre: Vector2, radius: float) -> float:
	var offset = centre - origin
	var along = offset.dot(direction)
	var perpendicular_sq = offset.length_squared() - along * along
	if perpendicular_sq > radius * radius or along + radius < 0.0: return INF
	return maxf(0.0, along - sqrt(maxf(0.0, radius * radius - perpendicular_sq)))

func _fire_ray(p: Dictionary, reach: float, damage: float, chain: bool) -> void:
	var b = body_for_part(p.id)
	var origin = _part_position(p)
	var direction = Vector2.RIGHT.rotated(b.angle + p.local_angle)
	var nearest = reach
	var hit: Dictionary = {}
	var hit_part: Dictionary = {}
	for h in obstacles:
		if h.health <= 0.0 or h.type == "gravity": continue
		var distance = _ray_circle(origin, direction, h.position, h.radius)
		if distance < nearest: nearest = distance; hit = h; hit_part = {}
	for other in bodies:
		if other.id == b.id: continue
		for q in other.parts:
			var distance = _ray_circle(origin, direction, _part_position(q), 0.43 * q.scale)
			if distance < nearest: nearest = distance; hit_part = q; hit = {}
	if not hit.is_empty():
		hit.health -= damage
		if chain and hit.conductive:
			for h in obstacles:
				if h != hit and h.conductive and h.position.distance_to(hit.position) <= h.radius + hit.radius + 2.0: h.health -= damage * 0.5
	if not hit_part.is_empty():
		_damage_part(hit_part, damage, "attack")
		if chain:
			# Electricity follows the socket graph, including any friendly module on it.
			var connected = _component(hit_part.id)
			for id in connected:
				if id != hit_part.id and parts[id].alive: _damage_part(parts[id], damage * 0.35, "attack")
	if p.cooldown <= 0.0:
		_effect("arc" if chain else "lance", origin, origin + direction * nearest, 0.12)
		p.cooldown = 0.09

func _explode(p: Dictionary) -> void:
	var centre = _part_position(p)
	var radius = maxf(0.5, p.param)
	var strength = 95.0 * p.output_factor
	p.spent = true
	_charge_replacement(p, "ammo")
	_destroy(p)
	for q in parts.values():
		if not q.alive: continue
		var delta = _part_position(q) - centre
		var distance = delta.length()
		if distance < radius:
			var fraction = 1.0 - distance / radius
			_damage_part(q, strength * fraction, "attack")
			var b = body_for_part(q.id)
			if not b.is_empty(): b.velocity += delta.normalized() * strength * fraction * 0.07 / b.mass
	for h in obstacles:
		var distance = h.position.distance_to(centre)
		if distance < radius + h.radius:
			var fraction = maxf(0.0, 1.0 - distance / (radius + h.radius))
			h.health -= strength * fraction
			if h.type != "gravity": h.velocity = h.get("velocity", Vector2.ZERO) + (h.position - centre).normalized() * strength * fraction * 0.07 / float(h.get("mass", 20.0))
	_effect("explosion", centre, Vector2(radius, 0.0), 0.8)
	_log("爆破核心引爆：冲击波同时影响友方与敌方。")

func _damage_part(p: Dictionary, amount: float, source: String) -> void:
	if not p.alive or p.delivered or amount <= 0.0: return
	var remaining = amount
	var b = body_for_part(p.id)
	if source == "attack" and not b.is_empty():
		for shield in b.parts:
			if shield.type == "shield" and shield.alive and _enabled(shield):
				var ratio = _consume(b, remaining * 1.5, shield.id, FIXED_DT)
				remaining *= 1.0 - ratio
				if remaining <= EPS: return
	if remaining > 0.0: _record_damage_incident(p, remaining, source)
	p.hp -= remaining
	if p.hp <= 0.0: _destroy(p)

func _record_damage_incident(p: Dictionary, amount: float, source: String) -> void:
	var key = "%d:%s" % [p.id, source]
	if _incident_keys.has(key): return
	_incident_keys[key] = true
	incidents.append({"elapsed": elapsed, "id": p.id, "type": p.type, "source": source, "amount": amount})
	var title = "货物" if p.type == "cargo" else str(PartData.catalog().get(p.type, {}).get("name", p.type))
	var cause = {"collision": "碰撞", "stress": "过载", "attack": "攻击"}.get(source, source)
	_log("首次受损：%s #%d · %s · %.2f HP。" % [title, p.id, cause, amount], true)

func _destroy(p: Dictionary) -> void:
	if not p.alive: return
	p.world_pos = _part_position(p); p.world_velocity = _part_velocity(p)
	p.alive = false
	_clear_control_state(p)
	telemetry.destroyed_mass += p.mass
	_charge_replacement(p, "lost")
	_detach(p.id)
	_graph_dirty = true
	_log("%s 损坏脱落。" % ("货物" if p.type == "cargo" else PartData.catalog().get(p.type, {}).get("name", p.type)))

func _collisions() -> void:
	for b in bodies:
		for p in b.parts:
			if not p.alive: continue
			for h in obstacles:
				if h.health <= 0.0 or h.type == "gravity": continue
				var delta = _part_position(p) - h.position
				var radius = 0.43 * p.scale + h.radius
				var distance = delta.length()
				if distance >= radius: continue
				var normal = delta / distance if distance > EPS else Vector2.LEFT
				var relative = _part_velocity(p).dot(normal)
				b.position += normal * (radius - distance + 0.002)
				_mark_contact(b)
				if relative < 0.0:
					var lever = p.local_pos.rotated(b.angle)
					var denominator = 1.0 / b.mass + pow(lever.cross(normal), 2.0) / b.inertia
					var impulse = -(1.12 * relative) / denominator
					b.velocity += normal * impulse / b.mass
					b.angular_velocity += lever.cross(normal * impulse) / b.inertia
					var damage = 0.5 * p.mass * relative * relative * 0.45
					_damage_part(p, damage, "collision")
					h.health -= damage * 0.6
	# Conservative circle broad phase: rotations cannot exceed this local-radius bound.
	for body in bodies:
		var bound: float = 0.0
		for module in body.parts:
			if module.alive: bound = maxf(bound, module.local_pos.length() + 0.43 * module.scale)
		body.collision_radius = bound + 0.001
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			var a = bodies[i]
			var b = bodies[j]
			if a.position.distance_squared_to(b.position) > pow(float(a.collision_radius) + float(b.collision_radius), 2.0): continue
			for p in a.parts:
				for q in b.parts:
					if not p.alive or not q.alive: continue
					var delta = _part_position(q) - _part_position(p)
					var radius = 0.43 * (p.scale + q.scale)
					var distance = delta.length()
					if distance >= radius: continue
					var normal = delta / distance if distance > EPS else Vector2.RIGHT
					var overlap = radius - distance + 0.001
					a.position -= normal * overlap * b.mass / (a.mass + b.mass)
					b.position += normal * overlap * a.mass / (a.mass + b.mass)
					_mark_contact(a); _mark_contact(b)
					var relative = (b.velocity - a.velocity).dot(normal)
					if relative < 0.0:
						var impulse = -relative * 1.1 / (1.0 / a.mass + 1.0 / b.mass)
						a.velocity -= normal * impulse / a.mass
						b.velocity += normal * impulse / b.mass
						_damage_part(p, absf(impulse * relative) * 0.12, "collision")
						_damage_part(q, absf(impulse * relative) * 0.12, "collision")

func _mark_contact(b: Dictionary) -> void:
	for p in b.parts:
		if p.type == "collision": p.next_contact = true

func _enemy_attacks(dt: float) -> void:
	for h in obstacles:
		if h.health <= 0.0: continue
		if h.type == "mine":
			if cargo_position().distance_to(h.position) < h.radius + 2.0:
				for p in parts.values():
					if p.alive:
						var d = _part_position(p).distance_to(h.position)
						if d < 5.0: _damage_part(p, 55.0 * (1.0 - d / 5.0), "attack")
				h.health = 0.0
				_effect("explosion", h.position, Vector2(5.0, 0.0), 0.6)
			continue
		if not h.type in ["turret", "tracker"]: continue
		h.cooldown -= dt
		if h.cooldown > 0.0: continue
		var target: Dictionary = {}
		for p in parts.values():
			if p.type == "cargo" and p.alive and not p.delivered: target = p; break
		if h.type == "tracker":
			var signal_strength = -INF
			for p in parts.values():
				if p.type == "decoy" and p.alive and p.active:
					var score = maxf(0.01, p.param) / maxf(1.0, _part_position(p).distance_squared_to(h.position))
					if score > signal_strength: target = p; signal_strength = score
		if target.is_empty() or _part_position(target).distance_to(h.position) > float(h.get("range", 18.0)): continue
		h.cooldown = float(h.get("fire_interval", 1.25))
		h.last_target_id = target.id
		var origin: Vector2 = h.position
		var end = _part_position(target)
		var direction = (end - origin).normalized()
		var distance = end.distance_to(origin)
		# Armour intercepts only when it is physically between the attacker and victim.
		for p in parts.values():
			if not p.alive: continue
			var hit_distance = _ray_circle(origin, direction, _part_position(p), 0.43 * p.scale)
			if hit_distance < distance: target = p; distance = hit_distance
		_damage_part(target, float(h.get("damage", 14.0)), "attack")
		_effect("enemy", origin, origin + direction * distance, 0.18)

func _linked(a: int, b: int) -> bool:
	for link in links:
		if (link.a == a and link.b == b) or (link.a == b and link.b == a): return true
	return false

func _cut(a: int, b: int) -> void:
	var before = links.size()
	links = links.filter(func(edge): return not ((edge.a == a and edge.b == b) or (edge.a == b and edge.b == a)))
	if links.size() != before:
		_graph_dirty = true
		_log("连接 %d ↔ %d 已断开。" % [a, b])

func _detach(id: int) -> void:
	links = links.filter(func(edge): return edge.a != id and edge.b != id)
	_graph_dirty = true

func _component(first: int) -> Array:
	var seen = [first]
	var queue = [first]
	while not queue.is_empty():
		var id = queue.pop_front()
		for edge in links:
			var next = edge.b if edge.a == id else (edge.a if edge.b == id else -1)
			if next >= 0 and parts[next].alive and not parts[next].delivered and not seen.has(next): seen.append(next); queue.append(next)
	return seen

func _rebuild_bodies() -> void:
	# Snapshot each point's exact world state before recomputing component COMs.
	for b in bodies:
		for p in b.parts:
			if p.alive and not p.delivered:
				p.world_pos = b.position + p.local_pos.rotated(b.angle)
				p.world_angle = b.angle + p.local_angle
				var r = p.local_pos.rotated(b.angle)
				p.world_velocity = b.velocity + Vector2(-r.y, r.x) * b.angular_velocity
				p.old_angular_velocity = b.angular_velocity
				p.old_force = b.get("force", Vector2.ZERO) * p.mass / b.mass
	var new_bodies: Array = []
	var assigned: Array = []
	for p in parts.values():
		if not p.alive or p.delivered or assigned.has(p.id): continue
		var ids = _component(p.id)
		assigned.append_array(ids)
		var mass = 0.0
		var centre = Vector2.ZERO
		var momentum = Vector2.ZERO
		var force = Vector2.ZERO
		var component_parts: Array = []
		for id in ids:
			var q = parts[id]
			mass += q.mass; centre += q.world_pos * q.mass; momentum += q.world_velocity * q.mass
			force += q.get("old_force", Vector2.ZERO)
			component_parts.append(q)
		centre /= maxf(mass, EPS)
		var velocity = momentum / maxf(mass, EPS)
		var inertia = 0.0
		var angular_momentum = 0.0
		for q in component_parts:
			var offset = q.world_pos - centre
			var own_inertia = q.mass / 6.0 # Ring size never changes the physical mass tensor.
			inertia += q.mass * offset.length_squared() + own_inertia
			angular_momentum += q.mass * offset.cross(q.world_velocity - velocity) + own_inertia * q.get("old_angular_velocity", 0.0)
		var b = {"id": _body_id, "position": centre, "velocity": velocity, "angle": 0.0, "angular_velocity": angular_momentum / maxf(EPS, inertia), "mass": mass, "inertia": maxf(EPS, inertia), "parts": component_parts, "force": force, "torque": 0.0}
		_body_id += 1
		for q in component_parts:
			q.local_pos = q.world_pos - centre
			q.local_angle = q.world_angle
			q.body_id = b.id
		new_bodies.append(b)
	bodies = new_bodies
	_bodies_by_id.clear()
	for body in bodies: _bodies_by_id[int(body.id)] = body
	_graph_dirty = false

func _body_by_id(id: int) -> Dictionary:
	return _bodies_by_id.get(id, {})

func _cargo_body() -> Dictionary:
	for p in parts.values():
		if p.type == "cargo" and p.alive and not p.delivered: return body_for_part(p.id)
	return {}

func _part_position(p: Dictionary) -> Vector2:
	var b = body_for_part(p.id)
	return b.position + p.local_pos.rotated(b.angle) if not b.is_empty() else p.world_pos

func _part_velocity(p: Dictionary) -> Vector2:
	var b = body_for_part(p.id)
	if b.is_empty(): return p.world_velocity
	var r = p.local_pos.rotated(b.angle)
	return b.velocity + Vector2(-r.y, r.x) * b.angular_velocity

func _refresh_telemetry() -> void:
	telemetry.integrity = ship_integrity()
	telemetry.repair_cost = 0.0
	telemetry.energy_remaining = _available_energy_all()
	telemetry.mass = total_mass()
	telemetry.body_count = bodies.size()
	telemetry.speed = _cargo_body().get("velocity", Vector2.ZERO).length()
	for p in parts.values():
		if p.alive and p.type != "cargo" and p.replacement_kind.is_empty() and (not _settlement_finalized or p.recovered):
			telemetry.repair_cost += p.price * (1.0 - clampf(p.hp / maxf(EPS, p.max_hp), 0.0, 1.0)) * 0.4
	for p in launcher_parts:
		if p.alive and p.replacement_kind.is_empty():
			telemetry.repair_cost += p.price * (1.0 - clampf(p.hp / maxf(EPS, p.max_hp), 0.0, 1.0)) * 0.4

func _available_energy_all() -> float:
	var n = 0.0
	for p in parts.values():
		if p.alive: n += p.energy
	return n

func _check_status() -> void:
	var destination = float(route.get("distance", 45.0))
	var y = float(route.get("destination_y", 0.0))
	var radius = float(route.get("delivery_radius", 8.0))
	var delivered = 0
	for p in parts.values():
		if p.type != "cargo": continue
		if not p.alive:
			status = "failed"; _log("部分货物损毁，委托失败。")
			return
		if p.delivered:
			delivered += 1
			continue
		var at = _part_position(p)
		if at.x >= destination and at.distance_to(Vector2(destination, y)) <= radius:
			if _part_velocity(p).length() <= float(route.get("max_delivery_speed", 45.0)):
				_recover_cargo_hardware(p)
				p.world_pos = at; p.world_velocity = Vector2.ZERO
				p.delivered = true; p.body_id = -1
				_detach(p.id)
				delivered += 1
				_log("货箱 %d 已由平台接收。" % p.id)
			else:
				status = "failed"; _log("抵达速度过高，收货平台拒收。")
				return
		elif absf(at.y) > float(route.get("boundary_y", 80.0)) or at.x < -35.0 or at.x > destination + 30.0:
			status = "failed"; _log("货物偏离收货区，委托失败。")
			return
	telemetry.delivered_count = delivered
	if delivered == _initial_cargo_count and delivered > 0:
		status = "success"; telemetry.delivered = true
		_log("全部货物自动投递成功：完整度 %d%%。" % int(ship_integrity() * 100.0))
	elif elapsed >= float(route.get("time_limit", 90.0)):
		status = "failed"; _log("货物未全部抵达，委托超时。")
	if _graph_dirty: _rebuild_bodies()

## Call before economy settlement, including when a UI sets status="failed" on abort.
## Repeated calls are safe; an ongoing flight is left untouched.
func finalize_settlement() -> Dictionary:
	if status != "running":
		_finalize_recovery()
		_refresh_telemetry()
	return telemetry

func _charge_replacement(p: Dictionary, category: String) -> void:
	if not p.replacement_kind.is_empty(): return
	p.replacement_kind = category
	telemetry["ammo_cost" if category == "ammo" else "lost_cost"] += p.price

func _in_recovery_zone(p: Dictionary) -> bool:
	var destination = float(route.get("distance", 45.0))
	var at = _part_position(p)
	return at.x >= destination and at.distance_to(Vector2(destination, float(route.get("destination_y", 0.0)))) <= float(route.get("delivery_radius", 8.0)) and _part_velocity(p).length() <= float(route.get("max_delivery_speed", 45.0))

func _recover_cargo_hardware(cargo: Dictionary) -> void:
	var b = body_for_part(cargo.id)
	if b.is_empty(): return
	# The receiving dock captures attached hardware before cargo leaves the socket graph.
	for p in b.parts:
		if not p.alive or p.delivered or p.type == "cargo": continue
		p.world_pos = _part_position(p); p.world_angle = b.angle + p.local_angle
		p.world_velocity = Vector2.ZERO
		p.recovered = true; p.delivered = true; p.body_id = -1
		_clear_control_state(p)
		_detach(p.id)

func _finalize_recovery() -> void:
	if _settlement_finalized: return
	if _graph_dirty: _rebuild_bodies()
	_settlement_finalized = true
	telemetry.settlement_finalized = true
	for p in parts.values():
		if p.alive and not p.delivered and _in_recovery_zone(p): p.recovered = true
		if p.alive and not p.delivered and not p.recovered:
			_charge_replacement(p, "lost")
			telemetry.unrecovered_count += 1
		if p.alive and p.recovered: telemetry.recovered_count += 1
		if not p.replacement_kind.is_empty(): telemetry.replenished_count += 1
	for p in launcher_parts:
		p.recovered = p.alive
		if p.alive: telemetry.recovered_count += 1
		elif p.replacement_kind.is_empty(): _charge_replacement(p, "lost")
		if not p.replacement_kind.is_empty(): telemetry.replenished_count += 1
	_log("自动整备：回收 %d 件，补齐 %d 件；耗用与遗失不重复计费。" % [telemetry.recovered_count, telemetry.replenished_count])

func _vector(value) -> Vector2:
	if value is Vector2: return value
	if value is Vector3: return Vector2(value.x, value.y)
	if value is Array and value.size() >= 2: return Vector2(value[0], value[1])
	if value is Dictionary: return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if value is int or value is float: return Vector2(float(value), 0.0)
	return Vector2.ZERO

func _log(message: String, precise_time: bool = false) -> void:
	events.append(("%08.4fs  %s" if precise_time else "%05.1fs  %s") % [elapsed, message])
	if events.size() > 100: events.pop_front()

func _effect(kind: String, start: Vector2, finish: Vector2, life: float) -> void:
	effects.append({"type": kind, "from": start, "to": finish, "ttl": life})
	if effects.size() > MAX_EFFECTS: effects.pop_front()

func _can_supply(b: Dictionary, desired: float, consumer_id: int, dt: float) -> bool:
	if _available_energy(b, consumer_id) + EPS < desired: return false
	for valve in b.parts:
		if valve.alive and not valve.delivered and _same_circuit(parts.get(consumer_id, {}), valve) and valve.type == "valve" and (valve.target == consumer_id or (valve.target < 0 and _linked(valve.id, consumer_id))):
			if not _enabled(valve) or maxf(0.0, valve.param) * dt + EPS < desired: return false
	return true

func _charge_springs(dt: float) -> void:
	for p in parts.values():
		if not p.alive or p.delivered or p.type != "spring" or p.spent: continue
		var desired = minf(maxf(0.0, p.param) - p.stored_energy, 30.0 * dt * p.output_factor)
		if desired <= EPS: continue
		var b = body_for_part(p.id)
		if not b.is_empty(): p.stored_energy += desired * _consume(b, desired, p.id, dt)

func _prepare_launcher(design: Array) -> void:
	launcher_parts.clear()
	var lookup: Dictionary = {}
	var edges: Array = []
	for raw in design:
		var p = _new_part(raw)
		launcher_parts.append(p); lookup[p.id] = p
	# The anchored pad is placed immediately behind the loaded craft, with real socket coordinates.
	var craft_left = INF
	for q in parts.values():
		if q.alive: craft_left = minf(craft_left, _part_position(q).x - 0.43 * q.scale)
	var pad_right = -INF
	for q in launcher_parts: pad_right = maxf(pad_right, float(q.x) + 0.43)
	launcher_origin = Vector2(craft_left - pad_right, 0.0) if is_finite(craft_left) and is_finite(pad_right) else Vector2.ZERO
	for q in launcher_parts: q.world_pos = Vector2(q.x, q.y) + launcher_origin
	for i in range(launcher_parts.size()):
		for j in range(i + 1, launcher_parts.size()):
			var a = launcher_parts[i]; var b = launcher_parts[j]
			if absi(a.x - b.x) + absi(a.y - b.y) == 1: edges.append([a.id, b.id])
	# Ground-anchored connected components share energy only through actual sockets.
	var visited: Array = []
	for root in launcher_parts:
		if visited.has(root.id): continue
		var component: Array = [root.id]
		var queue: Array = [root.id]
		while not queue.is_empty():
			var id = queue.pop_front()
			for edge in edges:
				var other = edge[1] if edge[0] == id else (edge[0] if edge[1] == id else -1)
				if other >= 0 and not component.has(other): component.append(other); queue.append(other)
		visited.append_array(component)
		var batteries: Array = []
		var has_support = false
		var support_strength = 0.0
		for id in component:
			var p = lookup[id]
			if p.type == "battery": batteries.append(p)
			if p.type == "beam": has_support = true; support_strength += maxf(0.0, p.strength)
		if not has_support:
			_log("发射台组件缺少结构梁支撑，不能施加发射力。")
			continue
		# Two seconds of explicit preparation resolve logic and transfer electricity to springs.
		for tick in range(120):
			var time = float(tick) / 60.0
			var old: Dictionary = {}
			for id in component: old[id] = lookup[id].signal
			for id in component:
				var p = lookup[id]
				var a = bool(old.get(p.input_a, false)); var b = bool(old.get(p.input_b, false))
				match p.type:
					"not_gate": p.signal = not a
					"and_gate": p.signal = a and b
					"or_gate": p.signal = a or b
					"delay":
						if a != p.delay_input:
							p.delay_queue.append({"time": time + maxf(0.0, p.param), "value": a}); p.delay_input = a
						while not p.delay_queue.is_empty() and p.delay_queue[0].time <= time + EPS: p.signal = p.delay_queue.pop_front().value
					"collision":
						p.signal = false
						for craft in parts.values():
							if craft.alive and p.world_pos.distance_to(_part_position(craft)) <= 0.43 * (p.scale + craft.scale) + EPS: p.signal = true
					"probe":
						p.distance = INF
						var ray = Vector2.RIGHT.rotated(p.local_angle)
						for craft in parts.values():
							if craft.alive: p.distance = minf(p.distance, _ray_circle(p.world_pos, ray, _part_position(craft), 0.43 * craft.scale))
						p.signal = p.distance <= maxf(0.0, p.param)
					_: p.signal = a if p.input_a >= 0 else true
			for id in component:
				var p = lookup[id]
				var enabled = (component.has(p.input_a) and bool(lookup[p.input_a].signal)) if p.input_a >= 0 else true
				if p.type == "rotator" and enabled and component.has(p.target):
					var desired_rotation = 4.0 * absf(p.param) / 45.0 / 60.0
					var used = _pad_draw(batteries, desired_rotation)
					lookup[p.target].local_angle += deg_to_rad(p.param) / 60.0 * used / maxf(EPS, desired_rotation)
				if not p.type in ["spring", "thruster", "accelerator"]: continue
				if not enabled: continue
				var desired = minf(maxf(0.0, p.param) - p.stored_energy, 30.0 / 60.0) if p.type == "spring" else (maxf(0.0, p.param) * 1.5 / 60.0)
				if desired <= 0.0: continue
				for vid in component:
					var valve = lookup[vid]
					if valve.type == "valve" and valve.target == p.id:
						var open = (component.has(valve.input_a) and bool(lookup[valve.input_a].signal)) if valve.input_a >= 0 else true
						desired = minf(desired, maxf(0.0, valve.param) / 60.0 if open else 0.0)
				p.stored_energy += _pad_draw(batteries, desired)
		var impulse = Vector2.ZERO
		var moving_mass = _cargo_body().get("mass", 0.0)
		var virtual_velocity = _cargo_body().get("velocity", Vector2.ZERO)
		for id in component:
			var p = lookup[id]
			if not p.type in ["spring", "thruster", "accelerator"] or p.stored_energy <= EPS: continue
			if p.input_a >= 0 and (not component.has(p.input_a) or not bool(lookup[p.input_a].signal)): continue
			var direction = Vector2.RIGHT.rotated(p.local_angle)
			var projected_speed = virtual_velocity.dot(direction)
			var magnitude = moving_mass * (sqrt(projected_speed * projected_speed + 2.0 * p.stored_energy / maxf(EPS, moving_mass)) - projected_speed)
			# The anchored supporting structure must withstand the 1-second release impulse.
			if magnitude > support_strength:
				p.hp = 0.0; p.alive = false
				_clear_control_state(p)
				_charge_replacement(p, "lost")
				_log("发射台过载：发射力超过结构梁承载。")
				continue
			impulse += direction * magnitude
			virtual_velocity += direction * magnitude / maxf(EPS, moving_mass)
			p.spent = true; p.stored_energy = 0.0
		if impulse.length() > EPS:
			launch(impulse)
			_log("发射台完成压缩供能，释放 %.1f N·s 冲量。" % impulse.length())

func _pad_draw(batteries: Array, desired: float) -> float:
	var left = maxf(0.0, desired)
	for battery in batteries:
		var take = minf(battery.energy, left)
		battery.energy -= take; left -= take
		if left <= EPS: break
	var used = desired - left
	telemetry.energy_used += used
	return used
