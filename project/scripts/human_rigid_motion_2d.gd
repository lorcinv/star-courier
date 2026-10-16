extends "res://scripts/actor_motion_2d.gd"
## Human-only raster cutouts. Caller owns displacement and time; no timers,
## process callbacks, shaders, runtime painting or additional movement speed.
const Pose = preload("res://scripts/human_rigid_pose_2d.gd")
const RIG_MANIFEST:String = "res://assets/2d_v5/actors/human_rig_motion_v1/rig-registration.json"
const PART_PREFIX:String = "res://assets/2d_v5/actors/human_rig_motion_v1/"
const STATES:Array[String] = ["idle", "start", "move", "inertial_stop", "stop"]
const MOVING:Array[String] = ["start", "move", "inertial_stop"]
const MAX_PARTS:int = 16
var _rig_data:Dictionary = {}
var _rig:Node2D
var _parts:Dictionary = {}
var _model:RefCounted
var _rig_active:bool = false
var _full_pose_active:bool = false
var _full_pose_textures:Dictionary = {}
var _rig_ready:bool = false
var _owner_clock:float = 0.0
var _owner_enabled:bool = true
var _owner_reduced:bool = false
var _rig_distance:float = 0.0
var _rig_stop_age:float = 0.0
var _motion_state:String = "idle"

func _preload_motion_assets() -> void:
 # Existing full farewell remains an explicit whole-pose boundary.
 super._preload_motion_assets()
 if appearance_id != "human_courier":_issue("human_rig_identity_mismatch");return
 if not FileAccess.file_exists(RIG_MANIFEST):_issue("missing_human_rig");return
 var parsed:Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_MANIFEST))
 if not parsed is Dictionary or not parsed.get("parts") is Dictionary or parsed.parts.size() > MAX_PARTS:_issue("invalid_human_rig");return
 _rig_data = parsed;_model = Pose.new()
 if not _model.configure(parsed, _height):_issue("invalid_human_geometry");return
 _rig = Node2D.new();_rig.name = "HumanRigidCutouts";_rig.visible = false
 _rig.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST;_node().add_child(_rig)
 var keys:Array = parsed.parts.keys()
 keys.sort_custom(func(a:Variant,b:Variant) -> bool:return int(parsed.parts[a].z) < int(parsed.parts[b].z))
 for key in keys:
  var part:Dictionary = parsed.parts[key];var path:String = "res://" + str(part.path)
  if not path.begins_with(PART_PREFIX) or ".." in path or not path.ends_with(".png"):_issue("unsafe_human_part");return
  var art:Texture2D = load(path) as Texture2D
  if art == null or not _point(part.root).is_finite() or not _point(part.tip).is_finite():_issue("invalid_human_part:"+str(key));return
  var node:Sprite2D = Sprite2D.new();node.name = str(key);node.texture = art;node.centered = false
  node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  # Only sibling order changes. Actor-owned depth still permits counter occlusion.
  node.z_index = 0;_rig.add_child(node);_parts[key] = node
 for side in ["near","far"]:
  for kind in ["arm","thigh","shin","boot"]:
   if not _parts.has(side+"_"+kind):_issue("missing_human_limb");return
 for key in ["head","torso","pelvis","near_sleeve_panel"]:
  if not _parts.has(key):_issue("missing_human_body");return
 for key in ["conversation","handoff","farewell"]:
  var record:Dictionary = parsed.get("full_poses",{}).get(key,{})
  var art:Texture2D = _texture(str(record.get("runtime","")))
  if art == null:_issue("missing_human_full_pose:"+key);return
  _full_pose_textures[key] = art
 _rig_ready = true

func dispose() -> void:
 if is_instance_valid(_rig):_rig.free()
 _parts.clear();_rig_active = false;_rig_ready = false

func set_visual_context(clock:float, enabled:bool = true, reduced:bool = false) -> void:
 if not is_finite(clock):return
 _owner_clock = clock;_owner_enabled = enabled;_owner_reduced = reduced
 if not enabled and _model != null:_model.freeze(clock, _rig_distance)

func apply_npc_pose(state:String, distance:float, right:bool, clock:float, stop_age:float = 0.0) -> bool:
 var sprite:Sprite2D = _node()
 if not is_instance_valid(sprite) or not _rig_ready or state not in STATES or not is_finite(distance) or distance < 0.0:return false
 set_visual_context(clock, _owner_enabled, _owner_reduced)
 if not sprite.is_visible_in_tree() or not _owner_enabled:
  _model.freeze(clock, distance);return true
 if not _rig_active:
  if not _model.initialized or _model.origin.distance_to(sprite.position) > 0.01:_model.reset(sprite.position, right, clock, distance)
  else:_model.freeze(clock, distance)
 if not _model.update(state, distance, sprite.position, right, clock, stop_age, true, _owner_reduced):return false
 _rig_active = true;_rig_distance = distance;_rig_stop_age = stop_age;_motion_state = state
 _facing_right = right;_active = true;_pose = "walk" if state in MOVING else state
 _frame_index = -1;_walk_phase = -1;_walk_phase_fraction = _model.step_fraction;_stance_shift = 0.0
 _frame = {"foot_anchor":[0,0],"hip_anchor":[0,0],"body_height":_height,"facing":"right" if right else "left","contains_parcel":false}
 sprite.texture = null;sprite.material = _original.get("material");sprite.scale = Vector2.ONE
 sprite.rotation = 0.0;sprite.skew = 0.0;sprite.offset = Vector2.ZERO;sprite.flip_h = false;sprite.flip_v = false
 _full_pose_active = false
 for part in _parts.values():part.show()
 _rig.show();_render()
 sprite.set_meta("pose",_pose);sprite.set_meta("motion_frame",-1);sprite.set_meta("motion_active",true)
 sprite.set_meta("motion_facing_right",right);sprite.set_meta("motion_support_shift",0.0);sprite.set_meta("art_id",RIG_MANIFEST)
 return true

func _transform_part(key:String, at:Vector2, angle:float) -> void:
 var p:Dictionary = _rig_data.parts[key];var px:float = float(p.pixel_scale) * _height / float(_rig_data.reference_height)
 var mirror:float = 1.0 if _facing_right else -1.0
 var x:Vector2 = Vector2(cos(angle),sin(angle))*px*mirror
 var y:Vector2 = Vector2(-sin(angle),cos(angle))*px
 var root:Vector2 = _point(p.root)
 _parts[key].transform = Transform2D(x,y,at-x*root.x-y*root.y)

func _rigid(key:String, at:Vector2, angle:float = 0.0) -> void:
 _transform_part(key,at,angle*(1.0 if _facing_right else -1.0))

func _segment(key:String, from:Vector2, to:Vector2) -> void:
 var p:Dictionary = _rig_data.parts[key];var v:Vector2 = _point(p.tip)-_point(p.root)
 if not _facing_right:v.x = -v.x
 _transform_part(key,from,(to-from).angle()-v.angle())

func _render() -> void:
 var origin:Vector2 = _model.origin;var sign_x:float = 1.0 if _facing_right else -1.0
 _support_points.clear()
 for side in ["far","near"]:
  var joint:Dictionary = _model.joints[side]
  _segment(side+"_thigh",joint.hip-origin,joint.knee-origin)
  _segment(side+"_shin",joint.knee-origin,joint.ankle-origin)
  _segment(side+"_shin_front",joint.knee-origin,joint.ankle-origin)
  _rigid(side+"_boot",joint.ankle-origin)
  if bool(_model.feet[side].planted):_support_points[side] = _node().global_transform*(_model.feet[side].position-origin)
 var hip:Vector2 = _model.hip-origin
 _rigid("pelvis",hip)
 var torso:Vector2 = _point(_rig_data.parts.torso.attachment_offset)*_height/240.0;torso.x *= sign_x
 _rigid("torso",hip+torso+_model.shoulder_offset)
 for side in ["far","near"]:
  var key:String = side+"_arm";var p:Dictionary = _rig_data.parts[key]
  var offset:Vector2 = _point(p.attachment_offset)*_height/240.0;offset.x *= sign_x
  var swing:float = _model.arm_angle*(-1.0 if side == "far" else 1.0)
  _rigid(key,hip+offset+_model.shoulder_offset,float(p.rest_angle)+swing)
  if side == "near":
   _rigid("near_arm_back",hip+offset+_model.shoulder_offset,float(p.rest_angle)+swing)
   _rigid("near_sleeve_panel",hip+offset+_model.shoulder_offset,swing)
 var neck:Vector2 = _point(_rig_data.parts.head.attachment_offset)*_height/240.0;neck.x *= sign_x
 _rigid("head",hip+neck+_model.shoulder_offset)

func apply_walk(distance_px:float, facing_right:bool = true) -> bool:
 return apply_npc_pose("move",distance_px,facing_right,_owner_clock)

func apply_run(distance_px:float, facing_right:bool = true) -> bool:
 return apply_walk(distance_px,facing_right)

func apply_idle(facing_right:bool = true) -> bool:
 return apply_npc_pose("idle",_rig_distance,facing_right,_owner_clock,_rig_stop_age)

func hide_rig() -> void:
 if is_instance_valid(_rig):_rig.hide()
 _rig_active = false;_full_pose_active = false
 if _model != null:_model.freeze(_owner_clock,_rig_distance)

func restore_original() -> void:
 hide_rig();super.restore_original()

func apply_full_pose(pose_id:String, facing_right:bool = true) -> bool:
 if not _rig_ready or not _full_pose_textures.has(pose_id):return false
 hide_rig()
 var sprite:Sprite2D = _node()
 sprite.texture = _full_pose_textures[pose_id]
 # The full body's existing scale/foot/hand registration is authoritative.
 # Head uses the same exact source texture and physical scale as locomotion.
 var sign_x:float = 1.0 if facing_right else -1.0
 var origin:Vector2 = _point(_rig_data.full_pose_head_origin_relative_to_foot)
 origin.x *= sign_x
 for key in _parts:_parts[key].visible = key == "head"
 _parts.head.transform = Transform2D(Vector2(sign_x,0),Vector2(0,1),origin)
 _full_pose_active = true;_rig.show()
 _facing_right = facing_right
 return true

func apply_gesture(pose_id:String,facing_right:bool = true) -> bool:
 hide_rig()
 if not super.apply_gesture(pose_id,facing_right):return false
 return apply_full_pose(pose_id,facing_right)

func debug_snapshot() -> Dictionary:
 if not _rig_active:
  var old:Dictionary = super.debug_snapshot();old.rigid_active = false;old.rig_ready = _rig_ready
  old.canonical_head_overlay = _full_pose_active
  if _full_pose_active:
   old.head_texture = _parts.head.texture.resource_path
   old.head_size_parent = Vector2(_parts.head.texture.get_width(),_parts.head.texture.get_height())*_height/240.0
   old.head_bounds_parent = _node().transform*_parts.head.transform*Rect2(Vector2.ZERO,Vector2(_parts.head.texture.get_width(),_parts.head.texture.get_height()))
  return old
 var sprite:Sprite2D = _node();var head:Sprite2D = _parts.head
 return {"appearance_id":appearance_id,"available":_rig_ready,"active":true,"pose":_pose,"motion_state":_motion_state,
 "rigid_active":true,"rig_ready":_rig_ready,"facing_right":_facing_right,"frame_index":-1,"walk_phase":-1,
 "head_size_parent":Vector2(head.texture.get_width(),head.texture.get_height())*_height/240.0,
 "head_bounds_parent":sprite.transform*head.transform*Rect2(Vector2.ZERO,Vector2(head.texture.get_width(),head.texture.get_height())),
 "head_texture":head.texture.resource_path,"support_points_world":_support_points.duplicate(),"support_shift":0.0,
 "relaxed_arms":true,"empty_hands":true,"flight":false,"rig_node_count":_parts.size()+1,"rig_texture_count":_parts.size(),
 "rig":_model.snapshot(),"diagnostics":_issues.duplicate(),"walk_cycle_distance":_model.half_step()*2.0,
 "manifest_load_count":_manifest_load_count,"texture_cache_size":_textures.size(),"texture_load_count":_texture_load_count}
