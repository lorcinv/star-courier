extends SceneTree
## Pure transaction/failure tests. NOT RUN by author. No player save paths.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var failures:int=0
var backups:int=0
var commits:int=0
var saved:Dictionary={}
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":0,"rot":1,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1}
func source() -> Dictionary:
 var craft:Array=[part(1,"cargo",0),part(2,"not_gate",1),part(3,"teleporter",2,2),part(4,"spring",3)]
 var pad:Array=[part(11,"shield",0),part(12,"battery",1)]
 return {"credits":75,"inventory":{"cargo":1,"not_gate":3,"teleporter":1,"spring":2,"shield":1,"battery":1},"design":craft,"launcher":pad,"designs":{"one":{"design":craft.duplicate(true),"launcher":pad.duplicate(true)},"two":{"design":craft.duplicate(true),"launcher":pad.duplicate(true)}},"settings":{},"in_flight":{},"contracts":[],"active_contract_id":""}
func backup(_snapshot:Dictionary) -> Dictionary:
 backups+=1;return {"ok":true,"source_sha256":"a".repeat(64)}
func commit(candidate:Dictionary) -> Dictionary:
 commits+=1;saved=candidate.duplicate(true);return {"ok":true}
func deny(_candidate:Dictionary) -> Dictionary:return {"ok":false}
func _initialize() -> void:
 var original:Dictionary=source();var frozen:Dictionary=original.duplicate(true)
 var plan:Dictionary=Migration.preview(original)
 if not bool(plan.get("ok",false)):
  print("MIGRATION_PREVIEW_REJECTED ",JSON.stringify(plan));check(false,"original asset fixture must produce a valid preview");quit(1);return
 check(plan.ok and plan.changed and original==frozen,"preview never mutates supplied save")
 check(plan.credit_delta==65 and plan.converted_owned=={"not_gate":3,"spring":1,"shield":1},"retired total counted once; active context conversions counted once")
 check(plan.candidate.inventory.keys().all(func(kind):return kind is String),"authored beam inventory key remains String, never dot-created StringName")
 check(plan.candidate.inventory.get("beam")==5 and plan.candidate.inventory.get("spring")==1,"inventory remains total owned including installed units")
 check(plan.before.total_value==plan.after.total_value and plan.after.credits==140,"full catalog property value is preserved")
 check(plan.candidate.design[1].id==2 and plan.candidate.design[1].x==1 and plan.candidate.design[1].rot==1,"converted installed part retains ID, cell and rotation")
 check(plan.candidate.design[2].input_a==-2 and plan.candidate.design[2].id==3,"legacy signal input is explicitly migrated to direct manual control")
 check(plan.candidate.designs.one.design[1].type=="beam" and plan.candidate.designs.two.design[1].type=="beam","all blueprint references migrate without extra property payments")
 var denied:Dictionary=Migration.transaction(original,"",backup,commit)
 check(not denied.ok and backups==0 and commits==0 and original==frozen,"missing confirmation performs no backup or mutation")
 var changed:Dictionary=original.duplicate(true);changed.credits+=1
 denied=Migration.transaction(changed,plan.confirmation_token,backup,commit)
 check(not denied.ok and backups==0 and commits==0,"stale whole-snapshot token cannot approve changed assets")
 denied=Migration.transaction(original,plan.confirmation_token,deny,commit)
 check(not denied.ok and commits==0 and original==frozen,"backup failure prevents commit")
 denied=Migration.transaction(original,plan.confirmation_token,backup,deny)
 check(not denied.ok and original==frozen,"commit failure returns no candidate and preserves caller state")
 var success:Dictionary=Migration.transaction(original,plan.confirmation_token,backup,commit)
 if not bool(success.get("ok",false)):
  print("MIGRATION_COMMIT_REJECTED ",JSON.stringify(success));check(false,"confirmed asset fixture must commit");quit(1);return
 check(success.ok and original==frozen and saved==success.candidate,"commit returns a detached candidate only after persistence")
 check(Migration.receipt_error(success.candidate).is_empty(),"one-time receipt and downgrade marker validate")
 var second:Dictionary=Migration.transaction(success.candidate,plan.confirmation_token,backup,commit)
 check(second.ok and bool(second.get("duplicate",false)) and not second.changed and commits==1,"committed receipt makes retry idempotent")
 var malformed:Dictionary=success.candidate.duplicate(true);malformed.erase(Migration.FIELD)
 check(not Migration.preview(malformed).ok,"retained settings marker detects missing downgraded receipt")
 malformed=success.candidate.duplicate(true);malformed.parts_retirement.converted_owned.not_gate=4
 check(not Migration.preview(malformed).ok,"receipt rejects double-refund ledger")
 var flight:Dictionary=source();flight.in_flight={"control_version":"pilot-free-v1","design":flight.design.duplicate(true)}
 var flight_before:Dictionary=flight.duplicate(true);var waiting:Dictionary=Migration.preview(flight)
 check(waiting.ok and waiting.deferred and flight==flight_before,"committed old replay is deferred unchanged")
 var accepted:Dictionary=source();accepted.active_contract_id="old";accepted.contracts=[{"contract_id":"old","status":"accepted","control_version":"pilot-free-v1"}]
 check(Migration.preview(accepted).deferred,"accepted old route is deferred until its delivery ends")
 var unknown:Dictionary=source();unknown.inventory["future_widget"]=1
 check(not Migration.preview(unknown).ok,"unknown future property fails closed without deletion")
 var deficit:Dictionary=source();deficit.inventory.not_gate=0
 check(not Migration.preview(deficit).ok,"installed count exceeding owned total never triggers guessed refund")
 var duplicate_id:Dictionary=source();duplicate_id.launcher[0].id=2
 check(not Migration.preview(duplicate_id).ok,"duplicate installed ID stops transaction before mutation")
 var invalid:Dictionary=source();invalid.design[1].rot=4
 check(not Migration.preview(invalid).ok,"out-of-range rotation fails closed")
 invalid=source();invalid.design[1].param=NAN
 check(not Migration.preview(invalid).ok,"nonfinite part parameter fails closed")
 invalid=source();invalid.design[2].input_a=0.5
 check(not Migration.preview(invalid).ok,"fractional wire reference fails closed")
 invalid=source();invalid.design[1].erase("target")
 check(not Migration.preview(invalid).ok,"missing original part field is preserved via rejection")
 invalid=source();invalid.contracts={}
 check(not Migration.preview(invalid).ok,"dictionary masquerading as contracts array is rejected")
 invalid=source();invalid.contracts=[null]
 check(not Migration.preview(invalid).ok,"malformed contract entry is rejected before iteration")
 invalid=source();invalid.inventory["not_gate"]=true
 check(not Migration.preview(invalid).ok,"boolean inventory quantity remains invalid")
 malformed=success.candidate.duplicate(true)
 for row in malformed.parts_retirement.controls:
  if row.path=="design" and row.id==3:row.after.input_a=-1
 check(not Migration.receipt_error(malformed).is_empty(),"receipt requires exact manual binding, not arbitrary minus1 or minus2")
 malformed=success.candidate.duplicate(true);malformed.parts_retirement.placements[0].path="somewhere"
 check(not Migration.receipt_error(malformed).is_empty(),"receipt only accepts exact craft/pad/blueprint paths")
 print("PARTS_MIGRATION_V2 failures=",failures," filesystem_archive=NOT_RUN native_gui=NOT_RUN");quit(1 if failures else 0)
