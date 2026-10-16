extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Helper=preload("res://scripts/cell_combinations_v6.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func pod(damping:float=8)->Array:
 return [part(1,"cargo",1,0,100),part(2,"accelerator",0,0,16,{"input_a":-2,"target":1}),part(3,"battery",-1,0,300),part(4,"battery",2,0,300),part(5,"thruster",2,-1,28),part(6,"thruster",2,1,28),part(7,"damper",1,1,damping,{"target":1})]
func make(design:Array):
 var s=Sim.new();s.configure(design,[],Chapter.fresh_route(3),42);s.release_launcher(0,0);return s
func state(s)->Dictionary:
 return {"parts":s.parts.duplicate(true),"links":s.links.duplicate(true),"bodies":s.bodies.duplicate(true),"telemetry":s.telemetry.duplicate(true),"obstacles":s.obstacles.duplicate(true),"route":s.route.duplicate(true),"events":s.events.duplicate(true),"incidents":s.incidents.duplicate(true)}
func actual(s)->void:s._accelerate(s.parts[2],s._target(s.parts[2],s.body_for_part(2)),s.body_for_part(2),1.0/120.0)
func compare_instant(s,preview:Dictionary,label:String)->void:
 var energy:float=s.telemetry.energy_used;var ammo:float=s.telemetry.ammo_cost
 actual(s)
 for impact in preview.cargo_impacts:
  var cargo:Dictionary=s.parts[impact.cargo_id]
  var integrity:float=clampf(float(cargo.hp)/float(cargo.max_hp),0.0,1.0)
  check(absf(integrity-float(impact.integrity_after))<0.00000001,label+" same-function instantaneous cargo HP matches")
  check(impact.source=="accelerator_pulse" and impact.meets_requirement_after==(integrity>=float(s.route.min_delivery_integrity)),label+" exact source and minimum predicate match")
 check(absf(float(s.telemetry.energy_used)-energy-float(preview.energy_required))<0.000001 and absf(float(s.telemetry.ammo_cost)-ammo-float(preview.ammo_cost))<0.000001,label+" this-shot energy and ammo match without final-cost promise")
func _initialize()->void:
 buffered();two_cargo_and_spin();cut_and_invalid();recompute();ammo();pure_math()
 print("ACCELERATOR_PULSE_PREVIEW_V6 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func buffered()->void:
 for value in [8.0,0.0]:
  var s=make(pod(value));var before:Dictionary=state(s);var preview:Dictionary=s.preview_accelerator(2)
  check(state(s)==before,"preview has no world/circuit/energy/event mutations damping"+str(value))
  check(preview.can_fire and preview.cargo_impacts.size()==1 and preview.cargo_impacts[0].side=="payload","payload impact covers actual cargo")
  check(preview.cargo_impacts[0].meets_requirement_after==(value>0.0),"buffer8 qualifies and same-mass buffer0 warns below threshold without blocking fire")
  compare_instant(s,preview,"buffer "+str(value))
 var manual=make(pod(8));var predicted:Dictionary=manual.preview_accelerator(2)
 manual.set_free_flight_input(0,0,false,true,2,false);manual.step(1.0/120.0)
 check(absf(float(manual.parts[1].hp)/100.0-float(predicted.cargo_impacts[0].integrity_after))<0.00000001,"real manual first fixed tick matches this-pulse preview")
func two_cargo_and_spin()->void:
 var ship:Array=pod(8);ship.append(part(8,"cargo",-1,-1,100))
 var s=make(ship);var body:Dictionary=s.body_for_part(1);body.velocity=Vector2(3,-1);body.angular_velocity=0.25
 var preview:Dictionary=s.preview_accelerator(2)
 check(preview.can_fire and preview.cargo_impacts.size()==2 and preview.cargo_impacts[0].side=="carrier" and preview.cargo_impacts[1].side=="payload","both sides of eccentric spinning two-cargo split are predicted")
 check(preview.carrier_delta_v.length()>0 and preview.payload_delta_v.length()>0 and absf(preview.payload_angular_delta)>0,"carrier recoil payload delta-v and spin changes are exposed")
 compare_instant(s,preview,"two cargo")
func cut_and_invalid()->void:
 var ship:Array=pod(8)
 for p in ship:
  if p.id==7:p.input_a=3
 var s=make(ship);s.parts[3].signal=true
 check(s.cargo_mount_properties(s.parts[1]).response_seconds>0,"precut wired damper is genuinely enabled")
 var preview:Dictionary=s.preview_accelerator(2)
 check(preview.can_fire and preview.cargo_impacts[0].mount_response_seconds==0,"postcut preview cannot borrow damper wire across detached carrier")
 compare_instant(s,preview,"wire cut")
 var blocked=make(pod());blocked.parts[3].energy=0;blocked.parts[4].energy=0
 var before:Dictionary=state(blocked);var no_power:Dictionary=blocked.preview_accelerator(2)
 check(not no_power.can_fire and no_power.cargo_impacts.is_empty() and no_power.ammo_cost==0 and state(blocked)==before,"insufficient energy reports no actual pulse or charge")
 var bypass:Array=pod();bypass.append(part(9,"beam",0,1,32))
 var b=make(bypass);var no_split:Dictionary=b.preview_accelerator(2)
 check(not no_split.can_fire and no_split.reason=="bypass_connection" and no_split.cargo_impacts.is_empty(),"bypass has no hypothetical HP display")
 var obstacle=make(pod());obstacle.obstacles.append({"type":"rock","position":obstacle.cargo_position()+Vector2(1,0),"radius":0.7,"health":100,"velocity":Vector2.ZERO})
 var no_exit:Dictionary=obstacle.preview_accelerator(2)
 check(not no_exit.can_fire and no_exit.reason=="exit_blocked" and no_exit.cargo_impacts.is_empty() and no_exit.ammo_cost==0,"blocked exit has no predicted actual damage or ammo")
func recompute()->void:
 var s=make(pod());var first:Dictionary=s.preview_accelerator(2);s.parts[2].param=8
 var slower:Dictionary=s.preview_accelerator(2)
 check(slower.energy_required<first.energy_required and slower.cargo_impacts[0].integrity_after>first.cargo_impacts[0].integrity_after,"changing strength immediately recomputes energy and pulse damage")
 s.parts[7].param=0;var zero:Dictionary=s.preview_accelerator(2)
 check(zero.cargo_impacts[0].mount_response_seconds==0,"changing mount setting immediately recomputes response")
 s.parts[3].energy=0;s.parts[4].energy=0
 check(not s.preview_accelerator(2).can_fire,"changing actual charge invalidates current trigger")
 var first_blueprint:Dictionary=Helper.preview_blueprint(pod(),Chapter.fresh_route(3),2)
 check(first_blueprint.cargo_impacts.size()==1 and first_blueprint.cargo_impacts[0].integrity_after==first.cargo_impacts[0].integrity_after,"workshop and live simulation share same immutable instantaneous result")
func ammo()->void:
 var ship:Array=[part(1,"cargo",0,0,100),part(2,"accelerator",-1,0,20,{"rot":2,"target":4,"input_a":-2}),part(3,"battery",1,0,300),part(4,"armor",-2,0,150),part(7,"damper",0,1,8,{"target":1}),part(8,"beam",-3,0,32),part(10,"beam",-4,0,32)]
 var s=make(ship);var preview:Dictionary=s.preview_accelerator(2)
 check(preview.can_fire and preview.ammo_part_ids==[4,8,10] and preview.ammo_cost==45 and preview.cargo_impacts[0].side=="carrier","actual three noncargo payload modules produce45face-value ammo and carrier impact")
 compare_instant(s,preview,"ammo group")
 check(not preview.has("total_cost") and not preview.has("lost_cost") and not preview.has("repair_cost"),"preview never guarantees unknown future losses repair or final bill")
func pure_math()->void:
 var s=make(pod());var cargo:Dictionary=s.parts[1];var mount:Dictionary=s.cargo_mount_properties(cargo);var saved:Dictionary=cargo.duplicate(true)
 var pulse:Dictionary=s.cargo_pulse_preview(cargo,Vector2(0.0001,0),0.125,mount,s.route)
 check(pulse.damage_hp==0 and pulse.integrity_after==1.0 and cargo==saved,"pure pulse keeps legacy small-delta no-damage rule without mutation")
