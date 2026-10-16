extends SceneTree
## Actual stringify/parse persistence boundary; NOT RUN by author.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Values=preload("res://scripts/pilot_protected_bird_profile.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var failures:int=0
var backups:int=0
var commits:int=0
var persisted:Dictionary={}
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":0,"rot":1,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1}
func source() -> Dictionary:
 var craft:Array=[part(1,"cargo",0),part(2,"not_gate",1),part(3,"teleporter",2,2),part(4,"spring",3)]
 var pad:Array=[part(11,"shield",0),part(12,"battery",1)]
 return {"credits":75,"inventory":{"cargo":1,"not_gate":3,"teleporter":1,"spring":2,"shield":1,"battery":1},"design":craft,"launcher":pad,"designs":{"one":{"design":craft.duplicate(true),"launcher":pad.duplicate(true)},"two":{"design":craft.duplicate(true),"launcher":pad.duplicate(true)}},"settings":{},"in_flight":{},"contracts":[],"active_contract_id":""}
func roundtrip(value:Dictionary) -> Dictionary:
 var parsed:Variant=JSON.parse_string(JSON.stringify(value,"",true,true))
 return parsed if parsed is Dictionary else {}
func backup(_snapshot:Dictionary) -> Dictionary:
 backups+=1;return {"ok":true,"source_sha256":"a".repeat(64)}
func persist(candidate:Dictionary) -> Dictionary:
 commits+=1
 persisted=roundtrip(candidate)
 var error:String=Migration.receipt_error(persisted)
 if not error.is_empty():print("ROUNDTRIP_PERSIST_REJECTED ",error)
 return {"ok":error.is_empty()}
func _initialize() -> void:
 for source_kind in ["memory_ints","parsed_floats"]:
  var original:Dictionary=source() if source_kind=="memory_ints" else roundtrip(source())
  var before:Dictionary=original.duplicate(true)
  var plan:Dictionary=Migration.preview(original)
  if not plan.ok:print("ROUNDTRIP_PREVIEW_REJECTED ",JSON.stringify(plan));check(false,source_kind+" preview");quit(1);return
  # This exact fixture has one manual rebind in each current/blueprint craft.
  # Replacing float(-1) with int(-1) must never create spurious control rows.
  check(plan.controls.size()==3,source_kind+" emits only3 real control changes across craft and2 blueprints")
  check(plan.credit_delta==65 and plan.before.total_value==345 and plan.after.total_value==345,source_kind+" preserves exact original property fixture and credit delta")
  var result:Dictionary=Migration.transaction(original,plan.confirmation_token,backup,persist)
  if not result.ok:print("ROUNDTRIP_TRANSACTION_REJECTED ",JSON.stringify(result));check(false,source_kind+" actual JSON persistence");quit(1);return
  check(original==before,source_kind+" transaction keeps original aliases unchanged")
  check(Migration.receipt_error(persisted).is_empty(),source_kind+" whole candidate survives actual JSON stringify/parse receipt guard")
  check(Values.same_value(result.candidate,persisted),source_kind+" full candidate retains every field and value across JSON numeric representation")
  var twice:Dictionary=roundtrip(persisted)
  check(Migration.receipt_error(twice).is_empty(),source_kind+" repeated save/load remains valid")
  var calls:int=commits;var archives:int=backups
  var retry:Dictionary=Migration.transaction(twice,plan.confirmation_token,backup,persist)
  check(retry.ok and bool(retry.get("duplicate",false)) and not retry.changed and calls==commits and archives==backups,source_kind+" reloaded receipt prevents repeat payout or callbacks")
  var corrupt:Dictionary=twice.duplicate(true);corrupt.parts_retirement.after.credits+=1
  check(not Migration.receipt_error(corrupt).is_empty(),source_kind+"1-credit corruption still rejects")
  corrupt=twice.duplicate(true);corrupt.parts_retirement.after.credits=str(corrupt.parts_retirement.after.credits)
  check(not Migration.receipt_error(corrupt).is_empty(),source_kind+"numeric string is never accepted as numeric amount")
  corrupt=twice.duplicate(true);corrupt.parts_retirement.after.inventory.beam=true
  check(not Migration.receipt_error(corrupt).is_empty(),source_kind+"boolean count still rejects")
  corrupt=twice.duplicate(true);corrupt.parts_retirement.placements[0].after.rot=0.5
  check(not Migration.receipt_error(corrupt).is_empty(),source_kind+"fractional rotation still rejects")
  corrupt=twice.duplicate(true);corrupt.parts_retirement.controls[0].after.input_a=-1
  check(not Migration.receipt_error(corrupt).is_empty(),source_kind+"wrong direct control still rejects")
  corrupt=twice.duplicate(true);corrupt.parts_retirement.after.extra_field=0
  check(not Migration.receipt_error(corrupt).is_empty(),source_kind+"extra ledger field still rejects")
 print("PARTS_MIGRATION_JSON_ROUNDTRIP_V2 failures=",failures," real_save_paths=UNTOUCHED");quit(1 if failures else 0)
