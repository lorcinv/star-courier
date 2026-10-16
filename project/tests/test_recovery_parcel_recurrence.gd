extends SceneTree
# Isolated synthetic exact-state regression, no real saves or native-input claim.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
const CASES={"human_courier":{"species":"human","accessories":["none"]},"elf_archivist":{"species":"elf","accessories":["book_pouch","map_case"]},"alien_botanist":{"species":"alien","accessories":["seed_pod","field_vial"]},"robot_machinist":{"species":"robot","accessories":["tool_pack","power_cell"]}}
var passed:int=0
var failures:Array=[]
var snapshots:Array=[]
var anomalies:Array=[]
var label:String=""
func _initialize() -> void:run.call_deferred()
func check(ok:bool,what:String) -> void:
 if ok:passed+=1
 else:failures.append(label+": "+what);push_error(label+": "+what)
func painted(actor) -> bool:
 if not is_instance_valid(actor) or actor.texture==null:return false
 # Classify the actual visible resource whose pixels were independently inspected.
 return actor.texture.resource_path in ["res://assets/2d_v5/npcs/elf_archivist/handoff-pixel.png","res://assets/2d_v5/npcs/alien_botanist/handoff-pixel.png","res://assets/2d_v5/npcs/robot_machinist/handoff-pixel.png"]
func snap(w,stage:String,expected:int=1) -> void:
 var a=w.customers["audit"].node
 var baked:int=int(a.is_visible_in_tree() and painted(a))
 var live:int=int(w.parcel.is_visible_in_tree())
 snapshots.append({"case":label,"stage":stage,"phase":w._parcel_phase,"pose":a.pose,"texture":a.texture.resource_path if a.texture!=null else "","baked":baked,"live":live,"clerk":w._clerk_motion._pose,"accessory":a.accessory_id,"position":str(w.parcel.position)})
 check(baked+live==expected,stage+" exact inspected-art + live representation count="+str(baked+live))
 check(a.pose_contains_parcel()==painted(a),stage+" metadata agrees with inspected actual texture")
func run() -> void:
 for ident in CASES:
  for accessory in CASES[ident].accessories:
   for talking in [false,true]:
    label=ident+"/"+accessory+"/dialogue="+str(talking)
    var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
    var w=World.new();viewport.add_child(w);w.set_process(false);w.assembly_feedback.set_process(false)
    w.show_design(Profile.starter_design());w.focus("hub",true)
    var contract={"contract_id":"audit","status":"available","appearance_id":ident,"species":CASES[ident].species,"appearance_seed":123,"accessory_id":accessory}
    var data={"phase":"morning","active_contract_id":"","contracts":[contract]}
    var original:String=JSON.stringify(data);w.update_shop_state(data)
    for i in 250:w.visual_time+=.01;w._step_customers(.01)
    var a=w.customers["audit"].node;var binding:Dictionary=a.binding_snapshot()
    check(a.appearance_id==ident and a.species==CASES[ident].species and a.accessory_id==accessory,"exact species/accessory binding")
    check(a.supports_counter_transfer_pose()==(ident=="human_courier"),"empty-human-only transfer capability")
    w.active_id="audit";w.parcel_state="accepted";w._parcel_phase="waiting_customer";w.set_dialogue_active(talking,"audit");w._set_counter_poses("audit");w._sync_customer_parcel();snap(w,"waiting")
    w._start_counter_handoff();w._parcel_tween.pause();snap(w,"giving")
    var generation:int=w._parcel_generation
    w.set_focus_active(false);var before:Vector2=w.parcel.position;w._process(.5)
    snap(w,"focus_frozen_giving");check(w.parcel.position==before and not w._parcel_tween.is_running(),"focus freezes transfer")
    w.set_focus_active(true);w._parcel_tween.pause();snap(w,"focus_resumed_giving")
    w.hide();check(not w._parcel_tween.is_running(),"hidden world freezes transfer");w.show();w._parcel_tween.pause();snap(w,"shown_giving")
    w._begin_counter_transfer("audit",generation);snap(w,"transfer_start")
    check(a.pose==("handoff" if ident=="human_courier" else ("conversation" if talking else "idle")),"giver pose ownership at live switch")
    for progress in [0.0,.01,.5,.99,1.0]:
     w._move_counter_parcel(progress,"audit",generation);w.visual_time+=.01;w._step_customers(.01);snap(w,"transfer_"+str(progress))
     check(w._clerk_motion._pose=="handoff","receiver ready during transfer")
    w._receive_counter_parcel("audit",generation);snap(w,"receive")
    w._finish_counter_handoff("audit",generation);snap(w,"counter")
    w.set_dialogue_active(false);w._set_counter_poses();w._process(.01);snap(w,"counter_after_idle")
    check(w._clerk_supports_counter_parcel() and w._clerk_motion._pose=="handoff","clerk retains support through counter wait")
    w._loading_requested=true;w._start_robot_fetch()
    for i in 300:
     if w._parcel_phase!="robot_fetch":break
     w._step_parcel_transport(.01)
    snap(w,"robot_pickup")
    check(w._parcel_phase=="robot_pickup" and w._clerk_motion._pose=="handoff","fetch reaches supported pickup")
    var until_contact:float=World.ROBOT_PICKUP_DURATION*World.ROBOT_REACH_FRACTION-w._transport_age
    w._step_parcel_transport(until_contact-.0001);check(w._clerk_supports_counter_parcel(),"support before pickup contact")
    w._step_parcel_transport(.0002);snap(w,"robot_contact")
    check(not w._clerk_supports_counter_parcel() and w.assembly_feedback.transport_grip_point().distance_to(w.parcel.position)<.001,"release only at actual robot contact")
    before=w.parcel.position;w._receive_counter_parcel("audit",generation);check(w.parcel.position==before and w._parcel_phase=="robot_pickup","stale giving callback rejected")
    w.hide();w.fastforward_loading("audit");w.show();snap(w,"hidden_skip_loaded",0)
    check(w.parcel_state=="loaded" and not a.visible,"skip settles and hides exited giver")
    check(a.binding_snapshot()==binding and JSON.stringify(data)==original,"all transitions leave binding/caller data untouched")
    # Order replacement/cancellation after a fresh giving state.
    w.customers["audit"].departure="present";a.show();w._loading_requested=false;w.parcel_state="counter";w._parcel_phase="customer_handoff";w._set_counter_poses("audit");w._sync_customer_parcel()
    generation=w._parcel_generation;w.update_shop_state(data)
    w._begin_counter_transfer("audit",generation);w._receive_counter_parcel("audit",generation);snap(w,"cancel_stale",0)
    check(w.active_id.is_empty() and w.parcel_state=="empty","order-clear generation owns cancellation")
    # Hidden reduced-motion setter: record immediate source state separately from rendered-frame claim.
    w.set_dialogue_active(talking,"audit")
    w.active_id="audit";w.parcel_state="counter";w._parcel_phase="customer_handoff";w._set_counter_poses("audit");w._sync_customer_parcel()
    generation=w._parcel_generation;w.hide();w.reduced_motion=true;w.show()
    if painted(a) and w.parcel.visible:anomalies.append({"case":label,"kind":"hidden_reduced_motion_resume_pre_process","pose":a.pose,"phase":w._parcel_phase})
    # Resume itself must reconcile ownership; no process frame is allowed first.
    snap(w,"hidden_reduce_immediate_resume")
    check(a.pose==("conversation" if talking else "idle"),"resume applies latest requested quiet/dialogue pose")
    check(w._parcel_phase=="counter" and w.parcel_state=="counter" and w._parcel_tween==null and w._parcel_generation==generation+1,"hidden reduced-motion settle keeps phase/generation/tween ownership")
    check(w._clerk_supports_counter_parcel() and w.parcel.position.distance_to(w._actor_parcel_point(w.clerk,"clerk"))<.001,"hidden reduced-motion settle preserves clerk support")
    before=w.parcel.position;generation=w._parcel_generation
    w.hide();w.show();snap(w,"hidden_reduce_repeated_resume")
    check(w.parcel.position==before and w._parcel_generation==generation,"repeat resume cannot restart or move settled transfer")
    w.set_focus_active(false);w.hide();w.show();snap(w,"hidden_reduce_focus_frozen_resume")
    w._process(.5)
    check(w.parcel.position==before and w._parcel_generation==generation,"focus-frozen process cannot alter reconciled ownership")
    w.set_focus_active(true);w._process(.01);snap(w,"hidden_reduce_after_first_process")
    w.free();viewport.free();await process_frame
 var result={"passed":passed,"failures":failures,"pre_process_anomalies":anomalies,"snapshots":snapshots,"scope":"Synthetic exact-state control of actual world renderer and inspected runtime resources; headless, not native player-input visual proof."}
 var out=FileAccess.open("user://recurrence-results.json",FileAccess.WRITE)
 if out!=null:out.store_string(JSON.stringify(result," "))
 print("PARCEL_RECURRENCE passed=",passed," failed=",failures.size()," pre_process_anomalies=",anomalies.size())
 quit(1 if not failures.is_empty() else 0)
