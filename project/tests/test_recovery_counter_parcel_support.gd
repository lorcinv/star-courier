extends SceneTree
## Recovery-profile world regression. Requires integrated world capability calls.
## Synthetic presentation fixture, separate from native actual-input proof.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL ",label)
func run() -> void:
 var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 var w=World.new();viewport.add_child(w);w.set_process(false);w.assembly_feedback.set_process(false)
 w.show_design(Profile.starter_design());w.focus("hub",true)
 var data:Dictionary={"phase":"morning","active_contract_id":"","contracts":[{"contract_id":"support-test","status":"available","appearance_id":"human_courier","species":"human","appearance_seed":123,"accessory_id":"none"}]}
 var original:String=JSON.stringify(data);w.update_shop_state(data)
 for i in 250:w.visual_time+=.01;w._step_customers(.01)
 var actor=w.customers["support-test"].node;var binding:Dictionary=actor.binding_snapshot()
 check(not actor.has_rigid_motion() and actor.supports_state_locomotion() and actor.supports_counter_transfer_pose(),"human raster preserves behavior without claiming rigid art")
 var parcel:int=w.parcel.get_instance_id()
 w.active_id="support-test";w.parcel_state="counter";w._parcel_phase="customer_handoff";w.parcel.show()
 var generation:int=w._parcel_generation
 w._begin_counter_transfer(w.active_id,generation)
 check(actor.pose=="handoff" and w._clerk_motion._pose=="handoff","both contact poses precede transfer; begin-transfer capability is independent of renderer")
 var future:Vector2=w._clerk_motion.dialogue_anchor_parent("parcel",false)
 check(future.distance_to(w._clerk_motion.pose_anchor_parent("parcel"))<.001,"pure future parcel target equals actual recovered handoff")
 w.visual_time+=.01;w._step_customers(.01)
 check(actor.pose=="handoff" and w._clerk_motion._pose=="handoff","counter-transfer tick retains both contact poses")
 check(w.parcel.visible and not actor.pose_contains_parcel(),"human empty hands preserve one separate visible parcel")
 w._move_counter_parcel(1.0,w.active_id,generation);w._receive_counter_parcel(w.active_id,generation)
 w._finish_counter_handoff(w.active_id,generation)
 check(w._parcel_phase=="counter" and w._clerk_supports_counter_parcel() and w._clerk_motion._pose=="handoff","counter wait retains receiver support")
 w.set_dialogue_active(false);w._set_counter_poses();w._process(.01)
 check(w._clerk_motion._pose=="handoff" and not w._shop_control_available(),"dialogue and ordinary idle calls cannot take support ownership")
 var counter:Vector2=w.parcel.position
 w._loading_requested=true;w._start_robot_fetch()
 for i in 200:
  if w._parcel_phase!="robot_fetch":break
  w._step_parcel_transport(.01)
  check(w._clerk_motion._pose=="handoff" and w.parcel.position==counter,"clerk supports every fetch sample")
 check(w._parcel_phase=="robot_pickup","real fetch reaches pickup")
 var before:Vector2=w.parcel.position;var age:float=w._transport_age
 w.set_focus_active(false);w._step_parcel_transport(.5)
 check(w._transport_age==age and w.parcel.position==before and w._clerk_motion._pose=="handoff","focus pause preserves support and excludes absent time")
 w.set_focus_active(true);w._scene_paused=true;w._step_parcel_transport(.5)
 check(w._transport_age==age and w._clerk_motion._pose=="handoff","scene pause preserves exact support")
 w._scene_paused=false
 var until_contact:float=World.ROBOT_PICKUP_DURATION*World.ROBOT_REACH_FRACTION-w._transport_age
 w._step_parcel_transport(until_contact-.001)
 w.set_dialogue_active(false);w._set_counter_poses()
 check(w._clerk_supports_counter_parcel() and w._clerk_motion._pose=="handoff" and w.parcel.position==counter,"support lasts until just before actual reach contact")
 w._step_parcel_transport(.00101)
 check(not w._clerk_supports_counter_parcel() and w._clerk_motion._pose=="idle","receiver releases at existing contact boundary")
 check(w.assembly_feedback.transport_grip_point().distance_to(w.parcel.position)<.001 and w.assembly_feedback.lift_arm.visible,"real visible gripper contacts the same parcel before release")
 var after_contact:Vector2=w.parcel.position
 w._receive_counter_parcel(w.active_id,generation)
 check(w.parcel.position==after_contact and w._parcel_phase=="robot_pickup","stale pre-fetch generation cannot reclaim parcel")
 w.fastforward_loading(w.active_id)
 check(w.parcel_state=="loaded" and w._clerk_motion._pose=="ready" and w.parcel.get_instance_id()==parcel,"skip settles one existing parcel without stale supporting hands")
 check(actor.binding_snapshot()==binding and JSON.stringify(data)==original,"support chain leaves identity and caller orders unchanged")
 # A pending counter transfer cancelled by a different order cannot replay.
 w.parcel_state="counter";w._parcel_phase="counter_transfer";w.parcel.show();w._clerk_state="counter";w._actor_pose(w.clerk,"clerk",true)
 generation=w._parcel_generation;w.update_shop_state(data) # Exercise the real order-clear transaction.
 check(w.parcel_state=="empty" and w._parcel_phase=="empty" and not w._clerk_supports_counter_parcel(),"real order cancellation releases support ownership before choosing the neutral pose")
 w._begin_counter_transfer("support-test",generation);w._receive_counter_parcel("support-test",generation)
 check(not w.parcel.visible and w._clerk_motion._pose=="idle" and w.active_id.is_empty(),"cancel and order generation guards reject stale support callbacks")
 w.queue_free();viewport.queue_free();await process_frame
 print("RECOVERY_COUNTER_SUPPORT passed=",passed," failed=",failed);quit(1 if failed else 0)
