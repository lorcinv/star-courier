extends SceneTree
## Asset and scene-geometry gates only. A real rendered composition review is
## still required in hub, counter close-up, and both expanded-bay contexts.
const Sign=preload("res://scripts/shop_sign_2d.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const SOURCE_SHA:String="7e353c979455fbb106c7325332cdb6362090c00000cddedb3e840c9b820dca16"
const DERIVATIVE_SHA:String="2a62905044f71182c4e3c03fa0e4cc645e4621211aaa41b631206158903506b0"
var passed:int=0
var failed:int=0
var viewport:SubViewport
var world
var sign:Sprite2D

func _initialize() -> void:run.call_deferred()

func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func sprite_world_rect(sprite:Sprite2D) -> Rect2:
 return sprite.global_transform*sprite.get_rect()

func count_signs(node:Node) -> int:
 var count:int=1 if node.get_script()==Sign else 0
 for child in node.get_children():count+=count_signs(child)
 return count

func asset_checks() -> void:
 var image:Image=Image.new()
 var error:Error=image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/2d_v5/shop-sign/hanging-sign-pixel.png"))
 check(error==OK and image.get_size()==Vector2i(436,148),"sign keeps its padded native 436x148 canvas")
 check(FileAccess.get_sha256("res://source_art/2d_v5/shop-sign/hanging-sign-original.png")==SOURCE_SHA,"generated original is preserved byte-for-byte")
 check(FileAccess.get_sha256("res://assets/2d_v5/shop-sign/hanging-sign-pixel.png")==DERIVATIVE_SHA,"runtime derivative matches recorded provenance")
 var palette:Dictionary={}
 var palette_data=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/pixel_pipeline_studies/palette_96.json"))
 for entry in palette_data.colors:palette[Color(str(entry)).to_rgba32()]=true
 var binary:bool=true;var palette_ok:bool=true;var grid_ok:bool=true;var rgb_zero:bool=true
 var left:int=image.get_width();var right:int=0;var top:int=image.get_height();var bottom:int=0
 for y in image.get_height():
  for x in image.get_width():
   var color:Color=image.get_pixel(x,y)
   binary=binary and color.a in [0.0,1.0]
   if color.a>0:
    palette_ok=palette_ok and palette.has(color.to_rgba32())
    left=mini(left,x);right=maxi(right,x+1);top=mini(top,y);bottom=maxi(bottom,y+1)
   else:rgb_zero=rgb_zero and color.r==0.0 and color.g==0.0 and color.b==0.0
   grid_ok=grid_ok and color==image.get_pixel(x-x%2,y-y%2)
 check(binary and rgb_zero,"derivative has binary alpha and zero transparent RGB")
 check(palette_ok and grid_ok,"every opaque pixel is shared96 palette and every 2x2 texel block is constant")
 check(Rect2(left,top,right-left,bottom-top)==Sign.OPAQUE_BOUNDS,"runtime opaque bounds exactly match the measured geometry")
 var clear_border:bool=true
 for x in image.get_width():clear_border=clear_border and image.get_pixel(x,0).a==0.0 and image.get_pixel(x,image.get_height()-1).a==0.0
 check(clear_border,"transparent top and bottom guard rows preserve the full hanging hardware")

func geometry_checks() -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 sign=world.find_child("GeneratedHangingShopSign",true,false) as Sprite2D
 check(sign!=null and sign.get_script()==Sign,"world mounts the dedicated generated shop emblem")
 if sign==null:return
 check(sign.get_parent()==world.workshop_root and not sign.is_set_as_top_level(),"sign is fixed to the original shop world layer, not the camera, HUD or an actor")
 check(sign.texture==Sign.SIGN_TEXTURE and sign.centered==false and sign.scale==Vector2.ONE and sign.position==Sign.WORLD_TOP_LEFT,"one cached Sprite2D uses native art without stretch, recrop or mirror")
 check(not sign.flip_h and not sign.flip_v and sign.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"sign retains original orientation and nearest filtering")
 check(sign.get_child_count()==0 and not sign.is_processing() and not sign.is_physics_processing(),"sign has no per-frame work, material creation or extra node tree")
 check(sign.z_index==1 and sign.z_index<world.actors_root.z_index and sign.z_index<world.ship_root.z_index and sign.z_index<world.foreground_root.z_index,"shop sign is above the shell and behind actors, assembly and foreground framing")
 var anchors:Array[Vector2]=sign.support_anchors_world()
 check(anchors.size()==2 and anchors[0].is_equal_approx(Vector2(101.6,53.6)) and anchors[1].is_equal_approx(Vector2(342.4,53.6)),"both measured source mounting plates map to their true world-space anchors")
 check(Sign.MOUNTING_BEAM.has_point(anchors[0]) and Sign.MOUNTING_BEAM.has_point(anchors[1]),"both support plates sit inside the original upper shop beam")
 var original_transform:Transform2D=sign.global_transform
 var original_id:int=sign.get_instance_id();var original_texture:Texture2D=sign.texture
 var envelope:Rect2=sign.opaque_world_rect()
 check(envelope==Rect2(48,50,348,136) and envelope.end.y<=186,"large plaque stays inside the original shop's roof region")
 check(not envelope.intersects(sprite_world_rect(world.clerk)) and envelope.end.y<266,"sign clears the clerk sprite and a conservative y266 actor-head line")
 for appearance in ["human_courier","elf_archivist","alien_botanist","robot_machinist"]:
  var order_id:String="sign/"+appearance
  world.update_shop_state({"contracts":[{"contract_id":order_id,"status":"available","appearance_id":appearance,"appearance_seed":7,"accessory_id":"none"}],"active_contract_id":""})
  var customer:Sprite2D=world.customers[order_id].node
  customer.position=Vector2(148,488)
  check(not envelope.intersects(sprite_world_rect(customer)),"plaque clears the whole customer sprite: "+appearance)
 world.update_shop_state({"contracts":[],"active_contract_id":""})
 world.show_design(Profile.starter_design())
 for tier in 3:
  world.set_workshop_tier(tier)
  check(not envelope.intersects(world.workshop_grid_rect()),"tier %d full editable assembly footprint clears the opaque sign"%tier)
  var craft_clear:bool=true
  for child in world.ship_root.get_children():
   if child is Sprite2D and child.has_meta("part_id"):craft_clear=craft_clear and not envelope.intersects(sprite_world_rect(child))
  check(craft_clear and not envelope.intersects(sprite_world_rect(world.parcel)),"tier %d assembly modules and parcel do not meet the sign"%tier)
  check(not envelope.intersects(sprite_world_rect(world.shop_cradle)),"tier %d sign remains clear of the departure pad"%tier)
  for context in ["hub","contracts","workshop","supply"]:
   world.focus(context,true)
   viewport.get_camera_2d().force_update_scroll()
   var canvas:Transform2D=viewport.get_canvas_transform()
   check(sign.global_transform==original_transform and sign.get_instance_id()==original_id and sign.texture==original_texture,"tier %d %s camera reuses the unmoved world sign"%[tier,context])
   var screen_anchor:Vector2=canvas*anchors[0]
   check((canvas.affine_inverse()*screen_anchor).distance_to(anchors[0])<.001,"tier %d %s camera round-trip retains physical support registration"%[tier,context])
   if context=="hub":check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(canvas*envelope),"tier %d hub camera includes the complete hanging sign geometry"%tier)
   if context=="contracts":
    # The camera may crop the upper brackets. The opaque plaque itself begins
    # near local y62; its complete face remains above every character head.
    var plaque:Rect2=Rect2(48,108,348,78)
    check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(canvas*plaque),"tier %d counter camera keeps the complete plaque face in view"%tier)
  for repeat in 12:world.set_workshop_tier(tier);world.show_design(Profile.starter_design());world.focus("hub",true)
  check(count_signs(world)==1 and sign.get_instance_id()==original_id,"tier %d repeated expansion/render paths never duplicate the shop emblem"%tier)
 world.set_workshop_tier(0)
 var sim=Sim.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),Ground.route(),3)
 world.start_flight(sim)
 check(sign.global_transform==original_transform and sign.get_parent()==world.workshop_root and count_signs(world)==1,"dispatch leaves the sign on the physical shop instead of carrying it with the camera")
 world.leave_flight()
 check(sign.global_transform==original_transform and sign.texture==original_texture and count_signs(world)==1,"return from dispatch preserves the same single cached sign")

func run() -> void:
 asset_checks()
 geometry_checks()
 if is_instance_valid(viewport):viewport.queue_free()
 await process_frame;await process_frame
 print("SHOP_SIGN_2D_TESTS passed=",passed," failed=",failed,"; rendered composition review remains required")
 quit(1 if failed else 0)
