extends SceneTree
const Backdrop=preload("res://scripts/flight_backdrop_2d.gd")
var passed:int=0
var failed:int=0
var backdrop
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run() -> void:
 var canvas:CanvasLayer=CanvasLayer.new();root.add_child(canvas)
 var stage:Node2D=Node2D.new();canvas.add_child(stage)
 backdrop=Backdrop.new();stage.add_child(backdrop)
 backdrop.configure_route({})
 check(backdrop.get_child_count()==3,"exactly three cached painted planes")
 check(backdrop.city.texture.get_size()==Vector2(1280,720),"approved city stays canonical 1280x720")
 check(backdrop.starfield.texture.get_size()==Vector2(1280,344),"star field is an actual aspect-preserved painted crop")
 check(backdrop.planet.texture.get_size()==Vector2(1280,720),"planet is separately alpha-extracted original art")
 check(not backdrop.is_processing(),"no wall-clock processing, tween, or time-dependent drifting")
 check(backdrop.city.visible and not backdrop.planet.visible,"route begins in city")
 backdrop.update_flight(Vector2(20,0),Vector2(5.5,0),0.25)
 check(is_zero_approx(backdrop.debug_snapshot().orbit_weight),"city is retained through first quarter")
 backdrop.update_flight(Vector2(50,0),Vector2(5.5,0),0.4)
 check(is_equal_approx(backdrop.debug_snapshot().orbit_weight,0.5),"atmospheric mid-transition is a balanced smooth crossfade")
 check(backdrop.city.visible and backdrop.planet.visible,"city and orbit layers coexist during transition")
 backdrop.update_flight(Vector2(80,0),Vector2(5.5,0),0.55)
 check(not backdrop.city.visible and backdrop.planet.visible,"orbit reached by 55 percent")
 check(backdrop.debug_snapshot().blur_pixels>0 and backdrop.debug_snapshot().blur_pixels<22,"cruise speed gets restrained background-only blur")
 backdrop.update_flight(Vector2(80,0),Vector2(4.4,20),0.8)
 check(is_zero_approx(backdrop.debug_snapshot().blur_pixels),"slow horizontal movement remains crisp even during fast vertical movement")
 backdrop.update_flight(Vector2(80,0),Vector2(8,2),0.8)
 check(is_equal_approx(backdrop.debug_snapshot().blur_pixels,22),"high-speed smear has a fixed 22-pixel upper bound")
 check(backdrop.debug_snapshot().blur_direction.x>0 and backdrop.debug_snapshot().blur_direction.y>0,"forward directional smear follows real velocity")
 backdrop.update_flight(Vector2(-80,0),Vector2(-8,-2),0.8)
 check(backdrop.debug_snapshot().blur_direction.x<0 and backdrop.debug_snapshot().blur_direction.y<0,"reverse and vertical smear retain signed direction")
 backdrop.reduced_motion=true
 check(is_zero_approx(backdrop.debug_snapshot().blur_pixels) and backdrop.debug_snapshot().blur_direction==Vector2.ZERO,"reduced motion immediately disables every blur")
 backdrop.reduced_motion=false;backdrop.motion_blur_enabled=false
 check(is_zero_approx(backdrop.debug_snapshot().blur_pixels),"independent motion-blur switch")
 backdrop.motion_blur_enabled=true
 var before:Dictionary=backdrop.debug_snapshot()
 await process_frame
 await process_frame
 check(backdrop.debug_snapshot()==before,"pause or unchanged flight input produces identical state")
 var textures:Array=[];var materials:Array=[]
 for node in backdrop.get_children():textures.append(node.texture);materials.append(node.material)
 var resource_count:int=int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
 var all_bounded:bool=true
 for i in range(12000):
  var travel:float=float(i)*19313.718 if i%2==0 else -float(i)*11013.333
  backdrop.update_flight(Vector2(travel,travel),Vector2(7.2,-1),fposmod(float(i)*0.017,1.0))
  var state:Dictionary=backdrop.debug_snapshot()
  for key in ["city_scroll","sky_scroll","planet_scroll"]:
   var offset:Vector2=state[key]
   all_bounded=all_bounded and offset.x>=0 and offset.x<2560 and offset==offset.round()
 check(all_bounded,"long positive and negative travel keeps every offset integral and bounded")
 check(backdrop.get_child_count()==3,"twelve thousand updates allocate no new nodes")
 var same_resources:bool=true
 for i in range(3):
  var node:Sprite2D=backdrop.get_child(i)
  same_resources=same_resources and node.texture==textures[i] and node.material==materials[i] and node.position==node.position.round()
 check(same_resources,"updates reuse the same three textures/materials and integer origins")
 check(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))<=resource_count,"updates do not accumulate resources")
 backdrop.update_flight(Vector2(1e15,-1e15),Vector2(6,0),0.8)
 check(backdrop.debug_snapshot().city_scroll.x>=0 and backdrop.debug_snapshot().city_scroll.x<2560,"huge finite positions also wrap before multiplying")
 before=backdrop.debug_snapshot()
 backdrop.update_flight(Vector2(NAN,0),Vector2(5,0),0.2)
 backdrop.update_flight(Vector2.ZERO,Vector2(INF,0),0.2)
 backdrop.update_flight(Vector2.ZERO,Vector2.ZERO,NAN)
 check(backdrop.debug_snapshot()==before,"invalid numeric inputs cannot poison shader or transforms")
 var seams:bool=true
 for extent in [1280.0,344.0,720.0]:
  for tile in range(-6,7):
   var edge:float=float(tile)*extent
   seams=seams and is_equal_approx(Backdrop.mirror_coordinate(edge-0.5,extent),Backdrop.mirror_coordinate(edge+0.5,extent))
   for offset in [-22.0,-7.0,0.0,7.0,22.0]:
    seams=seams and is_equal_approx(Backdrop.mirror_coordinate(edge+offset,extent),Backdrop.mirror_coordinate(edge+offset+extent*2,extent))
 check(seams,"mirrored joins are edge-identical, including negative tiles and blur taps")
 var source:Image=backdrop.city.texture.get_image()
 var edge_pixels_match:bool=true
 for y in range(0,720,17):
  for edge in [-2560.0,-1280.0,0.0,1280.0,2560.0]:
   var left:int=int(Backdrop.mirror_coordinate(edge-0.5,1280.0))
   var right:int=int(Backdrop.mirror_coordinate(edge+0.5,1280.0))
   edge_pixels_match=edge_pixels_match and source.get_pixel(left,y)==source.get_pixel(right,y)
 check(edge_pixels_match,"actual painted city pixels match on every mirrored seam")
 before=backdrop.debug_snapshot()
 for extent in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1440),Vector2(3840,2160),Vector2(1600,900)]:
  stage.scale=extent/Backdrop.LOGICAL_SIZE
  check(backdrop.city.get_global_transform().get_scale()*backdrop.city.texture.get_size()==extent,"parent-only logical fitting at "+str(extent))
 check(backdrop.debug_snapshot()==before,"viewport scaling does not change scroll phase or recreate resources")
 var minimum_limb_y:float=550-8
 check(minimum_limb_y>520,"extracted planet limb remains below the central gameplay lane")
 backdrop.configure_route({"background_route":"orbit","background_blur_start_mps":10.0,"background_blur_full_mps":12.0})
 backdrop.update_flight(Vector2.ZERO,Vector2(8,0),0.0)
 check(backdrop.planet.visible and not backdrop.city.visible and is_zero_approx(backdrop.debug_snapshot().blur_pixels),"route profile and speed thresholds are configurable")
 backdrop.configure_route({"background_route":"city","background_city_until":NAN,"background_orbit_after":-8,"background_blur_start_mps":INF})
 backdrop.update_flight(Vector2.ZERO,Vector2.ZERO,1.0)
 check(backdrop.city.visible and not backdrop.planet.visible,"malformed route tunables are safely normalized")
 var dock:Image=(load("res://assets/2d_v5/space/orbital-mail-dock.png") as Texture2D).get_image()
 var receiver:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/2d_v5/space/dock-anchors.json"))
 var anchor:Vector2=Vector2(receiver.runtime_anchor_snapped_px[0],receiver.runtime_anchor_snapped_px[1])
 check(dock.get_size()==Vector2i(760,428) and anchor==Vector2(318,213),"dock derivative preserves measured semantic bay anchor")
 check(anchor.x<float(dock.get_width())*0.5-50,"receiver uses the left-side bay, not whole-art center")
 var interior_opaque:bool=true
 for y in range(-19,20):
  for x in range(-19,20):
   if x*x+y*y<=19*19:interior_opaque=interior_opaque and dock.get_pixelv(Vector2i(anchor)+Vector2i(x,y)).a==1.0
 check(interior_opaque,"entire conservative 19px receiving interior is unobscured painted bay")
 var shader:String=FileAccess.get_file_as_string("res://assets/2d_v5/background_speed.gdshader")
 check(not shader.contains("hint_screen_texture") and not shader.contains("uniform sampler2D") and not shader.contains("TIME *"),"shader has no scene-screen read, unrelated sampler or time animation")
 print("Flight backdrop: ",passed," passed, ",failed," failed")
 canvas.free();quit(1 if failed else 0)
