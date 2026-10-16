extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
var hud
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for unused in 4:await process_frame
func copy_text() -> String:
 var result:String=""
 for child in hud.content.find_children("*","Control",true,false):
  if child.is_visible_in_tree() and (child is Label or child is Button):result+=child.text+"\n"
 return result
func button(prefix:String) -> Button:
 for child in hud.content.find_children("*","Button",true,false):
  if child.text.begins_with(prefix):return child
 return null
func run() -> void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud)
 var admin:String="043.7s  自动整备：回收 3 件，补齐 9 件；耗用与遗失不重复计费。"
 var report:Dictionary={"success":false,"trial":false,"elapsed":43.7,"integrity":100,"profit":-471,"cause":admin,"events":["043.7s  货物偏离收货区，委托失败。",admin],"income":0,"energy":201,"lost":270,"restored":true}
 var original:PackedByteArray=var_to_bytes(report)
 hud.render({"mode":"report","report":report,"settings":{"reduced_motion":true}});await settle()
 var shown:String=copy_text()
 check(shown.contains("飞出了这单的收货范围。") and shown.contains("亏了 ¥471"),"real terminal reason replaces final repair bookkeeping")
 check(not shown.contains("自动整备") and not shown.contains("不重复计费") and not shown.contains("100%") and not shown.contains("43.7"),"default result removes technical metrics and administrative prose")
 button("查看 · 收支明细").pressed.emit();await settle()
 check(copy_text().contains("43.7") and copy_text().contains("100%") and copy_text().contains("-201") and copy_text().contains("-270"),"actual legacy charges and flight metrics remain in optional receipt")
 check(var_to_bytes(report)==original,"copy repair leaves raw report evidence intact")
 for pair in [["货舱可用能量耗尽，委托失败。","电量耗尽，没能送达。"],["部分货物损毁，委托失败。","货物损毁，配送失败。"],["抵达速度过高，收货平台拒收。","进站太快，收件台没能接住。"],["货物未全部抵达，委托超时。","超时了，货物还没送到。"],["操作员中止本次航行。","你结束了本次飞行。"]]:
  check(hud._report_failure_copy({"cause":admin,"events":["023.4s  "+pair[0],admin]})==pair[1],"causal report: "+pair[0])
 check(hud._report_failure_copy({"cause":admin,"events":["单个电池耗尽。",admin]}).begins_with("这趟没能送达"),"nonterminal battery event is not invented as failure cause")
 check(hud._brief_flight_event("救援回收：3 件存活模块已带回，仍按实际耗能和损坏结算。").is_empty(),"live flight receipt omits administrative rescue text")
 check(hud._brief_flight_event("受损：横梁 #3 · 结构过载 · 2.0 HP。")=="结构受力过大，零件受损。","live damage notice retains real safety warning without solver numbers")
 check(hud._report_failure_copy({"cause":"首次受损：2秒", "events":[admin]}).begins_with("这趟没能送达"),"nonfatal first hit is not presented as terminal reason")
 report={"success":false,"trial":false,"control_version":"pilot-free-v1","economy_policy":"free-flight-economy-v1","income":0,"energy":201,"ammo":0,"repairs":0,"lost":270,"actual_costs":471,"insurance_coverage":446,"charged_costs":25,"profit":-25,"events":["货舱可用能量耗尽，委托失败。",admin],"elapsed":44}
 hud.render({"mode":"report","report":report,"settings":{"reduced_motion":true}});await settle();shown=copy_text()
 check(shown.contains("亏了 ¥25") and shown.contains("驿站承担 ¥446 · 你付 ¥25"),"insured result shows real personal debit and actual subsidy")
 button("查看 · 收支明细").pressed.emit();await settle()
 check(copy_text().contains("+446") and copy_text().contains("-201") and copy_text().contains("-270"),"insurance is an explicit positive receipt item, not erased original costs")
 var order:Dictionary={"name":"货站 → 屋顶收件台","destination_name":"屋顶收件台","distance":380.0,"contract_id":"insured-A","control_version":"pilot-free-v1","economy_policy":"free-flight-economy-v1","reward":220,"cargo":"包裹"}
 hud.render({"mode":"hub","activeorder":order,"control_version":"pilot-free-v1","settings":{"reduced_motion":true}});hud._act("dispatch");await settle();shown=copy_text()
 check(shown.contains("最高运费 ¥220") and shown.contains("送达最多自付 ¥30，失败最多 ¥25"),"new-policy dispatch discloses bounded charge and variable reward")
 check(not shown.contains("向上取整") and not shown.contains("/ J"),"insurance dispatch avoids unnecessary tariff math")
 hud._dismiss_dispatch();hud.render({"mode":"supply","phase":"day","settings":{"reduced_motion":true}});await settle();shown=copy_text()
 check(shown.contains("打烊后，可以补买零件。") and button("打烊")!=null,"closing page has one sentence and clear next action")
 check(not shown.contains("白天继续接单") and not shown.contains("未接受的委托可以婉拒"),"closing removes redundant rules")
 hud.render({"mode":"help","control_version":"pilot-free-v1","activeorder":order,"settings":{"reduced_motion":true}});await settle();shown=copy_text()
 check(shown.contains("WASD") and shown.contains("松开刹车") and not shown.contains("不改变声望") and not shown.contains("信号，逻辑门组合条件"),"help starts with actual controls rather than design prose")
 button("查看 · 设备说明").pressed.emit();await settle()
 check(copy_text().contains("空转也耗电") and copy_text().contains("不能免除结构过载"),"optional equipment help preserves real safety limitations")
 hud.queue_free();await settle();print("CONCISE_RESULTS_COPY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
