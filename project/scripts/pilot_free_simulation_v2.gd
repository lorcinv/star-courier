extends "res://scripts/pilot_extreme_simulation.gd"
## Versioned force-control free flight. Old free-v1 and pilot-v1/v2/v3 stay exact.
## Existing forces, circuits, source/socket stress, collision chronology, damage,
## launcher work, paid devices and finite batteries remain inherited.
const FreeProfile = preload("res://scripts/pilot_free_profile_v2.gd")
const LauncherV2 = preload("res://scripts/launcher_v2.gd")
const FREE_VERSION = "pilot-free-v2"
var pilot_axis_x_q:int=0
# Derived ONLY from this v2 recorded command stream. Zero means no direction has
# yet been recorded, so the device's installed arrow remains its initial aim.
var pilot_aim_x_q:int=0
var pilot_aim_y_q:int=0
var pilot_device_id:int=-1
var pilot_brake:bool=false
var _active_edge_device_id:int=-1
var free_route_error:String=""

func configure(design:Array, launcher:Array, route_data:Dictionary, random_seed:int=1) -> void:
 pilot_axis_x_q=0;pilot_aim_x_q=0;pilot_aim_y_q=0
 pilot_device_id=-1;pilot_brake=false;_active_edge_device_id=-1
 free_route_error=FreeProfile.validation_error(route_data)
 if not free_route_error.is_empty():
  bodies.clear();parts.clear();links.clear();obstacles.clear();launcher_parts.clear()
  route=route_data.duplicate(true);status="failed";events=[free_route_error];telemetry={"control_version":FREE_VERSION,"free_flight":true,"route_error":free_route_error}
  return
 super.configure(design,launcher,route_data,random_seed)
 # Ancestors stamp their own versions while configuring. Restore exact explicit
 # identity after they return, never reinterpret a legacy route as free flight.
 route.control_version=FREE_VERSION;route.pilot_profile=FREE_VERSION
 _refresh_telemetry()

func _prepare_launcher(design:Array) -> void:
 LauncherV2.prepare(self,design)

func set_free_flight_input(axis_x_q:int,axis_q:int,boost:bool=false,active:bool=false,device_id:int=-1,brake:bool=false) -> void:
 pilot_axis_x_q=clampi(axis_x_q,-1000,1000)
 pilot_device_id=device_id;pilot_brake=brake
 # Selection never substitutes another module; a switch while held cannot
 # manufacture a new Space/A edge and accidentally fire the next device.
 if active and not pilot_active:_active_edge_device_id=device_id
 elif not active:_active_edge_device_id=-1
 super.set_pilot_input(axis_q,boost,active)
 if pilot_axis_x_q!=0 or pilot_axis_q!=0:
  pilot_aim_x_q=pilot_axis_x_q;pilot_aim_y_q=pilot_axis_q

func set_pilot_input(axis_q:int,boost:bool=false,active:bool=false) -> void:
 # Legacy host clear/pause calls must clear X as well. Real flight ticks must use
 # set_free_flight_input so an old 1-axis stream cannot accidentally hold reverse.
 pilot_axis_x_q=0;pilot_brake=false;_active_edge_device_id=-1
 super.set_pilot_input(axis_q,boost,active)

func _enabled(p:Dictionary) -> bool:
 # Unwired manual accelerators used to auto-fire on their first tick. New v2
 # explicitly requires the cockpit sentinel, a wired signal, or a real trigger.
 if p.type=="accelerator" and p.input_a<0 and p.input_a!=COCKPIT_SIGNAL and not p.forced_signal:return false
 return super._enabled(p)

func selectable_device_ids() -> Array:
 var result:Array=[]
 for p in parts.values():
  if not p.alive or p.delivered or p.input_a!=COCKPIT_SIGNAL:continue
  if _contains_cargo(body_for_part(p.id)):result.append(int(p.id))
 result.sort()
 return result

func _read_wire(receiver:Dictionary,source_id:int,snapshot:Dictionary={}) -> bool:
 if source_id==COCKPIT_SIGNAL:
  if int(receiver.get("id",-1))!=pilot_device_id or pilot_device_id!=_active_edge_device_id:return false
 return super._read_wire(receiver,source_id,snapshot)

func _plan_pilot_forces(b:Dictionary) -> void:
 _planned_bodies[b.id]=true
 var engines:Array=[];var available_force:float=0.0
 for p in b.parts:
  if p.type=="thruster" and p.alive and _enabled(p) and _available_energy(b,p.id)>EPS:
   engines.append(p);available_force+=p.param*p.output_factor
 if engines.is_empty():return
 var input:Vector2=Vector2(float(pilot_axis_x_q),float(pilot_axis_q))/1000.0
 input=input.limit_length(1.0) # diagonals never receive sqrt(2) free power/speed
 var moving:bool=pilot_axis_x_q!=0 or pilot_axis_q!=0
 # No input means inertial coasting. Attitude assistance also consumes force,
 # so it is inactive during a coast rather than hiding a tiny automatic brake.
 if not moving and not pilot_brake:return
 var overdrive:bool=pilot_boost and moving and not pilot_brake
 var throttle:float=float(route.free_boost_throttle) if overdrive else float(route.free_drive_throttle)
 if pilot_brake:throttle=float(route.free_brake_throttle)
 var net_limit:float=available_force*throttle
 # HELD input requests force, never a target speed. Higher existing velocity
 # cannot turn forward input into counter-thrust. Inertia and paid work remain.
 # Explicit brake wins over held direction; opposite input is genuine thrust.
 var desired:Vector2=(-b.velocity*b.mass/float(route.free_brake_seconds)).limit_length(net_limit) if pilot_brake else input*net_limit
 var cargo_angle:float=b.angle
 for p in b.parts:
  if p.type=="cargo":cargo_angle+=p.local_angle;break
 # Level attitude is also requested through real offset nozzle forces. We never
 # rotate the body directly, so uneven builds and collisions still matter.
 var desired_torque:float=(-wrapf(cargo_angle,-PI,PI)*7.0-b.angular_velocity*4.5)*b.inertia
 var lever_scale:float=1.0
 for p in engines:lever_scale=maxf(lever_scale,p.local_pos.length())
 var forces:Dictionary={};var divisor:float=float(engines.size())
 for p in engines:
  forces[p.id]=Vector2.ZERO
  divisor+=3.0*p.local_pos.length_squared()/(lever_scale*lever_scale)
 var rate:float=0.95/maxf(1.0,divisor)
 for iteration in range(32):
  var force_sum:Vector2=Vector2.ZERO;var torque_sum:float=0.0
  for p in engines:
   force_sum+=forces[p.id];torque_sum+=p.local_pos.rotated(b.angle).cross(forces[p.id])
  var force_error:Vector2=force_sum-desired
  var torque_error:float=3.0*(torque_sum-desired_torque)/(lever_scale*lever_scale)
  for p in engines:
   var lever:Vector2=p.local_pos.rotated(b.angle)
   var next:Vector2=forces[p.id]-(force_error+Vector2(-lever.y,lever.x)*torque_error)*rate
   var limit:float=p.param*p.output_factor*throttle
   forces[p.id]=_project_nozzle(next,b.angle+p.local_angle,limit)
 var net:Vector2=Vector2.ZERO
 for force in forces.values():net+=force
 var scale:float=minf(1.0,net_limit/maxf(EPS,net.length()))
 for id in forces:forces[id]*=scale
 _planned_forces.merge(forces,true)

func _project_nozzle(force:Vector2,mounted_angle:float,limit:float) -> Vector2:
 if force.length_squared()<EPS or limit<=0.0:return Vector2.ZERO
 # New full swivel is explicit. The arrow remains the installed zero direction,
 # determining initial slew, energy and impulse; module position determines torque.
 var relative:float=wrapf(force.angle()-mounted_angle,-PI,PI)
 var cone:float=deg_to_rad(float(route.free_gimbal_degrees))
 var direction:Vector2=Vector2.RIGHT.rotated(mounted_angle+clampf(relative,-cone,cone))
 return direction*clampf(force.dot(direction),0.0,limit)

func _apply_vector_nozzle(p:Dictionary,b:Dictionary,dt:float) -> void:
 var planned:Vector2=_planned_forces.get(p.id,Vector2.ZERO)
 if planned.length_squared()<=EPS:return
 var target_angle:float=wrapf(planned.angle()-b.angle-p.local_angle,-PI,PI)
 var old_gimbal:float=float(p.get("gimbal_angle",0.0))
 var angle_delta:float=wrapf(target_angle-old_gimbal,-PI,PI)
 var slew:float=deg_to_rad(float(route.free_gimbal_slew_degrees))*dt
 var gimbal:float=old_gimbal+clampf(angle_delta,-slew,slew)
 var request:float=planned.length()*pow(maxf(0.0,cos(target_angle-gimbal)),2.0)
 var budget:float=_available_energy(b,p.id)
 for valve in b.parts:
  if valve.alive and valve.type=="valve" and _same_circuit(p,valve) and (valve.target==p.id or (valve.target<0 and _linked(valve.id,p.id))):
   budget=minf(budget,valve.param*dt if _enabled(valve) else 0.0)
 if budget<=EPS:return
 var ratio:float=1.0
 if _nozzle_energy(p,b,request,old_gimbal,gimbal,1.0,dt)>budget:
  var low:float=0.0;var high:float=1.0
  for iteration in range(24):
   var middle:float=(low+high)*0.5
   if _nozzle_energy(p,b,request,old_gimbal,gimbal,middle,dt)<=budget:low=middle
   else:high=middle
  ratio=low
 var energy:float=_nozzle_energy(p,b,request,old_gimbal,gimbal,ratio,dt)
 _consume(b,energy,p.id,dt)
 p.gimbal_angle=wrapf(lerpf(old_gimbal,gimbal,ratio),-PI,PI)
 var direction:Vector2=Vector2.RIGHT.rotated(b.angle+p.local_angle+p.gimbal_angle)
 var force:Vector2=direction*request*ratio
 b.force+=force;b.torque+=p.local_pos.rotated(b.angle).cross(force)
 p.pilot_force=force;p.pilot_throttle=request*ratio/maxf(EPS,p.param*p.output_factor)
 var servo_cost:float=absf(gimbal-old_gimbal)*0.08+0.04*dt
 telemetry.assist_energy_used=float(telemetry.get("assist_energy_used",0.0))+servo_cost*ratio

func teleport_direction(body:Dictionary,device:Dictionary) -> Vector2:
 # A detached device has no pilot authority and keeps its installed direction.
 # Releasing keys retains the last recorded direction; pause does not erase it.
 if _contains_cargo(body) and (pilot_aim_x_q!=0 or pilot_aim_y_q!=0):
  return Vector2(float(pilot_aim_x_q),float(pilot_aim_y_q)).normalized()
 return Vector2.RIGHT.rotated(float(body.angle)+float(device.local_angle))

func _act(p:Dictionary,b:Dictionary,dt:float,rising:bool) -> void:
 if p.type!="teleporter":
  super._act(p,b,dt,rising);return
 _sources_live=true
 if not rising:return
 var delta:Vector2=teleport_direction(b,p)*p.param
 if not destination_clear(b,delta):
  _log("位移失败：目标位置或出口前方无法容纳整个组件。");return
 if not _can_supply(b,25.0,p.id,dt):return
 _consume(b,25.0,p.id,dt)
 var before:Vector2=b.position
 b.position+=delta
 # The transit gap is not a swept collision ray. Both CCD anchors move to the
 # checked exit exactly as in the inherited device, with velocity untouched.
 if _motion_bodies.has(b.id):_motion_bodies[b.id].position+=delta
 for q in b.parts:
  if _motion_parts.has(q.id):_motion_parts[q.id]+=delta
 telemetry.free_teleport_count=int(telemetry.get("free_teleport_count",0))+1
 telemetry.free_last_teleport_x=delta.x;telemetry.free_last_teleport_y=delta.y
 _log("位移器：沿最近方向位移，出口净空，速度保持。")
 _effect("teleport",b.position,before,0.6)

func _check_status() -> void:
 var delivered:int=0
 var receiver:Vector2=Vector2(float(route.distance),float(route.destination_y))
 var empty_cargo:Array=[]
 for p in parts.values():
  if p.type!="cargo":continue
  if not p.alive:
   status="failed";telemetry.free_failure="cargo_destroyed";_log("部分货物损毁，委托失败。");return
  if p.delivered:delivered+=1;continue
  var at:Vector2=_part_position(p)
  # Arrival wins if cargo reaches the real circle safely on the last paid tick.
  # Overspeed is a missed capture, not terminal failure; overshoot and return work.
  if at.distance_to(receiver)<=float(route.delivery_radius) and _part_velocity(p).length()<=float(route.max_delivery_speed):
   _recover_cargo_hardware(p)
   p.world_pos=at;p.world_velocity=Vector2.ZERO;p.delivered=true;p.body_id=-1
   _detach(p.id);delivered+=1;_log("货箱 %d 已由平台接收。"%p.id)
  else:
   var cargo_body:Dictionary=body_for_part(p.id)
   if cargo_body.is_empty() or _available_energy(cargo_body,p.id)<=EPS:empty_cargo.append(p.id)
 telemetry.delivered_count=delivered
 if delivered==_initial_cargo_count and delivered>0:
  status="success";telemetry.delivered=true
  _log("全部货物自动投递成功：完整度 %d%%。"%int(ship_integrity()*100.0))
 elif not empty_cargo.is_empty() and _cargo_energy_failure_enabled():
  status="failed";telemetry.free_failure="usable_energy_empty"
  _log("货舱可用能量耗尽，委托失败。")
 # No gameplay elapsed, route offset, coordinate-sign or x-progress failure.
 # Physical collisions remain inherited; nonfinite state retains its safety stop.
 if _graph_dirty:_rebuild_bodies()

## Default preserves every published free/delivery protocol; v6 overrides only this policy.
func _cargo_energy_failure_enabled()->bool:return true

func _finalize_recovery() -> void:
 if _settlement_finalized:return
 var rescued:int=0
 if status=="failed":
  # Post-flight rescue classification only: no in-flight force, relocation,
  # repair, recharge or module creation. Already consumed/ammo is still billed.
  for p in parts.values():
   if p.alive and not p.delivered and not p.recovered and p.replacement_kind.is_empty():
    p.recovered=true;rescued+=1
 telemetry.recovery_policy="failed-survivors-rescued-v1"
 telemetry.rescue_recovered_count=rescued
 super._finalize_recovery()
 if rescued>0:_log("救援回收：%d 件存活模块已带回，仍按实际耗能和损坏结算。"%rescued)

func _in_recovery_zone(p:Dictionary) -> bool:
 var receiver:Vector2=Vector2(float(route.distance),float(route.destination_y))
 return _part_position(p).distance_to(receiver)<=float(route.delivery_radius) and _part_velocity(p).length()<=float(route.max_delivery_speed)

func _refresh_telemetry() -> void:
 super._refresh_telemetry()
 telemetry.control_version=FREE_VERSION;telemetry.free_flight=true
 telemetry.pilot_axis_x_q=pilot_axis_x_q;telemetry.input_schema=FreeProfile.INPUT_SCHEMA
 var at:Vector2=cargo_position()
 var receiver:Vector2=Vector2(float(route.get("distance",0.0)),float(route.get("destination_y",0.0)))
 telemetry.cargo_x=at.x;telemetry.cargo_y=at.y
 telemetry.destination_x=receiver.x;telemetry.destination_y=receiver.y
 telemetry.destination_distance=at.distance_to(receiver)
 telemetry.flight_status=status;telemetry.arrival_state="received" if status=="success" else "en_route"
 if status=="running" and telemetry.destination_distance<=float(route.get("delivery_radius",0.0)) and float(telemetry.speed)>float(route.get("max_delivery_speed",0.0)):telemetry.arrival_state="slow_down"
 var connected:Dictionary={};var energy:float=0.0;var capacity:float=0.0
 for p in parts.values():
  if p.type!="cargo" or not p.alive or p.delivered:continue
  var b:Dictionary=body_for_part(p.id)
  for q in b.get("parts",[]):
   if q.alive and not q.delivered and q.type=="battery" and not connected.has(q.id):
    connected[q.id]=true;energy+=q.energy;capacity+=q.capacity
 if status=="success":
  for q in parts.values():
   if q.alive and q.type=="battery" and q.delivered and q.recovered and not connected.has(q.id):
    connected[q.id]=true;energy+=q.energy;capacity+=q.capacity
 telemetry.energy_remaining=energy;telemetry.energy_capacity=capacity
 telemetry.energy_fraction=clampf(energy/maxf(EPS,capacity),0.0,1.0)
 telemetry.battery_capacity=capacity
 telemetry.free_nozzle_policy="paid-full-swivel-v1"
 telemetry.free_force_policy=FreeProfile.MARKERS.free_force_policy
 telemetry.free_teleport_policy=FreeProfile.MARKERS.free_teleport_policy
 telemetry.pilot_aim_x_q=pilot_aim_x_q;telemetry.pilot_aim_y_q=pilot_aim_y_q
 telemetry.pilot_device_id=pilot_device_id;telemetry.pilot_brake=pilot_brake
 telemetry.free_selectable_device_ids=selectable_device_ids()
 telemetry.free_selected_device_valid=pilot_device_id in telemetry.free_selectable_device_ids
 telemetry.free_control_mode="brake" if pilot_brake else ("thrust" if pilot_axis_x_q!=0 or pilot_axis_q!=0 else "coast")
 telemetry.free_control_hint="方向键持续施力；松开滑行；Ctrl 刹车；Shift 加力；Q 切换装置；空格启动所选装置"

func destination_clear(body: Dictionary, displacement: Vector2) -> bool:
 # Free-only exit predicate: preserve the two existing overlap/sweep passes.
 # The legacy corridor bound is deliberately absent; old protocol files stay exact.
 if not displacement.is_finite():return false
 for p in body.parts:
  var at = _part_position(p) + displacement
  var radius = 0.43 * p.scale
  for h in obstacles:
   if h.health > 0.0 and h.type != "gravity" and at.distance_to(h.position) < radius + h.radius: return false
  for other in bodies:
   if other.id == body.id: continue
   for q in other.parts:
    if at.distance_to(_part_position(q)) < radius + 0.43 * q.scale: return false

 var exit_time = 0.22
 for p in body.parts:
  if not p.alive or p.delivered: continue
  var at = _part_position(p) + displacement
  var radius: float = 0.43 * p.scale + 0.08
  var finish: Vector2 = at + _part_velocity(p) * exit_time
  for h in obstacles:
   if h.health <= 0.0 or h.type == "gravity": continue
   if at.distance_to(h.position) < radius + h.radius: return false
   var h_finish: Vector2 = h.position + h.get("velocity", Vector2.ZERO) * exit_time
   if _segment_circle_t(at - h.position, finish - h_finish, radius + h.radius) >= 0.0: return false
  for other in bodies:
   if other.id == body.id: continue
   for q in other.parts:
    if not q.alive or q.delivered: continue
    var q_at = _part_position(q)
    var q_finish = q_at + _part_velocity(q) * exit_time
    if at.distance_to(q_at) < radius + 0.43 * q.scale: return false
    if _segment_circle_t(at - q_at, finish - q_finish, radius + 0.43 * q.scale) >= 0.0: return false
 return true
