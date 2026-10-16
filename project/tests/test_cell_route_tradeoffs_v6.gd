extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Econ=preload("res://scripts/economy.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func craft(kind:String)->Array:
 if kind=="recoil":return [part(1,"cargo",0,0,100),part(2,"accelerator",-1,0,12,{"rot":2,"target":6,"input_a":-2}),part(3,"battery",1,0,300),part(4,"thruster",1,-1,28),part(5,"thruster",1,1,28),part(6,"beam",-2,0,32),part(7,"beam",-3,0,32)]
 return [part(1,"cargo",0,0,100),part(3,"battery",-1,0,300),part(6,"battery",1,0,300),part(4,"thruster",0,-1,28),part(5,"thruster",0,1,28),part(7,"armor",1,-1,150)]
func fly(kind:String)->Dictionary:
 var ship:Array=craft(kind);var pad:Array=Profile.starter_launcher();var route:Dictionary=Chapter.fresh_route(1)
 var econ=Econ.new();econ.enable_delivery_mode();econ.starter_stock(Profile.starter_design(),pad)
 check(econ.close_day().ok,"normal shop closing opens component supplier")
 var bought:float=0.0
 for key in econ.missing_parts(ship,pad):
  var count:int=econ.missing_parts(ship,pad)[key]
  for i in range(count):
   var result:Dictionary=econ.buy_part(key,Parts.catalog()[key]);check(result.ok,"normal purchase funds missing "+key);bought+=float(Parts.catalog()[key].price)
 check(econ.missing_parts(ship,pad).is_empty(),"actual newshop inventory supports "+kind)
 check(econ.next_day().ok,"normal nextday retains unlocked first level")
 route=econ.contract_by_id("D2-A").duplicate(true)
 var cost:float=0
 for p in ship+pad:
  if p.type!="cargo":cost+=float(Parts.catalog()[p.type].price)
 var s=Sim.new();s.configure(ship,pad,route,42);s.release_launcher(15,1)
 var waypoints:Array=[Vector2(34,-15),Vector2(80,-8)];var index:int=0;var fired:bool=false
 for tick in range(60*60):
  if s.status!="running":break
  var at:Vector2=s.cargo_position();var b:Dictionary=s.body_for_part(1)
  if at.distance_to(waypoints[index])<4.0 and index<waypoints.size()-1:index+=1
  var delta:Vector2=waypoints[index]-at
  var speed:float=minf(9.0,sqrt(2*3.5*maxf(0.0,delta.length()-1)))
  var desired:Vector2=(delta.normalized()*speed-b.velocity).limit_length(3.5)
  var output:float=0
  for p in b.parts:
   if p.type=="thruster" and p.alive:output+=float(p.param)*float(p.output_factor)*float(route.free_drive_throttle)
  var input:Vector2=desired*float(b.mass)/maxf(0.01,output)
  var active:bool=kind=="recoil" and tick==1
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,active,2 if kind=="recoil" else -1,false);s.step(1.0/60.0)
  if kind=="recoil":fired=fired or bool(s.parts[2].spent)
 s.finalize_settlement()
 var sample:Dictionary={"kind":kind,"status":s.status,"level":route.chapter_level,"original_destination":[route.distance,route.destination_y],"time":s.elapsed,"integrity":s.ship_integrity(),"energy_j":s.telemetry.energy_used,"remaining_j":s.telemetry.energy_remaining,"hardware_and_pad":cost,"newshop_purchase":bought,"ammo_cost":s.telemetry.ammo_cost,"lost_cost":s.telemetry.lost_cost,"repair_cost":s.telemetry.repair_cost,"fired":fired,"failure":s.telemetry.delivery_failure}
 print("CELL_ROUTE_SAMPLE ",JSON.stringify(sample))
 return sample
func _initialize()->void:
 var a:Dictionary=fly("recoil");var b:Dictionary=fly("durable")
 check(a.status=="success" and a.fired and a.integrity>=0.7,"normal unchanged80m order completes actual grouped recoil strategy")
 check(b.status=="success" and b.integrity>=0.7,"same unchanged order completes durable two-cell structure")
 check(a.hardware_and_pad<=405 and b.hardware_and_pad<=405,"both structures fit common405hardware budget")
 check(a.ammo_cost==20 and a.lost_cost==0 and b.ammo_cost==0,"recoil consumables and all recovery costs remain explicit")
 print("CELL_ROUTE_TRADEOFFS_V6 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
