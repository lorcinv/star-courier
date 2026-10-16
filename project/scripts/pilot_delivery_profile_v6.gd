extends RefCounted
const Legacy=preload("res://scripts/pilot_delivery_profile_v3.gd")
const CellRules=preload("res://scripts/cell_rules_profile_v6.gd")
const VERSION:String="pilot-delivery-v6"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String=CellRules.INPUT_SCHEMA
const SCHEMA:String="delivery-flight-policy-v6"
const ENVIRONMENT:String="ground"
static func route(base:Dictionary={})->Dictionary:
 if not CellRules.fresh_source_allowed(base):return {}
 var source:Dictionary=base.duplicate(true)
 if not source.has("route_kind"):source.route_kind="ground"
 return CellRules.stamp_fresh(Legacy.route(source),ENVIRONMENT)
static func has_markers(data:Dictionary)->bool:
 return data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.get("free_flight_schema")==SCHEMA or (CellRules.has_markers(data) and data.get("cell_environment")==ENVIRONMENT)
static func validation_error(data:Dictionary)->String:return CellRules.validation_error(data,ENVIRONMENT)
static func compatibility_route(data:Dictionary)->Dictionary:return CellRules.compatibility_route(data,ENVIRONMENT)
static func starter_design()->Array:return Legacy.starter_design()
static func starter_launcher()->Array:return Legacy.starter_launcher()
