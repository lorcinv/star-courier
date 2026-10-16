extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_rift_simulation_v8.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
func _initialize():
 for mode in ["bare_warm"]:fly(mode)
 quit()
func fly(mode:String):
 var f:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_RIFT_FIXED")))
 var r:Dictionary=C.offer(5,6,0,false,false,false,true)
 var ship:Array=f.ship.duplicate(true)
 if mode.begins_with("heater"):
  ship[4].y=1
  ship.append({"id":1026,"type":"heater","x":1,"y":0,"rot":0,"param":0,"target":-1,"input_a":-1 if mode=="heater_direct" else 9999,"input_b":-1})
 var s=Sim.new();s.configure(ship,f.launcher,r,42);s.release_launcher(0,.25)
 var points:Array=[Vector2(240,0)]
 if mode=="bare_warm":points=[Vector2(104,40),Vector2(218,40),Vector2(240,0)]
 var was_cold:bool=false
 var i:int=0;var initial_mass:float=s.body_for_part(1).mass
 for tick in range(7200):
  if s.status!="running":break
  var b:Dictionary=s.body_for_part(1);var at:Vector2=s.cargo_position()
  var cold:bool=Rect2(110,-30,100,60).has_point(at) and s.telemetry.region=="greenhouse"
  if cold!=was_cold:print("COLD_EDGE ",s.elapsed," ",at," velocity ",b.velocity);was_cold=cold
  var entered:bool=s.telemetry.region=="greenhouse"
  if entered and at.distance_to(points[i])<2 and i<points.size()-1:i+=1
  var target:Vector2=points[i] if entered else Vector2(29,0)
  var delta:Vector2=target-at;var speed:float=minf(12,sqrt(5.6*maxf(0,delta.length()-1)))
  var request:Vector2=(delta.normalized()*speed-b.velocity).limit_length(3)
  var input:Vector2=request*float(b.mass)/(56*.72)
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false);s.step(1.0/60)
 print("TRIAL ",JSON.stringify({"mode":mode,"hardware_cost":215 if mode.begins_with("heater") else 170,"initial_mass":initial_mass,"status":s.status,"seconds":s.elapsed,"integrity":s.ship_integrity(),"energy":s.telemetry.energy_used,"cold_damage":s.telemetry.biological_damage,"heater_energy":s.telemetry.get("heater_energy_used",0),"prevented":s.telemetry.get("heater_cold_prevented",0),"quote":C.quote(r,s.telemetry,s.status=="success"),"final_pos":[s.cargo_position().x,s.cargo_position().y],"telemetry":s.telemetry}))
