extends "res://scripts/clerk_motion_candidate_2d.gd"
const A2Pose=preload("res://scripts/clerk_motion_a2_pose_2d.gd")
func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 if not _rig_ready:return
 _model=A2Pose.new()
 if not _model.configure(_rig_data,_height):
  _rig_ready=false;_issue("motion_a2_invalid_geometry")
func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 result.motion_candidate="A2-stance-first-annulus; not visually accepted"
 return result
