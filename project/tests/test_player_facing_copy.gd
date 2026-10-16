extends SceneTree
## HUD copy contract only. Real controls, warnings and receipts remain intact;
## no production saves, world animation or native OS input are exercised here.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts.gd")
const EXPECTED_CHECKS=31
const REMOVED_COPY=["TEST /", "ON AIR /", "LAUNCH SEQUENCE", "TRANSFER", "CHARGE", "IGNITION", "RELEASE", "准备接手驾驶", "找到下一次改进", "关卡高度", "航线提示待命", "碰撞数据待命", "尚无碰撞吸收", "档位未知", "实推", "请求", "不随帧率变化", "像素网格保持不变"]
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]

func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 6:await process_frame
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
 await process_frame
func text_content(from:Node=null) -> String:
 var result:String=""
 for node in (hud.content if from==null else from).find_children("*","Control",true,false):
  if node.is_visible_in_tree() and (node is Label or node is Button):result+=node.text+"\n"
 return result
func clean_copy() -> bool:
 var copy:=text_content()
 for phrase in REMOVED_COPY:
  if copy.contains(phrase):return false
 return true
func button(text:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==text:return node
 return null
func fixture() -> Dictionary:
 var catalog:=Parts.catalog();var inventory:={}
 for type in catalog:catalog[type].type=type;catalog[type].available=4;inventory[type]=4
 return {"mode":"hub","day":2,"credits":358,"reputation":1,"phase":"morning","has_accepted_contract":true,"activeorder":{"name":"晨星轨道站","cargo":"耐寒种子","distance":520,"reward":165,"weight":1,"required":85,"deadline":48,"time_limit":70,"delivery_radius":5,"max_delivery_speed":24,"contract_id":"D2-A"},"catalog":catalog,"inventory":inventory,"chosen_type":"beam","assembly_mode":"craft","parts":[{"id":1,"type":"battery"}],"ship_stats":{"parts":8,"mass":9.4,"energy":6000},"control_version":"pilot-v3","energy_tariff":.025,"cancel_warning":"退回已接委托会失去 1 点声望；这份委托今天不会重新出现。","settings":{"reduced_motion":true}}
func telemetry() -> Dictionary:
 return {"speed":21.8,"altitude":73,"target_altitude":150,"flight_phase":"climb","next_gate_index":1,"next_gate_time":2.5,"next_gate_direction":-1,"next_gate_altitude":94,"energy_remaining":3720,"battery_capacity":6000,"thrust_actual":39,"thrust_requested":56,"overdrive":true,"impact_absorbed":0,"impact_shield_energy":0,"pilot_active":false,"distance":208,"total_distance":520,"elapsed":10.5,"integrity":.92,"events":[]}
func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])
func run() -> void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action)
 var data:=fixture();hud.render(data);await settle()
 check(clean_copy() and not hud.is_blocking_modal(),"hub starts without developer labels or a new modal")
 check(text_content().contains("358") and text_content().contains("晨星轨道站") and text_content().contains("完整度 ≥ 85%"),"balance, current destination and contract integrity remain visible")
 data.mode="workshop";hud.render(data);await settle()
 check(clean_copy() and button("试飞 · 免费")!=null and button("发射配送  ↗")!=null,"workshop retains trial and dispatch controls without extra commentary")
 check(text_content().contains("中键平移") and text_content().contains("滚轮缩放") and text_content().contains("F 看全"),"compact assembly controls remain discoverable")
 data.ship_stats.warning="已保留 2 个旧方案格。移回开放区，或收工后扩建。";hud.render(data);await settle()
 check(text_content().contains(data.ship_stats.warning),"actionable old-blueprint warning is not hidden by copy cleanup")
 data.mode="flight";data.trial=true;data.flight=telemetry();data.flight.charging=true;data.flight.phase="发射台蓄能中";hud.render(data);hud.update_launch(.3,"charge");await settle()
 check(clean_copy() and text_content().contains("免费试飞"),"trial is clear without test or protocol labels")
 check(hud._launch_layer.find_children("*","Label",true,false).size()==1 and hud._launch_title.text=="蓄能中","launch shows one short status without stage subtitles")
 check(hud._launch_layer.mouse_filter==Control.MOUSE_FILTER_IGNORE and not hud.is_blocking_modal(),"short launch status does not capture input or become a modal")
 check(hud.flight_labels.hint.text.is_empty() and not hud.content.get_node("FlightEventReceipt").visible,"charging does not show idle coaching or an empty receipt panel")
 for pair in [["ignition","点火！"],["release","出发！  ↗"]]:
  hud.update_launch(.9,pair[0]);await settle()
  check(hud._launch_title.text==pair[1] and clean_copy(),"short launch caption: "+pair[0])
 hud.update_launch(.9,"internal_phase_name");await settle()
 check(hud._launch_title.text.is_empty() and not text_content().contains("internal_phase_name"),"unrecognized internal phase names cannot leak into the HUD")
 hud.update_launch(1,"done");await settle();hud.update_flight(telemetry())
 check(hud.flight_labels.thrust.text=="全功率 · 推力 39.0 N","flight shows actual thrust without an algorithm request column")
 check(hud.flight_labels.energy.text=="电量 3.72 kJ / 6.00 kJ" and hud.flight_labels.altitude.text=="高度 73 / 150 m","actual charge, capacity and altitude remain legible")
 check(hud.flight_labels.gate.text=="↑ 向上 · 2.5 s 后过门" and hud.flight_labels.gate_detail.text=="第 2 门 · 门高 94 m","real obstacle direction and countdown remain visible")
 check(hud.flight_labels.impact.text.is_empty() and not hud.content.get_node("FlightEventReceipt").visible,"no unused shield or event waiting messages appear")
 check(text_content().contains("W / S") and text_content().contains("Shift  全功率") and text_content().contains("Space  触发回路") and button("暂停  [Esc / P]")!=null,"flight controls remain visible")
 var live:=telemetry();live.events=["推进喷口 损坏脱落。"];live.impact_absorbed=13;live.impact_shield_energy=19.5;hud.update_flight(live)
 check(hud.content.get_node("FlightEventReceipt").visible and hud.flight_labels.events.text.contains("损坏脱落"),"actual damage restores the flight event receipt")
 check(hud.flight_labels.impact.text.contains("13.0 HP") and hud.flight_labels.impact.text.contains("20 J"),"funded shield absorption still reports damage and energy")
 live.paused=true;hud.update_flight(live)
 check(hud.flight_labels.status.text=="已暂停" and button("继续  [Esc / P]")!=null and actions.is_empty(),"pausing changes only copy and never emits a gameplay action")
 hud.update_flight({})
 check(hud.flight_labels.gate.text.is_empty() and hud.flight_labels.thrust.text=="推力 — N" and hud.flight_labels.energy.text=="电量 — / —","missing telemetry remains unknown without waiting-state chatter")
 data.mode="workshop";hud.render(data);await settle();hud._act("dispatch");await settle()
 var dispatch_copy:=text_content()
 check(hud.dispatch_confirmation_open and root.gui_get_focus_owner()==button("再检查一下") and actions.is_empty(),"dispatch still opens on the safe cancel action")
 check(dispatch_copy.contains("基础运费") and dispatch_copy.contains("时限") and dispatch_copy.contains("完整度 ≥ 85%") and dispatch_copy.contains("到达速度 ≤ 24 m/s"),"dispatch retains payout and delivery constraints")
 check(dispatch_copy.contains("能源 ¥0.025 / J") and dispatch_copy.contains("向上取整") and dispatch_copy.contains("失败也会扣除实际费用") and dispatch_copy.contains("自动补件与维修"),"dispatch retains exact tariff, rounding, failure charges and automatic repairs")
 hud._dismiss_dispatch();await settle();hud.settings_open=true;hud.render(data);await settle()
 check(clean_copy() and button("减少镜头动态")!=null and button("飞行背景动态模糊")!=null,"settings retain accessibility controls without rendering implementation notes")
 var quality:Control;var density:Control
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)=="settings:quality":quality=node
  elif hud._view_key(node)=="settings:pixel_density":density=node
 check(quality==null and density!=null and density.tooltip_text.contains("按窗口大小"),"pure 2D settings expose useful pixel density but no ineffective legacy shadow-quality control")
 hud.settings_open=false;hud.render(data);await settle();hud.toast("保存失败，原存档已保留。请重试。","error")
 check(hud.toast_panel.visible and hud.toast_label.text.contains("保存失败") and hud.toast_label.text.contains("请重试"),"recovery errors and the retry instruction remain visible")
 data.mode="help";hud.render(data);await settle()
 check(text_content().contains("空转也耗电") and text_content().contains("吸收部分碰撞伤害") and text_content().contains("结构过载"),"on-demand handbook retains drill and shield limitations")
 check(clean_copy(),"on-demand handbook avoids implementation language while preserving useful rules")
 var copy_covered:=true
 for c in "高度推力蓄能中点火出发松开后不会立即停下自动清晰按窗口大小调整像素密度":copy_covered=copy_covered and hud.root.theme.default_font.has_char(c.unicode_at(0))
 check(copy_covered,"all changed Chinese copy has font coverage")
 hud.queue_free();for i in 6:await process_frame
 check(get_processed_tweens().is_empty(),"copy-only rerenders and modal closures release all Tweens")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every copy assertion ran: expected %d, saw %d"%[EXPECTED_CHECKS,passed+failed])
 print("PLAYER_FACING_COPY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
