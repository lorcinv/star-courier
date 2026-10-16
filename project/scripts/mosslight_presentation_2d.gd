extends Node2D
## Read-only ordinary free-flight environment. Two distant raster layers and a
## registered greenhouse surround the live solver's rocks and capture circle.
## No portal, ecology, floor, new collision shape, emitter, timer or replay cue.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Receipt=preload("res://scripts/mosslight_receipt_v2.gd")
const RasterSkin=preload("res://scripts/demo_raster_skin.gd")
const LOGICAL_SIZE:Vector2=Vector2(1280,720)
# Measured maximum opaque-pixel-center distance from each source's center.
# Every painted fragment fits inside the disclosed physical CCD circle.
const ROCK_RADII:Dictionary={"rock-1":97.13135436098891,"rock-2":92.01222744831254}
const MAX_ROCKS:int=3
const MAX_NODES:int=9
var _route:Dictionary={}
var _far:Sprite2D
var _islands:Sprite2D
var _props:PhysicalField
var _receiver:Sprite2D
var _label:Label
var _label_card:PanelContainer
var _rocks:Array=[]
var _origin:Vector2=Vector2.ZERO
var _cell:float=72.0
var _enabled:bool=false
var _scene_visible:bool=false
var _weight:float=0.0
var _sample_camera:Vector2=Vector2.ZERO
var _have_sample:bool=false

class PhysicalField extends Node2D:
 var circles:Array=[]
 var capture_center:Vector2=Vector2.ZERO
 var capture_radius:float=1.0
 var zoom:float=1.0
 var received:bool=false
 func _draw() -> void:
  # Functional overlays alone expose physical boundaries; distant islands
  # have neither these circles nor high-contrast foreground silhouettes.
  var color:Color=Color("c1ef9f") if received else Color("a3efd7")
  draw_arc(capture_center,capture_radius,0.0,TAU,64,color,1.5/zoom,true)
  for side in [-1.0,1.0]:
   var edge:Vector2=capture_center+Vector2(side*(capture_radius+12.0/zoom),0.0)
   var tip:Vector2=edge-Vector2(side*10.0/zoom,0.0)
   draw_line(edge,tip,color,2.0/zoom,true)
   draw_line(tip,tip+Vector2(side*5.0/zoom,-4.0/zoom),color,2.0/zoom,true)
   draw_line(tip,tip+Vector2(side*5.0/zoom,4.0/zoom),color,2.0/zoom,true)
  for item in circles:
   draw_arc(item.position,item.radius,0.0,TAU,48,Color(1.0,.78,.44,.64),1.0/zoom,true)

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false);set_physics_process(false)

func configure_route(route:Dictionary,world_parent:Node2D,origin:Vector2,cell:float=72.0) -> bool:
 leave_flight()
 if not Content.has_markers(route) or not Receipt.route_error(route).is_empty():return false
 if not is_instance_valid(world_parent) or not origin.is_finite() or not is_finite(cell) or cell<=0.0 or cell>10000.0:return false
 if route.hazards.size()>MAX_ROCKS:return false
 _route=route.duplicate(true);_origin=origin;_cell=cell
 _far=_plane("MosslightDistantGarden",Receipt.FAR)
 _islands=_plane("MosslightDecorativeIslands",Receipt.ISLANDS)
 _far.modulate.a=0.0
 # Far art is composition-compatible, not mathematically seamless. A small
 # uniform cover overscan and bounded drift avoid ever hard-wrapping it.
 _far.material.set_shader_parameter("repeat_x",false)
 _far.material.set_shader_parameter("overscan",1.10)
 _islands.modulate=Color(.74,.83,.80,0.0)
 _islands.material.set_shader_parameter("saturation",.48)
 _props=PhysicalField.new();_props.name="MosslightPhysicalField";_props.z_index=-2
 world_parent.add_child(_props)
 var spec:Dictionary=route.mosslight_receiver
 var goal:Vector2=origin+Vector2(float(route.distance),float(route.destination_y))*cell
 _props.capture_center=goal;_props.capture_radius=float(route.delivery_radius)*cell
 var anchor:Vector2=Vector2(float(spec.capture_anchor_native[0]),float(spec.capture_anchor_native[1]))
 _receiver=Sprite2D.new();_receiver.name="MosslightGreenhouseReceiver"
 _receiver.texture=load(Receipt.RECEIVER);_receiver.centered=false
 # The PNG is unchanged. Its alpha-1 tool residue is explicitly discarded by
 # the registered material; bounds include every alpha >= 2/255 pixel.
 # Offset preserves source-space registration while removing empty framing.
 var painted:Rect2i=Receipt.RECEIVER_VISIBLE_BOUNDS
 _receiver.region_enabled=true;_receiver.region_rect=Rect2(painted)
 _receiver.offset=Vector2(painted.position)
 _receiver.set_meta("painted_native_bounds",painted)
 var cutout:ShaderMaterial=ShaderMaterial.new();cutout.shader=load(Receipt.SHADER)
 cutout.set_shader_parameter("registered_cutout",true);_receiver.material=cutout
 _receiver.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _receiver.scale=Vector2.ONE*_props.capture_radius/float(spec.capture_radius_native)
 # No rounding: the registered transparent mouth and solver capture center
 # must remain coincident, including fractional world origin and zoom.
 _receiver.position=goal-anchor*_receiver.scale
 _receiver.set_meta("capture_center",goal)
 _receiver.set_meta("capture_radius",_props.capture_radius)
 _receiver.set_meta("registered_native_anchor",anchor)
 _receiver.set_meta("registered_native_radius",float(spec.capture_radius_native))
 _receiver.set_meta("mosslight_registered_receiver",true)
 _props.add_child(_receiver)
 for index in range(route.hazards.size()):
  var raw:Dictionary=route.hazards[index]
  var rock:Sprite2D=Sprite2D.new();rock.name="MosslightPhysicalRock"+str(index)
  rock.texture=load("res://assets/2d_v5/flight/"+str(raw.mosslight_art)+".png")
  rock.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  rock.set_meta("physical_hazard_index",index)
  rock.set_meta("registered_native_radius",ROCK_RADII[raw.mosslight_art])
  rock.position=origin+Vector2(float(raw.x),float(raw.y))*cell
  rock.scale=Vector2.ONE*float(raw.radius)*cell/float(ROCK_RADII[raw.mosslight_art])
  _props.add_child(rock);_rocks.append(rock)
 _label_card=PanelContainer.new();_label_card.name="MosslightReceiptAction"
 _label_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _label_card.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _label_card.add_theme_stylebox_override("panel",RasterSkin.style("normal",16.0,7.0))
 _label_card.custom_minimum_size=Vector2(196.0,40.0);_label_card.size=_label_card.custom_minimum_size
 _label_card.z_index=3;_props.add_child(_label_card)
 _label=Label.new();_label.name="MosslightReceiverLabel";_label.text="进入光圈交件"
 _label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
 _label.add_theme_font_override("font",load("res://assets/fonts/ChineseSans.otf"))
 _label.add_theme_font_size_override("font_size",22)
 _label.add_theme_color_override("font_color",Color("d6f4c6"))
 _label_card.add_child(_label)
 _label_card.hide()
 _enabled=true;_scene_visible=true;_refresh_visibility()
 return true

func _plane(label:String,path:String) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new();node.name=label;node.texture=load(path);node.centered=false
 node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 node.scale=LOGICAL_SIZE/Vector2(node.texture.get_size())
 var material:ShaderMaterial=ShaderMaterial.new();material.shader=load(Receipt.SHADER)
 material.set_shader_parameter("source_size_px",Vector2(node.texture.get_size()))
 material.set_shader_parameter("logical_size_px",LOGICAL_SIZE)
 material.set_shader_parameter("pixel_grid_px",2.0)
 node.material=material;add_child(node);return node

func update_from_sim(sim,zoom:float=1.0,camera_m:Vector2=Vector2(INF,INF),paused:bool=false,safe_view:Rect2=Rect2(),hud_rects:Array=[]) -> void:
 if not _enabled:return
 var cargo:Vector2=sim.cargo_position()
 if not cargo.is_finite():return
 _weight=smoothstep(float(_route.mosslight_backdrop_begin_x),float(_route.mosslight_backdrop_full_x),cargo.x)
 _far.modulate.a=_weight;_islands.modulate.a=.50*_weight
 # First restore samples directly at the restored camera. Later paused calls
 # freeze the sampled phase. Reverse flight derives the old phase directly;
 # there is no accumulated travel, transition event or ambient drift.
 if not paused or not _have_sample:
  _sample_camera=camera_m if camera_m.is_finite() else cargo
  _have_sample=true
 _far.material.set_shader_parameter("scroll_px",_far_scroll(_sample_camera,Vector2(_far.texture.get_size())))
 _islands.material.set_shader_parameter("scroll_px",_scroll(_sample_camera,2.0,.35,Vector2(_islands.texture.get_size())))
 var z:float=maxf(.01,zoom)
 _props.zoom=z;_props.received=sim.status=="success";_props.circles=[]
 for index in range(_rocks.size()):
  var rock:Sprite2D=_rocks[index]
  if index>=sim.obstacles.size():rock.hide();continue
  var hazard:Dictionary=sim.obstacles[index]
  rock.visible=float(hazard.health)>0.0
  rock.position=_origin+hazard.position*_cell
  rock.scale=Vector2.ONE*float(hazard.radius)*_cell/float(rock.get_meta("registered_native_radius"))
  if rock.visible:_props.circles.append({"position":rock.position,"radius":float(hazard.radius)*_cell})
 _label.text="货物已签收" if sim.status=="success" else "进入光圈交件"
 _layout_label(z,safe_view,hud_rects)
 _props.queue_redraw();_refresh_visibility()

func _layout_label(zoom:float,safe_view:Rect2,hud_rects:Array) -> void:
 # Only the text moves. World supplies its current mapped safe view and real
 # HUD bounds; the registered mouth, circle, camera and solver stay untouched.
 # Resolve the full panel/text size now, including the first paused restore,
 # rather than testing a point or waiting for the Container's next frame.
 _label_card.hide();_label_card.scale=Vector2.ONE/zoom
 _label_card.size=_label_card.custom_minimum_size.max(_label.get_combined_minimum_size()+_label_card.get_theme_stylebox("panel").get_minimum_size())
 var size:Vector2=_label_card.size/zoom
 var center:Vector2=_props.capture_center
 var gap:float=8.0/zoom
 var radius:float=_props.capture_radius-gap
 var safe:Rect2=safe_view.grow(-gap)
 if safe_view.size.x<=gap*2.0 or safe_view.size.y<=gap*2.0 or not safe.has_point(center):return
 if radius<=size.x*.5:return
 # All four corners must fit in the real circular aperture. Keep its center
 # open for the incoming cargo and leave the greenhouse pixels unobstructed.
 var chord:float=sqrt(radius*radius-size.x*size.x*.25)
 var top:float=maxf(center.y-chord,safe.position.y)
 var bottom:float=minf(center.y+chord-size.y,safe.end.y-size.y)
 var candidates:Array[float]=[top,bottom]
 for raw in hud_rects.slice(0,32):
  var blocked:Rect2=raw.grow(gap)
  candidates.append(blocked.end.y)
  candidates.append(blocked.position.y-size.y)
 var center_clearance:float=maxf(32.0/zoom,_props.capture_radius*.24)
 for y in candidates:
  var rect:Rect2=Rect2(Vector2(center.x-size.x*.5,y),size)
  if y<top or y>bottom or not safe.encloses(rect):continue
  if rect.position.y<center.y+center_clearance and rect.end.y>center.y-center_clearance:continue
  var blocked:bool=false
  for raw in hud_rects.slice(0,32):
   if rect.intersects(raw.grow(gap)):
    blocked=true;break
  if blocked:continue
  _label_card.position=rect.position;_label_card.show();return
 # No safe, genuinely in-circle slot: omit rather than clamp the world target
 # to a screen edge or show truncated/occluded text with a false association.

func _far_scroll(camera:Vector2,size:Vector2) -> Vector2:
 var limit_x:float=size.x*(1.0-1.0/1.10)*.5-2.0
 return Vector2(round(clampf((camera.x-72.0)*.28,-limit_x,limit_x)/2.0)*2.0,round(clampf((camera.y+18.0)*.14,-32.0,32.0)/2.0)*2.0)

func _scroll(camera:Vector2,x_depth:float,y_depth:float,size:Vector2) -> Vector2:
 # Coordinate-derived 2px raster phase is bounded even far beyond the goal.
 return Vector2(fposmod(round(fposmod(camera.x,size.x/x_depth)*x_depth/2.0)*2.0,size.x),round(clampf((camera.y+18.0)*y_depth,-32.0,32.0)/2.0)*2.0)

func set_scene_visible(value:bool) -> void:
 _scene_visible=value;_refresh_visibility()

func _refresh_visibility() -> void:
 visible=_enabled and _scene_visible
 if is_instance_valid(_props):_props.visible=visible

func route_enabled() -> bool:return _enabled
func receiver_node() -> Sprite2D:return _receiver
func suppresses_hazard(index:int) -> bool:return _enabled and index>=0 and index<_rocks.size()

func leave_flight() -> void:
 _enabled=false;_scene_visible=false;_weight=0.0;_route.clear();_rocks.clear()
 _sample_camera=Vector2.ZERO;_have_sample=false
 if is_instance_valid(_props):_props.free()
 if is_instance_valid(_far):_far.free()
 if is_instance_valid(_islands):_islands.free()
 _props=null;_far=null;_islands=null;_receiver=null;_label=null;_label_card=null;hide()

func debug_snapshot() -> Dictionary:
 return {"enabled":_enabled,"visible":visible,"weight":_weight,"rocks":_rocks.size(),"registered_receiver":is_instance_valid(_receiver),"node_budget":MAX_NODES,"sample_camera":_sample_camera,"has_sample":_have_sample}
