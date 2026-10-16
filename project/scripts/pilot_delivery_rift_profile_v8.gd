extends RefCounted
const Legacy=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const ShieldRules=preload("res://scripts/pilot_delivery_profile_v8.gd")
const VERSION:String="pilot-rift-v8"
const CONTROL_VERSION:String=VERSION
const INPUT_SCHEMA:String=ShieldRules.INPUT_SCHEMA
const SCHEMA:String="delivery-rift-policy-v8"
const ENVIRONMENT:String="rift"
const ROUTE_PROFILE:String=Legacy.ROUTE_PROFILE
const DESTINATION_ID:String=Legacy.DESTINATION_ID
static func route(base:Dictionary={})->Dictionary:return ShieldRules._route(base,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func has_markers(data:Dictionary)->bool:return ShieldRules._has_markers(data,VERSION,SCHEMA,ENVIRONMENT)
static func validation_error(data:Dictionary)->String:return ShieldRules._validation_error(data,Legacy,VERSION,SCHEMA,ENVIRONMENT)
static func compatibility_route(data:Dictionary)->Dictionary:return ShieldRules._compatibility_route(data,Legacy)
static func starter_design()->Array:return Legacy.starter_design()
static func starter_launcher()->Array:return Legacy.starter_launcher()
const PORTAL_ID:String=Legacy.PORTAL_ID
