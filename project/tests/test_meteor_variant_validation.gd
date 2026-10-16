extends SceneTree
## Untrusted save fields may be any Variant. Validation must reject malformed
## data with a normal error result, never a GDScript operand/runtime failure.
const Econ=preload("res://scripts/economy.gd")
const Meteor=preload("res://scripts/orbital_meteor_offers.gd")
const Catalog=preload("res://scripts/orbital_meteor_catalog.gd")
const Stories=preload("res://scripts/courier_stories.gd")
var passed:int=0
var failed:int=0
var paths:Array=[]
var bad_values:Array=[null,true,false,0,1,0.5,-1,"","42","wrong",[],[0],{}, {"x":0},NAN,INF,Vector2.ZERO]
func _initialize():run.call_deferred()
func check(value:bool,label:String):
 if value:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func descend(value:Variant,path:Array):
 paths.append(path.duplicate())
 if value is Dictionary:
  for key in value:descend(value[key],path+[key])
 elif value is Array:
  for i in value.size():descend(value[i],path+[i])
func value_at(root:Variant,path:Array)->Variant:
 var result:Variant=root
 for key in path:result=result[key]
 return result
func replace_at(root:Dictionary,path:Array,value:Variant):
 var target:Variant=root
 for i in range(path.size()-1):target=target[path[i]]
 target[path[-1]]=value.duplicate(true) if value is Dictionary or value is Array else value
func run():
 var e=Econ.new()
 var fresh:Dictionary=e._autonomous_routes()[1]
 var authored:Dictionary=Meteor.create_new_offer(fresh,{"version":Meteor.POLICY,"world_seed":42},2,0,Stories.IDS[2])
 check(authored.ok,"valid registered meteor fixture authors")
 if not authored.ok:quit(1);return
 var route:Dictionary=authored.offer.duplicate(true)
 route.appearance_id=Stories.IDS[2];route.story_id=Stories.PROFILES[Stories.IDS[2]].story_id
 var original:String=JSON.stringify(route,"",true,true)
 check(Meteor.validation_error(route).is_empty(),"original typed fixture accepted")
 check(Meteor.validation_error(JSON.parse_string(original)).is_empty(),"ordinary numeric JSON round trip accepted")
 for key in ["route_profile","control_version","mode","pilot_profile","pilot_overdrive","id","weight","reward","rep","gravity","wind","pilot_drag","pilot_cruise_speed","pilot_boost_speed","pilot_vertical_speed","pilot_net_force_limit","pilot_battery_multiplier","pilot_energy_tariff","pilot_altitude","pilot_climb_start","pilot_climb_end","lookahead_seconds","boundary_y","delivery_radius","max_delivery_speed","time_limit","deadline","distance","destination_y","variation","contract_id","accepted_day","variant","status","name","destination_name","required","client","cargo","story","appearance_id","story_id","hazards","pilot_gates"]:
  descend(route[key],[key])
 for key in ["version","seed","base_id","authoring_policy","kind","fully_realized","layout","world_seed","day","slot","selection_seed","dialogue"]:
  descend(route.generation[key],["generation",key])
 paths.append(["generation"])
 for key in ["version","seed","solver","max_events","spawn_clear_until_x","receiver_clear_from_x","events"]:
  descend(route.orbital_event[key],["orbital_event",key])
 paths.append(["orbital_event"])
 for path in paths:
  var old:Variant=value_at(route,path)
  for i in bad_values.size():
   var bad:Variant=bad_values[i]
   if Catalog._same_json(old,bad):continue
   var changed:Dictionary=route.duplicate(true)
   replace_at(changed,path,bad)
   var rejected_before:PackedByteArray=var_to_bytes(changed)
   check(not Meteor.validation_error(changed).is_empty(),"adapter rejects path %s variant %d"%[str(path),i])
   check(not Econ.route_validation_error(changed).is_empty(),"controller rejects path %s variant %d"%[str(path),i])
   check(var_to_bytes(changed)==rejected_before,"rejected raw snapshot stays byte-exact %s variant %d"%[str(path),i])
 check(JSON.stringify(route,"",true,true)==original,"validation never edits the caller snapshot")
 # Marker discovery runs before the shared route type guard. These exact raw
 # profile types reproduced errors in the unchanged Moon contract suite.
 for bad in bad_values:
  check(not Meteor.has_markers({"route_profile":bad}),"non-meteor raw profile marker is safe")
  check(not Meteor.has_markers({"generation":{"version":bad}}),"non-meteor raw generation marker is safe")
  check(Meteor.has_markers({"orbital_event":bad}),"partial event identity is always validated")
  check(not Econ.route_validation_error({"orbital_event":bad}).is_empty(),"partial event fails closed")
 check(not Meteor.has_markers({"generation":{"version":"future-unrelated-v9"}}),"unrelated future generation is not relabeled")
 # Public prototype restore and author APIs must be safe even without the
 # contract adapter. Keep their frozen geometry and valid authored outputs.
 var base={"id":1,"weight":1.5,"reward":220,"rep":2}
 var raw_route:Dictionary=Catalog.author(base,42).route
 var digest:String=JSON.stringify(raw_route,"",true,true).sha256_text()
 for key in base:
  for i in bad_values.size():
   if Catalog._same_json(base[key],bad_values[i]):continue
   var changed=base.duplicate(true);changed[key]=bad_values[i]
   check(not Catalog.author(changed,42).ok,"catalog rejects raw commercial type "+str(key)+"/"+str(i))
 for key in ["route_profile","control_version","generation","orbital_event","wind","hazards","pilot_gates","distance","weight"]:
  for i in bad_values.size():
   if Catalog._same_json(raw_route[key],bad_values[i]):continue
   var changed=raw_route.duplicate(true);changed[key]=bad_values[i]
   check(not Catalog.restore(changed).ok,"prototype restore rejects raw field "+key+"/"+str(i))
 check(JSON.stringify(Catalog.author(base,42).route,"",true,true).sha256_text()==digest,"validation repair preserves authored content bytes")
 var authored_bytes:String=""
 for base_id in [1,2]:
  var original_base={"id":base_id,"weight":1.5 if base_id==1 else 2.0,"reward":220 if base_id==1 else 280,"rep":2 if base_id==1 else 4}
  for fixed_seed in [0,1,42,1337,2147483646]:authored_bytes+=JSON.stringify(Catalog.author(original_base,fixed_seed).route,"",true,true)
 check(authored_bytes.sha256_text()=="d55b0a26edf30a9e73d2fc67a164dd4ff8ae510a7d85b00a38a2d3675de5f332","ten original authored realizations retain their pre-repair digest")
 print("METEOR_VARIANT_VALIDATION passed=%d failed=%d paths=%d"%[passed,failed,paths.size()])
 quit(1 if failed else 0)
