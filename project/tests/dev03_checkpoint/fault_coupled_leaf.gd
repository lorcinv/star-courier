extends "res://scripts/clerk_pose_render_observed_v4.gd"
const Fault=preload("res://tests/dev03_checkpoint/fault_control.gd")
const FaultBody=preload("res://tests/dev03_checkpoint/fault_body.gd")
const FaultArm=preload("res://tests/dev03_checkpoint/fault_arm.gd")
func enable_pose_experiment(profile:Dictionary,tablet_parts:Dictionary) -> bool:
 if not super.enable_pose_experiment(profile,tablet_parts):return false
 var body=FaultBody.new()
 if not body.configure(profile,_height):return false
 _model=body # Test-only collaborator injection, before the first model sample.
 return true
func bind_coupled_renderer(profile:Dictionary,tablet_parts:Dictionary,head_views:Array,textures:Dictionary) -> bool:
 if not super.bind_coupled_renderer(profile,tablet_parts,head_views,textures):return false
 var provider=FaultArm.new()
 if not provider.configure(_height):return false
 _coupled_arms=provider # Still before bootstrap initialization/accepted time.
 return true
func _owner_checkpoint() -> Dictionary:
 Fault.checkpoint_calls+=1;return super._owner_checkpoint()
func _coupled_checkpoint() -> Dictionary:
 Fault.coupled_calls+=1;return super._coupled_checkpoint()
func _copy_script_state(object:Object) -> Dictionary:
 Fault.copy_calls+=1;return super._copy_script_state(object)
func _poison_layers() -> void:
 _phone_elapsed+=4.0;_observed_clock+=7.0;_pose_last_token.fault="owner"
 _model.feet.far.position+=Vector2(11,13)
 _accepted_pose.draw_progress=.731
 _pose_helper.tablet_parts.near_upper.root[0]+=9.0
 _coupled_arms._display.placements.near_fore.angle+=.333
 _coupled_arms._walk._pose.arms.near.shoulder[0]+=8.0
func advance_review_phone_slice(owner:int,elapsed:float,frame_clock:float,slice_id:int) -> bool:
 var ok:bool=super.advance_review_phone_slice(owner,elapsed,frame_clock,slice_id)
 if ok and Fault.mode=="phone_after_slice":Fault.hits+=1;_poison_layers();return false
 return ok
func advance_cooperative_pose_slice(owner:int,elapsed:float,frame_clock:float,slice_id:int) -> bool:
 var ok:bool=super.advance_cooperative_pose_slice(owner,elapsed,frame_clock,slice_id)
 if ok and Fault.mode=="cooperative_after_slice":Fault.hits+=1;_poison_layers();return false
 return ok
