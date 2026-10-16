extends RefCounted
## New short lunar content only; this never restores or upgrades legacy Moon saves.
## Pure immutable authoring and read-only validation. The v2 free-flight solver
## remains responsible for gravity, paid nozzles, physical rock contacts and receipt.
const CATALOG_ID:int=6 # id5 remains reserved for the immutable pirate side job.
const SOURCE_PROFILE:String="lunar-outpost-source-v2"
const ROUTE_PROFILE:String="lunar-outpost-v2"
const SCHEMA:String="lunar-outpost-v2"
const CONTROL_VERSION:String="pilot-free-v2"
const DESTINATION_ID:String="lunar-delivery-platform-v2"
const DESTINATION:Vector2=Vector2(250.0,-40.0)
const DELIVERY_RADIUS:float=7.0
const MAX_DELIVERY_SPEED:float=24.0
const ART_SCHEMA:String="lunar-outpost-art-v2"
const FIELDS:Dictionary={
 "route_profile":ROUTE_PROFILE,"lunar_schema":SCHEMA,"route_kind":"lunar",
 "destination_id":DESTINATION_ID,"destination_name":"月面前哨收件台",
 "name":"城市货站 → 月面前哨","distance":250.0,"destination_y":-40.0,
 "delivery_radius":7.0,"max_delivery_speed":24.0,"gravity":0.20,
 "wind":[0.0,0.0],"variation":0.0,"pilot_drag":0.025,
 "boundary_y":230.0,"time_limit":110.0,"deadline":80.0,
 "pilot_altitude":40.0,"pilot_climb_start":20.0,"pilot_climb_end":210.0,
 "lookahead_seconds":3.5,"background_route":"city",
 "lunar_art_schema":ART_SCHEMA,
 "lunar_backdrop_begin_x":32.0,"lunar_backdrop_full_x":72.0,
 "lunar_receiver":{"id":DESTINATION_ID,"capture_center":[250.0,-40.0],
  "capture_radius":7.0,"entry":"any-direction","art":"flight/receiver.png",
  "native_size":[279.0,220.0],"deck_anchor_native":[139.5,149.0],
  "deck_clearance_m":6.0,"art_width_m":8.0},
 "lunar_hint":"月面低重力会让飞行器缓慢下坠。轻装可上下绕开矿石；钻头要慢速接触，护盾会耗电吸收部分碰撞。接近前哨时按 Ctrl 刹车，或用反向推力减速；飞过头也能返回。"
}
const HAZARDS:Array=[
 {"id":"lunar-ore-west-v2","x":95.0,"y":-15.0,"radius":3.75,
  "type":"rock","health":42.0,"mass":30.0,"destructible":true,"conductive":true,
  "lunar_role":"ore","lunar_art":"rock-1"},
 {"id":"lunar-ore-east-v2","x":165.0,"y":-26.0,"radius":4.0,
  "type":"rock","health":48.0,"mass":36.0,"destructible":true,"conductive":true,
  "lunar_role":"ore","lunar_art":"rock-2"},
 {"id":"lunar-drifter-v2","x":144.0,"y":-57.0,"radius":1.0,
  "velocity":[-0.25,0.75],"type":"rock","health":24.0,"mass":8.0,
  "destructible":true,"conductive":true,"lunar_role":"drifter","lunar_art":"rock-1"}
]

static func fresh_catalog() -> Dictionary:
 # A separate catalog identity avoids the legacy id-4 moon-surface-v1 branch.
 return {"id":CATALOG_ID,"route_profile":SOURCE_PROFILE,"route_kind":"lunar",
  "client":"小满","cargo":"月面前哨补给","weight":1.25,"reward":330,
  "rep":2,"required":85.0,"story":"把这箱补给送到月面前哨。两块矿石之间有一小片漂石，别急着冲过去。"}

static func author(base:Dictionary) -> Dictionary:
 if base.get("route_profile")!=SOURCE_PROFILE or base.get("route_kind")!="lunar":return {}
 for key in base:
  if key not in ["id","route_profile","route_kind","client","cargo","weight","reward","rep","required","story"]:return {}
 if not _same(base.get("id"),CATALOG_ID) or not _json_safe(base):return {}
 var result:Dictionary=base.duplicate(true)
 result.merge(FIELDS,true)
 result["hazards"]=HAZARDS.duplicate(true);result["pilot_gates"]=[]
 result["risk"]="月面低重力 · 矿石可绕行或慢速钻切 · 小心漂石 · 可从两侧返回收件"
 return result if validation_error(result).is_empty() else {}

static func has_markers(data:Dictionary) -> bool:
 return _scan_markers(data,0)

static func _scan_markers(value:Variant,depth:int) -> bool:
 if depth>12:return true
 if value is Dictionary:
  for key in value:
   var name:String=str(key)
   if name=="lunar" or name.begins_with("lunar_"):return true
   var child:Variant=value[key]
   if name in ["route_profile","destination_id"] and child is String and child.begins_with("lunar-"):return true
   if name=="route_kind" and child=="lunar":return true
   if (child is Dictionary or child is Array) and _scan_markers(child,depth+1):return true
 elif value is Array:
  for child in value:
   if (child is Dictionary or child is Array) and _scan_markers(child,depth+1):return true
 return false

static func validation_error(data:Dictionary) -> String:
 if not _json_safe(data):return "月面前哨记录包含无效数据。"
 # The existing Economy author gives the B-slot heavy parcel exactly +3 s.
 # This is a commercial deadline only; gravity, geometry and time_limit stay
 # byte-for-byte fixed. No unrelated or future commercial variant is accepted.
 if data.has("variant") and (not data.variant is String or data.variant not in ["标准件","重货件"]):return "月面前哨委托类型不支持。"
 for key in FIELDS:
  var expected:Variant=FIELDS[key]
  if key=="deadline" and data.get("variant")=="重货件":expected=83.0
  if not _same(data.get(key),expected):return "月面前哨航线参数不一致："+str(key)
 if not _same(data.get("id"),CATALOG_ID):return "月面前哨委托身份不一致。"
 if not data.get("pilot_gates") is Array or not data.pilot_gates.is_empty():return "月面自由航线不能添加必经门。"
 if not _same(data.get("hazards"),HAZARDS):return "月面矿石与漂石记录不一致。"
 for key in data:
  if str(key).begins_with("lunar_") and not FIELDS.has(key):return "月面前哨记录版本不支持。"
 if _foreign_markers(data):return "月面前哨与旧版特殊航线记录混杂。"
 for key in ["weight","required","reward","rep"]:
  if not _number(data.get(key)) or float(data[key])<0.0:return "月面委托货物或费用无效。"
 if float(data.weight)<=0.0 or float(data.weight)>8.0 or float(data.required)>100.0:return "月面委托货物参数无效。"
 for key in ["client","cargo","story","risk"]:
  if not data.get(key) is String or data[key].strip_edges().is_empty() or data[key].length()>400:return "月面委托说明缺失。"
 return ""

static func _foreign_markers(value:Variant) -> bool:
 if value is Dictionary:
  for key in value:
   var name:String=str(key)
   if name in ["generation","orbital_event","pirate_encounter","ecology","wildlife_offer","moon"] or name.begins_with("moon_") or name.begins_with("wormhole") or name.begins_with("otherworld") or name.begins_with("protected_bird") or name.begins_with("pirate_"):return true
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
 # Runtime Dictionary dot writes use StringName keys; both key types encode
 # as JSON strings. Values remain strictly JSON-safe, finite and depth-bounded.
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
