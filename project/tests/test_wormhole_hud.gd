extends SceneTree
## HUD-only version, telemetry, geometry, receipt and modal contracts.
## Inputs below are synthetic. Headless bounds checks are not native gameplay QA.
const HUD=preload("res://scripts/game_hud.gd")
const VERSION="pilot-v4-wormhole"
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]

func _initialize() -> void:run.call_deferred()
func check(ok:bool,title:String) -> void:
 if ok:passed+=1;print("PASS ",title)
 else:failed+=1;push_error("FAIL "+title)
func settle() -> void:
 for i in 6:await process_frame
 if is_instance_valid(hud):
  for tween in hud._motion_tweens.values():
   if tween.is_valid():tween.custom_step(1.0)
 await process_frame
func button(text:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==text:return node
 return null
func control(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func modal() -> Control:
 for node in hud.content.get_children():
  if node.has_meta("modal_panel"):return node
 return null
func text_content() -> String:
 var result:String=""
 for label in hud.content.find_children("*","Label",true,false):result+=label.text+"\n"
 return result
func key(code:int) -> void:
 for down in [true,false]:
  var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event);await process_frame
 await settle()
func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])
func telemetry() -> Dictionary:
 return {"control_version":VERSION,"wormhole_phase":"space","flight_phase":"approach","speed":23.8,"altitude":150.0,"target_altitude":150.0,"lookahead_seconds":3.5,"next_gate_index":4,"next_gate_time":2.2,"next_gate_altitude":150.0,"next_gate_direction":0,"energy_remaining":3712.0,"battery_capacity":6000.0,"pilot_boost":true,"pilot_active":true,"thrust_actual":54.2,"overdrive":true,"distance":550.0,"total_distance":1240.0,"elapsed":24.0,"integrity":.92}
func fixture() -> Dictionary:
 return {"mode":"flight","control_version":VERSION,"has_accepted_contract":true,"activeorder":{"control_version":VERSION,"contract_id":"W-D1-A","name":"城市货站 → 晨星虫洞 → 苔光驿站","cargo":"苔光补给","weight":1.2,"distance":1240.0,"deadline":72,"time_limit":100,"pilot_altitude":150.0,"required":85,"reward":85,"delivery_radius":8.0,"max_delivery_speed":24.0,"destination_name":"苔光驿站","pilot_gates":[{"index":3,"x":450.0,"y":-150.0},{"index":4,"x":600.0,"y":-150.0,"wormhole_entry":true},{"index":5,"x":1140.0,"y":-146.0,"otherworld":true}],"wormhole_portal":{"entry":[600.0,-150.0],"exit":[1000.0,-150.0],"aperture_radius":13.0,"margin":.125}},"wormhole_preflight":{"ok":true,"estimated_j":136.4,"station_capacity_j":2000.0,"max_centered_body_diameter_m":25.75,"starting_body_diameter_m":7.42,"estimated_bodies":1,"fits_starting_outline":true},"flight":telemetry(),"settings":{"reduced_motion":true,"motion_blur":true}}
func report_fixture(trial:bool) -> Dictionary:
 var data:=fixture();data.mode="report";data.report={"control_version":VERSION,"trial":trial,"success":true,"elapsed":54.6,"integrity":96.0,"energy_j":1700.0,"wormhole_energy_j":136.4,"wormhole_transits":1,"wormhole_station_remaining":1863.6,"energy":43,"income":85,"profit":42,"estimated_profit":42,"ammo":0,"repairs":0,"lost":0};return data
func controls_fit(frame:Rect2) -> bool:
 for node in hud.content.find_children("*","Button",true,false):
  if node.is_visible_in_tree() and not frame.encloses(node.get_global_rect()):
   print("BOUND ",node.text," ",node.get_global_rect()," frame=",frame);return false
 return true
func cue_fits() -> bool:
 for item in [hud._ascent_cue,hud.flight_labels.energy.get_parent().get_parent()]:
  for label in item.find_children("*","Label",true,false):
   if not item.get_global_rect().encloses(label.get_global_rect()) or label.get_minimum_size().x>label.size.x+.1:return false
 return true

func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action);hud.set_art_frame(Rect2(0,40,1280,720))
 var data:=fixture();hud.render(data);await settle()
 check(hud._pilot_mode() and hud._ascent_mode() and hud._extreme_mode() and hud._wormhole_mode(),"explicit v4 selects pilot, ascent and mounted-output controls")
 check(button("1×")==null and button("2×")==null and button("4×")==null,"v4 exposes no autonomous rate controls")
 check(text_content().contains("Shift  全功率") and hud.flight_labels.thrust.text=="全功率 · 推力 54.2 N","v4 keeps funded thrust and full-power semantics")
 check(hud.flight_labels.status.text=="速度 23.8 m/s · 太空","space label comes from actual wormhole phase")
 check(hud.flight_labels.gate.text=="虫洞入口 · → 保持" and hud.flight_labels.gate_detail.text=="约 2.2 s · 门高 150 m","marked upcoming entrance has concise portal cue and approximate guidance")
 var live:=telemetry();live.next_gate_direction=-1;hud.update_flight(live)
 check(hud.flight_labels.gate.text=="虫洞入口 · ↑ 向上","portal cue preserves upward input guidance")
 live.next_gate_direction=1;hud.update_flight(live)
 check(hud.flight_labels.gate.text=="虫洞入口 · ↓ 向下","portal cue preserves downward input guidance")
 live.next_gate_time=9.0;hud.update_flight(live)
 check(hud.flight_labels.gate.get_theme_color("font_color")==HUD.TEAL and not text_content().contains("可见"),"distant timing stays quiet and makes no visibility promise")
 live=telemetry();live.wormhole_phase="ascent";live.distance=1200.0;hud.update_flight(live)
 check(hud.flight_labels.status.text.ends_with("升空"),"large x alone cannot fabricate space or otherworld")
 live.wormhole_phase="otherworld";live.distance=4.0;live.next_gate_index=5;hud.update_flight(live)
 check(hud.flight_labels.status.text.ends_with("异世界") and not hud.flight_labels.gate.text.contains("虫洞入口"),"actual otherworld telemetry wins even at synthetic small x")
 live.next_gate_index=4;hud.update_flight(live)
 check(not hud.flight_labels.gate.text.contains("虫洞入口"),"already-transited cargo never advertises the old portal entrance")
 live.next_gate_index=-1;live.next_gate_time=-1;live.flight_phase="city";hud.update_flight(live)
 check(hud.flight_labels.gate.text=="接近苔光驿站" and hud.flight_labels.gate_detail.text=="收件限速 24 m/s","otherworld approach names the actual destination and arrival speed")
 live.wormhole_phase="space";live.flight_phase="approach";hud.update_flight(live)
 check(hud.flight_labels.gate.text.is_empty(),"legacy approach phase cannot announce a pre-transit destination")
 for phase in ["", "unknown", {"bad":"phase"}]:
  live.wormhole_phase=phase;live.distance=1240;hud.update_flight(live)
  check(hud.flight_labels.status.text.ends_with("航行") and hud.flight_labels.gate.text.is_empty(),"missing or malformed phase remains unclaimed: "+str(phase))
 data=fixture();data.activeorder.destination_name="蓝霜收件塔";data.activeorder.pilot_gates=[{"index":84,"x":745.0,"y":-210.0,"wormhole_entry":true},{"index":17,"x":1320.0,"y":-210.0,"otherworld":true}];data.activeorder.wormhole_portal={"entry":[745.0,-210.0],"exit":[1200.0,-210.0],"aperture_radius":9.0,"margin":.2};data.flight.next_gate_index=84;data.flight.next_gate_altitude=210.0;hud.render(data);await settle()
 check(hud.flight_labels.gate.text.contains("虫洞入口") and hud.flight_labels.gate_detail.text.contains("210 m"),"saved custom portal coordinates and index are recognized without defaults")
 live=data.flight.duplicate();live.next_gate_index=4;hud.update_flight(live)
 check(not hud.flight_labels.gate.text.contains("虫洞入口"),"default index four is not a portal without the actual marker")
 live.wormhole_phase="otherworld";live.next_gate_index=-1;live.next_gate_time=-1;hud.update_flight(live)
 check(hud.flight_labels.gate.text=="接近蓝霜收件塔","saved custom destination survives the otherworld approach")
 for gates in [null, "bad", [null, 8, {"index":4,"wormhole_entry":"true"}, {"index":"4","wormhole_entry":true}], [{"index":4,"x":600.0,"y":-150.0}], [{"index":4,"wormhole_entry":false},{"index":4,"wormhole_entry":true}]]:
  data=fixture();data.activeorder.pilot_gates=gates;hud.render(data);await settle()
  check(not hud.flight_labels.gate.text.contains("虫洞入口"),"malformed or unmarked geometry cannot invent an entrance: "+str(gates))
 data=fixture();data.erase("control_version");hud.render(data);await settle()
 check(hud._wormhole_mode() and hud._extreme_mode(),"saved order-level v4 version is recognized")
 for version in ["pilot-v1","pilot-v2","pilot-v3", "pilot-v4", ""]:
  data=fixture();data.control_version=version;hud.render(data);await settle()
  check(not hud._wormhole_mode() and hud._pilot_mode()==(version in ["pilot-v1","pilot-v2","pilot-v3"]) and hud._ascent_mode()==(version in ["pilot-v2","pilot-v3"]) and hud._extreme_mode()==(version=="pilot-v3"),"legacy and unknown version gates stay explicit: "+version)
  check(not text_content().contains("虫洞入口") and not text_content().contains("异世界"),"v4 fields do not change older or unknown presentation: "+version)
 data=fixture();hud.state=data
 var quote:Array[String]=hud._wormhole_preflight_lines()
 check(quote.size()==2 and quote[0].contains("136.4 J") and quote[0].contains("2.00 kJ") and quote[0].contains("合并计入能耗") and quote[0].contains("分离后按实际计费"),"preflight shows finite station energy, one bill and split caveat in one paragraph")
 check(quote[1]=="净口径 25.75 m · 当前轮廓 7.42 m","preflight shows actual net aperture and starting outline")
 data.wormhole_preflight.max_centered_body_diameter_m=17.6;data.wormhole_preflight.starting_body_diameter_m=21.03;data.wormhole_preflight.fits_starting_outline=false;hud.state=data
 check(hud._wormhole_preflight_lines()[1]=="净口径 17.60 m · 当前轮廓 21.03 m · 轮廓偏大","custom saved aperture and overlarge starting geometry receive a factual warning")
 data.wormhole_preflight.estimated_j=2001.0;hud.state=data
 check(hud._wormhole_preflight_lines()[0].contains("储能不足"),"station capacity is finite and insufficient quotes are visible")
 for malformed in [null,"invalid",[],{}, {"ok":false}, {"ok":true,"estimated_j":"136.4","station_capacity_j":2000,"estimated_bodies":1}, {"ok":true,"estimated_j":NAN,"station_capacity_j":INF,"estimated_bodies":1,"max_centered_body_diameter_m":{},"starting_body_diameter_m":[]}, {"ok":"true","estimated_j":3,"station_capacity_j":100,"estimated_bodies":1}, {"ok":true,"estimated_j":3,"station_capacity_j":100,"estimated_bodies":1.5}]:
  hud.state.wormhole_preflight=malformed;quote=hud._wormhole_preflight_lines();var joined:String=" ".join(quote)
  check(quote.size()==2 and joined.contains("当前预估不可用") and not joined.to_lower().contains("nan") and not joined.to_lower().contains("inf"),"absent or malformed preflight stays safe and unknown: "+str(malformed))
 for trial in [true,false]:
  data=report_fixture(trial);hud.report_costs_open=true;hud.render(data);await settle()
  var text:=text_content()
  check(text.contains("其中虫洞通行 136 J · 1 个组件（已含在"+("本次耗能" if trial else "能源消耗")+"中）") and text.contains("驿站余能 1.86 kJ"),"station energy is an informational subtotal in "+("trial" if trial else "formal")+" report")
  check(text.contains("1700.0 J") if trial else text.count("能源消耗\n")==1 and text.count("¥ -43")==1,"combined energy is displayed or debited once in "+("trial" if trial else "formal")+" report")
  check(not text.contains("虫洞费用") and not text.contains("额外扣费"),"report adds no second wormhole financial row: "+str(trial))
 for patch in [{"wormhole_energy_j":NAN},{"wormhole_energy_j":1701.0},{"wormhole_transits":-1},{"wormhole_transits":1.5},{"wormhole_energy_j":"bad"},{"control_version":"pilot-v3"}]:
  data=report_fixture(false);data.report.merge(patch,true);hud.render(data);await settle()
  check(not text_content().contains("其中虫洞通行"),"malformed or legacy reports cannot claim a station subtotal: "+str(patch))
 for spec in [[Vector2i(1280,800),Rect2(0,40,1280,720),1],[Vector2i(1920,1080),Rect2(0,0,1920,1080),1],[Vector2i(3840,2160),Rect2(0,0,3840,2160),3]]:
  var extent:Vector2i=spec[0];var frame:Rect2=spec[1];root.size=extent;hud.set_art_frame(frame);data=fixture();hud.render(data);await settle()
  check(hud.root.scale==Vector2.ONE*spec[2] and frame.encloses(hud._ascent_cue.get_global_rect()) and controls_fit(frame) and cue_fits(),"v4 flight labels and controls fit physical viewport "+str(extent))
  live=telemetry();live.paused=true;hud.update_flight(live);await settle()
  check(button("继续  [Esc / P]")!=null and hud.flight_labels.status.text=="已暂停" and hud.flight_labels.gate_detail.text.begins_with("已暂停") and hud.flight_labels.gate.get_theme_color("font_color")==HUD.DIM and cue_fits(),"paused v4 cue and resume controls stay readable "+str(extent))
  hud.set_input_device(true);hud.update_flight(live);await settle()
  check(button("继续  [Menu]")!=null and hud.flight_labels.controls.text.contains("RB 全功率") and hud.flight_labels.pilot_signal.text.begins_with("A 回路") and controls_fit(frame),"gamepad captions and pause controls remain correct "+str(extent))
  hud.set_input_device(false);hud.update_flight(telemetry());hud.update_launch(.5,"charge");await settle()
  check(not hud._ascent_cue.visible,"launch ribbon suppresses portal cue "+str(extent))
  hud.update_launch(1,"done");await settle()
  check(hud._ascent_cue.visible,"completed launch releases portal cue "+str(extent))
  for trial in [true,false]:
   hud.render(report_fixture(trial));await settle()
   check(controls_fit(frame),"report actions stay in frame "+str(extent)+" trial="+str(trial))
  data=fixture();data.mode="hub";data.activeorder.name="城市货站 → 晨星虫洞 → 蓝霜深空特别收件塔";data.wormhole_preflight.starting_body_diameter_m=29.24;data.wormhole_preflight.fits_starting_outline=false;hud.render(data);await settle();hud._act("dispatch");await settle()
  check(hud.dispatch_confirmation_open and modal()!=null and frame.encloses(modal().get_global_rect()) and controls_fit(frame),"wormhole dispatch and fixed actions fit "+str(extent))
  check(root.gui_get_focus_owner()==control("dispatch:cancel") and not control("dispatch:confirm").disabled and text_content().contains("轮廓偏大"),"overlarge design is warned with safe cancel default, never arbitrarily banned "+str(extent))
  var tab_safe:=true
  for i in 8:await key(KEY_TAB);tab_safe=tab_safe and modal().is_ancestor_of(root.gui_get_focus_owner())
  check(tab_safe,"dispatch Tab remains trapped inside modal "+str(extent))
  control("dispatch:cancel").grab_focus();var count_before:int=hud.content.get_child_count()
  for i in 8:hud.render(hud.state)
  await settle()
  check(hud.content.get_child_count()==count_before and root.gui_get_focus_owner()==control("dispatch:cancel") and controls_fit(frame),"repeated modal rebuild retains safe focus and bounded nodes "+str(extent))
  actions.clear();await key(KEY_ENTER)
  check(not hud.dispatch_confirmation_open and actions.is_empty(),"Enter on rebuilt safe default dismisses without dispatch "+str(extent))
  for i in 3:hud._act("dispatch");await settle();await key(KEY_ESCAPE)
  check(not hud.dispatch_confirmation_open and actions.is_empty(),"repeated Escape cancels without emitting a launch "+str(extent))
  hud._act("dispatch");await settle();control("dispatch:confirm").pressed.emit();await settle()
  check(actions==[["dispatch",null]] and not hud.dispatch_confirmation_open,"explicit confirm emits exactly one normal dispatch "+str(extent))
 hud.queue_free();for i in 8:await process_frame
 check(get_processed_tweens().is_empty(),"v4 modal and flight teardown release all Tweens")
 print("WORMHOLE_HUD passed=%d failed=%d input=synthetic_headless"%[passed,failed]);quit(1 if failed else 0)
