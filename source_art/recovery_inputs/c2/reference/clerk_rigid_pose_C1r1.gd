extends RefCounted
## Pure, caller-owned presentation math. All positions are logical parent/world
## coordinates. No timers, process callback, input, controller, textures or RNG.
const STATES:Array[String] = ["idle", "start", "move", "inertial_stop", "stop"]
const TRAVEL:Array[String] = ["start", "move", "inertial_stop"]
const SIDES:Array[String] = ["far", "near"]
const SETTLE_SECONDS:float = 0.28
const EPS:float = 0.00001
var reference_height:float = 240.0
var target_height:float = 210.0
var config:Dictionary = {}
var feet:Dictionary = {}
var joints:Dictionary = {}
var origin:Vector2 = Vector2.ZERO
var hip:Vector2 = Vector2.ZERO
var facing_right:bool = true
var state:String = "idle"
var support:String = "near"
var swing:String = "far"
var step_fraction:float = 0.0
var step_distance:float = 0.0
var distance_rebases:int = 0
var initialized:bool = false
var travelling:bool = false
var settling:bool = false
var settled:bool = true
var pose_time:float = 0.0
var shoulder_offset:Vector2 = Vector2.ZERO
var arm_angle:float = 0.0
var head_angle:float = 0.0
var eye_state:String = "open"
var max_reach_error:float = 0.0
var _last_distance:float = 0.0
var _last_clock:float = 0.0
var _freeze_clock:bool = false
var _step_start:Vector2 = Vector2.ZERO
var _step_direction:Vector2 = Vector2.RIGHT
var _swing_from:Vector2 = Vector2.ZERO
var _swing_target:Vector2 = Vector2.ZERO
var _swing_landed:bool = false
var _settle_start:float = 0.0
var _settle_from:Vector2 = Vector2.ZERO
var _settle_to:Vector2 = Vector2.ZERO
var _settle_arm:float = 0.0
var _settle_shoulder:Vector2 = Vector2.ZERO
var _clock_offset:float = 0.0
var _upper_from_angle:float = 0.0
var _upper_from_shoulder:Vector2 = Vector2.ZERO
var _upper_distance:float = 0.0
var _extension_weight:float = 1.0
var _extension_from:float = 1.0
var _settle_extension:float = 0.0
# FG01-C1r1 tuning changes pose trajectories only; frozen registration is copied.
const HIP_RELAX_DROP:float = 5.5
const SWING_LIFT:float = 6.0
var upper_body:Dictionary = {}
var _pelvis_angle:float = 0.0
var _torso_angle:float = 0.0
var _head_world:float = 0.0
var _current_step:float = 1.0
var _settle_hip:Vector2 = Vector2.ZERO
var _settle_pelvis:float = 0.0
var _settle_torso:float = 0.0
var _settle_head:float = 0.0
var _from_pelvis:float = 0.0
var _from_torso:float = 0.0
var _from_head:float = 0.0
var _from_hip:Vector2 = Vector2.ZERO
var _settle_moved:bool = false
var _reach_feasible:bool = true
var _facing_changed:bool = false

func configure(data:Dictionary, height:float = 210.0) -> bool:
 if height <= 0.0 or not is_finite(height):return false
 for side in SIDES:
  if not data.get("legs", {}).get(side) is Dictionary:return false
  var leg:Dictionary = data.legs[side]
  if float(leg.get("thigh_length", 0.0)) <= 0.0 or float(leg.get("shin_length", 0.0)) <= 0.0:return false
 config = data.duplicate(true);target_height = height
 reference_height = float(data.get("reference_height", 240.0))
 return reference_height > 0.0 and is_finite(reference_height)

func _s() -> float:return target_height / reference_height
func _sign() -> float:return 1.0 if facing_right else -1.0
func _v(value:Variant) -> Vector2:return Vector2(float(value[0]), float(value[1]))
func half_step() -> float:return float(config.get("half_step", 64.0)) * _s()

func reset(at:Vector2, right:bool, clock:float = 0.0, distance:float = 0.0) -> void:
 origin = at;facing_right = right;state = "idle";initialized = true
 travelling = false;settling = false;settled = true;step_distance = 0.0;step_fraction = 0.0
 _extension_weight = 1.0;_extension_from = 1.0
 _last_distance = distance;_last_clock = clock;pose_time = clock;_clock_offset = 0.0
 feet.clear()
 for side in SIDES:
  var offset:Vector2 = _v(config.legs[side].get("neutral_sole", [18.0 if side == "near" else -18.0, 0.0])) * _s()
  offset.x *= _sign()
  feet[side] = {"position": at + offset, "planted": true, "landing_id": 0}
 support = _choose_support();swing = _other(support)
 _pelvis_angle=0.0;_torso_angle=0.0;_head_world=0.0;arm_angle=0.0;shoulder_offset=Vector2.ZERO
 _facing_changed=false;_freeze_clock=false;distance_rebases=0
 _settle_hip=_v(config.hip)*_s()+Vector2(0,HIP_RELAX_DROP*_s())
 _upper_pose(false);_solve();_upper_transforms()

func freeze(clock:float, distance:float) -> void:
 # Only bookkeeping changes. A hidden/inactive call never moves a displayed
 # foot, head, phase, recovery or eye. First resumed call excludes elapsed time.
 if is_finite(clock):_last_clock = clock
 if is_finite(distance):_last_distance = distance
 _freeze_clock = true

func update(next_state:String, distance:float, at:Vector2, right:bool, clock:float, stop_age:float = 0.0, enabled:bool = true, reduced_motion:bool = false) -> bool:
 if next_state not in STATES or not at.is_finite() or not is_finite(distance) or distance < 0.0 or not is_finite(clock) or not is_finite(stop_age):return false
 if config.is_empty():return false
 if not enabled:
  freeze(clock, distance);return false
 if not initialized:reset(at, right, clock, distance)
 var old_origin:Vector2 = origin
 var displacement:Vector2 = at - old_origin
 var actual:float = displacement.length()
 var distance_delta:float = distance - _last_distance
 if _freeze_clock:
  _clock_offset += maxf(0.0, clock - _last_clock)
  # The owner normally freezes its visual clock. This also handles a caller
  # that keeps a global clock while the actor alone is hidden.
  _clock_offset = clock - pose_time
  _freeze_clock = false
 elif clock < _last_clock:
  _clock_offset = clock - pose_time
 pose_time = clock - _clock_offset;_last_clock = clock;_last_distance = distance
 state = next_state
 if distance_delta < -EPS:distance_rebases += 1
 if actual > half_step() * 1.5:
  # Teleports/reset never drag old world foot targets across the room.
  distance_rebases += 1;reset(at, right, clock, distance);state = next_state
  return true
 # Counter resets of cumulative distance alone do not justify a visible snap.
 var direction_change:bool = right != facing_right
 _facing_changed=direction_change
 facing_right = right;origin = at
 if actual > EPS:
  if not travelling or direction_change:
   _begin_step(old_origin, displacement.normalized())
  _advance_travel(old_origin, at, actual)
 elif travelling and next_state not in TRAVEL:
  _begin_settle(stop_age)
 if actual <= EPS and next_state in TRAVEL:
  # A blocked controller cannot march in place or advance a swing by time.
  pass
 elif next_state not in TRAVEL:
  if travelling:_begin_settle(stop_age)
  if settling:_advance_settle()
 _upper_pose(reduced_motion)
 _solve()
 _upper_transforms()
 return true

func _other(side:String) -> String:return "far" if side == "near" else "near"

func _choose_support() -> String:
 var planted:Array[String] = []
 for side in SIDES:
  if bool(feet[side].planted):planted.append(side)
 if planted.size() == 1:return planted[0]
 if planted.size() == 2:
  # Leading planted shoe can support the next complete step. Keeping its
  # anatomical identity avoids relabeling/flipping world anchors on reversal.
  return "near" if (feet.near.position.x - feet.far.position.x) * _sign() >= 0.0 else "far"
 return support # The construction always has at least one planted shoe.

func _begin_step(at:Vector2, direction:Vector2) -> void:
 support = _choose_support();swing = _other(support)
 _upper_from_angle = arm_angle;_upper_from_shoulder = shoulder_offset;_upper_distance = 0.0
 _extension_from = _extension_weight
 _from_pelvis=_pelvis_angle;_from_torso=_torso_angle;_from_head=_head_world;_from_hip=hip-at
 var available:float=(feet[support].position-at-_landing_offset(support)).dot(direction)+half_step()*0.5
 _current_step=clampf(available,half_step()*0.2,half_step())
 travelling = true;settling = false;settled = false;step_distance = 0.0;step_fraction = 0.0
 _step_start = at;_step_direction = direction
 _swing_from = feet[swing].position;_swing_landed = false
 _swing_target = at + direction * (_current_step+half_step()*0.5) + _landing_offset(swing)

func _advance_travel(from:Vector2, to:Vector2, actual:float) -> void:
 _upper_distance += actual
 var consumed:float = 0.0
 for boundary in 4:
  var take:float = minf(actual - consumed, _current_step - step_distance)
  step_distance += take;consumed += take
  step_fraction = clampf(step_distance / _current_step, 0.0, 1.0)
  # Land against the actual traversed root trajectory, including the diagonal
  # lane connector; no synthetic X distance is substituted for displacement.
  var here:Vector2 = from.lerp(to, consumed / actual)
  _swing_target = here + _step_direction * (_current_step - step_distance + half_step()*0.5) + _landing_offset(swing)
  _sample_swing()
  if step_fraction < 1.0 - EPS:break
  if not _swing_landed:
   feet[swing].position = _swing_target;feet[swing].planted = true
   feet[swing].landing_id = int(feet[swing].landing_id) + 1
  var old_support:String = support;support = swing;swing = old_support
  _step_start = here;step_distance = 0.0;step_fraction = 0.0;_current_step=half_step()
  _step_direction = (to - from).normalized()
  _swing_from = feet[swing].position;_swing_landed = false
  _swing_target = here + _step_direction * (half_step()*1.5) + _landing_offset(swing)
  if consumed >= actual - EPS:break

func _sample_swing() -> void:
 # Early/late double support. During lift/recovery only the swing chain moves.
 var start:float = 0.06
 var finish:float = 0.90
 if step_fraction <= start:
  feet[swing].position = _swing_from;return
 if step_fraction >= finish:
  if not _swing_landed:
   feet[swing].landing_id = int(feet[swing].landing_id) + 1
   feet[swing].position = _swing_target;feet[swing].planted = true;_swing_landed = true
  return
 var u:float = (step_fraction - start) / (finish - start)
 feet[swing].planted = false
 var smooth:float = u * u * (3.0 - 2.0 * u)
 feet[swing].position = _swing_from.lerp(_swing_target, smooth)
 feet[swing].position.y -= sin(PI * u) * SWING_LIFT * _s()

func _begin_settle(stop_age:float) -> void:
 support = _choose_support();swing = _other(support)
 travelling = false;settling = true;settled = false
 _settle_start = pose_time
 # stop_age belongs to physics (120 ms). Capture at the first displayed stop
 # without skipping recovery samples; its settled stance can persist into idle.
 # The longer visual recovery uses only the caller-owned visual clock.
 if stop_age < 0.0:return
 _settle_from = feet[swing].position
 _settle_arm = arm_angle;_settle_shoulder = shoulder_offset;_settle_extension = _extension_weight
 _settle_hip=hip-origin
 _settle_pelvis=_pelvis_angle;_settle_torso=_torso_angle;_settle_head=_head_world
 # Never shuffle an already planted foot. Recover only the airborne foot.
 _settle_to=feet[swing].position if bool(feet[swing].planted) else origin+_landing_offset(swing)+Vector2(_settle_hip.x,0)
 _settle_moved=not bool(feet[swing].planted)

func _advance_settle() -> void:
 var u:float = clampf((pose_time - _settle_start) / SETTLE_SECONDS, 0.0, 1.0)
 var smooth:float = u * u * (3.0 - 2.0 * u)
 feet[swing].position = _settle_from.lerp(_settle_to, smooth)
 # A grounded, widely trailing foot takes one small closing step. Do not
 # translate a shoe along the floor while describing it as planted.
 if _settle_moved:
  feet[swing].position.y -= sin(PI * u) * 4.0 * _s()
  feet[swing].planted = u >= 1.0
 if u >= 1.0:
  feet[swing].position = _settle_to;feet[swing].planted = true
  if _settle_moved:feet[swing].landing_id=int(feet[swing].landing_id)+1
  settling = false;settled = true

func _landing_offset(side:String) -> Vector2:
 var leg:Dictionary=config.legs[side]
 return Vector2((_v(leg.hip_offset).x+_v(leg.sole_from_ankle).x)*_sign()*_s(),0.0)

func _socket(side:String) -> Vector2:
 return (_v(config.legs[side].hip_offset)*Vector2(_sign(),1.0)*_s()).rotated(_pelvis_angle)

func _ankle(side:String) -> Vector2:
 return feet[side].position-_v(config.legs[side].sole_from_ankle)*Vector2(_sign(),1.0)*_s()

func _inside(p:Vector2,centers:Array[Vector2],radii:Array[float],inner:Array[float]) -> bool:
 for i in 2:
  var d:float=p.distance_to(centers[i])
  if d>radii[i]+0.00005 or d<inner[i]-0.00005:return false
 return true

func _nearest_feasible(target:Vector2,centers:Array[Vector2],radii:Array[float],inner:Array[float]) -> Vector2:
 # Work in native coordinates close to zero. The feasible set is the
 # intersection of both exact two-bone reach annuli, not just outer disks.
 # Its nearest point is interior, a radial boundary projection, or a pair
 # of circle intersections. Enumerate those finite candidates deterministically.
 if _inside(target,centers,radii,inner):return target
 var choices:Array[Vector2]=[]
 var cs:Array[Vector2]=[centers[0],centers[0],centers[1],centers[1]]
 var rs:Array[float]=[radii[0],inner[0],radii[1],inner[1]]
 for i in 4:
  var direction:Vector2=(target-cs[i]).normalized()
  if direction.length_squared()<EPS:direction=Vector2.UP
  var p:Vector2=cs[i]+direction*rs[i]
  if _inside(p,centers,radii,inner):choices.append(p)
  for j in range(i+1,4):
   var delta:Vector2=cs[j]-cs[i];var d:float=delta.length()
   if d<=EPS or d>rs[i]+rs[j] or d<absf(rs[i]-rs[j]):continue
   var a:float=(rs[i]*rs[i]-rs[j]*rs[j]+d*d)/(2.0*d)
   var h:float=sqrt(maxf(0.0,rs[i]*rs[i]-a*a));var v:Vector2=delta/d
   var center:Vector2=cs[i]+v*a;var normal:Vector2=Vector2(-v.y,v.x)*h
   for point in [center+normal,center-normal]:
    if _inside(point,centers,radii,inner):choices.append(point)
 if choices.is_empty():
  _reach_feasible=false
  return target
 var best:Vector2=choices[0]
 for point in choices:
  if point.distance_squared_to(target)<best.distance_squared_to(target):best=point
 return best

func _solve() -> void:
 var desired:Vector2=origin+_v(config.hip)*_s()+Vector2(0,HIP_RELAX_DROP*_s())
 if not travelling:desired=origin+_settle_hip
 else:
  var u:float=clampf(_upper_distance/(half_step()*0.5),0.0,1.0)
  desired=origin+_from_hip.lerp(desired-origin,u*u*(3.0-2.0*u))
 var centers:Array[Vector2]=[];var radii:Array[float]=[];var inner:Array[float]=[]
 for side in SIDES:
  var leg:Dictionary=config.legs[side]
  centers.append((_ankle(side)-origin-_socket(side))/_s())
  radii.append(float(leg.thigh_length)+float(leg.shin_length)-0.002)
  inner.append(absf(float(leg.thigh_length)-float(leg.shin_length))+0.002)
 _reach_feasible=true
 hip=origin+_nearest_feasible((desired-origin)/_s(),centers,radii,inner)*_s()
 max_reach_error=0.0
 for side in SIDES:
  var leg:Dictionary=config.legs[side]
  var at:Vector2=hip+_socket(side);var ankle:Vector2=_ankle(side)
  var l1:float=float(leg.thigh_length)*_s();var l2:float=float(leg.shin_length)*_s()
  var d:float=at.distance_to(ankle)
  var valid:float=clampf(d,absf(l1-l2)+0.00001,l1+l2-0.00001)
  var toward:Vector2=(ankle-at).normalized()
  var a:float=(l1*l1-l2*l2+valid*valid)/(2.0*valid)
  var bend:float=sqrt(maxf(0.0,l1*l1-a*a))
  var knee:Vector2=at+toward*a+Vector2(toward.y,-toward.x)*bend*_sign()
  max_reach_error=maxf(max_reach_error,absf(d-valid))
  joints[side]={"hip":at,"knee":knee,"ankle":ankle,"sole":feet[side].position}

func _upper_pose(reduced_motion:bool) -> void:
 var breath:float=0.0 if reduced_motion else sin(pose_time*1.65+0.8)*0.35*_s()
 if travelling:
  var phase:float=sin(step_fraction*PI)*(1.0 if swing=="near" else -1.0)
  var u:float=clampf(_upper_distance/(half_step()*0.5),0.0,1.0)
  var blend:float=u*u*(3.0-2.0*u)
  var weight:float=0.25 if reduced_motion else 1.0
  _pelvis_angle=lerpf(_from_pelvis,deg_to_rad(0.8)*phase*_sign()*weight,blend)
  _torso_angle=lerpf(_from_torso,-deg_to_rad(1.2)*phase*_sign()*weight,blend)
  _head_world=lerpf(_from_head,_torso_angle*0.12,blend)
  arm_angle=lerpf(_upper_from_angle,deg_to_rad(8.0)*phase*weight,blend)
  shoulder_offset=_upper_from_shoulder.lerp(Vector2.ZERO,blend)
 elif settling:
  var u:float=clampf((pose_time-_settle_start)/SETTLE_SECONDS,0.0,1.0)
  var k:float=u*u*(3.0-2.0*u)
  _pelvis_angle=lerpf(_settle_pelvis,0.0,k);_torso_angle=lerpf(_settle_torso,0.0,k)
  _head_world=lerpf(_settle_head,0.0,k);arm_angle=lerpf(_settle_arm,0.0,k)
  shoulder_offset=_settle_shoulder.lerp(Vector2(0,breath),k)
 else:
  _pelvis_angle=0.0;_torso_angle=0.0;_head_world=0.0;arm_angle=0.0
  shoulder_offset=Vector2(0,breath)
 head_angle=_head_world*_sign()
 var blink:float=fposmod(pose_time+float(config.get("blink_offset",1.73)),4.9)
 eye_state="closed" if blink<0.075 else ("half" if blink<0.115 else "open")
 if eye_state=="open" and state not in TRAVEL and not travelling and fposmod(pose_time+0.31,7.1)<0.65:eye_state="gaze"

func _upper_transforms() -> void:
 var pivot:Vector2=hip+shoulder_offset
 var shoulders:Dictionary={};var arms:Dictionary={}
 for side in SIDES:
  var offset:Vector2=_v(config.parts[side+"_arm"].attachment_offset)*Vector2(_sign(),1)*_s()
  shoulders[side]=pivot+offset.rotated(_torso_angle)
  arms[side]=_torso_angle+arm_angle*(1.0 if side=="near" else -1.0)*_sign()
 var neck_offset:Vector2=_v(config.parts.head.attachment_offset)*Vector2(_sign(),1)*_s()
 upper_body={"pelvis_world_angle":_pelvis_angle,"torso_world_angle":_torso_angle,
 "torso_pivot_world":pivot,"neck_world":pivot+neck_offset.rotated(_torso_angle),
 "shoulder_world":shoulders,"arm_world_angle":arms,"head_world_angle":_head_world,
 "head_scale":float(config.parts.head.pixel_scale)*_s(),"gaze_semantic":"forward" if state in TRAVEL else "idle",
 "orientation_space":"world","facing_changed":_facing_changed}

func snapshot() -> Dictionary:
 return {"state": state, "origin": origin, "feet": feet.duplicate(true), "joints": joints.duplicate(true),
 "hip": hip, "support": support, "swing": swing, "step_fraction": step_fraction, "step_distance": step_distance,
 "travelling": travelling, "settling": settling, "settled": settled, "facing_right": facing_right,
 "pose_time": pose_time, "arm_angle": arm_angle, "shoulder_offset": shoulder_offset, "head_angle": head_angle,
 "eye_state": eye_state, "distance_rebases": distance_rebases, "max_reach_error": max_reach_error,
 "relaxed_extension_weight": _extension_weight,"upper_body":upper_body.duplicate(true),
 "reach_feasible":_reach_feasible,"candidate":"FG01-C1r1","half_step_native":half_step()/_s(),
 "current_step_parent":_current_step,"hip_relax_drop_native":HIP_RELAX_DROP,"swing_lift_native":SWING_LIFT}
