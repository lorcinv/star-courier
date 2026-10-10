extends SceneTree
## pilot-v2 presentation fixture. Uses actual telemetry fields, never physics
## shortcuts. Optional --capture writes rendered HUD layouts, not gameplay QA.
const HUD=preload("res://scripts/game_hud.gd")
const EXPECTED_CHECKS=65
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
var background_clicks:int=0

func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 6:await process_frame
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
 await process_frame
func button(text:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==text:return node
 return null
func click(point:Vector2) -> void:
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion)
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event);await process_frame
func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])
func underlay_input(event:InputEvent) -> void:
 if event is InputEventMouseButton and event.pressed:background_clicks+=1
func telemetry() -> Dictionary:
 return {"speed":21.8,"forward_speed":17.2,"vertical_speed":-13.4,"altitude":73.0,"target_altitude":150.0,"flight_phase":"climb","route_heading":-.4,"ship_heading":-.6,"lane_offset":-2.0,"lookahead_seconds":3.5,"next_gate_index":1,"next_gate_time":4.2,"next_gate_altitude":94.0,"next_gate_direction":-1,"next_gate_dx":72.24,"next_gate_dy":-21.0,"next_gate_half_gap":8.0,"energy_remaining":3720.0,"battery_capacity":6000.0,"pilot_boost":true,"pilot_active":true,"distance":208.0,"total_distance":520.0,"elapsed":10.5,"integrity":.92}
func fixture() -> Dictionary:
 return {"mode":"flight","control_version":"pilot-v2","activeorder":{"name":"城市升空 → 晨星轨道站","distance":520.0,"deadline":48,"time_limit":70,"pilot_altitude":150.0},"flight":telemetry(),"settings":{"reduced_motion":true,"motion_blur":true}}
func resource_panel() -> Control:
 return hud.flight_labels.energy.get_parent().get_parent()
func resource_text_fits() -> bool:
 var panel:=resource_panel()
 if panel.size!=Vector2(260,96):return false
 for label in panel.find_children("*","Label",true,false):
  if not panel.get_global_rect().encloses(label.get_global_rect()):return false
  if label.get_minimum_size().x>label.size.x or label.get_minimum_size().y>label.size.y:return false
 return true
func logical_rect(rect:Rect2) -> Rect2:
 return Rect2(hud.root.position+rect.position*hud.root.scale,rect.size*hud.root.scale)
func capture(name:String) -> void:
 if DisplayServer.get_name()=="headless" or not "--capture" in OS.get_cmdline_user_args():return
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/ascent-hud"))
 root.get_texture().get_image().save_png("res://docs/qa/ascent-hud/"+name+".png")
func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
 var background:=ColorRect.new();background.color=Color("34465c");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.gui_input.connect(underlay_input);root.add_child(background)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action);hud.set_art_frame(Rect2(0,40,1280,720))
 var data:=fixture();hud.render(data);await settle()
 check(hud._pilot_mode() and hud._ascent_mode(),"v2 selects manual pilot and ascent presentation")
 check(button("1×")==null and button("2×")==null and button("4×")==null,"v2 exposes no autonomous simulation-rate controls")
 check(button("暂停  [Esc / P]")!=null and button("中止本次")!=null,"v2 preserves pause and abort controls")
 check(hud.flight_labels.status.text=="速度 21.8 m/s · 爬升","v2 shows velocity magnitude rather than forward component")
 check(hud.flight_labels.altitude.text=="高度 73 / 150 m","altitude retains actual route height without implementation labels")
 check(hud.flight_labels.energy.text=="电量 3.72 kJ / 6.00 kJ · 冲刺中","remaining energy and effective capacity come from telemetry")
 check(hud.flight_labels.pilot_signal.text=="Space 回路 · 触发中","v2 retains actual active-circuit feedback")
 check(is_equal_approx(hud.progress_bar.value,40.0),"v2 progress uses actual distance along the route")
 check(hud.flight_labels.gate.text=="↑ 向上 · 4.2 s 后过门" and hud.flight_labels.gate_detail.text=="第 2 门 · 门高 94 m","early gate cue names actual direction, time, index and height")
 check(hud.flight_labels.gate.get_theme_color("font_color")==HUD.TEAL,"distant gate cue stays quiet")
 var live:=telemetry();live.next_gate_time=3.5;hud.update_flight(live)
 check(hud.flight_labels.gate.get_theme_color("font_color")==HUD.YELLOW,"lookahead boundary receives a steady warning color")
 live.next_gate_time=2.1;live.next_gate_direction=1;hud.update_flight(live)
 check(hud.flight_labels.gate.text=="↓ 向下 · 2.1 s 后过门","positive gate direction requests downward input")
 live.next_gate_direction=0;hud.update_flight(live)
 check(hud.flight_labels.gate.text.begins_with("→ 保持"),"aligned gate requests holding the current lane")
 for i in 90:live.next_gate_time=3.5-float(i)/60.0;hud.update_flight(live)
 check(hud._motion_tweens.is_empty() and hud._ascent_cue.modulate==Color.WHITE,"repeated cue updates never create flashing or motion Tweens")
 live=telemetry();live.next_gate_time=2.1;live.paused=true;hud.update_flight(live)
 check(button("继续  [Esc / P]")!=null and hud.flight_labels.status.text=="已暂停","paused v2 uses the explicit Continue action")
 check(hud.flight_labels.gate_detail.text.begins_with("已暂停") and hud.flight_labels.gate.get_theme_color("font_color")==HUD.DIM,"paused gate cue stays informative without an urgency warning")
 var before_text:String=hud.flight_labels.gate.text;await settle()
 check(hud.flight_labels.gate.text==before_text,"HUD does not autonomously count down while paused")
 await click(button("继续  [Esc / P]").get_global_rect().get_center())
 check(actions==[["pause",null]],"native GUI pointer emits one resume intent")
 live.paused=false;hud.update_flight(live)
 check(button("暂停  [Esc / P]")!=null and hud.flight_labels.gate.get_theme_color("font_color")==HUD.YELLOW,"resumed telemetry restores pause action and imminent gate color")
 live.energy_remaining=84.0;live.battery_capacity=300.0;live.pilot_boost=false;hud.update_flight(live)
 check(hud.flight_labels.energy.text=="电量 84 J / 300 J · 冲刺待命","small batteries retain readable J units without inventing extra capacity")
 live.energy_remaining=0.0;live.pilot_boost=true;hud.update_flight(live)
 check(hud.flight_labels.energy.text=="电量 0 J / 300 J · 电量耗尽","empty battery overrides held boost text")
 live.energy_remaining=NAN;live.battery_capacity=INF;hud.update_flight(live)
 check(hud.flight_labels.energy.text=="电量 — / — · 电量未知","nonfinite energy remains unknown rather than fabricating a charged battery")
 live=telemetry();live.flight_phase="city";hud.update_flight(live)
 check(hud.flight_labels.status.text.ends_with("城市"),"city phase is compact and distinct")
 live.flight_phase="approach";live.next_gate_index=-1;live.next_gate_time=-1;hud.update_flight(live)
 check(hud.flight_labels.status.text.ends_with("接站") and hud.flight_labels.gate.text=="接近收件区" and hud.flight_labels.gate_detail.text.is_empty(),"final approach clears stale gate direction and countdown")
 live.flight_phase="climb";hud.update_flight(live)
 check(hud.flight_labels.gate.text.is_empty() and not hud.flight_labels.gate.text.contains("s"),"empty mid-route gate data never fabricates a next gate")
 hud.update_flight({})
 check(hud.flight_labels.gate.text.is_empty() and hud.flight_labels.energy.text.contains("— / —"),"missing telemetry adds no idle instructions and keeps energy unknown")
 live=telemetry();live.next_gate_time=NAN;hud.update_flight(live)
 check(not hud.flight_labels.gate.text.contains("nan") and not hud.flight_labels.gate.text.contains("s"),"nonfinite gate time is not presented as a usable warning")
 live=telemetry();live.charging=true;hud.update_flight(live)
 check(not hud._ascent_cue.visible and hud.flight_labels.hint.text.is_empty(),"charging hides redundant directional cues")
 live.charging=false;hud.update_flight(live);hud.update_launch(.4,"charge");await settle()
 check(not hud._ascent_cue.visible and hud._launch_layer.position.y==108,"charge ribbon stays above the tall ship and suppresses the cue")
 hud.update_launch(.9,"ignition");await settle()
 check(not hud._ascent_cue.visible,"ignition also suppresses redundant gate instructions")
 hud.update_launch(1,"release");await settle()
 check(hud._ascent_cue.visible and not hud._ascent_cue.get_global_rect().intersects(hud._launch_layer.get_global_rect()),"release reveals gate guidance without covering the ribbon")
 hud.update_launch(1,"done");await settle()
 check(hud._ascent_cue.visible and not is_instance_valid(hud._launch_layer),"completed ribbon releases cleanly and leaves live gate guidance")
 for spec in [[Vector2i(1280,800),Rect2(0,40,1280,720),1],[Vector2i(1920,1080),Rect2(0,0,1920,1080),1],[Vector2i(3840,2160),Rect2(0,0,3840,2160),3]]:
  var extent:Vector2i=spec[0];var frame:Rect2=spec[1];var factor:int=spec[2]
  root.size=extent;hud.set_art_frame(frame);data=fixture();data.flight.next_gate_time=2.8;hud.render(data);await settle()
  check(hud.root.scale==Vector2.ONE*factor and frame.encloses(hud._ascent_cue.get_global_rect()),"cue stays inside the integer-scaled frame at "+str(extent))
  var fits:bool=hud._ascent_cue.position==Vector2(20,108) and hud._ascent_cue.size==Vector2(260,78)
  for key in ["altitude","gate","gate_detail"]:fits=fits and hud._ascent_cue.get_global_rect().encloses(hud.flight_labels[key].get_global_rect())
  var energy_panel:=resource_panel()
  fits=fits and frame.encloses(energy_panel.get_global_rect()) and energy_panel.position==Vector2(20,198) and resource_text_fits()
  check(fits,"altitude/gate/capacity labels fit existing small HUD regions at "+str(extent))
  # The rightmost 304 logical pixels are the first visible incoming corridor.
  # Check every opaque top-level panel, including the retained route strip.
  var approach:=logical_rect(Rect2(hud._size.x-304,0,304,hud._size.y*.5))
  var approach_clear:=true
  for panel in hud.content.get_children():
   if panel is PanelContainer and panel.visible:
    var style:StyleBoxFlat=panel.get_theme_stylebox("panel") as StyleBoxFlat
    if style!=null and style.bg_color.a>.5:approach_clear=approach_clear and not panel.get_global_rect().intersects(approach)
  check(approach_clear,"opaque flight HUD leaves the incoming top-right corridor clear at "+str(extent))
  var separate:=not energy_panel.get_global_rect().intersects(hud._ascent_cue.get_global_rect())
  var ship_band:=logical_rect(Rect2(0,hud._size.y*.44,hud._size.x,hud._size.y*.22))
  separate=separate and not energy_panel.get_global_rect().intersects(ship_band)
  for control in hud.content.find_children("*","Button",true,false):separate=separate and not energy_panel.get_global_rect().intersects(control.get_global_rect())
  check(separate,"left resource column avoids the cue, central ship band and pilot buttons at "+str(extent))
  var states_fit:=true
  for energy_state in [{"integrity":1.0,"energy_remaining":12600.0,"battery_capacity":12600.0,"pilot_boost":false,"pilot_active":false},{"integrity":0.0,"energy_remaining":0.0,"battery_capacity":6000.0,"pilot_boost":true,"pilot_active":true},{"integrity":.42,"energy_remaining":NAN,"battery_capacity":INF,"pilot_boost":false,"pilot_active":false}]:
   live=telemetry();live.merge(energy_state,true);hud.update_flight(live);await settle();states_fit=states_fit and resource_text_fits()
  check(states_fit,"integrity, capacity, empty/unknown energy and Space states fit the left column at "+str(extent))
  live=telemetry();live.paused=true;hud.update_flight(live);await settle()
  check(resource_text_fits() and hud.flight_labels.status.text=="已暂停" and button("继续  [Esc / P]")!=null,"paused ascent retains readable resources and Continue caption at "+str(extent))
  hud.update_flight(data.flight);hud.update_launch(.4,"charge");await settle()
  check(not energy_panel.get_global_rect().intersects(hud._launch_layer.get_global_rect()),"left resource column leaves the launch ribbon clear at "+str(extent))
  hud.update_launch(1,"done");await settle()
  var before:=background_clicks;await click(hud._ascent_cue.get_global_rect().get_center())
  check(background_clicks==before+1 and not hud.is_blocking_modal(),"cue passes pointer input through without a modal at "+str(extent))
  await capture("ascent-"+str(extent.x)+"x"+str(extent.y))
 data=fixture();data.erase("control_version");data.activeorder.control_version="pilot-v2";hud.render(data);await settle()
 check(hud._ascent_mode() and button("2×")==null,"order-level v2 version also selects manual ascent")
 hud.state.parts=[{"id":1,"type":"battery"},{"id":2,"type":"thruster"}]
 check(-2 in hud._wire_options({"id":2},"input_a").map(func(row):return row.id) and not -2 in hud._wire_options({"id":2},"target").map(func(row):return row.id),"v2 offers cockpit signal only for signal selectors")
 data=fixture();data.control_version="pilot-v1";hud.render(data);await settle()
 check(hud._pilot_mode() and not hud._ascent_mode() and not hud.flight_labels.has("gate") and button("2×")==null,"v1 retains manual controls with no ascent cue")
 check(resource_panel().position==Vector2(hud._size.x-304,20) and resource_panel().size==Vector2(284,96),"non-ascent pilot keeps its existing resource placement")
 hud.update_flight({"forward_speed":24.5,"vertical_speed":-3.0,"speed":27.0,"energy_remaining":84.0,"pilot_boost":true})
 check(hud.flight_labels.status.text=="速度 24.5 m/s · 升降 -3.0" and hud.flight_labels.energy.text=="电量 84 J · 冲刺中","v1 forward/vertical speed and J-only energy semantics are unchanged")
 data.erase("control_version");hud.render(data);await settle()
 check(not hud._pilot_mode() and button("1×")!=null and button("2×")!=null and button("4×")!=null and not hud.flight_labels.has("gate"),"autonomous legacy retains rate controls without ascent guidance")
 hud.update_flight({"speed":2,"energy_used":18})
 check(hud.flight_labels.status.text.ends_with("2×") and hud.flight_labels.energy.text=="消耗 18.0 J","autonomous speed remains a simulation multiplier")
 data=fixture();data.settings.reduced_motion=false;hud.render(data);await settle()
 for i in 60:hud.update_flight(telemetry())
 check(hud._motion_tweens.is_empty(),"normal-motion mode also uses steady, Tween-free guidance")
 hud.queue_free();background.queue_free();for i in 6:await process_frame
 check(get_processed_tweens().is_empty(),"v2/v1/legacy rerenders and teardown release all Tweens")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every ascent HUD assertion ran: expected %d, saw %d"%[EXPECTED_CHECKS,passed+failed])
 print("ASCENT_HUD passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
