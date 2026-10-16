extends SceneTree
const Rift=preload("res://scripts/pilot_delivery_rift_simulation_v8.gd")
const Ground=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
const P=preload("res://scripts/pilot_delivery_profile_v8.gd")
func _initialize():
 for heated in [false,true]:fly_rift(heated)
 for braking in [false,true]:fly_ground(braking)
 quit()
func fly_rift(heated:bool):
 var f:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_RIFT_FIXED")))
 var ship:Array=f.ship
 for p in ship:
  if p.id==1025:p.type="heater";p.param=0;p.input_a=-1 if heated else 9999
 var s=Rift.new();s.configure(ship,f.launcher,f.route,42);s.release_launcher(0,.79)
 for tick in range(5400):
  if s.status!="running":break
  var b:Dictionary=s.body_for_part(1)
  var at:Vector2=s.cargo_position();var target=Vector2(200,0) if s.telemetry.region=="greenhouse" else Vector2(29,0)
  var delta=target-at;var speed=minf(12,sqrt(5.6*maxf(0,delta.length()-1)))
  var request:Vector2=(delta.normalized()*speed-b.velocity).limit_length(3)
  var input:Vector2=request*float(b.mass)/(56*.72)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false);s.step(1.0/60)
 print("HEATER_FLIGHT ",JSON.stringify({"heated":heated,"status":s.status,"seconds":s.elapsed,"integrity":s.ship_integrity(),"energy":s.telemetry.energy_used,"cold_damage":s.telemetry.biological_damage,"heater_energy":s.telemetry.get("heater_energy_used",0),"prevented":s.telemetry.get("heater_cold_prevented",0),"quote":C.quote(f.route,s.telemetry,s.status=="success")}))
func fly_ground(braking:bool):
 var f:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_RIFT_FIXED")))
 var ship:Array=f.ship
 for p in ship:
  if p.id==1025:p.type="airbrake";p.param=0;p.input_a=-2
 var r=C.fresh_route(1);var s=Ground.new();s.configure(ship,P.starter_launcher(),r,42);s.release_launcher(15,.12)
 var points=[Vector2(20,-14),Vector2(55,-14),Vector2(80,-8)];var i=0
 for tick in range(5400):
  if s.status!="running":break
  var b:Dictionary=s.body_for_part(1);var at:Vector2=s.cargo_position()
  if at.distance_to(points[i])<2 and i<2:i+=1
  var delta:Vector2=points[i]-at;var speed=minf(12,sqrt(4*maxf(0,delta.length()-.2)))
  var request:Vector2=(delta.normalized()*speed-b.velocity).limit_length(2)
  var active:bool=braking and request.dot(b.velocity)<0 and b.velocity.length()>5
  # Fixed assist replaces requested retro thrust only along velocity when deployed.
  if active:request-=request.project(b.velocity)
  var input:Vector2=request*float(b.mass)/(56*.72)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,active,1025,false);s.step(1.0/60)
 print("AIRBRAKE_FLIGHT ",JSON.stringify({"braking":braking,"status":s.status,"seconds":s.elapsed,"integrity":s.ship_integrity(),"energy":s.telemetry.energy_used,"air_work":s.telemetry.get("airbrake_work",0),"brake_seconds":s.telemetry.get("airbrake_active_seconds",0),"quote":C.quote(r,s.telemetry,s.status=="success")}))
