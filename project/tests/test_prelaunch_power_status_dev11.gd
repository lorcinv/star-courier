extends SceneTree
## Pure live observation before a fixed tick, at cuts, and during ordinary flight.
## Main owns the v2-only host guard; this helper never migrates either simulator.
const Power=preload("res://scripts/workshop_power_status_v1.gd")
const Free=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const OldFree=preload("res://scripts/pilot_free_simulation_v1.gd")
const OldProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0

func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func part(id:int,kind:String,x:int,y:int=0) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"input_a":-1,"input_b":-1,"target":-1}

func chain() -> Array:
 return [part(1,"cargo",0),part(2,"beam",1),part(3,"battery",2),part(4,"thruster",0,1)]

func make_sim(design:Array,legacy:bool=false,pad:Array=[]):
 var route:Dictionary=OldProfile.route(Extreme.route({"weight":1.0})) if legacy else Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var sim=OldFree.new() if legacy else Free.new()
 sim.configure(design,pad,route,42)
 return sim

func snapshot(sim) -> PackedByteArray:
 var state:Dictionary={}
 for property in sim.get_property_list():
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
   var value:Variant=sim.get(property.name)
   if value is RandomNumberGenerator:state[property.name]={"seed":value.seed,"state":value.state}
   elif not value is Object:state[property.name]=value
 return var_to_bytes(state)

func inspect(sim,expected:String,label:String) -> Dictionary:
 var before:PackedByteArray=snapshot(sim)
 var result:Dictionary=Power.runtime_status(sim)
 check(result.code==expected,label+" classification "+str(result.code))
 check(result.ready==(expected=="ready"),label+" ready describes all living undelivered cargo")
 for attempt in range(4):check(Power.runtime_status(sim)==result,label+" repeat %d is deterministic"%attempt)
 check(snapshot(sim)==before,label+" preserves all script variables, telemetry, graph, physics and RNG")
 return result

func _initialize() -> void:
 _before_first_tick();_multiple_cargo();_live_cuts_and_damage();_terminal_boundaries();_legacy_boundary();_read_only_flight()
 print("PRELAUNCH_POWER_STATUS_DEV11 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)

func _before_first_tick() -> void:
 var healthy=make_sim(chain())
 var ready:Dictionary=inspect(healthy,"ready","connected full battery before first tick")
 check(healthy.status=="running" and healthy.elapsed==0.0 and healthy.telemetry.energy_fraction>0.99,"configure leaves full battery on unchanged running simulator")
 check(ready.cargo_ids==[1] and ready.connected_battery_ids==[3] and ready.empty_cargo_ids.is_empty() and ready.cargo_failures.is_empty(),"healthy live observation has exact circuit and no failure")
 check(Power.runtime_failure(healthy).code=="not_applicable","healthy live observation does not widen terminal API")

 var disconnected:Array=chain();disconnected[2].x=6
 var loose=make_sim(disconnected)
 var disconnected_view:Dictionary=inspect(loose,"battery_disconnected","configured detached charged battery before first tick")
 check(loose.elapsed==0.0 and loose.status=="running" and loose.telemetry.get("free_failure","")=="" and loose.parts[3].energy>0.0,"disconnected observation does not step, fail or spend the battery")
 check(loose.telemetry.energy_fraction==0.0 and disconnected_view.empty_cargo_ids==[1] and disconnected_view.disconnected_battery_ids==[3],"zero percent is identified as detached power before launch")
 check(disconnected_view.failure_code=="" and Power.runtime_failure(loose).code=="not_applicable","prelaunch observation never invents a terminal failure code")
 check(disconnected_view.cargo_failures[0]=={"cargo_id":1,"code":"battery_disconnected","available_energy":0.0,"connected_battery_ids":[]},"prelaunch disconnection includes isolated cargo and actual usable energy")

 var empty=make_sim(chain());empty.parts[3].energy=0.0
 var depleted:Dictionary=inspect(empty,"energy_depleted","connected genuinely empty battery before first tick")
 check(empty.telemetry.energy_fraction>0.99 and depleted.connected_battery_ids==[3],"live energy read does not trust the preexisting full-charge telemetry")
 check(Power.runtime_failure(empty).code=="not_applicable","genuine prelaunch depletion leaves terminal-only API inactive")
 var absent=make_sim([part(1,"cargo",0),part(2,"beam",1)])
 var missing:Dictionary=inspect(absent,"no_battery","configured cargo without an onboard battery")
 check(missing.battery_ids.is_empty() and missing.empty_cargo_ids==[1] and absent.elapsed==0.0,"no-battery observation is distinct and needs no step")
 var pad_only=make_sim([part(1,"cargo",0)],false,[part(40,"battery",0)])
 check(inspect(pad_only,"no_battery","launcher-only battery").battery_ids.is_empty() and not pad_only.launcher_parts.is_empty(),"anchored launcher battery cannot masquerade as cargo power")

 var threshold=make_sim(chain());threshold.parts[3].energy=Power.EPS
 inspect(threshold,"energy_depleted","exact solver empty-energy threshold")
 threshold.parts[3].energy=Power.EPS*1.01
 inspect(threshold,"ready","positive power above solver empty-energy threshold")
 var spare:Array=chain();spare.append(part(30,"battery",30))
 var spare_view:Dictionary=inspect(make_sim(spare),"ready","powered cargo with a detached spare")
 check(spare_view.disconnected_battery_ids==[30] and spare_view.cargo_failures.is_empty(),"spare battery does not create a cargo-power failure")

func _multiple_cargo() -> void:
 var pieces:Array=[part(1,"cargo",0),part(2,"battery",1),part(10,"cargo",10),part(12,"battery",15)]
 var partial=make_sim(pieces)
 check(partial.telemetry.energy_remaining>0.0 and partial.telemetry.energy_fraction>0.99,"partial blackout fixture has a positive aggregate full-charge gauge")
 var view:Dictionary=inspect(partial,"battery_disconnected","one powered cargo and one disconnected cargo before first tick")
 check(view.cargo_ids==[1,10] and view.empty_cargo_ids==[10] and view.connected_battery_ids==[2] and view.disconnected_battery_ids==[12],"positive aggregate energy cannot hide an isolated second cargo")
 check(view.cargo_failures.size()==1 and view.cargo_failures[0].cargo_id==10,"only empty cargo contributes a live failure")
 partial.parts[2].energy=0.0
 var mixed:Dictionary=inspect(partial,"mixed_power_failure","different live failures across two cargo")
 check(mixed.cargo_failures[0].code=="energy_depleted" and mixed.cargo_failures[1].code=="battery_disconnected","mixed live observation retains both exact reasons in sorted cargo order")
 var shared=make_sim([part(10,"cargo",2),part(12,"battery",1,1),part(1,"cargo",0),part(2,"battery",1)])
 shared.parts[2].energy=0.0
 var supplied:Dictionary=inspect(shared,"ready","two cargo with one empty and one full shared battery")
 check(supplied.cargo_ids==[1,10] and supplied.connected_battery_ids==[2,12] and supplied.empty_cargo_ids.is_empty(),"shared circuit uses the remaining real battery for every cargo")

func _live_cuts_and_damage() -> void:
 var cut=make_sim(chain());cut._cut(2,3)
 check(cut._graph_dirty and cut.parts[1].body_id==cut.parts[3].body_id and cut.telemetry.energy_fraction>0.99,"immediate cut retains a deliberately stale shared body and full gauge")
 var detached:Dictionary=inspect(cut,"battery_disconnected","live severed socket before body rebuild")
 check(cut._graph_dirty and cut.elapsed==0.0 and detached.disconnected_battery_ids==[3],"observation follows dirty circuit without clearing it or advancing time")
 check(Power.runtime_failure(cut).code=="not_applicable","live cut does not activate terminal-only API")
 cut._rebuild_bodies()
 check(Power.runtime_status(cut)==detached,"ordinary body rebuild leaves live observation byte-equivalent")

 var bypass=make_sim([part(1,"cargo",0),part(2,"beam",1),part(3,"battery",1,1),part(4,"beam",0,1)])
 bypass._cut(2,3)
 inspect(bypass,"ready","cut with a surviving alternative socket path")
 bypass.parts[3].energy=0.0
 check(inspect(bypass,"energy_depleted","empty battery behind surviving alternative socket path").connected_battery_ids==[3],"dirty graph does not turn a connected empty battery into a disconnected one")
 var bridge=make_sim(chain());bridge._damage_part(bridge.parts[2],100000.0,"collision")
 inspect(bridge,"battery_disconnected","destroyed structural bridge before a flight tick")
 var destroyed=make_sim(chain());destroyed._damage_part(destroyed.parts[3],100000.0,"collision")
 check(inspect(destroyed,"battery_destroyed","destroyed sole battery before a flight tick").destroyed_battery_ids==[3],"destroyed battery is distinct from missing hardware and depletion")
 var unavailable=make_sim(chain());unavailable.parts[3].delivered=true;unavailable.parts[3].body_id=-1;unavailable._detach(3)
 check(inspect(unavailable,"battery_unavailable","already received battery before a flight tick").unavailable_battery_ids==[3],"received battery cannot be used as onboard power")

func _terminal_boundaries() -> void:
 check(Power.runtime_status(null).code=="not_applicable" and not Power.runtime_status(null).ready,"absent simulation is harmless")
 inspect(make_sim([]),"not_applicable","failed configure without cargo")
 var delivered=make_sim(chain())
 delivered.parts[1].delivered=true;delivered.parts[1].body_id=-1;delivered._detach(1);delivered.status="success"
 var received:Dictionary=inspect(delivered,"not_applicable","successful flight with no active cargo")
 check(received.cargo_ids.is_empty() and received.cargo_failures.is_empty() and received.empty_cargo_ids.is_empty(),"received cargo is not mislabeled missing battery or depleted")
 var damaged=make_sim([part(1,"cargo",0),part(3,"battery",6),part(10,"cargo",10)])
 damaged._damage_part(damaged.parts[10],100000.0,"collision");damaged._check_status()
 check(damaged.status=="failed" and damaged.telemetry.free_failure=="cargo_destroyed","other terminal fixture retains a living unpowered cargo")
 var other:Dictionary=inspect(damaged,"not_applicable","cargo damage takes precedence over a coincident blackout")
 check(other.failure_code=="cargo_destroyed" and other.cargo_failures.is_empty() and Power.runtime_failure(damaged).code=="not_applicable","neither API reclassifies another failure as a power failure")

 var exhausted=make_sim(chain());exhausted.parts[3].energy=0.0;exhausted.step(1.0/120.0)
 var live:Dictionary=inspect(exhausted,"energy_depleted","actual terminal depletion")
 var terminal:Dictionary=Power.runtime_failure(exhausted)
 live.erase("ready")
 check(live==terminal and terminal.failure_code=="usable_energy_empty" and not terminal.has("ready"),"terminal result retains its exact old shape and matches the shared live classification")
 var disconnected:Array=chain();disconnected[2].x=6
 var failed_cut=make_sim(disconnected);failed_cut.step(1.0/120.0)
 live=Power.runtime_status(failed_cut);live.erase("ready")
 check(live==Power.runtime_failure(failed_cut) and live.code=="battery_disconnected","actual disconnected terminal still uses the frozen failure contract")

func _legacy_boundary() -> void:
 var pieces:Array=chain();pieces[2].x=6
 var legacy=make_sim(pieces,true)
 inspect(legacy,"battery_disconnected","direct legacy-v1 diagnostic before first tick")
 check(Power.runtime_failure(legacy).code=="not_applicable" and legacy.route.control_version==OldProfile.VERSION and legacy.telemetry.control_version==OldProfile.VERSION,"read-only helper leaves host applicability and legacy protocol identity intact")
 legacy.step(1.0/120.0)
 var before:PackedByteArray=snapshot(legacy)
 var terminal:Dictionary=Power.runtime_failure(legacy)
 var live:Dictionary=Power.runtime_status(legacy);live.erase("ready")
 check(live==terminal and terminal.code=="battery_disconnected" and snapshot(legacy)==before,"existing legacy-v1 terminal caller remains byte-identical and read-only")

func _read_only_flight() -> void:
 var sim=make_sim(chain())
 var before:PackedByteArray=snapshot(sim)
 var start:int=Time.get_ticks_usec()
 for frame in range(240):Power.runtime_status(sim)
 print("MEASURE prelaunch_observation_240_calls_usec=",Time.get_ticks_usec()-start)
 check(snapshot(sim)==before,"240 consecutive display observations preserve complete configured solver state")
 var detached:Array=chain();detached[2].x=6
 var loose=make_sim(detached);before=snapshot(loose)
 var result:Dictionary=Power.runtime_status(loose)
 result.cargo_ids.clear();result.disconnected_battery_ids.append(999)
 result.cargo_failures[0].connected_battery_ids.append(999);result.cargo_failures[0].code="edited"
 check(snapshot(loose)==before and Power.runtime_status(loose).cargo_failures[0].code=="battery_disconnected","returned evidence owns only its output arrays and never aliases mutable solver data")

 var observed=make_sim(Profile.starter_design());var control=make_sim(Profile.starter_design())
 check(snapshot(observed)==snapshot(control),"observed/control flights start with identical deterministic state")
 for tick in range(120):
  observed.set_free_flight_input(650,-300,false,false,-1,false)
  control.set_free_flight_input(650,-300,false,false,-1,false)
  Power.runtime_status(observed)
  observed.step(1.0/120.0);control.step(1.0/120.0)
 check(snapshot(observed)==snapshot(control),"live observation on every active tick preserves exact physics, numerics, telemetry, events and RNG")
 check(observed.telemetry.energy_used>0.0 and observed.elapsed>0.9,"deterministic parity includes real paid propulsion and elapsed flight")
