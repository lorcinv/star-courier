extends Sprite2D
## A foot-registered whole-sprite NPC, with at most one compatible accessory.
## configure() consumes a saved identity; it never writes to the caller's binding
## or uses the global RNG. Empty legacy bindings retain the existing human actor.
## Original idle/handoff plus caller-driven whole-raster motion, not a Spine rig.
const ActorMotion2D=preload("res://scripts/actor_motion_2d.gd")
const NPC_MANIFEST:String="res://assets/2d_v5/npcs/npc-manifest.json"
const ACTOR_MANIFEST:String="res://assets/2d_v5/actors/actor-manifest.json"
const DEFAULT_HEIGHT:float=215.0
const SPECIES_APPEARANCES:Dictionary={"human":"human_courier","elf":"elf_archivist","alien":"alien_botanist","robot":"robot_machinist"}
const APPEARANCE_SPECIES:Dictionary={"human_courier":"human","elf_archivist":"elf","alien_botanist":"alien","robot_machinist":"robot"}
# Technical transfer anchors inspected on the actual 192x256 handoff images:
# elf parcel spans roughly x112..169/y103..142; alien x112..167/y115..155;
# robot x104..175/y106..157. These conservative centers lie inside the painted
# parcel, not on an accessory. The handoff pose itself already contains a parcel.
# As in world_view_2d's human helper, parcel_point() always means the handoff
# transfer destination, even when idle, so callers can start a tween beforehand.
const HANDOFF_PARCEL_ANCHORS:Dictionary={"elf_archivist":Vector2(141,123),"alien_botanist":Vector2(140,135),"robot_machinist":Vector2(140,132)}

static var _manifests_ready:bool=false
static var _appearances:Dictionary={}
static var _human_actor:Dictionary={}
static var _texture_cache:Dictionary={}
static var _manifest_load_count:int=0
static var _texture_load_count:int=0

var appearance_id:String=""
var species:String=""
var accessory_id:String="none"
var appearance_seed:int=0
var pose:String="idle"
var _appearance:Dictionary={}
var _accessory_data:Dictionary={}
var _accessory:Sprite2D
var _foot_anchor:Vector2=Vector2.ZERO
var _parcel_anchor:Vector2=Vector2.ZERO
var _height:float=DEFAULT_HEIGHT
var _valid:bool=false
var _issues:Array[String]=[]
var _motion:RefCounted
var _motion_frame:Dictionary={}

static func _read_json(path:String) -> Dictionary:
 if not FileAccess.file_exists(path):return {}
 var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
 return value if value is Dictionary else {}

static func _ensure_manifests() -> void:
 if _manifests_ready:return
 _manifests_ready=true;_manifest_load_count+=1
 var npcs:Dictionary=_read_json(NPC_MANIFEST)
 if npcs.get("appearances") is Dictionary:_appearances=npcs.appearances
 var actors:Dictionary=_read_json(ACTOR_MANIFEST)
 if actors.get("actors") is Dictionary and actors.actors.get("customer") is Dictionary:_human_actor=actors.actors.customer

static func _texture(path:String) -> Texture2D:
 if path.is_empty():return null
 var resource_path:String=path if path.begins_with("res://") else "res://"+path
 if not _texture_cache.has(resource_path):
  _texture_load_count+=1
  _texture_cache[resource_path]=load(resource_path) as Texture2D if ResourceLoader.exists(resource_path) else null
 return _texture_cache[resource_path] as Texture2D

static func _stable_seed(value:String) -> int:
 var result:int=5381
 for byte in value.to_utf8_buffer():result=(result*33+int(byte))%2147483647
 return result

static func _point(value:Variant,fallback:Vector2=Vector2.ZERO) -> Vector2:
 if value is Array and value.size()==2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
  var result:=Vector2(float(value[0]),float(value[1]))
  if is_finite(result.x) and is_finite(result.y):return result
 return fallback

func _issue(code:String) -> void:
 if not _issues.has(code):_issues.append(code)

func _clear_art() -> void:
 texture=null;_valid=false;set_meta("art_id","")
 if is_instance_valid(_accessory):_accessory.texture=null;_accessory.hide()
 hide()

func _publish_metadata() -> void:
 set_meta("appearance_id",appearance_id);set_meta("identity",appearance_id)
 set_meta("species",species);set_meta("accessory_id",accessory_id)
 set_meta("appearance_seed",appearance_seed);set_meta("pose",pose)
 set_meta("actor_id","customer" if appearance_id=="human_courier" else appearance_id)
 set_meta("npc_valid",_valid);set_meta("npc_diagnostics",_issues.duplicate())

func configure(binding:Dictionary,height:float=DEFAULT_HEIGHT) -> bool:
 _ensure_manifests();_issues.clear();_clear_art();_motion=null;_motion_frame={}
 set_meta("motion_active",false);set_meta("motion_frame",-1);set_meta("motion_diagnostics",[])
 _appearance={};_accessory_data={};_foot_anchor=Vector2.ZERO;_parcel_anchor=Vector2.ZERO
 appearance_id="";species="";accessory_id="none";appearance_seed=0;pose="idle"
 centered=false;offset=Vector2.ZERO;scale=Vector2.ONE;flip_h=false;flip_v=false
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _height=height if is_finite(height) and height>0 else DEFAULT_HEIGHT
 if _height!=height:_issue("invalid_height_defaulted")
 var saved_appearance:Variant=binding.get("appearance_id","")
 var saved_species:Variant=binding.get("species","")
 if not saved_appearance is String or not saved_species is String:
  _issue("invalid_identity_type");_publish_metadata();return false
 appearance_id=saved_appearance;species=saved_species
 if not species.is_empty() and not SPECIES_APPEARANCES.has(species):
  _issue("unknown_species");_publish_metadata();return false
 if appearance_id.is_empty():
  appearance_id=SPECIES_APPEARANCES.get(species,"human_courier")
  if species.is_empty():_issue("legacy_human_default")
 if not APPEARANCE_SPECIES.has(appearance_id):
  _issue("unknown_appearance");_publish_metadata();return false
 if not species.is_empty() and species!=APPEARANCE_SPECIES[appearance_id]:
  _issue("species_appearance_mismatch");_publish_metadata();return false
 species=APPEARANCE_SPECIES[appearance_id]
 var raw_seed:Variant=binding.get("appearance_seed")
 var has_seed:bool=raw_seed is int or (raw_seed is float and is_finite(raw_seed))
 appearance_seed=_stable_seed("star-courier-v1/"+appearance_id)
 if raw_seed is int:appearance_seed=posmod(raw_seed,2147483647)
 elif has_seed:appearance_seed=int(fposmod(raw_seed,2147483647.0))
 elif binding.has("appearance_seed"):_issue("invalid_seed_defaulted")
 _appearance=_human_actor if species=="human" else _appearances.get(appearance_id,{})
 if _appearance.is_empty():
  _issue("missing_species_manifest");_publish_metadata();return false
 if species!="human" and str(_appearance.get("species",""))!=species:
  _issue("manifest_species_mismatch");_appearance={};_publish_metadata();return false
 _foot_anchor=_point(_appearance.get("foot_anchor"))
 var body_height:float=float(_appearance.get("body_height",0))
 if not is_finite(body_height) or body_height<=0 or _foot_anchor==Vector2.ZERO:
  _issue("invalid_body_registration");_appearance={};_publish_metadata();return false
 offset=-_foot_anchor;scale=Vector2.ONE*_height/body_height
 if species=="human":
  _parcel_anchor=_point(_human_actor.get("poses",{}).get("handoff",{}).get("hand_and_parcel_anchors",{}).get("parcel"),Vector2(135.23,115.37))
 else:_parcel_anchor=HANDOFF_PARCEL_ANCHORS[appearance_id]
 _choose_accessory(binding,has_seed)
 set_pose(false)
 return _valid

func _choose_accessory(binding:Dictionary,has_seed:bool) -> void:
 var options:Dictionary=_appearance.get("accessory_options",{})
 var chosen:Variant=binding.get("accessory_id")
 if not binding.has("accessory_id"):
  var ids:Array=options.keys();ids.sort()
  chosen=ids[posmod(appearance_seed,ids.size())] if has_seed and not ids.is_empty() else _appearance.get("default_accessory","none")
 if not chosen is String:
  _issue("invalid_accessory_type");return
 if chosen=="none":return
 if not options.has(chosen) or not options[chosen] is Dictionary:
  _issue("incompatible_accessory");return
 var data:Dictionary=options[chosen]
 if not species in data.get("compatible_species",[]) or not appearance_id in data.get("compatible_appearance_ids",[]):
  _issue("incompatible_accessory");return
 accessory_id=chosen;_accessory_data=data

func set_pose(handoff:bool) -> void:
 var requested_pose:String="handoff" if handoff else "idle"
 if pose==requested_pose and _valid:return
 if _motion!=null:_motion.restore_original()
 _motion_frame={}
 pose=requested_pose
 if _appearance.is_empty():_clear_art();_publish_metadata();return
 var path:String=str(_appearance.get("poses",{}).get(pose,{}).get("runtime",""))
 if path.is_empty():path=str(_appearance.get("world",{}).get(pose,""))
 texture=_texture(path)
 if texture==null:
  _issue("missing_pose_texture:"+pose);_clear_art();_publish_metadata();return
 # A motion/reversed pose must never donate its registration to idle/handoff.
 var pose_data:Dictionary=_appearance.get("poses",{}).get(pose,{})
 _foot_anchor=_point(pose_data.get("foot_anchor"),_point(_appearance.get("foot_anchor")))
 var body_height:float=float(_appearance.get("body_height",240.0))
 offset=-_foot_anchor;scale=Vector2.ONE*_height/body_height;flip_h=false;flip_v=false
 _valid=true;show();set_meta("art_id",path)
 _update_accessory();_publish_metadata()

func set_walk(distance_px:float,facing_right:bool=true) -> bool:
 if not _valid:return false
 if _motion==null:_motion=ActorMotion2D.new(self,appearance_id,_height)
 if not _motion.apply_walk(distance_px,facing_right):return false
 _accept_motion("walk");return true

func set_gesture(pose_id:String,facing_right:bool=true) -> bool:
 if not _valid:return false
 if _motion==null:_motion=ActorMotion2D.new(self,appearance_id,_height)
 if not _motion.apply_gesture(pose_id,facing_right):return false
 _accept_motion(pose_id);return true

func _accept_motion(pose_id:String) -> void:
 _motion_frame=_motion.current_frame();_foot_anchor=_point(_motion_frame.get("foot_anchor"))
 pose=pose_id;_update_accessory();_publish_metadata()

func _art_point(point:Vector2) -> Vector2:
 return Vector2(float(texture.get_width())-point.x if flip_h and texture!=null else point.x,point.y)+offset

func _update_accessory() -> void:
 if is_instance_valid(_accessory):_accessory.hide();_accessory.texture=null
 if _accessory_data.is_empty():return
 var anchors:Dictionary=_accessory_data.get("world_anchors",{})
 if _motion_frame.is_empty() and not anchors.has(pose):_issue("missing_accessory_anchor:"+pose);return
 var art:Texture2D=_texture(str(_accessory_data.get("runtime","")))
 if art==null:_issue("missing_accessory_texture");return
 if not is_instance_valid(_accessory):
  _accessory=Sprite2D.new();_accessory.name="CompatibleAccessory";_accessory.centered=false
  _accessory.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;_accessory.z_index=1;add_child(_accessory)
 var local_anchor:Vector2=_point(_accessory_data.get("local_anchor"))
 var hip:Vector2=_point(_motion_frame.get("hip_anchor")) if not _motion_frame.is_empty() else _point(anchors[pose])
 # Existing accessory pixels were authored on the original RIGHT-facing NPC.
 # New body frames may face LEFT natively, so accessory mirroring follows the
 # semantic facing, not merely the body's texture flip flag.
 var accessory_flip:bool=flip_h if _motion_frame.is_empty() else (_motion_frame.get("facing","right")=="left")!=flip_h
 _accessory.texture=art;_accessory.flip_h=accessory_flip
 _accessory.offset=-Vector2(float(art.get_width())-local_anchor.x if accessory_flip else local_anchor.x,local_anchor.y)
 _accessory.position=_art_point(hip);_accessory.show()
 _accessory.set_meta("accessory_id",accessory_id);_accessory.set_meta("species",species)

func pose_contains_parcel() -> bool:
 # Inspected runtime pixels: the human courier reaches with EMPTY hands;
 # only these three generated nonhuman handoff images contain painted boxes.
 # This is visual asset metadata, not an inference from a pose name.
 return _valid and pose=="handoff" and appearance_id in HANDOFF_PARCEL_ANCHORS

func parcel_point() -> Vector2:
 # transform, rather than position + scale, also supports parent-local rotation.
 if not _valid:return position
 # This API always denotes the ORIGINAL handoff transfer point; walk/farewell
 # art never supplies parcel pixels or an alternate transfer destination.
 var foot:Vector2=_point(_appearance.get("poses",{}).get("handoff",{}).get("foot_anchor"),_point(_appearance.get("foot_anchor")))
 var handoff_scale:float=_height/float(_appearance.get("body_height",240.0))
 return transform*((_parcel_anchor-foot)*handoff_scale/scale)

func binding_snapshot() -> Dictionary:
 return {"appearance_id":appearance_id,"species":species,"appearance_seed":appearance_seed,"accessory_id":accessory_id}

func debug_snapshot() -> Dictionary:
 return {"valid":_valid,"appearance_id":appearance_id,"identity":appearance_id,"species":species,"accessory_id":accessory_id,"appearance_seed":appearance_seed,"pose":pose,"pose_contains_parcel":pose_contains_parcel(),"height":_height,"foot_anchor":_foot_anchor,"foot_point":transform*_art_point(_foot_anchor),"parcel_anchor":_parcel_anchor,"parcel_point":parcel_point(),"parcel_anchor_source":"actor_manifest" if species=="human" else "inspected_handoff_pixels","accessory_visible":is_instance_valid(_accessory) and _accessory.visible,"accessory_child_count":1 if is_instance_valid(_accessory) else 0,"diagnostics":_issues.duplicate(),"manifest_load_count":_manifest_load_count,"texture_cache_size":_texture_cache.size(),"texture_load_count":_texture_load_count,"motion":_motion.debug_snapshot() if _motion!=null else {"active":false,"available":false}}
