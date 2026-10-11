extends SceneTree
## OFFLINE ONLY. Explicit pilot-v4-wormhole replay/guidance using immutable saved inputs.
## Never loaded by the native game. No saves or live controller calls.
const Sim = preload("res://scripts/pilot_wormhole_simulation.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Wormhole = preload("res://scripts/pilot_wormhole_profile.gd")
const Guide = preload("res://tools/pilot_wormhole_guidance.gd")

func json_value(value: Variant) -> Variant:
 if value is Vector2: return [value.x,value.y]
 if value is Dictionary:
  var out: Dictionary = {}
  for key in value: out[str(key)] = json_value(value[key])
  return out
 if value is Array:
  var out: Array = []
  for item in value: out.append(json_value(item))
  return out
 return value

func compute(spec: Dictionary) -> Dictionary:
 var snapshot: Dictionary = spec.get("snapshot", {})
 var source: Dictionary = snapshot if not snapshot.is_empty() else spec
 for key in ["route","design","launcher","seed"]:
  if not source.has(key): return {"error":"Explicit recorded " + key + " required"}
 var route: Dictionary = source.route
 if str(route.get("control_version","")) != "pilot-v4-wormhole":
  return {"error":"Only explicit pilot-v4-wormhole is supported; never fall back to v1"}
 if not snapshot.is_empty() and str(snapshot.get("control_version","")) != "pilot-v4-wormhole":
  return {"error":"Snapshot physics identity must explicitly be pilot-v4-wormhole"}
 var s = Sim.new()
 s.configure(source.design, source.launcher, route, int(source.seed))
 var timeline = Timeline.new()
 var start_tick: int = int(snapshot.get("ticks",0))
 if not snapshot.is_empty():
  if not timeline.restore(snapshot.get("input_commands",[]),start_tick):return {"error":timeline.error}
  for tick in range(start_tick):
   var command: Dictionary = timeline.state_at(tick)
   s.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active))
   s.step(1.0/60.0)
 var checkpoint: Dictionary = {"ticks":start_tick,"elapsed":s.elapsed,"energy_used":s.telemetry.energy_used,
  "position":s.cargo_position(),"events":s.events.duplicate(true),"status":s.status}
 var commands: Array = []
 var axis: int = 0
 var last: Dictionary = {}
 var ticks: int = start_tick
 var mode: String = str(spec.get("mode","guide"))
 if mode != "replay" and mode != "guide":return {"error":"mode must be guide or replay"}
 if mode == "guide":
  for tick in range(start_tick, int(spec.get("max_ticks",3600))):
   if s.status != "running":break
   if tick == start_tick or tick % 12 == 0:axis = Guide.guidance(s)
   var command: Dictionary = {"axis_q":axis,
    "boost":tick >= int(spec.get("boost_start_tick",0)) and tick < int(spec.get("boost_end_tick",0)),
    "active":false}
   if command != last:
    commands.append({"tick":tick,"time":tick/60.0,"axis_q":axis,"boost":command.boost,"active":command.active,"position":s.cargo_position()})
    last=command.duplicate(true)
   timeline.record(tick,command)
   s.set_pilot_input(axis,bool(command.boost),bool(command.active));s.step(1.0/60.0)
   ticks=tick+1
 s.finalize_settlement()
 var exact: Dictionary = {"control_version":"pilot-v4-wormhole","route":route,"design":source.design,"launcher":source.launcher,
  "seed":source.seed,"ticks":ticks,"elapsed":s.elapsed,"input_commands":timeline.snapshot()}
 return json_value({"mode":mode,"status":s.status,"elapsed":s.elapsed,"ticks":ticks,"position":s.cargo_position(),
  "energy_used":s.telemetry.energy_used,"remaining_energy":s.total_energy(),"integrity":s.ship_integrity(),
  "telemetry":s.telemetry,"events":s.events,"wormhole_events":s.wormhole_events,"checkpoint":checkpoint,"commands":commands,"snapshot":exact})

func _initialize() -> void:
 var args = OS.get_cmdline_user_args()
 var spec: Dictionary = {}
 for index in range(args.size()-1):
  if args[index] == "--spec":spec=JSON.parse_string(FileAccess.get_file_as_string(args[index+1]))
 var result = compute(spec)
 print("WORMHOLE_REFERENCE_JSON:",JSON.stringify(result,"",true,true))
 quit(2 if result.has("error") else 0)
