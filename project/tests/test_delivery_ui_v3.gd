extends Node
## Isolated headless HUD assertions. Does not load Main, import assets, or save.
const HUD=preload("res://scripts/game_hud.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
const Preview=preload("res://scripts/delivery_launch_preview_v3.gd")
const World=preload("res://scripts/world_view_2d.gd")
var passed:int=0
var failed:int=0
var hud
var actions:Array=[]
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for tick in 5:await get_tree().process_frame
func order() -> Dictionary:
 return {"control_version":UI.VERSION,"contract_id":"ui-first-light","name":"首章轻货","destination_name":"晨光收件台","distance":96.0,"weight":1.0,"cargo":"轻件","client":"客户","reward":220,"cargo_value":500,"min_delivery_integrity":.8,"economy_policy":"delivery-economy-v3"}
func preview(angle:float=0,power:float=1) -> Dictionary:
 return {"schema":UI.LAUNCH_SCHEMA,"angle_degrees":angle,"power_fraction":power,"mass":12.5,"available_energy":1200.0,"energy_used":300.0,"kinetic_energy":300.0,"speed":6.928,"velocity":Vector2(6.928,0),"impulse":Vector2(86.6,0),"support_limited":false,"energy_limited":false,"can_release":true,"warning":"","trajectory":[Vector2(0,0),Vector2(1,.1),Vector2(2,.4)],"released":false}
func fixture(mode:String="workshop") -> Dictionary:
 return {"mode":mode,"control_version":UI.VERSION,"activeorder":order(),"contracts":[order()],"assembly_mode":"launcher","parts":[],"selectedpart":{},"settings":{"reduced_motion":true},"launch_settings":{"angle_degrees":0.0,"power_fraction":1.0},"launch_preview":preview(),"flight":{"delivery_integrity":1.0,"flight_status":"running","energy_remaining":600,"energy_capacity":600,"energy_fraction":1.0,"speed":8.0},"has_accepted_contract":true}
func text_of(node:Node) -> String:
 var result:String=node.text+"\n" if node is Label or node is Button else ""
 for child in node.get_children():result+=text_of(child)
 return result
func button_action(action:String) -> Button:
 for button in hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("view_key","")).begins_with("action:"+action+":"):return button
 return null
func test_selected_parameter_controls() -> void:
 var Parts=load("res://scripts/parts_expanded.gd")
 var selected:Dictionary={"id":101,"type":"spring","x":0,"y":0,"rot":0,"param":30.0,"input_a":-1,"input_b":-1,"target":-1}
 var current:Dictionary=fixture();current.selectedpart=selected;current.parts=[selected];current.assembly_mode="craft"
 hud.render(current);await settle()
 var parameter:HSlider=hud.content.find_child("PartParameterSlider",true,false)
 check(parameter!=null and "柔性储能" in text_of(hud.content) and not "旧版保留" in text_of(hud.content),"v3 ship spring keeps meaningful local parameter and no legacy disclaimer")
 actions.clear();parameter.value=31.0
 check(actions.size()==1 and actions[0][0]=="set_param" and actions[0][1]=={"id":101,"value":31.0},"existing part-parameter action shape is preserved")
 current=fixture();current.selectedpart=selected;current.parts=[selected]
 hud.render(current);await settle()
 check(hud.content.find_child("LaunchAngleSlider",true,false)!=null and hud.content.find_child("PartParameterSlider",true,false)!=null,"selected pad part preserves both launch settings and individual module slider")
 var old_slider:HSlider=hud.content.find_child("LaunchAngleSlider",true,false)
 actions.clear();hud.render(fixture("contracts"));old_slider.value_changed.emit(90.0)
 check(actions.is_empty(),"retired slider cannot commit after navigation")
 await settle()
 var legacy:Dictionary=fixture();legacy.control_version="pilot-free-v2";legacy.activeorder.control_version="pilot-free-v2";legacy.selectedpart=selected;legacy.parts=[selected]
 hud.render(legacy);await settle();actions.clear()
 check(hud.content.find_child("LaunchAngleSlider",true,false)==null and hud.content.find_child("PartParameterSlider",true,false)!=null,"old pad retains its sole original part slider")
 var slider:HSlider=hud.content.find_child("PartParameterSlider",true,false)
 slider.drag_started.emit();slider.value=32.0;check(actions.is_empty(),"legacy part drag remains commit-on-release")
 slider.drag_ended.emit(true);check(actions.size()==1 and actions[0][0]=="set_param","legacy part drag sends unchanged edit once")
 actions.clear()

func test_real_launcher_preview() -> void:
 var Profile=load("res://scripts/pilot_delivery_profile_v3.gd")
 var Sim=load("res://scripts/pilot_delivery_simulation_v3.gd")
 var route:Dictionary=Profile.route({"weight":1.0})
 var simulation=Sim.new();simulation.configure(Profile.starter_design(),Profile.starter_launcher(),route,42)
 check(simulation.status=="running","actual new solver accepts fresh v3 route")
 var snapshot:Dictionary=simulation.preview_launcher(35,.5)
 var before:PackedByteArray=var_to_bytes(snapshot)
 var actual:Dictionary=fixture();actual.activeorder=route;actual.launch_settings={"angle_degrees":35.0,"power_fraction":.5};actual.launch_preview=snapshot
 hud.render(actual);await settle()
 check(UI.preview_matches(snapshot,actual.launch_settings) and snapshot.speed>0.0,"HUD validates actual launcher_v3 snapshot")
 var numbers:String=str(hud._delivery_launch_labels.numbers.text)
 check(numbers==UI.launch_copy(snapshot,actual.launch_settings),"real mass energy and initial-speed fields reach HUD unchanged")
 var arc:Control=hud.content.find_child("DeliveryTrajectoryPreview",true,false)
 check(arc.projected_path().size()==snapshot.trajectory.size() and snapshot.velocity.x>0 and snapshot.velocity.y<0,"actual 35-degree velocity and full sampled arc reach preview")
 check(var_to_bytes(snapshot)==before and not simulation.launch_released,"drawing preview consumes no energy and does not release launch")
 var release:Dictionary=simulation.release_launcher(35,.5)
 check(is_equal_approx(release.speed,snapshot.speed) and release.velocity.is_equal_approx(snapshot.velocity) and is_equal_approx(release.energy_used,snapshot.energy_used),"displayed initial velocity and energy equal actual release results")
 var heavy_route:Dictionary=Profile.route({"weight":4.0})
 var heavy=Sim.new();heavy.configure(Profile.starter_design(),Profile.starter_launcher(),heavy_route,42)
 var heavy_preview:Dictionary=heavy.preview_launcher(35,.5)
 check(heavy_preview.mass>snapshot.mass and heavy_preview.speed<snapshot.speed,"actual heavier cargo predicts lower initial speed at same energy")
 actual.activeorder=heavy_route;actual.launch_preview=heavy_preview;hud.render(actual);await settle()
 check(hud._delivery_launch_labels.numbers.text==UI.launch_copy(heavy_preview,actual.launch_settings),"changing real order mass refreshes physical preview text")
 var weak:Dictionary=heavy.preview_launcher(35,.25)
 check(weak.energy_used<heavy_preview.energy_used and weak.speed<heavy_preview.speed,"actual power slider fraction changes paid energy and speed")

func run() -> void:
 if OS.get_environment("SC_DELIVERY_UI_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("isolated HOME/XDG required");get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720);hud=HUD.new();add_child(hud)
 hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 check(UI.percent(UI.fraction(.005))=="0.5%","explicit fraction never guesses percent")
 check(is_nan(UI.fraction(80.0)) and is_nan(UI.fraction(".8")),"invalid normalized values stay unknown")
 check(not UI.applies({"control_version":"pilot-free-v2"}),"legacy order is outside delivery presentation")
 check(UI.integrity({"delivery_integrity":.8},order()).qualified,"exact threshold qualifies")
 check(not UI.integrity({"delivery_integrity":.799},order()).qualified,"below threshold is unqualified")
 check(not UI.integrity({"integrity":100},order()).known,"legacy percent field does not fill new cargo bar")
 var snap:Dictionary=fixture();var before:PackedByteArray=var_to_bytes(snap)
 hud.palette_open=false;hud.render(snap);await settle()
 check(var_to_bytes(snap)==before and actions.is_empty(),"render has no mutations or action side effects")
 var angle:HSlider=hud.content.find_child("LaunchAngleSlider",true,false)
 var power:HSlider=hud.content.find_child("LaunchPowerSlider",true,false)
 check(angle!=null and angle.min_value==0 and angle.max_value==90 and power!=null,"launcher exposes 0 to 90 angle and power sliders")
 check("0° 向右 · 90° 向上" in text_of(hud.content),"angle convention is visible")
 check("12.5 kg" in text_of(hud.content) and "6.9 m/s" in text_of(hud.content) and "1200 J" in text_of(hud.content),"numbers consume the supplied physical snapshot")
 check(not button_action("trial").disabled and not button_action("dispatch").disabled,"valid release snapshot enables both launch actions")
 var arc:Control=hud.content.find_child("DeliveryTrajectoryPreview",true,false)
 var path:PackedVector2Array=arc.projected_path()
 check(path.size()==3 and path[1].x>path[0].x and path[1].y>path[0].y,"arc retains supplied direction and gravity shape")
 var panel:Control=hud.content.get_node("DeliveryLaunchControls")
 check(panel.get_global_rect().encloses(angle.get_global_rect()) and panel.get_global_rect().encloses(power.get_global_rect()),"real slider geometry fits launch panel")
 angle.drag_started.emit();angle.value=45
 check(actions.is_empty() and "松开滑条" in text_of(hud.content) and arc.projected_path().is_empty(),"drag shows pending state and retires stale trajectory")
 check(button_action("trial").disabled,"pending angle cannot launch with stale physics")
 angle.drag_ended.emit(true)
 check(actions.size()==1 and actions[0][0]=="set_launch_settings" and actions[0][1]=={"angle_degrees":45.0,"power_fraction":1.0},"mouse drag commits one complete settings intent")
 check("发射预览待更新" in text_of(hud.content),"after commit no speed is fabricated")
 hud.update_delivery_launch_preview({"angle_degrees":45.0,"power_fraction":1.0},preview(45))
 check(not button_action("trial").disabled,"same-settings authoritative preview releases pending state")
 actions.clear();power.value=50
 check(actions.size()==1 and is_equal_approx(actions[0][1].power_fraction,.5) and actions[0][1].angle_degrees==45,"keyboard step commits normalized power with current angle")
 hud.update_delivery_launch_preview({"angle_degrees":45.0,"power_fraction":.5},preview(0))
 check(button_action("trial").disabled and arc.projected_path().is_empty(),"mismatched snapshot is never displayed as current")
 actions.clear();hud.render(fixture("contracts"));await settle()
 var requirement:Label=hud.content.find_child("DeliveryIntegrityRequirement",true,false)
 check(requirement!=null and requirement.is_visible_in_tree() and "80%" in requirement.text,"minimum requirement visible before accepting even with details collapsed")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
  get_tree().root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(fixture("flight"));await settle()
  var health:Control=hud.content.get_node("CargoIntegrityPanel")
  var health_bar:ProgressBar=hud.content.find_child("CargoIntegrityBar",true,false)
  check(health.is_visible_in_tree() and health_bar!=null and health_bar.value==100,"one current cargo bar is permanently visible "+str(extent))
  check(hud.content.find_children("CargoIntegrityBar","ProgressBar",true,false).size()==1,"only one cargo-health resource exists "+str(extent))
  check(health.get_global_rect().encloses(hud.flight_labels.integrity.get_global_rect()) and health.get_global_rect().encloses(hud.flight_labels.integrity_status.get_global_rect()),"integrity text fits real native-density bounds "+str(extent))
  check(is_equal_approx(health_bar.marker_x(),health_bar.size.x*.8),"minimum line uses exact normalized order requirement "+str(extent))
  check(hud.flight_labels.controls.text.contains("Ctrl 刹车"),"approved inertial controls remain visible "+str(extent))
  hud.update_flight({"delivery_integrity":.799,"flight_status":"running"});await settle()
  check("不合格" in hud.flight_labels.integrity_status.text and health_bar.value<80,"below threshold is explicit during flight "+str(extent))
  hud.update_flight({"delivery_integrity":.8,"flight_status":"running"});await settle()
  check(hud.flight_labels.integrity_status.text=="完整度达标","exact threshold UI recovers qualification "+str(extent))
  hud.update_flight({"delivery_integrity":.8,"flight_status":"running","paused":true,"save_exit_available":true});await settle()
  var exit_button:Control=hud.content.get_node("FlightSaveAndExit")
  check(exit_button.visible and not health.get_global_rect().intersects(exit_button.get_global_rect()),"pause save button does not cover cargo bar "+str(extent))
 await test_real_launcher_preview()
 await test_selected_parameter_controls()
 var legacy:Dictionary=fixture("flight");legacy.control_version="pilot-free-v2";legacy.activeorder.control_version="pilot-free-v2"
 hud.render(legacy);await settle()
 check(hud.content.get_node_or_null("CargoIntegrityPanel")==null and not hud.flight_labels.has("integrity"),"old free-flight layout unchanged")
 legacy.mode="workshop";hud.render(legacy);await settle()
 check(hud.content.find_child("LaunchAngleSlider",true,false)==null,"old launcher has no new settings")
 hud.render(fixture());await settle();hud._act("dispatch");await settle()
 check(hud.dispatch_confirmation_open and "最低交付完整度 80%" in text_of(hud.content) and "债务" in text_of(hud.content) and not "失败最多 ¥25" in text_of(hud.content),"formal preflight shows threshold and actual debt liability")
 hud._dismiss_dispatch();await settle()
 var report:Dictionary=fixture("report");report.report={"control_version":UI.VERSION,"trial":false,"success":false,"delivery_integrity":.5,"min_delivery_integrity":.8,"integrity":50.0,"compensation":250,"debt_added":70,"debt":90,"profit":-270,"delivery_failure":"integrity_below_minimum"}
 hud.render(report);await settle()
 var report_text:String=text_of(hud.content)
 check("50%" in report_text and "不合格" in report_text and "货损赔偿 ¥250" in report_text and "新增债务 ¥70" in report_text and "当前债务 ¥90" in report_text,"formal receipt consumes canonical integrity compensation and debt")
 report.report.trial=true;hud.render(report);await settle()
 check("本次免费，不扣赔偿、不增债务。" in text_of(hud.content) and not "新增债务" in text_of(hud.content),"trial receipt cannot imply formal charging")
 var migration:Dictionary=fixture("contracts");migration.free_order_upgrade={"delivery":{"kind":"delivery","available":true,"count":3}}
 hud.render(migration);await settle()
 check(button_action("upgrade_delivery_offers")!=null,"existing counter offers explicit chapter migration")
 check(hud.open_free_order_upgrade(migration.free_order_upgrade.delivery),"delivery migration opens existing guarded modal")
 await settle();var upgrade_text:String=text_of(hud.content)
 check("先备份原存档" in upgrade_text and "已接旧订单按原规则完成" in upgrade_text and "确认进入首章" in upgrade_text,"migration explains backup old contracts and explicit confirmation")
 actions.clear();hud._dismiss_free_order_upgrade();await settle()
 check(actions.size()==1 and actions[0][0]=="cancel_free_upgrade","migration cancel emits no confirmation")
 var historical:Dictionary=fixture("report");historical.report={"control_version":"pilot-free-v2","trial":true,"success":true,"integrity":88.0}
 hud.render(historical);await settle()
 check("本次免费，资金不变。" in text_of(hud.content) and not "完整度数据待确认" in text_of(hud.content) and not "新增债务" in text_of(hud.content),"explicit old report version wins over current chapter UI state")
 hud.queue_free();await settle()
 print("DELIVERY_UI_V3 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
