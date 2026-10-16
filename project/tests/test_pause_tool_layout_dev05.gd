extends SceneTree
## Actual HUD bounds with the production font, skin and density adapter.
## Synthetic read-only snapshots; no native-input, solver or save claim.
const HUD=preload("res://scripts/game_hud.gd")
const Metrics=preload("res://scripts/demo_display_metrics.gd")
const Framing=preload("res://scripts/free_flight_framing_2d.gd")
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
var records:Array=[]
var capture_dir:String=""

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for index in 5:await process_frame
func flight() -> Dictionary:
 return {"elapsed":29.6,"paused":false,"save_exit_available":true,"free_flight":true,"speed":1.3,"cargo_y":-14.3,"energy_remaining":72.0,"energy_capacity":100.0,"energy_fraction":.72,"flight_status":"running","selected_tool":{"id":1006,"name":"接触钻头","direction":"→","status":"按住启动 · 慢推破岩","hold_to_use":true},"events":["028.5s  接触钻头 碰撞，受损 0.8 HP。"],"destination_navigation":{"status":"running","charging":false,"cargo_screen":Vector2(600,360),"receiver_screen":Vector2(1400,360),"distance_m":163.0}}
func fixture(data:Dictionary) -> Dictionary:
 return {"mode":"flight","trial":true,"control_version":"pilot-free-v2","activeorder":{"id":"pause-layout-fixture","control_version":"pilot-free-v2","destination_name":"月面前哨收件台","background_ground_y_m":0.0},"flight":data,"settings":{"reduced_motion":true}}
func bounds(control:Control) -> Array:
 var rect:Rect2=control.get_global_rect()
 return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
func verify_layout(frame:Rect2,label:String,paused:bool) -> void:
 var panel:Control=hud.content.get_node("SelectedFlightTool")
 var exit_button:Button=hud.content.get_node("FlightSaveAndExit")
 check(panel.is_visible_in_tree(),label+" selected device is visible")
 check(frame.encloses(panel.get_global_rect()),label+" selected card is in the art frame")
 for key in ["tool_name","tool_state","tool_keys"]:
  var text:Label=hud.flight_labels[key]
  check(text.is_visible_in_tree() and not text.text.is_empty(),label+" "+key+" remains visible and populated")
  check(panel.get_global_rect().grow(1).encloses(text.get_global_rect()),label+" "+key+" is contained by its card")
  var native_width:float=text.get_theme_font("font").get_string_size(text.text,HORIZONTAL_ALIGNMENT_LEFT,-1,text.get_theme_font_size("font_size")).x
  check(native_width<=text.size.x+1.0,label+" "+key+" has room for its full untrimmed text")
  for button in hud.content.find_children("*","Button",true,false):
   if button.is_visible_in_tree():check(not button.get_global_rect().intersects(text.get_global_rect()),label+" "+key+" is not covered by "+button.text)
 for button in hud.content.find_children("*","Button",true,false):
  if button.is_visible_in_tree():
   check(frame.encloses(button.get_global_rect()),label+" button fits frame: "+button.text)
   check(not panel.get_global_rect().intersects(button.get_global_rect()),label+" selected card is clear of "+button.text)
 var legend:Control=hud.flight_labels.controls.get_parent()
 check(frame.encloses(legend.get_global_rect()),label+" flight legend fits frame")
 check(not panel.get_global_rect().intersects(legend.get_global_rect()),label+" selected card is clear of movement legend")
 check(exit_button.visible==paused,label+" save exit retains pause-only visibility")
 if paused:
  check(not exit_button.get_global_rect().intersects(legend.get_global_rect()),label+" save exit is clear of movement legend")
  for name_value in ["FreeFlightGoal","FlightTelemetry","FlightResources"]:
   check(not exit_button.get_global_rect().intersects(hud.content.get_node(name_value).get_global_rect()),label+" save exit is clear of "+name_value)
  var telemetry:Control=hud.content.get_node("FlightTelemetry")
  var energy:Control=hud.content.get_node("FlightResources")
  check(exit_button.get_global_rect().position.x>=telemetry.get_global_rect().end.x+12.0*hud._ui_scale-1.0 and exit_button.get_global_rect().end.x<=energy.get_global_rect().position.x-12.0*hud._ui_scale+1.0,label+" exit has at least 12 authored pixels on each side in the existing top gap")
 var safe:Rect2=Framing.safe_rect(Vector2(1280,720))
 var native_safe:Rect2=Metrics.rect(safe,hud._ui_scale);native_safe.position+=frame.position
 check(not native_safe.intersects(panel.get_global_rect()) and (not paused or not native_safe.intersects(exit_button.get_global_rect())),label+" world safe rectangle remains unobstructed")
 check(actions.is_empty(),label+" layout emits no action")
func run() -> void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--capture-dir="):capture_dir=argument.trim_prefix("--capture-dir=")
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 # 1280x720 is the declared minimum. Intermediate widths cover narrower
 # supported desktops; subminimum window support is deliberately not claimed.
 var geometries:Array=[Vector2i(1280,720),Vector2i(1280,812),Vector2i(1366,768),Vector2i(1440,900),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(1280,720)]
 for extent in geometries:
  root.size=extent
  var frame:Rect2=Metrics.stage_rect(Vector2(extent));hud.set_art_frame(frame)
  var data:Dictionary=flight();hud.render(fixture(data));await settle()
  var card:Control=hud.content.get_node("SelectedFlightTool")
  var card_rect:Rect2=card.get_global_rect()
  var children:int=hud.content.get_child_count()
  for gamepad in [false,true]:
   hud.set_input_device(gamepad)
   for paused in [false,true,false,true]:
    data.paused=paused;var before:PackedByteArray=var_to_bytes(data)
    hud.update_flight(data);await settle()
    var tag:String=str(extent)+" pad="+str(gamepad)+" paused="+str(paused)
    verify_layout(frame,tag,paused)
    check(var_to_bytes(data)==before,tag+" exact input snapshot remains unchanged")
    check(card.get_global_rect()==card_rect and hud.content.get_child_count()==children,tag+" pause/resume does not move card or add nodes")
    check(hud.flight_labels.tool_name.text=="接触钻头  →",tag+" name and direction retained")
    check(hud.flight_labels.tool_state.text==("已暂停" if paused else "按住启动 · 慢推破岩"),tag+" held-drill state retained")
    check(hud.flight_labels.tool_keys.text==("Y 切换 · 按住 A" if gamepad else "Q 切换 · 按住 Space"),tag+" exact device-specific hold hint retained")
    var exit_button:Button=hud.content.get_node("FlightSaveAndExit")
    check(exit_button.disabled==false and exit_button.focus_mode==(Control.FOCUS_ALL if paused else Control.FOCUS_NONE),tag+" save availability/focus behavior retained")
    if paused:check(root.gui_get_focus_owner()==hud._pause_button.get_ref(),tag+" Continue keeps safe pause focus")
    else:check(root.gui_get_focus_owner()==null,tag+" active flight releases HUD focus")
   for status in ["钻头运转","钻头运转 · 供电不足","电量不足"]:
    data.paused=false;data.selected_tool.status=status;hud.update_flight(data);await settle()
    verify_layout(frame,str(extent)+" "+status,false)
    check(hud.flight_labels.tool_state.text==status,"source paid-output status is not rewritten: "+status)
   data.selected_tool.status="按住启动 · 慢推破岩"
  data.paused=true;hud.update_flight(data);hud.update_flight_exit_state(true,false);await settle()
  verify_layout(frame,str(extent)+" unavailable exit",true)
  var exit_button:Button=hud.content.get_node("FlightSaveAndExit")
  check(exit_button.disabled and exit_button.focus_mode==Control.FOCUS_NONE,"unavailable save stays disabled at "+str(extent))
  hud.update_flight_exit_state(true,true);await settle()
  var long_order:Dictionary=fixture(data)
  long_order.activeorder.destination_name="月面前哨南侧大型联合研究基地第二号快递收件台"
  hud.render(long_order);await settle()
  verify_layout(frame,str(extent)+" paused rebuild with long destination",true)
  check(hud.flight_labels.status.text=="已暂停" and hud.flight_labels.destination.text.contains("联合研究基地"),"long order and pause status survive unchanged at "+str(extent))
  check(hud.content.get_node("SelectedFlightTool").get_global_rect()==card_rect,"resize/rebuild does not drift device layout at "+str(extent))
  hud.settings_open=true;hud.render(fixture(data));await settle()
  exit_button=hud.content.get_node("FlightSaveAndExit")
  check(hud.is_blocking_modal() and exit_button.disabled and exit_button.focus_mode==Control.FOCUS_NONE,"settings retains exclusive focus at "+str(extent))
  hud.controller_back();await settle();hud.update_flight(data);await settle()
  verify_layout(frame,str(extent)+" after settings close",true)
  data.selected_tool={"name":"位移器","direction":"→","status":"可用"};hud.update_flight(data);await settle()
  verify_layout(frame,str(extent)+" edge device",true)
  check(hud.flight_labels.tool_state.text=="可用" and hud.flight_labels.tool_keys.text=="Y 切换 · A 使用","edge-device state and non-held hint are unchanged")
  data.selected_tool=flight().selected_tool;hud.set_input_device(false);hud.update_flight(data);await settle()
  for offset in [Vector2(1200,0),Vector2(1200,800),Vector2(0,800),Vector2(-1200,800),Vector2(-1200,0),Vector2(0,-800)]:
   data.destination_navigation.cargo_screen=frame.get_center();data.destination_navigation.receiver_screen=frame.get_center()+offset*hud._ui_scale
   hud.update_flight(data);await settle()
   var cue:Control=hud._destination_cue
   var distance_rect:Rect2=cue._distance.get_global_rect()
   var arrow_rect:Rect2=Rect2(cue._tip-Vector2.ONE*25.0*hud._ui_scale,Vector2.ONE*50.0*hud._ui_scale);arrow_rect.position+=frame.position
   check(cue.visible and not distance_rect.intersects(hud.content.get_node("SelectedFlightTool").get_global_rect()) and not distance_rect.intersects(hud.content.get_node("FlightSaveAndExit").get_global_rect()),"arrival distance is not covered from bearing "+str(offset)+" at "+str(extent))
   check(not arrow_rect.intersects(hud.content.get_node("SelectedFlightTool").get_global_rect()) and not arrow_rect.intersects(hud.content.get_node("FlightSaveAndExit").get_global_rect()),"arrival arrow is not covered from bearing "+str(offset)+" at "+str(extent))
  data.destination_navigation=flight().destination_navigation;hud.update_flight(data);await settle()
  records.append({"extent":[extent.x,extent.y],"art_frame":[frame.position.x,frame.position.y,frame.size.x,frame.size.y],"card":bounds(hud.content.get_node("SelectedFlightTool")),"save_exit":bounds(hud.content.get_node("FlightSaveAndExit")),"tool_name":bounds(hud.flight_labels.tool_name),"tool_state":bounds(hud.flight_labels.tool_state),"tool_keys":bounds(hud.flight_labels.tool_keys)})
  if not capture_dir.is_empty() and DisplayServer.get_name()!="headless":
   DirAccess.make_dir_recursive_absolute(capture_dir);await RenderingServer.frame_post_draw
   var output:String=capture_dir.path_join("paused-%dx%d.png"%[extent.x,extent.y])
   check(root.get_texture().get_image().save_png(output)==OK,"actual rendered synthetic HUD capture saved "+output)
  data.selected_tool={};hud.update_flight(data);await settle()
  check(not hud.content.get_node("SelectedFlightTool").visible,"no selected device keeps card hidden")
  data.selected_tool=flight().selected_tool;data.flight_status="failed";hud.update_flight(data);await settle()
  check(not hud.content.get_node("SelectedFlightTool").visible,"terminal flight keeps card hidden")
 # The actual action still emits exactly the unchanged intent, without a controller
 # or save implementation attached to this isolated layout fixture.
 var data:Dictionary=flight();data.paused=true;hud.render(fixture(data));await settle()
 hud.content.get_node("FlightSaveAndExit").pressed.emit()
 check(actions.size()==1 and actions[0]==["save_and_quit",null],"save button retains its exact action binding")
 print("PAUSE_TOOL_LAYOUT_RECTS "+JSON.stringify(records))
 print("PAUSE_TOOL_LAYOUT_DEV05 passed=%d failed=%d synthetic_layout=true native_input=NOT_RUN"%[passed,failed])
 hud.free();quit(1 if failed else 0)
