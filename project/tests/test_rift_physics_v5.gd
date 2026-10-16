extends SceneTree
const Profile=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const Sim=preload("res://scripts/pilot_delivery_rift_simulation_v5.gd")
const Old=preload("res://scripts/pilot_delivery_profile_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0.0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func craft(kind:String)->Array:
 var ship:Array=[part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(3,"thruster",-1,-1,28),part(4,"thruster",-1,1,28)]
 if kind=="warm":ship.append(part(5,"armor",0,-1,0))
 return ship
func make(ship:Array=[],pad:bool=false,data:Dictionary={}):
 var s=Sim.new();s.configure(craft("fast") if ship.is_empty() else ship,Profile.starter_launcher() if pad else [],Profile.route() if data.is_empty() else data,42);return s
func _initialize()->void:
 identity();portals();biology();flights()
 print("RIFT_PHYSICS_V5 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func identity()->void:
 var r:Dictionary=Profile.route();check(not r.is_empty() and Profile.validation_error(r).is_empty(),"explicit rift profile validates")
 check(not Old.validation_error(r).is_empty(),"old protocol rejects v5 instead of ignoring portal prerequisite")
 check(Profile.validation_error(JSON.parse_string(JSON.stringify(r))).is_empty(),"frozen route JSON roundtrip without reauthoring")
 check(Profile.route(r).is_empty(),"committed route cannot be silently reauthored")
 var bad:Dictionary=r.duplicate(true);bad.rift_pirate.ammo=INF
 check(not Profile.validation_error(bad).is_empty(),"nonfinite pirate or field data rejected")
 var s=make();check(s.telemetry.portal_crossing_tick==-1 and s.telemetry.region=="departure" and s.telemetry.portal_crossings.is_empty(),"uncrossed state exposes exact empty evidence")
func portals()->void:
 var s=make();var b:Dictionary=s.body_for_part(1);b.position=Vector2(27.98,0);b.velocity=Vector2(12,0);b.angular_velocity=0.04
 var momentum:Vector2=b.velocity;var spin:float=b.angular_velocity;var energy:float=s.telemetry.energy_remaining;var hp:float=s.ship_integrity();var route:Dictionary=s.route.duplicate(true)
 s.release_launcher(0,0);s.step(1.0/120.0)
 check(s.telemetry.region=="greenhouse" and s.telemetry.portal_crossing_tick==1 and s.telemetry.portal_crossings.size()==1,"real whole body CCD crossing creates one authoritative event")
 check(b.velocity==momentum and b.angular_velocity==spin and s.ship_integrity()==hp and s.telemetry.energy_remaining==energy,"passive gate preserves momentum cargo and finite stored energy")
 check(s.route==route,"runtime never rewrites frozen route")
 for i in range(10):s.step(1.0/120.0)
 check(s.telemetry.portal_crossings.size()==1,"postgate ticks cannot duplicate crossing")
 var off=make();off.body_for_part(1).position=Vector2(27.98,4.7);off.body_for_part(1).velocity=Vector2(12,0);off.release_launcher(0,0);off.step(1.0/120.0)
 check(off.telemetry.portal_crossing_tick==-1 and off.telemetry.portal_last_denial=="too_large_or_off_center","whole envelope rejects clipped offcenter entry")
 var blocked=make();blocked.body_for_part(1).position=Vector2(27.98,0);blocked.body_for_part(1).velocity=Vector2(12,0)
 blocked.obstacles.append({"type":"rock","position":Vector2(102,0),"velocity":Vector2.ZERO,"radius":2.0,"health":100.0,"mass":50.0})
 blocked.release_launcher(0,0);blocked.step(1.0/120.0)
 check(blocked.telemetry.portal_crossing_tick==-1 and blocked.telemetry.portal_last_denial=="exit_blocked","blocked actual exit rejects transit")
 var crowded:Dictionary=Profile.route();crowded.rift_pirate.position=[102.0,0.0]
 var unseen=make([],false,crowded);unseen.body_for_part(1).position=Vector2(27.98,0);unseen.body_for_part(1).velocity=Vector2(12,0)
 unseen.release_launcher(0,0);unseen.step(1.0/120.0)
 check(unseen.telemetry.portal_crossing_tick==-1 and unseen.telemetry.portal_last_denial=="exit_blocked","far-side pirate occupancy blocks exit before visual spawn")
 var skip=make([part(1,"cargo",0,0,100),part(2,"battery",-1,0,300),part(9,"teleporter",0,1,16,{"input_a":-2})]);skip.body_for_part(1).position=Vector2(20,0);skip.release_launcher(0,0)
 skip.set_free_flight_input(1000,0,false,true,9,false);skip.step(1.0/120.0)
 check(skip.cargo_position().x>28 and skip.telemetry.portal_crossing_tick==-1 and skip.telemetry.region=="departure","legal paid teleport across entry is not physical gate passage")
 var bypass=make();bypass.body_for_part(1).position=Vector2(200,0);bypass.release_launcher(0,0);bypass.step(1.0/120.0)
 check(bypass.status=="failed" and bypass.telemetry.delivery_failure=="required_portal_not_crossed","receiver explicitly refuses bypass without passage")
func enter(s)->void:
 s.body_for_part(1).position=Vector2(27.98,0);s.body_for_part(1).velocity=Vector2(12,0);s.release_launcher(0,0);s.step(1.0/120.0)
func biology()->void:
 var cold=make();enter(cold);cold.body_for_part(1).position=Vector2(145,0);cold.body_for_part(1).velocity=Vector2.ZERO
 # Isolate environmental exposure using a physically disabled pirate, not a new
 # HP variable. Field zero in this validated test route removes drift only.
 cold._rift_threats.before_tick(cold,0);cold.obstacles[0].health=0
 cold._rift_threats.field_definition.peak_force=0;cold._rift_threats.field_definition.peak_torque=0
 for i in range(300):cold.step(1.0/120.0)
 check(is_equal_approx(cold.ship_integrity(),1.0),"cold grace period leaves cargo HP intact")
 for i in range(120):cold.step(1.0/120.0)
 check(absf(cold.ship_integrity()-0.97)<0.0001 and absf(cold.telemetry.biological_damage-3.0)<0.0001,"one extra cold second damages existing cargo HP by actual rate")
 cold.body_for_part(1).position.y=16;cold.step(1.0/120.0)
 check(cold.telemetry.biological_exposure_seconds==0 and absf(cold.ship_integrity()-0.97)<0.0001,"warm exit resets continuous exposure but never heals cargo")
func fly(kind:String,cruise:float)->Dictionary:
 var s=make(craft(kind),true);s.release_launcher(0,1)
 var points:Array=[Vector2(29,0),Vector2(200,0)] if kind=="fast" else [Vector2(29,0),Vector2(118,16),Vector2(180,16),Vector2(200,0)]
 var index:int=0;var commands:Array=[];var active_field:bool=false;var warnings:bool=false
 for tick in range(60*90):
  if s.status!="running":break
  var at:Vector2=s.cargo_position();var b:Dictionary=s.body_for_part(1)
  if b.is_empty():break
  if index==0 and s.telemetry.region=="greenhouse":index=1
  elif at.distance_to(points[index])<5.0 and index<points.size()-1:index+=1
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
 var result:Dictionary={"kind":kind,"status":s.status,"time":s.elapsed,"energy_j":s.telemetry.energy_used,"remaining":s.telemetry.energy_remaining,"integrity":s.ship_integrity(),"failure":s.telemetry.delivery_failure,"cold_damage":s.telemetry.biological_damage,"field":active_field,"warnings":warnings,"shots":s.telemetry.rift_pirate.shots_fired,"crossing_tick":s.telemetry.portal_crossing_tick,"position":[s.cargo_position().x,s.cargo_position().y]}
 print("RIFT_BUILD_SAMPLE ",JSON.stringify(result))
 return {"sample":result,"sim":s,"commands":commands}
func flights()->void:
 var fast:Dictionary=fly("fast",12.0);var warm:Dictionary=fly("warm",9.0)
 check(fast.sample.status=="success" and fast.sample.integrity>=0.8 and fast.sample.warnings and fast.sample.shots>0,"initialstock compact fast craft completes real gate and active threats")
 check(warm.sample.status=="success" and warm.sample.integrity>=0.8 and warm.sample.warnings and warm.sample.shots>0,"initialstock armor warm bypass completes without a part key")
 check(fast.sample.time<warm.sample.time and fast.sample.cold_damage>warm.sample.cold_damage,"direct fast exposure and longer warm bypass produce visible tradeoff")
 var replay=make(craft("fast"),true);replay.release_launcher(0,1)
 for command in fast.commands:replay.set_free_flight_input(command[0],command[1],false,false,-1,false);replay.step(1.0/60.0)
 check(replay.parts==fast.sim.parts and replay.bodies==fast.sim.bodies and replay.obstacles==fast.sim.obstacles and replay.portal_crossings==fast.sim.portal_crossings and replay._rift_threats.snapshot()==fast.sim._rift_threats.snapshot(),"exact input replay reproduces portal threats field and biological HP")
