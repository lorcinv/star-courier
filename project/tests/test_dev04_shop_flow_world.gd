extends SceneTree
## Deterministic real-World regression. No OS/native-input claim.
## Optional DEV04_CAPTURE_DIR writes native-rendered tier0/1/2 home frames.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
var passed:int=0
var failed:int=0
var world
var viewport:SubViewport
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func order(id:String,status:String="available") -> Dictionary:
 return {"contract_id":id,"status":status,"appearance_id":"human_courier","species":"human","appearance_seed":107,"accessory_id":"none"}
func update(contracts:Array,active:String="",released:bool=false,loaded:bool=false) -> void:
 world.update_shop_state({"phase":"day","contracts":contracts,"active_contract_id":active,"handoff_released":released,"cargo_loaded":loaded})
func step(seconds:float) -> void:
 for unused in ceili(seconds*120):
  if world._parcel_tween!=null:
   world._parcel_tween.pause();world._parcel_tween.custom_step(1.0/120.0)
  world._process(1.0/120.0);world.assembly_feedback._process(1.0/120.0)
func make_world(tier:int) -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 world.set_workshop_tier(tier);world.show_design(Profile.starter_design());world.focus("hub",true)
func drop_world() -> void:
 viewport.queue_free();await process_frame;world=null;viewport=null
func capture(tier:int) -> void:
 var directory:String=OS.get_environment("DEV04_CAPTURE_DIR")
 if directory.is_empty():return
 DirAccess.make_dir_recursive_absolute(directory)
 await process_frame;await RenderingServer.frame_post_draw
 var path:String=directory.path_join("tier%d-home.png"%tier)
 check(viewport.get_texture().get_image().save_png(path)==OK,"native tier frame written "+path)
func run() -> void:
 for tier in [0,1,2]:
  make_world(tier)
  update([])
  check(not world.can_request_shop_navigation("focus_counter") and not world.request_shop_navigation("focus_counter"),"tier%d empty counter rejects both projection and direct intent"%tier)
  check(world.target_zoom==1.0 and world.target_center==Vector2(640,360),"tier%d hub uses grounded readable shell, not transparent full-bay extent"%tier)
  await capture(tier)
  var data:Array=[order("A"),order("B"),order("C")]
  update(data)
  check(world.counter_customer_id().is_empty() and world.counter_customer_id(false)=="A","tier%d approaching customer owns queue but cannot yet talk"%tier)
  check(not world.can_request_shop_navigation("focus_counter"),"tier%d arrival is required"%tier)
  step(2.0)
  check(world.has_counter_customer("A") and not world.has_counter_customer("B") and world.can_request_shop_navigation("focus_counter"),"tier%d only physically arrived first customer is actionable"%tier)
  world.customers.A.node.hide()
  check(not world.has_counter_customer("A") and not world.request_shop_navigation("focus_counter"),"hidden actor cannot authorize conversation")
  world.customers.A.node.show()
  data[0].status="settled";update(data)
  check(world.counter_customer_id(false)=="B" and world.customers.C.target.x<0,"settled first row advances exactly one next customer")
  step(3.0)
  check(world.has_counter_customer("B") and not world.has_counter_customer("C"),"queue successor arrives without overlapping third visitor")
  world.night=true
  check(world.counter_customer_id().is_empty(),"night counter cannot acquire a visitor")
  await drop_world()
  # Reloaded accepted state must not lose its required handoff or fly a box
  # from an offscreen giver. Exercise the actual customer arrival and tween.
  make_world(tier);var accepted:Array=[order("accepted","accepted")]
  update(accepted,"accepted",true,false)
  var parcel:int=world.parcel.get_instance_id()
  check(world._parcel_phase=="waiting_customer" and world._counter_arrival_handoff,"accepted restart retains a pending handoff until giver arrives")
  var before:Vector2=world.customers.accepted.node.position
  step(.2)
  check(world.customers.accepted.node.position.x>before.x and world._parcel_phase=="waiting_customer","saved giver physically approaches before parcel transfer")
  step(24.0)
  check(world.is_parcel_loaded("accepted") and world.parcel.get_instance_id()==parcel,"tier%d accepted restart finishes the same parcel exactly once"%tier)
  var start:Vector2=world.clerk.position
  var parcel_at:Vector2=world.parcel.position;var generation:int=world._parcel_generation
  var expected:float=maxf(.25,absf(start.x-World.COUNTER_EDGE_X)/World.COOPERATIVE_WALK_SPEED+World.AssemblyFeedback.MOTION_RAMP_SECONDS)+maxf(.25,(World.COUNTER_EDGE_X-World.CLERK_HOME_X)/World.COOPERATIVE_WALK_SPEED+World.AssemblyFeedback.MOTION_RAMP_SECONDS)
  world.start_flight()
  check(world._clerk_return_requested and world.clerk.position==start,"dispatch schedules physical return without root/parcel snap")
  var elapsed:float=0.0;var max_step:float=0.0
  while world._clerk_return_requested and elapsed<expected+2.0:
   var previous:Vector2=world.clerk.position;step(1.0/120.0);elapsed+=1.0/120.0
   max_step=maxf(max_step,world.clerk.position.distance_to(previous))
  check(not world._clerk_return_requested and world.clerk.position==Vector2(276,486),"tier%d return completes while actual World mode is flight"%tier)
  check(max_step<=World.COOPERATIVE_WALK_SPEED/120.0+.02,"return keeps normal grounded root speed with no jump")
  check(world.parcel.position==parcel_at and world.parcel.get_instance_id()==parcel and world._parcel_generation==generation and world.active_id=="accepted","return never transfers active parcel ownership")
  print("DEV04_RETURN_TIME ",JSON.stringify({"tier":tier,"from_x":start.x,"baseline_after_receipt_s":expected,"actual_physical_return_s":elapsed,"after_12s_flight_s":maxf(0.0,elapsed-12.0),"max_root_step":max_step}))
  await drop_world()
 print("DEV04_SHOP_FLOW_WORLD passed=%d failed=%d native_input=false"%[passed,failed]);quit(1 if failed else 0)
