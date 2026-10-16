extends RefCounted
## A fresh ordinary environment for free-v2; never a migration of legacy
## wormhole, otherworld or protected-bird content. Uses existing forces/rocks.
const CATALOG_ID:int=7
const SOURCE_PROFILE:String="mosslight-route-source-v2"
const ROUTE_PROFILE:String="mosslight-route-v2"
const SCHEMA:String="mosslight-route-v2"
const CONTROL_VERSION:String="pilot-free-v2"
const DESTINATION_ID:String="mosslight-delivery-platform-v2"
const DESTINATION:Vector2=Vector2(270.0,-18.0)
const DELIVERY_RADIUS:float=7.0
const MAX_DELIVERY_SPEED:float=24.0
const ART_SCHEMA:String="mosslight-art-v2"
const FIELDS:Dictionary={
 "route_profile":ROUTE_PROFILE,"mosslight_schema":SCHEMA,"route_kind":"mosslight",
 "destination_id":DESTINATION_ID,"destination_name":"苔光温室收件台",
 "name":"城市货站 → 苔光温室","distance":270.0,"destination_y":-18.0,
 "delivery_radius":7.0,"max_delivery_speed":24.0,"gravity":0.16,
 "wind":[0.32,0.0],"variation":0.0,"pilot_drag":0.025,
 "boundary_y":230.0,"time_limit":110.0,"deadline":85.0,
 "pilot_altitude":18.0,"pilot_climb_start":20.0,"pilot_climb_end":230.0,
 "lookahead_seconds":3.5,"background_route":"city",
 "mosslight_art_schema":ART_SCHEMA,
 "mosslight_backdrop_begin_x":32.0,"mosslight_backdrop_full_x":72.0,
 "mosslight_receiver":{"id":DESTINATION_ID,"capture_center":[270.0,-18.0],
  "capture_radius":7.0,"entry":"any-direction","art":"mosslight/receiver-greenhouse.png",
  "native_size":[1254.0,1254.0],"capture_anchor_native":[627.0,509.4375],"capture_radius_native":380.0},
 "mosslight_hint":"侧风会向右推，飞行器也会缓慢下坠；上下绕开岩石，接近温室时按 Ctrl 刹车，飞过头可逆风返回。"
}
const HAZARDS:Array=[
 {"id":"mosslight-rock-west-v2","x":90.0,"y":-14.0,"radius":3.5,
  "type":"rock","health":42.0,"mass":30.0,"destructible":true,"conductive":true,
  "mosslight_role":"rock","mosslight_art":"rock-1"},
 {"id":"mosslight-rock-middle-v2","x":145.0,"y":-24.0,"radius":4.0,
  "type":"rock","health":48.0,"mass":36.0,"destructible":true,"conductive":true,
  "mosslight_role":"rock","mosslight_art":"rock-2"},
 {"id":"mosslight-rock-east-v2","x":198.0,"y":-12.0,"radius":3.75,
  "type":"rock","health":42.0,"mass":30.0,"destructible":true,"conductive":true,
  "mosslight_role":"rock","mosslight_art":"rock-1"}
]

static func fresh_catalog() -> Dictionary:
 return {"id":CATALOG_ID,"route_profile":SOURCE_PROFILE,"route_kind":"mosslight",
  "client":"米洛","cargo":"温室育苗盘","weight":1.25,"reward":350,
  "rep":4,"required":85.0,"story":"温室在岩石后面，育苗盘请平稳送来。"}

static func author(base:Dictionary) -> Dictionary:
 if base.get("route_profile")!=SOURCE_PROFILE or base.get("route_kind")!="mosslight":return {}
 for key in base:
  if key not in ["id","route_profile","route_kind","client","cargo","weight","reward","rep","required","story"]:return {}
 if not _same(base.get("id"),CATALOG_ID) or not _json_safe(base):return {}
 var result:Dictionary=base.duplicate(true)
 result.merge(FIELDS,true)
 result["hazards"]=HAZARDS.duplicate(true);result["pilot_gates"]=[]
 result["risk"]="恒定侧风 · 缓慢下坠 · 岩石上下均可绕行"
 return result if validation_error(result).is_empty() else {}

static func has_markers(data:Dictionary) -> bool:
 # The new ID itself is reserved. Removing text markers cannot reinterpret
 # an incomplete ID7 snapshot through a historical generic route reader.
 return _same(data.get("id"),CATALOG_ID) or _scan_markers(data,0)

static func _scan_markers(value:Variant,depth:int) -> bool:
 # Recognition must not classify unrelated deep legacy metadata as new
 # content. Known content has its separate, strict12-level JSON validator.
 # Scan beyond the existing16-level presentation limit without changing it.
 if depth>32:return false
 if value is Dictionary:
  for key in value:
   var name:String=str(key)
   if name=="mosslight" or name.begins_with("mosslight_"):return true
   var child:Variant=value[key]
   # Legacy mosslight-protected-bird-v1 remains its own untouched protocol.
   if name in ["route_profile","destination_id"] and child is String and (child.begins_with("mosslight-route-") or child.begins_with("mosslight-delivery-")):return true
   if name=="route_kind" and child=="mosslight":return true
   if (child is Dictionary or child is Array) and _scan_markers(child,depth+1):return true
 elif value is Array:
  for child in value:
   if (child is Dictionary or child is Array) and _scan_markers(child,depth+1):return true
 return false

static func validation_error(data:Dictionary) -> String:
 if not _json_safe(data):return "苔光温室记录包含无效数据。"
 if data.has("variant") and (not data.variant is String or data.variant not in ["标准件","重货件"]):return "苔光温室委托类型不支持。"
 for key in FIELDS:
  var expected:Variant=FIELDS[key]
  if key=="deadline" and data.get("variant")=="重货件":expected=88.0
  if not _same(data.get(key),expected):return "苔光温室航线参数不一致："+str(key)
 if not _same(data.get("id"),CATALOG_ID):return "苔光温室委托身份不一致。"
 if not data.get("pilot_gates") is Array or not data.pilot_gates.is_empty():return "苔光自由航线不能添加必经门。"
 if not _same(data.get("hazards"),HAZARDS):return "苔光岩石记录不一致。"
 for key in data:
  if (str(key)=="mosslight" or str(key).begins_with("mosslight_")) and not FIELDS.has(key):return "苔光温室记录版本不支持。"
  if not FIELDS.has(key) and str(key)!="hazards" and (data[key] is Dictionary or data[key] is Array) and _scan_markers(data[key],1):return "苔光温室记录包含额外内容标记。"
 if _foreign_markers(data):return "苔光温室与其他特殊航线记录混杂。"
 for key in ["weight","required","reward","rep"]:
  if not _number(data.get(key)) or float(data[key])<0.0:return "苔光委托货物或费用无效。"
 if float(data.weight)<=0.0 or float(data.weight)>8.0 or float(data.required)>100.0:return "苔光委托货物参数无效。"
 if not _same(data.rep,4):return "苔光委托声望要求不一致。"
 for key in ["client","cargo","story","risk"]:
  if not data.get(key) is String or data[key].strip_edges().is_empty() or data[key].length()>400:return "苔光委托说明缺失。"
 return ""

static func _foreign_markers(value:Variant) -> bool:
 if value is Dictionary:
  for key in value:
   var name:String=str(key)
   if name in ["generation","orbital_event","pirate_encounter","ecology","wildlife_offer","moon","lunar","free_ground_schema"] or name.begins_with("moon_") or name.begins_with("lunar_") or name.begins_with("wormhole") or name.begins_with("otherworld") or name.begins_with("protected_bird") or name.begins_with("pirate_") or name.begins_with("ecology_") or name.begins_with("meteor_"):return true
   if _foreign_markers(value[key]):return true
 elif value is Array:
  for item in value:
   if _foreign_markers(item):return true
 return false

static func _same(a:Variant,b:Variant) -> bool:
 if _number(a) and _number(b):return float(a)==float(b)
 if typeof(a)!=typeof(b):return false
 if a is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not _same(a[key],b[key]):return false
  return true
 if a is Array:
  if a.size()!=b.size():return false
  for index in range(a.size()):
   if not _same(a[index],b[index]):return false
  return true
 return a==b

static func _number(value:Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value))

static func _json_safe(value:Variant,depth:int=0) -> bool:
 if depth>12:return false
 if value is Dictionary:
  for key in value:
   if not (key is String or key is StringName) or not _json_safe(value[key],depth+1):return false
  return true
 if value is Array:
  for item in value:
   if not _json_safe(item,depth+1):return false
  return true
 return value==null or value is String or value is bool or _number(value)
