extends RefCounted
## Finite intent planning, not a collision solver. All positions use scalar doubles.
const V = preload("ground_traffic_value_v1.gd")
const Bundle = preload("ground_traffic_bundle_v1.gd")
const Warning = preload("ground_patrol_warning_v1.gd")
const DT := 1.0 / 120.0
const SNAPSHOT_VERSION := "ground-traffic-candidate-v3-snapshot-1"
const STATE_KEYS := ["helper", "snapshot_version", "bundle", "last_tick", "actors", "warning", "charges"]
const ACTOR_KEYS := ["id", "source_id", "role", "x", "y", "vx", "vy", "mass_kg", "radius_m", "hp", "fuel_mj", "spent_mj", "anchor_tick", "anchor_fraction", "revision", "last_commit"]
const COMMIT_KEYS := ["actor_id", "tick", "fraction", "revision", "x", "y", "vx", "vy", "hp"]

static func configure(saved_bundle: Variant) -> Dictionary:
	var restored := Bundle.restore(saved_bundle)
	if not restored.ok:
		return V.fail(restored.error)
	var b: Dictionary = restored.bundle
	var actors: Array = b.actors.duplicate(true)
	for a in actors:
		a["spent_mj"] = 0
		a["anchor_tick"] = 0
		a["anchor_fraction"] = 0.0
		a["revision"] = 0
		a["last_commit"] = null
	return {"ok": true, "state": {"helper": Bundle.VERSION, "snapshot_version": SNAPSHOT_VERSION, "bundle": b,
		"last_tick": -1, "actors": actors, "warning": null, "charges": []}}

static func advance(saved_state: Variant, tick: Variant, step_enabled: Variant, command: Variant = null) -> Dictionary:
	var restored := restore_snapshot(saved_state)
	if not restored.ok:
		return restored
	if not V.integer(tick, 0, V.MAX_TICK) or not step_enabled is bool:
		return V.fail("invalid_tick_or_enable_type")
	var s: Dictionary = restored.state
	# Inert means no command inspection, clock movement, charge, or repeated intent.
	if not step_enabled or int(tick) == s.last_tick:
		return {"ok": true, "state": s, "intents": [], "inert": true}
	if int(tick) != s.last_tick + 1:
		return V.fail("nonsequential_tick")
	if command == null:
		command = {"warning_request": null, "cancel_warning": false}
	if not V.exact(command, ["warning_request", "cancel_warning"]) or not command.cancel_warning is bool:
		return V.fail("invalid_command")
	if command.warning_request != null and command.cancel_warning:
		return V.fail("conflicting_command")
	var patrol: Dictionary = _patrol(s)
	if command.warning_request != null and (s.warning != null or patrol.is_empty() or patrol.hp == 0):
		return V.fail("warning_unavailable_or_already_locked")
	if command.cancel_warning and (s.warning == null or s.warning.phase == "cancelled"):
		return V.fail("no_live_warning")
	var intents: Array = []
	var new_warning: bool = command.warning_request != null
	if new_warning:
		var pose := _sample(patrol, int(tick), 0.0)
		if not pose.ok:
			return pose
		var emitter: Dictionary = patrol.duplicate(true)
		emitter.x = pose.x
		emitter.y = pose.y
		var locked := Warning.lock(emitter, int(tick), command.warning_request)
		if not locked.ok:
			return locked
		s.warning = locked.warning
		s.warning.origin_motion = _motion(patrol)
		intents.append(_notice(s.warning, "warning_started", int(tick), 0.0))
	s.last_tick = int(tick)
	if s.warning == null or s.warning.phase == "cancelled":
		return {"ok": true, "state": s, "intents": intents, "inert": false}
	var w: Dictionary = s.warning
	if w.phase == "warning" and not new_warning:
		w.warning_left -= 1
		if w.warning_left == 0:
			w.phase = "active"
	if command.cancel_warning:
		Warning.cancel(w, "explicit_cancel", s.last_tick, 0.0)
		w.terminal_motion = _motion(patrol)
		intents.append(_notice(w, "warning_cancelled", s.last_tick, 0.0))
	elif w.phase == "active":
		var pose := _sample(patrol, s.last_tick, 0.0)
		if not pose.ok:
			return pose
		var cost: int = _cost(pose.vx, pose.vy)
		if cost > patrol.fuel_mj:
			Warning.cancel(w, "resource_exhausted", s.last_tick, 0.0, cost, pose.vx, pose.vy)
			w.terminal_motion = _motion(patrol)
			intents.append(_notice(w, "warning_cancelled", s.last_tick, 0.0))
		else:
			patrol.fuel_mj -= cost
			patrol.spent_mj += cost
			s.charges.append({"tick": s.last_tick, "cost_mj": cost, "vx": pose.vx, "vy": pose.vy, "motion": _motion(patrol)})
			w.emitted += 1
			w.active_left -= 1
			intents.append({"kind": "actor_force_intent", "event_id": w.event_id,
				"source_id": patrol.source_id, "actor_id": patrol.id,
				"intent_id": w.event_id + "/force/%d" % s.last_tick,
				"tick": s.last_tick, "from_fraction": 0.0, "to_fraction": 1.0,
				"fx_n": w.dir_x * 120.0, "fy_n": w.dir_y * 120.0,
				"reserved_energy_mj": cost, "impulse_limit_ns": 1.0})
			if patrol.fuel_mj == 0:
				Warning.cancel(w, "resource_exhausted", s.last_tick, 1.0, cost, pose.vx, pose.vy)
				w.terminal_motion = _motion(patrol)
				intents.append(_notice(w, "warning_cancelled", s.last_tick, 1.0))
	return {"ok": true, "state": s, "intents": intents, "inert": false}

static func segment(saved_state: Variant, actor_id: Variant, tick: Variant, from_fraction: Variant, to_fraction: Variant) -> Dictionary:
	var restored := restore_snapshot(saved_state)
	if not restored.ok:
		return restored
	if not actor_id is String or not V.integer(tick, 0, V.MAX_TICK) \
		or not V.real(from_fraction, 0.0, 1.0) or not V.real(to_fraction, 0.0, 1.0) or to_fraction < from_fraction:
		return V.fail("invalid_segment_query")
	var a := _find(restored.state, actor_id)
	if a.is_empty():
		return V.fail("unknown_actor")
	var start := _sample(a, int(tick), from_fraction)
	var end := _sample(a, int(tick), to_fraction)
	if not start.ok or not end.ok:
		return V.fail("segment_precedes_anchor_or_exceeds_bounds")
	return {"ok": true, "actor_id": a.id, "source_id": a.source_id, "tick": int(tick),
		"from_fraction": from_fraction, "to_fraction": to_fraction, "start": start, "end": end,
		"radius_m": a.radius_m, "mass_kg": a.mass_kg, "hp": a.hp,
		"model": "saved_linear_segment_only"}

static func rebase(saved_state: Variant, commit: Variant) -> Dictionary:
	var restored := restore_snapshot(saved_state)
	if not restored.ok:
		return restored
	var s: Dictionary = restored.state
	if not _valid_commit(commit) or int(commit.tick) != s.last_tick:
		return V.fail("invalid_rebase_commit")
	var a := _find(s, commit.actor_id)
	if a.is_empty():
		return V.fail("unknown_actor")
	var normalized: Dictionary = _normalize_commit(commit)
	if normalized.revision == a.revision:
		if V.typed_hash(normalized) == V.typed_hash(a.last_commit):
			return {"ok": true, "state": s, "intents": [], "inert": true}
		return V.fail("reused_rebase_revision")
	if normalized.revision != a.revision + 1 or normalized.hp > a.hp:
		return V.fail("invalid_rebase_revision_or_heal")
	if not _sample(a, int(normalized.tick), normalized.fraction).ok:
		return V.fail("rebase_precedes_anchor")
	a.anchor_tick = normalized.tick + (1 if normalized.fraction == 1.0 else 0)
	a.anchor_fraction = 0.0 if normalized.fraction == 1.0 else normalized.fraction
	for field in ["x", "y", "vx", "vy", "hp", "revision"]:
		a[field] = normalized[field]
	a.last_commit = normalized
	var intents: Array = []
	if a.hp == 0 and a.role == "patrol" and s.warning != null and s.warning.phase != "cancelled":
		Warning.cancel(s.warning, "actor_destroyed", s.last_tick, normalized.fraction)
		s.warning.terminal_motion = _motion(a)
		intents.append(_notice(s.warning, "warning_cancelled", s.last_tick, normalized.fraction))
	return {"ok": true, "state": s, "intents": intents, "inert": false}

static func snapshot(saved_state: Variant) -> Dictionary:
	var result := restore_snapshot(saved_state)
	return {"ok": true, "snapshot": result.state} if result.ok else result

static func save_json(saved_state: Variant) -> Dictionary:
	var result := restore_snapshot(saved_state)
	return {"ok": true, "json": V.pack_json(result.state, "snapshot")} if result.ok else result

static func load_json(text: Variant) -> Dictionary:
	var decoded := V.unpack_json(text, "snapshot")
	return restore_snapshot(decoded.value) if decoded.ok else decoded

static func restore_snapshot(saved: Variant) -> Dictionary:
	if not V.bounded_json(saved) or not V.exact(saved, STATE_KEYS) or saved.helper != Bundle.VERSION or saved.snapshot_version != SNAPSHOT_VERSION \
		or not V.integer(saved.last_tick, -1, V.MAX_TICK) or not saved.actors is Array \
		or not saved.charges is Array or saved.charges.size() > 60:
		return V.fail("invalid_snapshot")
	var base := Bundle.restore(saved.bundle)
	if not base.ok or saved.actors.size() != base.bundle.actors.size():
		return V.fail("invalid_snapshot_bundle")
	var s: Dictionary = saved.duplicate(true)
	s.bundle = base.bundle
	s.last_tick = int(s.last_tick)
	for i in s.actors.size():
		var a: Variant = s.actors[i]
		var original: Dictionary = s.bundle.actors[i]
		if not V.exact(a, ACTOR_KEYS):
			return V.fail("invalid_body_fields")
		for key in ["id", "source_id", "role", "mass_kg", "radius_m"]:
			if V.typed_hash(a[key]) != V.typed_hash(original[key]):
				return V.fail("body_identity_or_shape_changed")
		if not V.integer(a.hp, 0, original.hp) or not V.integer(a.fuel_mj, 0, original.fuel_mj) \
			or not V.integer(a.spent_mj, 0, original.fuel_mj) or a.spent_mj + a.fuel_mj != original.fuel_mj \
			or not V.integer(a.anchor_tick, 0, s.last_tick + 1) or not V.real(a.anchor_fraction, 0.0, 1.0) \
			or a.anchor_fraction == 1.0 or (a.anchor_tick == s.last_tick + 1 and a.anchor_fraction != 0.0) \
			or not V.integer(a.revision, 0, 1000000000) or not V.real(a.x, -1.0e12, 1.0e12) \
			or not V.real(a.y, -1.0e12, 1.0e12) or not V.real(a.vx, -1.0e6, 1.0e6) or not V.real(a.vy, -1.0e6, 1.0e6):
			return V.fail("invalid_body_state")
		for key in ["hp", "fuel_mj", "spent_mj", "anchor_tick", "revision"]:
			a[key] = int(a[key])
		if a.revision == 0:
			if a.last_commit != null or a.anchor_tick != 0 or a.anchor_fraction != 0.0 or a.hp != original.hp:
				return V.fail("uncommitted_body_changed")
			for key in ["x", "y", "vx", "vy"]:
				if V.float_bits(a[key]) != V.float_bits(original[key]):
					return V.fail("uncommitted_motion_changed")
		else:
			if not _valid_commit(a.last_commit):
				return V.fail("invalid_saved_rebase")
			a.last_commit = _normalize_commit(a.last_commit)
			var c: Dictionary = a.last_commit
			if c.actor_id != a.id or c.revision != a.revision or c.tick > s.last_tick \
				or a.anchor_tick != c.tick + (1 if c.fraction == 1.0 else 0) \
				or a.anchor_fraction != (0.0 if c.fraction == 1.0 else c.fraction):
				return V.fail("rebase_anchor_mismatch")
			for key in ["x", "y", "vx", "vy", "hp"]:
				if V.typed_hash(a[key]) != V.typed_hash(c[key]):
					return V.fail("rebase_payload_mismatch")
	var patrol := _patrol(s)
	if patrol.is_empty():
		if s.warning != null or not s.charges.is_empty():
			return V.fail("patrol_missing")
		return {"ok": true, "state": s}
	var warning := Warning.restore(s.warning, patrol.id, s.last_tick)
	if not warning.ok:
		return warning
	s.warning = warning.warning
	if s.warning == null:
		if not s.charges.is_empty() or patrol.spent_mj != 0:
			return V.fail("spending_without_warning")
		return {"ok": true, "state": s}
	var w: Dictionary = s.warning
	if s.charges.size() != w.emitted:
		return V.fail("charge_count_mismatch")
	var total: int = 0
	for i in s.charges.size():
		var charge: Variant = s.charges[i]
		if not V.exact(charge, ["tick", "cost_mj", "vx", "vy", "motion"]) \
			or not V.integer(charge.tick, w.locked_tick + 180 + i, w.locked_tick + 180 + i) \
			or charge.tick > s.last_tick or not V.integer(charge.cost_mj, 1000, 60000) \
			or not V.real(charge.vx, -1.0e6, 1.0e6) or not V.real(charge.vy, -1.0e6, 1.0e6) \
			or charge.cost_mj != _cost(charge.vx, charge.vy):
			return V.fail("invalid_charge_history")
		charge.tick = int(charge.tick)
		charge.cost_mj = int(charge.cost_mj)
		total += charge.cost_mj
	if total != patrol.spent_mj:
		return V.fail("resource_accounting_mismatch")
	if w.phase == "cancelled":
		if w.reason == "actor_destroyed" and patrol.hp != 0:
			return V.fail("wreck_cause_missing")
		if w.reason == "resource_exhausted":
			if w.warning_left != 0 or w.denied_cost_mj < 1000 or w.denied_cost_mj <= patrol.fuel_mj \
				or w.denied_cost_mj != _cost(w.denied_vx, w.denied_vy):
				return V.fail("exhaustion_cause_missing")
			if patrol.fuel_mj == 0:
				if s.charges.is_empty() or w.closed_fraction != 1.0 or s.charges.back().tick != w.closed_tick:
					return V.fail("invalid_zero_resource_close")
			elif w.closed_fraction != 0.0 or w.closed_tick != w.locked_tick + 180 + w.emitted:
				return V.fail("invalid_unaffordable_close")
		elif w.denied_cost_mj != 0:
			return V.fail("unexpected_denied_cost")
	elif patrol.hp == 0 or (w.phase == "active" and patrol.fuel_mj == 0):
		return V.fail("disabled_patrol_still_active")
	var history := _validate_decision_motions(s, patrol)
	if not history.ok:
		return history
	return {"ok": true, "state": s}

static func _sample(a: Dictionary, tick: int, fraction: float) -> Dictionary:
	if fraction == 1.0:
		tick += 1
		fraction = 0.0
	if tick < a.anchor_tick or (tick == a.anchor_tick and fraction < a.anchor_fraction):
		return V.fail("before_anchor")
	var elapsed: float = (float(tick - a.anchor_tick) + (fraction - a.anchor_fraction)) * DT
	if elapsed == 0.0:
		return {"ok": true, "x": a.x, "y": a.y, "vx": a.vx, "vy": a.vy}
	var x: float = a.x + a.vx * elapsed
	var y: float = a.y + a.vy * elapsed
	if not V.real(x, -1.0e12, 1.0e12) or not V.real(y, -1.0e12, 1.0e12):
		return V.fail("sample_out_of_bounds")
	return {"ok": true, "x": x, "y": y, "vx": a.vx, "vy": a.vy}

static func _valid_commit(c: Variant) -> bool:
	return V.bounded_json(c) and V.exact(c, COMMIT_KEYS) and c.actor_id is String \
		and V.integer(c.tick, 0, V.MAX_TICK) and V.real(c.fraction, 0.0, 1.0) \
		and V.integer(c.revision, 1, 1000000000) and V.real(c.x, -1.0e12, 1.0e12) \
		and V.real(c.y, -1.0e12, 1.0e12) and V.real(c.vx, -1.0e6, 1.0e6) \
		and V.real(c.vy, -1.0e6, 1.0e6) and V.integer(c.hp, 0, 40)

static func _normalize_commit(c: Dictionary) -> Dictionary:
	var copy: Dictionary = c.duplicate(true)
	for key in ["tick", "revision", "hp"]:
		copy[key] = int(copy[key])
	return copy

static func _cost(vx: float, vy: float) -> int:
	# Conservative free-body positive-work ceiling plus a minimum command cost.
	# Future chronology owner must cap real work by reserved_energy_mj after contacts.
	var speed: float = sqrt(vx * vx + vy * vy)
	var work_j: float = 120.0 * speed * DT + 120.0 * 120.0 * DT * DT / (2.0 * 60.0)
	return maxi(1000, ceili(work_j * 1000.0))

static func _motion(a: Dictionary) -> Dictionary:
	# Store the actual latest authoritative commit used for this decision.
	return {"revision": a.revision, "commit": a.last_commit.duplicate(true) if a.last_commit != null else null}

static func _motion_pose(s: Dictionary, actor: Dictionary, motion: Variant, tick: int, fraction: float, destruction: bool) -> Dictionary:
	if not V.exact(motion, ["revision", "commit"]) or not V.integer(motion.revision, 0, actor.revision):
		return V.fail("invalid_motion_witness")
	motion.revision = int(motion.revision)
	var original := _find({"actors": s.bundle.actors}, actor.id)
	var anchor: Dictionary
	var hp: int
	if motion.revision == 0:
		if motion.commit != null or destruction:
			return V.fail("uncommitted_motion_witness")
		anchor = {"anchor_tick": 0, "anchor_fraction": 0.0, "x": original.x, "y": original.y, "vx": original.vx, "vy": original.vy}
		hp = original.hp
	else:
		if not _valid_commit(motion.commit):
			return V.fail("invalid_motion_commit")
		motion.commit = _normalize_commit(motion.commit)
		var c: Dictionary = motion.commit
		if c.actor_id != actor.id or c.revision != motion.revision or c.hp > original.hp:
			return V.fail("motion_commit_identity")
		if destruction:
			if c.hp != 0 or c.tick != tick or V.float_bits(c.fraction) != V.float_bits(fraction):
				return V.fail("destruction_not_at_damage_commit")
		elif c.tick >= tick or c.hp == 0:
			# advance decides before any rebase belonging to its own tick.
			return V.fail("decision_precedes_motion_commit")
		anchor = {"anchor_tick": c.tick + (1 if c.fraction == 1.0 else 0),
			"anchor_fraction": 0.0 if c.fraction == 1.0 else c.fraction,
			"x": c.x, "y": c.y, "vx": c.vx, "vy": c.vy}
		hp = c.hp
	if motion.revision == actor.revision and not _commits_equal(motion.commit, actor.last_commit):
		return V.fail("motion_does_not_match_saved_actor")
	var pose := _sample(anchor, tick, fraction if destruction else 0.0)
	if not pose.ok:
		return V.fail("invalid_decision_motion_time")
	pose["hp"] = hp
	return {"ok": true, "pose": pose}

static func _validate_decision_motions(s: Dictionary, patrol: Dictionary) -> Dictionary:
	var w: Dictionary = s.warning
	var decisions: Array = [{"motion": w.origin_motion, "tick": w.locked_tick, "fraction": 0.0, "kind": "origin"}]
	for charge in s.charges:
		decisions.append({"motion": charge.motion, "tick": charge.tick, "fraction": 0.0, "kind": "charge", "charge": charge})
	if w.phase == "cancelled":
		decisions.append({"motion": w.terminal_motion, "tick": w.closed_tick, "fraction": w.closed_fraction, "kind": w.reason})
	var previous: Dictionary = {}
	var previous_hp: int = 25
	for decision in decisions:
		var motion: Variant = decision.motion
		var result := _motion_pose(s, patrol, motion, decision.tick, decision.fraction, decision.kind == "actor_destroyed")
		if not result.ok:
			return result
		var pose: Dictionary = result.pose
		if pose.hp > previous_hp:
			return V.fail("motion_history_heals_actor")
		previous_hp = pose.hp
		if not previous.is_empty():
			if motion.revision < previous.motion.revision:
				return V.fail("motion_revision_went_backwards")
			if motion.revision == previous.motion.revision:
				if not _commits_equal(motion.commit, previous.motion.commit):
					return V.fail("motion_revision_rewritten")
			elif motion.commit.tick < previous.tick:
				return V.fail("historical_commit_hidden_from_previous_decision")
		if decision.kind == "origin":
			if V.float_bits(pose.x) != V.float_bits(w.origin_x) or V.float_bits(pose.y) != V.float_bits(w.origin_y):
				return V.fail("warning_origin_not_on_saved_motion")
		elif decision.kind == "charge":
			if V.float_bits(pose.vx) != V.float_bits(decision.charge.vx) or V.float_bits(pose.vy) != V.float_bits(decision.charge.vy):
				return V.fail("charge_velocity_not_on_saved_motion")
		elif decision.kind == "resource_exhausted":
			if V.float_bits(pose.vx) != V.float_bits(w.denied_vx) or V.float_bits(pose.vy) != V.float_bits(w.denied_vy):
				return V.fail("denial_velocity_not_on_saved_motion")
		previous = decision
	if patrol.hp > previous_hp:
		return V.fail("current_actor_healed_after_decision")
	if patrol.revision > previous.motion.revision and patrol.last_commit.tick < previous.tick:
		return V.fail("latest_commit_hidden_from_decision")
	return {"ok": true}

static func _commits_equal(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == b
	if a != b:
		return false
	return PackedFloat64Array([a.fraction, a.x, a.y, a.vx, a.vy]).to_byte_array() \
		== PackedFloat64Array([b.fraction, b.x, b.y, b.vx, b.vy]).to_byte_array()

static func _find(s: Dictionary, actor_id: String) -> Dictionary:
	for a in s.actors:
		if a.id == actor_id:
			return a
	return {}

static func _patrol(s: Dictionary) -> Dictionary:
	for a in s.actors:
		if a.role == "patrol":
			return a
	return {}

static func _notice(w: Dictionary, kind: String, tick: int, fraction: float) -> Dictionary:
	# Geometry and direction are visible in the first warning, never chosen later.
	return {"kind": kind, "event_id": w.event_id, "source_id": w.source_id, "actor_id": w.source_id,
		"intent_id": w.event_id + "/%s/%d" % [kind, tick], "tick": tick, "fraction": fraction,
		"origin_x": w.origin_x, "origin_y": w.origin_y, "target_x": w.target_x, "target_y": w.target_y,
		"dir_x": w.dir_x, "dir_y": w.dir_y, "reason": w.reason}
