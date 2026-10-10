extends SceneTree
const Backdrop=preload("res://scripts/ascent_backdrop_2d.gd")
var passed:int=0
var failed:int=0
var backdrop
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same_edges(image:Image,vertical:bool) -> bool:
 var length:int=image.get_width() if vertical else image.get_height()
 for i in range(length):
  if vertical:
   if image.get_pixel(i,0)!=image.get_pixel(i,image.get_height()-1):return false
  elif image.get_pixel(0,i)!=image.get_pixel(image.get_width()-1,i):return false
 return true
func run() -> void:
 var canvas:CanvasLayer=CanvasLayer.new();root.add_child(canvas)
 var stage:Node2D=Node2D.new();canvas.add_child(stage)
 backdrop=Backdrop.new();stage.add_child(backdrop);backdrop.configure_route({})
 check(backdrop.get_child_count()==7,"seven cached independently generated raster layers")
 check(not backdrop.orbit_dust.visible,"near orbit dust stays absent at ground altitude")
 check(not backdrop.is_processing(),"no process clock, tweens, timers or autonomous drift")
 check(backdrop.city.visible and not backdrop.planet.visible,"departure shows a real skyline below clear sky")
 backdrop.update_flight(Vector2(520,0),Vector2(18,0),1.0)
 check(backdrop.debug_snapshot().orbit_weight==0.0 and backdrop.city.visible,"horizontal progress alone never unlocks space")
 backdrop.update_flight(Vector2(0,-110),Vector2(0,-18),0.0)
 check(is_equal_approx(backdrop.debug_snapshot().orbit_weight,0.5),"actual negative Y altitude controls orbit even at zero progress")
 check(backdrop.debug_snapshot().city_scroll.y==-630.0,"climbing physically moves skyline downscreen")
 backdrop.update_flight(Vector2(0,-150),Vector2.ZERO,0.0)
 check(backdrop.orbit_dust.visible and backdrop.orbit_dust.modulate.a<=0.32,"small sparse dust retains parallax in orbit with bounded low opacity")
 check(not backdrop.city.visible and backdrop.planet.visible and not backdrop.clouds.visible,"above clouds: city below viewport and genuine orbital layer visible")
 backdrop.update_flight(Vector2(60,-20),Vector2(20,-10),0.2,Vector2(12,-4))
 var a:Dictionary=backdrop.debug_snapshot()
 check(a.city_scroll==Vector2(48,-100) and a.cloud_scroll==Vector2(96,144),"all parallax follows actual camera center, not cargo displacement")
 backdrop.update_flight(Vector2(80,-40),Vector2(20,-10),0.3,Vector2(12,-4))
 check(backdrop.debug_snapshot().blur_pixels==0.0,"held camera does not smear scenery when cargo moves inside dead-zone")
 backdrop.update_flight(Vector2(100,-60),Vector2(20,-10),0.4,Vector2(12,-24))
 check(backdrop.debug_snapshot().blur_direction.x==0 and backdrop.debug_snapshot().blur_direction.y<0,"camera's vertical-only movement yields vertical-only blur")
 backdrop.update_flight(Vector2(100,-60),Vector2(20,-10),0.4,Vector2(12,-24))
 check(backdrop.debug_snapshot().blur_direction.y<0,"identical quantized camera sample preserves stable motion estimate")
 backdrop.update_flight(Vector2(100,-60),Vector2.ZERO,0.4,Vector2(12,-24))
 check(backdrop.debug_snapshot().blur_pixels==0.0 and backdrop.debug_snapshot().blur_direction==Vector2.ZERO,"explicit zero presentation velocity clears blur immediately for pause")
 backdrop.update_flight(Vector2(90,-45),Vector2(0,-22),0.2)
 check(is_equal_approx(backdrop.debug_snapshot().blur_pixels,24) and backdrop.debug_snapshot().blur_direction==Vector2(0,-24),"pure ascent gets bounded 2D directional blur")
 backdrop.update_flight(Vector2(-90,45),Vector2(-22,12),0.2)
 check(backdrop.debug_snapshot().blur_direction.x<0 and backdrop.debug_snapshot().blur_direction.y>0,"reverse and descent preserve signed smear direction")
 backdrop.reduced_motion=true
 check(backdrop.debug_snapshot().blur_pixels==0 and backdrop.debug_snapshot().blur_direction==Vector2.ZERO,"reduced motion turns off every blur")
 backdrop.reduced_motion=false;backdrop.motion_blur_enabled=false
 check(backdrop.debug_snapshot().blur_pixels==0,"independent blur setting takes effect immediately")
 backdrop.motion_blur_enabled=true
 var before:Dictionary=backdrop.debug_snapshot()
 await process_frame;await process_frame
 check(backdrop.debug_snapshot()==before,"unchanged input/pause leaves every material state identical")
 var resources:Array=[]
 for child in backdrop.get_children():resources.append([child.texture,child.material])
 var resource_count:int=int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
 var bounded:bool=true
 for i in range(12000):
  var travel:float=float(i)*19313.718 if i%2==0 else -float(i)*11013.333
  backdrop.update_flight(Vector2(travel,-travel),Vector2(22,-12),0.7)
  var state:Dictionary=backdrop.debug_snapshot()
  for key in ["city_scroll","sky_scroll","cloud_scroll","wisp_scroll","star_scroll","dust_scroll"]:
   var offset:Vector2=state[key]
   bounded=bounded and offset.is_finite() and offset.x>=0 and offset.x<1280 and offset==offset.round()
  bounded=bounded and state.cloud_scroll.y>=0 and state.cloud_scroll.y<640 and state.star_scroll.y>=0 and state.star_scroll.y<720
 check(bounded,"long-distance X/Y/reverse offsets remain finite, integral and bounded")
 check(backdrop.get_child_count()==7,"twelve thousand updates keep exact seven-node pool")
 var stable_resources:bool=true
 for i in range(7):stable_resources=stable_resources and backdrop.get_child(i).texture==resources[i][0] and backdrop.get_child(i).material==resources[i][1]
 check(stable_resources and int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))<=resource_count,"no node, texture, material or resource accumulation")
 backdrop.update_flight(Vector2(1e30,-1e30),Vector2(18,0),1.0)
 check(backdrop.debug_snapshot().cloud_scroll.is_finite(),"huge finite journeys reduce modulo before multiplication")
 before=backdrop.debug_snapshot()
 backdrop.update_flight(Vector2(NAN,0),Vector2.ZERO,0.0)
 backdrop.update_flight(Vector2.ZERO,Vector2(INF,0),0.0)
 backdrop.update_flight(Vector2.ZERO,Vector2.ZERO,NAN)
 backdrop.update_flight(Vector2.ZERO,Vector2.ZERO,0.0,Vector2(NAN,0))
 check(backdrop.debug_snapshot()==before,"invalid positions/velocities/progress/camera cannot poison the layer state")
 var periodic:bool=true
 for size in [1280.0,640.0,720.0]:
  for tile in range(-6,7):
   for offset in [-22.0,-0.5,0.5,22.0]:
    periodic=periodic and is_equal_approx(Backdrop.ordinary_coordinate(float(tile)*size+offset,size),Backdrop.ordinary_coordinate(float(tile+1)*size+offset,size))
 check(periodic,"ordinary forward-orientation tiles repeat every single extent in both directions")
 check(Backdrop.ordinary_coordinate(1281,1280)==1 and Backdrop.ordinary_coordinate(2559,1280)==1279,"wrap never reverses architecture or star orientation")
 var x_edges:bool=true;var y_edges:bool=true
 for child in [backdrop.atmosphere,backdrop.city,backdrop.clouds,backdrop.wisps,backdrop.starfield,backdrop.orbit_dust]:x_edges=x_edges and same_edges(child.texture.get_image(),false)
 for child in [backdrop.clouds,backdrop.wisps,backdrop.starfield,backdrop.orbit_dust]:y_edges=y_edges and same_edges(child.texture.get_image(),true)
 check(x_edges and y_edges,"actual runtime RGBA edges match on every declared repeating axis")
 var sky:Image=backdrop.atmosphere.texture.get_image()
 var composite_seams:bool=true
 for child in [backdrop.city,backdrop.clouds,backdrop.wisps,backdrop.starfield,backdrop.orbit_dust]:
  var source:Image=child.texture.get_image()
  for y in range(source.get_height()):
   var under:Color=sky.get_pixel(200,1840+y%720)
   composite_seams=composite_seams and under.blend(source.get_pixel(0,y))==under.blend(source.get_pixel(source.get_width()-1,y))
 check(composite_seams,"actual composite seam pixels match over the authored sky")
 var shader:String=FileAccess.get_file_as_string("res://assets/2d_v5/ascent_background.gdshader")
 check(not shader.contains("hint_screen_texture") and not shader.contains("uniform sampler2D") and not shader.contains("TIME") and shader.contains("i <= 6"),"bounded seven-tap local-texture blur cannot sample gameplay/UI and has no time animation")
 var dimensions:bool=true
 for extent in [Vector2(1280,720),Vector2(1920,1080),Vector2(3840,2160)]:
  stage.scale=extent/Backdrop.LOGICAL_SIZE
  for child in backdrop.get_children():dimensions=dimensions and child.get_global_transform().get_scale()*child.texture.get_size()==extent
 check(dimensions,"parent-only viewport scaling keeps seven screen-space planes aligned")
 backdrop.configure_route({"background_route":"orbit","background_blur_start_mps":30,"background_blur_full_mps":40})
 backdrop.update_flight(Vector2.ZERO,Vector2(22,0),0)
 check(backdrop.planet.visible and not backdrop.city.visible and backdrop.debug_snapshot().blur_pixels==0,"route presentation options remain configurable")
 backdrop.configure_route({"background_orbit_begin_altitude_m":NAN,"background_orbit_full_altitude_m":-10,"background_blur_start_mps":INF})
 backdrop.update_flight(Vector2.ZERO,Vector2.ZERO,1)
 check(backdrop.city.visible and not backdrop.planet.visible,"malformed route options are finite and altitude remains authoritative")
 print("Ascent backdrop: ",passed," passed, ",failed," failed")
 canvas.free();quit(1 if failed else 0)
