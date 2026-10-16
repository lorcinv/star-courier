extends "res://scripts/pilot_pirate_structure_candidate_v1.gd"
## Unregistered finite-drill extension; reviewed structural owner stays intact.
const DRILL_CANDIDATE = "unregistered-pirate-drill-candidate-2"
const DrillClock = preload("res://scripts/pirate_drill_chronology_v1.gd")
const Exposure = preload("res://scripts/drill_exposure_intervals_v1.gd")
var chrono_drills: Dictionary = {}
var chrono_contact_plans: Dictionary = {}
var chrono_drill_damage_base = 0.0
var chrono_drill_loss_base = 0.0
var chrono_cut_fields: Dictionary = {}
var chrono_pending_obstacles: Array = []

func _chrono_supports_part(kind: Variant) -> bool:
	return kind == "drill" or super._chrono_supports_part(kind)

func configure_candidate(design: Array, launcher: Array, route_data: Dictionary, definition: Dictionary, random_seed: int = 1) -> Dictionary:
	chrono_contact_plans.clear(); chrono_drills.clear(); chrono_cut_fields.clear(); chrono_pending_obstacles.clear(); chrono_pair_plans.clear(); chrono_cut_dirty.clear()
	var result = super.configure_candidate(design, launcher, route_data, definition, random_seed)
	if result.ok: result.candidate = DRILL_CANDIDATE
	return result

func _tick(dt: float) -> void:
	_drill_clear_motion_anchors()
	chrono_contact_plans.clear(); chrono_drills.clear(); chrono_cut_fields.clear(); chrono_pending_obstacles.clear(); chrono_pair_plans.clear(); chrono_cut_dirty.clear()
	for p in parts.values():
		if p.type == "drill": p.drill_power_ratio = 0.0
	chrono_drill_damage_base = float(telemetry.get("drill_damage", 0.0))
	chrono_drill_loss_base = float(telemetry.get("drill_lost_seconds_bound", 0.0))
	super._tick(dt)

func _chrono_after_paid_action(p: Dictionary, _body: Dictionary, _dt: float, activation: Dictionary, consumed_j: float) -> void:
	if p.type != "drill": return
	var paid: Dictionary = _paid_drills[p.id]
	chrono_drills[int(p.id)] = {"source_id": int(p.id), "activation": activation, "reserved_j": consumed_j,
		"paid_ratio": float(paid.ratio), "paid_output": float(paid.output), "effective_output": float(paid.ratio) * float(paid.output),
		"paid_start_fraction": 0.0, "paid_end_fraction": 1.0, "live": true, "body_id": -1,
		"binding_parts": [], "binding_revision": 0, "target_index": -1,
		"motor_applied_j": 0.0, "contact_seconds": 0.0, "damage_hp": 0.0,
		"exposure_completed_seconds": 0.0, "exposure_completed_damage": 0.0, "exposure_anchor_fraction": 0.0, "exposure_rate": 0.0, "lost_seconds_bound": 0.0, "refund_j": 0.0, "additional_debit_j": 0.0}

func _run_chronology(dt: float) -> Dictionary:
	for r in chrono_reservations:
		r.paid_start_fraction = 0.0; r.paid_end_fraction = 1.0
	return DrillClock.run(self, dt)

func _refresh_telemetry() -> void:
	super._refresh_telemetry()
	telemetry.review_candidate = DRILL_CANDIDATE

const DRILL_POSE_KEYS = ["position", "velocity", "angle", "angular_velocity", "acceleration", "alpha"]
const DRILL_ANCHOR_KEYS = ["chrono_motion_anchor", "chrono_motion_offset", "chrono_motion_revision", "chrono_motion_start_fraction", "chrono_motion_sample_fraction", "chrono_motion_tick"]
var chrono_pair_plans: Dictionary = {}
var chrono_cut_dirty: Dictionary = {}

func _drill_clear_motion_anchors() -> void:
	var all: Array = bodies.duplicate()
	for index in _chrono_hazards.size():
		if obstacles[index].health > 0.0: all.append(_chrono_hazards[index])
	if not pirate_body.is_empty(): all.append(pirate_body)
	for body in all:
		for key in DRILL_ANCHOR_KEYS: body.erase(key)

func _drill_anchor(body: Dictionary) -> void:
	var anchor: Dictionary = {}
	for key in DRILL_POSE_KEYS: anchor[key] = body.get(key, Vector2.ZERO if key in ["position", "velocity", "acceleration"] else 0.0)
	body.chrono_motion_anchor = anchor
	body.chrono_motion_offset = 0.0
	body.chrono_motion_start_fraction = chrono_fraction
	body.chrono_motion_sample_fraction = chrono_fraction
	body.chrono_motion_tick = pilot_tick - 1
	body.chrono_motion_revision = int(body.get("chrono_motion_revision", 0)) + 1

func _drill_prepare_motion_anchors() -> void:
	var all: Array = bodies.duplicate(); all.append_array(_chrono_hazards); all.append(pirate_body)
	for body in all:
		if not body.has("chrono_motion_anchor") or body.chrono_motion_anchor.acceleration != body.get("acceleration", Vector2.ZERO) or body.chrono_motion_anchor.alpha != body.get("alpha", 0.0):
			_drill_anchor(body)

func _drill_curve_copy(body: Dictionary) -> Dictionary:
	var curve: Dictionary = {}
	for key in DRILL_POSE_KEYS: curve[key] = body.get(key, Vector2.ZERO if key in ["position", "velocity", "acceleration"] else 0.0)
	for key in DRILL_ANCHOR_KEYS:
		if body.has(key): curve[key] = body[key].duplicate(true) if body[key] is Dictionary else body[key]
	return curve

func _drill_advance_at(body: Dictionary, fraction: float) -> void:
	var offset: float = (fraction - body.chrono_motion_start_fraction) * _tick_dt
	var state = Motion.pose(body.chrono_motion_anchor, offset)
	for key in ["position", "velocity", "angle", "angular_velocity"]: body[key] = state[key]
	body.chrono_motion_offset = offset
	body.chrono_motion_sample_fraction = fraction

func _drill_entity_curve_key(entity: Dictionary) -> String:
	var identity: String = entity.kind + ":" + (_chrono_component_key(entity.body) if entity.kind == "courier" else str(entity.modules[0].id))
	return identity + ":" + str(entity.body.chrono_motion_revision) + ":" + str(entity.body.chrono_motion_start_fraction)

func _drill_curve_at(body: Dictionary, fraction: float) -> Dictionary:
	var copy = _drill_curve_copy(body)
	copy.chrono_motion_offset = (fraction - body.chrono_motion_start_fraction) * _tick_dt
	return copy

func _chrono_fields() -> void:
	super._chrono_fields()
	_drill_prepare_motion_anchors()
	for r in chrono_drills.values():
		if not r.live: continue
		var p: Dictionary = parts.get(r.source_id, {})
		if p.is_empty() or not p.alive or p.delivered or not _chrono_activation_connected(p, r.activation):
			r.live = false; _drill_select(r, -1, 0.0); continue
		var body = body_for_part(p.id)
		if body.is_empty(): r.live = false; _drill_select(r, -1, 0.0); continue
		var members = _chrono_component_ids(body)
		if members != r.binding_parts: r.binding_parts = members; r.binding_revision += 1
		r.body_id = body.id; r.effective_output = r.paid_ratio * minf(r.paid_output, p.output_factor)
		var selected = -1; var candidates: Array = []
		if chrono_fraction < r.paid_end_fraction and r.effective_output > 0.0:
			for index in obstacles.size():
				var h: Dictionary = obstacles[index]
				if h.health <= 0.0 or h.get("pilot_gate", false) or not h.get("destructible", true) or h.get("type", "rock") == "gravity": continue
				var plan = _drill_plan(p, body, index)
				if not plan.ok: chrono_error = plan.error; return
				if _drill_inside(plan.windows, chrono_fraction):
					var entered = 0.0
					for window in plan.windows:
						if window[0] <= chrono_fraction and chrono_fraction < window[1]: entered = window[0]; break
					candidates.append({"index": index, "entry": entered})
			candidates.sort_custom(func(a, b): return a.entry < b.entry or (a.entry == b.entry and a.index < b.index))
			for item in candidates:
				if item.index == r.target_index: selected = r.target_index; break
			if selected < 0 and not candidates.is_empty(): selected = candidates[0].index
		_drill_select(r, selected, Expanded.DRILL_DAMAGE_RATE * r.effective_output if selected >= 0 else 0.0)
	_drill_refresh_cut_fields()

func _drill_plan(p: Dictionary, body: Dictionary, index: int) -> Dictionary:
	var hazard: Dictionary = _chrono_hazards[index]
	var pair = "%d:%d" % [p.id, index]
	var signature = "%s:%d:%d" % [_chrono_component_key(body), body.chrono_motion_revision, hazard.chrono_motion_revision]
	var key = pair + ":" + signature
	if chrono_pair_plans.has(key): return chrono_pair_plans[key]
	for old in chrono_pair_plans.values():
		if old.pair == pair and old.valid_until > chrono_fraction: old.valid_until = chrono_fraction
	var plan = Exposure.plan(_drill_curve_copy(body), p.local_pos, p.local_angle, p.scale, _drill_curve_copy(hazard), obstacles[index].radius, (1.0 - chrono_fraction) * _tick_dt)
	if not plan.ok: return plan
	# Keep the original certificates and boundaries once per physical curve.
	# Event queries only select from them; they never rerun root refinement.
	for list in [plan.windows, plan.unknown]:
		for interval in list:
			interval[0] = chrono_fraction + interval[0] / _tick_dt
			interval[1] = 1.0 if interval[1] == (1.0 - chrono_fraction) * _tick_dt else chrono_fraction + interval[1] / _tick_dt
	plan.pair = pair; plan.source_id = int(p.id); plan.obstacle_index = index; plan.signature = signature
	plan.start_fraction = chrono_fraction; plan.valid_until = 1.0
	chrono_pair_plans[key] = plan
	return plan

func _drill_inside(windows: Array, fraction: float) -> bool:
	for interval in windows:
		if interval[0] <= fraction and fraction < interval[1]: return true
	return false

func _drill_select(r: Dictionary, target: int, rate: float) -> void:
	if not r.live:
		for plan in chrono_pair_plans.values():
			if plan.source_id == r.source_id and plan.valid_until > chrono_fraction: plan.valid_until = chrono_fraction
	if r.target_index == target and r.exposure_rate == rate: return
	r.exposure_completed_seconds = r.contact_seconds
	r.exposure_completed_damage = r.damage_hp
	r.exposure_anchor_fraction = chrono_fraction
	r.target_index = target; r.exposure_rate = rate
	if target >= 0: telemetry.drill_contacts = int(telemetry.get("drill_contacts", 0)) + 1

func _drill_refresh_cut_fields() -> void:
	var next: Dictionary = {}
	for index in obstacles.size():
		if obstacles[index].health <= 0.0: continue
		var sources: Array = []; var rate = 0.0
		for r in chrono_drills.values():
			if r.live and r.target_index == index and r.exposure_rate > 0.0:
				sources.append([r.source_id, r.binding_revision, r.exposure_rate]); rate += r.exposure_rate
		if sources.is_empty(): continue
		var signature = var_to_bytes(sources).hex_encode()
		var field: Dictionary = chrono_cut_fields.get(index, {})
		if field.is_empty() or field.signature != signature or chrono_cut_dirty.has(index):
			field = {"obstacle_index": index, "signature": signature, "sources": sources, "rate": rate,
				"anchor_hp": float(obstacles[index].health), "anchor_fraction": chrono_fraction}
		next[index] = field
	chrono_cut_fields = next; chrono_cut_dirty.clear()

func _drill_boundary() -> Dictionary:
	var first = 2.0; var deaths: Array = []
	for plan in chrono_pair_plans.values():
		if plan.valid_until <= chrono_fraction: continue
		for window in plan.windows:
			for at in window:
				if at > chrono_fraction and at <= plan.valid_until: first = minf(first, at)
	for field in chrono_cut_fields.values():
		var at: float = field.anchor_fraction + field.anchor_hp / (field.rate * _tick_dt)
		at = maxf(chrono_fraction, at)
		if at < first: first = at; deaths = [field.obstacle_index]
		elif at == first: deaths.append(field.obstacle_index)
	return {"fraction": first, "ids": deaths}

func _drill_apply(fraction: float, scheduled: Array) -> void:
	var damage = 0.0; var loss = 0.0
	for r in chrono_drills.values():
		if r.live:
			r.motor_applied_j = r.reserved_j * minf(fraction, r.paid_end_fraction)
			if r.target_index >= 0:
				var duration: float = (fraction - r.exposure_anchor_fraction) * _tick_dt
				r.contact_seconds = r.exposure_completed_seconds + duration
				r.damage_hp = r.exposure_completed_damage + duration * r.exposure_rate
		var gaps: Array = []
		for plan in chrono_pair_plans.values():
			if plan.source_id != r.source_id: continue
			for gap in plan.unknown:
				var end = minf(fraction, minf(plan.valid_until, gap[1]))
				if end > gap[0]: gaps.append([gap[0], end])
		r.lost_seconds_bound = 0.0
		for gap in Exposure._merge(gaps): r.lost_seconds_bound += (gap[1] - gap[0]) * _tick_dt
		damage += r.damage_hp; loss += r.lost_seconds_bound
	for field in chrono_cut_fields.values():
		var index: int = field.obstacle_index
		var hp: float = maxf(0.0, field.anchor_hp - field.rate * _tick_dt * (fraction - field.anchor_fraction))
		if scheduled.has(index): hp = 0.0
		obstacles[index].health = hp
		if hp == 0.0 and not chrono_pending_obstacles.has(index): chrono_pending_obstacles.append(index)
	telemetry.drill_damage = chrono_drill_damage_base + damage
	telemetry.drill_lost_seconds_bound = chrono_drill_loss_base + loss

func _drill_death_due() -> bool:
	return not chrono_pending_obstacles.is_empty()

func _drill_commit_deaths(ordinal: int) -> void:
	chrono_pending_obstacles.sort()
	for index in chrono_pending_obstacles:
		chrono_trace.append({"kind": "drill_obstacle_death", "tick": pilot_tick - 1, "fraction": chrono_fraction,
			"phase": 1, "ordinal": ordinal, "obstacle_index": index})
	chrono_pending_obstacles.clear()

func _chrono_entities() -> Array:
	var entities = super._chrono_entities()
	for index in chrono_pending_obstacles:
		var h: Dictionary = obstacles[index]
		entities.append({"key": "obstacle:%08d" % index, "kind": "obstacle", "body": _chrono_hazards[index], "fixed": true,
			"modules": [{"id": index, "lever": Vector2.ZERO, "radius": h.radius, "mass": h.mass}]})
	entities.sort_custom(func(a, b): return a.key < b.key)
	return entities

func _chrono_contact(event: Dictionary) -> void:
	super._chrono_contact(event)
	chrono_trace.back().contact_bracket_fraction = event.get("contact_bracket_fraction", [])
	for entity in [event.a, event.b]:
		if not entity.fixed: _drill_anchor(entity.body)
		if entity.kind == "obstacle":
			var index: int = entity.modules[0].id
			chrono_cut_dirty[index] = true
			if chrono_pending_obstacles.has(index): obstacles[index].health = 0.0

func _chrono_ray(ray: Dictionary, target: Dictionary, ordinal: int) -> void:
	super._chrono_ray(ray, target, ordinal)
	if not target.is_empty() and target.entity.kind == "obstacle": chrono_cut_dirty[int(target.module.id)] = true

const DrillSnapshot = preload("res://scripts/pirate_drill_snapshot_v1.gd")
func save_candidate_json() -> Dictionary:
	return DrillSnapshot.save(self, super.save_candidate_json())

func load_candidate_json(text: String) -> Dictionary:
	return DrillSnapshot.restore(self, text)
