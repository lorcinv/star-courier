extends "res://scripts/clerk_motion_a2_2d.gd"
const BlinkPose=preload("res://scripts/clerk_motion_a2_blink_pose_2d.gd")
const CLOSED_HEAD:String="res://assets/2d_v5/actors/motion_candidate_v1/head-closed-pixel.png"
var _blink_ready:bool=false
func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 if not _rig_ready:return
 var closed:Texture2D=_texture(CLOSED_HEAD)
 if closed==null or closed.get_size()!=Vector2(104,91):return
 _rig_textures["head_closed_candidate"]=closed
 _model=BlinkPose.new()
 if not _model.configure(_rig_data,_height):
  _rig_ready=false;_issue("motion_a2_blink_invalid_geometry");return
 _blink_ready=true
func _render_rig() -> void:
 super._render_rig()
 if _blink_ready and _model.eye_state=="closed":_parts.head.texture=_rig_textures.head_closed_candidate
func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 result.blink_ready=_blink_ready
 result.blink_eye_state=_model.eye_state
 result.blink_candidate="75ms closed,4.1s period; caller pose clock; native review pending"
 return result
