extends "res://scripts/clerk_recovery_base_2d.gd"
## Explicit preview candidate only. Existing tablet/dialogue full-body art stays
## unchanged. Root motion, body geometry and C2 status are not modified.
const CANDIDATE_META:String="res://assets/2d_v5/actors/reconstructed_recovery_v1/head-level-registration.json"
var _candidate_head_ready:bool=false
func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 if not _rig_ready or not FileAccess.file_exists(CANDIDATE_META):return
 var record:Variant=JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_META))
 if not record is Dictionary:return
 var texture:Texture2D=_texture(str(record.get("runtime","")))
 var measured_root:Vector2=_point(record.get("root"))
 if texture==null or texture.get_size()!=Vector2(104,91) or not measured_root.is_finite():return
 _rig_data=_rig_data.duplicate(true)
 _rig_data.parts.head.root=record.root
 _rig_data.parts.head.tip=record.tip
 _rig_data.parts.head.path=record.runtime
 _rig_data.parts.head.sha256=record.sha256
 _rig_data.head_reference="reconstructed-level-head-v1; unaccepted"
 _rig_data.head_variants={"open":"head","half":"head","closed":"head","gaze":"head"}
 for key in ["head","head_half","head_closed","head_gaze"]:_rig_textures[key]=texture
 _parts.head.texture=texture
 _candidate_head_ready=true
func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 result.candidate_head_ready=_candidate_head_ready
 result.candidate_head_active=_candidate_head_ready and _rig_active
 result.candidate_head_registration=CANDIDATE_META
 result.candidate_visual_acceptance="pending neck/collar and transitions; blink frozen"
 return result
