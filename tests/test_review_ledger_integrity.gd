extends SceneTree
## Pure normalization tests remain independent; these use real Economy receipts.
const Econ=preload("res://scripts/economy.gd")
const Reviews=preload("res://scripts/customer_reviews.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func write_save(path:String,value:Dictionary):
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(value,"",true,true));f.close()
func clear_files():
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:DirAccess.remove_absolute("user://"+name)
func actual_save() -> Dictionary:
 clear_files();var e=Econ.new();e.enable_extreme_mode();e.ensure_contracts();e.accept_contract("D1-A");e.begin_dispatch([],[])
 check(e.settle_contract_and_save("D1-A",{"integrity":1.0,"energy_used":120.0},62.675,true,[],[],{}).ok,"actual late receipt saved atomically")
 check(e.customer_reviews().is_empty(),"formal receipt reveals no current-day review")
 return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func coherent_publication(raw:Dictionary) -> Dictionary:
 var value:Dictionary=raw.duplicate(true);value.day=2;value.contracts=[]
 value.review_state=Reviews.publish_next_day(raw.review_state,1,2).state
 return value
func _initialize():
 var good:Dictionary=actual_save();var e=Econ.new();var id:String="D1-A"
 check(e._valid_save(good),"real receipt and pending facts agree")
 for full_precision in [false,true]:
  check(e._valid_save(JSON.parse_string(JSON.stringify(good,"",true,full_precision))),"both historical/default and full-precision JSON representations remain valid")
 var edits:Dictionary={"delivery_day":2,"client":"伪造客户","route_name":"伪造航线","destination_name":"虚构收货点","appearance_id":"alien_botanist","success":false,"elapsed":1.0,"deadline":100.0,"integrity":99.0,"required":84.0}
 for key in edits:
  var bad:Dictionary=good.duplicate(true);bad.review_state.pending[id][key]=edits[key]
  check(not e._valid_save(bad),"pending contradiction rejected: "+key)
  if key!="delivery_day" and key!="appearance_id":
   var published:Dictionary=coherent_publication(bad)
   check(Reviews.normalize_state(published.review_state,2).ok,"pure normalization intentionally has no ledger authority: "+key)
   check(not e._valid_save(published),"coherently regenerated published contradiction rejected: "+key)
 var bad:Dictionary=good.duplicate(true);bad.review_state.pending[id].elapsed=1.0;bad.review_state.pending[id].destination_name="虚构收货点"
 check(Reviews.normalize_state(bad.review_state,1).ok and not e._valid_save(bad),"original forged five-star probe is blocked at economy boundary")
 var dual:Dictionary=good.duplicate(true);dual.settled_ids[id].route_context={"destination_name":"contradictory retained destination"}
 check(not e._valid_save(dual),"new review context cannot conceal contradictory retained route context")
 var oversized:Dictionary=good.duplicate(true);oversized.settled_ids[id].review_context.extra="unexpected"
 check(not e._valid_save(oversized),"new receipt context stays at its bounded schema")
 var other_id:String="D1-B";var rekeyed:Dictionary=good.duplicate(true);rekeyed.review_state.pending[other_id]=rekeyed.review_state.pending[id];rekeyed.review_state.pending.erase(id);rekeyed.review_state.pending[other_id].settlement_id=other_id
 check(not e._valid_save(rekeyed),"review cannot point at nonexistent formal settlement")
 for key in ["contract_id","day","client","route","success","elapsed","deadline","integrity","required"]:
  var missing:Dictionary=good.duplicate(true);missing.settled_ids[id].erase(key)
  check(not e._valid_save(missing),"review-era common authoritative fact cannot disappear: "+key)
 # Older reviews without dedicated destination context retain common facts.
 var legacy:Dictionary=good.duplicate(true);legacy.settled_ids[id].erase("review_context")
 check(e._valid_save(legacy),"legacy pending receipt matches retained settled contract")
 var legacy_bad:Dictionary=legacy.duplicate(true);legacy_bad.review_state.pending[id].destination_name="虚构收货点"
 check(not e._valid_save(legacy_bad),"legacy pending destination checked against retained contract")
 var published:Dictionary=coherent_publication(legacy)
 check(e._valid_save(published),"old published destination without retained evidence is preserved")
 var original_body:String=published.review_state.published[0].body
 clear_files();write_save("user://savegame.json",published)
 var restored=Econ.new();restored.load_state()
 check(not restored.review_load_blocked and restored.customer_reviews()[0].body==original_body,"legacy text is neither guessed nor rewritten")
 published.settled_ids[id].route_context={"route_name":published.settled_ids[id].route,"destination_name":published.review_state.published[0].destination_name}
 check(e._valid_save(published),"old Moon/wormhole destination context is authoritative")
 published.settled_ids[id].route_context.destination_name="another destination"
 check(not e._valid_save(published),"retained route context contradiction rejected")
 # Retained appearance remains evidence even when old route_context already
 # owns the destination. A real D3 wormhole receipt reproduces the review gap.
 clear_files();var portal=Econ.new();portal.day=3;portal.reputation=7;portal.enable_extreme_mode();portal.enable_story_mode()
 portal.accept_contract("D3-B");portal.mark_cargo_loaded("D3-B");portal.begin_dispatch([],[])
 check(portal.settle_contract_and_save("D3-B",{"integrity":1.0},30.0,true,[],[],{}).ok,"actual wormhole settlement retains authoritative route context")
 var old_portal:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"));old_portal.settled_ids["D3-B"].erase("review_context")
 check(e._valid_save(old_portal),"old route-context receipt retains matching known actor")
 var erased_actor:Dictionary=old_portal.duplicate(true);erased_actor.review_state.pending["D3-B"].appearance_id=""
 check(Reviews.normalize_state(erased_actor.review_state,3).ok and not e._valid_save(erased_actor),"route_context cannot hide erased retained known appearance")
 for order in old_portal.contracts:
  if order.contract_id=="D3-B":order.destination_name="mutable contract destination"
 check(e._valid_save(old_portal),"old receipt destination still takes precedence over mutable contract")
 # Existing backup and no-backup recovery both preserve raw rejected bytes.
 clear_files();write_save("user://savegame.json",bad);write_save("user://savegame.backup.json",good)
 var source:String=FileAccess.get_file_as_string("user://savegame.json");var backup:String=FileAccess.get_file_as_string("user://savegame.backup.json")
 restored=Econ.new();restored.load_state()
 check(not restored.review_load_blocked and restored.load_notice.contains("备份") and restored.review_state.pending[id].elapsed==62.675,"forged primary uses valid formal backup")
 check(FileAccess.get_file_as_string("user://savegame.json")==source and FileAccess.get_file_as_string("user://savegame.backup.json")==backup,"review recovery preserves both source files")
 DirAccess.remove_absolute("user://savegame.backup.json");restored=Econ.new();restored.load_state()
 check(restored.review_load_blocked and restored.customer_reviews().is_empty() and not restored.next_day_and_save([],[],{}).ok and not restored.save_state([],[],{}),"no backup blocks publication and all saves")
 check(FileAccess.get_file_as_string("user://savegame.json")==source,"no-backup review corruption preserved")
 # New destination context participates in the same failed-save rollback.
 clear_files();var tx=Econ.new();tx.enable_extreme_mode();tx.ensure_contracts();tx.accept_contract(id);tx.begin_dispatch([],[]);tx.save_state([],[],{})
 source=FileAccess.get_file_as_string("user://savegame.json");var balance:int=tx.credits;var flight:Dictionary=tx.in_flight.duplicate(true)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not tx.settle_contract_and_save(id,{"integrity":1.0},62.675,true,[],[],{}).ok,"failed save rejects receipt context and pending facts together")
 check(tx.credits==balance and tx.settled_ids.is_empty() and tx.last_settlement.is_empty() and tx.review_state.pending.is_empty() and tx.in_flight==flight,"failed settlement restores financial and review evidence")
 check(FileAccess.get_file_as_string("user://savegame.json")==source,"failed context commit preserves in-flight source")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(tx.settle_contract_and_save(id,{"integrity":1.0},62.675,true,[],[],{}).ok and tx.settled_ids[id].review_context.size()==3,"retry atomically commits bounded destination context")
 balance=tx.credits;check(not tx.settle_contract_and_save(id,{"integrity":1.0},1.0,true,[],[],{}).ok and tx.credits==balance,"duplicate cannot replace evidence or pay again")
 tx.close_day();check(tx.next_day_and_save([],[],{}).ok and tx.customer_reviews().size()==1 and tx.customer_reviews()[0].category=="late","next day publishes the real late review once")
 clear_files();print("REVIEW_LEDGER_INTEGRITY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
