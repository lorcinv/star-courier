extends SceneTree
## Pure versioned-retirement contract tests; old receipt captured by unchanged v2.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Values=preload("res://scripts/pilot_protected_bird_profile.gd")
const FIXTURE:String="res://tests/fixtures/held-drill-migration/"
var passed:int=0
var failed:int=0
var backups:int=0
var commits:int=0
var saved:Dictionary={}
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:check(Values.same_value(a,b),label)
func read(name:String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE+name))
func roundtrip(s:Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(s,"",true,true))
func part(id:int,kind:String,x:int,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":2,"rot":1,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1}
func mixed() -> Dictionary:
 var s:Dictionary=read("after-drill-held.json")
 s.design.back().input_b=999;s.design.back().target=13
 s.design.append(part(2001,"drill",-3));s.design.append(part(2002,"drill",-2,2003));s.design.append(part(2003,"not_gate",-1))
 s.launcher.append(part(3001,"drill",2,-2))
 s.inventory["drill"]=4;s.inventory["not_gate"]=2
 s.designs["copy:with:colons"]={"design":s.design.duplicate(true),"launcher":s.launcher.duplicate(true)}
 s.designs["second"]={"design":s.design.duplicate(true),"launcher":s.launcher.duplicate(true)}
 return s
func backup(_s:Dictionary) -> Dictionary:backups+=1;return {"ok":true,"source_sha256":"b".repeat(64)}
func persist(s:Dictionary) -> Dictionary:commits+=1;saved=roundtrip(s);return {"ok":Migration.receipt_error(saved).is_empty()}
func deny(_s:Dictionary) -> Dictionary:return {"ok":false}
func find_part(items:Array,id:int) -> Dictionary:
 for p in items:
  if int(p.id)==id:return p
 return {}
func _initialize() -> void:
 for numeric in ["parsed","integer"]:
  var s:Dictionary=mixed()
  if numeric=="integer":
   for p in s.design+s.launcher:
    for key in ["id","x","y","rot","input_a","input_b","target"]:p[key]=int(p[key])
  var before:Dictionary=s.duplicate(true);var plan:Dictionary=Migration.preview(s)
  check(plan.ok and plan.changed,numeric+" mixed old/new fixture is eligible")
  if not plan.ok:print("MIXED_REJECTED ",JSON.stringify(plan));continue
  same(s,before,numeric+" preview retains exact source")
  check(plan.converted_owned=={"not_gate":2,"drill":1},numeric+" only owned legacy gates and unsupported pad drill retire once")
  check(plan.credit_delta==int(Parts.catalog().drill.price)-int(Parts.catalog().beam.price),numeric+" exact catalog delta, no blueprint refund")
  check(plan.before.total_value==plan.after.total_value,numeric+" property and money sum exactly preserved")
  check(plan.candidate.inventory.drill==3,numeric+" all three craft drills stay owned")
  for group in [plan.candidate,plan.candidate.designs["copy:with:colons"],plan.candidate.designs.second]:
   var held:Dictionary=find_part(group.design,1006);var old_held:Dictionary=find_part(before.design,1006).duplicate(true);old_held.input_b=-1
   same(held,old_held,numeric+" held craft drill only loses obsolete input_b, parameter/target/position preserved")
   same(find_part(group.design,2001),find_part(before.design,2001),numeric+" automatic craft drill remains exact")
   var wired:Dictionary=find_part(before.design,2002).duplicate(true);wired.input_a=-1
   same(find_part(group.design,2002),wired,numeric+" external legacy drill wire becomes automatic")
   check(find_part(group.launcher,3001).type=="beam" and find_part(group.launcher,3001).input_a==-1,numeric+" unsupported held launcher drill still retires")
   check(find_part(group.design,2003).type=="beam",numeric+" old logic actually retires")
  var b:int=backups;var c:int=commits
  check(not Migration.transaction(s,"",backup,persist).ok and backups==b and commits==c,numeric+" cancel/missing approval has zero callbacks")
  var changed:Dictionary=s.duplicate(true);changed.credits+=1
  check(not Migration.transaction(changed,plan.confirmation_token,backup,persist).ok and backups==b and commits==c,numeric+" stale whole-source approval cannot execute")
  check(not Migration.transaction(s,plan.confirmation_token,deny,persist).ok and commits==c,numeric+" archive failure blocks commit")
  check(not Migration.transaction(s,plan.confirmation_token,backup,deny).ok,numeric+" persist failure rejects candidate")
  same(s,before,numeric+" all failures preserve caller aliases")
  var result:Dictionary=Migration.transaction(s,plan.confirmation_token,backup,persist)
  check(result.ok and Migration.receipt_error(saved).is_empty(),numeric+" new exact receipt passes actual JSON boundary")
  if not result.ok:continue
  check(saved.parts_retirement.schema=="mechanical-parts-retirement-v3" and saved.settings.parts_retirement_schema=="mechanical-parts-retirement-v3",numeric+" new transaction records explicit new policy version")
  var broken:Dictionary=saved.duplicate(true)
  for row in broken.parts_retirement.controls:
   if row.before.type=="drill" and int(row.before.input_a)==-2:row.after.input_a=-1
  check(Migration.receipt_error(broken)=="incoherent_parts_retirement_change",numeric+" v3 validator rejects held-to-auto corruption")
  broken=saved.duplicate(true)
  for row in broken.parts_retirement.controls:
   if row.before.type=="drill" and int(row.before.input_a)>=0:row.after.input_a=-2
  check(Migration.receipt_error(broken)=="incoherent_parts_retirement_change",numeric+" v3 validator rejects invented held mode on legacy wire")
  broken=saved.duplicate(true);broken.settings.parts_retirement_schema="mechanical-parts-retirement-v2"
  check(not Migration.receipt_error(broken).is_empty(),numeric+" schema/marker cross-version mismatch fails closed")
  b=backups;c=commits
  check(Migration.transaction(saved,plan.confirmation_token,backup,persist).get("duplicate",false) and backups==b and commits==c,numeric+" new receipt is idempotent")
 var invalid:Dictionary=mixed();invalid.design[9].param=2.125
 check(Migration.preview(invalid).get("reason")=="out_of_range_installed_parameter","nondefault drill parameter remains fail-closed, not normalized or silently permitted")
 var legacy:Dictionary=read("legacy-v2-receipt.json");var original:Dictionary=legacy.duplicate(true)
 check(Migration.receipt_error(legacy).is_empty(),"actual historical v2 receipt remains valid")
 for iteration in 3:legacy=roundtrip(legacy);check(Migration.receipt_error(legacy).is_empty(),"historical v2 receipt roundtrip "+str(iteration))
 same(legacy,original,"historical receipt and marker remain exact across repeated roundtrips")
 var b:int=backups;var c:int=commits
 check(Migration.transaction(legacy,"",backup,persist).get("duplicate",false) and backups==b and commits==c,"old completed retirement remains duplicate with no callbacks")
 var forged:Dictionary=legacy.duplicate(true)
 for row in forged.parts_retirement.controls:
  if row.before.type=="drill" and int(row.before.input_a)==-2:row.after.input_a=-2
 check(Migration.receipt_error(forged)=="incoherent_parts_retirement_change","v2 validator still demands historical forced-auto control rows")
 var old_source:Dictionary=read("legacy-v2-source.json");var old_token:String=read("legacy-v2-plan.json").confirmation_token
 var rejected:Dictionary=Migration.transaction(old_source,old_token,backup,persist)
 check(not rejected.ok and rejected.reason=="confirmation_stale_or_missing" and backups==b and commits==c,"historical pending confirmation cannot approve new policy")
 for kind in ["accepted","in_flight"]:
  var deferred:Dictionary=mixed()
  deferred.active_contract_id="old";deferred.contracts=[{"contract_id":"old","status":kind,"control_version":"pilot-free-v1"}]
  if kind=="in_flight":deferred.in_flight={"contract_id":"old","control_version":"pilot-free-v1","design":deferred.design.duplicate(true),"opaque_legacy_state":[1,2,3]}
  var before:Dictionary=deferred.duplicate(true);var plan:Dictionary=Migration.preview(deferred)
  check(plan.ok and plan.get("deferred",false) and not plan.changed,kind+" legacy state defers")
  var result:Dictionary=Migration.transaction(deferred,"unapproved",backup,persist)
  check(result.ok and result.get("deferred",false) and backups==b and commits==c,kind+" deferral never archives or writes")
  same(deferred,before,kind+" entire legacy save remains exact")
 print("HELD_DRILL_MIGRATION_DEV05 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
