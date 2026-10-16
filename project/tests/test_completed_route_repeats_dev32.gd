extends Node
## Narrow authoring and economic-boundary checks. Native input saves are copied
## unchanged; normal close/open creates D7/D8. Settlement telemetry and portal
## witness below are explicitly model fixtures, not another physical/GUI flight.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
var sources:Dictionary={}
var raw:Dictionary={}
var records:Array=[]
func check(ok:bool,label:String)->bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func same(a:Variant,b:Variant,label:String)->bool:
 return check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
func copy_seed(variable:String):
 clear_files();var path:String=OS.get_environment(variable)
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path);sources[path]=bytes
 raw=JSON.parse_string(bytes.get_string_from_utf8())
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked,"native input loads without migration "+variable)
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"loading does not rewrite native input copy")
 return e
func next_day(e)->bool:
 return check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"ordinary saved close/open generates day %d"%e.day)
func offer_check(e,level:int,b_level:int,progression:bool=false)->void:
 var a:Dictionary=e.contracts[0];var b:Dictionary=e.contracts[1]
 check(a.contract_id=="D%d-A"%e.day and a.chapter_level==level and b.contract_id=="D%d-B"%e.day and b.chapter_level==b_level,"A/B level and identity day %d"%e.day)
 check(a.chapter_progression==progression and not b.chapter_progression and not a.recovery_offer and not b.recovery_offer,"normal progression flags day %d"%e.day)
 check(Chapter.route_error(a).is_empty() and Chapter.route_error(b).is_empty() and a.control_version==Chapter.authored_version_for_level(level),"new quotes retain valid current versions day %d"%e.day)
func fixture_telemetry(e)->Dictionary:
 var order:Dictionary=e.active_contract()
 var result:Dictionary={"control_version":order.control_version,"integrity":0.875,"delivery_integrity":0.875,"energy_used":123.4,"ammo_cost":1.2,"repair_cost":2.2,"lost_cost":3.2}
 if Chapter.is_rift_version(order.control_version):
  var ids:Array=[];var cargo:Array=[]
  for part in e.in_flight.design:
   ids.append(int(part.id))
   if part.type=="cargo":cargo.append(int(part.id))
  var portal:Dictionary=order.rift_portal
  var from:Array=portal.entry.duplicate();var to:Array=[float(portal.exit[0])+1.5+float(portal.margin),float(portal.exit[1])]
  result.merge({"pilot_tick":120,"required_portal_id":order.required_portal_id,"portal_crossing_tick":40,"region":"greenhouse","portal_crossings":[{"portal_id":order.required_portal_id,"tick":40,"cargo_ids":cargo,"part_ids":ids,"from":from,"to":to,"body_radius":1.5,"margin":portal.margin}]})
 return result
func settle_repeat_fixture(e)->void:
 var id:String="D%d-A"%e.day
 var chapter:Dictionary=e.delivery_chapter_state.duplicate(true);var ledger:Dictionary=e.settled_ids.duplicate(true)
 var inventory:Dictionary=e.inventory.duplicate(true);var research:int=e.research
 var tier:int=e.workshop_tier;var credits:int=e.credits;var offered:Dictionary=e.contract_by_id(id).duplicate(true)
 e.ensure_contracts();same(e.contract_by_id(id),offered,"displayed repeat cannot reroll "+id)
 if not check(e.accept_contract_and_save(id,raw.design,raw.launcher,raw.settings).ok and e.mark_cargo_loaded(id).ok,"normal accept and cargo load "+id):return
 var accepted:Dictionary=e.active_contract().duplicate(true)
 e.ensure_contracts();same(e.active_contract(),accepted,"accepted repeat cannot reroll "+id)
 if not check(e.begin_dispatch(raw.design,raw.launcher,raw.settings.launch_settings).ok,"normal dispatch freezes repeat "+id):return
 var in_flight:Dictionary=e.in_flight.duplicate(true);e.ensure_contracts()
 same(e.in_flight,in_flight,"in-flight repeat cannot reroll "+id)
 if not check(e.save_state(raw.design,raw.launcher,raw.settings),"repeat dispatch saves "+id):return
 var resumed=Econ.new();resumed.load_state();resumed.enable_story_mode()
 check(not resumed.review_load_blocked,"repeat dispatch reopens "+id)
 same(resumed.in_flight,in_flight,"every frozen dispatch field survives reload "+id)
 same(resumed.active_contract(),e.active_contract(),"accepted contract survives reload "+id)
 # Model boundary fixture only. No simulated flight or physical success claim.
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation");e.in_flight.ticks=60;e.in_flight.elapsed=1.0
 var telemetry:Dictionary=fixture_telemetry(e);var quote:Dictionary=e.estimate_delivery(e.active_contract(),telemetry,1.0,true)
 check(quote.energy==4 and quote.ammo==2 and quote.repairs==3 and quote.lost==4 and quote.compensation==Chapter.cargo_damage(int(offered.cargo_value),0.875),"repeat uses unchanged rounded actual fees "+id)
 check(quote.income==offered.reward and quote.profit==int(offered.reward)-int(quote.actual_costs),"repeat pays normal fare less full costs "+id)
 check(e.credits==credits and e.settled_ids==ledger,"trial estimate cannot settle or award progress "+id)
 if not check(e.settle_contract_and_save(id,telemetry,1.0,true,raw.design,raw.launcher,raw.settings).ok,"model fixture settles through real saved transaction "+id):return
 check(e.credits==credits+int(quote.profit) and not e.last_settlement.chapter_progression and not e.last_settlement.level_completed,"repeat charges and pays once without chapter completion "+id)
 same(e.delivery_chapter_state,chapter,"repeat preserves exact five completion receipts "+id)
 same(e.inventory,inventory,"repeat grants no inventory "+id);same(e.research,research,"repeat grants no research "+id)
 check(e.workshop_tier==tier and Chapter.receipt_error(e.last_settlement).is_empty(),"repeat keeps workshop tier and valid historical receipt "+id)
 for key in ledger:same(e.settled_ids[key],ledger[key],"historical receipt remains exact "+str(key))
 var after=Econ.new();after.load_state();after.enable_story_mode()
 check(not after.review_load_blocked and after.credits==e.credits and after.in_flight.is_empty(),"saved repeat reopens with exact balance and empty dispatch "+id)
 same(after.delivery_chapter_state,chapter,"five-complete state survives repeat save "+id)
 check(not after.settle_contract(id,telemetry,1.0,true).ok and after.credits==e.credits,"repeated settlement cannot pay again "+id)
 records.append({"contract_id":id,"level":offered.chapter_level,"scope":"model telemetry and portal witness; not physical or native flight","income":quote.income,"actual_costs":quote.actual_costs,"profit":quote.profit,"credits_before":credits,"credits_after":e.credits,"chapter_progression":false,"level_completed":false})
func completed_native()->void:
 var e=copy_seed("COURIER_NATIVE_COMPLETED_SAVE")
 check(e.day==6 and e.credits==1799 and e.delivery_chapter_state.unlocked_level==6 and e.delivery_chapter_status().complete,"actual dev31 day6 has all five receipt-backed completions")
 same(e.contracts,raw.contracts,"actual old displayed day6 batch stays exact")
 same(e.settled_ids,raw.settled_ids,"loading preserves historical native receipts")
 if not next_day(e):return
 offer_check(e,4,2);settle_repeat_fixture(e)
 if not next_day(e):return
 offer_check(e,5,3);settle_repeat_fixture(e)
 if not next_day(e):return
 offer_check(e,4,1)
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 same(saved.keys(),raw.keys(),"repeat policy adds no top-level save field or migration")
 same(saved.delivery_chapter_state,raw.delivery_chapter_state,"normal D7 D8 repeats leave native chapter state exact")
func debt_and_completion_guards()->void:
 var e=copy_seed("COURIER_NATIVE_COMPLETED_SAVE");var displayed:Array=e.contracts.duplicate(true)
 # Explicit isolated economic-boundary fixtures, never source-save mutations.
 e.credits=-1;e.ensure_contracts();same(e.contracts,displayed,"debt cannot rewrite an already displayed native batch")
 if not next_day(e):return
 check(e.day==7 and e.contracts[0].chapter_level==1 and e.contracts[1].chapter_level==1 and e.contracts[0].recovery_offer and e.contracts[1].recovery_offer,"completed but indebted next day offers two recovery light jobs")
 check(not e.contracts[0].chapter_progression and not e.contracts[1].chapter_progression,"debt jobs cannot re-complete chapters")
 var debt_batch:Array=e.contracts.duplicate(true);e.credits=0;e.ensure_contracts()
 same(e.contracts,debt_batch,"clearing debt cannot rewrite displayed recovery batch")
 if not next_day(e):return
 offer_check(e,5,3)
 check(e.credits==0,"zero balance qualifies without subsidy")
 var invalid=Econ.new();invalid.flight_mode=Chapter.VERSION;invalid.day=7;invalid.credits=0
 invalid.delivery_chapter_state=raw.delivery_chapter_state.duplicate(true)
 invalid.ensure_contracts()
 check(invalid.contracts.is_empty() and not invalid.load_notice.is_empty(),"unbacked unlocked6 cannot create completed-route repeats")
func old_completed_batch()->void:
 # Source was produced by exact dev31, using the native day6 copy and its
 # normal close/open API. It is not a hand-authored incompatible day7 order.
 var e=copy_seed("COURIER_OLD_COMPLETED_BATCH")
 check(e.day==7 and e.contracts[0].chapter_level==5 and not e.contracts[0].chapter_progression,"pre-dev32 completed odd-day fifth offer remains fifth")
 same(e.contracts,raw.contracts,"every pre-dev32 displayed batch field remains frozen")
 e.ensure_contracts();same(e.contracts,raw.contracts,"old odd-day display cannot become new moon quote")
 check(e.accept_contract_and_save("D7-A",raw.design,raw.launcher,raw.settings).ok and e.mark_cargo_loaded("D7-A").ok,"old completed fifth quote accepts normally")
 var accepted:Dictionary=e.active_contract().duplicate(true)
 e.ensure_contracts();same(e.active_contract(),accepted,"old accepted fifth quote is not upgraded to moon")
 if not check(e.begin_dispatch(raw.design,raw.launcher,raw.settings.launch_settings).ok,"old completed fifth quote dispatches under its own frozen protocol"):return
 var frozen:Dictionary=e.in_flight.duplicate(true)
 check(e.save_state(raw.design,raw.launcher,raw.settings),"old completed fifth dispatch saves")
 var loaded=Econ.new();loaded.load_state();loaded.ensure_contracts()
 check(not loaded.review_load_blocked,"old completed fifth dispatch remains loadable")
 same(loaded.in_flight,frozen,"old odd-day in-flight fifth route survives reload byte-equivalent")
func unfinished_native()->void:
 var e=copy_seed("COURIER_NATIVE_MOON_SAVE")
 check(e.delivery_chapter_state.unlocked_level==5 and not e.delivery_chapter_status().complete,"real moon-only player is not five-complete")
 if not next_day(e):return
 offer_check(e,5,1,true)
 if not next_day(e):return
 offer_check(e,5,2,true)
 check(not e.delivery_chapter_status().complete,"odd day keeps unfinished fifth progression instead of moon repeat")
func run()->void:
 if OS.get_environment("SC_COMPLETED_REPEATS_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 for variable in ["COURIER_NATIVE_COMPLETED_SAVE","COURIER_NATIVE_MOON_SAVE","COURIER_OLD_COMPLETED_BATCH"]:
  if not FileAccess.file_exists(OS.get_environment(variable)):printerr("Missing read-only source "+variable);get_tree().quit(2);return
 completed_native();debt_and_completion_guards();old_completed_batch();unfinished_native()
 check(records.size()==2,"both advanced-route model settlements completed")
 for path in sources:check(FileAccess.get_file_as_bytes(path)==sources[path],"native source remains byte-identical "+str(path))
 clear_files();print("COMPLETED_ROUTE_REPEATS_DEV32_RECORDS ",JSON.stringify(records))
 print("COMPLETED_ROUTE_REPEATS_DEV32 passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 get_tree().quit(0 if failed==0 else 1)
