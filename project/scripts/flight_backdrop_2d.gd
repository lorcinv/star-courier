extends Node2D
## Generated, purely 2D city -> atmosphere -> orbit flight backdrop.
## Parent under the existing screen-space CanvasLayer/background_root. The
## parent alone scales its canonical 1280x720 space; no Camera2D is used here.
## Exactly three cached Sprite2Ds/materials. No processing clock or time shader.
const LOGICAL_SIZE:Vector2=Vector2(1280,720)
const SPACE_ROOT:String="res://assets/2d_v5/space/"
const SPEED_SHADER=preload("res://assets/2d_v5/background_speed.gdshader")
const CITY_TEXTURE=preload("res://assets/2d_v5/environment/far-city.png")
const SKY_TEXTURE=preload("res://assets/2d_v5/space/orbit-starfield.png")
const PLANET_TEXTURE=preload("res://assets/2d_v5/space/orbit-planet-limb.png")
const PLANET_BASE_Y:float=176.0
const MAX_BLUR_PX:float=22.0

var reduced_motion:bool=false:
 set(value):
  reduced_motion=value
  _refresh()
var motion_blur_enabled:bool=true:
 set(value):
  motion_blur_enabled=value
  _refresh()
var city:Sprite2D
var starfield:Sprite2D
var planet:Sprite2D
var _city_material:ShaderMaterial
var _sky_material:ShaderMaterial
var _planet_material:ShaderMaterial
var _position_m:Vector2=Vector2.ZERO
var _velocity_mps:Vector2=Vector2.ZERO
var _progress:float=0.0
var _route_kind:String="city_to_orbit"
var _city_until:float=0.25
var _orbit_after:float=0.55
var _blur_start_mps:float=4.5
var _blur_full_mps:float=8.0
var _orbit_weight:float=0.0
var _blur_pixels:float=0.0
var _ready_complete:bool=false

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false)
 starfield=_make_plane("GeneratedDistantSky",SKY_TEXTURE,Color("07132b"),0.24,true)
 _sky_material=starfield.material as ShaderMaterial
 planet=_make_plane("GeneratedPlanetLimb",PLANET_TEXTURE,Color("112850"),0.34,false)
 _planet_material=planet.material as ShaderMaterial
 city=_make_plane("GeneratedDepartureCity",CITY_TEXTURE,Color("43608a"),0.25,true)
 _city_material=city.material as ShaderMaterial
 _ready_complete=true
 _refresh()

func _make_plane(label:String,texture:Texture2D,fog:Color,fog_mix:float,vertical_repeat:bool) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new()
 node.name=label;node.texture=texture;node.centered=false
 # The authored starfield is shorter than the viewport; its shader samples at
 # original pixel size and mirrors the painted crop rather than stretching it.
 node.scale=LOGICAL_SIZE/Vector2(texture.get_size())
 node.position=Vector2.ZERO
 node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var material:ShaderMaterial=ShaderMaterial.new()
 material.shader=SPEED_SHADER
 material.set_shader_parameter("source_size_px",Vector2(texture.get_size()))
 material.set_shader_parameter("logical_size_px",LOGICAL_SIZE)
 material.set_shader_parameter("distance_color",fog)
 material.set_shader_parameter("distance_mix",fog_mix)
 material.set_shader_parameter("repeat_vertical",vertical_repeat)
 node.material=material;add_child(node)
 return node

func configure_route(route:Dictionary) -> void:
 # Optional presentation-only keys. Existing route dictionaries need no edits.
 _route_kind=str(route.get("background_route","city_to_orbit"))
 if _route_kind not in ["city_to_orbit","city","orbit"]:_route_kind="city_to_orbit"
 _city_until=_finite_value(route.get("background_city_until",0.25),0.25,0.0,0.9)
 _orbit_after=_finite_value(route.get("background_orbit_after",0.55),0.55,_city_until+0.01,1.0)
 _blur_start_mps=_finite_value(route.get("background_blur_start_mps",4.5),4.5,0.0,200.0)
 _blur_full_mps=_finite_value(route.get("background_blur_full_mps",8.0),8.0,_blur_start_mps+0.01,250.0)
 _position_m=Vector2.ZERO;_velocity_mps=Vector2.ZERO;_progress=0.0
 _refresh()

func update_flight(position_m:Vector2,velocity_mps:Vector2,progress:float) -> void:
 if not position_m.is_finite() or not velocity_mps.is_finite() or not is_finite(progress):return
 _position_m=position_m;_velocity_mps=velocity_mps;_progress=clampf(progress,0.0,1.0)
 _refresh()

func _finite_value(value:Variant,fallback:float,low:float,high:float) -> float:
 if not (value is float or value is int):return clampf(fallback,low,high)
 var number:float=float(value)
 return clampf(number,low,high) if is_finite(number) else clampf(fallback,low,high)

static func mirror_coordinate(pixel:float,extent:float) -> float:
 # CPU equivalent of the shader, useful for seam/negative-coordinate tests.
 var mirrored:float=fposmod(pixel,extent*2.0)
 return clampf(minf(mirrored,extent*2.0-mirrored),0.5,extent-0.5)

static func wrapped_offset(meters:float,pixels_per_meter:float) -> float:
 # Reduce before multiplying, so arbitrarily long/reverse journeys cannot grow
 # scene transforms or lose precision through an unnecessarily huge product.
 var period_m:float=LOGICAL_SIZE.x*2.0/pixels_per_meter
 return fposmod(round(fposmod(meters,period_m)*pixels_per_meter),LOGICAL_SIZE.x*2.0)

func _refresh() -> void:
 if not _ready_complete:return
 _orbit_weight=smoothstep(_city_until,_orbit_after,_progress)
 if _route_kind=="city":_orbit_weight=0.0
 elif _route_kind=="orbit":_orbit_weight=1.0
 city.visible=_orbit_weight<1.0
 city.modulate=Color(1,1,1,1.0-_orbit_weight)
 starfield.visible=_orbit_weight>0.0;planet.visible=_orbit_weight>0.0
 # All plane origins are integral and remain at zero. Only integral, bounded
 # source-pixel offsets move; texture sampling handles mirrored adjoining tiles.
 var city_offset:Vector2=Vector2(wrapped_offset(_position_m.x,11.0),round(clampf(_position_m.y*1.4,-16.0,16.0)))
 var sky_offset:Vector2=Vector2(wrapped_offset(_position_m.x,1.6),round(clampf(_position_m.y*0.35,-10.0,10.0)))
 # A far planetary arc must not form a V-shaped valley at mirrored joins.
 # Its giant horizon therefore has only a bounded, almost imperceptible drift.
 var planet_offset:Vector2=Vector2(fposmod(round(clampf(_position_m.x*0.025,-18.0,18.0)),2560.0),-PLANET_BASE_Y+round(clampf(_position_m.y*0.4,-8.0,8.0)))
 _city_material.set_shader_parameter("scroll_px",city_offset)
 _sky_material.set_shader_parameter("scroll_px",sky_offset)
 _planet_material.set_shader_parameter("scroll_px",planet_offset)
 _blur_pixels=0.0
 if motion_blur_enabled and not reduced_motion:
  _blur_pixels=MAX_BLUR_PX*smoothstep(_blur_start_mps,_blur_full_mps,absf(_velocity_mps.x))
 var direction:float=signf(_velocity_mps.x)
 # Vertical contribution follows screen-space background motion. Horizontal
 # speed alone gates the effect, so a vertical drop cannot wash out the lane.
 var slope:float=clampf(_velocity_mps.y/maxf(absf(_velocity_mps.x),0.01),-0.4,0.4)
 var blur:Vector2=Vector2(direction,slope)*_blur_pixels
 _city_material.set_shader_parameter("blur_delta_px",blur)
 _sky_material.set_shader_parameter("blur_delta_px",blur*0.42)
 _planet_material.set_shader_parameter("blur_delta_px",blur*0.64)

func debug_snapshot() -> Dictionary:
 return {"route_kind":_route_kind,"progress":_progress,"orbit_weight":_orbit_weight,
 "blur_pixels":_blur_pixels,"plane_nodes":get_child_count(),"logical_size":LOGICAL_SIZE,
 "city_scroll":_city_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "sky_scroll":_sky_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "planet_scroll":_planet_material.get_shader_parameter("scroll_px") if _ready_complete else Vector2.ZERO,
 "blur_direction":_city_material.get_shader_parameter("blur_delta_px") if _ready_complete else Vector2.ZERO}
