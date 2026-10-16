extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var folder:String
var frozen:Dictionary
func save(name:String,value:Variant)->void:
 var f=FileAccess.open(folder.path_join(name),FileAccess.WRITE)
 f.store_string(JSON.stringify(value,"  ")+"\n")
func snap(s)->Dictionary:
 var b:Dictionary=s.body_for_part(1)
 var ps:Array=[]
 for p in s.parts.values():ps.append({"id":p.id,"type":p.type,"alive":p.alive,"energy":p.energy,"body":p.body_id})
 return {"elapsed":s.elapsed,"position":[s.cargo_position().x,s.cargo_position().y],"velocity":b.get("velocity",Vector2.ZERO),"cargo_mass":b.get("mass",0),"cargo_body":b.get("id",-1),"parts":ps,"integrity":s.ship_integrity(),"energy_used":s.telemetry.get("energy_used",0)}
func run_case(sample:Dictionary,r:Dictionary)->Dictionary:
 var s=Sim.new();s.configure(sample.ship.duplicate(true),frozen.launcher.duplicate(true),r.duplicate(true),int(frozen.seed))
 if s.status!="running" or not s.free_route_error.is_empty():return {"error":"configure","events":s.events}
 var launch:Dictionary=s.release_launcher(float(frozen.launch.angle),float(frozen.launch.power))
 var points:Array=[]
 for p in sample.waypoints:points.append(Vector2(p[0],p[1]))
 var c:Dictionary=frozen.controller;var index:int=0;var release_tick:int=-1;var trigger_tick:int=-1;var trace:Array=[];var cuts:Array=[];var inputs:Array=[];var previous:Array=[]
 for tick in int(c.max_ticks):
  if s.status!="running":break
  var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  var at:Vector2=s.cargo_position()
  if index<points.size()-1 and at.distance_to(points[index])<float(c.arrival_radius):index+=1
  var delta:Vector2=points[index]-at
  var speed:float=minf(float(c.cruise),sqrt(maxf(0.0,2.0*float(c.acceleration)*delta.length())))
  var desired:Vector2=delta.normalized()*speed
  var request:Vector2=((desired-Vector2(b.velocity))/float(c.response)).limit_length(float(c.acceleration))
  var output:float=0.0
  for p in b.parts:
   if p.type=="thruster" and p.alive:output+=p.param*p.output_factor*float(r.free_drive_throttle)
  var axis:Vector2=request*float(b.mass)/maxf(.01,output)
  var brake:bool=false;var active:bool=false
  if bool(sample.release) and release_tick<0 and at.x>=float(c.release_x):release_tick=tick
  if release_tick>=0 and trigger_tick<0:
   if float(tick-release_tick)*float(c.dt)<float(c.brake_seconds):brake=true
   else:active=true;trigger_tick=tick;cuts.append({"before":snap(s)})
  var command:Array=[clampi(roundi(axis.x*1000),-1000,1000),clampi(roundi(axis.y*1000),-1000,1000),false,active,5,brake]
  if command!=previous:inputs.append({"tick":tick,"command":command});previous=command
  s.set_free_flight_input(command[0],command[1],false,active,5,brake);s.step(float(c.dt))
  if tick==trigger_tick:cuts[-1].after=snap(s)
  if tick%120==0 or tick==trigger_tick or s.status!="running":trace.append(snap(s))
 var quote:Dictionary=Chapter.quote(r,s.telemetry,s.status=="success") if s.status!="running" else {}
 var out:Dictionary={"sample":sample.id,"outcome":s.status,"elapsed":s.elapsed,"integrity":s.ship_integrity()*100,"energy_j":s.telemetry.get("energy_used",0),"hardware_ship":sample.ship_hardware_cost,"hardware_pad":sample.pad_cost,"trigger_tick":trigger_tick,"cuts":cuts,"launch":launch,"quote_not_formal":quote,"telemetry":s.telemetry,"events":s.events,"incidents":s.incidents,"final":snap(s)}
 save(sample.id+".json",out);save(sample.id+"-trace.json",trace);save(sample.id+"-inputs.json",inputs)
 print("SAMPLE ",sample.id," ",s.status," ",s.elapsed," integrity ",out.integrity," energy ",out.energy_j," cost ",quote.get("actual_costs",-1));return out
func _initialize()->void:
 folder=get_script().resource_path.get_base_dir();frozen=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("DESIGN-FROZEN.json")))
 var r:Dictionary=Chapter.fresh_route(3,false,false)
 if not Chapter.route_error(r).is_empty():print("route error");quit(2);return
 save("ACTUAL-ROUTE.json",r)
 var out:Array=[]
 for sample in frozen.samples:
  var result:Dictionary=run_case(sample,r);out.append(result)
  if result.has("error"):save("RESULTS.json",out);quit(2);return
 save("RESULTS.json",out);quit()
