extends "res://scripts/clerk_arm_owner_transfer_v2.gd"
## Explicit teardown only; phase and accepted clock are never advanced.
func abort_owner(kind:String,accepted_time:float) -> bool:
 if kind not in ["cooperative","phone"] or _owner!=kind or _mode not in ["acquire","neutral"]:return false
 if not is_finite(accepted_time) or accepted_time!=_time or _display.is_empty():return false
 _owner="";_mode="walk";_from={};_display=_walk.snapshot()
 return true
