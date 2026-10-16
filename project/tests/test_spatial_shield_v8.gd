extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Legacy=preload("res://scripts/pilot_delivery_simulation_v7.gd")
const Shield=preload("res://scripts/spatial_shield_v1.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func near(a:float,b:float)->bool:return absf(a-b)<0.00001
func part(id:int,kind:String,x:int,y:int=0,param:float=0.0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func ship(second:String="")->Array:
 var result:Array=[part(1,"cargo",0,0,100),part(2,"shield",1,0,1.5),part(3,"beam",2,0,32),part(4,"beam",3,0,32),part(5,"armor",4,0,150),part(6,"battery",1,1,300)]
 if second=="separate":result.append(part(7,"shield",4,1,1.5))
 if second=="overlap":result.append(part(7,"shield",0,1,1.5))
 return result
func make(design:Array,old:bool=false):
 var s=Legacy.new() if old else Sim.new();var r:Dictionary=Profile.route({"weight":1.2,"cargo_safe_acceleration":4.0,"cargo_damage_per_excess_mps":3.0,"cargo_contact_damage_scale":2.0})
 s.configure(design,[],Profile.compatibility_route(r) if old else r,42);s.release_launcher(0,0);return s
func bytes(s)->PackedByteArray:return var_to_bytes([s.parts,s.bodies,s.links,s.telemetry,s.events,s.incidents,s._shield_spent,s._shield_valve_spent])
func hit(s,id:int,amount:float=12.0,source:String="attack")->void:s._damage_part(s.parts[id],amount,source)
func _initialize()->void:
 spatial();overlap();supply();transform_and_split();damage_paths();environments()
 print("SPATIAL_SHIELD_V8 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func spatial()->void:
 var s=make(ship());var before:PackedByteArray=bytes(s);var view:Dictionary=s.shield_coverage_snapshot()
 check(bytes(s)==before,"coverage snapshot mutates no world energy budget or incidents")
 check(view.protected_ids.has(1) and not view.protected_ids.has(5) and view.generators[0].radius_m==1.5,"one local shield covers near cargo but not distant same-circuit armor")
 hit(s,1);hit(s,5)
 check(s.parts[1].hp==100 and s.parts[5].hp==138 and near(s.telemetry.energy_used,18),"same local shield protects near hit only and pays18J")
 var moved:Array=ship();moved[1].x=3;moved[3].x=1
 var other=make(moved);hit(other,1);hit(other,5)
 check(other.parts[1].hp==88 and other.parts[5].hp==150 and near(other.telemetry.energy_used,18),"moving one identical shield swaps protected end without changing cost")
 var dual=make(ship("separate"));hit(dual,1);hit(dual,5)
 check(dual.parts[1].hp==100 and dual.parts[5].hp==150 and near(dual.telemetry.energy_used,36),"separate second shield adds real distant coverage at actual36J work")
 var old=make(ship(),true);hit(old,5)
 check(old.parts[5].hp==150 and near(old.telemetry.energy_used,18),"published v7 retains old whole-circuit remote protection")
 var blueprint:Dictionary=Shield.preview_blueprint(ship(),Profile.route({"weight":1.2}),2)
 check(blueprint.protected_ids==view.protected_ids and blueprint.generators[0].world_position==view.generators[0].world_position,"workshop uses same actual world geometry and protected centers as live")
 print("SHIELD_SPACE ",JSON.stringify({"near":[s.parts[1].hp,s.parts[5].hp,s.telemetry.energy_used],"moved":[other.parts[1].hp,other.parts[5].hp,other.telemetry.energy_used],"separate":[dual.parts[1].hp,dual.parts[5].hp,dual.telemetry.energy_used],"legacy_far":[old.parts[5].hp,old.telemetry.energy_used]}))
func overlap()->void:
 var a=make(ship("overlap"));hit(a,1)
 check(a.parts[1].hp==100 and near(a.telemetry.energy_used,18),"overlapping attack circles never pay twice for the same12HP")
 var design:Array=ship("overlap");design.reverse();var b=make(design);b.body_for_part(1).parts.reverse();hit(b,1)
 check(near(b.telemetry.energy_used,a.telemetry.energy_used) and near(b.parts[6].energy,a.parts[6].energy) and b.parts[1].hp==a.parts[1].hp,"blueprint and live body-array permutation leave attack billing unchanged")
 var collision_design:Array=ship("separate");collision_design[1].x=3;collision_design[3].x=1
 var c=make(collision_design);hit(c,5,100,"collision")
 check(near(c.parts[5].hp,98) and near(c.telemetry.impact_absorbed,48) and near(c.telemetry.energy_used,72),"two local collision shields retain24HP each and1.5J per HP budget")
 var spent:float=c.telemetry.energy_used;hit(c,5,1,"collision")
 check(near(c.parts[5].hp,97) and near(c.telemetry.energy_used,spent),"same-tick repeated collision cannot reset per-generator budget")
 var reverse:Array=collision_design.duplicate(true);reverse.reverse();var d=make(reverse);d.body_for_part(5).parts.reverse();hit(d,5,100,"collision");hit(d,5,1,"collision")
 check(d._shield_spent==c._shield_spent and near(d.telemetry.energy_used,c.telemetry.energy_used) and d.parts[5].hp==c.parts[5].hp,"stable shield id order preserves collision budget and charge under permutation")
func supply()->void:
 var empty=make(ship());empty.parts[6].energy=0;var view:Dictionary=empty.shield_coverage_snapshot()
 check(view.generators[0].candidate_ids.has(1) and view.protected_ids.is_empty() and not view.generators[0].active,"empty supply leaves geometric candidates but no active protection")
 hit(empty,1);check(empty.parts[1].hp==88 and empty.telemetry.energy_used==0,"empty shield does not produce free absorption")
 var partial=make(ship());partial.parts[6].energy=9
 check(partial.shield_coverage_snapshot().generators[0].active,"partial power is displayed as available rather than requiring full hit funding")
 hit(partial,1);check(near(partial.parts[1].hp,94) and near(partial.telemetry.energy_used,9),"partial9J absorbs6HP and applies residual6HP exactly once")
 var disabled=make(ship());disabled.parts[2].input_a=3;disabled.parts[3].signal=false
 check(disabled.shield_coverage_snapshot().generators[0].reason=="disabled","disabled input is visible in coverage snapshot")
 hit(disabled,1);check(disabled.parts[1].hp==88 and disabled.telemetry.energy_used==0,"disabled generator cannot protect even when powered")
 var cut=make(ship());cut._cut(1,2)
 check(cut._graph_dirty and not cut.shield_coverage_snapshot().protected_ids.has(1),"dirty cut removes protection before body rebuild")
 hit(cut,1);check(cut.parts[1].hp==88 and cut.telemetry.energy_used==0,"cut body cannot borrow nearby shield or battery")
 var valve_design:Array=ship();valve_design.append(part(8,"valve",1,2,120,{"target":2}))
 var valve=make(valve_design);hit(valve,1);hit(valve,1)
 check(near(valve.telemetry.energy_used,1) and near(valve.parts[1].hp,100-24+1.0/1.5),"attack contacts share existing valve1J fixed-tick budget")
 check(not valve.shield_coverage_snapshot().generators[0].active,"snapshot consumes no budget and reports exhausted valve current tick")
func transform_and_split()->void:
 var s=make(ship());var original:Dictionary=s.shield_coverage_snapshot();var body:Dictionary=s.body_for_part(1);body.position+=Vector2(37,-22);body.angle=1.1
 var rotated:Dictionary=s.shield_coverage_snapshot()
 check(rotated.protected_ids==original.protected_ids and rotated.generators[0].world_position!=original.generators[0].world_position,"translation and rotation preserve coverage IDs and move actual centers")
 s.parts[2].scale=0.2;s.parts[2].hp=1
 check(s.shield_coverage_snapshot().generators[0].radius_m==1.5,"visual shrink and damage do not secretly reduce protection radius")
 var design:Array=[part(1,"cargo",0,0,100),part(2,"shield",1,0,1.5),part(3,"splitter",2,0,0,{"target":2,"input_a":-2}),part(4,"battery",2,1,300),part(5,"beam",0,1,32),part(6,"beam",1,1,32)]
 var split=make(design)
 for stage in range(3):
  if stage>0:split._split_module(split.parts[3],split.parts[2],split.body_for_part(3),1.0/120.0)
  var view:Dictionary=split.shield_coverage_snapshot(2);var expected:float=1.5*sqrt(pow(0.5,stage))
  check(near(view.generators[0].radius_m,expected),"real split radius follows square-root material area stage"+str(stage))
  check(view.protected_ids.has(1)==(stage<2) and view.protected_ids.has(5)==(stage==0),"center at1m and diagonal atsqrt2 leave actual half and quarter coverage stage"+str(stage))
 check(near(split.telemetry.energy_used,20),"radius updates do not add charges beyond real two10J splits")
 var edge=make(ship());edge.parts[1].local_pos=edge.parts[2].local_pos+Vector2(1.5,0)
 check(Shield.covers(edge,edge.parts[2],edge.parts[1]),"part center exactly on1.5m boundary is covered")
 edge.parts[1].local_pos.x+=0.0001
 check(not Shield.covers(edge,edge.parts[2],edge.parts[1]),"part edge overlapping bubble does not protect a center outside radius")
func damage_paths()->void:
 var far=make(ship());hit(far,5,100,"collision")
 check(far.parts[5].hp==50 and far.telemetry.energy_used==0 and float(far.telemetry.impact_absorbed)==0,"far collision cannot fall through to inherited full-body shield")
 var design:Array=ship();design.append(part(7,"damper",0,1,8,{"target":1}))
 var cargo=make(design);var mount:Dictionary=cargo.cargo_mount_properties(cargo.parts[1]);var scaled:float=100*float(cargo.route.cargo_contact_damage_scale)*pow(.04/(.04+float(mount.response_seconds)),2)
 hit(cargo,1,100,"collision")
 var absorbed:float=minf(scaled*.65,24)
 check(near(cargo.parts[1].hp,100-scaled+absorbed) and near(cargo.telemetry.energy_used,absorbed*1.5),"cargo direct-collision mount scaling occurs exactly once before preserved shield fraction")
 var load=make(ship());hit(load,1,12,"cargo_acceleration")
 check(load.parts[1].hp==88 and load.telemetry.energy_used==0,"cargo load remains unshielded")
 var destroyed=make(ship());hit(destroyed,5,200);hit(destroyed,5,200)
 check(not destroyed.parts[5].alive and destroyed.incidents.size()==1 and near(destroyed.telemetry.lost_cost,25) and near(destroyed.telemetry.destroyed_mass,1.4),"residual destruction and incident/replacement are recorded only once")
func environments()->void:
 for prefix in ["pilot_delivery","pilot_delivery_ascent","pilot_delivery_rift"]:
  var profile=load("res://scripts/"+prefix+"_profile_v8.gd");var script=load("res://scripts/"+prefix+"_simulation_v8.gd")
  if profile==null or script==null or not profile.can_instantiate() or not script.can_instantiate():check(false,"v8 scripts compile "+prefix);continue
  var s=script.new();var route:Dictionary=profile.route();var original:Dictionary=route.duplicate(true);s.configure(ship(),[],route,42)
  check(s.free_route_error.is_empty() and s.telemetry.control_version==profile.VERSION and route==original,"immutable exact v8 route and solver identity "+prefix)
  hit(s,5);check(s.parts[5].hp==138 and s.telemetry.energy_used==0,"same spatial attack rule in "+prefix)
