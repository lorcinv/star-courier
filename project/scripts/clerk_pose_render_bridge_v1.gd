extends "res://scripts/clerk_pose_owner_adapter_v1.gd"
## DEFAULT OFF. Draw-only leaf. No World selector, root writes, or new clock.
## Bind AFTER inherited preload, BEFORE the first model reset/pose call.
const BRIDGE_KEYS:Array[String]=["torso","head","far_upper","far_fore","far_hand","near_upper","near_fore","near_hand","tablet"]
const BRIDGE_OVERLAY_KEYS:Array[String]=["far_upper","far_fore","far_hand","near_upper","near_fore","near_hand","tablet"]
const BRIDGE_TEXTURE_KEYS:Array[String]=["torso","head_level","head_midpoint","head_reading","far_upper","far_fore","near_upper","near_fore","near_hand_relaxed","far_hand_relaxed","hand_tap","hand_hold","hand_support","tablet"]
var pose_render_bridge_enabled:bool=false
var _bridge_textures:Dictionary={}
var _bridge_nodes:Dictionary={}
var _bridge_last_draw:Dictionary={}
var _bridge_last_facing:bool=true
var _bridge_explicit_completion:bool=false
var _bridge_status:String="disabled"

func bind_pose_renderer(profile:Dictionary,tablet_parts:Dictionary,head_views:Array,textures:Dictionary) -> bool:
 # This is an initialization hook, never a live contact/model replacement.
 if pose_render_bridge_enabled or accepted_pose_experiment_enabled or not _rig_ready or not _tablet_ready:return false
 if _model==null or _model.initialized or not is_instance_valid(_rig):return false
 if _rig.transform!=Transform2D.IDENTITY or _rig.get_parent()!=_node():return false
 if head_views.size()!=3:return false
 var expected_heads:Array[String]=["head_level","head_midpoint","head_reading"]
 var expected_roots:Array[Vector2]=[Vector2(53.35194672131147,91.0),Vector2(53.39856557377049,91.18647540983608),Vector2(53.80532786885246,91.65266393442623)]
 for i in range(3):
  if not head_views[i] is Dictionary or str(head_views[i].get("texture_key",""))!=expected_heads[i]:return false
  if not _bridge_point(head_views[i].get("root")).is_finite():return false
  if _bridge_point(head_views[i].root).distance_to(expected_roots[i])>0.000001:return false
 for key in BRIDGE_TEXTURE_KEYS:
  if not textures.get(key) is Texture2D or textures[key].get_width()<=0 or textures[key].get_height()<=0:return false
 for key in ["near_hand_relaxed","far_hand_relaxed"]:
  if not tablet_parts.get(key) is Dictionary or not tablet_parts[key].has_all(["root","tip"]):return false
 for key in ["torso","head","pelvis","near_arm","far_arm"]:
  if not _parts.get(key) is Sprite2D:return false
 for key in BRIDGE_OVERLAY_KEYS:
  if not _tablet_nodes.get(key) is Sprite2D:return false
 var nodes:Dictionary={"torso":_parts.torso,"head":_parts.head}
 for key in BRIDGE_OVERLAY_KEYS:nodes[key]=_tablet_nodes[key]
 # The isolated rig must contain only its known sibling cutouts.
 if _rig.get_child_count()!=_parts.size()+_tablet_nodes.size():return false
 for node in _parts.values()+_tablet_nodes.values():
  if not node is Sprite2D or node.get_parent()!=_rig:return false
 if not enable_pose_experiment(profile,tablet_parts):return false
 if not set_pose_head_views(head_views):return false
 _bridge_textures=textures.duplicate();_bridge_nodes=nodes
 for key in _parts:
  _parts[key].set_meta("rig_layer",int(profile.parts[key].get("z",0)))
 for node in _parts.values()+_tablet_nodes.values():
  # Absolute or additive child depth can escape counter/foreground occlusion.
  node.z_index=0;node.z_as_relative=true;node.show_behind_parent=false
  node.top_level=false;node.centered=false;node.offset=Vector2.ZERO
  node.flip_h=false;node.flip_v=false;node.hframes=1;node.vframes=1;node.frame=0
  node.region_enabled=false;node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  node.material=null;node.use_parent_material=false
 _rig.z_index=0;_rig.z_as_relative=true;_rig.y_sort_enabled=false
 pose_render_bridge_enabled=true;_bridge_status="bound_before_initialization"
 return true

func _bridge_point(value:Variant) -> Vector2:
 if value is Vector2:return value
 return _point(value)

func _bridge_has_owner() -> bool:
 return not _cooperative_gesture.is_empty() or _phone_owner!=0

func _render_tablet_pose() -> void:
 if not pose_render_bridge_enabled:super._render_tablet_pose();return
 if not _rig_active or _model==null or not _model.initialized:return
 # This bridge has no accepted walking placement provider. Keep the inherited
 # moving body visible, explicitly expose the unsupported boundary, and never
 # suggest that the independent articulated-walking candidate was integrated.
 if _model.travelling or _model.settling:
  _bridge_restore_inherited_upper()
  _bridge_status="unsupported_moving_placement_provider"
  _issue(_bridge_status)
  return
 var context:Dictionary=accepted_pose_context()
 if context.is_empty():return
 if _bridge_has_owner():_bridge_explicit_completion=false
 elif not _bridge_explicit_completion and float(context.draw_progress)>0.000001:
  # Caller must retain the closing owner while consuming its lower slices.
  # Ordinary early release does NOT invent time or snap the head/prop to rest.
  if not _bridge_last_draw.is_empty():
   _bridge_apply_result(_bridge_last_draw,_bridge_last_facing)
  _bridge_status="unsupported_unlowered_release"
  _issue(_bridge_status)
  return
 var evaluated:Dictionary=_pose_helper.evaluate(context)
 if not _bridge_apply_result(evaluated,bool(context.facing_right)):
  _bridge_status="invalid_evaluated_placement";_issue(_bridge_status)
  return
 _pose_result=evaluated
 _bridge_last_draw=evaluated.duplicate(true);_bridge_last_facing=bool(context.facing_right)
 _bridge_status="drawn_neutral_tablet_only"

func _bridge_apply_result(result:Dictionary,right:bool) -> bool:
 # Validate the whole proposal first. Invalid rows cannot partially draw.
 if not result.get("valid",false) or not result.get("placements") is Dictionary:return false
 var scale_px:float=float(result.get("scale",NAN))
 if not is_finite(scale_px) or scale_px<=0.0 or absf(scale_px-_height/240.0)>0.000001:return false
 var proposed:Dictionary={}
 var placements:Dictionary=result.placements
 for key in BRIDGE_KEYS:
  if not placements.get(key) is Dictionary:return false
  var p:Dictionary=placements[key]
  if not p.has_all(["texture_key","at","angle","root","z","mirror"]):return false
  var texture_key:String=str(p.texture_key)
  if not _bridge_textures.get(texture_key) is Texture2D:return false
  var at:Vector2=_bridge_point(p.at);var root:Vector2=_bridge_point(p.root)
  var angle:float=float(p.angle);var mirror:float=float(p.mirror)
  if not at.is_finite() or not root.is_finite() or not is_finite(angle) or mirror not in [-1.0,1.0]:return false
  var facing:float=1.0 if right else -1.0
  var bx:Vector2=Vector2(cos(angle),sin(angle))*scale_px*facing*mirror
  var by:Vector2=Vector2(-sin(angle),cos(angle))*scale_px
  proposed[key]={"transform":Transform2D(bx,by,at-bx*root.x-by*root.y),"texture":_bridge_textures[texture_key],"layer":int(p.z)}
 for key in BRIDGE_KEYS:
  var node:Sprite2D=_bridge_nodes[key]
  node.texture=proposed[key].texture;node.transform=proposed[key].transform
  node.set_meta("rig_layer",proposed[key].layer)
  node.visible=true
 _bridge_nodes.tablet.visible=bool(result.get("prop_visible",true))
 # Segments and relaxed-hand cutouts are used even at p=0: no whole-arm
 # activation switch at pickup. Torso owns the waist; no duplicate pelvis.
 _parts.near_arm.visible=false;_parts.far_arm.visible=false;_parts.pelvis.visible=false
 _bridge_sort_siblings()
 return true

func _bridge_sort_siblings() -> void:
 var siblings:Array=_rig.get_children()
 siblings.sort_custom(func(a:Node,b:Node) -> bool:
  var az:int=int(a.get_meta("rig_layer",0));var bz:int=int(b.get_meta("rig_layer",0))
  return str(a.name)<str(b.name) if az==bz else az<bz)
 for i in range(siblings.size()):_rig.move_child(siblings[i],i)

func _bridge_restore_inherited_upper() -> void:
 # Called after the inherited renderer has placed its body for this sample.
 for key in BRIDGE_OVERLAY_KEYS:_bridge_nodes[key].visible=false
 _parts.near_arm.visible=true;_parts.far_arm.visible=true;_parts.pelvis.visible=false
 for key in ["torso","head"]:
  _parts[key].set_meta("rig_layer",int(_rig_data.parts[key].z))
 _bridge_sort_siblings()

func reset_cooperative_completion(right:bool,owner:int) -> void:
 # The inherited explicit endpoint publishes final-ready, NOT neutral. Set
 # the draw permission before super, whose source03 implementation renders.
 if pose_render_bridge_enabled:_bridge_explicit_completion=true
 super.reset_cooperative_completion(right,owner)

func render_bridge_snapshot() -> Dictionary:
 return {"enabled":pose_render_bridge_enabled,"status":_bridge_status,
  "draw_count":_bridge_nodes.size(),"head_nodes":1 if pose_render_bridge_enabled else 0,
  "prop_nodes":1 if pose_render_bridge_enabled else 0,
  "moving_provider":"UNSUPPORTED; separate V4 candidate not integrated",
  "depth":"zero relative z; character-local sibling order",
  "runtime_acceptance":"PENDING; no native visual/performance claim"}
