extends RefCounted
## Explicit commercial adapter; saved routes are validated, never authored again.
const Profile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Guard = preload("res://scripts/seeded_offer_guard.gd")
const Stories = preload("res://scripts/courier_stories.gd")
const VERSION = "protected-bird-offers-v1"
const POLICY = "seeded-protected-bird-policy-v1"
const OPENING = "这箱补给送到苔光驿站。出口前方有保护鸟穿越，请从下方绕行。"
const META_KEYS = ["version", "world_seed", "day", "slot", "kind", "authoring_policy", "seed", "fully_realized", "dialogue"]
const FIXED_ROUTE_FIELDS = {"id":3,"rep":7,"weight":2.4,"reward":340,"required":90.0,
 "name":"城市货站 → 晨星虫洞 → 苔光驿站","destination_name":"苔光驿站","distance":1240.0,"destination_y":-150.0,
 "delivery_radius":9.0,"max_delivery_speed":24.0,"boundary_y":260.0,"time_limit":100.0,"deadline":72.0,"gravity":0.0,"wind":[0.0,0.0],
 "variation":0.0,"pilot_drag":0.025,"pilot_cruise_speed":18.0,"pilot_boost_speed":22.0,"pilot_vertical_speed":5.0,"pilot_net_force_limit":30.0,
 "pilot_battery_multiplier":20.0,"pilot_energy_tariff":0.025,"pilot_altitude":150.0,"pilot_climb_start":35.0,"pilot_climb_end":410.0,"lookahead_seconds":3.5,
 "risk":"先升空，再对准虫洞；整体轮廓须装入 25.75 m 净口径。收件限速 24 m/s。 苔光保护鸟会在出口前方穿越，请从下方绕行。",
 "wormhole_hint":"通行使用驿站储能，按实际能耗计费；离洞后继续驶向收件灯。",
 "route_story_hook":"苔光驿站等着这箱补给。过洞后沿着亮着的收件灯走，别忘了留电。"}
const COMMERCIAL_KEYS = ["status", "accepted_day", "variant", "client", "cargo", "story", "generation", "appearance_id", "appearance_seed", "species", "accessory_id", "story_id", "story_node", "cargo_loaded", "success"]

static func derived_seed(world_seed:int, day:int) -> int:
 var value:int=5381
 for byte in ("star-courier/%s/%d/%d/0/protected-introduction"%[POLICY,world_seed,day]).to_utf8_buffer():value=(value*33+int(byte))%2147483647
 return maxi(1,value)

static func has_markers(route:Dictionary) -> bool:
 var gen:Variant=route.get("generation")
 return Profile.same_value(route.get("control_version"),Profile.CONTROL_VERSION) or Profile.same_value(route.get("route_profile"),Profile.ROUTE_PROFILE) or route.has("ecology") or route.has("ecology_schema") or route.has("ecology_generator") or (gen is Dictionary and Profile.same_value(gen.get("version"),VERSION))

static func create_new_offer(root:Dictionary, day:int, actor:String) -> Dictionary:
 if not Guard.seed_state_error(root).is_empty() or not Profile.same_value(root.get("version"),POLICY) or day<5 or day>1000000 or not actor in Stories.IDS:return {"ok":false,"error":"Invalid protected-area authoring request.","offer":{}}
 var seed_value:int=derived_seed(int(root.world_seed),day)
 var route:Dictionary=Profile.route({"id":3,"rep":7,"weight":2.4,"reward":340,"required":90.0},"D%d-A"%day,seed_value)
 var person:Dictionary=Stories.PROFILES[actor]
 route.merge({"status":"available","accepted_day":day,"variant":"标准件","client":person.name,"cargo":person.cargo,"story":OPENING,"appearance_id":actor,
  "generation":{"version":VERSION,"world_seed":int(root.world_seed),"day":day,"slot":0,"kind":"protected-area","authoring_policy":POLICY,"seed":seed_value,"fully_realized":true,
   "dialogue":{"id":"protected-bird-address-v1","appearance_id":actor,"story_id":person.story_id,"cargo":person.cargo,"destination_name":"苔光驿站","accept_lines":[{"speaker":"npc","text":OPENING,"expression":"neutral"}]}}},true)
 var error:String=validation_error(route)
 return {"ok":error.is_empty(),"error":error,"offer":route if error.is_empty() else {}}

static func canonical_route(route:Dictionary) -> Dictionary:
 # Call validation_error first. Only registered commerce/presentation fields
 # are projected away; the authoritative contract_id stays in physics.
 var result:Dictionary=route.duplicate(true)
 for key in COMMERCIAL_KEYS:result.erase(key)
 return result

static func validation_error(route:Dictionary) -> String:
 var metadata:Variant=route.get("generation")
 if not metadata is Dictionary or not Profile.exact_keys(metadata,META_KEYS):return "bird_offer_metadata"
 if not Profile.same_value(metadata.get("version"),VERSION) or not Profile.same_value(metadata.get("authoring_policy"),POLICY) or not Profile.same_value(metadata.get("kind"),"protected-area") or not Profile.same_value(metadata.get("fully_realized"),true):return "bird_offer_protocol"
 if not Guard.integer_in(metadata.get("world_seed"),0,2147483646) or not Guard.integer_in(metadata.get("day"),5,1000000) or not Guard.integer_in(metadata.get("slot"),0,0):return "bird_offer_provenance"
 var seed_value:int=derived_seed(int(metadata.world_seed),int(metadata.day))
 for pair in [["contract_id","D%d-A"%int(metadata.day)],["accepted_day",metadata.day],["variant","标准件"],["seed",seed_value],["id",3],["rep",7],["weight",2.4],["reward",340],["required",90.0]]:
  if not Profile.same_value(route.get(pair[0]),pair[1]):return "bird_offer_identity_or_terms"
 if not Profile.same_value(metadata.get("seed"),seed_value):return "bird_offer_seed"
 if not route.get("status") is String or not route.status in ["available","accepted","in_flight","settled","declined","cancelled"]:return "bird_offer_status"
 var dialogue:Variant=metadata.get("dialogue")
 if not dialogue is Dictionary or not dialogue.get("appearance_id") is String or not dialogue.appearance_id in Stories.IDS:return "bird_offer_actor"
 var actor:String=dialogue.appearance_id
 var person:Dictionary=Stories.PROFILES[actor]
 var expected:Dictionary={"id":"protected-bird-address-v1","appearance_id":actor,"story_id":person.story_id,"cargo":person.cargo,"destination_name":"苔光驿站","accept_lines":[{"speaker":"npc","text":OPENING,"expression":"neutral"}]}
 if not Profile.same_value(dialogue,expected):return "bird_offer_dialogue"
 for pair in [["client",person.name],["cargo",person.cargo],["story",OPENING],["appearance_id",actor]]:
  if not Profile.same_value(route.get(pair[0]),pair[1]):return "bird_offer_customer"
 for key in ["cargo_loaded","success"]:
  if route.has(key) and not route[key] is bool:return "bird_offer_flag"
 for key in ["appearance_seed","story_node"]:
  if route.has(key) and not Guard.integer_in(route[key],0,2147483646):return "bird_offer_binding"
 for key in ["species","accessory_id","story_id"]:
  if route.has(key) and not route[key] is String:return "bird_offer_binding"
 if route.has("story_id") and not Profile.same_value(route.story_id,person.story_id):return "bird_offer_story"
 if route.has("battery_capacity_multiplier") and not Guard.number_in(route.battery_capacity_multiplier,1.0,1.45):return "bird_offer_research"
 return fixed_route_error(canonical_route(route))

static func fixed_route_error(route:Dictionary) -> String:
 # Constant comparison is not a restore-time call to the authoring function.
 # The physics-only profile supports analytical fixtures; this registered
 # commercial version admits exactly the realization offered to the player.
 for key in FIXED_ROUTE_FIELDS:
  if not Profile.same_value(route.get(key),FIXED_ROUTE_FIELDS[key]):return "bird_offer_fixed_field: "+str(key)
 if route.has("battery_capacity_multiplier") and not Guard.number_in(route.battery_capacity_multiplier,1.0,1.45):return "bird_offer_research"
 return Profile.validation_error(route)
