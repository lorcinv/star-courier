extends RefCounted
## NEW isolated reconstruction. This is not the missing historical v6 protocol.
## Pure state/intent bookkeeping. One external common-time owner resolves all
## motion, contacts, rays and damage. A disabled actor remains a solid body.
const V = preload("../vendor/traffic_corrected_v3/ground_traffic_value_v1.gd")
const VERSION = "pirate-reconstructed-actor-v1"
const DEFINITION = "pirate-reconstructed-definition-v1"
const DT = 1.0 / 120.0
const DEFINITION_KEYS = ["schema", "id", "x", "y", "vx", "vy", "mass_kg", "radius_m", "max_hp", "warning_ticks", "shot_cost_mj", "ammo", "range_m", "shot_damage_hp"]
const STATE_KEYS = ["schema", "definition", "last_tick", "x", "y", "vx", "vy", "hp", "anchor_tick", "anchor_fraction", "revision", "last_commit", "disabled_at", "warnings", "emissions", "spent_mj", "solid"]
const COMMIT_KEYS = ["actor_id", "tick", "fraction", "revision", "x", "y", "vx", "vy", "hp"]
const WARNING_KEYS = ["event_id", "request_id", "locked_tick", "due_tick", "origin_x", "origin_y", "target_x", "target_y", "dir_x", "dir_y", "phase", "closed_tick", "closed_fraction", "reason"]
const EMISSION_KEYS = ["event_id", "intent_id", "source_id", "tick", "fraction", "cost_mj"]

static func example_definition() -> Dictionary:
	# Explicit NEW fixture tuning, not recovered historical HP/range/damage.
	return {"schema": DEFINITION, "id": "pirate_example", "x": 30.0, "y": 0.0,
		"vx": 0.0, "vy": 0.0, "mass_kg": 6.0, "radius_m": 1.5, "max_hp": 40.0,
		"warning_ticks": 330, "shot_cost_mj": 18000, "ammo": 2, "range_m": 64.0, "shot_damage_hp": 12.0}

static func configure(definition: Variant) -> Dictionary:
	var valid = _definition(definition)
	if not valid.ok: return valid
	var d: Dictionary = valid.definition
	return {"ok": true, "state": {"schema": VERSION, "definition": d,
		"last_tick": -1, "x": d.x, "y": d.y, "vx": d.vx, "vy": d.vy, "hp": d.max_hp,
		"anchor_tick": 0, "anchor_fraction": 0.0, "revision": 0, "last_commit": null,
		"disabled_at": null, "warnings": [], "emissions": [], "spent_mj": 0, "solid": true}}

static func neutral_command() -> Dictionary:
	return {"warning_request": null, "cancel_warning": false}

static func advance(saved: Variant, tick: Variant, enabled: Variant, command: Variant = null) -> Dictionary:
	var checked = restore(saved)
	if not checked.ok: return checked
	if not V.integer(tick, 0, V.MAX_TICK) or not enabled is bool: return V.fail("invalid_tick_or_enable")
	var s: Dictionary = checked.state
	if not enabled or int(tick) == s.last_tick: return _result(s, [], true)
	if int(tick) != s.last_tick + 1: return V.fail("nonsequential_tick")
	if command == null: command = neutral_command()
	if not V.bounded_json(command) or not V.exact(command, ["warning_request", "cancel_warning"]) or not command.cancel_warning is bool:
		return V.fail("invalid_command")
	if command.warning_request != null and command.cancel_warning: return V.fail("conflicting_command")
	var current: Dictionary = _open_warning(s)
	if current.get("phase", "") == "ready": return V.fail("pending_emission_must_resolve")
	var notices: Array = []
	if command.warning_request != null:
		if not current.is_empty() or s.hp <= 0.0 or s.warnings.size() >= int(s.definition.ammo): return V.fail("warning_unavailable")
		if int(tick) > V.MAX_TICK - int(s.definition.warning_ticks): return V.fail("warning_exceeds_clock_bound")
		var request: Variant = command.warning_request
		if not V.exact(request, ["request_id", "target_x", "target_y"]) or not V.request_id(request.request_id) \
			or not V.real(request.target_x, -1.0e9, 1.0e9) or not V.real(request.target_y, -1.0e9, 1.0e9): return V.fail("invalid_warning_request")
		# Freeze the predicted emission point from committed motion at lock.
		# Later collision/rebase changes the live muzzle, never this marker.
		var pose = _sample(s, int(tick) + int(s.definition.warning_ticks), 0.0)
		if not pose.ok: return pose
		var ox: float = pose.x - float(s.definition.radius_m)
		var oy: float = pose.y
		var dx: float = request.target_x - ox
		var dy: float = request.target_y - oy
		var distance: float = sqrt(dx * dx + dy * dy)
		if not is_finite(distance) or distance < 0.5 or distance > float(s.definition.range_m): return V.fail("invalid_warning_distance")
		var event_id: String = s.definition.id + "/lock/%d" % s.warnings.size()
		current = {"event_id": event_id, "request_id": request.request_id, "locked_tick": int(tick),
			"due_tick": int(tick) + int(s.definition.warning_ticks), "origin_x": ox, "origin_y": oy,
			"target_x": request.target_x, "target_y": request.target_y, "dir_x": dx / distance, "dir_y": dy / distance,
			"phase": "warning", "closed_tick": -1, "closed_fraction": 0.0, "reason": ""}
		s.warnings.append(current)
		notices.append(_notice(current, "warning_started", int(tick), 0.0))
	if command.cancel_warning:
		if current.is_empty(): return V.fail("no_live_warning")
		_close(current, "cancelled", "explicit_cancel", int(tick), 0.0)
		notices.append(_notice(current, "warning_cancelled", int(tick), 0.0))
	s.last_tick = int(tick)
	if not current.is_empty() and current.phase == "warning" and int(tick) == int(current.due_tick):
		current.phase = "ready"
		# This is a proposal, not an emitted attack or debit. The common owner
		# must first process disable/contact events at this same absolute time.
		notices.append(_notice(current, "shot_due", int(tick), 0.0))
	return _result(s, notices)

static func rebase(saved: Variant, commit: Variant) -> Dictionary:
	var checked = restore(saved)
	if not checked.ok: return checked
	var s: Dictionary = checked.state
	if not _valid_commit(commit, s.definition) or int(commit.tick) != s.last_tick: return V.fail("invalid_rebase_commit")
	var c: Dictionary = _normalize_commit(commit)
	if c.revision == s.revision:
		if V.typed_hash(c) == V.typed_hash(s.last_commit): return _result(s, [], true)
		return V.fail("reused_revision")
	if c.revision != s.revision + 1 or c.hp > s.hp: return V.fail("invalid_revision_or_heal")
	if not _sample(s, c.tick, c.fraction).ok: return V.fail("rebase_precedes_anchor")
	if c.hp == 0.0:
		for emitted in s.emissions:
			if not _time_less(int(emitted.tick), emitted.fraction, c.tick, c.fraction): return V.fail("disable_precedes_already_emitted_shot")
	s.anchor_tick = c.tick + (1 if c.fraction == 1.0 else 0)
	s.anchor_fraction = 0.0 if c.fraction == 1.0 else c.fraction
	for key in ["x", "y", "vx", "vy", "hp", "revision"]: s[key] = c[key]
	s.last_commit = c
	var notices: Array = []
	if s.hp == 0.0 and s.disabled_at == null:
		s.disabled_at = {"tick": c.tick, "fraction": c.fraction, "revision": c.revision}
		var current = _open_warning(s)
		if not current.is_empty():
			_close(current, "cancelled", "actor_disabled", c.tick, c.fraction)
			notices.append(_notice(current, "warning_cancelled", c.tick, c.fraction))
	return _result(s, notices)

static func commit_emission(saved: Variant, event_id: Variant, tick: Variant, fraction: Variant) -> Dictionary:
	var checked = restore(saved)
	if not checked.ok: return checked
	var s: Dictionary = checked.state
	if not event_id is String or not V.integer(tick, 0, V.MAX_TICK) or not V.real(fraction, 0.0, 0.0): return V.fail("invalid_emission_request")
	for e in s.emissions:
		if e.event_id == event_id:
			return _result(s, [], true) if int(tick) == e.tick and fraction == e.fraction else V.fail("reused_emission_identity")
	var warning: Dictionary = {}
	for w in s.warnings:
		if w.event_id == event_id: warning = w; break
	if warning.is_empty(): return V.fail("unknown_warning")
	if int(tick) != s.last_tick or int(tick) != int(warning.due_tick): return V.fail("wrong_emission_time")
	if warning.phase == "cancelled":
		var result = _result(s, [], true); result.suppressed = true; return result
	if warning.phase != "ready" or s.hp <= 0.0: return V.fail("emission_not_ready")
	if not _sample(s, int(tick), fraction).ok: return V.fail("emission_precedes_authority")
	var cost: int = int(s.definition.shot_cost_mj)
	if s.emissions.size() >= int(s.definition.ammo) or s.spent_mj + cost > int(s.definition.ammo) * cost: return V.fail("shot_budget_exhausted")
	var record = {"event_id": event_id, "intent_id": event_id + "/shot", "source_id": s.definition.id,
		"tick": int(tick), "fraction": fraction, "cost_mj": cost}
	s.emissions.append(record); s.spent_mj += cost
	_close(warning, "emitted", "emitted", int(tick), fraction)
	var intent = {"kind": "ray_emitted", "event_id": event_id, "intent_id": record.intent_id,
		"source_id": s.definition.id, "owner_kind": "pirate", "tick": int(tick), "fraction": fraction,
		"origin_x": warning.origin_x, "origin_y": warning.origin_y, "dir_x": warning.dir_x, "dir_y": warning.dir_y,
		"range_m": s.definition.range_m, "damage_hp": s.definition.shot_damage_hp, "energy_mj": cost}
	return _result(s, [intent])

static func segment(saved: Variant, tick: Variant, from_fraction: Variant, to_fraction: Variant) -> Dictionary:
	var checked = restore(saved)
	if not checked.ok: return checked
	if not V.integer(tick, 0, V.MAX_TICK) or not V.real(from_fraction, 0.0, 1.0) or not V.real(to_fraction, 0.0, 1.0) or from_fraction > to_fraction:
		return V.fail("invalid_segment")
	var s: Dictionary = checked.state
	var first = _sample(s, int(tick), from_fraction)
	var last = _sample(s, int(tick), to_fraction)
	if not first.ok or not last.ok: return V.fail("segment_precedes_anchor")
	return {"ok": true, "model": "authoritative_saved_linear_segment_only", "start": first, "end": last,
		"mass_kg": s.definition.mass_kg, "radius_m": s.definition.radius_m, "hp": s.hp, "solid": true}

static func view(saved: Variant, tick: Variant, fraction: Variant) -> Dictionary:
	var checked = restore(saved)
	if not checked.ok: return checked
	if not V.integer(tick, 0, V.MAX_TICK) or not V.real(fraction, 0.0, 1.0): return V.fail("invalid_view_time")
	var s: Dictionary = checked.state
	var at = _sample(s, int(tick), fraction)
	if not at.ok: return at
	var warning: Dictionary = _open_warning(s).duplicate(true)
	return {"ok": true, "x": at.x, "y": at.y, "left_muzzle_x": at.x - float(s.definition.radius_m), "left_muzzle_y": at.y,
		"hp": s.hp, "disabled": s.hp == 0.0, "solid": true, "warning": warning,
		"shots_remaining": int(s.definition.ammo) - s.emissions.size(), "spent_mj": s.spent_mj,
		"cue_style": "cyan_dark_keyline_frozen_lock_with_live_muzzle_link"}

static func restore(saved: Variant) -> Dictionary:
	if saved is Dictionary and saved.get("schema") is String and saved.schema != VERSION:
		return {"ok": false, "error": "unsupported_actor_schema", "unsupported": true}
	if not V.bounded_json(saved) or not V.exact(saved, STATE_KEYS) or saved.schema != VERSION: return V.fail("invalid_actor_snapshot")
	var defined = _definition(saved.definition)
	if not defined.ok: return defined
	var d: Dictionary = defined.definition
	if not V.integer(saved.last_tick, -1, V.MAX_TICK) or not V.integer(saved.anchor_tick, 0, int(saved.last_tick) + 1) \
		or not V.real(saved.anchor_fraction, 0.0, 1.0) or saved.anchor_fraction == 1.0 \
		or (saved.anchor_tick == int(saved.last_tick) + 1 and saved.anchor_fraction != 0.0) \
		or not V.integer(saved.revision, 0, 1000000000) or not V.real(saved.hp, 0.0, d.max_hp) \
		or not saved.solid is bool or not saved.solid \
		or not saved.warnings is Array or saved.warnings.size() > int(d.ammo) \
		or not saved.emissions is Array or saved.emissions.size() > int(d.ammo) \
		or not V.integer(saved.spent_mj, 0, int(d.ammo) * int(d.shot_cost_mj)): return V.fail("invalid_actor_state")
	for key in ["x", "y", "vx", "vy"]:
		if not V.real(saved[key], -1.0e9 if key in ["x", "y"] else -1.0e6, 1.0e9 if key in ["x", "y"] else 1.0e6): return V.fail("invalid_actor_motion")
	if saved.revision == 0:
		if saved.last_commit != null or saved.anchor_tick != 0 or saved.anchor_fraction != 0.0 or saved.hp != d.max_hp: return V.fail("uncommitted_actor_changed")
		for key in ["x", "y", "vx", "vy"]:
			if V.float_bits(saved[key]) != V.float_bits(d[key]): return V.fail("uncommitted_motion_changed")
	else:
		if not _valid_commit(saved.last_commit, d): return V.fail("invalid_saved_commit")
		var c: Dictionary = saved.last_commit
		if c.tick > saved.last_tick or c.revision != saved.revision \
			or saved.anchor_tick != int(c.tick) + (1 if c.fraction == 1.0 else 0) \
			or saved.anchor_fraction != (0.0 if c.fraction == 1.0 else c.fraction): return V.fail("authority_anchor_mismatch")
		for key in ["x", "y", "vx", "vy", "hp"]:
			if V.typed_hash(saved[key]) != V.typed_hash(c[key]): return V.fail("authority_payload_mismatch")
	if saved.hp == 0.0:
		if not V.exact(saved.disabled_at, ["tick", "fraction", "revision"]) \
			or not V.integer(saved.disabled_at.tick, 0, int(saved.last_tick)) \
			or not V.real(saved.disabled_at.fraction, 0.0, 1.0) \
			or not V.integer(saved.disabled_at.revision, 1, int(saved.revision)): return V.fail("missing_disable_authority")
		if _time_less(int(saved.last_commit.tick), saved.last_commit.fraction, int(saved.disabled_at.tick), saved.disabled_at.fraction): return V.fail("authority_precedes_disable")
	elif saved.disabled_at != null: return V.fail("premature_disable")
	var emitted: Array = []
	var previous_close: int = -1
	for index in saved.warnings.size():
		var w: Variant = saved.warnings[index]
		if not V.exact(w, WARNING_KEYS) or w.event_id != d.id + "/lock/%d" % index or not V.request_id(w.request_id) \
			or not V.integer(w.locked_tick, 0, int(saved.last_tick)) or int(w.locked_tick) <= previous_close \
			or not V.integer(w.due_tick, int(w.locked_tick) + int(d.warning_ticks), int(w.locked_tick) + int(d.warning_ticks)): return V.fail("invalid_warning_identity")
		for key in ["origin_x", "origin_y", "target_x", "target_y"]:
			if not V.real(w[key], -1.0e9, 1.0e9): return V.fail("invalid_warning_geometry")
		var dx: float = w.target_x - w.origin_x
		var dy: float = w.target_y - w.origin_y
		var distance: float = sqrt(dx * dx + dy * dy)
		if distance < 0.5 or distance > float(d.range_m) or not V.real(w.dir_x, -1.0, 1.0) or not V.real(w.dir_y, -1.0, 1.0) \
			or V.float_bits(w.dir_x) != V.float_bits(dx / distance) or V.float_bits(w.dir_y) != V.float_bits(dy / distance): return V.fail("warning_direction_changed")
		if not V.integer(w.closed_tick, -1, int(saved.last_tick)) or not V.real(w.closed_fraction, 0.0, 1.0): return V.fail("invalid_warning_close")
		if w.phase in ["warning", "ready"]:
			if index != saved.warnings.size() - 1 or saved.hp == 0.0 or w.closed_tick != -1 or w.closed_fraction != 0.0 or w.reason != "": return V.fail("invalid_live_warning")
			if (w.phase == "warning" and saved.last_tick >= w.due_tick) or (w.phase == "ready" and saved.last_tick != w.due_tick): return V.fail("invalid_warning_clock")
		elif w.phase == "emitted":
			if w.closed_tick != w.due_tick or w.closed_fraction != 0.0 or w.reason != "emitted": return V.fail("invalid_emission_clock")
			emitted.append(w)
		elif w.phase == "cancelled":
			if w.closed_tick < w.locked_tick or w.closed_tick > w.due_tick or not w.reason in ["explicit_cancel", "actor_disabled"]: return V.fail("invalid_cancellation")
			if w.reason == "explicit_cancel" and w.closed_fraction != 0.0: return V.fail("invalid_cancel_time")
			if w.reason == "actor_disabled" and (saved.disabled_at == null or w.closed_tick != saved.disabled_at.tick or w.closed_fraction != saved.disabled_at.fraction): return V.fail("invalid_disable_cancellation")
		else: return V.fail("invalid_warning_phase")
		previous_close = int(w.closed_tick)
	if emitted.size() != saved.emissions.size() or saved.spent_mj != saved.emissions.size() * int(d.shot_cost_mj): return V.fail("invalid_shot_ledger")
	for index in saved.emissions.size():
		var e: Variant = saved.emissions[index]
		var w: Dictionary = emitted[index]
		if not V.exact(e, EMISSION_KEYS) or e.event_id != w.event_id or e.intent_id != w.event_id + "/shot" or e.source_id != d.id \
			or not V.integer(e.tick, int(w.due_tick), int(w.due_tick)) or not V.real(e.fraction, 0.0, 0.0) \
			or not V.integer(e.cost_mj, int(d.shot_cost_mj), int(d.shot_cost_mj)): return V.fail("invalid_emission_record")
		if saved.disabled_at != null and not _time_less(int(e.tick), e.fraction, int(saved.disabled_at.tick), saved.disabled_at.fraction): return V.fail("emission_after_disable")
	var s: Dictionary = saved.duplicate(true)
	s.definition = d
	for key in ["last_tick", "anchor_tick", "revision", "spent_mj"]: s[key] = int(s[key])
	if s.last_commit != null: s.last_commit = _normalize_commit(s.last_commit)
	return {"ok": true, "state": s}

static func save_json(saved: Variant) -> Dictionary:
	var checked = restore(saved)
	return {"ok": true, "json": V.pack_json(checked.state, VERSION)} if checked.ok else checked

static func resource_receipt(saved: Variant) -> Dictionary:
	# Evidence for the lead's paid/trial settlement boundary, never a payout or
	# economy mutation. Enemy energy cannot be charged as courier battery use.
	var checked = restore(saved)
	if not checked.ok: return checked
	var s: Dictionary = checked.state
	return {"ok": true, "schema": "pirate-resource-evidence-v1", "actor_id": s.definition.id,
		"owner_kind": "pirate", "shots_emitted": s.emissions.size(), "enemy_energy_mj": s.spent_mj,
		"courier_billable_energy_j": 0.0, "refund_mj": 0, "emissions": s.emissions.duplicate(true)}

static func load_json(text: Variant) -> Dictionary:
	var decoded = V.unpack_json(text, VERSION)
	return restore(decoded.value) if decoded.ok else decoded

static func _definition(value: Variant) -> Dictionary:
	if not V.bounded_json(value) or not V.exact(value, DEFINITION_KEYS) or value.schema != DEFINITION or not V.request_id(value.id): return V.fail("invalid_definition")
	for key in ["x", "y", "vx", "vy"]:
		if not V.real(value[key], -1.0e9 if key in ["x", "y"] else -1.0e6, 1.0e9 if key in ["x", "y"] else 1.0e6): return V.fail("invalid_definition_motion")
	if not V.real(value.mass_kg, 6.0, 6.0) or not V.real(value.radius_m, 1.5, 1.5) or not V.real(value.max_hp, 1.0, 1000.0) \
		or not V.integer(value.warning_ticks, 330, 330) or not V.integer(value.shot_cost_mj, 18000, 18000) \
		or not V.integer(value.ammo, 2, 2) or not V.real(value.range_m, 1.0, 256.0) or not V.real(value.shot_damage_hp, 0.0, 100.0): return V.fail("invalid_definition_budget")
	var d: Dictionary = value.duplicate(true)
	for key in ["warning_ticks", "shot_cost_mj", "ammo"]: d[key] = int(d[key])
	return {"ok": true, "definition": d}

static func _valid_commit(c: Variant, d: Dictionary) -> bool:
	if not V.exact(c, COMMIT_KEYS) or c.actor_id != d.id or not V.integer(c.tick, 0, V.MAX_TICK) \
		or not V.real(c.fraction, 0.0, 1.0) or not V.integer(c.revision, 1, 1000000000) or not V.real(c.hp, 0.0, d.max_hp): return false
	for key in ["x", "y", "vx", "vy"]:
		if not V.real(c[key], -1.0e9 if key in ["x", "y"] else -1.0e6, 1.0e9 if key in ["x", "y"] else 1.0e6): return false
	return true

static func _normalize_commit(c: Dictionary) -> Dictionary:
	var result: Dictionary = c.duplicate(true)
	for key in ["tick", "revision"]: result[key] = int(result[key])
	return result

static func _sample(s: Dictionary, tick: int, fraction: float) -> Dictionary:
	if _time_less(tick, fraction, int(s.anchor_tick), s.anchor_fraction): return V.fail("sample_precedes_anchor")
	var seconds: float = (float(tick - int(s.anchor_tick)) + fraction - float(s.anchor_fraction)) * DT
	var x: float = s.x + s.vx * seconds
	var y: float = s.y + s.vy * seconds
	if not V.real(x, -1.0e9, 1.0e9) or not V.real(y, -1.0e9, 1.0e9): return V.fail("sample_out_of_bounds")
	return {"ok": true, "x": x, "y": y, "vx": s.vx, "vy": s.vy}

static func _open_warning(s: Dictionary) -> Dictionary:
	if not s.warnings.is_empty() and s.warnings.back().phase in ["warning", "ready"]: return s.warnings.back()
	return {}

static func _close(w: Dictionary, phase: String, reason: String, tick: int, fraction: float) -> void:
	w.phase = phase; w.reason = reason; w.closed_tick = tick; w.closed_fraction = fraction

static func _notice(w: Dictionary, kind: String, tick: int, fraction: float) -> Dictionary:
	return {"kind": kind, "event_id": w.event_id, "tick": tick, "fraction": fraction}

static func _result(s: Dictionary, intents: Array, inert: bool = false) -> Dictionary:
	return {"ok": true, "state": s, "intents": intents, "inert": inert}

static func _time_less(at: int, af: float, bt: int, bf: float) -> bool:
	# A saved fraction1 endpoint and the next tick's fraction0 are the same
	# instant. Preserve original commit fields, canonicalize comparisons only.
	if af == 1.0: at += 1; af = 0.0
	if bf == 1.0: bt += 1; bf = 0.0
	return at < bt or (at == bt and af < bf)
