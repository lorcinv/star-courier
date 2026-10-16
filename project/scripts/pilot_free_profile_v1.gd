extends RefCounted
## Explicit NEW ordinary contracts only. Never run route() on an existing offer/save.
## Full-swivel nozzles are a new paid mechanical capability, not a legacy upgrade.
const VERSION = "pilot-free-v1"
const CONTROL_VERSION = VERSION
const INPUT_SCHEMA = "free-flight-input-v1"
const SCHEMA = "free-flight-policy-v1"
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const FreeGround = preload("res://scripts/pilot_free_ground_route_v1.gd")
const BirdOffer = preload("res://scripts/protected_bird_offer_v1.gd")
const PirateProtocols = preload("res://scripts/pirate_protocols.gd")
const PirateOffer = preload("res://scripts/pirate_sidejob_offer_v1.gd")
const Moon = preload("res://scripts/pilot_moon_profile.gd")
const Meteor = preload("res://scripts/orbital_meteor_offers.gd")
const MARKERS = {
 "mode":"pilot", "control_version":VERSION, "pilot_profile":VERSION,
 "free_flight_schema":SCHEMA, "input_schema":INPUT_SCHEMA,
 "delivery_policy":"any-direction-safe-arrival-v1",
 "energy_policy":"cargo-connected-empty-fails-v1",
 "nozzle_policy":"paid-full-swivel-v1",
 "recovery_policy":"failed-survivors-rescued-v1"
}
const TUNING = {
 "free_cruise_speed":12.0, "free_boost_speed":18.0, "free_response_seconds":0.30,
 "free_brake_seconds":0.24, "free_net_force_limit":42.0,
 "free_cruise_throttle":0.90, "free_gimbal_degrees":180.0,
 "free_gimbal_slew_degrees":720.0
}

static func route(base:Dictionary) -> Dictionary:
 # Conversion is only valid before identity/acceptance/generation is committed.
 if base.has("contract_id") or base.has("status") or base.has("generation") or has_markers(base) or _special(base):return {}
 var result:Dictionary=FreeGround.author(base) if base.get("route_profile")==FreeGround.SOURCE_PROFILE and base.get("route_kind")=="ground" else base.duplicate(true)
 if result.is_empty():return {}
 result.merge(MARKERS,true);result.merge(TUNING,true)
 # Reuse v3's finite capacity and tariff; no recharge or capacity grant midflight.
 result.pilot_battery_multiplier=20.0;result.pilot_energy_tariff=0.025
 result.pilot_overdrive="mounted-output"
 return result if validation_error(result).is_empty() else {}

static func has_markers(data:Dictionary) -> bool:
 return data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.has("free_flight_schema") or data.has("nozzle_policy") or data.has("input_schema") or data.has("delivery_policy") or data.has("energy_policy") or data.has("recovery_policy") or FreeGround.has_markers(data)

static func validation_error(data:Dictionary) -> String:
 for key in MARKERS:
  if not data.get(key) is String or data[key]!=MARKERS[key]:return "自由飞行规则记录不一致。"
 if data.has("generation") or _special(data):return "特殊航行记录不能改为普通自由飞行。"
 for key in ["route_profile","route_kind","destination_id"]:
  if data.has(key) and not data[key] is String:return "自由飞行身份字段无效。"
 for key in data:
  if key is String and key.begins_with("free_") and key not in ["free_flight_schema","free_ground_schema"] and not TUNING.has(key):return "自由飞行规则版本不支持。"
 if FreeGround.has_markers(data):
  var ground_error:String=FreeGround.validation_error(data)
  if not ground_error.is_empty():return ground_error
 for key in TUNING:
  if not _number(data.get(key)) or float(data[key])!=float(TUNING[key]):return "自由飞行操控参数不一致。"
 for key in ["distance","destination_y","delivery_radius","max_delivery_speed","pilot_battery_multiplier","pilot_energy_tariff"]:
  if not _number(data.get(key)):return "自由飞行目的地或能量参数缺失。"
 if absf(float(data.distance))>100000.0 or absf(float(data.destination_y))>100000.0:return "自由飞行目的地超出有效范围。"
 if float(data.delivery_radius)<=0.0 or float(data.delivery_radius)>1000.0:return "收件范围无效。"
 if float(data.max_delivery_speed)<=0.0 or float(data.max_delivery_speed)>1000.0:return "收件速度无效。"
 if float(data.pilot_battery_multiplier)!=20.0 or float(data.pilot_energy_tariff)!=0.025:return "自由飞行能量规则不一致。"
 if not data.get("hazards") is Array or data.hazards.size()>512:return "障碍记录无效。"
 for h in data.hazards:
  if not h is Dictionary:return "障碍记录无效。"
  for key in ["x","y","radius"]:
   if not _number(h.get(key)):return "障碍坐标无效。"
  if absf(float(h.x))>100000.0 or absf(float(h.y))>100000.0 or float(h.radius)<=0.0 or float(h.radius)>1000.0:return "障碍范围无效。"
  if not h.get("type") is String or h.type not in ["rock","gravity","turret","tracker","pirate"]:return "障碍类型无效。"
  for key in ["health","mass","damage","strength","cooldown"]:
   if h.has(key) and (not _number(h[key]) or absf(float(h[key]))>1000000000.0):return "障碍参数无效。"
  for key in ["position","velocity"]:
   if h.has(key) and not _vector_valid(h[key]):return "障碍运动参数无效。"
 for key in ["weight","gravity","variation","pilot_drag","battery_capacity_multiplier"]:
  if data.has(key) and not _number(data[key]):return "自由飞行环境参数无效。"
 if data.has("weight") and (float(data.weight)<=0.0 or float(data.weight)>1000.0):return "货物质量无效。"
 if data.has("gravity") and absf(float(data.gravity))>10000.0:return "重力参数无效。"
 if data.has("variation") and (float(data.variation)<0.0 or float(data.variation)>100.0):return "障碍变化范围无效。"
 if data.has("pilot_drag") and (float(data.pilot_drag)<0.0 or float(data.pilot_drag)>100.0):return "阻力参数无效。"
 if data.has("battery_capacity_multiplier") and (float(data.battery_capacity_multiplier)<1.0 or float(data.battery_capacity_multiplier)>1.45):return "电池容量参数无效。"
 if data.has("wind") and not _vector_valid(data.wind):return "风力参数无效。"
 return ""

static func _special(data:Dictionary) -> bool:
 if BirdOffer.has_markers(data) or PirateProtocols.has_markers(data) or PirateOffer.has_markers(data) or Moon.has_moon_markers(data) or Meteor.has_markers(data):return true
 for key in ["wormhole_portal","wormhole_schema","ecology","pirate_encounter","pirate_schema","wildlife_offer","moon_surface_y"]:
  if data.has(key):return true
 var version:String=str(data.get("control_version",""))
 return (not version.is_empty() and version not in ["pilot-v1","pilot-v2","pilot-v3",VERSION]) or str(data.get("route_kind","")) in ["moon","wormhole","otherworld","pirate"]

static func _vector_valid(value:Variant) -> bool:
 if value is Vector2:return value.is_finite() and absf(value.x)<=100000.0 and absf(value.y)<=100000.0
 return value is Array and value.size()==2 and _number(value[0]) and _number(value[1]) and absf(float(value[0]))<=100000.0 and absf(float(value[1]))<=100000.0

static func _number(value:Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value))

static func starter_design() -> Array:return Extreme.starter_design()
static func starter_launcher() -> Array:return Extreme.starter_launcher()
