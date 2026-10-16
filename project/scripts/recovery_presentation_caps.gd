extends RefCounted
## Recovery-only presentation receipt. This class never preloads optional art,
## authors routes, repairs metadata, or changes the save/simulation protocol.
const METEOR_ROOT:String="res://assets/2d_v5/events/meteor/"
const METEOR_MANIFEST_SHA:String="3de6c3b030c5f4c0e03406a525934868b6e4cf48c0f8fcbfe4ba3c4657b1ed7e"
const METEOR_SPRITES:Dictionary={
 "meteor":{"sha256":"dbd7fe2f013fc7c16de64774334c5927990f08a2018b94ee6a5a3f1bb9b01164","size":192,"anchor":96.0},
 "fragment-a":{"sha256":"e9e51cdcc9aa11e0617ab0a1fa936dc39e4e0d1ac006a25ddc3c9c33801f1a6d","size":64,"anchor":32.0},
 "fragment-b":{"sha256":"7a4e65c0427b4f9a03e73319362ea074c712f171eb37eb4fba74c57a14f69f67","size":64,"anchor":32.0}
}

static func group_available(id:String) -> bool:
 match id:
  "meteor":return _meteor_receipt_ready(METEOR_ROOT,true)
  # No approved complete receipt exists for these groups. File presence or a
  # few poses can never enable them. Bird also depends on the full otherworld
  # receiver, portal hardware/energy, background planes and shaders.
  "moon","otherworld","wormhole","protected-bird","bird":return false
 return false

static func route_error(route:Dictionary) -> String:
 var groups:Dictionary={}
 if not _collect_markers(route,groups,0):return "航线记录过于复杂，原进度已保留。"
 for group in ["moon","protected-bird","otherworld","meteor"]:
  if groups.has(group) and not group_available(group):
   var labels:Dictionary={"moon":"月球","otherworld":"虫洞与苔光","protected-bird":"保护鸟","meteor":"流星"}
   return "%s航线画面仍在恢复中，暂时无法出发。原进度已保留。"%labels[group]
 # Resource readiness alone cannot turn a partial meteor hazard into an
 # ordinary route. Complete content validation remains in the economy/model.
 if groups.has("meteor") and (route.get("route_profile")!="orbital-meteor-v1" or not route.get("orbital_event") is Dictionary):
  return "流星航线记录不完整，原进度已保留。"
 return ""

static func _collect_markers(value:Variant,groups:Dictionary,depth:int) -> bool:
 # Test keys, not their truthiness: null/false/incomplete special records must
 # not fall through into ordinary v3 scenery. Do not guess from display names.
 if depth>16:return false
 if value is Dictionary:
  for raw_key in value:
   var key:String=str(raw_key)
   var child:Variant=value[raw_key]
   if key=="moon" or key.begins_with("moon_"):groups.moon=true
   if key=="wormhole" or key.begins_with("wormhole_") or key=="otherworld" or key.begins_with("otherworld_"):groups.otherworld=true
   if key=="ecology" or key.begins_with("ecology_") or key=="protected_bird" or key.begins_with("protected_bird_"):groups["protected-bird"]=true;groups.otherworld=true
   if key=="orbital_event" or key.begins_with("orbital_event_") or key.begins_with("meteor_"):groups.meteor=true
   if child is String:
    if key in ["route_profile","destination_id"] and child.begins_with("moon-"):groups.moon=true
    if key=="route_kind" and child=="moon":groups.moon=true
    if (key in ["control_version","pilot_profile"] and child=="pilot-v4-wormhole") or (key=="route_profile" and child=="wormhole-otherworld-v1") or (key=="route_kind" and child=="wormhole"):groups.otherworld=true
    if (key in ["control_version","pilot_profile"] and child=="pilot-v5-protected-bird") or (key=="route_profile" and child=="mosslight-protected-bird-v1") or (key=="version" and child=="protected-bird-offers-v1"):
     groups["protected-bird"]=true;groups.otherworld=true
    if (key=="route_profile" and child=="orbital-meteor-v1") or (key=="version" and child=="orbital-meteor-offers-v1") or (key=="kind" and child=="moving_meteor"):groups.meteor=true
   if child is Dictionary or child is Array:
    if not _collect_markers(child,groups,depth+1):return false
 elif value is Array:
  for child in value:
   if child is Dictionary or child is Array:
    if not _collect_markers(child,groups,depth+1):return false
 return true

static func _meteor_receipt_ready(root:String,require_import:bool) -> bool:
 # Hash pins refer to newly reconstructed and measured resources, never to
 # historical bytes. The pinned manifest closes anchors, dimensions, alpha
 # spans and occupied radii for exactly three registered sprites.
 var manifest_path:String=root+"manifest.json"
 if not FileAccess.file_exists(manifest_path) or FileAccess.get_sha256(manifest_path)!=METEOR_MANIFEST_SHA:return false
 var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
 if not raw is Dictionary or raw.get("schema")!=1 or not raw.get("assets") is Array or raw.assets.size()!=3:return false
 var seen:Dictionary={}
 for record in raw.assets:
  if not record is Dictionary or not record.get("name") is String:return false
  var name:String=record.name
  if not METEOR_SPRITES.has(name) or seen.has(name):return false
  seen[name]=true
  var expected:Dictionary=METEOR_SPRITES[name]
  if record.get("runtime")!="assets/2d_v5/events/meteor/"+name+".png" or record.get("runtime_sha256")!=expected.sha256:return false
  if not _numeric_pair_is(record.get("dimensions"),float(expected.size),float(expected.size)) or not _numeric_pair_is(record.get("anchor_px"),float(expected.anchor),float(expected.anchor)):return false
  if not record.get("silhouette_runs") is Array or record.silhouette_runs.is_empty():return false
  if not (record.get("occupied_circumradius_px") is float or record.get("occupied_circumradius_px") is int) or float(record.occupied_circumradius_px)<=0.0:return false
  var path:String=root+name+".png"
  if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=expected.sha256:return false
  if require_import:
   if not ResourceLoader.exists(path,"Texture2D"):return false
   var texture:Texture2D=ResourceLoader.load(path,"Texture2D") as Texture2D
   if texture==null or texture.get_width()!=expected.size or texture.get_height()!=expected.size:return false
 return seen.size()==3

static func _numeric_pair_is(value:Variant,x:float,y:float) -> bool:
 # JSON numbers are floats; array equality would falsely reject the receipt's
 # integer dimensions. Validate types/values without truncation or coercion.
 if not value is Array or value.size()!=2:return false
 for number in value:
  if not (number is float or number is int) or not is_finite(float(number)):return false
 return float(value[0])==x and float(value[1])==y
