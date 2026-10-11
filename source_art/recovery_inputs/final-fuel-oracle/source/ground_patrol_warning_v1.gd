extends RefCounted
const V = preload("ground_traffic_value_v1.gd")
const KEYS := ["event_id", "source_id", "request_id", "locked_tick", "target_x", "target_y", "origin_x", "origin_y", "dir_x", "dir_y", "warning_left", "active_left", "emitted", "phase", "reason", "closed_tick", "closed_fraction", "denied_cost_mj", "denied_vx", "denied_vy", "origin_motion", "terminal_motion"]

static func lock(patrol: Dictionary, tick: int, request: Variant) -> Dictionary:
	if not V.bounded_json(request) or not V.exact(request, ["request_id", "target_x", "target_y"]) or not V.request_id(request.request_id) \
		or not V.real(request.target_x, 96.0, 170.0) or not V.real(request.target_y, -24.0, 2.0):
		return V.fail("invalid_warning_request")
	var dx: float = request.target_x - patrol.x
	var dy: float = request.target_y - patrol.y
	var distance: float = sqrt(dx * dx + dy * dy)
	if not is_finite(distance) or distance < 0.5 or distance > 80.0:
		return V.fail("invalid_warning_distance")
	var warning: Dictionary = {"event_id": patrol.id + "/warning_0", "source_id": patrol.source_id,
		"request_id": request.request_id, "locked_tick": tick,
		"target_x": request.target_x, "target_y": request.target_y,
		"origin_x": patrol.x, "origin_y": patrol.y, "dir_x": dx / distance, "dir_y": dy / distance,
		"warning_left": 180, "active_left": 120, "emitted": 0, "phase": "warning", "reason": "",
		"closed_tick": -1, "closed_fraction": 0.0, "denied_cost_mj": 0, "denied_vx": 0.0, "denied_vy": 0.0,
		"origin_motion": null, "terminal_motion": null}
	return {"ok": true, "warning": warning}

static func restore(value: Variant, source_id: String, last_tick: int) -> Dictionary:
	if value == null:
		return {"ok": true, "warning": null}
	if not V.bounded_json(value) or not V.exact(value, KEYS) or value.source_id != source_id or value.event_id != source_id + "/warning_0" \
		or not V.request_id(value.request_id) or not V.integer(value.locked_tick, 0, last_tick) \
		or not V.real(value.target_x, 96.0, 170.0) or not V.real(value.target_y, -24.0, 2.0) \
		or not V.real(value.origin_x, -1.0e12, 1.0e12) or not V.real(value.origin_y, -1.0e12, 1.0e12) \
		or not V.real(value.dir_x, -1.0, 1.0) or not V.real(value.dir_y, -1.0, 1.0) \
		or not V.integer(value.warning_left, 0, 180) or not V.integer(value.active_left, 0, 120) \
		or not V.integer(value.emitted, 0, 60) or value.active_left + value.emitted != 120 \
		or not V.integer(value.closed_tick, -1, last_tick) or not V.real(value.closed_fraction, 0.0, 1.0) \
		or not V.integer(value.denied_cost_mj, 0, 2000000000) \
		or not V.real(value.denied_vx, -1.0e6, 1.0e6) or not V.real(value.denied_vy, -1.0e6, 1.0e6):
		return V.fail("invalid_warning_state")
	var dx: float = value.target_x - value.origin_x
	var dy: float = value.target_y - value.origin_y
	var length: float = sqrt(dx * dx + dy * dy)
	if length < 0.5 or length > 80.0 or not is_finite(length) \
		or V.float_bits(value.dir_x) != V.float_bits(dx / length) or V.float_bits(value.dir_y) != V.float_bits(dy / length):
		return V.fail("warning_direction_changed")
	if value.phase == "warning":
		if value.warning_left < 1 or value.emitted != 0 or value.reason != "" \
			or last_tick - value.locked_tick != 180 - value.warning_left:
			return V.fail("invalid_warning_clock")
	elif value.phase == "active":
		if value.warning_left != 0 or value.emitted < 1 or value.active_left < 1 or value.reason != "" \
			or last_tick - value.locked_tick != 179 + value.emitted:
			return V.fail("invalid_active_clock")
	elif value.phase == "cancelled":
		if not value.reason in ["explicit_cancel", "actor_destroyed", "resource_exhausted"]:
			return V.fail("invalid_warning_cancellation")
		if value.closed_tick < value.locked_tick \
			or value.warning_left != maxi(0, 180 - int(value.closed_tick - value.locked_tick)):
			return V.fail("invalid_cancellation_clock")
		var possible_issued: int = maxi(0, int(value.closed_tick - value.locked_tick) - 179)
		if value.emitted > possible_issued or value.emitted < maxi(0, possible_issued - 1):
			return V.fail("impossible_emission_history")
		if value.reason == "explicit_cancel" and (value.closed_fraction != 0.0 or value.emitted != maxi(0, possible_issued - 1)):
			return V.fail("explicit_cancel_after_issue")
		if value.reason == "actor_destroyed" and value.emitted != possible_issued:
			return V.fail("destruction_issue_history_mismatch")
	else:
		return V.fail("invalid_warning_phase")
	if value.phase in ["warning", "active"] and (value.closed_tick != -1 or value.closed_fraction != 0.0 or value.denied_cost_mj != 0):
		return V.fail("premature_closed_state")
	if value.reason != "resource_exhausted" and (value.denied_cost_mj != 0 or value.denied_vx != 0.0 or value.denied_vy != 0.0):
		return V.fail("unexpected_exhaustion_evidence")
	if not value.origin_motion is Dictionary or (value.phase == "cancelled" and not value.terminal_motion is Dictionary) \
		or (value.phase != "cancelled" and value.terminal_motion != null):
		return V.fail("missing_decision_motion")
	var copy: Dictionary = value.duplicate(true)
	for key in ["locked_tick", "warning_left", "active_left", "emitted", "closed_tick", "denied_cost_mj"]:
		copy[key] = int(copy[key])
	return {"ok": true, "warning": copy}

static func cancel(warning: Dictionary, reason: String, tick: int, fraction: float, denied_cost_mj: int = 0, denied_vx: float = 0.0, denied_vy: float = 0.0) -> void:
	if warning.phase in ["warning", "active"]:
		warning.phase = "cancelled"
		warning.reason = reason
		warning.closed_tick = tick
		warning.closed_fraction = fraction
		warning.denied_cost_mj = denied_cost_mj
		warning.denied_vx = denied_vx
		warning.denied_vy = denied_vy
