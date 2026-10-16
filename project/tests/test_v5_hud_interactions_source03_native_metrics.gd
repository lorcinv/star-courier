extends SceneTree
## HUD-only focus, repeat, scroll and resize tests using physical-window
## synthetic InputEvents. Native OS/XTest captures are recorded separately.
## Explicit successor: the retained original uses a pre-native-metrics 960px check.
## This fixture verifies design-to-native geometry exactly instead of widening it.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts.gd")
const EXPECTED_CHECKS=79
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
func control(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func button(text:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==text:return node
 return null
func pointer(position:Vector2,held:bool=false) -> void:
 var event:=InputEventMouseMotion.new();event.position=position;event.global_position=position;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;root.push_input(event);await process_frame
func mouse(position:Vector2,down:bool,index:int=MOUSE_BUTTON_LEFT) -> void:
 var event:=InputEventMouseButton.new();event.position=position;event.global_position=position;event.button_index=index;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down and index==MOUSE_BUTTON_LEFT else 0;root.push_input(event);await process_frame
func click(node:Control) -> void:
 var center:=node.get_global_rect().get_center();await pointer(center);await mouse(center,true);await mouse(center,false);await settle()
func key(code:int,shift:bool=false) -> void:
 for down in [true,false]:
  var event:=InputEventKey.new();event.keycode=code;event.pressed=down;event.shift_pressed=shift;root.push_input(event);await process_frame
 await settle()
func fixture() -> Dictionary:
 var catalog:=Parts.catalog();var inventory:={}
 for type in catalog:catalog[type].type=type;catalog[type].available=10;inventory[type]=10
 return {"mode":"workshop","day":1,"credits":260,"catalog":catalog,"inventory":inventory,"chosen_type":"beam","assembly_mode":"craft","settings":{"reduced_motion":false,"volume":.55},"has_accepted_contract":true,"activeorder":{"name":"晨星社区","cargo":"耐寒种子","distance":64,"required":85,"deadline":14,"contract_id":"D1-A"},"selectedpart":{"id":2,"type":"thruster","name":"推进喷口","rot":0,"param":3.0,"input_a":-1,"controls":Parts.controls("thruster"),"schema":Parts.parameter_schema("thruster"),"description":"推进喷口的参数。"},"parts":[{"id":1,"type":"battery"},{"id":2,"type":"thruster"}]}
func modal() -> Control:
 for child in hud.content.get_children():
  if child.has_meta("modal_panel"):return child
 return null
func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])
func rect_values(value:Rect2) -> Array:
 return [value.position.x,value.position.y,value.size.x,value.size.y]

func check_native_tray(frame:Rect2,extent:Vector2i,tray:Control) -> void:
 # These explicit profiles are the externally reviewed 720/1080/2160 contract.
 # Do not call DisplayMetrics.factor/rect to compute its own expected answer.
 var density:float=1.0 if extent==Vector2i(1280,800) else 1.5 if extent==Vector2i(1920,1080) else 3.0
 # The original interaction sequence retains its chosen category between loops.
 # Its Parts fixture has 25 legacy entries: eight ordinary and seventeen advanced.
 var expected_category:String="现有库存" if extent==Vector2i(1280,800) else "高级零件"
 var ordinary:Array=["battery","valve","thruster","spring","beam","damper","armor","shield"]
 var expected_ids:Array=ordinary.duplicate()
 if expected_category=="高级零件":
  expected_ids=[]
  for kind in Parts.catalog():
   if not kind in ordinary:expected_ids.append(kind)
 var actual_ids:Array=[]
 for card in tray.find_children("*","Button",true,false):
  var key:String=hud._view_key(card)
  if key.begins_with("catalog:"):actual_ids.append(key.trim_prefix("catalog:"))
 expected_ids.sort();actual_ids.sort()
 # The palette is authored at (20, 720-232), with 104 per card and 16 padding,
 # 728 minimum, 960 maximum, and 152 height. Integer native edges are mandatory.
 var authored_width:float=clampf(float(expected_ids.size())*104.0+16.0,728.0,960.0)
 var authored:Rect2=Rect2(20,488,authored_width,152)
 var native_start:Vector2=(authored.position*density).round()
 var native_end:Vector2=(authored.end*density).round()
 var expected_native:Rect2=Rect2(frame.position+native_start,native_end-native_start)
 var native_actual:Rect2=tray.get_global_rect()
 var snapshot:Dictionary=tray.get_meta(&"demo_native_layout_base_v2",{})
 var offsets:Vector4=snapshot.get("offsets",Vector4(-1,-1,-1,-1))
 var captured_authored:Rect2=Rect2(Vector2(offsets.x,offsets.y),Vector2(offsets.z-offsets.x,offsets.w-offsets.y))
 var proof:Dictionary={"extent":[extent.x,extent.y],"frame":rect_values(frame),"category":hud.palette_category,"expected_category":expected_category,"expected_density":density,"actual_density":hud._ui_scale,"root_scale":[hud.root.scale.x,hud.root.scale.y],"content_scale":[hud.content.scale.x,hud.content.scale.y],"tray_scale":[tray.scale.x,tray.scale.y],"logical_hud_size":[hud._size.x,hud._size.y],"root_rect":rect_values(hud.root.get_global_rect()),"tray_local_rect":rect_values(tray.get_rect()),"captured_authored_rect":rect_values(captured_authored),"expected_authored_rect":rect_values(authored),"actual_global_rect":rect_values(native_actual),"expected_native_rect":rect_values(expected_native),"actual_card_ids":actual_ids,"expected_card_ids":expected_ids,"original_physical_960_check":tray.size.x<=960,"frame_contains":frame.encloses(native_actual),"width_fraction":native_actual.size.x/frame.size.x}
 print("NATIVE_TRAY_PROFILE ",JSON.stringify(proof))
 check(hud.palette_category==expected_category and actual_ids==expected_ids,"tray content matches the controlled category and fixture "+str(extent))
 check(hud._ui_scale==density,"tray uses the explicit native density profile "+str(extent))
 check(hud.root.scale==Vector2.ONE and hud.content.scale==Vector2.ONE and tray.scale==Vector2.ONE,"tray native metrics are not multiplied by a CanvasItem scale "+str(extent))
 check(hud._size==Vector2(1280,720) and hud.root.size==frame.size,"logical design space and native root size remain distinct "+str(extent))
 check(captured_authored==authored,"tray retains the exact compact authored rectangle "+str(extent))
 check(native_actual==expected_native,"tray physical edges equal the exact rounded design transform "+str(extent))
 check(frame.encloses(native_actual),"tray remains wholly inside the physical art frame "+str(extent))
 check(authored.size.x<=960 and native_actual.size.x/frame.size.x<=0.75,"tray occupies at most the original three-quarter design width "+str(extent))

func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action)
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent
  var frame:=Rect2(0,40,1280,720) if extent==Vector2i(1280,800) else Rect2(Vector2.ZERO,Vector2(extent))
  hud.set_art_frame(frame);hud._last_selection_id=-999;hud.render(fixture());await settle()
  check(not hud.palette_open,"selecting an installed part exposes the grounded assistant "+str(extent))
  await click(button("打开零件箱"))
  check(frame.encloses(hud.root.get_global_rect()),"HUD stays within physical art frame "+str(extent))
  var tray:=hud.content.get_node("PartsTray") as Control
  check_native_tray(frame,extent,tray)
  var edits:=hud.content.get_node("WorkshopTools") as Control;var dispatch:=hud.content.get_node("DispatchActions") as Control
  check(not edits.get_global_rect().intersects(dispatch.get_global_rect()) and frame.encloses(dispatch.get_global_rect()),"editing and dispatch clusters do not overlap "+str(extent))
  await click(button("高级零件"))
  var scroll:=control("parts:craft:高级零件") as ScrollContainer
  var point:=scroll.get_global_rect().get_center()
  for i in 4:await pointer(point);await mouse(point,true,MOUSE_BUTTON_WHEEL_DOWN);await mouse(point,false,MOUSE_BUTTON_WHEEL_DOWN)
  var offset:=scroll.scroll_horizontal
  check(offset>0,"physical-window wheel scrolls the parts tray "+str(extent))
  var tray_before_rerender:Rect2=(hud.content.get_node("PartsTray") as Control).get_global_rect()
  hud.render(hud.state);await settle();scroll=control("parts:craft:高级零件") as ScrollContainer
  check(scroll.scroll_horizontal==offset,"tray scroll survives rerender "+str(extent))
  check((hud.content.get_node("PartsTray") as Control).get_global_rect()==tray_before_rerender,"tray native rectangle does not compound on rerender "+str(extent))
  # Source03 deliberately puts the unchanged precise editor behind an explicit disclosure.
  if control("part:2:param:edit")==null:await click(control("part:2:advanced"))
  var editor:=control("part:2:param:edit") as LineEdit
  editor.grab_focus();editor.text="2.75";editor.caret_column=3;editor.select(0,2)
  hud.render(hud.state);await settle();editor=control("part:2:param:edit") as LineEdit
  check(editor.has_focus() and editor.text=="2.75" and editor.caret_column==3 and editor.has_selection(),"in-progress numeric input and selection survive rerender "+str(extent))
  await click(button("发射配送  ↗"))
  check(hud.dispatch_confirmation_open and root.gui_get_focus_owner()==control("dispatch:cancel"),"dispatch starts on the safe cancel action "+str(extent))
  var contained:=true
  for i in 14:
   await key(KEY_TAB);contained=contained and modal().is_ancestor_of(root.gui_get_focus_owner())
  check(contained,"Tab cannot focus background controls through dispatch "+str(extent))
  await key(KEY_ESCAPE)
  check(not hud.dispatch_confirmation_open and root.gui_get_focus_owner()==button("发射配送  ↗"),"Escape closes dispatch and returns keyboard focus "+str(extent))
  actions.clear()
  for i in 3:
   await click(button("发射配送  ↗"));await key(KEY_ENTER)
  check(not hud.dispatch_confirmation_open and actions.is_empty(),"repeated Enter on fresh dispatch only cancels "+str(extent))
  await click(button("≡"))
  check(hud.settings_open and root.gui_get_focus_owner()==control("settings:done"),"settings opens on a safe continuation "+str(extent))
  check(control("settings:done").get_theme_color("font_focus_color")==HUD.INK,"focused cream-sheet action keeps dark legible text "+str(extent))
  var slider:=control("settings:volume") as HSlider
  var rect:=slider.get_global_rect();var start:=rect.position+rect.size*Vector2(.2,.5);var finish:=rect.position+rect.size*Vector2(.8,.5)
  await pointer(start);await mouse(start,true);await pointer(finish,true);await mouse(finish,false);await settle()
  var volume:=float(hud.state.settings.volume)
  check(volume>.65 and volume<.95,"physical-window volume drag updates state "+str(extent))
  root.size=Vector2i(1280,800);hud.set_art_frame(Rect2(0,40,1280,720));hud.render(hud.state);await settle()
  check(hud.settings_open and is_equal_approx((control("settings:volume") as HSlider).value,volume),"modal resize retains dragged volume "+str(extent))
  await click(button("飞行背景动态模糊"))
  check(not bool(hud.state.settings.motion_blur),"background-only blur preference updates without replacing other settings "+str(extent))
  await click(button("减少镜头动态"));await key(KEY_ESCAPE)
  check(not hud.settings_open and bool(hud.state.settings.reduced_motion),"reduced-motion toggle survives modal close "+str(extent))
  await click(button("取消委托"));await key(KEY_ESCAPE)
  check(not hud.is_blocking_modal() and not button("取消委托")==null,"inline cancellation can be dismissed without accepting it "+str(extent))
 hud._stop_motion();hud.queue_free();for i in 8:await process_frame
 check(get_processed_tweens().is_empty(),"focus/scroll/modal teardown leaves no processed Tween")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every interaction assertion ran")
 print("V5_HUD_INTERACTIONS_SOURCE03_NATIVE_METRICS passed=%d failed=%d input=synthetic_physical_window_InputEvent"%[passed,failed]);quit(1 if failed else 0)
