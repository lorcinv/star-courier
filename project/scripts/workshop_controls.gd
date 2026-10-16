extends RefCounted
## Camera math and a non-mutating input transaction for the 2D workbench.
## Pixels here are SubViewport pixels, AFTER PixelStage's integer inverse.
## Do not call main.render(), HUD.render(), or rebuild world nodes while panning.
const SCENE_SIZE:Vector2=Vector2(1280,720)
const CELL:float=72.0
const MIN_ZOOM:float=.25
# A retained legacy design may need a wider recovery view than a paid grid.
# This finite floor covers the complete Vector2i cell range without zero zoom.
const MIN_SAFE_ZOOM:float=1.0e-12
const MAX_ZOOM:float=2.0
const ZOOM_STEP:float=1.125
const DRAG_DISTANCE:float=6.0
var grid_bounds:Rect2i=Rect2i(-4,-2,9,5)
var origin:Vector2=Vector2(728,288)
var extent:Vector2=SCENE_SIZE
var usable:Rect2=Rect2(Vector2.ZERO,SCENE_SIZE)
var center:Vector2=Vector2(708,315)
var zoom:float=1.12
var minimum_zoom:float=MIN_ZOOM
var content:Rect2
var presentation_bounds:Rect2
var configured:bool=false
var gesture:String=""
var gesture_button:int=0
var press_pixel:Vector2
var press_cell:Vector2i
var press_center:Vector2
var press_id:int=-1
var press_revision:int=-1
var dragged:bool=false
var epoch:int=0

func configure(bounds_value:Rect2i,origin_value:Vector2,extent_value:Vector2,usable_value:Rect2=Rect2(),parts:Array=[],presentation_rect:Rect2=Rect2()) -> bool:
 if bounds_value.size.x<=0 or bounds_value.size.y<=0 or not origin_value.is_finite() or not extent_value.is_finite() or extent_value.x<=0 or extent_value.y<=0:return false
 var frame:Rect2=Rect2(Vector2.ZERO,extent_value)
 var next_usable:Rect2=frame if usable_value.size==Vector2.ZERO else frame.intersection(usable_value)
 if not next_usable.position.is_finite() or not next_usable.size.is_finite() or next_usable.size.x<=0 or next_usable.size.y<=0:return false
 if presentation_rect.size!=Vector2.ZERO and not finite_rect(presentation_rect):return false
 var extra_changed:bool=presentation_rect!=presentation_bounds
 presentation_bounds=presentation_rect
 var changed:bool=extra_changed or not configured or bounds_value!=grid_bounds or origin_value!=origin or extent_value!=extent or next_usable!=usable
 if changed:cancel()
 var geometry_changed:bool=extra_changed or not configured or bounds_value!=grid_bounds or origin_value!=origin
 grid_bounds=bounds_value;origin=origin_value;extent=extent_value;usable=next_usable
 content=grid_rect()
 if presentation_bounds.size!=Vector2.ZERO:content=content.merge(presentation_bounds)
 var craft:Rect2=design_rect(parts)
 if craft.size!=Vector2.ZERO:content=content.merge(craft)
 configured=true
 if geometry_changed:fit(parts,true)
 else:center=clamp_center(center)
 return true

func grid_rect() -> Rect2:
 return Rect2(origin+(Vector2(grid_bounds.position)-Vector2.ONE*.5)*CELL,Vector2(grid_bounds.size)*CELL)

func design_rect(parts:Array) -> Rect2:
 var result:Rect2
 var first:bool=true
 for part in parts:
  if not part is Dictionary or not part.has("x") or not part.has("y"):continue
  if not (part.x is int or part.x is float) or not (part.y is int or part.y is float):continue
  var cell:Vector2=Vector2(float(part.x),float(part.y))
  if not cell.is_finite():continue
  var rect:Rect2=Rect2(origin+(cell-Vector2.ONE*.5)*CELL,Vector2.ONE*CELL)
  if not finite_rect(rect):continue
  var merged:Rect2=rect if first else result.merge(rect)
  if not finite_rect(merged):continue
  result=merged;first=false
 return result

static func finite_rect(rect:Rect2) -> bool:
 return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite() and rect.size.x>0 and rect.size.y>0

func pixels_per_world() -> float:return extent.x/SCENE_SIZE.x*zoom
func rendered_center() -> Vector2:
 var scale_value:float=pixels_per_world()
 return (center*scale_value).round()/scale_value
func world_to_pixel(point:Vector2) -> Vector2:return (point-rendered_center())*pixels_per_world()+extent*.5
func pixel_to_world(pixel:Vector2) -> Vector2:return (pixel-extent*.5)/pixels_per_world()+rendered_center()
func cell_at(pixel:Vector2) -> Vector2i:return Vector2i(((pixel_to_world(pixel)-origin)/CELL).round())
func contains_pixel(pixel:Vector2) -> bool:return pixel.is_finite() and Rect2(Vector2.ZERO,extent).has_point(pixel)

func clamp_center(value:Vector2) -> Vector2:
 # Keep the usable-frame focus within one cell of the actual editable content.
 # This lets every edge cell be centered without allowing infinite empty panning.
 var offset:Vector2=(usable.get_center()-extent*.5)/pixels_per_world()
 var limits:Rect2=content.grow(CELL)
 var focus:Vector2=value+offset
 return Vector2(clampf(focus.x,limits.position.x,limits.end.x),clampf(focus.y,limits.position.y,limits.end.y))-offset

func set_view(center_value:Vector2,zoom_value:float) -> bool:
 if not center_value.is_finite() or not is_finite(zoom_value) or zoom_value<=0:return false
 zoom=clampf(zoom_value,minimum_zoom,MAX_ZOOM);center=clamp_center(center_value)
 return true

func fit(parts:Array=[],include_grid:bool=true) -> void:
 cancel()
 var craft:Rect2=design_rect(parts)
 var target:Rect2=grid_rect() if include_grid or craft.size==Vector2.ZERO else craft
 if include_grid and craft.size!=Vector2.ZERO:target=target.merge(craft)
 # Floor-bearing equipment must remain visible above native editing controls.
 # It changes only the fit rectangle, never cell coordinates or input inversion.
 if include_grid and presentation_bounds.size!=Vector2.ZERO:target=target.merge(presentation_bounds)
 content=grid_rect().merge(target)
 # 24 reference pixels per side, including the half-cell outside edge. Leave
 # another viewport pixel for the mandatory rendered-camera rounding below.
 var padding:Vector2=Vector2.ONE*(24.0*extent.x/SCENE_SIZE.x+1.0)
 var available:Vector2=(usable.size-padding*2.0).max(Vector2.ONE)
 var fit_zoom:float=minf(available.x/target.size.x,available.y/target.size.y)/(extent.x/SCENE_SIZE.x)
 minimum_zoom=minf(MIN_ZOOM,maxf(MIN_SAFE_ZOOM,fit_zoom))
 zoom=clampf(fit_zoom,minimum_zoom,MAX_ZOOM)
 center=target.get_center()-(usable.get_center()-extent*.5)/pixels_per_world()
 center=clamp_center(center)

func zoom_at(pixel:Vector2,steps:float) -> bool:
 if not contains_pixel(pixel) or not is_finite(steps) or is_zero_approx(steps):return false
 cancel()
 var anchor:Vector2=pixel_to_world(pixel)
 var next_zoom:float=clampf(zoom*pow(ZOOM_STEP,clampf(steps,-32,32)),minimum_zoom,MAX_ZOOM)
 if is_equal_approx(next_zoom,zoom):return false
 zoom=next_zoom
 center=clamp_center(anchor-(pixel-extent*.5)/pixels_per_world())
 return true

func begin_pan(pixel:Vector2) -> bool:
 cancel()
 if not contains_pixel(pixel):return false
 gesture="pan";gesture_button=MOUSE_BUTTON_MIDDLE;press_pixel=pixel;press_center=center
 return true

func pan_to(pixel:Vector2,button_held:bool=true,allowed:bool=true) -> bool:
 if gesture!="pan":return false
 if not button_held or not allowed or not contains_pixel(pixel):cancel();return false
 center=clamp_center(press_center-(pixel-press_pixel)/pixels_per_world())
 return true

func begin_edit(pixel:Vector2,cell:Vector2i,part_id:int,revision:int) -> bool:
 cancel()
 # Source permission differs from target permission: preserve recovery access
 # to a real saved part outside this tier; empty locked cells remain forbidden.
 if not contains_pixel(pixel) or (part_id<0 and not grid_bounds.has_point(cell)):return false
 gesture="move" if part_id>=0 else "place";gesture_button=MOUSE_BUTTON_LEFT
 press_pixel=pixel;press_cell=cell;press_id=part_id;press_revision=revision;dragged=false
 return true

func update_edit(pixel:Vector2,button_held:bool=true,allowed:bool=true) -> void:
 if gesture not in ["move","place"]:return
 if not button_held or not allowed or not contains_pixel(pixel):cancel();return
 if pixel.distance_to(press_pixel)>=DRAG_DISTANCE*extent.x/SCENE_SIZE.x:dragged=true

func release_edit(pixel:Vector2,cell:Vector2i,parts:Array,revision:int,allowed:bool=true) -> Dictionary:
 var kind:String=gesture;var id:int=press_id;var from:Vector2i=press_cell
 var same_revision:bool=press_revision==revision;var was_dragged:bool=dragged or pixel.distance_to(press_pixel)>=DRAG_DISTANCE*extent.x/SCENE_SIZE.x
 cancel() # Consume first: duplicate releases cannot produce duplicate commits.
 if kind not in ["move","place"] or not allowed or not contains_pixel(pixel) or not same_revision:return {}
 if kind=="place":
  if was_dragged or cell!=from or not grid_bounds.has_point(cell) or occupied(parts,cell):return {}
  return {"kind":"place","cell":cell}
 if not was_dragged or not valid_move(parts,id,from,cell,grid_bounds):return {}
 return {"kind":"move","id":id,"from":from,"cell":cell}

func cancel() -> void:
 gesture="";gesture_button=0;press_id=-1;press_revision=-1;dragged=false;epoch+=1

static func occupied(parts:Array,cell:Vector2i,except_id:int=-1) -> bool:
 for part in parts:
  if part is Dictionary and int(part.get("id",-1))!=except_id and Vector2i(int(part.get("x",0)),int(part.get("y",0)))==cell:return true
 return false

static func valid_move(parts:Array,id:int,from:Vector2i,to:Vector2i,bounds_value:Rect2i) -> bool:
 if id<0 or from==to or not bounds_value.has_point(to) or occupied(parts,to,id):return false
 for part in parts:
  if part is Dictionary and int(part.get("id",-1))==id:return Vector2i(int(part.get("x",0)),int(part.get("y",0)))==from
 return false
