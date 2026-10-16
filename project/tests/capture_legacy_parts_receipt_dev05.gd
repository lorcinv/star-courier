extends SceneTree
## Run ONLY against unmodified source02 retirement code; keep actual old output.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
func backup(_snapshot:Dictionary) -> Dictionary:return {"ok":true,"source_sha256":"a".repeat(64)}
func persist(_snapshot:Dictionary) -> Dictionary:return {"ok":true}
func _initialize() -> void:
 if Migration.SCHEMA!="mechanical-parts-retirement-v2":printerr("Requires historical source02 runtime");quit(2);return
 var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/held-drill-migration/after-drill-held.json"))
 snapshot.design.back().input_b=999
 snapshot.inventory["not_gate"]=2
 var gate:Dictionary={"id":999,"type":"not_gate","x":4,"y":2,"rot":0,"param":Parts.defaults("not_gate"),"input_a":-1,"input_b":-1,"target":-1}
 snapshot.design.append(gate)
 snapshot.designs["historical"]={"design":snapshot.design.duplicate(true),"launcher":snapshot.launcher.duplicate(true)}
 var plan:Dictionary=Migration.preview(snapshot)
 var result:Dictionary=Migration.transaction(snapshot,plan.get("confirmation_token",""),backup,persist)
 if not result.get("ok",false):printerr(JSON.stringify(result));quit(1);return
 for pair in [["legacy-v2-source.json",snapshot],["legacy-v2-receipt.json",result.candidate],["legacy-v2-plan.json",{"confirmation_token":plan.confirmation_token,"controls":plan.controls,"placements":plan.placements}]]:
  var f=FileAccess.open("res://tests/fixtures/held-drill-migration/"+str(pair[0]),FileAccess.WRITE);f.store_string(JSON.stringify(pair[1],"  ",true,true)+"\n");f.close()
 print("LEGACY_V2_CAPTURE schema=",result.receipt.schema," controls=",result.receipt.controls.size()," valid=",Migration.receipt_error(result.candidate).is_empty());quit(0)
