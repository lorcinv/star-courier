extends RefCounted
## Pure presentation selection. Caller supplies the authoritative structural edges.
## No adjacency inference, mass/collision changes, or gameplay ownership.
const MAX_TARGETS:int=153
const MAX_COMPONENT_SUPPORTS:int=2

static func choose(parts:Array,edges:Array) -> Array:
 var by_id:Dictionary={};var adjacency:Dictionary={}
 for p in parts:
  if not p is Dictionary or not p.has("id") or not p.has("contact"):continue
  var id:int=int(p.id);var point:Vector2=p.contact
  if not point.is_finite() or by_id.has(id) or by_id.size()>=MAX_TARGETS:continue
  by_id[id]=p;adjacency[id]=[]
 for edge in edges:
  var a:int;var b:int
  if edge is Dictionary:a=int(edge.get("a",-1));b=int(edge.get("b",-1))
  elif edge is Array and edge.size()==2:a=int(edge[0]);b=int(edge[1])
  else:continue
  if a==b or not by_id.has(a) or not by_id.has(b):continue
  if not adjacency[a].has(b):adjacency[a].append(b)
  if not adjacency[b].has(a):adjacency[b].append(a)
 var ids:Array=by_id.keys();ids.sort();var seen:Dictionary={};var selected:Array=[]
 for seed in ids:
  if seen.has(seed):continue
  var queue:Array=[seed];var component:Array=[]
  while not queue.is_empty():
   var id:int=int(queue.pop_back())
   if seen.has(id):continue
   seen[id]=true;component.append(id)
   for other in adjacency[id]:
    if not seen.has(other):queue.append(other)
  component.sort()
  # Lowest actual member in each narrow x column is eligible; upper modules are
  # carried by their real component. Separate components are never joined here.
  var bottom_by_column:Dictionary={}
  for id in component:
   var p:Dictionary=by_id[id];var column:int=roundi(float(p.get("center_x",p.contact.x))/8.0)
   if not bottom_by_column.has(column) or p.contact.y>by_id[bottom_by_column[column]].contact.y:bottom_by_column[column]=id
  var candidates:Array=bottom_by_column.values()
  candidates.sort_custom(func(a,b):return by_id[a].contact.x<by_id[b].contact.x if not is_equal_approx(by_id[a].contact.x,by_id[b].contact.x) else a<b)
  if candidates.is_empty():continue
  var wanted:Array=[candidates[0]]
  if candidates.size()>1 and by_id[candidates[-1]].contact.x-by_id[candidates[0]].contact.x>=40.0:wanted.append(candidates[-1])
  for id in wanted:
   var p:Dictionary=by_id[id]
   selected.append({"part_id":id,"component_id":int(component[0]),"component_parts":component.duplicate(),"contact":p.contact,"rear_path":false})
 return selected
