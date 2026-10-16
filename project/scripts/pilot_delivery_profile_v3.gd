extends RefCounted
## New contracts only. Existing free-v1/v2 contracts are never re-authored here.
const Free=preload("res://scripts/pilot_free_profile_v2.gd")
const Launcher=preload("res://scripts/launcher_v3.gd")
const VERSION:String="pilot-delivery-v3"
const CONTROL_VERSION:String=VERSION
# Command semantics intentionally remain the proven free-v2 held-input stream.
const INPUT_SCHEMA:String="free-flight-input-v2"
const SCHEMA:String="delivery-flight-policy-v3"
const MARKERS:Dictionary={"mode":"pilot","control_version":VERSION,"pilot_profile":VERSION,
 "free_flight_schema":SCHEMA,"input_schema":INPUT_SCHEMA,
 "delivery_policy":"minimum-integrity-arrival-v3","energy_policy":"cargo-connected-empty-fails-v1",
 "nozzle_policy":"paid-full-swivel-v1","recovery_policy":"failed-survivors-rescued-v1",
 "free_force_policy":"held-thrust-coast-explicit-brake-v2",
 "free_teleport_policy":"mass-distance-preserve-momentum-v3",
 "launch_policy":"delivery-launch-v3","cargo_damage_policy":"physical-cargo-load-v3"}
const DAMAGE_DEFAULTS:Dictionary={"min_delivery_integrity":0.85,"cargo_safe_acceleration":40.0,
 "cargo_damage_per_excess_mps":0.5,"cargo_contact_damage_scale":1.0}
const TELEPORT_JOULES_PER_KG_METRE:float=6.0

static func route(base:Dictionary={}) -> Dictionary:
 for key in ["contract_id","status","generation","control_version","pilot_profile","free_flight_schema","input_schema","delivery_policy","energy_policy","launch_policy","cargo_damage_policy"]:
  if base.has(key):return {}
 var source:Dictionary={"weight":1.0,"distance":100.0,"destination_y":0.0,"delivery_radius":8.0,"max_delivery_speed":8.0,"hazards":[],"gravity":0.0,"wind":[0.0,0.0],"variation":0.0,"pilot_drag":0.0}
 source.merge(base,true)
 var result:Dictionary=Free.route(source)
 if result.is_empty():return {}
 result.merge(MARKERS,true)
 for key in DAMAGE_DEFAULTS:
  if not result.has(key):result[key]=DAMAGE_DEFAULTS[key]
 result.teleport_joules_per_kg_metre=TELEPORT_JOULES_PER_KG_METRE
 return result if validation_error(result).is_empty() else {}

static func has_markers(data:Dictionary)->bool:
 return data.get("control_version")==VERSION or data.get("pilot_profile")==VERSION or data.get("free_flight_schema")==SCHEMA or data.get("launch_policy")==MARKERS.launch_policy or data.get("cargo_damage_policy")==MARKERS.cargo_damage_policy

static func validation_error(data:Dictionary)->String:
 for key in MARKERS:
  if not data.get(key) is String or data[key]!=MARKERS[key]:return "首章运输规则身份不一致。"
 # A private validation copy reuses only the old finite geometry/input checker.
 # The caller's committed v3 route is never relabelled or mutated.
 var common_error:String=Free.validation_error(compatibility_route(data))
 if not common_error.is_empty():return common_error
 for key in DAMAGE_DEFAULTS:
  if not _number(data.get(key)):return "货物完整度或耐受参数缺失。"
 if float(data.min_delivery_integrity)<0.0 or float(data.min_delivery_integrity)>1.0:return "最低交付完整度须为0到1。"
 if float(data.cargo_safe_acceleration)<=0.0 or float(data.cargo_safe_acceleration)>100000.0:return "货物加速度耐受无效。"
 if float(data.cargo_damage_per_excess_mps)<0.0 or float(data.cargo_damage_per_excess_mps)>1000.0:return "货物加速度损伤参数无效。"
 if float(data.cargo_contact_damage_scale)<0.0 or float(data.cargo_contact_damage_scale)>100.0:return "货物接触损伤参数无效。"
 if not _number(data.get("teleport_joules_per_kg_metre")) or float(data.teleport_joules_per_kg_metre)!=TELEPORT_JOULES_PER_KG_METRE:return "位移质量与距离计能规则不一致。"
 return ""

static func compatibility_route(data:Dictionary)->Dictionary:
 var local:Dictionary=data.duplicate(true)
 local.merge(Free.MARKERS,true)
 return local

static func _number(value:Variant)->bool:
 return (value is int or value is float) and is_finite(float(value))

static func starter_design()->Array:return Free.starter_design()
static func starter_launcher()->Array:return Launcher.starter_launcher()
