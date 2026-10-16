extends SceneTree
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Content=preload("res://scripts/pilot_free_ground_route_v1.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Free=preload("res://scripts/pilot_free_simulation_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Expanded=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:
 _snapshot_rules()
 _light_detour()
 _drill_controlled_contact()
 _drill_simple_approach("low_stick")
 _drill_simple_approach("brake_then_continue")
 print("FREE_GROUND_CHOICE_V1_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
func _route() -> Dictionary:return Profile.route(Ground.route({"id":0,"weight":1.0}))
func _drill_design() -> Array:
 var design:Array=Profile.starter_design()
 # This is a paid-build fixture, not an automatically granted default module.
 # One drill at(2,0) sockets to the existing front armor at(1,0).
 design.append(Extreme.part(9,"drill",2,0,{"input_a":-1}))
 return design
func _sim(drill:bool=false):
 var sim=Free.new()
 sim.configure(_drill_design() if drill else Profile.starter_design(),Profile.starter_launcher(),_route(),42)
 return sim
func _step(sim,input:Vector2) -> void:
 sim.set_free_flight_input(clampi(roundi(input.x*1000.0),-1000,1000),clampi(roundi(input.y*1000.0),-1000,1000),false,false)
 sim.step(1.0/60.0)
func _toward(sim,target:Vector2,speed:float) -> Vector2:
 var delta:Vector2=target-sim.cargo_position()
 return delta.normalized()*minf(speed,delta.length()*1.5)/float(sim.route.free_cruise_speed)
func _measure(label:String,sim) -> void:
 print("GROUND_MEASURE ",label," ",JSON.stringify({"status":sim.status,"elapsed":sim.elapsed,"position":[sim.cargo_position().x,sim.cargo_position().y],"energy_used":sim.telemetry.energy_used,"energy_remaining":sim.telemetry.energy_remaining,"integrity":sim.telemetry.integrity,"drill_hp":sim.parts.get(9,{}).get("hp",0.0),"drill_alive":sim.parts.get(9,{}).get("alive",false),"drill_contacts":sim.telemetry.drill_contacts,"drill_damage":sim.telemetry.drill_damage,"drill_energy_used":sim.telemetry.drill_energy_used,"rock_health":sim.obstacles[0].health,"repair_cost":sim.telemetry.repair_cost,"lost_cost":sim.telemetry.lost_cost,"contacts":sim.telemetry.swept_contacts}))
func _snapshot_rules() -> void:
 var legacy:Dictionary=Ground.route({"id":0,"weight":1.0});var frozen:Dictionary=legacy.duplicate(true)
 var route:Dictionary=Profile.route(legacy)
 check(legacy==frozen and legacy.hazards.size()==6 and legacy.distance==360.0,"old ground catalog source remains unchanged")
 check(route.route_profile==Content.ROUTE_PROFILE and route.free_ground_schema==Content.SCHEMA and route.distance==260.0,"fresh ordinary ground is explicit short choice content")
 check(route.hazards.size()==1 and route.pilot_gates.is_empty() and route.hazards[0].destructible and not route.hazards[0].has("pilot_gate"),"single breakable physical rock has no mandatory gate tag")
 check(Profile.validation_error(JSON.parse_string(JSON.stringify(route))).is_empty(),"deterministic exact ground snapshot survives JSON")
 check(Profile.route(route).is_empty(),"already authored free snapshot cannot be reauthored")
 var corrupted:Dictionary=route.duplicate(true);corrupted.hazards[0].health=47.0
 check(not Profile.validation_error(corrupted).is_empty(),"ground snapshot cannot silently reroll rock health")
 corrupted=route.duplicate(true);corrupted.erase("free_ground_schema")
 check(Profile.has_markers(corrupted) and not Profile.validation_error(corrupted).is_empty(),"partial new-ground identity fails closed")
 var drill:Array=_drill_design()
 check(drill.size()==9 and drill[8].x==2 and drill[8].y==0 and drill[8].rot==0 and drill[8].input_a==-1,"drill example is one real forward module on existing front armor")
 var light=_sim();var heavy=_sim(true)
 check(absf(heavy.total_mass()-light.total_mass()-1.8)<0.000001,"drill adds real1.8kg without a mass waiver")
 check(heavy._same_circuit(heavy.parts[1],heavy.parts[9]),"front drill shares a genuine live socket circuit")
func _light_detour() -> void:
 var sim=_sim();var waypoints:Array=[Vector2(95,-14),Vector2(155,-14),Content.DESTINATION]
 var phase:int=0;var minimum_clearance:float=INF
 for tick in range(7200):
  if sim.status!="running":break
  if phase<waypoints.size()-1 and sim.cargo_position().distance_to(waypoints[phase])<2.0:phase+=1
  minimum_clearance=minf(minimum_clearance,sim.cargo_position().distance_to(Vector2(Content.ROCK.x,Content.ROCK.y))-float(Content.ROCK.radius))
  _step(sim,_toward(sim,waypoints[phase],12.0))
 _measure("light_above_detour",sim)
 check(sim.status=="success" and sim.telemetry.integrity==1.0,"default light ship physically flies around rock and delivers intact")
 check(sim.telemetry.swept_contacts==0 and sim.obstacles[0].health==Content.ROCK.health,"detour leaves real obstacle intact with zero contact")
 check(sim.telemetry.energy_remaining>0.0 and sim.telemetry.energy_used>0.0,"detour pays actual propulsion and remains within finite charge")
 check(minimum_clearance>2.0,"detour has body-scale clearance, not a pixel-perfect gap")
func _drill_controlled_contact() -> void:
 var sim=_sim(true)
 var before_snapshot:Dictionary=sim.route.duplicate(true)
 for tick in range(7200):
  if sim.status!="running":break
  if sim.obstacles[0].health<=0.0:
   _step(sim,_toward(sim,Content.DESTINATION,12.0));continue
  if not sim.parts[9].alive or sim.body_for_part(9).is_empty():break
  # Physical contact target derives from actual mounted drill/head geometry.
  # This precise probe validates cutting, not beginner usability.
  var head:Vector2=sim.part_world_position(9)+Vector2.RIGHT.rotated(sim.body_for_part(9).angle+sim.parts[9].local_angle)*Expanded.DRILL_HEAD_OFFSET
  var gap:float=Content.ROCK.x-float(Content.ROCK.radius)-Expanded.DRILL_HEAD_RADIUS-head.x
  var approach_speed:float=clampf(sqrt(maxf(0.0,gap)*3.0),0.6,12.0)
  var target:Vector2=Vector2(Content.ROCK.x,float(Content.ROCK.y))
  _step(sim,_toward(sim,target,approach_speed))
 _measure("controlled_contact",sim)
 check(sim.status=="success" and sim.parts[9].alive,"paid drill physically breaches rock and survives delivery")
 check(sim.obstacles[0].health<=0.0 and sim.telemetry.drill_contacts>0 and sim.telemetry.drill_damage>0.0,"drill reports actual contact damage to the authored rock")
 check(sim.telemetry.drill_energy_used>0.0 and sim.telemetry.energy_remaining>0.0,"drill uses finite60J/s power with real remaining charge")
 check(sim.route==before_snapshot,"live rock damage never rewrites immutable route snapshot")
func _drill_simple_approach(mode:String) -> void:
 var sim=_sim(true);var brake_started:bool=false;var brake_ticks:int=0
 var heading:Vector2=Content.DESTINATION.normalized()
 for tick in range(7200):
  if sim.status!="running":break
  var input:Vector2=heading*0.25 if mode=="low_stick" else heading
  # A visible broad slowdown: release direction once before the rock, wait4s,
  # then press toward it again. No nose-position feedback or0.6m/s servo script.
  if mode=="brake_then_continue" and not brake_started and sim.cargo_position().x>=96.0:
   brake_started=true;brake_ticks=240
  if brake_ticks>0:input=Vector2.ZERO;brake_ticks-=1
  _step(sim,input)
 _measure(mode,sim)
 check(sim.status=="success" and sim.parts[9].alive and sim.telemetry.integrity>=0.90,"simple "+mode+" approach breaches with surviving drill and>=90% cargo")
 check(sim.obstacles[0].health<=0.0 and sim.telemetry.drill_contacts>0 and sim.telemetry.drill_damage>0.0,"simple "+mode+" uses real paid contact cutting")
 check(sim.telemetry.energy_remaining>0.0 and sim.telemetry.drill_energy_used>0.0,"simple "+mode+" remains finite-energy feasible")
