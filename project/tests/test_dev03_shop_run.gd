extends SceneTree
## Synthetic deterministic input + actual production motion/contact model.
## No physical keyboard/controller or rendered-animation acceptance claim.
const Motion=preload("res://scripts/shop_locomotion_2d.gd")
const Pose=preload("res://scripts/clerk_shop_run_pose_v1.gd")
const Arms=preload("res://scripts/clerk_walk_arm_v4.gd")
const Router=preload("res://scripts/courier_input.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
class InputProbe extends "res://scripts/courier_input.gd":
 func desired_context() -> String:return context
var passed:int=0
var failed:int=0
var first_failures:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:
  failed+=1
  if first_failures.size()<24:first_failures.append(label);push_error(label)
func hold(router,code:int,down:bool=true) -> void:
 var token:String="k:%d"%code
 if down:router._keys[token]=true
 else:router._keys.erase(token);router._blocked.erase(token)
func stick(router,value:float) -> void:
 router.active_device=0;router._axes["a:0:0"]=value
 if absf(value)<=router.deadzone:router._blocked.erase("a:0:0")
func body_at(at:Vector2=Vector2(4000,496)):
 var motion=Motion.new();motion.configure(10000);motion.adopt_position(at);motion.set_input(0.0,true);return motion
func run() -> void:
 var router=InputProbe.new();router.context="shop"
 check(Router.ACTION_KEYS.shop_run==[KEY_SHIFT],"physical Shift has an explicit shop action")
 hold(router,KEY_D)
 check(router.shop_axis()==1.0 and not router.shop_running(),"D alone walks")
 hold(router,KEY_SHIFT)
 check(router.shop_running(),"D+Shift runs")
 hold(router,KEY_A)
 check(not router.shop_running(),"opposed keys cannot run")
 hold(router,KEY_D,false);hold(router,KEY_A,false);hold(router,KEY_SHIFT,false)
 for zone in [.10,.22,.45]:
  router.deadzone=zone;stick(router,zone-.01)
  check(router.shop_axis()==0 and not router.shop_running(),"deadzone drift does not move/run")
  stick(router,.60);check(not router.shop_running(),"partial stick walks")
  stick(router,.79);check(router.shop_running(),"high stick magnitude enters run")
  for magnitude in [.77,.75,.66,.74]:
   stick(router,magnitude);check(router.shop_running(),"hysteresis retains run above leave point")
  stick(router,.63);check(not router.shop_running(),"lower stick leaves run")
  stick(router,-.90);check(router.shop_running() and router.shop_axis()<0,"left full stick also runs")
  router.quarantine();check(not router.shop_running() and router.shop_axis()==0,"modal quarantine suppresses held run axis")
  stick(router,0);stick(router,.8);check(router.shop_running(),"neutral then fresh stick restores run")
  router.context="phone";check(not router.shop_running(),"phone owns run input")
  router.context="shop";router.quarantine();stick(router,0)
 router.free()
 for direction in [-1.0,1.0]:
  var motion=body_at();motion.set_input(direction,true,false,true)
  for i in 120:motion.step(1.0/120.0)
  check(is_equal_approx(absf(motion.velocity),Motion.RUN_SPEED),"run reaches bounded 260 px/s")
  motion.set_input(direction,true,false,false);motion.step(1.0/120.0)
  check(absf(motion.velocity)>Motion.WALK_SPEED and absf(motion.velocity)<Motion.RUN_SPEED,"Shift release decelerates into walk")
  for i in 60:motion.step(1.0/120.0)
  check(is_equal_approx(absf(motion.velocity),Motion.WALK_SPEED),"walk remains 155 px/s")
  motion.set_input(direction,true,false,true)
  for i in 60:motion.step(1.0/120.0)
  var at:Vector2=motion.position;motion.set_input(0.0,true,false,false)
  for i in 120:motion.step(1.0/120.0)
  check(absf(motion.position.distance_to(at)-Motion.RUN_SPEED*Motion.RUN_SPEED/(2.0*Motion.BRAKING))<.01,"run stopping distance is physically integrated")
  check(motion.state=="idle" and motion.velocity==0 and motion.facing_right==(direction>0),"stop settles with actual final facing")
  motion.set_input(direction,true,false,true);motion.step(.1);motion.set_input(0,false)
  at=motion.position;motion.set_input(direction,true,false,true);motion.step(.1)
  check(motion.position==at and not motion.snapshot().running_requested,"context resume rejects held run")
  motion.set_input(0,true);motion.set_input(direction,true,false,true);motion.step(.1)
  check(motion.position!=at,"fresh movement resumes after neutral")
 for right in [true,false]:
  for frame_dt in [1.0/120.0,1.0/60.0,1.0/30.0,.1]:
   var walk:Dictionary=pose_case(right,frame_dt,false)
   var running:Dictionary=pose_case(right,frame_dt,true)
   check(running.contacts>walk.contacts,"run advances actual foot contacts faster than walk")
   check(running.peak_run>.9 and walk.peak_run==0.0,"pose switches from observed velocity without changing idle/walk")
 # Route timing documents physical distances; geometry/profile is untouched.
 for tier in 3:
  var route_distance:float=Profile.assembly_origin(tier).x-276.0+10.0
  print("SHOP_TRAVEL tier=%d distance=%.0f walk=%.3f run=%.3f seconds_from_rest_before_stop"%[tier,route_distance,route_distance/Motion.WALK_SPEED+Motion.WALK_SPEED/(2.0*Motion.ACCELERATION),route_distance/Motion.RUN_SPEED+Motion.RUN_SPEED/(2.0*Motion.ACCELERATION)])
 print("DEV03_SHOP_RUN passed=%d failed=%d first_failures=%s"%[passed,failed,str(first_failures)])
 quit(1 if failed else 0)
func pose_case(right:bool,frame_dt:float,running:bool) -> Dictionary:
 var motion=body_at();var model=Pose.new();var arms=Arms.new()
 var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/2d_v5/actors/clerk_runtime_bootstrap_v1/upper-response-v2.0.json"))
 check(model.configure(profile,210),"live run pose accepts unchanged approved source profile")
 check(arms.configure(210),"live arm provider configures")
 model.reset(motion.position,right,0.0,0.0)
 var clock:float=0.0;var previous:Dictionary=model.snapshot();var contact_count:int=0;var peak:float=0.0
 var armed:bool=false
 for frame in ceili(3.0/frame_dt):
  var time:float=float(frame)*frame_dt
  motion.set_input((1.0 if right else -1.0) if time<2.0 else 0.0,true,false,running)
  motion.step(frame_dt)
  for segment in motion.presentation_segments().segments:
   var row:Dictionary=segment.after;clock+=float(segment.dt)
   check(model.update(row.state,row.distance,row.position,row.facing_right,clock,row.stop_age),"actual observed root slice accepted")
   var now:Dictionary=model.snapshot();peak=maxf(peak,float(now.run_weight))
   check(now.max_reach_error<.002 and now.reach_feasible,"run retains fixed-length reachable leg chains")
   check(now.feet.far.planted or now.feet.near.planted,"at least one real support foot remains grounded")
   check(is_equal_approx(float(now.upper_body.head_scale),.875),"head source scale stays fixed across run/stop")
   for side in ["far","near"]:
    var foot:Dictionary=now.feet[side];var old:Dictionary=previous.feet[side]
    if foot.planted and old.planted and foot.landing_id==old.landing_id:
     check(foot.position.distance_to(old.position)<.001,"one planted contact cannot slide")
    if foot.planted and foot.landing_id!=old.landing_id:contact_count+=1
    if foot.planted:check(absf(foot.position.y-motion.position.y)<.001,"flat-route planted foot matches authored floor")
   check(arms.advance(now,float(row.velocity),clock),"arm gait consumes exactly the real accepted root velocity/time")
   if armed:
    for side in ["far","near"]:
     var arm:Dictionary=arms.snapshot().arms[side]
     check(absf(Vector2(arm.shoulder[0],arm.shoulder[1]).distance_to(Vector2(arm.elbow[0],arm.elbow[1]))-float(arm.lengths[0]))<.001,"running upper arm length remains exact")
   armed=true;previous=now
 var frozen:Dictionary=model.snapshot()
 check(not model.update("idle",motion.distance,motion.position,right,clock+1.0,0.0,false),"disabled model consumes no running time")
 check(model.snapshot()==frozen,"disabled run pose freezes exact accepted snapshot")
 return {"contacts":contact_count,"peak_run":peak}
