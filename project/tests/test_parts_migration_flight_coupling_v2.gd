extends SceneTree
## Contradictory legacy-flight regression. NOT RUN by author; no filesystem writes.
const Migration=preload("res://scripts/parts_migration_v2.gd")
var failures:int=0
var backups:int=0
var commits:int=0
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func backup(_value:Dictionary) -> Dictionary:
 backups+=1;return {"ok":true,"source_sha256":"a".repeat(64)}
func commit(_value:Dictionary) -> Dictionary:
 commits+=1;return {"ok":true}
func rejected(snapshot:Dictionary,reason:String,label:String) -> void:
 var before:Dictionary=snapshot.duplicate(true)
 var result:Dictionary=Migration.preview(snapshot)
 check(not result.ok and result.get("reason")==reason,label+" returns exact fail-closed reason")
 var transaction:Dictionary=Migration.transaction(snapshot,"unapproved",backup,commit)
 check(not transaction.ok and backups==0 and commits==0,label+" cannot reach backup or persist callbacks")
 check(snapshot==before,label+" leaves whole source including original gate untouched")
func _initialize() -> void:
 var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dev04-review/legacy-flight-missing-snapshot.json"))
 if not raw is Dictionary:check(false,"independent review fixture loads");quit(1);return
 var fixture:Dictionary=raw
 rejected(fixture,"in_flight_contract_missing_snapshot","old flight with missing wrapper")
 var changed:Dictionary=fixture.duplicate(true);changed.contracts[0].control_version="pilot-free-v2"
 rejected(changed,"in_flight_contract_missing_snapshot","new flight with missing wrapper")
 changed=fixture.duplicate(true);changed.contracts[0].status="accepted";changed.active_contract_id=""
 rejected(changed,"accepted_contract_not_active","accepted old job missing active identity")
 changed.contracts[0].control_version="pilot-free-v2"
 rejected(changed,"accepted_contract_not_active","accepted new job missing active identity")
 changed=fixture.duplicate(true);changed.contracts[0].status="accepted";changed.contracts.append({"contract_id":"second","status":"accepted","control_version":"pilot-free-v1"})
 rejected(changed,"accepted_contract_not_active","second accepted job outside active identity")
 changed=fixture.duplicate(true);changed.contracts[0].status="settled"
 rejected(changed,"active_contract_not_accepted","active identity incorrectly names settled job")
 var legal:Dictionary=fixture.duplicate(true);legal.contracts[0].status="accepted"
 var before:Dictionary=legal.duplicate(true);var pending:Dictionary=Migration.preview(legal)
 check(pending.ok and pending.get("deferred",false) and pending.reason=="accepted_legacy_order" and legal==before,"legitimate active accepted old job still defers unchanged")
 legal=fixture.duplicate(true);legal.in_flight={"contract_id":"old","control_version":"pilot-free-v1","design":legal.design.duplicate(true)}
 before=legal.duplicate(true);pending=Migration.preview(legal)
 check(pending.ok and pending.get("deferred",false) and pending.reason=="in_flight" and legal==before,"nonempty old replay wrapper remains opaque and deferred")
 legal=fixture.duplicate(true);legal.contracts[0].status="available";legal.active_contract_id=""
 pending=Migration.preview(legal)
 check(pending.ok and pending.changed,"ordinary available legacy offer remains eligible for property preview")
 legal=fixture.duplicate(true);legal.contracts[0].status="accepted";legal.contracts[0].control_version="pilot-free-v2"
 pending=Migration.preview(legal)
 check(pending.ok and pending.changed,"coherent active v2 accepted job keeps authorized property preview path")
 print("PARTS_MIGRATION_FLIGHT_COUPLING_V2 failures=",failures," real_save_paths=UNTOUCHED");quit(1 if failures else 0)
