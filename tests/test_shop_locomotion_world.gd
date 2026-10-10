extends SceneTree
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
var passed:int=0
var failed:int=0
var world
var viewport:SubViewport
var arrivals:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func step(seconds:float,axis:float=0.0,enabled:bool=true) -> void:
 for i in ceili(seconds*120):
  world.set_shop_input(axis,enabled);world._process(1.0/120.0);world.assembly_feedback._process(1.0/120.0)
func run() -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 world.show_design(Profile.starter_design());world.focus("hub",true)
 world.shop_navigation_arrived.connect(func(id:String):arrivals.append(id))
 step(.01)
 check(world.is_at_shop_counter() and world.shop_interaction().id=="focus_counter","fresh shop exposes the actual nearby counter")
 var parcel:int=world.parcel.get_instance_id();var generation:int=world._parcel_generation;var position:Vector2=world.clerk.position
 step(.4,1.0)
 check(world.clerk.position.x>position.x and world.clerk.position.y==486 and world.clerk.z_index==0,"short A/D walk remains occluded behind the counter")
 check(not world.is_at_shop_counter(),"acceptance guard fails away from exact counter home")
 step(1.2,1.0)
 check(world.clerk.position.x>600 and world.clerk.position.y==496 and world.clerk.z_index==11,"held direction rounds the counter onto the authored front deck")
 check(world.shop_locomotion_snapshot().state=="run","world applies the distance-driven held-run state")
 check(world.shop_locomotion_snapshot().motion.pose=="run","run movement uses the distinct registered run artwork")
 position=world.clerk.position;var distance:float=world._clerk_walk_distance
 world.set_shop_input(0.0,false);step(.5,1.0,false)
 check(world.clerk.position==position and world._clerk_walk_distance==distance,"modal context freezes position and raster phase")
 check(world.shop_locomotion_snapshot().motion.pose=="idle" and world.clerk.flip_h,"modal stop settles into visibly right-facing standing art, correctly mirroring the native left-facing original")
 step(.5,1.0,true)
 check(world.clerk.position==position,"held key cannot restart after modal closes")
 step(.01,0.0);step(.1,-1.0)
 check(world.clerk.position.x<position.x,"fresh opposite press restores control")
 step(.3,0.0)
 check(world.shop_locomotion_snapshot().motion.pose=="idle" and not world.shop_locomotion_snapshot().motion.facing_right and not world.clerk.flip_h,"leftward stop preserves the actual native left-facing pixels without restarting phase")
 position=world.clerk.position
 for i in 10:
  world.focus("hub");world.show_design(Profile.starter_design());world.update_shop_state({"contracts":[],"active_contract_id":""})
 check(world.clerk.position==position,"generic render and empty order refresh never relocate a roaming clerk")
 check(not world.request_shop_navigation("focus_counter"),"distant counter click starts an asynchronous physical route")
 var continuous:bool=true;var began:Vector2=world.clerk.position
 for i in 1800:
  position=world.clerk.position;step(1.0/120.0)
  continuous=continuous and world.clerk.position.distance_to(position)<=World.ShopLocomotion2D.WALK_SPEED/120.0+.01
  if arrivals.size()>0:break
 check(continuous and arrivals==["focus_counter"] and world.is_at_shop_counter() and began!=world.clerk.position,"counter click walks both route corners and emits exactly one arrival at home")
 world.focus("contracts");check(world.is_at_shop_counter(),"counter acceptance stays valid inside the counter drawer")
 world.focus("hub");step(.01);step(1.1,1.0);step(.3)
 position=world.clerk.position
 check(not world.prepare_counter_interaction(),"story preparation queues a physical return from manual position")
 for i in 1800:
  step(1.0/120.0,0.0,false)
  if not world._clerk_return_requested:break
 check(world.is_at_shop_counter() and world.clerk.position!=position,"pending story return works while manual input remains gated")
 step(.01);step(1.2,1.0);world.set_focus_active(false);position=world.clerk.position
 step(.8,1.0);check(world.clerk.position==position,"focus loss freezes direct movement")
 world.set_focus_active(true);step(.4,1.0);check(world.clerk.position==position,"focus return requires a neutral and fresh movement")
 step(.01);world.hide();position=world.clerk.position;step(.3,1.0)
 world.show();step(.3,1.0);check(world.clerk.position==position,"hidden lifecycle cannot restart a held key")
 step(.01);world.focus("flight");position=world.clerk.position;step(.2,1.0)
 check(world.clerk.position==position,"flight context never drives shop movement")
 world.focus("hub");step(.01);check(not world.prepare_counter_interaction(),"post-flight free clerk keeps continuous return ownership")
 for i in 1800:
  step(1.0/120.0,0.0,false)
  if not world._clerk_return_requested:break
 check(world.is_at_shop_counter(),"post-flight return reaches exact counter without a vertical snap")
 step(.01);step(4.0,1.0)
 check(world.clerk.position==Vector2(864,496) and world.shop_locomotion_snapshot().state=="idle" and world.shop_locomotion_snapshot().motion.pose=="idle","running into base boundary stops short of machinery and stands instead of freezing an airborne frame")
 world.request_shop_navigation("focus_counter")
 for i in 1800:
  step(1.0/120.0)
  if world.is_at_shop_counter():break
 for tier in [1,2]:
  world.set_workshop_tier(tier);world.focus("hub");step(.01);step(11.0,1.0)
  var snap:Dictionary=world.shop_locomotion_snapshot()
  check(world.clerk.position.x>2000 and world.clerk.position.y==496 and world.clerk.position.x<=world.workshop_exit_x()-96,"tier "+str(tier)+" reaches its real expanded bay and stops before launch machinery")
  check(world.target_zoom==1.0 and absf(world.target_center.x-world.clerk.position.x)<600,"tier "+str(tier)+" follows the clerk at readable scale")
  if tier==1:world.request_shop_navigation("focus_counter")
  else:world.prepare_counter_interaction()
  var follow_ok:bool=true
  for i in 4200:
   step(1.0/120.0,0.0,tier==1)
   follow_ok=follow_ok and world.target_zoom==1.0 and absf(world.target_center.x-world.clerk.position.x)<600
   if world.is_at_shop_counter():break
  check(world.is_at_shop_counter() and follow_ok,"tier "+str(tier)+" has a visible connected return path to counter even with manual input gated")
 check(world.parcel.get_instance_id()==parcel and world._parcel_generation==generation and world.active_id.is_empty(),"roaming and interaction routes preserve parcel/order identity")
 world.queue_free();viewport.queue_free();await process_frame
 print("SHOP_LOCOMOTION_WORLD passed=",passed," failed=",failed);quit(1 if failed else 0)
