extends "res://scripts/clerk_tablet_rig_candidate_2d.gd"
const QueuedBlink=preload("res://scripts/clerk_shop_run_legacy_pose_v1.gd")
func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 if not _rig_ready:return
 _model=QueuedBlink.new()
 if not _model.configure(_rig_data,_height):_issue("r5_r3_invalid_geometry")
func _render_rig() -> void:
 var owner_facing:bool=_facing_right
 if _model!=null and _model.initialized:_facing_right=_model.facing_right
 super._render_rig()
 _facing_right=owner_facing
func _apply_observed_segments(segments:Array,frame_clock:float,enabled:bool,source:String) -> bool:
 var ok:bool=super._apply_observed_segments(segments,frame_clock,enabled,source)
 if is_instance_valid(_node()) and _model!=null:_node().set_meta("motion_facing_right",_model.facing_right)
 return ok
func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 if _model!=null and _model.initialized:
  result.requested_root_facing_right=_facing_right
  result.facing_right=_model.facing_right
  result.visual_turn_queue=_model.snapshot().turn_queue
 return result
