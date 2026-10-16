extends "res://scripts/clerk_motion_r5_r3_pose_2d.gd"
## A brief stylized blink using only caller-owned pose time. No breathing,
## gaze change, independent timer, geometry update or idle gesture is added.
const BLINK_FIRST_TICK:int=84
const BLINK_PERIOD_TICKS:int=492
const BLINK_CLOSED_TICKS:int=9
func _upper_pose(reduced_motion:bool) -> void:
 super._upper_pose(reduced_motion)
 var tick:int=int(floor(pose_time*120.0+0.000001))
 eye_state="closed" if tick>=BLINK_FIRST_TICK and (tick-BLINK_FIRST_TICK)%BLINK_PERIOD_TICKS<BLINK_CLOSED_TICKS else "open"
func snapshot() -> Dictionary:
 var result:Dictionary=super.snapshot()
 result.blink={"owner":"pose_time","first_tick":BLINK_FIRST_TICK,"period_ticks":BLINK_PERIOD_TICKS,"closed_ticks":BLINK_CLOSED_TICKS,"step_hz":120,"style":"brief gently smiling closure"}
 return result
