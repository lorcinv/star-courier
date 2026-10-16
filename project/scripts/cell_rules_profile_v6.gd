extends RefCounted
## Explicit future-contract identities. Validation never rewrites a stored route.
const Ground=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Ascent=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const INPUT_SCHEMA:String="free-flight-input-v2"
const SCHEMA:String="cell-combinations-v1"
const VERSIONS:Dictionary={"ground":"pilot-delivery-v6","ascent":"pilot-ascent-v6","rift":"pilot-rift-v6"}
const FLIGHT_SCHEMAS:Dictionary={"ground":"delivery-flight-policy-v6","ascent":"delivery-ascent-policy-v6","rift":"delivery-rift-policy-v6"}
const POLICIES:Dictionary={"cell_rules_schema":SCHEMA,"energy_policy":"unpowered-coast-v1","accelerator_policy":"target-component-recoil-v1","supply_policy":"proportional-circuit-energy-v1","accelerator_damage_policy":"finite-stroke-delta-v-v1"}
const ACCELERATOR_STROKE_METRES:float=1.0
const ACCELERATOR_CLEARANCE_SECONDS:float=0.18

static func is_version(value:Variant)->bool:return value is String and value in VERSIONS.values()
static func environment_for_version(value:Variant)->String:
 for environment in VERSIONS:
  if value==VERSIONS[environment]:return environment
 return ""
static func has_markers(data:Dictionary)->bool:
 if is_version(data.get("control_version")) or is_version(data.get("pilot_profile")) or data.get("free_flight_schema") in FLIGHT_SCHEMAS.values():return true
 for key in data:
  if str(key).begins_with("cell_") or str(key).begins_with("accelerator_") or key=="supply_policy":return true
 return data.get("energy_policy")==POLICIES.energy_policy
static func fresh_source_allowed(data:Dictionary)->bool:
 if has_markers(data):return false
 for key in ["contract_id","status","generation","accepted_day"]:
  if data.has(key):return false
 return true
static func _legacy(environment:String):
 return Ground if environment=="ground" else (Ascent if environment=="ascent" else Rift if environment=="rift" else null)
static func stamp_fresh(data:Dictionary,environment:String)->Dictionary:
 if not fresh_source_allowed(data) or not VERSIONS.has(environment):return {}
 var legacy=_legacy(environment)
 if not legacy.validation_error(data).is_empty():return {}
 var result:Dictionary=data.duplicate(true)
 result.merge(POLICIES,true);result.cell_environment=environment
 result.control_version=VERSIONS[environment];result.pilot_profile=VERSIONS[environment];result.free_flight_schema=FLIGHT_SCHEMAS[environment]
 result.accelerator_stroke_metres=ACCELERATOR_STROKE_METRES;result.accelerator_clearance_seconds=ACCELERATOR_CLEARANCE_SECONDS
 return result if validation_error(result,environment).is_empty() else {}
static func compatibility_route(data:Dictionary,environment:String)->Dictionary:
 if not VERSIONS.has(environment):return {}
 var result:Dictionary=data.duplicate(true)
 for key in POLICIES:
  if key!="energy_policy":result.erase(key)
 result.erase("cell_environment");result.erase("accelerator_stroke_metres");result.erase("accelerator_clearance_seconds")
 var legacy=_legacy(environment)
 result.control_version=legacy.VERSION;result.pilot_profile=legacy.VERSION;result.free_flight_schema=legacy.SCHEMA
 result.energy_policy=Ground.MARKERS.energy_policy
 return result
static func validation_error(data:Dictionary,environment:String="")->String:
 if environment.is_empty():environment=environment_for_version(data.get("control_version"))
 if not VERSIONS.has(environment):return "格子组合规则版本不支持。"
 for key in POLICIES:
  if not data.get(key) is String or data[key]!=POLICIES[key]:return "格子组合规则身份不一致。"
 for pair in [["control_version",VERSIONS[environment]],["pilot_profile",VERSIONS[environment]],["free_flight_schema",FLIGHT_SCHEMAS[environment]],["input_schema",INPUT_SCHEMA],["cell_environment",environment],["route_kind",environment]]:
  if not data.get(pair[0]) is String or data[pair[0]]!=pair[1]:return "组合规则与环境身份不一致。"
 for key in data:
  if (str(key).begins_with("cell_") and key not in ["cell_rules_schema","cell_environment"]) or (str(key).begins_with("accelerator_") and key not in ["accelerator_policy","accelerator_damage_policy","accelerator_stroke_metres","accelerator_clearance_seconds"]):return "未知组合规则字段。"
  if environment!="ascent" and str(key).begins_with("ascent_"):return "混入其他环境的升空规则。"
  if environment!="rift" and (str(key).begins_with("rift_") or key=="required_portal_id"):return "混入其他环境的门户规则。"
 var stroke:Variant=data.get("accelerator_stroke_metres")
 if not (stroke is int or stroke is float) or not is_finite(float(stroke)) or float(stroke)!=ACCELERATOR_STROKE_METRES:return "加速器有限行程规则不一致。"
 var clearance:Variant=data.get("accelerator_clearance_seconds")
 if not (clearance is int or clearance is float) or not is_finite(float(clearance)) or float(clearance)!=ACCELERATOR_CLEARANCE_SECONDS:return "加速器净空规则不一致。"
 var legacy=_legacy(environment)
 return legacy.validation_error(compatibility_route(data,environment))
