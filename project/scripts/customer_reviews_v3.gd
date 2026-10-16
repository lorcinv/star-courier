extends RefCounted
## Append-only free-flight review dispatcher. Frozen V1/V2 files are unchanged.
## A new explicit template ignores time without altering recorded elapsed facts.
const Legacy=preload("res://scripts/customer_reviews.gd")
const Bird=preload("res://scripts/protected_bird_settlement_v1.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const Facts=preload("res://scripts/protected_bird_facts_v1.gd")
const VERSION=1 # Immutable receipt review_context remains V1.
const ENVELOPE_VERSION=2
const MAX_DAY=Legacy.MAX_DAY
const MAX_PENDING=Legacy.MAX_PENDING
const MAX_PUBLISHED=Legacy.MAX_PUBLISHED
const DELIVERY_TEMPLATE="delivery-review-v1"
const BIRD_TEMPLATE="protected-bird-review-v1"
const FREE_TEMPLATE="free-delivery-review-v1"
const FREE_VERSION="pilot-free-v1"
const FREE_DELIVERY_POLICY="any-direction-safe-arrival-v1"
const ROOT_KEYS=["version","template_version","start_day","published_through_day","pending","published","dispatch"]

static func _integer(value:Variant,low:int,high:int) -> bool:return Legacy._integer(value,low,high)
static func initial_state(day:int) -> Dictionary:return Legacy.initial_state(day)
static func schema_version(raw:Variant) -> int:return 2 if raw is Dictionary and Profile.same_value(raw.get("version"),2) else 1
static func _error(reason:String) -> Dictionary:return Legacy._error(reason)

static func _dispatch(evidence:Dictionary={}) -> Dictionary:
 if evidence.is_empty():return {"facts_schema":"delivery-facts-v1","template_id":DELIVERY_TEMPLATE}
 return {"facts_schema":Bird.SCHEMA,"template_id":BIRD_TEMPLATE if not evidence.result.harms.is_empty() else DELIVERY_TEMPLATE,"evidence":evidence.duplicate(true)}

static func _free_dispatch() -> Dictionary:
 return {"facts_schema":"delivery-facts-v1","template_id":FREE_TEMPLATE}

static func _free_receipt(receipt:Dictionary) -> bool:
 # New chapter receipts also have no timed-delivery promise. Their separate
 # economy/qualification schema is validated by Economy, never by this copy.
 if Profile.same_value(receipt.get("control_version"),"pilot-delivery-v3") or Profile.same_value(receipt.get("control_version"),"pilot-ascent-v4") or Profile.same_value(receipt.get("control_version"),"pilot-rift-v5") or Profile.same_value(receipt.get("control_version"),"pilot-delivery-v6") or Profile.same_value(receipt.get("control_version"),"pilot-ascent-v6") or Profile.same_value(receipt.get("control_version"),"pilot-rift-v6") or Profile.same_value(receipt.get("control_version"),"pilot-delivery-v7") or Profile.same_value(receipt.get("control_version"),"pilot-ascent-v7") or Profile.same_value(receipt.get("control_version"),"pilot-rift-v7") or Profile.same_value(receipt.get("control_version"),"pilot-delivery-v8") or Profile.same_value(receipt.get("control_version"),"pilot-ascent-v8") or Profile.same_value(receipt.get("control_version"),"pilot-rift-v8"):
  return Profile.same_value(receipt.get("delivery_policy"),"minimum-integrity-arrival-v3") and Profile.same_value(receipt.get("receipt_schema"),"delivery-receipt-v3")
 return (Profile.same_value(receipt.get("control_version"),FREE_VERSION) or Profile.same_value(receipt.get("control_version"),"pilot-free-v2")) and Profile.same_value(receipt.get("delivery_policy"),FREE_DELIVERY_POLICY)

static func migrate_v1(raw:Variant,current_day:int) -> Dictionary:
 var checked:Dictionary=Legacy.normalize_state(raw,current_day)
 if not checked.ok:return checked
 var state:Dictionary=checked.state
 if raw is Dictionary:
  # Retain every validated legacy record value, including its exact old body.
  # Extra fields cannot silently smuggle newer facts or a premature body.
  for record in raw.pending.values():
   if not record is Dictionary or not Profile.exact_keys(record,Legacy.FACT_KEYS):return _error("legacy_pending_unknown_fields")
  for record in raw.published:
   if not record is Dictionary or not Profile.exact_keys(record,Legacy.FACT_KEYS+["published_day","category","rating","body"]):return _error("legacy_published_unknown_fields")
  state=raw.duplicate(true)
 state.version=ENVELOPE_VERSION;state.template_version=ENVELOPE_VERSION;state.dispatch={}
 for record in state.pending.values()+state.published:state.dispatch[record.settlement_id]=_dispatch()
 return {"ok":true,"state":state,"changed":true,"published_count":0}

static func _publish(facts:Dictionary,tag:Dictionary) -> Dictionary:
 var result:Dictionary=Legacy._publish(facts)
 if tag.template_id==FREE_TEMPLATE:
  # Actual time remains in the signed ledger facts. This explicit new template
  # evaluates only delivery and condition, never a fabricated timely outcome.
  if not facts.success:return result
  var damaged:bool=float(facts.integrity)<float(facts.required)
  var worn:bool=float(facts.integrity)<100.0
  result.category="damaged" if damaged else ("worn" if worn else "complete")
  result.rating=2 if damaged else (4 if worn else 5)
  result.body=("%s收到货了，不过有些破损。下次请再稳一些。" if damaged else ("%s收到货了，有点损伤，谢谢你送过来。" if worn else "%s收到货了，包装完好。谢谢你送过来。"))%facts.destination_name
  return result
 if tag.template_id!=BIRD_TEMPLATE:return result
 result.rating=mini(int(result.rating),2)
 # Category retains the ordinary delivery outcome. No invented fine, intent,
 # death, reputation debit, or contradictory praise for careful handling.
 var outcome:String="这次没送到%s。"%facts.destination_name
 if facts.success:
  outcome="包裹送到%s了。"%facts.destination_name
  if float(facts.integrity)<float(facts.required):outcome+="包裹有些破损。"
  elif float(facts.integrity)<100.0:outcome+="包裹有一点损伤。"
  if float(facts.elapsed)>float(facts.deadline):outcome+="比约好的时间晚了些。"
 result.body=outcome+"这趟配送的装置伤到了保护鸟，请给它们留出通路。"
 return result

static func _tag_error(tag:Variant,id:String) -> String:
 if not tag is Dictionary:return "dispatch_type"
 if Profile.same_value(tag.get("facts_schema"),"delivery-facts-v1"):
  return "" if Profile.exact_keys(tag,["facts_schema","template_id"]) and tag.get("template_id") in [DELIVERY_TEMPLATE,FREE_TEMPLATE] else "legacy_dispatch"
 if not Profile.same_value(tag.get("facts_schema"),Bird.SCHEMA) or not Profile.exact_keys(tag,["facts_schema","template_id","evidence"]):return "dispatch_schema"
 var error:String=Bird.validation_error(tag.evidence)
 if not error.is_empty():return error
 if not Profile.same_value(tag.evidence.route.contract_id,id):return "dispatch_identity"
 var expected:String=BIRD_TEMPLATE if not tag.evidence.result.harms.is_empty() else DELIVERY_TEMPLATE
 return "" if Profile.same_value(tag.get("template_id"),expected) else "dispatch_template"

static func normalize_state(raw:Variant,current_day:int) -> Dictionary:
 if raw==null:return Legacy.normalize_state(raw,current_day)
 if raw is Dictionary and Profile.same_value(raw.get("version"),1):
  if raw.has("dispatch"):return _error("mixed_review_schema")
  for collection in [raw.get("pending",{}).values() if raw.get("pending") is Dictionary else [],raw.get("published",[]) if raw.get("published") is Array else []]:
   for record in collection:
    if record is Dictionary:
     for key in ["facts_schema","template_id","wildlife_result","wildlife_evidence"]:
      if record.has(key):return _error("mixed_review_record")
  return Legacy.normalize_state(raw,current_day)
 if current_day<1 or current_day>MAX_DAY:return _error("invalid_current_day")
 if not raw is Dictionary or not Profile.exact_keys(raw,ROOT_KEYS):return _error("invalid_v2_state")
 if not _integer(raw.version,2,2) or not _integer(raw.template_version,2,2):return _error("unsupported_version")
 if not _integer(raw.start_day,1,current_day) or not _integer(raw.published_through_day,current_day-1,current_day-1):return _error("invalid_day_watermark")
 if not raw.pending is Dictionary or not raw.published is Array or not raw.dispatch is Dictionary or raw.pending.size()>MAX_PENDING or raw.published.size()>MAX_PUBLISHED:return _error("invalid_collections")
 var seen:Dictionary={}
 for id in raw.pending:
  var record:Variant=raw.pending[id]
  var facts:Dictionary=Legacy._facts(record)
  if not id is String or facts.is_empty() or not Profile.exact_keys(record,Legacy.FACT_KEYS) or not Profile.same_value(facts.settlement_id,id) or int(facts.delivery_day)!=current_day:return _error("invalid_pending_receipt")
  var tag_error:String=_tag_error(raw.dispatch.get(id),id)
  if not tag_error.is_empty():return _error(tag_error)
  seen[id]=true
 for record in raw.published:
  var facts:Dictionary=Legacy._facts(record)
  if facts.is_empty() or not Profile.exact_keys(record,Legacy.FACT_KEYS+["published_day","category","rating","body"]) or seen.has(facts.settlement_id):return _error("invalid_published_receipt")
  var id:String=facts.settlement_id
  if int(facts.delivery_day)<int(raw.start_day) or int(facts.delivery_day)>=current_day:return _error("future_or_pre_migration_review")
  var tag_error:String=_tag_error(raw.dispatch.get(id),id)
  if not tag_error.is_empty():return _error(tag_error)
  var expected:Dictionary=_publish(facts,raw.dispatch[id])
  if not Profile.same_value(record,expected):return _error("incoherent_review")
  seen[id]=true
 if not Profile.exact_keys(raw.dispatch,seen.keys()):return _error("orphaned_dispatch")
 return {"ok":true,"state":raw.duplicate(true),"changed":false,"published_count":0}

static func capture_settlement(raw:Variant,contract:Dictionary,ledger:Dictionary,current_day:int) -> Dictionary:
 var receipt:Variant=ledger.get(contract.get("contract_id"))
 var bird:bool=receipt is Dictionary and receipt.has("wildlife_evidence")
 var free_flight:bool=receipt is Dictionary and _free_receipt(receipt)
 if schema_version(raw)==1 and not bird and not free_flight:return Legacy.capture_settlement(raw,contract,ledger,current_day)
 var normalized:Dictionary=migrate_v1(raw,current_day) if schema_version(raw)==1 else normalize_state(raw,current_day)
 if not normalized.ok:return normalized
 var captured:Dictionary=Legacy.capture_settlement(null,contract,ledger,current_day)
 if not captured.ok:return captured
 var id:String=contract.contract_id
 var facts:Dictionary=captured.state.pending[id]
 var tag:Dictionary=_free_dispatch() if free_flight else _dispatch()
 if bird:
  var error:String=Bird.receipt_validation_error(receipt)
  if not error.is_empty():return _error(error)
  tag=_dispatch(receipt.wildlife_evidence)
 var state:Dictionary=normalized.state
 if state.pending.has(id):
  return normalized if Profile.same_value(state.pending[id],facts) and Profile.same_value(state.dispatch.get(id),tag) else _error("conflicting_settlement_id")
 for record in state.published:
  if record.settlement_id==id:return _error("already_published_id")
 if state.pending.size()>=MAX_PENDING:return _error("pending_overflow")
 state.pending[id]=facts;state.dispatch[id]=tag
 return {"ok":true,"state":state,"changed":true,"published_count":0}

static func publish_next_day(raw:Variant,closing_day:int,new_day:int) -> Dictionary:
 if schema_version(raw)==1:return Legacy.publish_next_day(raw,closing_day,new_day)
 if new_day!=closing_day+1 or new_day>MAX_DAY:return _error("not_next_day")
 var already:Dictionary=normalize_state(raw,new_day)
 if already.ok:return already
 var normalized:Dictionary=normalize_state(raw,closing_day)
 if not normalized.ok:return normalized
 var state:Dictionary=normalized.state
 var count:int=state.pending.size()
 for id in state.pending:state.published.append(_publish(state.pending[id],state.dispatch[id]))
 state.pending={};state.published_through_day=closing_day
 state.published.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.settlement_id)<str(b.settlement_id) if int(a.published_day)==int(b.published_day) else int(a.published_day)>int(b.published_day))
 while state.published.size()>MAX_PUBLISHED:
  var dropped:Dictionary=state.published.pop_back();state.dispatch.erase(dropped.settlement_id)
 return {"ok":true,"state":state,"changed":true,"published_count":count}

static func ledger_validation_error(state:Dictionary,ledger:Dictionary,contracts:Array=[]) -> String:
 var error:String=Legacy.ledger_validation_error(state,ledger,contracts)
 if not error.is_empty():return error
 for record in state.pending.values()+state.published:
  var receipt:Dictionary=ledger[record.settlement_id]
  var evidence:Variant=receipt.get("wildlife_evidence")
  if evidence!=null:
   error=Bird.receipt_validation_error(receipt)
   if not error.is_empty():return error
   if schema_version(state)!=2 or not Profile.same_value(state.dispatch[record.settlement_id],_dispatch(evidence)):return "ledger_wildlife_mismatch"
  elif schema_version(state)==2:
   var expected:Dictionary=_free_dispatch() if _free_receipt(receipt) else _dispatch()
   if not Profile.same_value(state.dispatch[record.settlement_id],expected):return "ledger_template_mismatch"
 return ""

static func visible_reviews(raw:Variant,current_day:int) -> Array:
 var normalized:Dictionary=normalize_state(raw,current_day)
 return normalized.state.published.duplicate(true) if normalized.ok else []

static func opaque_error(save:Dictionary) -> String:
 # Protocol inspection precedes corrupt-data backup recovery. Never reinterpret
 # future authored reviews, template tags, or wildlife results as ordinary V1.
 var root:Variant=save.get("offer_generation_state")
 if root is Dictionary and root.get("version") is String and root.version.begins_with("seeded-protected-bird-policy-") and root.version!=preload("res://scripts/protected_bird_offer_v1.gd").POLICY:return "future_bird_policy"
 var settings:Variant=save.get("settings")
 if settings is Dictionary:
  if settings.has("customer_reviews_schema") and not _integer(settings.customer_reviews_schema,1,2):return "future_review_schema"
  if settings.has("protected_bird_schema") and not _integer(settings.protected_bird_schema,1,1):return "future_bird_schema"
 var offers:Array=save.get("contracts",[]).duplicate() if save.get("contracts") is Array else []
 if save.get("in_flight") is Dictionary and save.in_flight.get("route") is Dictionary:offers.append(save.in_flight.route)
 for route in offers:
  if route is Dictionary and preload("res://scripts/protected_bird_offer_v1.gd").has_markers(route):
   var error:String=_opaque_evidence({"schema":Bird.SCHEMA,"route":route})
   if not error.is_empty():return error
   var metadata:Variant=route.get("generation")
   if metadata is Dictionary and metadata.get("version") is String and metadata.version!=Profile.GENERATOR_VERSION:return "future_bird_offer"
 var raw:Variant=save.get("review_state")
 if raw is Dictionary:
  for key in ["version","template_version"]:
   if raw.has(key) and not _integer(raw[key],1,2):return "future_review_envelope"
  for collection in [raw.get("pending",{}).values() if raw.get("pending") is Dictionary else [],raw.get("published",[]) if raw.get("published") is Array else []]:
   for record in collection:
    if not record is Dictionary:continue
    for key in ["wildlife_evidence","evidence"]:
     var error:String=_opaque_evidence(record.get(key))
     if not error.is_empty():return error
    if record.get("facts_schema") is String and not record.facts_schema in ["delivery-facts-v1",Bird.SCHEMA]:return "future_embedded_facts"
    if record.get("template_id") is String and not record.template_id in [DELIVERY_TEMPLATE,BIRD_TEMPLATE,FREE_TEMPLATE]:return "future_embedded_template"
  var dispatch:Variant=raw.get("dispatch")
  if dispatch is Dictionary:
   for tag in dispatch.values():
    if not tag is Dictionary:continue
    if tag.get("facts_schema") is String and not tag.facts_schema in ["delivery-facts-v1",Bird.SCHEMA]:return "future_facts_schema"
    if tag.get("template_id") is String and not tag.template_id in [DELIVERY_TEMPLATE,BIRD_TEMPLATE,FREE_TEMPLATE]:return "future_review_template"
    var error:String=_opaque_evidence(tag.get("evidence"))
    if not error.is_empty():return error
 var ledger:Variant=save.get("settled_ids")
 if ledger is Dictionary:
  for receipt in ledger.values():
   if receipt is Dictionary:
    var error:String=_opaque_evidence(receipt.get("wildlife_evidence"))
    if not error.is_empty():return error
 return ""

static func _opaque_evidence(raw:Variant) -> String:
 if not raw is Dictionary:return ""
 if raw.get("schema") is String and raw.schema!=Bird.SCHEMA:return "future_bird_evidence"
 var result:Variant=raw.get("result")
 if result is Dictionary:
  if Facts.classify(result)=="unsupported":return "future_bird_fact"
  if result.get("harms") is Array:
   for harm in result.harms:
    if harm is Dictionary and ((harm.get("schema") is String and harm.schema!=Facts.SCHEMA) or (harm.get("control_version") is String and harm.control_version!=Profile.CONTROL_VERSION)):return "future_bird_harm"
 var route:Variant=raw.get("route")
 if route is Dictionary:
  for pair in [["control_version",Profile.CONTROL_VERSION],["route_profile",Profile.ROUTE_PROFILE],["ecology_schema",Profile.ECOLOGY_SCHEMA],["ecology_generator",Profile.GENERATOR_VERSION]]:
   if route.get(pair[0]) is String and route[pair[0]]!=pair[1]:return "future_bird_route"
 return ""
