extends "res://scripts/clerk_arm_acquire_return_v1.gd"
## The frozen V1 provider remains unchanged. This subclass only transfers the
## label on its already-neutral placement; no phase/display/time alteration.
func transfer_neutral_owner(from_kind:String,to_kind:String,accepted_time:float) -> bool:
 if from_kind!="cooperative" or to_kind!="phone" or _mode!="neutral" or _owner!=from_kind:return false
 if _display.is_empty() or not is_finite(accepted_time) or accepted_time!=_time:return false
 _owner=to_kind
 return true
