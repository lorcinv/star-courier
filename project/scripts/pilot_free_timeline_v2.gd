extends RefCounted
## v2 force semantics, selected only after exact route/snapshot schema validation.
## Last teleport aim is derived from the last nonzero recorded axis pair.
## The two extra fields are mandatory; v1 payloads cannot be adopted as v2.
## ~414 days at 60 Hz, not a gameplay timeout. Sparse bounded command storage.
const CONTROL_VERSION="pilot-free-v2"
const INPUT_SCHEMA="free-flight-input-v2"
const MAX_TICKS:int=2147483647
const MAX_COMMANDS:int=262144
var commands:Array=[]
var error:String=""
var _cursor:int=0
var _cursor_tick:int=-1
func _init() -> void:reset()
static func neutral() -> Dictionary:return {"axis_x_q":0,"axis_q":0,"boost":false,"active":false,"device_id":-1,"brake":false}
func reset() -> void:
 commands=[{"tick":0,"axis_x_q":0,"axis_q":0,"boost":false,"active":false,"device_id":-1,"brake":false}];error="";_cursor=0;_cursor_tick=-1
func record(tick:int,state:Dictionary) -> bool:
 if tick<0 or tick>MAX_TICKS or state.size()!=6 or not _valid_state(state):return _invalid()
 if not commands.is_empty() and tick<int(commands.back().tick):return _invalid()
 var command:Dictionary={"tick":tick,"axis_x_q":int(state.axis_x_q),"axis_q":int(state.axis_q),"boost":state.boost,"active":state.active,"device_id":int(state.device_id),"brake":state.brake}
 var replacing:bool=not commands.is_empty() and int(commands.back().tick)==tick
 var prior_index:int=commands.size()-2 if replacing else commands.size()-1
 var append_needed:bool=prior_index<0 or not _same_state(commands[prior_index],command)
 var next_size:int=commands.size()-(1 if replacing else 0)+(1 if append_needed else 0)
 if next_size>MAX_COMMANDS:return _invalid()
 if replacing:commands.pop_back()
 if append_needed:commands.append(command)
 _cursor=0;_cursor_tick=-1;error="";return true

func state_at(tick:int) -> Dictionary:
 if commands.is_empty():return neutral()
 if tick<_cursor_tick:_cursor=0
 while _cursor+1<commands.size() and int(commands[_cursor+1].tick)<=tick:_cursor+=1
 _cursor_tick=tick
 var c:Dictionary=commands[_cursor]
 return {"axis_x_q":int(c.axis_x_q),"axis_q":int(c.axis_q),"boost":c.boost,"active":c.active,"device_id":int(c.device_id),"brake":c.brake}
func snapshot() -> Array:return commands.duplicate(true)
func restore(value:Variant,completed_ticks:int) -> bool:
 if completed_ticks<0 or completed_ticks>MAX_TICKS or not value is Array or value.is_empty() or value.size()>MAX_COMMANDS:return _invalid()
 var accepted:Array=[];var previous:int=-1
 for raw in value:
  if not raw is Dictionary or raw.size()!=7 or not _integer(raw.get("tick")) or not _valid_state(raw):return _invalid()
  var tick:int=int(raw.tick)
  if tick<=previous or tick<0 or tick>completed_ticks or (accepted.is_empty() and tick!=0):return _invalid()
  accepted.append({"tick":tick,"axis_x_q":int(raw.axis_x_q),"axis_q":int(raw.axis_q),"boost":raw.boost,"active":raw.active,"device_id":int(raw.device_id),"brake":raw.brake});previous=tick
 commands=accepted;_cursor=0;_cursor_tick=-1;error="";return true
func _invalid() -> bool:
 error="自由飞行驾驶记录无法安全继续，已暂停并保留原记录。";return false
static func _integer(value:Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and absf(float(value))<=float(MAX_TICKS)
static func _valid_state(value:Dictionary) -> bool:
 return _integer(value.get("axis_x_q")) and _integer(value.get("axis_q")) and absf(float(value.axis_x_q))<=1000.0 and absf(float(value.axis_q))<=1000.0 and value.get("boost") is bool and value.get("active") is bool and _integer(value.get("device_id")) and int(value.device_id)>=-1 and value.get("brake") is bool
static func _same_state(a:Dictionary,b:Dictionary) -> bool:
 return a.axis_x_q==b.axis_x_q and a.axis_q==b.axis_q and a.boost==b.boost and a.active==b.active and a.device_id==b.device_id and a.brake==b.brake
