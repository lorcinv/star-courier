extends "res://scripts/pilot_delivery_ascent_simulation_v8.gd"
## RESEARCH ONLY. Never registered as a production contract or save protocol.
## Cut normal follows the splitter arrow; exact-zero socket projections go +.
const PROTOTYPE_ID:String="split-axis-source-experiment-01"
const HALF_GAP:float=0.002
var prototype_last_split:Dictionary={}

func _own_inertia(p:Dictionary)->float:
 return float(p.get("prototype_own_inertia",float(p.mass)/6.0))

func _rebuild_bodies()->void:
 super._rebuild_bodies()
 # Keep the frozen body's point velocities; replace only the local inertia term
 # for research halves. Unsplit modules retain the exact mass/6 convention.
 for body in bodies:
  var inertia:float=0.0;var momentum:float=0.0
  for q in body.parts:
   var r:Vector2=Vector2(q.world_pos)-Vector2(body.position)
   var own:float=_own_inertia(q)
   inertia+=float(q.mass)*r.length_squared()+own
   momentum+=float(q.mass)*r.cross(Vector2(q.world_velocity)-Vector2(body.velocity))+own*float(q.get("old_angular_velocity",0.0))
  body.inertia=maxf(EPS,inertia);body.angular_velocity=momentum/body.inertia

func prototype_totals()->Dictionary:
 var mass:float=0.0;var energy:float=0.0;var hp:float=0.0;var output:float=0.0;var capacity:float=0.0;var centre:Vector2=Vector2.ZERO
 for q in parts.values():
  if not q.alive or q.delivered:continue
  mass+=float(q.mass);energy+=float(q.energy)+float(q.stored_energy);hp+=float(q.hp);output+=float(q.output_factor);capacity+=float(q.capacity)
  centre+=_part_position(q)*float(q.mass)
 var linear:Vector2=Vector2.ZERO;var angular:float=0.0;var kinetic:float=0.0
 for body in bodies:
  var p:Vector2=Vector2(body.velocity)*float(body.mass)
  linear+=p;angular+=Vector2(body.position).cross(p)+float(body.inertia)*float(body.angular_velocity)
  kinetic+=.5*float(body.mass)*Vector2(body.velocity).length_squared()+.5*float(body.inertia)*float(body.angular_velocity)*float(body.angular_velocity)
 return {"mass":mass,"energy":energy,"hp":hp,"output":output,"capacity":capacity,"com":centre/maxf(EPS,mass),"linear":linear,"angular":angular,"kinetic":kinetic}

func _virtual_component(start:int,edges:Array)->Array:
 var seen:Array=[start];var queue:Array=[start]
 while not queue.is_empty():
  var id:int=queue.pop_front()
  for edge in edges:
   var next:int=int(edge.b) if int(edge.a)==id else (int(edge.a) if int(edge.b)==id else -1)
   if next>=0 and not seen.has(next):seen.append(next);queue.append(next)
 seen.sort();return seen

func _split_module(tool:Dictionary,target:Dictionary,body:Dictionary,dt:float)->void:
 prototype_last_split={"success":false,"reason":"invalid_target"}
 if parts.size()>=MAX_SIM_PARTS or not tool.alive or not target.alive or target.delivered:return
 if target.body_id!=body.id or not _linked(tool.id,target.id) or target.type in ["cargo","splitter"] or target.mass<0.05:return
 if not _can_supply(body,10.0,tool.id,dt):prototype_last_split.reason="no_energy";return
 var axis:Vector2=Vector2.RIGHT.rotated(float(body.angle)+float(tool.local_angle))
 var original_position:Vector2=_part_position(target)
 var original_velocity:Vector2=_part_velocity(target)
 var original_angle:float=float(body.angle)+float(target.local_angle)
 var omega:float=float(body.angular_velocity)
 var half_radius:float=.43*float(target.scale)*sqrt(.5)
 var offset:float=half_radius+HALF_GAP*.5
 var half_inertia:float=.5*_own_inertia(target)-.5*float(target.mass)*offset*offset
 if half_inertia<=EPS:prototype_last_split.reason="nonpositive_half_inertia";return
 var clone_id:int=_next_id
 var negative_position:Vector2=original_position-axis*offset
 var positive_position:Vector2=original_position+axis*offset
 var proposed:Array=[];var negative_neighbors:Array=[];var positive_neighbors:Array=[]
 for edge in links:
  var copy:Dictionary=edge.duplicate(true)
  var neighbor:int=int(edge.b) if int(edge.a)==int(target.id) else (int(edge.a) if int(edge.b)==int(target.id) else -1)
  if neighbor>=0:
   var positive:bool=(_part_position(parts[neighbor])-original_position).dot(axis)>=-EPS
   if positive:
    positive_neighbors.append(neighbor)
    if int(copy.a)==int(target.id):copy.a=clone_id
    else:copy.b=clone_id
   else:negative_neighbors.append(neighbor)
  proposed.append(copy)
 if negative_neighbors.is_empty() or positive_neighbors.is_empty():prototype_last_split.reason="one_side_has_no_socket";return
 var negative_group:Array=_virtual_component(int(target.id),proposed)
 var positive_group:Array=_virtual_component(clone_id,proposed)
 var bypass:bool=negative_group.has(clone_id)
 # Preflight only: no positional mutation or payment before all clearances pass.
 for fragment in [[int(target.id),negative_position,negative_group],[clone_id,positive_position,positive_group]]:
  var at:Vector2=fragment[1];var group:Array=fragment[2]
  for q in parts.values():
   if not q.alive or q.delivered or int(q.id)==int(target.id) or group.has(int(q.id)):continue
   if at.distance_to(_part_position(q))<half_radius+.43*float(q.scale)-EPS:
    prototype_last_split.reason="other_body_overlap";return
  for obstacle in obstacles:
   if float(obstacle.health)>0.0 and obstacle.type!="gravity" and at.distance_to(Vector2(obstacle.position))<half_radius+float(obstacle.radius)-EPS:
    prototype_last_split.reason="obstacle_overlap";return
 if not bypass and negative_position.distance_to(positive_position)<2.0*half_radius-EPS:
  prototype_last_split.reason="halves_overlap";return
 var before:Dictionary=prototype_totals()
 _consume(body,10.0,tool.id,dt)
 for key in ["mass","energy","capacity","hp","max_hp","strength","stored_energy","price","output_factor"]:target[key]*=.5
 target.base_scale*=sqrt(.5);target.scale*=sqrt(.5);target.prototype_own_inertia=half_inertia
 var clone:Dictionary=target.duplicate(true);clone.id=clone_id;_next_id+=1
 target.local_pos=(negative_position-Vector2(body.position)).rotated(-float(body.angle))
 target.world_pos=negative_position
 clone.body_id=-1;clone.local_pos=Vector2.ZERO;clone.world_pos=positive_position;clone.world_angle=original_angle
 var shift:Vector2=axis*offset
 clone.world_velocity=original_velocity+Vector2(-shift.y,shift.x)*omega
 clone.old_angular_velocity=omega;clone.old_force=Vector2(body.get("force",Vector2.ZERO))*float(clone.mass)/float(body.mass)
 clone.spent=true if clone.type in ["splitter","accelerator","spring","bomb"] else clone.spent
 parts[clone_id]=clone;links=proposed;_graph_dirty=true;_rebuild_bodies()
 var after:Dictionary=prototype_totals()
 prototype_last_split={"success":true,"reason":"bypass_still_connected" if bypass else "separated","target":int(target.id),"clone":clone_id,"axis":axis,"half_offset":offset,"half_inertia":half_inertia,"negative_ids":negative_group,"positive_ids":positive_group,"negative_neighbors":negative_neighbors,"positive_neighbors":positive_neighbors,"before":before,"after":after}
 _log("研究原型：目标两半按切分轴继承接口，"+("旁路仍连通。" if bypass else "形成真实两个子体。"))
