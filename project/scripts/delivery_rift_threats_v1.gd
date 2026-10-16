extends RefCounted
## One post-portal stationary raider and one bounded periodic physical field.
## The v5 simulation owns verified portal passage and calls activate only there.
## Existing CCD, actual ray/circle geometry, circuits and paid shields remain the
## damage owners. No wall clock, random HP pulses, extra cargo HP or enemy bill.
const DEFAULT_PIRATE:Dictionary={"position":[154.0,-20.0],"radius":1.5,"health":40.0,"mass":6.0,"ammo":2,"warning_seconds":2.75,"cooldown_seconds":1.5,"range":65.0,"damage":12.0}
const DEFAULT_TURBULENCE:Dictionary={"bounds":[132.0,-10.0,35.0,20.0],"period_seconds":7.0,"active_seconds":3.0,"peak_force":18.0,"peak_torque":10.0}
var pirate_definition:Dictionary={}
var field_definition:Dictionary={}
var active:bool=false
var activated_at:float=-1.0
var hazard_index:int=-1
var shots_fired:int=0
var next_lock_at:float=0.0
var warning:Dictionary={}
var ray_records:Array=[]

func configure(route:Dictionary)->void:
 pirate_definition=route.get("rift_pirate",DEFAULT_PIRATE).duplicate(true)
 field_definition=route.get("rift_turbulence",DEFAULT_TURBULENCE).duplicate(true)
 active=false;activated_at=-1.0;hazard_index=-1;shots_fired=0;next_lock_at=0.0
 warning.clear();ray_records.clear()

func activate(sim)->void:
 if active:return
 active=true;activated_at=float(sim.elapsed);next_lock_at=activated_at

func before_tick(sim,_dt:float)->void:
 if not active or hazard_index>=0:return
 var d:Dictionary=pirate_definition
 hazard_index=sim.obstacles.size()
 sim.obstacles.append({"id":"rift_raider_1","type":"rift_pirate","position":Vector2(d.position[0],d.position[1]),"velocity":Vector2.ZERO,"radius":float(d.radius),"health":float(d.health),"mass":float(d.mass),"cooldown":0.0,"conductive":true,"destructible":true,"rift_pirate":true})
 sim._log("海盗伏击区：实体巡逻艇正在锁定航线，激光预警后可绕开射线或用遮挡、防护处理。")

func field_for_body(sim,body:Dictionary)->Dictionary:
 var phase:float=fposmod(maxf(0.0,float(sim.elapsed)-activated_at),float(field_definition.get("period_seconds",7.0)))
 var bounds:Array=field_definition.get("bounds",DEFAULT_TURBULENCE.bounds)
 var inside:bool=Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3])).has_point(body.get("position",Vector2.ZERO))
 var duration:float=float(field_definition.get("active_seconds",3.0))
 var on:bool=active and inside and phase<duration
 var force:Vector2=Vector2.ZERO;var torque:float=0.0
 if on and duration>0.0:
  # Smooth zero-force edges make waiting through the quiet interval useful.
  # The exact fixed-step elapsed clock reconstructs this field on replay.
  var envelope:float=sin(PI*phase/duration)
  var heading:float=TAU*phase/duration
  force=Vector2(cos(heading),sin(heading))*float(field_definition.peak_force)*envelope
  torque=sin(heading+0.65)*float(field_definition.peak_torque)*envelope
 return {"active":on,"inside":inside,"phase_seconds":phase,"force":force,"torque":torque}

func add_forces(sim,_dt:float)->void:
 if not active:return
 # Called once from the first enabled part action, AFTER the inherited force
 # reset and BEFORE integration. Cargo is always enabled while undelivered.
 # All real bodies, including detached hardware, receive the local field.
 for body in sim.bodies:
  var field:Dictionary=field_for_body(sim,body)
  if not field.active:continue
  var force:Vector2=field.force;var torque:float=field.torque
  body.force+=force;body.torque+=torque
  var rotational_weight:float=0.0
  for p in body.parts:rotational_weight+=float(p.mass)*p.local_pos.length_squared()
  # Real source/socket loads use the same force and a balanced force couple.
  # A one-module body's local angular loading needs no inter-module socket.
  for p in body.parts:
   var arm:Vector2=p.local_pos.rotated(body.angle)
   var source:Vector2=force*float(p.mass)/float(body.mass)
   if rotational_weight>0.0000001:source+=Vector2(-arm.y,arm.x)*torque*float(p.mass)/rotational_weight
   sim._source_forces[p.id]=Vector2(sim._source_forces.get(p.id,Vector2.ZERO))+source
  sim._sources_live=true

func after_tick(sim,_dt:float)->void:
 # Invoke from the v5 _enemy_attacks hook, AFTER physical contacts resolve.
 # An obstacle destroyed during this tick cannot emit its pending attack.
 if not active or hazard_index<0:return
 var h:Dictionary=sim.obstacles[hazard_index]
 if float(h.health)<=0.0:
  if not warning.is_empty():sim._log("海盗已失去攻击能力，当前锁定取消。")
  warning.clear();return
 if not warning.is_empty():
  if float(sim.elapsed)+0.000000001>=float(warning.due_at):_fire(sim,h)
  return
 if shots_fired>=int(pirate_definition.ammo) or float(sim.elapsed)+0.000000001<next_lock_at:return
 var target:Vector2=sim.cargo_position()
 var delta:Vector2=target-Vector2(h.position)
 if delta.length()>float(pirate_definition.range) or delta.length()<=float(h.radius)+0.01:return
 var direction:Vector2=delta.normalized()
 var origin:Vector2=Vector2(h.position)+direction*float(h.radius)
 warning={"locked_at":float(sim.elapsed),"due_at":float(sim.elapsed)+float(pirate_definition.warning_seconds),"origin":origin,"target":target,"direction":direction,"locked_tick":int(sim.pilot_tick)}
 sim._log("海盗激光锁定：%.2f 秒后沿当前标线开火；改变航线可避开。"%float(pirate_definition.warning_seconds))

func _fire(sim,_hazard:Dictionary)->void:
 var origin:Vector2=warning.origin;var direction:Vector2=warning.direction
 var distance:float=float(pirate_definition.range)
 var hit_kind:String="miss";var part_id:int=-1;var obstacle_id:int=-1
 # Solids win an exact-distance tie. Stable numeric IDs decide module ties,
 # so a saved blueprint's array order cannot change who intercepts a laser.
 for index in range(sim.obstacles.size()):
  if index==hazard_index:continue
  var h:Dictionary=sim.obstacles[index]
  if float(h.health)<=0.0 or h.type=="gravity":continue
  var at:float=_forward_ray_circle(origin,direction,h.position,float(h.radius))
  if at<distance:
   distance=at;hit_kind="obstacle";obstacle_id=index
 var ids:Array=sim.parts.keys();ids.sort()
 for id in ids:
  var p:Dictionary=sim.parts[id]
  if not p.alive or p.delivered:continue
  var at:float=_forward_ray_circle(origin,direction,sim._part_position(p),0.43*float(p.scale))
  if at<distance:
   distance=at;hit_kind="part";part_id=int(id);obstacle_id=-1
 var hp_before:float=0.0;var damage_taken:float=0.0
 var energy_before:float=float(sim.telemetry.get("energy_used",0.0))
 var damage:float=float(pirate_definition.damage)
 if hit_kind=="part":
  var p:Dictionary=sim.parts[part_id];hp_before=maxf(0.0,float(p.hp))
  sim._damage_part(p,damage,"attack")
  damage_taken=hp_before-maxf(0.0,float(p.hp))
 elif hit_kind=="obstacle":
  var h:Dictionary=sim.obstacles[obstacle_id];hp_before=maxf(0.0,float(h.health))
  if h.get("destructible",true):h.health=maxf(0.0,float(h.health)-damage)
  damage_taken=hp_before-maxf(0.0,float(h.health))
 var record:Dictionary={"tick":int(sim.pilot_tick),"time":float(sim.elapsed),"origin":origin,"end":origin+direction*distance,"hit_kind":hit_kind,"part_id":part_id,"obstacle_index":obstacle_id,"damage":damage,"damage_taken":damage_taken,"shield_energy_j":maxf(0.0,float(sim.telemetry.get("energy_used",0.0))-energy_before)}
 ray_records.append(record);shots_fired+=1
 next_lock_at=float(sim.elapsed)+float(pirate_definition.cooldown_seconds)
 sim._effect("enemy",record.origin,record.end,0.22)
 sim._log("海盗激光发射，剩余 %d 发。"%(int(pirate_definition.ammo)-shots_fired))
 warning.clear()

static func _forward_ray_circle(origin:Vector2,direction:Vector2,centre:Vector2,radius:float)->float:
 # Local v5 query only: the older solver's along+radius rejection admits a
 # behind-origin off-axis circle, then clamps its negative near root to zero.
 # Reject its ACTUAL far root before clamping. Scalar quadratic arithmetic
 # also accounts for the represented direction's not-quite-unit length.
 var dx:float=float(direction.x);var dy:float=float(direction.y)
 var ox:float=float(centre.x)-float(origin.x);var oy:float=float(centre.y)-float(origin.y)
 var a:float=dx*dx+dy*dy
 if a<=0.0:return INF
 var along:float=ox*dx+oy*dy
 var discriminant:float=along*along-a*(ox*ox+oy*oy-radius*radius)
 if discriminant<0.0:return INF
 var root:float=sqrt(discriminant)
 if (along+root)/a<0.0:return INF
 return maxf(0.0,(along-root)/a)

func telemetry(sim)->Dictionary:
 var d:Dictionary=pirate_definition if not pirate_definition.is_empty() else DEFAULT_PIRATE
 var f:Dictionary=field_definition if not field_definition.is_empty() else DEFAULT_TURBULENCE
 var h:Dictionary=sim.obstacles[hazard_index] if hazard_index>=0 and hazard_index<sim.obstacles.size() else {}
 var position:Vector2=h.get("position",Vector2(d.position[0],d.position[1]))
 var body:Dictionary=sim._cargo_body()
 var field:Dictionary=field_for_body(sim,body)
 var phase:float=float(field.phase_seconds)
 var remaining:float=float(f.active_seconds)-phase if phase<float(f.active_seconds) else float(f.period_seconds)-phase
 return {"rift_pirate":{"active":active and not h.is_empty(),"position":position,"radius":float(d.radius),"health":maxf(0.0,float(h.get("health",d.health))),"max_health":float(d.health),"ammo_remaining":int(d.ammo)-shots_fired,"shots_fired":shots_fired,"warning":not warning.is_empty(),"warning_remaining":maxf(0.0,float(warning.get("due_at",sim.elapsed))-float(sim.elapsed)),"warning_origin":warning.get("origin",position),"warning_target":warning.get("target",position),"warning_direction":warning.get("direction",Vector2.ZERO),"range":float(d.range),"disabled":not h.is_empty() and float(h.health)<=0.0,"hazard_index":hazard_index,"last_ray":ray_records.back().duplicate(true) if not ray_records.is_empty() else {},"ray_records":ray_records.duplicate(true)},
  "rift_turbulence":{"enabled":active,"active":field.active,"inside":field.inside,"phase_seconds":phase,"seconds_to_change":maxf(0.0,remaining),"bounds":f.bounds.duplicate(),"force":field.force,"torque":field.torque,"peak_force":float(f.peak_force),"peak_torque":float(f.peak_torque),"period_seconds":float(f.period_seconds),"active_seconds":float(f.active_seconds)}}

func snapshot()->Dictionary:
 return {"active":active,"activated_at":activated_at,"hazard_index":hazard_index,"shots_fired":shots_fired,"next_lock_at":next_lock_at,"warning":warning.duplicate(true),"ray_records":ray_records.duplicate(true)}
