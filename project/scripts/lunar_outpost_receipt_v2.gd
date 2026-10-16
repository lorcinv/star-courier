extends RefCounted
## Fail-closed receipt for this new slice only. No legacy recovery cap is changed.
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const SKY:String="res://assets/2d_v5/moon/far-sky-clamped.png"
const REGOLITH:String="res://assets/2d_v5/moon/regolith-decorative-wrap.png"
const SHADER:String="res://assets/2d_v5/moon/moon_background.gdshader"
const SHADER_SHA:String="5b53b57650f2737e6c1d56e626b29ec63b367a21df523aa5bc86413f77530379"
const EXISTING:Dictionary={
 SKY:{"sha":"a7556349c5c61047bd5e96ce1b25681057555b9fa399f22678441ac51215fed9","size":Vector2i(1536,864)},
 REGOLITH:{"sha":"32b046c05035b4c8882841518c8567ba3b5b75fa651dc7b549240ffed1951888","size":Vector2i(1280,720)},
 "res://assets/2d_v5/flight/receiver.png":{"sha":"8b9303bb183d412e8f601da83f4a199d25bcfb36c5751d6e13ea26a6c0a481f0","size":Vector2i(279,220)},
 "res://assets/2d_v5/flight/rock-1.png":{"sha":"795c9de6c637ab59083e0a51f38b1e877cd4e4f8679580712a2b66e2e0394e01","size":Vector2i(144,160)},
 "res://assets/2d_v5/flight/rock-2.png":{"sha":"e2d4b611b18040a00924172d61a152dfe452f6d7c61d8ec0fbee64cc5d9eaa26","size":Vector2i(115,160)}
}

static func route_error(route:Dictionary) -> String:
 if not Content.has_markers(route):return ""
 var invalid:String=Content.validation_error(route)
 if not invalid.is_empty():return invalid
 if route.get("control_version")!=Content.CONTROL_VERSION:return "月面前哨需要对应的双向驾驶记录。"
 return art_error()

static func art_error(require_import:bool=true) -> String:
 if not FileAccess.file_exists(SHADER) or FileAccess.get_sha256(SHADER)!=SHADER_SHA:return "月面前哨场景效果尚未完成验证，原进度已保留。"
 for path in EXISTING:
  var item:Dictionary=EXISTING[path]
  if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=item.sha:return "月面前哨资源记录不完整，原进度已保留。"
  if require_import and not _texture_matches(path,item.size):return "月面前哨资源尚未导入，原进度已保留。"
 if require_import and not ResourceLoader.exists(SHADER,"Shader"):return "月面前哨场景效果尚未导入，原进度已保留。"
 return ""

static func _texture_matches(path:String,size:Vector2i) -> bool:
 if not ResourceLoader.exists(path,"Texture2D"):return false
 var texture:Texture2D=ResourceLoader.load(path,"Texture2D") as Texture2D
 return texture!=null and texture.get_width()==size.x and texture.get_height()==size.y
