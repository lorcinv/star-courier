extends SceneTree
## Lead-run fixture only. NOT RUN by author; requires a fresh isolated user dir.
const Econ=preload("res://scripts/economy.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Old=preload("res://scripts/pilot_free_profile_v1.gd")
const Force=preload("res://scripts/pilot_free_profile_v2.gd")
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Migration=preload("res://scripts/parts_migration_v2.gd")
var passed:int=0
var failed:int=0
var craft:Array=[]
var pad:Array=[]

class CommitFault extends "res://scripts/economy.gd":
 var deny_commit:bool=false
 func _commit_shop_save() -> bool:
  if deny_commit:save_error="Injected pre-rename failure";return false
  return super._commit_shop_save()

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Fresh isolated XDG_DATA_HOME required");quit(2);return
 test_preview_cancel_stale();test_commit_restart();test_failure_slots();test_deferred();test_schema();test_starter()
 clean();print("PARTS_RETIREMENT_ECONOMY_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.stringify(JSON.parse_string(JSON.stringify(a,"",true,true)),"",true,true)==JSON.stringify(JSON.parse_string(JSON.stringify(b,"",true,true)),"",true,true),label)
func remove(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for file in directory.get_files():remove(path.path_join(file))
 for child in directory.get_directories():remove(path.path_join(child))
 DirAccess.remove_absolute(path)
func clean() -> void:
 for item in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","parts-retirement-v2","force-offer-upgrade-v2"]:remove("user://"+item)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func slots() -> Array:
 var result:Array=[]
 for path in ["user://savegame.json","user://savegame.backup.json"]:result.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return result
func state(e) -> Dictionary:
 var value:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var item:Variant=e.get(key);value[key]=item.duplicate(true) if item is Dictionary or item is Array else item
 return value
func write(value:Dictionary) -> void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(value,"",true,true));file.close()
func fixture():
 clean();craft=Old.starter_design();pad=Old.starter_launcher()
 craft.append({"id":901,"type":"probe","x":4,"y":2,"rot":1,"param":Parts.defaults("probe"),"input_a":-1,"input_b":-1,"target":-1})
 var e=CommitFault.new();e.enable_free_mode();e.starter_stock(craft,pad)
 e.inventory["probe"]=2;e.inventory["not_gate"]=3
 e.designs={"copy":{"design":craft.duplicate(true),"launcher":pad.duplicate(true)}}
 check(e.save_state(craft,pad,{}),"fixture first durable save")
 e.credits+=1;check(e.save_state(craft,pad,{}),"fixture preserves distinct previous backup")
 return e
func preview(e) -> Dictionary:return e.parts_retirement_preview(craft,pad,{})
func confirm(e,p:Dictionary) -> Dictionary:return e.retire_legacy_parts_and_save(str(p.get("confirmation_token","")),craft,pad,{})
func test_preview_cancel_stale() -> void:
 var e=fixture();var before:Dictionary=state(e);var bytes:Array=slots();var old_craft:Array=craft.duplicate(true)
 var p:Dictionary=preview(e);check(p.get("available",false),"durable old user gets explicit parts preview")
 same(state(e),before,"preview/cancel does not change model");same(slots(),bytes,"preview/cancel preserves both raw slots");same(craft,old_craft,"preview retains caller design")
 check(not DirAccess.dir_exists_absolute("user://parts-retirement-v2"),"preview creates no archive")
 var bad:Dictionary=p.duplicate(true);bad.confirmation_token="stale";check(not confirm(e,bad).ok,"stale confirmation is rejected")
 same(state(e),before,"stale confirmation preserves live model");same(slots(),bytes,"stale confirmation preserves slots")
 craft[0].x+=1;check(not confirm(e,p).ok,"unsaved design change invalidates whole snapshot")
 same(slots(),bytes,"unsaved edit refusal writes no slot")
 craft=old_craft;e.credits+=1;check(e.save_state(craft,pad,{}),"changed credits saved")
 check(not confirm(e,p).ok,"changed durable unrelated money invalidates token")
func test_commit_restart() -> void:
 var e=fixture();var p:Dictionary=preview(e);var bytes:Array=slots();var before:Dictionary=state(e)
 var inventory_alias:Dictionary=e.inventory;var design_alias:Array=craft;var blueprint_alias:Dictionary=e.designs
 var result:Dictionary=confirm(e,p)
 if not result.get("ok",false) or not result.get("changed",false):check(false,"confirmed migration commits: "+str(result));return
 check(result.design.back().id==901 and result.design.back().x==4 and result.design.back().rot==1 and result.design.back().type=="beam","converted placement retains ID/position/rotation")
 check(e.inventory.beam==10 and not e.inventory.has("probe") and not e.inventory.has("not_gate"),"owned total converted once, blueprint not extra property")
 check(e.credits==int(before.credits)+30,"catalog delta paid once")
 same(inventory_alias,before.inventory,"retained old inventory alias is never mutated")
 same(design_alias,craft,"retained old editor alias is never mutated")
 same(blueprint_alias,before.designs,"retained old blueprint alias is never mutated")
 for key in ["contracts","settled_ids","last_settlement","history","review_state","story_state"]:same(e.get(key),before[key],"retirement preserves "+key)
 var folder:String="user://parts-retirement-v2/"+str(e.parts_retirement.source_sha256)
 check(FileAccess.get_file_as_bytes(folder+"/savegame.json")==bytes[0],"raw primary archived byte-for-byte")
 check(FileAccess.get_file_as_bytes(folder+"/savegame.backup.json")==bytes[1],"raw prior backup archived byte-for-byte")
 check(Migration.receipt_error(disk()).is_empty(),"durable receipt and marker validate")
 craft=result.design;pad=result.launcher
 var current:Array=slots();check(not preview(e).get("available",false),"migration has no repeated offer")
 var duplicate:Dictionary=e.retire_legacy_parts_and_save(str(p.confirmation_token),craft,pad,result.settings)
 check(duplicate.get("ok",false) and not duplicate.get("changed",true),"duplicate transaction grants nothing")
 same(slots(),current,"duplicate does not rotate either slot")
 var restored=Econ.new();var loaded:Dictionary=restored.load_state(true)
 check(not restored.review_load_blocked and not loaded.is_empty(),"new receipt loads cleanly")
 same(restored.parts_retirement,e.parts_retirement,"receipt survives restart")
 check(restored.save_state(loaded.design,loaded.launcher,loaded.settings),"ordinary save preserves receipt marker")
 check(Migration.receipt_error(disk()).is_empty(),"ordinary save keeps receipt coherent")
func test_failure_slots() -> void:
 var e=fixture();var p:Dictionary=preview(e);var before:Dictionary=state(e);var bytes:Array=slots();var old_inventory:Dictionary=e.inventory
 e.deny_commit=true;check(not confirm(e,p).ok,"primary commit failure reported")
 same(state(e),before,"failed commit changes no economy field");same(slots(),bytes,"failed commit preserves both durable slots");same(e.inventory,old_inventory,"failed commit retains live inventory")
 e.deny_commit=false;check(confirm(e,p).ok,"same confirmation can safely retry after failure")
 e=fixture();p=preview(e);before=state(e);bytes=slots()
 var blocker=FileAccess.open("user://parts-retirement-v2",FileAccess.WRITE);blocker.store_string("archive blocked");blocker.close()
 check(not confirm(e,p).ok,"archive failure blocks persistence");same(state(e),before,"archive failure changes no state");same(slots(),bytes,"archive failure preserves both slots")
func test_deferred() -> void:
 var e=fixture();check(e.accept_contract("D1-A").ok,"old v1 accepted");check(e.save_state(craft,pad,{}),"old acceptance saved")
 var before:Dictionary=state(e);var bytes:Array=slots();var p:Dictionary=preview(e)
 check(not p.get("available",false) and p.get("deferred",false),"accepted old physics defers retirement")
 same(state(e),before,"accepted old route and apparatus untouched");same(slots(),bytes,"deferred preview is read-only")
 e.mark_cargo_loaded("D1-A");check(e.begin_dispatch(craft,pad).ok,"old dispatch created");check(e.save_state(craft,pad,{}),"old frozen snapshot saved")
 var frozen:Dictionary=e.in_flight.duplicate(true);p=preview(e)
 check(not p.get("available",false) and p.get("deferred",false),"old in-flight snapshot defers retirement")
 same(e.in_flight,frozen,"deferred flight remains exact")
func test_schema() -> void:
 var e=fixture();var result:Dictionary=confirm(e,preview(e))
 if not result.get("ok",false):check(false,"schema fixture migration");return
 var valid:Dictionary=disk()
 for mode in ["missing_receipt","missing_marker","future_marker","bad_delta","bad_id"]:
  var bad:Dictionary=valid.duplicate(true)
  if mode=="missing_receipt":bad.erase(Migration.FIELD)
  elif mode=="missing_marker":bad.settings.erase(Migration.MARKER)
  elif mode=="future_marker":bad.settings[Migration.MARKER]="future-v99"
  elif mode=="bad_delta":bad.parts_retirement.credit_delta+=1
  else:bad.parts_retirement.placements[0].after.id+=1
  write(bad);var bytes:Array=slots();var loaded=Econ.new();loaded.load_state(true)
  check(loaded.review_load_blocked,"corrupt marker/receipt blocks fallback "+mode)
  check(not loaded.save_state(craft,pad,{}),"recovery cannot overwrite "+mode);same(slots(),bytes,"recovery preserves both raw files "+mode)
func test_starter() -> void:
 clean();var e=Econ.new();e.enable_force_mode();var ship:Array=Force.starter_design();var launch:Array=Force.starter_launcher();e.starter_stock(ship,launch)
 check(Policy.sale_kinds().size()==12 and e.day_basic_part_kinds().size()==12,"exact twelve mechanical sale types")
 for kind in e.inventory:check(kind=="cargo" or Policy.is_core(kind),"new inventory has no legacy type "+kind)
 check(e.missing_parts(ship,launch).is_empty(),"new inventory covers ship and actual two-beam pad")
