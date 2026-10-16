extends RefCounted
## Local protection of struck part CENTRES, not a ray-interception surface.
## All snapshots are read-only; payment happens only in damage_part.
const SCHEMA:String="cell-center-shield-v1"
const RADIUS_POLICY:String="sqrt-material-area-v1"
const BASE_RADIUS_METRES:float=1.5
const ATTACK_JOULES_PER_HP:float=1.5
const EPS:float=0.000001
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")

static func radius_metres(part:Dictionary,route:Dictionary)->float:
 return float(route.get("shield_base_radius_metres",BASE_RADIUS_METRES))*sqrt(clampf(float(part.get("output_factor",1.0)),0.0,1.0))

static func covers(sim,shield:Dictionary,target:Dictionary)->bool:
 if not shield.alive or shield.delivered or not target.alive or target.delivered or not sim._same_circuit(shield,target):return false
 var radius:float=radius_metres(shield,sim.route)
 return radius>0.0 and sim._part_position(shield).distance_squared_to(sim._part_position(target))<=radius*radius

static func available_energy(sim,shield:Dictionary,body:Dictionary)->float:
 # Read the same consumer/valve remaining tick budget used by Extreme._consume.
 if body.is_empty():return 0.0
 var available:float=maxf(0.0,float(sim._available_energy(body,int(shield.id))))
 for valve in body.get("parts",[]):
  if not valve.alive or valve.delivered or valve.type!="valve" or not sim._same_circuit(shield,valve):continue
  if valve.target!=shield.id and not (valve.target<0 and sim._linked(valve.id,shield.id)):continue
  var key:String="%d:%d"%[valve.id,shield.id]
  var budget:float=maxf(0.0,float(valve.param)*float(sim._tick_dt)-float(sim._shield_valve_spent.get(key,0.0))) if sim._enabled(valve) else 0.0
  available=minf(available,budget)
 return available

static func _shields(sim,target:Dictionary)->Array:
 var result:Array=[];var body:Dictionary=sim.body_for_part(target.id)
 for shield in body.get("parts",[]):
  if shield.type=="shield" and covers(sim,shield,target) and sim._enabled(shield):result.append(shield)
 result.sort_custom(func(a,b):return int(a.id)<int(b.id))
 return result

static func damage_part(sim,part:Dictionary,amount:float,source:String)->void:
 # Called only for attack/collision. Residual damage must NEVER recurse into
 # the inherited all-circuit shield branch, which would absorb it a second time.
 if source not in ["attack","collision"] or not part.alive or part.delivered or amount<=0.0:return
 var scaled:float=amount
 if source=="collision" and part.type=="cargo":
  var response:float=float(sim.cargo_mount_properties(part).response_seconds)
  var ratio:float=0.04/(0.04+response)
  scaled*=float(sim.route.cargo_contact_damage_scale)*ratio*ratio
 var remaining:float=scaled
 var absorb_remaining:float=scaled*Extreme.IMPACT_ABSORB_FRACTION
 var body:Dictionary=sim.body_for_part(part.id)
 for shield in _shields(sim,part):
  if source=="attack":
   remaining*=1.0-sim._consume(body,remaining*ATTACK_JOULES_PER_HP,shield.id,sim._tick_dt)
   if remaining<=EPS:return
  else:
   var limit:float=maxf(0.0,Extreme.IMPACT_ABSORB_LIMIT*float(shield.output_factor)-float(sim._shield_spent.get(shield.id,0.0)))
   var desired:float=minf(absorb_remaining,limit)
   if desired<=EPS:continue
   var before:float=sim.telemetry.energy_used
   var absorbed:float=desired*sim._consume(body,desired*Extreme.IMPACT_JOULES_PER_HP,shield.id,sim._tick_dt)
   remaining-=absorbed;absorb_remaining-=absorbed
   sim._shield_spent[shield.id]=float(sim._shield_spent.get(shield.id,0.0))+absorbed
   sim.telemetry.impact_absorbed=float(sim.telemetry.get("impact_absorbed",0.0))+absorbed
   sim.telemetry.impact_shield_energy=float(sim.telemetry.get("impact_shield_energy",0.0))+float(sim.telemetry.energy_used)-before
 if remaining>0.0:sim._record_damage_incident(part,remaining,source)
 part.hp-=remaining
 if part.hp<=0.0:sim._destroy(part)

static func reason_text(reason:String)->String:
 return str({"ready":"圈内格中心可由当前电路供能保护","disabled":"输入未启用","no_material":"没有有效护盾材料","no_power":"当前电路或阀没有可支付能量","no_shield":"未选择有效护盾","wrong_protocol":"当前合同不使用局部护盾规则","invalid_route":"订单护盾规则无效"}.get(reason,"护盾暂不可用"))

static func _empty(reason:String)->Dictionary:
 return {"schema":SCHEMA,"scope":"hit-part-center","reason":reason,"generators":[],"targets":[],"candidate_ids":[],"protected_ids":[]}

static func snapshot(sim,shield_id:int=-1)->Dictionary:
 var result:Dictionary=_empty("no_shield")
 result.control_version=str(sim.route.get("control_version",""));result.elapsed=float(sim.elapsed)
 var candidates:Dictionary={};var protected:Dictionary={};var ids:Array=sim.parts.keys();ids.sort()
 for id in ids:
  var target:Dictionary=sim.parts[id]
  if target.alive and not target.delivered:result.targets.append({"id":int(id),"world_position":sim._part_position(target)})
 for id in ids:
  var shield:Dictionary=sim.parts[id]
  if shield.type!="shield" or not shield.alive or shield.delivered or (shield_id>=0 and id!=shield_id):continue
  var enabled:bool=sim._enabled(shield);var radius:float=radius_metres(shield,sim.route)
  var body:Dictionary=sim.body_for_part(id);var charge:float=available_energy(sim,shield,body)
  var active:bool=enabled and radius>0.0 and charge>EPS
  var reason:String="ready" if active else ("no_material" if radius<=0.0 else ("disabled" if not enabled else "no_power"))
  var candidate_ids:Array=[];var protected_ids:Array=[]
  for target_id in ids:
   var target:Dictionary=sim.parts[target_id]
   if covers(sim,shield,target):
    candidate_ids.append(int(target_id));candidates[target_id]=true
    if active:protected_ids.append(int(target_id));protected[target_id]=true
  result.generators.append({"id":int(id),"world_position":sim._part_position(shield),"radius_m":radius,
   "material_fraction":clampf(float(shield.output_factor),0.0,1.0),"enabled":enabled,"active":active,"reason":reason,
   "available_energy_j":charge,"candidate_ids":candidate_ids,"protected_ids":protected_ids,
   "impact_absorb_remaining":maxf(0.0,Extreme.IMPACT_ABSORB_LIMIT*float(shield.output_factor)-float(sim._shield_spent.get(shield.id,0.0)))})
 result.candidate_ids=candidates.keys();result.candidate_ids.sort();result.protected_ids=protected.keys();result.protected_ids.sort()
 if not result.generators.is_empty():result.reason="ready"
 return result

static func preview_blueprint(design:Array,route:Dictionary,shield_id:int=-1)->Dictionary:
 var paths:Dictionary={"pilot-delivery-v8":"res://scripts/pilot_delivery_simulation_v8.gd","pilot-ascent-v8":"res://scripts/pilot_delivery_ascent_simulation_v8.gd","pilot-rift-v8":"res://scripts/pilot_delivery_rift_simulation_v8.gd"}
 if not paths.has(route.get("control_version","")):return _empty("wrong_protocol")
 var script=load(paths[route.control_version]);var sim=script.new();sim.configure(design,[],route,1)
 if not sim.free_route_error.is_empty():return _empty("invalid_route")
 return snapshot(sim,shield_id)
