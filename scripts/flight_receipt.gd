extends RefCounted
## Presentation-only projection of the unchanged simulation event ring.
## No Nodes, wall-clock timers, Tweens, callbacks, or references to the HUD.
const MAX_EVENTS: int = 100
const VISIBLE_SECONDS: float = 6.0
const PORTAL_DENIALS: Dictionary = {
 "too_large_or_off_center":"未进入虫洞：请对准洞口，或缩小飞船轮廓。",
 "exit_blocked":"出口被挡住了，本次无法通行。",
 "station_empty":"驿站通行电量不足，本次无法过洞。"
}
const BIRD_FAILURE_PREFIX:String="保护鸟模拟未通过有限接触检查："
const BIRD_FAILURE_COPY:String="航行已停止，配送记录已保留。"
const BIRD_DIRECTION_COPY:String="保护鸟穿越 · 从下方绕行"
var _elapsed: float = 0.0
var _untimed_seen: Dictionary = {}

func reset() -> void:
 _elapsed=0.0;_untimed_seen.clear()

func update(data: Dictionary, limit: int = 2) -> Array[Dictionary]:
 var now:float=_number(data.get("elapsed"),_elapsed)
 if now<_elapsed:reset()
 _elapsed=now
 var source:Variant=data.get("events",[])
 if source is String:source=[source]
 if not source is Array:return []
 var recent:Array[Dictionary]=[]
 var unresolved:Array[Dictionary]=[]
 for raw in source.slice(maxi(0,source.size()-MAX_EVENTS)):
  if not raw is String or raw.is_empty():continue
  var presented:String=player_event(raw,str(data.get("control_version","")))
  var parsed:Dictionary=_parse(presented)
  var message:String=parsed.message
  if _is_narration(message):continue
  # The native receipt cue already announces confirmed delivery. Do not show
  # the solver's old autonomous-mode bookkeeping beside that same cue.
  if data.get("delivered") is bool and data.delivered and _is_delivery_bookkeeping(message):continue
  var at:float=parsed.at
  if at<0.0:
   if not _untimed_seen.has(raw):
    _untimed_seen[raw]=now
    if _untimed_seen.size()>MAX_EVENTS:_untimed_seen.erase(_untimed_seen.keys()[0])
   at=float(_untimed_seen[raw])
  # Retire only this exact v5 directional emitter. The raw event ring and
  # report/player_event projection keep their original history.
  var advice:Variant=data.get("protected_bird_advice")
  if str(data.get("control_version",""))=="pilot-v5-protected-bird" and message==BIRD_DIRECTION_COPY and advice is Dictionary and advice.get("active") is bool and not advice.active:continue
  var item:Dictionary={"text":message,"source":presented}
  # A current denied crossing remains actionable until cargo passes the portal.
  # Only exact, actually logged reasons qualify; unknown messages still pass.
  var denial:String=str(data.get("wormhole_last_denial",""))
  var pending:bool=str(data.get("control_version","")) in ["pilot-v4-wormhole","pilot-v5-protected-bird"] and str(data.get("wormhole_phase","")) in ["ascent","space"] and message==str(PORTAL_DENIALS.get(denial,""))
  if pending:unresolved=[item]
  elif now-at<=VISIBLE_SECONDS and at<=now+.051:recent.append(item)
 # Recent failures/damage take priority over an older pinned denial. Duplicate
 # fragment denials occupy one slot, never the whole receipt.
 unresolved.append_array(recent)
 return unresolved.slice(maxi(0,unresolved.size()-clampi(limit,1,3)))

static func player_event(raw:String,control_version:String) -> String:
 # Preserve the solver diagnostic and event chronology internally. Only this
 # exact v5 failure emitter has developer-only text; other events stay exact.
 if control_version!="pilot-v5-protected-bird":return raw
 var message:String=raw;var envelope:String=""
 var separator:int=raw.find("s  ")
 if separator>0:
  var token:String=raw.left(separator)
  if token.is_valid_float() and is_finite(token.to_float()) and token.to_float()>=0.0:
   envelope=raw.left(separator+3);message=raw.substr(separator+3)
 return envelope+BIRD_FAILURE_COPY if message.begins_with(BIRD_FAILURE_PREFIX) else raw

func _parse(raw: String) -> Dictionary:
 # This is the exact _log timestamp envelope, not a translation/filter regex.
 var separator:int=raw.find("s  ")
 if separator>0:
  var token:String=raw.left(separator)
  if token.is_valid_float():
   var at:float=token.to_float()
   if is_finite(at) and at>=0.0:return {"at":at,"message":raw.substr(separator+3)}
 return {"at":-1.0,"message":raw}

func _is_narration(message: String) -> bool:
 # Deliberately narrow emitter contracts. Never suppress unknown messages,
 # damage, resource failures, unsupported launches, overload, or safety limits.
 if message.begins_with("发射：") and message.ends_with(" kg。"):
  var fields:PackedStringArray=message.trim_prefix("发射：").trim_suffix(" kg。").split(" 个模块，质量 ")
  if fields.size()==2 and fields[0].is_valid_int() and int(fields[0])>=0 and _finite_token(fields[1]):return true
 if message.begins_with("发射台完成压缩供能，释放 ") and message.ends_with(" N·s 冲量。"):
  if _finite_token(message.trim_prefix("发射台完成压缩供能，释放 ").trim_suffix(" N·s 冲量。")):return true
 if message.begins_with("自动整备：回收 ") and message.ends_with(" 件；耗用与遗失不重复计费。"):
  var fields:PackedStringArray=message.trim_prefix("自动整备：回收 ").trim_suffix(" 件；耗用与遗失不重复计费。").split(" 件，补齐 ")
  if fields.size()==2 and fields[0].is_valid_int() and fields[1].is_valid_int() and int(fields[0])>=0 and int(fields[1])>=0:return true
 return false

func _is_delivery_bookkeeping(message:String) -> bool:
 if message.begins_with("货箱 ") and message.ends_with(" 已由平台接收。"):
  var token:String=message.trim_prefix("货箱 ").trim_suffix(" 已由平台接收。")
  return token.is_valid_int() and int(token)>=0
 if message.begins_with("全部货物自动投递成功：完整度 ") and message.ends_with("%。"):
  var token:String=message.trim_prefix("全部货物自动投递成功：完整度 ").trim_suffix("%。")
  return token.is_valid_int() and int(token)>=0 and int(token)<=100
 return false

func _finite_token(token: String) -> bool:
 return token.is_valid_float() and is_finite(token.to_float())

func _number(value: Variant, fallback: float) -> float:
 if not (value is int or value is float):return fallback
 return maxf(0.0,float(value)) if is_finite(float(value)) else fallback
