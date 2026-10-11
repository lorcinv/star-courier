extends SceneTree
## OFFLINE ONLY. Explicit pilot-v4-wormhole replay/guidance using immutable saved inputs.
## Never loaded by the native game. No saves or live controller calls.
const WormholeSim = preload("res://scripts/pilot_wormhole_simulation.gd")
const ExtremeSim = preload("res://scripts/pilot_extreme_simulation.gd")
const Econ = preload("res://scripts/economy.gd")
const Profile = preload("res://scripts/pilot_extreme_profile.gd")
const Parts = preload("res://scripts/parts_expanded.gd")
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
 if not str(route.get("control_version","")) in ["pilot-v3","pilot-v4-wormhole"]:
  return {"error":"Only explicit v3/v4 is supported; never fall back to v1"}
 if not snapshot.is_empty() and str(snapshot.get("control_version","")) != str(route.control_version):
  return {"error":"Snapshot physics identity must match its route"}
 var s = WormholeSim.new() if route.control_version=="pilot-v4-wormhole" else ExtremeSim.new()
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
 var exact: Dictionary = {"control_version":route.control_version,"route":route,"design":source.design,"launcher":source.launcher,
  "seed":source.seed,"ticks":ticks,"elapsed":s.elapsed,"input_commands":timeline.snapshot()}
 return json_value({"mode":mode,"status":s.status,"elapsed":s.elapsed,"ticks":ticks,"position":s.cargo_position(),
  "energy_used":s.telemetry.energy_used,"remaining_energy":s.total_energy(),"integrity":s.ship_integrity(),
  "telemetry":s.telemetry,"events":s.events,"wormhole_events":s.wormhole_events if route.control_version=="pilot-v4-wormhole" else [],"checkpoint":checkpoint,"commands":commands,"snapshot":exact})

var checks:Array=[]
func check(ok:bool,label:String) -> void:
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)

func progression_plan() -> Dictionary:
 var e=Econ.new();e.enable_extreme_mode();e.enable_story_mode()
 var design:Array=Profile.starter_design();var launcher:Array=Profile.starter_launcher();e.starter_stock(design,launcher)
 var days:Array=[]
 check(e.day==1 and e.reputation==0 and e.credits==260,"ordinary default economy without seeded progress")
 for business_day in range(1,4):
  e.ensure_contracts()
  var row={"day":e.day,"start_reputation":e.reputation,"start_credits":e.credits,"offers":e.contracts.duplicate(true),"deliveries":[],"purchases":[]}
  for slot in ["A","B"]:
   var id="D%d-%s"%[business_day,slot]
   check(e.accept_contract(id).ok,"accept "+id)
   check(e.mark_cargo_loaded(id).ok,"load "+id)
   var dispatch=e.begin_dispatch(design,launcher)
   check(dispatch.ok,"formal dispatch "+id)
   var result=compute(dispatch.snapshot)
   check(result.status=="success" and result.integrity==1.0,"ordinary ship guidance delivers intact "+id)
   var receipt=e.settle_contract(id,result.telemetry,result.elapsed,result.status=="success")
   check(receipt.ok and receipt.report.reputation==2,"unique on-time natural receipt "+id)
   var credits=e.credits
   check(not e.settle_contract(id,result.telemetry,result.elapsed,true).ok and e.credits==credits,"duplicate settlement rejected "+id)
   row.deliveries.append({"id":id,"control_version":dispatch.snapshot.route.control_version,"route_profile":dispatch.snapshot.route.get("route_profile",""),"elapsed":result.elapsed,"energy_used":result.energy_used,"remaining_energy":result.remaining_energy,"receipt":receipt.report})
  check(e.close_day().ok,"close day %d"%business_day)
  if business_day==1:
   check(e.workshop_upgrade(1).ok,"earned tier-one workshop purchase")
   check(e.buy_part("battery",Parts.catalog().battery).ok,"earned spare battery purchase")
   row.purchases=[{"item":"workshop_tier_1","cost":180},{"item":"battery","cost":45}]
  if business_day==2:
   check(e.buy_part("beam",Parts.catalog().beam).ok,"earned spare beam purchase")
   row.purchases=[{"item":"beam","cost":10}]
  row.end_credits=e.credits;row.end_reputation=e.reputation;days.append(row)
  check(e.next_day().ok,"next day from %d"%business_day)
 check(days[0].start_reputation==0 and days[1].start_reputation==4 and days[2].start_reputation==8,"reputation unlocked entirely by six settlements")
 check(days[2].offers[1].control_version=="pilot-v4-wormhole","first fresh rep-seven wormhole offer is D3-B")
 check(e.settled_ids.size()==6 and e.deliveries==6 and e.day==4,"complete three-day ledger")
 return {"method":"Offline route planning and direct-method regression only; never a native game or save fixture","checks":checks,"days":days,"final_credits":e.credits,"final_reputation":e.reputation,"passed":checks.all(func(c):return c.passed)}

func _initialize() -> void:
 var args=OS.get_cmdline_user_args()
 var result:Dictionary={}
 if args.is_empty() or "--plan" in args:
  result=progression_plan()
 else:
  var spec:Dictionary={}
  for index in range(args.size()-1):
   if args[index]=="--spec":spec=JSON.parse_string(FileAccess.get_file_as_string(args[index+1]))
  result=compute(spec)
 print("THREE_DAY_REFERENCE_JSON:",JSON.stringify(result,"",true,true))
 quit(2 if result.has("error") or not result.get("passed",true) else 0)
