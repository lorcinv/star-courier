extends "res://scripts/clerk_upper_response_v2.gd"
## Grounded run response on the existing finite-contact solver. The root owns
## distance and speed; faster travel advances real foot contacts faster. A
## modest pelvis drop/forward lean distinguishes run without scaling any part.
const RUN_START_SPEED:float=185.0
const RUN_TOP_SPEED:float=260.0
var _run_weight:float=0.0
var _run_dt:float=0.0

func reset(at:Vector2,right:bool,clock:float=0.0,distance:float=0.0) -> void:
 _run_weight=0.0;_run_dt=0.0
 super.reset(at,right,clock,distance)

func update(next_state:String,distance:float,at:Vector2,right:bool,clock:float,stop_age:float=0.0,enabled:bool=true,reduced_motion:bool=false) -> bool:
 if not enabled:return super.update(next_state,distance,at,right,clock,stop_age,enabled,reduced_motion)
 if next_state not in STATES or not at.is_finite() or not is_finite(distance) or distance<0.0 or not is_finite(clock) or not is_finite(stop_age):return false
 _run_dt=clampf(clock-_last_clock,0.0,0.1) if initialized and not _freeze_clock else 0.0
 var observed_speed:float=at.distance_to(origin)/_run_dt if initialized and _run_dt>EPS else 0.0
 var target:float=clampf((observed_speed-RUN_START_SPEED)/(RUN_TOP_SPEED-RUN_START_SPEED),0.0,1.0)
 _run_weight=move_toward(_run_weight,target,_run_dt*5.0)
 return super.update(next_state,distance,at,right,clock,stop_age,enabled,reduced_motion)

func _motion_walk_drop_native() -> float:
 return super._motion_walk_drop_native()+4.0*_run_weight

func _upper_pose(reduced_motion:bool) -> void:
 super._upper_pose(reduced_motion)
 if upper_body.is_empty() or _run_weight<=0.0:return
 var factor:float=0.35 if reduced_motion else 1.0
 var lean:float=0.045*_run_weight*_sign()*factor
 var at:Vector2=upper_body.torso_pivot_world
 upper_body.torso_world_angle+=lean
 upper_body.neck_world=at+(upper_body.neck_world-at).rotated(lean)
 for side in SIDES:
  upper_body.shoulder_world[side]=at+(upper_body.shoulder_world[side]-at).rotated(lean)
  upper_body.arm_world_angle[side]+=lean
 # The registered head retains its exact source scale and stabilization.
 upper_body.run_weight=_run_weight

func snapshot() -> Dictionary:
 var result:Dictionary=super.snapshot()
 result.run_weight=_run_weight
 result.gait="run" if _run_weight>0.1 else "walk" if travelling else "idle"
 return result
