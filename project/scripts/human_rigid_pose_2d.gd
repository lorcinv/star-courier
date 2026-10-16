extends RefCounted
## Human customer only: measured low shoes and independent source limb lengths.
## Adapted from the accepted clerk displacement/support policy.
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
var _step_span:float = 32.0
var _has_travelled:bool = false
var _extension_weight:float = 1.0
var _extension_from:float = 1.0
var _settle_extension:float = 0.0

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
 travelling = false;settling = false;settled = true;step_distance = 0.0;step_fraction = 0.0;_has_travelled = false;_step_span = half_step()
 _extension_weight = 1.0;_extension_from = 1.0
 _last_distance = distance;_last_clock = clock;pose_time = clock;_clock_offset = 0.0
 feet.clear()
 for side in SIDES:
  var offset:Vector2 = _v(config.legs[side].get("neutral_sole", [18.0 if side == "near" else -18.0, 0.0])) * _s()
  offset.x *= _sign()
  feet[side] = {"position": at + offset, "planted": true, "landing_id": 0}
 support = _choose_support();swing = _other(support)
 _solve()

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
 facing_right = right;origin = at
 if actual > EPS:
  _has_travelled = true
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
 _solve()
 _upper_pose(reduced_motion)
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

func _floor_offset(side:String) -> float:
 return float(config.legs[side].get("floor_offset", 0.0)) * _s()

func _sole_baseline(side:String) -> float:
 # Anatomical sockets and shoe sole offsets determine each foot track. The
 # broad human pelvis must not borrow the clerk's near-central hip positions.
 return (_v(config.hip).x + _v(config.legs[side].hip_offset).x + _v(config.legs[side].sole_from_ankle).x) * _sign() * _s()

func _landing(at:Vector2, direction:Vector2, remaining:float, side:String) -> Vector2:
 return at + direction * remaining + Vector2(_sole_baseline(side) + _sign() * float(config.get("landing_ahead", 18.0)) * _s(), _floor_offset(side))

func _begin_step(at:Vector2, direction:Vector2) -> void:
 support = _choose_support();swing = _other(support)
 _upper_from_angle = arm_angle;_upper_from_shoulder = shoulder_offset;_upper_distance = 0.0
 _extension_from = _extension_weight
 travelling = true;settling = false;settled = false;step_distance = 0.0;step_fraction = 0.0
 _step_start = at;_step_direction = direction
 # First/reversal steps end before the existing support exceeds its measured
 # comfortable trailing reach. Later alternating steps can use the full span.
 var forward:float = (feet[support].position.x - at.x - _sole_baseline(support)) * _sign()
 _step_span = clampf(forward + float(config.get("max_trailing", 22.0)) * _s(), 6.0 * _s(), half_step())
 _swing_from = feet[swing].position;_swing_landed = false
 _swing_target = _landing(at, direction, _step_span, swing)

func _advance_travel(from:Vector2, to:Vector2, actual:float) -> void:
 _upper_distance += actual
 var consumed:float = 0.0
 for boundary in 4:
  var take:float = minf(actual - consumed, _step_span - step_distance)
  step_distance += take;consumed += take
  step_fraction = clampf(step_distance / _step_span, 0.0, 1.0)
  # Land against the actual traversed root trajectory, including the diagonal
  # lane connector; no synthetic X distance is substituted for displacement.
  var here:Vector2 = from.lerp(to, consumed / actual)
  _swing_target = _landing(here, _step_direction, _step_span - step_distance, swing)
  _sample_swing()
  if step_fraction < 1.0 - EPS:break
  if not _swing_landed:
   feet[swing].position = _swing_target;feet[swing].planted = true
   feet[swing].landing_id = int(feet[swing].landing_id) + 1
  var old_support:String = support;support = swing;swing = old_support
  _step_start = here;step_distance = 0.0;step_fraction = 0.0;_step_span = half_step()
  _step_direction = (to - from).normalized()
  _swing_from = feet[swing].position;_swing_landed = false
  _swing_target = _landing(here, _step_direction, _step_span, swing)
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
 feet[swing].position.y -= sin(PI * u) * float(config.get("swing_lift", 13.0)) * _s()

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
 var wanted:Vector2 = origin + Vector2(_sole_baseline(swing), _floor_offset(swing))
 # Keep already comfortable real contacts. Only an airborne/uncomfortable
 # closing foot takes a short, visibly lifted recovery step.
 if bool(feet[swing].planted) and absf(feet[swing].position.x - wanted.x) <= float(config.get("max_comfort", 26.0)) * _s():
  _settle_to = feet[swing].position
 else:
  _settle_to = wanted

func _advance_settle() -> void:
 var u:float = clampf((pose_time - _settle_start) / SETTLE_SECONDS, 0.0, 1.0)
 var smooth:float = u * u * (3.0 - 2.0 * u)
 feet[swing].position = _settle_from.lerp(_settle_to, smooth)
 # A grounded, widely trailing foot takes one small closing step. Do not
 # translate a shoe along the floor while describing it as planted.
 if _settle_from.distance_to(_settle_to) > EPS:
  feet[swing].position.y -= sin(PI * u) * 4.0 * _s()
  feet[swing].planted = u >= 1.0
 if u >= 1.0:
  feet[swing].position = _settle_to;feet[swing].planted = true
  settling = false;settled = true

func _relaxed_hip(default_hip:Vector2) -> Vector2:
 # Intersect two comfort-reach circles around the ACTUAL fixed ankles. This
 # changes only the rigid pelvis translation. Bone lengths, shoes and head
 # scale stay fixed, and neither knee is forced into a straight lock.
 var centers:Array[Vector2] = []
 var radii:Array[float] = []
 var bend:float = deg_to_rad(float(config.get("relaxed_knee_degrees", 12.0)))
 for side in SIDES:
  var leg:Dictionary = config.legs[side]
  var offset:Vector2 = _v(leg.get("hip_offset", [-3.0 if side == "far" else 3.0, 0.0])) * _s();offset.x *= _sign()
  var ankle:Vector2 = feet[side].position - _v(leg.get("sole_from_ankle", [0.0, 34.64])) * Vector2(_sign(), 1.0) * _s()
  centers.append(ankle - offset)
  var l1:float = float(leg.thigh_length) * _s();var l2:float = float(leg.shin_length) * _s()
  radii.append(sqrt(l1 * l1 + l2 * l2 + 2.0 * l1 * l2 * cos(bend)))
 var between:Vector2 = centers[1] - centers[0];var d:float = between.length()
 if d < 0.001 or d > radii[0] + radii[1] or d < absf(radii[0] - radii[1]):return default_hip
 var toward:Vector2 = between / d
 var a:float = (radii[0] * radii[0] - radii[1] * radii[1] + d * d) / (2.0 * d)
 var h:float = sqrt(maxf(0.0, radii[0] * radii[0] - a * a))
 var normal:Vector2 = Vector2(-toward.y, toward.x) * h
 var candidate_a:Vector2 = centers[0] + toward * a + normal
 var candidate_b:Vector2 = centers[0] + toward * a - normal
 var wanted:Vector2 = candidate_a if candidate_a.y < candidate_b.y else candidate_b
 # At a floor-lane corner a one-foot elevation difference can otherwise pull
 # the torso sideways. Keep that local response bounded without moving feet.
 # Sole anchors can sit ahead of the painted ankle in a full-height boot.
 # Center the bounded body response over ankles, not the toe/contact marker.
 
 wanted.x = clampf(wanted.x, default_hip.x - 4.0 * _s(), default_hip.x + 4.0 * _s())
 wanted.y = clampf(wanted.y, default_hip.y - 3.0 * _s(), default_hip.y + 3.0 * _s())
 return wanted

func _reachable_hip(desired:Vector2) -> Vector2:
 # The wide human hip sockets make a facing reversal different from the
 # clerk. Find the closest real pelvis point inside BOTH fixed-length reach
 # circles; never project an ankle, rescale a segment, or move a support shoe.
 var centers:Array[Vector2] = []
 var radii:Array[float] = []
 for side in SIDES:
  var leg:Dictionary = config.legs[side]
  var offset:Vector2 = _v(leg.hip_offset) * _s();offset.x *= _sign()
  var ankle:Vector2 = feet[side].position - _v(leg.sole_from_ankle) * Vector2(_sign(),1.0) * _s()
  centers.append(ankle-offset)
  radii.append((float(leg.thigh_length)+float(leg.shin_length)-0.25)*_s())
 if desired.distance_to(centers[0]) <= radii[0] and desired.distance_to(centers[1]) <= radii[1]:return desired
 var candidates:Array[Vector2] = []
 for i in 2:
  var other:int = 1-i
  var direction:Vector2 = (desired-centers[i]).normalized()
  var point:Vector2 = centers[i]+direction*radii[i]
  if point.distance_to(centers[other]) <= radii[other]+0.00001:candidates.append(point)
 var between:Vector2 = centers[1]-centers[0];var d:float = between.length()
 if d > 0.00001 and d <= radii[0]+radii[1] and d >= absf(radii[0]-radii[1]):
  var along:float = (radii[0]*radii[0]-radii[1]*radii[1]+d*d)/(2.0*d)
  var height:float = sqrt(maxf(0.0,radii[0]*radii[0]-along*along))
  var toward:Vector2 = between/d;var normal:Vector2 = Vector2(-toward.y,toward.x)*height
  candidates.append(centers[0]+toward*along+normal);candidates.append(centers[0]+toward*along-normal)
 if candidates.is_empty():return desired # Reported as reach error; never hidden.
 var best:Vector2 = candidates[0]
 for point in candidates:
  if point.distance_squared_to(desired)<best.distance_squared_to(desired):best=point
 return best

func _solve() -> void:
 # Keep ankle targets exact. Lower the pelvis only if source bone lengths
 # require it; never shorten/stretch a thigh, shin, body or head.
 var hip_offset:Vector2 = _v(config.hip) * _s();hip_offset.x *= _sign()
 var desired:Vector2 = origin + hip_offset
 if travelling:
  var u:float = clampf(_upper_distance / (half_step() * 0.25), 0.0, 1.0)
  _extension_weight = _extension_from * (1.0 - u * u * (3.0 - 2.0 * u))
 elif settling:
  var u:float = clampf((pose_time - _settle_start) / SETTLE_SECONDS, 0.0, 1.0)
  _extension_weight = lerpf(_settle_extension, 1.0, u * u * (3.0 - 2.0 * u))
 else:_extension_weight = 1.0
 if _has_travelled:desired = desired.lerp(_relaxed_hip(desired), _extension_weight)
 hip = _reachable_hip(desired)
 max_reach_error = 0.0
 for side in SIDES:
  var leg:Dictionary = config.legs[side]
  var offset:Vector2 = _v(leg.get("hip_offset", [-3.0 if side == "far" else 3.0, 0.0])) * _s();offset.x *= _sign()
  var at:Vector2 = hip + offset
  var ankle:Vector2 = feet[side].position - _v(leg.get("sole_from_ankle", [0.0, 34.64])) * Vector2(_sign(), 1.0) * _s()
  var l1:float = float(leg.thigh_length) * _s();var l2:float = float(leg.shin_length) * _s()
  var d:float = at.distance_to(ankle)
  var valid:float = clampf(d, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
  var toward:Vector2 = (ankle - at).normalized()
  var a:float = (l1 * l1 - l2 * l2 + valid * valid) / (2.0 * valid)
  var h:float = sqrt(maxf(0.0, l1 * l1 - a * a))
  var knee:Vector2 = at + toward * a + Vector2(toward.y, -toward.x) * h * _sign()
  max_reach_error = maxf(max_reach_error, absf(d - valid))
  joints[side] = {"hip": at, "knee": knee, "ankle": ankle, "sole": feet[side].position}

func _upper_pose(reduced_motion:bool) -> void:
 var breath:float = 0.0 if reduced_motion else sin(pose_time * 1.65 + 0.8) * 0.45 * _s()
 if travelling:
  var wanted:float = sin(step_fraction * PI) * (0.11 if swing == "near" else -0.11)
  var u:float = clampf(_upper_distance / (half_step() * 0.25), 0.0, 1.0)
  var blend:float = u * u * (3.0 - 2.0 * u)
  arm_angle = lerpf(_upper_from_angle, wanted, blend)
  shoulder_offset = _upper_from_shoulder.lerp(Vector2.ZERO, blend)
 elif settling:
  var u:float = clampf((pose_time - _settle_start) / SETTLE_SECONDS, 0.0, 1.0)
  var smooth:float = u * u * (3.0 - 2.0 * u)
  arm_angle = lerpf(_settle_arm, 0.0, smooth)
  shoulder_offset = _settle_shoulder.lerp(Vector2(0.0, breath), smooth)
 else:
  arm_angle = 0.0;shoulder_offset = Vector2(0.0, breath)
 # Head tilt requires separately authored collar overlap. Until then remain
 # rigid, same scale, and use only supplied eye-state texture variants.
 head_angle = 0.0
 eye_state = "open"

func snapshot() -> Dictionary:
 return {"state": state, "origin": origin, "feet": feet.duplicate(true), "joints": joints.duplicate(true),
 "hip": hip, "support": support, "swing": swing, "step_fraction": step_fraction, "step_distance": step_distance,
 "travelling": travelling, "settling": settling, "settled": settled, "facing_right": facing_right,
 "pose_time": pose_time, "arm_angle": arm_angle, "shoulder_offset": shoulder_offset, "head_angle": head_angle,
 "eye_state": eye_state, "distance_rebases": distance_rebases, "max_reach_error": max_reach_error,
 "relaxed_extension_weight": _extension_weight, "step_span": _step_span, "has_travelled": _has_travelled}
