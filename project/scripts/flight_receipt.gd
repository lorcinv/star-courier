extends RefCounted
## Presentation-only projection of the unchanged simulation event ring.
## No Nodes, wall-clock timers, Tweens, callbacks, or references to the HUD.
const DisplayParts=preload("res://scripts/parts_expanded.gd")
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
const SPLITTER_SUCCESS_COPY:String="模块分裂：质量、储能、强度与耐久均分，未复制货物。"
var _elapsed: float = 0.0
var _untimed_seen: Dictionary = {}
var _shield_seen: bool = false
var _shield_elapsed: float = 0.0
var _shield_absorbed: float = 0.0
var _shield_energy: float = 0.0
var _shield_until: float = -1.0
var _shield_copy: String = ""

func reset() -> void:
 _elapsed=0.0;_untimed_seen.clear();_reset_shield()

func _reset_shield() -> void:
 _shield_seen=false;_shield_elapsed=0.0;_shield_absorbed=0.0;_shield_energy=0.0;_shield_until=-1.0;_shield_copy=""

static func shield_totals(data:Dictionary) -> Dictionary:
 # Read only existing paid COLLISION absorption counters. Never infer a shield
 # effect from total ship energy, installed parts, an attack or contact alone.
 if str(data.get("control_version","")) not in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:return {}
 var absorbed:Variant=data.get("impact_absorbed")
 var energy:Variant=data.get("impact_shield_energy")
 if not (absorbed is int or absorbed is float) or not (energy is int or energy is float):return {}
 if not is_finite(float(absorbed)) or not is_finite(float(energy)) or float(absorbed)<0.0 or float(energy)<0.0:return {}
 if (float(absorbed)>0.0)!=(float(energy)>0.0):return {}
 return {"impact_absorbed":absorbed,"impact_shield_energy":energy}

func shield_receipt(data:Dictionary) -> String:
 var totals:Dictionary=shield_totals(data)
 var raw_time:Variant=data.get("elapsed")
 var navigation:Variant=data.get("destination_navigation",{})
 var terminal:bool=str(data.get("flight_status",data.get("status","")))!="running" or str(data.get("status","")) in ["success","failed"] or str(data.get("arrival_state",""))=="received" or (data.get("delivered") is bool and data.delivered)
 if navigation is Dictionary and (str(navigation.get("status","")) in ["success","failed"] or (navigation.get("charging") is bool and navigation.charging)):terminal=true
 if totals.is_empty() or terminal or (data.get("charging") is bool and data.charging) or not (raw_time is int or raw_time is float):
  _reset_shield();return ""
 var now:float=float(raw_time)
 if not is_finite(now) or now<0.0:_reset_shield();return ""
 var absorbed:float=totals.impact_absorbed;var energy:float=totals.impact_shield_energy
 if not _shield_seen or now<_shield_elapsed or absorbed<_shield_absorbed or energy<_shield_energy:
  # A restored/rebuilt flight with historical totals is only a baseline.
  _reset_shield();_shield_seen=true
 elif absorbed>_shield_absorbed and energy>_shield_energy:
  _shield_until=now+VISIBLE_SECONDS
  _shield_copy="护盾已抵消 %.1f HP"%absorbed if absorbed>=.05 else "护盾已抵消少量撞击"
 _shield_elapsed=now;_shield_absorbed=absorbed;_shield_energy=energy
 return _shield_copy if now<=_shield_until else ""

func update(data: Dictionary, limit: int = 2) -> Array[Dictionary]:
 var now:float=_number(data.get("elapsed"),_elapsed)
 # The two observers own independent clocks; a shield-first observation may
 # already have established this rewound baseline. Explicit reset clears both.
 if now<_elapsed:_elapsed=0.0;_untimed_seen.clear()
 _elapsed=now
 var source:Variant=data.get("events",[])
 if source is String:source=[source]
 if not source is Array:return []
 var recent:Array[Dictionary]=[]
 var unresolved:Array[Dictionary]=[]
 for raw in source.slice(maxi(0,source.size()-MAX_EVENTS)):
  if not raw is String or raw.is_empty():continue
  var presented:String=display_event(raw,str(data.get("control_version","")))
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

func update_free(data:Dictionary,limit:int=1) -> Array[Dictionary]:
 # The one-line free-flight HUD may retain a short split acknowledgement next
 # to the actual collision. Never replace an event or change update's contract.
 var items:Array[Dictionary]=update(data,limit)
 if str(data.get("control_version","")) not in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] or items.size()!=1:return items
 if str(data.get("flight_status","")) in ["success","failed"] or str(data.get("status","")) in ["success","failed"] or str(data.get("arrival_state",""))=="received":return items
 if data.get("delivered") is bool and data.delivered:return items
 var navigation:Variant=data.get("destination_navigation")
 if navigation is Dictionary and str(navigation.get("status","")) in ["success","failed"]:return items
 if not _is_zero_display_collision(str(items[0].text)):return items
 var source:Variant=data.get("events",[])
 if not source is Array:return items
 var recent:Array=source.slice(maxi(0,source.size()-MAX_EVENTS))
 var collisions:int=0
 for index in range(recent.size()-1,-1,-1):
  var raw:Variant=recent[index]
  if not raw is String or raw.is_empty():continue
  var parsed:Dictionary=_parse(raw)
  var at:float=parsed.at if float(parsed.at)>=0.0 else float(_untimed_seen.get(raw,-1.0))
  if at<0.0 or at>_elapsed+.051:return items
  if _is_zero_display_collision(parsed.message):
   if collisions==0 and display_event(raw,"pilot-free-v2")!=str(items[0].source):return items
   collisions+=1
   continue
  # Source order is authoritative: the success emitter rounds to 0.1 s while
  # incident emitters keep 0.0001 s. A following incident can read slightly earlier.
  if collisions>0 and parsed.message==SPLITTER_SUCCESS_COPY and _elapsed-at<=VISIBLE_SECONDS:items[0]["short_success"]="模块已分裂"
  # Only this uninterrupted, authored tail qualifies. Any other event, including
  # a warning or nonzero/overload/attack incident, keeps the original receipt.
  return items
 return items

func _is_zero_display_collision(message:String) -> bool:
 var prefix:String="首次受损：" if message.begins_with("首次受损：") else "受损："
 if not message.begins_with(prefix) or not message.ends_with(" · 碰撞 · 0.00 HP。"):return false
 var part:PackedStringArray=message.trim_prefix(prefix).trim_suffix(" · 碰撞 · 0.00 HP。").rsplit(" #",true,1)
 if part.size()!=2 or not part[1].is_valid_int() or int(part[1])<0 or str(int(part[1]))!=part[1]:return false
 if part[0]=="货物":return true
 for spec in DisplayParts.catalog().values():
  if part[0]==str(spec.get("name","")):return true
 return false

static func display_event(raw:String,control_version:String) -> String:
 # Display-only translation: replay events and Main's player_event comparisons
 # must retain their existing bytes/semantics. Match only the authored emitter.
 var presented:String=player_event(raw,control_version)
 var message:String=presented;var envelope:String=""
 var separator:int=presented.find("s  ")
 if separator>0:
  var token:String=presented.left(separator)
  if token.is_valid_float() and is_finite(token.to_float()) and token.to_float()>=0.0:
   envelope=presented.left(separator+3);message=presented.substr(separator+3)
 # The raw incident emitter means first per (part ID, source), not per flight.
 # Translate only that structured event; Main's first-incident diagnosis differs.
 if message.begins_with("首次受损：") and message.ends_with(" HP。"):
  var fields:PackedStringArray=message.trim_prefix("首次受损：").trim_suffix(" HP。").split(" · ")
  if fields.size()==3 and fields[1] in ["碰撞","过载","攻击"]:
   var part_fields:PackedStringArray=fields[0].rsplit(" #",true,1)
   if part_fields.size()==2 and not part_fields[0].is_empty() and part_fields[1].is_valid_int() and int(part_fields[1])>=0 and fields[2].is_valid_float() and is_finite(fields[2].to_float()) and fields[2].to_float()>=0.0:
    return envelope+"受损："+message.trim_prefix("首次受损：")
 var prefix:String="质量加速器发射 ";var suffix:String="，载体承受反冲。"
 if not message.begins_with(prefix) or not message.ends_with(suffix):return presented
 var kind:String=message.trim_prefix(prefix).trim_suffix(suffix)
 var catalog:Dictionary=DisplayParts.catalog()
 if kind!="cargo" and not catalog.has(kind):return presented
 var spec:Dictionary=DisplayParts.cargo_spec() if kind=="cargo" else catalog[kind]
 return envelope+"%s已发射「%s」，飞船受到反冲。"%[catalog.accelerator.name,spec.name]

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
