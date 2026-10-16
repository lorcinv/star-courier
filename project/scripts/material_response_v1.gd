extends RefCounted
## v7 engineering approximation: split parallel material, retaining working
## length. No displacement state, bottom-out, directional suspension or reservoir.
const SCHEMA:String="parallel-material-v1"
const GEOMETRY:String="constant-working-length-v1"
const EPS:float=0.000001
const REFERENCE_MASS_KG:float=1.0
const REFERENCE_INERTIA_KG_M2:float=1.0

static func material_properties(part:Dictionary,route:Dictionary)->Dictionary:
 var fraction:float=clampf(float(part.get("output_factor",1.0)),0.0,1.0)
 var condition:float=clampf(float(part.get("hp",0.0))/maxf(EPS,float(part.get("max_hp",1.0))),0.0,1.0)
 var setting:float=maxf(0.0,float(part.get("param",0.0)))
 var reference_mass:float=float(route.get("damper_reference_mass_kg",REFERENCE_MASS_KG))
 var reference_inertia:float=float(route.get("damper_reference_inertia_kg_m2",REFERENCE_INERTIA_KG_M2))
 var spring:bool=part.get("type","")=="spring"
 var damper:bool=part.get("type","")=="damper"
 # Strength, mass, actual charge and price were already divided by _split_module.
 # Health affects the existing cargo mount response, not the legacy active-damper enable rule.
 return {"material_fraction":fraction,"condition":condition,
  "spring_capacity_j":setting*fraction*condition if spring else 0.0,
  "damper_linear_coefficient":setting*fraction*reference_mass if damper else 0.0,
  "damper_angular_coefficient":setting*fraction*reference_inertia if damper else 0.0,
  "damper_reference_mass_kg":reference_mass,"damper_reference_inertia_kg_m2":reference_inertia}

static func cargo_mount_properties(sim,cargo:Dictionary,component_ids:Array=[])->Dictionary:
 var mounts:Array=[]
 for edge in sim.links:
  var other:int=int(edge.b) if int(edge.a)==int(cargo.id) else (int(edge.a) if int(edge.b)==int(cargo.id) else -1)
  if other<0 or not sim.parts.has(other):continue
  if not component_ids.is_empty() and not component_ids.has(other):continue
  var mount:Dictionary=sim.parts[other]
  if not mount.alive or mount.delivered or (int(mount.target)>=0 and int(mount.target)!=int(cargo.id)):continue
  if mount.type not in ["spring","damper"] or float(mount.param)<=0.0:continue
  if mount.type=="damper" and not sim._mount_enabled_after_cut(mount,component_ids):continue
  var properties:Dictionary=material_properties(mount,sim.route)
  var energy:float=float(properties.spring_capacity_j)
  var force:float=minf(float(mount.strength),float(edge.strength))*float(properties.condition) if mount.type=="spring" else 0.0
  var stiffness:float=force*force/(2.0*energy) if energy>EPS else 0.0
  var coefficient:float=float(properties.damper_linear_coefficient)*float(properties.condition)
  var damping:float=coefficient/maxf(EPS,float(properties.damper_reference_mass_kg))
  mounts.append({"part_id":int(mount.id),"type":str(mount.type),"material_fraction":properties.material_fraction,"condition":properties.condition,
   "elastic_energy":energy,"strength":force,"stiffness":stiffness,"damping":damping,
   "damper_linear_coefficient":coefficient,"damper_angular_coefficient":float(properties.damper_angular_coefficient)*float(properties.condition)})
 mounts.sort_custom(func(a,b):return int(a.part_id)<int(b.part_id))
 var energy:float=0.0;var force:float=0.0;var stiffness:float=0.0;var damping:float=0.0
 for mount in mounts:
  energy+=float(mount.elastic_energy);force+=float(mount.strength);stiffness+=float(mount.stiffness);damping+=float(mount.damping)
 # Parallel stiffness is sum(k_i), including unlike capacities/force limits.
 var response:float=sqrt(float(cargo.mass)/stiffness) if stiffness>EPS else 0.0
 # Retain the published scalar cargo lag model, with corrected material input.
 # This delay is not a tracked travel limit or a finite dissipative-energy store.
 var damper_seconds:float=0.43*damping/(1.0+damping) if damping>EPS else 0.0
 response=response*(1.0+damping*response)+damper_seconds
 return {"elastic_energy":energy,"strength":force,"stiffness":stiffness,"damping":damping,"response_seconds":response,"mounts":mounts,"material_rules_schema":SCHEMA}

static func damp(sim,part:Dictionary,body:Dictionary,target:Dictionary,dt:float)->void:
 if dt<=0.0:return
 var material:Dictionary=material_properties(part,sim.route)
 if target.is_empty() or target.body_id==body.id:
  var inertia:float=maxf(EPS,float(body.inertia))
  var before:float=0.5*inertia*float(body.angular_velocity)*float(body.angular_velocity)
  body.angular_velocity*=exp(-float(material.damper_angular_coefficient)*dt/inertia)
  var after:float=0.5*inertia*float(body.angular_velocity)*float(body.angular_velocity)
  sim.telemetry.heat+=maxf(0.0,before-after)
  # Existing abstract despin interface: no modelled external reaction torque.
  # Do not describe this as closed-system angular-momentum conservation.
  return
 var other:Dictionary=sim.body_for_part(target.id)
 if other.is_empty() or body.position.distance_to(other.position)>5.0:return
 var relative:Vector2=other.velocity-body.velocity
 var reduced:float=float(body.mass)*float(other.mass)/(float(body.mass)+float(other.mass))
 if reduced<=EPS:return
 var impulse:Vector2=relative*reduced*(1.0-exp(-float(material.damper_linear_coefficient)*dt/reduced))
 var before:float=0.5*reduced*relative.length_squared()
 body.velocity+=impulse/float(body.mass);other.velocity-=impulse/float(other.mass)
 var after:float=0.5*reduced*(other.velocity-body.velocity).length_squared()
 sim.telemetry.heat+=maxf(0.0,before-after)
