extends RefCounted
## Registered contract adapter. Geometry remains the frozen meteor catalog.
## No RNG, authoring or template substitution occurs on restore/validation.
const Catalog=preload("res://scripts/orbital_meteor_catalog.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const VERSION=Catalog.GENERATOR_VERSION
const POLICY="seeded-orbital-policy-v1"
const OPENING="这件货送到晨星轨道站。前面有流星横越，先看清它的方向。"

static func derived_seed(world_seed:int,day:int,domain:String) -> int:
 var value:int=5381
 for byte in ("star-courier/%s/%d/%d/0/ascent/%s"%[POLICY,world_seed,day,domain]).to_utf8_buffer():value=(value*33+int(byte))%2147483647
 return maxi(1,value)

static func has_markers(route:Dictionary) -> bool:
 # This explicit event field belongs to this registered content adapter.
 # Partial or malformed event records must fail closed, not bypass validation.
 var gen:Variant=route.get("generation")
 return _same(route.get("route_profile"),Catalog.VERSION) or (gen is Dictionary and _same(gen.get("version"),VERSION)) or route.has("orbital_event")

static func create_new_offer(base:Dictionary,root:Dictionary,day:Variant,slot:Variant,appearance_id:String) -> Dictionary:
 if not Guard.seed_state_error(root).is_empty() or root.get("version")!=POLICY:return _error("Unsupported authoring policy.")
 if not Guard.integer_in(day,2,1000000) or not Guard.integer_in(slot,0,0):return _error("Meteor requires a post-onboarding standard slot.")
 if not appearance_id in Stories.IDS:return _error("Unknown customer identity.")
 var outcome:Dictionary=Catalog.author(base,derived_seed(int(root.world_seed),int(day),"meteor"))
 if not outcome.ok:return _error(outcome.error)
 var offer:Dictionary=outcome.route.duplicate(true)
 offer.contract_id="D%d-A"%int(day);offer.status="available";offer.accepted_day=int(day);offer.variant="标准件"
 offer.client=Stories.PROFILES[appearance_id].name;offer.cargo=Stories.PROFILES[appearance_id].cargo;offer.story=OPENING
 offer.generation.merge({"world_seed":int(root.world_seed),"day":int(day),"slot":0,"kind":"ascent","authoring_policy":POLICY,
  "selection_seed":derived_seed(int(root.world_seed),int(day),"selection"),
  "dialogue":{"id":"meteor-address-v1","appearance_id":appearance_id,"story_id":Stories.PROFILES[appearance_id].story_id,
  "cargo":Stories.PROFILES[appearance_id].cargo,"destination_name":"晨星轨道站","accept_lines":[{"speaker":"npc","text":OPENING,"expression":"neutral"}]}},true)
 var error:String=validation_error(offer)
 return {"ok":true,"offer":offer,"error":""} if error.is_empty() else _error(error)

static func validation_error(route:Dictionary) -> String:
 var error:String=Catalog.route_error(route)
 if not error.is_empty():return error
 # The simulator copies each hazard record and honors mechanics absent from
 # the prototype's x/y envelope check (notably position overrides x/y).
 # This registered version admits exactly its original authored rock schema.
 # Future mechanics need an explicit content version, never extra save keys.
 var hazard:Dictionary=route.hazards[8]
 var hazard_keys:Array=["x","y","velocity","radius","health","mass","type","destructible","pilot_gate","meteor_event_id","meteor_sprite","cooldown"]
 if hazard.size()!=hazard_keys.size():return "Unexpected meteor mechanic field."
 for key in hazard:
  if not key in hazard_keys:return "Unexpected meteor mechanic field: "+str(key)
 if not _same(hazard.get("meteor_sprite"),"meteor"):return "Meteor raster registration changed."
 error=Guard.generic_snapshot_error(route)
 if not error.is_empty():return error
 var meta:Dictionary=route.generation
 if not _same(meta.get("authoring_policy"),POLICY) or not _same(meta.get("kind"),"ascent") or not _same(meta.get("fully_realized"),true) or not _same(meta.get("layout"),"ascent-four-gates-plus-one-orbital-crossing"):return "Unsupported meteor contract policy."
 if not Guard.integer_in(meta.get("world_seed"),0,Catalog.MAX_SEED) or not Guard.integer_in(meta.get("day"),2,1000000) or not Guard.integer_in(meta.get("slot"),0,0):return "Invalid meteor offer provenance."
 var seed:int=derived_seed(int(meta.world_seed),int(meta.day),"meteor")
 if not _same(meta.get("seed"),seed) or not _same(meta.get("selection_seed"),derived_seed(int(meta.world_seed),int(meta.day),"selection")):return "Meteor seed provenance disagrees with its saved root/day."
 if not _same(route.get("contract_id"),"D%d-A"%int(meta.day)) or not _same(route.get("accepted_day"),meta.day) or not _same(route.get("variant"),"标准件"):return "Meteor contract identity or cargo slot changed."
 if route.get("status") not in ["available","accepted","in_flight","settled","declined","cancelled"]:return "Invalid meteor contract status."
 if not _same(route.get("name"),"城市升空 → 流星横越区 → 晨星轨道站") or not _same(route.get("destination_name"),"晨星轨道站") or not _same(route.get("required"),(90.0 if int(route.id)==1 else 75.0)):return "Meteor address or commercial facts changed."
 if route.has("battery_capacity_multiplier") and not Guard.number_in(route.battery_capacity_multiplier,1.0,1.45):return "Invalid saved research capacity."
 for key in ["wormhole_portal","wormhole_schema","moon_schema","route_kind","destination_id"]:
  if route.has(key):return "Mixed special content identity."
 var dialogue:Variant=meta.get("dialogue")
 if not dialogue is Dictionary or not dialogue.get("appearance_id") is String or not dialogue.get("appearance_id") in Stories.IDS:return "Missing meteor customer."
 var actor:String=dialogue.appearance_id;var profile:Dictionary=Stories.PROFILES[actor]
 var expected:Dictionary={"id":"meteor-address-v1","appearance_id":actor,"story_id":profile.story_id,"cargo":profile.cargo,
  "destination_name":"晨星轨道站","accept_lines":[{"speaker":"npc","text":OPENING,"expression":"neutral"}]}
 if not _same(dialogue,expected) or not _same(route.get("client"),profile.name) or not _same(route.get("cargo"),profile.cargo) or not _same(route.get("story"),OPENING):return "Saved meteor customer, parcel or opening changed."
 if route.has("appearance_id") and not _same(route.appearance_id,actor):return "Bound customer differs from meteor contract."
 if route.has("story_id") and not _same(route.story_id,profile.story_id):return "Bound story differs from meteor contract."
 return ""

static func _error(message:String) -> Dictionary:return {"ok":false,"offer":{},"error":message}

static func _same(a:Variant,b:Variant) -> bool:return Catalog._same_json(a,b)
