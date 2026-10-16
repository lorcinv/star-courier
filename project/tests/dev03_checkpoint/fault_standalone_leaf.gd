extends "res://scripts/clerk_pose_owner_adapter_v1.gd"
const Fault=preload("res://tests/dev03_checkpoint/fault_control.gd")
const FaultBody=preload("res://tests/dev03_checkpoint/fault_body.gd")
func enable_pose_experiment(profile:Dictionary,tablet_parts:Dictionary) -> bool:
 if not super.enable_pose_experiment(profile,tablet_parts):return false
 var body=FaultBody.new()
 if not body.configure(profile,_height):return false
 _model=body
 return true
# This fixture-only bootstrap signature deliberately selects the independent
# adapter API. No coupled transaction, provider or external rollback exists.
func bind_coupled_renderer(profile:Dictionary,tablet_parts:Dictionary,head_views:Array,_textures:Dictionary) -> bool:
 return enable_pose_experiment(profile,tablet_parts) and set_pose_head_views(head_views)
func _owner_checkpoint() -> Dictionary:
 Fault.checkpoint_calls+=1;return super._owner_checkpoint()
func _copy_script_state(object:Object) -> Dictionary:
 Fault.copy_calls+=1;return super._copy_script_state(object)
