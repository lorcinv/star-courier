extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
const Cue=preload("res://scripts/delivery_direction_cue.gd")
var passed:int=0
var failed:int=0
var actions:Array=[]
var hud
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for unused in 4:await process_frame
func copy_text(node:Node=null) -> String:
 var result:String=""
 for child in (hud.content if node==null else node).find_children("*","Control",true,false):
  if child.is_visible_in_tree() and (child is Label or child is Button):result+=child.text+"\n"
 return result
func button(prefix:String) -> Button:
 for child in hud.content.find_children("*","Button",true,false):
  if child.text.begins_with(prefix):return child
 return null
func order(version:String="pilot-free-v1") -> Dictionary:
 return {"name":"城市货站 → 屋顶收件台","destination_name":"屋顶收件台","client":"小禾","cargo":"包好的一把小勺","contract_id":"clarity-A","distance":380.0,"destination_y":-24.0,"weight":1.13,"reward":170,"required":85,"deadline":40,"time_limit":60,"delivery_radius":7,"max_delivery_speed":24,"control_version":version,"story":"小勺已经包好了。","risk":"小心沿途障碍。"}
func data(version:String="pilot-free-v1") -> Dictionary:
 return {"mode":"contracts","contracts":[order(version)],"activeorder":{},"energy_tariff":.025,"settings":{"reduced_motion":true}}
func telemetry() -> Dictionary:
 return {"control_version":"pilot-free-v1","flight_status":"running","arrival_state":"en_route","energy_remaining":750.0,"energy_capacity":1000.0,"energy_fraction":.75,"elapsed":4.0,"events":[],"destination_navigation":{"cargo_screen":Vector2(220,350),"receiver_screen":Vector2(1800,120),"distance_m":380.0,"status":"running","charging":false}}
func run() -> void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud)
 hud.action_requested.connect(func(action:String,payload:Variant):actions.append([action,payload]))
 var state:Dictionary=data();hud.render(state);await settle()
 var shown:String=copy_text()
 check(shown.contains("小禾") and shown.contains("包好的一把小勺") and shown.contains("送到屋顶收件台") and shown.contains("运费 ¥170"),"order foreground has who, cargo, destination and reward")
 check(not shown.contains("380") and not shown.contains("完整度") and not shown.contains("3.4") and not shown.contains("40 s"),"default order has no technical wall")
 button("查看 · 委托详情").pressed.emit();await settle()
 check(copy_text().contains("380") and copy_text().contains("小心沿途障碍"),"details keep route information and warnings available")
 button("收起 · 委托详情").pressed.emit();await settle()
 check(not copy_text().contains("380"),"details close without rebuilding gameplay state")
 button("接下这单").pressed.emit()
 check(actions==[["accept_contract","clarity-A"]],"accept preserves the original action and contract payload")
 actions.clear();state=data("pilot-v3");state.activeorder=order("pilot-v3");state.mode="hub";state.has_accepted_contract=true;hud.render(state);hud._act("dispatch");await settle()
 shown=copy_text()
 check(hud.dispatch_confirmation_open and root.gui_get_focus_owner()==button("再检查一下"),"dispatch starts on safe cancel")
 check(shown.contains("失败也会扣除本次消耗") and not shown.contains("¥0.025") and not shown.contains("投递半径"),"formal-delivery risk is visible; formula is optional")
 button("查看 · 费用与收件要求").pressed.emit();await settle()
 shown=copy_text()
 check(shown.contains("¥0.025") and shown.contains("向上取整") and shown.contains("最迟 60 s") and shown.contains("速度不超过 24 m/s"),"legacy exact cost and receipt limits remain accessible")
 button("再检查一下").pressed.emit();await settle()
 check(not hud.dispatch_confirmation_open and actions.is_empty(),"cancel does not launch")
 hud._act("dispatch");await settle();button("出发配送").pressed.emit()
 check(actions==[["dispatch",null]],"confirm emits exactly one unchanged dispatch action")
 actions.clear();state=data();state.mode="flight";state.activeorder=order();state.control_version="pilot-free-v1";state.flight=telemetry();var before:PackedByteArray=var_to_bytes(state.activeorder)
 hud.render(state);await settle();shown=copy_text()
 check(hud.flight_labels.destination.text=="送到屋顶收件台" and hud.flight_labels.status.text=="朝箭头方向飞","free flight has one destination goal and one action")
 check(hud.flight_labels.energy.text=="电量 75%" and hud._energy_bar.value==75,"energy uses actual connected-energy telemetry")
 check(not shown.contains("航线进度") and not shown.contains("奖励") and not shown.contains("门高") and not shown.contains("完整度"),"free flight has no legacy route deadline telemetry wall")
 check(hud._destination_cue.visible,"valid actual projected receiver shows direction signpost")
 var live:Dictionary=telemetry();live.arrival_state="slow_down";hud.update_flight(live)
 check(hud.flight_labels.status.text=="松开方向键，减速收件","too-fast receiver approach gives the actual braking action")
 live=telemetry();live.energy_remaining=190.0;live.energy_fraction=.19;hud.update_flight(live)
 check(hud.flight_labels.energy_warning.text=="电量不足，尽快送达","low connected battery produces readable warning")
 live=telemetry();live.paused=true;hud.update_flight(live)
 check(hud.flight_labels.status.text=="已暂停" and button("继续")!=null,"pause stays truthful without changing inputs")
 live=telemetry();live.flight_status="success";live.arrival_state="received";live.destination_navigation.status="success";hud.update_flight(live)
 check(hud.flight_labels.status.text=="货物已签收" and not hud._destination_cue.visible,"only actual receipt retires arrow and announces arrival")
 live=telemetry();live.energy_remaining=NAN;live.energy_capacity=NAN;live.energy_fraction=NAN;hud.update_flight(live)
 check(hud.flight_labels.energy.text=="电量未知" and not hud._energy_bar.visible,"missing energy is never fabricated")
 check(var_to_bytes(state.activeorder)==before and actions.is_empty(),"display updates do not mutate saved route or emit gameplay actions")
 var safe:=Rect2(40,140,1200,400)
 var cue:Dictionary=Cue.layout(Vector2(220,350),Vector2(1800,120),safe)
 check(absf(cue.bearing.cross((Vector2(1800,120)-Vector2(220,350)).normalized()))<.00001,"arrow uses actual two-dimensional receiver bearing")
 check(cue.point.x<=safe.end.x and cue.point.y>=safe.position.y,"offscreen signpost is bounded to visible playfield")
 cue=Cue.layout(Vector2(220,350),Vector2(100,500),safe)
 check(cue.bearing.x<0 and cue.bearing.y>0 and cue.onscreen,"overshoot points back to real receiver instead of forward route")
 check(Cue.layout(Vector2(NAN,0),Vector2(1,1),safe).is_empty(),"invalid camera projection cannot fabricate navigation")
 hud.queue_free();await settle();print("FIRST_DELIVERY_CLARITY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
