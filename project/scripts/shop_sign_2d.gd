extends Sprite2D
## Original station name mounted on a taller blank plaque.
## Original supports and lamp pixels are reused; all source images stay intact.
const SIGN_TEXTURE:Texture2D=preload("res://assets/2d_v5/shop-sign/hanging-sign-pixel.png")
const PLAQUE_TEXTURE:Texture2D=preload("res://source_art/2d_v5/shop-sign/blank-plaque-original-v2.png")
const WORDMARK_TEXTURE:Texture2D=preload("res://assets/2d_v5/title/star-courier-sign-pixel-v2.png")
const WORLD_TOP_LEFT:Vector2=Vector2(4,46)
const SUPPORT_ANCHORS:Array[Vector2]=[Vector2(111.552941,10.603529),Vector2(324.242353,10.603529)]
# Conservative composition envelope. CPU alpha128: Rect2(24,4,386,171).
# One guard pixel permits renderer sampling differences.
const OPAQUE_BOUNDS:Rect2=Rect2(23,3,389,174)
const MOUNTING_BEAM:Rect2=Rect2(92,36,296,25)
const PLAQUE_REGION:Rect2=Rect2(40,24,2080,656)
const PLAQUE_POSITION:Vector2=Vector2(23,54)
const PLAQUE_SCALE:float=0.1875
const WORDMARK_POSITION:Vector2=Vector2(146,76)
const WORDMARK_SCALE:float=1.0
# Transparent native-pixel wordmark; no concept-sheet paper or screenshot notch.
const WORDMARK_REGION:Rect2=Rect2(0,0,144,80)

func _init() -> void:
 name="GeneratedHangingShopSign"
 texture=SIGN_TEXTURE
 centered=false
 region_enabled=true
 region_rect=Rect2(0,0,436,54)
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 position=WORLD_TOP_LEFT
 z_index=1
 set_meta("art_id","shop-sign/pixel-station-wordmark-v2")
 set_meta("source_manifest","res://source_art/2d_v5/shop-sign/station-wordmark-registration.json")
 _add_atlas("BlankTallerPlaque",PLAQUE_TEXTURE,PLAQUE_REGION,PLAQUE_POSITION,PLAQUE_SCALE)
 # Restore the original suspension bases over the new upper frame.
 _add_atlas("LeftOriginalSupportBase",SIGN_TEXTURE,Rect2(96,36,28,28),Vector2(96,36))
 _add_atlas("RightOriginalSupportBase",SIGN_TEXTURE,Rect2(310,36,28,28),Vector2(310,36))
 # Four original cyan modules at native scale, registered to the taller frame.
 _add_atlas("TopOriginalLamp",SIGN_TEXTURE,Rect2(202,58,32,12),Vector2(202,62))
 _add_atlas("BottomOriginalLamp",SIGN_TEXTURE,Rect2(202,116,32,12),Vector2(202,160))
 _add_atlas("LeftOriginalLamp",SIGN_TEXTURE,Rect2(50,82,14,20),Vector2(30,104))
 _add_atlas("RightOriginalLamp",SIGN_TEXTURE,Rect2(372,82,14,20),Vector2(392,104))
 _add_atlas("PixelStationWordmark",WORDMARK_TEXTURE,WORDMARK_REGION,WORDMARK_POSITION,WORDMARK_SCALE)

func _add_atlas(node_name:String,source:Texture2D,source_region:Rect2,at:Vector2,uniform_scale:float=1.0) -> Sprite2D:
 var atlas:AtlasTexture=AtlasTexture.new()
 atlas.atlas=source
 atlas.region=source_region
 atlas.filter_clip=true
 var sprite:Sprite2D=Sprite2D.new()
 sprite.name=node_name
 sprite.texture=atlas
 sprite.centered=false
 sprite.position=at
 sprite.scale=Vector2.ONE*uniform_scale
 sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 add_child(sprite)
 return sprite

func opaque_world_rect() -> Rect2:
 return global_transform*OPAQUE_BOUNDS

func support_anchors_world() -> Array[Vector2]:
 var result:Array[Vector2]=[]
 for anchor in SUPPORT_ANCHORS:result.append(to_global(anchor))
 return result
