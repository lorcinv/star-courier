extends SceneTree
const Motion=preload("res://scripts/shop_locomotion_2d.gd")
const STATES:Array[String]=["idle","start","move","inertial_stop","stop"]
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func fresh(at:Vector2=Vector2(276,486),right:float=3400.0):
 var m=Motion.new();m.configure(right);m.adopt_position(at);m.set_input(0.0,true);return m
func step(m,seconds:float,dt:float=1.0/120.0) -> void:
 for i in floori(seconds/dt):m.step(dt)
 var remainder:float=seconds-floorf(seconds/dt)*dt
 if remainder>.000001:m.step(remainder)
func run() -> void:
 check(Motion.MOVE_SPEED==155.0 and Motion.WALK_SPEED==Motion.MOVE_SPEED,"one 155 px/s movement speed; legacy route alias is identical")
 check(Motion.ACCELERATION==700.0 and Motion.BRAKING==750.0 and Motion.REVERSAL_BRAKING==1000.0 and Motion.STOP_SETTLE_SECONDS==.12,"acceleration, normal/reverse braking and stopped settle duration match the movement contract")
 for direction in [-1.0,1.0]:
  var label:String="left" if direction<0 else "right"
  var m=fresh(Vector2(1500,496));var before:Vector2=m.position
  check(m.state=="idle" and m.velocity==0,"%s begins in relaxed idle"%label)
  m.set_input(direction);m.step(1.0/120.0)
  check(m.state=="start" and m.velocity*direction>0 and absf(m.velocity)<Motion.MOVE_SPEED,"%s input enters a real accelerating start"%label)
  check(m.facing_right==(direction>0) and m.position.x*direction>before.x*direction,"%s faces and moves in its actual direction"%label)
  step(m,.3)
  check(m.state=="move" and m.velocity==direction*Motion.MOVE_SPEED,"%s start settles into the only moving gait"%label)
  var stayed_single:bool=true
  for i in 360:
   m.step(1.0/120.0);stayed_single=stayed_single and m.state=="move" and absf(m.velocity)==Motion.MOVE_SPEED
  check(stayed_single,"%s long hold never unlocks another speed or gait"%label)
  var snap:Dictionary=m.snapshot()
  check(not snap.has("hold_seconds") and snap.has("stop_age") and snap.state in STATES,"%s snapshot exposes five-state motion without hold/run bookkeeping"%label)
  before=m.position;var d:float=m.distance
  m.set_input(0.0);m.step(1.0/120.0)
  check(m.state=="inertial_stop" and absf(m.velocity)<Motion.MOVE_SPEED and absf(m.velocity)>0 and m.distance>d,"%s release brakes with actual inertial travel"%label)
  var stopped:bool=false
  for i in 40:
   m.step(1.0/120.0)
   if m.state=="stop":stopped=true;break
  check(stopped and m.velocity==0,"%s reaches a zero-velocity stopped settle state"%label)
  check(absf(m.position.distance_to(before)-Motion.MOVE_SPEED*Motion.MOVE_SPEED/(2.0*Motion.BRAKING))<.002,"%s release integrates the exact braking distance"%label)
  check(m.facing_right==(direction>0),"%s stopped pose keeps its last real facing"%label)
  before=m.position;d=m.distance;step(m,.09)
  check(m.state=="stop" and m.position==before and m.distance==d,"%s stopped settle freezes position and foot phase"%label)
  step(m,.04);check(m.state=="idle" and m.stop_age==Motion.STOP_SETTLE_SECONDS,"%s stopped settle becomes relaxed idle after 0.12 seconds"%label)
  step(m,2.0);check(m.position==before and m.distance==d and m.velocity==0,"%s long idle never advances feet or distance"%label)
  m.set_input(direction);m.step(1.0/120.0)
  check(m.state=="start" and m.stop_age==0,"%s fresh movement cleanly leaves the stopped sequence"%label)
 for axis in [-.15,.15,-.6,.6]:
  var m=fresh(Vector2(1500,496));m.set_input(axis);step(m,1.0)
  check(absf(m.velocity-Motion.MOVE_SPEED*axis)<.00001 and m.state=="move","analog %s scales the sole target after the router deadzone"%axis)
 var m=fresh(Vector2(1000,496));m.set_input(1.0);step(m,1.0)
 var before:Vector2=m.position;var d:float=m.distance
 m.set_input(-1.0);m.step(1.0/120.0)
 check(m.state=="inertial_stop" and m.velocity>0 and m.facing_right and m.position.x>before.x,"reversal first brakes in the old physical direction")
 step(m,.2)
 check(m.state=="start" and m.velocity<0 and not m.facing_right,"reversal accelerates anew only after old velocity reaches zero")
 step(m,.25);check(m.state=="move" and m.velocity==-Motion.MOVE_SPEED,"reversal reaches the same one speed on the opposite side")
 check(m.distance>d+absf(m.position.x-before.x),"a reversal counts both physical legs rather than only their net displacement")
 m.set_input(0.0);step(m,.25);before=m.position;d=m.distance
 check(m.state=="stop","a released full-speed reversal reaches the stop phase")
 m.set_input(1.0);m.step(1.0/120.0)
 check(m.state=="start" and m.distance>d and m.position.x>before.x,"new input can interrupt stopped settling without a hold threshold")
 m=fresh(Vector2(1000,496));m.set_input(1.0);step(m,1.0);m.set_input(.2);m.step(1.0/120.0)
 check(m.state=="inertial_stop" and m.velocity>Motion.MOVE_SPEED*.2,"reducing analog demand brakes rather than snapping speed")
 step(m,.3);check(m.state=="move" and absf(m.velocity-31.0)<.00001,"reduced analog demand settles into the same gait")
 for inactive_context in ["modal","hidden","focus_lost","loading","flight"]:
  m=fresh();m.set_input(1.0);step(m,.8);before=m.position;d=m.distance
  m.set_input(1.0,false);step(m,1.0)
  check(m.velocity==0 and m.state=="idle" and m.position==before and m.distance==d and not m.snapshot().active,"%s immediately freezes physical motion and feet"%inactive_context)
  m.set_input(1.0,true);step(m,.5)
  check(m.position==before and m.snapshot().needs_neutral,"%s re-entry cannot consume a held direction"%inactive_context)
  m.set_input(0.0,true);m.set_input(1.0,true);m.step(.1)
  check(m.position!=before and m.state=="start","%s neutral then fresh input starts from rest"%inactive_context)
 m=fresh();m.navigate_to(m.coordinate_for_front_x(800));step(m,.5);before=m.position;d=m.distance
 m.set_input(0.0,false);step(m,1.0)
 check(m.velocity==0 and m.position==before and m.distance==d and m.is_navigating() and m.snapshot().navigation_paused,"disabled context freezes retained click navigation and removes its momentum")
 m.set_input(1.0,true);step(m,.5)
 check(m.position==before and m.velocity==0,"retained navigation cannot move through a non-neutral UI re-entry")
 m.set_input(0.0,true);m.step(1.0/120.0)
 check(m.state=="start" and m.position!=before and m.velocity<10,"neutral re-arms a retained navigation route from zero speed")
 m.set_input(0.0,false);before=m.position;m.navigate_to(m.coordinate_for_front_x(900));step(m,.5)
 check(m.position==before and m.velocity==0,"a new route request cannot override an inactive context")
 m.set_input(0.0,false,true);step(m,.3)
 check(m.position!=before and m.state=="move" and not m.snapshot().enabled,"explicit story navigation can run while direct input remains gated")
 var speed:float=m.velocity;m.set_input(0.0,false,true);m.step(1.0/120.0)
 check(m.velocity==speed,"repeated permitted story updates preserve continuous physical velocity")
 m.set_input(0.0,false);before=m.position;d=m.distance;step(m,.5)
 check(m.velocity==0 and m.position==before and m.distance==d,"removing the story exception immediately freezes its route")
 m=fresh();m.set_input(1.0);var path_safe:bool=true;var corners:bool=false;var spacing:bool=true
 for i in 3000:
  m.set_blockers([Vector2(516,486),Vector2(1800,486)])
  var previous:Vector2=m.position;m.step(1.0/120.0)
  path_safe=path_safe and (m.position.x<=452.001 and absf(m.position.y-486)<.001 or absf(m.position.x-452)<.001 and m.position.y>=486 and m.position.y<=496 or absf(m.position.y-496)<.001 and m.position.x>=452)
  corners=corners or m.position.y>486.1 and m.position.y<495.9
  spacing=spacing and m._foot_gap(m.position,Vector2(516,486))>=1.0 and m._foot_gap(m.position,Vector2(1800,486))>=1.0 and m.position.distance_to(previous)<=Motion.MOVE_SPEED/120.0+.001
 check(path_safe and corners,"direct input follows the actual counter end and separate foreground floor lane")
 check(spacing,"route maintains robot floor clearance and the single-speed per-step displacement cap")
 check(m.position==Vector2(3400,496) and m.velocity==0 and m.state=="idle","expanded right boundary stops feet and settles into relaxed idle")
 before=m.position;d=m.distance;step(m,2.0)
 check(m.position==before and m.distance==d,"holding into a boundary cannot advance foot distance")
 m.set_input(-1.0);m.step(.1);check(m.velocity<0 and m.state=="start","leaving a boundary starts the same ordinary movement ramp")
 m=fresh(Vector2(620,486));before=m.position
 check(m.position==before and m.joining_route(),"adopting a cutscene endpoint does not teleport the visible actor")
 m.set_input(1.0);m.step(.1)
 check(m.position.x==620 and m.position.y>486 and m.position.y<496,"first movement physically connects the workbench to the foreground aisle")
 step(m,.5);check(m.position.y==496 and not m.joining_route(),"connector reaches the actual aisle without a floor snap")
 m=fresh();m.set_input(1.0);step(m,1.0);m.navigate_to(80.0);m.set_input(1.0);m.step(1.0/120.0)
 check(m.velocity>0.0 and m.velocity<Motion.MOVE_SPEED and m.state=="inertial_stop" and m.is_navigating(),"click return brakes existing momentum and ignores the old held direction until neutral")
 step(m,5.0);check(m.arrived() and m.position==Vector2(276,486),"click return reverses naturally and settles at the exact counter")
 m=fresh(Vector2(800,496));m.navigate_to(80.0);var returned:bool=false;var limit:bool=true;d=m.distance
 for i in 1600:
  before=m.position;m.step(1.0/120.0);limit=limit and m.position.distance_to(before)<=Motion.MOVE_SPEED/120.0+.001
  if m.arrived():returned=true;break
 check(returned and m.position==Vector2(276,486) and m.velocity==0 and m.state=="stop","click route returns exactly home through both corners and enters stop")
 check(limit,"click route never teleports or accelerates to expanded-room catch-up speed")
 check(absf(m.distance-d-534.0)<.001,"click route counts its entire physical path, including the final arrival distance")
 before=m.position;d=m.distance;step(m,.13)
 check(m.state=="idle" and m.position==before and m.distance==d,"arrived navigation settles without foot phase drift")
 m=fresh(Vector2(620,486));m.navigate_to(m.coordinate);step(m,.5)
 check(m.arrived() and m.position==Vector2(620,496) and absf(m.distance-10.0)<.001,"navigation to the adopted coordinate still walks the entire connector")
 m=fresh();m.navigate_to(m.coordinate);m.step(.01)
 check(m.arrived() and m.distance==0 and m.velocity==0,"a request for the current point never manufactures a footstep")
 m=fresh();m.set_blockers([Vector2(444,486)]);m.set_input(1.0);step(m,3.0)
 check(m.position.x<=386.01 and m.position.y==486 and m.velocity==0 and m.state=="idle","an occupied counter opening blocks feet and settles to idle")
 before=m.position;d=m.distance;step(m,1.0)
 check(m.position==before and m.distance==d,"holding into a robot cannot animate invisible movement")
 m.set_input(-1.0);step(m,.1);check(m.velocity<0,"an obstruction always permits retreat")
 m.set_blockers([]);m.set_input(1.0);step(m,2.0);check(m.position.y==496,"clearing the opening permits ordinary movement again")
 m=fresh(Vector2(864,496),864.0);before=m.position;m.configure(3400.0)
 check(m.position==before,"expansion changes the route bound without relocating the actor")
 m.set_input(1.0);step(m,1.0);check(m.position.x>864 and m.position.x<1020,"an expanded route is reached by ordinary single-speed travel")
 m=fresh(Vector2(196,486));m.set_input(-1.0);step(m,1.0)
 check(m.position==Vector2(196,486) and m.distance==0 and m.velocity==0,"the rear counter boundary blocks without movement or phase advance")
 var variants:Array=[]
 for dt in [1.0/30.0,1.0/60.0,1.0/120.0,1.0/144.0]:
  var candidate=fresh(Vector2(1000,496));candidate.set_input(1.0);step(candidate,.7,dt)
  candidate.set_input(-1.0);step(candidate,.6,dt);candidate.set_input(0.0);step(candidate,.4,dt);variants.append(candidate.snapshot())
 for i in [0,1,3]:
  check(absf(float(variants[i].distance)-float(variants[2].distance))<.002 and absf(float(variants[i].coordinate)-float(variants[2].coordinate))<.002 and variants[i].state==variants[2].state,"30/60/120/144 Hz variant %d preserves travel, reversal and stop state"%i)
 m=fresh(Vector2(1000,496));m.set_input(1.0);step(m,1.0)
 check(absf(m.distance-(Motion.MOVE_SPEED-Motion.MOVE_SPEED*Motion.MOVE_SPEED/(2.0*Motion.ACCELERATION)))<.00001,"acceleration integrates exact distance across the target-speed crossing")
 before=m.position;m.step(20.0)
 check(m.position.distance_to(before)<=Motion.MOVE_SPEED*Motion.MAX_FRAME_SECONDS+.01,"a hitch is capped at 0.1 seconds of the only movement speed")
 before=m.position;d=m.distance
 for bad in [0.0,-1.0,INF,NAN]:m.step(bad)
 check(m.position==before and m.distance==d,"nonpositive and nonfinite time cannot contaminate coordinates")
 m.set_input(NAN);step(m,.5);check(m.velocity==0 and m.position.is_finite(),"invalid axis decelerates safely to finite rest")
 m.set_input(INF);step(m,.5);check(m.velocity==0 and m.position.is_finite(),"infinite axis is treated as neutral")
 before=m.position;m.configure(NAN);m.adopt_position(Vector2(INF,NAN));m.navigate_to(NAN);m.set_blockers([Vector2(NAN,0),null,"bad"],NAN)
 check(m.position==before and is_finite(m.route_length()),"invalid route, endpoint, goal and obstacle data leave finite geometry intact")
 print("SHOP_LOCOMOTION_2D passed=",passed," failed=",failed);quit(1 if failed else 0)
