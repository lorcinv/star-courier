extends RefCounted
const Legacy=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const MaterialRules=preload("res://scripts/pilot_delivery_profile_v7.gd")
const VERSION:String="pilot-rift-v7"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String=MaterialRules.INPUT_SCHEMA
const SCHEMA:String="delivery-rift-policy-v7"
const ENVIRONMENT:String="rift"
const ROUTE_PROFILE:String=Legacy.ROUTE_PROFILE
const DESTINATION_ID:String=Legacy.DESTINATION_ID
static func route(base:Dictionary={})->Dictionary:return MaterialRules._route(base,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func has_markers(data:Dictionary)->bool:
 return data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.get("free_flight_schema")==SCHEMA or (MaterialRules.material_markers(data) and data.get("cell_environment")==ENVIRONMENT)
static func validation_error(data:Dictionary)->String:return MaterialRules._validation_error(data,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func compatibility_route(data:Dictionary)->Dictionary:return MaterialRules._compatibility_route(data,Legacy)
static func starter_design()->Array:return Legacy.starter_design()
static func starter_launcher()->Array:return Legacy.starter_launcher()
const PORTAL_ID:String=Legacy.PORTAL_ID
