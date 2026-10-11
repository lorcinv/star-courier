extends RefCounted
## Author only at an empty batch boundary. Validation/restore never calls _build.
const T=preload("res://scripts/readable_offer_templates.gd")
const Guard=preload("res://scripts/readable_offer_guard.gd")
const LegacyGuard=preload("res://scripts/seeded_offer_guard.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const VERSION=T.VERSION
const POLICY=T.ROOT_POLICY

static func request_error(base:Dictionary,root:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> String:
 if not LegacyGuard.seed_state_error(root).is_empty() or not Guard.same(root.get("version"),POLICY):return "Unsupported readable authoring root."
 if not Guard.exact_keys(root,["version","world_seed"]):return "Unexpected readable root fields."
 if not LegacyGuard.integer_in(day,1,1000000) or not LegacyGuard.integer_in(slot,0,1):return "Invalid new-offer day/slot."
 if not kind in T.TEMPLATES or not actor in Stories.IDS:return "Unknown readable template/customer."
 if not LegacyGuard.safe_json(base):return "Catalog must be finite JSON."
 for key in ["generation","contract_id","status","accepted_day","input_commands","ticks","seed","readable_offer_schema","orbital_event","wormhole_portal","wormhole_schema","moon_schema","destination_id","protected_bird_event","wildlife_event"]:
  if base.has(key):return "Only an uncommitted ordinary catalog may be authored."
 if not LegacyGuard.integer_in(base.get("id"),0,2):return "Unsupported catalog identity."
 var row:Array=T.COMMERCIAL[int(base.id)]
 if not Guard.same(base.get("weight"),row[0]) or not Guard.same(base.get("reward"),row[1]) or not Guard.same(base.get("rep"),row[2]):return "Catalog commercial terms changed."
 if (kind=="ground")!=(int(base.id)==0):return "Catalog unlock and geometry disagree."
 if kind=="ascent" and (base.has("route_profile") or base.has("route_kind")):return "Special routes cannot be replaced by readable ascent."
 if kind=="ground" and ((base.has("route_profile") and not Guard.same(base.route_profile,"ground-city-v1")) or (base.has("route_kind") and not Guard.same(base.route_kind,"ground"))):return "Foreign ground content."
 return ""

static func create_new_offer(base:Dictionary,root:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> Dictionary:
 var error:String=request_error(base,root,day,slot,kind,actor)
 if not error.is_empty():return _error(error)
 return accept_candidate_or_fallback(_build(base,root,int(day),int(slot),kind,actor,false),base,root,day,slot,kind,actor)

static func accept_candidate_or_fallback(candidate:Dictionary,base:Dictionary,root:Dictionary,day:Variant,slot:Variant,kind:String,actor:String) -> Dictionary:
 var error:String=request_error(base,root,day,slot,kind,actor)
 if not error.is_empty():return _error(error) # Bad requests never invoke fallback.
 error=Guard.validation_error(candidate)
 if error.is_empty():
  var m:Dictionary=candidate.generation
  if not Guard.same([m.world_seed,m.day,m.slot,m.kind,m.base_id,m.dialogue.appearance_id],[root.world_seed,day,slot,kind,base.id,actor]) or m.fallback:error="Candidate belongs to another request or is already a fallback."
 if error.is_empty():return {"ok":true,"offer":candidate.duplicate(true),"error":"","fallback":false}
 # One no-jitter fallback, same request/physics/task/mass/identity. No rerolls.
 var fallback:Dictionary=_build(base,root,int(day),int(slot),kind,actor,true)
 var fallback_error:String=Guard.validation_error(fallback)
 if not fallback_error.is_empty():return _error("Readable fallback invalid; abort whole batch: "+fallback_error)
 return {"ok":true,"offer":fallback,"error":"","fallback":true,"candidate_error":error}

static func restore_offer(saved:Dictionary) -> Dictionary:
 # In particular, never stamp registration onto an older opaque QA snapshot.
 var error:String=Guard.validation_error(saved) if Guard.has_markers(saved) else LegacyGuard.saved_metadata_error(saved)
 return {"ok":error.is_empty(),"offer":saved.duplicate(true),"error":error}

static func _build(base:Dictionary,root:Dictionary,day:int,slot:int,kind:String,actor:String,fallback:bool) -> Dictionary:
 var t:Dictionary=T.TEMPLATES[kind]
 var c:Dictionary=T.choices(int(root.world_seed),day,slot,kind)
 var heavy:bool=slot==1
 var result:Dictionary=T.physical_fields(kind)
 result.merge({"id":int(base.id),"rep":int(base.rep),"weight":snappedf(float(base.weight)*(1.55 if heavy else 1.0)+c.weight_delta,0.125),
  "reward":int(base.reward)+(55 if heavy else 0)+(10 if c.careful else 0)+int(c.weight_delta*40.0),"required":90.0 if c.careful else 85.0,
  "deadline":t.deadline+(3.0 if heavy else 0.0)+(2.0 if c.careful else 0.0),"contract_id":"D%d-%s"%[day,"A" if slot==0 else "B"],
  "status":"available","accepted_day":day,"variant":"重货件" if heavy else "标准件","client":Stories.PROFILES[actor].name,
  "cargo":("加急补货 · " if heavy else "")+str(Stories.PROFILES[actor].cargo),"appearance_id":actor,"story_id":Stories.PROFILES[actor].story_id,
  "readable_offer_schema":1,"pilot_gates":[],"hazards":[]})
 for index in 2:
  var x:float=t.xs[index]+(0.0 if fallback else c.jitter[index][0])
  var offset:float=t.offsets[index]+(0.0 if fallback or index==1 else c.jitter[index][1])
  var y:float=(0.0 if index==0 else -t.altitude)+offset
  result.pilot_gates.append({"index":index,"x":x,"y":y,"half_gap":8.0,"lane_offset":offset,"heading":0.0})
  for side in [-1.0,1.0]:result.hazards.append({"x":x,"y":y+side*13.0,"radius":5.0,"type":"rock","health":1000000.0,"mass":1000000.0,"pilot_gate":true,"gate_index":index})
 var opening:String=T.OPENINGS[actor][c.dialogue]%result.destination_name
 result.story=opening
 result.generation={"version":VERSION,"policy":T.POLICY,"readable_commercial_adapter":T.ADAPTER,"authoring_policy":POLICY,
  "world_seed":int(root.world_seed),"day":day,"slot":slot,"kind":kind,"layout_template":t.id,"fallback":fallback,"fallback_reason":"candidate_rejected" if fallback else "",
  "base_id":int(base.id),"base_rep":int(base.rep),"base_weight":base.weight,"base_reward":int(base.reward),"weight_delta":c.weight_delta,
  "task_template":("bulk" if heavy else "standard")+("-careful" if c.careful else "-steady"),"readability":T.READABILITY.duplicate(true),
  "dialogue":{"id":"%s-readable-address-%d"%[actor,c.dialogue],"appearance_id":actor,"story_id":Stories.PROFILES[actor].story_id,
  "cargo":Stories.PROFILES[actor].cargo,"destination_name":result.destination_name,"accept_lines":[{"speaker":"npc","text":opening,"expression":"neutral"},{"speaker":"clerk","text":"地址核对好了。我先把箱子固定稳。","expression":"warm_smile"}]}}
 for domain in ["offer","layout","task","dialogue"]:result.generation["seed" if domain=="offer" else domain+"_seed"]=T.derived_seed(int(root.world_seed),day,slot,kind,domain)
 return result

static func _error(error:String) -> Dictionary:return {"ok":false,"offer":{},"error":error}
