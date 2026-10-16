extends "res://tests/test_lunar_outpost_v2.gd"
## Actual unchanged solver/quantized-input journey, sampled by the read-only
## observer. No health, body, energy, clock or route edits create the break.
const Feedback=preload("res://scripts/lunar_ore_feedback_v2.gd")
const Presenter=preload("res://scripts/lunar_outpost_presentation_2d.gd")

func _initialize() -> void:run_feedback.call_deferred()

func sim_bytes(sim) -> PackedByteArray:
 return var_to_bytes([sim.parts,sim.bodies,sim.obstacles,sim.route,sim.telemetry,sim.events,sim.effects,sim.elapsed])

func run_feedback() -> void:
 var sim=_sim("drill");var observer=Feedback.new();observer.configure(sim.route)
 var timeline=Timeline.new();var ticks:int=0;var flashes:int=0;var broke:bool=false
 var read_only:bool=true;var previous_health:float=float(sim.obstacles[0].health)
 observer.observe(sim.get_instance_id(),sim.elapsed,sim.obstacles)
 for tick in 7200:
  if sim.status!="running" or not bool(sim.parts[9].alive):break
  var h:Dictionary=sim.obstacles[0]
  var head:Vector2=sim.part_world_position(9)+Vector2.RIGHT.rotated(float(sim.body_for_part(9).angle)+float(sim.parts[9].local_angle))*Expanded.DRILL_HEAD_OFFSET
  var gap:float=h.position.x-float(h.radius)-Expanded.DRILL_HEAD_RADIUS-head.x
  var speed:float=clampf(sqrt(maxf(0.0,gap)*1.5),.35,8.0)
  var command:Dictionary=_command(sim,h.position,speed)
  timeline.record(tick,command);_step(sim,command);ticks+=1
  var before:PackedByteArray=sim_bytes(sim)
  observer.observe(sim.get_instance_id(),sim.elapsed,sim.obstacles)
  read_only=read_only and sim_bytes(sim)==before
  var frame:Array=observer.frame()
  if not frame.is_empty() and frame[0].hit_strength>0.0:flashes+=1
  if previous_health>0.0 and float(sim.obstacles[0].health)<=0.0:
   broke=not frame.is_empty() and frame[0].id==Feedback.ORE_IDS[0] and frame[0].burst_alpha==1.0
   break
  previous_health=float(sim.obstacles[0].health)
 check(broke,"real paid solver contact crossing ore HP zero earns a break on the actual advancing tick")
 check(flashes>0,"real preceding nonlethal damage produces a warm flash")
 check(read_only,"per-tick feedback leaves every actual simulation field byte-identical")
 check(bool(sim.parts[9].alive) and float(sim.obstacles[0].health)<=0.0 and float(sim.telemetry.drill_energy_used)>0.0,"actual drill survives and spends energy while real ore breaks")
 print("ORE_FEEDBACK_REAL_BREAK ",JSON.stringify({"elapsed":sim.elapsed,"ticks":ticks,"ore_health":sim.obstacles[0].health,"drill_alive":sim.parts[9].alive,"drill_energy_used":sim.telemetry.drill_energy_used,"feedback":observer.debug_snapshot()}))
 var cue:PackedByteArray=var_to_bytes(observer.frame());var before:PackedByteArray=sim_bytes(sim)
 for draw in 120:observer.observe(sim.get_instance_id(),sim.elapsed,sim.obstacles)
 check(broke and var_to_bytes(observer.frame())==cue and sim_bytes(sim)==before,"real last-step break remains exact through repeated paused draws")
 var saved:Dictionary=JSON.parse_string(JSON.stringify({"route":sim.route,"commands":timeline.snapshot(),"ticks":ticks}))
 var replay=Free.new();replay.configure(_design("drill"),[],saved.route,42)
 var restored=Timeline.new();check(restored.restore(saved.commands,int(saved.ticks)),"real break checkpoint restores the unchanged input schema")
 for tick in int(saved.ticks):_step(replay,restored.state_at(tick))
 check(replay.cargo_position()==sim.cargo_position() and replay.obstacles==sim.obstacles and replay.telemetry.energy_used==sim.telemetry.energy_used,"actual checkpoint replay reconstructs ore HP, trajectory and paid energy exactly")
 observer.observe(replay.get_instance_id(),replay.elapsed,replay.obstacles)
 check(observer.frame().is_empty(),"replacement with an actually replayed simulation primes without phantom break")
 var host:Node2D=Node2D.new();root.add_child(host)
 var world:Node2D=Node2D.new();host.add_child(world)
 var presenter=Presenter.new();host.add_child(presenter)
 presenter.configure_route(replay.route,world,Vector2.ZERO,72.0)
 before=sim_bytes(replay);presenter.update_from_sim(replay,.52,replay.cargo_position())
 check(presenter._ore_feedback.frame().is_empty() and not presenter._rocks[0].visible,"Continue-style first render of the actual replay hides dead ore without replaying effects")
 check(sim_bytes(replay)==before,"Continue-style presentation preserves reconstructed simulation bytes")
 host.free()
 print("LUNAR_ORE_PHYSICS_DEV05 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)
