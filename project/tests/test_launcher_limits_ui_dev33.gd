extends Node
## Bounded actual v8 launcher/HUD checks at the normal 1280x814 window size.
## Godot lays out real controls; no native mouse, visual or gameplay acceptance
## is claimed. Fixtures use isolated simulation state and never write saves.
const HUD=preload("res://scripts/game_hud.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
var hud
var actions:Array=[]
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for frame in 5:await get_tree().process_frame
func inside(control:Control,clip:Control)->bool:
 return control!=null and clip!=null and control.is_visible_in_tree() and clip.get_global_rect().encloses(control.get_global_rect())
func labels_with(node:Node,copy:String)->int:
 var count:int=0
 for label in node.find_children("*","Label",true,false):
  if label.text.contains(copy):count+=1
 return count
func button_action(action:String)->Button:
 for button in hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("view_key","")).begins_with("action:"+action+":"):return button
 return null
func simulation(kind:String="default"):
 var launcher:Array=Profile.starter_launcher()
 if kind=="support":launcher=launcher.filter(func(part):return str(part.type)!="beam" or int(part.id)==1006)
 var sim=Sim.new();sim.configure(Profile.starter_design(),launcher,Chapter.fresh_route(1),42)
 if kind=="energy":
  for part in sim.launcher_parts:
   if part.type=="battery":part.energy=100.0
 return sim
func physical_bytes(sim)->PackedByteArray:
 return var_to_bytes([sim.parts,sim.bodies,sim.links,sim.launcher_parts,sim.telemetry,sim.route,sim.launch_released,sim.status,sim.elapsed])
func data_for(sim,preview:Dictionary)->Dictionary:
 var order:Dictionary=sim.route.duplicate(true);order.contract_id="ui-launch-limits"
 return {"mode":"workshop","control_version":Profile.VERSION,"activeorder":order,"assembly_mode":"launcher","parts":sim.launcher_parts.duplicate(true),"selectedpart":{},"settings":{"reduced_motion":true},"has_accepted_contract":true,"launch_settings":{"angle_degrees":float(preview.angle_degrees),"power_fraction":float(preview.power_fraction)},"launch_preview":preview}
func check_actions(label:String)->void:
 var dispatch:Control=hud.content.find_child("DispatchActions",true,false)
 var tools:Control=hud.content.find_child("WorkshopTools",true,false)
 var trial:Button=button_action("trial");var send:Button=button_action("dispatch")
 check(inside(dispatch,hud.root) and inside(tools,hud.root),label+" keeps launch and workshop footer panels in normal frame")
 check(inside(trial,dispatch) and inside(send,dispatch) and not trial.disabled and not send.disabled,label+" keeps full enabled trial and dispatch buttons visible")
 var panel:Control=hud.content.find_child("DeliveryLaunchControls",true,false)
 if panel==null:panel=hud.content.find_child("ModuleInspector",true,false)
 check(not panel.get_global_rect().intersects(dispatch.get_global_rect()) and not panel.get_global_rect().intersects(tools.get_global_rect()),label+" explanation does not cover existing footer actions")
func check_case(kind:String,expected:float,warning_fragment:String)->void:
 # Each case starts a fresh HUD, rather than inheriting the previous case's
 # intentionally scrolled position through the real scroll-memory feature.
 if is_instance_valid(hud):hud.queue_free();await settle()
 hud=HUD.new();add_child(hud);hud.set_art_frame(Rect2(0,47,1280,720));hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var sim=simulation(kind)
 check(sim.status=="running",kind+" uses accepted actual v8 simulation")
 var physical:PackedByteArray=physical_bytes(sim)
 var preview:Dictionary=sim.preview_launcher(0.0,1.0)
 var frozen:PackedByteArray=var_to_bytes(preview)
 check(is_equal_approx(float(preview.energy_used),expected),kind+" actual plan has expected paid work")
 check(preview.has("group_limits") and preview.group_limits.size()==1,kind+" preview carries one authoritative component summary")
 var data:Dictionary=data_for(sim,preview)
 hud.palette_open=false;hud.render(data);await settle()
 var panel:Control=hud.content.find_child("DeliveryLaunchControls",true,false)
 var scroll:ScrollContainer=panel.find_children("*","ScrollContainer",true,false)[0]
 var numbers:Label=hud._delivery_launch_labels.numbers
 var warning:Label=hud._delivery_launch_labels.warning
 var arc:Control=hud.content.find_child("DeliveryTrajectoryPreview",true,false)
 check(hud._ui_scale==1.0 and hud.root.get_global_rect()==Rect2(0,47,1280,720),kind+" matches normal 1280x814 native-density art frame")
 check(numbers.text==UI.launch_copy(preview,data.launch_settings) and numbers.text.contains("动力上限 240 J"),kind+" real HUD shows exact shared capacity copy")
 check(numbers.text.contains("6000 J") if kind!="energy" else numbers.text.contains("100 J"),kind+" battery amount remains distinct from motor capacity")
 check(inside(numbers,scroll) and inside(warning,scroll) and inside(arc,scroll),kind+" numbers trajectory and warning are fully visible with tray closed")
 check(inside(hud.content.find_child("LaunchAngleSlider",true,false),scroll) and inside(hud.content.find_child("LaunchPowerSlider",true,false),scroll),kind+" both settings sliders remain fully visible")
 if warning_fragment.is_empty():
  check(warning.text.is_empty() and numbers.text.contains("动力已用满"),"default identifies motor capacity as the active limit without a false battery warning")
 else:
  check(warning.text==str(preview.warning) and warning.text.contains(warning_fragment),kind+" preserves existing authoritative warning verbatim")
  check(labels_with(panel,warning_fragment)==1 and not numbers.text.contains(warning_fragment),kind+" does not duplicate the existing warning in summary")
 check_actions(kind+" closed tray")
 print("LAUNCH_LIMITS_LAYOUT case=",kind," tray_open=false panel=",panel.get_global_rect()," scroll=",scroll.get_global_rect()," numbers=",numbers.get_global_rect()," warning=",warning.get_global_rect()," copy=",numbers.text.replace("\n"," | "))
 hud.palette_open=true;hud.render(data);await settle()
 panel=hud.content.find_child("DeliveryLaunchControls",true,false);scroll=panel.find_children("*","ScrollContainer",true,false)[0]
 numbers=hud._delivery_launch_labels.numbers;warning=hud._delivery_launch_labels.warning
 check(scroll.scroll_vertical==0 and inside(numbers,scroll),kind+" compact capacity explanation is fully visible with the default open tray")
 check_actions(kind+" open tray")
 if not warning_fragment.is_empty():
  scroll.ensure_control_visible(warning);await settle()
  check(scroll.scroll_vertical>0 and inside(warning,scroll),kind+" existing longer warning remains reachable in open-tray scroll")
 print("LAUNCH_LIMITS_LAYOUT case=",kind," tray_open=true panel=",panel.get_global_rect()," scroll=",scroll.get_global_rect()," numbers=",numbers.get_global_rect()," warning=",warning.get_global_rect()," offset=",scroll.scroll_vertical)
 check(physical_bytes(sim)==physical and var_to_bytes(preview)==frozen and actions.is_empty(),kind+" repeated real HUD layout preserves simulation and preview without actions")
 var released:Dictionary=sim.release_launcher(0.0,1.0)
 check(is_equal_approx(float(released.energy_used),float(preview.energy_used)) and released.velocity.is_equal_approx(preview.velocity),kind+" displayed use and velocity equal real release")
func selected_controls()->void:
 var sim=simulation();var data:Dictionary=data_for(sim,sim.preview_launcher(0.0,1.0));data.selectedpart=Profile.starter_launcher()[1]
 hud.palette_open=true;hud.render(data);await settle()
 var panel:Control=hud.content.find_child("ModuleInspector",true,false)
 var scroll:ScrollContainer=panel.find_children("*","ScrollContainer",true,false)[0]
 var numbers:Label=hud._delivery_launch_labels.numbers
 check(inside(button_action("rotate_part"),panel) and inside(button_action("remove_part"),panel),"selected launcher part keeps full rotate and remove actions")
 scroll.ensure_control_visible(numbers);await settle()
 check(inside(numbers,scroll),"selected launcher part can scroll to the complete capacity explanation")
 var parameter:HSlider=panel.find_child("PartParameterSlider",true,false)
 check(parameter!=null,"selected spring retains its existing local parameter slider")
 scroll.ensure_control_visible(parameter);await settle()
 check(inside(parameter,scroll),"selected spring parameter remains reachable below launch preview")
 check_actions("selected part")
func refreshing_copy()->void:
 var sim=simulation();var preview:Dictionary=sim.preview_launcher(0.0,1.0);var data:Dictionary=data_for(sim,preview)
 hud.palette_open=false;hud.render(data);await settle()
 var settings:Dictionary={"angle_degrees":0.0,"power_fraction":.2}
 var low:Dictionary=sim.preview_launcher(0.0,.2)
 hud.update_delivery_launch_preview(settings,low);await settle()
 check(hud._delivery_launch_labels.numbers.text.contains("动力上限 240 J") and hud._delivery_launch_labels.numbers.text.contains("力度请求 48 J") and not hud._delivery_launch_labels.numbers.text.contains("动力已用满"),"real reduced power displays requested work rather than claiming full motor use")
 hud.update_delivery_launch_preview(settings,preview);await settle()
 check(hud._delivery_launch_labels.numbers.text=="发射预览待更新" and button_action("trial").disabled and button_action("dispatch").disabled,"mismatched settings clear the new capacity explanation and block stale launch")
 var starved=simulation("energy");var limited:Dictionary=starved.preview_launcher(0.0,1.0)
 hud.update_delivery_launch_preview(data.launch_settings,limited);await settle()
 check(hud._delivery_launch_labels.warning.text==limited.warning,"changing actual state refreshes energy warning")
 hud.update_delivery_launch_preview(data.launch_settings,preview);await settle()
 check(hud._delivery_launch_labels.warning.text.is_empty() and labels_with(hud.content,"动力上限")==1 and not button_action("trial").disabled,"restoring real default preview clears stale warning without duplicate summaries")
 var historical:Dictionary=preview.duplicate(true);historical.erase("group_limits")
 check(UI.launch_copy(historical,data.launch_settings).count("\n")==1 and not UI.launch_copy(historical,data.launch_settings).contains("动力上限"),"older snapshots without component evidence retain their two historical lines")
func run()->void:
 if OS.get_environment("SC_LAUNCHER_LIMITS_UI_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,814)
 hud=HUD.new();add_child(hud);hud.set_art_frame(Rect2(0,47,1280,720));hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 await check_case("default",240.0,"")
 await check_case("support",64.0,"支撑承载限制了输出")
 await check_case("energy",100.0,"台上电量限制了输出")
 await selected_controls()
 await refreshing_copy()
 hud.queue_free();await settle()
 print("LAUNCHER_LIMITS_UI_DEV33 passed=%d failed=%d actual_v8_plan=true normal_1280x814_layout=true native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
