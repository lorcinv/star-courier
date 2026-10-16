extends RefCounted
## Frozen explicit rift identity. Existing v3/v4 orders cannot ignore these rules.
const Delivery=preload("res://scripts/pilot_delivery_profile_v3.gd")
const VERSION:String="pilot-rift-v5"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String="free-flight-input-v2"
const SCHEMA:String="delivery-rift-policy-v1"
const ROUTE_PROFILE:String="delivery-greenhouse-rift-v1"
const DESTINATION_ID:String="rift-greenhouse-receiver-v1"
const PORTAL_ID:String="rift-greenhouse-gate-v1"
const PORTAL_SCHEMA:String="whole-body-section-transit-v1"
const THREAT_SCHEMA:String="finite-pirate-periodic-field-v1"
const BIOLOGY_SCHEMA:String="continuous-cold-exposure-v1"

static func route(base:Dictionary={})->Dictionary:
 for key in ["contract_id","status","generation","control_version","pilot_profile","free_flight_schema","rift_portal"]:
  if base.has(key):return {}
 var source:Dictionary={"name":"第五关 · 穿门护送生物货","destination_name":"裂隙苔光温室","weight":1.0,"min_delivery_integrity":0.8,"cargo_safe_acceleration":40.0,"cargo_damage_per_excess_mps":0.5,"cargo_contact_damage_scale":1.0}
 source.merge(base,true)
 source.merge({"route_kind":"rift","route_profile":ROUTE_PROFILE,"destination_id":DESTINATION_ID,"background_route":"rift",
  "distance":200.0,"destination_y":0.0,"delivery_radius":8.0,"max_delivery_speed":8.0,
  "gravity":0.0,"wind":[0.0,0.0],"pilot_drag":0.0,"variation":0.0,"hazards":[],"pilot_gates":[],
  "rift_portal_schema":PORTAL_SCHEMA,"rift_threat_schema":THREAT_SCHEMA,"rift_biology_schema":BIOLOGY_SCHEMA,"required_portal_id":PORTAL_ID,
  "rift_portal":{"id":PORTAL_ID,"entry":[28.0,0.0],"exit":[100.0,0.0],"aperture_radius":5.0,"margin":0.25,"exit_lookahead":0.18},
  "rift_pirate":{"position":[154.0,-20.0],"radius":1.5,"health":40.0,"mass":6.0,"ammo":2,"warning_seconds":2.75,"cooldown_seconds":1.5,"range":65.0,"damage":12.0},
  "rift_turbulence":{"bounds":[132.0,-10.0,35.0,20.0],"period_seconds":7.0,"active_seconds":3.0,"peak_force":18.0,"peak_torque":10.0},
  "rift_biology":{"cold_bounds":[130.0,-10.0,40.0,20.0],"warm_temperature_c":18.0,"cold_temperature_c":-12.0,"grace_seconds":2.5,"damage_hp_per_second":3.0},
  "risk":"对准入口整船过门。门后海盗有限弹药、开火前预警；冷区停留超宽限会伤生物货，暖区可绕行；乱流有边界与周期。收件前减速。"},true)
 var result:Dictionary=Delivery.route(source)
 if result.is_empty():return {}
 result.control_version=VERSION;result.pilot_profile=VERSION;result.free_flight_schema=SCHEMA
 return result if validation_error(result).is_empty() else {}

static func has_markers(data:Dictionary)->bool:
 if data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.get("free_flight_schema")==SCHEMA or data.get("route_profile")==ROUTE_PROFILE:return true
 for key in data:
  if str(key).begins_with("rift_") or key=="required_portal_id":return true
 return false
static func compatibility_route(data:Dictionary)->Dictionary:
 var local:Dictionary=data.duplicate(true);local.merge(Delivery.MARKERS,true);return local
static func validation_error(data:Dictionary)->String:
 for entry in [["control_version",VERSION],["pilot_profile",VERSION],["input_schema",INPUT_SCHEMA],["free_flight_schema",SCHEMA],["route_kind","rift"],["route_profile",ROUTE_PROFILE],["destination_id",DESTINATION_ID],["background_route","rift"],["required_portal_id",PORTAL_ID],["rift_portal_schema",PORTAL_SCHEMA],["rift_threat_schema",THREAT_SCHEMA],["rift_biology_schema",BIOLOGY_SCHEMA]]:
  if data.get(entry[0])!=entry[1]:return "裂隙运输协议或环境身份不一致。"
 var error:String=Delivery.validation_error(compatibility_route(data))
 if not error.is_empty():return error
 if not _json_safe(data):return "裂隙路线含无效数据。"
 if not data.get("rift_portal") is Dictionary:return "缺少实体门户。"
 var gate:Dictionary=data.rift_portal
 if gate.get("id")!=PORTAL_ID or not _pair(gate.get("entry")) or not _pair(gate.get("exit")):return "门户位置或身份无效。"
 for key in ["aperture_radius","margin","exit_lookahead"]:
  if not _number(gate.get(key)):return "门户包络或出口安全参数无效。"
 if float(gate.entry[0])<=4.0 or float(gate.exit[0])<=float(gate.entry[0])+10.0 or float(gate.exit[0])>=float(data.distance)-10.0 or float(gate.aperture_radius)<1.0 or float(gate.aperture_radius)>15.0 or float(gate.margin)<0.05 or float(gate.margin)>=float(gate.aperture_radius) or float(gate.exit_lookahead)<0.1 or float(gate.exit_lookahead)>2.0:return "门户通道或净空范围无效。"
 if not data.get("rift_pirate") is Dictionary or not data.get("rift_turbulence") is Dictionary or not data.get("rift_biology") is Dictionary:return "裂隙威胁配置缺失。"
 var pirate:Dictionary=data.rift_pirate
 if not _pair(pirate.get("position")):return "海盗位置无效。"
 for key in ["radius","health","mass","ammo","warning_seconds","cooldown_seconds","range","damage"]:
  if not _number(pirate.get(key)):return "海盗有限武器参数无效。"
 if pirate.ammo!=floor(float(pirate.ammo)) or pirate.ammo<1 or pirate.ammo>4 or pirate.warning_seconds<2.0 or pirate.warning_seconds>10.0 or pirate.cooldown_seconds<0.5 or pirate.cooldown_seconds>10.0 or pirate.radius<=0 or pirate.radius>5 or pirate.health<=0 or pirate.health>1000 or pirate.mass<=0 or pirate.mass>1000 or pirate.range<1 or pirate.range>100 or pirate.damage<=0 or pirate.damage>100:return "海盗武器或实体超出范围。"
 var field:Dictionary=data.rift_turbulence
 if not _bounds(field.get("bounds")):return "乱流边界无效。"
 for key in ["period_seconds","active_seconds","peak_force","peak_torque"]:
  if not _number(field.get(key)):return "乱流周期或受力无效。"
 if field.period_seconds<1 or field.period_seconds>60 or field.active_seconds<=0 or field.active_seconds>field.period_seconds or field.peak_force<0 or field.peak_force>100 or field.peak_torque<0 or field.peak_torque>100:return "乱流参数超出范围。"
 var bio:Dictionary=data.rift_biology
 if not _bounds(bio.get("cold_bounds")):return "生物货冷区边界无效。"
 for key in ["warm_temperature_c","cold_temperature_c","grace_seconds","damage_hp_per_second"]:
  if not _number(bio.get(key)):return "生物环境耐受参数无效。"
 if bio.cold_temperature_c>=bio.warm_temperature_c or bio.grace_seconds<0 or bio.grace_seconds>30 or bio.damage_hp_per_second<=0 or bio.damage_hp_per_second>20:return "生物冷区耐受超出范围。"
 return ""
static func _number(value:Variant)->bool:return (value is float or value is int) and is_finite(float(value)) and absf(float(value))<=1000000.0
static func _pair(value:Variant)->bool:return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])
static func _bounds(value:Variant)->bool:
 if not value is Array or value.size()!=4:return false
 for v in value:
  if not _number(v):return false
 return float(value[2])>0 and float(value[3])>0 and float(value[2])<=200 and float(value[3])<=200
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
static func starter_design()->Array:return Delivery.starter_design()
static func starter_launcher()->Array:return Delivery.starter_launcher()
