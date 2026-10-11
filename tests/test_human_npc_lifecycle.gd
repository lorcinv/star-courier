extends SceneTree
## Isolated mechanics fixture. This is NOT native input or gameplay evidence.
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
 var world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 world.show_design(Profile.starter_design());world.focus("hub",true)
 var data:Dictionary={"phase":"morning","active_contract_id":"","contracts":[{"contract_id":"human-lifecycle","status":"available","appearance_id":"human_courier","species":"human","appearance_seed":123,"accessory_id":"none","story_id":"spoon_at_the_station","story_node":0}]}
 var original:String=JSON.stringify(data)
 world.update_shop_state(data)
 var customer:Dictionary=world.customers["human-lifecycle"];var node=customer.node
 var binding:Dictionary=node.binding_snapshot();var parcel:int=world.parcel.get_instance_id();var order:String=world.active_id
 for i in 300:world.visual_time+=1.0/120.0;world._step_customers(1.0/120.0)
 check(node.position==Vector2(148,488) and node.visible,"human actually approaches the authoritative counter root")
 check(node._motion._model.settled and node.texture==null and node._motion._rig.visible,"human stops in one supported cutout body")
 check(world.is_at_shop_counter() and world.shop_interaction().get("id","")=="focus_counter","nearby counter interaction stays authoritative")
 var snapshot:Dictionary=node._motion._model.snapshot();var time:float=world.visual_time
 world.set_focus_active(false);world._process(.5)
 check(world.visual_time==time and node._motion._model.snapshot()==snapshot,"focus loss freezes root, feet, pose and clock")
 world.set_focus_active(true);world._process(.01)
 check(node._motion._model.pose_time-time<.02,"focus resume excludes absent time")
 world._scene_paused=true;snapshot=node._motion._model.snapshot();time=world.visual_time;world._process(.5)
 check(world.visual_time==time and node._motion._model.snapshot()==snapshot,"pause freezes exact visible human rig")
 world._scene_paused=false;world.reduced_motion=true;world._process(.02)
 check(node._motion._model.shoulder_offset==Vector2.ZERO,"reduced motion disables idle breathing without changing support")
 node.set_pose(true)
 check(node.texture!=null and node._motion._full_pose_active and not node.pose_contains_parcel(),"human handoff remains one empty-handed full body")
 node.set_pose(false)
 check(node.texture==null and node._motion._rig.visible,"quiet return restores exactly one relaxed body")
 # Same parcel moves only while receiver is visibly ready; the human giver
 # holds its empty hands through contact. No gameplay acceptance API is used.
 world.active_id="human-lifecycle";world.parcel_state="counter";world._parcel_phase="customer_handoff"
 var generation:int=world._parcel_generation
 world._begin_counter_transfer("human-lifecycle",generation)
 check(node.pose=="handoff" and world._clerk_motion._pose=="handoff","giver and receiver are ready before parcel travel")
 var handoff_anchor:Vector2=node.parcel_point()
 for i in 5:
  world._move_counter_parcel(i/4.0,"human-lifecycle",generation)
  world.visual_time+=.01;world._step_customers(.01)
  check(node.pose=="handoff" and world._clerk_motion._pose=="handoff","both contact poses persist through transfer")
 check(world.parcel.get_instance_id()==parcel and node.parcel_point()==handoff_anchor,"one parcel and original giver anchor during transfer")
 world._receive_counter_parcel("human-lifecycle",generation)
 check(world._parcel_phase=="clerk_handoff" and world.parcel.position==world._actor_parcel_point(world.clerk,"clerk"),"parcel ends at original receiver anchor")
 world.active_id=order;world._parcel_phase="empty";world.parcel_state="empty"
 # Permanent regression: consume EXACTLY the remainder of farewell. The root
 # has zero displacement on this tick; that is not completion of the exit.
 customer.departure="farewell";customer.departure_age=World.CUSTOMER_FAREWELL_DURATION-.01
 customer.target=node.position;customer.walk_target=node.position;customer.walk_age=0.0
 var start:Vector2=node.position
 world.visual_time+=.01;world._step_customers(.01)
 check(customer.departure=="exiting" and node.visible and node.position==start,"first zero-displacement exit tick cannot hide the customer")
 var travelled:float=0.0;var monotonic:bool=true;var hidden_early:bool=false
 for i in 600:
  var before:Vector2=node.position;world.visual_time+=1.0/120.0;world._step_customers(1.0/120.0)
  travelled+=node.position.distance_to(before)
  monotonic=monotonic and node.position.x<=before.x+.0001 and node.position.distance_to(before)<=World.CUSTOMER_WALK_SPEED/120.0+.01
  if not node.visible and node.position!=Vector2(World.CUSTOMER_EXIT_X,488):hidden_early=true
  if customer.departure=="departed":break
 check(monotonic and travelled>327.9,"actual exit travels the whole authored path at one speed")
 check(not hidden_early and customer.departure=="departed" and not node.visible and node.position==Vector2(World.CUSTOMER_EXIT_X,488),"hide occurs only after actual path completion")
 check(node.binding_snapshot()==binding and JSON.stringify(data)==original,"identity, story and caller order data remain unchanged")
 check(world.parcel.get_instance_id()==parcel and world.active_id==order,"exit keeps parcel instance and active-order ownership unchanged")
 node.set_conversation(true);check(not node.visible,"late dialogue cannot resurrect a departed actor")
 world.queue_free();viewport.queue_free();await process_frame
 print("HUMAN_NPC_LIFECYCLE passed=",passed," failed=",failed);quit(1 if failed else 0)
