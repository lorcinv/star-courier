extends SceneTree
## Three actual formal flights on each of two owned builds. Tests the physics to
## receipt boundary and normal model progression; it is not a human playtest.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v3.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func play_chapter(teleport:bool)->Array:
 var e=Econ.new();e.enable_delivery_mode();e.starter_stock(Profile.starter_design(),Profile.starter_launcher());e.enable_story_mode()
 var reports:Array=[]
 var ship:Array=Profile.starter_design()
 var pad:Array=Profile.starter_launcher()
 if teleport:
  ship=[part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"battery",-1,1,300),part(9,"teleporter",0,1,16,{"input_a":-2})];pad=[]
 for level in range(1,4):
  var id:String="D%d-A"%level
  check(e.contract_by_id(id).chapter_level==level,"normal authoring reaches real-flight level %d"%level)
  check(e.accept_contract(id).ok,"real-flight order accepts")
  if teleport and level==1:check(e.buy_part("teleporter",Parts.catalog().teleporter).ok,"teleport strategy buys its extra part at real full price")
  check(e.missing_parts(ship,pad).is_empty(),"actual build and launcher use only owned inventory")
  e.mark_cargo_loaded(id)
  var launch:Dictionary={"angle_degrees":0.0 if teleport else 15.0,"power_fraction":0.0 if teleport else (0.2 if level==3 else 1.0)}
  check(e.begin_dispatch(ship,pad,launch).ok,"formal flight freezes real launch settings")
  var s=Sim.new();s.configure(ship,pad,e.in_flight.route,int(e.in_flight.seed))
  s.release_launcher(launch.angle_degrees,launch.power_fraction)
  e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
  var timeline=Timeline.new();var completed:int=0
  var waypoints:Array=[]
  if level==1:waypoints=[Vector2(34,-15),Vector2(80,-8)]
  elif level==2:waypoints=[Vector2(40,-10),Vector2(74,-12),Vector2(110,-18)]
  else:waypoints=[Vector2(35,-7),Vector2(64,-10),Vector2(95,-10)]
  var index:int=0
  for tick in range(60*90):
   if s.status!="running":break
   var input:Vector2
   if teleport:input=(Vector2(float(s.route.distance),float(s.route.destination_y))-s.cargo_position()).normalized()
   else:
    var at:Vector2=s.cargo_position()
    if at.distance_to(waypoints[index])<4.0 and index<waypoints.size()-1:index+=1
    var delta:Vector2=waypoints[index]-at
    var max_acceleration:float=2.8 if level==3 else 3.5
    var cruise:float=7.0 if level==3 else 9.0
    var desired_speed:float=minf(cruise,sqrt(2.0*max_acceleration*maxf(0.0,delta.length()-1.0)))
    var body:Dictionary=s.body_for_part(1)
    if body.is_empty():break
    var desired:Vector2=(delta.normalized()*desired_speed-body.velocity).limit_length(max_acceleration)
    var thrust:float=0.0
    for p in body.parts:
     if p.type=="thruster" and p.alive:thrust+=float(p.param)*float(p.output_factor)*float(s.route.free_drive_throttle)
    input=desired*float(body.mass)/maxf(0.01,thrust)
   var x:int=clampi(roundi(input.x*1000),-1000,1000);var y:int=clampi(roundi(input.y*1000),-1000,1000)
   var active:bool=teleport and tick%2==0;var device:int=9 if teleport else -1
   timeline.record(tick,{"axis_x_q":x,"axis_q":y,"boost":false,"active":active,"device_id":device,"brake":false})
   s.set_free_flight_input(x,y,false,active,device,false);s.step(1.0/60.0);completed+=1
  e.in_flight.ticks=completed;e.in_flight.input_commands=timeline.snapshot();e.in_flight.elapsed=s.elapsed
  check(s.status=="success" and s.telemetry.delivery_qualified,"actual physics qualifies this route")
  check(Econ.replay_protocol_error(e.in_flight).is_empty(),"recorded real flight has a valid exact v3 replay")
  var before:int=e.credits
  var result:Dictionary=e.settle_contract_and_save(id,s.telemetry,s.elapsed,s.status=="success",ship,pad,{})
  check(result.ok,"real simulation result commits as formal versioned receipt")
  if not result.ok:printerr(result);return reports
  check(e.credits==before+int(e.last_settlement.profit) and e.last_settlement.charged_costs==e.last_settlement.actual_costs,"real settlement applies exact uncapped costs")
  check(e.last_settlement.energy==ceili(float(s.telemetry.energy_used)*float(s.route.pilot_energy_tariff)),"paid launch and flight energy are rounded/billed once")
  reports.append(e.last_settlement.duplicate(true))
  print("CHAPTER_FORMAL_SAMPLE ",JSON.stringify({"strategy":"two_cell_teleport" if teleport else "starter_steering","level":level,"elapsed":s.elapsed,"energy_j":s.telemetry.energy_used,"costs":e.last_settlement.actual_costs,"profit":e.last_settlement.profit,"credits":e.credits,"integrity":e.last_settlement.delivery_integrity}))
  var restored=Econ.new();restored.load_state();restored.enable_story_mode()
  check(not restored.review_load_blocked and restored.credits==e.credits and restored.delivery_chapter_state.unlocked_level==level+1,"formal result resumes with exact money and chapter progress")
  e=restored
  if level<3:check(e.close_day().ok and e.next_day_and_save(ship,pad,{}).ok,"normal next day authors next real-flight level")
 check(e.delivery_chapter_status().first_chapter_complete,"actual three-day deliveries complete first chapter")
 return reports
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Use isolated XDG_DATA_HOME.");quit(2);return
 var standard:Array=play_chapter(false)
 # Each scenario starts with its own new-shop model and the same 260 credits;
 # disk is only the isolated test's durable resume slot, never a player save.
 var transit:Array=play_chapter(true)
 check(standard.size()==3 and transit.size()==3,"both owned strategies complete all three actual chapters")
 if standard.size()==3 and transit.size()==3:
  for i in range(3):
   check(transit[i].energy>standard[i].energy*2,"teleport costs materially more real credits on level %d"%(i+1))
   check(transit[i].profit<standard[i].profit,"teleport speed advantage has lower net income on level %d"%(i+1))
   check(transit[i].elapsed<standard[i].elapsed,"comparison preserves teleport's real speed advantage")
 print("DELIVERY_CHAPTER_ECONOMY_MECHANICS_V3 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
