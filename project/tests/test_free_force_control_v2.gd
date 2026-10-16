extends SceneTree
## Focused deterministic source-side mechanics fixture. Lead runs engine serially.
const Free=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Inputs=preload("res://scripts/pilot_free_input_v2.gd")
const OldFree=preload("res://scripts/pilot_free_simulation_v1.gd")
const OldProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const OldTimeline=preload("res://scripts/pilot_free_timeline_v1.gd")
const Open=preload("res://scripts/pilot_extreme_profile.gd")
const Framing=preload("res://scripts/free_flight_framing_2d.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:
 _profile_and_timeline();_force_and_coast();_physical_response();_teleport_and_selection();_launch();_replay();_high_speed();_legacy()
 print("FREE_FORCE_CONTROL_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func route() -> Dictionary:
 var data:Dictionary=Profile.route(Open.route({"weight":1.0}))
 data.hazards=[];data.pilot_gates=[];data.distance=10000.0;data.destination_y=-1000.0;data.pilot_drag=0.0
 return data
func design(devices:bool=false) -> Array:
 var result:Array=Profile.starter_design()
 if devices:
  result.append({"id":9,"type":"teleporter","x":2,"y":0,"rot":0,"param":8.0,"input_a":-2})
  result.append({"id":10,"type":"teleporter","x":2,"y":1,"rot":1,"param":8.0,"input_a":-2})
 return result
func make_sim(devices:bool=false,pad:Array=[]):
 var sim=Free.new();sim.configure(design(devices),pad,route(),42);return sim
func place(sim,at:Vector2,velocity:Vector2) -> void:
 var body:Dictionary=sim.body_for_part(1)
 body.position+=at-sim.cargo_position();body.velocity=velocity;body.angular_velocity=0.0
func step(sim,ticks:int,x:int=0,y:int=0,boost:bool=false,active:bool=false,device_id:int=-1,brake:bool=false) -> void:
 for tick in range(ticks):
  if sim.status!="running":break
  sim.set_free_flight_input(x,y,boost,active,device_id,brake);sim.step(1.0/60.0)
func rock(at:Vector2) -> Dictionary:
 return {"position":at,"velocity":Vector2.ZERO,"mass":1000000.0,"radius":1.0,"health":1000000.0,"type":"rock","cooldown":0.0,"conductive":false}
func total_hp(sim) -> float:
 var result:float=0.0
 for p in sim.parts.values():result+=p.hp
 return result
func state(sim) -> Dictionary:
 return {"status":sim.status,"elapsed":sim.elapsed,"bodies":sim.bodies.duplicate(true),"parts":sim.parts.values().duplicate(true),"links":sim.links.duplicate(true),"telemetry":sim.telemetry.duplicate(true),"events":sim.events.duplicate(true),"pilot_tick":sim.pilot_tick,"aim":[sim.pilot_aim_x_q,sim.pilot_aim_y_q],"device":sim.pilot_device_id,"edge":sim._active_edge_device_id,"brake":sim.pilot_brake,"rng":sim._rng.state}
func _profile_and_timeline() -> void:
 var base:Dictionary=Open.route({"weight":1.0});var original:Dictionary=base.duplicate(true)
 var authored:Dictionary=Profile.route(base)
 check(Profile.validation_error(authored).is_empty() and authored.control_version=="pilot-free-v2","explicit v2 route validates")
 check(base==original,"authoring leaves source route exact")
 var starter:Array=Profile.starter_design();var legacy_starter:Array=OldProfile.starter_design()
 var coupler:Dictionary={};var target:Dictionary={};var old_coupler:Dictionary={}
 for p in starter:
  if p.id==8:coupler=p
  if p.id==3:target=p
 for p in legacy_starter:
  if p.id==8:old_coupler=p
 check(coupler.type=="coupler" and coupler.input_a==-2 and coupler.target==3 and absi(coupler.x-target.x)+absi(coupler.y-target.y)==1,"new v2 starter has an explicitly selected cockpit coupler with adjacent target")
 check(old_coupler.input_a==-1 and old_coupler.target==-1,"new starter wiring never mutates legacy design")
 var starter_sim=make_sim();var before_links:int=starter_sim.links.size();step(starter_sim,1,0,0,false,true,8)
 check(starter_sim.links.size()==before_links-1 and 8 in starter_sim.selectable_device_ids(),"starter selected coupler actually cuts its one explicit socket edge")
 var old:Dictionary=OldProfile.route(base)
 check(Profile.route(old).is_empty() and not Profile.validation_error(old).is_empty(),"v1 route cannot be relabeled or loaded as v2")
 base.contract_id="committed";check(Profile.route(base).is_empty(),"committed contract is never reauthored")
 var bad:Dictionary=authored.duplicate(true);bad.free_cruise_speed=12.0
 check(not Profile.validation_error(bad).is_empty(),"v2 rejects obsolete speed-governor field")
 bad=authored.duplicate(true);bad.free_drive_throttle=INF
 check(not Profile.validation_error(bad).is_empty(),"nonfinite thrust tuning is rejected")
 var timeline=Timeline.new();var command:Dictionary=Timeline.neutral()
 command.axis_x_q=-1000;command.axis_q=500;command.device_id=9;command.active=true
 check(timeline.record(0,command) and timeline.record(60,command) and timeline.commands.size()==1,"six-field held command stores sparsely")
 command=command.duplicate();command.brake=true
 check(timeline.record(61,command) and timeline.commands.size()==2,"brake transition is recorded")
 command=command.duplicate();command.device_id=10
 check(timeline.record(62,command) and timeline.commands.size()==3,"device selection transition is recorded")
 var saved:Array=timeline.snapshot();var replay=Timeline.new()
 check(replay.restore(JSON.parse_string(JSON.stringify(saved)),90) and replay.state_at(62)==command,"seven-key JSON timeline roundtrips")
 check(not replay.restore(OldTimeline.new().snapshot(),90) and replay.snapshot()==saved,"v1 command shape rejects atomically")
 for mutation in [{"device_id":-2},{"device_id":2.5},{"device_id":INF},{"device_id":2147483648.0},{"brake":1},{"axis_q":1001},{"axis_x_q":NAN},{"active":1}]:
  var malformed:Array=saved.duplicate(true);malformed[0].merge(mutation,true)
  check(not replay.restore(malformed,90) and replay.snapshot()==saved,"invalid command preserves history "+str(mutation))
 var extra:Array=saved.duplicate(true);extra[0].unknown=true
 check(not replay.restore(extra,90),"unknown persisted field rejected")
 var input:Dictionary=Inputs.state({KEY_W:true,KEY_A:true,KEY_CTRL:true,KEY_SPACE:true},null,9)
 check(input.axis_x_q==-1000 and input.axis_q==-1000 and input.brake and input.active and input.device_id==9,"keyboard input records steering brake and explicit device")
 check(Inputs.state({KEY_A:true,KEY_D:true}).axis_x_q==0,"opposite keyboard directions cancel")
func _force_and_coast() -> void:
 var sim=make_sim();var body:Dictionary=sim.body_for_part(1)
 sim.set_free_flight_input(1000,0,false,false)
 body.velocity=Vector2.ZERO;sim._plan_pilot_forces(body);var rest:Dictionary=sim._planned_forces.duplicate(true)
 body.velocity=Vector2(100,0);sim._plan_pilot_forces(body)
 check(sim._planned_forces==rest,"held thrust allocation is independent of existing forward speed")
 var net:Vector2=Vector2.ZERO
 for force in sim._planned_forces.values():net+=force
 check(net.x>0.0,"even at100m/s forward input never requests governor counter-thrust")
 sim.set_free_flight_input(-1000,0,false,false);sim._plan_pilot_forces(body);net=Vector2.ZERO
 for force in sim._planned_forces.values():net+=force
 check(net.x<0.0,"negative X requests genuine reverse force")
 sim.set_free_flight_input(1000,0,true,false);sim._plan_pilot_forces(body)
 var boost_net:Vector2=Vector2.ZERO
 for force in sim._planned_forces.values():boost_net+=force
 var normal_net:Vector2=Vector2.ZERO
 for force in rest.values():normal_net+=force
 check(boost_net.length()>normal_net.length(),"boost changes mounted throttle, not speed target")
 for id in sim._planned_forces:
  var p:Dictionary=sim.parts[id]
  check(Vector2(sim._planned_forces[id]).length()<=p.param*p.output_factor+0.0001,"per-nozzle thrust remains bounded "+str(id))
 var idle=make_sim();var at:Vector2=idle.cargo_position();step(idle,60)
 check(idle.cargo_position()==at and idle.telemetry.energy_used==0.0,"rest has no artificial translation or paid idle servo")
 var drift=make_sim();place(drift,Vector2.ZERO,Vector2(12,-3));step(drift,60)
 check(drift.body_for_part(1).velocity==Vector2(12,-3) and drift.cargo_position().x>11.9 and drift.telemetry.energy_used==0.0,"release visibly preserves inertial two-axis coast")
 var fast=make_sim();place(fast,Vector2.ZERO,Vector2(30,0));step(fast,30,1000,0)
 check(fast.status=="running" and fast.body_for_part(1).velocity.x>30.5 and fast.telemetry.energy_used>0.0,"ordinary thrust accelerates beyond old12/18 speed targets with paid work")
 print("MEASURE held_from30_speed=",fast.body_for_part(1).get("velocity")," energy=",fast.telemetry.energy_used)
func _physical_response() -> void:
 var reverse=make_sim();place(reverse,Vector2.ZERO,Vector2(6,0));step(reverse,1,-1000,0)
 check(reverse.body_for_part(1).velocity.x>5.8,"reverse has finite slew/impulse, no direct velocity assignment")
 step(reverse,179,-1000,0)
 check(reverse.body_for_part(1).velocity.x<0.0,"sustained opposite input reverses movement")
 var brake=make_sim();place(brake,Vector2.ZERO,Vector2(6,-2));step(brake,180,0,0,false,false,-1,true)
 check(brake.body_for_part(1).velocity.length()<0.8 and brake.telemetry.energy_used>1.0,"explicit brake slows both axes by paid forces")
 var priority=make_sim();place(priority,Vector2.ZERO,Vector2(6,0));step(priority,120,1000,0,true,false,-1,true)
 check(priority.body_for_part(1).velocity.x<2.0,"explicit brake takes priority over direction and boost")
 var heavy_route:Dictionary=route();heavy_route.weight=2.0
 var heavy=Free.new();heavy.configure(design(),[],heavy_route,42)
 var light=make_sim();step(heavy,60,1000,0);step(light,60,1000,0)
 check(heavy.body_for_part(1).velocity.x<light.body_for_part(1).velocity.x,"mass limits response")
 var empty=make_sim();empty.parts[3].energy=0.0;step(empty,1,1000,0)
 check(empty.status=="failed" and empty.telemetry.free_failure=="usable_energy_empty","finite empty battery still fails the cargo")
 var clearing=make_sim(true);clearing.set_free_flight_input(-1000,1000,true,true,9,true);clearing.set_pilot_input(0,false,false)
 check(clearing.pilot_axis_x_q==0 and clearing.pilot_axis_q==0 and not clearing.pilot_boost and not clearing.pilot_active and not clearing.pilot_brake and clearing._active_edge_device_id==-1,"pause/clear removes every live action without clearing deterministic last aim")
 check(clearing.pilot_aim_x_q==-1000 and clearing.pilot_aim_y_q==1000,"last aim survives safe release")
func _teleport_and_selection() -> void:
 for axis in [Vector2i(1000,0),Vector2i(-1000,0),Vector2i(0,-1000),Vector2i(0,1000),Vector2i(-1000,-1000)]:
  var sim=make_sim(true);var before:Vector2=sim.cargo_position();var energy:float=sim.total_energy()
  step(sim,1,axis.x,axis.y,false,true,9)
  var delta:Vector2=sim.cargo_position()-before;var expected:Vector2=Vector2(axis).normalized()*8.0
  check(delta.distance_to(expected)<0.02 and int(sim.telemetry.get("free_teleport_count",0))==1,"selected teleport follows recorded direction "+str(axis))
  check(sim.total_energy()<energy-24.9,"teleport spends real energy "+str(axis))
  step(sim,5,0,0,false,true,9)
  check(int(sim.telemetry.free_teleport_count)==1,"holding active never retriggers "+str(axis))
 var last=make_sim(true);last.set_free_flight_input(-1000,0,false,false,9);last.set_free_flight_input(0,0,false,true,9)
 var before:Vector2=last.cargo_position();last.step(1.0/60.0)
 check(last.cargo_position().x<before.x-7.9,"released directional history remains teleport aim")
 var selected=make_sim(true)
 check(selected.selectable_device_ids()==[8,9,10],"selector lists concrete live cockpit-wired IDs in stable order")
 step(selected,1,0,0,false,true,9);step(selected,1,0,0,false,true,10)
 check(int(selected.telemetry.free_teleport_count)==1,"cycling selected ID while held does not synthesize a new activation edge")
 step(selected,1,0,0,false,false,10);step(selected,1,0,0,false,true,10)
 check(int(selected.telemetry.free_teleport_count)==2,"release/repress activates exactly newly selected device")
 var mixed_design:Array=design(true)
 for p in mixed_design:
  if p.id==8:p.input_a=-2;p.target=3
 mixed_design.append({"id":11,"type":"accelerator","x":3,"y":0,"rot":0,"param":20.0,"input_a":-2,"target":9})
 var mixed=Free.new();mixed.configure(mixed_design,[],route(),42)
 var link_count:int=mixed.links.size();step(mixed,1,0,0,false,true,9)
 check(mixed.selectable_device_ids()==[8,9,10,11] and mixed.links.size()==link_count and not mixed.parts[11].spent,"selecting teleport does not fire wired coupler or accelerator")
 var unwired_design:Array=mixed_design.duplicate(true)
 for p in unwired_design:
  if p.id==11:p.input_a=-1
 var unwired=Free.new();unwired.configure(unwired_design,[],route(),42);step(unwired,1)
 check(not unwired.parts[11].spent and 11 not in unwired.selectable_device_ids(),"unwired accelerator cannot silently auto-fire in v2")
 var invalid=make_sim(true);step(invalid,1,0,0,false,true,99999)
 check(int(invalid.telemetry.get("free_teleport_count",0))==0 and invalid.pilot_device_id==99999,"invalid selection never substitutes a different device")
 var blocked=make_sim(true);place(blocked,Vector2.ZERO,Vector2.ZERO);blocked.obstacles.append(rock(Vector2(-8,0)))
 before=blocked.cargo_position();step(blocked,1,-1000,0,false,true,9)
 check(blocked.cargo_position().distance_to(before)<0.02 and int(blocked.telemetry.get("free_teleport_count",0))==0,"directional exit overlap remains blocked")
 var swept=make_sim(true);place(swept,Vector2.ZERO,Vector2(20,0));swept.obstacles.append(rock(Vector2(15,0)))
 check(not swept.destination_clear(swept.body_for_part(1),Vector2(8,0)),"post-exit0.22s high-speed collision preview remains")
 var detached=make_sim(true);detached._cut(9,5);detached._cut(9,10);detached._cut(10,7);detached._rebuild_bodies()
 check(9 not in detached.selectable_device_ids(),"detached device loses cockpit selection authority")
 var delivered=make_sim();delivered.route.distance=0.0;delivered.route.destination_y=0.0;place(delivered,Vector2.ZERO,Vector2(50,0));delivered._check_status();delivered._refresh_telemetry()
 check(delivered.status=="running" and delivered.telemetry.arrival_state=="slow_down","unsafe receiver speed still requires player braking")
func _launch() -> void:
 var none=make_sim();var standard=make_sim(false,Profile.starter_launcher())
 var powerful:Array=Profile.starter_launcher()
 # The shared spring is capped at60J; stronger output needs a real extra
 # motor and support, not an out-of-range slider that sanitizes back to60.
 powerful.append({"id":1005,"type":"armor","x":1,"y":-1,"rot":0,"param":0.0,"input_a":-1})
 powerful.append({"id":1006,"type":"thruster","x":0,"y":-1,"rot":0,"param":28.0,"input_a":-1})
 var strong=make_sim(false,powerful)
 var standard_start:Vector2=standard.cargo_position();var strong_start:Vector2=strong.cargo_position()
 var standard_v:float=standard.body_for_part(1).velocity.x;var strong_v:float=strong.body_for_part(1).velocity.x
 step(none,60);step(standard,60);step(strong,60)
 var normal_distance:float=standard.cargo_position().x-standard_start.x;var strong_distance:float=strong.cargo_position().x-strong_start.x
 print("MEASURE launch none=",none.body_for_part(1).velocity," standard_v=",standard_v," strong_v=",strong_v," normal_1s=",normal_distance," strong_1s=",strong_distance)
 check(none.body_for_part(1).velocity==Vector2.ZERO and standard_v>0.5 and strong_v>standard_v,"pad configuration creates physically different initial outgoing velocity")
 check(normal_distance>0.5 and strong_distance>normal_distance+0.1,"neutral first second visibly preserves launcher benefit")
 check(standard.parts[3].energy==standard.parts[3].capacity and standard.telemetry.launch_energy_drawn>0.0,"launch spends anchored pad battery without draining coasting ship battery")
func _replay() -> void:
 var a=make_sim(true,Profile.starter_launcher());var timeline=Timeline.new()
 for tick in range(300):
  var c:Dictionary={"axis_x_q":1000 if tick<60 else (-750 if tick<150 else 0),"axis_q":-500 if tick<80 else 0,"boost":tick<40,"active":tick in [20,21,95,150,151],"device_id":9 if tick<151 else 10,"brake":tick>=200}
  timeline.record(tick,c);a.set_free_flight_input(c.axis_x_q,c.axis_q,c.boost,c.active,c.device_id,c.brake);a.step(1.0/60.0)
 var snapshot:Dictionary=JSON.parse_string(JSON.stringify({"route":a.route,"input_schema":Profile.INPUT_SCHEMA,"ticks":300,"commands":timeline.snapshot()}))
 var b=Free.new();b.configure(design(true),Profile.starter_launcher(),snapshot.route,42)
 var restored=Timeline.new();check(restored.restore(snapshot.commands,snapshot.ticks),"full v2 recorded command stream restores")
 for tick in range(snapshot.ticks):
  var c:Dictionary=restored.state_at(tick);b.set_free_flight_input(c.axis_x_q,c.axis_q,c.boost,c.active,c.device_id,c.brake);b.step(1.0/60.0)
 check(state(a)==state(b),"JSON replay exactly reproduces force/coast/brake/selection/aim/launcher and paid state")
func _high_speed() -> void:
 var finite=make_sim();place(finite,Vector2.ZERO,Vector2(10000,-4000));step(finite,1)
 check(finite.status=="running" and finite.cargo_position().is_finite() and finite.body_for_part(1).velocity==Vector2(10000,-4000),"large finite unobstructed speed is not clamped or failed by arbitrary ceiling")
 var impact=make_sim();place(impact,Vector2.ZERO,Vector2(1000,0));impact.obstacles.append(rock(Vector2(6,0)))
 var hp:float=total_hp(impact);step(impact,1)
 check(total_hp(impact)<hp and int(impact.telemetry.get("swept_contacts",0))>0,"high-speed obstacle is struck by chronological CCD rather than tunneled through")
 for body in impact.bodies:
  check(body.position.is_finite() and body.velocity.is_finite() and is_finite(body.angle) and is_finite(body.angular_velocity),"high-speed contact remains finite")
 var frame:Dictionary=Framing.compose_bounds(Rect2(-50,-50,100,100),Vector2.ZERO,Vector2(100000,0),Rect2(99900,-100,200,200),200,Vector2(10000,-4000),32,Vector2(1280,720),Rect2(12,120,1256,466),1.0,"running")
 check(Vector2(frame.center).is_finite() and is_finite(float(frame.zoom)) and Vector2(frame.lookahead).length()<1000.0,"high-speed camera lookahead remains bounded independently of actual ship velocity")
func _legacy() -> void:
 var old_route:Dictionary=OldProfile.route(Open.route({"weight":1.0}));old_route.hazards=[];old_route.pilot_gates=[];old_route.distance=10000.0;old_route.destination_y=-1000.0;old_route.pilot_drag=0.0
 var old=OldFree.new();old.configure(OldProfile.starter_design(),[],old_route,42);place(old,Vector2.ZERO,Vector2(30,0))
 for tick in range(60):old.set_free_flight_input(1000,0,true,false);old.step(1.0/60.0)
 check(old.route.control_version==OldProfile.VERSION and old.body_for_part(1).velocity.x<30.0,"frozen v1 still has its original paid overspeed response")
 var rejected=Free.new();rejected.configure(design(),[],old_route,42)
 check(rejected.status=="failed" and not rejected.free_route_error.is_empty(),"v2 simulator refuses old trajectory identity")
