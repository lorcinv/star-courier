extends "res://scripts/clerk_cooperative_owner_2d.gd"
## PROPOSAL ONLY. New leaf above the separately accepted cooperative owner.
## No solver, World, historical art, actor-manifest or hand/parcel anchors change.
const DIALOGUE_LEVEL_HEAD_V1:Dictionary = {
 "idle": {
  "runtime":"assets/2d_v5/actors/registered_handoff_head_v1/clerk-idle-level-head.png",
  "sha256":"a39e80a1db7b7ae28adfd442e96e9ccc2d116961a2e666b88fd65bb3e9526a8a"
 },
 "handoff": {
  "runtime":"assets/2d_v5/actors/registered_handoff_head_v1/clerk-handoff-level-head.png",
  "sha256":"e6290d44f97df867310f5c92bec0b71c1340e8d19dd2584007e94e39937c8afd"
 }
}

func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 var staged:Dictionary = {}
 for pose_id in ["idle", "handoff"]:
  var historical:Dictionary = _dialogue.get(pose_id, {})
  var record:Dictionary = DIALOGUE_LEVEL_HEAD_V1[pose_id]
  var art:Texture2D = _texture(str(record.runtime))
  if historical.is_empty() or art == null or art.get_size() != Vector2(159,256):
   _issue("dialogue_level_head_invalid_texture:"+pose_id);return
  if _point(historical.get("foot_anchor")) != Vector2(85.59,247.59) or float(historical.get("body_height",0.0)) != 240.0 or str(historical.get("facing","")) != "left":
   _issue("dialogue_level_head_historical_registration_changed:"+pose_id);return
  # Duplicate the full historical record: exact hand/parcel, foot, facing and
  # body-height data stay intact. Commit neither pose unless both are valid.
  var replacement:Dictionary = historical.duplicate(true)
  replacement.historical_runtime = historical.get("runtime", "")
  replacement.historical_runtime_sha256 = historical.get("runtime_sha256", "")
  replacement.runtime = record.runtime
  replacement.runtime_sha256 = record.sha256
  replacement.dialogue_head_profile = "registered_handoff_head_v1"
  replacement.registration_status = "fixed-size canonical head on historical collar; original foot/hands; hip unmeasured"
  replacement.visual_acceptance = "level-gaze CPU candidate; native route pending; lateral body transition remains"
  staged[pose_id] = replacement
 for pose_id in staged:_dialogue[pose_id] = staged[pose_id]
