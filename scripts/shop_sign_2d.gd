extends Sprite2D
## The shop's generated hanging emblem, mounted once to its original upper beam.
## Fixed world-space art: no camera compensation, animation or tier-specific copy.
const SIGN_TEXTURE:Texture2D=preload("res://assets/2d_v5/shop-sign/hanging-sign-pixel.png")
const WORLD_TOP_LEFT:Vector2=Vector2(4,46)
const SUPPORT_ANCHORS:Array[Vector2]=[Vector2(97.6,7.6),Vector2(338.4,7.6)]
# Exact alpha>=128 bounds from the padded, uniform nearest-sampled derivative.
const OPAQUE_BOUNDS:Rect2=Rect2(44,4,348,136)
const MOUNTING_BEAM:Rect2=Rect2(92,36,296,25)

func _init() -> void:
 name="GeneratedHangingShopSign"
 texture=SIGN_TEXTURE
 centered=false
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 position=WORLD_TOP_LEFT
 z_index=1
 set_meta("art_id","shop-sign/hanging-sign-pixel")
 set_meta("source_manifest","res://source_art/2d_v5/shop-sign/manifest.json")

func opaque_world_rect() -> Rect2:
 return global_transform*OPAQUE_BOUNDS

func support_anchors_world() -> Array[Vector2]:
 var result:Array[Vector2]=[]
 for anchor in SUPPORT_ANCHORS:result.append(to_global(anchor))
 return result
