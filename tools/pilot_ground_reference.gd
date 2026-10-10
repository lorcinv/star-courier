extends SceneTree
## OFFLINE ONLY. Explicit pilot-v3 replay/guidance using immutable saved inputs.
## Never loaded by the native game. No saves or live controller calls.
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Ground = preload("res://scripts/pilot_ground_profile.gd")
const GroundTests = preload("res://tests/test_ground_route.gd")

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
 if str(route.get("control_version","")) != "pilot-v3":
  return {"error":"Only explicit pilot-v3 is supported; never fall back to v1"}
 if not snapshot.is_empty() and str(snapshot.get("control_version","")) != "pilot-v3":
  return {"error":"Snapshot physics identity must explicitly be pilot-v3"}
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
  if not Ground.is_ground_route(route):return {"error":"Ground guidance only accepts the saved ground-city-v1 route"}
  for tick in range(start_tick, int(spec.get("max_ticks",3600))):
   if s.status != "running":break
   if tick == start_tick or tick % 12 == 0:axis = GroundTests.binary_guidance(s)
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
 var exact: Dictionary = {"control_version":"pilot-v3","route":route,"design":source.design,"launcher":source.launcher,
  "seed":source.seed,"ticks":ticks,"elapsed":s.elapsed,"input_commands":timeline.snapshot()}
 return json_value({"mode":mode,"status":s.status,"elapsed":s.elapsed,"ticks":ticks,"position":s.cargo_position(),
  "energy_used":s.telemetry.energy_used,"remaining_energy":s.total_energy(),"integrity":s.ship_integrity(),
  "telemetry":s.telemetry,"events":s.events,"checkpoint":checkpoint,"commands":commands,"snapshot":exact})

func _initialize() -> void:
 var args = OS.get_cmdline_user_args()
 if "--self-test" in args:
  var passed = 0
  for weight in [1.0,1.55,4.34]:
   var result = compute({"route":Ground.route({"weight":weight}),"design":Ground.starter_design(),"launcher":Ground.starter_launcher(),"seed":100})
   var json_snapshot:Dictionary = JSON.parse_string(JSON.stringify(result.snapshot,"",true,true))
   var replay = compute({"snapshot":json_snapshot,"mode":"replay"})
   if result.status != "success" or replay.telemetry != result.telemetry or replay.position != result.position or replay.events != result.events:
    printerr("GROUND_REFERENCE_SELF_TEST_FAILED ",JSON.stringify({"weight":weight,"guide":result,"replay":replay}));quit(1);return
   var checkpoint:Dictionary=json_snapshot.duplicate(true)
   checkpoint.ticks=481;checkpoint.elapsed=481.0/60.0
   checkpoint.input_commands=checkpoint.input_commands.filter(func(c):return int(c.tick)<=481)
   var resumed=compute({"snapshot":checkpoint})
   if resumed.status!="success":printerr("GROUND_REFERENCE_RESUME_FAILED");quit(3);return
   passed += 1
  var invalid = compute({"route":{"control_version":"pilot-v2"},"design":[],"launcher":[],"seed":1})
  if not invalid.has("error"):quit(2);return
  print("GROUND_REFERENCE_SELF_TEST_PASS ",passed," exact JSON weight replays and checkpoint resumes; non-v3 rejected");quit();return
 var spec: Dictionary = {}
 for index in range(args.size()-1):
  if args[index] == "--spec":spec=JSON.parse_string(FileAccess.get_file_as_string(args[index+1]))
 var result = compute(spec)
 print("GROUND_REFERENCE_JSON:",JSON.stringify(result,"",true,true))
 quit(2 if result.has("error") else 0)
