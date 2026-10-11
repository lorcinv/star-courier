extends Node2D
## Presentation only: saved geometry in, camera/background proposals out.
## Never owns clocks, input, simulation, route construction, or collision shapes.
const LOGICAL_SIZE=Vector2(1280,720)
const AIRLOCK_ANCHOR=Vector2(244,392)
const AIRLOCK_RADIUS=64.0
const SKY=preload("res://assets/2d_v5/moon/far-sky-clamped.png")
const REGOLITH=preload("res://assets/2d_v5/moon/regolith-decorative-wrap.png")
const AIRLOCK=preload("res://assets/2d_v5/moon/airlock-pixel.png")
const SHADER=preload("res://assets/2d_v5/moon/moon_background.gdshader")
const MAX_HARDWARE=14
var reduced_motion=false
var motion_blur_enabled=true
var show_hardware_audit=false # Explicit QA only; ordinary gameplay stays clean.
var _enabled=false
var _scene_visible=false
var _ready_complete=false
var _far:Sprite2D
var _terrain:Sprite2D
var _props:Node2D
var _airlock:Sprite2D
var _cue:HardwareCues
var _registered:Dictionary={}
var _route:Dictionary={}
var _origin=Vector2.ZERO
var _cell=72.0
var _position=Vector2.ZERO
var _camera=Vector2.ZERO
var _velocity=Vector2.ZERO
var _motion=Vector2.ZERO
var _zoom=.15
var _have_sample=false
var _paused=false
var _weight=0.0
var _blur=0.0
var _far_scroll=Vector2.ZERO
var _terrain_scroll=Vector2.ZERO
var _last_frame:Dictionary={}

class HardwareCues extends Node2D:
 var circles:Array=[]
 var cargo=Vector2.ZERO
 var zoom=.1
 var track=false
 var audit=false
 func _draw() -> void:
  if track:
   var radius=22.0/maxf(.001,zoom);var tick=6.0/maxf(.001,zoom)
   for side in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
    var at=cargo+side*radius
    draw_line(at,at-Vector2(side.x*tick,0),Color(.55,.96,1,.8),1.0/maxf(.001,zoom),false)
    draw_line(at,at-Vector2(0,side.y*tick),Color(.55,.96,1,.8),1.0/maxf(.001,zoom),false)
  if not audit:return
  for circle in circles:
   draw_arc(circle.position,circle.radius,0,TAU,40,Color(1,.76,.36,.30),3,false)

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false);set_physics_process(false)
 _far=_plane("SingleClampedEarth",SKY,false)
 _terrain=_plane("DistantDecorativeRegolith",REGOLITH,true)
 _terrain.modulate=Color(.62,.65,.80,.78)
 _terrain.material.set_shader_parameter("saturation",.48)
 _ready_complete=true;_refresh()

func _plane(label:String,texture:Texture2D,repeat_x:bool) -> Sprite2D:
 var node=Sprite2D.new();node.name=label;node.centered=false;node.texture=texture
 node.scale=LOGICAL_SIZE/Vector2(texture.get_size());node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var material=ShaderMaterial.new();material.shader=SHADER
 material.set_shader_parameter("repeat_x",repeat_x)
 material.set_shader_parameter("terrain",repeat_x)
 node.material=material;add_child(node);return node

static func _number(value:Variant) -> bool:
 return (value is float or value is int) and is_finite(float(value))
static func _pair(value:Variant) -> bool:
 return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])
static func accepts_route(route:Dictionary) -> bool:
 if str(route.get("control_version",""))!="pilot-v3" or str(route.get("route_profile",""))!="moon-surface-v1" or str(route.get("route_kind",""))!="moon" or str(route.get("destination_id",""))!="moon-regolith-airlock" or route.get("moon_schema")!=1:return false
 if not route.get("moon_receiver") is Dictionary:return false
 var receiver:Dictionary=route.moon_receiver
 for key in ["distance","destination_y","delivery_radius","moon_approach_start","moon_clear_approach_start","moon_surface_y"]:
  if not _number(route.get(key)):return false
 if float(route.delivery_radius)<=0 or float(route.delivery_radius)>100:return false
 if float(route.moon_approach_start)>=float(route.moon_clear_approach_start) or float(route.moon_clear_approach_start)>=float(route.distance):return false
 if str(receiver.get("art_profile",""))!="moon-airlock-pixel-v1" or str(receiver.get("entrance_side",""))!="left":return false
 if not _pair(receiver.get("capture_anchor_native")) or Vector2(receiver.capture_anchor_native[0],receiver.capture_anchor_native[1])!=AIRLOCK_ANCHOR:return false
 if not _number(receiver.get("meters_per_native_pixel")) or not is_equal_approx(float(receiver.meters_per_native_pixel),float(route.delivery_radius)/AIRLOCK_RADIUS):return false
 if not receiver.get("hardware_hazard_ids") is Array or receiver.hardware_hazard_ids.size()>MAX_HARDWARE:return false
 return true

func configure_route(route:Dictionary,world_parent:Node2D,origin:Vector2,cell:float,actual_hazards:Array=[]) -> bool:
 leave_flight()
 if not accepts_route(route) or not is_instance_valid(world_parent) or not origin.is_finite() or not is_finite(cell) or cell<=0 or cell>10000:return false
 _enabled=true;_scene_visible=true;_route=route.duplicate(true);_origin=origin;_cell=cell
 _props=Node2D.new();_props.name="SourceRegisteredMoonAirlock";_props.z_index=-3;world_parent.add_child(_props)
 _airlock=Sprite2D.new();_airlock.texture=AIRLOCK;_airlock.centered=false;_airlock.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _airlock.scale=Vector2.ONE*cell*float(route.delivery_radius)/AIRLOCK_RADIUS
 _airlock.position=origin+Vector2(route.distance,route.destination_y)*cell-AIRLOCK_ANCHOR*_airlock.scale
 _airlock.set_meta("capture_anchor_native",AIRLOCK_ANCHOR);_airlock.set_meta("surface_y",float(route.moon_surface_y));_airlock.set_meta("generated_raster",true)
 _props.add_child(_airlock)
 _cue=HardwareCues.new();_cue.name="ActualAirlockCircleCues";_cue.z_index=4;_props.add_child(_cue)
 # Suppress a rock only if the saved ID, source circle, position and radius
 # all match this exact source registration. Unknown or moved hazards survive.
 for index in actual_hazards.size():
  var h:Dictionary=actual_hazards[index]
  if str(h.get("id","")) not in route.moon_receiver.hardware_hazard_ids or str(h.get("moon_role",""))!="airlock":continue
  var native:Variant=h.get("source_circle_native")
  if not native is Array or native.size()!=3 or not _number(native[0]) or not _number(native[1]) or not _number(native[2]):continue
  var expected=Vector2(route.distance,route.destination_y)+(Vector2(native[0],native[1])-AIRLOCK_ANCHOR)*float(route.delivery_radius)/AIRLOCK_RADIUS
  if h.position.distance_to(expected)>.001 or absf(float(h.radius)-float(native[2])*float(route.delivery_radius)/AIRLOCK_RADIUS)>.001:continue
  _registered[index]={"id":str(h.id),"position":expected,"radius":float(h.radius)}
 update_hardware(actual_hazards);_refresh();return true

func update_hardware(hazards:Array) -> void:
 if not _enabled:return
 _cue.circles.clear()
 for index in _registered.keys():
  var saved:Dictionary=_registered[index]
  if index>=hazards.size():_registered.erase(index);continue
  var h:Dictionary=hazards[index]
  if str(h.get("id",""))!=saved.id or h.position.distance_to(saved.position)>.001 or absf(float(h.radius)-saved.radius)>.001 or float(h.health)<=0:
   _registered.erase(index);continue
  _cue.circles.append({"position":_origin+h.position*_cell,"radius":float(h.radius)*_cell})
 _cue.queue_redraw()

func suppresses_hazard(index:int) -> bool:return _enabled and _registered.has(index)
func route_enabled() -> bool:return _enabled
func receiver_node() -> Sprite2D:return _airlock if is_instance_valid(_airlock) else null
func moon_weight() -> float:return _weight
func set_scene_visible(active:bool) -> void:
 _scene_visible=active;_refresh()

func update_view(position_m:Vector2,velocity_mps:Vector2,camera_m:Vector2,zoom:float,paused:bool=false) -> void:
 if not _enabled or not position_m.is_finite() or not velocity_mps.is_finite() or not camera_m.is_finite() or not is_finite(zoom) or zoom<=0:return
 _paused=paused
 if paused and _have_sample:
  _motion=Vector2.ZERO;_refresh();return
 if not _have_sample or paused or velocity_mps==Vector2.ZERO:_motion=Vector2.ZERO
 elif camera_m!=_camera or position_m!=_position:
  var camera_delta=camera_m-_camera;var cargo_delta=position_m-_position
  _motion=camera_delta.normalized()*minf(100.0,velocity_mps.length())*clampf(camera_delta.length()/maxf(.0001,cargo_delta.length()),0,1)
 _position=position_m;_velocity=velocity_mps;_camera=camera_m;_zoom=zoom;_have_sample=true
 # Actual reversible progress, not elapsed time or a launch/restart event.
 _weight=smoothstep(float(_route.moon_approach_start),float(_route.moon_approach_start)+70.0,position_m.x)
 _refresh()

func camera_target(cargo:Vector2,velocity:Vector2,hazards:Array,status:String="running") -> Dictionary:
 if not _enabled:return {}
 if status=="success":
  _last_frame={"center":_origin+(Vector2(_route.distance,_route.destination_y)+Vector2(10,1))*_cell,"zoom":.22,"forward_m":0.0,"receipt":true}
  return _last_frame.duplicate()
 var forward=maxf(80.0,minf(100000.0,velocity.length())*3.5)
 var left=cargo.x-8.0;var right=cargo.x+forward;var selection_right=right
 var top=cargo.y-6.0;var bottom=cargo.y+6.0
 for h in hazards:
  if float(h.health)<=0:continue
  if h.position.x+float(h.radius)<left or h.position.x-float(h.radius)>selection_right:continue
  top=minf(top,h.position.y-float(h.radius)-6.0);bottom=maxf(bottom,h.position.y+float(h.radius)+6.0)
  right=maxf(right,h.position.x+float(h.radius)+6.0)
 # x300..1240 stays clear of left cue; y150..570 clears top/right HUD and
 # the bottom event/controls band. Include complete circles, never just centers.
 var zoom=minf(.17,minf(940.0/((right-cargo.x)*_cell),420.0/maxf(1.0,(bottom-top)*_cell)))
 var center_x=cargo.x+(640.0-300.0)/(zoom*_cell)
 var center_y=(top+bottom)*.5
 _last_frame={"center":_origin+Vector2(center_x,center_y)*_cell,"zoom":zoom,"forward_m":forward,"bounds":Rect2(Vector2(left,top),Vector2(right-left,bottom-top)),"receipt":false}
 return _last_frame.duplicate()

static func wrapped_offset(meters:float,ppm:float,extent:float=1280.0) -> float:
 if not is_finite(meters) or not is_finite(ppm) or not is_finite(extent) or ppm<=0 or extent<=0:return 0.0
 return fposmod(round(fposmod(meters,extent/ppm)*ppm/2.0)*2.0,extent)

func _refresh() -> void:
 visible=_enabled and _scene_visible and _weight>0
 if is_instance_valid(_props):_props.visible=_enabled and _scene_visible
 if is_instance_valid(_cue):
  _cue.cargo=_origin+_position*_cell;_cue.zoom=_zoom;_cue.track=_weight>0.0;_cue.audit=show_hardware_audit;_cue.queue_redraw()
 if not _ready_complete:return
 _far.modulate.a=_weight;_terrain.modulate.a=.78*_weight
 # One nonrepeating cover plate: drift is clamped to its overscan coverage.
 # Slow drift uses actual camera coordinates; there is no autonomous clock.
 _far_scroll=Vector2(-78.0+clampf((_camera.x-560.0)*.025,-8,8),clampf((_camera.y+150.0)*.05,-8,8))
 _far.material.set_shader_parameter("scroll_px",_far_scroll)
 # Distant horizontal parallax, an authored low silhouette, and a ground
 # reference derived from the saved surface. This is decoration, no floor.
 _terrain_scroll=Vector2(wrapped_offset(_camera.x-560.0,2.4),0)
 var surface_screen=minf(740.0,360.0+(float(_route.get("moon_surface_y",-91.8125))-_camera.y)*_cell*_zoom)
 _terrain.material.set_shader_parameter("surface_y_px",surface_screen)
 _terrain.material.set_shader_parameter("scroll_px",_terrain_scroll)
 _blur=0.0
 if _enabled and not _paused and motion_blur_enabled and not reduced_motion:_blur=10.0*smoothstep(12,24,_motion.length())
 var direction=_motion.normalized() if _motion.length_squared()>.0001 else Vector2.ZERO
 _far.material.set_shader_parameter("blur_delta_px",direction*_blur*.08)
 _terrain.material.set_shader_parameter("blur_delta_px",direction*_blur)

func debug_snapshot() -> Dictionary:
 return {"enabled":_enabled,"visible":visible,"moon_weight":_weight,"position":_position,"camera":_camera,"blur":_blur,"far_scroll":_far_scroll,"terrain_scroll":_terrain_scroll,"paused":_paused,"planes":get_child_count(),"props":_props.get_child_count() if is_instance_valid(_props) else 0,"registered_hardware":_registered.size(),"frame":_last_frame.duplicate(true),"earth_instances":1 if _enabled else 0}

func leave_flight() -> void:
 if is_instance_valid(_props):_props.free()
 _props=null;_airlock=null;_cue=null;_registered.clear();_route.clear();_last_frame.clear()
 _enabled=false;_scene_visible=false;_position=Vector2.ZERO;_camera=Vector2.ZERO;_velocity=Vector2.ZERO;_motion=Vector2.ZERO;_weight=0;_blur=0;_have_sample=false;_paused=false
 _refresh()
func _exit_tree() -> void:leave_flight()
