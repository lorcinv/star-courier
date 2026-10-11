extends Node2D
## Presentation only. No simulation mutation, collisions, route construction,
## clocks, autonomous motion, entry flash, or replay of old transit effects.
## Parent under WorldView's screen-space background_root. World props are
## independently parented under flight_root; leave_flight() releases them.
signal camera_cut_requested(restored:bool)
signal biome_changed(phase:String,restored:bool)

const BirdProfile=preload("res://scripts/pilot_protected_bird_profile.gd")
const CONTROL_VERSION:String="pilot-v4-wormhole"
const ROUTE_PROFILE:String="wormhole-otherworld-v1"
const LOGICAL_SIZE:Vector2=Vector2(1280,720)
const SOURCE_SIZE:Vector2=Vector2(1280,640)
const PIXEL_GRID:float=2.0
const MAX_BLUR_PX:float=12.0
const REFERENCE_ZOOM:float=0.30
const FAR_DEPTH:float=0.05
const ISLAND_DEPTH:float=0.16
const PORTAL_ANCHOR:Vector2=Vector2(48,264)
const PORTAL_CONTENT_HALF_HEIGHT:float=262.0
const CAP_ANCHOR:Vector2=Vector2(96,96)
const CAP_RADIUS:float=93.0
const MAX_HARDWARE:int=32
const RECEIVER_ANCHOR:Vector2=Vector2(167,307)
const RECEIVER_EMPTY_RADIUS:float=59.0
const RECEIVER_MOUTH:Rect2=Rect2(64,248,204,124)
const RECEIVER_DECK:Vector2=Vector2(166,388)
const BACKGROUND_SHADER=preload("res://assets/2d_v5/otherworld/otherworld_background.gdshader")
const FAR_TEXTURE=preload("res://assets/2d_v5/otherworld/far-world-wrap.png")
const ISLAND_TEXTURE=preload("res://assets/2d_v5/otherworld/decorative-island-band.png")
const PORTAL_TEXTURE=preload("res://assets/2d_v5/wormhole/portal-energy-plane.png")
const TOP_CAP_TEXTURE=preload("res://assets/2d_v5/wormhole/portal-top-cap.png")
const BOTTOM_CAP_TEXTURE=preload("res://assets/2d_v5/wormhole/portal-bottom-cap.png")
const RECEIVER_TEXTURE=preload("res://assets/2d_v5/otherworld/receiver-pixel.png")

var reduced_motion:bool=false:
 set(value):
  if reduced_motion==value:return
  reduced_motion=value
  _refresh()
var motion_blur_enabled:bool=true:
 set(value):
  if motion_blur_enabled==value:return
  motion_blur_enabled=value
  _refresh()
var _far:Sprite2D
var _islands:Sprite2D
var _far_material:ShaderMaterial
var _island_material:ShaderMaterial
var _props:Node2D
var _entry_sprite:Sprite2D
var _exit_sprite:Sprite2D
var _receiver_sprite:Sprite2D
var _enabled:bool=false
var _accepted_control_version:String=CONTROL_VERSION
var _scene_visible:bool=false
var _phase:String=""
var _ready_complete:bool=false
var _entry_m:Vector2=Vector2.ZERO
var _exit_m:Vector2=Vector2.ZERO
var _destination_m:Vector2=Vector2.ZERO
var _aperture_m:float=13.0
var _capture_m:float=9.0
var _origin:Vector2=Vector2.ZERO
var _cell:float=72.0
var _position_m:Vector2=Vector2.ZERO
var _camera_m:Vector2=Vector2.ZERO
var _velocity_mps:Vector2=Vector2.ZERO
var _motion_mps:Vector2=Vector2.ZERO
var _have_sample:bool=false
var _pending_sample_reset:bool=true
var _paused:bool=false
var _blur_pixels:float=0.0
var _far_scroll:Vector2=Vector2.ZERO
var _island_scroll:Vector2=Vector2.ZERO
var _live_transitions:int=0
var _last_cut_restored:bool=false
var _hardware:Dictionary={}
var _portal_records:Array=[]
var _transit_strength:float=0.0

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false);set_physics_process(false)
 _far=_make_plane("GeneratedOtherworldFar",FAR_TEXTURE,false)
 _far_material=_far.material as ShaderMaterial
 _islands=_make_plane("GeneratedDistantIslandDecoration",ISLAND_TEXTURE,true)
 _island_material=_islands.material as ShaderMaterial
 _island_material.set_shader_parameter("saturation",0.45)
 _islands.modulate=Color(0.68,0.72,0.88,0.50)
 _ready_complete=true
 _refresh()

func _make_plane(label:String,paint:Texture2D,repeat_y:bool) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new()
 node.name=label;node.texture=paint;node.centered=false
 # Geometry covers the canonical viewport. The shader samples a uniform
 # cover crop, preserving authored aspect ratio on a fixed 2px output grid.
 node.scale=LOGICAL_SIZE/Vector2(paint.get_size())
 node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var material:ShaderMaterial=ShaderMaterial.new()
 material.shader=BACKGROUND_SHADER
 material.set_shader_parameter("source_size_px",Vector2(paint.get_size()))
 material.set_shader_parameter("logical_size_px",LOGICAL_SIZE)
 material.set_shader_parameter("pixel_grid_px",PIXEL_GRID)
 material.set_shader_parameter("repeat_y",repeat_y)
 node.material=material;add_child(node)
 return node

static func accepts_route(route:Dictionary) -> bool:
 # This identifies the supported protocol only. It never selects the biome.
 if BirdProfile.same_value(route.get("control_version"),BirdProfile.CONTROL_VERSION):
  return BirdProfile.validation_error(route).is_empty()
 if str(route.get("control_version",""))!=CONTROL_VERSION or str(route.get("route_profile",""))!=ROUTE_PROFILE:return false
 if route.get("wormhole_schema")!=1 or not route.get("wormhole_portal") is Dictionary:return false
 var portal:Dictionary=route.wormhole_portal
 if not _pair(portal.get("entry")) or not _pair(portal.get("exit")):return false
 for key in ["distance","destination_y","delivery_radius"]:
  if not _number(route.get(key)):return false
 if not _number(portal.get("aperture_radius")):return false
 return float(route.delivery_radius)>0.0 and float(route.delivery_radius)<=1000.0 and float(portal.aperture_radius)>0.0 and float(portal.aperture_radius)<=64.0

static func _number(value:Variant) -> bool:
 return (value is float or value is int) and is_finite(float(value))

static func _pair(value:Variant) -> bool:
 return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])

func configure_route(route:Dictionary,world_parent:Node2D,new_origin:Vector2,new_cell:float,actual_hazards:Array=[]) -> bool:
 leave_flight()
 if not accepts_route(route) or not is_instance_valid(world_parent) or not new_origin.is_finite() or not is_finite(new_cell) or new_cell<=0.0 or new_cell>10000.0:return false
 # Read the saved geometry exactly. Never reconstruct a default profile.
 var portal:Dictionary=route.wormhole_portal
 _entry_m=Vector2(float(portal.entry[0]),float(portal.entry[1]))
 _exit_m=Vector2(float(portal.exit[0]),float(portal.exit[1]))
 _destination_m=Vector2(float(route.distance),float(route.destination_y))
 _aperture_m=float(portal.aperture_radius);_capture_m=float(route.delivery_radius)
 _origin=new_origin;_cell=new_cell
 _accepted_control_version=str(route.control_version)
 _enabled=true;_scene_visible=true
 _props=Node2D.new();_props.name="GeneratedRegisteredWormholeProps";_props.z_index=-3
 world_parent.add_child(_props)
 _entry_sprite=_registered_sprite("GeneratedEntryPortal",PORTAL_TEXTURE,_entry_m,PORTAL_ANCHOR,_aperture_m/PORTAL_CONTENT_HALF_HEIGHT)
 _exit_sprite=_registered_sprite("GeneratedExitPortal",PORTAL_TEXTURE,_exit_m,PORTAL_ANCHOR,_aperture_m/PORTAL_CONTENT_HALF_HEIGHT)
 _receiver_sprite=_registered_sprite("GeneratedOtherworldReceiver",RECEIVER_TEXTURE,_destination_m,RECEIVER_ANCHOR,_capture_m/RECEIVER_EMPTY_RADIUS)
 _entry_sprite.set_meta("aperture_radius_m",_aperture_m)
 _exit_sprite.set_meta("aperture_radius_m",_aperture_m)
 _receiver_sprite.set_meta("capture_radius_m",_capture_m)
 _receiver_sprite.set_meta("mouth_native",RECEIVER_MOUTH)
 _receiver_sprite.set_meta("deck_reference_native",RECEIVER_DECK)
 _portal_records=[{"sprite":_entry_sprite,"center":_entry_m,"top":-1,"bottom":-1},{"sprite":_exit_sprite,"center":_exit_m,"top":-1,"bottom":-1}]
 _configure_hardware(actual_hazards)
 update_hardware(actual_hazards)
 _refresh()
 return true

func _registered_sprite(label:String,paint:Texture2D,anchor_m:Vector2,native_anchor:Vector2,meters_per_texel:float) -> Sprite2D:
 var sprite:Sprite2D=Sprite2D.new()
 sprite.name=label;sprite.texture=paint;sprite.centered=false
 sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 sprite.scale=Vector2.ONE*_cell*meters_per_texel
 # Do not round these offsets: that would move the real measured hole away
 # from the trigger. WorldView already snaps the camera to its pixel grid.
 sprite.position=_origin+anchor_m*_cell-native_anchor*sprite.scale
 sprite.set_meta("registered_world_center_m",anchor_m)
 sprite.set_meta("registered_native_anchor",native_anchor)
 sprite.set_meta("generated_raster",true)
 _props.add_child(sprite)
 return sprite

func _configure_hardware(actual_hazards:Array) -> void:
 # Saved physical hazards own the hardware, including varied/custom geometry.
 # No cap is invented for a route that contains only a free energy aperture.
 for index in actual_hazards.size():
  if _hardware.size()>=MAX_HARDWARE:break
  var hazard:Dictionary=actual_hazards[index]
  if not bool(hazard.get("wormhole_hardware",false)):continue
  var at:Vector2=hazard.get("position",Vector2.ZERO)
  var record:Dictionary=_portal_records[0 if absf(at.x-_entry_m.x)<=absf(at.x-_exit_m.x) else 1]
  var top:bool=at.y<float(record.center.y)
  var cap:Sprite2D=Sprite2D.new();cap.name="PhysicalPortalCap"+str(index)
  cap.texture=TOP_CAP_TEXTURE if top else BOTTOM_CAP_TEXTURE;cap.centered=false;cap.offset=-CAP_ANCHOR
  cap.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  cap.set_meta("physical_hazard_index",index);cap.set_meta("registered_native_anchor",CAP_ANCHOR);cap.set_meta("registered_native_radius",CAP_RADIUS)
  record.sprite.add_child(cap);_hardware[index]=cap
  var key:String="top" if top else "bottom"
  if int(record[key])<0 or absf(at.y-record.center.y)<absf(float(actual_hazards[int(record[key])].position.y)-record.center.y):record[key]=index

func update_hardware(actual_hazards:Array) -> void:
 if not _enabled:return
 # Energy spans only between the authored emitters. Cap sprites independently
 # retain each actual circle's position/radius; neither physics nor hull moves.
 for record in _portal_records:
  var top_y:float=float(record.center.y)-_aperture_m
  var bottom_y:float=float(record.center.y)+_aperture_m
  if int(record.top)>=0 and int(record.top)<actual_hazards.size():
   var top:Dictionary=actual_hazards[int(record.top)]
   top_y=float(top.position.y)+float(top.radius)*72.0/CAP_RADIUS
  if int(record.bottom)>=0 and int(record.bottom)<actual_hazards.size():
   var bottom:Dictionary=actual_hazards[int(record.bottom)]
   bottom_y=float(bottom.position.y)-float(bottom.radius)*74.0/CAP_RADIUS
  if bottom_y<=top_y:top_y=float(record.center.y)-_aperture_m;bottom_y=float(record.center.y)+_aperture_m
  var energy:Sprite2D=record.sprite
  energy.scale=Vector2(_cell*_aperture_m/13.0*5.0/CAP_RADIUS,_cell*(bottom_y-top_y)/(PORTAL_CONTENT_HALF_HEIGHT*2.0))
  var middle:Vector2=Vector2(record.center.x,(top_y+bottom_y)*.5)
  energy.position=_origin+middle*_cell-PORTAL_ANCHOR*energy.scale
  energy.set_meta("registered_world_center_m",record.center)
  energy.set_meta("content_endpoints_m",[Vector2(record.center.x,top_y),Vector2(record.center.x,bottom_y)])
 for index in _hardware:
  var cap:Sprite2D=_hardware[index]
  if int(index)>=actual_hazards.size():cap.hide();continue
  var hazard:Dictionary=actual_hazards[int(index)];var energy:Sprite2D=cap.get_parent()
  cap.position=(_origin+hazard.position*_cell-energy.position)/energy.scale
  cap.scale=Vector2.ONE*_cell*float(hazard.radius)/CAP_RADIUS/energy.scale
  cap.visible=float(hazard.health)>0.0
  cap.set_meta("registered_world_center_m",hazard.position);cap.set_meta("physical_radius_m",float(hazard.radius))

func hardware_node(index:int) -> Sprite2D:
 return _hardware.get(index)

func set_transit_strength(strength:float) -> void:
 _transit_strength=clampf(strength,0.0,1.0) if is_finite(strength) else 0.0
 _refresh()

func sync_telemetry(telemetry:Dictionary,restoring:bool=false) -> bool:
 if not _enabled:return false
 if _accepted_control_version==BirdProfile.CONTROL_VERSION and not BirdProfile.same_value(telemetry.get("control_version"),_accepted_control_version):return false
 if str(telemetry.get("control_version",_accepted_control_version))!=_accepted_control_version:return false
 var next:String=str(telemetry.get("wormhole_phase",""))
 if next not in ["ascent","space","otherworld"]:return false
 if next==_phase:return false
 var was_otherworld:bool=_phase=="otherworld"
 var first_sample:bool=_phase.is_empty()
 var restored:bool=restoring or first_sample
 _phase=next
 var cut:bool=was_otherworld!=(_phase=="otherworld")
 if cut:
  _pending_sample_reset=true;_have_sample=false;_motion_mps=Vector2.ZERO
  _last_cut_restored=restored
  if not restored and _phase=="otherworld":_live_transitions+=1
 _refresh()
 biome_changed.emit(_phase,restored)
 if cut:camera_cut_requested.emit(restored)
 return cut

func route_enabled() -> bool:return _enabled
func otherworld_active() -> bool:return _enabled and _phase=="otherworld"
func receiver_node() -> Sprite2D:return _receiver_sprite if is_instance_valid(_receiver_sprite) else null

func set_scene_visible(active:bool) -> void:
 _scene_visible=active
 _refresh()

func reset_camera_sample(position_m:Vector2,camera_position_m:Vector2) -> void:
 # Call after WorldView has snapped to the exit-side target, never before.
 if not position_m.is_finite() or not camera_position_m.is_finite():return
 _position_m=position_m;_camera_m=camera_position_m
 _velocity_mps=Vector2.ZERO;_motion_mps=Vector2.ZERO
 _have_sample=true;_pending_sample_reset=false
 _refresh()

func update_view(position_m:Vector2,velocity_mps:Vector2,camera_position_m:Vector2,paused:bool=false) -> void:
 if not otherworld_active():return
 if not position_m.is_finite() or not velocity_mps.is_finite() or not camera_position_m.is_finite():return
 _paused=paused
 if paused and _have_sample and not _pending_sample_reset:
  # An already sampled paused view is a freeze. Restore's pending reset can
  # still establish the correct exit-side image on its first frame.
  _velocity_mps=Vector2.ZERO;_motion_mps=Vector2.ZERO;_refresh();return
 var safe_velocity:Vector2=velocity_mps.clamp(Vector2(-1000000,-1000000),Vector2(1000000,1000000))
 if _pending_sample_reset or not _have_sample:
  _motion_mps=Vector2.ZERO;_pending_sample_reset=false
 elif paused or safe_velocity==Vector2.ZERO:
  _motion_mps=Vector2.ZERO
 elif position_m!=_position_m or camera_position_m!=_camera_m:
  var camera_delta:Vector2=(camera_position_m-_camera_m).clamp(Vector2(-1000000,-1000000),Vector2(1000000,1000000))
  var cargo_delta:Vector2=(position_m-_position_m).clamp(Vector2(-1000000,-1000000),Vector2(1000000,1000000))
  _motion_mps=camera_delta.normalized()*safe_velocity.length()*clampf(camera_delta.length()/maxf(cargo_delta.length(),0.0001),0.0,1.0)
 elif safe_velocity!=_velocity_mps:
  _motion_mps=_motion_mps.normalized()*safe_velocity.length()
 _position_m=position_m;_camera_m=camera_position_m;_velocity_mps=safe_velocity
 _have_sample=true
 _refresh()

static func ordinary_coordinate(pixel:float,extent:float) -> float:
 return fposmod(pixel,extent) if is_finite(pixel) and is_finite(extent) and extent>0.0 else 0.0

static func wrapped_offset(meters:float,ppm:float,extent:float) -> float:
 if not is_finite(meters) or not is_finite(ppm) or not is_finite(extent) or ppm<=0.0 or extent<=0.0:return 0.0
 # Reduce before multiplying, and snap only the bounded result. No reflected
 # alternating tile, direction-dependent flip, or growing coordinate ever.
 return fposmod(round(fposmod(meters,extent/ppm)*ppm/PIXEL_GRID)*PIXEL_GRID,extent)

func _refresh() -> void:
 visible=_enabled and _scene_visible and _phase=="otherworld"
 if is_instance_valid(_props):
  _props.visible=_enabled and _scene_visible
  _entry_sprite.visible=_phase!="otherworld"
  _exit_sprite.visible=_phase=="otherworld"
  _receiver_sprite.visible=_phase=="otherworld"
  _entry_sprite.self_modulate=Color(1,1,1,.76)
  var pulse:float=0.0 if reduced_motion else _transit_strength
  _exit_sprite.self_modulate=Color(1.0+pulse*.18,1.0+pulse*.18,1.0+pulse*.18,.76+pulse*.24)
 if not _ready_complete:return
 var relative_camera:Vector2=_camera_m-_exit_m
 var far_ppm:float=_cell*REFERENCE_ZOOM*FAR_DEPTH
 var island_ppm:float=_cell*REFERENCE_ZOOM*ISLAND_DEPTH
 _far_scroll=Vector2(wrapped_offset(relative_camera.x,far_ppm,SOURCE_SIZE.x),round(clampf(relative_camera.y*far_ppm,-96.0,96.0)/PIXEL_GRID)*PIXEL_GRID)
 _island_scroll=Vector2(wrapped_offset(relative_camera.x,island_ppm,SOURCE_SIZE.x),wrapped_offset(relative_camera.y,island_ppm,SOURCE_SIZE.y))
 _far_material.set_shader_parameter("scroll_px",_far_scroll)
 _island_material.set_shader_parameter("scroll_px",_island_scroll)
 _blur_pixels=0.0
 if otherworld_active() and not _paused and motion_blur_enabled and not reduced_motion and not _pending_sample_reset:
  _blur_pixels=MAX_BLUR_PX*smoothstep(12.0,24.0,_motion_mps.length())
 var direction:Vector2=_motion_mps.normalized() if _motion_mps.length_squared()>0.0001 else Vector2.ZERO
 _far_material.set_shader_parameter("blur_delta_px",direction*_blur_pixels*0.20)
 _island_material.set_shader_parameter("blur_delta_px",direction*_blur_pixels)

func leave_flight() -> void:
 if is_instance_valid(_props):
  if not _props.is_queued_for_deletion():_props.free()
 _props=null;_entry_sprite=null;_exit_sprite=null;_receiver_sprite=null
 _hardware.clear();_portal_records.clear();_transit_strength=0.0
 _enabled=false;_scene_visible=false;_phase=""
 _accepted_control_version=CONTROL_VERSION
 _entry_m=Vector2.ZERO;_exit_m=Vector2.ZERO;_destination_m=Vector2.ZERO
 _aperture_m=13.0;_capture_m=9.0;_origin=Vector2.ZERO;_cell=72.0
 _position_m=Vector2.ZERO;_camera_m=Vector2.ZERO
 _velocity_mps=Vector2.ZERO;_motion_mps=Vector2.ZERO
 _have_sample=false;_pending_sample_reset=true;_paused=false
 _live_transitions=0;_last_cut_restored=false
 _refresh()

func debug_snapshot() -> Dictionary:
 # New values only, no mutable route, node, material, or simulation reference.
 return {"enabled":_enabled,"phase":_phase,"otherworld_active":otherworld_active(),"visible":visible,
 "entry_m":_entry_m,"exit_m":_exit_m,"destination_m":_destination_m,"aperture_m":_aperture_m,"capture_m":_capture_m,
 "portal_anchor_native":PORTAL_ANCHOR,"receiver_anchor_native":RECEIVER_ANCHOR,"receiver_mouth_native":RECEIVER_MOUTH,
 "camera_m":_camera_m,"relative_camera_m":_camera_m-_exit_m,"position_m":_position_m,"motion_mps":_motion_mps,
 "pending_sample_reset":_pending_sample_reset,"paused":_paused,"blur_pixels":_blur_pixels,
 "far_scroll":_far_scroll,"island_scroll":_island_scroll,"live_transitions":_live_transitions,"last_cut_restored":_last_cut_restored,
 "plane_nodes":get_child_count(),"prop_nodes":_props.get_child_count() if is_instance_valid(_props) else 0,
 "hardware_nodes":_hardware.size(),"transit_strength":0.0 if reduced_motion else _transit_strength,
 "far_blur":_far_material.get_shader_parameter("blur_delta_px") if _ready_complete else Vector2.ZERO,
 "island_blur":_island_material.get_shader_parameter("blur_delta_px") if _ready_complete else Vector2.ZERO,
 "pixel_grid":PIXEL_GRID,"island_opacity":0.50,"island_saturation":0.45,"island_depth":ISLAND_DEPTH,"reference_zoom":REFERENCE_ZOOM}

func _exit_tree() -> void:
 leave_flight()
