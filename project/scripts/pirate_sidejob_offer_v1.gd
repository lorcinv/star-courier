extends RefCounted
## Dedicated optional commercial identity. Never adapts an existing saved order.
## The immutable v2 physical owner remains unchanged; delivery needs no kill.
const Profile=preload("res://scripts/pirate_encounter_profile_v2.gd")
const Shape=preload("res://scripts/pilot_protected_bird_profile.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const VERSION="pirate-sidejob-offers-v1"
const POLICY="seeded-protected-bird-policy-v3-pirate-a1"
const ORDINARY_POLICY="seeded-readable-policy-a1"
const ROOT_KEYS=["version","world_seed","ordinary_policy","introduced_day","pirate_introduced_day"]
const META_KEYS=["version","world_seed","day","slot","kind","authoring_policy","seed","fully_realized","dialogue"]
const NAME="自选委托 · 近轨护送"
const RISK="可接可拒，婉拒不扣声望。送达即可，不必击毁海盗；留意攻击预警，停摆船只也要绕开。"
const OPENING="麻烦把%s送去近轨护航收货站。听说路上有海盗，你看这趟接不接？"
const BINDING_KEYS=["appearance_seed","species","accessory_id","story_id","story_node"]
const BUSINESS_KEYS=["contract_id","status","accepted_day","variant","client","cargo","story","generation","pirate_sidejob_schema","seed","appearance_id","appearance_seed","species","accessory_id","story_id","story_node","cargo_loaded","success","battery_capacity_multiplier"]
const TERMS={"id":5,"rep":8,"weight":1.55,"reward":340,"required":85.0}

static func root_error(root:Dictionary) -> String:
 if not Guard.seed_state_error(root).is_empty() or not Shape.exact_keys(root,ROOT_KEYS):return "pirate_root_shape"
 if not Shape.same_value(root.get("version"),POLICY) or not Shape.same_value(root.get("ordinary_policy"),ORDINARY_POLICY):return "pirate_root_protocol"
 for pair in [["introduced_day",5],["pirate_introduced_day",4]]:
  var value:Variant=root.get(pair[0])
  if not Guard.integer_in(value,0,1000000) or (int(value)!=0 and int(value)<int(pair[1])):return "pirate_root_introduction"
 return ""

static func physics_seed(day:int) -> int:return day*100+16

static func has_markers(route:Dictionary) -> bool:
 if route.has("pirate_sidejob_schema") or Shape.same_value(route.get("id"),5):return true
 var metadata:Variant=route.get("generation")
 if not metadata is Dictionary:return false
 for key in ["version","authoring_policy","kind"]:
  var value:Variant=metadata.get(key)
  if value is String and (value.begins_with("pirate-sidejob-") or value.begins_with("seeded-protected-bird-policy-v3-pirate-")):return true
 return false

static func future_offer(route:Dictionary) -> bool:
 if not has_markers(route):return false
 if route.has("pirate_sidejob_schema") and not Guard.integer_in(route.pirate_sidejob_schema,1,1):return true
 var metadata:Variant=route.get("generation")
 if not metadata is Dictionary:return false
 return (metadata.get("version") is String and metadata.version!=VERSION) or (metadata.get("authoring_policy") is String and metadata.authoring_policy!=POLICY)

static func create_new_offer(root:Dictionary,day:int,actor:String) -> Dictionary:
 if not root_error(root).is_empty() or day<4 or day>1000000 or int(root.pirate_introduced_day)!=0 or int(root.introduced_day)>day:return _error("pirate_authoring_request")
 if actor!=Stories.IDS[posmod((day-1)*2+1,Stories.IDS.size())]:return _error("pirate_authoring_actor")
 var route:Dictionary=Profile.ascent_route(TERMS.duplicate(true))
 var person:Dictionary=Stories.PROFILES[actor]
 route.merge({"name":NAME,"risk":RISK,"contract_id":"D%d-B"%day,"status":"available","accepted_day":day,"variant":"自选护送件","client":person.name,"cargo":person.cargo,"story":_opening(actor),"appearance_id":actor,"pirate_sidejob_schema":1,"seed":physics_seed(day),
  "generation":{"version":VERSION,"world_seed":int(root.world_seed),"day":day,"slot":1,"kind":"pirate-sidejob-delivery","authoring_policy":POLICY,"seed":physics_seed(day),"fully_realized":true,"dialogue":_dialogue(actor)}},true)
 var error:String=validation_error(route)
 return {"ok":error.is_empty(),"error":error,"offer":route if error.is_empty() else {}}

static func _opening(actor:String) -> String:return OPENING%str(Stories.PROFILES[actor].cargo)

static func _dialogue(actor:String) -> Dictionary:
 var person:Dictionary=Stories.PROFILES[actor]
 return {"id":"pirate-sidejob-address-v1","appearance_id":actor,"story_id":person.story_id,"cargo":person.cargo,"destination_name":"近轨护航收货站","accept_lines":[{"speaker":"npc","text":_opening(actor),"expression":"neutral"}]}

static func validation_error(route:Dictionary) -> String:
 if not Guard.safe_json(route):return "pirate_offer_value"
 var metadata:Variant=route.get("generation")
 if not metadata is Dictionary or not Shape.exact_keys(metadata,META_KEYS):return "pirate_offer_metadata"
 if not Shape.same_value([metadata.get("version"),metadata.get("authoring_policy"),metadata.get("kind"),metadata.get("fully_realized"),route.get("pirate_sidejob_schema")],[VERSION,POLICY,"pirate-sidejob-delivery",true,1]):return "pirate_offer_protocol"
 if not Guard.integer_in(metadata.get("world_seed"),0,2147483646) or not Guard.integer_in(metadata.get("day"),4,1000000) or not Guard.integer_in(metadata.get("slot"),1,1):return "pirate_offer_provenance"
 var day:int=int(metadata.day)
 var actor:String=Stories.IDS[posmod((day-1)*2+1,Stories.IDS.size())]
 var person:Dictionary=Stories.PROFILES[actor]
 for pair in [["contract_id","D%d-B"%day],["accepted_day",day],["variant","自选护送件"],["seed",physics_seed(day)],["name",NAME],["risk",RISK],["client",person.name],["cargo",person.cargo],["story",_opening(actor)],["appearance_id",actor]]:
  if not Shape.same_value(route.get(pair[0]),pair[1]):return "pirate_offer_identity_or_terms:"+str(pair[0])
 for key in TERMS:
  if not Shape.same_value(route.get(key),TERMS[key]):return "pirate_offer_terms:"+str(key)
 if not Shape.same_value(metadata.get("seed"),physics_seed(day)) or not Shape.same_value(metadata.get("dialogue"),_dialogue(actor)):return "pirate_offer_seed_or_dialogue"
 if not route.get("status") is String or not route.status in ["available","accepted","in_flight","settled","declined","cancelled"]:return "pirate_offer_status"
 for key in ["cargo_loaded","success"]:
  if route.has(key) and not route[key] is bool:return "pirate_offer_flag"
 var binding_count:int=0
 for key in BINDING_KEYS:
  if route.has(key):binding_count+=1
 if binding_count!=0 and binding_count!=BINDING_KEYS.size():return "pirate_offer_partial_binding"
 if binding_count>0:
  if not Guard.integer_in(route.appearance_seed,0,2147483646) or not Guard.integer_in(route.story_node,0,3):return "pirate_offer_binding_number"
  if not Shape.same_value(route.species,person.species) or not Shape.same_value(route.story_id,person.story_id) or not route.accessory_id is String or not route.accessory_id in person.accessories:return "pirate_offer_binding_identity"
 if route.has("battery_capacity_multiplier") and not Guard.number_in(route.battery_capacity_multiplier,1.0,1.45):return "pirate_offer_research"
 # Compare untrusted identity/geometry with the fixed snapshot using the
 # type-safe exact utility BEFORE the unchanged physical reader compares its
 # known protocol strings. Malformed saved types cannot raise engine errors.
 var physical:Dictionary=Profile.ascent_route()
 for key in physical:
  if key=="name":continue
  if not Shape.same_value(route.get(key),physical[key]):return "pirate_offer_fixed_field:"+str(key)
 # Unknown fields cannot smuggle an event through the broad protocol reader.
 for key in route:
  if not key in physical and not key in TERMS and not key in BUSINESS_KEYS and key!="risk":return "pirate_offer_unknown_field:"+str(key)
 return Profile.route_error(route)

static func _error(error:String) -> Dictionary:return {"ok":false,"offer":{},"error":error}
