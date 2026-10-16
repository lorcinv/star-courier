extends RefCounted
## Presentation-only power observations. Never migrates blueprints or changes a solver.
## A socket is an orthogonal one-cell link. Rotation, footprint and visual scale do
## not create sockets; every structural module can carry the actual circuit.
const EPS:float=0.00001

static func analyze(design:Array) -> Dictionary:
 var result:Dictionary={"cargo_ids":[],"battery_ids":[],"unpowered_cargo_ids":[],"disconnected_battery_ids":[],"powered_ids":[],"status":"blocked","code":"no_cargo","ready":false}
 var nodes:Dictionary={};var next_id:int=1
 # Mirror configure's identity/default-coordinate rules without writing to input.
 for raw in design:
  if not raw is Dictionary:continue
  var id:int=int(raw.get("id",next_id))
  if nodes.has(id):id=next_id
  next_id=maxi(next_id,id+1)
  nodes[id]={"id":id,"type":str(raw.get("type","beam")),"x":int(raw.get("x",0)),"y":int(raw.get("y",0))}
  if nodes[id].type=="cargo":result.cargo_ids.append(id)
  if nodes[id].type=="battery":result.battery_ids.append(id)
 var neighbors:Dictionary={}
 for id in nodes:neighbors[id]=[]
 var ids:Array=nodes.keys()
 for i in range(ids.size()):
  for j in range(i+1,ids.size()):
   var a:Dictionary=nodes[ids[i]];var b:Dictionary=nodes[ids[j]]
   if absi(a.x-b.x)+absi(a.y-b.y)==1:
    neighbors[a.id].append(b.id);neighbors[b.id].append(a.id)
 var seen:Dictionary={}
 for first in ids:
  if seen.has(first):continue
  var component:Array=[];var queue:Array=[first];seen[first]=true
  var has_cargo:bool=false;var has_battery:bool=false
  while not queue.is_empty():
   var current:int=int(queue.pop_front());component.append(current)
   has_cargo=has_cargo or nodes[current].type=="cargo"
   has_battery=has_battery or nodes[current].type=="battery"
   for adjacent in neighbors[current]:
    if not seen.has(adjacent):seen[adjacent]=true;queue.append(adjacent)
  for id in component:
   if has_battery:result.powered_ids.append(id)
   if nodes[id].type=="cargo" and not has_battery:result.unpowered_cargo_ids.append(id)
   if nodes[id].type=="battery" and not has_cargo:result.disconnected_battery_ids.append(id)
 for key in ["cargo_ids","battery_ids","unpowered_cargo_ids","disconnected_battery_ids","powered_ids"]:result[key].sort()
 if result.cargo_ids.is_empty():return result
 if result.battery_ids.is_empty():result.code="no_battery";return result
 if not result.unpowered_cargo_ids.is_empty():result.code="cargo_unpowered";return result
 result.ready=true
 result.status="ready" if result.disconnected_battery_ids.is_empty() else "warning"
 result.code="ready" if result.disconnected_battery_ids.is_empty() else "disconnected_battery"
 return result

static func runtime_failure(sim) -> Dictionary:
 var result:Dictionary=_runtime_result(sim)
 if sim==null:return result
 if str(sim.status)!="failed" or result.failure_code!="usable_energy_empty":return result
 return _collect_runtime_status(sim,result)

## Live presentation evidence, including configure-before-first-step and launch
## preparation. The host owns version/phase applicability. Never advances a tick,
## refreshes telemetry, rebuilds bodies, or copies mutable simulation structures.
## runtime_failure deliberately keeps its original terminal-only contract.
static func runtime_status(sim) -> Dictionary:
 var result:Dictionary=_runtime_result(sim)
 result.ready=false
 if sim==null:return result
 # A power observation must not replace a different terminal failure's reason.
 if str(sim.status)=="failed" and result.failure_code!="usable_energy_empty":return result
 _collect_runtime_status(sim,result)
 if not result.cargo_ids.is_empty() and result.empty_cargo_ids.is_empty():
  result.code="ready";result.ready=true
 return result

static func _runtime_result(sim) -> Dictionary:
 return {"code":"not_applicable","failure_code":"" if sim==null else str(sim.telemetry.get("free_failure","")),"cargo_ids":[],"empty_cargo_ids":[],"battery_ids":[],"connected_battery_ids":[],"disconnected_battery_ids":[],"destroyed_battery_ids":[],"unavailable_battery_ids":[],"cargo_failures":[]}

static func _collect_runtime_status(sim,result:Dictionary) -> Dictionary:
 var all_battery_ids:Array=[]
 for p in sim.parts.values():
  if p.type=="cargo" and p.alive and not p.delivered:result.cargo_ids.append(int(p.id))
  if p.type!="battery":continue
  all_battery_ids.append(int(p.id))
  if not p.alive:result.destroyed_battery_ids.append(int(p.id))
  elif p.delivered:result.unavailable_battery_ids.append(int(p.id))
  else:result.battery_ids.append(int(p.id))
 result.cargo_ids.sort()
 var reasons:Dictionary={};var connected_to_cargo:Dictionary={}
 for cargo_id in result.cargo_ids:
  var cargo:Dictionary=sim.parts[cargo_id]
  var body:Dictionary=sim.body_for_part(cargo_id)
  var connected:Array=[]
  # Body membership alone is stale between a cut/damage and the next rebuild.
  # _same_circuit consults the live _component graph whenever it is dirty.
  for battery in body.get("parts",[]):
   if battery.type=="battery" and battery.alive and not battery.delivered and sim._same_circuit(cargo,battery):
    connected.append(int(battery.id));connected_to_cargo[int(battery.id)]=true
  connected.sort()
  var available:float=0.0 if body.is_empty() else float(sim._available_energy(body,cargo_id))
  if available>EPS:continue
  var code:String="energy_depleted"
  if connected.is_empty():
   if not result.battery_ids.is_empty():code="battery_disconnected"
   elif all_battery_ids.is_empty():code="no_battery"
   elif not result.unavailable_battery_ids.is_empty():code="battery_unavailable"
   else:code="battery_destroyed"
  result.empty_cargo_ids.append(cargo_id)
  result.cargo_failures.append({"cargo_id":cargo_id,"code":code,"available_energy":available,"connected_battery_ids":connected})
  reasons[code]=true
 result.connected_battery_ids=connected_to_cargo.keys()
 for id in result.battery_ids:
  if not connected_to_cargo.has(id):result.disconnected_battery_ids.append(id)
 for key in ["battery_ids","connected_battery_ids","disconnected_battery_ids","destroyed_battery_ids","unavailable_battery_ids"]:result[key].sort()
 if reasons.size()==1:result.code=str(reasons.keys()[0])
 elif reasons.size()>1:result.code="mixed_power_failure"
 return result
