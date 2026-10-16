extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
func part(id:int,kind:String,x:int,y:int,param:float=0)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1}
func pad()->Array:
 var rows:Array=[["beam","beam","beam","armor","spring","spring","spring"],["beam","battery","beam","armor","spring","spring","spring"],["beam","spring","spring","spring","spring","spring","spring"]]
 var out:Array=[]
 for y in range(3):
  for x in range(7):
   var kind:String=rows[y][x];var param:float=60 if kind=="spring" else (300 if kind=="battery" else (90 if kind=="armor" else 32))
   out.append(part(100+x+y*7,kind,x-3,y-1,param))
 return out
func run(kind:String)->Dictionary:
 var r:Dictionary=Chapter.fresh_route(2)
 var design:Array=[part(1,"cargo",0,0,100)]
 if kind=="powered":design.append_array([part(2,"battery",-1,0,300),part(3,"thruster",-1,1,28),part(4,"thruster",0,1,28)])
 var s=Sim.new();s.configure(design,pad() if kind=="ballistic" else Profile.starter_launcher(),r,42)
 var plan:Dictionary=s.release_launcher(61.0 if kind=="ballistic" else (90.0 if kind=="default-vertical" else 70.0),1.0)
 var points:Array=[Vector2(25,-38),Vector2(48,-88),Vector2(82,-88),Vector2(110,-72)]
 var index:int=0;var highest:float=0;var near:float=INF
 for tick in range(60*45):
  if s.status!="running":break
  var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  var at:Vector2=s.cargo_position();highest=minf(highest,at.y);near=minf(near,at.distance_to(Vector2(110,-72)))
  if kind=="powered":
   if at.distance_to(points[index])<2.0 and index<points.size()-1:index+=1
   var delta:Vector2=points[index]-at
   var speed:float=minf(5.0,sqrt(2*2.0*maxf(0,delta.length()-.2)))
   var request:Vector2=(delta.normalized()*speed-b.velocity-Vector2(-.1,.5)).limit_length(2.0)
   var output:float=0
   for q in b.parts:
    if q.type=="thruster" and q.alive:output+=float(q.param)*float(q.output_factor)*float(r.free_drive_throttle)
   var input:Vector2=request*float(b.mass)/maxf(.01,output)
   s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false)
  s.step(1.0/60.0)
 var result:Dictionary={"kind":kind,"status":s.status,"elapsed":s.elapsed,"integrity":s.ship_integrity(),"energy":s.telemetry.energy_used,"launch_energy":plan.energy_used,"launch_speed":plan.speed,"mass":plan.mass,"contact":s.telemetry.cargo_contact_impulse,"highest":highest,"nearest":near,"position":[s.cargo_position().x,s.cargo_position().y],"failure":s.telemetry.delivery_failure}
 print("HEAVY ",JSON.stringify(result));return result
var failures:int=0
var checks:int=0
func check(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize()->void:
 var r:Dictionary=Chapter.fresh_route(2)
 check(r.destination_y==-72.0 and r.hazards.size()==1,"fixed authored heavy destination and obstacle")
 check(r.min_delivery_integrity==.75 and r.max_delivery_speed==10.0,"existing heavy receipt constraints retained")
 var bare:Dictionary=run("default-bare")
 var vertical:Dictionary=run("default-vertical")
 var powered:Dictionary=run("powered")
 var ballistic:Dictionary=run("ballistic")
 check(bare.status!="success" and bare.highest>-40.0,"default pad bare heavy cannot attain required altitude")
 check(vertical.status!="success" and vertical.highest>-40.0,"even full vertical default launch cannot reach 72m; no hidden steering requirement")
 check(bare.launch_energy==240.0 and bare.mass==12.0,"default paid impulse and real cargo mass")
 check(powered.status=="success" and powered.integrity>.99 and powered.contact==0,"stock powered heavy ship climbs and clears physical rock")
 check(ballistic.status=="success" and ballistic.integrity>=.75 and ballistic.contact==0,"supported spring pad unpowered cargo reaches real receiver")
 check(ballistic.launch_energy==720.0 and ballistic.energy==720.0,"ballistic route uses exactly paid launch work, no active propulsion")
 check(powered.energy>ballistic.energy and powered.mass>ballistic.mass,"ship propulsion versus pad investment remains a measurable tradeoff")
 print("HEAVY_CHOICES_CHECKS ",checks," passed=",checks-failures," failed=",failures)
 quit(1 if failures else 0)
