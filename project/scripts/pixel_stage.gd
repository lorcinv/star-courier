extends Control
## One integer-scaled nearest-neighbor 3D canvas. UI lives in a separate canvas.
## Coordinate helpers make pointer picking and world labels use that same view.
signal art_frame_changed(rect:Rect2)
const CANVAS_SIZE:Vector2i=Vector2i(640,360)
const SUPPORTED_CANVASES:Array[Vector2i]=[Vector2i(640,360),Vector2i(960,540),Vector2i(1280,720)]
var canvas_size:Vector2i=CANVAS_SIZE
var density_mode:String="fixed"
var viewport:SubViewport
var display:TextureRect
var pixel_scale:int=1
var display_rect:Rect2=Rect2()

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 viewport=SubViewport.new();viewport.name="PixelWorld";viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 viewport.msaa_3d=Viewport.MSAA_DISABLED
 viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
 viewport.scaling_3d_scale=1.0
 viewport.positional_shadow_atlas_size=1024
 add_child(viewport)
 display=TextureRect.new();display.name="IntegerPixelDisplay"
 display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 display.texture=viewport.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 display.stretch_mode=TextureRect.STRETCH_SCALE;display.mouse_filter=Control.MOUSE_FILTER_STOP
 add_child(display)
 resized.connect(_resize_canvas)
 _resize_canvas()

func _resize_canvas() -> void:
 if not is_instance_valid(viewport):return
 var extent:Vector2i=Vector2i(size.floor())
 if extent.x<=0 or extent.y<=0:return
 if density_mode!="fixed":canvas_size=choose_canvas(extent,density_mode)
 pixel_scale=maxi(1,mini(extent.x/canvas_size.x,extent.y/canvas_size.y))
 var pixels:Vector2i=canvas_size
 viewport.size=pixels
 var shown:Vector2=Vector2(pixels*pixel_scale)
 var offset:Vector2=((Vector2(extent)-shown)*.5).floor()
 var next_rect:Rect2=Rect2(offset,shown)
 var changed:bool=next_rect!=display_rect
 display_rect=next_rect;display.position=offset;display.size=shown
 if changed:art_frame_changed.emit(display_rect)

func set_canvas_size(pixels:Vector2i) -> bool:
 if not pixels in SUPPORTED_CANVASES:return false
 density_mode="fixed";canvas_size=pixels
 _resize_canvas()
 return true

func set_density_mode(value:String) -> bool:
 if not value in ["auto","balanced","low"]:return false
 density_mode=value;_resize_canvas();return true

static func choose_canvas(extent:Vector2i,value:String) -> Vector2i:
 # Only window changes select a grid. Frame rate never changes the artwork.
 var cap:int=640 if value=="low" else (960 if value=="balanced" else 1280)
 var chosen:Vector2i=CANVAS_SIZE;var best_area:int=-1
 for candidate in SUPPORTED_CANVASES:
  if candidate.x>cap:continue
  var scale:int=mini(extent.x/candidate.x,extent.y/candidate.y)
  if scale<1:continue
  var area:int=candidate.x*candidate.y*scale*scale
  if area>best_area or (area==best_area and candidate.x>chosen.x):chosen=candidate;best_area=area
 # A tiny embedding still fits without fractional pixels. The game's own
 # 1280×720 window minimum separately protects the native-resolution HUD.
 if best_area<0:
  var units:int=maxi(1,mini(extent.x/16,extent.y/9));chosen=Vector2i(units*16,units*9)
 return chosen

func screen_to_pixel(point:Vector2) -> Vector2:
 return (point-display_rect.position)/float(pixel_scale)

func pixel_to_screen(point:Vector2) -> Vector2:
 return display_rect.position+point*float(pixel_scale)
