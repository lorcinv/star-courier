extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_ascent_simulation_v4.gd")
const Profile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const OldProfile=preload("res://scripts/pilot_delivery_profile_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0.0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func craft(kind:String)->Array:
 if kind=="light":return [part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"thruster",-1,-1,28),part(4,"thruster",-1,1,28),part(5,"thruster",1,0,28)]
 if kind=="endurance":return [part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"battery",1,0,300),part(4,"thruster",0,-1,28),part(5,"thruster",0,1,28)]
 return [part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(9,"teleporter",0,1,16,{"input_a":-2})]
func make(ship:Array=[],pad:bool=true,data:Dictionary={}):
 var s=Sim.new();s.configure(craft("light") if ship.is_empty() else ship,Profile.starter_launcher() if pad else [],Profile.route() if data.is_empty() else data,42);return s
func _initialize()->void:
 identity();field_and_preview();events();flights();failures()
 print("ASCENT_PHYSICS_V4 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func identity()->void:
 var r:Dictionary=Profile.route();check(not r.is_empty() and Profile.validation_error(r).is_empty(),"new explicit ascent profile validates")
 check(not OldProfile.validation_error(r).is_empty(),"old v3 refuses unknown v4 instead of ignoring altitude fields")
 var decoded:Dictionary=JSON.parse_string(JSON.stringify(r));check(Profile.validation_error(decoded).is_empty(),"v4 fully realized route survives JSON without reauthoring")
 var bad:Dictionary=r.duplicate(true);bad.ascent_meteor_events[0].warning_seconds=2.9
 check(not Profile.validation_error(bad).is_empty(),"less than3seconds warning rejected")
 bad=r.duplicate(true);bad.gravity=2.8;check(not Profile.validation_error(bad).is_empty(),"duplicate inherited gravity rejected")
 check(Profile.route(r).is_empty(),"committed ascent cannot be reauthored")
func field_and_preview()->void:
 var s=make();var snapshot:Dictionary=s.route.duplicate(true)
 var ground:Dictionary=s.environment_at(Vector2(0,0));var sky:Dictionary=s.environment_at(Vector2(0,-150));var space:Dictionary=s.environment_at(Vector2(0,-300))
 check(ground.phase=="ground" and sky.phase=="upper_air" and space.phase=="space" and ground.gravity>sky.gravity and sky.gravity>space.gravity,"real altitude changes gravity wind and phase")
 check(s.environment_at(Vector2(10000,-150))==sky,"horizontal progress cannot unlock a flight phase")
 check(s.environment_at(Vector2(0,-101)).phase=="upper_air" and s.environment_at(Vector2(0,-99)).phase=="ground","descending restores the corresponding environment")
 check(absf(float(s.environment_at(Vector2(0,-100.001)).gravity)-float(s.environment_at(Vector2(0,-99.999)).gravity))<0.001,"phase boundary physical field is continuous")
 var preview:Dictionary=s.preview_launcher(90,1);s.release_launcher(90,1)
 for tick in range(360):s.set_free_flight_input(0,0);s.step(1.0/120.0)
 check(s.cargo_position().distance_to(preview.trajectory[-1])<0.01,"3second launch preview matches actual neutral fixed-step trajectory")
 check(s.route==snapshot,"environment integration never mutates committed route")
 check(s.ship_integrity()==1.0,"freefall gravity alone never crushes cargo")
 var a=make([],false);var body:Dictionary=a.body_for_part(1);body.position.y=-150.0;a.release_launcher(0,0);a.step(1.0/120.0)
 check(body.velocity.x>0.0 and body.velocity.y>0.0,"high-air wind and gravity produce actual motion")
func events()->void:
 var first=make([],false);first.body_for_part(1).position=Vector2(80,-281);first.release_launcher(0,0)
 for i in range(360):first.step(1.0/120.0)
 check(first.telemetry.ascent_meteors_spawned==0 and first.telemetry.ascent_warnings.size()==3,"warning precedes every physical meteor birth for at least3seconds")
 for i in range(240):first.step(1.0/120.0)
 check(first.telemetry.ascent_meteors_spawned==3 and first.obstacles.size()==6,"finite shower creates3 actual collision hazards")
 var moving:Dictionary=first.obstacles[3];var at:Vector2=moving.position;first.step(1.0/120.0)
 check(moving.position.distance_to(at+moving.velocity/120.0)<0.0001,"meteor artwork and collision entity share actual velocity")
 var replay=make([],false);replay.body_for_part(1).position=Vector2(80,-281);replay.release_launcher(0,0)
 for i in range(601):replay.step(1.0/120.0)
 check(replay.telemetry.ascent_event_state==first.telemetry.ascent_event_state and replay.obstacles==first.obstacles and replay.parts==first.parts,"same input replay rebuilds identical warnings births geometry and cargo")
 var stationary=make([],false);stationary.body_for_part(1).position=Vector2(90,-350);stationary.release_launcher(0,0)
 var low_body:Dictionary=stationary.bodies[0]
 # Body field samples are local, not borrowed from a route progress counter.
 check(stationary.environment_at(low_body.position).phase=="space","environment can be queried at each real body position")
func fly(kind:String,cruise:float)->Dictionary:
 var s=make(craft(kind));s.release_launcher(90,1)
 var points:Array=[Vector2(22,-80),Vector2(22,-195),Vector2(-12,-315),Vector2(14,-460),Vector2(40,-560)]
 var index:int=0;var phases:Dictionary={};var min_energy:float=INF
 for tick in range(60*180):
  if s.status!="running":break
  var at:Vector2=s.cargo_position();var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  var field:Dictionary=s.environment_at(b.position);phases[field.phase]=true
  if at.distance_to(points[index])<7.0 and index<points.size()-1:index+=1
  var delta:Vector2=points[index]-at
  var speed:float=minf(cruise,sqrt(2.0*2.8*maxf(0.0,delta.length()-1.0)))
  var requested:Vector2=(delta.normalized()*speed-b.velocity).limit_length(3.0)-Vector2(0,float(field.gravity))-Vector2(field.wind)
  var output:float=0.0
  for p in b.parts:
   if p.type=="thruster" and p.alive:output+=float(p.param)*float(p.output_factor)*0.72
  var input:Vector2=requested*float(b.mass)/maxf(0.01,output)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false);s.step(1.0/60.0)
  min_energy=minf(min_energy,float(s.telemetry.energy_remaining))
 var result:Dictionary={"kind":kind,"status":s.status,"time":s.elapsed,"energy_j":s.telemetry.energy_used,"remaining":s.telemetry.energy_remaining,"integrity":s.ship_integrity(),"phase_count":phases.size(),"meteors":s.telemetry.ascent_meteors_spawned,"contact_impulse":s.telemetry.cargo_contact_impulse,"altitude":s.telemetry.altitude_m,"position":[s.cargo_position().x,s.cargo_position().y],"failure":s.telemetry.delivery_failure}
 print("ASCENT_BUILD_SAMPLE ",JSON.stringify(result));return result
func flights()->void:
 var light:Dictionary=fly("light",12.0);var endurance:Dictionary=fly("endurance",8.0)
 check(light.status=="success" and light.integrity>=0.8 and light.phase_count==4,"165cost3nozzle1cell plus205pad completes all4 physical altitude stages")
 check(endurance.status=="success" and endurance.integrity>=0.8 and endurance.phase_count==4,"170cost2nozzle2cell plus205pad also completes within same375budget")
 check(float(light.time)<float(endurance.time) and float(light.remaining)<float(endurance.remaining),"budget variants trade delivery speed against stored energy margin")
func failures()->void:
 var ballistic=make([part(1,"cargo",0,0,100),part(2,"battery",-1,0,300)]);ballistic.release_launcher(90,1);var peak:float=0.0
 for i in range(120*20):
  if ballistic.status!="running":break
  ballistic.step(1.0/120.0);peak=maxf(peak,float(ballistic.telemetry.altitude_m))
 check(ballistic.status=="failed" and ballistic.telemetry.delivery_failure=="returned_to_ground" and peak<100.0,"launcher alone cannot fake continuous ascent and falling back ends recoverably")
 var transit=make(craft("teleport"),false);transit.release_launcher(90,0)
 for tick in range(60*120):
  if transit.status!="running":break
  transit.set_free_flight_input(0,-1000,false,tick%2==0,9,false);transit.step(1.0/60.0)
 check(transit.status=="failed" and transit.telemetry.delivery_failure=="returned_to_ground","pure onecell teleport runs out of usable jump budget and returns without a softlock")
 check(transit.telemetry.delivery_teleport_energy>0 and transit.ship_integrity()==1.0,"teleporter remains legal and paid; failure is range/gravity rather than an item ban")
