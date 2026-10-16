extends SceneTree
const Free=preload("res://scripts/pilot_free_simulation_v1.gd")
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v1.gd")
const Inputs=preload("res://scripts/pilot_free_input_v1.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const OpenProfile=preload("res://scripts/pilot_extreme_profile.gd")
const Legacy=preload("res://scripts/pilot_extreme_simulation.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:
 _profile_and_timeline();_response();_destination_and_energy();_rescue();_replay();_legacy()
 print("FREE_FLIGHT_V1_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
func _route() -> Dictionary:
 # Generic free mechanics fixtures deliberately use an unbound ascent source.
 # New ground-choice content is immutable and has its own full-route fixture.
 var route:Dictionary=Profile.route(OpenProfile.route({"weight":1.0}))
 route.distance=10000.0;route.destination_y=-1000.0;route.hazards=[];route.pilot_gates=[]
 return route
func _sim(weight:float=1.0,force:float=28.0):
 var design:Array=Profile.starter_design()
 for p in design:
  if p.type=="thruster":p.param=force
 var route:Dictionary=_route();route.weight=weight
 var sim=Free.new();sim.configure(design,[],route,42);return sim
func _step(sim,ticks:int,x:int=0,y:int=0,boost:bool=false) -> void:
 for tick in range(ticks):
  sim.set_free_flight_input(x,y,boost,false);sim.step(1.0/60.0)
func _place(sim,at:Vector2,velocity:Vector2) -> void:
 var b:Dictionary=sim.body_for_part(1)
 b.position+=at-sim.cargo_position();b.velocity=velocity;b.angular_velocity=0.0
func _profile_and_timeline() -> void:
 var base:Dictionary=Ground.route({"weight":1.0});var before:Dictionary=base.duplicate(true)
 var route:Dictionary=Profile.route(base)
 check(not route.is_empty() and Profile.validation_error(route).is_empty(),"explicit finite new profile is valid")
 check(base==before and base.control_version=="pilot-v3","authoring cannot mutate legacy source route")
 base.status="accepted";check(Profile.route(base).is_empty(),"accepted order cannot be relabeled")
 var invalid:Dictionary=route.duplicate(true);invalid.free_gimbal_slew_degrees=INF
 check(not Profile.validation_error(invalid).is_empty(),"nonfinite physical tuning rejected")
 invalid=route.duplicate(true);invalid.control_version="pilot-v3"
 check(Profile.has_markers(invalid) and not Profile.validation_error(invalid).is_empty(),"partial identity cannot masquerade as legacy")
 var t=Timeline.new();var state:Dictionary={"axis_x_q":-1000,"axis_q":500,"boost":false,"active":true}
 check(t.record(0,state) and t.record(80,state) and t.commands.size()==1,"two-axis held input is sparse")
 check(t.record(36001,Timeline.neutral()),"10-minute legacy ceiling does not stop new free flight")
 var snapshot:Array=t.snapshot();var replay=Timeline.new()
 check(replay.restore(JSON.parse_string(JSON.stringify(snapshot)),36002),"strict two-axis JSON replay accepted")
 check(replay.state_at(79)==state and replay.state_at(36001)==Timeline.neutral(),"both axes and release replay exactly")
 var old:Array=[{"tick":0,"axis_q":0,"boost":false,"active":false}]
 check(not replay.restore(old,20),"legacy one-axis record not silently adopted")
 check(replay.snapshot()==snapshot,"rejected restore preserves valid command history")
 var unknown:Array=snapshot.duplicate(true);unknown[0].surprise=true
 check(not replay.restore(unknown,36002),"unknown command field rejected")
 var fractional:Array=snapshot.duplicate(true);fractional[0].axis_x_q=0.5
 check(not replay.restore(fractional,36002),"fractional saved quantized axis rejected")
 check(Inputs.state({KEY_A:true,KEY_W:true}).axis_x_q==-1000 and Inputs.state({KEY_A:true,KEY_D:true}).axis_x_q==0,"keyboard reverse and opposite-key cancellation exist")
func _response() -> void:
 var idle=_sim();var start:Vector2=idle.cargo_position();_step(idle,120)
 check(idle.cargo_position().distance_to(start)<0.0001 and idle.telemetry.energy_used<0.0001,"neutral rest has no hidden route-following forward force")
 var climb=_sim();_step(climb,60,0,-1000)
 var climb_velocity:Vector2=climb.body_for_part(1).velocity
 print("MEASURE climb_1s=",climb_velocity," energy=",climb.telemetry.energy_used)
 check(climb_velocity.y < -1.5 and climb.cargo_position().y<start.y-0.4,"starter gains meaningful upward velocity/displacement within one second")
 var reverse=_sim();_place(reverse,Vector2.ZERO,Vector2(6,0));_step(reverse,1,-1000,0)
 check(reverse.body_for_part(1).velocity.x>5.8,"reverse is finite impulse, not immediate velocity clamp")
 _step(reverse,119,-1000,0)
 print("MEASURE reverse_after_2s=",reverse.body_for_part(1).velocity," energy=",reverse.telemetry.energy_used)
 check(reverse.body_for_part(1).velocity.x < -0.25,"starter reverses horizontal velocity within two seconds from 6 m/s")
 var vertical=_sim();_place(vertical,Vector2.ZERO,Vector2(0,-4));_step(vertical,90,0,1000)
 check(vertical.body_for_part(1).velocity.y>0.1,"starter reverses vertical velocity with held opposite input")
 var brake=_sim();_place(brake,Vector2.ZERO,Vector2(6,-2));_step(brake,150)
 print("MEASURE brake_2_5s=",brake.body_for_part(1).velocity," energy=",brake.telemetry.energy_used)
 check(brake.body_for_part(1).velocity.length()<0.8 and brake.telemetry.energy_used>1.0,"release brakes both axes by paid nozzle work")
 var heavy=_sim(2.0);var weak=_sim(1.0,10.0);var strong=_sim()
 _step(heavy,60,0,-1000);_step(weak,60,0,-1000);_step(strong,60,0,-1000)
 check(absf(heavy.body_for_part(1).velocity.y)<absf(strong.body_for_part(1).velocity.y),"cargo mass still limits actual response")
 check(absf(weak.body_for_part(1).velocity.y)<absf(strong.body_for_part(1).velocity.y),"mounted thrust parameter still limits actual response")
 check(strong.total_energy()<6000.0 and strong.total_energy()>0.0,"maneuver consumes finite stored battery")
 var boost=_sim();_step(boost,600,1000,0,true)
 var boost_velocity:Vector2=boost.body_for_part(1).velocity
 print("MEASURE boost_10s=",boost_velocity," energy=",boost.telemetry.energy_used)
 check(boost.status=="running" and boost_velocity.x>16.0 and boost_velocity.length()<18.5,"held Shift approaches18m/s through force without unbounded thrust buildup")
 check(boost.telemetry.energy_used>1000.0 and boost.total_energy()>0.0,"boost kinetic energy and servo work come from finite battery")
 var overspeed=_sim();_place(overspeed,Vector2.ZERO,Vector2(30,0));_step(overspeed,1,1000,0,true)
 check(overspeed.body_for_part(1).velocity.x>29.8,"boost speed request never clamps externally supplied overspeed")
 _step(overspeed,120,1000,0,true)
 check(overspeed.body_for_part(1).velocity.x<25.0 and overspeed.telemetry.energy_used>0.0,"overspeed is reduced by paid counter-thrust")

 var normal=_sim();var rotated_design:Array=Profile.starter_design()
 for p in rotated_design:
  if p.type=="thruster":p.rot=2
 var rotated=Free.new();rotated.configure(rotated_design,[],_route(),42)
 _step(normal,1,1000,0);_step(rotated,1,1000,0)
 check(normal.body_for_part(1).velocity.x>rotated.body_for_part(1).velocity.x,"installed arrow still controls initial paid slew and impulse")
 var collision=_sim();var starting_hp:float=0.0
 for p in collision.parts.values():starting_hp+=p.hp
 collision.obstacles.append({"position":Vector2(8,0),"velocity":Vector2.ZERO,"mass":1000000.0,"radius":1.0,"health":1000000.0,"type":"rock","cooldown":0.0,"conductive":false})
 _place(collision,Vector2.ZERO,Vector2(18,0));_step(collision,45,1000,0,true)
 var after_hp:float=0.0
 for p in collision.parts.values():after_hp+=p.hp
 check(after_hp<starting_hp and collision.telemetry.swept_contacts>0,"free-flight collision chronology still causes real damage")

 var disconnected=_sim();disconnected.parts[3].energy=0.0
 disconnected._check_status();check(disconnected.status=="failed","depleted battery fails even with neutral input")
func _destination_and_energy() -> void:
 var sim=_sim();var at:Vector2=Vector2(-100,500)
 _place(sim,at,Vector2.ZERO);sim.elapsed=7200.0;sim._check_status()
 check(sim.status=="running","backtracking/detour beyond old bounds and old time_limit remain valid")
 var overshoot=_sim();overshoot.route.distance=30.0;overshoot.route.destination_y=0.0;overshoot.route.max_delivery_speed=2.0
 _place(overshoot,Vector2(30,0),Vector2(8,0));overshoot._check_status();overshoot._refresh_telemetry()
 check(overshoot.status=="running" and overshoot.telemetry.arrival_state=="slow_down","fast receiver pass stays controllable and says slow down")
 # Real force-driven return from beyond the old destination+30 cut-off.
 _place(overshoot,Vector2(70,0),Vector2.ZERO)
 for tick in range(900):
  var error:Vector2=Vector2(30,0)-overshoot.cargo_position()
  var vel:Vector2=overshoot.body_for_part(1).get("velocity",Vector2.ZERO)
  var command:Vector2=(error*0.55-vel*0.25)/12.0
  if error.length()<5.5:command=Vector2.ZERO
  overshoot.set_free_flight_input(clampi(roundi(command.x*1000),-1000,1000),clampi(roundi(command.y*1000),-1000,1000),false,false)
  overshoot.step(1.0/60.0)
  if overshoot.status!="running":break
 check(overshoot.status=="success","physically reverse from overshoot, brake and deliver")
 check(overshoot.parts[3].recovered and overshoot.parts[4].recovered,"attached battery/engines recovered before any-side detach")
 check(overshoot.telemetry.energy_remaining>0.0,"received display retains real captured unused energy")
 for side in [-1.0,1.0]:
  var arrival=_sim();arrival.route.distance=30.0;arrival.route.destination_y=0.0
  _place(arrival,Vector2(30.0+side*2.0,0),Vector2.ZERO);arrival._check_status()
  check(arrival.status=="success","destination accepts safe approach from side "+str(side))
 var detached=_sim();detached.links.clear();detached._rebuild_bodies();detached._refresh_telemetry();detached._check_status()
 check(detached.telemetry.energy_remaining==0.0 and detached.status=="failed","remote detached batteries cannot fund cargo or postpone empty failure")
 var destroyed=_sim();destroyed.parts[1].alive=false;destroyed._check_status()
 check(destroyed.status=="failed" and destroyed.telemetry.free_failure=="cargo_destroyed","cargo damage failure still exists")
func _rescue() -> void:
 var sim=_sim();_place(sim,Vector2(-200,500),Vector2(8,0))
 sim.parts[5].hp-=30.0
 sim._destroy(sim.parts[4])
 sim._charge_replacement(sim.parts[6],"ammo");sim._destroy(sim.parts[6])
 sim.links.clear();sim._rebuild_bodies()
 sim.status="failed";sim.finalize_settlement()
 check(sim.parts[3].recovered and sim.parts[5].recovered and sim.parts[1].recovered,"failed rescue returns distant detached surviving battery, armor and cargo")
 check(not sim.parts[4].recovered and not sim.parts[6].recovered,"rescue never resurrects destroyed or consumed modules")
 check(sim.telemetry.lost_cost==sim.parts[4].price and sim.telemetry.ammo_cost==sim.parts[6].price,"destroyed and consumed replacements billed exactly once")
 check(sim.parts[5].hp==120.0 and sim.parts[3].energy==6000.0 and sim.telemetry.repair_cost>0.0,"rescue preserves actual damage and remaining charge; repair is still billed")
 var counts:Dictionary={"rescued":sim.telemetry.rescue_recovered_count,"recovered":sim.telemetry.recovered_count,"replenished":sim.telemetry.replenished_count,"lost":sim.telemetry.lost_cost,"ammo":sim.telemetry.ammo_cost,"events":sim.events.size()}
 sim.finalize_settlement()
 check(counts=={"rescued":sim.telemetry.rescue_recovered_count,"recovered":sim.telemetry.recovered_count,"replenished":sim.telemetry.replenished_count,"lost":sim.telemetry.lost_cost,"ammo":sim.telemetry.ammo_cost,"events":sim.events.size()},"repeated settlement cannot duplicate rescue or replenishment")

func _replay() -> void:
 var a=_sim();var t=Timeline.new()
 for tick in range(360):
  var command:Dictionary={"axis_x_q":1000 if tick<120 else (-750 if tick<240 else 0),"axis_q":-500 if tick<180 else 500,"boost":false,"active":false}
  t.record(tick,command);a.set_free_flight_input(command.axis_x_q,command.axis_q,command.boost,command.active);a.step(1.0/60.0)
 var snapshot:Dictionary=JSON.parse_string(JSON.stringify({"route":a.route,"input_schema":Profile.INPUT_SCHEMA,"ticks":360,"commands":t.snapshot()}))
 var b=Free.new();b.configure(Profile.starter_design(),[],snapshot.route,42)
 var restored=Timeline.new();check(restored.restore(snapshot.commands,snapshot.ticks),"persisted two-axis trajectory restores")
 for tick in range(snapshot.ticks):
  var c:Dictionary=restored.state_at(tick);b.set_free_flight_input(c.axis_x_q,c.axis_q,c.boost,c.active);b.step(1.0/60.0)
 check(a.status==b.status and a.cargo_position()==b.cargo_position() and a.body_for_part(1).velocity==b.body_for_part(1).velocity,"JSON route plus commands replay exact trajectory")
 check(a.telemetry.energy_used==b.telemetry.energy_used and a.parts[4].gimbal_angle==b.parts[4].gimbal_angle,"replay preserves paid energy and finite nozzle state")
 # Existing host pause/clear API must not leave X latched.
 a.set_free_flight_input(-1000,1000,true,true);a.set_pilot_input(0,false,false)
 check(a.pilot_axis_x_q==0 and a.pilot_axis_q==0 and not a.pilot_boost,"old neutral clear also clears new horizontal held state")
func _legacy() -> void:
 var route:Dictionary=Ground.route({"weight":1.0});route.hazards=[];route.pilot_gates=[]
 var legacy=Legacy.new();legacy.configure(Profile.starter_design(),[],route,42)
 for tick in range(60):legacy.set_pilot_input(0,false,false);legacy.step(1.0/60.0)
 check(legacy.route.control_version=="pilot-v3" and legacy.body_for_part(1).velocity.x>0.5,"legacy protocol retains its own auto-forward behavior")
 _place(legacy,Vector2(-100,0),Vector2.ZERO);legacy._check_status()
 check(legacy.status=="failed","legacy saved boundary rule remains unchanged")
