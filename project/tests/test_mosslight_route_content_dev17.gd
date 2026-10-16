extends SceneTree
## Bounded content/protocol checks only. No save, GUI, or art fallback.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Econ=preload("res://scripts/economy.gd")
const Lunar=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Moon=preload("res://scripts/pilot_moon_profile.gd")
const Bird=preload("res://scripts/pilot_protected_bird_profile.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func reject(route:Dictionary,label:String) -> void:
 check(not Content.validation_error(route).is_empty() and not Profile.validation_error(route).is_empty() and not Econ.route_validation_error(route).is_empty(),label)
func _initialize() -> void:
 var source:Dictionary=Content.fresh_catalog();var saved:Dictionary=source.duplicate(true)
 var route:Dictionary=Profile.route(source)
 check(not route.is_empty() and source==saved,"fresh authoring is detached and explicit")
 if route.is_empty():quit(1);return
 check(route.id==7 and route.rep==4 and route.control_version==Profile.VERSION and route.route_kind=="mosslight","ID7 rep4 uses the existing free-v2 protocol")
 check(Content.validation_error(route).is_empty() and Profile.validation_error(route).is_empty() and Econ.route_validation_error(route).is_empty(),"complete new route passes content/profile/economy")
 check(route.hazards.size()==3 and route.pilot_gates.is_empty() and route.gravity==.16 and route.wind==[.32,0.0],"three physical rocks, fixed sidewind/weak downward force, no gates")
 check(Content.validation_error(JSON.parse_string(JSON.stringify(route))).is_empty(),"new snapshot survives JSON number normalization")
 check(Profile.route(route).is_empty() and Content.author(route).is_empty(),"saved routes cannot be reauthored")
 var changed:Dictionary=route.duplicate(true);changed.contract_id="D3-B";changed.status="available";changed.accepted_day=3
 check(Content.validation_error(changed).is_empty(),"normal runtime StringName keys are valid")
 changed.variant="重货件";changed.deadline=88.0;changed.weight=float(changed.weight)*1.55;changed.reward=int(changed.reward)+55
 check(Content.validation_error(changed).is_empty(),"existing heavy commercial decoration remains valid")
 changed.deadline=85.0;reject(changed,"heavy deadline must be exactly88")
 for key in ["gravity","distance","destination_y","delivery_radius","max_delivery_speed","pilot_drag","variation","time_limit","deadline","rep"]:
  changed=route.duplicate(true);changed[key]=float(changed[key])+.01;reject(changed,"content fixed number rejects mutation: "+key)
 for key in ["mosslight_schema","mosslight_art_schema","mosslight_hint","mosslight_receiver"]:
  changed=route.duplicate(true);changed.erase(key);reject(changed,"partial new content fails closed: "+key)
 for key in ["generation","moon_schema","lunar_schema","wormhole_schema","otherworld_surface","protected_bird_schema","pirate_schema","ecology","meteor_schema","free_ground_schema"]:
  changed=route.duplicate(true);changed[key]={};reject(changed,"foreign route marker is rejected: "+key)
 changed=route.duplicate(true);changed.hazards[0].position=[0.0,0.0];reject(changed,"hazard position alias cannot override exact physical placement")
 changed=route.duplicate(true);changed.hazards[1].velocity=[1.0,0.0];reject(changed,"static rock cannot become an unregistered mover")
 changed=route.duplicate(true);changed.mosslight_receiver.entry="left";reject(changed,"receiver stays any-direction")
 changed=route.duplicate(true);changed.wind=[-.32,0.0];reject(changed,"saved wind direction cannot change")
 changed=route.duplicate(true);changed.gravity=NAN;reject(changed,"nonfinite forces fail closed")
 changed=route.duplicate(true);changed.hazards[0].health=INF;reject(changed,"nonfinite nested hazard fails closed")
 changed=route.duplicate(true);changed[123]=true;reject(changed,"non-string dictionary keys fail closed")
 changed=route.duplicate(true);changed.extra=StringName("not-JSON");reject(changed,"StringName values remain invalid")
 changed=route.duplicate(true);changed.mosslight_future={};reject(changed,"future content schema fields fail closed")
 changed=route.duplicate(true);changed.extra={"mosslight_future":true};reject(changed,"nested unknown new markers fail closed")
 changed=route.duplicate(true)
 for key in Profile.MARKERS:changed.erase(key)
 check(Content.has_markers(changed) and not Econ.route_validation_error(changed).is_empty(),"stripped free markers cannot downgrade through economy")
 changed=route.duplicate(true)
 for key in changed.keys():
  if str(key).begins_with("mosslight_"):changed.erase(key)
 changed.route_profile="generic";changed.route_kind="ordinary";changed.destination_id="ordinary";changed.hazards=[]
 check(Content.has_markers(changed) and not Econ.route_validation_error(changed).is_empty(),"reserved ID7 remains fail-closed without all text markers")
 changed=route.duplicate(true);changed.id=0
 for key in changed.keys():
  if str(key).begins_with("mosslight_"):changed.erase(key)
 changed.route_profile="generic";changed.route_kind="ordinary";changed.destination_id="ordinary"
 check(Content.has_markers(changed) and not Profile.validation_error(changed).is_empty(),"nested new rock marker cannot bypass route validation")
 for key in ["contract_id","status","generation","free_flight_schema"]:
  changed=source.duplicate(true);changed[key]="invalid";check(Profile.route(changed).is_empty(),"source author rejects committed or premarked input: "+key)
 var lunar:Dictionary=Profile.route(Lunar.fresh_catalog())
 check(not lunar.is_empty() and not Content.has_markers(lunar),"new route recognition does not relabel existing lunar content")
 var moon:Dictionary=Moon.route({"id":4,"weight":2.8});var frozen:Dictionary=moon.duplicate(true)
 check(Profile.route(moon).is_empty() and moon==frozen and not Content.has_markers(moon),"historical Moon identity remains untouched")
 check(not Content.has_markers({"route_profile":Bird.ROUTE_PROFILE,"control_version":Bird.CONTROL_VERSION}),"legacy mosslight-protected-bird identity is not this route")
 check(not Caps.group_available("moon") and not Caps.group_available("wormhole") and not Caps.group_available("protected-bird"),"all historical recovery caps remain closed")
 var metadata:Dictionary={"note":"legacy opaque detail"}
 for unused in range(13):metadata={"detail":metadata}
 for version in ["autonomous-v5","pilot-free-v1"]:
  var old_model=Econ.new();old_model.flight_mode=version
  var legacy:Dictionary=old_model.routes()[1].duplicate(true);legacy.extra=metadata.duplicate(true)
  check(not Content.has_markers(legacy) and Econ.route_validation_error(legacy).is_empty(),"unbound historical Economy reader keeps harmless deep metadata: "+version)
 var marked:Dictionary={"mosslight_schema":Content.SCHEMA}
 for unused in range(13):marked={"detail":marked}
 var legacy:Dictionary=Econ.new().routes()[1].duplicate(true);legacy.extra=marked
 check(Content.has_markers(legacy) and not Econ.route_validation_error(legacy).is_empty(),"deep actual new marker still routes to strict new validation")
 changed=route.duplicate(true);changed.extra=metadata
 reject(changed,"recognized new content still rejects unsafe depth")
 print("MOSSLIGHT_ROUTE_CONTENT_DEV17 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
