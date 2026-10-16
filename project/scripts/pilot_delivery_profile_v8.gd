extends RefCounted
## Future quotes only. Spatial protection fields are immutable route assumptions;
## the adapter copy retains v7 material and all older physical/economic policies.
const Legacy=preload("res://scripts/pilot_delivery_profile_v7.gd")
const VERSION:String="pilot-delivery-v8"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String=Legacy.INPUT_SCHEMA
const SCHEMA:String="delivery-flight-policy-v8"
const ENVIRONMENT:String="ground"
const SPATIAL_SHIELD_SCHEMA:String="cell-center-shield-v1"
const SHIELD_BASE_RADIUS_METRES:float=1.5
const SHIELD_RADIUS_POLICY:String="sqrt-material-area-v1"
const POLICIES:Dictionary={"spatial_shield_schema":SPATIAL_SHIELD_SCHEMA,"shield_base_radius_metres":SHIELD_BASE_RADIUS_METRES,"shield_radius_policy":SHIELD_RADIUS_POLICY}
const SHIELD_VERSIONS:Array[String]=["pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const SHIELD_FLIGHT_SCHEMAS:Array[String]=["delivery-flight-policy-v8","delivery-ascent-policy-v8","delivery-rift-policy-v8"]

static func route(base:Dictionary={})->Dictionary:return _route(base,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func has_markers(data:Dictionary)->bool:return _has_markers(data,VERSION,SCHEMA,ENVIRONMENT)
static func _has_markers(data:Dictionary,version:String,schema:String,environment:String)->bool:
 return (data.get("control_version") is String and data.control_version==version) or (data.get("pilot_profile") is String and data.pilot_profile==version) or (data.get("free_flight_schema") is String and data.free_flight_schema==schema) or (shield_markers(data) and data.get("cell_environment") is String and data.cell_environment==environment)
static func shield_markers(data:Dictionary)->bool:
 for key in ["control_version","pilot_profile"]:
  if data.get(key) is String and data[key] in SHIELD_VERSIONS:return true
 if data.get("free_flight_schema") is String and data.free_flight_schema in SHIELD_FLIGHT_SCHEMAS:return true
 for key in data:
  if str(key).begins_with("spatial_shield_") or str(key).begins_with("shield_"):return true
 return false
static func validation_error(data:Dictionary)->String:return _validation_error(data,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func compatibility_route(data:Dictionary)->Dictionary:return _compatibility_route(data,Legacy)
static func starter_design()->Array:return Legacy.starter_design()
static func starter_launcher()->Array:return Legacy.starter_launcher()

static func _route(base:Dictionary,legacy,version:String,schema:String,environment:String)->Dictionary:
 if shield_markers(base):return {}
 for key in ["contract_id","status","generation","accepted_day"]:
  if base.has(key):return {}
 var fresh:Dictionary=legacy.route(base)
 if fresh.is_empty():return {}
 fresh.merge(POLICIES,true);fresh.control_version=version;fresh.pilot_profile=version;fresh.free_flight_schema=schema
 return fresh if _validation_error(fresh,legacy,version,schema,environment).is_empty() else {}
static func _compatibility_route(data:Dictionary,legacy)->Dictionary:
 var result:Dictionary=data.duplicate(true)
 for key in POLICIES:result.erase(key)
 result.control_version=legacy.VERSION;result.pilot_profile=legacy.VERSION;result.free_flight_schema=legacy.SCHEMA
 return result
static func _validation_error(data:Dictionary,legacy,version:String,schema:String,environment:String)->String:
 for pair in [["control_version",version],["pilot_profile",version],["free_flight_schema",schema],["input_schema",INPUT_SCHEMA],["cell_environment",environment],["route_kind",environment]]:
  if not data.get(pair[0]) is String or data[pair[0]]!=pair[1]:return "空间护盾与驾驶环境身份不一致。"
 for key in ["spatial_shield_schema","shield_radius_policy"]:
  if not data.get(key) is String or data[key]!=POLICIES[key]:return "空间护盾覆盖规则记录不完整。"
 var radius:Variant=data.get("shield_base_radius_metres")
 if not (radius is int or radius is float) or not is_finite(float(radius)) or float(radius)!=SHIELD_BASE_RADIUS_METRES:return "空间护盾半径与冻结规则不一致。"
 for key in data:
  if (str(key).begins_with("spatial_shield_") or str(key).begins_with("shield_")) and not POLICIES.has(key):return "未知空间护盾规则字段。"
 return legacy.validation_error(_compatibility_route(data,legacy))
