extends RefCounted
## Isolated authoring-only content. This is NOT seeded-offers-v1 and cannot edit it.
## Constant-velocity geometry uses the existing unmodified pilot-v3 protocol.
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const VERSION = "orbital-meteor-v1"
const GENERATOR_VERSION = "orbital-meteor-offers-v1"
const MAX_SEED = 2147483646
const RADIUS = 0.8
const HP = 80.0
const MASS = 20.0
const SPEED = 3.0
const X_SAMPLES = [592.0, 600.0, 608.0]

static func author(fresh_catalog: Dictionary, explicit_seed: Variant) -> Dictionary:
 var error = request_error(fresh_catalog, explicit_seed)
 if not error.is_empty(): return {"ok":false,"error":error,"route":{}}
 var seed: int = int(explicit_seed)
 # Local integer stream only. No global random calls, clock, wall time or RNG
 # draw inside simulation is consumed while realizing this immutable snapshot.
 var state: int = (seed % 2147483646) + 1
 state = (state * 48271) % 2147483647
 var x: float = X_SAMPLES[state % X_SAMPLES.size()]
 state = (state * 48271) % 2147483647
 var sign_y: float = -1.0 if state % 2 == 0 else 1.0
 state = (state * 48271) % 2147483647
 var jitter: float = [-0.125,0.0,0.125][state % 3]
 var route: Dictionary = Extreme.route(fresh_catalog)
 # Dyadic authored coordinates/times survive JSON exactly. We never shift
 # current physics state or read a craft to move the meteor into its path.
 var crossing: float = (37.78125 if int(fresh_catalog.id)==1 else 38.515625) + (x-600.0)*0.0546875 + jitter
 var event_id: String = "meteor-%d-0" % seed
 route.route_profile = VERSION
 route.name = "城市升空 → 流星横越区 → 晨星轨道站"
 route.distance = 740.0; route.deadline = 60.0; route.time_limit = 78.0
 route.risk = "轨道流星 · 提前转向避让，钻切消耗电量与耐久"
 route.variation = 0.0
 for gate in route.pilot_gates:gate.heading=snappedf(float(gate.heading),1.0/1024.0)
 var event: Dictionary = {"id":event_id,"kind":"moving_meteor","hazard_index":route.hazards.size(),
  "initial_position":[x,-150.0-sign_y*SPEED*crossing],"velocity":[0.0,sign_y*SPEED],
  "lane_y":-150.0,"center_crossing_seconds":crossing,"warning_start_seconds":crossing-4.0,
  "warning_end_seconds":crossing+6.0,"radius":RADIUS,"health":HP,"mass":MASS,
  "destructible":true,"sprite":"meteor","art_version":"orbital-meteor-art-v1",
  "max_fragments":2,"fragment_lifetime_seconds":0.65}
 route.hazards.append({"x":event.initial_position[0],"y":event.initial_position[1],"velocity":event.velocity.duplicate(),
  "radius":RADIUS,"health":HP,"mass":MASS,"type":"rock","destructible":true,"pilot_gate":false,
  "meteor_event_id":event_id,"meteor_sprite":"meteor","cooldown":1.0})
 route.orbital_event = {"version":VERSION,"seed":seed,"events":[event],"max_events":1,
  "spawn_clear_until_x":35.0,"receiver_clear_from_x":680.0,"solver":"pilot-v3",
  "timing_semantics":"constant-velocity-from-launch; center crossing is not first contact",
  "warning_claim":"analytic cue plus measured actual silhouette; human/native acceptance pending"}
 route.generation = {"version":GENERATOR_VERSION,"seed":seed,"base_id":int(fresh_catalog.id),
  "layout":"ascent-four-gates-plus-one-orbital-crossing","fully_realized":true}
 error = route_error(route)
 if not error.is_empty():return {"ok":false,"error":error,"route":{}}
 _freeze(route)
 return {"ok":true,"error":"","route":route}

static func request_error(base: Dictionary, seed: Variant) -> String:
 if not _integer(seed,0,MAX_SEED):return "An explicit finite JSON-safe integer seed is required."
 if not _json_safe(base):return "Catalog must contain bounded finite JSON data."
 for key in base:
  if str(key) not in ["id","weight","reward","rep","name","client","cargo","distance","deadline","time_limit","required","risk","story","gravity","wind","max_delivery_speed","delivery_radius","hazards"]:return "Unexpected state/profile field in fresh catalog data."
 for key in ["contract_id","status","generation","input_commands","ticks","route_profile","orbital_event","control_version","pilot_profile","pilot_gates","wormhole_portal","moon_schema"]:
  if base.has(key):return "Only fresh catalog data may be authored; saved offers and dispatches are immutable."
 if not _integer(base.get("id"),1,2):return "This first slice supports only the two unlocked ascent catalog entries."
 var terms: Array = [1.5,220,2] if int(base.id)==1 else [2.0,280,4]
 if not _same_json(base.get("weight"),terms[0]) or not _same_json(base.get("reward"),terms[1]) or not _same_json(base.get("rep"),terms[2]):return "Fresh catalog commercial identity is invalid."
 return ""

static func restore(saved: Dictionary) -> Dictionary:
 # Validation of the stored realization only; never author/reroll on restore.
 var error=route_error(saved)
 if not error.is_empty():return {"ok":false,"error":error,"route":{}}
 var copy=saved.duplicate(true);_freeze(copy)
 return {"ok":true,"error":"","route":copy}

static func route_error(route: Dictionary) -> String:
 if not _json_safe(route):return "Route is not bounded finite JSON."
 if not _same_json(route.get("route_profile"),VERSION) or not _same_json(route.get("control_version"),"pilot-v3"):return "Unknown content or solver version; preserve original snapshot."
 var meta:Variant=route.get("orbital_event");var gen:Variant=route.get("generation")
 if not meta is Dictionary or not gen is Dictionary:return "Missing event/generation metadata."
 if not _same_json(meta.get("version"),VERSION) or not _same_json(gen.get("version"),GENERATOR_VERSION):return "Unknown generation or event version."
 if not _integer(meta.get("seed"),0,MAX_SEED) or not _same_json(meta.seed,gen.get("seed")):return "Invalid persisted event seed."
 if not _integer(gen.get("base_id"),1,2) or not _same_json(route.get("id"),gen.base_id):return "Invalid saved commercial identity."
 var expected=Extreme.route({"id":int(gen.base_id),"weight":1.5 if int(gen.base_id)==1 else 2.0,"reward":220 if int(gen.base_id)==1 else 280,"rep":2 if int(gen.base_id)==1 else 4})
 for key in ["mode","pilot_profile","control_version","pilot_overdrive","gravity","wind","pilot_drag","pilot_cruise_speed","pilot_boost_speed","pilot_vertical_speed","pilot_net_force_limit","pilot_battery_multiplier","pilot_energy_tariff","pilot_altitude","pilot_climb_start","pilot_climb_end","lookahead_seconds","boundary_y","delivery_radius","max_delivery_speed","weight","reward","rep"]:
  if not _same_json(route.get(key),expected.get(key)):return "Saved profile field is outside this content version: "+key
 if not _same_json(route.get("time_limit"),78.0) or not _same_json(route.get("deadline"),60.0):return "Invalid delivery time budget."
 if not _same_json(meta.get("solver"),"pilot-v3") or not _same_json(meta.get("max_events"),1) or not _same_json(meta.get("spawn_clear_until_x"),35.0) or not _same_json(meta.get("receiver_clear_from_x"),680.0):return "Invalid event bounds."
 if not route.get("hazards") is Array or route.hazards.size()!=9 or not route.get("pilot_gates") is Array or route.pilot_gates.size()!=4:return "Unexpected bounded geometry."
 if not meta.get("events") is Array or meta.events.size()!=1:return "Exactly one pre-realized meteor is supported."
 if not _same_json(route.get("distance"),740.0) or not _same_json(route.get("destination_y"),-150.0) or not _same_json(route.get("variation"),0.0):return "Unexpected receiver or runtime random geometry."
 var e:Variant=meta.events[0]
 if not e is Dictionary or not _same_json(e.get("kind"),"moving_meteor") or not _same_json(e.get("hazard_index"),8) or not _same_json(e.get("id"),"meteor-%d-0"%int(meta.seed)):return "Invalid stable meteor identity."
 for key in ["initial_position","velocity"]:
  if not e.get(key) is Array or e[key].size()!=2:return "Invalid event vectors."
  for component in e[key]:
   if not (component is int or component is float):return "Event vectors must be numeric."
 if e.initial_position[0] not in X_SAMPLES or e.velocity[0]!=0.0 or absf(float(e.velocity[1]))!=SPEED:return "Unexpected meteor lane/velocity."
 if not e.get("center_crossing_seconds") is float and not e.get("center_crossing_seconds") is int:return "Invalid crossing time."
 var t=float(e.center_crossing_seconds)
 if t<37.0 or t>40.0 or float(e.initial_position[1])+float(e.velocity[1])*t!=-150.0:return "Stored geometry disagrees with center-crossing timing."
 if not _same_json(e.get("warning_start_seconds"),t-4.0) or not _same_json(e.get("warning_end_seconds"),t+6.0):return "Invalid warning window."
 if not _same_json(e.get("art_version"),"orbital-meteor-art-v1") or not _same_json(e.get("sprite"),"meteor") or not _same_json(e.get("lane_y"),-150.0):return "Invalid event presentation identity."
 if not _same_json(e.get("radius"),RADIUS) or not _same_json(e.get("health"),HP) or not _same_json(e.get("mass"),MASS) or not _same_json(e.get("destructible"),true):return "Meteor physical budget changed."
 if not _same_json(e.get("max_fragments"),2) or not _same_json(e.get("fragment_lifetime_seconds"),0.65):return "Fragment budget changed."
 if not route.hazards[8] is Dictionary:return "Invalid hazard record."
 var h:Dictionary=route.hazards[8]
 if not _same_json(h.get("type"),"rock") or not _same_json(h.get("pilot_gate"),false) or not _same_json(h.get("cooldown"),1.0):return "Unexpected meteor mechanics."
 if not _same_json(h.get("meteor_event_id"),e.id) or not _same_json(h.get("x"),e.initial_position[0]) or not _same_json(h.get("y"),e.initial_position[1]) or not _same_json(h.get("velocity"),e.velocity):return "Hazard realization disagrees with event metadata."
 for key in ["radius","health","mass","destructible"]:
  if not _same_json(h.get(key),e[key]):return "Hazard physical budget disagrees with metadata."
 for i in range(8):
  if not route.hazards[i] is Dictionary or not _same_json(route.hazards[i],expected.hazards[i]):return "Frozen ascent gates must remain physical and unmodified."
 for i in range(4):
  var gate=expected.pilot_gates[i].duplicate(true);gate.heading=snappedf(float(gate.heading),1.0/1024.0)
  if not _same_json(route.pilot_gates[i],gate):return "Frozen ascent gate metadata changed."
 return ""

static func _integer(value: Variant, low: int, high: int) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=low and float(value)<=high

static func _json_safe(value: Variant, depth: int=0) -> bool:
 if depth>12:return false
 if value==null or value is bool:return true
 if value is int:return value>=-9007199254740991 and value<=9007199254740991
 if value is float:return is_finite(value) and absf(value)<=9007199254740991.0
 if value is String or value is StringName:return str(value).length()<=4096
 if value is Array:
  if value.size()>256:return false
  for child in value:
   if not _json_safe(child,depth+1):return false
  return true
 if value is Dictionary:
  if value.size()>128:return false
  for key in value:
   if not (key is String or key is StringName) or str(key).length()>128 or not _json_safe(value[key],depth+1):return false
  return true
 return false

static func _freeze(value: Variant) -> void:
 if value is Array:
  for child in value:_freeze(child)
  value.make_read_only()
 elif value is Dictionary:
  for child in value.values():_freeze(child)
  value.make_read_only()

static func _same_json(a:Variant,b:Variant) -> bool:
 # Raw save values must never reach a mixed-Variant comparison. Numeric
 # int/float JSON round trips are equivalent; booleans and strings are not.
 if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in range(a.size()):
   if not _same_json(a[i],b[i]):return false
  return true
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not _same_json(a[key],b[key]):return false
  return true
 return typeof(a)==typeof(b) and a==b
