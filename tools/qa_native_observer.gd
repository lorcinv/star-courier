extends "res://tools/qa_audio_game.gd"
## QA-only wrapper. The inherited entry instantiates the unchanged production
## scene and real Master tap. This observer only reads gameplay state. It never
## calls controller actions, supplies input, or writes gameplay/physics fields.
## At most 8,000 samples, 20 Hz wall-clock maximum, one disk write on exit.
class ReadOnlyObserver extends Node:
 var game
 var samples:Array=[]
 var last_usec:int=-100000
 var previous_page:String=""
 var output:String=""
 var sample_limit:int=8000
 var capped:bool=false
 func _ready() -> void:
  process_mode=Node.PROCESS_MODE_ALWAYS
  process_priority=100
  output=OS.get_environment("SC_QA_TELEMETRY_OUTPUT")
  print("QA_READ_ONLY_OBSERVER_READY ",JSON.stringify({"max_hz":20,"max_samples":sample_limit,"output":output,"mutates_gameplay":false}))
 func _process(_delta:float) -> void:
  if not is_instance_valid(game):
   for node in get_tree().root.get_children():
    if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":game=node;break
  if not is_instance_valid(game):return
  var now:int=Time.get_ticks_usec()
  if now-last_usec<50000 and previous_page==game.page:return
  last_usec=now;previous_page=game.page
  if samples.size()>=sample_limit:capped=true;return
  var ledger:Dictionary={}
  for key in ["credits","day","phase","deliveries","jobs_today","research","inventory","active_contract_id","settled_ids","history","in_flight"]:
   var value=game.economy.get(key)
   ledger[key]=value.duplicate(true) if value is Dictionary or value is Array else value
  var item:Dictionary={"engine_monotonic_usec":now,"unix_seconds":Time.get_unix_time_from_system(),
   "page":game.page,"trial":game.trial,"paused":game.paused,"simulation_rate":game.speed,
   "launch_countdown":game.launch_countdown,"launch_age":game.launch_age,"launch_transfer_remaining":game.launch_transfer_remaining,
   "parcel_phase":game.world._parcel_phase,"parcel_state":game.world.parcel_state,
   "completed_ticks":game.pilot_completed_ticks,
   "controller_keys":game.pilot_keys.duplicate(true),"timeline":game.pilot_timeline.snapshot(),"ledger":ledger}
  if game.sim!=null:
   var sim=game.sim
   item.elapsed=sim.elapsed;item.status=sim.status;item.telemetry=sim.telemetry.duplicate(true)
   item.events=sim.events.duplicate(true);item.incidents=sim.incidents.duplicate(true)
   item.bodies=[];item.parts=[];item.obstacles=[]
   for body in sim.bodies:
    item.bodies.append({"id":body.get("id",-1),"position":[body.position.x,body.position.y],
     "velocity":[body.velocity.x,body.velocity.y],"angle":body.angle,"angular_velocity":body.angular_velocity,
     "mass":body.mass,"part_ids":body.parts.map(func(p):return p.id)})
   for p in sim.parts.values():
    item.parts.append({"id":p.id,"type":p.type,"hp":p.hp,"max_hp":p.max_hp,
     "alive":p.alive,"energy":p.get("energy",0),"capacity":p.get("capacity",0),"drill_power_ratio":p.get("drill_power_ratio",0),
     "input_a":p.get("input_a",-1)})
   for obstacle in sim.obstacles:
    item.obstacles.append({"position":[obstacle.position.x,obstacle.position.y],"hp":obstacle.get("health",-1),
     "alive":float(obstacle.get("health",0))>0,"radius":obstacle.get("radius",0),"type":obstacle.get("type","")})
  samples.append(item)
 func _exit_tree() -> void:
  if output.is_empty():return
  var file=FileAccess.open(output,FileAccess.WRITE)
  if file==null:push_error("QA observer could not write output");return
  file.store_string(JSON.stringify({"method":"Read-only sampling of actual native production main process",
   "max_hz":20,"max_samples":sample_limit,"capped":capped,"samples":samples},"",true,true));file.close()
  print("QA_READ_ONLY_OBSERVER_SAVED ",JSON.stringify({"output":output,"samples":samples.size(),"capped":capped}))
func _initialize() -> void:
 super._initialize()
 var observer=ReadOnlyObserver.new();observer.name="QAReadOnlyObserver"
 root.add_child.call_deferred(observer)
