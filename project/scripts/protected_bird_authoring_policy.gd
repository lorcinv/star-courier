extends RefCounted
## One introduction per shop. Only the next-day/empty-offer boundary may claim it.
## Old authoring helpers remain frozen; unrelated slots keep their old domains.
const Legacy=preload("res://scripts/offer_authoring_policy.gd")
const Bird=preload("res://scripts/protected_bird_offer_v1.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const VERSION=Bird.POLICY

static func supported_root(state:Dictionary) -> bool:
 if not Guard.seed_state_error(state).is_empty():return false
 if Legacy.supported_root(state):return Profile.exact_keys(state,["version","world_seed"])
 if not Profile.same_value(state.get("version"),VERSION) or not Profile.exact_keys(state,["version","world_seed","introduced_day"]):return false
 return Guard.integer_in(state.get("introduced_day"),0,1000000) and (int(state.introduced_day)==0 or int(state.introduced_day)>=5)

static func known_offer(version:String) -> bool:return version==Bird.VERSION or Legacy.known_offer(version)

static func next_day_root(state:Dictionary,new_day:int=0) -> Dictionary:
 if not supported_root(state):return {"ok":false,"state":state.duplicate(true)}
 if state.version==VERSION:return {"ok":true,"state":state.duplicate(true)}
 var old:Dictionary=Legacy.next_day_root(state)
 if not old.ok or new_day<5:return old
 return {"ok":true,"state":{"version":VERSION,"world_seed":old.state.world_seed,"introduced_day":0}}

static func selects_bird(state:Dictionary,day:int,reputation:int,first:Dictionary) -> bool:
 return supported_root(state) and Profile.same_value(state.get("version"),VERSION) and int(state.introduced_day)==0 and day>=5 and reputation>=7 and not Profile.same_value(first.get("id"),4)

static func author(catalog:Dictionary,fresh_catalog:Dictionary,state:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> Dictionary:
 if not supported_root(state):return {"ok":false,"offer":{},"error":"Unsupported authoring root."}
 var projected:Dictionary=state.duplicate(true)
 if state.version==VERSION:projected={"version":Legacy.VERSION,"world_seed":state.world_seed}
 return Legacy.author(catalog,fresh_catalog,projected,day,slot,kind,actor)
