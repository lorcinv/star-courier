extends SceneTree
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
func key_types(data:Dictionary) -> Array:
 var result:Array=[]
 for key in data:
  if not key is String:result.append({"key":str(key),"type":type_string(typeof(key))})
 return result
func report(label:String,data:Dictionary) -> void:
 print("LUNAR_AUTHOR_DIAGNOSTIC ",label," ",JSON.stringify({"empty":data.is_empty(),"json_safe":Content._json_safe(data),"non_string_keys":key_types(data),"content_error":Content.validation_error(data),"profile_error":Profile.validation_error(data)}))
func _initialize() -> void:
 var source:Dictionary=Content.fresh_catalog()
 print("LUNAR_AUTHOR_SOURCE ",JSON.stringify({"safe":Content._json_safe(source),"keys":key_types(source)}))
 var raw:Dictionary=source.duplicate(true);raw.merge(Content.FIELDS,true)
 raw["hazards"]=Content.HAZARDS.duplicate(true);raw["pilot_gates"]=[]
 raw["risk"]="月面低重力 · 矿石可绕行或慢速钻切 · 小心漂石 · 可从两侧返回收件"
 report("explicit_content",raw)
 var direct:Dictionary=Content.author(source);report("author_result",direct)
 var force:Dictionary=raw.duplicate(true);force.merge(Profile.MARKERS,true);force.merge(Profile.TUNING,true)
 force.pilot_battery_multiplier=20.0;force.pilot_energy_tariff=0.025;force.pilot_overdrive="mounted-output"
 report("dot_force_fields",force)
 var explicit:Dictionary=raw.duplicate(true);explicit.merge(Profile.MARKERS,true);explicit.merge(Profile.TUNING,true)
 explicit["pilot_battery_multiplier"]=20.0;explicit["pilot_energy_tariff"]=0.025;explicit["pilot_overdrive"]="mounted-output"
 report("explicit_force_fields",explicit)
 var offered:Dictionary=explicit.duplicate(true)
 offered.contract_id="D2-B";offered.status="available";offered.accepted_day=2;offered.variant="标准件";offered.economy_policy="free-flight-economy-v1"
 report("dot_commercial_fields",offered)
 var actual:Dictionary=Profile.route(source);report("full_profile_author",actual)
 quit(0 if not actual.is_empty() else 1)
