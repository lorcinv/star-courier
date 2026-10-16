extends SceneTree
## Focused v6 contract tests: empty power is not a physics failure, but never
## grants an active device free work. Residual-cell fixtures exercise payment
## through _consume, including inherited valves and graph-cut boundaries.
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const OldSim=preload("res://scripts/pilot_delivery_simulation_v3.gd")
const OldProfile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Launcher=preload("res://scripts/launcher_v3.gd")
const DT:float=1.0/120.0
const TOL:float=0.000001
var passed:int=0
var failed:int=0

func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func near(a:float,b:float)->bool:return absf(a-b)<TOL

func part(id:int,kind:String,x:int,y:int=0,param:float=0.0,extra:Dictionary={})->Dictionary:
 var result:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1}
 result.merge(extra,true);return result

func route(extra:Dictionary={},legacy:bool=false)->Dictionary:
 var source:Dictionary={"distance":1000.0,"destination_y":0.0,"delivery_radius":1.0,"max_delivery_speed":8.0,"weight":1.0,"hazards":[],"gravity":0.0,"wind":[0.0,0.0],"pilot_drag":0.0,"min_delivery_integrity":0.85}
 source.merge(extra,true)
 return OldProfile.route(source) if legacy else Profile.route(source)

func make(ship:Array,extra:Dictionary={},pad:Array=[],legacy:bool=false):
 var sim=OldSim.new() if legacy else Sim.new()
 sim.configure(ship,pad,route(extra,legacy),42)
 return sim

func supply_ship(consumer:String="thruster")->Array:
 return [part(1,"cargo",0),part(2,"battery",-1,0,300.0),part(3,"battery",1,0,300.0),part(4,consumer,0,-1,20.0),part(6,"battery",5,0,300.0)]

func residual_cells(sim)->void:
 # Initial capacities are untouched; only explicitly depleted fixture state.
 sim.parts[2].energy=100.0;sim.parts[3].energy=300.0;sim.parts[6].energy=500.0

func _initialize()->void:
 coast_to_receiver();empty_devices();proportional_supply();valve_limits();cut_circuits();legacy_payment()
 print("CELL_SUPPLY_COAST_V6 passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)

func coast_to_receiver()->void:
 var ship:Array=[part(1,"cargo",0)]
 var receiver:Dictionary={"distance":20.0}
 var launched=make(ship,receiver,Launcher.starter_launcher())
 var old=make(ship,receiver,Launcher.starter_launcher(),true)
 var idle=make(ship,receiver)
 check(launched.status=="running" and Profile.validation_error(launched.route).is_empty(),"bare cargo accepts a valid explicit v6 contract")
 var preview:Dictionary=launched.preview_launcher(0.0,0.2)
 var release:Dictionary=launched.release_launcher(0.0,0.2)
 old.release_launcher(0.0,0.2);idle.release_launcher(0.0,0.0)
 var start:Vector2=launched.cargo_position()
 check(release.released and float(release.speed)>0.0 and float(release.speed)<=float(launched.route.max_delivery_speed),"real paid launcher gives battery-free cargo capturable velocity")
 check(near(float(launched.telemetry.energy_used),48.0) and near(float(preview.speed),float(release.speed)),"launch preview and release agree and the pad pays 48 J")
 check(near(launched._available_energy(launched.body_for_part(1),1),0.0),"launched cargo really has no connected electrical storage")
 launched.step(DT);old.step(DT)
 check(launched.status=="running" and launched.cargo_position().x>start.x,"v6 battery-free cargo advances under the real integrator")
 check(old.status=="failed" and old.telemetry.free_failure=="usable_energy_empty","same launch retains the old v3 first-tick empty-energy failure")
 for tick in range(600):
  launched.set_free_flight_input(0,0);idle.set_free_flight_input(0,0)
  launched.step(DT);idle.step(DT)
 check(launched.status=="success" and launched.parts[1].delivered and launched.telemetry.delivery_qualified,"battery-free cargo coasts into the actual receiver and qualifies")
 check(launched.cargo_position().distance_to(Vector2(20.0,0.0))<=float(launched.route.delivery_radius)+TOL,"coasting success occurs inside the real receiver geometry")
 check(near(launched.ship_integrity(),1.0) and near(float(launched.telemetry.energy_used),48.0),"coasting preserves undamaged cargo with no hidden recharge or flight bill")
 check(idle.status=="running" and idle.cargo_position()==Vector2.ZERO and near(float(idle.telemetry.energy_used),0.0),"identical bare cargo without a pad remains stationary rather than receiving free movement")
 var gravity=make(ship,{"gravity":2.0});gravity.release_launcher(0.0,0.0)
 for tick in range(120):gravity.step(DT)
 # Godot Vector2 uses single precision; use its built-in vector comparison
 # after 120 integrations rather than the tighter double-precision money test.
 check(gravity.status=="running" and gravity.body_for_part(1).velocity.is_equal_approx(Vector2(0.0,2.0)) and gravity.cargo_position().y>1.0,"empty cargo still follows configured gravity instead of being frozen")
 var rejected=make(ship,receiver,Launcher.starter_launcher());rejected.release_launcher(0.0,0.2);rejected.parts[1].hp=80.0
 for tick in range(600):rejected.step(DT)
 check(rejected.status=="failed" and rejected.telemetry.delivery_failure=="integrity_below_requirement","coasting does not bypass the unchanged minimum-integrity requirement")
 var destroyed=make(ship);destroyed.release_launcher(0.0,0.0);destroyed._damage_part(destroyed.parts[1],100.0,"attack");destroyed.step(DT)
 check(destroyed.status=="failed" and destroyed.telemetry.delivery_failure=="cargo_destroyed","real cargo destruction remains terminal without a battery")
 print("CELL_V6_BARE_CARGO status=",launched.status," elapsed=",launched.elapsed," energy=",launched.telemetry.energy_used," integrity=",launched.ship_integrity()," old_status=",old.status)

func empty_devices()->void:
 var ship:Array=[part(1,"cargo",0),part(2,"battery",-1,0,300.0),part(3,"thruster",0,-1,40.0),part(4,"teleporter",1,0,8.0,{"input_a":-2}),part(5,"shield",0,1,1.5)]
 var sim=make(ship);sim.parts[2].energy=0.0;sim.release_launcher(0.0,0.0)
 var start:Vector2=sim.cargo_position()
 sim.set_free_flight_input(1000,0,true,true,4)
 for tick in range(120):sim.step(DT)
 check(sim.status=="running" and sim.cargo_position()==start and sim.body_for_part(1).velocity==Vector2.ZERO,"held empty thruster plus teleporter input cannot move cargo")
 check(sim.parts[3].pilot_force==Vector2.ZERO and near(float(sim.parts[3].pilot_throttle),0.0),"empty thruster produces zero actual nozzle force and throttle")
 check(int(sim.telemetry.get("free_teleport_count",0))==0 and near(float(sim.telemetry.get("delivery_teleport_energy",0.0)),0.0),"empty teleporter never buys a free displacement")
 sim._damage_part(sim.parts[1],10.0,"attack")
 check(near(float(sim.parts[1].hp),90.0) and near(float(sim.telemetry.energy_used),0.0),"unpowered shield absorbs no attack and creates no payment")
 check(near(float(sim.parts[2].energy),0.0),"repeated unpowered inputs never regenerate a battery")

func proportional_supply()->void:
 var ship:Array=supply_ship();var reversed:Array=ship.duplicate(true);reversed.reverse()
 var sim=make(ship);var reordered=make(reversed);residual_cells(sim);residual_cells(reordered)
 var body:Dictionary=sim.body_for_part(4)
 var ratio:float=sim._consume(body,80.0,4,DT)
 var reverse_ratio:float=reordered._consume(reordered.body_for_part(4),80.0,4,DT)
 check(near(ratio,1.0) and near(reverse_ratio,1.0),"normal _consume pays the full affordable request in both array orders")
 check(near(float(sim.parts[2].energy),80.0) and near(float(sim.parts[3].energy),240.0),"unequal same-circuit residual cells pay in their 1-to-3 available-energy ratio")
 check(near(float(sim.parts[6].energy),500.0) and near(float(sim.telemetry.energy_used),80.0),"disconnected cells are untouched and total supply is billed exactly once")
 var equivalent:bool=true
 for id in [2,3,6]:equivalent=equivalent and near(float(sim.parts[id].energy),float(reordered.parts[id].energy))
 check(equivalent,"reversing blueprint arrays leaves energy identical for every cell ID")
 var second:float=sim._consume(body,30.0,4,DT)
 check(near(second,1.0) and near(float(sim.parts[2].energy),72.5) and near(float(sim.parts[3].energy),217.5),"successive requests preserve proportional residual charge")
 var partial:float=sim._consume(body,400.0,4,DT)
 check(near(partial,0.725) and near(float(sim.parts[2].energy),0.0) and near(float(sim.parts[3].energy),0.0),"oversized request returns the actually affordable fraction without negative cells")
 check(near(float(sim.telemetry.energy_used),400.0) and near(sim._consume(body,10.0,4,DT),0.0),"empty circuit cannot keep paying from unrelated storage")
 var driven=make(supply_ship());var driven_reverse=make(reversed);residual_cells(driven);residual_cells(driven_reverse)
 var driven_start:Vector2=driven.cargo_position()
 driven.release_launcher(0.0,0.0);driven_reverse.release_launcher(0.0,0.0)
 driven.set_free_flight_input(1000,0);driven_reverse.set_free_flight_input(1000,0)
 for tick in range(12):driven.step(DT);driven_reverse.step(DT)
 check(float(driven.telemetry.energy_used)>0.0 and driven.cargo_position().x>driven_start.x,"real held thrust consumes energy through the shared v6 payment hook")
 equivalent=near(float(driven.telemetry.energy_used),float(driven_reverse.telemetry.energy_used))
 for id in [2,3,6]:equivalent=equivalent and near(float(driven.parts[id].energy),float(driven_reverse.parts[id].energy))
 check(equivalent and driven.cargo_position().distance_to(driven_reverse.cargo_position())<TOL,"actual powered ticks preserve per-ID energy and motion under blueprint reversal")

func valve_limits()->void:
 var ship:Array=supply_ship();ship.append(part(5,"valve",0,-2,12.0,{"target":4}))
 var sim=make(ship);residual_cells(sim)
 var ratio:float=sim._consume(sim.body_for_part(4),30.0,4,0.25)
 check(near(ratio,0.1) and near(float(sim.telemetry.energy_used),3.0),"target valve still caps payment at its actual rate times dt")
 check(near(float(sim.parts[2].energy),99.25) and near(float(sim.parts[3].energy),297.75),"valve-limited payment is shared proportionally rather than bypassing the cap")
 sim.parts[5].input_a=999
 check(near(sim._consume(sim.body_for_part(4),10.0,4,0.25),0.0) and near(float(sim.telemetry.energy_used),3.0),"unsignalled closed valve blocks every connected cell")
 sim.parts[5].input_a=-1;sim._cut(4,5)
 check(near(sim._consume(sim.body_for_part(4),10.0,4,0.25),1.0),"detached valve cannot cap a circuit it no longer belongs to even before rebuild")
 var shield_ship:Array=supply_ship("shield");shield_ship.append(part(5,"valve",0,-2,12.0,{"target":4}))
 var shield=make(shield_ship);residual_cells(shield)
 var first:float=shield._consume(shield.body_for_part(4),10.0,4,0.25)
 var next:float=shield._consume(shield.body_for_part(4),10.0,4,0.25)
 check(near(first,0.3) and near(next,0.0) and near(float(shield.telemetry.energy_used),3.0),"inherited shield contacts share one valve budget instead of refilling per hit")
 check(near(float(shield.parts[2].energy),99.25) and near(float(shield.parts[3].energy),297.75),"shield-specific inherited _consume also delegates proportional cell payment")

func cut_circuits()->void:
 var sim=make(supply_ship());residual_cells(sim)
 var stale_body:Dictionary=sim.body_for_part(4);sim._cut(1,3)
 check(sim._graph_dirty and stale_body.parts.has(sim.parts[3]),"boundary fixture retains a stale body immediately after a real socket cut")
 var ratio:float=sim._consume(stale_body,50.0,4,DT)
 check(near(ratio,1.0) and near(float(sim.parts[2].energy),50.0) and near(float(sim.parts[3].energy),300.0),"new payment honors the cut circuit before bodies are rebuilt")
 sim._rebuild_bodies()
 check(sim.body_for_part(3).id!=sim.body_for_part(4).id,"real cut produces independent battery and consumer bodies")
 ratio=sim._consume(sim.body_for_part(4),100.0,4,DT)
 check(near(ratio,0.5) and near(float(sim.parts[2].energy),0.0) and near(float(sim.parts[3].energy),300.0) and near(float(sim.parts[6].energy),500.0),"rebuilt consumer exhausts only its remaining local cell")
 sim.release_launcher(0.0,0.0);sim.set_free_flight_input(1000,0,true);sim.step(DT)
 check(sim.status=="running" and sim.body_for_part(1).velocity==Vector2.ZERO and sim.parts[4].pilot_force==Vector2.ZERO,"empty cargo circuit coasts safely but cannot borrow detached batteries for thrust")

func legacy_payment()->void:
 var sim=make(supply_ship(),{},[],true);residual_cells(sim)
 check(near(sim._consume(sim.body_for_part(4),80.0,4,DT),1.0),"legacy v3 retains the full affordable payment ratio")
 check(near(float(sim.parts[2].energy),20.0) and near(float(sim.parts[3].energy),300.0) and near(float(sim.parts[6].energy),500.0),"legacy v3 preserves its sequential cell payment and detached boundary")
