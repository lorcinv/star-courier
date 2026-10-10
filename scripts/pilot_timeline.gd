extends RefCounted
## Versioned, sparse 60 Hz input history. A command at tick N is applied before
## simulation step N; ticks in a checkpoint counts COMPLETED 1/60 steps.
const CONTROL_VERSION:String="pilot-v1"
const MAX_TICKS:int=36000
var commands:Array=[]
var error:String=""
var _cursor:int=0
var _cursor_tick:int=-1

func _init() -> void:reset()

static func neutral() -> Dictionary:
 return {"axis_q":0,"boost":false,"active":false}

static func quantize(axis:float,boost:bool,active:bool) -> Dictionary:
 return {"axis_q":clampi(roundi(axis*1000),-1000,1000) if is_finite(axis) else 0,"boost":boost,"active":active}

func reset() -> void:
 commands=[{"tick":0,"axis_q":0,"boost":false,"active":false}]
 error="";_cursor=0;_cursor_tick=-1

func record(tick:int,state:Dictionary) -> bool:
 if tick<0 or tick>MAX_TICKS:error="控制记录超出安全时长。";return false
 var command:Dictionary={"tick":tick,"axis_q":clampi(int(state.get("axis_q",0)),-1000,1000),"boost":bool(state.get("boost",false)),"active":bool(state.get("active",false))}
 if not commands.is_empty() and tick<int(commands.back().tick):error="控制记录的时间顺序无效。";return false
 if not commands.is_empty() and int(commands.back().tick)==tick:commands.pop_back()
 if commands.is_empty() or not _same_state(commands.back(),command):commands.append(command)
 _cursor=0;_cursor_tick=-1
 return true

func state_at(tick:int) -> Dictionary:
 if commands.is_empty():return neutral()
 if tick<_cursor_tick:_cursor=0
 while _cursor+1<commands.size() and int(commands[_cursor+1].tick)<=tick:_cursor+=1
 _cursor_tick=tick
 var command:Dictionary=commands[_cursor]
 return {"axis_q":int(command.axis_q),"boost":bool(command.boost),"active":bool(command.active)}

func snapshot() -> Array:return commands.duplicate(true)

func restore(value:Variant,completed_ticks:int) -> bool:
 error=""
 if not value is Array or value.is_empty() or value.size()>MAX_TICKS+1:return _invalid()
 if completed_ticks<0 or completed_ticks>MAX_TICKS:return _invalid()
 var previous:int=-1
 var accepted:Array=[]
 for raw in value:
  if not raw is Dictionary:return _invalid()
  for key in ["tick","axis_q"]:
   if not (raw.get(key) is int or raw.get(key) is float):return _invalid()
   if not is_finite(float(raw[key])) or float(raw[key])!=float(int(raw[key])):return _invalid()
  if not raw.get("boost") is bool or not raw.get("active") is bool:return _invalid()
  var tick:int=int(raw.tick);var axis:int=int(raw.axis_q)
  if tick<=previous or tick<0 or tick>completed_ticks or absi(axis)>1000:return _invalid()
  if accepted.is_empty() and tick!=0:return _invalid()
  accepted.append({"tick":tick,"axis_q":axis,"boost":raw.boost,"active":raw.active});previous=tick
 commands=accepted;_cursor=0;_cursor_tick=-1
 return true

func _invalid() -> bool:
 error="驾驶记录损坏或版本不兼容，已停止恢复，原始存档保留。"
 return false

func _same_state(a:Dictionary,b:Dictionary) -> bool:
 return int(a.axis_q)==int(b.axis_q) and bool(a.boost)==bool(b.boost) and bool(a.active)==bool(b.active)
