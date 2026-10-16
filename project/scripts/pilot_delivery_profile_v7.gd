extends RefCounted
## Future contracts only. Material assumptions are frozen in the route; adapters
## validate before taking a private same-environment v6 compatibility copy.
const Legacy=preload("res://scripts/pilot_delivery_profile_v6.gd")
const VERSION:String="pilot-delivery-v7"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String=Legacy.INPUT_SCHEMA
const SCHEMA:String="delivery-flight-policy-v7"
const ENVIRONMENT:String="ground"
const MATERIAL_RULES_SCHEMA:String="parallel-material-v1"
const MATERIAL_GEOMETRY_POLICY:String="constant-working-length-v1"
const POLICIES:Dictionary={"material_rules_schema":MATERIAL_RULES_SCHEMA,"material_geometry_policy":MATERIAL_GEOMETRY_POLICY,"damper_reference_mass_kg":1.0,"damper_reference_inertia_kg_m2":1.0}
const MATERIAL_VERSIONS:Array[String]=["pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7"]
const MATERIAL_FLIGHT_SCHEMAS:Array[String]=["delivery-flight-policy-v7","delivery-ascent-policy-v7","delivery-rift-policy-v7"]

static func route(base:Dictionary={})->Dictionary:return _route(base,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func has_markers(data:Dictionary)->bool:
 return data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.get("free_flight_schema")==SCHEMA or (material_markers(data) and data.get("cell_environment")==ENVIRONMENT)
static func material_markers(data:Dictionary)->bool:
 for key in ["control_version","pilot_profile"]:
  if data.get(key) is String and data[key] in MATERIAL_VERSIONS:return true
 if data.get("free_flight_schema") is String and data.free_flight_schema in MATERIAL_FLIGHT_SCHEMAS:return true
 for key in data:
  if str(key).begins_with("material_") or str(key).begins_with("damper_reference_"):return true
 return false
static func validation_error(data:Dictionary)->String:return _validation_error(data,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func compatibility_route(data:Dictionary)->Dictionary:return _compatibility_route(data,Legacy)
static func starter_design()->Array:return Legacy.starter_design()
static func starter_launcher()->Array:return Legacy.starter_launcher()

static func _route(base:Dictionary,legacy,version:String,schema:String,environment:String)->Dictionary:
 if material_markers(base):return {}
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
  if not data.get(pair[0]) is String or data[pair[0]]!=pair[1]:return "材料响应与驾驶环境身份不一致。"
 for key in ["material_rules_schema","material_geometry_policy"]:
  if not data.get(key) is String or data[key]!=POLICIES[key]:return "材料缩放假设记录不完整。"
 for key in ["damper_reference_mass_kg","damper_reference_inertia_kg_m2"]:
  var value:Variant=data.get(key)
  if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=float(POLICIES[key]):return "阻尼参考单位与冻结规则不一致。"
 for key in data:
  if (str(key).begins_with("material_") or str(key).begins_with("damper_reference_")) and not POLICIES.has(key):return "未知材料响应规则字段。"
 return legacy.validation_error(_compatibility_route(data,legacy))
