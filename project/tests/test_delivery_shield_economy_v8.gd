extends SceneTree
## Only new protocol/quote/receipt boundaries. Shield mechanics and display have
## separate focused tests; telemetry here is a commercial validation fixture.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Ground=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Ascent=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const OldGround=preload("res://scripts/pilot_delivery_profile_v7.gd")
const OldAscent=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const OldRift=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
var sources:Dictionary={}
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String)->void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
func copy_native(variable:String)->Dictionary:
 clear_files();var path:String=OS.get_environment(variable);var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path);sources[path]=bytes
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 return JSON.parse_string(bytes.get_string_from_utf8())
func telemetry(version:String,integrity:float=1.0)->Dictionary:
 return {"control_version":version,"integrity":integrity,"delivery_integrity":integrity,"energy_used":0.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0}
func test_profiles()->void:
 for pair in [[Ground,OldGround],[Ascent,OldAscent],[Rift,OldRift]]:
  var current=pair[0];var old=pair[1];var data:Dictionary=current.route()
  check(not data.is_empty() and current.validation_error(data).is_empty(),"new explicit shield family validates "+current.VERSION)
  check(not old.validation_error(data).is_empty(),"old v7 reader cannot ignore v8 shield identity")
  var frozen:Dictionary=data.duplicate(true);var private_copy:Dictionary=current.compatibility_route(data)
  check(old.validation_error(private_copy).is_empty() and private_copy.control_version==old.VERSION,"private compatibility maps to exact same-environment v7")
  same(data,frozen,"validation/private copy never changes committed physics terms")
  check(private_copy.material_rules_schema=="parallel-material-v1" and private_copy.damper_reference_mass_kg==1.0 and private_copy.energy_policy=="unpowered-coast-v1","v7 material and v6 supply/coast policies remain inherited")
  for key in Ground.POLICIES:
   check(not private_copy.has(key),"private legacy copy removes only new shield field "+key)
   var broken:Dictionary=data.duplicate(true);broken.erase(key)
   check(not current.validation_error(broken).is_empty(),"missing shield assumption rejected "+key)
  check(current.validation_error(JSON.parse_string(JSON.stringify(data))).is_empty(),"JSON save round trip preserves exact new rules")
  var offered:Dictionary=data.duplicate(true);offered.contract_id="D2-A";offered.status="available"
  check(current.route(offered).is_empty(),"factory refuses to rewrite an already displayed quote")
 var data:Dictionary=Ground.route()
 for value in [null,true,"1.5",NAN,INF,-1.0,2.0]:
  var broken:Dictionary=data.duplicate(true);broken.shield_base_radius_metres=value
  check(not Ground.validation_error(broken).is_empty(),"nonfinite/wrong-type/unfrozen radius is rejected")
 for key in ["spatial_shield_schema","shield_radius_policy"]:
  var broken:Dictionary=data.duplicate(true);broken[key]=[]
  check(not Ground.validation_error(broken).is_empty(),"shield policy requires exact typed string")
 var unknown:Dictionary=data.duplicate(true);unknown.shield_free_energy=true
 check(not Ground.validation_error(unknown).is_empty(),"unknown shield policy cannot add hidden power")
 for level in [1,4,5]:
  var order:Dictionary=Chapter.fresh_route(level)
  check(order.control_version==Chapter.authored_version_for_level(level) and Chapter.route_error(order).is_empty(),"existing level authors matching v8 family %d"%level)
  check(Chapter.allowed_version_for_level(Chapter.version_for_level(level),level) and Chapter.allowed_version_for_level(Chapter.cell_version_for_level(level),level) and Chapter.allowed_version_for_level(Chapter.material_version_for_level(level),level),"all historical families remain valid for their existing level")
 var old_order:Dictionary=Ground.compatibility_route(Chapter.fresh_route(1));old_order.spatial_shield_schema=Ground.SPATIAL_SHIELD_SCHEMA
 check(not Chapter.route_error(old_order).is_empty(),"new shield marker cannot fall through an old protocol")
func test_real_old_accepted_and_flight()->void:
 var raw:Dictionary=copy_native("COURIER_V7_ACCEPTED");var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked and e.credits==444 and e.active_contract_id=="D2-A","real native v7 accepted shop loads without migration")
 same(e.contracts,raw.contracts,"already displayed and accepted v7 quotes remain byte-equivalent values")
 same(e.settled_ids,raw.settled_ids,"earlier v6 receipts are not recalculated")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==sources[OS.get_environment("COURIER_V7_ACCEPTED")],"Continue does not rewrite native input copy")
 check(e.begin_dispatch(raw.design,raw.launcher,raw.settings.launch_settings).ok and e.in_flight.control_version==OldGround.VERSION,"old accepted quote dispatches with exact old material rules")
 check(e.save_state(raw.design,raw.launcher,raw.settings),"old committed v7 dispatch saves")
 var frozen:Dictionary=e.in_flight.duplicate(true);var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode()
 same(loaded.in_flight,frozen,"old in-flight route and phase survive restart unchanged")
 check(Econ.replay_protocol_error(loaded.in_flight).is_empty(),"old v7 input replay remains supported")
 check(loaded.settle_contract_and_save("D2-A",telemetry(OldGround.VERSION),0.0,false,raw.design,raw.launcher,raw.settings).ok,"unreleased old dispatch can abort with its original zero-cost terms")
 check(loaded.last_settlement.control_version==OldGround.VERSION and loaded.credits==444,"old settlement never changes identity or awards v8 subsidy")
 check(loaded.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and loaded.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"ordinary next business day is the only new authoring boundary")
 check(loaded.contracts[0].control_version==Ground.VERSION and loaded.contracts[1].control_version==Ground.VERSION,"future normal A and basic B use v8 automatically")
 same(loaded.inventory,raw.inventory,"new content entry adds no inventory")
func test_new_bills_and_rift()->void:
 clear_files();var ship:Array=Ground.starter_design();var pad:Array=Ground.starter_launcher();var e=Econ.new();e.enable_delivery_mode();e.starter_stock(ship,pad);e.enable_story_mode()
 check(e.contracts[0].control_version==Ground.VERSION and e.contracts[1].control_version==Ground.VERSION,"normal new shop reaches v8 A/B without flags")
 check(e.accept_contract("D1-A").ok,"new A accepts normally")
 for item in ["battery","battery","battery","battery","armor","armor","beam","beam","beam"]:
  if not e.buy_part(item,Parts.catalog()[item]).ok:check(false,"catalogue purchase failed");return
 check(e.credits==0,"spending before failure is paid at full price")
 var inventory:Dictionary=e.inventory.duplicate(true);e.mark_cargo_loaded("D1-A");e.begin_dispatch(ship,pad,{"angle_degrees":1.0,"power_fraction":0.3});e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 var t:Dictionary=telemetry(Ground.VERSION,0.5);t.merge({"energy_used":36.0,"impact_shield_energy":36.0,"attack_shield_energy":0.0,"ammo_cost":20.0,"repair_cost":10.0,"lost_cost":100.0},true)
 var quote:Dictionary=e.estimate_delivery(e.contract_by_id("D1-A"),t,0.0,false)
 check(quote.energy==1 and quote.actual_costs==221 and e.credits==0 and e.settled_ids.is_empty(),"shield-use counters explain paid energy without double billing or trial side effects")
 check(not e.settle_contract_and_save("D1-A",telemetry(OldGround.VERSION),0.0,true,ship,pad,{}).ok,"older result cannot impersonate v8")
 check(e.settle_contract_and_save("D1-A",t,0.0,false,ship,pad,{}).ok,"new v8 actual-loss receipt commits")
 check(e.credits==-221 and e.last_settlement.compensation==90 and e.last_settlement.charged_costs==221 and e.inventory==inventory,"cash depletion cannot exempt energy/cargo/hardware losses")
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.review_load_blocked and loaded.credits==-221 and Chapter.receipt_error(loaded.last_settlement).is_empty(),"new receipt and debt survive save/Continue")
 check(not loaded.recover_legacy_debt_and_save(ship,pad,{}).changed and loaded.credits==-221,"Continue preserves v8 debt")
 check(not loaded.settle_contract_and_save("D1-A",t,0.0,false,ship,pad,{}).ok and loaded.credits==-221,"settlement cannot repeat after reload")
 var raw:Dictionary=copy_native("COURIER_V5_COMPLETE");e=Econ.new();e.load_state();e.enable_story_mode();e.close_day_and_save(raw.design,raw.launcher,raw.settings);e.next_day_and_save(raw.design,raw.launcher,raw.settings)
 check(e.contracts[0].control_version==Rift.VERSION and e.contracts[1].control_version==Ground.VERSION,"completed old fifth-level shop naturally authors rift-v8 plus basic-v8")
 var id:String=str(e.contracts[0].contract_id);e.accept_contract(id);e.mark_cargo_loaded(id);e.begin_dispatch(raw.design,raw.launcher,raw.settings.launch_settings);e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 var credits:int=e.credits
 check(not e.settle_contract_and_save(id,telemetry(Rift.VERSION),0.0,true,raw.design,raw.launcher,raw.settings).ok and e.credits==credits and not e.in_flight.is_empty(),"spatial-shield version does not bypass required portal proof")
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 for key in ["COURIER_V7_ACCEPTED","COURIER_V5_COMPLETE"]:
  if OS.get_environment(key).is_empty():printerr("Missing read-only native input "+key);quit(2);return
 test_profiles();test_real_old_accepted_and_flight();test_new_bills_and_rift()
 for path in sources:check(FileAccess.get_file_as_bytes(path)==sources[path],"native source remains untouched "+str(path.get_file()))
 clear_files();print("DELIVERY_SHIELD_ECONOMY_V8 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
