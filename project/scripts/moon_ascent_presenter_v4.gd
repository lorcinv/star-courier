extends Node2D
## Read-only continuous ascent presentation. No teleport, clock, physics,
## damage, route mutation or background-driven progression occurs here.
const VERSION:String="pilot-ascent-v4"
const ShieldProfile=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const ShieldMarkers=preload("res://scripts/pilot_delivery_profile_v8.gd")
const MaterialProfile=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const MaterialMarkers=preload("res://scripts/pilot_delivery_profile_v7.gd")
const CellRules=preload("res://scripts/cell_rules_profile_v6.gd")
const CellProfile=preload("res://scripts/pilot_delivery_ascent_profile_v6.gd")
const Profile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const LunarReceipt=preload("res://scripts/lunar_outpost_receipt_v2.gd")
const SKY:String="res://assets/2d_v5/moon/far-sky-clamped.png"
const TERRAIN:String="res://assets/2d_v5/moon/regolith-decorative-wrap.png"
const SHADER:String="res://assets/2d_v5/moon/moon_background.gdshader"
const LOGICAL_SIZE:Vector2=Vector2(1280,720)
const MAX_WARNINGS:int=8
var _route:Dictionary={}
var _sky:Sprite2D
var _terrain:Sprite2D
var _cues:WarningCues
var _receiver:Sprite2D
var _origin:Vector2=Vector2.ZERO
var _cell:float=72.0
var _enabled:bool=false
var _scene_visible:bool=false
var _weight:float=0.0
var _altitude:float=0.0
var _surface_y:float=0.0

class WarningCues extends Node2D:
 const FONT=preload("res://assets/fonts/ChineseSans.otf")
 var warnings:Array[Dictionary]=[]
 var origin:Vector2=Vector2.ZERO
 var cell:float=72.0
 var safe:Rect2
 var zoom:float=1.0
 func _draw() -> void:
  if safe.size.x<=0 or safe.size.y<=0:return
  for warning in warnings:
   var real:Vector2=origin+warning.position*cell
   var anchor:Vector2=Vector2(clampf(real.x,safe.position.x+24.0/zoom,safe.end.x-24.0/zoom),clampf(real.y,safe.position.y+24.0/zoom,safe.end.y-24.0/zoom))
   var direction:Vector2=warning.velocity.normalized()
   if direction.length_squared()<.001:direction=Vector2.DOWN
   var shade:Color=Color("ee7863") if warning.active else Color("ffca57")
   var tip:Vector2=anchor+direction*16.0/zoom
   draw_line(anchor-direction*16.0/zoom,tip,Color("101a30"),5.0/zoom,false)
   draw_line(anchor-direction*16.0/zoom,tip,shade,2.0/zoom,false)
   draw_line(tip,tip-direction.rotated(.6)*10.0/zoom,shade,2.0/zoom,false)
   draw_line(tip,tip-direction.rotated(-.6)*10.0/zoom,shade,2.0/zoom,false)
   if safe.has_point(real):draw_arc(real,float(warning.radius)*cell,0,TAU,32,Color(shade,.55),1.0/zoom,false)
   draw_set_transform(anchor+Vector2(22,-12)/zoom,0,Vector2.ONE/zoom)
   var label:String="来袭" if warning.active else "%.1fs"%float(warning.seconds_to_spawn)
   draw_string_outline(FONT,Vector2.ZERO,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,4,Color("101a30"))
   draw_string(FONT,Vector2.ZERO,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,shade)
   draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

static func applies(route:Dictionary) -> bool:
 return str(route.get("control_version","")) in [VERSION,CellProfile.VERSION,MaterialProfile.VERSION,ShieldProfile.VERSION]

static func has_markers(route:Dictionary) -> bool:
 return ShieldProfile.has_markers(route) or MaterialProfile.has_markers(route) or CellProfile.has_markers(route) or Profile.has_markers(route)

static func route_error(route:Dictionary) -> String:
 if not has_markers(route):return ""
 var invalid:String=ShieldProfile.validation_error(route) if ShieldMarkers.shield_markers(route) else (MaterialProfile.validation_error(route) if MaterialMarkers.material_markers(route) else (CellProfile.validation_error(route) if CellRules.has_markers(route) else Profile.validation_error(route)))
 return invalid if not invalid.is_empty() else LunarReceipt.art_error()

static func warnings_from(telemetry:Dictionary) -> Array[Dictionary]:
 var result:Array[Dictionary]=[]
 var raw:Variant=telemetry.get("ascent_warnings",[])
 if not raw is Array:return result
 for item in raw:
  if result.size()>=MAX_WARNINGS:break
  if not item is Dictionary or not item.get("position") is Vector2 or not item.get("velocity") is Vector2:continue
  if not item.position.is_finite() or not item.velocity.is_finite():continue
  if not (item.get("seconds_to_spawn") is float or item.get("seconds_to_spawn") is int) or not (item.get("radius") is float or item.get("radius") is int) or not item.get("active") is bool:continue
  if not is_finite(float(item.seconds_to_spawn)) or float(item.seconds_to_spawn)<0.0 or not is_finite(float(item.radius)) or float(item.radius)<=0.0:continue
  result.append(item.duplicate(true))
 return result

static func status_text(telemetry:Dictionary) -> String:
 var warnings:Array[Dictionary]=warnings_from(telemetry)
 if not warnings.is_empty():
  var nearest:Dictionary=warnings[0]
  for warning in warnings:
   if warning.active or float(warning.seconds_to_spawn)<float(nearest.seconds_to_spawn):nearest=warning
  return "流星来袭，避开箭头标记" if nearest.active else "流星雨 %.1f 秒后进入航线"%float(nearest.seconds_to_spawn)
 return str({"ground":"持续向上飞，离开地面","upper_air":"穿过高空，留意电量","space":"已到太空，继续向月面飞","lunar_approach":"接近月面，减速进入收件光圈"}.get(str(telemetry.get("ascent_phase","")),"向上飞往月面"))

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false);set_physics_process(false)

func configure_route(route:Dictionary,world_parent:Node2D,origin:Vector2,cell:float=72.0) -> bool:
 leave_flight()
 if not applies(route) or not route_error(route).is_empty():return false
 _route=route.duplicate(true);_origin=origin;_cell=cell
 _sky=_plane("ContinuousAscentEarthSky",SKY,false)
 _terrain=_plane("ContinuousAscentLunarHorizon",TERRAIN,true)
 _sky.modulate.a=0.0;_terrain.modulate.a=0.0
 _cues=WarningCues.new();_cues.name="PhysicalAscentWarnings";_cues.z_index=10;world_parent.add_child(_cues)
 _enabled=true;_scene_visible=true;_refresh_visibility();return true

func _plane(label:String,path:String,terrain:bool) -> Sprite2D:
 var sprite:=Sprite2D.new();sprite.name=label;sprite.texture=load(path);sprite.centered=false
 sprite.scale=LOGICAL_SIZE/Vector2(sprite.texture.get_size());sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var material:=ShaderMaterial.new();material.shader=load(SHADER)
 material.set_shader_parameter("source_size_px",Vector2(sprite.texture.get_size()));material.set_shader_parameter("logical_size_px",LOGICAL_SIZE)
 material.set_shader_parameter("repeat_x",terrain);material.set_shader_parameter("terrain",terrain);material.set_shader_parameter("blur_delta_px",Vector2.ZERO)
 sprite.material=material;add_child(sprite);return sprite

func bind_receiver(receiver:Sprite2D) -> void:
 _receiver=receiver

func update_from_sim(sim,camera_world:Vector2,zoom:float,scene:Vector2,safe_world:Rect2) -> void:
 if not _enabled:return
 var cargo:Vector2=sim.cargo_position()
 _altitude=float(_route.get("background_ground_y_m",0.0))-cargo.y
 var begin:float=float(_route.get("ascent_lunar_approach_begin_altitude_m",500.0))
 var full:float=float(_route.get("ascent_lunar_approach_full_altitude_m",560.0))
 _weight=smoothstep(begin,full,_altitude)
 _sky.modulate.a=_weight;_terrain.modulate.a=.88*_weight
 var camera:Vector2=(camera_world-_origin)/_cell
 _sky.material.set_shader_parameter("scroll_px",Vector2(clampf(camera.x*.025,-16.0,16.0),clampf((camera.y-float(_route.destination_y))*.05,-8.0,8.0)))
 _terrain.material.set_shader_parameter("scroll_px",Vector2(fposmod(round(fposmod(camera.x,1280.0/2.4)*2.4/2.0)*2.0,1280.0),0.0))
 # The receiver is world-fixed. Its approach guides a decorative horizon,
 # constrained below the clear flight band; this art is never a new floor.
 var deck:Vector2=_receiver.get_meta("deck_center") if is_instance_valid(_receiver) and _receiver.has_meta("deck_center") else _origin+Vector2(float(_route.distance),float(_route.destination_y)+float(_route.delivery_radius)+1.0)*_cell
 _surface_y=clampf(scene.y*.5+(deck.y-camera_world.y)*zoom+90.0,scene.y-72.0,scene.y+120.0)
 _terrain.material.set_shader_parameter("surface_y_px",_surface_y)
 _cues.origin=_origin;_cues.cell=_cell;_cues.zoom=maxf(.01,zoom);_cues.safe=safe_world
 _cues.warnings=warnings_from(sim.telemetry);_cues.queue_redraw()
 _refresh_visibility()

func set_scene_visible(value:bool) -> void:
 _scene_visible=value;_refresh_visibility()
func _refresh_visibility() -> void:
 visible=_enabled and _scene_visible
 if is_instance_valid(_cues):_cues.visible=visible
func route_enabled() -> bool:return _enabled
func moon_weight() -> float:return _weight
func leave_flight() -> void:
 _enabled=false;_scene_visible=false;_weight=0.0;_altitude=0.0;_route.clear()
 for node in [_sky,_terrain,_cues]:
  if is_instance_valid(node):node.free()
 _sky=null;_terrain=null;_cues=null;_receiver=null;hide()
func debug_snapshot() -> Dictionary:
 return {"enabled":_enabled,"altitude_m":_altitude,"weight":_weight,"surface_y":_surface_y,"warning_count":_cues.warnings.size() if is_instance_valid(_cues) else 0,"receiver_bound":is_instance_valid(_receiver)}
