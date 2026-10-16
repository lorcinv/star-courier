extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v3.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Launcher=preload("res://scripts/launcher_v3.gd")
const OldProfile=preload("res://scripts/pilot_free_profile_v2.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,param:float=0.0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func route(extra:Dictionary={})->Dictionary:
 var base:Dictionary={"distance":1000.0,"destination_y":0.0,"weight":1.0,"hazards":[],"pilot_drag":0.0};base.merge(extra,true);return Profile.route(base)
func design()->Array:return [part(1,"cargo",0),part(2,"battery",-1,0,300.0),part(3,"thruster",0,-1,40.0),part(4,"thruster",0,1,40.0)]
func make(extra:Dictionary={},pad:Array=[],ship:Array=[]):
 var s=Sim.new();s.configure(design() if ship.is_empty() else ship,pad,route(extra),42);return s
func settle(s,integrity:float)->void:
 s.parts[1].hp=100.0*integrity;var b:Dictionary=s.body_for_part(1);b.position+=Vector2(float(s.route.distance),float(s.route.destination_y))-s.cargo_position();b.velocity=Vector2.ZERO;b.angular_velocity=0.0;s._check_status();s._refresh_telemetry()
func _initialize()->void:
 profile();launch();transit();cargo();integration()
 print("DELIVERY_PHYSICS_V3 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func profile()->void:
 var r:Dictionary=route();var copy:Dictionary=r.duplicate(true)
 check(not r.is_empty() and Profile.validation_error(r).is_empty(),"v3 route validates with explicit identity")
 check(r.control_version=="pilot-delivery-v3" and r.input_schema=="free-flight-input-v2","v3 identity retains proven seven-field controls")
 check(not OldProfile.validation_error(r).is_empty(),"old profile rejects v3 identity")
 check(Profile.validation_error(r).is_empty() and r==copy,"compatibility validation never mutates source")
 var bad:Dictionary=r.duplicate(true);bad.min_delivery_integrity=90.0
 check(not Profile.validation_error(bad).is_empty(),"percent-versus-fraction mismatch rejected")
 bad=r.duplicate(true);bad.cargo_safe_acceleration=NAN
 check(not Profile.validation_error(bad).is_empty(),"nonfinite cargo physics rejected")
 check(Profile.route(r).is_empty() and Profile.route({"contract_id":"old"}).is_empty(),"committed or previously stamped identities cannot be reauthored")
func launch()->void:
 var s=make({},Launcher.starter_launcher());var at:Vector2=s.cargo_position()
 check(s.status=="running" and not s.launch_released and s.body_for_part(1).velocity==Vector2.ZERO,"configure prepares without an invisible launch")
 s.step(0.5)
 check(s.elapsed==0.0 and s.cargo_position()==at and s.telemetry.energy_used==0.0,"pre-release time and energy are frozen")
 var preview:Dictionary=s.preview_launcher(45.0,1.0)
 check(absf(float(preview.energy_used)-240.0)<0.00001 and absf(float(preview.available_energy)-6000.0)<0.00001,"four real spring capacities sum to240J within the shared6000J cell")
 check(absf(float(preview.speed)-sqrt(480.0/float(preview.mass)))<0.00001,"preview speed equals sqrt2EoverM")
 check(preview.velocity.x>0.0 and preview.velocity.y<0.0 and absf(preview.velocity.x+preview.velocity.y)<0.00001,"45degrees aims upward and right")
 check(s.telemetry.energy_used==0.0 and s.body_for_part(1).velocity==Vector2.ZERO,"preview is read only")
 var released:Dictionary=s.release_launcher(45.0,1.0);var velocity:Vector2=s.body_for_part(1).velocity;var energy:float=s.telemetry.energy_used
 check(released.released and velocity.distance_to(preview.velocity)<0.00001 and absf(energy-240.0)<0.00001,"actual release matches the preview and pays once")
 s.release_launcher(0.0,1.0)
 check(s.body_for_part(1).velocity==velocity and s.telemetry.energy_used==energy,"duplicate release cannot add a second impulse or bill")
 var reordered:Array=Launcher.starter_launcher();reordered.reverse();var same=make({},reordered)
 check(absf(float(same.preview_launcher(45,1).speed)-float(preview.speed))<0.00001,"pad array reversal leaves computed speed unchanged")
 same.release_launcher(45,1)
 check(same.body_for_part(1).velocity.distance_to(velocity)<0.00001,"pad array reversal leaves actual release unchanged")
 for angle in [0.0,90.0]:
  var probe=make({},Launcher.starter_launcher());probe.release_launcher(angle,1.0);var v:Vector2=probe.body_for_part(1).velocity
  check((v.x>0.0 and absf(v.y)<0.00001) if angle==0.0 else (v.y<0.0 and absf(v.x)<0.00001),"launch angle axis "+str(angle))
 var heavy=make({"weight":6.0},Launcher.starter_launcher());var low=make({},Launcher.starter_launcher())
 check(float(heavy.preview_launcher().speed)<float(low.preview_launcher().speed),"same finite energy launches heavier real mass slower")
 check(absf(pow(float(low.preview_launcher(0,0.25).speed),2.0)/pow(float(low.preview_launcher().speed),2.0)-0.25)<0.00001,"quarter energy yields half launch speed")
 var weak_pad:Array=[part(1001,"spring",0,0,60),part(1002,"spring",0,1,60),part(1003,"battery",-1,0,300),part(1004,"beam",1,0,32)]
 var weak=make({},weak_pad);var weak_p:Dictionary=weak.preview_launcher()
 weak_pad.append(part(1005,"beam",1,1,32));var supported=make({},weak_pad)
 check(weak_p.support_limited and float(supported.preview_launcher().energy_used)>float(weak_p.energy_used),"adding connected support removes an actual work bottleneck")
 var energy_pad:Array=[part(1001,"accelerator",0,0,20),part(1002,"accelerator",0,1,20),part(1003,"battery",-1,0,300),part(1004,"armor",1,0,150),part(1005,"armor",1,1,150)]
 var one_cell=make({},energy_pad);energy_pad.append(part(1006,"battery",-1,1,300));var two_cells=make({},energy_pad)
 # Explicit residual-energy fixture: each cell has300J left, capacity remains6000.
 # A full first-chapter bank is not energy-limited; adding cells there adds no work.
 for p in one_cell.launcher_parts:
  if p.type=="battery":p.energy=300.0
 for p in two_cells.launcher_parts:
  if p.type=="battery":p.energy=300.0
 check(one_cell.preview_launcher().energy_limited and float(two_cells.preview_launcher().energy_used)>float(one_cell.preview_launcher().energy_used),"adding a cell only helps a real finite remaining-energy bottleneck")
 var shared_capacity:float=0.0
 for p in low.launcher_parts:
  if p.type=="battery":shared_capacity=float(p.capacity)
 check(shared_capacity==float(low.parts[2].capacity),"the same cell has identical ship and launcher capacity")
 check(not low.preview_launcher(91,1).can_release and not low.preview_launcher(45,INF).can_release,"out of range or nonfinite controls rejected")
func transit()->void:
 var ship:Array=design();ship.append(part(9,"teleporter",1,0,8.0,{"input_a":-2}))
 var light=make({},[],ship);var heavy=make({"weight":6.0},[],ship)
 light.release_launcher(0,0);heavy.release_launcher(0,0)
 var lb:Dictionary=light.body_for_part(9);var hb:Dictionary=heavy.body_for_part(9)
 var cost:float=light.teleport_energy_cost(lb,8.0)
 check(absf(cost-float(lb.mass)*8.0*6.0)<0.00001 and heavy.teleport_energy_cost(hb,8)>cost,"teleport pays every carried kilogram times distance")
 check(absf(light.teleport_energy_cost(lb,16)-2.0*cost)<0.00001,"doubling teleport distance doubles cost")
 lb.velocity=Vector2(2,-3);lb.angular_velocity=0.25;var before:Vector2=lb.position;var momentum:Vector2=light.total_momentum()
 light._act(light.parts[9],lb,1.0/120.0,true)
 check(absf(float(light.telemetry.energy_used)-cost)<0.00001 and lb.position.distance_to(before+Vector2(8,0))<0.00001,"successful transit deducts the exact massdistance cost")
 check(light.total_momentum()==momentum and lb.angular_velocity==0.25,"teleport preserves linear and angular momentum")
 var blocked=make({},[],ship);blocked.release_launcher(0,0);var b:Dictionary=blocked.body_for_part(9);var start:Vector2=b.position
 blocked.obstacles.append({"type":"rock","position":blocked.part_world_position(1)+Vector2(8,0),"velocity":Vector2.ZERO,"radius":2.0,"health":1000.0,"mass":1000.0})
 blocked._act(blocked.parts[9],b,1.0/120.0,true)
 check(b.position==start and blocked.telemetry.energy_used==0.0,"blocked exit neither moves nor bills")
 var poor=make({},[],ship);poor.release_launcher(0,0);poor.parts[2].energy=cost-1.0;var pb:Dictionary=poor.body_for_part(9);var pos:Vector2=pb.position
 poor._act(poor.parts[9],pb,1.0/120.0,true)
 check(pb.position==pos and poor.parts[2].energy==cost-1.0,"insufficient energy cannot buy a partial or free teleport")
func cargo()->void:
 var r:Dictionary={"min_delivery_integrity":0.9,"cargo_safe_acceleration":4.0,"cargo_damage_per_excess_mps":3.0,"cargo_contact_damage_scale":2.0}
 var invalid=make(r);invalid.release_launcher(0,0);settle(invalid,0.70)
 check(invalid.status=="failed" and invalid.telemetry.delivery_failure=="integrity_below_requirement","inside receiver at70percent fails90percent contract")
 var threshold=make(r);threshold.release_launcher(0,0);settle(threshold,0.90)
 check(threshold.status=="success" and threshold.telemetry.delivery_qualified,"exact required integrity is accepted")
 var bare=make(r,Launcher.starter_launcher());bare.release_launcher(0,1)
 var gentle=make(r,Launcher.starter_launcher());gentle.release_launcher(0,0.2)
 check(gentle.ship_integrity()>bare.ship_integrity() and gentle.ship_integrity()>=0.9,"gentle launch protects fragile cargo with no required part")
 var cushioned_ship:Array=design();cushioned_ship.append(part(10,"spring",1,0,60.0,{"target":1}));var cushioned=make(r,Launcher.starter_launcher(),cushioned_ship);cushioned.release_launcher(0,1)
 check(cushioned.ship_integrity()>bare.ship_integrity(),"real connected spring energy and stiffness spread launch loading")
 var zero_ship:Array=design();zero_ship.append(part(10,"spring",1,0,0.0,{"target":1}));var zero=make(r,[],zero_ship)
 check(zero.cargo_mount_properties(zero.parts[1]).response_seconds==0.0,"zero energy spring is not a named protection key")
 cushioned._cut(1,10);cushioned._rebuild_bodies()
 check(cushioned.cargo_mount_properties(cushioned.parts[1]).response_seconds==0.0,"cut mount loses cargo protection")
 var damper_ship:Array=design();damper_ship.append(part(10,"damper",1,0,5.0,{"target":1}));var buffered=make(r,[],damper_ship);var raw=make(r)
 buffered._pulse_damage(buffered.parts[1],Vector2(4,0),0.04,"test_contact");raw._pulse_damage(raw.parts[1],Vector2(4,0),0.04,"test_contact")
 check(buffered.ship_integrity()>raw.ship_integrity() and buffered.ship_integrity()<1.0,"damper setting reduces actual impulse damage without immunity")
 buffered._pulse_damage(buffered.parts[1],Vector2(1000,0),0.04,"test_contact")
 check(buffered.ship_integrity()==0.0,"finite protection cannot save arbitrarily violent impact")
 var passive_ship:Array=design();passive_ship.append(part(10,"spring",1,0,60.0,{"target":1,"input_a":-2}))
 var passive=make(r,[],passive_ship);passive.release_launcher(0,0);var links_before:int=passive.links.size();var battery_before:float=passive.parts[2].energy
 for i in range(120):passive.set_free_flight_input(0,0,false,true,10);passive.step(1.0/120.0)
 check(passive.parts[2].energy==battery_before and passive.parts[10].stored_energy==0.0,"passive ship spring never secretly charges from battery")
 check(passive.links.size()==links_before and passive.body_for_part(1).id==passive.body_for_part(10).id and not 10 in passive.selectable_device_ids(),"passive spring cannot become a cockpit ejection device")
 var just_below=make(r);just_below.release_launcher(0,0);settle(just_below,0.8999999)
 check(just_below.status=="failed" and not just_below.telemetry.integrity_meets_requirement,"threshold uses the same strict comparison as UI and settlement")
 var drag=make({"pilot_drag":0.1});drag.release_launcher(0,0);drag.body_for_part(1).velocity=Vector2(5,0);drag.step(1.0/120.0)
 check(drag.telemetry.cargo_contact_impulse==0.0,"environmental drag is not mislabeled a contact impulse")
 var collision=make(r);collision.release_launcher(0,0);collision.body_for_part(1).velocity=Vector2(4,0)
 collision.obstacles.append({"type":"rock","position":collision.part_world_position(1)+Vector2(3,0),"velocity":Vector2.ZERO,"radius":0.6,"health":10000.0,"mass":10000.0,"cooldown":1.0})
 for i in range(90):collision.step(1.0/120.0)
 check(collision.telemetry.cargo_contact_impulse>0.0 and collision.ship_integrity()<1.0,"real resolved collision transmits measured impulse and damage to cargo")
 var accelerating=make(r);accelerating.release_launcher(0,0)
 for i in range(120):accelerating.set_free_flight_input(1000,0,true);accelerating.step(1.0/120.0)
 check(accelerating.ship_integrity()<1.0 and accelerating.telemetry.cargo_peak_acceleration>4.0,"sustained real propulsion acceleration damages fragile cargo")
func integration()->void:
 var r:Dictionary={"distance":30.0,"destination_y":0.0,"delivery_radius":2.0,"max_delivery_speed":9.0,"min_delivery_integrity":0.85}
 var launched=make(r,Launcher.starter_launcher());var idle=make(r)
 launched.release_launcher(0,1);idle.release_launcher(0,0)
 for i in range(720):
  launched.set_free_flight_input(0,0);idle.set_free_flight_input(0,0)
  launched.step(1.0/120.0);idle.step(1.0/120.0)
 check(launched.status=="success" and idle.status=="running" and idle.cargo_position().length()<2.0,"real30m receiver: paid launch delivers while identical unpowered craft stays behind")
 print("DELIVERY_V3_RECEIVER_COUNTERFACTUAL launched_status=",launched.status," elapsed=",launched.elapsed," cost=",launched.telemetry.energy_used," no_pad_x=",idle.cargo_position().x)
