extends SceneTree
const A = preload("ground_traffic_actor_v1.gd")
const V = preload("ground_traffic_value_v1.gd")
var failures: Array = []
var stage_hashes: Array = []
var checkpoints: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var decoded := V.unpack_json(FileAccess.get_file_as_string("res://fixtures/REFERENCE_INPUTS_TYPED.json"), "reference_fixture")
	if not decoded.ok:
		print(JSON.stringify({"passed": false, "error": decoded.error}))
		quit(1)
		return
	var f: Dictionary = decoded.value
	var configured := A.configure(f.initial_bundle)
	var s: Dictionary = configured.state
	check(V.typed_hash(s) == f.initial_state_hash, "initial realization matches native golden")
	var main_hash: String = ""
	for op in f.operations:
		var r: Dictionary = {"ok": true, "state": s}
		match op.kind:
			"advance": r = A.advance(s, op.tick, true, op.get("command", null))
			"advance_range":
				for tick in range(op.first, op.last + 1):
					r = A.advance(r.state, tick, true)
					if not r.ok: break
			"rebase": r = A.rebase(s, op.commit)
			"round_trip":
				var saved := A.save_json(s)
				r = A.load_json(saved.json) if saved.ok else saved
			"segment":
				var segment := A.segment(s, s.actors.back().id, op.tick, op.from_fraction, op.to_fraction)
				check(segment.ok and segment.hp == 0 and segment.end.x < segment.start.x, "retained wreck query")
			"restore_checkpoint": r = A.restore_snapshot(checkpoints[op.checkpoint])
			_: r = {"ok": false, "error": "unknown_fixture_operation"}
		if not r.ok:
			check(false, op.label + ": " + r.error)
			break
		s = r.state
		var actual := V.typed_hash(s)
		check(actual != "" and actual == op.expected_state_hash, op.label + " native golden mismatch")
		stage_hashes.append({"label": op.label, "hash": actual})
		if op.has("save_checkpoint"): checkpoints[op.save_checkpoint] = s.duplicate(true)
		if op.get("capture_main_result", false): main_hash = actual
	var report := {"suite": "independent-typed-reference-fixture", "passed": failures.is_empty(), "failures": failures,
		"operation_count": stage_hashes.size(), "stage_hashes": stage_hashes, "main_hash": main_hash,
		"fixture_hash": V.typed_hash(f), "solver_implemented": false}
	var dest := OS.get_environment("SC_GROUND_QA_DIR")
	var file := FileAccess.open(dest.path_join("FIXTURE_REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true, true))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
