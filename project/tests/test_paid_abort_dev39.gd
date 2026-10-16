extends Node
class FlightStub extends RefCounted:
 var status:String="running"
class Controller extends "res://scripts/main.gd":
 var aborts:int=0
 func _ready()->void:pass
 func _process(_delta:float)->void:pass
 func abort_flight()->void:
  aborts+=1;sim.status="failed";page="report"
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 await get_tree().process_frame;await get_tree().process_frame
func setup(app,was_paused:bool)->void:
 app.page="flight";app.trial=false;app.paused=was_paused;app.sim=FlightStub.new();app.economy.in_flight={"contract_id":"ordinary-paid"};app.flight_order={"control_version":"pilot-delivery-v8"}
func run()->void:
 get_tree().root.gui_embed_subwindows=true;get_tree().root.size=Vector2i(1280,720)
 var app=Controller.new();add_child(app);setup(app,false)
 var before:PackedByteArray=var_to_bytes(app.economy.in_flight)
 app._action("abort",null);await settle()
 check(app._abort_prompt_pending and app.closing and app.paused and app.aborts==0,"paid HUD action pauses and waits without abort")
 check(app._abort_prompt.gui_get_focus_owner()==app._abort_prompt.get_cancel_button(),"safe continue default focus")
 check("不能再次正式配送" in app._abort_prompt.dialog_text and "债务" in app._abort_prompt.dialog_text and not "¥" in app._abort_prompt.dialog_text,"warning states lost attempt and actual-cost risk without fixed price")
 app._action("abort",null);app._action("pause",null);check(app.aborts==0 and app.paused,"repeated input while modal cannot abort or resume")
 app._abort_prompt.get_cancel_button().pressed.emit();await settle()
 check(not app.closing and not app.paused and app.aborts==0 and var_to_bytes(app.economy.in_flight)==before,"cancel restores running state without contract mutation")
 setup(app,true);app._action("abort",null);await settle();app._abort_prompt.get_cancel_button().pressed.emit();await settle()
 check(app.paused and app.aborts==0,"cancel preserves prior manual pause")
 setup(app,false);app._action("abort",null);app._hold_quit_resume_for_disconnect();app._abort_prompt.get_cancel_button().pressed.emit();await settle()
 check(app.paused and app.aborts==0,"disconnect during confirmation remains safely paused")
 setup(app,true);app._action("abort",null);await settle();app._abort_prompt.get_ok_button().pressed.emit();await settle();app._confirm_abort_prompt();app._cancel_abort_prompt()
 check(app.aborts==1 and app.page=="report" and not app.closing,"confirmation commits once; stale duplicate callbacks inert")
 setup(app,true);app._action("abort",null);app.economy.in_flight.contract_id="different-order";app._confirm_abort_prompt()
 check(app.aborts==1 and app.sim.status=="running","stale contract identity cannot abort replacement")
 setup(app,true);app.trial=true;app._action("abort",null)
 check(app.aborts==2 and app.page=="report" and not app._abort_prompt_pending,"free trial abort remains immediate")
 setup(app,true);app.pilot_resume_blocked=true;app._action("abort",null)
 check(app.aborts==2 and not app._abort_prompt_pending,"blocked recovery does not expose paid abort")
 app.free();await settle()
 print("PAID_ABORT_DEV39 passed=",passed," failed=",failed," synthetic_dialog_semantics=true native=false")
 get_tree().quit(0 if failed==0 else 1)
