extends RefCounted
## This independent receipt opens only the new ordinary mosslight route.
## Legacy otherworld/wormhole capabilities stay closed. Source alpha-1 matte
## residue is disclosed below; no image bytes are altered by this receipt.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const FAR:String="res://assets/2d_v5/mosslight/far-garden-wrap.png"
const ISLANDS:String="res://assets/2d_v5/mosslight/decorative-island-band.png"
const RECEIVER:String="res://assets/2d_v5/mosslight/receiver-greenhouse.png"
const SHADER:String="res://assets/2d_v5/mosslight/mosslight_background.gdshader"
const SHADER_SHA:String="67e274a2d177d9cb623f21878f6fb25a3dcec391d9db31bcc9874312f5400ad1"
const RECEIVER_ALPHA_CUTOFF:float=1.0/255.0
# Bounding box of source pixels with alpha >= 2/255. Source alpha-1 residue
# stays in the unchanged PNG and is removed only by registered_cutout.
const RECEIVER_VISIBLE_BOUNDS:Rect2i=Rect2i(13,788,1228,356)
const ART:Dictionary={
 FAR:{"sha":"37e19d3d1d1027c0146e4dff98a470d7580361db7d8fb2295f757f9770257328","size":Vector2i(1672,941)},
 ISLANDS:{"sha":"b0b0119ae638291f0c2d62d55adca9009c9995e790c9b21a538e6253f4586e66","size":Vector2i(1672,940)},
 RECEIVER:{"sha":"0ffe52151a86cd47b27059d6652d17ceed8090f2167214bbe612463b563b77e8","size":Vector2i(1254,1254)},
 "res://assets/2d_v5/flight/rock-1.png":{"sha":"795c9de6c637ab59083e0a51f38b1e877cd4e4f8679580712a2b66e2e0394e01","size":Vector2i(144,160)},
 "res://assets/2d_v5/flight/rock-2.png":{"sha":"e2d4b611b18040a00924172d61a152dfe452f6d7c61d8ec0fbee64cc5d9eaa26","size":Vector2i(115,160)}
}

static func route_error(route:Dictionary) -> String:
 if not Content.has_markers(route):return ""
 var invalid:String=Content.validation_error(route)
 if not invalid.is_empty():return invalid
 if route.get("control_version")!=Content.CONTROL_VERSION:return "苔光温室需要对应的双向驾驶记录。"
 return art_error()

static func art_error(require_import:bool=true) -> String:
 if SHADER_SHA.length()!=64 or not FileAccess.file_exists(SHADER) or FileAccess.get_sha256(SHADER)!=SHADER_SHA:return "苔光温室场景效果尚未完成验证，原进度已保留。"
 return registered_art_error(ART,require_import)

static func registered_art_error(records:Dictionary,require_import:bool=true) -> String:
 # Deliberately no fallback raster. The supplied manifest can only verify the
 # fixed known keys, making negative receipts testable without changing files.
 if records.size()!=ART.size():return "苔光温室资源记录不完整，原进度已保留。"
 for path in ART:
  if not records.has(path) or not records[path] is Dictionary:return "苔光温室资源记录不完整，原进度已保留。"
  var item:Dictionary=records[path]
  if not item.get("sha") is String or item.sha.length()!=64 or not item.get("size") is Vector2i:return "苔光温室资源记录不完整，原进度已保留。"
  if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=item.sha:return "苔光温室资源记录不完整，原进度已保留。"
  if require_import and not _texture_matches(path,item.size):return "苔光温室资源尚未导入，原进度已保留。"
 if require_import and not ResourceLoader.exists(SHADER,"Shader"):return "苔光温室场景效果尚未导入，原进度已保留。"
 return ""

static func _texture_matches(path:String,size:Vector2i) -> bool:
 if size.x<=0 or size.y<=0 or not ResourceLoader.exists(path,"Texture2D"):return false
 var texture:Texture2D=ResourceLoader.load(path,"Texture2D") as Texture2D
 return texture!=null and texture.get_width()==size.x and texture.get_height()==size.y
