extends Node
## One event owner for controllers. Native keyboard/mouse widgets remain native.
## Raw held state never crosses context, focus or device boundaries without release.
const REPEAT_DELAY:float=.34
const REPEAT_INTERVAL:float=.10
const PROMPT_HYSTERESIS:float=.32
const ACTION_BUTTONS:Dictionary={"confirm":JOY_BUTTON_A,"back":JOY_BUTTON_B,"grid":JOY_BUTTON_X,"move":JOY_BUTTON_Y,"remove":JOY_BUTTON_LEFT_SHOULDER,"boost":JOY_BUTTON_RIGHT_SHOULDER,"menu":JOY_BUTTON_START,"fit":JOY_BUTTON_RIGHT_STICK,"part":JOY_BUTTON_LEFT_STICK}
const ACTION_KEYS:Dictionary={"confirm":[KEY_ENTER,KEY_KP_ENTER],"back":[KEY_ESCAPE],"interact":[KEY_E],"shop_left":[KEY_A],"shop_right":[KEY_D],"pause":[KEY_P],"rotate":[KEY_R],"fit":[KEY_F]}
var host
var context:String=""
var focused:bool=true
var gamepad:bool=false # Cosmetic prompt device; deliberately debounced.
var controller_navigation:bool=false # Immediate real input owner; never debounced.
var active_device:int=-1
var deadzone:float=.22
var _buttons:Dictionary={}
var _keys:Dictionary={}
var _mouse:Dictionary={}
var _axes:Dictionary={}
var _blocked:Dictionary={}
var _clock:float=0.0
var _prompt_changed:float=-100.0
var _direction:Vector2i=Vector2i.ZERO
var _repeat_left:float=0.0
var _hub_ui:bool=false
var _grid:bool=false
var _last_page:String=""
var _hint:Label
var _cursor:Panel
var _layer:CanvasLayer

func bind(owner_node) -> void:
 host=owner_node;name="CourierInput"
 _install_actions()
 if not Input.joy_connection_changed.is_connected(_joy_connection_changed):Input.joy_connection_changed.connect(_joy_connection_changed)
 _layer=CanvasLayer.new();_layer.layer=45;add_child(_layer)
 _hint=Label.new();_hint.name="DeviceActions";_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;_hint.add_theme_font_override("font",preload("res://assets/fonts/ChineseSans.otf"));_hint.add_theme_font_size_override("font_size",17);_hint.add_theme_color_override("font_color",Color("fff1ce"));_hint.add_theme_color_override("font_shadow_color",Color("101a30"));_hint.add_theme_constant_override("shadow_offset_x",2);_hint.add_theme_constant_override("shadow_offset_y",2);_layer.add_child(_hint)
 _cursor=Panel.new();_cursor.name="ControllerGridCursor";_cursor.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var border:=StyleBoxFlat.new();border.bg_color=Color(.3,.8,.9,.09);border.border_color=Color("ffca57");border.set_border_width_all(3);_cursor.add_theme_stylebox_override("panel",border);_layer.add_child(_cursor);_cursor.hide()
 synchronize()

func _install_actions() -> void:
 for action in ACTION_BUTTONS:
  var name_value:String="courier_"+action
  if not InputMap.has_action(name_value):InputMap.add_action(name_value)
  var event:=InputEventJoypadButton.new();event.device=-1;event.button_index=ACTION_BUTTONS[action]
  if not InputMap.action_has_event(name_value,event):InputMap.action_add_event(name_value,event)
 for action in ACTION_KEYS:
  var name_value:String="courier_"+action
  if not InputMap.has_action(name_value):InputMap.add_action(name_value)
  for code in ACTION_KEYS[action]:
   var event:=InputEventKey.new();event.physical_keycode=code
   if not InputMap.action_has_event(name_value,event):InputMap.action_add_event(name_value,event)

func desired_context() -> String:
 if not focused or not is_instance_valid(host) or host.closing:return "inactive"
 if host._dialogue_is_open():return "dialogue"
 if host._loading_scene_active():return "loading"
 if host.hud.is_blocking_modal():return "modal"
 if host.page=="flight":return "flight_paused" if host.paused else "flight"
 if host.has_method("_review_phone_is_open") and host._review_phone_is_open():return "phone"
 if host.has_method("_investigation_is_open") and host._investigation_is_open():return "investigation"
 if host.page=="hub":return "ui" if _hub_ui else "shop"
 if host.page=="workshop" and _grid:return "grid"
 return "ui"

func synchronize() -> void:
 if not is_instance_valid(host):return
 deadzone=clampf(float(host.settings.get("controller_deadzone",.22)),.10,.45)
 var page_changed:bool=_last_page!=host.page
 if page_changed:
  _last_page=host.page;_hub_ui=false;_grid=false
 var next:String=desired_context()
 if next==context and not page_changed:return
 context=next;quarantine()
 if context!="grid":host.workshop_input.controller_cancel()
 if controller_navigation and context in ["ui","modal","dialogue","flight_paused","phone","investigation"]:ensure_focus()

func quarantine() -> void:
 for token in _mouse:_blocked[token]=true
 for token in _keys:_blocked[token]=true
 for token in _buttons:_blocked[token]=true
 for token in _axes:
  if absf(float(_axes[token]))>deadzone:_blocked[token]=true
 _direction=Vector2i.ZERO;_repeat_left=0.0
 if is_instance_valid(host):host._clear_pilot_input()

func set_focus_active(value:bool) -> void:
 focused=value
 if not focused:controller_navigation=false
 quarantine();synchronize()
 # A key released outside the application may never send its release here.
 _keys.clear();_buttons.clear();_axes.clear();_mouse.clear()

func _joy_connection_changed(device:int,connected:bool) -> void:
 if connected:return
 var prefixes:Array=["b:%d:"%device,"a:%d:"%device]
 for state in [_buttons,_axes,_blocked]:
  for token in state.keys():
   if str(token).begins_with(prefixes[0]) or str(token).begins_with(prefixes[1]):state.erase(token);_blocked.erase(token)
 if active_device==device:
  active_device=-1;controller_navigation=false;quarantine()
  if is_instance_valid(host) and host.page=="flight":host._set_paused(true);host._checkpoint_flight();host.save_game()
  synchronize()

func _set_device(value:bool) -> void:
 if value==gamepad:return
 if _clock-_prompt_changed<PROMPT_HYSTERESIS:return
 gamepad=value;_prompt_changed=_clock
 if host.has_method("_investigation_is_open") and is_instance_valid(host.investigation):host.investigation.set_input_device(gamepad)
 if is_instance_valid(host.dialogue):host.dialogue.set_input_device(gamepad)
 if is_instance_valid(host.loading_overlay):host.loading_overlay.set_input_device(gamepad)
 if is_instance_valid(host.hud):host.hud.set_input_device(gamepad)

func _input(event:InputEvent) -> void:
 if not is_instance_valid(host):return
 synchronize()
 if event is InputEventJoypadButton or event is InputEventJoypadMotion:
  get_viewport().set_input_as_handled()
  observe_joy(event);return
 if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:
  var mouse_token:String="m:%d"%event.button_index
  if not event.pressed:
   _mouse.erase(mouse_token)
   if _blocked.has(mouse_token):_blocked.erase(mouse_token);get_viewport().set_input_as_handled();return
  else:
   _mouse[mouse_token]=true
   if not focused:_blocked[mouse_token]=true
   if _blocked.has(mouse_token):get_viewport().set_input_as_handled();return
 if event is InputEventKey:
  var code:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
  var token:String="k:%d"%code
  if context=="investigation":get_viewport().set_input_as_handled()
  if not event.pressed:_keys.erase(token);_blocked.erase(token);return
  if not focused:_blocked[token]=true;get_viewport().set_input_as_handled();return
  if event.echo or _keys.has(token):
   if _blocked.has(token) or context=="phone":get_viewport().set_input_as_handled()
   return
  _keys[token]=true
  if _blocked.has(token):get_viewport().set_input_as_handled();return
  controller_navigation=false;_set_device(false)
  if context=="phone":
   get_viewport().set_input_as_handled();_phone_key(code,event.shift_pressed);return
  if context=="investigation":
   if code in [KEY_E,KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_ESCAPE]:host.investigation.close()
   elif code==KEY_TAB:ensure_focus()
   return
  var editing:Control=get_viewport().gui_get_focus_owner()
  if code in [KEY_A,KEY_D] and context in ["ui","grid"] and not editing is LineEdit and not editing is TextEdit:
   if host.page!="hub":host.navigate("hub")
   _hub_ui=false;synchronize();_blocked.erase(token)
   if host.world.has_method("set_shop_input"):host.world.set_shop_input(0.0,true)
   get_viewport().set_input_as_handled();return
  if context=="shop" and code in [KEY_A,KEY_D,KEY_E,KEY_ENTER,KEY_KP_ENTER]:
   get_viewport().set_input_as_handled()
   if code in [KEY_E,KEY_ENTER,KEY_KP_ENTER]:_interact()
  elif context=="shop" and code==KEY_TAB:
   _hub_ui=true;synchronize();ensure_focus();get_viewport().set_input_as_handled()
  elif context=="ui" and host.page=="hub" and code==KEY_ESCAPE:
   _hub_ui=false;synchronize();get_viewport().set_input_as_handled()
 elif event is InputEventMouse and not focused:
  get_viewport().set_input_as_handled()
 elif event is InputEventMouseButton and event.pressed and focused:
  controller_navigation=false;_set_device(false)
  if _grid:_grid=false;host.workshop_input.controller_cancel();synchronize()

func observe_joy(event:InputEvent) -> void:
 var token:String=("b:" if event is InputEventJoypadButton else "a:")+"%d:%d"%[event.device,event.button_index if event is InputEventJoypadButton else event.axis]
 if event is InputEventJoypadMotion:
  _axes[token]=event.axis_value
  if absf(event.axis_value)<=deadzone:_blocked.erase(token)
  elif not focused:_blocked[token]=true
  elif absf(event.axis_value)>deadzone+.08:
   if active_device!=-1 and active_device!=event.device:quarantine()
   active_device=event.device
   if not _blocked.has(token):
    controller_navigation=true
    if absf(event.axis_value)>maxf(.40,deadzone+.10):_set_device(true)
  return
 if not event.pressed:_buttons.erase(token);_blocked.erase(token);return
 var fresh:bool=not _buttons.has(token)
 _buttons[token]=true
 if not focused:_blocked[token]=true;return
 if active_device!=-1 and active_device!=event.device:quarantine()
 active_device=event.device
 if not fresh or _blocked.has(token):return
 controller_navigation=true;_set_device(true)
 var action:String=""
 for candidate in ACTION_BUTTONS:
  if event.is_action_pressed("courier_"+candidate):action=candidate;break
 if not action.is_empty():_dispatch(action)
 synchronize()

func axis(axis_index:int) -> float:
 if not focused or active_device<0:return 0.0
 var token:String="a:%d:%d"%[active_device,axis_index]
 if _blocked.has(token):return 0.0
 var value:float=clampf(float(_axes.get(token,0.0)),-1.0,1.0)
 return 0.0 if absf(value)<=deadzone else signf(value)*(absf(value)-deadzone)/(1.0-deadzone)

func button(index:int) -> bool:
 var token:String="b:%d:%d"%[active_device,index]
 return focused and _buttons.has(token) and not _blocked.has(token)

func key(code:int) -> bool:
 var token:String="k:%d"%code
 return focused and _keys.has(token) and not _blocked.has(token)

func shop_axis() -> float:
 if context!="shop":return 0.0
 var digital:float=float(int(key(KEY_D))-int(key(KEY_A)))
 if not is_zero_approx(digital):return digital
 digital=float(int(button(JOY_BUTTON_DPAD_RIGHT))-int(button(JOY_BUTTON_DPAD_LEFT)))
 return digital if button(JOY_BUTTON_DPAD_RIGHT) or button(JOY_BUTTON_DPAD_LEFT) else axis(JOY_AXIS_LEFT_X)

func pilot_state() -> Dictionary:
 if context!="flight" or desired_context()!="flight" or not focused:return {"axis_q":0,"boost":false,"active":false}
 var digital:int=int(button(JOY_BUTTON_DPAD_DOWN))-int(button(JOY_BUTTON_DPAD_UP))
 return {"axis_q":digital*1000 if button(JOY_BUTTON_DPAD_DOWN) or button(JOY_BUTTON_DPAD_UP) else clampi(roundi(axis(JOY_AXIS_LEFT_Y)*1000),-1000,1000),"boost":button(JOY_BUTTON_RIGHT_SHOULDER),"active":button(JOY_BUTTON_A)}

func tick(delta:float) -> void:
 _clock+=maxf(0.0,delta);synchronize()
 if host.world.has_method("set_shop_input"):host.world.set_shop_input(shop_axis(),context=="shop")
 if context in ["ui","modal","dialogue","flight_paused","grid","phone","investigation"]:
  var direction:=Vector2i(int(button(JOY_BUTTON_DPAD_RIGHT))-int(button(JOY_BUTTON_DPAD_LEFT)),int(button(JOY_BUTTON_DPAD_DOWN))-int(button(JOY_BUTTON_DPAD_UP)))
  if direction==Vector2i.ZERO:
   var stick:=Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
   if stick.length()>.50:direction=Vector2i(int(signf(stick.x)),0) if absf(stick.x)>absf(stick.y) else Vector2i(0,int(signf(stick.y)))
  if direction!=_direction:
   _direction=direction;_repeat_left=REPEAT_DELAY
   if direction!=Vector2i.ZERO:_navigate(direction)
  elif direction!=Vector2i.ZERO:
   _repeat_left-=minf(delta,.10)
   if _repeat_left<=0:_repeat_left+=REPEAT_INTERVAL;_navigate(direction)
  if context=="grid":host.workshop_input.controller_pan(Vector2(axis(JOY_AXIS_RIGHT_X),axis(JOY_AXIS_RIGHT_Y))*minf(delta,.1))
  elif context in ["ui","modal","phone"]:_scroll_ui(axis(JOY_AXIS_RIGHT_Y)*minf(delta,.1)*650.0)
 _update_hint()

func _phone_key(code:int,shift:bool=false) -> void:
 match code:
  KEY_ESCAPE:host._close_review_phone()
  KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:activate_focus(host.review_phone.focus_root())
  KEY_UP:_navigate(Vector2i.UP)
  KEY_DOWN:_navigate(Vector2i.DOWN)
  KEY_LEFT:_navigate(Vector2i.LEFT)
  KEY_RIGHT:_navigate(Vector2i.RIGHT)
  KEY_PAGEUP:host.review_phone.scroll_by(-260.0)
  KEY_PAGEDOWN:host.review_phone.scroll_by(260.0)
  KEY_HOME:host.review_phone.scroll_to_edge(false)
  KEY_END:host.review_phone.scroll_to_edge(true)
  KEY_TAB:
   var candidates:Array[Control]=_focusables(_focus_root())
   if not candidates.is_empty():
    var current:Control=ensure_focus()
    _focus(candidates[posmod(candidates.find(current)+(-1 if shift else 1),candidates.size())])

func _scroll_ui(amount:float) -> void:
 if context=="phone":host.review_phone.scroll_by(amount);return
 if absf(amount)<.01:return
 var owner:Control=get_viewport().gui_get_focus_owner()
 var parent:Node=owner
 while parent!=null:
  if parent is ScrollContainer:parent.scroll_vertical+=roundi(amount);return
  parent=parent.get_parent()
 for scroll in host.hud.content.find_children("*","ScrollContainer",true,false):
  if scroll.is_visible_in_tree():scroll.scroll_vertical+=roundi(amount);return

func _dispatch(action:String) -> void:
 match context:
  "investigation":
   if action in ["confirm","back"]:host.investigation.close()
  "phone":
   if action=="back":host._close_review_phone()
   elif action=="confirm":activate_focus(host.review_phone.focus_root())
  "dialogue":
   if action=="confirm":activate_focus(host.dialogue._root)
   elif action=="back":host.dialogue.skip_conversation()
  "loading":
   if action in ["confirm","back"]:host.loading_overlay.request_skip()
  "modal":
   if action=="back":host.hud.controller_back()
   elif action=="confirm":activate_focus(host.hud.content)
  "shop":
   if action=="confirm":_interact()
   elif action=="menu":_hub_ui=true;synchronize()
  "flight":
   if action in ["menu","back"]:host._set_paused(true)
  "flight_paused":
   if action=="menu":host._set_paused(false)
   elif action=="confirm":activate_focus(host.hud.content)
   elif action=="back":host._set_paused(false)
  "grid":
   match action:
    "confirm":host.workshop_input.controller_confirm()
    "move":host.workshop_input.controller_pickup()
    "grid":host.rotate_part()
    "remove":host.remove_part();host.workshop_input.controller_cancel()
    "boost":host.undo_assembly();host.workshop_input.controller_cancel()
    "fit":host.workshop_input.fit()
    "part":host.workshop_input.controller_select_next()
    "back":
     if host.workshop_input.controller_moving():host.workshop_input.controller_cancel()
     else:_grid=false;synchronize()
    "menu":_grid=false;synchronize()
  "ui":
   if action=="confirm":activate_focus(host.hud.content)
   elif action=="back":
    if host.page=="hub":_hub_ui=false;synchronize()
    else:host.navigate("hub")
   elif action=="grid" and host.page=="workshop":
    _grid=true;host.workshop_input.controller_begin();synchronize()
   elif action=="menu":host.hud.settings_open=true;host.hud.render(host.hud.state)

func _interact() -> void:
 if not host.world.has_method("shop_interaction"):return
 var target:Dictionary=host.world.shop_interaction()
 if not target.is_empty() and bool(target.get("enabled",true)):host._action(str(target.id),null)

func _focus_root() -> Control:
 if context=="investigation":return host.investigation._root
 if context=="phone":return host.review_phone.focus_root()
 if context=="dialogue":return host.dialogue._root
 if context=="modal":
  for node in host.hud.content.get_children():
   if node is Control and node.has_meta("modal_panel"):return node
  var cancel_id:String=str(host.hud._cancel_confirmation_id)
  if not cancel_id.is_empty():
   for node in host.hud.content.find_children("*","Button",true,false):
    if str(node.get_meta("view_key",""))=="cancel:"+cancel_id:return node
 return host.hud.content

func _focusables(root:Node) -> Array[Control]:
 var result:Array[Control]=[]
 var children:Array=root.find_children("*","Control",true,false)
 if root is BaseButton:children.push_front(root)
 for child in children:
  if not child.is_visible_in_tree() or child.focus_mode==Control.FOCUS_NONE:continue
  if child is BaseButton and child.disabled:continue
  if child is LineEdit and child.get_parent() is SpinBox:
   if not result.has(child.get_parent()):result.append(child.get_parent())
  elif child is BaseButton or child is Range or child is LineEdit or (context=="phone" and child.has_meta("phone_review")):result.append(child)
 return result

func ensure_focus() -> Control:
 var root:Control=_focus_root();var candidates:Array[Control]=_focusables(root)
 var owner:Control=get_viewport().gui_get_focus_owner()
 if owner is LineEdit and owner.get_parent() is SpinBox:owner=owner.get_parent()
 if is_instance_valid(owner) and owner in candidates:return owner
 if candidates.is_empty():return null
 # First modal focus was explicitly chosen by GameHUD (safe cancel).
 _focus(candidates[0]);return candidates[0]

func _focus(control:Control) -> void:
 if control is SpinBox:control.get_line_edit().grab_focus()
 else:control.grab_focus()
 var parent:Node=control.get_parent()
 while parent!=null:
  if parent is ScrollContainer:parent.ensure_control_visible(control)
  parent=parent.get_parent()

func _navigate(direction:Vector2i) -> void:
 if context=="grid":host.workshop_input.controller_step(direction);return
 var current:Control=ensure_focus()
 if current==null:return
 if direction.x!=0 and _adjust(current,direction.x):return
 var origin:Vector2=current.get_global_rect().get_center();var target:Control=null;var best:float=INF
 for candidate in _focusables(_focus_root()):
  if candidate==current:continue
  var offset:Vector2=candidate.get_global_rect().get_center()-origin
  var forward:float=offset.dot(Vector2(direction))
  if forward<=2:continue
  var sideways:float=absf(offset.cross(Vector2(direction)))
  var score:float=forward+sideways*3.0
  if score<best:best=score;target=candidate
 if target!=null:_focus(target)

func _adjust(control:Control,direction:int) -> bool:
 if control is OptionButton:
  var count:int=control.item_count
  if count==0:return true
  var next:int=posmod(control.selected+direction,count)
  for unused in count:
   if not control.is_item_disabled(next):break
   next=posmod(next+direction,count)
  control.select(next);control.item_selected.emit(next);return true
 if control is Range:
  control.value=clampf(control.value+direction*maxf(control.step,.01),control.min_value,control.max_value);return true
 return false

func activate_focus(root:Control) -> void:
 var owner:Control=ensure_focus()
 if owner==null or (owner!=root and not root.is_ancestor_of(owner)):return
 if owner is OptionButton:_adjust(owner,1)
 elif owner is BaseButton and not owner.disabled:
  if owner.toggle_mode:owner.button_pressed=not owner.button_pressed
  owner.pressed.emit()

func _update_hint() -> void:
 var frame:Rect2=host.view_container.display_rect
 var ui_scale:int=clampi(floori(frame.size.y/720.0),1,3)
 _hint.scale=Vector2.ONE*ui_scale;_hint.position=(frame.position+Vector2(24*ui_scale,frame.size.y-23*ui_scale)).round()
 _hint.size=Vector2(maxf(1,frame.size.x/float(ui_scale)-48),22);_hint.clip_text=true
 _hint.add_theme_font_size_override("font_size",14);_hint.text="";_cursor.hide()
 if context=="shop":
  var target:Dictionary=host.world.shop_interaction() if host.world.has_method("shop_interaction") else {}
  if not target.is_empty() and bool(target.get("enabled",true)):
   var label:String="前台" if str(target.id)=="focus_counter" else str(target.get("label",""))
   _hint.text=("A " if gamepad else "E ")+label
 elif gamepad and context in ["ui","modal","flight_paused"]:
  _hint.text="方向 选择  ·  A 确认  ·  B 返回"+("  ·  X 网格" if host.page=="workshop" and context=="ui" else "")
 elif gamepad and context=="grid":
  _hint.text="A 选 / 放  ·  Y 搬动  ·  X 旋转  ·  LB 拆除  ·  RB 撤销  ·  R3 全景  ·  B 菜单"
  if host.workshop_input.controller_moving():
   var chosen:Dictionary=host.selected_part()
   var label:String=str(host.catalog.get(str(chosen.get("type","")),{}).get("name","零件"))
   _hint.text=label+"  ·  A 放置  ·  B 取消搬动"
  var rect:Rect2=host.workshop_input.controller_cursor_rect()
  _cursor.position=rect.position;_cursor.size=rect.size;_cursor.visible=rect.has_area()

func _exit_tree() -> void:
 if Input.joy_connection_changed.is_connected(_joy_connection_changed):Input.joy_connection_changed.disconnect(_joy_connection_changed)

func debug_snapshot() -> Dictionary:
 return {"context":context,"device":"gamepad" if gamepad else "keyboard_mouse","focused":focused,"controller_navigation":controller_navigation,"active_device":active_device,"connected_devices":Input.get_connected_joypads(),"deadzone":deadzone,"held_keys":_keys.keys(),"held_buttons":_buttons.keys(),"fresh_release_barrier":_blocked.keys(),"shop_axis":shop_axis(),"pilot":pilot_state(),"grid_mode":_grid,"grid_cell":host.workshop_input.controller_cell,"grid_moving":host.workshop_input.controller_moving(),"ui_navigation":_hub_ui,"repeat_direction":_direction,"hint_rect":Rect2(_hint.global_position,_hint.size*_hint.scale),"hint_scale":_hint.scale.x,"hint_text":_hint.text,"cursor_rect":_cursor.get_global_rect(),"cursor_visible":_cursor.visible}
