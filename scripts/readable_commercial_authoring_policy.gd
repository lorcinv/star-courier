extends RefCounted
## New future-offer policy. The three seeded-offers-v1 helpers stay unchanged.
## Selection is frozen at 1 in 4 eligible standard ascent slots, never rerolled.
const Seeded=preload("res://scripts/seeded_offer_catalog.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Meteor=preload("res://scripts/orbital_meteor_offers.gd")
const Readable=preload("res://scripts/readable_offer_catalog.gd")
const ReadableGuard=preload("res://scripts/readable_offer_guard.gd")
const VERSION=Meteor.POLICY # Frozen legacy root remains an explicit source.
const CURRENT_VERSION=Readable.POLICY
const METEOR_DENOMINATOR=4

static func supported_root(state:Dictionary) -> bool:
 if not Guard.seed_state_error(state).is_empty():return false
 if state.get("version")==CURRENT_VERSION:return ReadableGuard.exact_keys(state,["version","world_seed"])
 return state.get("version") in [Seeded.VERSION,VERSION]
static func known_offer(version:String) -> bool:return version in [Seeded.VERSION,Meteor.VERSION]

static func known_route(route:Dictionary) -> bool:
 # A camera/version string alone never reinterprets a prior opaque snapshot.
 if ReadableGuard.has_markers(route):return ReadableGuard.recognized(route)
 var metadata:Variant=route.get("generation")
 return metadata is Dictionary and known_offer(str(metadata.get("version","")))

static func next_day_root(state:Dictionary) -> Dictionary:
 var error:String=Guard.seed_state_error(state)
 if not error.is_empty() or not supported_root(state):return {"ok":false,"error":"Unsupported future authoring root; preserve existing state.","state":state.duplicate(true)}
 var result:Dictionary=state.duplicate(true)
 # Only this explicit whitelisted next-day transition may change the root.
 if result.version in [Seeded.VERSION,VERSION]:result.version=CURRENT_VERSION
 return {"ok":true,"error":"","state":result}

static func selects_meteor(state:Dictionary,day:Variant,slot:Variant,base_id:Variant) -> bool:
 if not Guard.seed_state_error(state).is_empty() or state.get("version")!=VERSION:return false
 if not Guard.integer_in(day,2,1000000) or not Guard.integer_in(slot,0,0) or not Guard.integer_in(base_id,1,2):return false
 return Meteor.derived_seed(int(state.world_seed),int(day),"selection")%METEOR_DENOMINATOR==0

static func author(catalog:Dictionary,fresh_catalog:Dictionary,state:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> Dictionary:
 var error:String=Guard.seed_state_error(state)
 if not error.is_empty() or not supported_root(state):return {"ok":false,"offer":{},"error":"Unsupported authoring root."}
 if state.version==CURRENT_VERSION:
  error=Readable.request_error(catalog,state,day,slot,kind,actor)
  if not error.is_empty():return {"ok":false,"offer":{},"error":error}
  if not ReadableGuard.same([fresh_catalog.get("id"),fresh_catalog.get("weight"),fresh_catalog.get("reward"),fresh_catalog.get("rep")],[catalog.get("id"),catalog.get("weight"),catalog.get("reward"),catalog.get("rep")]):return {"ok":false,"offer":{},"error":"Fresh catalog identity disagrees with selected commercial terms."}
  # Preserve meteor's exact original independent domain and 1-in-4 selection.
  # No mutation or seed replacement of the persisted readable root.
  var meteor_root:Dictionary={"version":VERSION,"world_seed":state.world_seed}
  if selects_meteor(meteor_root,day,slot,catalog.get("id")):return Meteor.create_new_offer(fresh_catalog,meteor_root,day,slot,actor)
  return Readable.create_new_offer(catalog,state,day,slot,kind,actor)
 if selects_meteor(state,day,slot,catalog.get("id")):return Meteor.create_new_offer(fresh_catalog,state,day,slot,actor)
 # This explicit projection asks the unchanged helper to author v1 CONTENT;
 # it never changes the persisted root or reinterprets a saved snapshot.
 return Seeded.create_new_offer(catalog,{"version":Seeded.VERSION,"world_seed":state.world_seed},day,slot,kind,actor)
