extends SceneTree
# Fixed dev23 flight controller, re-executed on the actual current v8 contract.
# No simulation state, geometry, threat clock, HP or progression injection.
const Profile=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const Sim=preload("res://scripts/pilot_delivery_rift_simulation_v8.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var failures:int=0
var checks:int=0
func check(ok:bool,label:String)->void:
 checks+=1
 if ok:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0.0)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1}
func craft(kind:String)->Array:
 var ship:Array=[part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"thruster",-1,-1,28),part(4,"thruster",-1,1,28)]
 if kind=="warm":ship.append(part(5,"armor",0,-1,0))
 return ship
func fly(kind:String,cruise:float)->Dictionary:
 var route:Dictionary=Chapter.fresh_route(5)
 var frozen:String=JSON.stringify(route)
 var s=Sim.new();s.configure(craft(kind),Profile.starter_launcher(),route,42)
 var launch:Dictionary=s.release_launcher(0,1)
 var points:Array=[Vector2(29,0),Vector2(200,0)] if kind=="fast" else [Vector2(29,0),Vector2(118,16),Vector2(180,16),Vector2(200,0)]
 var index:int=0;var active_field:bool=false;var warnings:bool=false
 var peak_exposure:float=0.0;var cold_seconds:float=0.0;var contact:float=0.0
 var frames:Array=[];var commands:Array=[];var waypoints:Array=[];var last_rays:int=0
 for tick in range(60*90):
  if s.status!="running":break
  var at:Vector2=s.cargo_position();var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  var previous_index:int=index
  if index==0 and s.telemetry.region=="greenhouse":index=1
  elif at.distance_to(points[index])<5.0 and index<points.size()-1:index+=1
  if index!=previous_index:waypoints.append({"time":s.elapsed,"next_index":index,"position":[at.x,at.y],"velocity":[b.velocity.x,b.velocity.y]})
  var delta:Vector2=points[index]-at
  var speed:float=minf(cruise,sqrt(2.0*2.8*maxf(0.0,delta.length()-1.0)))
  var requested:Vector2=(delta.normalized()*speed-b.velocity).limit_length(3.0)
  var output:float=0.0
  for p in b.parts:
   if p.type=="thruster" and p.alive:output+=float(p.param)*float(p.output_factor)*0.72
  var input:Vector2=requested*float(b.mass)/maxf(0.01,output)
  var command:Array=[roundi(input.x*1000),roundi(input.y*1000)]
  commands.append(command);s.set_free_flight_input(command[0],command[1],false,false,-1,false);s.step(1.0/60.0)
  active_field=active_field or s.telemetry.rift_turbulence.active
  warnings=warnings or s.telemetry.rift_pirate.warning
  peak_exposure=maxf(peak_exposure,float(s.telemetry.biological_exposure_seconds))
  if float(s.telemetry.biological_temperature_c)==float(route.rift_biology.cold_temperature_c):cold_seconds+=1.0/60.0
  contact=maxf(contact,float(s.telemetry.cargo_contact_impulse))
  if tick%15==0 or s.status!="running" or s.telemetry.rift_pirate.ray_records.size()!=last_rays:
   b=s.body_for_part(1);at=s.cargo_position()
   frames.append({"frame":tick,"time":s.elapsed,"position":[at.x,at.y],"velocity":[b.velocity.x,b.velocity.y] if not b.is_empty() else [],"integrity":s.ship_integrity(),"cold_exposure":s.telemetry.biological_exposure_seconds,"cold_damage":s.telemetry.biological_damage,"energy_used":s.telemetry.energy_used,"field_active":s.telemetry.rift_turbulence.active,"warning":s.telemetry.rift_pirate.warning,"shots":s.telemetry.rift_pirate.shots_fired})
  last_rays=s.telemetry.rift_pirate.ray_records.size()
 var rays:Array=s.telemetry.rift_pirate.ray_records.duplicate(true)
 var hits:int=0
 for ray in rays:
  if ray.hit_kind!="miss":hits+=1
 var result:Dictionary={"kind":kind,"control_version":s.telemetry.control_version,"status":s.status,"time":s.elapsed,"energy_j":s.telemetry.energy_used,"remaining_j":s.telemetry.energy_remaining,"integrity":s.ship_integrity(),"failure":s.telemetry.delivery_failure,"cold_damage_hp":s.telemetry.biological_damage,"peak_continuous_cold_seconds":peak_exposure,"sampled_total_cold_seconds":cold_seconds,"active_field_encountered":active_field,"warnings":warnings,"shots":s.telemetry.rift_pirate.shots_fired,"actual_ray_hits":hits,"ray_records":rays,"contact_impulse":contact,"crossing_tick":s.telemetry.portal_crossing_tick,"crossings":s.telemetry.portal_crossings,"position":[s.cargo_position().x,s.cargo_position().y],"launch":launch,"waypoints":waypoints,"route_unchanged":frozen==JSON.stringify(s.route)}
 print("RIFT_ROUTE_CHOICE_DEV31 ",JSON.stringify(result))
 var output_dir:String=OS.get_environment("SC_RIFT_CHOICES_OUT")
 if not output_dir.is_empty():
  var file=FileAccess.open(output_dir.path_join(kind+".json"),FileAccess.WRITE)
  file.store_string(JSON.stringify({"sample":result,"route":route,"design":craft(kind),"launcher":Profile.starter_launcher(),"commands":commands,"frames":frames},"  ")+"\n");file.close()
 return result
func _initialize()->void:
 var r:Dictionary=Chapter.fresh_route(5)
 check(r.control_version=="pilot-rift-v8" and Chapter.route_error(r).is_empty(),"actual current chapter-five v8 contract validates")
 check(r.rift_portal.entry==[28.0,0.0] and r.rift_portal.exit==[100.0,0.0],"actual fixed portal geometry")
 check(r.rift_biology.cold_bounds==[130.0,-10.0,40.0,20.0] and r.rift_biology.grace_seconds==2.5 and r.rift_biology.damage_hp_per_second==3.0,"actual cold bounds grace and damage")
 var fast:Dictionary=fly("fast",12.0)
 var warm:Dictionary=fly("warm",9.0)
 for sample in [fast,warm]:
  check(sample.status=="success" and sample.integrity>=.8,"current v8 "+sample.kind+" fixed route succeeds")
  check(sample.crossing_tick>0 and sample.crossings.size()==1 and sample.route_unchanged,"current v8 "+sample.kind+" physically crosses portal exactly once without changing frozen route")
  check(sample.warnings and sample.shots>0,"current v8 "+sample.kind+" encounters live finite pirate threats")
 check(fast.time<warm.time and fast.cold_damage_hp>warm.cold_damage_hp,"fast exposure versus longer warm bypass remains a measured tradeoff")
 print("RIFT_ROUTE_CHOICES_DEV31 checks=%d passed=%d failed=%d"%[checks,checks-failures,failures])
 quit(1 if failures else 0)
