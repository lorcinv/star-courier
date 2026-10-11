extends SceneTree
## Test-only oracle. No runtime edits, collision solver or force application.
const A = preload("../ground_traffic_actor_v1.gd")
const B = preload("../ground_traffic_bundle_v1.gd")
const V = preload("../ground_traffic_value_v1.gd")
var failures: Array = []
var calls: Array = []
var output: String

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func record(name: String, payload: Dictionary) -> void:
	calls.append({"call_index": calls.size(), "name": name, "returned": payload})
	print(name + " " + JSON.stringify(payload, "", true, true))

func summary(s: Dictionary) -> Dictionary:
	var a: Dictionary = s.actors.back()
	return {"last_tick": s.last_tick, "body_count": s.actors.size(), "hp": a.hp, "revision": a.revision,
		"fuel_mj": a.fuel_mj, "reserved_total_mj": a.spent_mj, "charge_count": s.charges.size(),
		"warning_phase": s.warning.phase, "reason": s.warning.reason,
		"closed_tick": s.warning.closed_tick, "closed_fraction": s.warning.closed_fraction,
		"state_hash": V.typed_hash(s), "charge_history_hash": V.typed_hash(s.charges)}

func write(name: String, value: String) -> void:
	var f := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	f.store_string(value)
	f.close()

func run() -> void:
	output = OS.get_environment("SC_GROUND_QA_DIR")
	var s: Dictionary = A.configure(B.author(42, B.fresh_definition()).bundle).state
	var request := {"warning_request": {"request_id": "final_fuel_0", "target_x": 132.0, "target_y": -8.0}, "cancel_warning": false}
	s = A.advance(s, 0, true, request).state
	for tick in range(1, 239):
		var r := A.advance(s, tick, true)
		check(r.ok, "valid warmup tick " + str(tick))
		if not r.ok:
			finish({})
			return
		s = r.state
	check(s.last_tick == 238 and s.charges.size() == 59 and s.actors.back().fuel_mj == 1000, "exact one-payment precondition")
	record("00 final-fuel precondition", {"state": summary(s)})
	var paid := A.advance(s, 239, true)
	check(paid.ok and paid.intents.size() == 2, "final tick returns exactly force then cancellation")
	if not paid.ok or paid.intents.size() != 2:
		finish({})
		return
	var force: Dictionary = paid.intents[0]
	var cancel: Dictionary = paid.intents[1]
	check(force.kind == "actor_force_intent" and force.tick == 239 and force.from_fraction == 0.0 and force.to_fraction == 1.0, "first return is full-tick paid force")
	check(force.reserved_energy_mj == 1000 and force.impulse_limit_ns == 1.0, "finite final reservation")
	check(cancel.kind == "warning_cancelled" and cancel.reason == "resource_exhausted" and cancel.tick == 239 and cancel.fraction == 1.0, "second return is end-of-tick exhaustion notice")
	s = paid.state
	check(s.warning.phase == "cancelled" and s.actors.back().fuel_mj == 0 and s.actors.back().spent_mj == 60000 and s.charges.size() == 60, "final fee is already reserved once")
	var paid_ledger := V.typed_hash(s.charges)
	write("AFTER_PAID_TICK.json", A.save_json(s).json)
	record("01 advance returns ordered intents", {"intents": paid.intents, "state": summary(s)})
	var id: String = s.actors.back().id
	var alive := A.segment(s, id, 239, 0.0, 0.25)
	check(alive.ok and alive.hp == 25, "saved pre-contact segment remains live")
	record("02 pre-death segment query", {"segment": alive})
	var commit := {"actor_id": id, "tick": 239, "fraction": 0.25, "revision": 1,
		"x": alive.end.x, "y": alive.end.y, "vx": -1.5, "vy": 0.25, "hp": 0}
	var death := A.rebase(s, commit)
	check(death.ok and death.intents.is_empty(), "earlier death returns no extra cancellation after phase already cancelled")
	if not death.ok:
		finish({})
		return
	s = death.state
	check(s.warning.reason == "resource_exhausted" and s.warning.closed_fraction == 1.0, "existing exhaustion notice is not rewritten to death")
	check(s.actors.size() == 3 and s.actors.back().hp == 0 and s.actors.back().last_commit == commit, "dead body and lethal authority commit retained")
	check(s.actors.back().fuel_mj == 0 and s.actors.back().spent_mj == 60000 and V.typed_hash(s.charges) == paid_ledger, "death neither refunds nor charges the reservation again")
	record("03 earlier lethal external rebase", {"external_input": commit, "intents": death.intents, "state": summary(s)})
	var wreck := A.segment(s, id, 239, 0.25, 1.0)
	check(wreck.ok and wreck.hp == 0 and wreck.end.x < wreck.start.x and wreck.end.y > wreck.start.y, "wreck retains its supplied sliding segment")
	record("04 post-death segment query", {"segment": wreck})
	var duplicate := A.rebase(s, commit)
	check(duplicate.ok and duplicate.inert and duplicate.intents.is_empty() and V.typed_hash(duplicate.state) == V.typed_hash(s), "duplicate contact cannot debit or notify again")
	record("05 duplicate commit is inert", {"inert": duplicate.inert, "intents": duplicate.intents, "state": summary(duplicate.state)})
	var saved := A.save_json(s)
	var restored := A.load_json(saved.json)
	check(saved.ok and restored.ok and V.typed_hash(s) == V.typed_hash(restored.state), "exact typed restore after earlier death")
	write("AFTER_EARLIER_DEATH.json", saved.json)
	var restored_segment := A.segment(restored.state, id, 239, 0.25, 1.0)
	check(V.typed_hash(restored_segment) == V.typed_hash(wreck), "restored wreck segment is bit-exact")
	record("06 exact restore", {"state": summary(restored.state), "segment": restored_segment, "segment_hash": V.typed_hash(restored_segment)})
	var next := A.advance(restored.state, 240, true)
	check(next.ok and next.intents.is_empty() and next.state.actors.size() == 3 and next.state.actors.back().hp == 0 and V.typed_hash(next.state.charges) == paid_ledger, "next tick keeps wreck without another fee or intent")
	record("07 next tick", {"intents": next.intents, "state": summary(next.state)})
	var owner_oracle := {
		"kind": "required_future_owner_behavior_not_executed_solver_result",
		"returned_intents_keep_api_order": paid.intents,
		"timeline_order": [
			{"from_fraction": 0.0, "to_fraction": 0.25, "hp": 25, "force_eligible_intent_id": force.intent_id},
			{"at_fraction": 0.25, "cause": "external_hp_zero_commit", "force_must_stop": true, "commit": commit},
			{"from_fraction": 0.25, "to_fraction": 1.0, "hp": 0, "force_must_be_zero": true, "body_retained": true},
			{"at_fraction": 1.0, "notice_already_returned_at_advance": cancel}
		],
		"final_tick_reservation_mj": 1000, "refund_mj": 0, "additional_debit_mj": 0,
		"reserved_total_after_damage_mj": 60000, "force_application_simulated": false,
		"no_new_cancel_notice_does_not_authorize_force_on_hp_zero": true,
		"phase_cancelled_does_not_erase_paid_intent": true
	}
	finish(owner_oracle)

func finish(owner_oracle: Dictionary) -> void:
	var artifact := {"suite": "final-fuel-tick-explicit-intent-oracle", "passed": failures.is_empty(), "failures": failures,
		"ordered_calls": calls, "future_owner_oracle": owner_oracle,
		"runtime_modified": false, "solver_implemented": false}
	write("ORACLE.json", JSON.stringify(artifact, "  ", true, true))
	write("ORACLE_TYPED.json", V.pack_json(artifact, "final_fuel_tick_oracle"))
	print(JSON.stringify({"suite": artifact.suite, "passed": artifact.passed, "failures": failures,
		"call_count": calls.size(), "oracle_hash": V.typed_hash(artifact), "runtime_modified": false, "solver_implemented": false}))
	quit(0 if failures.is_empty() else 1)
