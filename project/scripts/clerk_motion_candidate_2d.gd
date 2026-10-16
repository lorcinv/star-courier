extends "res://scripts/clerk_level_head_candidate_2d.gd"
## Preview-only adapter. Constant-size level head and original rigid parts.
const MotionCandidate = preload("res://scripts/clerk_motion_candidate_pose_2d.gd")

func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 if not _rig_ready:return
 _model = MotionCandidate.new()
 if not _model.configure(_rig_data, _height):
  _rig_ready = false;_issue("motion_candidate_invalid_geometry")

func _render_rig() -> void:
 var at:Vector2 = _model.origin
 var upper:Dictionary = _model.upper_body
 _support_points = {}
 for side in ["far", "near"]:
  var joint:Dictionary = _model.joints[side]
  _place_segment(side + "_thigh", joint.hip - at, joint.knee - at)
  _place_segment(side + "_shin", joint.knee - at, joint.ankle - at)
  _place_rigid(side + "_boot", joint.ankle - at, 0.0)
  if bool(_model.feet[side].planted):
   _support_points[side] = _node().global_transform * (_model.feet[side].position - at)
 _part_transform("pelvis", _model.hip - at, float(upper.pelvis_world_angle))
 _part_transform("torso", upper.torso_pivot_world - at, float(upper.torso_world_angle))
 for side in ["far", "near"]:
  _part_transform(side + "_arm", upper.shoulder_world[side] - at, float(upper.arm_world_angle[side]))
 _parts.head.texture = _rig_textures.head
 _part_transform("head", upper.neck_world - at, float(upper.head_world_angle))

func debug_snapshot() -> Dictionary:
 var result:Dictionary = super.debug_snapshot()
 result.motion_candidate = "A1-fixed-step-upright; not visually accepted"
 result.motion_contract = "120 Hz owner sampling; no render interpolation, no root writes, no crossfades"
 return result
