extends "res://scripts/clerk_upper_response_v2.gd"
const Fault=preload("res://tests/dev03_checkpoint/fault_control.gd")
func update(next_state:String,distance:float,at:Vector2,right:bool,clock:float,stop_age:float=0.0,enabled:bool=true,reduced_motion:bool=false) -> bool:
 if Fault.mode=="body_before":Fault.hits+=1;return false
 var ok:bool=super.update(next_state,distance,at,right,clock,stop_age,enabled,reduced_motion)
 if ok and Fault.mode=="body_after":
  Fault.hits+=1
  # Deliberately corrupt nested fields as well as scalars. The real original
  # update ran first; a shallow or partial rollback cannot pass this fixture.
  feet.near.position+=Vector2(19,7);joints.near.hip+=Vector2(3,5)
  config.calibration.rest_hip_drop_native+=17.0;pose_time+=9.0
  return false
 return ok
