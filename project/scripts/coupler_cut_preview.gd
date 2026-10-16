extends RefCounted
## Read-only prediction of removing one socket pair. No firing/target authority.
static func text(still_connected:bool) -> String:
 return "断开后仍相连" if still_connected else "断开后会分离"

static func from_design(part:Dictionary,target:Dictionary,parts:Array) -> bool:
 var edges:Array=[];var ids:Dictionary={}
 for item in parts:ids[int(item.id)]=true
 for i in range(parts.size()):
  for j in range(i+1,parts.size()):
   if absi(int(parts[i].x)-int(parts[j].x))+absi(int(parts[i].y)-int(parts[j].y))==1:
    edges.append({"a":int(parts[i].id),"b":int(parts[j].id)})
 return _connected_after_cut(int(part.id),int(target.id),edges,ids)

static func from_live(sim,part:Dictionary,target:Dictionary,body:Dictionary) -> bool:
 var ids:Dictionary={}
 for item in sim.parts.values():
  if item.alive and not item.delivered and int(item.body_id)==int(body.id):ids[int(item.id)]=true
 # Never reconstruct sockets from saved grid coordinates: cut/broken links stay
 # absent, and dead/delivered parts or other bodies cannot provide a bypass.
 return _connected_after_cut(int(part.id),int(target.id),sim.links,ids)

static func _connected_after_cut(first:int,target:int,edges:Array,ids:Dictionary) -> bool:
 if not ids.has(first) or not ids.has(target):return false
 var seen:Dictionary={first:true};var queue:Array=[first]
 while not queue.is_empty():
  var current:int=int(queue.pop_front())
  for edge in edges:
   var a:int=int(edge.a);var b:int=int(edge.b)
   # The solver removes every occurrence of this undirected socket pair.
   if (a==first and b==target) or (a==target and b==first):continue
   var next:int=b if a==current else a if b==current else -1
   if next<0 or not ids.has(next) or seen.has(next):continue
   if next==target:return true
   seen[next]=true;queue.append(next)
 return false

## Hypothetical assembly topology only. Does not mutate links or predict charge,
## trajectories, impulse, damage, or delivery success. Unrelated groups excluded.
static func design_groups(part:Dictionary,target:Dictionary,parts:Array) -> Dictionary:
 var empty:Dictionary={"valid":false,"separates":false,"groups":[]}
 if part.is_empty() or target.is_empty():return empty
 var first:int=int(part.get("id",-1));var second:int=int(target.get("id",-1))
 var by_id:Dictionary={};var edges:Array=[]
 for item in parts:by_id[int(item.id)]=item
 if not by_id.has(first) or not by_id.has(second) or first==second:return empty
 if absi(int(part.x)-int(target.x))+absi(int(part.y)-int(target.y))!=1:return empty
 for i in parts.size():
  for j in range(i+1,parts.size()):
   if absi(int(parts[i].x)-int(parts[j].x))+absi(int(parts[i].y)-int(parts[j].y))==1:edges.append({"a":int(parts[i].id),"b":int(parts[j].id)})
 var original:Array=_reachable(first,edges,-1,-1)
 var pending:Array=original.duplicate();pending.sort()
 var groups:Array=[]
 while not pending.is_empty():
  var ids:Array=_reachable(int(pending[0]),edges,first,second);ids.sort()
  var cells:Array=[];var cargo:int=0;var batteries:int=0
  for id in ids:
   pending.erase(id)
   var item:Dictionary=by_id[id];cells.append(Vector2(item.x,item.y))
   if str(item.type)=="cargo":cargo+=1
   if str(item.type)=="battery":batteries+=1
  groups.append({"ids":ids,"cells":cells,"count":ids.size(),"cargo_count":cargo,"battery_count":batteries})
 return {"valid":true,"separates":groups.size()>1,"groups":groups,"cut_from":Vector2(part.x,part.y),"cut_to":Vector2(target.x,target.y)}

static func _reachable(start:int,edges:Array,cut_a:int,cut_b:int)->Array:
 var result:Array=[start];var cursor:int=0
 while cursor<result.size():
  var id:int=int(result[cursor]);cursor+=1
  for edge in edges:
   var a:int=int(edge.a);var b:int=int(edge.b)
   if (a==cut_a and b==cut_b) or (a==cut_b and b==cut_a):continue
   var next:int=b if a==id else a if b==id else -1
   if next>=0 and not result.has(next):result.append(next)
 return result

static func group_text(preview:Dictionary,pilot:bool)->String:
 if not bool(preview.get("valid",false)) or not bool(preview.get("separates",false)):return ""
 var lines:Array[String]=["断开预览：当前相连组变为%d组"%preview.groups.size()]
 var missing_battery:bool=false;var detached:bool=false
 for index in preview.groups.size():
  var g:Dictionary=preview.groups[index]
  lines.append("%d%s：%d件 · 货物%d · 电芯%d"%[index+1,"青" if index==0 else "紫",g.count,g.cargo_count,g.battery_count])
  missing_battery=missing_battery or (int(g.cargo_count)>0 and int(g.battery_count)==0)
  detached=detached or int(g.cargo_count)==0
 if missing_battery:lines.append("注意：货物组没有电芯，分离后不能借另一组电量。")
 if pilot and detached:lines.append("无货物组不再接收驾驶输入。")
 lines.append("仅预览连接与电芯数量，不代表剩余电量或能否送达。")
 return "\n".join(lines)
