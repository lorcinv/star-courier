extends "res://scripts/clerk_rigid_motion_2d.gd"
## Explicit reconstructed compatibility profile. Surviving raster bytes are
## unchanged. Missing canonical single-walk data are never treated as recovered.
const RECOVERY_PROFILE:String = "reconstructed_recovery_v1"
const HISTORICAL_ACTORS:String = "res://assets/2d_v5/actors/actor-manifest.json"

func _preload_motion_assets() -> void:
 _record = _record.duplicate(true)
 for key in ["walk", "run", "walk_sequence", "run_sequence", "walk_phase_weights", "run_phase_weights"]:_record[key] = []
 var gestures:Dictionary = {}
 for key in ["reach", "align", "ready"]:
  var frame:Variant = _record.get("gestures", {}).get(key)
  if not frame is Dictionary:_issue("recovery_missing_tablet:"+key);return
  if _texture(str(frame.get("runtime", ""))) == null:_issue("recovery_missing_tablet_texture:"+key);return
  gestures[key] = frame.duplicate(true)
 _record.gestures = gestures
 if not FileAccess.file_exists(HISTORICAL_ACTORS):_issue("recovery_missing_historical_actor_manifest");return
 var raw:Variant = JSON.parse_string(FileAccess.get_file_as_string(HISTORICAL_ACTORS))
 if not raw is Dictionary:_issue("recovery_invalid_historical_actor_manifest");return
 var clerk:Dictionary = raw.get("actors", {}).get("clerk", {})
 for key in ["idle", "handoff"]:
  var frame:Dictionary = clerk.get("poses", {}).get(key, {}).duplicate(true)
  frame.body_height = float(clerk.get("body_height", 0.0))
  frame.facing = str(clerk.get("facing", ""))
  frame.contains_parcel = false
  frame.recovery_profile = RECOVERY_PROFILE
  frame.registration_status = "historical_full_body_foot_and_hands; hip_and_head_unmeasured"
  if _texture(str(frame.get("runtime", ""))) == null or not _point(frame.get("foot_anchor")).is_finite() or frame.body_height <= 0.0 or frame.facing not in ["left", "right"]:
   _issue("recovery_invalid_clerk_full_pose:"+key);return
  _dialogue[key] = frame
 # Deliberately skip the missing single-walk loader. The extracted helper is
 # identical to the recovered renderer's rig setup, not a new gait solver.
 _preload_rig_assets()
 if _rig_ready:
  _neutral = {"foot_anchor":[0,0], "hip_anchor":_rig_data.get("hip", [0,0]),
   "body_height":240.0, "facing":"right", "contains_parcel":false,
   "empty_hands":true, "relaxed_arms":true, "recovery_profile":RECOVERY_PROFILE,
   "registration_status":"rig_joint_coordinates; no_canonical_neutral_raster"}

func walk_cycle_distance() -> float:
 return _model.half_step() * 2.0 if _model != null else NAN

func run_cycle_distance() -> float:
 return walk_cycle_distance()

func apply_player_pose(state:String, distance_px:float, right:bool, enabled:bool = true, clock:float = NAN, stop_age:float = 0.0) -> bool:
 return super.apply_player_pose(state,distance_px,right,enabled and _owner_enabled,clock,stop_age)

func apply_gesture(pose_id:String, facing_right:bool = true) -> bool:
 if not _owner_enabled:return false
 return super.apply_gesture(pose_id,facing_right)

func apply_dialogue(handoff:bool = false, facing_right:bool = true) -> bool:
 var sprite:Sprite2D = _node()
 if not is_instance_valid(sprite) or not sprite.is_visible_in_tree() or not _owner_enabled:return false
 var key:String = "handoff" if handoff else "idle"
 var frame:Dictionary = _dialogue.get(key, {})
 var art:Texture2D = _texture(str(frame.get("runtime", "")))
 var foot:Vector2 = _point(frame.get("foot_anchor"))
 var height:float = float(frame.get("body_height", 0.0))
 if art == null or not foot.is_finite() or height <= 0.0:return false
 # A stationary whole body only needs its authored foot and hand registration.
 # Do not invent a hip/head registration just to pass canonical-frame validation.
 _hide_rig()
 _was_moving = false;_distance_baseline = NAN;_player_state = "idle"
 sprite.texture = art;sprite.material = _original.get("material")
 sprite.centered = false;sprite.hframes = 1;sprite.vframes = 1;sprite.frame = 0;sprite.region_enabled = false
 sprite.flip_h = facing_right != (str(frame.facing) == "right");sprite.flip_v = false
 sprite.offset = -Vector2(float(art.get_width())-foot.x if sprite.flip_h else foot.x, foot.y)
 sprite.scale = Vector2.ONE * _height / height
 _frame = frame;_active = true;_facing_right = facing_right
 _pose = "handoff" if handoff else "dialogue";_frame_index = -1;_walk_phase = -1;_walk_phase_fraction = 0.0
 _stance_shift = 0.0;_support_points = {}
 sprite.set_meta("pose", _pose);sprite.set_meta("art_id", str(frame.runtime))
 sprite.set_meta("motion_active", true);sprite.set_meta("motion_frame", -1);sprite.set_meta("motion_facing_right", facing_right)
 sprite.set_meta("motion_support_shift", 0.0);sprite.set_meta("recovery_profile", RECOVERY_PROFILE)
 return true

func debug_snapshot() -> Dictionary:
 var result:Dictionary = super.debug_snapshot()
 result.recovery_profile = RECOVERY_PROFILE
 result.exact_canonical_recovery = false
 result.visual_acceptance = "pending: level_gaze, full_body_head_consistency, turns, pelvis_torso_motion"
 return result
