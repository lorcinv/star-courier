extends "res://scripts/clerk_single_walk_2d.gd"
## Clerk-only staged renderer. Ordinary Sprite2D rigid cutouts; no meshes,
## shaders, timers, process callbacks, whole-body warp or runtime image writes.
## PROVISIONAL manifest is not approved artwork. Keep this out of production.
const Pose = preload("res://scripts/clerk_rigid_pose_2d.gd")
const RIG_MANIFEST:String = "res://assets/2d_v5/actors/rig_motion_v1/rig-registration.json"
const MAX_PARTS:int = 20
var _rig_data:Dictionary = {}
var _rig:Node2D
var _parts:Dictionary = {}
var _rig_textures:Dictionary = {}
var _model:RefCounted
var _rig_active:bool = false
var _rig_ready:bool = false
var _owner_clock:float = 0.0
var _owner_enabled:bool = true
var _owner_reduced:bool = false
var _rig_distance:float = 0.0
var _rig_stop_age:float = 0.0

func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 _preload_rig_assets()

func _preload_rig_assets() -> void:
 if not FileAccess.file_exists(RIG_MANIFEST):_issue("missing_rig_manifest");return
 var parsed:Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_MANIFEST))
 if not parsed is Dictionary or not parsed.get("parts") is Dictionary or parsed.parts.size() > MAX_PARTS:
  _issue("invalid_rig_manifest");return
 _rig_data = parsed
 _model = Pose.new()
 if not _model.configure(parsed, _height):_issue("invalid_rig_geometry");return
 var sprite:Sprite2D = _node()
 _rig = Node2D.new();_rig.name = "ClerkRigidCutouts";_rig.visible = false
 _rig.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 sprite.add_child(_rig)
 var part_keys:Array = parsed.parts.keys()
 part_keys.sort_custom(func(a:Variant,b:Variant) -> bool:return int(parsed.parts[a].get("z",0)) < int(parsed.parts[b].get("z",0)))
 for key in part_keys:
  var part:Dictionary = parsed.parts[key]
  var path:String = "res://" + str(part.get("path", ""))
  if not path.begins_with("res://assets/2d_v5/actors/rig_motion_v1/") or ".." in path or not path.ends_with(".png"):
   _issue("unsafe_rig_art_path");return
  var texture:Texture2D = load(path) as Texture2D
  if texture == null:_issue("missing_rig_part:" + str(key));return
  if not _point(part.get("root")).is_finite() or not _point(part.get("tip")).is_finite() or float(part.get("pixel_scale", 0.0)) <= 0.0:
   _issue("invalid_rig_part:" + str(key));return
  _rig_textures[key] = texture
  # Eye variants are cached textures, never duplicate overlaid head sprites.
  if str(key).begins_with("head_"):continue
  var node:Sprite2D = Sprite2D.new();node.name = str(key);node.texture = texture
  node.centered = false;node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  # Character-local order is sibling draw order. All children retain the
  # actor's one shop-depth value, so the counter/foreground can occlude it.
  node.z_index = 0;node.set_meta("rig_layer", int(part.get("z", 0)))
  _rig.add_child(node);_parts[key] = node
 for side in ["near", "far"]:
  for segment in ["thigh", "shin", "boot"]:
   if not _parts.has(side + "_" + segment):_issue("missing_required_rig_part");return
 for key in ["head", "torso", "pelvis", "near_arm", "far_arm"]:
  if not _parts.has(key):_issue("missing_required_rig_part:" + key);return
 _rig_ready = true

func set_visual_context(clock:float, enabled:bool = true, reduced:bool = false) -> void:
 if not is_finite(clock):return
 _owner_clock = clock;_owner_enabled = enabled;_owner_reduced = reduced
 if not enabled and _model != null:_model.freeze(clock, _rig_distance)

func advance_visual(clock:float, enabled:bool = true, reduced:bool = false) -> bool:
 set_visual_context(clock, enabled, reduced)
 if not _rig_active:return false
 return apply_player_pose(_player_state, _rig_distance, _facing_right, enabled, clock, _rig_stop_age)

func apply_player_pose(state:String, distance_px:float, right:bool, enabled:bool = true, clock:float = NAN, stop_age:float = 0.0) -> bool:
 var sprite:Sprite2D = _node()
 if not is_instance_valid(sprite) or not _rig_ready:return false
 var time:float = _owner_clock if not is_finite(clock) else clock
 if not sprite.is_visible_in_tree():
  _model.freeze(time, distance_px);return false
 if not enabled:
  _model.freeze(time, distance_px);return true
 if state not in PLAYER_STATES or not is_finite(distance_px) or distance_px < 0.0:return false
 if not _rig_active:
  # Returning from an explicit tablet/dialogue pose is a deliberate full-pose
  # boundary. Keep the rig's last stance only if its root has not moved.
  if not _model.initialized or _model.origin.distance_to(sprite.position) > 0.01:
   _model.reset(sprite.position, right, time, distance_px)
  else:
   _model.freeze(time, distance_px)
 if not _model.update(state, distance_px, sprite.position, right, time, stop_age, true, _owner_reduced):return false
 _rig_active = true;_rig_distance = distance_px;_rig_stop_age = stop_age
 _player_state = state;_facing_right = right;_active = true;_pose = "walk" if state in MOVING_STATES else state
 _frame_index = -1;_walk_phase = -1;_walk_phase_fraction = _model.step_fraction
 _stance_shift = 0.0;_frame = _neutral
 # Empty owner texture keeps its CanvasItem visibility/tint/z and external
 # references alive. Child cutouts inherit those, with no duplicated body.
 sprite.texture = null;sprite.material = _original.get("material")
 sprite.scale = Vector2.ONE;sprite.rotation = 0.0;sprite.skew = 0.0
 sprite.offset = Vector2.ZERO;sprite.flip_h = false;sprite.flip_v = false
 _rig.visible = true
 _render_rig()
 sprite.set_meta("pose", _pose);sprite.set_meta("motion_frame", -1);sprite.set_meta("motion_active", true)
 sprite.set_meta("motion_facing_right", right);sprite.set_meta("motion_support_shift", 0.0)
 sprite.set_meta("art_id", RIG_MANIFEST);sprite.set_meta("motion_diagnostics", _issues.duplicate())
 return true

func _render_rig() -> void:
 var at:Vector2 = _model.origin
 var sign_x:float = 1.0 if _facing_right else -1.0
 _support_points = {}
 for side in ["far", "near"]:
  var joint:Dictionary = _model.joints[side]
  _place_segment(side + "_thigh", joint.hip - at, joint.knee - at)
  _place_segment(side + "_shin", joint.knee - at, joint.ankle - at)
  _place_rigid(side + "_boot", joint.ankle - at, 0.0)
  if bool(_model.feet[side].planted):
   _support_points[side] = _node().global_transform * (_model.feet[side].position - at)
 var hip_local:Vector2 = _model.hip - at
 _place_rigid("pelvis", hip_local, 0.0)
 _place_rigid("torso", hip_local + _model.shoulder_offset, 0.0)
 for side in ["far", "near"]:
  var key:String = side + "_arm"
  var offset:Vector2 = _point(_rig_data.parts[key].get("attachment_offset", [0, 0])) * _height / 240.0
  offset.x *= sign_x
  _place_rigid(key, hip_local + offset + _model.shoulder_offset, _model.arm_angle * (-1.0 if side == "far" else 1.0))
 var neck:Vector2 = _point(_rig_data.parts.head.attachment_offset) * _height / 240.0;neck.x *= sign_x
 var eye_key:String = str(_rig_data.get("head_variants", {}).get(_model.eye_state, "head"))
 var head:Sprite2D = _parts.head
 head.texture = _rig_textures.get(eye_key, _rig_textures.head)
 _place_rigid("head", hip_local + neck + _model.shoulder_offset, _model.head_angle)

func _part_transform(key:String, at:Vector2, angle:float) -> void:
 var part:Dictionary = _rig_data.parts[key]
 var node:Sprite2D = _parts[key]
 var scale_px:float = float(part.pixel_scale) * _height / float(_rig_data.reference_height)
 var mirror:float = 1.0 if _facing_right else -1.0
 var c:float = cos(angle);var s:float = sin(angle)
 # Direct Transform2D avoids negative-scale Node2D decomposition surprises.
 # Each rigid part is reflected around its joint, so a flipped shoe retains
 # its registered sole world point; no scene-root mirror moves both feet.
 var basis_x:Vector2 = Vector2(c, s) * scale_px * mirror
 var basis_y:Vector2 = Vector2(-s, c) * scale_px
 var root_point:Vector2 = _point(part.root)
 node.transform = Transform2D(basis_x, basis_y, at - basis_x * root_point.x - basis_y * root_point.y)

func _place_segment(key:String, from:Vector2, to:Vector2) -> void:
 var part:Dictionary = _rig_data.parts[key]
 var source_vector:Vector2 = _point(part.tip) - _point(part.root)
 if not _facing_right:source_vector.x = -source_vector.x
 var angle:float = (to - from).angle() - source_vector.angle()
 _part_transform(key, from, angle)

func _place_rigid(key:String, at:Vector2, angle:float) -> void:
 _part_transform(key, at, angle * (1.0 if _facing_right else -1.0))

func apply_idle(facing_right:bool = true) -> bool:
 return apply_player_pose("idle", _rig_distance, facing_right)

func apply_walk(distance_px:float, facing_right:bool = true) -> bool:
 return apply_player_pose("move", distance_px, facing_right)

func apply_run(distance_px:float, facing_right:bool = true) -> bool:
 return apply_walk(distance_px, facing_right)

func _hide_rig() -> void:
 if is_instance_valid(_rig):_rig.hide()
 _rig_active = false
 if _model != null:_model.freeze(_owner_clock, _rig_distance)

func apply_gesture(pose_id:String, facing_right:bool = true) -> bool:
 var sprite:Sprite2D = _node()
 if not is_instance_valid(sprite) or not sprite.is_visible_in_tree():return false
 _hide_rig()
 return super.apply_gesture(pose_id, facing_right)

func apply_dialogue(handoff:bool = false, facing_right:bool = true) -> bool:
 var sprite:Sprite2D = _node()
 if not is_instance_valid(sprite) or not sprite.is_visible_in_tree():return false
 _hide_rig()
 return super.apply_dialogue(handoff, facing_right)

func restore_original() -> void:
 apply_idle(_facing_right)

func pose_anchor_parent(anchor_name:String) -> Vector2:
 if not _rig_active:return super.pose_anchor_parent(anchor_name)
 # Quiet empty hands never own the parcel. No invented moving handoff anchor.
 return Vector2(INF, INF)

func debug_snapshot() -> Dictionary:
 if not _rig_active:
  var old:Dictionary = super.debug_snapshot();old.rigid_active = false;old.rig_ready = _rig_ready
  return old
 var sprite:Sprite2D = _node()
 var head:Sprite2D = _parts.head
 var head_size:Vector2 = _point(_rig_data.get("head_alpha_size", [104, 91])) * _height / 240.0
 var neck:Vector2 = sprite.position + head.transform * _point(_rig_data.parts.head.root)
 var bounds:Rect2 = sprite.transform * head.transform * Rect2(Vector2.ZERO, Vector2(104, 91))
 var snap:Dictionary = {"appearance_id": appearance_id, "available": _rig_ready, "active": true,
  "pose": _pose, "player_state": _player_state, "rigid_active": true, "rig_ready": _rig_ready,
  "frame_index": -1, "walk_phase": -1, "walk_phase_fraction": _model.step_fraction,
  "single_walk_phase": _model.step_fraction, "walk_cycle_distance": _model.half_step() * 2.0,
  "run_cycle_distance": _model.half_step() * 2.0, "support_shift": 0.0,
  "support_points_world": _support_points.duplicate(), "flight": false, "facing_right": _facing_right,
  "foot_anchor": Vector2.ZERO, "foot_point": sprite.position, "diagnostics": _issues.duplicate(),
  "head_reference": str(_rig_data.head_reference), "head_view": "upright", "head_size_parent": head_size,
  "head_bounds_parent": bounds, "head_texture": head.texture.resource_path, "neutral_ready": _rig_ready,
  "relaxed_arms": true, "empty_hands": true, "distance_rebases": _model.distance_rebases,
  "neck_point": neck, "hip_point": _model.hip, "rig_node_count": _parts.size() + 1,
  "rig_texture_count": _rig_textures.size(), "rig": _model.snapshot(),
  "manifest_load_count": _manifest_load_count, "texture_cache_size": _textures.size(),
  "texture_load_count": _texture_load_count, "max_cache_textures": MAX_CACHE_TEXTURES}
 return snap
