extends SceneTree
## Actual World + real title-selected bootstrap. Headless positional/camera
## metrics only; this is not native input or subjective animation approval.
const World=preload("res://scripts/world_view_2d.gd")
const Bootstrap=preload("res://scripts/clerk_runtime_bootstrap_observed_v4.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
const Motion=preload("res://scripts/shop_locomotion_2d.gd")
var passed:int=0
var failed:int=0
var reports:Array=[]
var issues:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:
  failed+=1
  if issues.size()<24:issues.append(label);push_error(label)
func run() -> void:
 for tier in 3:
  for running in [false,true]:
   var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
   var world=World.new();world.set_workshop_tier(tier)
   check(world.configure_clerk_pose_bootstrap(Bootstrap),"title bootstrap selected before World construction")
   viewport.add_child(world);world.set_process(false)
   if not world._clerk_pose_setup_error.is_empty():
    check(false,"bootstrap failed: "+world._clerk_pose_setup_error);viewport.free();continue
   world.assembly_feedback.set_process(false);world.show_design(Profile.starter_design());world.focus("hub",true)
   world.set_shop_input(0.0,true,false);world._process(1.0/120.0)
   var outward:Dictionary=trip(world,world._shop_motion.coordinate_for_front_x(world.assembly_origin.x),1.0,running)
   outward.tier=tier;outward.direction="counter_to_workbench";reports.append(outward)
   for i in 120:
    world.set_shop_input(0.0,true,false);world._process(1.0/120.0)
   check(world._clerk_motion._model.settled,"actual workbench stop settles feet")
   var returning:Dictionary=trip(world,World.CLERK_HOME_X-Motion.COUNTER_MIN_X,-1.0,running)
   returning.tier=tier;returning.direction="workbench_to_counter";reports.append(returning)
   for i in 120:
    world.set_shop_input(0.0,true,false);world._process(1.0/120.0)
   check(world._clerk_motion._model.settled,"actual return stop settles feet")
   check(world._motion_failures.is_empty(),"World accepts run/return ownership and pose samples")
   viewport.free()
 print("DEV03_SHOP_TRAVERSAL ",JSON.stringify({"passed":passed,"failed":failed,"trips":reports,"first_failures":issues}))
 quit(1 if failed else 0)
func trip(world,goal:float,direction:float,running:bool) -> Dictionary:
 var speed:float=Motion.RUN_SPEED if running else Motion.WALK_SPEED
 var distance:float=absf(goal-world._shop_motion.coordinate)
 var predicted:float=distance/speed+speed/(2.0*Motion.ACCELERATION)
 var elapsed:float=0.0;var reached:bool=false;var max_reach:float=0.0;var min_screen:float=INF;var max_screen:float=-INF
 var max_camera_step:float=0.0;var max_head_scale_error:float=0.0;var max_speed:float=0.0;var contact_count:int=0
 var previous:Dictionary=world._clerk_motion._model.snapshot()
 for tick in 3600:
  var camera_before:Vector2=world.camera.position
  world.set_shop_input(direction,true,running);world._process(1.0/120.0);elapsed+=1.0/120.0
  var body:Dictionary=world._clerk_motion._model.snapshot()
  max_reach=maxf(max_reach,float(body.max_reach_error));max_speed=maxf(max_speed,absf(world._shop_motion.velocity))
  check(body.reach_feasible and body.max_reach_error<.002,"traversal keeps pose reachable")
  check(body.feet.far.planted or body.feet.near.planted,"traversal keeps real support")
  for side in ["far","near"]:
   if body.feet[side].planted and body.feet[side].landing_id!=previous.feet[side].landing_id:contact_count+=1
   if body.feet[side].planted and previous.feet[side].planted and body.feet[side].landing_id==previous.feet[side].landing_id:
    check(body.feet[side].position.distance_to(previous.feet[side].position)<.001,"same contact stays anchored across floor corner")
  previous=body
  var head:Sprite2D=world._clerk_motion._parts.head
  max_head_scale_error=maxf(max_head_scale_error,absf(head.transform.x.length()-.875))
  max_head_scale_error=maxf(max_head_scale_error,absf(head.transform.y.length()-.875))
  var screen_x:float=(world.clerk.position.x-world.camera.position.x)*world.camera.zoom.x+640.0
  min_screen=minf(min_screen,screen_x);max_screen=maxf(max_screen,screen_x)
  max_camera_step=maxf(max_camera_step,world.camera.position.distance_to(camera_before))
  if (world._shop_motion.coordinate-goal)*direction>=0.0:reached=true;break
 check(reached,"actual trip reaches station center without geometry relocation")
 check(absf(elapsed-predicted)<.025,"actual trip time matches bounded physical prediction")
 check(min_screen>=80.0 and max_screen<=1200.0,"running clerk remains in readable camera bounds")
 check(max_head_scale_error<.00001,"actual rendered head basis keeps exact scale")
 return {"gait":"run" if running else "walk","distance_px":distance,"predicted_seconds":predicted,"actual_seconds":elapsed,"station_center_reached":reached,"peak_speed":max_speed,"max_reach_error":max_reach,"contacts":contact_count,"screen_x_min":min_screen,"screen_x_max":max_screen,"max_camera_step_120hz":max_camera_step,"max_head_scale_error":max_head_scale_error}
