extends SceneTree
## Real current and captured older seeded Economy writers, no flight simulation.
const Econ=preload("res://scripts/economy.gd")
const OldEcon=preload("res://tests/fixtures/economy_pre_integrity_seeded_v5.gd")
const Stories=preload("res://scripts/courier_stories.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func clean():
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:DirAccess.remove_absolute("user://"+name)
func raw() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write(value:Dictionary):
 var f=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_string(JSON.stringify(value,"",true,true));f.close()
func prepare(e,future:bool=true):
 e.enable_extreme_mode();e.story_state=Stories.initial_state(59);e.enable_story_mode();e.enable_seeded_offers(59)
 # This is specifically a historical unmarked v1 opacity fixture. New ordinary
 # content now has dedicated commercial markers and must reject a forged
 # version-only mutation; it is covered by test_combined_authoring_policy.
 e.day=2;e.contracts=[];e.review_state=preload("res://scripts/customer_reviews.gd").initial_state(2);e.ensure_contracts()
 var order:Dictionary=e.contracts[0]
 if future:
  order.generation.version="future-offers-v900";order.appearance_id="future_crystal_customer";order.client="遥远客户";order.species="future_species"
 var id:String=order.contract_id
 check(e.accept_contract(id).ok and e.mark_cargo_loaded(id).ok and e.begin_dispatch([],[]).ok,"actual supported flight accepts opaque content identity")
 return id
func _initialize():
 clean();var e=Econ.new();var id:String=prepare(e);var order:Dictionary=e.active_contract().duplicate(true)
 check(e.save_state([],[],{}),"opaque formal commitment saves without identity rewrite")
 var source:String=FileAccess.get_file_as_string("user://savegame.json");var balance:int=e.credits
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.settle_contract_and_save(id,{"integrity":1.0},8.0,true,[],[],{}).ok,"failed opaque receipt save rolls back")
 check(e.credits==balance and e.settled_ids.is_empty() and e.in_flight.contract_id==id and e.active_contract()==order,"rollback preserves opaque original order and commitment")
 check(FileAccess.get_file_as_string("user://savegame.json")==source,"failed opaque receipt leaves source unchanged")
 DirAccess.remove_absolute("user://savegame.tmp")
 var result:Dictionary=e.settle_contract_and_save(id,{"integrity":1.0},8.0,true,[],[],{})
 check(result.ok,"new opaque receipt can commit with the same generic review identity")
 if not result.ok:
  print("SEEDED_INTEGRITY_SEAM passed=%d failed=%d"%[passed,failed]);quit(1);return
 check(e.settled_ids[id].review_context.appearance_id=="" and e.review_state.pending[id].appearance_id=="","new receipt context and facts agree on generic voice")
 var retained:Dictionary=e.contract_by_id(id)
 check(retained.appearance_id=="future_crystal_customer" and retained.client=="遥远客户" and retained.generation.version=="future-offers-v900","original opaque customer identity remains untouched")
 check(e.customer_reviews().is_empty() and not result.story_advanced,"opaque receipt neither leaks today nor advances a guessed story")
 var disk:Dictionary=raw();check(e._valid_save(disk),"new opaque context passes actual saved-economy validation")
 var reload=Econ.new();reload.load_state();check(not reload.review_load_blocked and reload.review_state.pending[id].appearance_id=="","new generic pending receipt survives restart")
 reload.close_day();check(reload.next_day_and_save([],[],{}).ok and reload.customer_reviews().size()==1 and reload.customer_reviews()[0].appearance_id=="","new opaque receipt publishes generic copy next day")
 # Old reviewed writer legitimately used generic facts and retained unknown
 # contract appearance, before review_context existed in any receipt.
 clean();var old=OldEcon.new();var old_id:String=prepare(old)
 check(old.settle_contract_and_save(old_id,{"integrity":1.0},8.0,true,[],[],{}).ok,"captured old seeded writer produces actual generic opaque receipt")
 var legacy:Dictionary=raw()
 check(not legacy.settled_ids[old_id].has("review_context") and legacy.review_state.pending[old_id].appearance_id=="" and legacy.contracts[0].appearance_id=="future_crystal_customer","old-format fixture actually has generic facts and unknown retained actor")
 source=FileAccess.get_file_as_string("user://savegame.json")
 reload=Econ.new();check(reload._valid_save(legacy),"old opaque generic review remains compatible with retained contract")
 reload.load_state();check(not reload.review_load_blocked and FileAccess.get_file_as_string("user://savegame.json")==source,"old opaque receipt reload does not rewrite original source")
 reload.close_day();check(reload.next_day_and_save([],[],{}).ok and reload.customer_reviews()[0].appearance_id=="","old opaque generic review publishes once without known-character impersonation")
 # Ordinary known identity is still evidence and cannot be erased as generic.
 clean();old=OldEcon.new();old_id=prepare(old,false);old.settle_contract_and_save(old_id,{"integrity":1.0},8.0,true,[],[],{});legacy=raw()
 check(Econ.new()._valid_save(legacy) and not legacy.review_state.pending[old_id].appearance_id.is_empty(),"old known-character receipt remains valid")
 legacy.review_state.pending[old_id].appearance_id="";check(not Econ.new()._valid_save(legacy),"known identity erasure cannot borrow opaque-content compatibility")
 clean();print("SEEDED_INTEGRITY_SEAM passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
