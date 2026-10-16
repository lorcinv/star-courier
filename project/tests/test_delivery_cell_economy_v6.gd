extends SceneTree
## Version/authoring boundary only. Native pre-v6 saves are copied, never edited.
## Physical coasting/ejection invoices are exercised by the separate focused test.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const V6=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Receipt=preload("res://scripts/flight_receipt.gd")
var passed:int=0
var failed:int=0
var frozen_sources:Dictionary={}
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String)->void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func remove_tree(path:String)->void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var dir=DirAccess.open(path)
 for name in dir.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in dir.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:remove_tree("user://"+name)
func copy_native(variable:String)->Dictionary:
 clear_files();var path:String=OS.get_environment(variable);var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path);frozen_sources[path]=bytes
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 return JSON.parse_string(bytes.get_string_from_utf8())
func telemetry(version:String,integrity:float=1.0)->Dictionary:
 return {"control_version":version,"integrity":integrity,"delivery_integrity":integrity,"energy_used":120.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0}
func capture(e)->Dictionary:
 var out:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var v:Variant=e.get(key);out[key]=v.duplicate(true) if v is Dictionary or v is Array else v
 return out
func begin(e,id:String,ship:Array,pad:Array)->void:
 check(e.accept_contract(id).ok,"accept normal offered "+id);e.mark_cargo_loaded(id)
 check(e.begin_dispatch(ship,pad,{"angle_degrees":0.0,"power_fraction":0.2}).ok,"dispatch freezes actual order version")
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
func test_frozen_native_and_new_day()->void:
 for variable in ["COURIER_NATIVE_MOON_SAVE","COURIER_NATIVE_RIFT_SAVE","COURIER_NATIVE_RIFT_FLIGHT"]:
  var raw:Dictionary=copy_native(variable);var before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  check(Chapter.saved_error(raw).is_empty(),"pre-v6 ledger and portal evidence remain valid "+variable)
  var e=Econ.new();e.load_state();e.enable_story_mode()
  check(not e.review_load_blocked,"native old identity loads "+variable)
  same(e.contracts,raw.contracts,"displayed/accepted orders are never reauthored "+variable)
  same(e.in_flight,raw.in_flight,"committed input/physics version stays exact "+variable)
  same(e.settled_ids,raw.settled_ids,"old paid receipts retain their amounts and versions "+variable)
  check(FileAccess.get_file_as_bytes("user://savegame.json")==before,"Continue does not rewrite source copy "+variable)
  if not e.in_flight.is_empty():
   check(e.in_flight.control_version=="pilot-rift-v5" and Econ.replay_protocol_error(e.in_flight).is_empty(),"old portal-warning replay stays v5")
   continue
  check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"only normal new day selects v6 author")
  check(e.contracts[0].control_version=="pilot-rift-v6" and e.contracts[1].control_version=="pilot-delivery-v6","future A and basic B use correct new environments")
  check(e.credits==int(raw.credits) and e.inventory==raw.inventory,"new rules grant neither money nor assets")
  same(e.settled_ids,raw.settled_ids,"new quote generation preserves earlier paid history")
  check(Chapter.route_error(e.contracts[0]).is_empty() and Chapter.route_error(e.contracts[1]).is_empty(),"new future quotes validate")
func test_new_shop_and_versioned_receipt()->void:
 clear_files();var e=Econ.new();e.enable_delivery_mode();var ship:Array=V6.starter_design();var pad:Array=V6.starter_launcher();e.starter_stock(ship,pad);e.enable_story_mode()
 check(e.flight_mode==Chapter.VERSION,"shop mode/state identity does not migrate")
 check(e.contracts[0].control_version==V6.VERSION and e.contracts[1].control_version==V6.VERSION,"ordinary new shop A/B are immediately v6")
 for level in [1,4,5]:
  var order:Dictionary=Chapter.fresh_route(level)
  check(order.control_version==Chapter.authored_version_for_level(level) and Chapter.route_error(order).is_empty(),"new catalog uses explicit environment version at level %d"%level)
  check(Chapter.allowed_version_for_level(Chapter.version_for_level(level),level),"historical per-level version remains allowed %d"%level)
  check(not V6.route(order).size(),"new profile cannot relabel an already versioned route")
  check(not Receipt.shield_totals({"control_version":order.control_version,"impact_absorbed":2.0,"impact_shield_energy":3.0}).is_empty(),"receipt presenter recognizes physical evidence for "+str(order.control_version))
 begin(e,"D1-A",ship,pad);check(e.save_state(ship,pad,{}),"new dispatch saves")
 var original:Dictionary=capture(e);var wrong:Dictionary=telemetry("pilot-delivery-v3")
 check(not e.settle_contract_and_save("D1-A",wrong,0.0,true,ship,pad,{}).ok,"old solver telemetry cannot claim new v6 physics")
 same(capture(e),original,"wrong physical version leaves dispatch untouched")
 var result:Dictionary=e.settle_contract_and_save("D1-A",telemetry(V6.VERSION),0.0,true,ship,pad,{})
 check(result.ok and e.last_settlement.control_version==V6.VERSION and Chapter.receipt_error(e.last_settlement).is_empty(),"new v6 receipt retains actual v3 economic semantics")
 var paid:int=e.credits
 check(not e.settle_contract_and_save("D1-A",telemetry(V6.VERSION),0.0,true,ship,pad,{}).ok and e.credits==paid,"duplicate settlement cannot award again")
 var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 check(not restored.review_load_blocked and restored.credits==paid and restored.delivery_chapter_state.unlocked_level==2,"new protocol receipt persists once")
 check(restored.close_day_and_save(ship,pad,{}).ok and restored.next_day_and_save(ship,pad,{}).ok,"normal receipt progression authors next v6 task")
 check(restored.contracts[0].chapter_level==2 and restored.contracts[0].control_version==V6.VERSION and restored.customer_reviews()[0].success,"v6 progression and customer review publish normally")
func test_rift_v6_proof_and_debt()->void:
 var raw:Dictionary=copy_native("COURIER_NATIVE_MOON_SAVE");var e=Econ.new();e.load_state();e.enable_story_mode()
 e.close_day_and_save(raw.design,raw.launcher,raw.settings);e.next_day_and_save(raw.design,raw.launcher,raw.settings)
 begin(e,"D6-A",raw.design,raw.launcher)
 var missing:Dictionary=telemetry("pilot-rift-v6")
 var before:Dictionary=capture(e)
 check(not e.settle_contract_and_save("D6-A",missing,0.0,true,raw.design,raw.launcher,raw.settings).ok,"v6 rift cannot bypass strict portal proof by new version name")
 same(capture(e),before,"missing gate evidence leaves balance/history/flight unchanged")
 check(e.estimate_delivery(e.contract_by_id("D6-A"),missing,0.0,true).income==0,"unproven portal quote cannot promise success income")
 var aborted:Dictionary=telemetry("pilot-rift-v6",0.1);aborted.merge({"pilot_tick":0,"required_portal_id":"rift-greenhouse-gate-v1","portal_crossing_tick":-1,"portal_crossings":[],"region":"departure","lost_cost":900.0,"repair_cost":30.0,"ammo_cost":10.0},true)
 check(e.settle_contract_and_save("D6-A",aborted,0.0,false,raw.design,raw.launcher,raw.settings).ok,"new rift failure retains explicit uncrossed evidence")
 check(e.last_settlement.compensation==468 and e.last_settlement.actual_costs==1411 and e.credits==-182,"failure bills energy/ammo/repairs/all lost hardware/cargo without cash cap")
 check(e.delivery_chapter_state.unlocked_level==5 and not e.recover_legacy_debt_and_save(raw.design,raw.launcher,raw.settings).changed,"failure neither advances nor forgives debt")
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.review_load_blocked and loaded.credits==-182 and Chapter.receipt_error(loaded.last_settlement).is_empty(),"new rift debt receipt survives Continue")
 check(loaded.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and loaded.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"negative balance still reaches new basic work")
 for order in loaded.contracts:check(order.control_version==V6.VERSION and order.recovery_offer and order.chapter_level==1,"debt A/B use v6 physics with same non-grant repayment rules")
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 for key in ["COURIER_NATIVE_MOON_SAVE","COURIER_NATIVE_RIFT_SAVE","COURIER_NATIVE_RIFT_FLIGHT"]:
  if OS.get_environment(key).is_empty():printerr("Missing read-only native input "+key);quit(2);return
 test_frozen_native_and_new_day();test_new_shop_and_versioned_receipt();test_rift_v6_proof_and_debt()
 for path in frozen_sources:check(FileAccess.get_file_as_bytes(path)==frozen_sources[path],"original native file unchanged "+str(path.get_file()))
 clear_files();print("DELIVERY_CELL_ECONOMY_V6 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
