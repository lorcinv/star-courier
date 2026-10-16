extends SceneTree
## Narrow commercial boundary over a read-only copy of the real native moon
## completion. Synthetic witness cases below test validation, not physical play.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const Delivery=preload("res://scripts/pilot_delivery_profile_v3.gd")
var passed:int=0
var failed:int=0
var seed_bytes:PackedByteArray
var seed:Dictionary={}
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String)->void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft()->Array:return seed.design.duplicate(true)
func pad()->Array:return seed.launcher.duplicate(true)
func settings()->Dictionary:return seed.settings.duplicate(true)
func remove_tree(path:String)->void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var dir=DirAccess.open(path)
 for name in dir.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in dir.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:remove_tree("user://"+name)
func loaded_seed():
 clear_files();var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(seed_bytes);file.close()
 var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked and e.day==5 and e.credits==1229 and e.delivery_chapter_state.unlocked_level==5,"real native moon completion loads unchanged")
 return e
func next_rift(e)->void:
 check(e.close_day_and_save(craft(),pad(),settings()).ok,"normal close saves without a content migration")
 check(e.next_day_and_save(craft(),pad(),settings()).ok,"normal next day authors global fifth level")
func begin(e,id:String="D6-A")->void:
 check(e.accept_contract(id).ok,"accept actual offered "+id);e.mark_cargo_loaded(id)
 check(e.begin_dispatch(craft(),pad(),{"angle_degrees":0.0,"power_fraction":0.6}).ok,"dispatch keeps fifth protocol and frozen setup")
func telemetry(crossed:bool=true,integrity:float=1.0)->Dictionary:
 var out:Dictionary={"control_version":Rift.VERSION,"pilot_tick":120,"integrity":integrity,"delivery_integrity":integrity,"energy_used":1000.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0,"required_portal_id":Rift.PORTAL_ID,"portal_crossing_tick":40 if crossed else -1,"portal_crossings":[],"region":"greenhouse" if crossed else "departure"}
 if crossed:
  var ids:Array=[];var cargos:Array=[]
  for p in craft():
   ids.append(int(p.id))
   if p.type=="cargo":cargos.append(int(p.id))
  out.portal_crossings=[{"portal_id":Rift.PORTAL_ID,"tick":40,"cargo_ids":cargos,"part_ids":ids,"from":[28.0,0.0],"to":[101.75,0.0],"body_radius":1.5,"margin":0.25}]
 return out
func released(e)->void:
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation");e.in_flight.ticks=60;e.in_flight.elapsed=1.0
func state(e)->Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result
func test_native_progression_and_receipt()->void:
 var e=loaded_seed();var old_ledger:Dictionary=e.settled_ids.duplicate(true);var old_orders:Array=e.contracts.duplicate(true)
 same(e.contracts,seed.contracts,"current displayed D5 orders retain their old content")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==seed_bytes,"Continue is byte-read-only")
 check(e.delivery_chapter_status().moon_complete and not e.delivery_chapter_status().rift_complete,"moon remains complete after content catalog grows")
 next_rift(e)
 var order:Dictionary=e.contract_by_id("D6-A")
 check(order.control_version==Rift.VERSION and order.chapter_id==3 and order.chapter_level==5 and order.cargo_kind=="biological","normal day-six A is third-chapter global level five")
 check(order.min_delivery_integrity==0.8 and order.cargo_value==520 and order.economy_policy==Chapter.ECONOMY_POLICY,"new cargo uses same HP requirement and actual-cost policy")
 check(e.contract_by_id("D6-B").control_version==Delivery.VERSION and not e.contract_by_id("D6-B").chapter_progression,"daily basic B remains available")
 same(e.settled_ids,old_ledger,"authoring fifth never recalculates historical bills")
 same(e.inventory,seed.inventory,"new content supplies no cash or assets")
 check(e.credits==1229,"new day has no stage-entry subsidy")
 check(not Delivery.validation_error(order).is_empty() and Chapter.route_error(order).is_empty(),"old v3 reader rejects new explicit rift version")
 check(order.cargo=="活体苔光幼苗","existing customer story cannot replace biological cargo")
 begin(e);released(e)
 check(Econ.replay_protocol_error(e.in_flight).is_empty(),"new snapshot stays on shared input schema with explicit v5")
 check(e.save_state(craft(),pad(),settings()),"fifth in-flight saves")
 var frozen:Dictionary=e.in_flight.duplicate(true);var flying=Econ.new();flying.load_state();flying.enable_story_mode()
 same(flying.in_flight,frozen,"Continue freezes new in-flight route and launch inputs")
 var actual:Dictionary=telemetry(true,0.9);actual.energy_used=2000.1;actual.repair_cost=2.2;actual.lost_cost=45.0;actual.ammo_cost=1.1
 var quote:Dictionary=flying.estimate_delivery(order,actual,1.0,true)
 check(quote.actual_costs==153 and quote.profit==507,"biology damage shares cargo HP and actual energy/ammo/repair/lost costs")
 var before:Dictionary=state(flying)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not flying.settle_contract_and_save("D6-A",actual,1.0,true,craft(),pad(),settings()).ok,"failed receipt write cannot commit fifth progress")
 same(state(flying),before,"failed receipt write rolls back witness/cash/story/progress")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(flying.settle_contract_and_save("D6-A",actual,1.0,true,craft(),pad(),settings()).ok,"bound synthetic valid portal receipt commits")
 check(flying.credits==1736 and flying.delivery_chapter_state.unlocked_level==6 and flying.last_settlement.level_completed,"one qualified fifth receipt advances global progress to six")
 check(flying.last_settlement.portal_delivery_evidence.schema==Chapter.PORTAL_EVIDENCE_SCHEMA and Chapter.receipt_error(flying.last_settlement).is_empty(),"receipt stores versioned validated portal witness")
 var broken_receipt:Dictionary=flying.last_settlement.duplicate(true);broken_receipt.erase("portal_delivery_evidence")
 check(not Chapter.receipt_error(broken_receipt).is_empty(),"saved successful fifth receipt cannot omit portal proof")
 broken_receipt=flying.last_settlement.duplicate(true);broken_receipt.portal_delivery_evidence.required_portal_id="other-gate";broken_receipt.portal_delivery_evidence.portal.id="other-gate";broken_receipt.portal_delivery_evidence.portal_crossings[0].portal_id="other-gate"
 check(not Chapter.receipt_error(broken_receipt).is_empty(),"self-consistent foreign gate cannot rewrite saved success")
 for id in old_ledger:same(flying.settled_ids[id],old_ledger[id],"prior receipt remains immutable "+str(id))
 var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 check(not restored.review_load_blocked and restored.delivery_chapter_status().complete and restored.credits==1736,"fifth money/proof/completion survive restart")
 same(restored.last_settlement,flying.last_settlement,"restart does not rewrite the new receipt")
 check(not restored.settle_contract_and_save("D6-A",actual,1.0,true,craft(),pad(),settings()).ok and restored.credits==1736,"receipt cannot pay twice after restart")
 check(restored.close_day_and_save(craft(),pad(),settings()).ok and restored.next_day_and_save(craft(),pad(),settings()).ok,"fifth result can publish review next normal day")
 check(restored.customer_reviews()[0].success and not "准时" in restored.customer_reviews()[0].body,"rift review uses existing no-time-pressure facts")
 check(old_orders[0].control_version=="pilot-ascent-v4","native source retains completed moon protocol")
func test_false_success_rejected_and_failure_billed()->void:
 var e=loaded_seed();next_rift(e);begin(e);released(e)
 var original:Dictionary=state(e)
 var cases:Array=[]
 var bad:Dictionary=telemetry(false);cases.append(bad)
 bad=telemetry();bad.erase("portal_crossing_tick");cases.append(bad)
 bad=telemetry();bad.required_portal_id="other-gate";cases.append(bad)
 bad=telemetry();bad.portal_crossing_tick=121;bad.portal_crossings[0].tick=121;cases.append(bad)
 bad=telemetry();bad.portal_crossings[0].cargo_ids=[];cases.append(bad)
 bad=telemetry();bad.portal_crossings[0].part_ids=[999];cases.append(bad)
 bad=telemetry();bad.portal_crossings[0].to=[200.0,0.0];cases.append(bad)
 bad=telemetry();bad.portal_crossings[0].body_radius=10.0;cases.append(bad)
 bad=telemetry();bad.region="departure";cases.append(bad)
 bad=telemetry();bad.erase("pilot_tick");cases.append(bad)
 bad=telemetry();bad.required_portal_id=[];cases.append(bad)
 bad=telemetry();bad.portal_crossings[0].tick={};cases.append(bad)
 for index in range(cases.size()):
  check(not e.settle_contract_and_save("D6-A",cases[index],1.0,true,craft(),pad(),settings()).ok,"fake/missing/foreign portal success rejected case %d"%index)
  same(state(e),original,"rejected success preserves complete in-flight state case %d"%index)
 var actual:Dictionary=telemetry(false,0.2);actual.energy_used=20000;actual.repair_cost=100;actual.lost_cost=400
 check(e.settle_contract_and_save("D6-A",actual,1.0,false,craft(),pad(),settings()).ok,"real no-portal failure settles losses without claiming transition")
 check(e.last_settlement.actual_costs==1416 and e.last_settlement.compensation==416 and e.credits==-187,"unpassed portal failure still charges all actual loss into debt")
 check(e.delivery_chapter_state.unlocked_level==5 and not e.last_settlement.level_completed,"failure cannot advance fifth level")
 check(not e.recover_legacy_debt_and_save(craft(),pad(),settings()).changed,"Continue does not forgive rift debt")
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.review_load_blocked and loaded.credits==-187,"negative balance and no-crossing receipt survive restart")
 check(loaded.close_day_and_save(craft(),pad(),settings()).ok and loaded.next_day_and_save(craft(),pad(),settings()).ok,"debt retains normal next-day basic work")
 for offer in loaded.contracts:check(offer.chapter_level==1 and offer.recovery_offer and not offer.chapter_progression,"debt A/B use owned inventory to repay without stage skip")
func test_old_pending_and_unreleased_abort()->void:
 var e=loaded_seed();begin(e,"D5-B");check(e.save_state(craft(),pad(),settings()),"old accepted basic dispatch saves")
 var old:Dictionary=e.in_flight.duplicate(true);var orders:Array=e.contracts.duplicate(true)
 var loaded=Econ.new();loaded.load_state();same(loaded.in_flight,old,"old in-flight v3 is not relabelled rift");same(loaded.contracts,orders,"old accepted and settled quote values freeze")
 e=loaded_seed();next_rift(e);begin(e)
 var aborted:Dictionary=telemetry(false);aborted.pilot_tick=0;aborted.energy_used=0.0
 check(e.settle_contract_and_save("D6-A",aborted,0.0,false,craft(),pad(),settings()).ok,"unreleased v5 abort has explicit empty portal evidence")
 check(e.credits==1229 and e.delivery_chapter_state.unlocked_level==5 and e.last_settlement.actual_costs==0,"pre-release abort causes no phantom cost or progression")
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Use isolated XDG_DATA_HOME.");quit(2);return
 var path:String=OS.get_environment("COURIER_NATIVE_MOON_SAVE")
 if path.is_empty() or not FileAccess.file_exists(path):printerr("Provide the read-only native moon completion through COURIER_NATIVE_MOON_SAVE.");quit(2);return
 seed_bytes=FileAccess.get_file_as_bytes(path);seed=JSON.parse_string(seed_bytes.get_string_from_utf8())
 test_native_progression_and_receipt();test_false_success_rejected_and_failure_billed();test_old_pending_and_unreleased_abort()
 check(FileAccess.get_file_as_bytes(path)==seed_bytes,"original native moon save remains byte-for-byte untouched")
 clear_files();print("DELIVERY_RIFT_ECONOMY_V5 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
