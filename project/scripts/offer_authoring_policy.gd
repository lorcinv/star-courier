extends RefCounted
## New future-offer policy. The three seeded-offers-v1 helpers stay unchanged.
## Selection is frozen at 1 in 4 eligible standard ascent slots, never rerolled.
const Seeded=preload("res://scripts/seeded_offer_catalog.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Meteor=preload("res://scripts/orbital_meteor_offers.gd")
const VERSION=Meteor.POLICY
const METEOR_DENOMINATOR=4

static func supported_root(state:Dictionary) -> bool:return state.get("version") in [Seeded.VERSION,VERSION]
static func known_offer(version:String) -> bool:return version in [Seeded.VERSION,Meteor.VERSION]

static func next_day_root(state:Dictionary) -> Dictionary:
 var error:String=Guard.seed_state_error(state)
 if not error.is_empty() or not supported_root(state):return {"ok":false,"error":"Unsupported future authoring root; preserve existing state.","state":state.duplicate(true)}
 var result:Dictionary=state.duplicate(true)
 # Only this explicit whitelisted next-day transition may change the root.
 if result.version==Seeded.VERSION:result.version=VERSION
 return {"ok":true,"error":"","state":result}

static func selects_meteor(state:Dictionary,day:Variant,slot:Variant,base_id:Variant) -> bool:
 if not Guard.seed_state_error(state).is_empty() or state.get("version")!=VERSION:return false
 if not Guard.integer_in(day,2,1000000) or not Guard.integer_in(slot,0,0) or not Guard.integer_in(base_id,1,2):return false
 return Meteor.derived_seed(int(state.world_seed),int(day),"selection")%METEOR_DENOMINATOR==0

static func author(catalog:Dictionary,fresh_catalog:Dictionary,state:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> Dictionary:
 var error:String=Guard.seed_state_error(state)
 if not error.is_empty() or not supported_root(state):return {"ok":false,"offer":{},"error":"Unsupported authoring root."}
 if selects_meteor(state,day,slot,catalog.get("id")):return Meteor.create_new_offer(fresh_catalog,state,day,slot,actor)
 # This explicit projection asks the unchanged helper to author v1 CONTENT;
 # it never changes the persisted root or reinterprets a saved snapshot.
 return Seeded.create_new_offer(catalog,{"version":Seeded.VERSION,"world_seed":state.world_seed},day,slot,kind,actor)
