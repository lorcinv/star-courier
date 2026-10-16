extends "res://scripts/clerk_arm_owner_abort_v3.gd"
const Fault=preload("res://tests/dev03_checkpoint/fault_control.gd")
func advance(body:Dictionary,root_ending_velocity:float,accepted_time:float) -> bool:
 var ok:bool=super.advance(body,root_ending_velocity,accepted_time)
 if ok and Fault.mode=="provider_after":
  Fault.hits+=1;_time+=21.0;_owner="fault-owner"
  _display.placements.near_upper.angle+=1.25
  _walk._pose.placements.far_fore.angle-=.75
  return false
 return ok
