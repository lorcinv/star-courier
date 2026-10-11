extends SceneTree
const Receipt=preload("res://scripts/flight_receipt.gd")
var passed:int=0
var failed:int=0

func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)

func text(items:Array[Dictionary]) -> String:
 var lines:Array[String]=[]
 for item in items:lines.append(item.text)
 return "\n".join(lines)

func _initialize() -> void:
 var receipt=Receipt.new()
 var startup:Array=["000.0s  发射：8 个模块，质量 9.4 kg。","000.0s  发射台完成压缩供能，释放 36.1 N·s 冲量。"]
 var original:PackedByteArray=var_to_bytes(startup)
 for elapsed in [0.0,.7,1.35,40.0,500.0]:
  check(receipt.update({"elapsed":elapsed,"events":startup}).is_empty(),"known startup explanations never appear at "+str(elapsed))
 check(var_to_bytes(startup)==original,"source logs remain byte-for-byte identical")
 check(receipt.update({"elapsed":40.0,"events":["040.0s  自动整备：回收 8 件，补齐 0 件；耗用与遗失不重复计费。"]}).is_empty(),"flight receipt omits settlement bookkeeping")
 var delivered_events:Array=["050.0s  货箱 1 已由平台接收。","050.0s  全部货物自动投递成功：完整度 93%。"]
 var delivered_before:PackedByteArray=var_to_bytes(delivered_events)
 check(receipt.update({"elapsed":50.0,"events":delivered_events,"delivered":true}).is_empty(),"confirmed screen receipt replaces old autonomous solver delivery bookkeeping")
 check(var_to_bytes(delivered_events)==delivered_before,"delivery projection never edits frozen source logs")
 for value in [false,"true",1,null]:
  check(not receipt.update({"elapsed":50.0,"events":delivered_events,"delivered":value}).is_empty(),"only actual boolean delivery can replace source feedback: "+str(value))
 check(text(receipt.update({"elapsed":50.0,"delivered":true,"events":["050.0s  货箱接收失败，需重试。"]})).contains("接收失败"),"nearby failure text cannot be suppressed as successful bookkeeping")
 var warnings:Array=[
  "没有货物，发射已取消。", "位移失败：目标位置无法容纳整个组件。",
  "弹簧仍被其他连接锁住，未释放储能。", "加速器能量不足，弹丸保留。",
  "已达到 192 个动态模块的安全上限，本次分裂未执行。", "分裂拒绝：货物与分裂器不能复制。",
  "爆破核心引爆：冲击波同时影响友方与敌方。", "首次受损：货物 #1 · collision · 7.00 HP。",
  "推进喷口 损坏脱落。", "连接 1 ↔ 2 已断开。", "部分货物损毁，委托失败。",
  "货箱 1 已由平台接收。", "抵达速度过高，收货平台拒收。", "货物偏离收货区，委托失败。",
  "全部货物自动投递成功：完整度 93%。", "货物未全部抵达，委托超时。",
  "发射台组件缺少结构梁支撑，不能施加发射力。", "发射台过载：发射力超过结构梁承载。",
  "起飞取消：飞行器整体出生空间或前方安全距离不足。", "飞行状态超出有限数值范围，安全结束本次试飞。",
  "极限试飞取消：蓝图超过 192 个模块的安全上限。", "未进入虫洞：请对准洞口，或缩小飞船轮廓。",
  "出口被挡住了，本次无法通行。", "驿站通行电量不足，本次无法过洞。",
  "错过了虫洞，未能到达苔光驿站。", "虫洞航线协议不匹配。", "操作员中止本次航行。",
  "发射：故障，质量超限。", "发射台完成压缩供能，释放失败。", "自动整备：回收失败，需重试。",
  "新版本未识别的实际故障：请重试。"
 ]
 for warning in warnings:
  receipt.reset()
  check(text(receipt.update({"elapsed":10.0,"events":["010.0s  "+warning]}))==warning,"meaningful and unknown event preserved: "+warning)
 receipt.reset()
 var live:Dictionary={"elapsed":10.0,"events":["010.0s  推进喷口 损坏脱落。"]}
 check(text(receipt.update(live)).contains("损坏脱落"),"fresh damage shown without timestamp noise")
 live.elapsed=15.0;live.paused=true
 for i in 1000:receipt.update(live)
 check(text(receipt.update(live)).contains("损坏脱落"),"paused repeat does not spend simulation-time lifetime")
 live.elapsed=16.01;live.paused=false
 check(receipt.update(live).is_empty(),"damage receipt expires after six active simulation seconds")
 for i in 1000:receipt.update(live)
 check(receipt.update(live).is_empty(),"unchanged full log cannot rejuvenate old receipt")
 receipt.reset();live.elapsed=40.0
 check(receipt.update(live).is_empty(),"restored snapshot does not replay stale timestamped damage")
 live.events.append("038.0000s  首次受损：货物 #1 · collision · 7.00 HP。")
 check(text(receipt.update(live)).contains("7.00 HP"),"restored snapshot retains still-recent precise-time damage")
 receipt.reset();live={"elapsed":7.0,"events":["操作员中止本次航行。"]}
 check(not receipt.update(live).is_empty(),"untimed controller abort is visible")
 live.elapsed=14.0;check(receipt.update(live).is_empty(),"untimed event is first-seen aged")
 live.elapsed=0.0;check(not receipt.update(live).is_empty(),"elapsed rewind resets untimed ownership for retry")
 live.elapsed=7.0;check(receipt.update(live).is_empty(),"retry does not create immortal receipt")
 receipt.reset();check(not receipt.update(live).is_empty(),"explicit new-flight reset clears receipt ownership")
 for reason in Receipt.PORTAL_DENIALS:
  receipt.reset()
  var denied:Dictionary={"elapsed":50.0,"control_version":"pilot-v4-wormhole","wormhole_phase":"space","wormhole_last_denial":reason,"events":["020.0s  "+str(Receipt.PORTAL_DENIALS[reason])]}
  check(text(receipt.update(denied))==Receipt.PORTAL_DENIALS[reason],"unresolved real portal denial remains actionable: "+reason)
  denied.wormhole_phase="otherworld";check(receipt.update(denied).is_empty(),"successful cargo passage releases old denial: "+reason)
  denied.wormhole_phase="space";denied.control_version="pilot-v3";check(receipt.update(denied).is_empty(),"legacy protocol cannot pin v4 telemetry: "+reason)
 receipt.reset()
 var repeated_denial:Dictionary={"elapsed":50.0,"control_version":"pilot-v4-wormhole","wormhole_phase":"space","wormhole_last_denial":"exit_blocked","events":["020.0s  出口被挡住了，本次无法通行。","021.0s  出口被挡住了，本次无法通行。","050.0s  部分货物损毁，委托失败。"]}
 var priority:Array[Dictionary]=receipt.update(repeated_denial)
 check(priority.size()==2 and priority.back().text=="部分货物损毁，委托失败。","current failure takes newest visual slot ahead of one deduplicated old portal denial")
 receipt.reset()
 var many:Array=[]
 for i in 2000:
  many.append("实际故障 "+str(i));if many.size()>100:many.pop_front()
  receipt.update({"elapsed":float(i),"events":many})
 check(receipt._untimed_seen.size()<=100,"long flight receipt memory is bounded to the source ring budget")
 check(receipt.update({"elapsed":2000.0,"events":many}).size()<=2,"long flight draws at most two current receipts")
 check(receipt.update({"elapsed":2500.0,"events":many}).is_empty(),"long flight goes quiet after last current event expires")
 receipt.reset()
 check(text(receipt.update({"elapsed":0.0,"events":["000.0s  事件一","000.0s  事件二","000.0s  事件三"]},2))=="事件二\n事件三","latest events preserve source order and bounded count")
 check(receipt.update({"elapsed":0.0,"events":[]}).is_empty(),"empty source has no placeholder")
 for malformed in [null,{},3.0]:check(receipt.update({"events":malformed}).is_empty(),"malformed source does not invent a message")
 for elapsed in [null,"bad",NAN,INF]:check(text(receipt.update({"elapsed":elapsed,"events":["无法通行"]}))=="无法通行","unavailable elapsed preserves actual untimed warning")
 check(text(receipt.update({"elapsed":0.0,"events":["not-a-times  实际警告"]}))=="not-a-times  实际警告","malformed time envelope is preserved rather than discarded")
 var ref:WeakRef=weakref(receipt);receipt=null
 check(ref.get_ref()==null,"receipt has no self-retention")
 print("FLIGHT_RECEIPT passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
