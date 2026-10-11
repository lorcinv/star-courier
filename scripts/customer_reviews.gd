extends RefCounted
## Pure, bounded customer feed. Its only source is the committed formal ledger.
## No money, reputation, collision inference, story advancement, or random calls.
const VERSION:int=1
const MAX_PENDING:int=2
const MAX_PUBLISHED:int=30
const MAX_DAY:int=1000000
const ACTORS:Dictionary={"human_courier":"小禾","elf_archivist":"叶笺","alien_botanist":"绒团","robot_machinist":"铆钉"}
const FACT_KEYS:Array[String]=["settlement_id","delivery_day","client","appearance_id","route_name","destination_name","success","elapsed","deadline","integrity","required"]

static func initial_state(current_day:int) -> Dictionary:
 if current_day<1 or current_day>MAX_DAY:return {}
 return {"version":VERSION,"template_version":VERSION,"start_day":current_day,"published_through_day":current_day-1,"pending":{},"published":[]}

static func _integer(value:Variant,low:int,high:int) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=low and float(value)<=high

static func _number(value:Variant,low:float,high:float) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _text(value:Variant,limit:int,empty:bool=false) -> bool:
 if not value is String or value.length()>limit or (not empty and value.strip_edges().is_empty()):return false
 for i in value.length():
  if value.unicode_at(i)<32 or value.unicode_at(i)==127:return false
 return true

static func _error(reason:String) -> Dictionary:
 return {"ok":false,"reason":reason,"state":{},"changed":false,"published_count":0}

static func _facts(raw:Variant) -> Dictionary:
 if not raw is Dictionary:return {}
 if not _text(raw.get("settlement_id"),96) or not _integer(raw.get("delivery_day"),1,MAX_DAY):return {}
 for key in ["client","route_name","destination_name"]:
  if not _text(raw.get(key),96):return {}
 if not _text(raw.get("appearance_id"),32,true):return {}
 var actor:String=raw.appearance_id
 if not actor.is_empty() and (not ACTORS.has(actor) or raw.client!=ACTORS[actor]):return {}
 if not raw.get("success") is bool:return {}
 if not _number(raw.get("elapsed"),0.0,10000000.0) or not _number(raw.get("deadline"),0.001,10000000.0):return {}
 if not _number(raw.get("integrity"),0.0,100.0) or not _number(raw.get("required"),0.001,100.0):return {}
 var result:Dictionary={}
 for key in FACT_KEYS:result[key]=raw[key]
 result.delivery_day=int(result.delivery_day)
 for key in ["elapsed","deadline","integrity","required"]:result[key]=float(result[key])
 return result

static func _stable_index(id:String,count:int) -> int:
 var value:int=5381
 for byte in id.to_utf8_buffer():value=(value*33+int(byte))%2147483647
 return value%count

static func _publish(facts:Dictionary) -> Dictionary:
 var result:Dictionary=facts.duplicate(true)
 var late:bool=float(facts.elapsed)>float(facts.deadline)
 var damaged:bool=float(facts.integrity)<float(facts.required)
 var worn:bool=float(facts.integrity)<100.0
 var category:String="complete"
 var rating:int=5
 var body:String=""
 var destination:String=str(facts.destination_name)
 if not facts.success:
  category="failed";rating=1
  var lines:Array=["%s这边没收到货，还在等。","这次没送到%s，希望下回顺利。"]
  body=str(lines[_stable_index(facts.settlement_id,lines.size())])%destination
 elif damaged:
  category="late_damaged" if late else "damaged";rating=2
  body="货到了%s，可惜有些破损。"%destination
  body+="也比约好的时间晚了些。" if late else "下次请帮我送稳一些。"
 elif late:
  category="late";rating=3
  body=("%s收到货了，晚了些，货也有一点损伤。" if worn else "%s收到货了，东西完好，就是等久了些。")%destination
 elif worn:
  category="worn";rating=4
  body="货按时送到%s了，有点损伤，下次请再稳一些。"%destination
 else:
  match str(facts.appearance_id):
   "human_courier":body="%s签收啦！准时到，东西也完好，谢谢。"%destination
   "elf_archivist":body="送到%s的包裹完好，也没有误时。多谢照看。"%destination
   "alien_botanist":body="%s收到啦，时间刚好，包裹也好好的！"%destination
   "robot_machinist":body="%s已收件。时限内到达，货物完整。辛苦了。"%destination
   _:
    var lines:Array=["%s收到货了，准时又完好，谢谢。","这一趟送得很稳，%s已经按时签收。"]
    body=str(lines[_stable_index(facts.settlement_id,lines.size())])%destination
 result.published_day=int(facts.delivery_day)+1
 result.category=category;result.rating=rating;result.body=body
 return result

static func normalize_state(raw:Variant,current_day:int) -> Dictionary:
 if current_day<1 or current_day>MAX_DAY:return _error("invalid_current_day")
 # Absence is the sole migration path. Never synthesize historical reviews.
 if raw==null:return {"ok":true,"state":initial_state(current_day),"changed":false,"published_count":0}
 if not raw is Dictionary:return _error("invalid_state_type")
 if not _integer(raw.get("version"),VERSION,VERSION) or not _integer(raw.get("template_version"),VERSION,VERSION):return _error("unsupported_version")
 if not _integer(raw.get("start_day"),1,current_day) or not _integer(raw.get("published_through_day"),current_day-1,current_day-1):return _error("invalid_day_watermark")
 if not raw.get("pending") is Dictionary or not raw.get("published") is Array:return _error("invalid_collections")
 if raw.pending.size()>MAX_PENDING or raw.published.size()>MAX_PUBLISHED:return _error("collection_overflow")
 var state:Dictionary=initial_state(int(raw.start_day))
 state.published_through_day=current_day-1
 var seen:Dictionary={}
 for id in raw.pending:
  var facts:Dictionary=_facts(raw.pending[id])
  if not id is String or facts.is_empty() or facts.settlement_id!=id or int(facts.delivery_day)!=current_day:return _error("invalid_pending_receipt")
  # Pending may contain facts only. Future body/rating fields are never exposed.
  state.pending[id]=facts;seen[id]=true
 for record in raw.published:
  var facts:Dictionary=_facts(record)
  if facts.is_empty() or seen.has(facts.settlement_id):return _error("invalid_or_duplicate_published")
  if int(facts.delivery_day)<int(state.start_day) or int(facts.delivery_day)>=current_day:return _error("future_or_pre_migration_review")
  var expected:Dictionary=_publish(facts)
  if not _integer(record.get("published_day"),int(expected.published_day),int(expected.published_day)):return _error("invalid_publication_day")
  if not _integer(record.get("rating"),int(expected.rating),int(expected.rating)):return _error("incoherent_review")
  for key in ["body","category"]:
   if not record.get(key) is String or record[key]!=expected[key]:return _error("incoherent_review")
  state.published.append(expected);seen[facts.settlement_id]=true
 state.published.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.settlement_id)<str(b.settlement_id) if int(a.published_day)==int(b.published_day) else int(a.published_day)>int(b.published_day))
 return {"ok":true,"state":state,"changed":false,"published_count":0}

static func ledger_validation_error(state:Dictionary,ledger:Dictionary,contracts:Array=[]) -> String:
 # Called by saved-economy validation AFTER pure normalization. Only the
 # bounded retained feed is checked, not every historical ledger entry.
 for facts in state.pending.values()+state.published:
  var id:String=facts.settlement_id
  var receipt:Variant=ledger.get(id)
  if not receipt is Dictionary:return "missing_ledger_receipt"
  for pair in [["settlement_id","contract_id"],["client","client"],["route_name","route"]]:
   if not receipt.get(pair[1]) is String or facts[pair[0]]!=receipt[pair[1]]:return "ledger_identity_mismatch"
  if not _integer(receipt.get("day"),int(facts.delivery_day),int(facts.delivery_day)):return "ledger_day_mismatch"
  if not receipt.get("success") is bool or facts.success!=receipt.success:return "ledger_outcome_mismatch"
  # Both copies came from one receipt, so compare numeric values, not JSON
  # int/float representation. Do not round away a late/damage threshold.
  for key in ["elapsed","deadline","integrity","required"]:
   var value:Variant=receipt.get(key)
   if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=float(facts[key]):return "ledger_fact_mismatch"
  if receipt.has("review_context"):
   var context:Variant=receipt.review_context
   if not context is Dictionary or context.size()!=3 or not _integer(context.get("version"),VERSION,VERSION):return "invalid_review_context"
   for key in ["destination_name","appearance_id"]:
    if not context.get(key) is String or facts[key]!=context[key]:return "ledger_review_context_mismatch"
  if receipt.has("route_context"):
   var context:Variant=receipt.route_context
   if not context is Dictionary or not context.get("destination_name") is String or facts.destination_name!=context.destination_name:return "ledger_destination_mismatch"
  if not receipt.has("review_context"):
   # Pre-context review-era receipts still contain all common numeric/identity
   # facts above. Use a retained settled contract for extra evidence if present.
   # Once old contracts are gone, never invent destination/appearance evidence
   # by parsing route names or consulting today's route authoring profiles.
   for order in contracts:
    if not order is Dictionary or order.get("contract_id")!=id:continue
    if order.get("client")!=receipt.client or order.get("name")!=receipt.route:return "ledger_contract_mismatch"
    if facts.appearance_id!=order.get("appearance_id",""):return "legacy_contract_context_mismatch"
    if not receipt.has("route_context") and facts.destination_name!=order.get("destination_name",receipt.route):return "legacy_contract_context_mismatch"
 return ""

static func capture_settlement(raw:Variant,contract:Dictionary,ledger:Dictionary,current_day:int) -> Dictionary:
 var normalized:Dictionary=normalize_state(raw,current_day)
 if not normalized.ok:return normalized
 var state:Dictionary=normalized.state
 var id:Variant=contract.get("contract_id")
 if not _text(id,96) or not _text(contract.get("status"),24) or contract.status!="settled":return _error("not_formally_settled")
 var receipt:Variant=ledger.get(id)
 if not receipt is Dictionary or not _text(receipt.get("contract_id"),96) or receipt.contract_id!=id:return _error("missing_ledger_receipt")
 if not _integer(receipt.get("day"),current_day,current_day):return _error("historical_or_future_receipt")
 # Committed receipt owns the factual outcome. Contract identity must match it.
 for key in ["client","name"]:
  if not _text(contract.get(key),96):return _error("invalid_contract_identity")
 for key in ["client","route"]:
  if not _text(receipt.get(key),96):return _error("invalid_receipt_identity")
 if receipt.client!=contract.client or receipt.route!=contract.name:return _error("receipt_identity_mismatch")
 var destination:Variant=contract.get("destination_name",receipt.get("route"))
 var context:Variant=receipt.get("route_context")
 if context!=null:
  if not context is Dictionary or not _text(context.get("destination_name"),96):return _error("invalid_saved_destination")
  destination=context.destination_name
 var appearance:Variant=contract.get("appearance_id","")
 if receipt.has("review_context"):
  var review_context:Variant=receipt.review_context
  if not review_context is Dictionary or review_context.size()!=3 or not _integer(review_context.get("version"),VERSION,VERSION):return _error("invalid_review_context")
  destination=review_context.get("destination_name");appearance=review_context.get("appearance_id")
 var facts:Dictionary=_facts({"settlement_id":id,"delivery_day":receipt.get("day"),"client":receipt.get("client"),"appearance_id":appearance,"route_name":receipt.get("route"),"destination_name":destination,"success":receipt.get("success"),"elapsed":receipt.get("elapsed"),"deadline":receipt.get("deadline"),"integrity":receipt.get("integrity"),"required":receipt.get("required")})
 if facts.is_empty():return _error("invalid_settlement_facts")
 if state.pending.has(id):
  if state.pending[id]!=facts:return _error("conflicting_settlement_id")
  return normalized
 for record in state.published:
  if record.settlement_id==id:return _error("already_published_id")
 if state.pending.size()>=MAX_PENDING:return _error("pending_overflow")
 state.pending[id]=facts
 return {"ok":true,"state":state,"changed":true,"published_count":0}

static func publish_next_day(raw:Variant,closing_day:int,new_day:int) -> Dictionary:
 if new_day!=closing_day+1 or new_day>MAX_DAY:return _error("not_next_day")
 # A retried committed transition is an explicit idempotent no-op.
 var already:Dictionary=normalize_state(raw,new_day)
 if already.ok and raw!=null:return already
 var normalized:Dictionary=normalize_state(raw,closing_day)
 if not normalized.ok:return normalized
 var state:Dictionary=normalized.state
 var count:int=state.pending.size()
 for facts in state.pending.values():state.published.append(_publish(facts))
 state.pending={};state.published_through_day=closing_day
 state.published.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.settlement_id)<str(b.settlement_id) if int(a.published_day)==int(b.published_day) else int(a.published_day)>int(b.published_day))
 if state.published.size()>MAX_PUBLISHED:state.published.resize(MAX_PUBLISHED)
 return {"ok":true,"state":state,"changed":true,"published_count":count}

static func visible_reviews(raw:Variant,current_day:int) -> Array:
 var normalized:Dictionary=normalize_state(raw,current_day)
 return normalized.state.published.duplicate(true) if normalized.ok else []
