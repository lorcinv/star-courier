extends RefCounted
## The controller supplies this package directly from the completed live v5 sim.
## This boundary is bounded structural validation, never synchronous replay.
const Simulator=preload("res://scripts/pilot_protected_bird_simulation.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const Facts=preload("res://scripts/protected_bird_facts_v1.gd")
const Design=preload("res://scripts/protected_bird_design_v1.gd")
const Offer=preload("res://scripts/protected_bird_offer_v1.gd")
const SCHEMA="protected-bird-settlement-v1"
const KEYS=["schema","route","seed","command_ticks","status","elapsed","launch_design","registry","result","dispatch_identity"]
const REGISTRY_RECORD_KEYS=["part_id","owner_kind","origin_part_id","part_type"]

static func from_simulator(sim:Variant, snapshot:Dictionary) -> Dictionary:
 if not sim is Simulator or sim.status not in ["success","failed"] or not sim.wildlife_error.is_empty():return {}
 if not snapshot.get("route") is Dictionary or not Offer.validation_error(snapshot.route).is_empty():return {}
 if not snapshot.get("design") is Array or not snapshot.get("launcher") is Array or not Design.validation_error(snapshot.design,snapshot.launcher).is_empty():return {}
 var route:Dictionary=Offer.canonical_route(snapshot.route)
 if not Profile.same_value(route,sim.route) or not Profile.same_value(snapshot.get("seed"),sim.seed_value):return {}
 var registry:Array=[]
 var ids:Array=sim.source_registry.keys();ids.sort()
 for id in ids:
  var source:Dictionary=sim.source_registry[id].duplicate(true);source.part_id=id;registry.append(source)
 var result:Dictionary={"schema":SCHEMA,"route":route,"seed":sim.seed_value,"command_ticks":snapshot.get("ticks"),"status":sim.status,"elapsed":sim.elapsed,"launch_design":snapshot.design.duplicate(true),"registry":registry,"result":sim.wildlife_result(),"dispatch_identity":{"delivery_day":snapshot.route.accepted_day,"client":snapshot.route.client,"appearance_id":snapshot.route.appearance_id}}
 return result if validation_error(result).is_empty() else {}

static func registry_from_records(raw:Variant) -> Dictionary:
 if not raw is Array or raw.is_empty() or raw.size()>192:return {}
 var result:Dictionary={};var previous:int=-1
 for entry in raw:
  if not entry is Dictionary or not Profile.exact_keys(entry,REGISTRY_RECORD_KEYS) or not Facts._integer(entry.get("part_id"),0,2147483647):return {}
  var id:int=int(entry.part_id)
  if id<=previous:return {}
  previous=id
  var source:Dictionary=entry.duplicate(true);source.erase("part_id");result[id]=source
 return result

static func validation_error(value:Variant) -> String:
 if not value is Dictionary or not Profile.exact_keys(value,KEYS) or not Profile.same_value(value.get("schema"),SCHEMA):return "completion_schema"
 if not value.route is Dictionary or not Offer.fixed_route_error(value.route).is_empty():return "completion_route"
 if not Facts._integer(value.seed,0,2147483647) or not Profile.same_value(value.seed,value.route.seed):return "completion_seed"
 if not Facts._integer(value.command_ticks,0,6000):return "completion_command_ticks"
 if not value.status is String or not value.status in ["success","failed"] or not Facts._number(value.elapsed,0.0,600.0):return "completion_outcome"
 if not Design.validation_error(value.launch_design,[]).is_empty():return "completion_design"
 var identity:Variant=value.dispatch_identity
 if not identity is Dictionary or not Profile.exact_keys(identity,["delivery_day","client","appearance_id"]):return "completion_customer_schema"
 if not Facts._integer(identity.delivery_day,5,1000000) or not identity.appearance_id is String or not identity.appearance_id in Offer.Stories.IDS:return "completion_customer"
 if not Profile.same_value(identity.client,Offer.Stories.PROFILES[identity.appearance_id].name) or not Profile.same_value(value.route.contract_id,"D%d-A"%int(identity.delivery_day)):return "completion_customer_identity"
 var registry:Dictionary=registry_from_records(value.registry)
 var error:String=Facts.validation_error(value.result,value.route,registry)
 if not error.is_empty():return error
 # One completed 60 Hz command advances at most two 120 Hz steps. Terminal
 # completion can stop on its first substep; abort before launch is tick zero.
 if int(value.result.physics_ticks)>int(value.command_ticks)*2 or int(value.result.physics_ticks)<maxi(0,int(value.command_ticks)*2-1):return "completion_tick_domains"
 if absf(float(value.elapsed)-float(value.result.physics_ticks)/120.0)>0.00001:return "completion_elapsed"
 var originals:Dictionary={}
 for part in value.launch_design:originals[int(part.id)]=str(part.type)
 for id in registry:
  var source:Dictionary=registry[id]
  if not originals.has(int(source.origin_part_id)) or not Profile.same_value(originals[int(source.origin_part_id)],source.part_type):return "completion_origin_design"
 for id in originals:
  if not registry.has(id) or not Profile.same_value(registry[id].origin_part_id,id) or not Profile.same_value(registry[id].part_type,originals[id]):return "completion_missing_launch_source"
 return ""

static func capture(order:Dictionary,snapshot:Dictionary,telemetry:Dictionary,elapsed:float,success:bool,completion:Variant) -> Dictionary:
 var error:String=validation_error(completion)
 if not error.is_empty():return {"ok":false,"error":error}
 if not Offer.validation_error(order).is_empty() or not snapshot.get("route") is Dictionary or not Offer.validation_error(snapshot.route).is_empty():return {"ok":false,"error":"completion_dispatch_route"}
 if not Profile.same_value(order.get("contract_id"),snapshot.get("contract_id")) or not Profile.same_value(order.contract_id,completion.route.contract_id):return {"ok":false,"error":"completion_contract"}
 if not Profile.same_value(completion.dispatch_identity,{"delivery_day":order.accepted_day,"client":order.client,"appearance_id":order.appearance_id}):return {"ok":false,"error":"completion_customer_changed"}
 var accepted:Dictionary=Offer.canonical_route(order)
 var dispatched:Dictionary=Offer.canonical_route(snapshot.route)
 # Research energy is fixed at dispatch; all other accepted physics stays exact.
 accepted.battery_capacity_multiplier=dispatched.get("battery_capacity_multiplier",1.0)
 if not Profile.same_value(accepted,dispatched) or not Profile.same_value(dispatched,completion.route):return {"ok":false,"error":"completion_changed_route"}
 if not Profile.same_value(snapshot.get("design"),completion.launch_design) or not Profile.same_value(snapshot.get("seed"),completion.seed) or not Profile.same_value(snapshot.get("ticks"),completion.command_ticks):return {"ok":false,"error":"completion_dispatch_identity"}
 if not Profile.same_value(telemetry.get("wildlife_result"),completion.result):return {"ok":false,"error":"completion_telemetry_mismatch"}
 if not Profile.same_value(elapsed,completion.elapsed) or success!=(completion.status=="success"):return {"ok":false,"error":"completion_terminal_outcome"}
 return {"ok":true,"error":"","evidence":completion.duplicate(true)}

static func receipt_validation_error(receipt:Dictionary) -> String:
 var evidence:Variant=receipt.get("wildlife_evidence")
 var error:String=validation_error(evidence)
 if not error.is_empty():return error
 if not Profile.same_value(receipt.get("contract_id"),evidence.route.contract_id) or not Profile.same_value(receipt.get("control_version"),Profile.CONTROL_VERSION):return "receipt_bird_identity"
 if not Profile.same_value(receipt.get("elapsed"),evidence.elapsed) or not receipt.get("success") is bool or receipt.success!=(evidence.status=="success"):return "receipt_bird_outcome"
 for pair in [["day",evidence.dispatch_identity.delivery_day],["client",evidence.dispatch_identity.client],["deadline",evidence.route.deadline],["required",evidence.route.required]]:
  if not Profile.same_value(receipt.get(pair[0]),pair[1]):return "receipt_bird_commercial_facts"
 var review_context:Variant=receipt.get("review_context")
 if not review_context is Dictionary or not Profile.same_value(review_context.get("appearance_id"),evidence.dispatch_identity.appearance_id):return "receipt_bird_customer"
 var context:Variant=receipt.get("route_context")
 if not context is Dictionary or not Profile.same_value(context.get("route_profile"),Profile.ROUTE_PROFILE) or not Profile.same_value(context.get("destination_name"),evidence.route.destination_name) or not Profile.same_value(receipt.get("route"),evidence.route.name):return "receipt_bird_route"
 return ""
