extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v7.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v7.gd")
const OldSim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const OldProfile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Cells=preload("res://scripts/cell_combinations_v6.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func near(a:float,b:float)->bool:return absf(a-b)<0.0000001
func part(id:int,kind:String,x:int,y:int,param:float,target:int=-1)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-2 if kind in ["splitter","accelerator"] else -1,"input_b":-1,"target":target}
func base()->Dictionary:
 return {"weight":1.2,"distance":95.0,"destination_y":-10.0,"min_delivery_integrity":0.9,"cargo_safe_acceleration":4.0,"cargo_damage_per_excess_mps":3.0,"cargo_contact_damage_scale":2.0}
func ship()->Array:return [part(1,"cargo",0,0,100),part(2,"spring",1,0,60),part(3,"splitter",2,0,0,2),part(4,"battery",2,-1,300)]
func make(design:Array,old:bool=false):
 var sim=OldSim.new() if old else Sim.new()
 sim.configure(design,[],OldProfile.route(base()) if old else Profile.route(base()),42);sim.release_launcher(0,0);return sim
func split(sim)->void:sim._split_module(sim.parts[3],sim.parts[2],sim.body_for_part(3),1.0/120.0)
func state(sim)->PackedByteArray:return var_to_bytes([sim.parts,sim.bodies,sim.links,sim.telemetry,sim.obstacles,sim.route,sim.events,sim.incidents])
func _initialize()->void:
 scaling();parallel_mounts();predictions();isolation();environments();replay()
 print("MATERIAL_MOUNTS_V7 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func scaling()->void:
 for stage in range(3):
  var s=make(ship());var old=make(ship(),true)
  for _n in range(stage):split(s);split(old)
  var f:float=pow(0.5,stage);var mount:Dictionary=s.cargo_mount_properties(s.parts[1]);var previous:Dictionary=old.cargo_mount_properties(old.parts[1])
  var k:float=67.5*f;var response:float=sqrt(3.6/k)
  check(near(mount.elastic_energy,60*f) and near(mount.strength,90*f),"split capacity scales once and already-divided strength is not divided twice stage"+str(stage))
  check(near(mount.stiffness,k) and near(mount.response_seconds,response),"split stiffness and response are derived from actual cargo mass stage"+str(stage))
  check(near(mount.strength/mount.stiffness,90.0/67.5),"working-length approximation keeps nominal maximum displacement stage"+str(stage))
  check(near(previous.elastic_energy,60) and near(previous.stiffness,67.5*f*f),"published v6 retains historical split capacity and stiffness stage"+str(stage))
  var before:PackedByteArray=state(s)
  var preview:Dictionary=s.cargo_pulse_preview(s.parts[1],Vector2(4,0),0.04,mount,s.route,"material_probe")
  check(state(s)==before,"material and pulse preview are read only stage"+str(stage))
  s._pulse_damage(s.parts[1],Vector2(4,0),0.04,"material_probe")
  check(near(s.parts[1].hp/100.0,preview.integrity_after),"same-source material pulse predicts exact immediate HP stage"+str(stage))
  print("MATERIAL_NUMBERS ",JSON.stringify({"fraction":f,"capacity_j":mount.elastic_energy,"strength_n":mount.strength,"stiffness_n_m":mount.stiffness,"response_seconds":mount.response_seconds,"pulse_damage_hp":preview.damage_hp,"old_capacity_j":previous.elastic_energy,"old_response_seconds":previous.response_seconds}))
func parallel_mounts()->void:
 var design:Array=[part(1,"cargo",0,0,100),part(2,"spring",1,0,60),part(3,"spring",-1,0,30)]
 var s=make(design);var mount:Dictionary=s.cargo_mount_properties(s.parts[1])
 check(near(mount.elastic_energy,90) and near(mount.strength,180) and near(mount.stiffness,202.5),"unlike parallel mounts sum individual stiffness not squared summed force")
 var reverse:Array=design.duplicate(true);reverse.reverse();var other=make(reverse)
 check(other.cargo_mount_properties(other.parts[1])==mount,"blueprint array permutation keeps derived mount properties exact")
 var cut:Dictionary=s.cargo_mount_properties(s.parts[1],[1,2])
 check(near(cut.stiffness,67.5) and cut.mounts.size()==1,"postcut component scope cannot borrow another spring")
 s.parts[2].param=0
 check(near(s.cargo_mount_properties(s.parts[1]).stiffness,135),"zero setting has no capacity stiffness or protection")
 s.parts[3].target=2
 check(s.cargo_mount_properties(s.parts[1]).stiffness==0,"mount explicitly targeting another module cannot protect cargo")
func predictions()->void:
 var design:Array=[part(1,"cargo",1,0,100),part(2,"accelerator",0,0,16,1),part(3,"battery",-1,0,300),part(4,"battery",2,0,300),part(5,"damper",1,1,8,1)]
 var s=make(design);var before:PackedByteArray=state(s);var preview:Dictionary=s.preview_accelerator(2)
 check(preview.can_fire and state(s)==before,"v7 live accelerator preview stays read only")
 var workshop:Dictionary=Cells.preview_blueprint(design,Profile.route(base()),2)
 check(workshop.cargo_impacts==preview.cargo_impacts,"v7 workshop dispatch uses actual new material solver")
 s.set_free_flight_input(0,0,false,true,2,false);s.step(1.0/120.0)
 check(near(s.parts[1].hp/100.0,preview.cargo_impacts[0].integrity_after),"v7 actual manual trigger matches shown immediate integrity")
func isolation()->void:
 var s=make(ship());s.parts[2].alive=false
 check(s.cargo_mount_properties(s.parts[1]).mounts.is_empty(),"destroyed mounts do not contribute")
 var d:Array=[part(1,"cargo",0,0,100),part(2,"damper",1,0,8),part(3,"battery",2,0,300)]
 var wired=make(d);wired.parts[2].input_a=3;wired.parts[3].signal=true
 check(wired.cargo_mount_properties(wired.parts[1]).damping==8 and wired.cargo_mount_properties(wired.parts[1],[1,2]).damping==0,"preview cut removes a damper control wire across the cut")
 wired.parts[2].forced_signal=true
 check(wired.cargo_mount_properties(wired.parts[1],[1,2]).damping==8,"actual forced signal remains valid after the cut")
func environments()->void:
 for prefix in ["pilot_delivery","pilot_delivery_ascent","pilot_delivery_rift"]:
  var profile=load("res://scripts/"+prefix+"_profile_v7.gd");var script=load("res://scripts/"+prefix+"_simulation_v7.gd")
  if profile==null or script==null or not profile.can_instantiate() or not script.can_instantiate():
   check(false,"environment scripts compile "+prefix);continue
  var route:Dictionary=profile.route();var saved:Dictionary=route.duplicate(true);var s=script.new();s.configure(ship(),[],route,42)
  check(s.free_route_error.is_empty() and s.telemetry.control_version==profile.VERSION and s.telemetry.material_rules_schema=="parallel-material-v1" and route==saved,"exact material identity and immutable route in "+prefix)
func replay()->void:
 var first=make(ship());var second=make(ship())
 for tick in range(24):
  var active:bool=tick in [0,8]
  first.set_free_flight_input(0,0,false,active,3,false);first.step(1.0/120.0)
  second.set_free_flight_input(0,0,false,active,3,false);second.step(1.0/120.0)
 check(first.parts.size()==6 and first.parts[2].output_factor==0.25 and state(first)==state(second),"two real manual splits and deterministic replay produce exact quarter material state")
