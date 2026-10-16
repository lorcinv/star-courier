extends SceneTree
## Bounded protocol + commercial boundary. Material mathematics has its own
## solver tests; these telemetry fixtures do not claim a physical flight.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Ground=preload("res://scripts/pilot_delivery_profile_v7.gd")
const Ascent=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const OldGround=preload("res://scripts/pilot_delivery_profile_v6.gd")
const OldAscent=preload("res://scripts/pilot_delivery_ascent_profile_v6.gd")
const OldRift=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
var source_bytes:Dictionary={}
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String)->void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
func native(variable:String)->Dictionary:
 clear_files();var path:String=OS.get_environment(variable);var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path);source_bytes[path]=bytes
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 return JSON.parse_string(bytes.get_string_from_utf8())
func telemetry(version:String,integrity:float=1.0)->Dictionary:
 return {"control_version":version,"integrity":integrity,"delivery_integrity":integrity,"energy_used":120.0,"ammo_cost":20.0,"repair_cost":10.0,"lost_cost":100.0}
func profiles()->void:
 for pair in [[Ground,OldGround],[Ascent,OldAscent],[Rift,OldRift]]:
  var current=pair[0];var old=pair[1];var data:Dictionary=current.route()
  check(not data.is_empty() and current.validation_error(data).is_empty(),"new explicit material profile validates "+current.VERSION)
  check(not old.validation_error(data).is_empty(),"v6 refuses v7 instead of ignoring material rules "+current.VERSION)
  var frozen:Dictionary=data.duplicate(true);var compatible:Dictionary=current.compatibility_route(data)
  check(old.validation_error(compatible).is_empty() and compatible.control_version==old.VERSION,"private adapter copy has exact same-environment v6 identity")
  same(data,frozen,"private adaptation never rewrites the frozen v7 route")
  for key in Ground.POLICIES:
   check(not compatible.has(key),"compatibility removes only new material key "+key)
   var broken:Dictionary=data.duplicate(true);broken.erase(key)
   check(not current.validation_error(broken).is_empty(),"missing frozen material parameter rejected "+key)
  var invalid:Dictionary=data.duplicate(true);invalid.damper_reference_mass_kg=INF
  check(not current.validation_error(invalid).is_empty(),"nonfinite material reference rejected")
  invalid=data.duplicate(true);invalid.material_unrecognized=true
  check(not current.validation_error(invalid).is_empty(),"unknown material assumption is not silently ignored")
  var committed:Dictionary=data.duplicate(true);committed.contract_id="D1-A";committed.status="available"
  check(current.route(committed).is_empty(),"current factory cannot relabel existing quote")
 for level in [1,4,5]:
  var data:Dictionary=Chapter.fresh_route(level)
  check(data.control_version==Chapter.authored_version_for_level(level) and Chapter.route_error(data).is_empty(),"five-level authoring selects new matching family at level %d"%level)
  var private_old:Dictionary=Ground.compatibility_route(data) if level==1 else (Ascent.compatibility_route(data) if level==4 else Rift.compatibility_route(data))
  check(Chapter.route_error(private_old).is_empty() and Chapter.allowed_version_for_level(private_old.control_version,level),"commercial validator still accepts frozen prior v6 family")
  private_old.material_rules_schema="parallel-material-v1"
  check(not Chapter.route_error(private_old).is_empty(),"old protocol mixed with new material marker cannot fall through")
func frozen_native_orders()->void:
 for variable in ["COURIER_V6_COMPLETE","COURIER_V6_FLIGHT","COURIER_V6_ACCEPTED","COURIER_V5_COMPLETE"]:
  var raw:Dictionary=native(variable);var e=Econ.new();e.load_state();e.enable_story_mode()
  check(not e.review_load_blocked and Chapter.saved_error(raw).is_empty(),"native historical save remains readable "+variable)
  same(e.contracts,raw.contracts,"already displayed/accepted quotes keep their exact versions "+variable)
  same(e.in_flight,raw.in_flight,"committed flight keeps exact old inputs and material absence "+variable)
  same(e.settled_ids,raw.settled_ids,"history is never rebilled "+variable)
  check(FileAccess.get_file_as_bytes("user://savegame.json")==source_bytes[OS.get_environment(variable)],"Continue is read-only "+variable)
  if variable not in ["COURIER_V6_COMPLETE","COURIER_V5_COMPLETE"]:continue
  check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"ordinary future-day boundary authors v7 without migration")
  check(e.contracts[0].control_version==Chapter.authored_version_for_level(int(e.contracts[0].chapter_level)) and e.contracts[1].control_version==Ground.VERSION,"future A and basic B both use matching v7 profiles")
  check(e.credits==int(raw.credits) and e.inventory==raw.inventory,"new material rules grant no cash or inventory")
func no_cash_cap_and_rift_proof()->void:
 clear_files();var ship:Array=Ground.starter_design();var pad:Array=Ground.starter_launcher();var e=Econ.new();e.enable_delivery_mode();e.starter_stock(ship,pad);e.enable_story_mode()
 check(e.contracts[0].control_version==Ground.VERSION and e.contracts[1].control_version==Ground.VERSION,"normal fresh shop immediately reaches material rules")
 check(e.accept_contract("D1-A").ok,"normal new quote accepts")
 for item in ["battery","battery","battery","battery","armor","armor","beam","beam","beam"]:
  if not e.buy_part(item,Parts.catalog()[item]).ok:check(false,"full-price spending failed");return
 check(e.credits==0,"cash is spent through actual purchases before risky dispatch")
 var inventory:Dictionary=e.inventory.duplicate(true);e.mark_cargo_loaded("D1-A")
 check(e.begin_dispatch(ship,pad,{"angle_degrees":1.0,"power_fraction":0.3}).ok,"v7 formal snapshot freezes new identity")
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 var t:Dictionary=telemetry(Ground.VERSION,0.5);var before:int=e.credits
 var quote:Dictionary=e.estimate_delivery(e.contract_by_id("D1-A"),t,0.0,false)
 check(quote.actual_costs==223 and e.credits==before and e.inventory==inventory and e.settled_ids.is_empty(),"trial/quote has no account side effect and no changed rate")
 check(not e.settle_contract_and_save("D1-A",telemetry(OldGround.VERSION),0.0,true,ship,pad,{}).ok,"old physics result cannot impersonate v7")
 check(e.settle_contract_and_save("D1-A",t,0.0,false,ship,pad,{}).ok,"v7 actual-loss categories commit as an unchanged economic receipt")
 check(e.credits==-223 and e.last_settlement.charged_costs==223 and e.last_settlement.compensation==90 and e.inventory==inventory,"spent cash gives no liability exemption or new assets")
 var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode()
 check(not loaded.review_load_blocked and loaded.credits==-223 and Chapter.receipt_error(loaded.last_settlement).is_empty(),"v7 receipt and debt survive save/Continue")
 check(not loaded.recover_legacy_debt_and_save(ship,pad,{}).changed and loaded.credits==-223,"Continue does not subsidize material-rule debt")
 check(not loaded.settle_contract_and_save("D1-A",t,0.0,false,ship,pad,{}).ok and loaded.credits==-223,"receipt is settled once")
 check(loaded.close_day_and_save(ship,pad,{}).ok and loaded.next_day_and_save(ship,pad,{}).ok,"debt still reaches normal next-day basic work")
 for order in loaded.contracts:check(order.control_version==Ground.VERSION and order.recovery_offer,"basic repayment work uses v7 without grants")
 var raw:Dictionary=native("COURIER_V5_COMPLETE");e=Econ.new();e.load_state();e.enable_story_mode();e.close_day_and_save(raw.design,raw.launcher,raw.settings);e.next_day_and_save(raw.design,raw.launcher,raw.settings)
 var id:String=str(e.contracts[0].contract_id);e.accept_contract(id);e.mark_cargo_loaded(id);e.begin_dispatch(raw.design,raw.launcher,{"angle_degrees":0.0,"power_fraction":0.2});e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 before=e.credits
 check(not e.settle_contract_and_save(id,telemetry(Rift.VERSION),0.0,true,raw.design,raw.launcher,raw.settings).ok and e.credits==before and not e.in_flight.is_empty(),"new rift v7 still requires strict physical portal proof")
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 for key in ["COURIER_V6_COMPLETE","COURIER_V6_FLIGHT","COURIER_V6_ACCEPTED","COURIER_V5_COMPLETE"]:
  if OS.get_environment(key).is_empty():printerr("Missing read-only native input "+key);quit(2);return
 profiles();frozen_native_orders();no_cash_cap_and_rift_proof()
 for path in source_bytes:check(FileAccess.get_file_as_bytes(path)==source_bytes[path],"original source untouched "+str(path.get_file()))
 clear_files();print("DELIVERY_MATERIAL_ECONOMY_V7 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
