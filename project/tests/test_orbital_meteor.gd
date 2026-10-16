extends SceneTree
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Catalog=preload("res://scripts/orbital_meteor_catalog.gd")
const Observer=preload("res://scripts/orbital_meteor_observer.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
const Guide=preload("res://tools/calibrate.gd")
const Probe=preload("res://tools/probe_meteor.gd")
const Drill=preload("res://tools/drill_approach_probe.gd")
const Open=preload("res://tools/extreme_build_probe.gd")
var checks=0
var failures:Array=[]
var evidence:Dictionary={"native_visual_acceptance":"not run; GPU slot required","human_fairness":"not established by input witnesses","runs":[],"contact_fixtures":[]}
var sprite:Dictionary={}
var output=""
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 sprite=JSON.parse_string(FileAccess.get_file_as_string("res://assets/2d_v5/events/meteor/manifest.json")).assets[0]
 if "--probe-only" in OS.get_cmdline_user_args():
  var bytes=""
  for seed_value in [0,1,42,1337,2147483646]:bytes+=JSON.stringify(Catalog.author(base(1),seed_value).route)
  print("METEOR_DIGEST ",bytes.sha256_text());quit(0);return
 static_checks()
 if not "--static-only" in OS.get_cmdline_user_args():
  flight_checks();contact_checks()
 evidence.assertions=checks;evidence.failures=failures
 if not output.is_empty():var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "))
 for failure in failures:printerr("FAIL ",failure)
 print("METEOR_RESULT ",JSON.stringify({"assertions":checks,"failed":failures.size()}))
 quit(0 if failures.is_empty() else 1)
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message)
func pause():
 if FileAccess.file_exists("/tmp/courier-meteor-pause"):print("PAUSED_FOR_NATIVE_PRIORITY")
 while FileAccess.file_exists("/tmp/courier-meteor-pause"):OS.delay_msec(250)
static func base(id:int)->Dictionary:return {"id":id,"weight":1.5 if id==1 else 2.0,"reward":220 if id==1 else 280,"rep":2 if id==1 else 4}
func static_checks():
 var variants={};var before=base(1);var before_bytes=JSON.stringify(before)
 for seed_value in range(512):
  for id in [1,2]:
   var a=Catalog.author(base(id),seed_value)
   check(a.ok,"valid explicit seed "+str(seed_value))
   if not a.ok:continue
   var r:Dictionary=a.route;var e:Dictionary=r.orbital_event.events[0]
   variants[str(e.initial_position)+str(e.velocity)]=true
   check(r.is_read_only() and r.hazards.is_read_only() and r.hazards[8].is_read_only() and e.is_read_only(),"recursive immutable candidate")
   check(Catalog.route_error(r).is_empty() and Catalog.restore(JSON.parse_string(JSON.stringify(r))).ok,"stored JSON realization restores without generation")
   check(r.hazards.size()==9 and r.pilot_gates.size()==4 and e.max_fragments==2,"fixed event/obstacle/FX budget")
   check(e.initial_position[0]-e.radius>470.0 and e.initial_position[0]+e.radius<680.0,"launch, ascent gate and receiver clearance")
   check(absf(float(e.initial_position[1])+float(e.velocity[1])*float(e.center_crossing_seconds)+150.0)<0.0000001,"metadata center crossing matches actual constant motion")
   check(float(e.center_crossing_seconds)-float(e.warning_start_seconds)-(3.3/18.0)>3.0,"warning precedes nominal conservative contact envelope, not merely center crossing")
 check(variants.size()>=12,"multiple bounded lateral lanes, directions and schedules")
 var a=Catalog.author(before,42);check(JSON.stringify(before)==before_bytes,"authoring does not mutate caller catalog")
 var saved=a.route.duplicate(true);saved.contract_id="already-accepted"
 check(not Catalog.author(saved,42).ok,"never append to materialized or accepted snapshot")
 var seeded=base(1);seeded.generation={"version":"seeded-offers-v1","seed":42}
 check(not Catalog.author(seeded,42).ok,"frozen seeded-offers-v1 cannot be reinterpreted")
 for invalid in [null,-1,2147483647,0.5,INF,NAN,"42",{},[]]:check(not Catalog.author(base(1),invalid).ok,"invalid explicit seed safely rejected")
 for valid in [0,2147483646]:check(Catalog.author(base(1),valid).ok,"bounded explicit seed endpoints")
 seed(9137);var expected=randi();seed(9137);Catalog.author(base(1),999)
 check(randi()==expected,"authoring never consumes global RNG")
 for path in ["seed","version","velocity","health","geometry","budget","gate","battery","vectors"]:
  var changed=a.route.duplicate(true)
  match path:
   "seed":changed.orbital_event.seed=-1
   "version":changed.orbital_event.version="future-unknown"
   "velocity":changed.hazards[8].velocity=[0.0,100000.0]
   "health":changed.hazards[8].health=INF
   "geometry":changed.orbital_event.events[0].initial_position[0]=0.0
   "budget":changed.orbital_event.events[0].max_fragments=500
   "gate":changed.hazards[0].x=0.0
   "battery":changed.pilot_battery_multiplier=1000.0
   "vectors":changed.orbital_event.events[0].velocity=["0",3.0]
  check(not Catalog.restore(changed).ok,"reject corrupted/foreign saved "+path)
 check(Catalog.author(base(1),42).route==a.route,"same explicit request identical after other seeds")
 var reset=new_sim(a.route);var original=snapshot(reset)
 reset.configure(Profile.starter_design(),Profile.starter_launcher(),a.route,42)
 check(reset.obstacles.size()==9 and snapshot(reset)==original,"reconfigure restarts exact realized hazards without duplicate spawning")
 evidence.authored_seed_count=1024;evidence.distinct_realizations=variants.size()
func new_sim(r:Dictionary,design:Array=[],empty:bool=false):
 var s=Sim.new();s.configure(Profile.starter_design() if design.is_empty() else design,Profile.starter_launcher(),r,int(r.orbital_event.seed))
 if empty:
  for p in s.parts.values():
   if p.type=="battery":p.energy=0.0
 return s
func run_flight(id:int,seed_value:int,evade:bool,empty:bool=false)->Dictionary:
 var r:Dictionary=Catalog.author(base(id),seed_value).route
 var s=new_sim(r,[],empty);var e:Dictionary=r.orbital_event.events[0]
 var timeline=Timeline.new();var observer=Observer.new();observer.configure(r,s)
 var axis=0;var first_hit={};var first_visual=-1.0;var first_envelope=-1.0;var checkpoint={};var maxfx=0;var completed_ticks=0
 for tick in range(4800):
  if tick%60==0:pause()
  if tick%12==0:axis=Guide.guidance(s)
  if s.cargo_position().x>500.0:
   axis=0
   if evade and s.elapsed>=e.center_crossing_seconds-2.6 and s.elapsed<e.center_crossing_seconds-0.4:axis=-1000
   if s.cargo_position().x>e.initial_position[0]+15.0:axis=Guide.guidance(s)
  var h:Dictionary=s.obstacles[8]
  if first_visual<0.0 and Probe.silhouette_visible(s.cargo_position(),h.position,sprite):first_visual=s.elapsed
  if first_envelope<0.0 and s.cargo_position().distance_to(h.position)<=3.3:first_envelope=s.elapsed
  timeline.record(tick,{"axis_q":axis,"boost":false,"active":false})
  var previous=int(s.telemetry.swept_contacts)
  s.set_pilot_input(axis,false,false);s.step(1.0/60.0)
  completed_ticks=tick+1
  var obs=observer.update(s);maxfx=maxi(maxfx,obs.fragments.size());maxfx=maxi(maxfx,s.effects.size())
  if int(s.telemetry.swept_contacts)>previous and first_hit.is_empty():first_hit={"time":s.elapsed,"x":s.cargo_position().x,"y":s.cargo_position().y}
  if tick==2160:checkpoint={"route":r.duplicate(true),"seed":seed_value,"ticks":tick+1,"input_commands":timeline.snapshot(),"observer":observer.snapshot(),"physical":snapshot(s)}
  if s.status!="running":break
 var result={"id":id,"seed":seed_value,"evade":evade,"empty":empty,"status":s.status,"time":s.elapsed,"integrity":s.telemetry.integrity,"remaining_energy":s.total_energy(),"energy_used":s.telemetry.energy_used,"contacts":s.telemetry.swept_contacts,"meteor_health":s.obstacles[8].health,"first_hit":first_hit,"first_visible_occupied_pixel":first_visual,"first_conservative_envelope":first_envelope,"warning_start":e.warning_start_seconds,"center_crossing":e.center_crossing_seconds,"max_effects":maxfx,"observer":observer.snapshot(),"physical":snapshot(s),"commands":timeline.snapshot(),"checkpoint":checkpoint,"ticks":completed_ticks}
 return result
func flight_checks():
 var reference:Dictionary={};var hit_reference:Dictionary={}
 for id in [1,2]:
  for seed_value in [0,1,42,1337]:
   var r=run_flight(id,seed_value,true)
   check(r.status=="success" and r.integrity==1.0 and r.contacts==0,"funded starter evades and delivers: "+str([id,seed_value]))
   check(r.remaining_energy>1800.0 and r.meteor_health==80.0,"evasion uses finite motors and does not invent meteor damage")
   check(r.max_effects<=192 and r.observer.burst_count==0,"bounded FX with no invented destruction")
   evidence.runs.append(summary(r));print("FLIGHT ",JSON.stringify(summary(r)))
   if id==1 and seed_value==42:reference=r
  var hit=run_flight(id,42,false)
  check(hit.contacts>0 and hit.meteor_health<80.0,"neutral trajectory produces real avoidable impact")
  check(hit.first_conservative_envelope<hit.first_hit.time and hit.first_hit.time<hit.center_crossing,"envelope then physical first contact precede meteor-center crossing")
  check(hit.first_hit.time-hit.first_visible_occupied_pixel>=2.5,"actual alpha silhouette visible at least2.5s before first hit")
  check(hit.first_conservative_envelope-hit.warning_start>=3.0,"cue precedes whole-craft possible contact by3s")
  check(hit.energy_used>reference.energy_used+500.0,"impact carries serious engine recovery/repair consequences")
  evidence.runs.append(summary(hit));print("HIT ",JSON.stringify(summary(hit)))
  if id==1:hit_reference=hit
 var depleted=run_flight(1,42,true,true)
 check(depleted.status=="failed" and depleted.remaining_energy==0.0 and depleted.contacts==0,"fully depleted flight remains a failure; no event lift or forced progress")
 evidence.runs.append(summary(depleted))
 # Repeated exact commands, fully serialized input and route, and replay to a
 # saved completed-tick checkpoint all use the production simulator verbatim.
 var route:Dictionary=Catalog.author(base(1),42).route
 var repeated=replay(route,reference.commands,int(reference.ticks))
 check(snapshot(repeated)==reference.physical,"exact repeated inputs produce identical state")
 var json_save:Dictionary=JSON.parse_string(JSON.stringify({"route":route,"commands":reference.commands,"ticks":reference.ticks,"seed":42}))
 var json_run=replay(Catalog.restore(json_save.route).route,json_save.commands,int(json_save.ticks))
 check(snapshot(json_run)==reference.physical,"JSON route/seed/input replay is exact")
 var saved:Dictionary=JSON.parse_string(JSON.stringify(reference.checkpoint))
 var resumed=replay(Catalog.restore(saved.route).route,saved.input_commands,int(saved.ticks))
 check(snapshot(resumed)==reference.checkpoint.physical,"checkpoint reconstruction matches original exact physical proof from persisted route and inputs")
 var observer=Observer.new();observer.configure(saved.route,resumed,saved.observer)
 var timeline=Timeline.new();check(timeline.restore(reference.commands,int(reference.ticks)),"continued input timeline accepted")
 for tick in range(int(saved.ticks),int(reference.ticks)):
  if tick%60==0:pause()
  var state=timeline.state_at(tick);resumed.set_pilot_input(state.axis_q,state.boost,state.active);resumed.step(1.0/60.0);observer.update(resumed)
 check(snapshot(resumed)==reference.physical,"checkpoint resume reaches exactly same terminal physical state")
 check(observer.snapshot()==reference.observer,"warning observer resumes without duplicate trigger")
 evidence.replay={"repeat_exact":snapshot(repeated)==reference.physical,"json_exact":snapshot(json_run)==reference.physical,"checkpoint_exact":snapshot(resumed)==reference.physical}
func replay(route:Dictionary,commands:Array,ticks:int):
 var s=new_sim(route);var timeline=Timeline.new();check(timeline.restore(commands,ticks),"bounded persisted timeline")
 for tick in range(ticks):
  if tick%60==0:pause()
  var state=timeline.state_at(tick);s.set_pilot_input(state.axis_q,state.boost,state.active);s.step(1.0/60.0)
 return s
static func snapshot(s)->Dictionary:
 var modules=[];var bodies=[];var hazards=[]
 for p in s.parts.values():modules.append({"id":p.id,"alive":p.alive,"hp":p.hp,"energy":p.energy,"delivered":p.delivered,"position":[s.part_world_position(p.id).x,s.part_world_position(p.id).y]})
 for b in s.bodies:bodies.append({"id":b.id,"position":[b.position.x,b.position.y],"velocity":[b.velocity.x,b.velocity.y],"angle":b.angle,"angular_velocity":b.angular_velocity})
 for h in s.obstacles:hazards.append({"health":h.health,"position":[h.position.x,h.position.y],"velocity":[h.velocity.x,h.velocity.y]})
 return {"time":s.elapsed,"status":s.status,"tick":s.pilot_tick,"modules":modules,"bodies":bodies,"hazards":hazards,"telemetry":s.telemetry.duplicate(true),"incidents":s.incidents.duplicate(true)}
static func summary(r:Dictionary)->Dictionary:
 var out=r.duplicate(true)
 for key in ["physical","commands","checkpoint"]:out.erase(key)
 return out
func contact_checks():
 for control in ["on","motor_off","shield_off","empty"]:
  var r=moving_contact(control)
  evidence.contact_fixtures.append(r)
  if control=="on":
   check(r.rock_hp<=0.0 and r.drill_alive and r.drill_hp<40.0,"moving meteor can be broken by funded drill/shields at serious real durability cost")
   check(r.drill_damage>0.0 and r.shield_energy>0.0 and r.drill_energy>0.0,"actual motor and shield energy are paid")
   check(absf(r.shield_energy-r.absorbed*1.5)<0.00001,"shield HP/J accounting is exact")
   check(r.observer_bursts==1 and r.max_fragments==2 and r.restore_bursts==1 and r.restored_fragments==0,"one actual destruction, bounded fragments, no repeated restart burst")
  if control=="motor_off":check(r.drill_damage==0.0 and r.drill_energy==0.0,"disabled motor cannot cut moving meteor")
  if control=="shield_off":check(r.shield_energy==0.0 and not r.drill_alive,"disabled shields cannot save high-speed cutter")
  if control=="empty":check(r.energy_used==0.0 and r.drill_damage==0.0 and r.shield_energy==0.0 and not r.drill_alive,"empty circuit cannot run drill or shields")
  check(r.hull_contacts>0 and r.ccd_holds==0,"moving impact is real and chronological")
 # Extreme relative motion is an explicit contact-geometry fixture, not a
 # playable delivery: a moving rock traverses the whole craft in one tick.
 var s=Sim.new();var route=Open.open_route();route.hazards=[{"x":600.0,"y":0.0,"radius":0.8,"health":80.0,"mass":20.0,"type":"rock","velocity":[-2400.0,0.0],"destructible":true}]
 s.configure(Profile.starter_design(),[],route,42)
 check(s.status=="running","fast moving fixture starts beyond real0.22s spawn-safety window")
 for tick in range(31):s.set_pilot_input(0,false,false);s.step(1.0/120.0)
 check(s.telemetry.swept_contacts>0,"2400m/s moving hazard does not tunnel through stationary craft")
 check(s.telemetry.ccd_budget_holds==0 and s.telemetry.energy_used<20.0,"high-relative-speed contact needs no velocity cap or free energy")
 evidence.fast_relative_contact={"relative_speed":2400.0,"contacts":s.telemetry.swept_contacts,"holds":s.telemetry.ccd_budget_holds,"status":s.status}
func moving_contact(control:String)->Dictionary:
 pause()
 var s=Sim.new();var route=Open.open_route();var x=2.6
 # Test-only disclosed initial speed, aligned to cutter nose. No later writes
 # to position/velocity/HP/energy; real v3 motor/contact logic does all work.
 s.configure(Drill.design(control!="motor_off",control!="shield_off"),[],route,42)
 s.bodies[0].velocity=Vector2(18.0,0.0)
 if control=="empty":
  for p in s.parts.values():
   if p.type=="battery":p.energy=0.0
 var at=s.part_world_position(40)+Vector2(2.23,-0.15)
 s.obstacles.append({"position":at,"velocity":Vector2(0.0,3.0),"radius":0.8,"health":80.0,"mass":20.0,"type":"rock","destructible":true,"pilot_gate":false})
 var observe_route={"orbital_event":{"events":[{"id":"moving-fixture","hazard_index":0,"warning_start_seconds":0.0,"warning_end_seconds":10.0,"center_crossing_seconds":0.05,"radius":0.8,"fragment_lifetime_seconds":0.65}]}}
 var observer=Observer.new();observer.configure(observe_route,s);var max_fragments=0;var restorable={};var restored_fragments=-1
 for tick in range(120):
  s.set_pilot_input(0,false,false);s.step(1.0/120.0)
  var frame=observer.update(s);max_fragments=maxi(max_fragments,frame.fragments.size())
  if s.obstacles[0].health<=0.0 and restorable.is_empty():
   restorable=observer.snapshot();var restored=Observer.new();restored.configure(observe_route,s,JSON.parse_string(JSON.stringify(restorable)));restored_fragments=restored.update(s).fragments.size()
   check(restored.snapshot()==restorable,"restored observer preserves exact one-shot ledger")
  observer.update(s) # repeated render frame cannot emit a second burst
 return {"control":control,"fixture_only_initial_speed":18.0,"meteor_velocity":[0.0,3.0],"rock_hp":s.obstacles[0].health,"drill_alive":s.parts[40].alive,"drill_hp":s.parts[40].hp,"cargo_hp":s.parts[1].hp,"energy_used":s.telemetry.energy_used,"drill_energy":s.telemetry.drill_energy_used,"drill_damage":s.telemetry.drill_damage,"shield_energy":s.telemetry.impact_shield_energy,"absorbed":s.telemetry.impact_absorbed,"hull_contacts":s.telemetry.swept_contacts,"ccd_holds":s.telemetry.ccd_budget_holds,"observer_bursts":observer.burst_count,"max_fragments":max_fragments,"restore_bursts":restorable.get("burst_count",0),"restored_fragments":restored_fragments,"remaining_fragments":observer.update(s).fragments.size()}
