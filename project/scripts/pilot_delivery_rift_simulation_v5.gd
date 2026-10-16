extends "res://scripts/pilot_delivery_simulation_v3.gd"
## New protocol; chronological portal events share the inherited collision clock.
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const RiftThreats=preload("res://scripts/delivery_rift_threats_v1.gd")
var rift_route_error:String=""
var portal_crossings:Array=[]
var _rift_ready:bool=false
var _rift_attempted:Dictionary={}
var _rift_denied:Dictionary={}
var _rift_exposure:Dictionary={}
var _rift_forces_applied:bool=false
var _rift_threats=RiftThreats.new()

func configure(design:Array,launcher:Array,route_data:Dictionary,random_seed:int=1)->void:
 _rift_ready=false;portal_crossings.clear();_rift_attempted.clear();_rift_denied.clear();_rift_exposure.clear();_rift_forces_applied=false
 _rift_threats=RiftThreats.new()
 rift_route_error=Rift.validation_error(route_data)
 if not rift_route_error.is_empty():
  super.configure([],[],route_data,random_seed)
  free_route_error=rift_route_error;delivery_route_error=rift_route_error
  telemetry.control_version=Rift.VERSION;telemetry.route_error=rift_route_error;return
 super.configure(design,launcher,Rift.compatibility_route(route_data),random_seed)
 route=route_data.duplicate(true);free_route_error="";delivery_route_error=""
 _rift_threats.configure(route);_rift_ready=true
 _refresh_telemetry()

func _tick(dt:float)->void:
 _rift_attempted.clear();_rift_forces_applied=false
 if _rift_ready:_rift_threats.before_tick(self,dt)
 super._tick(dt)

func _act(p:Dictionary,b:Dictionary,dt:float,rising:bool)->void:
 # Cargo is a passive enabled module. This hook runs after the base force reset,
 # before integration, and applies the field to every body, including debris.
 if _rift_ready and not _rift_forces_applied:
  _rift_forces_applied=true;_rift_threats.add_forces(self,dt)
 super._act(p,b,dt,rising)

func _next_contact(used_drills:Dictionary)->Dictionary:
 var ordinary:Dictionary=super._next_contact(used_drills)
 if not _rift_ready:return ordinary
 var gate:Dictionary=route.rift_portal
 var entry:Vector2=Vector2(gate.entry[0],gate.entry[1])
 var best:Dictionary={}
 for body in bodies:
  if not _contains_cargo(body) or _rift_body_visited(body) or _rift_attempted.has(_rift_anchor(body)):continue
  var start:Vector2=_motion_bodies.get(body.id,{}).get("position",body.position)
  var finish:Vector2=body.position
  # Teleporters have already moved _motion_bodies to their checked exit, so their
  # skipped segment cannot manufacture a physical crossing.
  if start.x>entry.x+EPS or finish.x<entry.x or finish.x<=start.x+EPS:continue
  var fraction:float=clampf((entry.x-start.x)/(finish.x-start.x),0.0,1.0)
  if absf(start.lerp(finish,fraction).y-entry.y)>float(gate.aperture_radius):continue
  var candidate:Dictionary={"p":_rift_anchor(body),"q":-1,"h":-1,"time":fraction,"normal":Vector2.LEFT,"rift_portal_event":true}
  if best.is_empty() or fraction<float(best.time) or (fraction==float(best.time) and int(candidate.p)<int(best.p)):best=candidate
 # A real collision wins any tie; transit cannot erase an earlier impact.
 if best.is_empty() or (not ordinary.is_empty() and float(ordinary.time)<=float(best.time)):return ordinary
 return best

func _try_collinear_contacts(hit:Dictionary)->bool:
 return false if hit.get("rift_portal_event",false) else super._try_collinear_contacts(hit)

func _apply_swept_impulse(hit:Dictionary)->void:
 if not hit.get("rift_portal_event",false):super._apply_swept_impulse(hit);return
 var body:Dictionary=body_for_part(int(hit.p))
 if body.is_empty():return
 _rift_attempted[_rift_anchor(body)]=true
 if _rift_body_visited(body):return
 var gate:Dictionary=route.rift_portal
 var entry:Vector2=Vector2(gate.entry[0],gate.entry[1])
 var radius:float=_rift_bound(body)
 if absf(body.position.y-entry.y)+radius+float(gate.margin)>float(gate.aperture_radius):
  _rift_deny(body,"too_large_or_off_center","门户未通过：请对准入口，并让整船轮廓适配洞口。");return
 var target:Vector2=Vector2(gate.exit[0],gate.exit[1])+Vector2(radius+float(gate.margin),body.position.y-entry.y)
 if not _rift_safe_exit(body,target,radius,float(gate.exit_lookahead)):
  _rift_deny(body,"exit_blocked","门户出口无法容纳整船或前方净空不足，请重新选择过门时机。");return
 var from:Vector2=body.position
 var ids:Array=[];var cargo_ids:Array=[]
 body.position=target
 for p in body.parts:
  if not p.alive or p.delivered:continue
  p.rift_crossing_tick=pilot_tick;p.rift_portal_id=str(gate.id);ids.append(int(p.id))
  if p.type=="cargo":cargo_ids.append(int(p.id))
  _motion_parts[p.id]=_part_position(p)
 ids.sort();cargo_ids.sort()
 portal_crossings.append({"portal_id":str(gate.id),"tick":pilot_tick,"part_ids":ids,"cargo_ids":cargo_ids,
  "from":[from.x,from.y],"to":[target.x,target.y],"body_radius":radius,"margin":float(gate.margin)})
 # This passive fixed gate changes coordinates only: no hidden battery charge,
 # velocity reset, angular damping, cargo repair, or replacement modules.
 _rift_threats.activate(self)
 _log("整船已通过裂隙门，进入苔光温室区域。")
 _effect("wormhole",target,from,0.35)

func _rift_bound(body:Dictionary)->float:
 var radius:float=0.0
 for p in body.parts:
  if p.alive and not p.delivered:radius=maxf(radius,p.local_pos.length()+(0.48 if p.type=="drill" else 0.43)*p.scale)
 return radius
func _rift_anchor(body:Dictionary)->int:
 var result:int=2147483647
 for p in body.parts:
  if p.alive and not p.delivered:result=mini(result,int(p.id))
 return result
func _rift_body_visited(body:Dictionary)->bool:
 for p in body.parts:
  if p.type=="cargo" and p.get("rift_portal_id","")==route.get("required_portal_id",""):return true
 return false
func _rift_safe_exit(body:Dictionary,target:Vector2,radius:float,seconds:float)->bool:
 var expanded:float=radius+float(route.rift_portal.margin)
 var finish:Vector2=target+body.velocity*seconds
 if minf(target.x,finish.x)-expanded< -30.0:return false
 if maxf(absf(target.y),absf(finish.y))+expanded>float(route.get("boundary_y",80.0)):return false
 for hi in range(obstacles.size()):
  var h:Dictionary=obstacles[hi]
  if h.health<=0.0 or h.type=="gravity":continue
  var at:Vector2=_motion_hazards[hi] if hi<_motion_hazards.size() else h.position
  var relative:Vector2=target-at
  var end:Vector2=finish-at-h.get("velocity",Vector2.ZERO)*seconds
  var clearance:float=expanded+float(h.radius)
  if relative.length()<=clearance or _segment_circle_t(relative,end,clearance)>=0.0:return false
 # The far-side raider already occupies its frozen world position even before
 # its first visible activation tick; a hidden spawn may not invalidate clearance.
 if _rift_threats.hazard_index<0:
  var pirate:Dictionary=route.rift_pirate
  var occupied:Vector2=Vector2(pirate.position[0],pirate.position[1])
  var clearance:float=expanded+float(pirate.radius)
  if (target-occupied).length()<=clearance or _segment_circle_t(target-occupied,finish-occupied,clearance)>=0.0:return false
 for other in bodies:
  if other.id==body.id:continue
  var relative:Vector2=target-other.position
  var end:Vector2=finish-other.position-other.velocity*seconds
  var clearance:float=expanded+_rift_bound(other)
  if relative.length()<=clearance or _segment_circle_t(relative,end,clearance)>=0.0:return false
 return true
func _rift_deny(body:Dictionary,reason:String,message:String)->void:
 var key:String="%s:%s"%[_rift_anchor(body),reason]
 if not _rift_denied.has(key):_rift_denied[key]=true;_log(message)
 telemetry.portal_last_denial=reason

func _enemy_attacks(dt:float)->void:
 super._enemy_attacks(dt)
 if not _rift_ready:return
 _rift_threats.after_tick(self,dt)
 var bio:Dictionary=route.rift_biology
 var values:Array=bio.cold_bounds
 var bounds:Rect2=Rect2(values[0],values[1],values[2],values[3])
 for p in parts.values():
  if p.type!="cargo" or not p.alive or p.delivered:continue
  var cold:bool=p.get("rift_portal_id","")==route.required_portal_id and bounds.has_point(_part_position(p))
  var previous:float=float(_rift_exposure.get(p.id,0.0))
  var current:float=previous+dt if cold else 0.0
  _rift_exposure[p.id]=current
  if cold:
   var harmful:float=maxf(0.0,current-float(bio.grace_seconds))-maxf(0.0,previous-float(bio.grace_seconds))
   var loss:float=harmful*float(bio.damage_hp_per_second)
   # One physical adjacent live heater protects this cargo; stacked modules
   # cannot produce immunity. Payment uses the actual current circuit.
   var heaters:Array=[]
   for module in parts.values():
    if module.type=="heater" and _enabled(module) and _same_circuit(p,module) and _linked(p.id,module.id):heaters.append(int(module.id))
   heaters.sort()
   if not heaters.is_empty():
    var heater:Dictionary=parts[heaters[0]]
    var material:float=clampf(float(heater.output_factor),0.0,1.0)
    var desired:float=Expanded.HEATER_POWER*dt*material
    var ratio:float=_consume(body_for_part(heater.id),desired,heater.id,dt)
    var avoided:float=loss*Expanded.HEATER_PROTECTION*ratio*material
    loss-=avoided
    telemetry.heater_energy_used=float(telemetry.get("heater_energy_used",0.0))+desired*ratio
    telemetry.heater_cold_prevented=float(telemetry.get("heater_cold_prevented",0.0))+avoided
   _cargo_damage(p,loss,"biological_cold")
   telemetry.biological_damage=float(telemetry.get("biological_damage",0.0))+loss

func _check_status()->void:
 if _rift_ready:
  var receiver:Vector2=Vector2(route.distance,route.destination_y)
  for p in parts.values():
   if p.type!="cargo" or not p.alive or p.delivered:continue
   if _part_position(p).distance_to(receiver)<=float(route.delivery_radius) and p.get("rift_portal_id","")!=route.required_portal_id:
    status="failed";telemetry.delivery_failure="required_portal_not_crossed";telemetry.free_failure="required_portal_not_crossed";telemetry.delivery_qualified=false
    _log("未实际通过指定裂隙门，当前区域不能交付此单。");return
 super._check_status()

func _refresh_telemetry()->void:
 super._refresh_telemetry()
 telemetry.control_version=Rift.VERSION;telemetry.input_schema=Rift.INPUT_SCHEMA
 telemetry.required_portal_id=str(route.get("required_portal_id",Rift.PORTAL_ID))
 telemetry.portal_crossings=portal_crossings.duplicate(true)
 telemetry.portal_crossing_tick=-1;telemetry.region="departure"
 telemetry.biological_temperature_c=float(route.get("rift_biology",{}).get("warm_temperature_c",18.0))
 telemetry.biological_exposure_seconds=0.0
 if not telemetry.has("biological_damage"):telemetry.biological_damage=0.0
 if not telemetry.has("portal_last_denial"):telemetry.portal_last_denial=""
 for event in portal_crossings:
  if telemetry.portal_crossing_tick<0:telemetry.portal_crossing_tick=int(event.tick)
  else:telemetry.portal_crossing_tick=mini(telemetry.portal_crossing_tick,int(event.tick))
 if not _rift_ready:return
 var bio:Dictionary=route.rift_biology
 var box:Array=bio.cold_bounds
 var bounds:Rect2=Rect2(box[0],box[1],box[2],box[3])
 for p in parts.values():
  if p.type!="cargo":continue
  if p.get("rift_portal_id","")==route.required_portal_id:
   telemetry.region="greenhouse"
   if p.alive and bounds.has_point(_part_position(p)):telemetry.biological_temperature_c=float(bio.cold_temperature_c)
  telemetry.biological_exposure_seconds=maxf(float(telemetry.biological_exposure_seconds),float(_rift_exposure.get(p.id,0.0)))
 telemetry.merge(_rift_threats.telemetry(self),true)
