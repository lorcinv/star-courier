extends SceneTree
## One real D3-B7 durable roundtrip. Synthetic prior-day progression is explicitly
## a fixture; all current offer, acceptance, flight, replay and receipt are real.
const Econ=preload("res://scripts/economy.gd")
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Free=preload("res://scripts/pilot_free_simulation_v2.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
var design:Array=Profile.starter_design()
var pad:Array=Profile.starter_launcher()
var settings:Dictionary={"volume":0.0,"reduced_motion":true}
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
 return ok
func gate(route:Dictionary) -> String:
 # Model-only roundtrip; pinned art and real Main entry have separate tests.
 var error:String=Econ.route_validation_error(route)
 return error if not error.is_empty() else Caps.route_error(route)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func restored():
 var e=Econ.new();e.route_guard=gate;e.load_state(true);return e
func command(sim,target:Vector2) -> Dictionary:
 var body:Dictionary=sim.body_for_part(1)
 if body.is_empty():return Timeline.neutral()
 var delta:Vector2=target-sim.cargo_position()
 var wanted:Vector2=delta.normalized()*minf(9.0,sqrt(delta.length()*3.0))
 var accel:Vector2=(wanted-body.velocity)/.65-Vector2(float(sim.route.wind[0]),float(sim.route.wind[1])+float(sim.route.gravity))
 var force:float=0.0
 for p in body.parts:
  if p.type=="thruster" and p.alive:force+=float(p.param)*float(p.output_factor)
 var input:Vector2=(accel*float(body.mass)/maxf(.001,force*float(sim.route.free_drive_throttle))).limit_length(1.0)
 var state:Dictionary=Timeline.neutral();state.axis_x_q=roundi(input.x*1000.0);state.axis_q=roundi(input.y*1000.0);return state
func step(sim,state:Dictionary) -> void:
 sim.set_free_flight_input(state.axis_x_q,state.axis_q,state.boost,state.active,state.device_id,state.brake);sim.step(1.0/60.0)
func finish() -> void:
 print("MOSSLIGHT_ECONOMY_ROUNDTRIP_DEV17 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json"):
  printerr("Use a fresh isolated HOME/XDG_DATA_HOME. Existing saves are never removed by this test.");quit(2);return
 var e=Econ.new();e.route_guard=gate;e.enable_force_mode();e.day=3;e.reputation=4;e.deliveries=2;e.credits=600
 e.starter_stock(design,pad);e.enable_story_mode()
 if not check(e.contracts.size()==2 and e.contracts[1].id==7 and e.contracts[1].contract_id=="D3-B","normal empty authoring boundary exposes D3-B7"):finish();return
 var cid:String=e.contracts[1].contract_id
 if not check(e.save_state(design,pad,settings),"new offer saves through production ledger"):finish();return
 var authored:Dictionary=disk().contracts[1].duplicate(true)
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 e=restored();e.ensure_contracts()
 if not check(not e.review_load_blocked and Content._same(e.contract_by_id(cid),authored),"saved available ID7 reloads exactly without reroll"):finish();return
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"read-only load and queries preserve durable bytes")
 if not check(e.accept_contract_and_save(cid,design,pad,settings).ok,"actual ID7 accepts through durable transaction"):finish();return
 var accepted:Dictionary=disk().contracts[1].duplicate(true)
 e=restored()
 if not check(not e.review_load_blocked and e.active_contract_id==cid and Content._same(e.active_contract(),accepted),"accepted ID7 and committed commercial terms reload exactly"):finish();return
 e.mark_story_seen(cid,cid+"/accept")
 if not check(e.mark_cargo_loaded(cid).ok and e.begin_dispatch(design,pad).ok,"loaded ID7 starts actual formal dispatch"):finish();return
 var original:Dictionary=e.in_flight.duplicate(true)
 var sim=Free.new();sim.configure(original.design,original.launcher,original.route,int(original.seed))
 var timeline=Timeline.new()
 for tick in range(120):
  if sim.status!="running":break
  var state:Dictionary=command(sim,Vector2(58.0,-45.0));timeline.record(tick,state);step(sim,state)
 if not check(sim.status=="running","actual current flight reaches120 recorded ticks"):finish();return
 e.in_flight.input_commands=timeline.snapshot();e.in_flight.ticks=120;e.in_flight.elapsed=sim.elapsed
 if not check(e.save_state(design,pad,settings),"actual flight and input commands save through normal ledger"):finish();return
 var raw:Dictionary=disk();var frozen:Dictionary=raw.in_flight.duplicate(true)
 var position:Vector2=sim.cargo_position();var used:float=float(sim.telemetry.energy_used)
 check(raw.in_flight.route.id==7 and raw.in_flight.input_schema==Profile.INPUT_SCHEMA and raw.in_flight.ticks==120,"raw in-flight record has exact new identity and existing command protocol")
 e=restored()
 if not check(not e.review_load_blocked and Content._same(e.in_flight,frozen),"real saved in-flight ID7 snapshot reloads intact"):finish();return
 var replay=Free.new();replay.configure(e.in_flight.design,e.in_flight.launcher,e.in_flight.route,int(e.in_flight.seed))
 var restored_timeline=Timeline.new()
 if not check(restored_timeline.restore(e.in_flight.input_commands,120),"durable recorded inputs restore"):finish();return
 for tick in range(120):step(replay,restored_timeline.state_at(tick))
 if not check(replay.status=="running" and replay.cargo_position()==position and float(replay.telemetry.energy_used)==used,"real durable replay reconstructs exact trajectory and paid energy"):finish();return
 var targets:Array=[Vector2(58.0,-45.0),Vector2(228.0,-45.0),Content.DESTINATION]
 var phase:int=0;var ticks:int=120
 for unused in range(8880):
  if replay.status!="running":break
  if phase<targets.size()-1 and replay.cargo_position().distance_to(targets[phase])<2.0:phase+=1
  var state:Dictionary=command(replay,targets[phase]);restored_timeline.record(ticks,state);step(replay,state);ticks+=1
 print("MOSSLIGHT_DURABLE_FLIGHT ",JSON.stringify({"status":replay.status,"ticks":ticks,"energy_used":replay.telemetry.get("energy_used"),"energy_remaining":replay.telemetry.get("energy_remaining"),"integrity":replay.telemetry.get("integrity"),"contacts":replay.telemetry.get("swept_contacts")}))
 if not check(replay.status=="success" and float(replay.telemetry.get("integrity",0.0))==1.0 and float(replay.telemetry.get("energy_remaining",0.0))>=600.0,"restored genuine heavy ID7 delivers intact with at least10percent reserve"):finish();return
 e.in_flight.input_commands=restored_timeline.snapshot();e.in_flight.ticks=ticks;e.in_flight.elapsed=replay.elapsed
 replay.finalize_settlement()
 if not check(e.settle_contract_and_save(cid,replay.telemetry,replay.elapsed,true,design,pad,settings).ok,"actual ID7 delivery settles durably once"):finish();return
 raw=disk();var receipt:Dictionary=raw.last_settlement.duplicate(true);var context:Dictionary=receipt.get("route_context",{})
 check(context.get("route_profile")==Content.ROUTE_PROFILE and context.get("route_kind")=="mosslight" and context.get("destination_id")==Content.DESTINATION_ID and context.get("destination_name")==Content.FIELDS.destination_name,"raw formal receipt stores exact new route and actual destination")
 check(float(receipt.get("energy_j",-1.0))==float(replay.telemetry.energy_used) and receipt.get("control_version")==Profile.VERSION,"receipt records actual once-billed energy under unchanged free-v2 protocol")
 e=restored()
 check(not e.review_load_blocked and e.in_flight.is_empty() and e.settled_ids.has(cid) and Content._same(e.last_settlement,receipt),"real settled ledger reload preserves exact receipt and clears flight")
 var credit:int=e.credits;var jobs:int=e.jobs_today
 check(not e.settle_contract(cid,replay.telemetry,replay.elapsed,true).ok and e.credits==credit and e.jobs_today==jobs,"repeated settlement cannot award or charge twice")
 var returns:Array=e.pending_story_returns();var true_address:bool=false
 for conversation in returns:
  if conversation.get("contract_id")==cid:
   for line in conversation.get("lines",[]):true_address=true_address or str(line.text).contains(Content.FIELDS.destination_name)
 check(true_address,"reloaded pending return story names actual mosslight destination")
 finish()
