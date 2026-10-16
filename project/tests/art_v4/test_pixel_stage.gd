extends SceneTree
## Integer-fit density contract; no rendering or simulation timing assumptions.
const Stage=preload("res://scripts/pixel_stage.gd")
const EXPECTED_CHECKS=157
var passed:int=0
var failed:int=0
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var stage=Stage.new();root.add_child(stage)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=14.6;stage.viewport.add_child(camera);camera.position=Vector3(0,6.35,28);camera.look_at(Vector3(0,2.15,0));camera.current=true
 var cases:Array=[
  [Vector2i(1440,900),Vector2i(1280,720),Vector2i(640,360)],
  [Vector2i(1280,800),Vector2i(1280,720),Vector2i(640,360)],
  [Vector2i(1920,1080),Vector2i(960,540),Vector2i(960,540)],
  [Vector2i(3840,2160),Vector2i(1280,720),Vector2i(960,540)],
  [Vector2i(1366,768),Vector2i(1280,720),Vector2i(640,360)],
  [Vector2i(1279,719),Vector2i(960,540),Vector2i(960,540)],
  [Vector2i(960,540),Vector2i(960,540),Vector2i(960,540)],
  [Vector2i(639,359),Vector2i(624,351),Vector2i(624,351)],
  [Vector2i(320,200),Vector2i(320,180),Vector2i(320,180)],
  [Vector2i(16,9),Vector2i(16,9),Vector2i(16,9)]
 ]
 var baseline:Array=[]
 for mode in ["auto","balanced","low"]:
  for case in cases:
   var extent:Vector2i=case[0];stage.size=Vector2(extent);stage.set_density_mode(mode);stage._resize_canvas();await process_frame
   var expected:Vector2i=case[1] if mode=="auto" else case[2]
   if mode=="low" and extent.x>=640 and extent.y>=360:expected=Vector2i(640,360)
   var label:="%s at %s"%[mode,extent]
   check(stage.canvas_size==expected and stage.viewport.size==expected,"window coverage / density tie-break: "+label)
   check(stage.pixel_scale>=1 and stage.display.size==Vector2(stage.viewport.size*stage.pixel_scale),"exact integer presentation: "+label)
   check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(stage.display_rect) and stage.display.position==((Vector2(extent)-stage.display.size)*.5).floor(),"centered canvas fits without cropping: "+label)
   var mapping_ok:=true
   for fraction in [Vector2.ZERO,Vector2(.123,.456),Vector2(.5,.5),Vector2.ONE]:
    var pixel:Vector2=Vector2(stage.viewport.size)*fraction;mapping_ok=mapping_ok and stage.screen_to_pixel(stage.pixel_to_screen(pixel)).is_equal_approx(pixel)
   check(mapping_ok,"pointer round trip including frame corners: "+label)
   var rays:Array=[]
   for fraction in [Vector2.ZERO,Vector2(.5,.5),Vector2.ONE]:rays.append(camera.project_ray_origin(Vector2(stage.viewport.size)*fraction))
   if baseline.is_empty():baseline=rays
   var same_fov:=true
   for i in rays.size():same_fov=same_fov and rays[i].distance_to(baseline[i])<.00001
   check(same_fov and is_equal_approx(camera.size,14.6),"identical orthographic FOV at every density: "+label)
 stage.size=Vector2(1920,1080);stage.set_density_mode("balanced")
 var old_canvas:Vector2i=stage.canvas_size;var old_mode:String=stage.density_mode;var old_rect:Rect2=stage.display_rect
 check(not stage.set_density_mode("ultra") and stage.canvas_size==old_canvas and stage.density_mode==old_mode and stage.display_rect==old_rect,"invalid density mode is rejected without state mutation")
 check(not stage.set_canvas_size(Vector2i(800,450)) and stage.canvas_size==old_canvas and stage.density_mode==old_mode,"unsupported fixed canvas is rejected without state mutation")
 check(stage.set_canvas_size(Vector2i(1280,720)) and stage.density_mode=="fixed" and stage.viewport.size==Vector2i(1280,720),"supported fixed-canvas probe remains available")
 check(stage.display.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"nearest presentation has no bilinear blur")
 check(stage.viewport.msaa_3d==Viewport.MSAA_DISABLED and stage.viewport.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED and stage.viewport.scaling_3d_scale==1.0,"only one native pixel grid, no secondary scaling or antialiasing")
 check(Stage.choose_canvas(Vector2i(1280,720),"auto")==Vector2i(1280,720) and Stage.choose_canvas(Vector2i(1280,720),"balanced")==Vector2i(640,360),"equal covered area favors the sharpest canvas within the selected cap")
 old_rect=stage.display_rect;stage.size=Vector2.ZERO;stage._resize_canvas()
 check(stage.display_rect==old_rect,"zero-area transient resize preserves the last valid frame")
 stage.free()
 if passed+failed!=EXPECTED_CHECKS:check(false,"every expected density assertion ran")
 print("PIXEL_STAGE_TESTS passed=",passed," failed=",failed);quit(1 if failed else 0)
