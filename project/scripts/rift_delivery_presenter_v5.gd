extends Node2D
## Read-only physical rift projection. No clock, collision, transport, damage,
## camera changes or progression. Region switches require the solver receipt.
const VERSION:String="pilot-rift-v5"
const ShieldProfile=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const ShieldMarkers=preload("res://scripts/pilot_delivery_profile_v8.gd")
const MaterialProfile=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const MaterialMarkers=preload("res://scripts/pilot_delivery_profile_v7.gd")
const CellRules=preload("res://scripts/cell_rules_profile_v6.gd")
const CellProfile=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const Profile=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const PirateArt=preload("res://scripts/pirate_world_presenter_2d.gd")
const SKY:String="res://assets/2d_v5/mosslight/far-garden-wrap.png"
const SKY_SHA:String="37e19d3d1d1027c0146e4dff98a470d7580361db7d8fb2295f757f9770257328"
const RECEIVER:String="res://assets/2d_v5/flight/receiver.png"
var _route:Dictionary={}
var _sky:Sprite2D
var _field:PhysicalField
var _pirate:Sprite2D
var _origin:Vector2=Vector2.ZERO
var _cell:float=72.0
var _enabled:bool=false
var _scene_visible:bool=false
var _special:bool=false
var _receiver:Sprite2D
var _pirate_active:bool=false

class PhysicalField extends Node2D:
 const FONT=preload("res://assets/fonts/ChineseSans.otf")
 var route:Dictionary={}
 var frame:Dictionary={}
 var origin:Vector2=Vector2.ZERO
 var cell:float=72.0
 var zoom:float=1.0
 var safe:Rect2
 var special:bool=false
 var physics_time:float=0.0
 func point(value:Variant) -> Vector2:
  if value is Vector2:return origin+value*cell
  if value is Array and value.size()==2:return origin+Vector2(float(value[0]),float(value[1]))*cell
  return origin
 func caption(at:Vector2,label:String,color:Color) -> void:
  if safe.size.x<=0 or safe.size.y<=0:return
  var width:float=FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
  var location:Vector2=Vector2(clampf(at.x,safe.position.x+8/zoom,maxf(safe.position.x+8/zoom,safe.end.x-(width+8)/zoom)),clampf(at.y,safe.position.y+20/zoom,safe.end.y-8/zoom))
  draw_set_transform(location,0,Vector2.ONE/zoom)
  draw_string_outline(FONT,Vector2.ZERO,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,4,Color("101a30"))
  draw_string(FONT,Vector2.ZERO,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)
  draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
 func portal(at:Vector2,radius:float,label:String,color:Color,hint:bool) -> void:
  var top:Vector2=at-Vector2(0,radius);var bottom:Vector2=at+Vector2(0,radius)
  # Vertical luminous aperture is the real entry plane; hardware is outside.
  draw_line(top,bottom,Color(color,.34),5/zoom,false)
  for side in [-1.0,1.0]:
   var cap:Vector2=at+Vector2(0,side*(radius+7/zoom))
   draw_rect(Rect2(cap-Vector2(16,5)/zoom,Vector2(32,10)/zoom),Color("162a42"))
   draw_rect(Rect2(cap-Vector2(12,2)/zoom,Vector2(24,4)/zoom),color)
  var tip:Vector2=at+Vector2(18/zoom,0)
  draw_line(at-Vector2(18/zoom,0),tip,color,2/zoom,false)
  draw_line(tip,tip+Vector2(-8,-6)/zoom,color,2/zoom,false)
  draw_line(tip,tip+Vector2(-8,6)/zoom,color,2/zoom,false)
  if safe.has_point(at) or hint:caption(top+Vector2(20,-8)/zoom,label,color)
 func zone_label_position(bounds:Array,bottom:bool=false) -> Vector2:
  var corner:Vector2=origin+Vector2(float(bounds[0]),float(bounds[1]))*cell
  return corner+Vector2(8/zoom,float(bounds[3])*cell-10/zoom if bottom else 22/zoom)
 func zone(bounds:Array,color:Color,label:String,bottom:bool=false) -> void:
  if bounds.size()!=4:return
  var area:Rect2=Rect2(origin+Vector2(float(bounds[0]),float(bounds[1]))*cell,Vector2(float(bounds[2]),float(bounds[3]))*cell)
  if not area.intersects(safe):return
  draw_rect(area.intersection(safe),Color(color,.055))
  draw_rect(area,Color(color,.6),false,1.5/zoom)
  caption(zone_label_position(bounds,bottom),label,color)
 func _draw() -> void:
  if route.is_empty():return
  var gate:Dictionary=route.rift_portal
  portal(point(gate.entry),float(gate.aperture_radius)*cell,"入口 →",Color("49cce5"),not special)
  portal(point(gate.exit),float(gate.aperture_radius)*cell,"出口 →",Color("b7a0f4"),false)
  if not special:return
  zone(route.rift_biology.cold_bounds,Color("8dcfe9"),"冷区")
  _draw_threats()
 func _draw_threats() -> void:
  var turbulence:Dictionary=frame.get("rift_turbulence",{})
  if bool(turbulence.get("enabled",false)):
   var active:bool=float(turbulence.get("phase_seconds",0.0))<float(turbulence.get("active_seconds",0.0))
   zone(turbulence.get("bounds",[]),Color("e9aa70") if active else Color("9c93bc"),("乱流 " if active else "乱流间歇 ")+"%.1fs"%float(turbulence.get("seconds_to_change",0)),true)
  var pirate:Dictionary=frame.get("rift_pirate",{})
  if not bool(pirate.get("active",false)):return
  var center:Vector2=point(pirate.get("position",Vector2.ZERO))
  var radius:float=float(pirate.get("radius",1.5))*cell
  if safe.has_point(center):caption(center+Vector2(-radius,-radius-10/zoom),"海盗 · 余弹 %d"%int(pirate.get("ammo_remaining",0)),Color("f2a288"))
  if bool(pirate.get("warning",false)):
   var start:Vector2=point(pirate.warning_origin);var target:Vector2=start+Vector2(pirate.warning_direction)*float(pirate.range)*cell
   draw_dashed_line(start,target,Color("ffca57"),2/zoom,10/zoom,false)
   if safe.has_point(target):draw_arc(target,12/zoom,0,TAU,16,Color("ffca57"),2/zoom,false)
  var ray:Dictionary=pirate.get("last_ray",{})
  if not ray.is_empty() and physics_time>=float(ray.get("time",INF)) and physics_time-float(ray.get("time",-INF))<=.3:
   var start:Vector2=point(ray.origin);var end:Vector2=point(ray.end)
   draw_line(start,end,Color("f08070"),3/zoom,false)
   draw_arc(end,8/zoom,0,TAU,12,Color("ffcf8a"),2/zoom,false)

static func applies(route:Dictionary) -> bool:return str(route.get("control_version","")) in [VERSION,CellProfile.VERSION,MaterialProfile.VERSION,ShieldProfile.VERSION]
static func has_markers(route:Dictionary) -> bool:return ShieldProfile.has_markers(route) or MaterialProfile.has_markers(route) or CellProfile.has_markers(route) or Profile.has_markers(route)
static func route_error(route:Dictionary) -> String:
 if not has_markers(route):return ""
 var invalid:String=ShieldProfile.validation_error(route) if ShieldMarkers.shield_markers(route) else (MaterialProfile.validation_error(route) if MaterialMarkers.material_markers(route) else (CellProfile.validation_error(route) if CellRules.has_markers(route) else Profile.validation_error(route)))
 if not invalid.is_empty():return invalid
 if not FileAccess.file_exists(SKY) or FileAccess.get_sha256(SKY)!=SKY_SHA or not ResourceLoader.exists(SKY,"Texture2D"):return "裂隙远景资源尚未恢复，原进度已保留。"
 var sky:Texture2D=load(SKY)
 if sky==null or sky.get_size()!=Vector2(1672,941):return "裂隙远景资源不匹配，原进度已保留。"
 if not FileAccess.file_exists(RECEIVER) or FileAccess.get_sha256(RECEIVER)!="8b9303bb183d412e8f601da83f4a199d25bcfb36c5751d6e13ea26a6c0a481f0" or not ResourceLoader.exists(RECEIVER,"Texture2D"):return "裂隙收件台资源尚未恢复，原进度已保留。"
 return "" if PirateArt.resources_error().is_empty() else "裂隙海盗资源尚未恢复，原进度已保留。"
static func crossed(data:Dictionary) -> bool:
 var tick:Variant=data.get("portal_crossing_tick",-1)
 return tick is int and tick>=0 and str(data.get("region",""))=="greenhouse"
static func has_warning(data:Dictionary) -> bool:
 if not crossed(data):return false
 return bool(data.get("rift_pirate",{}).get("warning",false)) or (bool(data.get("rift_turbulence",{}).get("active",false)) and bool(data.get("rift_turbulence",{}).get("inside",false)))
static func status_text(data:Dictionary) -> String:
 if not crossed(data):
  match str(data.get("portal_last_denial","")):
   "too_large_or_off_center":return "对准入口，整船需能通过"
   "exit_blocked":return "出口受阻，等待安全通行"
  return "从蓝色入口向右穿门"
 var pirate:Dictionary=data.get("rift_pirate",{})
 if bool(pirate.get("active",false)) and bool(pirate.get("warning",false)):return "海盗瞄准 · %.1fs"%float(pirate.get("warning_remaining",0.0))
 var turbulence:Dictionary=data.get("rift_turbulence",{})
 if bool(turbulence.get("enabled",false)) and bool(turbulence.get("inside",false)):
  return ("乱流持续 " if bool(turbulence.get("active",false)) else "乱流间歇 ")+"%.1fs"%float(turbulence.get("seconds_to_change",0.0))
 return "飞往温室收件台"
static func biology_text(data:Dictionary,order:Dictionary) -> String:
 if not crossed(data):return ""
 var exposure:float=float(data.get("biological_exposure_seconds",NAN))
 var temperature:float=float(data.get("biological_temperature_c",NAN))
 var grace:float=float(order.get("rift_biology",{}).get("grace_seconds",NAN))
 if not is_finite(exposure) or not is_finite(temperature) or not is_finite(grace):return ""
 return "冷区 %.1f/%.1fs"%[exposure,grace] if temperature<float(order.get("rift_biology",{}).get("warm_temperature_c",18.0)) else "暖区 %.0f°C"%temperature
func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false);set_physics_process(false)
func configure_route(route:Dictionary,world_parent:Node2D,origin:Vector2,cell:float=72.0) -> bool:
 leave_flight()
 if not applies(route) or not route_error(route).is_empty():return false
 _route=route.duplicate(true);_origin=origin;_cell=cell
 _sky=Sprite2D.new();_sky.name="CrossedRiftGarden";_sky.texture=load(SKY);_sky.centered=false;_sky.scale=Vector2(1280,720)/Vector2(_sky.texture.get_size());add_child(_sky)
 _field=PhysicalField.new();_field.name="AuthoritativeRiftField";_field.z_index=9;_field.route=_route.duplicate(true);_field.origin=origin;_field.cell=cell;world_parent.add_child(_field)
 _pirate=Sprite2D.new();_pirate.name="FiniteRiftPirate";_pirate.texture=load(PirateArt.ART_ROOT+"charges-2.png");_pirate.z_index=8;world_parent.add_child(_pirate)
 _enabled=true;_scene_visible=true;_refresh_visibility();return true
func bind_receiver(receiver:Sprite2D) -> void:_receiver=receiver
func update_from_sim(sim,zoom:float,safe_world:Rect2) -> void:
 if not _enabled:return
 _special=crossed(sim.telemetry)
 _field.frame=sim.telemetry.duplicate(true);_field.physics_time=float(sim.elapsed);_field.special=_special;_field.zoom=maxf(.01,zoom);_field.safe=safe_world;_field.queue_redraw()
 var pirate:Dictionary=sim.telemetry.get("rift_pirate",{})
 _pirate_active=_special and bool(pirate.get("active",false)) and pirate.get("position") is Vector2
 if _pirate_active:
  _pirate.position=_origin+pirate.position*_cell
  _pirate.scale=Vector2.ONE*float(pirate.get("radius",1.5))*2.0*_cell/192.0
  var ammo:int=clampi(int(pirate.get("ammo_remaining",0)),0,2)
  _pirate.texture=load(PirateArt.ART_ROOT+("disabled" if bool(pirate.get("disabled",false)) else "charges-"+str(ammo))+".png")
 _refresh_visibility()
func set_scene_visible(value:bool) -> void:_scene_visible=value;_refresh_visibility()
func _refresh_visibility() -> void:
 visible=_enabled and _scene_visible
 if is_instance_valid(_sky):_sky.visible=visible and _special
 if is_instance_valid(_field):_field.visible=visible
 if is_instance_valid(_pirate):_pirate.visible=visible and _pirate_active
 if is_instance_valid(_receiver):_receiver.visible=visible and _special
func route_enabled() -> bool:return _enabled
func special_active() -> bool:return _enabled and _special
func leave_flight() -> void:
 _enabled=false;_scene_visible=false;_special=false;_pirate_active=false;_route.clear()
 for node in [_sky,_field,_pirate]:
  if is_instance_valid(node):node.free()
 _sky=null;_field=null;_pirate=null;_receiver=null;hide()
func debug_snapshot() -> Dictionary:
 return {"enabled":_enabled,"special":_special,"crossing_tick":_field.frame.get("portal_crossing_tick",-1) if is_instance_valid(_field) else -1,"field_frame":_field.frame.duplicate(true) if is_instance_valid(_field) else {}}
