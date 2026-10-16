extends SceneTree
## Dedicated five-candidate expansion coverage. Does not edit dev06 assertions.
## Uses synthetic progression fixtures; no claim of played deliveries.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
class Catalog extends "res://scripts/economy.gd":
 var catalog:Array=[]
 func routes() -> Array:return catalog.duplicate(true)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func ids(offers:Array) -> Array:
 var result:Array=[]
 for order in offers:result.append(int(order.id))
 return result
func gate(route:Dictionary,allow_mosslight:bool=true) -> String:
 # Model capability boundary: art readyness is separately checked by the
 # presenter's receipt test. No fake asset success is written into production.
 if Content.has_markers(route) and not allow_mosslight:return "new art unavailable"
 return Caps.route_error(route)
func model(day:int,rep:int=4,allow_mosslight:bool=true):
 var e=Econ.new();e.enable_force_mode();e.day=day;e.reputation=rep;e.deliveries=2;e.credits=600
 e.route_guard=gate.bind(allow_mosslight);return e
func _initialize() -> void:
 var five:Array=[0,1,2,6,7];var old:Array=[0,1,2,6]
 var pairs:Array=[[0,2],[1,6],[2,7],[6,0],[7,1]]
 var old_pairs:Array=[[0,2],[1,6],[2,0],[6,1]]
 var seen_a:Dictionary={};var seen_b:Dictionary={}
 for index in range(5):
  var e=model(index+1);e.ensure_contracts()
  check(ids(e.contracts)==pairs[index],"new five-item pool half-offset day%d"%(index+1))
  if e.contracts.size()!=2:continue
  var a:int=int(e.contracts[0].id);var b:int=int(e.contracts[1].id)
  seen_a[a]=int(seen_a.get(a,0))+1;seen_b[b]=int(seen_b.get(b,0))+1
  for slot in 2:check(Econ.route_validation_error(e.contracts[slot]).is_empty(),"new pair validates day%d slot%d"%[index+1,slot])
 for id in five:check(seen_a.get(id)==1 and seen_b.get(id)==1,"each new ordinary ID occupies both slots once: "+str(id))
 for index in range(4):
  var e=model(index+1,4,false);e.ensure_contracts()
  check(ids(e.contracts)==old_pairs[index],"cap-off keeps the exact four-item old pair day%d"%(index+1))
 for rep in [2,4]:
  var e=model(2,rep);e.ensure_contracts()
  check(ids(e.contracts)==[1,6] and e.contracts[1].deadline==83.0,"D2-B6 lunar entry remains exact at rep%d"%rep)
 var third=model(3);third.ensure_contracts()
 check(ids(third.contracts)==[2,7] and third.contracts[1].rep==4 and third.contracts[1].deadline==88.0 and third.contracts[1].weight==1.25*1.55,"D3-B7 naturally authors exact heavy mosslight terms")
 var low=model(3,3);low.ensure_contracts();check(not 7 in ids(low.contracts),"rep below4 does not introduce new route")
 # Entirely ordinary five-item pool opts in. Mixed pools retain all historical
 # candidates and their original final ID6, even when the new art is available.
 var early=model(1,10);early.ensure_contracts();check(ids(early.contracts)==[0,6],"early mixed legacy-ID4 pool keeps historical pair")
 var unbound=model(4,12);unbound.route_guard=Callable();unbound.ensure_contracts()
 check(ids(unbound.contracts)==[3,6],"unbound wormhole/Moon mixed pool keeps historical pair")
 var current_unbound=model(3);current_unbound.route_guard=Callable();current_unbound.ensure_contracts()
 check(ids(current_unbound.contracts)==[2,7],"unbound genuinely ordinary pool can use ID7")
 for mode in ["autonomous-v5","pilot-v1","pilot-v2","pilot-v3","pilot-free-v1"]:
  var e=model(3);e.flight_mode=mode;e.ensure_contracts()
  check(ids(e.contracts)==[2,2] and not 7 in ids(e.routes()),"historical catalog and pair unchanged: "+mode)
 for row in [{"deliveries":1,"credits":600,"last":{}},{"deliveries":2,"credits":219,"last":{}},{"deliveries":2,"credits":600,"last":{"success":false}}]:
  var e=model(3);e.deliveries=row.deliveries;e.credits=row.credits;e.last_settlement=row.last;e.ensure_contracts()
  check(ids(e.contracts)==[0,0] and e.contracts[0].reward==220 and e.contracts[1].reward==220 and e.contracts[0].weight==1.0 and e.contracts[1].weight==1.0 and e.contracts[1].variant=="轻件续单" and e.contracts[1].deadline==35.0,"recovery light follow-up remains first priority: "+str(row))
 var snapshots=model(3,4,false);snapshots.ensure_contracts();var frozen:Array=snapshots.contracts.duplicate(true)
 snapshots.route_guard=gate.bind(true);snapshots.reputation=12;snapshots.enable_force_mode()
 snapshots.ensure_contracts();snapshots.available_contracts();snapshots.contract_by_id("D3-B")
 check(snapshots.contracts==frozen and ids(snapshots.contracts)==[2,0],"newly available art and rep do not reroll existing available orders")
 for status in ["accepted","settled","cancelled"]:
  snapshots.contracts[1].status=status;frozen=snapshots.contracts.duplicate(true);snapshots.ensure_contracts()
  check(snapshots.contracts==frozen,"committed status blocks all reauthoring: "+status)
 var flying=model(3);flying.in_flight={"contract_id":"D3-B","route":{"id":6}}
 var flight:Dictionary=flying.in_flight.duplicate(true);flying.ensure_contracts()
 check(flying.contracts.is_empty() and flying.in_flight==flight,"in-flight-only saved snapshot blocks authoring")
 var catalog:Array=model(3).routes().filter(func(route):return int(route.id) in five)
 var e=Econ.new()
 check(e._ordinary_force_pool(catalog),"exact five candidate pool registers")
 check(not e._ordinary_force_pool(catalog+[catalog[0]]) and not e._ordinary_force_pool(catalog.slice(0,4)+[catalog[0]]),"six candidates or duplicated five-item pool cannot opt in")
 check(e._ordinary_force_pool(catalog.filter(func(route):return int(route.id) in old)),"old four-candidate ordinary pool remains registered")
 for key in ["unknown_id","missing_policy","wrong_version","invalid_force","generation"]:
  var special=Catalog.new();special.enable_force_mode();special.day=3;special.reputation=4;special.deliveries=2;special.credits=600;special.catalog=catalog.duplicate(true)
  match key:
   "unknown_id":special.catalog[1].id=99
   "missing_policy":special.catalog[1].erase("economy_policy")
   "wrong_version":special.catalog[1].control_version="pilot-v3"
   "invalid_force":special.catalog[1].free_drive_throttle=0.123
   "generation":special.catalog[1].generation={"version":"future"}
  special.ensure_contracts();check(ids(special.contracts)==[2,6],"new ID7 cannot disturb mixed/invalid historical pairing: "+key)
 print("MOSSLIGHT_ROTATION_DEV17 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
