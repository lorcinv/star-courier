extends SceneTree
## No UI, saves, replay migration or solver changes: inspect exact live circuits.
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

func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var value:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"input_a":-1,"input_b":-1,"target":-1}
 value.merge(extra,true);return value

func chain() -> Array:
 return [part(1,"cargo",0),part(2,"beam",1),part(3,"battery",2),part(4,"thruster",0,1)]

func route(legacy:bool=false) -> Dictionary:
 var data:Dictionary=OldProfile.route(Extreme.route({"weight":1.0})) if legacy else Profile.route(Extreme.route({"weight":1.0}))
 data.hazards=[];data.pilot_gates=[];data.distance=10000.0;data.destination_y=-1000.0;data.pilot_drag=0.0
 return data

func make_sim(design:Array,legacy:bool=false,pad:Array=[]):
 var sim=OldFree.new() if legacy else Free.new()
 sim.configure(design,pad,route(legacy),42)
 return sim

func snapshot(sim) -> PackedByteArray:
 var state:Dictionary={}
 for property in sim.get_property_list():
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
   var value:Variant=sim.get(property.name)
   if value is RandomNumberGenerator:state[property.name]={"seed":value.seed,"state":value.state}
   elif not value is Object:state[property.name]=value
 return var_to_bytes(state)

func inspect_static(design:Array,label:String) -> Dictionary:
 var before:PackedByteArray=var_to_bytes(design)
 var result:Dictionary=Power.analyze(design)
 for attempt in range(5):check(Power.analyze(design)==result,label+" repeat %d is deterministic"%attempt)
 check(var_to_bytes(design)==before,label+" preserves every blueprint byte")
 return result

func inspect_failure(sim,expected:String,label:String) -> Dictionary:
 var before:PackedByteArray=snapshot(sim)
 var result:Dictionary=Power.runtime_failure(sim)
 check(result.code==expected,label+" classification "+str(result.code))
 for attempt in range(5):check(Power.runtime_failure(sim)==result,label+" repeat %d is deterministic"%attempt)
 check(snapshot(sim)==before,label+" preserves all solver variables, physics, telemetry and RNG")
 if expected!="not_applicable":check(sim.telemetry.free_failure=="usable_energy_empty" and result.failure_code=="usable_energy_empty",label+" retains frozen failure code")
 return result

func _initialize() -> void:
 _static_topology();_runtime_configuration();_runtime_damage_and_cuts();_runtime_multiple_cargo();_legacy()
 print("WORKSHOP_POWER_STATUS_DEV10 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)

func _static_topology() -> void:
 var linked:Array=chain()
 var ready:Dictionary=inspect_static(linked,"indirect beam circuit")
 check(ready.ready and ready.status=="ready" and ready.code=="ready","structural beam powers cargo indirectly")
 check(ready.cargo_ids==[1] and ready.battery_ids==[3] and ready.powered_ids==[1,2,3,4],"powered ids include every circuit module")
 check(ready.unpowered_cargo_ids.is_empty() and ready.disconnected_battery_ids.is_empty(),"valid circuit has no warning ids")
 var separated:Array=chain();separated[2].x=4
 var detached:Dictionary=inspect_static(separated,"detached battery")
 check(not detached.ready and detached.code=="cargo_unpowered" and detached.status=="blocked","unpowered cargo is blocked")
 check(detached.unpowered_cargo_ids==[1] and detached.disconnected_battery_ids==[3] and detached.powered_ids==[3],"loose battery is energized but disconnected from cargo")
 var no_battery:Dictionary=Power.analyze([part(1,"cargo",0),part(2,"beam",1)])
 check(not no_battery.ready and no_battery.code=="no_battery" and no_battery.unpowered_cargo_ids==[1] and no_battery.powered_ids.is_empty(),"no battery is distinct from detached battery")
 var no_cargo:Dictionary=Power.analyze([part(3,"battery",0),part(2,"beam",1)])
 check(not no_cargo.ready and no_cargo.code=="no_cargo" and no_cargo.cargo_ids.is_empty() and no_cargo.disconnected_battery_ids==[3],"no cargo never reports launch ready")
 check(Power.analyze([]).code=="no_cargo" and not Power.analyze([]).ready,"empty design reports no cargo")
 var extra:Array=chain();extra.append(part(20,"battery",20))
 var warning:Dictionary=Power.analyze(extra)
 check(warning.ready and warning.status=="warning" and warning.code=="disconnected_battery" and warning.disconnected_battery_ids==[20],"spare disconnected battery warns without denying powered cargo")
 var multiple:Array=[part(10,"cargo",10),part(12,"battery",11),part(1,"cargo",0),part(3,"battery",1),part(30,"beam",30)]
 var both:Dictionary=inspect_static(multiple,"independently powered cargo")
 check(both.ready and both.cargo_ids==[1,10] and both.battery_ids==[3,12] and both.powered_ids==[1,3,10,12],"all independent cargo circuits require and find their own batteries")
 multiple[1].x=15
 var partial:Dictionary=Power.analyze(multiple)
 check(not partial.ready and partial.unpowered_cargo_ids==[10] and partial.disconnected_battery_ids==[12],"first powered cargo cannot conceal a second unpowered cargo")
 var shared:Dictionary=Power.analyze([part(5,"cargo",2),part(3,"battery",1),part(1,"cargo",0),part(9,"battery",1,1)])
 check(shared.ready and shared.cargo_ids==[1,5] and shared.disconnected_battery_ids.is_empty(),"multiple cargo and batteries can share a single circuit")
 var rotated:Array=chain()
 for module in rotated:module.rot=3;module.scale=20.0;module.footprint=[8,8];module.param=0.137
 check(Power.analyze(rotated)==ready,"rotation and visual footprint do not change actual socket connectivity")
 var diagonal:Dictionary=Power.analyze([part(1,"cargo",0),part(3,"battery",1,1,{"scale":20.0,"rot":3})])
 check(diagonal.code=="cargo_unpowered","diagonal contact or large visual scale cannot create a socket")
 var overlapping:Dictionary=Power.analyze([part(1,"cargo",0),part(3,"battery",0)])
 check(overlapping.code=="cargo_unpowered","overlapping centers are not an orthogonal socket")
 var persisted:Array=JSON.parse_string(JSON.stringify(rotated))
 persisted[0].retained_payload={"nested":[1,2,{"unknown":true}]}
 inspect_static(persisted,"JSON compatibility blueprint")
 var normalized:Array=[{"type":"cargo"},{"id":1,"type":"beam","x":1},{"type":"battery","x":2}]
 var defaults:Dictionary=Power.analyze(normalized);var sim=make_sim(normalized)
 check(defaults.cargo_ids==[1] and defaults.battery_ids==[3] and defaults.ready and sim._same_circuit(sim.parts[1],sim.parts[3]),"missing/duplicate ids match simulator read-only normalization")

func _runtime_configuration() -> void:
 var linked=make_sim(chain())
 inspect_failure(linked,"not_applicable","healthy configured flight")
 linked.step(1.0/120.0)
 check(linked.status=="running" and linked.telemetry.energy_fraction>0.99,"connected configuration flies with real usable energy")
 var starter:Array=Profile.starter_design()
 for module in starter:
  if module.id==3:module.x=-3;module.y=0
 var original:PackedByteArray=var_to_bytes(starter)
 var loose=make_sim(starter)
 check(Power.analyze(starter).unpowered_cargo_ids==[1],"fresh-profile battery #3 move to (-3,0) identifies cargo blackout")
 loose.step(1.0/120.0)
 var detail:Dictionary=inspect_failure(loose,"battery_disconnected","fresh-profile one-tick failure")
 check(loose.status=="failed" and is_equal_approx(loose.elapsed,1.0/120.0) and loose.parts[3].energy>0.0,"detached battery remains charged at first fixed-step failure")
 check(detail.empty_cargo_ids==[1] and detail.disconnected_battery_ids==[3] and detail.connected_battery_ids.is_empty(),"failed flight names the exact disconnected battery and cargo")
 check(detail.cargo_failures[0].code=="battery_disconnected" and detail.cargo_failures[0].available_energy<=Power.EPS,"per-cargo reason uses actual zero usable energy")
 check(var_to_bytes(starter)==original,"configure and feedback leave the loaded blueprint unchanged")
 for module in starter:
  if module.id==3:module.x=-1;module.y=0
 var restored=make_sim(starter);restored.step(1.0/120.0)
 check(Power.analyze(starter).ready and restored.status=="running" and restored.telemetry.energy_fraction>0.99,"reconnecting the original socket restores full usable charge")
 var exhausted=make_sim(chain());exhausted.parts[3].energy=0.0;exhausted.step(1.0/120.0)
 var depleted:Dictionary=inspect_failure(exhausted,"energy_depleted","connected exhausted battery")
 check(depleted.connected_battery_ids==[3] and depleted.disconnected_battery_ids.is_empty(),"true depletion retains the connected empty battery")
 var absent=make_sim([part(1,"cargo",0),part(2,"beam",1)]);absent.step(1.0/120.0)
 inspect_failure(absent,"no_battery","no onboard battery")
 var pad_only=make_sim([part(1,"cargo",0)],false,[part(40,"battery",0)])
 pad_only.step(1.0/120.0)
 var pad_view:Dictionary=inspect_failure(pad_only,"no_battery","launcher battery is not onboard power")
 check(pad_view.battery_ids.is_empty() and not pad_only.launcher_parts.is_empty(),"runtime lookup excludes real launcher battery records")
 check(Power.runtime_failure(null).code=="not_applicable","missing simulation is harmless")

func _runtime_damage_and_cuts() -> void:
 var cut=make_sim(chain());cut._cut(2,3)
 # Reproduce the valid pre-rebuild window where status has just become terminal.
 cut.status="failed";cut.telemetry.free_failure="usable_energy_empty"
 check(cut._graph_dirty and cut.parts[1].body_id==cut.parts[3].body_id,"cut fixture deliberately retains stale shared body")
 var before_rebuild:Dictionary=inspect_failure(cut,"battery_disconnected","dirty graph after severed socket")
 check(cut._graph_dirty and before_rebuild.disconnected_battery_ids==[3],"observation neither trusts stale body nor rebuilds it")
 cut._rebuild_bodies()
 check(Power.runtime_failure(cut)==before_rebuild,"classification remains identical after normal body rebuild")
 var actual_cut=make_sim(chain());actual_cut._cut(2,3);actual_cut.step(1.0/120.0)
 inspect_failure(actual_cut,"battery_disconnected","ordinary cut then actual terminal flight step")
 check(actual_cut.parts[3].energy>0.0,"real post-cut failure does not spend the isolated battery")
 var bypass=make_sim([part(1,"cargo",0),part(2,"beam",1),part(3,"battery",1,1),part(4,"beam",0,1)])
 bypass.parts[3].energy=0.0;bypass._cut(2,3)
 bypass.status="failed";bypass.telemetry.free_failure="usable_energy_empty"
 var alternate:Dictionary=inspect_failure(bypass,"energy_depleted","alternate surviving socket path after one cut")
 check(alternate.connected_battery_ids==[3] and alternate.disconnected_battery_ids.is_empty(),"a cut is not automatically a disconnection when another living path remains")
 var broken=make_sim(chain());broken._damage_part(broken.parts[2],100000.0,"collision")
 broken.status="failed";broken.telemetry.free_failure="usable_energy_empty"
 check(not broken.parts[2].alive and broken._graph_dirty,"collision fixture breaks conductive structural beam")
 inspect_failure(broken,"battery_disconnected","destroyed bridge cannot carry power through stale body")
 var destroyed=make_sim(chain());destroyed._damage_part(destroyed.parts[3],100000.0,"collision")
 destroyed.status="failed";destroyed.telemetry.free_failure="usable_energy_empty"
 var destruction:Dictionary=inspect_failure(destroyed,"battery_destroyed","destroyed onboard battery")
 check(destruction.destroyed_battery_ids==[3] and destruction.battery_ids.is_empty(),"destroyed battery is not mislabeled missing or depleted")
 var received=make_sim(chain());received.parts[3].delivered=true;received.parts[3].body_id=-1;received._detach(3)
 received.status="failed";received.telemetry.free_failure="usable_energy_empty"
 var unavailable:Dictionary=inspect_failure(received,"battery_unavailable","already delivered battery")
 check(unavailable.unavailable_battery_ids==[3] and unavailable.destroyed_battery_ids.is_empty(),"delivered hardware is not mislabeled destroyed")
 var cargo_lost=make_sim(chain());cargo_lost._damage_part(cargo_lost.parts[1],100000.0,"collision");cargo_lost._check_status()
 inspect_failure(cargo_lost,"not_applicable","cargo damage remains its own failure")
 check(cargo_lost.telemetry.free_failure=="cargo_destroyed","power presentation cannot replace cargo damage failure")

func _runtime_multiple_cargo() -> void:
 var mixed=make_sim([part(1,"cargo",0),part(2,"battery",1),part(10,"cargo",10),part(12,"battery",15)])
 mixed.parts[2].energy=0.0;mixed.step(1.0/120.0)
 var view:Dictionary=inspect_failure(mixed,"mixed_power_failure","different failures across cargo circuits")
 check(view.empty_cargo_ids==[1,10] and view.connected_battery_ids==[2] and view.disconnected_battery_ids==[12],"mixed failure contains each exact circuit")
 check(view.cargo_failures.size()==2 and view.cargo_failures[0].code=="energy_depleted" and view.cargo_failures[1].code=="battery_disconnected","mixed message can report precise individual reasons")
 var partial=make_sim([part(1,"cargo",0),part(2,"battery",1),part(10,"cargo",10),part(12,"battery",15)])
 partial.step(1.0/120.0)
 var one:Dictionary=inspect_failure(partial,"battery_disconnected","one powered cargo and one disconnected cargo")
 check(one.empty_cargo_ids==[10] and one.connected_battery_ids==[2] and one.cargo_failures.size()==1,"powered cargo is not included in failure details")
 var depleted_with_spare=make_sim([part(1,"cargo",0),part(2,"battery",1),part(12,"battery",15)])
 depleted_with_spare.parts[2].energy=0.0;depleted_with_spare.step(1.0/120.0)
 var spare:Dictionary=inspect_failure(depleted_with_spare,"energy_depleted","empty connected circuit with a charged remote spare")
 check(spare.connected_battery_ids==[2] and spare.disconnected_battery_ids==[12],"connected depletion is not rewritten as disconnection merely because a spare exists")
 var shared=make_sim([part(1,"cargo",0),part(2,"battery",1),part(10,"cargo",2),part(12,"battery",1,1)])
 shared.parts[2].energy=0.0;shared.step(1.0/120.0)
 check(shared.status=="running","one empty battery cannot mask another charged battery in the same circuit")
 inspect_failure(shared,"not_applicable","shared live battery continues powering both cargo")

func _legacy() -> void:
 var disconnected:Array=chain();disconnected[2].x=6
 var old=make_sim(disconnected,true);old.step(1.0/120.0)
 inspect_failure(old,"battery_disconnected","legacy v1 uses the same unmodified power contract")
 check(old.route.control_version=="pilot-free-v1" and old.telemetry.control_version=="pilot-free-v1","helper does not relabel legacy route or telemetry versions")
