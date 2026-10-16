extends RefCounted
## New ordinary ground content only. Snapshot-bound; never reconstruct on load.
## One actual rock offers open detours or paid physical drilling, not a gate.
const SCHEMA="free-ground-choice-v1"
const ROUTE_PROFILE=SCHEMA
const SOURCE_PROFILE="ground-city-v1"
const DESTINATION=Vector2(260.0,-8.0)
const DELIVERY_RADIUS=7.0
const MAX_DELIVERY_SPEED=24.0
const ROCK={"id":"free-ground-rock-01","x":128.0,"y":-4.0,"radius":3.25,"type":"rock","health":48.0,"mass":40.0,"destructible":true,"conductive":true}

static func author(base:Dictionary) -> Dictionary:
 if base.has("contract_id") or base.has("status") or base.has("generation") or base.get("route_profile")!=SOURCE_PROFILE or base.get("route_kind")!="ground" or has_markers(base):return {}
 var result:Dictionary=base.duplicate(true)
 result.route_profile=ROUTE_PROFILE;result.free_ground_schema=SCHEMA
 result.distance=DESTINATION.x;result.destination_y=DESTINATION.y
 result.delivery_radius=DELIVERY_RADIUS;result.max_delivery_speed=MAX_DELIVERY_SPEED
 result.hazards=[ROCK.duplicate(true)];result.pilot_gates=[]
 result.variation=0.0
 result.risk="一块浮石挡在前方；可上下绕行，也可减速后用接触钻头破开。"
 return result

static func has_markers(data:Dictionary) -> bool:
 return data.has("free_ground_schema") or (data.get("route_profile") is String and data.route_profile.begins_with("free-ground-choice-"))

static func validation_error(data:Dictionary) -> String:
 if data.get("free_ground_schema")!=SCHEMA or data.get("route_profile")!=ROUTE_PROFILE or data.get("route_kind")!="ground":return "普通自由航行场景记录不一致。"
 if not _same_number(data.get("distance"),DESTINATION.x) or not _same_number(data.get("destination_y"),DESTINATION.y) or not _same_number(data.get("variation"),0.0):return "普通自由航行目的地记录不一致。"
 if not _same_number(data.get("delivery_radius"),DELIVERY_RADIUS) or not _same_number(data.get("max_delivery_speed"),MAX_DELIVERY_SPEED):return "普通自由航行收件规则不一致。"
 if not data.get("pilot_gates") is Array or not data.pilot_gates.is_empty():return "自由航行场景不能添加必经门。"
 if not data.get("hazards") is Array or data.hazards.size()!=1 or not data.hazards[0] is Dictionary:return "自由航行岩石记录缺失。"
 var rock:Dictionary=data.hazards[0]
 if rock.size()!=ROCK.size():return "自由航行岩石记录不完整。"
 for key in ROCK:
  var expected:Variant=ROCK[key]
  if expected is float:
   if not _same_number(rock.get(key),expected):return "自由航行岩石物理参数不一致。"
  elif typeof(rock.get(key))!=typeof(expected) or rock[key]!=expected:return "自由航行岩石记录不一致。"
 return ""

static func _same_number(value:Variant,expected:float) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==expected
