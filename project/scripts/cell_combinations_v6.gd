extends RefCounted
## Shared new-protocol mechanisms. No mutable legacy route relabelling at runtime.
const EPS:float=0.000001

static func canonical_design(design:Array)->Array:
 var result:Array=design.duplicate(true)
 result.sort_custom(func(a,b):return int(a.get("id",0))<int(b.get("id",0)))
 return result

static func pay_energy(sim,body:Dictionary,used:float,consumer_id:int)->void:
 var sources:Array=[];var total:float=0.0
 for p in body.parts:
  if p.alive and not p.delivered and float(p.energy)>0.0 and sim._same_circuit(sim.parts.get(consumer_id,{}),p):sources.append(p)
 sources.sort_custom(func(a,b):return int(a.id)<int(b.id))
 for p in sources:total+=float(p.energy)
 if total<=0.0 or used<=0.0:return
 var fraction:float=clampf(used/total,0.0,1.0)
 # All sources pay the same fraction of their ACTUAL remaining charge. The
 # stable sum order only removes floating-point permutation noise, no priority.
 for p in sources:p.energy=maxf(0.0,float(p.energy)*(1.0-fraction))

static func refresh(sim)->void:
 var ids:Array=[]
 for p in sim.parts.values():
  if p.type!="cargo" or not p.alive or p.delivered:continue
  var b:Dictionary=sim.body_for_part(p.id)
  if b.is_empty() or sim._available_energy(b,p.id)<=EPS:ids.append(int(p.id))
 ids.sort();sim.telemetry.unpowered_cargo_ids=ids
 sim.telemetry.unpowered_coasting=sim.status=="running" and not ids.is_empty()
 sim.telemetry.energy_policy="unpowered-coast-v1"
 sim.telemetry.supply_policy="proportional-circuit-energy-v1"
 if not sim.telemetry.has("accelerator_events"):sim.telemetry.accelerator_events=[]

static func preview_blueprint(design:Array,route:Dictionary,accelerator_id:int)->Dictionary:
 var paths:Dictionary={"pilot-delivery-v6":"res://scripts/pilot_delivery_simulation_v6.gd","pilot-ascent-v6":"res://scripts/pilot_delivery_ascent_simulation_v6.gd","pilot-rift-v6":"res://scripts/pilot_delivery_rift_simulation_v6.gd","pilot-delivery-v7":"res://scripts/pilot_delivery_simulation_v7.gd","pilot-ascent-v7":"res://scripts/pilot_delivery_ascent_simulation_v7.gd","pilot-rift-v7":"res://scripts/pilot_delivery_rift_simulation_v7.gd","pilot-delivery-v8":"res://scripts/pilot_delivery_simulation_v8.gd","pilot-ascent-v8":"res://scripts/pilot_delivery_ascent_simulation_v8.gd","pilot-rift-v8":"res://scripts/pilot_delivery_rift_simulation_v8.gd"}
 if not paths.has(route.get("control_version","")):return _empty("wrong_protocol")
 var script=load(paths[route.control_version]);var sim=script.new()
 sim.configure(design,[],route,1)
 if not sim.free_route_error.is_empty():return _empty("invalid_route")
 return preview_accelerator(sim,accelerator_id)

static func reason_text(reason:String)->String:
 var labels:Dictionary={"ready":"接口可分离，整组净空与供能满足", "spent":"本件已经发射", "target_not_linked":"目标未通过选中接口相连", "bypass_connection":"存在旁路连接，切此接口仍无法分体", "no_payload":"接口两侧没有有效载荷", "insufficient_energy":"当前电路或阀无法支付整次发射", "exit_blocked":"两侧发射方向或出口净空不足", "no_impulse":"发射强度为零", "wrong_protocol":"此规则版本不支持成组预演", "invalid_route":"订单规则无效"}
 return str(labels.get(reason,"暂时无法发射"))

static func _empty(reason:String)->Dictionary:
 return {"valid":false,"can_fire":false,"reason":reason,"carrier_ids":[],"payload_ids":[],"carrier_mass":0.0,"payload_mass":0.0,"energy_required":0.0,"impulse":0.0,"direction":Vector2.ZERO,"relative_delta_speed":0.0,"stroke_metres":0.0,"release_seconds":0.0,"cargo_delta_v":{}}
static func preview_accelerator(sim,id:int)->Dictionary:
 var result:Dictionary=_plan(sim,id,sim.FIXED_DT)
 # Presentation-only fields never enter _plan or the historical runtime event.
 result.cargo_impacts=[];result.ammo_cost=0.0;result.ammo_part_ids=[]
 result.carrier_delta_v=Vector2.ZERO;result.payload_delta_v=Vector2.ZERO
 result.carrier_angular_delta=0.0;result.payload_angular_delta=0.0
 result.preview_scope="instantaneous_accelerator_pulse_only"
 if result.can_fire:
  var body:Dictionary=sim.body_for_part(id)
  for side in ["carrier","payload"]:
   var group:Dictionary=result["_"+side]
   var before:Dictionary=_group(sim,group.ids,body)
   result[side+"_delta_v"]=Vector2(group.velocity)-Vector2(before.velocity)
   result[side+"_angular_delta"]=float(group.omega)-float(before.omega)
   for qid in group.ids:
    var cargo:Dictionary=sim.parts[qid]
    if cargo.type!="cargo":continue
    var mount:Dictionary=sim.cargo_mount_properties(cargo,group.ids)
    var impact:Dictionary=sim.cargo_pulse_preview(cargo,result.cargo_delta_v[qid],float(result.release_seconds),mount,sim.route)
    impact.cargo_id=int(qid);impact.side=side;result.cargo_impacts.append(impact)
  var payload_has_cargo:bool=false
  for qid in result.payload_ids:
   if sim.parts[qid].type=="cargo":payload_has_cargo=true
  if not payload_has_cargo:
   for qid in result.payload_ids:
    var item:Dictionary=sim.parts[qid]
    if str(item.replacement_kind).is_empty():
     result.ammo_cost+=float(item.price);result.ammo_part_ids.append(int(qid))
 result.erase("_carrier");result.erase("_payload")
 return result
static func _component_after_cut(sim,start:int,first:int,second:int,allowed:Dictionary)->Array:
 var seen:Dictionary={start:true};var queue:Array=[start]
 while not queue.is_empty():
  var current:int=queue.pop_front()
  for edge in sim.links:
   var a:int=edge.a;var b:int=edge.b
   if (a==first and b==second) or (a==second and b==first):continue
   var next:int=b if a==current else (a if b==current else -1)
   if next<0 or not allowed.has(next) or seen.has(next):continue
   seen[next]=true;queue.append(next)
 var ids:Array=seen.keys();ids.sort();return ids
static func _group(sim,ids:Array,body:Dictionary)->Dictionary:
 var mass:float=0.0;var centre:Vector2=Vector2.ZERO
 for id in ids:
  var p:Dictionary=sim.parts[id];mass+=float(p.mass);centre+=sim._part_position(p)*float(p.mass)
 centre/=mass
 var inertia:float=0.0
 for id in ids:
  var p:Dictionary=sim.parts[id];inertia+=float(p.mass)*(sim._part_position(p)-centre).length_squared()+float(p.mass)/6.0
 var arm:Vector2=centre-Vector2(body.position)
 return {"ids":ids,"mass":mass,"centre":centre,"inertia":maxf(EPS,inertia),"velocity":Vector2(body.velocity)+Vector2(-arm.y,arm.x)*float(body.angular_velocity),"omega":float(body.angular_velocity)}
static func _plan(sim,id:int,dt:float)->Dictionary:
 var result:Dictionary=_empty("target_not_linked")
 var p:Dictionary=sim.parts.get(id,{})
 if p.is_empty() or p.type!="accelerator" or not p.alive or p.delivered:return result
 if p.spent:result.reason="spent";return result
 var b:Dictionary=sim.body_for_part(id)
 if b.is_empty():return result
 var target:Dictionary=sim._target(p,b)
 if target.is_empty() or target.body_id!=b.id or not sim._linked(p.id,target.id):return result
 var allowed:Dictionary={}
 for q in b.parts:
  if q.alive and not q.delivered:allowed[int(q.id)]=true
 var payload_ids:Array=_component_after_cut(sim,target.id,p.id,target.id,allowed)
 if payload_ids.has(p.id):result.reason="bypass_connection";return result
 var carrier_ids:Array=[]
 for qid in allowed:
  if not payload_ids.has(qid):carrier_ids.append(qid)
 carrier_ids.sort()
 if payload_ids.is_empty() or carrier_ids.is_empty():result.reason="no_payload";return result
 var carrier:Dictionary=_group(sim,carrier_ids,b);var payload:Dictionary=_group(sim,payload_ids,b)
 var direction:Vector2=Vector2.RIGHT.rotated(float(b.angle)+float(p.local_angle))
 # Equal and opposite impulses act at the shared interface. Off-centre loading
 # therefore conserves angular as well as linear momentum, and costs rotation.
 var interface_at:Vector2=(sim._part_position(p)+sim._part_position(target))*0.5
 var carrier_arm:Vector2=interface_at-Vector2(carrier.centre)
 var payload_arm:Vector2=interface_at-Vector2(payload.centre)
 var inverse_effective_mass:float=1.0/float(carrier.mass)+1.0/float(payload.mass)+pow(carrier_arm.cross(direction),2)/float(carrier.inertia)+pow(payload_arm.cross(direction),2)/float(payload.inertia)
 var delta_speed:float=maxf(0.0,float(p.param))*float(p.output_factor)
 var impulse:float=delta_speed/inverse_effective_mass
 var energy:float=0.5*impulse*delta_speed
 carrier.velocity-=direction*impulse/float(carrier.mass);payload.velocity+=direction*impulse/float(payload.mass)
 carrier.omega-=carrier_arm.cross(direction)*impulse/float(carrier.inertia);payload.omega+=payload_arm.cross(direction)*impulse/float(payload.inertia)
 var stroke:float=float(sim.route.get("accelerator_stroke_metres",1.0))
 var duration:float=2.0*stroke/maxf(EPS,delta_speed)
 result.merge({"carrier_ids":carrier_ids,"payload_ids":payload_ids,"carrier_mass":carrier.mass,"payload_mass":payload.mass,"energy_required":energy,"impulse":impulse,"direction":direction,"relative_delta_speed":delta_speed,"stroke_metres":stroke,"release_seconds":duration,"_carrier":carrier,"_payload":payload,"interface_position":interface_at},true)
 for group in [carrier,payload]:
  for qid in group.ids:
   var q:Dictionary=sim.parts[qid]
   if q.type=="cargo":
    var arm:Vector2=sim._part_position(q)-Vector2(group.centre)
    result.cargo_delta_v[qid]=Vector2(group.velocity)+Vector2(-arm.y,arm.x)*float(group.omega)-sim._part_velocity(q)
 if delta_speed<=EPS:result.reason="no_impulse";return result
 if not sim._can_supply(b,energy,id,dt):result.reason="insufficient_energy";return result
 if not _clear(sim,b,carrier,payload,float(sim.route.get("accelerator_clearance_seconds",0.18))):result.reason="exit_blocked";return result
 result.valid=true;result.can_fire=true;result.reason="ready";return result

static func _position_at(sim,p:Dictionary,group:Dictionary,time:float)->Vector2:
 var arm:Vector2=sim._part_position(p)-Vector2(group.centre)
 return Vector2(group.centre)+Vector2(group.velocity)*time+arm.rotated(float(group.omega)*time)
static func _clear(sim,old_body:Dictionary,carrier:Dictionary,payload:Dictionary,seconds:float)->bool:
 # Sweep actual module circles, not a muzzle teleport. Eight short angular
 # segments are conservatively expanded by their circular-arc sagitta.
 for group in [carrier,payload]:
  var other:Dictionary=payload if group==carrier else carrier
  for id in group.ids:
   var p:Dictionary=sim.parts[id]
   var radius:float=(0.48 if p.type=="drill" else 0.43)*float(p.scale)
   for segment in range(8):
    var t0:float=seconds*float(segment)/8.0;var t1:float=seconds*float(segment+1)/8.0
    var start:Vector2=_position_at(sim,p,group,t0);var end:Vector2=_position_at(sim,p,group,t1)
    var arc:float=(sim._part_position(p)-Vector2(group.centre)).length()*(1.0-cos(absf(float(group.omega))*(t1-t0)*0.5))
    for qid in other.ids:
     var q:Dictionary=sim.parts[qid]
     var q0:Vector2=_position_at(sim,q,other,t0);var q1:Vector2=_position_at(sim,q,other,t1)
     var qarc:float=(sim._part_position(q)-Vector2(other.centre)).length()*(1.0-cos(absf(float(other.omega))*(t1-t0)*0.5))
     if _blocked(sim,start-q0,end-q1,radius+0.43*float(q.scale)+arc+qarc):return false
    for h in sim.obstacles:
     if h.health<=0 or h.type=="gravity":continue
     var v:Vector2=h.get("velocity",Vector2.ZERO)
     if _blocked(sim,start-h.position-v*t0,end-h.position-v*t1,radius+float(h.radius)+arc):return false
    for body in sim.bodies:
     if body.id==old_body.id:continue
     for q in body.parts:
      if not q.alive or q.delivered:continue
      var q0:Vector2=sim._part_position(q)+sim._part_velocity(q)*t0
      var q1:Vector2=sim._part_position(q)+sim._part_velocity(q)*t1
      if _blocked(sim,start-q0,end-q1,radius+0.43*float(q.scale)+arc):return false
 return true
static func _blocked(sim,start:Vector2,end:Vector2,radius:float)->bool:
 return start.length()<radius or sim._segment_circle_t(start,end,radius)>=0.0

static func accelerate(sim,p:Dictionary,target:Dictionary,body:Dictionary,dt:float)->void:
 var plan:Dictionary=_plan(sim,int(p.id),dt)
 if not plan.can_fire:
  sim.telemetry.accelerator_last_denial=plan.reason
  sim._log("成组弹射未执行：%s；电量、连接与位置保留。"%reason_text(str(plan.reason)));return
 sim._consume(body,float(plan.energy_required),int(p.id),dt)
 sim._cut(int(p.id),int(target.id));sim._rebuild_bodies()
 var carrier:Dictionary=sim.body_for_part(int(p.id));var payload:Dictionary=sim.body_for_part(int(target.id))
 carrier.velocity=plan._carrier.velocity;carrier.angular_velocity=plan._carrier.omega
 payload.velocity=plan._payload.velocity;payload.angular_velocity=plan._payload.omega
 p.spent=true
 var has_cargo:bool=false
 for id in plan.payload_ids:
  if sim.parts[id].type=="cargo":has_cargo=true
 if not has_cargo:
  for id in plan.payload_ids:sim._charge_replacement(sim.parts[id],"ammo")
 # Real per-cargo point velocity changes include recoil and off-centre rotation.
 for id in plan.cargo_delta_v:sim._pulse_damage(sim.parts[id],plan.cargo_delta_v[id],float(plan.release_seconds),"accelerator_pulse")
 var event:Dictionary=preview_event(plan);event.tick=sim.pilot_tick;event.accelerator_id=int(p.id);event.target_id=int(target.id)
 if not sim.telemetry.has("accelerator_events"):sim.telemetry.accelerator_events=[]
 sim.telemetry.accelerator_events.append(event);sim.telemetry.accelerator_last_event=event
 sim._log("成组弹射：%.1f kg 载荷，%.1f J；载体承受真实反冲，未平移模块。"%[float(plan.payload_mass),float(plan.energy_required)])
 if sim._graph_dirty:sim._rebuild_bodies()
static func preview_event(plan:Dictionary)->Dictionary:
 var result:Dictionary=plan.duplicate(true);result.erase("_carrier");result.erase("_payload");return result
