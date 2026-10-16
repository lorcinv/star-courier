extends "res://scripts/clerk_motion_r5_r3_blink_pose_2d.gd"
## Isolated anatomy profile on the existing R5 contact/turn scheduler.
## Caller timestamps and root observations are authoritative. No root writes,
## timers, scene callbacks, altered lengths, contact relabels or tablet keys.
const ANATOMY_PROFILE:String="clerk-anatomy-runtime-profile/v1.0"
var _anatomy_returning:bool=false
var _anatomy_return_clock:float=0.0
var _anatomy_return_torso:float=0.0
var _anatomy_return_arm:float=0.0
var _anatomy_was_moving:bool=false

func configure(data:Dictionary,height:float=210.0) -> bool:
 if str(data.get("schema",""))!=ANATOMY_PROFILE:return false
 var calibration:Dictionary=data.get("calibration",{})
 if not calibration.has_all(["rest_hip_drop_native","walk_hip_drop_native","contact_margin_native"]):return false
 if float(calibration.contact_margin_native)<=0.0:return false
 # Each source-approved target must remain truly inside fixed-length reach.
 # This is a profile-specific geometric reserve, not a relaxed error tolerance.
 for side in SIDES:
  var leg:Dictionary=data.get("legs",{}).get(side,{})
  if not leg.has_all(["hip_offset","neutral_sole","sole_from_ankle","thigh_length","shin_length"]):return false
  var socket:Vector2=_v(data.hip)+_v(leg.hip_offset)
  var cuff:Vector2=_v(leg.neutral_sole)-_v(leg.sole_from_ankle)
  var length:float=socket.distance_to(cuff)
  if length>float(leg.thigh_length)+float(leg.shin_length)-float(calibration.contact_margin_native):return false
  if length<absf(float(leg.thigh_length)-float(leg.shin_length))+float(calibration.contact_margin_native):return false
 return super.configure(data,height)

func reset(at:Vector2,right:bool,clock:float=0.0,distance:float=0.0) -> void:
 _anatomy_returning=false;_anatomy_was_moving=false
 _anatomy_return_clock=clock;_anatomy_return_torso=0.0;_anatomy_return_arm=0.0
 super.reset(at,right,clock,distance)

func _motion_rest_drop_native() -> float:
 return float(config.calibration.rest_hip_drop_native)

func _motion_walk_drop_native() -> float:
 return float(config.calibration.walk_hip_drop_native)

func _r5_rest_sole_native(side:String) -> Vector2:
 # The old exact-12-degree recipe is preserved in the archived parent source.
 # It must never overwrite these approved, asymmetric neutral coordinates.
 return _v(config.legs[side].neutral_sole)

func _a2_bounds(side:String) -> Vector2:
 var leg:Dictionary=config.legs[side]
 var margin:float=float(config.calibration.contact_margin_native)
 return Vector2(absf(float(leg.thigh_length)-float(leg.shin_length))+margin,
  float(leg.thigh_length)+float(leg.shin_length)-margin)*_s()

func _upper_pose(reduced_motion:bool) -> void:
 var moving:bool=travelling and _candidate_speed>EPS
 var factor:float=0.35 if reduced_motion else 1.0
 if moving:
  _anatomy_returning=false
  var strength:float=clampf(_candidate_speed/155.0,0.0,1.0)
  var wave:float=sin(step_fraction*PI)*(1.0 if swing=="near" else -1.0)
  var lean:float=-0.005 if state=="inertial_stop" else 0.007
  var torso_limit:float=float(config.calibration.torso_max_radians)
  var wanted_torso:float=clampf(lean-wave*0.010,-torso_limit,torso_limit)*strength*_sign()*factor
  var wanted_arm:float=wave*float(config.calibration.arm_max_radians)*strength*_sign()*factor
  _candidate_torso_angle=_follow_angle(_candidate_torso_angle,wanted_torso)
  _candidate_arm_angle=_follow_angle(_candidate_arm_angle,wanted_arm)
 elif _anatomy_was_moving:
  _anatomy_returning=true;_anatomy_return_clock=pose_time
  _anatomy_return_torso=_candidate_torso_angle;_anatomy_return_arm=_candidate_arm_angle
 if _anatomy_returning:
  var u:float=clampf((pose_time-_anatomy_return_clock)/float(config.calibration.upper_return_seconds),0.0,1.0)
  var remain:float=1.0-u*u*(3.0-2.0*u)
  _candidate_torso_angle=_anatomy_return_torso*remain
  _candidate_arm_angle=_anatomy_return_arm*remain
  if u>=1.0:_anatomy_returning=false
 _anatomy_was_moving=moving
 shoulder_offset=Vector2.ZERO;arm_angle=_candidate_arm_angle*_sign()
 # Rigid upper assembly carries collar/head together. Relative head/collar
 # angle and head scale stay exact; world-zero is only the neutral endpoint.
 head_angle=_candidate_torso_angle
 var mirror:Vector2=Vector2(_sign(),1.0)
 var neck:Vector2=hip+(_v(config.parts.head.attachment_offset)*mirror*_s()).rotated(_candidate_torso_angle)
 var shoulders:Dictionary={};var arms:Dictionary={}
 for side in SIDES:
  shoulders[side]=hip+(_v(config.parts[side+"_arm"].attachment_offset)*mirror*_s()).rotated(_candidate_torso_angle)
  arms[side]=_candidate_torso_angle+_candidate_arm_angle*(-1.0 if side=="far" else 1.0)
 upper_body={"pelvis_world_angle":0.0,"torso_world_angle":_candidate_torso_angle,
  "torso_pivot_world":hip,"neck_world":neck,"shoulder_world":shoulders,
  "arm_world_angle":arms,"head_world_angle":head_angle,"head_scale":_s(),
  "gaze_semantic":"forward","orientation_space":"world","tablet_owner":"external_sibling"}
 var tick:int=int(floor(pose_time*120.0+0.000001))
 eye_state="closed" if tick>=BLINK_FIRST_TICK and (tick-BLINK_FIRST_TICK)%BLINK_PERIOD_TICKS<BLINK_CLOSED_TICKS else "open"

func snapshot() -> Dictionary:
 var result:Dictionary=super.snapshot()
 result.candidate=ANATOMY_PROFILE
 result.rest_plan.erase("target_knee_flexion_degrees")
 result.rest_plan.target_contract="explicit asymmetric neutral soles; fixed lengths; real lift/landing"
 result.anatomy_calibration=config.calibration.duplicate(true)
 result.upper_returning=_anatomy_returning
 result.waist_visible_owner="torso"
 result.rest_hip_drop_native=_motion_rest_drop_native()
 result.walk_hip_drop_native=_motion_walk_drop_native()
 return result

func _turn_preparation_wanted(moving:String) -> Vector2:
 # The historical vertical-only lift/land target can repeat forever after
 # the wider hip sockets: it makes no progress toward the future mirror.
 # Propose the nearest future-facing reachable foot, then let the inherited
 # current-facing reach + finite-flight intersection constrain the actual
 # step. The existing support anchor is untouched and no contact is invented.
 var from:Vector2=_a2_before[moving].position
 var future_center:Vector2=hip+_turn_offset(moving,_turn_requested_right)
 var ray:Vector2=from-future_center
 var bounds:Vector2=_a2_bounds(moving)
 var distance:float=ray.length()
 if distance>bounds.y+EPS or distance<bounds.x-EPS:
  var direction:Vector2=ray.normalized() if distance>EPS else Vector2.DOWN
  var wanted:Vector2=future_center+direction*clampf(distance,bounds.x,bounds.y)
  wanted.y=minf(wanted.y,origin.y)
  return wanted
 return super._turn_preparation_wanted(moving)

func _turn_preparation_hip_target(keep:String) -> Vector2:
 # Approach future-facing support reach while the inherited actual-support
 # rings and <=2px continuity ball remain authoritative. Limit the proposed
 # body contribution to1.25 native px/tick, leaving room for coherent collar
 # rotation within the unchanged2px upper continuity gate.
 var current:Vector2=origin+_a2_before_hip_local
 var center:Vector2=_a2_before[keep].position-_turn_offset(keep,_turn_requested_right)
 var bounds:Vector2=_a2_bounds(keep);var ray:Vector2=current-center
 var distance:float=ray.length()
 if distance<=bounds.y and distance>=bounds.x:return current
 var direction:Vector2=ray.normalized() if distance>EPS else Vector2.UP
 var goal:Vector2=center+direction*clampf(distance,bounds.x,bounds.y)
 return current.move_toward(goal,1.25*_s())
