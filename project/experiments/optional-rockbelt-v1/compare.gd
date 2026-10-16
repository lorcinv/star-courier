extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var folder:String
var frozen:Dictionary

func save_json(name:String,data:Variant)->void:
 var f=FileAccess.open(folder.path_join(name),FileAccess.WRITE)
 f.store_string(JSON.stringify(data,"  ")+"\n")
 f.close()

func v2(v:Vector2)->Array:return [v.x,v.y]

func same_data(a:Variant,b:Variant)->bool:
 if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same_data(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not same_data(a[i],b[i]):return false
  return true
 return a==b

func obstacle(s,id:String)->Dictionary:
 for h in s.obstacles:
  if str(h.get("id",""))==id:return h
 return {}

func obstacles_state(s)->Array:
 var result:Array=[]
 for h in s.obstacles:
  result.append({"id":h.get("id",""),"health":h.health,"radius":h.radius,"position":v2(h.position),"velocity":v2(h.velocity)})
 return result

func parts_state(s)->Array:
 var result:Array=[]
 for p in s.parts.values():
  result.append({"id":p.id,"type":p.type,"alive":p.alive,"delivered":p.delivered,"recovered":p.recovered,"hp":p.hp,"max_hp":p.max_hp,"energy":p.energy,"body_id":p.body_id,"replacement_kind":p.replacement_kind})
 return result

func state(s,tick:int,index:int)->Dictionary:
 var b:Dictionary=s.body_for_part(1)
 return {"external_tick":tick,"elapsed":s.elapsed,"status":s.status,"position":v2(s.cargo_position()),"velocity":v2(b.get("velocity",Vector2.ZERO)),"angle":b.get("angle",0.0),"waypoint_index":index,"integrity":s.ship_integrity(),"energy_used":s.telemetry.get("energy_used",0.0),"energy_remaining":s.telemetry.get("energy_remaining",0.0),"drill_damage":s.telemetry.get("drill_damage",0.0),"drill_energy_used":s.telemetry.get("drill_energy_used",0.0),"cargo_contact_impulse":s.telemetry.get("cargo_contact_impulse",0.0),"obstacles":obstacles_state(s),"parts":parts_state(s)}

func run_sample(sample:Dictionary,r:Dictionary)->Dictionary:
 var c:Dictionary=frozen.controller
 var s=Sim.new()
 var ship:Array=frozen.ship.duplicate(true)
 if bool(sample.get("omit_drill",false)):ship=ship.filter(func(part):return int(part.id)!=7)
 s.configure(ship,frozen.launcher.duplicate(true),r.duplicate(true),int(frozen.seed))
 if s.status!="running" or not s.free_route_error.is_empty():
  var error:Dictionary={"sample":sample.id,"harness_error":"configure_failed","status":s.status,"events":s.events,"telemetry":s.telemetry}
  save_json(str(sample.id)+".json",error);return error
 var before:Dictionary=state(s,0,0)
 var preview:Dictionary=s.preview_launcher(float(frozen.launch.angle_degrees),float(frozen.launch.power_fraction))
 var shield:Dictionary=s.shield_coverage_snapshot(6)
 var release:Dictionary=s.release_launcher(float(frozen.launch.angle_degrees),float(frozen.launch.power_fraction))
 var points:Array=[]
 for p in sample.waypoints:points.append(Vector2(float(p[0]),float(p[1])))
 var index:int=0
 var trace:Array=[state(s,0,0)]
 var commands:Array=[]
 var previous_command:Array=[]
 var prior_damage:float=0.0
 var prior_contact:float=0.0
 var enabled_ticks:int=0
 var steps:int=0
 var stop:String="horizon"
 var first_drill_damage:Variant=null
 var destroyed_rock_time:Variant=null
 for tick in range(int(c.max_external_ticks)):
  if s.status!="running":stop="terminal";break
  var b:Dictionary=s.body_for_part(1)
  if b.is_empty():stop="missing_cargo_body";break
  var at:Vector2=s.cargo_position()
  if at.distance_to(points[index])<float(c.waypoint_radius_m) and index<points.size()-1:index+=1
  var delta:Vector2=points[index]-at
  var upper:Dictionary=obstacle(s,str(c.target_obstacle_id))
  var rock_alive:bool=not upper.is_empty() and float(upper.health)>0.0
  var speed_cap:float=float(c.max_speed_mps)
  if rock_alive and at.distance_to(upper.position)<=float(c.approach_cargo_distance_m) and absf(at.y-float(upper.position.y))<=float(c.approach_cargo_vertical_offset_max_m):speed_cap=float(c.approach_speed_cap_mps)
  var speed:float=minf(speed_cap,sqrt(2.0*float(c.acceleration_limit_mps2)*maxf(0.0,delta.length()-float(c.stopping_margin_m))))
  var request:Vector2=(delta.normalized()*speed-b.velocity).limit_length(float(c.acceleration_limit_mps2))
  var output:float=0.0
  for q in b.parts:
   if q.type=="thruster" and q.alive:output+=float(q.param)*float(q.output_factor)*float(r.free_drive_throttle)
  var input:Vector2=request*float(b.mass)/maxf(0.01,output)
  var active:bool=false
  var drill:Dictionary=s.parts.get(7,{})
  if bool(sample.drill_allowed) and rock_alive and not drill.is_empty() and drill.alive and not drill.delivered:
   var drill_body:Dictionary=s.body_for_part(7)
   if not drill_body.is_empty():
    var tip:Vector2=s._part_position(drill)+Vector2.RIGHT.rotated(float(drill_body.angle)+float(drill.local_angle))*float(c.drill_tip_offset_m)*float(drill.scale)
    active=tip.distance_to(upper.position)<=float(upper.radius)+float(c.drill_trigger_tip_distance_leq_radius_plus_m)
  var x:int=clampi(roundi(input.x*float(c.input_quantization)),-1000,1000)
  var y:int=clampi(roundi(input.y*float(c.input_quantization)),-1000,1000)
  var command:Array=[x,y,false,active,int(c.drill_device_id),false]
  if command!=previous_command:
   commands.append({"tick":tick,"axis_x_q":x,"axis_q":y,"boost":false,"active":active,"device_id":int(c.drill_device_id),"brake":false})
   previous_command=command
  if active:enabled_ticks+=1
  s.set_free_flight_input(x,y,false,active,int(c.drill_device_id),false)
  s.step(float(c.external_dt_seconds));steps=tick+1
  var damage:float=float(s.telemetry.get("drill_damage",0.0))
  var contact:float=float(s.telemetry.get("cargo_contact_impulse",0.0))
  if damage>0.0 and first_drill_damage==null:first_drill_damage=s.elapsed
  var after_upper:Dictionary=obstacle(s,str(c.target_obstacle_id))
  if (after_upper.is_empty() or float(after_upper.health)<=0.0) and destroyed_rock_time==null:destroyed_rock_time=s.elapsed
  if tick%60==0 or damage!=prior_damage or contact!=prior_contact or s.status!="running":trace.append(state(s,tick+1,index))
  prior_damage=damage;prior_contact=contact
 if s.status!="running":stop="terminal"
 var dead:Array=[]
 var unrecovered:Array=[]
 var detached:Array=[]
 var cargo_body:Dictionary=s.body_for_part(1)
 for p in s.parts.values():
  if p.type=="cargo":continue
  if not p.alive:dead.append(int(p.id))
  if p.alive and not p.recovered and not p.delivered:unrecovered.append(int(p.id))
  if s.status=="running" and p.alive and int(p.body_id)!=int(cargo_body.get("id",-999)):detached.append(int(p.id))
 var quote:Dictionary=Chapter.quote(r,s.telemetry,s.status=="success") if s.status!="running" else {}
 var result:Dictionary={"sample":sample.id,"outcome":s.status,"stop_reason":stop,"horizon_reached_still_running":stop=="horizon" and s.status=="running","elapsed_seconds":s.elapsed,"external_steps":steps,"integrity_fraction":s.ship_integrity(),"integrity_percent":s.ship_integrity()*100.0,"position":v2(s.cargo_position()),"energy_used_j":s.telemetry.get("energy_used",0.0),"energy_remaining_ship_j":s.telemetry.get("energy_remaining",0.0),"drill_damage_hp":s.telemetry.get("drill_damage",0.0),"drill_energy_used_j":s.telemetry.get("drill_energy_used",0.0),"drill_contacts":s.telemetry.get("drill_contacts",0),"drill_held_input_seconds":float(enabled_ticks)*float(c.external_dt_seconds),"first_drill_damage_seconds":first_drill_damage,"upper_rock_destroyed_seconds":destroyed_rock_time,"cargo_contact_impulse_ns":s.telemetry.get("cargo_contact_impulse",0.0),"impact_absorbed_hp":s.telemetry.get("impact_absorbed",0.0),"impact_shield_energy_j":s.telemetry.get("impact_shield_energy",0.0),"destroyed_part_ids":dead,"currently_unrecovered_part_ids":unrecovered,"detached_surviving_part_ids_at_horizon":detached,"obstacles":obstacles_state(s),"parts":parts_state(s),"capital":frozen.capital,"drill_omitted":bool(sample.get("omit_drill",false)),"initial_state_before_release":before,"launch_preview":preview,"release_result":release,"initial_shield_snapshot":shield,"precomputed_fee_not_formal_settlement":quote,"fee_limit":"Only terminal cases quoted; running horizon is not terminated or settled. No real contract, inventory, money, chapter or save mutated.","telemetry":s.telemetry.duplicate(true),"incidents":s.incidents.duplicate(true),"events":s.events.duplicate(true)}
 save_json(str(sample.id)+".json",result)
 save_json(str(sample.id)+"-trace.json",trace)
 save_json(str(sample.id)+"-inputs.json",commands)
 print("SAMPLE_RESULT ",JSON.stringify({"sample":sample.id,"outcome":result.outcome,"elapsed":result.elapsed_seconds,"integrity":result.integrity_percent,"energy":result.energy_used_j,"drill_damage":result.drill_damage_hp,"contact":result.cargo_contact_impulse_ns,"destroyed":dead,"obstacles":result.obstacles,"precomputed_fee":quote.get("actual_costs",null)}))
 return result

func _initialize()->void:
 folder=get_script().resource_path.get_base_dir()
 frozen=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("DESIGN-FROZEN.json")))
 var r:Dictionary=Chapter.fresh_route(3,false,false)
 r.erase("route_layout")
 r.hazards=frozen.route_identity.hazards.duplicate(true)
 if r.is_empty() or not Chapter.route_error(r).is_empty():print("HARNESS_ERROR route invalid");quit(2);return
 var expected:Dictionary=frozen.route_identity
 for key in expected:
  if not same_data(r.get(key),expected[key]):
   print("HARNESS_ERROR frozen route mismatch ",key," ",JSON.stringify(r.get(key))," != ",JSON.stringify(expected[key]));quit(2);return
 if not same_data(Profile.starter_launcher(),frozen.launcher):print("HARNESS_ERROR launcher mismatch ",JSON.stringify(Profile.starter_launcher())," != ",JSON.stringify(frozen.launcher));quit(2);return
 save_json("PREFLIGHT-LAUNCHER.json",{"actual":Profile.starter_launcher(),"frozen":frozen.launcher,"numeric_structural_equal":true})
 save_json("ACTUAL-ROUTE.json",r)
 var results:Array=[]
 for sample in frozen.samples:
  var result:Dictionary=run_sample(sample,r)
  results.append(result)
  if result.has("harness_error"):save_json("RESULTS.json",results);quit(2);return
 save_json("RESULTS.json",results)
 quit()
