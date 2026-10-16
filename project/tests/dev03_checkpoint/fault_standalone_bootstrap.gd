extends RefCounted
## Opt-in construction only. Production World selector is deliberately unchanged.
const Leaf=preload("res://tests/dev03_checkpoint/fault_standalone_leaf.gd")
const RECIPE:String="res://assets/2d_v5/actors/clerk_runtime_bootstrap_v1/runtime-resources.json"
const RECIPE_SHA:String="7114f0c40f49218da0d247a32ccaa14641fe96e723a19a144b597b700e40d308"
const COPY_PROPERTIES:Array[String]=["texture","offset","scale","centered","flip_h","flip_v","hframes","vframes","frame","region_enabled","material","position","rotation","skew"]

static func create(target:Sprite2D,height:float=210.0) -> Dictionary:
 if not is_instance_valid(target) or not is_finite(height) or height<=0.0:return {"ok":false,"error":"invalid_target_or_height"}
 if target.has_node("ClerkRigidCutouts") or bool(target.get_meta("motion_active",false)):return {"ok":false,"error":"already_bound_target"}
 if not FileAccess.file_exists(RECIPE) or FileAccess.get_sha256(RECIPE)!=RECIPE_SHA:return {"ok":false,"error":"missing_or_changed_recipe"}
 var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(RECIPE))
 if not parsed is Dictionary:return {"ok":false,"error":"invalid_recipe"}
 # Hash and import-readiness validation occurs before even staging a constructor.
 var textures:Dictionary={}
 for row in parsed.resources:
  var path:String="res://"+str(row.runtime)
  if not path.begins_with("res://assets/2d_v5/") or ".." in path:return {"ok":false,"error":"unsafe_resource_path"}
  if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=str(row.sha256):return {"ok":false,"error":"missing_or_changed_resource","path":path}
  if path.ends_with(".png"):
   if not ResourceLoader.exists(path):return {"ok":false,"error":"resource_not_imported","path":path}
   var texture:Texture2D=load(path) as Texture2D
   if texture==null or texture.get_width()<=0:return {"ok":false,"error":"invalid_texture","path":path}
   textures[path]=texture
 var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(parsed.profile)))
 var contracts:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(parsed.contracts)))
 var heads:Array=JSON.parse_string(FileAccess.get_file_as_string(str(parsed.heads)))
 var bank:Dictionary={}
 for key in parsed.textures:
  if not textures.has(parsed.textures[key]):return {"ok":false,"error":"texture_not_pinned","key":key}
  bank[key]=textures[parsed.textures[key]]
 # The inherited constructor sees real manifests and ResourceLoader textures.
 # It may only mutate this unattached shadow. No fixture.prepare or ImageTexture.
 var shadow:=Sprite2D.new()
 for property in COPY_PROPERTIES:shadow.set(property,target.get(property))
 for key in target.get_meta_list():shadow.set_meta(key,target.get_meta(key))
 var motion=Leaf.new(shadow,"clerk",height)
 if not motion._issues.is_empty() or not motion._rig_ready or not motion._tablet_ready or motion._model==null:
  var issues:Array=motion._issues.duplicate();shadow.free()
  return {"ok":false,"error":"real_constructor_failed","issues":issues}
 if motion._model.initialized or not motion.bind_coupled_renderer(profile,contracts.tablet_parts,heads,bank):
  shadow.free();return {"ok":false,"error":"preinit_binding_failed"}
 # Historical blink texture is only cached by inheritance, never selected here.
 motion._blink_ready=false
 for key in ["head","head_half","head_closed","head_gaze","head_closed_candidate"]:motion._rig_textures[key]=bank.head_level
 motion._parts.head.texture=bank.head_level
 if motion._model.initialized or motion._tablet_nodes.size()!=7 or not motion._tablet_nodes.has("tablet"):
  shadow.free();return {"ok":false,"error":"invalid_preinit_state"}
 # Commit has no fallible resource operations. Target pose/model remain unstarted.
 var rig:Node2D=motion._rig
 shadow.remove_child(rig);target.add_child(rig)
 motion._target=weakref(target)
 shadow.free()
 return {"ok":true,"motion":motion,"model_initialized":false,"runtime_loader":"real_constructor","native_acceptance":false}
