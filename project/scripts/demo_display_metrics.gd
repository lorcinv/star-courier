extends RefCounted
## Display-only metric adapter. Authored Controls retain their original design
## units; native rectangles, font rasterization and hit areas grow together.
## Never applies a fractional CanvasItem transform or touches world/camera state.
const BASE:Vector2=Vector2(1280,720)
const SNAPSHOT:StringName=&"demo_native_layout_base_v2"

static func factor(extent:Vector2) -> float:
 # Explicit half-step profiles: 720p=1,1080p=1.5,1440p=2,2160p=3.
 # A 1280x800 window keeps its 720p art frame and 40px top/bottom gutters.
 return clampf(floorf(minf(extent.x/BASE.x,extent.y/BASE.y)*2.0)*0.5,1.0,3.0)

static func point(value:Vector2,density:float) -> Vector2:
 return (value*density).round()

static func rect(value:Rect2,density:float) -> Rect2:
 # Round both edges, not width independently, to prevent one-pixel seams.
 var start:Vector2=point(value.position,density)
 return Rect2(start,point(value.end,density)-start)

static func font_size(value:int,density:float) -> int:
 return maxi(1,roundi(float(value)*density))

static func stage_rect(extent:Vector2) -> Rect2:
 var shown:Vector2=point(BASE,factor(extent))
 return Rect2(((extent-shown)*0.5).floor(),shown)

static func integer_texture(source:Texture2D,grid:Vector2i) -> Texture2D:
 # Re-sample the existing source to its authored pixel grid once per owner.
 # Callers display this at 2x/3x; no generated/repainted artwork is introduced.
 if source==null or grid.x<1 or grid.y<1:return source
 if Vector2i(source.get_size())==grid:return source
 var pixels:Image=source.get_image()
 if pixels==null or pixels.is_empty():return source
 pixels.resize(grid.x,grid.y,Image.INTERPOLATE_NEAREST)
 return ImageTexture.create_from_image(pixels)

static func apply_stage(stage:Control,density:float) -> void:
 # Root geometry is caller-owned. Descendants keep per-node authored snapshots,
 # so repeated application and 720->1080->720 round trips cannot compound.
 # Newly rebuilt menu nodes are captured automatically on their first pass.
 _apply_theme(stage,density)
 for child in stage.get_children():
  if child is Control:_apply_control(child,density)

static func apply_theme(control:Control,density:float) -> void:
 _apply_theme(control,density)

static func style(base:StyleBox,density:float) -> StyleBox:
 return _scaled_style(base,density)

static func apply_control(control:Control,density:float) -> void:
 _apply_control(control,density)

static func set_constant_override(control:Control,key:String,value:int) -> void:
 # Change one authored metric without recapturing already-native rectangles.
 if control.has_meta(SNAPSHOT):
  var base:Dictionary=control.get_meta(SNAPSHOT);base.constants[key]=value
 control.add_theme_constant_override(key,roundi(value*float(control.get_meta(&"demo_native_density_v2",1.0))))

static func set_style_override(control:Control,key:String,value:StyleBox) -> void:
 if control.has_meta(SNAPSHOT):
  var base:Dictionary=control.get_meta(SNAPSHOT);base.styles[key]=value.duplicate()
 control.add_theme_stylebox_override(key,_scaled_style(value,float(control.get_meta(&"demo_native_density_v2",1.0))))

static func set_rect_override(control:Control,value:Rect2) -> void:
 # Authored top-left-anchored controls only; Container children own their rect.
 if control.has_meta(SNAPSHOT):
  var base:Dictionary=control.get_meta(SNAPSHOT)
  base.offsets=Vector4(value.position.x,value.position.y,value.end.x,value.end.y)
 var native:Rect2=rect(value,float(control.get_meta(&"demo_native_density_v2",1.0)))
 control.position=native.position;control.size=native.size

static func forget(control:Control,recursive:bool=false) -> void:
 # Only call after assigning FRESH authored values, never on scaled geometry.
 if control.has_meta(SNAPSHOT):control.remove_meta(SNAPSHOT)
 if recursive:
  for child in control.get_children():
   if child is Control:forget(child,true)

static func _apply_control(control:Control,density:float) -> void:
 control.set_meta(&"demo_native_density_v2",density)
 var base:Dictionary
 if control.has_meta(SNAPSHOT):base=control.get_meta(SNAPSHOT)
 else:
  base={"offsets":Vector4(control.offset_left,control.offset_top,control.offset_right,control.offset_bottom),"minimum":control.custom_minimum_size,"fonts":{},"constants":{},"styles":{}}
  for property in control.get_property_list():
   var path:String=str(property.name)
   if path.begins_with("theme_override_font_sizes/"):
    var key:String=path.get_slice("/",1)
    if control.has_theme_font_size_override(key):base.fonts[key]=control.get_theme_font_size(key)
   elif path.begins_with("theme_override_constants/"):
    var key:String=path.get_slice("/",1)
    if control.has_theme_constant_override(key):base.constants[key]=control.get_theme_constant(key)
   elif path.begins_with("theme_override_styles/"):
    var key:String=path.get_slice("/",1)
    if control.has_theme_stylebox_override(key):base.styles[key]=control.get_theme_stylebox(key).duplicate()
  control.set_meta(SNAPSHOT,base)
 _apply_theme(control,density)
 for key in base.fonts:control.add_theme_font_size_override(key,font_size(int(base.fonts[key]),density))
 for key in base.constants:control.add_theme_constant_override(key,roundi(float(base.constants[key])*density))
 for key in base.styles:control.add_theme_stylebox_override(key,_scaled_style(base.styles[key],density))
 control.custom_minimum_size=point(base.minimum,density)
 # Resolve descendant font/minimum changes before restoring a parent rectangle.
 # Otherwise a 1080->720 transition may be clamped by the previous larger text.
 for child in control.get_children():
  if child is Control:_apply_control(child,density)
 # Containers own child positions and size; only their native minimum metrics
 # are retargeted. Direct Control children keep authored anchors and offsets.
 if not control.get_parent() is Container:
  var edges:Vector4=base.offsets
  control.offset_left=roundf(edges.x*density);control.offset_top=roundf(edges.y*density)
  control.offset_right=roundf(edges.z*density);control.offset_bottom=roundf(edges.w*density)
 if control is Container:control.queue_sort()

static func _apply_theme(control:Control,density:float) -> void:
 if control.theme==null:return
 var base:Theme
 if control.has_meta(&"demo_native_theme_base_v2"):base=control.get_meta(&"demo_native_theme_base_v2")
 else:
  base=control.theme.get_meta(&"demo_native_theme_source_v2") if control.theme.has_meta(&"demo_native_theme_source_v2") else control.theme.duplicate()
  control.set_meta(&"demo_native_theme_base_v2",base)
 var theme:Theme=base.duplicate()
 if base.default_font_size>0:theme.default_font_size=font_size(base.default_font_size,density)
 for kind in base.get_font_size_type_list():
  for key in base.get_font_size_list(kind):theme.set_font_size(key,kind,font_size(base.get_font_size(key,kind),density))
 for kind in base.get_constant_type_list():
  for key in base.get_constant_list(kind):theme.set_constant(key,kind,roundi(base.get_constant(key,kind)*density))
 for kind in base.get_stylebox_type_list():
  for key in base.get_stylebox_list(kind):theme.set_stylebox(key,kind,_scaled_style(base.get_stylebox(key,kind),density))
 theme.set_meta(&"demo_native_theme_source_v2",base)
 control.theme=theme

static func _scaled_style(base:StyleBox,density:float) -> StyleBox:
 var style:StyleBox=base.duplicate()
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
  var margin:float=base.get_content_margin(side)
  if margin>=0.0:style.set_content_margin(side,roundf(margin*density))
 if style is StyleBoxFlat:
  var original:StyleBoxFlat=base as StyleBoxFlat
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
   style.set_border_width(side,roundi(original.get_border_width(side)*density))
   style.set_expand_margin(side,roundf(original.get_expand_margin(side)*density))
  for corner in [CORNER_TOP_LEFT,CORNER_TOP_RIGHT,CORNER_BOTTOM_LEFT,CORNER_BOTTOM_RIGHT]:style.set_corner_radius(corner,roundi(original.get_corner_radius(corner)*density))
  style.shadow_size=roundi(original.shadow_size*density);style.shadow_offset=point(original.shadow_offset,density)
 # Texture style corners keep their source-pixel margins. They are drawn by
 # the existing skin at native output resolution, never by a 1.5x root transform.
 return style
