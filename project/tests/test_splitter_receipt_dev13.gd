extends SceneTree
const Receipt=preload("res://scripts/flight_receipt.gd")
const SPLIT:String="模块分裂：质量、储能、强度与耐久均分，未复制货物。"
const HIT:String="首次受损：分裂核 #1005 · 碰撞 · 0.00 HP。"
const SHOWN_HIT:String="受损：分裂核 #1005 · 碰撞 · 0.00 HP。"
var passed:int=0
var failed:int=0

func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)

func frame(events:Array,elapsed:float=2.0) -> Dictionary:
 return {"elapsed":elapsed,"control_version":"pilot-free-v2","events":events}

func has_success(items:Array[Dictionary]) -> bool:
 return items.size()==1 and items[0].get("short_success","")=="模块已分裂"

func plain(data:Dictionary,title:String,limit:int=1) -> void:
 var before:PackedByteArray=var_to_bytes(data)
 var original=Receipt.new();var extended=Receipt.new()
 var expected:Array[Dictionary]=original.update(data,limit)
 var actual:Array[Dictionary]=extended.update_free(data,limit)
 check(var_to_bytes(actual)==var_to_bytes(expected),title+" retains the exact original receipt")
 check(var_to_bytes(data)==before,title+" does not mutate input")

func _initialize() -> void:
 # Exact active-flight prefix from dev12 native evidence. Do not include the
 # later operator abort: the new prefix must never decorate that terminal event.
 var native:Array=[
  "000.0s  发射台弹射：起步 3.3 m/s，台上电芯消耗 60.0 J。",
  "000.0s  发射：9 个模块，质量 11.2 kg。",
  "001.9s  "+SPLIT,
  "001.8917s  首次受损：货物 #1 · 碰撞 · 0.00 HP。",
  "001.8917s  首次受损：推进喷口 #1006 · 碰撞 · 0.00 HP。",
  "001.8917s  首次受损：推进喷口 #4 · 碰撞 · 0.00 HP。",
  "001.9500s  "+HIT
 ]
 var data:Dictionary=frame(native)
 var before:PackedByteArray=var_to_bytes(data)
 var receipt=Receipt.new()
 var result:Array[Dictionary]=receipt.update_free(data)
 check(has_success(result),"native success survives all four rounded micro-collisions")
 check(result.size()==1 and result[0].text==SHOWN_HIT,"collision text is retained in the single slot")
 check(result[0].source=="001.9500s  "+SHOWN_HIT,"original displayed source is retained")
 check(result[0].keys().size()==3,"the sole addition is short_success metadata")
 check(not str(result[0].short_success).contains("无损"),"acknowledgement does not claim damage-free splitting")
 check(var_to_bytes(data)==before,"exact native data and event ring are byte-identical")
 var old:Array[Dictionary]=receipt.update(data,1)
 check(old.size()==1 and old[0]=={"text":SHOWN_HIT,"source":"001.9500s  "+SHOWN_HIT},"existing update remains collision-only even after extended update")
 for count in range(1,5):
  check(has_success(Receipt.new().update_free(frame(native.slice(0,3+count)))),"one through four native collisions: "+str(count))
 for limit in [2,3,99]:plain(data,"multi-slot caller "+str(limit),limit)
 plain(frame(["001.9s  "+SPLIT]),"unobscured split already has its own receipt")
 plain(frame(["001.9500s  "+HIT]),"collision without success")
 plain(frame(["001.9s  "+HIT,"001.9500s  "+SPLIT]),"success after collision is already latest")

 # The success ages from its own simulation timestamp, not from later contacts.
 data.elapsed=7.9
 check(has_success(receipt.update_free(data)),"six-second success boundary is inclusive")
 data.elapsed=7.901
 result=receipt.update_free(data)
 check(not has_success(result) and result.size()==1 and result[0].text==SHOWN_HIT,"expired success leaves still-current collision intact")
 for i in 20:check(not has_success(receipt.update_free(data)),"unchanged tail cannot rejuvenate expired success "+str(i))
 data.elapsed=7.951
 check(receipt.update_free(data).is_empty(),"collision expires on its own six-second boundary")
 data.elapsed=40.0
 check(receipt.update_free(data).is_empty(),"restored old timestamped tail remains quiet")
 receipt.reset();data.elapsed=2.0;data.paused=true
 for i in 1000:result=receipt.update_free(data)
 check(has_success(result),"paused renders do not spend simulation-time lifetime")
 data.paused=false;data.elapsed=7.901
 check(not has_success(receipt.update_free(data)),"unpausing uses the original success timestamp")
 data.elapsed=0.0
 result=receipt.update_free(data)
 check(not has_success(result) and result==Receipt.new().update(data,1),"rewound clock does not display future split or collision")
 data.events=["000.0s  "+SPLIT,"000.0000s  "+HIT]
 check(has_success(receipt.update_free(data)),"new flight after rewind can acknowledge a new split")
 receipt.reset()
 var untimed:Dictionary=frame([SPLIT,HIT],10.0)
 check(has_success(receipt.update_free(untimed)),"untimed pair uses existing first-seen ownership")
 untimed.elapsed=16.0
 check(has_success(receipt.update_free(untimed)),"untimed six-second boundary is inclusive")
 untimed.elapsed=16.001
 check(receipt.update_free(untimed).is_empty(),"untimed pair expires without renewal")
 untimed.elapsed=0.0
 check(has_success(receipt.update_free(untimed)),"rewind resets untimed first-seen ownership")
 untimed.elapsed=7.0
 check(receipt.update_free(untimed).is_empty(),"rewound untimed acknowledgement is not immortal")
 receipt.reset()
 check(has_success(receipt.update_free(untimed)),"explicit new-flight reset clears untimed ownership")

 for mode in ["","pilot-free-v1","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-free-v2-nearby"]:
  data=frame(native);data.control_version=mode
  plain(data,"other control mode "+mode)
 for terminal in ["success","failed"]:
  for field in ["flight_status","status"]:
   data=frame(native);data[field]=terminal
   plain(data,"terminal "+field+"="+terminal)
  data=frame(native);data.destination_navigation={"status":terminal}
  plain(data,"terminal navigation "+terminal)
 data=frame(native);data.arrival_state="received";plain(data,"received cargo")
 data=frame(native);data.delivered=true;plain(data,"delivered boolean")
 for nonterminal in [false,0,"true",null]:
  data=frame(native);data.delivered=nonterminal
  check(has_success(Receipt.new().update_free(data)),"non-boolean delivery cannot invent terminal state: "+str(nonterminal))

 var blockers:Array=[
  "首次受损：货物 #1 · 碰撞 · 0.01 HP。",
  "受损：推进喷口 #4 · 碰撞 · 7.00 HP。",
  "首次受损：货物 #1 · 过载 · 0.00 HP。",
  "首次受损：货物 #1 · 攻击 · 0.00 HP。",
  "首次受损：货物 #1 · collision · 0.00 HP。",
  "推进喷口 损坏脱落。",
  "部分货物损毁，委托失败。",
  "全部货物自动投递成功：完整度 93%。",
  "货物未全部抵达，委托超时。",
  "操作员中止本次航行。",
  "分裂拒绝：货物与分裂器不能复制。",
  "已达到 192 个动态模块的安全上限，本次分裂未执行。",
  "新版本未识别的实际警报：请重试。"
 ]
 for blocker in blockers:
  plain(frame(["001.9s  "+SPLIT,"001.9500s  "+blocker]),"latest meaningful event: "+blocker)
  plain(frame(["001.9s  "+SPLIT,"001.9400s  "+blocker,"001.9500s  "+HIT]),"intervening meaningful event: "+blocker)
 plain(frame(["001.9s  "+SPLIT,"001.9500s  "+HIT,"002.0s  自动整备：回收 14 件，补齐 0 件；耗用与遗失不重复计费。"]),"even filtered later settlement breaks active split tail")
 var complete_native:Array=native.duplicate(true)
 complete_native.append_array(["操作员中止本次航行。","002.7s  自动整备：回收 14 件，补齐 0 件；耗用与遗失不重复计费。","002.7s  救援回收：10 件存活模块已带回，仍按实际耗能和损坏结算。"])
 plain(frame(complete_native,2.7333333333333263),"exact native final report is unchanged")

 var approximate_hits:Array=[
  "首次受损：货物 #1 · 碰撞 · 0 HP。",
  "首次受损：货物 #1 · 碰撞 · 0.000 HP。",
  "首次受损：货物 #1 · 碰撞 · -0.00 HP。",
  "首次受损：货物 #1 · 碰撞 · +0.00 HP。",
  "首次受损：货物 #1 · 碰撞 · 0e0 HP。",
  "首次受损：货物 #1 · 碰撞 · NaN HP。",
  "首次受损：货物 #1 · 碰撞 · INF HP。",
  "首次受损：货物 #1 · 碰撞 · 0.00HP。",
  "首次受损：货物 #1 · 碰撞 · 0.00 HP",
  "首次受损：货物 #1 · 碰撞 · 0.00 HP。额外警报",
  "首次受损：货物 #01 · 碰撞 · 0.00 HP。",
  "首次受损：货物 #+1 · 碰撞 · 0.00 HP。",
  "首次受损：货物 #-1 · 碰撞 · 0.00 HP。",
  "首次受损：货物 #1.0 · 碰撞 · 0.00 HP。",
  "首次受损： #1 · 碰撞 · 0.00 HP。",
  "首次受损：未知零件 #1 · 碰撞 · 0.00 HP。",
  "首次受损：推进喷口假 #1 · 碰撞 · 0.00 HP。",
  "疑似首次受损：货物 #1 · 碰撞 · 0.00 HP。"
 ]
 for hit in approximate_hits:
  plain(frame(["001.9s  "+SPLIT,"001.9500s  "+hit]),"nearby collision grammar: "+hit)
  plain(frame(["001.9s  "+SPLIT,"001.9400s  "+hit,"001.9500s  "+HIT]),"nearby intervening grammar: "+hit)
 for split in [SPLIT+" "," "+SPLIT,SPLIT+"失败",SPLIT.replace("未复制货物","复制货物"),SPLIT.replace("模块分裂：","模块分裂失败："),SPLIT.trim_suffix("。")]:
  plain(frame(["001.9s  "+split,"001.9500s  "+HIT]),"nearby success grammar: "+split)
 for envelope in ["bad s  ","-1.0s  ","nans  ","001.9s ","001.9 s  "]:
  plain(frame([envelope+SPLIT,"001.9500s  "+HIT]),"malformed success timestamp "+envelope)
  plain(frame(["001.9s  "+SPLIT,envelope+HIT]),"malformed collision timestamp "+envelope)
 check(has_success(Receipt.new().update_free(frame(["001.9s  "+SPLIT,"001.9500s  "+SHOWN_HIT]))),"structured already-presented damage is supported")
 for spec in Receipt.DisplayParts.catalog().values():
  check(has_success(Receipt.new().update_free(frame(["001.9s  "+SPLIT,"001.9500s  首次受损：%s #4 · 碰撞 · 0.00 HP。"%spec.name]))),"exact authored part title "+str(spec.name))

 # Neither a forged oversized history nor first-seen ownership may exceed the
 # same 100-event ring that the unchanged receipt consumes.
 var hundred:Array=["001.9s  "+SPLIT]
 for i in 99:hundred.append("001.9500s  首次受损：推进喷口 #%d · 碰撞 · 0.00 HP。"%i)
 check(has_success(Receipt.new().update_free(frame(hundred))),"success at oldest included ring entry qualifies")
 hundred.append("001.9500s  "+HIT)
 plain(frame(hundred),"success beyond 100-entry cap is never recovered")
 var ring:Array=[];receipt.reset()
 for i in 250:
  ring.append("首次受损：推进喷口 #%d · 碰撞 · 0.00 HP。"%i)
  receipt.update_free(frame(ring,float(i)))
 check(receipt._untimed_seen.size()<=100,"extended update retains bounded untimed ownership")
 plain(frame([]),"empty source")
 for source in [null,{},3.0,HIT]:
  data=frame([]);data.events=source;plain(data,"non-array source "+str(source))
 for value in [null,"bad",NAN,INF]:
  data=frame([SPLIT,HIT]);data.elapsed=value
  check(has_success(Receipt.new().update_free(data)),"unavailable clock follows original fallback: "+str(value))
 plain(frame(["020.0s  "+SPLIT,"001.9500s  "+HIT]),"future-dated success cannot acknowledge")
 plain(frame(["001.9s  "+SPLIT,"020.0000s  "+HIT]),"future-dated collision cannot acknowledge")
 plain(frame(["000.0s  "+SPLIT,"006.1000s  "+HIT],6.1),"new collision cannot revive old split")
 print("SPLITTER_RECEIPT_DEV13 passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)
