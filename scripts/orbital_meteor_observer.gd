extends RefCounted
## Presentation/accounting observation only; never writes to the simulation.
const VERSION="orbital-meteor-observer-v1"
const MAX_EVENTS=1
const MAX_FRAGMENTS=2
var _events:Array=[]
var _last_health:Dictionary={}
var _emitted:Dictionary={}
var _fragments:Array=[]
var _last_time:float=0.0
var cue_start_count:int=0
var burst_count:int=0
var _warned:Dictionary={}

func configure(route:Dictionary,sim,checkpoint:Dictionary={}) -> void:
 _events=route.get("orbital_event",{}).get("events",[]).duplicate(true)
 _last_health.clear();_emitted.clear();_fragments.clear();_warned.clear()
 cue_start_count=0;burst_count=0;_last_time=float(sim.elapsed)
 for e in _events:
  _last_health[e.id]=float(sim.obstacles[int(e.hazard_index)].health)
  if _last_health[e.id]<=0.0:_emitted[e.id]=true
 if checkpoint.get("version")==VERSION:
  var emitted:Variant=checkpoint.get("emitted",[])
  var warned:Variant=checkpoint.get("warned",[])
  if not emitted is Array or not warned is Array:return
  for id in emitted.slice(0,MAX_EVENTS):
   if _known(id):_emitted[id]=true
  for id in warned.slice(0,MAX_EVENTS):
   if _known(id):_warned[id]=true
  cue_start_count=clampi(int(checkpoint.get("cue_start_count",0)),0,MAX_EVENTS)
  burst_count=clampi(int(checkpoint.get("burst_count",0)),0,MAX_EVENTS)
 # Historical fragments are intentionally not restarted after resume. This is
 # only cosmetic; event geometry and health come from replayed saved physics.

func update(sim) -> Dictionary:
 var time:float=sim.elapsed
 if time<_last_time:return {"error":"Time reversed; configure a new attempt or restored checkpoint.","cues":[],"fragments":[],"new_destructions":[]}
 var cues:Array=[];var destroyed:Array=[]
 for e in _events:
  var h:Dictionary=sim.obstacles[int(e.hazard_index)]
  var health:float=h.health
  if health>0.0 and time>=float(e.warning_start_seconds) and time<=float(e.warning_end_seconds) and not _whole_craft_passed(sim,h):
   if not _warned.has(e.id):_warned[e.id]=true;cue_start_count+=1
   cues.append({"id":e.id,"position":h.position,"velocity":h.velocity,
    "center_crossing_in":float(e.center_crossing_seconds)-time,"radius":float(e.radius)})
  if float(_last_health.get(e.id,health))>0.0 and health<=0.0 and not _emitted.has(e.id):
   _emitted[e.id]=true;burst_count+=1;destroyed.append(e.id)
   for i in range(MAX_FRAGMENTS):
    _fragments.append({"id":e.id+"-fragment-"+str(i),"sprite":"fragment-a" if i==0 else "fragment-b",
     "position":h.position,"velocity":h.velocity+Vector2(-1.0 if i==0 else 1.0,-1.5 if i==0 else 1.5),
     "born":time,"expires":time+float(e.fragment_lifetime_seconds)})
  _last_health[e.id]=health
 _fragments=_fragments.filter(func(f):return time<float(f.expires))
 _last_time=time
 return {"error":"","cues":cues,"fragments":_fragments.duplicate(true),"new_destructions":destroyed}

func snapshot() -> Dictionary:
 return {"version":VERSION,"emitted":_emitted.keys(),"warned":_warned.keys(),"cue_start_count":cue_start_count,"burst_count":burst_count}

func _known(id:Variant) -> bool:
 for e in _events:
  if e.id==id:return true
 return false

func _whole_craft_passed(sim,h:Dictionary) -> bool:
 # The entire occupied module raster fits inside this conservative circle.
 # Use every living module, including detached pieces, rather than cargo alone.
 # This is a read-only warning condition, never a simulation/collider change.
 var left:float=INF
 for part in sim.parts.values():
  if bool(part.get("alive",false)):
   left=minf(left,sim.part_world_position(int(part.id)).x-.71*float(part.get("scale",1.0)))
 return is_finite(left) and left>float(h.position.x)+float(h.radius)+.1
