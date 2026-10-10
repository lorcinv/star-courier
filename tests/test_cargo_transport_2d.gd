extends SceneTree
## Renderer-only coverage; durable loading/save/launch gates live in controller suite.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
const PHASES:Array[String]=["waiting_customer","customer_handoff","counter_transfer","clerk_handoff","robot_fetch","robot_pickup","robot_turn","clerk_round_counter","clerk_join","robot_carry","robot_insert","clerk_align","clerk_confirm","loaded"]
var passed:int=0
var failed:int=0
var viewport:SubViewport
var world
var completed:Array[String]=[]
var current:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func contract(id:String,released:bool=false,loaded:bool=false) -> Dictionary:
 return {"contract_id":id,"status":"accepted","appearance_id":"human_courier","species":"human","appearance_seed":712,"accessory_id":"none","handoff_released":released,"cargo_loaded":loaded}
func update(value:Dictionary) -> void:
 current=value.duplicate(true)
 world.update_shop_state({"contracts":[] if value.is_empty() else [value],"active_contract_id":str(value.get("contract_id",""))})
 if world._parcel_tween!=null:world._parcel_tween.pause()
func reset(id:String="A",released:bool=false,loaded:bool=false) -> void:
 update({});world.reduced_motion=false;world.show();world.set_focus_active(true);world.focus("hub");step(24.0)
 world.show_design(Profile.starter_design());update(contract(id,released,loaded))
 if world.customers.has(id):world.customers[id].node.position=world.customers[id].target
 world._sync_customer_parcel()
func step(seconds:float) -> void:
 for i in ceili(seconds*120):
  if world._parcel_tween!=null and world._focus_active and world.is_visible_in_tree():world._parcel_tween.custom_step(1.0/120.0)
  world._process(1.0/120.0);world.assembly_feedback._process(1.0/120.0)
func reach(phase:String,id:String="A") -> void:
 reset(id)
 if phase=="waiting_customer":return
 update(contract(id,true))
 for i in 1400:
  if world._parcel_phase==phase:return
  step(1.0/120.0)
 check(false,"reachable phase "+phase)
func visible_parcels() -> int:
 var total:int=1 if world.parcel.visible else 0
 for entry in world.customers.values():
  if entry.node.visible and entry.node.pose_contains_parcel():total+=1
 for node in world.ship_root.get_children():
  if node is Sprite2D and bool(node.get_meta("is_cargo",false)) and node.visible:total+=1
 return total
func signal_count(id:String) -> int:return completed.count(id)
func test_continuity() -> void:
 reset("continuous")
 var instance:int=world.parcel.get_instance_id();var age:float=world.visual_time
 check(not world.customers.continuous.node.pose_contains_parcel() and world.parcel.visible and world.parcel.position==world.customers.continuous.node.parcel_point(),"verified empty-handed human holds the real external parcel while dialogue waits")
 step(1.0)
 check(world._parcel_phase=="waiting_customer" and not world.is_loading() and visible_parcels()==1,"unread dialogue retains one customer parcel without starting delivery")
 check(world.customers.continuous.node.position==Vector2(148,488) and world.clerk.position==Vector2(276,486),"idle feet remain on their registered floor")
 var clerk_angle:float=world.clerk.rotation;step(.5)
 check(clerk_angle!=world.clerk.rotation and world.clerk.scale==Vector2.ONE*210.0/240.0,"subtle clerk idle changes angle without deforming or scaling the body")
 update(contract("continuous",true))
 var seen:Array[String]=[];var single:bool=true;var connected:bool=true;var floor_ok:bool=true;var elapsed:float=0.0
 for i in 1400:
  if not world._parcel_phase in seen:seen.append(world._parcel_phase)
  single=single and visible_parcels()==1 and world.parcel.get_instance_id()==instance
  floor_ok=floor_ok and world.assembly_feedback.robot_root.position.y==486 and world.assembly_feedback.robot_root.position.x>=436 and world.assembly_feedback.robot_root.position.x<=818
  if world._parcel_phase in ["robot_pickup","robot_turn","clerk_round_counter","clerk_join","robot_carry","robot_insert","clerk_align","clerk_confirm"] and world.assembly_feedback.lift_arm.visible and (world._parcel_phase!="robot_pickup" or world._transport_age>=World.ROBOT_PICKUP_DURATION*World.ROBOT_REACH_FRACTION):
   connected=connected and world.assembly_feedback.transport_grip_point().distance_to(world.parcel.position)<.01
  if world.is_parcel_loaded():break
  step(1.0/120.0);elapsed+=1.0/120.0
 check(single,"customer→counter→robot→ship always has exactly one visible parcel and reuses external node")
 check(floor_ok and connected,"robot stays on floor and original mechanical-arm grip remains attached to actual parcel")
 check(seen==PHASES.slice(1),"continuous chain visits every transfer phase in order")
 check(elapsed>=5.0 and elapsed<7.0 and world.is_parcel_loaded("continuous") and signal_count("continuous")==1,"full cooperative post-dialogue handoff loads in five to seven seconds and emits one completion")
 for i in 300:update(contract("continuous",true));world.pack_parcel();world.fastforward_loading("continuous")
 check(signal_count("continuous")==1 and world.is_parcel_loaded(),"300 stale accepted renders/repeated begins/fast-forwards cannot replay loaded cargo")
func test_reach_and_expanded_route() -> void:
 reach("robot_pickup","reach-first")
 var offered:Vector2=world.parcel.position
 step(World.ROBOT_PICKUP_DURATION*World.ROBOT_REACH_FRACTION*.65)
 check(world.parcel.position==offered and world.assembly_feedback.lift_arm.visible and world.assembly_feedback.transport_grip_point().distance_to(offered)>1.0,"clerk holds parcel stationary while a visible empty gripper approaches")
 step(World.ROBOT_PICKUP_DURATION*.30)
 check(world.assembly_feedback.transport_grip_point().distance_to(world.parcel.position)<.01 and world.parcel.position!=offered,"parcel moves only after the generated gripper makes contact")
 world.fastforward_loading()
 for tier in [1,2]:
  world.set_workshop_tier(tier)
  reset("expanded/"+str(tier))
  var design:Array=Profile.starter_design();design[0].x=8 if tier==1 else 12;world.show_design(design)
  update(contract("expanded/"+str(tier),true))
  var elapsed:float=0.0;var farthest:float=0.0;var fixed_claw:bool=true;var single:bool=true;var sane_speed:bool=true
  while not world.is_parcel_loaded() and elapsed<24.0:
   step(1.0/120.0);elapsed+=1.0/120.0
   farthest=maxf(farthest,world.assembly_feedback.debug_snapshot().robot_x)
   fixed_claw=fixed_claw and world.assembly_feedback._lift_claw.scale==Vector2.ONE*.65 and world.assembly_feedback.robot_root.position.y==486
   single=single and visible_parcels()==1
   sane_speed=sane_speed and absf(world.assembly_feedback.debug_snapshot().robot_velocity)<=World.COOPERATIVE_WALK_SPEED+1
  check(world.is_parcel_loaded() and elapsed>10.0 and elapsed<24.0 and farthest>2000 and sane_speed,"tier "+str(tier)+" walks physically to expanded cargo without time-cap gliding")
  check(world.parcel.position==world._cargo_destination and fixed_claw and single,"tier "+str(tier)+" keeps one parcel, fixed-size claw and registered floor through real destination insertion")
  check(world.clerk.position==Vector2(world._clerk_loaded_x(),486) and world.clerk.z_index==8,"tier "+str(tier)+" clerk finishes beside the real cargo in the near aisle")
 world.set_workshop_tier(0)
 reset("long-frame");update(contract("long-frame",true))
 # Complete the existing counter handoff normally, then exercise bounded phase
 # carry-over with one large active frame. This is not elapsed paused wall time.
 for i in 120:
  if world._parcel_phase=="robot_fetch":break
  step(1.0/120.0)
 world._step_parcel_transport(10.0)
 check(world.is_parcel_loaded() and signal_count("long-frame")==1,"one long active frame consumes remaining phases once with no artificial phase waits")

func test_every_phase() -> void:
 for phase in PHASES:
  var id:String="cancel/"+phase;reach(phase,id)
  var generation:int=world._parcel_generation
  update({})
  world._begin_counter_transfer(id,generation);world._receive_counter_parcel(id,generation);world._finish_counter_handoff(id,generation);world._complete_loading(id,generation)
  check(world.active_id.is_empty() and world.parcel_state=="empty" and not world.parcel.visible and world._parcel_tween==null and world.assembly_feedback.debug_snapshot().transport_owner.is_empty(),"cancel releases parcel, robot and all callbacks during "+phase)
  update(contract(id,true));step(12.0)
  check(world.is_parcel_loaded(id) and visible_parcels()==1,"same-ID reaccept starts a clean complete chain after "+phase)
  reach(phase,"old/"+phase);var old_id:String=world.active_id;generation=world._parcel_generation
  update(contract("replacement/"+phase,true));world._complete_loading(old_id,generation);step(12.0)
  check(world.is_parcel_loaded("replacement/"+phase) and signal_count("replacement/"+phase)==1,"new order rejects old completion from "+phase)
 for phase in PHASES.slice(0,PHASES.size()-1):
  var id:String="reduced/"+phase;reach(phase,id);world.reduced_motion=true
  if phase=="waiting_customer":
   check(not world.is_loading() and world._parcel_phase==phase and signal_count(id)==0,"reduced motion respects unread acceptance")
   update(contract(id,true))
  check(world.is_parcel_loaded(id) and signal_count(id)==1 and world._parcel_tween==null and visible_parcels()==1 and not world.assembly_feedback.lift_arm.visible,"reduced motion settles exact loaded state from "+phase)
  reach(phase,"fast/"+phase)
  check(not world.fastforward_loading("wrong-order") and not world.is_parcel_loaded(),"wrong-order fastforward cannot affect "+phase)
  world.fastforward_loading();world.fastforward_loading()
  check(world.is_parcel_loaded() and signal_count("fast/"+phase)==1 and world.parcel.position==world._cargo_destination,"explicit fastforward settles and notifies once from "+phase)
func test_restore_and_edits() -> void:
 reset("restored",true,true)
 check(world.is_parcel_loaded("restored") and signal_count("restored")==0 and world._parcel_tween==null and visible_parcels()==1,"loaded durable snapshot restores without replay or new completion")
 world.restore_loaded("wrong-order")
 check(world.active_id=="restored" and world.is_parcel_loaded(),"wrong-order restore cannot replace active identity")
 reset("seen-restart",true,false);step(12.0)
 check(world.is_parcel_loaded() and signal_count("seen-restart")==1,"seen-but-unloaded restart safely resumes one complete loading chain")
 reach("robot_carry","edits")
 var parcel_instance:int=world.parcel.get_instance_id();var generation:int=world._parcel_generation;var phase:String=world._parcel_phase
 var design:Array=Profile.starter_design()
 for i in 100:
  world.show_design(design);world.committed_edit("rotate",design[1]);update(contract("edits",true))
 check(world._parcel_phase==phase and world._parcel_generation==generation and world.assembly_feedback.debug_snapshot().transport_owner=="edits" and world.assembly_feedback.robot_pose=="carry-empty","100 rapid part edits/redraws do not hijack active cargo")
 design[0].x=1;design[0].rot=1;world.show_design(design);step(12.0)
 check(world.is_parcel_loaded() and world.parcel.get_instance_id()==parcel_instance and world.parcel.position==world.assembly_origin+Vector2(72,0),"delivery follows latest actual cargo cell after legitimate design rebuild")

func test_repeat_order_return() -> void:
 reach("robot_pickup","first-depth")
 var first_pickup_z:int=world.assembly_feedback.z_index
 check(first_pickup_z==World.ROBOT_BEHIND_COUNTER_Z,"first pickup body is behind counter while the independent claw stays above it")
 world.fastforward_loading()
 var loaded_x:float=world.assembly_feedback.transport_current_x()
 var loaded_facing:float=world.assembly_feedback.robot_root.scale.x
 var instance:int=world.parcel.get_instance_id()
 update({})
 check(world.assembly_feedback.transport_current_x()==loaded_x and world.assembly_feedback.robot_root.scale.x==loaded_facing and world._robot_return_pending and world._clerk_return_requested,"loaded cancellation preserves the real workbench position/facing and queues a safe return")
 world.committed_edit("rotate",Profile.starter_design()[1])
 check(world.assembly_feedback.transport_current_x()==loaded_x and world.assembly_feedback.robot_state=="idle" and world.assembly_feedback.debug_snapshot().actions==1,"part feedback remains active without stealing the robot's safe wait for the clerk")
 var held_clear:bool=true;var return_started:bool=false
 for i in 500:
  if not world._clerk_return_requested:
   return_started=true;break
  held_clear=held_clear and world.assembly_feedback.transport_current_x()==loaded_x
  if world.clerk.z_index>0:
   held_clear=held_clear and world.assembly_feedback.transport_current_x()-world.clerk.position.x>=World.CLERK_ESCORT_GAP-.01
  update({});step(1.0/120.0)
 check(held_clear and return_started and world.clerk.position==Vector2(World.CLERK_HOME_X,486),"cancel holds robot clear of the returning clerk until she is behind counter, even across repeated renders")
 for i in 100:
  if world.assembly_feedback.robot_state=="return":break
  step(1.0/120.0)
 step(.15)
 var returning_x:float=world.assembly_feedback.transport_current_x()
 check(returning_x<loaded_x and returning_x>World.AssemblyFeedback.DOCK_X,"empty return moves continuously from the workbench toward the original dock")
 world.set_focus_active(false);step(.5)
 check(world.assembly_feedback.transport_current_x()==returning_x,"focus loss pauses the actual empty return without resetting its position")
 world.hide();world.set_focus_active(true);step(.5)
 check(world.assembly_feedback.transport_current_x()==returning_x,"hiding the world pauses an unowned return without a hidden dock teleport")
 world.show();step(.01)
 check(world.assembly_feedback.transport_current_x()<returning_x and returning_x-world.assembly_feedback.transport_current_x()<4,"showing the world resumes the same return without catching up paused time")
 # Replace while the empty return is still in flight. Acquisition must retain
 # this exact x through the counter handoff, then fetch from there.
 var replacement_x:float=world.assembly_feedback.transport_current_x()
 update(contract("second-depth",true))
 check(world.assembly_feedback.transport_current_x()==replacement_x,"accepting the second order does not snap an interrupted return to its dock")
 var continuous:bool=true;var pickup:bool=false;var fetch_from_current:bool=false
 var previous_x:float=replacement_x
 for i in 1400:
  if world._parcel_phase=="robot_fetch":fetch_from_current=world._transport_leg_from_x==replacement_x
  if world._parcel_phase=="robot_pickup":
   pickup=true
   continuous=continuous and world.assembly_feedback.z_index==first_pickup_z and world.assembly_feedback.lift_arm.z_index==9
  continuous=continuous and absf(world.assembly_feedback.transport_current_x()-previous_x)<2.01
  previous_x=world.assembly_feedback.transport_current_x()
  if world.is_parcel_loaded():break
  step(1.0/120.0)
 check(fetch_from_current and pickup and continuous,"second fetch uses the real interrupted position, never jumps, and restores first-order pickup occlusion")
 check(world.is_parcel_loaded("second-depth") and signal_count("second-depth")==1 and world.parcel.get_instance_id()==instance,"second order still completes once using the same parcel node")
 # Immediate replacement also gates its fetch while the clerk is away.
 loaded_x=world.assembly_feedback.transport_current_x()
 update(contract("third-depth",true))
 check(world._parcel_phase=="waiting_clerk" and world.assembly_feedback.transport_current_x()==loaded_x,"direct loaded-to-new-order replacement waits for clerk without moving the robot")
 continuous=true;previous_x=loaded_x;pickup=false
 for i in 1600:
  if world._parcel_phase=="waiting_clerk":continuous=continuous and world.assembly_feedback.transport_current_x()==loaded_x
  if world._parcel_phase=="robot_pickup":pickup=true;continuous=continuous and world.assembly_feedback.z_index==first_pickup_z
  continuous=continuous and absf(world.assembly_feedback.transport_current_x()-previous_x)<2.01
  previous_x=world.assembly_feedback.transport_current_x()
  if world.is_parcel_loaded():break
  step(1.0/120.0)
 check(continuous and pickup and world.is_parcel_loaded("third-depth") and signal_count("third-depth")==1,"immediate repeat-order chain preserves physical continuity and counter depth through completion")
 update({});step(6.0)
 check(world.assembly_feedback.transport_current_x()==World.AssemblyFeedback.DOCK_X and world.assembly_feedback.robot_state=="idle" and not world._robot_return_pending,"uncancelled empty return terminates at dock once after the clerk is clear")
func test_actor_choreography() -> void:
 reset("cooperation");update(contract("cooperation",true))
 var instance:int=world.parcel.get_instance_id();var clerk_frames:Dictionary={};var npc_frames:Dictionary={}
 var behind_path:bool=true;var floor:bool=true;var escort:bool=true;var camera_follows:bool=true
 var farewell_seen:bool=false;var exit_seen:bool=false;var help_seen:Array[String]=[]
 var prior_clerk:Vector2=world.clerk.position;var prior_npc:Vector2=world.customers.cooperation.node.position
 var max_clerk_step:float=0.0;var max_npc_step:float=0.0
 for i in 1600:
  var snap:Dictionary=world.loading_snapshot()
  if snap.customer_departure=="farewell":farewell_seen=true
  if snap.customer_departure=="exiting":
   exit_seen=true
   var motion:Dictionary=snap.customer_motion.get("motion",{})
   npc_frames[str(motion.get("frame_index",-1))]=true
   check_motion_foot(motion,Vector2(snap.customer_position.x,488))
  if snap.phase in ["clerk_round_counter","clerk_join","robot_carry"] and str(snap.clerk_motion.pose)=="walk":
   clerk_frames[str(snap.clerk_motion.get("frame_index",-1))]=true
   floor=floor and snap.clerk_motion.get("foot_point",Vector2.ZERO).distance_to(world.clerk.position)<.01
  if snap.phase=="clerk_round_counter":behind_path=behind_path and world.clerk.z_index==0 and world.clerk.position.x<=World.COUNTER_EDGE_X
  if snap.phase in ["clerk_join","robot_carry","robot_insert","clerk_align","clerk_confirm","loaded"]:
   behind_path=behind_path and world.clerk.z_index==8 and world.clerk.position.x>=World.COUNTER_EDGE_X
  if snap.phase=="robot_carry":
   escort=escort and absf(absf(world.clerk.position.x-world._transport_x)-World.CLERK_ESCORT_GAP)<.02
   camera_follows=camera_follows and absf(snap.camera_center.x-maxf((world.clerk.position.x+world._transport_x)*.5,World.SCENE_SIZE.x/(2.0*snap.camera_zoom)))<1 and snap.camera_zoom>1.0
  if snap.clerk_state in ["reach","align","ready"] and not snap.clerk_state in help_seen:help_seen.append(snap.clerk_state)
  floor=floor and world.clerk.position.y==486 and world.customers.cooperation.node.position.y==488
  max_clerk_step=maxf(max_clerk_step,world.clerk.position.distance_to(prior_clerk));prior_clerk=world.clerk.position
  max_npc_step=maxf(max_npc_step,world.customers.cooperation.node.position.distance_to(prior_npc));prior_npc=world.customers.cooperation.node.position
  if world.is_parcel_loaded():break
  step(1.0/120.0)
 check(world.loading_snapshot().motion_failures.is_empty() and world._clerk_motion.debug_snapshot().diagnostics.is_empty(),"every visible choreography motion call has valid generated art")
 check(farewell_seen and exit_seen and world.customers.cooperation.departure=="departed" and not world.customers.cooperation.node.visible,"customer visibly says farewell, walks off left, and remains departed")
 check(clerk_frames.size()>=3 and not clerk_frames.has("-1") and npc_frames.size()>=3 and not npc_frames.has("-1"),"generated clerk/NPC foot cadence uses distinct authored walk frames")
 check(behind_path and floor and escort,"clerk clears the counter right edge before near-aisle occlusion and walks beside the robot on registered feet")
 check(max_clerk_step<2 and max_npc_step<2,"cooperative actor travel has no frame teleports or idle-sprite gliding")
 check(camera_follows and help_seen==["reach","align","ready"],"camera follows the actual group and clerk performs reach, align and confirmation")
 var final:Dictionary=world.loading_snapshot();step(2.0)
 check(world.loading_snapshot().clerk_position==final.clerk_position and world.assembly_feedback.robot_root.position.x==final.robot.robot_x and world.assembly_feedback.robot_state=="idle" and world.assembly_feedback.debug_snapshot().transport_owner.is_empty(),"loaded actors rest beside actual cargo without a queued robot return")
 for i in 100:update(contract("cooperation",true))
 check(world.customers.cooperation.departure=="departed" and not world.customers.cooperation.node.visible and world.parcel.get_instance_id()==instance,"accepted redraw cannot respawn departed customer or create a parcel")
 check(not world.prepare_counter_interaction(),"next counter interaction requests a natural clerk return")
 var returned_behind:bool=false;var return_path:bool=true
 for i in 800:
  if world._clerk_state=="return_behind":returned_behind=true
  if world.clerk.z_index==0:return_path=return_path and world.clerk.position.x<=World.COUNTER_EDGE_X
  if world.prepare_counter_interaction():break
  step(1.0/120.0)
 check(returned_behind and return_path and world.clerk.position==Vector2(276,486) and world.prepare_counter_interaction(),"clerk returns through edge then behind counter without teleporting")
 for phase in PHASES.slice(0,PHASES.size()-1):
  reach(phase,"identical/"+phase);world.fastforward_loading();var snap:Dictionary=world.loading_snapshot()
  check(snap.clerk_position==final.clerk_position and snap.clerk_state==final.clerk_state and snap.clerk_z==final.clerk_z and snap.customer_departure=="departed" and snap.customer_position==final.customer_position and snap.robot.robot_x==final.robot.robot_x and snap.robot.robot_state=="idle" and world.parcel.get_instance_id()==instance,"skip from "+phase+" settles identical actors and the same parcel")
 reset("restore-actors",true,true)
 check(world.clerk.position==final.clerk_position and world.customers["restore-actors"].departure=="departed" and world.assembly_feedback.robot_root.position.x==final.robot.robot_x,"durable loaded restore derives the same departed customer and cooperative resting actors")
 # An interrupted/new order must wait for the physically returning clerk.
 update(contract("return-replacement",true))
 check(world._parcel_phase=="waiting_clerk" and world.is_loading_scene(),"new order while away gates its handoff on clerk return")
 world.set_focus_active(false);var frozen:Dictionary=world.loading_snapshot();step(1.0)
 check(world.loading_snapshot().clerk_position==frozen.clerk_position and world._parcel_phase=="waiting_clerk","waiting-clerk return freezes on focus loss")
 world.set_focus_active(true);step(12.0)
 check(world.is_parcel_loaded("return-replacement") and signal_count("return-replacement")==1,"new-order return finishes one complete fresh chain")
func check_motion_foot(motion:Dictionary,expected:Vector2) -> void:
 # Fold cadence registration into the aggregate assertion without thousands of log lines.
 if motion.get("foot_point",Vector2.ZERO).distance_to(expected)>.01:failed+=1;push_error("NPC motion foot registration")

func test_customer_walk_easing() -> void:
 reset("npc-ramp")
 var customer:Dictionary=world.customers["npc-ramp"]
 customer.node.position=Vector2(-100,488);customer.erase("walk_target")
 var start:Vector2=customer.node.position
 step(.05);var first:Vector2=customer.node.position
 step(.15);var accelerating:Vector2=customer.node.position
 check(first.x-start.x>0 and first.x-start.x<World.CUSTOMER_WALK_SPEED*.05*.3,"NPC starts with grounded acceleration rather than jumping to full walk speed")
 check((accelerating.x-first.x)/.15>(first.x-start.x)/.05 and accelerating.y==488,"NPC cadence advances with actual accelerating floor travel")
 var distance:float=customer.walk_distance;world.set_focus_active(false);step(.8)
 check(customer.node.position==accelerating and customer.walk_distance==distance,"focus loss freezes NPC travel and gait distance during the ramp")
 world.set_focus_active(true);step(3.0)
 check(customer.node.position==customer.target and customer.node.position.y==488,"NPC eases to the same exact counter endpoint without foot drift")
 var duration:float=2.0;var final_step:float=1.0-world._customer_walk_progress(duration-.05,duration)
 var cruise_step:float=world._customer_walk_progress(1.05,duration)-world._customer_walk_progress(1.0,duration)
 check(final_step>0 and final_step<cruise_step*.3 and world._customer_walk_progress(duration,duration)==1.0,"analytic NPC braking slows the last step and finishes without overshoot")

func test_species_departure_and_hidden_skip() -> void:
 for pair in [["human_courier","human"],["elf_archivist","elf"],["alien_botanist","alien"],["robot_machinist","robot"]]:
  var id:String="species/"+str(pair[0]);reset(id)
  var value:Dictionary=contract(id);value.appearance_id=pair[0];value.species=pair[1];update(value)
  var identity:Dictionary=world.customers[id].node.binding_snapshot();var single:bool=true;var frames:Dictionary={}
  value.handoff_released=true;update(value)
  for i in 1200:
   single=single and visible_parcels()==1
   if world.customers[id].departure=="exiting":
    var motion:Dictionary=world.customers[id].node.debug_snapshot().motion
    frames[str(motion.frame_index)]=true
   if world.is_parcel_loaded():break
   step(1.0/120.0)
  check(world.is_parcel_loaded() and single and frames.size()>=3 and not frames.has("-1") and world.customers[id].node.binding_snapshot()==identity and not world.customers[id].node.visible,"species "+str(pair[0])+" keeps its identity, one parcel and authored departing walk")
 for phase in PHASES.slice(0,PHASES.size()-1):
  var id:String="hidden-skip/"+phase;reach(phase,id)
  world.hide();world.set_focus_active(false);world.fastforward_loading()
  check(world.is_parcel_loaded() and signal_count(id)==1,"hidden/focus-paused skip commits once from "+phase)
  world.show();world.set_focus_active(true);step(.02)
  check(world._clerk_motion.debug_snapshot().pose=="ready" and world._clerk_motion.debug_snapshot().foot_point.distance_to(world.clerk.position)<.01 and not world.customers[id].node.visible and world.assembly_feedback.robot_state=="idle","hidden skip restores exact ready art and departed customer on reveal from "+phase)
 # Replacing a carry destination during its helper gestures must restart only
 # the leg and still notify once, rather than insert into a stale cargo cell.
 for phase in ["robot_insert","clerk_align","clerk_confirm"]:
  var id:String="late-edit/"+phase;reach(phase,id)
  var instance:int=world.parcel.get_instance_id();var generation:int=world._parcel_generation
  var design:Array=Profile.starter_design();design[0].x=2;design[0].y=-1;design[0].rot=3
  world.show_design(design);step(5.0)
  check(world.is_parcel_loaded(id) and world.parcel.position==world._cargo_destination and world._parcel_generation==generation and world.parcel.get_instance_id()==instance and signal_count(id)==1,"cargo relocation during "+phase+" reuses current generation and reaches actual changed cell")

func test_leftmost_cargo_aisle() -> void:
 for cell_x in [-4,-3,-2,-1]:
  var id:String="left-cargo/"+str(cell_x);reset(id)
  var design:Array=Profile.starter_design();design[0].x=cell_x;world.show_design(design);update(contract(id,true))
  var one:bool=true;var safe:bool=true
  for i in 1800:
   one=one and visible_parcels()==1
   if world.clerk.z_index==8:safe=safe and world.clerk.position.x>=World.COUNTER_EDGE_X
   if world.is_parcel_loaded():break
   step(1.0/120.0)
  check(world.is_parcel_loaded() and one and safe and world.clerk.position.x-world._cargo_destination.x>=90.0 and world.clerk.position.y==486,"left cargo cell "+str(cell_x)+" uses safe right aisle and keeps the parcel clear of clerk head")
 var id:String="waiting-clerk-skip";update(contract(id,true))
 check(world._parcel_phase=="waiting_clerk","loaded-to-new-order establishes waiting-clerk recovery phase")
 var generation:int=world._parcel_generation;world.hide();world.fastforward_loading();world.show();step(.02)
 check(world.is_parcel_loaded(id) and signal_count(id)==1 and world._clerk_motion.debug_snapshot().pose=="ready","skip during hidden waiting-clerk recovery settles the complete loaded actors")
 update({});world._complete_loading(id,generation);step(5.0)
 check(world.active_id.is_empty() and world.parcel_state=="empty" and world.clerk.position==Vector2(276,486),"cancel after waiting-clerk skip rejects stale completion and naturally returns home")

func test_pause_and_bounds() -> void:
 for phase in PHASES.slice(1,PHASES.size()-1):
  reach(phase,"pause/"+phase)
  var at:Vector2=world.parcel.position;var robot_at:Vector2=world.assembly_feedback.robot_root.position;var visual:float=world.visual_time
  world.set_focus_active(false);step(1.0)
  check(world._parcel_phase==phase and world.parcel.position==at and world.assembly_feedback.robot_root.position==robot_at and world.visual_time==visual,"focus loss freezes parcel, robot and idle during "+phase)
  world.hide();world.set_focus_active(true);step(.5)
  check(world._parcel_phase==phase and world.parcel.position==at,"focus gain cannot resume while world remains hidden: "+phase)
  world.show();if world._parcel_tween!=null:world._parcel_tween.pause()
  step(12.0)
  check(world.is_parcel_loaded() and signal_count("pause/"+phase)==1,"visibility/focus resume continues without catch-up or duplicate completion: "+phase)
 update({});await process_frame;await process_frame
 var nodes:int=world.assembly_feedback.get_child_count();var actors:int=world.actors_root.get_child_count();var tweens:int=get_processed_tweens().size();var bounded:bool=true
 var motion_cache:Dictionary=world._clerk_motion.debug_snapshot()
 for i in 80:
  reset("bounded/"+str(i),true);step(.1+float(i%8)*.2);update({});await process_frame
  bounded=bounded and world.assembly_feedback.get_child_count()==nodes and world.actors_root.get_child_count()==actors and get_processed_tweens().size()<=tweens and world._parcel_tween==null
 check(bounded,"80 interrupted chains retain no nodes, actors or processed tweens")
 var after_cache:Dictionary=world._clerk_motion.debug_snapshot()
 check(after_cache.texture_cache_size==motion_cache.texture_cache_size and after_cache.texture_load_count==motion_cache.texture_load_count and after_cache.manifest_load_count==motion_cache.manifest_load_count,"80 interruptions reuse the same bounded generated motion resources")
func run() -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 world.loading_complete.connect(func(id:String):completed.append(id))
 test_continuity();test_reach_and_expanded_route();test_every_phase();test_restore_and_edits();test_repeat_order_return();test_actor_choreography();test_customer_walk_easing();test_species_departure_and_hidden_skip();test_leftmost_cargo_aisle();await test_pause_and_bounds()
 viewport.queue_free();await process_frame;await process_frame
 print("CARGO_TRANSPORT_2D_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
