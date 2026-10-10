extends SceneTree
const Motion=preload("res://scripts/shop_locomotion_2d.gd")
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
 var m=fresh();m.set_input(.15);step(m,2.0)
 check(absf(m.velocity-Motion.WALK_SPEED*.15)<.001 and m.hold_seconds==0 and m.state=="walk","adapter-deadzoned light analog tilt walks gently without a second deadzone or run charge")
 m=fresh();m.set_input(1.0);step(m,.20)
 check(m.velocity>140.0 and m.velocity<=Motion.WALK_SPEED and m.state=="walk","brief hold reaches walk with a real acceleration ramp")
 step(m,.25);check(m.velocity==Motion.WALK_SPEED and m.hold_seconds<.5,"under-threshold hold stays a walk")
 step(m,.30);check(m.velocity==Motion.RUN_SPEED and m.state=="run","continuous half-second hold becomes genuine run state")
 var before:Vector2=m.position;var d:float=m.distance;var speed:float=m.velocity
 m.set_input(0.0);m.step(1.0/120.0)
 check(m.velocity>0 and m.velocity<speed and m.position!=before,"release brakes smoothly instead of instant stop")
 step(m,.5);check(m.velocity==0.0 and m.state=="idle","release settles at rest")
 d=m.distance;before=m.position;step(m,2.0)
 check(m.distance==d and m.position==before,"rest freezes exact phase and feet")
 m=fresh();m.set_input(1.0);step(m,1.0);before=m.position
 m.set_input(-1.0);m.step(1.0/120.0)
 check(m.velocity>0.0 and m.facing_right and m.position!=before,"reversal initially brakes in the real old direction")
 step(m,.25);check(m.velocity<0.0 and not m.facing_right and m.hold_seconds<.5,"reversal changes facing only after velocity reverses and resets run hold")
 step(m,.5);check(m.state=="run" and m.velocity==-Motion.RUN_SPEED,"sustained opposite hold can run left")
 m.set_input(1.0,false);d=m.distance;before=m.position;step(m,1.0)
 check(m.velocity==0 and m.hold_seconds==0 and m.position==before,"disabled context immediately clears motion and held-run charge")
 m.set_input(1.0,true);step(m,.5);check(m.position==before and m.snapshot().needs_neutral,"held direction cannot leak through context re-entry")
 m.set_input(0.0,true);m.set_input(1.0,true);step(m,.1);check(m.position!=before and m.state=="walk","neutral then new input starts a fresh walk")
 m=fresh();m.set_input(1.0);var path_safe:bool=true;var corners:bool=false;var spacing:bool=true
 for i in 1800:
  m.set_blockers([Vector2(516,486),Vector2(1800,486)])
  var previous:Vector2=m.position;m.step(1.0/120.0)
  path_safe=path_safe and (m.position.x<=452.001 and absf(m.position.y-486)<.001 or absf(m.position.x-452)<.001 and m.position.y>=486 and m.position.y<=496 or absf(m.position.y-496)<.001 and m.position.x>=452)
  corners=corners or m.position.y>486.1 and m.position.y<495.9
  spacing=spacing and m._foot_gap(m.position,Vector2(516,486))>=1.0 and m._foot_gap(m.position,Vector2(1800,486))>=1.0 and m.position.distance_to(previous)<=2.501
 check(path_safe and corners,"A/D follows the actual counter end and a separate foreground floor lane")
 check(spacing,"route maintains robot floor clearance with bounded per-step displacement")
 check(m.position==Vector2(3400,496) and m.velocity==0 and m.hold_seconds==0,"expanded right boundary blocks movement and cannot charge run")
 m.set_input(-1.0);m.step(.1);check(m.velocity<0 and m.state=="walk","leaving boundary starts walking rather than retaining wall-charged run")
 m=fresh(Vector2(620,486));before=m.position
 check(m.position==before and m.joining_route(),"adopting the cutscene endpoint does not teleport the visible actor")
 m.set_input(1.0);m.step(.1)
 check(m.position.x==620 and m.position.y>486 and m.position.y<496,"first manual motion steps physically from workbench into foreground aisle")
 step(m,.5);check(m.position.y==496 and not m.joining_route(),"connector reaches the same real aisle without a floor snap")
 m=fresh();m.set_input(1.0);step(m,1.0);m.navigate_to(80.0);m.set_input(1.0);m.step(1.0/120.0)
 check(m.velocity>0.0 and m.velocity<Motion.RUN_SPEED and m.is_navigating(),"click return brakes existing run momentum and ignores the old held direction until neutral")
 step(m,5.0);check(m.arrived() and m.position==Vector2(276,486),"click return reverses naturally and settles at the exact counter")
 m=fresh(Vector2(800,496));m.navigate_to(80.0);var returned:bool=false;var limit:bool=true
 for i in 1600:
  before=m.position;m.step(1.0/120.0);limit=limit and m.position.distance_to(before)<=Motion.WALK_SPEED/120.0+.001
  if m.arrived():returned=true;break
 check(returned and m.position==Vector2(276,486) and m.velocity==0,"click route returns exactly home through both counter corners")
 check(limit,"click route never teleports or accelerates to expanded-room catch-up speed")
 m=fresh(Vector2(276,486));m.set_blockers([Vector2(444,486)]);m.set_input(1.0);step(m,3.0)
 check(m.position.x<=386.01 and m.position.y==486 and m.velocity==0 and m.hold_seconds==0,"temporarily occupied counter opening blocks feet and run charge")
 m.set_input(-1.0);step(m,.1);check(m.velocity<0,"an obstruction always allows retreat")
 m.set_blockers([]);m.set_input(1.0);step(m,2.0);check(m.position.y==496,"cleared opening permits ordinary movement again")
 var variants:Array=[]
 for dt in [1.0/30.0,1.0/60.0,1.0/120.0]:
  var candidate=fresh();candidate.set_input(1.0);step(candidate,2.0,dt);candidate.set_input(0.0);step(candidate,.4,dt);variants.append(candidate.snapshot())
 check(absf(float(variants[0].distance)-float(variants[2].distance))<.02 and absf(float(variants[1].distance)-float(variants[2].distance))<.02,"30/60/120 Hz traces preserve the same physical distance and run threshold")
 m=fresh();m.set_input(1.0);step(m,.8);before=m.position;m.step(20.0)
 check(m.position.distance_to(before)<=Motion.RUN_SPEED*Motion.MAX_FRAME_SECONDS+.01,"a hitch cannot catch up twenty seconds or cross geometry")
 before=m.position;d=m.distance
 for bad in [0.0,-1.0,INF,NAN]:m.step(bad)
 check(m.position==before and m.distance==d,"nonpositive and nonfinite time cannot contaminate coordinates")
 m.set_input(NAN);step(m,.5);check(m.velocity==0 and m.position.is_finite(),"invalid axis safely decelerates to a finite rest")
 print("SHOP_LOCOMOTION_2D passed=",passed," failed=",failed);quit(1 if failed else 0)
