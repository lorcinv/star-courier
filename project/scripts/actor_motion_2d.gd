extends RefCounted
## Caller-driven, foot-registered image-generated raster poses. No timers, process,
## tweens, inventory state, or RNG. One adapter per sprite; no nodes are created.
## Positive distance is cumulative travel in logical world pixels. Keep it fixed
## on idle/focus loss; hidden sprites are additionally frozen here.
const MANIFEST_PATHS:Array[String]=[
 "res://assets/2d_v5/actors/cooperative/motion-manifest.json",
 "res://assets/2d_v5/npcs/walk_exit/motion-manifest.json"]
const ACTOR_IDS:Array[String]=["clerk","human_courier","elf_archivist","alien_botanist","robot_machinist"]
const MAX_WALK_FRAMES:int=32
const MAX_WALK_PHASES:int=64
const MAX_GESTURES:int=8
const MAX_CACHE_TEXTURES:int=112
#64 clerk raster samples +3 tablet +16 NPC walk +4 farewell =87 fixed PNGs.
# The112 cap is explicit headroom for registered idle assets; no per-call textures.
static var _ready:bool=false
static var _actors:Dictionary={}
static var _textures:Dictionary={}
static var _manifest_load_count:int=0
static var _texture_load_count:int=0
var appearance_id:String=""
var _target:WeakRef
var _height:float=240.0
var _original:Dictionary={}
var _record:Dictionary={}
var _frame:Dictionary={}
var _issues:Array[String]=[]
var _active:bool=false
var _facing_right:bool=true
var _frame_index:int=-1
var _pose:String=""
var _walk_phase:int=-1
var _walk_phase_fraction:float=0.0
var _stance_shift:float=0.0
var _stance_material:ShaderMaterial
var _support_points:Dictionary={}
const STANCE_SHADER:String="""shader_type canvas_item;
render_mode unshaded;
uniform float support_shift=0.0;
uniform float hip_y=180.0;
uniform float floor_y=280.0;
varying vec4 actor_tint;
void vertex(){actor_tint=COLOR;}
void fragment(){
 vec2 p=UV/TEXTURE_PIXEL_SIZE;
 float w=smoothstep(hip_y+5.0,floor_y-16.0,p.y);
 vec2 uv=UV-vec2(support_shift*w,0.0)*TEXTURE_PIXEL_SIZE;
 COLOR=actor_tint*texture(TEXTURE,uv);
}
"""

static func _ensure_manifests() -> void:
 if _ready:return
 _ready=true
 for path in MANIFEST_PATHS:
  _manifest_load_count+=1
  if not FileAccess.file_exists(path):continue
  var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
  if not data is Dictionary or not data.get("actors") is Dictionary:continue
  for id in ACTOR_IDS:
   if data.actors.get(id) is Dictionary:_actors[id]=data.actors[id]

static func _point(value:Variant) -> Vector2:
 if value is Array and value.size()==2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
  var result:=Vector2(float(value[0]),float(value[1]))
  if is_finite(result.x) and is_finite(result.y):return result
 return Vector2(INF,INF)

static func _texture(path:String) -> Texture2D:
 var full:String=path if path.begins_with("res://") else "res://"+path
 # Paths originate only in the fixed, bounded actor manifests, never a binding.
 if not full.begins_with("res://assets/2d_v5/") or not full.ends_with(".png") or ".." in full:return null
 if not _textures.has(full):
  if _textures.size()>=MAX_CACHE_TEXTURES:return null
  _texture_load_count+=1
  _textures[full]=load(full) as Texture2D if ResourceLoader.exists(full) else null
 return _textures[full] as Texture2D

func _init(sprite:Sprite2D=null,id:String="",target_height:float=240.0) -> void:
 _ensure_manifests();appearance_id=id
 if not is_instance_valid(sprite):_issue("missing_target");return
 _target=weakref(sprite)
 if not is_finite(target_height) or target_height<=0:_issue("invalid_target_height");return
 _height=target_height
 _original={"texture":sprite.texture,"offset":sprite.offset,"scale":sprite.scale,"centered":sprite.centered,"flip_h":sprite.flip_h,"flip_v":sprite.flip_v,"hframes":sprite.hframes,"vframes":sprite.vframes,"frame":sprite.frame,"region_enabled":sprite.region_enabled,"pose":sprite.get_meta("pose","idle"),"art_id":sprite.get_meta("art_id",""),"material":sprite.material}
 _record=_actors.get(id,{})
 if _record.is_empty():_issue("missing_motion_manifest:"+id)
 else:_preload_motion_assets()

func _preload_motion_assets() -> void:
 # Bounded warm-up happens on binding, before any requested movement. Clerk
 # has64 assembled frames +3 tablet textures; all five actors total87 PNGs.
 for kind in ["walk","run"]:
  var frames:Variant=_record.get(kind,[])
  if not frames is Array or frames.size()>MAX_WALK_FRAMES:continue
  for frame in frames:
   if frame is Dictionary:_texture(str(frame.get("runtime","")))
 var gestures:Variant=_record.get("gestures",{})
 if gestures is Dictionary and gestures.size()<=MAX_GESTURES:
  for frame in gestures.values():
   if frame is Dictionary:_texture(str(frame.get("runtime","")))

func _node() -> Sprite2D:
 return _target.get_ref() as Sprite2D if _target!=null else null

func _issue(code:String) -> void:
 # Invalid caller-provided pose names cannot grow the diagnostic list forever.
 if not _issues.has(code) and _issues.size()<16:_issues.append(code)
 var sprite:Sprite2D=_node()
 if is_instance_valid(sprite):sprite.set_meta("motion_diagnostics",_issues.duplicate())

func apply_walk(distance_px:float,facing_right:bool=true) -> bool:
 return _apply_locomotion("walk",distance_px,facing_right)

func apply_run(distance_px:float,facing_right:bool=true) -> bool:
 return _apply_locomotion("run",distance_px,facing_right)

func apply_idle(facing_right:bool=true) -> bool:
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or _original.is_empty() or not sprite.is_visible_in_tree():return false
 restore_original()
 if sprite.texture==null:return false
 var original_foot:Vector2=-_original.offset
 if bool(_original.centered):original_foot+=Vector2(sprite.texture.get_width(),sprite.texture.get_height())*.5
 var native_right:bool=str(_record.get("idle_facing","right"))=="right"
 var flipped:bool=facing_right!=native_right
 sprite.centered=false;sprite.flip_h=flipped;sprite.flip_v=bool(_original.flip_v)
 sprite.offset=-Vector2(float(sprite.texture.get_width())-original_foot.x if flipped else original_foot.x,original_foot.y)
 _frame={"foot_anchor":[original_foot.x,original_foot.y],"hip_anchor":[original_foot.x,original_foot.y-_height*.4],"body_height":_height}
 _active=true;_pose="idle";_facing_right=facing_right;_frame_index=-1;_walk_phase=-1;_walk_phase_fraction=0
 sprite.set_meta("pose","idle");sprite.set_meta("motion_frame",-1);sprite.set_meta("motion_facing_right",facing_right);sprite.set_meta("motion_active",true)
 return true

func _apply_locomotion(kind:String,distance_px:float,facing_right:bool=true) -> bool:
 if not is_finite(distance_px) or distance_px<0:_issue("invalid_walk_distance");return false
 var frames:Variant=_record.get(kind,[])
 if not frames is Array or frames.size()<3 or frames.size()>MAX_WALK_FRAMES:_issue("missing_or_invalid_walk_frames");return false
 var cycle:float=_cycle_distance(kind)
 if not is_finite(cycle) or cycle<=0:_issue("invalid_walk_cycle_distance");return false
 # Explicit support/contact beats avoid an abrupt second-contact -> first-
 # contact cut in a four-drawing sheet. Reusing a passing drawing does not
 # synthesize art. All phase/cadence state remains derived from caller distance.
 var sequence:Variant=_record.get(kind+"_sequence",[])
 if not sequence is Array or sequence.size()>MAX_WALK_PHASES:_issue("invalid_walk_sequence");return false
 var count:int=frames.size() if sequence.is_empty() else sequence.size()
 if count<3:_issue("invalid_walk_sequence");return false
 var weights:Variant=_record.get(kind+"_phase_weights",[])
 if not weights is Array or (not weights.is_empty() and weights.size()!=count):_issue("invalid_walk_weights");return false
 var total:float=0.0
 for i in count:
  if not sequence.is_empty() and (not (sequence[i] is int or sequence[i] is float) or not is_finite(float(sequence[i])) or float(sequence[i])!=floor(float(sequence[i])) or int(sequence[i])<0 or int(sequence[i])>=frames.size()):_issue("invalid_walk_sequence");return false
  var weight:float=1.0
  if not weights.is_empty():
   if not (weights[i] is int or weights[i] is float):_issue("invalid_walk_weights");return false
   weight=float(weights[i])
  if not is_finite(weight) or weight<=0.0 or weight>8.0:_issue("invalid_walk_weights");return false
  total+=weight
 var remaining:float=fposmod(distance_px,cycle)/cycle*total
 var phase:int=count-1
 var fraction:float=0.0
 for i in count:
  var weight:float=1.0 if weights.is_empty() else float(weights[i])
  if remaining<weight or i==count-1:
   phase=i;fraction=clampf(remaining/weight,0.0,1.0);break
  remaining-=weight
 var index:int=phase if sequence.is_empty() else int(sequence[phase])
 if not frames[index] is Dictionary:_issue("invalid_walk_frame");return false
 var applied:bool=_apply_frame(frames[index],kind,index,facing_right)
 if applied:
  _walk_phase=phase;_walk_phase_fraction=fraction
  _apply_stance_compensation(distance_px,cycle)
 return applied

func _cycle_distance(kind:String) -> float:
 var cycle:float=float(_record.get(kind+"_cycle_distance",120.0))
 var reference:float=float(_record.get(kind+"_reference_height",_height))
 if not is_finite(reference) or reference<=0:return NAN
 return cycle*_height/reference

func walk_cycle_distance() -> float:return _cycle_distance("walk")
func run_cycle_distance() -> float:return _cycle_distance("run")

func _apply_stance_compensation(distance_px:float,cycle:float) -> void:
 var sprite:Sprite2D=_node()
 _stance_shift=0.0;_support_points={}
 if not is_instance_valid(sprite):return
 if not bool(_frame.get("foot_lock",false)):
  sprite.material=_original.get("material");return
 var phase:float=fposmod(distance_px,cycle)/cycle
 var sampled:float=float(_frame.get("distance_phase",phase))
 var feet:Variant=_frame.get("support_feet",[])
 if not feet is Array or feet.size()>2 or not is_finite(sampled):_issue("invalid_support_metadata");return
 var source_cycle:float=cycle/sprite.scale.x
 _stance_shift=-(phase-sampled)*source_cycle
 # These32 samples bound the correction to one sample's distance; rejecting
 # bad metadata cannot pull a leg or body across the screen.
 if absf(_stance_shift)>source_cycle/16.0+0.001:
  _issue("invalid_support_phase");_stance_shift=0;return
 if _stance_material==null:
  var shader:=Shader.new();shader.code=STANCE_SHADER
  _stance_material=ShaderMaterial.new();_stance_material.shader=shader
 _stance_material.set_shader_parameter("support_shift",_stance_shift)
 _stance_material.set_shader_parameter("hip_y",float(_frame.hip_anchor[1]))
 _stance_material.set_shader_parameter("floor_y",float(_frame.foot_anchor[1]))
 sprite.material=_stance_material
 for foot in feet:
  if not foot is Dictionary:continue
  var p:Vector2=_point(foot.get("point"))
  if not is_finite(p.x):continue
  p.x+=_stance_shift
  _support_points[str(foot.get("id","support"))]=sprite.global_transform*anchor_local(p)
 sprite.set_meta("motion_support_shift",_stance_shift)

func apply_gesture(pose_id:String,facing_right:bool=true) -> bool:
 var gestures:Variant=_record.get("gestures",{})
 if not gestures is Dictionary or gestures.size()>MAX_GESTURES or not gestures.get(pose_id) is Dictionary:
  _issue("missing_or_invalid_gesture");return false
 return _apply_frame(gestures[pose_id],pose_id,-1,facing_right)

func _apply_frame(frame_data:Dictionary,pose_id:String,index:int,facing_right:bool) -> bool:
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite):_issue("missing_target");return false
 if _original.is_empty():return false
 if not sprite.is_visible_in_tree():return false
 var foot:Vector2=_point(frame_data.get("foot_anchor"))
 var hip:Vector2=_point(frame_data.get("hip_anchor"))
 var body_height:float=float(frame_data.get("body_height",0.0))
 if not is_finite(foot.x) or not is_finite(hip.x) or not is_finite(body_height) or body_height<=0:
  _issue("invalid_motion_registration");return false
 if not frame_data.get("facing","") in ["right","left"] or frame_data.get("contains_parcel",true)!=false:
  _issue("unsafe_motion_art_metadata");return false
 var path:String=str(frame_data.get("runtime",""))
 var art:Texture2D=_texture(path)
 if art==null:_issue("missing_motion_texture");return false
 if foot.x<0 or foot.y<0 or foot.x>art.get_width() or foot.y>art.get_height() or hip.x<0 or hip.y<0 or hip.x>art.get_width() or hip.y>art.get_height():
  _issue("motion_anchor_outside_texture");return false
 # Sprite2D.flip_h mirrors pixels inside the drawing rect. Re-register its
 # mirrored semantic foot at the same origin instead of mirroring about canvas
 # center or using negative Node2D scales (which decompose into rotation/Y flip).
 sprite.texture=art;sprite.centered=false;sprite.hframes=1;sprite.vframes=1;sprite.frame=0;sprite.region_enabled=false
 sprite.flip_h=facing_right!=(frame_data.get("facing")=="right");sprite.flip_v=false
 sprite.offset=-Vector2(float(art.get_width())-foot.x if sprite.flip_h else foot.x,foot.y)
 sprite.scale=Vector2.ONE*_height/body_height
 _frame=frame_data;_active=true;_facing_right=facing_right;_frame_index=index;_pose=pose_id
 if not pose_id in ["walk","run"]:
  _walk_phase=-1;_walk_phase_fraction=0.0;_stance_shift=0;_support_points={};sprite.material=_original.get("material")
 sprite.set_meta("pose",pose_id);sprite.set_meta("art_id",path);sprite.set_meta("motion_active",true)
 sprite.set_meta("motion_frame",index);sprite.set_meta("motion_facing_right",facing_right)
 sprite.set_meta("motion_diagnostics",_issues.duplicate())
 return true

func restore_original() -> void:
 var sprite:Sprite2D=_node()
 if is_instance_valid(sprite) and _active and not _original.is_empty():
  sprite.texture=_original.texture;sprite.offset=_original.offset;sprite.scale=_original.scale;sprite.centered=_original.centered;sprite.material=_original.get("material")
  sprite.flip_h=_original.flip_h;sprite.flip_v=_original.flip_v;sprite.hframes=_original.hframes;sprite.vframes=_original.vframes;sprite.frame=_original.frame;sprite.region_enabled=_original.region_enabled
  sprite.set_meta("pose",_original.pose);sprite.set_meta("art_id",_original.art_id);sprite.set_meta("motion_active",false);sprite.set_meta("motion_frame",-1);sprite.set_meta("motion_support_shift",0.0)
 _active=false;_frame={};_frame_index=-1;_pose="";_walk_phase=-1;_walk_phase_fraction=0.0;_stance_shift=0;_support_points={}

func is_active() -> bool:return _active

func current_frame() -> Dictionary:return _frame.duplicate(true)

func anchor_local(source_point:Vector2) -> Vector2:
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or sprite.texture==null:return Vector2.ZERO
 return Vector2(float(sprite.texture.get_width())-source_point.x if sprite.flip_h else source_point.x,source_point.y)+sprite.offset

func debug_snapshot() -> Dictionary:
 var sprite:Sprite2D=_node()
 var foot:Vector2=_point(_frame.get("foot_anchor"))
 return {"appearance_id":appearance_id,"available":not _record.is_empty(),"active":_active,"pose":_pose,"frame_index":_frame_index,"walk_phase":_walk_phase,"walk_phase_fraction":_walk_phase_fraction,"walk_cycle_distance":walk_cycle_distance(),"run_cycle_distance":run_cycle_distance(),"support_shift":_stance_shift,"support_points_world":_support_points.duplicate(),"flight":bool(_frame.get("flight",false)),"facing_right":_facing_right,"foot_anchor":foot if _active else Vector2.ZERO,"foot_point":sprite.transform*anchor_local(foot) if _active and is_instance_valid(sprite) else Vector2.ZERO,"diagnostics":_issues.duplicate(),"manifest_load_count":_manifest_load_count,"texture_cache_size":_textures.size(),"texture_load_count":_texture_load_count,"max_cache_textures":MAX_CACHE_TEXTURES}
