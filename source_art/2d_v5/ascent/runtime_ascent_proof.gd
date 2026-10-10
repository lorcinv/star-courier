extends SceneTree
## Isolated native renderer fixture, not a claim of integrated gameplay QA.
const Backdrop=preload("res://scripts/ascent_backdrop_2d.gd")
const OUT:String="res://source_art/2d_v5/ascent/"
var backdrop
var status:Label
var started:bool=false
var fps_samples:Array[float]=[]
var data:Dictionary={"fixture":"Actual Godot GL Compatibility native rendering. Scripted camera path exercises the isolated component; native Enter starts the run. This is not gameplay input evidence.","recording_fps":30,"frames":[],"snapshots":[]}
func _initialize() -> void:run.call_deferred()
class NativeStart extends Node:
 var fixture
 func _input(event:InputEvent) -> void:
  if event is InputEventKey and event.pressed and event.keycode==KEY_ENTER:fixture.started=true
func run() -> void:
 var starter:NativeStart=NativeStart.new();starter.fixture=self;root.add_child(starter)
 root.size=Vector2i(1280,720);root.title="Ascent Backdrop Native Proof"
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 var canvas:CanvasLayer=CanvasLayer.new();root.add_child(canvas)
 var stage:Node2D=Node2D.new();canvas.add_child(stage)
 backdrop=Backdrop.new();stage.add_child(backdrop);backdrop.configure_route({})
 # A generated cargo sprite and functional text stay outside the background
 # materials. Their exact pixels are checked at rest and at full blur.
 var cargo:Sprite2D=Sprite2D.new();cargo.texture=load("res://assets/2d_v5/modules/cargo-pixel.png")
 cargo.position=Vector2(352,356);cargo.scale=Vector2(2,2);cargo.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;stage.add_child(cargo)
 status=Label.new();status.position=Vector2(24,24);status.add_theme_font_size_override("font_size",24);status.text="Isolated ascent layers | Press Enter";stage.add_child(status)
 while not started:await process_frame
 await capture("runtime-00-departure")
 await segment("SLOW CAMERA / ascent + horizontal travel",8.0,Vector2.ZERO,Vector2(3,-3),"slow")
 await segment("FAST CAMERA / clouds to orbital altitude",11.0,Vector2(90,-25),Vector2(22,-11),"fast")
 await segment("ORBIT / sparse near dust + distant stars",5.0,Vector2(332,-150),Vector2(22,0),"orbit")
 await segment("REVERSE / signed two-axis parallax",4.0,Vector2(290,-90),Vector2(-22,11),"reverse")
 backdrop.update_flight(Vector2(220,-80),Vector2(22,-11),0.5)
 status.text="PAUSED / identical material state and pixels"
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 var first:PackedByteArray=root.get_texture().get_image().get_data()
 root.get_texture().get_image().save_png(OUT+"runtime-pause-before.png")
 await create_timer(1.5).timeout
 await RenderingServer.frame_post_draw
 var second:PackedByteArray=root.get_texture().get_image().get_data()
 root.get_texture().get_image().save_png(OUT+"runtime-pause-after.png")
 data["pause_pixels_identical"]=first==second
 # Exactly equal nontransparent cargo pixels with blur off/on at same geometry.
 backdrop.motion_blur_enabled=false
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 var crisp:Image=root.get_texture().get_image()
 backdrop.motion_blur_enabled=true
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 var blurred:Image=root.get_texture().get_image()
 var mask:Image=cargo.texture.get_image();var unchanged:bool=true;var tested:int=0
 var origin:Vector2i=Vector2i(cargo.position)-mask.get_size()
 for y in range(mask.get_height()):
  for x in range(mask.get_width()):
   if mask.get_pixel(x,y).a==1.0:
    for yy in range(2):
     for xx in range(2):
      var p:Vector2i=origin+Vector2i(x*2+xx,y*2+yy)
      unchanged=unchanged and crisp.get_pixelv(p)==blurred.get_pixelv(p);tested+=1
 var ui_same:bool=true;var ui_pixels:int=0
 for y in range(24,60):
  for x in range(24,1200):
   var pixel:Color=crisp.get_pixel(x,y)
   if pixel.r>=0.999 and pixel.g>=0.999 and pixel.b>=0.999:
    ui_same=ui_same and pixel==blurred.get_pixel(x,y);ui_pixels+=1
 data["ui_opaque_text_pixels_unchanged_by_background_blur"]=ui_same
 data["ui_text_pixels_tested"]=ui_pixels
 data["cargo_opaque_pixels_unchanged_by_background_blur"]=unchanged;data["cargo_pixels_tested"]=tested
 data["engine_fps_samples"]=fps_samples
 var f:FileAccess=FileAccess.open(OUT+"native-render-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(data," "));f.close()
 print("NATIVE_RENDER_RESULT ",data["pause_pixels_identical"]," cargo ",unchanged," samples ",fps_samples.size())
 quit(0 if first==second and unchanged and ui_same and ui_pixels>100 else 1)
func segment(label:String,duration:float,origin:Vector2,velocity:Vector2,slug:String) -> void:
 var age:float=0.0;var frames:int=0;var last_second:int=-1
 var begin:int=Time.get_ticks_msec()
 while age<duration:
  await process_frame
  var delta:float=root.get_process_delta_time();age+=delta;frames+=1
  var p:Vector2=origin+velocity*age
  backdrop.update_flight(p,velocity,clampf(p.x/520.0,0,1),p)
  status.text=label+" | altitude "+str(roundi(-p.y))+" m"
  var second:int=int(age)
  if second!=last_second:
   fps_samples.append(float(Engine.get_frames_per_second()));last_second=second
   if second in [0,3,7,10]:await capture("runtime-"+slug+"-"+str(second))
 data["frames"].append({"segment":slug,"render_frames":frames,"elapsed_wall_ms":Time.get_ticks_msec()-begin,"script_path_seconds":age})
func capture(label:String) -> void:
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+label+".png")
 data["snapshots"].append({"name":label,"state":backdrop.debug_snapshot()})
