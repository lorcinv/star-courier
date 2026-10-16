extends Node2D
## Local imagegen repair of the old-shop / expanded-bay entrance join.
## Presentation only: never changes tier geometry, floor, actors or saves.
const Cutout=preload("res://assets/2d_v5/workshop-seam/registered_cutout.gdshader")
const PATCH_PATH:String="res://assets/2d_v5/workshop-seam/entrance-tier%d.png"
const RECTS:Array[Rect2]=[Rect2(),Rect2(1008,340,280,380),Rect2(1008,340,320,380)]
var _patch:Sprite2D
var _bound:bool=false
var _shop_material:Material
var _bay_material:Material
var _tier:int=0

func _init() -> void:
 _patch=Sprite2D.new();_patch.name="RegisteredEntranceRepair";_patch.centered=false
 _patch.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(_patch);_patch.hide()

func configure(tier:int,shop:Sprite2D,bay:Sprite2D) -> void:
 if shop==null or bay==null:return
 if not _bound:
  _shop_material=shop.material;_bay_material=bay.material;_bound=true
 shop.material=_shop_material;bay.material=_bay_material;_patch.hide();_tier=0
 if tier<1 or tier>2:return
 var replacement:Texture2D=load(PATCH_PATH%tier) as Texture2D
 if replacement==null:return
 var rect:Rect2=RECTS[tier]
 if Vector2(replacement.get_size())!=rect.size:
  push_error("Registered shop entrance repair has unexpected dimensions");return
 # Both existing sprites retain their original visible flag, position, scale,
 # texture, dimensions and instance identity. Their source alpha is cut locally.
 shop.material=_material_for(rect)
 bay.material=_material_for(Rect2(rect.position-bay.position,rect.size))
 _patch.texture=replacement;_patch.position=rect.position;_patch.scale=Vector2.ONE
 _patch.show();_tier=tier

func _material_for(rect:Rect2) -> ShaderMaterial:
 var material:=ShaderMaterial.new();material.shader=Cutout
 material.set_shader_parameter("source_cutout_px",Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y))
 return material

func debug_snapshot() -> Dictionary:
 return {"tier":_tier,"visible":_patch.visible,"world_rect":RECTS[_tier],"scale":_patch.scale}
