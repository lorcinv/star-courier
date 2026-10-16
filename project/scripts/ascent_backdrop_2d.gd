extends Node2D
## Seven independent generated raster layers in canonical screen space.
## Parent under CanvasLayer; pass the camera center in simulation metres, relative
## to its departure center. Negative camera Y means climbing. Actual cargo altitude
## chooses the atmospheric stage; horizontal route progress cannot unlock orbit.
## No _process, timer, randomization, tween, per-frame node/material/array creation.
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
const GROUND_TEXTURE=preload("res://assets/2d_v5/ground/near-city-strip.png")
const GROUND_PPM:Vector2=Vector2(14.0,2.0)
const GROUND_Y_OFFSET:float=-192.0
const LOGICAL_SIZE:Vector2=Vector2(1280,720)
const MAX_BLUR_PX:float=24.0
const PLANE_COUNT:int=7
const BACKGROUND_SHADER=preload("res://assets/2d_v5/ascent_background.gdshader")
const SKY_TEXTURE=preload("res://assets/2d_v5/ascent/atmosphere-tall.png")
const CITY_TEXTURE=preload("res://assets/2d_v5/ascent/far-city-band.png")
const CLOUD_TEXTURE=preload("res://assets/2d_v5/ascent/cloud-banks.png")
const WISP_TEXTURE=preload("res://assets/2d_v5/ascent/cloud-wisps.png")
const DUST_TEXTURE=preload("res://assets/2d_v5/ascent/orbit-dust.png")
const STAR_TEXTURE=preload("res://assets/2d_v5/ascent/orbit-stars.png")
const PLANET_TEXTURE=preload("res://assets/2d_v5/ascent/planet-limb.png")
const CITY_PPM:Vector2=Vector2(4.0,5.0)
const CLOUD_PPM:Vector2=Vector2(8.0,9.0)
const WISP_PPM:Vector2=Vector2(18.0,20.0)
const DUST_PPM:Vector2=Vector2(16.0,18.0)
const STAR_PPM:Vector2=Vector2(0.5,0.6)
const SKY_PPM:Vector2=Vector2(0.6,12.5)

var reduced_motion:bool=false:
 set(value):
  reduced_motion=value
  _refresh()
var motion_blur_enabled:bool=true:
 set(value):
  motion_blur_enabled=value
  _refresh()
var atmosphere:Sprite2D
var starfield:Sprite2D
var planet:Sprite2D
var city:Sprite2D
var clouds:Sprite2D
var wisps:Sprite2D
var orbit_dust:Sprite2D
var near_city:Sprite2D
var _ground_material:ShaderMaterial
var _ground_route:bool=false
var _dust_material:ShaderMaterial
var _sky_material:ShaderMaterial
var _star_material:ShaderMaterial
var _planet_material:ShaderMaterial
var _city_material:ShaderMaterial
var _cloud_material:ShaderMaterial
var _wisp_material:ShaderMaterial
var _position_m:Vector2=Vector2.ZERO
var _velocity_mps:Vector2=Vector2.ZERO
var _camera_position_m:Vector2=Vector2.ZERO
var _motion_velocity_mps:Vector2=Vector2.ZERO
var _have_camera_sample:bool=false
var _progress:float=0.0
var _route_kind:String="city_to_orbit"
var _ground_y_m:float=0.0
var _orbit_begin_m:float=85.0
var _orbit_full_m:float=135.0
var _cloud_top_m:float=120.0
var _blur_start_mps:float=10.0
var _blur_full_mps:float=22.0
var _altitude_m:float=0.0
var _orbit_weight:float=0.0
var _cloud_weight:float=1.0
var _blur_pixels:float=0.0
var _ready_complete:bool=false

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false)
 atmosphere=_make_plane("GeneratedTallAtmosphere",SKY_TEXTURE,true,false,true)
 _sky_material=atmosphere.material as ShaderMaterial
 starfield=_make_plane("GeneratedOrdinaryStarTile",STAR_TEXTURE,true,true)
 _star_material=starfield.material as ShaderMaterial
 planet=_make_plane("GeneratedDistantPlanetLimb",PLANET_TEXTURE,false,false)
 _planet_material=planet.material as ShaderMaterial
 city=_make_plane("GeneratedDepartureSkyline",CITY_TEXTURE,true,false)
 _city_material=city.material as ShaderMaterial
 clouds=_make_plane("GeneratedMiddleCloudBanks",CLOUD_TEXTURE,true,true)
 _cloud_material=clouds.material as ShaderMaterial
 wisps=_make_plane("GeneratedNearCloudWisps",WISP_TEXTURE,true,true)
 _wisp_material=wisps.material as ShaderMaterial
 orbit_dust=_make_plane("GeneratedNearOrbitDust",DUST_TEXTURE,true,true)
 _dust_material=orbit_dust.material as ShaderMaterial
 _ready_complete=true
 if _ground_route:_ensure_ground_plane()
 _refresh()

func _make_plane(label:String,texture:Texture2D,repeat_x:bool,repeat_y:bool,clamp_y:bool=false) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new()
 node.name=label;node.texture=texture;node.centered=false
 node.scale=LOGICAL_SIZE/Vector2(texture.get_size())
 node.position=Vector2.ZERO
 node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var shader_material:ShaderMaterial=ShaderMaterial.new()
 shader_material.shader=BACKGROUND_SHADER
 shader_material.set_shader_parameter("source_size_px",Vector2(texture.get_size()))
 shader_material.set_shader_parameter("logical_size_px",LOGICAL_SIZE)
 shader_material.set_shader_parameter("repeat_x",repeat_x)
 shader_material.set_shader_parameter("repeat_y",repeat_y)
 shader_material.set_shader_parameter("clamp_y",clamp_y)
 node.material=shader_material;add_child(node)
 return node

func _ensure_ground_plane() -> void:
 # Keep the seven legacy planes unchanged. Cache one generated depth layer
 # only after an explicit ground contract; it never creates collision shapes.
 near_city=_make_plane("GeneratedNearDepotRooftops",GROUND_TEXTURE,true,false)
 near_city.modulate=Color(1,1,1,.76)
 _ground_material=near_city.material as ShaderMaterial

func configure_route(route:Dictionary) -> void:
 _ground_route=(route.get("control_version") in ["pilot-delivery-v3","pilot-delivery-v6","pilot-delivery-v7","pilot-delivery-v8"] and route.get("route_kind")=="ground") or GroundProfile.is_ground_route(route) or (route.get("control_version") in ["pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-delivery-v6","pilot-delivery-v7","pilot-delivery-v8"] and route.get("route_profile")=="free-ground-choice-v1" and route.get("free_ground_schema")=="free-ground-choice-v1")
 _route_kind="city" if _ground_route else str(route.get("background_route","city_to_orbit"))
 if route.get("control_version") in ["pilot-ascent-v4","pilot-ascent-v6","pilot-ascent-v7","pilot-ascent-v8"] and _route_kind=="ascent":_route_kind="city_to_orbit"
 if _ground_route and _ready_complete and near_city==null:_ensure_ground_plane()
 if _route_kind not in ["city_to_orbit","city","orbit"]:_route_kind="city_to_orbit"
 _ground_y_m=_finite_value(route.get("background_ground_y_m",0.0),0.0,-1000000.0,1000000.0)
 _orbit_begin_m=_finite_value(route.get("background_orbit_begin_altitude_m",85.0),85.0,1.0,100000.0)
 _orbit_full_m=_finite_value(route.get("background_orbit_full_altitude_m",135.0),135.0,_orbit_begin_m+1.0,200000.0)
 _cloud_top_m=_finite_value(route.get("background_cloud_top_altitude_m",120.0),120.0,10.0,200000.0)
 _blur_start_mps=_finite_value(route.get("background_blur_start_mps",10.0),10.0,0.0,200.0)
 _blur_full_mps=_finite_value(route.get("background_blur_full_mps",22.0),22.0,_blur_start_mps+0.01,250.0)
 _position_m=Vector2(0,_ground_y_m);_camera_position_m=Vector2.ZERO
 _velocity_mps=Vector2.ZERO;_motion_velocity_mps=Vector2.ZERO;_have_camera_sample=false;_progress=0.0
 _refresh()

func update_flight(position_m:Vector2,velocity_mps:Vector2,progress:float,camera_position_m:Vector2=Vector2(INF,INF)) -> void:
 if not position_m.is_finite() or not velocity_mps.is_finite() or not is_finite(progress):return
 # Omitted optional camera uses flight position. A partially invalid camera is
 # rejected instead of poisoning shader uniforms. Explicit INF,INF is sentinel.
 var supplied_camera:bool=camera_position_m!=Vector2(INF,INF)
 if not supplied_camera:camera_position_m=position_m-Vector2(0,_ground_y_m)
 elif not camera_position_m.is_finite():return
 var safe_velocity:Vector2=velocity_mps.clamp(Vector2(-1000000,-1000000),Vector2(1000000,1000000))
 if safe_velocity==Vector2.ZERO:
  _motion_velocity_mps=Vector2.ZERO
 elif not supplied_camera or not _have_camera_sample:
  _motion_velocity_mps=safe_velocity
 elif camera_position_m!=_camera_position_m or position_m!=_position_m:
  var camera_delta:Vector2=(camera_position_m-_camera_position_m).clamp(Vector2(-1000000,-1000000),Vector2(1000000,1000000))
  var cargo_delta:Vector2=(position_m-_position_m).clamp(Vector2(-1000000,-1000000),Vector2(1000000,1000000))
  # Camera dead-zones and restrained axes also restrain blur. Delta-derived
  # direction matches actual scenery movement; inferred speed is bounded by
  # cargo speed so camera recentering cannot introduce an unbounded smear.
  _motion_velocity_mps=camera_delta.normalized()*safe_velocity.length()*clampf(camera_delta.length()/maxf(cargo_delta.length(),0.0001),0.0,1.0)
 elif velocity_mps!=_velocity_mps:
  _motion_velocity_mps=_motion_velocity_mps.normalized()*safe_velocity.length()
 _have_camera_sample=supplied_camera
 _position_m=position_m;_velocity_mps=velocity_mps
 _camera_position_m=camera_position_m;_progress=clampf(progress,0.0,1.0)
 _refresh()

static func ordinary_coordinate(pixel:float,extent:float) -> float:
 return fposmod(pixel,extent)

static func wrapped_offset(meters:float,pixels_per_meter:float,extent:float=1280.0) -> float:
 if not is_finite(meters) or not is_finite(pixels_per_meter) or not is_finite(extent) or pixels_per_meter<=0.0 or extent<=0.0:return 0.0
 # Reduce metres before multiplying. Long/reverse paths never create gigantic
 # shader coordinates; round only the reduced result onto the stable pixel grid.
 var period_m:float=extent/pixels_per_meter
 return fposmod(round(fposmod(meters,period_m)*pixels_per_meter),extent)

func _finite_value(value:Variant,fallback:float,low:float,high:float) -> float:
 if not (value is float or value is int):return clampf(fallback,low,high)
 var number:float=float(value)
 return clampf(number,low,high) if is_finite(number) else clampf(fallback,low,high)

func _repeat_scroll(ppm:Vector2,height:float,y_origin:float=0.0) -> Vector2:
 return Vector2(wrapped_offset(_camera_position_m.x,ppm.x),fposmod(wrapped_offset(_camera_position_m.y,ppm.y,height)+y_origin,height))

func _layer_blur(ppm:Vector2,strength:float) -> Vector2:
 if _blur_pixels<=0.0:return Vector2.ZERO
 # Source sampling delta is opposite visible background drift. A climbing
 # camera (negative Y) sends scenery downscreen and trails it upward.
 var movement:Vector2=_motion_velocity_mps*ppm
 if movement.length_squared()<0.0001:return Vector2.ZERO
 return movement.normalized()*_blur_pixels*strength

func _refresh() -> void:
 if not _ready_complete:return
 _altitude_m=clampf(_ground_y_m-_position_m.y,-1000000.0,1000000.0)
 _orbit_weight=smoothstep(_orbit_begin_m,_orbit_full_m,_altitude_m)
 if _route_kind=="city":_orbit_weight=0.0
 elif _route_kind=="orbit":_orbit_weight=1.0
 _cloud_weight=1.0-smoothstep(_cloud_top_m-40.0,_cloud_top_m+10.0,_altitude_m)
 if _route_kind=="orbit":_cloud_weight=0.0
 orbit_dust.visible=_orbit_weight>0.0;orbit_dust.modulate=Color(1,1,1,0.32*_orbit_weight)
 atmosphere.visible=_orbit_weight<1.0
 starfield.visible=_orbit_weight>0.0;starfield.modulate=Color(1,1,1,_orbit_weight)
 planet.visible=_orbit_weight>0.0;planet.modulate=Color(1,1,1,_orbit_weight)
 # The skyline physically drops below the viewport. It does not dissolve as X
 # progress advances. Very high/low finite camera Y is clamped while offscreen.
 var city_y:float=round(clampf(_camera_position_m.y,-400.0,400.0)*CITY_PPM.y-80.0)
 city.visible=city_y>-LOGICAL_SIZE.y and _route_kind!="orbit"
 city.modulate=Color.WHITE
 clouds.visible=_cloud_weight>0.0;clouds.modulate=Color(1,1,1,0.76*_cloud_weight)
 wisps.visible=_cloud_weight>0.0;wisps.modulate=Color(1,1,1,0.38*_cloud_weight)
 if near_city!=null:
  # Roof silhouettes sit below the clear flight band, behind every real
  # collider. The shallow camera-relative parallax is scenery, not a floor.
  near_city.visible=_ground_route
  var ground_y:float=round(clampf(_camera_position_m.y,-400.0,400.0)*GROUND_PPM.y+GROUND_Y_OFFSET)
  _ground_material.set_shader_parameter("scroll_px",Vector2(wrapped_offset(_camera_position_m.x,GROUND_PPM.x),ground_y))
 _city_material.set_shader_parameter("scroll_px",Vector2(wrapped_offset(_camera_position_m.x,CITY_PPM.x),city_y))
 _cloud_material.set_shader_parameter("scroll_px",_repeat_scroll(CLOUD_PPM,640.0,180.0))
 _wisp_material.set_shader_parameter("scroll_px",_repeat_scroll(WISP_PPM,640.0,80.0))
 _star_material.set_shader_parameter("scroll_px",_repeat_scroll(STAR_PPM,720.0))
 _dust_material.set_shader_parameter("scroll_px",_repeat_scroll(DUST_PPM,640.0))
 var sky_y:float=round(clampf(1840.0+clampf(_camera_position_m.y,-400.0,400.0)*SKY_PPM.y,0.0,1840.0))
 _sky_material.set_shader_parameter("scroll_px",Vector2(wrapped_offset(_camera_position_m.x,SKY_PPM.x),sky_y))
 var planet_scroll:Vector2=Vector2(round(clampf(_camera_position_m.x,-800.0,800.0)*0.025),-180.0+round(clampf(_camera_position_m.y+135.0,-30.0,30.0)*0.12))
 _planet_material.set_shader_parameter("scroll_px",planet_scroll)
 _blur_pixels=0.0
 if motion_blur_enabled and not reduced_motion:
  _blur_pixels=MAX_BLUR_PX*smoothstep(_blur_start_mps,_blur_full_mps,_motion_velocity_mps.length())
 if _ground_material!=null:_ground_material.set_shader_parameter("blur_delta_px",_layer_blur(GROUND_PPM,.45))
 _dust_material.set_shader_parameter("blur_delta_px",_layer_blur(DUST_PPM,0.85))
 _sky_material.set_shader_parameter("blur_delta_px",Vector2.ZERO)
 _city_material.set_shader_parameter("blur_delta_px",_layer_blur(CITY_PPM,0.3))
 _cloud_material.set_shader_parameter("blur_delta_px",_layer_blur(CLOUD_PPM,0.65))
 _wisp_material.set_shader_parameter("blur_delta_px",_layer_blur(WISP_PPM,1.0))
 _star_material.set_shader_parameter("blur_delta_px",_layer_blur(STAR_PPM,0.04))
 _planet_material.set_shader_parameter("blur_delta_px",_layer_blur(Vector2(0.025,0.12),0.02))

func debug_snapshot() -> Dictionary:
 return {"ground_route":_ground_route,"ground_scroll":_ground_material.get_shader_parameter("scroll_px") if _ground_material!=null else Vector2.ZERO,"ground_blur":_ground_material.get_shader_parameter("blur_delta_px") if _ground_material!=null else Vector2.ZERO,
 "route_kind":_route_kind,"progress":_progress,"altitude_m":_altitude_m,"camera_position_m":_camera_position_m,"motion_velocity_mps":_motion_velocity_mps,
 "orbit_weight":_orbit_weight,"cloud_weight":_cloud_weight,"blur_pixels":_blur_pixels,"plane_nodes":get_child_count(),"logical_size":LOGICAL_SIZE,
 "city_scroll":_city_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "sky_scroll":_sky_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "cloud_scroll":_cloud_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "wisp_scroll":_wisp_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "star_scroll":_star_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "dust_scroll":_dust_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "planet_scroll":_planet_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "blur_direction":_wisp_material.get_shader_parameter("blur_delta_px") if _ready_complete else Vector2.ZERO}
