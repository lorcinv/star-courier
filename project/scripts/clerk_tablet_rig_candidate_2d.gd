extends "res://scripts/clerk_observed_motion_2d.gd"
## Source-only tablet layer candidate. Existing head/torso/pelvis/legs are never
## replaced by a wholebody gesture texture. Root and feet are not written here.
const UprightBlink=preload("res://scripts/clerk_motion_r5_blink_pose_2d.gd")
const TABLET_DIR:String="res://assets/2d_v5/actors/tablet_rig_candidate_v1/"
const TABLET_RAISE_SECONDS:float=0.18
var _tablet_parts:Dictionary={}
var _tablet_nodes:Dictionary={}
var _tablet_textures:Dictionary={}
var _tablet_ready:bool=false
var _tablet_weight:float=0.0
var _tablet_target:float=0.0
var _tablet_clock:float=-1.0
var _tablet_gesture:String="align"
var _tablet_joints:Dictionary={}

func _preload_motion_assets() -> void:
 super._preload_motion_assets()
 if not _rig_ready:return
 _model=UprightBlink.new()
 if not _model.configure(_rig_data,_height):_issue("tablet_rig_invalid_geometry");return
 var record:Variant=JSON.parse_string(FileAccess.get_file_as_string(TABLET_DIR+"REGISTRATION.json"))
 if not record is Dictionary:return
 _tablet_parts=record.parts
 for key in _tablet_parts:
  var art:Texture2D=_texture(TABLET_DIR+str(_tablet_parts[key].file))
  if art==null:_issue("tablet_piece_missing:"+key);return
  _tablet_textures[key]=art
 for key in ["near_upper","near_fore","far_upper","far_fore","near_hand","far_hand","tablet"]:
  var part:=Sprite2D.new();part.name="Tablet_"+key;part.centered=false
  part.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;part.visible=false
  part.z_index=45 if str(key).begins_with("near") else 42
  if key=="tablet":part.z_index=43
  _rig.add_child(part);_tablet_nodes[key]=part
 _tablet_ready=true

func set_visual_context(clock:float,enabled:bool=true,reduced:bool=false) -> void:
 super.set_visual_context(clock,enabled,reduced)
 if not _tablet_ready or not is_finite(clock):return
 if _uses_accepted_pose_clock():
  _tablet_clock=clock
  return
 var dt:float=clampf(clock-_tablet_clock,0.0,0.1) if _tablet_clock>=0.0 else 0.0
 _tablet_clock=clock
 if not is_instance_valid(_node()) or not _node().is_visible_in_tree():return
 if _rig_active and (_tablet_weight>0.0 or _tablet_target>0.0):
  _tablet_weight=move_toward(_tablet_weight,_tablet_target,dt/TABLET_RAISE_SECONDS)
  _render_rig()

func apply_gesture(pose_id:String,facing_right:bool=true) -> bool:
 if pose_id not in ["reach","align","ready"] or not _tablet_ready:return false
 if not _rig_active:
  if not super.apply_player_pose("idle",_rig_distance,facing_right,true,_observed_clock,0.0):return false
 _tablet_gesture=pose_id;_tablet_target=1.0;_tablet_clock=_owner_clock
 _pose=pose_id;_facing_right=facing_right
 _node().set_meta("pose",pose_id)
 # Entry does not change lower-body pose, contact IDs or head texture/scale.
 _render_rig();return true

func apply_idle(facing_right:bool=true) -> bool:
 _tablet_target=0.0
 return super.apply_idle(facing_right)

func apply_player_pose(state:String,distance_px:float,right:bool,enabled:bool=true,clock:float=NAN,stop_age:float=0.0) -> bool:
 if state in MOVING_STATES:_tablet_target=0.0
 return super.apply_player_pose(state,distance_px,right,enabled,clock,stop_age)

func _apply_observed_segments(segments:Array,frame_clock:float,enabled:bool,source:String) -> bool:
 if not segments.is_empty() and str(segments[-1].after.state) in MOVING_STATES:_tablet_target=0.0
 return super._apply_observed_segments(segments,frame_clock,enabled,source)

func _hide_rig() -> void:
 _tablet_weight=0.0;_tablet_target=0.0
 super._hide_rig()

func _tablet_transform(node:Sprite2D,key:String,at:Vector2,angle:float,local_mirror:float=1.0) -> void:
 var record:Dictionary=_tablet_parts[key]
 var s:float=_height/240.0;var sign_x:float=1.0 if _facing_right else -1.0
 var bx:Vector2=Vector2(cos(angle),sin(angle))*s*sign_x*local_mirror
 var by:Vector2=Vector2(-sin(angle),cos(angle))*s
 node.texture=_tablet_textures[key]
 var root:Vector2=_point(record.root)
 node.transform=Transform2D(bx,by,at-bx*root.x-by*root.y)
 node.visible=true

func _tablet_segment(key:String,from:Vector2,to:Vector2) -> void:
 var vector:Vector2=_point(_tablet_parts[key].tip)-_point(_tablet_parts[key].root)
 if not _facing_right:vector.x=-vector.x
 _tablet_transform(_tablet_nodes[key],key,from,(to-from).angle()-vector.angle())

func _uses_accepted_pose_clock() -> bool:
 return false

func _render_rig() -> void:
 super._render_rig()
 _render_tablet_pose()

func _render_tablet_pose() -> void:
 if not _tablet_ready:return
 var active:bool=_tablet_weight>0.000001
 _parts.near_arm.visible=not active;_parts.far_arm.visible=not active
 for node in _tablet_nodes.values():node.visible=active
 if not active:return
 var s:float=_height/240.0;var sign_x:float=1.0 if _facing_right else -1.0
 var at:Vector2=_model.origin;var hip_local:Vector2=_model.hip-at
 var weight:float=_tablet_weight*_tablet_weight*(3.0-2.0*_tablet_weight)
 _tablet_joints={}
 for side in ["near","far"]:
  var shoulder:Vector2=_model.upper_body.shoulder_world[side]-at
  var upper_key:String=side+"_upper";var fore_key:String=side+"_fore"
  var upper_vec:Vector2=_point(_tablet_parts[upper_key].tip)-_point(_tablet_parts[upper_key].root)
  var lower_vec:Vector2=_point(_tablet_parts[fore_key].tip)-_point(_tablet_parts[fore_key].root)
  var relaxed:Vector2=(upper_vec+lower_vec)*Vector2(sign_x,1.0)*s
  relaxed=relaxed.rotated(float(_model.upper_body.arm_world_angle[side]))
  var held:Vector2=hip_local+Vector2(-5.0 if side=="near" else 26.0,-31.0 if side=="near" else -22.0)*Vector2(sign_x,1.0)*s
  var wrist:Vector2=(shoulder+relaxed).lerp(held,weight)
  var l1:float=upper_vec.length()*s;var l2:float=lower_vec.length()*s
  var distance:float=shoulder.distance_to(wrist)
  if distance>l1+l2+0.001 or distance<absf(l1-l2)-0.001:
   _issue("tablet_wrist_outside_arm_annulus");continue
  var toward:Vector2=(wrist-shoulder).normalized()
  var along:float=(l1*l1-l2*l2+distance*distance)/(2.0*maxf(distance,0.00001))
  var high:float=sqrt(maxf(0.0,l1*l1-along*along))
  var bend:Vector2=Vector2(-toward.y,toward.x)*sign_x*(1.0 if side=="near" else -1.0)
  var elbow:Vector2=shoulder+toward*along+bend*high
  _tablet_segment(upper_key,shoulder,elbow);_tablet_segment(fore_key,elbow,wrist)
  var hand_key:String="hand_tap" if side=="near" and _tablet_gesture=="align" else ("hand_hold" if side=="near" else "hand_support")
  _tablet_transform(_tablet_nodes[side+"_hand"],hand_key,wrist,0.0,-1.0 if side=="far" else 1.0)
  _tablet_joints[side]={"shoulder":shoulder,"elbow":elbow,"wrist":wrist,"upper_length":l1,"fore_length":l2}
 var tablet_pos:Vector2=hip_local+Vector2(18.0,4.0).lerp(Vector2(8.0,-28.0),weight)*Vector2(sign_x,1.0)*s
 _tablet_transform(_tablet_nodes.tablet,"tablet",tablet_pos,0.0)
 _tablet_nodes.tablet.visible=_tablet_weight>0.08

func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 result.tablet_rig={"ready":_tablet_ready,"weight":_tablet_weight,"target":_tablet_target,"gesture":_tablet_gesture,
  "joints":_tablet_joints.duplicate(true),"body_texture_switch":false,"status":"source candidate; native overlap and gesture timing unreviewed"}
 return result
