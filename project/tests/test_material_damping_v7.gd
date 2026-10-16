extends SceneTree
## Focused v7 material and passive damping equations. Split factors come only
## from the real _split_module path. Inertia overrides below isolate Ctheta/I;
## resource and two-body checks use the actual configured simulation data.
## Abstract despin has no modelled reaction torque: no closed-system angular
## momentum claim is made or tested here.
const Sim=preload("res://scripts/pilot_delivery_simulation_v7.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v7.gd")
const Materials=preload("res://scripts/material_response_v1.gd")
const DT:float=1.0/120.0
const TOL:float=0.000001
const VECTOR_TOL:float=0.00002
var passed:int=0
var failed:int=0

func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func near(a:float,b:float,tolerance:float=TOL)->bool:return absf(a-b)<=tolerance

func part(id:int,kind:String,x:int,y:int=0,param:float=0.0,target:int=-1)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-2 if kind=="splitter" else -1,"input_b":-1,"target":target}

func route()->Dictionary:
 # Use a fresh source, never relabel an already committed older route.
 return Profile.route({"distance":1000.0,"destination_y":0.0,"delivery_radius":1.0,"max_delivery_speed":8.0,"weight":1.0,"hazards":[],"gravity":0.0,"wind":[0.0,0.0],"pilot_drag":0.0,"min_delivery_integrity":0.85})

func make(kind:String="damper",remote:bool=false):
 var ship:Array=[part(1,"cargo",0),part(2,kind,1,0,8.0 if kind=="damper" else 300.0,5 if remote else 1),part(3,"splitter",2,0,0.0,2),part(4,"battery",2,-1,300.0)]
 if remote:ship.append(part(5,"beam",4))
 var sim=Sim.new();sim.configure(ship,[],route(),42)
 return sim

func totals(sim)->Dictionary:
 var result:Dictionary={"mass":0.0,"hp":0.0,"max_hp":0.0,"price":0.0,"capacity":0.0,"energy":0.0,"stored_energy":0.0,"strength":0.0,"output_factor":0.0,"cargo_count":0}
 for p in sim.parts.values():
  for key in ["mass","hp","max_hp","price","capacity","energy","stored_energy","strength","output_factor"]:result[key]+=float(p[key])
  if p.type=="cargo":result.cargo_count+=1
 return result

func split_target(sim)->void:
 # Reset only motion from isolated equation fixtures before the real rebuild.
 for body in sim.bodies:body.velocity=Vector2.ZERO;body.angular_velocity=0.0
 sim._split_module(sim.parts[3],sim.parts[2],sim.body_for_part(3),DT)

func _initialize()->void:
 var configured=make()
 check(configured.status=="running" and configured.route.control_version==Profile.VERSION and Profile.validation_error(configured.route).is_empty(),"fresh Profile.route configures the real v7 solver")
 check(near(float(configured.route.damper_reference_mass_kg),1.0) and near(float(configured.route.damper_reference_inertia_kg_m2),1.0),"route freezes Mref=1 kg and Iref=1 kg m2")
 angular_material_scaling()
 relative_damping()
 split_resource_conservation()
 cargo_split_refused()
 fixed_tick_dispatch()
 print("MATERIAL_DAMPING_V7 passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)

func angular_material_scaling()->void:
 var sim=make()
 for stage in range(3):
  if stage>0:split_target(sim)
  var label:String=["whole","half","quarter"][stage]
  var expected:float=8.0/pow(2.0,stage)
  var p:Dictionary=sim.parts[2]
  var properties:Dictionary=Materials.material_properties(p,sim.route)
  check(near(float(p.output_factor),1.0/pow(2.0,stage)) and near(float(p.param),8.0),label+" material fraction comes from real splitting with unchanged knob")
  check(near(float(properties.damper_linear_coefficient),expected) and near(float(properties.damper_angular_coefficient),expected),label+" physical coefficients are "+str(expected)+", with no mass double scaling")
  var mount:Dictionary=sim.cargo_mount_properties(sim.parts[1])
  check(near(float(mount.damping),expected),label+" attached cargo response reads the same scaled material")
  var aggregate:float=0.0
  for q in sim.parts.values():
   if q.type=="damper":aggregate+=float(Materials.material_properties(q,sim.route).damper_angular_coefficient)
  check(near(aggregate,8.0),label+" all live fragments retain the original total damping material")
  var body:Dictionary=sim.body_for_part(2)
  body.inertia=1.0;body.angular_velocity=3.0;body.velocity=Vector2(2.0,-1.0)
  var charge:float=sim.total_energy();var billed:float=sim.telemetry.energy_used
  var heat:float=sim.telemetry.heat
  # _act traverses the normal device dispatch into the new _damp override.
  sim._act(p,body,DT,false)
  var ratio:float=float(body.angular_velocity)/3.0
  var loss:float=0.5*(9.0-float(body.angular_velocity)*float(body.angular_velocity))
  check(near(ratio,exp(-expected*DT)),label+" I=1 single tick omega ratio is exp(-c/120)")
  check(float(sim.telemetry.heat)>=heat and near(float(sim.telemetry.heat)-heat,loss),label+" spin heat equals nonnegative rotational KE loss")
  check(body.velocity==Vector2(2.0,-1.0) and near(sim.total_energy(),charge) and near(float(sim.telemetry.energy_used),billed),label+" spin damping neither changes translation nor charges or drains the battery")
  body.inertia=2.0;body.angular_velocity=-3.0;heat=sim.telemetry.heat
  sim._damp(p,body,sim.parts[1],DT)
  check(near(float(body.angular_velocity)/-3.0,exp(-expected*DT/2.0)),label+" doubled actual inertia halves the exponent and preserves spin sign")
  loss=9.0-float(body.angular_velocity)*float(body.angular_velocity)
  check(float(sim.telemetry.heat)>=heat and near(float(sim.telemetry.heat)-heat,loss),label+" doubled-inertia heat still equals actual rotational KE loss")
  print("MATERIAL_SPIN ",JSON.stringify({"stage":label,"coefficient":expected,"omega_ratio_I1":ratio,"omega_ratio_I2":float(body.angular_velocity)/-3.0,"material_fraction":p.output_factor}))

func relative_damping()->void:
 var sim=make("damper",true)
 for stage in range(3):
  if stage>0:split_target(sim)
  var label:String=["whole","half","quarter"][stage]
  var coefficient:float=8.0/pow(2.0,stage)
  var body:Dictionary=sim.body_for_part(2)
  var other:Dictionary=sim.body_for_part(5)
  check(body.id!=other.id and body.position.distance_to(other.position)<5.0,label+" two-body fixture has distinct real bodies within damper reach")
  body.velocity=Vector2(2.0,-1.0);other.velocity=Vector2(-3.0,4.0)
  body.angular_velocity=0.0;other.angular_velocity=0.0
  var relative:Vector2=other.velocity-body.velocity
  var reduced:float=float(body.mass)*float(other.mass)/(float(body.mass)+float(other.mass))
  var momentum:Vector2=body.velocity*float(body.mass)+other.velocity*float(other.mass)
  var kinetic:float=0.5*float(body.mass)*body.velocity.length_squared()+0.5*float(other.mass)*other.velocity.length_squared()
  var heat:float=sim.telemetry.heat;var charge:float=sim.total_energy();var billed:float=sim.telemetry.energy_used
  sim._act(sim.parts[2],body,DT,false)
  var relative_after:Vector2=other.velocity-body.velocity
  var expected:Vector2=relative*exp(-coefficient*DT/reduced)
  var momentum_after:Vector2=body.velocity*float(body.mass)+other.velocity*float(other.mass)
  var kinetic_after:float=0.5*float(body.mass)*body.velocity.length_squared()+0.5*float(other.mass)*other.velocity.length_squared()
  check(relative_after.distance_to(expected)<=VECTOR_TOL,label+" relative velocity decays at c/actual reduced mass")
  check(momentum_after.distance_to(momentum)<=VECTOR_TOL,label+" equal opposite damping impulses preserve total linear momentum")
  check(kinetic_after<=kinetic+VECTOR_TOL and float(sim.telemetry.heat)>=heat and near(float(sim.telemetry.heat)-heat,kinetic-kinetic_after,VECTOR_TOL),label+" two-body heat is the nonnegative total translational KE decrease")
  check(near(sim.total_energy(),charge) and near(float(sim.telemetry.energy_used),billed),label+" relative damping cannot recharge or consume electrical storage")
  print("MATERIAL_RELATIVE ",JSON.stringify({"stage":label,"mass_left":body.mass,"mass_right":other.mass,"reduced_mass":reduced,"coefficient":coefficient,"expected_ratio":exp(-coefficient*DT/reduced),"actual_ratio":relative_after.length()/relative.length(),"heat_delta":float(sim.telemetry.heat)-heat}))
 # A target beyond the existing five-metre reach has no hidden remote effect.
 var body:Dictionary=sim.body_for_part(2);var other:Dictionary=sim.body_for_part(5)
 other.position=body.position+Vector2(6.0,0.0)
 var before:PackedByteArray=var_to_bytes([body.velocity,other.velocity,sim.telemetry.heat,sim.total_energy()])
 sim._damp(sim.parts[2],body,sim.parts[5],DT)
 check(var_to_bytes([body.velocity,other.velocity,sim.telemetry.heat,sim.total_energy()])==before,"out-of-reach two-body damper has no motion, heat or energy side effect")

func split_resource_conservation()->void:
 # Split an actual charged battery so capacity/charge checks are non-vacuous.
 var sim=make("battery")
 sim.parts[2].hp=31.0
 var initial:Dictionary=totals(sim)
 for stage in range(1,3):
  split_target(sim)
  var actual:Dictionary=totals(sim)
  check(sim.parts.size()==4+stage and near(float(sim.parts[2].output_factor),1.0/pow(2.0,stage)),"resource split %d creates exactly one fragment and halves its source"%stage)
  for key in ["mass","hp","max_hp","price","capacity","stored_energy","strength","output_factor"]:
   check(near(float(actual[key]),float(initial[key])),"resource split %d conserves total %s"%[stage,key])
  check(near(float(actual.energy),float(initial.energy)-10.0*stage) and near(float(sim.telemetry.energy_used),10.0*stage),"resource split %d spends exactly 10 J per operation"%stage)
  check(int(actual.cargo_count)==1 and near(float(sim.parts[1].hp),100.0),"resource split %d preserves one unchanged cargo"%stage)
  check(near(float(sim.parts[2].hp)/float(sim.parts[2].max_hp),31.0/45.0),"resource split %d preserves existing damage fraction"%stage)

func cargo_split_refused()->void:
 var sim=Sim.new()
 sim.configure([part(1,"cargo",0),part(2,"splitter",1,0,0.0,1),part(3,"battery",2,0,300.0)],[],route(),42)
 var before:PackedByteArray=var_to_bytes([sim.parts,sim.links,sim.bodies,totals(sim),sim.telemetry.energy_used])
 sim._split_module(sim.parts[2],sim.parts[1],sim.body_for_part(2),DT)
 check(var_to_bytes([sim.parts,sim.links,sim.bodies,totals(sim),sim.telemetry.energy_used])==before,"linked cargo split is refused without payment or physical mutation")

func fixed_tick_dispatch()->void:
 var sim=make();sim.release_launcher(0.0,0.0)
 var body:Dictionary=sim.body_for_part(2)
 var inertia:float=body.inertia
 body.angular_velocity=1.0
 var charge:float=sim.total_energy();var heat:float=sim.telemetry.heat
 sim.step(DT)
 check(sim.pilot_tick==1 and sim.status=="running" and near(float(body.angular_velocity),exp(-8.0*DT/inertia)),"real released v7 fixed tick invokes inertia-dependent passive damping")
 check(near(sim.total_energy(),charge) and float(sim.telemetry.heat)>heat,"real fixed tick dissipates heat without hidden electrical work")
