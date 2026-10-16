extends SceneTree
## Real durable Economy + HUD entry seam. Only a fresh explicitly isolated profile.
const Econ=preload("res://scripts/economy.gd")
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Values=preload("res://scripts/pilot_protected_bird_profile.gd")
const HUD=preload("res://scripts/game_hud.gd")
const FIXTURE:String="res://tests/fixtures/held-drill-migration/"
var passed:int=0
var failed:int=0
var craft:Array=[]
var pad:Array=[]
var settings:Dictionary={}
class FaultEconomy extends "res://scripts/economy.gd":
 var deny_commit:bool=false
 func _commit_shop_save() -> bool:
  if deny_commit:save_error="Injected held migration pre-rename failure";return false
  return super._commit_shop_save()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:check(Values.same_value(a,b),label)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func slots() -> Array:return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func state(e) -> Dictionary:
 var result:Dictionary={"craft":craft.duplicate(true),"pad":pad.duplicate(true),"settings":settings.duplicate(true)}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var v:Variant=e.get(key);result[key]=v.duplicate(true) if v is Dictionary or v is Array else v
 return result
func install(name:String):
 for row in [["savegame.json",name],["savegame.backup.json","after-drill-attach-auto.json"]]:
  var file=FileAccess.open("user://"+row[0],FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE+row[1]));file.close()
 var bytes:Array=slots();var e=FaultEconomy.new();var loaded:Dictionary=e.load_state(true)
 check(not e.review_load_blocked and not loaded.is_empty(),name+" real Economy load is valid")
 if loaded.is_empty():return null
 craft=loaded.design;pad=loaded.launcher;settings=loaded.settings
 same(slots(),bytes,name+" load writes no durable slot")
 return e
func preview(e) -> Dictionary:return e.parts_retirement_preview(craft,pad,settings)
func confirm(e,p:Dictionary) -> Dictionary:return e.retire_legacy_parts_and_save(p.get("confirmation_token",""),craft,pad,settings)
func part(id:int,kind:String,x:int,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":2,"rot":1,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1}
func preserve_case(name:String) -> void:
 var folder:String="user://evidence/"+name;DirAccess.make_dir_recursive_absolute(folder)
 for slot in ["savegame.json","savegame.backup.json"]:
  var f=FileAccess.open(folder+"/"+slot,FileAccess.WRITE);f.store_buffer(FileAccess.get_file_as_bytes("user://"+slot));f.close()
func hud_entry(p:Dictionary) -> int:
 var hud=HUD.new();var box=VBoxContainer.new();hud.state={"free_order_upgrade":{"parts":p}}
 hud._parts_retirement_entry(box)
 var count:int=box.get_child_count();box.free();hud.free();return count
func _initialize() -> void:
 if OS.get_environment("SC_HELD_MIGRATION_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Requires SC_HELD_MIGRATION_ISOLATED=1 and a fresh empty XDG_DATA_HOME");quit(2);return
 for name in ["after-drill-attach-auto.json","after-drill-held.json"]:
  var e=install(name)
  if e==null:continue
  var before:Dictionary=state(e);var bytes:Array=slots();var p:Dictionary=preview(e)
  check(not p.get("available",false) and p.get("reason","").is_empty(),name+" valid durable no-op suppresses false offer")
  check(hud_entry(p)==0,name+" actual HUD creates no cleanup button")
  same(state(e),before,name+" inspection leaves all model fields exact");same(slots(),bytes,name+" inspection creates no write")
  check(not DirAccess.dir_exists_absolute("user://parts-retirement-v2"),name+" no unapproved raw archive")
  preserve_case(name.get_basename())
 var e=install("after-drill-held.json")
 if e!=null:
  craft.back().input_b=999;craft.append(part(2001,"drill",-3));craft.append(part(2002,"not_gate",-2));pad.append(part(3001,"drill",2,-2))
  e.inventory["drill"]=3;e.inventory["not_gate"]=2;e.designs["copy"]={"design":craft.duplicate(true),"launcher":pad.duplicate(true)}
  check(e.save_state(craft,pad,settings),"mixed fixture durable save")
  e.credits+=1;check(e.save_state(craft,pad,settings),"mixed fixture distinct previous backup")
  var before:Dictionary=state(e);var bytes:Array=slots();var p:Dictionary=preview(e)
  check(p.get("available",false) and p.get("converted_count")==3,"mixed save offers only real owned cleanup")
  check(hud_entry(p)==1,"actual HUD still offers necessary mixed cleanup")
  same(state(e),before,"preview/cancel changes no live model");same(slots(),bytes,"preview/cancel writes neither slot")
  check(not DirAccess.dir_exists_absolute("user://parts-retirement-v2"),"preview/cancel creates no archive")
  var bad:Dictionary=p.duplicate(true);bad.confirmation_token="stale"
  check(not confirm(e,bad).ok,"bad confirmation refused")
  same(slots(),bytes,"bad confirmation preserves both slots")
  craft.back().rot=2
  check(not confirm(e,p).ok,"unsaved edit invalidates whole-source consent")
  craft.back().rot=1
  same(slots(),bytes,"unsaved stale edit writes no slots")
  var inventory_alias:Dictionary=e.inventory;var blueprint_alias:Dictionary=e.designs;var craft_alias:Array=craft
  e.deny_commit=true;var denied:Dictionary=confirm(e,p)
  check(not denied.ok and denied.get("reason")=="atomic_save_failed","injected primary commit failure is reported")
  same(state(e),before,"failed save keeps all economy/editor fields exact");same(slots(),bytes,"failed save preserves both raw slots")
  same(inventory_alias,e.inventory,"failed save keeps inventory alias exact")
  preserve_case("failed-save-originals")
  var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes[0]);var sha:String=h.finish().hex_encode()
  var archive:String="user://parts-retirement-v2/"+sha
  check(FileAccess.get_file_as_bytes(archive+"/source.json")==bytes[0],"explicit transaction archives exact raw source even on commit failure")
  check(FileAccess.get_file_as_bytes(archive+"/savegame.json")==bytes[0] and FileAccess.get_file_as_bytes(archive+"/savegame.backup.json")==bytes[1],"both raw slots archived byte-for-byte")
  e.deny_commit=false;var result:Dictionary=confirm(e,p)
  check(result.ok and result.get("changed",false),"same approved source safely retries staged commit")
  if result.ok and result.get("changed",false):
   check(int(result.design[9].input_a)==-2 and int(result.design[9].input_b)==-1,"committed mixed held drill stays held")
   check(int(result.design[10].input_a)==-1,"committed automatic drill remains automatic")
   check(result.launcher.back().type=="beam" and not e.inventory.has("not_gate"),"unsupported pad drill and logic actually retire")
   check(e.credits==int(before.credits)+int(Parts.catalog().drill.price)-int(Parts.catalog().beam.price),"funds pay only exact owned conversion delta")
   same(inventory_alias,before.inventory,"successful swap does not mutate retained old inventory alias")
   same(blueprint_alias,before.designs,"successful swap does not mutate retained blueprint alias")
   same(craft_alias,before.craft,"successful swap does not mutate caller craft alias")
   for key in ["contracts","settled_ids","history","review_state","in_flight"]:same(e.get(key),before[key],"migration preserves unrelated "+key)
   craft=result.design;pad=result.launcher;settings=result.settings
   check(Migration.receipt_error(disk()).is_empty() and e.parts_retirement.schema=="mechanical-parts-retirement-v3","new disk receipt exact and versioned")
   var stable:Array=slots();check(not preview(e).get("available",false),"successful cleanup has no repeat offer")
   check(confirm(e,p).get("duplicate",false),"confirmed duplicate grants nothing")
   same(slots(),stable,"duplicate does not rotate raw slots")
   var restored=Econ.new();var loaded:Dictionary=restored.load_state(true)
   check(not restored.review_load_blocked and not loaded.is_empty(),"v3 disk reloads")
   check(restored.save_state(loaded.design,loaded.launcher,loaded.settings),"ordinary save retains v3 receipt")
   check(disk().settings.parts_retirement_schema=="mechanical-parts-retirement-v3" and Migration.receipt_error(disk()).is_empty(),"ordinary v3 save retains exact schema guard")
   preserve_case("committed-v3")
 e=install("legacy-v2-receipt.json")
 if e!=null:
  var original:Dictionary=disk().parts_retirement.duplicate(true)
  for iteration in 3:
   check(e.save_state(craft,pad,settings),"historical v2 ordinary save "+str(iteration))
   check(disk().settings.parts_retirement_schema=="mechanical-parts-retirement-v2","historical marker not silently upgraded "+str(iteration))
   same(disk().parts_retirement,original,"historical receipt untouched "+str(iteration))
   var loader=Econ.new();var loaded:Dictionary=loader.load_state(true)
   check(not loader.review_load_blocked and not loaded.is_empty(),"historical v2 restarts "+str(iteration))
   if loaded.is_empty():break
   e=loader;craft=loaded.design;pad=loaded.launcher;settings=loaded.settings
   check(not preview(e).get("available",false),"historical receipt remains duplicate "+str(iteration))
  preserve_case("historical-v2-roundtrip")
 print("HELD_DRILL_RETIREMENT_ECONOMY_DEV05 passed=%d failed=%d native_ui=NOT_RUN retained_profile=%s"%[passed,failed,OS.get_user_data_dir()]);quit(1 if failed else 0)
