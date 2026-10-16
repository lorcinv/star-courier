extends "res://scripts/pilot_free_simulation_v2.gd"
## New-contract delivery physics. The mature force/nozzle/circuit/CCD/load solver
## is inherited unchanged; only explicitly versioned launch, transit and cargo rules differ.
const Delivery=preload("res://scripts/pilot_delivery_profile_v3.gd")
const DeliveryLauncher=preload("res://scripts/launcher_v3.gd")
var launch_released:bool=false
var delivery_route_error:String=""
var _cargo_filtered_acceleration:Dictionary={}
var _delivery_contact_parts:Dictionary={}

func configure(design:Array,launcher:Array,route_data:Dictionary,random_seed:int=1)->void:
 launch_released=false;_cargo_filtered_acceleration.clear();_delivery_contact_parts.clear()
 delivery_route_error=Delivery.validation_error(route_data)
 free_route_error=delivery_route_error
 if not delivery_route_error.is_empty():
  bodies.clear();_bodies_by_id.clear();parts.clear();links.clear();obstacles.clear();launcher_parts.clear();effects.clear();incidents.clear()
  route=route_data.duplicate(true);status="failed";elapsed=0.0;events=[delivery_route_error]
  telemetry={"control_version":Delivery.VERSION,"route_error":delivery_route_error,"launch_released":false,"delivery_qualified":false,"delivery_failure":"invalid_route"}
  return
 # Inheritance reuse is private; exact new identity is restored before returning.
 super.configure(design,launcher,Delivery.compatibility_route(route_data),random_seed)
 route=route_data.duplicate(true)
 _refresh_telemetry()

func _prepare_launcher(design:Array)->void:DeliveryLauncher.prepare(self,design)
func preview_launcher(angle_degrees:float=0.0,power_fraction:float=1.0)->Dictionary:
 return DeliveryLauncher.preview(self,angle_degrees,power_fraction)
func release_launcher(angle_degrees:float=0.0,power_fraction:float=1.0)->Dictionary:
 return DeliveryLauncher.release(self,angle_degrees,power_fraction)
func step(dt:float)->void:
 if not launch_released:return
 super.step(dt)

func _enabled(p:Dictionary)->bool:
 # In this new protocol, ship springs are passive cargo mounts. The old active
 # accumulator/launcher behavior remains exact in all older protocol solvers.
 if p.type=="spring":return false
 return super._enabled(p)

func _charge_springs(_dt:float)->void:
 # A passive suspension stores energy only by mechanical deflection, not an
 # invisible electrical compressor. The anchored launch bank is charged once
 # at release by DeliveryLauncher, outside this ship-only tick hook.
 pass

func selectable_device_ids()->Array:
 var result:Array=[]
 for id in super.selectable_device_ids():
  if parts[id].type!="spring":result.append(id)
 return result

func teleport_energy_cost(body:Dictionary,distance:float)->float:
 if body.is_empty() or not is_finite(distance):return INF
 return maxf(0.0,float(body.get("mass",0.0)))*absf(distance)*float(route.get("teleport_joules_per_kg_metre",Delivery.TELEPORT_JOULES_PER_KG_METRE))

func _act(p:Dictionary,b:Dictionary,dt:float,rising:bool)->void:
 if p.type in ["airbrake","solid_booster"]:
  var force_before:Vector2=b.force
  super._act(p,b,dt,rising)
  var delta:Vector2=(b.force-force_before)*dt/maxf(EPS,float(b.mass))
  for cargo in b.parts:
   if cargo.type=="cargo":_pulse_damage(cargo,delta,dt,"solid_booster_acceleration" if p.type=="solid_booster" else "airbrake_deceleration")
  return
 if p.type!="teleporter":super._act(p,b,dt,rising);return
 _sources_live=true
 if not rising:return
 var delta:Vector2=teleport_direction(b,p)*p.param
 var cost:float=teleport_energy_cost(b,delta.length())
 telemetry.delivery_teleport_last_cost=cost
 if not destination_clear(b,delta):
  _log("位移失败：出口无法容纳整船或前方净空不足。");return
 if not _can_supply(b,cost,p.id,dt):
  _log("位移失败：搬运 %.1f kg × %.1f m 需要 %.1f J，当前电路无法供给。"%[b.mass,delta.length(),cost]);return
 _consume(b,cost,p.id,dt)
 var before:Vector2=b.position
 b.position+=delta
 # Transit skips the gap; start CCD at the checked exit with momentum unchanged.
 if _motion_bodies.has(b.id):_motion_bodies[b.id].position+=delta
 for q in b.parts:
  if _motion_parts.has(q.id):_motion_parts[q.id]+=delta
 telemetry.free_teleport_count=int(telemetry.get("free_teleport_count",0))+1
 telemetry.free_last_teleport_x=delta.x;telemetry.free_last_teleport_y=delta.y
 telemetry.delivery_teleport_energy=float(telemetry.get("delivery_teleport_energy",0.0))+cost
 _log("位移：%.1f kg × %.1f m，消耗 %.1f J；速度保持。"%[b.mass,delta.length(),cost])
 _effect("teleport",b.position,before,0.6)

func cargo_mount_properties(cargo:Dictionary,component_ids:Array=[])->Dictionary:
 # Only a direct living mount participates. A spare somewhere on the same body
 # cannot protect cargo, and a named part with zero setting has zero effect.
 var elastic_energy:float=0.0;var strength:float=0.0;var damping:float=0.0
 for edge in links:
  var other:int=int(edge.b) if int(edge.a)==int(cargo.id) else (int(edge.a) if int(edge.b)==int(cargo.id) else -1)
  if other<0 or not parts.has(other):continue
  # Optional read-only post-cut scope is used by the instantaneous preview.
  if not component_ids.is_empty() and not component_ids.has(other):continue
  var mount:Dictionary=parts[other]
  if not mount.alive or mount.delivered or (int(mount.target)>=0 and int(mount.target)!=int(cargo.id)):continue
  var condition:float=clampf(float(mount.hp)/maxf(EPS,float(mount.max_hp)),0.0,1.0)
  if mount.type=="spring" and mount.param>0.0:
   elastic_energy+=float(mount.param)*condition;strength+=minf(float(mount.strength),float(edge.strength))*condition
  elif mount.type=="damper" and mount.param>0.0 and _mount_enabled_after_cut(mount,component_ids):damping+=float(mount.param)*condition
 # E=F²/(2k), tau=sqrt(m/k). Multiple parallel mounts add k and capacity.
 var stiffness:float=strength*strength/(2.0*elastic_energy) if elastic_energy>EPS else 0.0
 var response:float=sqrt(float(cargo.mass)/stiffness) if stiffness>EPS else 0.0
 # A damper has one module-width of effective stroke; its actual rate controls
 # how much impulse is spread in that stroke. This is a sub-grid cargo model,
 # never an external hull force, a battery recharge or a second health bar.
 var damper_seconds:float=0.43*damping/(1.0+damping) if damping>EPS else 0.0
 response=response*(1.0+damping*response)+damper_seconds
 return {"elastic_energy":elastic_energy,"strength":strength,"stiffness":stiffness,"damping":damping,"response_seconds":response}

func _mount_enabled_after_cut(mount:Dictionary,component_ids:Array)->bool:
 # A surviving direct mount cannot read a wire across the previewed cut. Actual
 # runtime calls use the empty default and retain the exact old _enabled chain.
 if not component_ids.is_empty() and not mount.forced_signal and int(mount.input_a)>=0 and not component_ids.has(int(mount.input_a)):return false
 return _enabled(mount)

static func cargo_pulse_preview(cargo:Dictionary,delta_velocity:Vector2,seconds:float,mount:Dictionary,route_data:Dictionary,source:String="accelerator_pulse")->Dictionary:
 # Pure extraction of the published pulse mathematics. No new stroke, axis,
 # capacity, damage scale, status change or mutation is introduced here.
 var duration:float=maxf(1.0/120.0,seconds)+float(mount.response_seconds)
 var acceleration:float=delta_velocity.length()/duration
 var excess:float=maxf(0.0,delta_velocity.length()-float(route_data.cargo_safe_acceleration)*duration)
 var damage:float=excess*float(route_data.cargo_damage_per_excess_mps)
 if not cargo.alive or cargo.delivered or delta_velocity.length_squared()<=EPS:acceleration=0.0;damage=0.0
 # _cargo_damage has always ignored <=EPS requests. Preview the same HP result.
 if damage<=EPS:damage=0.0
 var maximum:float=maxf(EPS,float(cargo.max_hp))
 var before:float=clampf(float(cargo.hp)/maximum,0.0,1.0)
 var after:float=clampf((float(cargo.hp)-damage)/maximum,0.0,1.0)
 var minimum:float=float(route_data.min_delivery_integrity)
 return {"source":source,"delta_v":delta_velocity,"delta_speed":delta_velocity.length(),"release_seconds":seconds,"effective_seconds":duration,"peak_acceleration":acceleration,"damage_hp":damage,"integrity_before":before,"integrity_after":after,"min_delivery_integrity":minimum,"meets_requirement_after":after>=minimum,"mount_response_seconds":float(mount.response_seconds)}

func _cargo_damage(p:Dictionary,amount:float,source:String)->void:
 if amount<=EPS or not p.alive or p.delivered:return
 # Cargo integrity is the existing cargo HP only. No route-independent player HP.
 super._damage_part(p,amount,source)
 telemetry.cargo_load_damage=float(telemetry.get("cargo_load_damage",0.0))+amount

func _pulse_damage(p:Dictionary,delta_velocity:Vector2,seconds:float,source:String)->void:
 if not p.alive or p.delivered or delta_velocity.length_squared()<=EPS:return
 var pulse:Dictionary=cargo_pulse_preview(p,delta_velocity,seconds,cargo_mount_properties(p),route,source)
 telemetry.cargo_peak_acceleration=maxf(float(telemetry.get("cargo_peak_acceleration",0.0)),float(pulse.peak_acceleration))
 _cargo_damage(p,float(pulse.damage_hp),source)

func _apply_launch_damage(delta_velocity:Vector2,seconds:float)->void:
 var b:Dictionary=_cargo_body()
 for p in b.get("parts",[]):
  if p.type=="cargo":_pulse_damage(p,delta_velocity,maxf(seconds,1.0/120.0),"launch_acceleration")
 if _graph_dirty:_rebuild_bodies()
 if ship_integrity()<=0.0:
  status="failed";telemetry.delivery_failure="cargo_destroyed";_finalize_recovery()

func _mark_contact(b:Dictionary)->void:
 for p in b.parts:
  if p.type=="cargo":_delivery_contact_parts[p.id]=true
 super._mark_contact(b)

func _collisions()->void:
 _delivery_contact_parts.clear()
 # Thrust/centripetal acceleration is proper loading. Gravity/freefall alone is
 # not cargo crushing. Sustained load reaches full strength after the mount lag.
 var before:Dictionary={}
 for p in parts.values():
  if p.type!="cargo" or not p.alive or p.delivered:continue
  var b:Dictionary=body_for_part(p.id)
  if b.is_empty():continue
  var arm:Vector2=p.local_pos.rotated(b.angle)
  var angular:float=float(b.get("torque",0.0))/maxf(EPS,float(b.inertia))
  var raw:Vector2=b.get("force",Vector2.ZERO)/float(b.mass)+Vector2(-arm.y,arm.x)*angular-arm*float(b.angular_velocity)*float(b.angular_velocity)
  var mount:Dictionary=cargo_mount_properties(p)
  var tau:float=mount.response_seconds
  var alpha:float=1.0-exp(-_tick_dt/tau) if tau>EPS else 1.0
  var filtered:Vector2=Vector2(_cargo_filtered_acceleration.get(p.id,Vector2.ZERO)).lerp(raw,alpha)
  _cargo_filtered_acceleration[p.id]=filtered
  telemetry.cargo_peak_acceleration=maxf(float(telemetry.get("cargo_peak_acceleration",0.0)),filtered.length())
  var excess:float=maxf(0.0,filtered.length()-float(route.cargo_safe_acceleration))
  _cargo_damage(p,excess*_tick_dt*float(route.cargo_damage_per_excess_mps),"cargo_acceleration")
  if p.alive:before[p.id]=_part_velocity(p)
 super._collisions()
 # Contact transmitted through an armor/beam still reaches the cargo. Use the
 # actual resolved velocity change rather than the name of the struck module.
 for id in before:
  var p:Dictionary=parts[id]
  if not p.alive or p.delivered or not _delivery_contact_parts.has(id):continue
  var change:Vector2=_part_velocity(p)-Vector2(before[id])
  var impulse:float=float(p.mass)*change.length()
  if impulse<=EPS:continue
  telemetry.cargo_contact_impulse=float(telemetry.get("cargo_contact_impulse",0.0))+impulse
  _pulse_damage(p,change,0.04,"cargo_contact_impulse")

func _damage_part(p:Dictionary,amount:float,source:String)->void:
 if source=="collision" and p.type=="cargo" and p.alive and amount>0.0:
  # Direct crushing still exists. Spread the same impulse over the mount response
  # time; peak kinetic damage falls with the square of that acceleration ratio.
  var response:float=float(cargo_mount_properties(p).response_seconds)
  var ratio:float=0.04/(0.04+response)
  super._damage_part(p,amount*float(route.cargo_contact_damage_scale)*ratio*ratio,source)
  return
 super._damage_part(p,amount,source)

func _check_status()->void:
 var receiver:Vector2=Vector2(float(route.distance),float(route.destination_y))
 var requirement:float=float(route.min_delivery_integrity)
 for p in parts.values():
  if p.type!="cargo":continue
  if not p.alive:
   status="failed";telemetry.delivery_failure="cargo_destroyed";telemetry.delivery_qualified=false
   _log("货物损毁，运输不合格。");return
  if p.delivered:continue
  if _part_position(p).distance_to(receiver)<=float(route.delivery_radius) and _part_velocity(p).length()<=float(route.max_delivery_speed):
   var integrity:float=clampf(float(p.hp)/maxf(EPS,float(p.max_hp)),0.0,1.0)
   if integrity<requirement:
    status="failed";telemetry.delivery_failure="integrity_below_requirement";telemetry.free_failure="integrity_below_requirement";telemetry.delivery_qualified=false
    _log("运输不合格：货物完整度 %.1f%%，本单要求至少 %.1f%%。"%[integrity*100.0,requirement*100.0]);return
 super._check_status()
 telemetry.delivery_qualified=status=="success" and ship_integrity()>=requirement
 if status=="failed" and str(telemetry.get("delivery_failure","")).is_empty():telemetry.delivery_failure=str(telemetry.get("free_failure","flight_failed"))

func _refresh_telemetry()->void:
 super._refresh_telemetry()
 telemetry.control_version=Delivery.VERSION;telemetry.input_schema=Delivery.INPUT_SCHEMA
 telemetry.free_teleport_policy=Delivery.MARKERS.free_teleport_policy
 telemetry.launch_released=launch_released
 telemetry.delivery_integrity=ship_integrity()
 telemetry.min_delivery_integrity=float(route.get("min_delivery_integrity",1.0))
 telemetry.integrity_meets_requirement=float(telemetry.delivery_integrity)>=float(telemetry.min_delivery_integrity)
 telemetry.delivery_qualified=status=="success" and float(telemetry.delivery_integrity)>=float(telemetry.min_delivery_integrity)
 for key in ["cargo_peak_acceleration","cargo_contact_impulse","cargo_load_damage","delivery_teleport_energy"]:
  if not telemetry.has(key):telemetry[key]=0.0
 if not telemetry.has("delivery_failure"):telemetry.delivery_failure=""
 if telemetry.delivery_failure=="integrity_below_requirement":telemetry.arrival_state="integrity_rejected"
 telemetry.cargo_safe_acceleration=float(route.get("cargo_safe_acceleration",40.0))
 telemetry.delivery_teleport_joules_per_kg_metre=Delivery.TELEPORT_JOULES_PER_KG_METRE
