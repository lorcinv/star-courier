extends "res://scripts/clerk_rigid_pose_2d.gd"
## Isolated A1 presentation candidate. The inherited foot scheduler, actual
## root inputs, contact identities, registration and bone lengths are intact.
## A stable upright hip target replaces the two-circle equal-flex selector.
## Source artwork and the locomotion owner are never modified here.
const CANDIDATE_ID:String = "R5-near-upright-rest"
const REST_HIP_DROP_NATIVE:float = 1.5
const WALK_HIP_DROP_NATIVE:float = 7.5
const HIP_BLEND_SPEED:float = 5.5
const UPPER_RESPONSE:float = 12.0
const UPPER_MAX_SPEED:float = 0.52
var upper_body:Dictionary = {}
var _candidate_dt:float = 0.0
var _candidate_speed:float = 0.0
var _candidate_walk_weight:float = 0.0
var _candidate_torso_angle:float = 0.0
var _candidate_arm_angle:float = 0.0
var _candidate_reach_feasible:bool = true

func reset(at:Vector2, right:bool, clock:float = 0.0, distance:float = 0.0) -> void:
 _candidate_dt = 0.0;_candidate_speed = 0.0;_candidate_walk_weight = 0.0
 _candidate_torso_angle = 0.0;_candidate_arm_angle = 0.0
 super.reset(at, right, clock, distance)
 _upper_pose(false)

func update(next_state:String, distance:float, at:Vector2, right:bool, clock:float, stop_age:float = 0.0, enabled:bool = true, reduced_motion:bool = false) -> bool:
 _candidate_dt = clampf(clock - _last_clock, 0.0, 0.1) if initialized and not _freeze_clock else 0.0
 _candidate_speed = at.distance_to(origin) / _candidate_dt if initialized and _candidate_dt > EPS else 0.0
 return super.update(next_state, distance, at, right, clock, stop_age, enabled, reduced_motion)

func _solve() -> void:
 # Keep the pelvis horizontally above the actor root. The previous exact
 # circle-intersection rest target could switch sides while a foot recovered.
 # A small named drop leaves actual lateral reach without anterior pelvic tilt.
 var target_weight:float = clampf(_candidate_speed / 155.0, 0.0, 1.0) if travelling else 0.0
 _candidate_walk_weight = move_toward(_candidate_walk_weight, target_weight, _candidate_dt * HIP_BLEND_SPEED)
 var drop:float = lerpf(_motion_rest_drop_native(), _motion_walk_drop_native(), _candidate_walk_weight)
 var desired:Vector2 = origin + _v(config.get("hip", [0.0, -94.4626334519573])) * _s()
 desired.y += drop * _s()
 var highest:float = -INF
 var lowest:float = INF
 _candidate_reach_feasible = true
 for side in SIDES:
  var leg:Dictionary = config.legs[side]
  var socket:Vector2 = _v(leg.hip_offset) * Vector2(_sign(), 1.0) * _s()
  var ankle:Vector2 = feet[side].position - _v(leg.sole_from_ankle) * Vector2(_sign(), 1.0) * _s()
  var radius:float = (float(leg.thigh_length) + float(leg.shin_length) - 0.25) * _s()
  var dx:float = ankle.x - desired.x - socket.x
  if absf(dx) > radius:_candidate_reach_feasible = false
  var span:float = sqrt(maxf(0.0, radius * radius - dx * dx))
  highest = maxf(highest, ankle.y - span - socket.y)
  lowest = minf(lowest, ankle.y + span - socket.y)
 _candidate_reach_feasible = _candidate_reach_feasible and highest <= lowest
 hip = Vector2(desired.x, clampf(desired.y, highest, lowest)) if highest <= lowest else desired
 max_reach_error = 0.0
 for side in SIDES:
  var leg:Dictionary = config.legs[side]
  var socket:Vector2 = _v(leg.hip_offset) * Vector2(_sign(), 1.0) * _s()
  var at:Vector2 = hip + socket
  var ankle:Vector2 = feet[side].position - _v(leg.sole_from_ankle) * Vector2(_sign(), 1.0) * _s()
  var l1:float = float(leg.thigh_length) * _s()
  var l2:float = float(leg.shin_length) * _s()
  var distance:float = at.distance_to(ankle)
  var valid:float = clampf(distance, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
  var toward:Vector2 = (ankle - at).normalized()
  var along:float = (l1 * l1 - l2 * l2 + valid * valid) / (2.0 * valid)
  var bend:float = sqrt(maxf(0.0, l1 * l1 - along * along))
  var knee:Vector2 = at + toward * along + Vector2(toward.y, -toward.x) * bend * _sign()
  max_reach_error = maxf(max_reach_error, absf(distance - valid))
  joints[side] = {"hip":at, "knee":knee, "ankle":ankle, "sole":feet[side].position}
 _extension_weight = 1.0 - _candidate_walk_weight

func _follow_angle(current:float, wanted:float) -> float:
 var filtered:float = lerpf(current, wanted, 1.0 - exp(-UPPER_RESPONSE * _candidate_dt))
 return move_toward(current, filtered, UPPER_MAX_SPEED * _candidate_dt)

func _upper_pose(reduced_motion:bool) -> void:
 var wave:float = sin(step_fraction * PI) * (1.0 if swing == "near" else -1.0)
 var moving:bool = travelling and _candidate_speed > EPS
 var strength:float = clampf(_candidate_speed / 155.0, 0.0, 1.0) if moving else 0.0
 var factor:float = 0.35 if reduced_motion else 1.0
 var lean:float = -0.007 if state == "inertial_stop" else 0.009
 var wanted_torso:float = (lean - wave * 0.014) * strength * _sign() * factor
 var wanted_arm:float = wave * 0.105 * strength * _sign() * factor
 _candidate_torso_angle = _follow_angle(_candidate_torso_angle, wanted_torso)
 _candidate_arm_angle = _follow_angle(_candidate_arm_angle, wanted_arm)
 if not travelling and not settling and absf(_candidate_torso_angle) < 0.00001 and absf(_candidate_arm_angle) < 0.00001:
  _candidate_torso_angle = 0.0;_candidate_arm_angle = 0.0
 # No standing wave, no independent breath translation through the waist.
 shoulder_offset = Vector2.ZERO
 arm_angle = _candidate_arm_angle * _sign()
 head_angle = 0.0;eye_state = "open"
 var neck_offset:Vector2 = _v(config.parts.head.attachment_offset) * Vector2(_sign(), 1.0) * _s()
 var shoulders:Dictionary = {}
 var arms:Dictionary = {}
 for side in SIDES:
  var offset:Vector2 = _v(config.parts[side + "_arm"].attachment_offset) * Vector2(_sign(), 1.0) * _s()
  shoulders[side] = hip + offset.rotated(_candidate_torso_angle)
  arms[side] = _candidate_torso_angle + _candidate_arm_angle * (-1.0 if side == "far" else 1.0)
 upper_body = {"pelvis_world_angle":0.0, "torso_world_angle":_candidate_torso_angle,
  "torso_pivot_world":hip, "neck_world":hip + neck_offset.rotated(_candidate_torso_angle),
  "shoulder_world":shoulders, "arm_world_angle":arms, "head_world_angle":0.0,
  "head_scale":_s(), "gaze_semantic":"forward", "orientation_space":"world"}

func snapshot() -> Dictionary:
 var result:Dictionary = super.snapshot()
 result.candidate = CANDIDATE_ID
 result.upper_body = upper_body.duplicate(true)
 result.reach_feasible = _candidate_reach_feasible
 result.walk_weight = _candidate_walk_weight
 result.rest_hip_drop_native = _motion_rest_drop_native()
 result.walk_hip_drop_native = _motion_walk_drop_native()
 result.foot_scheduler = "unchanged source clerk_rigid_pose_2d.gd"
 return result

# Isolated calibration hooks. Historical defaults are unchanged.
func _motion_rest_drop_native() -> float:return REST_HIP_DROP_NATIVE
func _motion_walk_drop_native() -> float:return WALK_HIP_DROP_NATIVE
