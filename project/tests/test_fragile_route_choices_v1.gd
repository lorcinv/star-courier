extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
func part(id:int,kind:String,x:int,y:int,param:float=0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func ship(kind:String)->Array:
 if kind=="compact":return [part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"thruster",-1,1,28),part(4,"thruster",0,1,28)]
 return [part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"thruster",0,-1,28),part(4,"thruster",0,1,28),part(5,"damper",1,0,0 if kind=="tall_unbuffered" else 8,{"target":1})]
func run(kind:String,detour:bool)->Dictionary:
 var r:Dictionary=Chapter.fresh_route(3)

 var s=Sim.new();s.configure(ship(kind),Profile.starter_launcher(),r,42);s.release_launcher(15.0,.12)
 var points:Array=[Vector2(28,-10),Vector2(66,-10),Vector2(95,-10)]
 if detour:points=[Vector2(28,-30),Vector2(68,-30),Vector2(95,-10)]
 var index:int=0
 for tick in range(60*90):
  if s.status!="running":break
  var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  var at:Vector2=s.cargo_position()
  if at.distance_to(points[index])<2.0 and index<points.size()-1:index+=1
  var delta:Vector2=points[index]-at
  var speed:float=minf(5.0,sqrt(2*2.0*maxf(0,delta.length()-.2)))
  var request:Vector2=(delta.normalized()*speed-b.velocity).limit_length(2.0)
  var output:float=0
  for q in b.parts:
   if q.type=="thruster" and q.alive:output+=float(q.param)*float(q.output_factor)*float(r.free_drive_throttle)
  var input:Vector2=request*float(b.mass)/maxf(.01,output)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false);s.step(1.0/60.0)
 var result:Dictionary={"kind":kind,"detour":detour,"status":s.status,"elapsed":s.elapsed,"integrity":s.ship_integrity(),"energy":s.telemetry.energy_used,"contact":s.telemetry.cargo_contact_impulse,"position":[s.cargo_position().x,s.cargo_position().y],"failure":s.telemetry.delivery_failure}
 print("GEOMETRY ",JSON.stringify(result));return result
var failures:int=0
var checks:int=0
func check(ok:bool,description:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(description)
func _initialize()->void:
 var r:Dictionary=Chapter.fresh_route(3)
 check(r.hazards.size()==2,"two authored visible obstacles")
 check(is_equal_approx(absf(float(r.hazards[0].y)-float(r.hazards[1].y))-float(r.hazards[0].radius)-float(r.hazards[1].radius),2.4),"authored actual gap is 2.4m")
 var compact:Dictionary=run("compact",false)
 var buffered:Dictionary=run("tall",false)
 var wide:Dictionary=run("tall",true)
 var failed:Dictionary=run("tall_unbuffered",false)
 var retry:Dictionary=run("tall_unbuffered",true)
 check(compact.status=="success" and compact.integrity>.99 and compact.contact==0,"compact short route viable intact")
 check(wide.status=="success" and wide.integrity>.99 and wide.contact==0,"tall wide route viable intact")
 check(buffered.status=="success" and buffered.integrity>=.90 and buffered.integrity<.98 and buffered.contact>0,"buffered forced crossing remains legitimate damage tradeoff")
 check(failed.status=="failed" and failed.failure=="integrity_below_requirement" and failed.integrity<.90,"unbuffered squeeze fails declared integrity requirement")
 check(retry.status=="success" and retry.integrity>.99 and retry.contact==0,"same unbuffered equipment succeeds by changing route only")
 check(compact.elapsed<wide.elapsed,"compact short route saves time")
 check(wide.energy<buffered.energy and wide.integrity>buffered.integrity,"wide route saves contact losses and energy against forcing same tall craft")
 print("FRAGILE_GEOMETRY_CHECKS ",checks," passed=",checks-failures," failed=",failures)
 quit(1 if failures else 0)
