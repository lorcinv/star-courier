extends "res://scripts/clerk_upper_response_v1.gd"
## V2 upper-only experiment. Exact inherited root/contact/lower solver.
## Continuous phase is measured from actual solved ankles and hip sockets.
var _upper_v2_last_speed:float=0.0
var _upper_v2_accel:float=0.0
var _upper_v2_progression:float=0.0

func reset(at:Vector2,right:bool,clock:float=0.0,distance:float=0.0) -> void:
 _upper_v2_last_speed=0.0;_upper_v2_accel=0.0;_upper_v2_progression=0.0
 super.reset(at,right,clock,distance)

func _v2_follow(current:float,wanted:float,response:float,max_speed:float) -> float:
 var filtered:float=lerpf(current,wanted,1.0-exp(-response*_candidate_dt))
 return move_toward(current,filtered,max_speed*_candidate_dt)

func _upper_pose(reduced_motion:bool) -> void:
 var moving:bool=travelling and _candidate_speed>EPS
 var factor:float=0.35 if reduced_motion else 1.0
 var p:Dictionary=config.presentation
 var acceleration:float=(_candidate_speed-_upper_v2_last_speed)/_candidate_dt if _candidate_dt>EPS else 0.0
 _upper_v2_accel=lerpf(_upper_v2_accel,clampf(acceleration/float(p.acceleration_normalizer),-1.0,1.0),1.0-exp(-float(p.acceleration_response)*_candidate_dt))
 _upper_v2_last_speed=_candidate_speed
 # Body-relative solved ankle progression includes the actual socket offset.
 # Positive near progress means near arm rotates backward, far arm forward.
 var near_progress:float=(joints.near.ankle.x-joints.near.hip.x)*_sign()/_s()
 var far_progress:float=(joints.far.ankle.x-joints.far.hip.x)*_sign()/_s()
 _upper_v2_progression=clampf((near_progress-far_progress)/float(p.progression_normalizer_native),-1.0,1.0)
 if moving:
  _anatomy_returning=false
  var strength:float=clampf(_candidate_speed/155.0,0.0,1.0)
  var lean:float=float(p.brake_lean_radians) if state=="inertial_stop" else float(p.move_lean_radians)
  lean+=_upper_v2_accel*float(p.acceleration_lean_radians)
  var wanted_torso:float=clampf(lean-_upper_v2_progression*float(p.torso_wave_radians),-float(p.torso_limit_radians),float(p.torso_limit_radians))*strength*_sign()*factor
  var wanted_arm:float=_upper_v2_progression*float(p.arm_swing_radians)*strength*_sign()*factor
  _candidate_torso_angle=_v2_follow(_candidate_torso_angle,wanted_torso,float(p.torso_response),float(p.torso_max_speed))
  _candidate_arm_angle=_v2_follow(_candidate_arm_angle,wanted_arm,float(p.arm_response),float(p.arm_max_speed))
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
 # Same fixed collar pivot and exact source scale; head modestly stabilizes.
 head_angle=_candidate_torso_angle*float(p.head_torso_fraction)
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
 result.candidate="clerk-upper-response-v2.0"
 result.upper_progression=_upper_v2_progression
 result.upper_acceleration_weight=_upper_v2_accel
 return result
