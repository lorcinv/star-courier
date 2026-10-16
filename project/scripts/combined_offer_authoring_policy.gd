extends RefCounted
## Explicit composition boundary. Neither old root is reinterpreted on load.
## Ordinary geometry and once-only wildlife have independent source policies.
const Legacy=preload("res://scripts/offer_authoring_policy.gd")
const Previous=preload("res://scripts/protected_bird_authoring_policy.gd")
const Ordinary=preload("res://scripts/readable_commercial_authoring_policy.gd")
const Pirate=preload("res://scripts/pirate_sidejob_offer_v1.gd")
const ReadableGuard=preload("res://scripts/readable_offer_guard.gd")
const Bird=preload("res://scripts/protected_bird_offer_v1.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const VERSION=Previous.VERSION
const CURRENT_VERSION="seeded-protected-bird-policy-v2-readable-a1"
const PIRATE_VERSION=Pirate.POLICY
const COMBINED_PREFIX="seeded-protected-bird-policy-"
const CURRENT_KEYS=["version","world_seed","ordinary_policy","introduced_day"]

static func supported_root(state:Dictionary) -> bool:
 if not Guard.seed_state_error(state).is_empty():return false
 if Profile.same_value(state.get("version"),PIRATE_VERSION):return Pirate.root_error(state).is_empty()
 if Profile.same_value(state.get("version"),CURRENT_VERSION):
  return Profile.exact_keys(state,CURRENT_KEYS) and Profile.same_value(state.get("ordinary_policy"),Ordinary.CURRENT_VERSION) and _valid_introduction(state.get("introduced_day"))
 if Profile.same_value(state.get("version"),Ordinary.CURRENT_VERSION):return Ordinary.supported_root(state)
 return Previous.supported_root(state)

static func _valid_introduction(value:Variant) -> bool:
 return Guard.integer_in(value,0,1000000) and (int(value)==0 or int(value)>=5)

static func is_bird_root(state:Dictionary) -> bool:
 return supported_root(state) and state.version in [VERSION,CURRENT_VERSION,PIRATE_VERSION]

static func known_root_version(version:Variant) -> bool:
 return version is String and version in [Legacy.Seeded.VERSION,Legacy.VERSION,Ordinary.CURRENT_VERSION,VERSION,CURRENT_VERSION,PIRATE_VERSION]

static func future_root(state:Variant) -> bool:
 # Unknown composition is recovery-only even if an older backup is playable.
 # Generic historical unknown roots keep their existing opaque-save behavior.
 if not state is Dictionary or not state.get("version") is String:return false
 if state.version.begins_with(COMBINED_PREFIX) and not state.version in [VERSION,CURRENT_VERSION,PIRATE_VERSION]:return true
 return state.version in [CURRENT_VERSION,PIRATE_VERSION] and state.get("ordinary_policy") is String and state.ordinary_policy!=Ordinary.CURRENT_VERSION

static func review_inspection(save:Dictionary) -> Dictionary:
 # The frozen review inspector recognizes the original bird root namespace.
 # Only an exact fully supported composition may use its existing protocol
 # view. This read-only shallow outer copy does not rewrite any saved bytes,
 # route, receipt, review record, policy marker or introduction ledger.
 var state:Variant=save.get("offer_generation_state")
 if not state is Dictionary or not state.get("version") in [CURRENT_VERSION,PIRATE_VERSION] or not supported_root(state):return save
 var result:Dictionary=save.duplicate()
 result.offer_generation_state=bird_root(state)
 return result

static func known_offer(version:String) -> bool:return Previous.known_offer(version)

static func known_route(route:Dictionary) -> bool:
 # Complete dedicated markers plus the exact guard grant interpretation.
 if Pirate.has_markers(route):return Pirate.validation_error(route).is_empty()
 if Bird.has_markers(route):return Bird.validation_error(route).is_empty()
 return Ordinary.known_route(route)

static func next_day_root(state:Dictionary,new_day:int) -> Dictionary:
 if not Guard.integer_in(new_day,1,1000000) or not supported_root(state):return {"ok":false,"state":state.duplicate(true)}
 var introduced:int=int(state.get("introduced_day",0))
 if introduced>new_day:return {"ok":false,"state":state.duplicate(true)}
 if state.version==PIRATE_VERSION:
  return {"ok":int(state.pirate_introduced_day)<=new_day,"state":state.duplicate(true)}
 # Called only by explicit next-day/new-empty-batch APIs, never by the loader.
 return {"ok":true,"state":{"version":PIRATE_VERSION,"world_seed":state.world_seed,"ordinary_policy":Ordinary.CURRENT_VERSION,"introduced_day":introduced,"pirate_introduced_day":0}}

static func selects_bird(state:Dictionary,day:int,reputation:int,first:Dictionary) -> bool:
 return is_bird_root(state) and int(state.introduced_day)==0 and day>=5 and reputation>=7 and not Profile.same_value(first.get("id"),4)

static func bird_root(state:Dictionary) -> Dictionary:
 if not is_bird_root(state):return {}
 # The saved special offer retains its exact pre-composition provenance/seed.
 return {"version":VERSION,"world_seed":state.world_seed,"introduced_day":state.introduced_day}

static func author(catalog:Dictionary,fresh_catalog:Dictionary,state:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> Dictionary:
 if not supported_root(state):return {"ok":false,"offer":{},"error":"Unsupported authoring root."}
 if state.version in [CURRENT_VERSION,PIRATE_VERSION]:
  return Ordinary.author(catalog,fresh_catalog,{"version":state.ordinary_policy,"world_seed":state.world_seed},day,slot,kind,actor)
 if state.version==Ordinary.CURRENT_VERSION:return Ordinary.author(catalog,fresh_catalog,state,day,slot,kind,actor)
 # Both old source trees remain byte-identical, including bird -> meteor/v1.
 return Previous.author(catalog,fresh_catalog,state,day,slot,kind,actor)

static func is_pirate_root(state:Dictionary) -> bool:
 return supported_root(state) and state.version==PIRATE_VERSION

static func selects_pirate(state:Dictionary,day:int,reputation:int,deliveries:int,credits:int,first:Dictionary) -> bool:
 if not is_pirate_root(state) or int(state.pirate_introduced_day)!=0 or day<4 or reputation<8 or deliveries<4 or credits<200:return false
 # Exactly registered current ordinary ground/ascent; a meteor/bird/special A
 # remains untouched and defers this optional B introduction.
 return ReadableGuard.recognized(first) and first.generation.kind in ["ground","ascent"] and not Pirate.has_markers(first)
