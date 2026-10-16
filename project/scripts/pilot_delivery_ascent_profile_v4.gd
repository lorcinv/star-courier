extends RefCounted
## Explicit new ascent protocol; old clients must reject rather than ignore fields.
const Delivery=preload("res://scripts/pilot_delivery_profile_v3.gd")
const AltitudeEnvironment=preload("res://scripts/delivery_ascent_environment_v1.gd")
const VERSION:String="pilot-ascent-v4"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String="free-flight-input-v2"
const SCHEMA:String="delivery-ascent-policy-v1"
const ROUTE_PROFILE:String="delivery-lunar-ascent-v1"
const DESTINATION_ID:String="ascent-lunar-outpost-v1"
const ASCENT_SCHEMA:String="continuous-altitude-v1"
const EVENT_SCHEMA:String="warned-meteor-shower-v1"
const MAX_EVENTS:int=6

static func route(base:Dictionary={})->Dictionary:
 for key in ["contract_id","status","generation","control_version","pilot_profile","free_flight_schema","ascent_schema"]:
  if base.has(key):return {}
 var source:Dictionary={"name":"第四关 · 持续升空登月","destination_name":"月面高地收件站","weight":1.0,"min_delivery_integrity":0.80,"cargo_safe_acceleration":35.0,"cargo_damage_per_excess_mps":0.5,"cargo_contact_damage_scale":1.0}
 source.merge(base,true)
 source.merge({"route_kind":"ascent","route_profile":ROUTE_PROFILE,"destination_id":DESTINATION_ID,
  "distance":40.0,"destination_y":-560.0,"delivery_radius":9.0,"max_delivery_speed":8.0,
  "gravity":0.0,"wind":[0.0,0.0],"pilot_drag":0.0,"variation":0.0,
  "background_route":"ascent","background_ground_y_m":0.0,
  "background_orbit_begin_altitude_m":180.0,"background_orbit_full_altitude_m":260.0,"background_cloud_top_altitude_m":240.0,
  "ascent_lunar_approach_begin_altitude_m":500.0,"ascent_lunar_approach_full_altitude_m":560.0,
  "ascent_schema":ASCENT_SCHEMA,"ascent_event_schema":EVENT_SCHEMA,"ascent_transition_metres":20.0,
  "ascent_return_below_ground_m":8.0,"ascent_event_world_bounds":[-160.0,-650.0,320.0,700.0],
  "ascent_layers":[
   {"phase":"ground","start_altitude_m":0.0,"gravity":2.8,"wind":[0.0,0.0],"drag":0.025},
   {"phase":"upper_air","start_altitude_m":100.0,"gravity":1.2,"wind":[0.35,0.0],"drag":0.015},
   {"phase":"space","start_altitude_m":240.0,"gravity":0.08,"wind":[0.0,0.0],"drag":0.0},
   {"phase":"lunar_approach","start_altitude_m":520.0,"gravity":0.25,"wind":[0.0,0.0],"drag":0.0}],
  "ascent_meteor_events":[
   _event("ascent-shower-1",280.0,3.25,[-50.0,-330.0],[16.0,2.5],0.9),
   _event("ascent-shower-2",280.0,3.90,[50.0,-360.0],[-14.0,2.0],1.1),
   _event("ascent-shower-3",280.0,4.55,[-50.0,-390.0],[13.0,1.5],1.0)],
  "hazards":[
   _rock("ascent-asteroid-lower",0.0,-170.0,6.0),
   _rock("ascent-asteroid-middle",16.0,-300.0,5.0),
   _rock("ascent-asteroid-upper",-18.0,-445.0,6.0)],
  "pilot_gates":[],"risk":"持续上升至月面站；低空检查推重比，高空有横风，轨道陨石可绕行，流星雨提前预警。为接近收件站留足制动电量。"},true)
 var result:Dictionary=Delivery.route(source)
 if result.is_empty():return {}
 result.control_version=VERSION;result.pilot_profile=VERSION;result.free_flight_schema=SCHEMA
 return result if validation_error(result).is_empty() else {}

static func _rock(id:String,x:float,y:float,radius:float)->Dictionary:
 return {"id":id,"type":"rock","x":x,"y":y,"radius":radius,"health":120.0,"mass":80.0,"destructible":true,"conductive":true,"ascent_asteroid":true}
static func _event(id:String,altitude:float,warning:float,position:Array,velocity:Array,radius:float)->Dictionary:
 return {"id":id,"trigger_altitude_m":altitude,"warning_seconds":warning,"position":position,"velocity":velocity,"radius":radius,"health":55.0,"mass":12.0}
static func has_markers(data:Dictionary)->bool:
 if data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.get("free_flight_schema")==SCHEMA or data.get("route_profile")==ROUTE_PROFILE:return true
 for key in data:
  if str(key).begins_with("ascent_"):return true
 return false
static func compatibility_route(data:Dictionary)->Dictionary:
 var local:Dictionary=data.duplicate(true);local.merge(Delivery.MARKERS,true);return local
static func validation_error(data:Dictionary)->String:
 for entry in [["control_version",VERSION],["pilot_profile",VERSION],["free_flight_schema",SCHEMA],["input_schema",INPUT_SCHEMA],["route_profile",ROUTE_PROFILE],["route_kind","ascent"],["destination_id",DESTINATION_ID],["ascent_schema",ASCENT_SCHEMA],["ascent_event_schema",EVENT_SCHEMA],["background_route","ascent"]]:
  if not data.get(entry[0]) is String or data[entry[0]]!=entry[1]:return "持续登月协议或环境身份不一致。"
 var inherited:String=Delivery.validation_error(compatibility_route(data))
 if not inherited.is_empty():return inherited
 if not _json_safe(data):return "登月路线含无效或过量数据。"
 if float(data.gravity)!=0.0 or data.wind!=[0.0,0.0] or float(data.pilot_drag)!=0.0:return "登月外场不能与旧恒定外场叠加。"
 for key in ["background_ground_y_m","background_orbit_begin_altitude_m","background_orbit_full_altitude_m","background_cloud_top_altitude_m","ascent_lunar_approach_begin_altitude_m","ascent_lunar_approach_full_altitude_m","ascent_transition_metres","ascent_return_below_ground_m"]:
  if not _number(data.get(key)):return "登月高度或阶段字段缺失。"
 if float(data.ascent_transition_metres)<=0.0 or float(data.ascent_transition_metres)>100.0 or float(data.ascent_return_below_ground_m)<=0.0 or float(data.ascent_return_below_ground_m)>100.0:return "登月外场过渡参数无效。"
 if float(data.background_orbit_begin_altitude_m)<0.0 or float(data.background_orbit_full_altitude_m)<=float(data.background_orbit_begin_altitude_m) or float(data.ascent_lunar_approach_begin_altitude_m)<float(data.background_orbit_full_altitude_m) or float(data.ascent_lunar_approach_full_altitude_m)<=float(data.ascent_lunar_approach_begin_altitude_m):return "登月视觉阶段高度次序无效。"
 if float(data.destination_y)>=float(data.background_ground_y_m)-float(data.background_orbit_full_altitude_m):return "月面目标必须位于真实升空区上方。"
 if not data.get("ascent_layers") is Array or data.ascent_layers.size()!=4:return "登月环境需要四个连续高度阶段。"
 var previous:float=-INF
 for i in range(4):
  var layer:Variant=data.ascent_layers[i]
  if not layer is Dictionary or layer.get("phase")!=["ground","upper_air","space","lunar_approach"][i]:return "登月环境阶段无效。"
  for key in ["start_altitude_m","gravity","drag"]:
   if not _number(layer.get(key)):return "登月外场参数无效。"
  if float(layer.start_altitude_m)<=previous or float(layer.gravity)<0.0 or float(layer.gravity)>20.0 or float(layer.drag)<0.0 or float(layer.drag)>10.0 or not _pair(layer.get("wind")):return "登月外场超出有效范围。"
  if Vector2(layer.wind[0],layer.wind[1]).length()>10.0:return "登月横风超出有效范围。"
  previous=float(layer.start_altitude_m)
 if float(data.ascent_layers[0].start_altitude_m)!=0.0:return "登月地面阶段须从0米开始。"
 if not data.get("ascent_event_world_bounds") is Array or data.ascent_event_world_bounds.size()!=4:return "流星实体边界无效。"
 for value in data.ascent_event_world_bounds:
  if not _number(value):return "流星实体边界无效。"
 if float(data.ascent_event_world_bounds[2])<=0.0 or float(data.ascent_event_world_bounds[3])<=0.0:return "流星实体边界无效。"
 if not data.get("ascent_meteor_events") is Array or data.ascent_meteor_events.size()>MAX_EVENTS:return "流星事件数量无效。"
 var ids:Dictionary={}
 for event in data.ascent_meteor_events:
  if not event is Dictionary or not event.get("id") is String or event.id.is_empty() or ids.has(event.id):return "流星事件身份无效。"
  ids[event.id]=true
  for key in ["trigger_altitude_m","warning_seconds","radius","health","mass"]:
   if not _number(event.get(key)):return "流星事件物理字段缺失。"
  if float(event.trigger_altitude_m)<0.0 or float(event.trigger_altitude_m)>100000.0 or float(event.warning_seconds)<3.0 or float(event.warning_seconds)>30.0 or float(event.radius)<=0.0 or float(event.radius)>10.0 or float(event.health)<=0.0 or float(event.health)>10000.0 or float(event.mass)<=0.0 or float(event.mass)>10000.0 or not _pair(event.get("position")) or not _pair(event.get("velocity")):return "流星预警或物理范围无效。"
  if Vector2(event.velocity[0],event.velocity[1]).length()>100.0:return "流星速度无效。"
 return ""
static func _number(value:Variant)->bool:return (value is float or value is int) and is_finite(float(value)) and absf(float(value))<=1000000.0
static func _pair(value:Variant)->bool:return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])
static func _json_safe(value:Variant,depth:int=0)->bool:
 if depth>14:return false
 if value==null or value is bool or value is String:return true
 if value is int or value is float:return is_finite(float(value)) and absf(float(value))<=9007199254740991.0
 if value is Array:
  if value.size()>512:return false
  for child in value:
   if not _json_safe(child,depth+1):return false
  return true
 if value is Dictionary:
  if value.size()>256:return false
  for key in value:
   if not (key is String or key is StringName) or not _json_safe(value[key],depth+1):return false
  return true
 return false
static func environment_at(data:Dictionary,position:Vector2)->Dictionary:return AltitudeEnvironment.at(data,position)
static func starter_design()->Array:return Delivery.starter_design()
static func starter_launcher()->Array:return Delivery.starter_launcher()
