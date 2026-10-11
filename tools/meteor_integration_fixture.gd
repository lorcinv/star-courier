extends SceneTree
## Explicit deterministic QA fixtures. No player's seed is changed or searched.
## World seed 59/day 2 is a documented selectable policy result with the same
## physical geometry as the prototype's seed 42. All motion begins at rest.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Guide=preload("res://tools/meteor_guidance_fixture.gd")
const Drill=preload("res://tools/drill_approach_probe.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
const Observer=preload("res://scripts/orbital_meteor_observer.gd")
var output="res://evidence/trajectories"
var controls=["evasion","neutral","drill","motor_off","shield_off","empty"]
var results=[]
var fails=[]
var pause_file="/tmp/courier-meteor-integration-pause"
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
  elif arg=="--empty-only":controls=["empty"]
 run.call_deferred()
func verify(v:bool,label:String):
 if not v:fails.append(label);push_error("FAIL "+label)
func clean():
 for name in ["savegame.json","savegame.tmp","savegame.backup.json"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
func run():
 DirAccess.make_dir_recursive_absolute(output)
 for control in controls:
  clean();var e=Econ.new();e.enable_extreme_mode();e.story_state=Stories.initial_state(59);e.enable_story_mode();e.enable_seeded_offers(59);e.reputation=2;e.phase="night";verify(e.next_day_and_save([],[],{}).ok,"fixture actual atomic next morning")
  verify(e.contracts[0].generation.version=="orbital-meteor-offers-v1","fixture is a real saved policy selection")
  var build=Profile.starter_design() if control in ["evasion","neutral","empty"] else drill_build(control)
  e.inventory={}
  for p in build+Profile.starter_launcher():e.inventory[p.type]=int(e.inventory.get(p.type,0))+1
  verify(e.accept_contract("D2-A").ok,"fixture acceptance");e.mark_cargo_loaded("D2-A")
  var trial=e.trial_route();var dispatch=e.begin_dispatch(build,Profile.starter_launcher())
  verify(dispatch.ok,"fixture formal dispatch")
  var s=Sim.new();s.configure(build,Profile.starter_launcher(),dispatch.snapshot.route,dispatch.snapshot.seed)
  if control=="empty":
   for p in s.parts.values():
    if p.type=="battery":p.energy=0.0
  var commands=Timeline.new();var observer=Observer.new();observer.configure(s.route,s)
  var axis=0;var first_hit={};var cleared={};var max_fragments=0;var warning_end=-1.0;var saw_warning=false;var checkpoints={};var ticks=0
  var checkpoint_ticks=[2010] if control in ["evasion","neutral"] else ([2568,2610,2646] if control=="drill" else [])
  for tick in range(4800):
   if tick%60==0:
    while FileAccess.file_exists(pause_file):OS.delay_msec(250)
   if tick%12==0:axis=axis_for(s,control)
   var command={"axis_q":axis,"boost":control in ["drill","motor_off","shield_off"] and tick<60,"active":control=="drill" and s.cargo_position().x>560.0 and s.obstacles[8].health>0.0}
   commands.record(tick,command);s.set_pilot_input(axis,command.boost,command.active);var contacts=s.telemetry.swept_contacts;s.step(1.0/60.0);ticks=tick+1
   var f=observer.update(s);max_fragments=maxi(max_fragments,f.fragments.size())
   if not f.cues.is_empty():saw_warning=true
   if saw_warning and f.cues.is_empty() and warning_end<0:warning_end=s.elapsed
   if s.telemetry.swept_contacts>contacts and first_hit.is_empty():first_hit=physics(s)
   if s.obstacles[8].health<=0 and cleared.is_empty():cleared=physics(s)
   if ticks in checkpoint_ticks:
    e.in_flight.ticks=ticks;e.in_flight.elapsed=s.elapsed;e.in_flight.input_commands=commands.snapshot()
    verify(e.save_state(build,Profile.starter_launcher(),{"pixel_density":"auto","volume":0.0}),"fixture checkpoint atomic save")
    var path=output+"/"+control+"-tick-"+str(ticks)+".json"
    var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(FileAccess.get_file_as_string("user://savegame.json"));file.close();checkpoints[str(ticks)]={"path":path,"physics":physics(s)}
   if s.status!="running":break
  var terminal=physics(s);var result={"control":control,"fixture_world_seed":59,"generation_seed":s.route.generation.seed,"initial_velocity_assigned":false,"from_rest":true,"first_hit":first_hit,"cleared":cleared,"final":terminal,"max_fragments":max_fragments,"warning_end":warning_end,"observer":observer.snapshot(),"checkpoints":checkpoints,"commands":commands.snapshot(),"ticks":ticks}
  if control=="evasion":verify(s.status=="success" and s.telemetry.integrity==1.0 and s.telemetry.swept_contacts==0 and s.total_energy()>1800,"integrated standard evasion delivers finite energy");verify(warning_end<s.route.orbital_event.events[0].warning_end_seconds,"passed whole-craft warning stops before stale fixed window")
  if control=="neutral":verify(s.telemetry.swept_contacts==2 and s.telemetry.energy_used>results[0].final.energy_used+500,"neutral control has two real impacts and cost")
  if control=="drill":verify(not cleared.is_empty() and s.parts[40].alive and s.telemetry.drill_damage>0 and s.telemetry.drill_energy_used>0 and s.telemetry.impact_shield_energy>0,"finite drill shield destruction");verify(first_hit.time<cleared.time and s.elapsed>60,"costly drill witness retains earlier gate hit and late arrival");verify(max_fragments==2 and observer.burst_count==1,"actual one-shot two-fragment destruction")
  if control=="motor_off":verify(s.telemetry.drill_damage==0 and s.telemetry.drill_energy_used==0 and not cleared.is_empty(),"motor-off eventually breaks via collision; no exclusive drill claim")
  if control=="shield_off":verify(s.telemetry.impact_shield_energy==0 and not s.parts[40].alive,"shield-off loses cutter")
  if control=="empty":verify(s.status=="failed" and s.total_energy()==0 and s.telemetry.energy_used==20.0 and s.telemetry.assist_energy_used==0.0,"empty craft fails with only the separate paid 20 J launcher; no free thrust")
  if control in ["evasion","drill"]:
   var replay=Sim.new();replay.configure(build,Profile.starter_launcher(),JSON.parse_string(JSON.stringify(trial,"",true,true)),dispatch.snapshot.seed)
   var timeline=Timeline.new();verify(timeline.restore(JSON.parse_string(JSON.stringify(commands.snapshot())),ticks),"saved timeline accepted")
   for tick in range(ticks):
    if tick%60==0:
     while FileAccess.file_exists(pause_file):OS.delay_msec(250)
    var c=timeline.state_at(tick);replay.set_pilot_input(c.axis_q,c.boost,c.active);replay.step(1.0/60.0)
   verify(exact(physics(replay),terminal),"trial JSON and formal replay exact "+control)
   var restored=Observer.new();restored.configure(replay.route,replay);verify(restored.update(replay).fragments.is_empty(),"restored destroyed state never emits historical fragments")
  verify(e.settle_contract_and_save("D2-A",s.telemetry,s.elapsed,s.status=="success",build,Profile.starter_launcher(),{}).ok,"actual physics receipt settles")
  e.close_day();verify(e.next_day_and_save(build,Profile.starter_launcher(),{}).ok,"physics next-day review publication")
  result.review=e.customer_reviews();results.append(result)
  print("INTEGRATED_TRAJECTORY ",JSON.stringify({"control":control,"final":terminal,"cleared":cleared,"warning_end":warning_end,"max_fragments":max_fragments}))
 var file=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"runs":results,"failures":fails,"human_fairness":false,"fixtures_only":true},"  ",true,true));file.close();clean();print("INTEGRATED_TRAJECTORY_RESULT failures=",fails.size());quit(1 if not fails.is_empty() else 0)
static func drill_build(control:String) -> Array:
 var build=Drill.design(control!="motor_off",control!="shield_off")
 for p in build:
  if p.id==40:p.input_a=-1 if control=="shield_off" else -2
  if p.type=="shield" and control=="shield_off":p.input_a=-2
 return build
static func axis_for(s,control:String) -> int:
 var axis=Guide.guidance(s)
 if control in ["evasion","neutral","empty"]:
  if s.cargo_position().x>500:
   axis=0;var event=s.route.orbital_event.events[0]
   if control=="evasion" and s.elapsed>=float(event.center_crossing_seconds)-2.6 and s.elapsed<float(event.center_crossing_seconds)-.4:axis=-1000
   if s.cargo_position().x>float(event.initial_position[0])+15:axis=Guide.guidance(s)
  return axis
 var offset=0.0
 if s.cargo_position().x>480 and s.cargo_position().x<610 and s.obstacles[8].health>0:
  var h=s.obstacles[8];var velocity:Vector2=s._cargo_body().get("velocity",Vector2.ZERO);var t=maxf(0,(h.position.x-s.cargo_position().x-2)/maxf(1,velocity.x));offset=h.position.y+h.velocity.y*t+150
 axis=Guide.guidance(s,offset)
 if s.cargo_position().x>477 and s.cargo_position().x<605 and s.obstacles[8].health>0:
  var h=s.obstacles[8];var head=s.part_world_position(40)+Vector2.RIGHT.rotated(s.body_for_part(40).get("angle",0.0))*.3
  axis=roundi(clampf(h.velocity.y+(h.position.y-head.y)*1.25,-5,5)/5*1000)
 return axis
static func physics(s) -> Dictionary:
 var modules=[]
 for p in s.parts.values():modules.append({"id":p.id,"hp":p.hp,"energy":p.energy,"alive":p.alive,"position":str(s.part_world_position(p.id))})
 return {"time":s.elapsed,"status":s.status,"x":s.cargo_position().x,"y":s.cargo_position().y,"integrity":s.telemetry.integrity,"energy":s.total_energy(),"energy_used":s.telemetry.energy_used,"contacts":s.telemetry.swept_contacts,"rock_hp":s.obstacles[8].health,"drill_damage":s.telemetry.drill_damage,"drill_energy":s.telemetry.drill_energy_used,"shield_energy":s.telemetry.impact_shield_energy,"velocity":str(s._cargo_body().get("velocity",Vector2.ZERO)),"modules":modules}
static func exact(a,b):return JSON.stringify(JSON.parse_string(JSON.stringify(a,"",true,true)),"",true,true)==JSON.stringify(JSON.parse_string(JSON.stringify(b,"",true,true)),"",true,true)
