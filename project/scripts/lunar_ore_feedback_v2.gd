extends RefCounted
## Presentation-only samples. Health loss does not identify its damage source.
## No events, telemetry, replay state or obstacle fields are written here.
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const ORE_IDS:Array[String]=["lunar-ore-west-v2","lunar-ore-east-v2"]
const MAX_ORES:int=2
const HIT_DURATION:float=.18
const HIT_INTERVAL:float=.45
const BURST_DURATION:float=.65
const LABEL_DURATION:float=1.6
var _enabled:bool=false
var _owner:int=0
var _elapsed:float=-1.0
var _health:Dictionary={}
var _cues:Dictionary={}

func configure(route:Dictionary) -> bool:
 clear()
 _enabled=str(route.get("control_version",""))==Content.CONTROL_VERSION and Content.validation_error(route).is_empty()
 return _enabled

func clear() -> void:
 _enabled=false;_owner=0;_elapsed=-1.0;_health.clear();_cues.clear()

func observe(owner:int,elapsed:float,obstacles:Array) -> void:
 if not _enabled:return
 # RefCounted instance IDs can occupy the signed high-bit range in Godot.
 # Zero alone means no owner; negative IDs are real simulation identities.
 if owner==0 or not is_finite(elapsed) or elapsed<0.0:
  _prime(0,-1.0,{});return
 var current:Dictionary={}
 var duplicate_ids:Dictionary={}
 for value in obstacles:
  if not value is Dictionary:continue
  var id:String=str(value.get("id",""))
  if id not in ORE_IDS:continue
  if current.has(id):duplicate_ids[id]=true;continue
  var hp:Variant=value.get("health")
  var point:Variant=value.get("position")
  if not (hp is int or hp is float) or not is_finite(float(hp)) or not point is Vector2 or not point.is_finite():continue
  current[id]={"health":float(hp),"position":point}
 for id in duplicate_ids:current.erase(id)
 # First render, a reconstructed/replaced simulation and time reversal seed a
 # baseline only. They cannot replay a destruction that happened off screen.
 if _owner!=owner or _elapsed<0.0 or elapsed<_elapsed:
  _prime(owner,elapsed,current);return
 if elapsed==_elapsed:
  # Ordinary pause preserves an earned cue. A same-time edited/reseeded health
  # sample instead establishes a new baseline, without inventing an event.
  if not _same_health(current):_prime(owner,elapsed,current)
  return
 for id in ORE_IDS:
  if not current.has(id):_health.erase(id);_cues.erase(id);continue
  var hp:float=current[id].health
  if _health.has(id):
   var before:float=_health[id]
   if hp>before:
    _cues.erase(id)
   elif before>0.0 and hp<before:
    var cue:Dictionary=_cues.get(id,{"hit_started":-1.0,"break_started":-1.0})
    if hp<=0.0:
     cue.hit_started=-1.0;cue.break_started=elapsed
     cue.position=current[id].position;_cues[id]=cue
    elif float(cue.hit_started)<0.0 or elapsed-float(cue.hit_started)>=HIT_INTERVAL:
     cue.hit_started=elapsed;cue.position=current[id].position;_cues[id]=cue
  _health[id]=hp
 _elapsed=elapsed
 # Retain the last hit timestamp for the cooldown, never a growing hit list.
 for id in _cues.keys():
  var cue:Dictionary=_cues[id]
  var hit_done:bool=float(cue.hit_started)<0.0 or elapsed-float(cue.hit_started)>=HIT_INTERVAL
  var break_done:bool=float(cue.break_started)<0.0 or elapsed-float(cue.break_started)>=LABEL_DURATION
  if hit_done and break_done:_cues.erase(id)

func _prime(owner:int,elapsed:float,current:Dictionary) -> void:
 _owner=owner;_elapsed=elapsed;_health.clear();_cues.clear()
 for id in current:_health[id]=current[id].health

func _same_health(current:Dictionary) -> bool:
 if current.size()!=_health.size():return false
 for id in current:
  if not _health.has(id) or float(current[id].health)!=float(_health[id]):return false
 return true

func frame() -> Array[Dictionary]:
 var result:Array[Dictionary]=[]
 for id in ORE_IDS:
  if not _cues.has(id):continue
  var cue:Dictionary=_cues[id]
  var hit_age:float=_elapsed-float(cue.hit_started)
  var break_age:float=_elapsed-float(cue.break_started)
  var hit:float=clampf(1.0-hit_age/HIT_DURATION,0.0,1.0) if float(cue.hit_started)>=0.0 else 0.0
  var burst:float=clampf(1.0-break_age/BURST_DURATION,0.0,1.0) if float(cue.break_started)>=0.0 else 0.0
  var label:float=clampf((LABEL_DURATION-break_age)/.3,0.0,1.0) if float(cue.break_started)>=0.0 else 0.0
  if hit>0.0 or burst>0.0 or label>0.0:
   result.append({"id":id,"position":cue.position,"hit_strength":hit,"burst_alpha":burst,"label_alpha":label})
 return result

func debug_snapshot() -> Dictionary:
 return {"enabled":_enabled,"owner":_owner,"elapsed":_elapsed,"tracked_ores":_health.size(),"cue_count":_cues.size(),"frame":frame()}
