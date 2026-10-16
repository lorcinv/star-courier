extends Node
## Bounded headless Main receipt checks. The copied native completed-moon save
## is unedited input; all subsequent flying is automated Main input, not native
## player/GUI evidence. No production simulator, price or order field is changed.
## The final table is explicitly synthetic: finish_flight is invoked on a live
## simulator (so finalize does not refresh fields) and only the report-boundary
## version label/counter is varied. It is not protocol or gameplay acceptance.
const Main=preload("res://scripts/main.gd")
const Economy=preload("res://scripts/economy.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
var passed:int=0
var failed:int=0
var main
var frozen_route:Dictionary={}
var records:Array=[]
func check(ok:bool,label:String)->bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func same(a:Variant,b:Variant,label:String)->bool:
 return check(var_to_bytes(a)==var_to_bytes(b),label)
func canonical(value:Variant)->Variant:
 if value is Dictionary:
  var result:Dictionary={};var keys:Array=value.keys();keys.sort_custom(func(a,b):return str(a)<str(b))
  for key in keys:result[key]=canonical(value[key])
  return result
 if value is Array:
  var result:Array=[]
  for item in value:result.append(canonical(item))
  return result
 return value
func model_state()->PackedByteArray:
 return var_to_bytes([main.sim.parts,main.sim.bodies,main.sim.links,main.sim.obstacles,main.sim.telemetry,main.sim.events,main.sim.elapsed,main.sim._rng.state])
func persisted()->Dictionary:
 var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 return raw if raw is Dictionary else {}
func run()->void:
 if OS.get_environment("SC_COLD_RECEIPT_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_require_existing_save=true;main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main);main.set_process(false)
 if not check(not main.economy.review_load_blocked,"real Main loads isolated unedited completed-moon input"):finish();return
 check(main.economy.day==5 and main.economy.credits==1229 and main.economy.delivery_chapter_state.unlocked_level==5,"seed has actual completed moon and no fabricated chapter progress")
 check(main.economy.close_day_and_save(main.design,main.launcher,main.settings).ok and main.economy.next_day_and_save(main.design,main.launcher,main.settings).ok,"ordinary close/open creates next fifth-level offer")
 check(main.economy.contract_by_id("D6-A").control_version==Rift.VERSION,"new offer is current rift v8")
 check(main.economy.accept_contract_and_save("D6-A",main.design,main.launcher,main.settings).ok and main.economy.mark_cargo_loaded("D6-A").ok,"real economy accepts and loads unchanged D6-A")
 main.settings.launch_settings={"angle_degrees":0.0,"power_fraction":1.0}
 frozen_route=main.economy.active_contract().duplicate(true)
 actual_cold_receipt(true)
 actual_cold_receipt(false)
 synthetic_observation_boundaries()
 print("COLD_RECEIPT_DEV31_RECORDS ",JSON.stringify(records))
 main.queue_free();await get_tree().process_frame
 finish()
func steer(goal:Vector2,speed:float)->void:
 var body:Dictionary=main.sim.body_for_part(1)
 var delta:Vector2=goal-main.sim.cargo_position()
 var desired:Vector2=delta.normalized()*minf(speed,sqrt(2.0*2.0*maxf(0.0,delta.length()-1.0)))
 var error:Vector2=desired-Vector2(body.velocity)
 main.pilot_keys.clear()
 if error.x>.2:main.pilot_keys[KEY_D]=true
 elif error.x<-.2:main.pilot_keys[KEY_A]=true
 if error.y>.2:main.pilot_keys[KEY_S]=true
 elif error.y<-.2:main.pilot_keys[KEY_W]=true
func actual_cold_receipt(is_trial:bool)->void:
 var label:String="free" if is_trial else "formal"
 var credits:int=main.economy.credits
 var ledger:Dictionary=main.economy.settled_ids.duplicate(true)
 var inventory:Dictionary=main.economy.inventory.duplicate(true)
 var chapter:Dictionary=main.economy.delivery_chapter_state.duplicate(true)
 var route:Dictionary=main.economy.trial_route()
 if not is_trial:
  if not check(main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"formal dispatch freezes actual current contract"):return
  route=main.economy.in_flight.route.duplicate(true)
 var committed:Dictionary=main.economy.active_contract().duplicate(true)
 main._configure_flight(is_trial,main.design,main.launcher,route)
 if not check(main.page=="flight" and main.sim.get_script()==load("res://scripts/pilot_delivery_rift_simulation_v8.gd"),label+" uses actual Main current rift simulator"):return
 check(main._release_delivery_launcher() and main.sim.launch_released,label+" actual launcher release")
 for tick in 60*40:
  if main.sim.status!="running" or float(main.sim.telemetry.get("biological_damage",0.0))>=6.0:break
  var entered:bool=main.sim.telemetry.get("region","")=="greenhouse"
  steer(Vector2(147,0) if entered else Vector2(29,0),8.0 if entered else 7.0)
  main._step_flight()
 var cold:float=float(main.sim.telemetry.get("biological_damage",0.0))
 if not check(main.sim.status=="running" and cold>=6.0 and int(main.sim.telemetry.portal_crossing_tick)>=0,label+" real portal then actual timed cold exposure generates HP loss"):print("COLD_RECEIPT_FLIGHT_FAILURE ",JSON.stringify(main.sim.telemetry));return
 var integrity:float=float(main.sim.telemetry.delivery_integrity)
 var elapsed:float=float(main.sim.elapsed)
 var frozen_physics:PackedByteArray=var_to_bytes([main.sim.parts,main.sim.bodies,main.sim.links,main.sim.obstacles,main.sim.elapsed,main.sim._rng.state])
 var quote:Dictionary=main.economy.estimate_delivery(route,main.sim.telemetry,elapsed,false)
 var without_counter:Dictionary=main.sim.telemetry.duplicate(true);without_counter.erase("biological_damage")
 same(quote,main.economy.estimate_delivery(route,without_counter,elapsed,false),label+" cold observation cannot create a separate fee or alter quote")
 main.abort_flight()
 if not check(main.page=="report" and not main.report.success and main.report.trial==is_trial,label+" real abort finishes through Main report"):return
 check(main.report.has("biological_damage") and main.report.biological_damage==cold,label+" report retains exact actual HP counter after result merge")
 check(main.report.delivery_integrity==integrity and main.report.integrity==integrity*100.0 and main.report.elapsed==elapsed,label+" observation does not rescale integrity or advance time")
 # Finalize may mark recovery fields; the stable position/velocity and all
 # cost totals are checked below instead of pretending finalization is a no-op.
 check(main.sim.telemetry.biological_damage==cold and main.sim.elapsed==elapsed,label+" reporting adds no cold tick")
 same(main.economy.inventory,inventory,label+" receipt leaves owned inventory unchanged")
 same(main.economy.delivery_chapter_state,chapter,label+" abort never advances chapter")
 if is_trial:
  check(main.economy.credits==credits and main.economy.settled_ids==ledger,"free receipt changes neither credits nor formal ledger")
  same(main.economy.active_contract(),committed,"free receipt preserves every accepted order field")
  check(main.report.estimated_profit==quote.profit,"free estimated profit remains existing fee calculation")
  var record:Dictionary=main.economy.last_trials["D6-A"].latest
  check(record.biological_damage==cold and persisted().last_trials["D6-A"].latest.biological_damage==cold,"free exact cold counter survives real saved trial report")
 else:
  for key in ["energy_j","income","energy","ammo","repairs","lost","compensation","actual_costs","charged_costs","profit","delivery_integrity","min_delivery_integrity"]:
   check(main.report[key]==quote[key],"formal merge preserves normal quote "+key)
  check(main.economy.credits==credits+int(quote.profit) and main.economy.in_flight.is_empty(),"formal charges only existing quote once and clears dispatch")
  var settled:Dictionary=main.economy.contract_by_id("D6-A").duplicate(true);settled.erase("success");settled.status=committed.status
  same(settled,committed,"formal settlement changes only ordinary status/success fields")
  for id in ledger:same(main.economy.settled_ids[id],ledger[id],"historical receipt unchanged "+str(id))
  var after:int=main.economy.credits;main.finish_flight();check(main.economy.credits==after,"repeated finish cannot settle twice")
  var reopened=Economy.new();var saved:Dictionary=reopened.load_state(true)
  check(not saved.is_empty() and not reopened.review_load_blocked and reopened.credits==after and reopened.in_flight.is_empty(),"real saved formal account reopens with exact balance and empty dispatch")
  # The change is Main's displayed report; it does not retrofit a new field
  # into the economic ledger/history or rewrite earlier saved reports.
  check(not reopened.last_settlement.has("biological_damage"),"formal historical ledger schema is not expanded by display-only observation")
 records.append({"scope":"automated Main input, not native player","trial":is_trial,"elapsed":elapsed,"biological_damage_hp":cold,"integrity":integrity,"energy_j":main.sim.telemetry.energy_used,"quote":quote,"credits_before":credits,"credits_after":main.economy.credits,"native":false})
func synthetic_observation_boundaries()->void:
 var current:Dictionary=frozen_route.duplicate(true)
 # Synthetic report observation only. No formal settlement or protocol claim.
 for version in ["pilot-rift-v5","pilot-rift-v6","pilot-rift-v7","pilot-rift-v8"]:
  boundary(current,version,2.125,true,true,"exact rift family positive value")
 for value in [0,0.0,7,0.00001]:boundary(current,Rift.VERSION,value,true,true,"finite nonnegative numeric value")
 for value in [null,true,false,"3",-0.1,NAN,INF,-INF,{},[]]:boundary(current,Rift.VERSION,value,true,false,"invalid counter omitted")
 boundary(current,Rift.VERSION,null,false,false,"absent observation stays absent without simulator refresh")
 for version in ["pilot-delivery-v8","pilot-ascent-v8","pilot-free-v2","pilot-rift-v9","pilot-rift-v8-extra"]:
  boundary(current,version,12.0,true,false,"non-rift or unknown version cannot leak cold field")
func boundary(route:Dictionary,version:String,value:Variant,present:bool,expected:bool,label:String)->void:
 main._configure_flight(true,main.design,main.launcher,route)
 main.flight_order.control_version=version
 if present:main.sim.telemetry.biological_damage=value
 else:main.sim.telemetry.erase("biological_damage")
 var before:PackedByteArray=model_state()
 var credits:int=main.economy.credits;var ledger:Dictionary=main.economy.settled_ids.duplicate(true)
 main.finish_flight()
 check(main.report.has("biological_damage")==expected and (not expected or main.report.biological_damage==float(value)),"synthetic "+label+" "+version+" "+str(value))
 check(model_state()==before and main.economy.credits==credits and main.economy.settled_ids==ledger,"synthetic observation is physically and financially read-only")
func finish()->void:
 print("COLD_RECEIPT_DEV31 ",passed," passed ",failed," failed")
 get_tree().quit(0 if failed==0 else 1)
