extends SceneTree
## Regression from the native inspector saves. Same checks run before/after fix.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Values=preload("res://scripts/pilot_protected_bird_profile.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:
 for name in ["after-drill-attach-auto.json","after-drill-held.json"]:
  var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/held-drill-migration/"+name))
  var original:Dictionary=snapshot.duplicate(true)
  var plan:Dictionary=Migration.preview(snapshot)
  check(plan.get("ok",false),name+" native save validates")
  check(not plan.get("changed",true),name+" no fake legacy cleanup offer")
  check(Values.same_value(snapshot,original),name+" preview is read-only")
  if plan.has("candidate"):
   check(Values.same_value(plan.candidate,original),name+" all saved fields preserved")
  print("NATIVE_REPRO ",JSON.stringify({"fixture":name,"changed":plan.get("changed"),"controls":plan.get("controls"),"credit_delta":plan.get("credit_delta")}))
 print("HELD_DRILL_MIGRATION_REPRO_DEV05 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
