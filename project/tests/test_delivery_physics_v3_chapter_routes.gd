extends SceneTree
## Small actual chapter-route experiment. Scripted held inputs prove mechanical
## feasibility/cost, not human playability or a complete game/session acceptance.
const Sim=preload("res://scripts/pilot_delivery_simulation_v3.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func fly(level:int,with_pad:bool=true,gentle:bool=false)->Dictionary:
 var s=Sim.new();var r:Dictionary=Chapter.fresh_route(level)
 s.configure(Profile.starter_design(),Profile.starter_launcher() if with_pad else [],r,42)
 s.release_launcher(15.0,0.2 if level==3 else 1.0)
 var waypoints:Array=[]
 if level==1:waypoints=[Vector2(34,-15 if not gentle else 6),Vector2(80,-8)]
 elif level==2:waypoints=[Vector2(40,-10),Vector2(74,-12),Vector2(110,-18)]
 else:waypoints=[Vector2(35,-7),Vector2(64,-10),Vector2(95,-10)]
 var index:int=0;var max_acceleration:float=1.8 if gentle else (2.8 if level==3 else 3.5)
 var cruise:float=5.0 if gentle else (7.0 if level==3 else 9.0)
 for tick in range(60*90):
  if s.status!="running":break
  var at:Vector2=s.cargo_position()
  if at.distance_to(waypoints[index])<4.0 and index<waypoints.size()-1:index+=1
  var delta:Vector2=waypoints[index]-at
  var desired_speed:float=minf(cruise,sqrt(2.0*max_acceleration*maxf(0.0,delta.length()-1.0)))
  var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  var desired:Vector2=(delta.normalized()*desired_speed-b.velocity).limit_length(max_acceleration)
  var thrust:float=0.0
  for p in b.parts:
   if p.type=="thruster" and p.alive:thrust+=float(p.param)*float(p.output_factor)*float(r.free_drive_throttle)
  var input:Vector2=desired*float(b.mass)/maxf(0.01,thrust)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false)
  s.step(1.0/60.0)
 var result:Dictionary={"level":level,"strategy":"gentle" if gentle else ("launch" if with_pad else "no_pad"),"status":s.status,"time":s.elapsed,"energy_j":s.telemetry.energy_used,"energy_cost":float(s.telemetry.energy_used)*float(r.pilot_energy_tariff),"integrity":s.ship_integrity(),"peak_acceleration":s.telemetry.cargo_peak_acceleration,"contact_impulse":s.telemetry.cargo_contact_impulse,"position":[s.cargo_position().x,s.cargo_position().y],"failure":s.telemetry.delivery_failure}
 print("CHAPTER_PHYSICS_SAMPLE ",JSON.stringify(result))
 return result
func teleport(level:int)->Dictionary:
 var ship:Array=[part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"battery",-1,1,300),part(9,"teleporter",0,1,16,{"input_a":-2})]
 var s=Sim.new();var r:Dictionary=Chapter.fresh_route(level);s.configure(ship,[],r,42);s.release_launcher(0,0)
 for tick in range(40):
  if s.status!="running":break
  var delta:Vector2=Vector2(float(r.distance),float(r.destination_y))-s.cargo_position()
  var direction:Vector2=delta.normalized()
  s.set_free_flight_input(roundi(direction.x*1000),roundi(direction.y*1000),false,tick%2==0,9,false)
  s.step(1.0/60.0)
 var result:Dictionary={"level":level,"strategy":"two_cell_teleport","status":s.status,"time":s.elapsed,"energy_j":s.telemetry.energy_used,"energy_cost":float(s.telemetry.energy_used)*float(r.pilot_energy_tariff),"integrity":s.ship_integrity(),"position":[s.cargo_position().x,s.cargo_position().y],"failure":s.telemetry.delivery_failure}
 print("CHAPTER_PHYSICS_SAMPLE ",JSON.stringify(result))
 return result
func _initialize()->void:
 for level in [1,2,3]:
  var launched:Dictionary=fly(level,true,false)
  var gentle:Dictionary=fly(level,true,true)
  var transit:Dictionary=teleport(level)
  check(launched.status=="success","actual chapter%d standard steering completes"%level)
  check(gentle.status=="success","actual chapter%d gentler/different path completes"%level)
  check(transit.status=="success" or transit.status=="failed","teleport comparison reaches a determinate result on chapter%d"%level)
  if transit.status=="success":check(float(transit.energy_cost)>float(launched.energy_cost)*2.0,"two-cell teleport no longer dominates energy cost on chapter%d"%level)
  if level==1:
   var no_pad:Dictionary=fly(level,false,false)
   check(no_pad.status=="success" and float(launched.time)<float(no_pad.time),"real first chapter paid launch changes delivery time")
 print("DELIVERY_CHAPTER_ROUTES_V3 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
