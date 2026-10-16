extends SceneTree
const Main=preload("res://scripts/main.gd")
const Econ=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
class FakeFlight extends RefCounted:
 var status:String="success"
 var elapsed:float=8.0
 var telemetry:Dictionary={"integrity":1.0,"energy_used":12.0,"ammo_cost":2.0,"repair_cost":3.0,"lost_cost":4.0}
 var events:Array=[]
 var incidents:Array=[]
 func finalize_settlement() -> void:pass
class Controller extends "res://scripts/main.gd":
 var rendered:int=0
 var notices:Array=[]
 var requested_stories:int=0
 func _ready() -> void:pass
 func render() -> void:rendered+=1
 func notify(message:String) -> void:notices.append(message)
 func _play_music(_flight:bool) -> void:pass
 func _sound(_kind:String) -> void:pass
 func _request_story(_contract_id:String,_beat:String) -> void:requested_stories+=1

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func run() -> void:
 clear_files();var app=Controller.new();app.economy=Econ.new();app.economy.ensure_contracts()
 var id:String=app.economy.contracts[0].contract_id;app.economy.accept_contract(id);app.economy.begin_dispatch([],[]);app.economy.save_state([],[],{})
 app.design=[];app.launcher=[];app.sim=FakeFlight.new();app.page="flight";app.flight_order=app.economy.active_contract().duplicate(true)
 var balance:int=app.economy.credits;DirAccess.make_dir_absolute("user://savegame.tmp")
 app.finish_flight()
 check(app.page=="flight" and app.paused and app.completion_countdown==3.0,"main keeps failed settlement paused with bounded delayed retry")
 check(app.rendered==0 and app.requested_stories==0 and not app.report.has("income"),"main shows neither unpaid receipt nor result dialogue")
 check(app.economy.credits==balance and app.economy.settled_ids.is_empty() and app.economy.review_state.pending.is_empty(),"main rollback includes financial commit and pending facts")
 check(app.economy.in_flight.contract_id==id,"main rollback retains formal dispatch for deterministic restart")
 DirAccess.remove_absolute("user://savegame.tmp");app.finish_flight()
 check(app.page=="report" and app.rendered==1 and app.requested_stories==1,"main renders receipt/dialogue only after successful retry saves")
 check(app.economy.review_state.pending.size()==1 and app.economy.customer_reviews().is_empty(),"successful controller settlement still publishes no current-day review")
 var stored_balance:int=app.economy.credits;app.finish_flight()
 check(app.economy.credits==stored_balance and app.economy.review_state.pending.size()==1,"duplicate controller finish cannot pay or enqueue twice")
 app.free();clear_files()
 var rejected=Controller.new();rejected.economy=Econ.new();rejected.economy.enable_story_mode()
 var rejected_id:String=rejected.economy.contracts[0].contract_id
 rejected.economy.accept_contract(rejected_id);rejected.economy.mark_cargo_loaded(rejected_id);rejected.economy.begin_dispatch([],[]);rejected.economy.save_state([],[],{})
 rejected.economy.active_contract().appearance_id="injected_unknown_identity"
 rejected.design=[];rejected.launcher=[];rejected.sim=FakeFlight.new();rejected.page="flight";rejected.flight_order=rejected.economy.active_contract().duplicate(true)
 var original_credits:int=rejected.economy.credits;var original_story:Dictionary=rejected.economy.story_state.duplicate(true)
 rejected.finish_flight()
 check(rejected.page=="flight" and rejected.paused and rejected.rendered==0 and not rejected.report.has("income"),"capture failure cannot display an unpaid formal report")
 check(rejected.requested_stories==0 and rejected.economy.story_state==original_story,"capture failure cannot advance result dialogue or story state")
 check(rejected.economy.credits==original_credits and rejected.economy.in_flight.contract_id==rejected_id and rejected.economy.review_state.pending.is_empty(),"controller capture failure restores money, dispatch, and pending facts")
 check(rejected.notices.size()==1 and str(rejected.notices[0]).contains("尚未保存"),"controller surfaces capture failure as a concise recoverable notice")
 rejected.economy.active_contract().appearance_id="human_courier";rejected.finish_flight()
 check(rejected.page=="report" and rejected.economy.review_state.pending.size()==1 and rejected.requested_stories==1,"controller retries corrected capture as one complete saved transaction")
 rejected.free();clear_files()
 for filename in ["savegame.json","savegame.backup.json"]:
  var file=FileAccess.open("user://"+filename,FileAccess.WRITE);file.store_string("{broken");file.close()
 var recovery=Main.new();root.add_child(recovery);await process_frame
 check(recovery.economy.review_load_blocked and recovery.world==null,"corrupt-save startup never builds an apparently playable new shop")
 check(recovery.get_child_count()==1 and recovery.get_child(0) is Label,"unparseable save shows only a concise native recovery notice")
 check(not recovery.is_processing() and not recovery.is_processing_input(),"recovery-only startup disables normal frame/input work")
 check(not recovery.economy.save_state([],[],{}),"recovery-only startup cannot overwrite the damaged save")
 check(FileAccess.get_file_as_string("user://savegame.json")=="{broken" and FileAccess.get_file_as_string("user://savegame.backup.json")=="{broken","recovery-only startup preserves both source files")
 recovery.queue_free();await process_frame;clear_files()
 print("REVIEW_CONTROLLER passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)
