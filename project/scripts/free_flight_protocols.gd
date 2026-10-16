extends RefCounted
## Version dispatch only. Older stored routes and command streams are never
## reauthored or fed to the newer physics implementation.
const V1=preload("res://scripts/pilot_free_profile_v1.gd")
const V2=preload("res://scripts/pilot_free_profile_v2.gd")
const V3=preload("res://scripts/pilot_delivery_profile_v3.gd")
const V4=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const V5=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const V6=preload("res://scripts/cell_rules_profile_v6.gd")
const V7=preload("res://scripts/pilot_delivery_profile_v7.gd")
const AscentV7=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const RiftV7=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const MATERIAL_VERSIONS:Array[String]=["pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7"]
const V8=preload("res://scripts/pilot_delivery_profile_v8.gd")
const AscentV8=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const RiftV8=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const SHIELD_VERSIONS:Array[String]=["pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const TimelineV1=preload("res://scripts/pilot_free_timeline_v1.gd")
const TimelineV2=preload("res://scripts/pilot_free_timeline_v2.gd")
const VERSIONS:Array[String]=["pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const CURRENT:String="pilot-delivery-v3"

static func is_version(value:Variant) -> bool:
 return value is String and value in VERSIONS

static func has_markers(route:Dictionary) -> bool:
 return V8.shield_markers(route) or V7.material_markers(route) or V6.has_markers(route) or V5.has_markers(route) or V4.has_markers(route) or V3.has_markers(route) or V2.has_markers(route) or V1.has_markers(route)

static func route_error(route:Dictionary) -> String:
 # New markers take precedence, so mixed records cannot fall through to v1.
 if V8.shield_markers(route):
  if route.get("control_version")==AscentV8.VERSION:return AscentV8.validation_error(route)
  if route.get("control_version")==RiftV8.VERSION:return RiftV8.validation_error(route)
  return V8.validation_error(route)
 if V7.material_markers(route):
  if route.get("control_version")==AscentV7.VERSION:return AscentV7.validation_error(route)
  if route.get("control_version")==RiftV7.VERSION:return RiftV7.validation_error(route)
  return V7.validation_error(route)
 if V6.has_markers(route):return V6.validation_error(route)
 if V5.has_markers(route):return V5.validation_error(route)
 if V4.has_markers(route):return V4.validation_error(route)
 if V3.has_markers(route):return V3.validation_error(route)
 return V2.validation_error(route) if V2.has_markers(route) else V1.validation_error(route)

static func input_schema(version:String) -> String:
 return V2.INPUT_SCHEMA if (version in SHIELD_VERSIONS or version in MATERIAL_VERSIONS or V6.is_version(version) or version in [V2.VERSION,V3.VERSION,V4.VERSION,V5.VERSION]) else V1.INPUT_SCHEMA if version==V1.VERSION else ""

static func new_timeline(version:String):
 if (version in SHIELD_VERSIONS or version in MATERIAL_VERSIONS or V6.is_version(version) or version in [V2.VERSION,V3.VERSION,V4.VERSION,V5.VERSION]):return TimelineV2.new()
 if version==V1.VERSION:return TimelineV1.new()
 return null

static func initial_commands(version:String) -> Array:
 var timeline=new_timeline(version)
 return timeline.snapshot() if timeline!=null else []

static func snapshot_error(snapshot:Dictionary) -> String:
 var error:String="这份自由飞行驾驶记录不完整，原记录已保留。"
 if not snapshot.get("route") is Dictionary:return error
 var route:Dictionary=snapshot.route
 var version:Variant=snapshot.get("control_version")
 if not is_version(version) or route.get("control_version")!=version or not route_error(route).is_empty():return error
 if snapshot.get("input_schema")!=input_schema(version):return error
 if version in SHIELD_VERSIONS or version in MATERIAL_VERSIONS or V6.is_version(version) or version in [V3.VERSION,V4.VERSION,V5.VERSION]:
  if not launch_settings_error(snapshot.get("launch_settings")).is_empty() or not launch_phase_error(snapshot).is_empty():return error
 if not TimelineV1._integer(snapshot.get("ticks")) or float(snapshot.ticks)<0.0:return error
 var timeline=new_timeline(version)
 if not timeline.restore(snapshot.get("input_commands"),int(snapshot.ticks)):return error
 if snapshot.get("contract_id")!=route.get("contract_id"):return "这份自由飞行配送身份不一致，原记录已保留。"
 return ""

static func launch_settings_error(value:Variant) -> String:
 if not value is Dictionary or value.size()!=2:return "发射设置记录不完整。"
 for key in ["angle_degrees","power_fraction"]:
  var number:Variant=value.get(key)
  if not (number is int or number is float) or not is_finite(float(number)):return "发射设置记录无效。"
 if float(value.angle_degrees)<0.0 or float(value.angle_degrees)>90.0 or float(value.power_fraction)<0.0 or float(value.power_fraction)>1.0:return "发射设置超出有效范围。"
 return ""

static func launch_phase_error(snapshot:Dictionary) -> String:
 if not snapshot.get("launch_released") is bool:return "发射阶段记录不完整。"
 if snapshot.launch_released:
  return "已释放记录不应保留蓄能阶段。" if snapshot.has("launch_preparation") else ""
 if snapshot.get("ticks")!=0:return "尚未释放的发射不能有航行步数。"
 var stage:Variant=snapshot.get("launch_preparation")
 if not stage is Dictionary or stage.size()!=2:return "蓄能阶段记录不完整。"
 for key in ["age","transfer_remaining"]:
  var number:Variant=stage.get(key)
  if not (number is int or number is float) or not is_finite(float(number)) or float(number)<0.0:return "蓄能阶段记录无效。"
 if float(stage.age)>.95 or float(stage.transfer_remaining)>120.0:return "蓄能阶段超出有效范围。"
 if float(stage.age)>0.0 and float(stage.transfer_remaining)>0.0:return "移送与发射阶段记录不一致。"
 return ""
