extends SceneTree
const Legacy=preload("res://scripts/pilot_delivery_ascent_simulation_v8.gd")
const Profile=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var Proto
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func near(a:float,b:float,epsilon:float=.0001)->bool:return absf(a-b)<=epsilon
func part(id:int,kind:String,x:int,y:int,param:float=0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func craft(kind:String)->Array:
 if kind=="prototype":return [part(1,"cargo",-1,0,100),part(2,"battery",0,0,300),part(3,"thruster",-2,0,28),part(4,"thruster",-1,-1,28),part(5,"thruster",1,0,28),part(6,"splitter",0,1,0,{"input_a":-2,"target":2})]
 if kind=="coupler":return [part(1,"cargo",-1,0,100),part(2,"battery",-2,0,300),part(3,"thruster",-1,-1,28),part(4,"thruster",-1,1,28),part(5,"thruster",2,0,28),part(6,"coupler",0,0,0,{"input_a":-2,"target":7}),part(7,"battery",1,0,300)]
 return [part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"battery",1,0,300),part(4,"thruster",0,-1,28),part(5,"thruster",0,1,28)]
func make(design:Array):
 var s=Proto.new();s.configure(design,[],Profile.route(),42);s.release_launcher(0,0);return s
func local_tests()->void:
 var s=make(craft("prototype"));var b:Dictionary=s.body_for_part(1);b.position=Vector2(7,-40);b.angle=.7;b.velocity=Vector2(3,-5);b.angular_velocity=.8
 var old_ids:Array=s.parts.keys();var before:Dictionary=s.prototype_totals();var cargo_velocity:Vector2=s._part_velocity(s.parts[1]);var cargo_position:Vector2=s._part_position(s.parts[1]);var links_before:Array=s.links.duplicate(true)
 s._split_module(s.parts[6],s.parts[2],b,1.0/120.0)
 var event:Dictionary=s.prototype_last_split;var after:Dictionary=s.prototype_totals()
 check(event.get("success",false) and event.reason=="separated" and s.bodies.size()==2,"axis cut actually creates two connected subassemblies")
 if not event.get("success",false):return
 var clone:int=event.clone
 check(s._same_circuit(s.parts[1],s.parts[2]) and s._same_circuit(s.parts[5],s.parts[clone]) and not s._same_circuit(s.parts[1],s.parts[clone]),"each side retains a real half battery; circuits are independent")
 check(near(s.parts[2].energy,2995) and near(s.parts[clone].energy,2995),"actual10J cut is paid before conserved two2995J stores")
 for key in ["mass","hp","output","capacity"]:check(near(before[key],after[key]),"conserves total "+key)
 check(near(before.energy-after.energy,10),"energy decreases by exactly paid10J")
 check(Vector2(before.com).distance_to(Vector2(after.com))<.00001,"symmetric fragments preserve whole-system center of mass")
 check(Vector2(before.linear).distance_to(Vector2(after.linear))<.0001,"cut creates no net linear impulse")
 check(near(before.angular,after.angular,.001),"parallel-axis correction conserves angular momentum about fixed origin")
 check(near(before.kinetic,after.kinetic,.001),"cut does not create or delete kinetic energy")
 check(s._part_position(s.parts[1]).distance_to(cargo_position)<.00001 and s._part_velocity(s.parts[1]).distance_to(cargo_velocity)<.00001,"cargo is neither repositioned nor kicked")
 check(s._part_position(s.parts[2]).distance_to(s._part_position(s.parts[clone]))>=.43*(s.parts[2].scale+s.parts[clone].scale),"half proxies do not overlap across the split")
 print("AXIS_LOCAL ",JSON.stringify(event))
 var bypass_design:Array=craft("prototype");bypass_design.append(part(8,"beam",-1,1,32))
 var bypass=make(bypass_design);bypass._split_module(bypass.parts[6],bypass.parts[2],bypass.body_for_part(6),1.0/120.0)
 check(bypass.prototype_last_split.get("success",false) and bypass.prototype_last_split.reason=="bypass_still_connected" and bypass.bodies.size()==1,"alternate structural path truthfully keeps both halves in one body")
 var dry=make(craft("prototype"));dry.parts[2].energy=9
 var dry_before:PackedByteArray=var_to_bytes([dry.parts,dry.links,dry.telemetry.energy_used]);dry._split_module(dry.parts[6],dry.parts[2],dry.body_for_part(6),1.0/120.0)
 check(dry.prototype_last_split.reason=="no_energy" and dry_before==var_to_bytes([dry.parts,dry.links,dry.telemetry.energy_used]),"insufficient cut power leaves material links and energy unchanged")
 var blocked=make(craft("prototype"));var target_at:Vector2=blocked._part_position(blocked.parts[2]);blocked.obstacles.append({"health":100.0,"type":"rock","position":target_at+Vector2(.7,0),"radius":.1})
 var blocked_before:PackedByteArray=var_to_bytes([blocked.parts,blocked.links,blocked.telemetry.energy_used]);blocked._split_module(blocked.parts[6],blocked.parts[2],blocked.body_for_part(6),1.0/120.0)
 check(blocked.prototype_last_split.reason=="obstacle_overlap" and blocked_before==var_to_bytes([blocked.parts,blocked.links,blocked.telemetry.energy_used]),"new fragment obstacle overlap rejects without paying or changing topology")
func hardware(design:Array,pad:Array)->float:
 var result:float=0.0
 for p in design+pad:
  if p.type!="cargo":result+=float(Parts.catalog()[p.type].price)
 return result
func state(s)->Dictionary:
 var groups:Array=[]
 for b in s.bodies:
  var ids:Array=[]
  for p in b.parts:ids.append(int(p.id))
  ids.sort();groups.append({"ids":ids,"mass":b.mass,"inertia":b.inertia,"energy":s._available_energy(b),"velocity":b.velocity})
 return {"elapsed":s.elapsed,"position":s.cargo_position(),"cargo_ids":s._component(1),"groups":groups}
func fly(kind:String)->void:
 var s=Proto.new() if kind=="prototype" else Legacy.new();var design:Array=craft(kind);var pad:Array=Profile.starter_launcher();s.configure(design,pad,Profile.route(),42);s.release_launcher(90,1)
 var points:Array=[Vector2(22,-80),Vector2(22,-195),Vector2(-12,-315),Vector2(14,-460),Vector2(40,-560)];var index:int=0;var triggered:bool=false;var pending:bool=false;var before:Dictionary={};var after:Dictionary={};var start:Dictionary=state(s)
 for tick in range(60*180):
  if s.status!="running":break
  var at:Vector2=s.cargo_position();var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  if pending:after=state(s);pending=false
  var field:Dictionary=s.environment_at(b.position)
  if at.distance_to(points[index])<7.0 and index<points.size()-1:index+=1
  var delta:Vector2=points[index]-at;var speed:float=minf(8.0,sqrt(2.0*2.8*maxf(0.0,delta.length()-1.0)))
  var requested:Vector2=(delta.normalized()*speed-b.velocity).limit_length(3.0)-Vector2(0,float(field.gravity))-Vector2(field.wind)
  var output:float=0.0
  for p in b.parts:
   if p.type=="thruster" and p.alive:output+=float(p.param)*float(p.output_factor)*.72
  var input:Vector2=requested*float(b.mass)/maxf(.01,output);var active:bool=false
  if kind in ["prototype","coupler"] and not triggered and -at.y>=100:
   active=true;triggered=true;pending=true;before=state(s)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,active,6 if active else -1,false);s.step(1.0/60.0)
 var result:Dictionary={"variant":kind,"hardware":hardware(design,pad),"budget_limit":440,"status":s.status,"time":s.elapsed,"integrity":s.ship_integrity(),"energy_used":s.telemetry.energy_used,"energy_remaining":s.telemetry.energy_remaining,"lost":s.telemetry.lost_cost,"ammo":s.telemetry.ammo_cost,"repair":s.telemetry.repair_cost,"failure":s.telemetry.delivery_failure,"contact_impulse":s.telemetry.cargo_contact_impulse,"start":start,"before_stage":before,"after_stage":after,"incidents":s.incidents,"events_tail":s.events.slice(-12)}
 if kind=="prototype":result.axis_event=s.prototype_last_split
 print("AXIS_FLIGHT ",JSON.stringify(result))
func _initialize()->void:
 Proto=load(get_script().resource_path.get_base_dir().path_join("prototype_ascent.gd"))
 if Proto==null or not Proto.can_instantiate():push_error("prototype failed to compile");quit(1);return
 local_tests();print("AXIS_LOCAL_RESULT passed=%d failed=%d"%[passed,failed])
 if failed>0:quit(1);return
 if "--local-only" not in OS.get_cmdline_user_args():
  for kind in ["prototype","coupler","compact"]:fly(kind)
 quit()
