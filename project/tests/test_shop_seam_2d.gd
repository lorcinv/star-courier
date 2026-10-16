extends SceneTree
## Focused runtime registration check. Authored here, reserved for lead's engine.
const Seam=preload("res://scripts/shop_seam_2d.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
var checks:int=0

func require(value:bool,label:String) -> void:
 checks+=1
 assert(value,label)
 print("PASS ",label)

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 var shop:=Sprite2D.new();shop.texture=load("res://assets/2d_v5/environment/shop-shell.png")
 shop.position=Vector2(640,360);root.add_child(shop)
 var bay:=Sprite2D.new();bay.centered=false;root.add_child(bay)
 var seam=Seam.new();root.add_child(seam)
 var shop_texture:Texture2D=shop.texture
 var shop_id:int=shop.get_instance_id();var bay_id:int=bay.get_instance_id()
 for tier in [0,1,1,2,2,0,1,0]:
  if tier>0:
   bay.texture=load("res://assets/2d_v5/workshop-support/right-bay-tier%d-floor-reconstructed.png"%tier)
   bay.position=Profile.bay_top_left(tier);bay.show()
  else:bay.texture=null;bay.hide()
  var bay_texture:Texture2D=bay.texture;var bay_position:Vector2=bay.position
  seam.configure(tier,shop,bay)
  var state:Dictionary=seam.debug_snapshot()
  require(state.tier==tier and state.visible==(tier>0),"tier %d local patch visibility"%tier)
  require(shop.texture==shop_texture and shop.position==Vector2(640,360) and shop.scale==Vector2.ONE,"original shop registration unchanged")
  require(bay.texture==bay_texture and bay.position==bay_position and bay.scale==Vector2.ONE and bay.visible==(tier>0),"bay texture, position, scale and visibility unchanged")
  require(shop.get_instance_id()==shop_id and bay.get_instance_id()==bay_id,"original node identities survive repeated transitions")
  if tier==0:
   require(shop.material==null and bay.material==null,"tier0 restores uncut original artwork")
  else:
   require(shop.material is ShaderMaterial and bay.material is ShaderMaterial,"both overlapped sources use a local cutout")
   require(state.world_rect==Seam.RECTS[tier] and state.scale==Vector2.ONE,"native-size repair at registered world rectangle")
   var rect:Rect2=Seam.RECTS[tier]
   require(shop.material.get_shader_parameter("source_cutout_px")==Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y),"shell cutout is exact source pixels")
   var local:Rect2=Rect2(rect.position-bay.position,rect.size)
   require(bay.material.get_shader_parameter("source_cutout_px")==Vector4(local.position.x,local.position.y,local.end.x,local.end.y),"bay cutout compensates its existing tier anchor")
 require(Profile.FLOOR_Y==486.0,"ground level remains y486")
 print("SHOP_SEAM_REGISTRATION_PASS ",checks)
 quit(0)
