extends CanvasLayer
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
## Scene-first presentation. Domain state lives in main; this layer emits intent only.
## Every full-viewport container ignores mouse events. Only visible controls capture them.
signal action_requested(action: String, payload: Variant)

const INK := Color("101a30")
const PANEL := Color("17243a")
const PANEL_LIGHT := Color("253b58")
const EDGE := Color("7588a2")
const DIM := Color("a8b8cb")
const BLUE := Color("2f527a")
const TEAL := Color("49cce5")
const CREAM := Color("f7e9c7")
const YELLOW := Color("ffca57")
const CORAL := Color("ee7863")
const WHITE := Color("fff3d7")
const MUTED := Color("52647c")
var root: Control
var content: Control
var toast_panel: PanelContainer
var toast_label: Label
var toast_timer: float = 0.0
var _toast_raw_text: String = ""
var state: Dictionary = {}
var mode: String = "hub"
var palette_open: bool = true
var palette_category: String = "现有库存"
var report_costs_open: bool = false
var settings_open: bool = false
var flight_labels: Dictionary = {}
var progress_bar: ProgressBar
var _pause_button: WeakRef
var _size: Vector2 = Vector2(1440, 900)
var _art_frame: Rect2 = Rect2()
var _art_frame_enabled: bool = false
var _ui_scale: int = 1
var _built: bool = false
var _last_mode: String = ""
var _cancel_confirmation_id: String = ""
var _hotspot_layer: Control
var _hotspot_buttons: Dictionary = {}
var dispatch_confirmation_open: bool = false
var _dispatch_contract_id: String = ""
var _motion_tweens: Dictionary = {}
var _last_selection_id: int = -999
var _gamepad:bool=false
var _last_modal: String = ""
var _launch_layer: Control
var _launch_title: Label
var _launch_meter: ProgressBar
var _launch_phase: String = ""
var _launch_dismissing: bool = false
var _render_generation: int = 0
var _scroll_memory: Dictionary = {}
var _modal_return_focus: String = ""
var _missing_icon_reports: Dictionary = {}
var _ascent_cue: Control
var _ascent_telemetry: Dictionary = {}
var _impact_absorbed: float = 0.0
var _impact_energy: float = 0.0
var _impact_cue_until: float = -1.0
var _extreme_elapsed: float = 0.0


class MotionAccent extends Control:
 var ink:=Color("142042")
 var teal:=Color("35d4d2")
 var cream:=Color("fff0bd")
 func _draw() -> void:
  var w:=size.x
  draw_colored_polygon(PackedVector2Array([Vector2(0,26),Vector2(w-35,0),Vector2(w,32),Vector2(0,72)]),ink)
  draw_colored_polygon(PackedVector2Array([Vector2(0,31),Vector2(w-67,11),Vector2(w-41,33),Vector2(0,59)]),teal)
  for i in 3:
   var x:=w-18+float(i)*17
   draw_colored_polygon(PackedVector2Array([Vector2(x,10),Vector2(x+6,9),Vector2(x+27,36),Vector2(x+21,37)]),cream)

class LaunchRibbon extends Control:
 var phase: String = "charge"
 func _draw() -> void:
  var ink:=Color("101a30");var cream:=Color("f4e6bd")
  var accent:=Color("ee7863") if phase=="ignition" else Color("49cce5")
  draw_colored_polygon(PackedVector2Array([Vector2(0,8),Vector2(452,8),Vector2(452,16),Vector2(464,16),Vector2(464,100),Vector2(456,100),Vector2(456,108),Vector2(8,108),Vector2(8,100),Vector2(0,100)]),ink)
  draw_rect(Rect2(4,12,452,4),accent)
  draw_rect(Rect2(4,34,452,50),cream)
  draw_rect(Rect2(4,84,452,4),accent)
  for x in range(420,448,8):draw_rect(Rect2(x,20,4,12),accent)


func _ready() -> void:
 layer = 10
 _build_root()
 get_viewport().size_changed.connect(_on_resize)
 if not state.is_empty():render(state)

func _build_root() -> void:
 if _built:return
 _built = true
 root = Control.new();root.name = "SceneHUD";root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter = Control.MOUSE_FILTER_IGNORE;root.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(root)
 root.theme = _make_theme()
 content = Control.new();content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.mouse_filter = Control.MOUSE_FILTER_IGNORE;root.add_child(content)
 toast_panel = PanelContainer.new();toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE;toast_panel.add_theme_stylebox_override("panel", _style(YELLOW, 3, 12));root.add_child(toast_panel)
 toast_label = _label(toast_panel, "", 16);toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
 toast_panel.hide()
 _apply_art_frame()

func set_art_frame(rect: Rect2) -> void:
 # Physical viewport coordinates; bounds/input stay tied to this rectangle.
 # Framed HUD uses an integer1x/2x/3x scale at720/1440/2160-high art frames.
 # _size is its local logical size. The caller renders state after updating
 # the stage. Empty/invalid sizes restore the unscaled legacy viewport HUD.
 _art_frame_enabled=rect.size.x>0.0 and rect.size.y>0.0
 _art_frame=Rect2(rect.position.round(),rect.size.round()) if _art_frame_enabled else Rect2()
 if _art_frame_enabled and (_art_frame.size.x<=0.0 or _art_frame.size.y<=0.0):_art_frame_enabled=false;_art_frame=Rect2()
 if _built:_apply_art_frame()

func _apply_art_frame() -> void:
 if not _built:return
 _ui_scale=clampi(floori(_art_frame.size.y/720.0),1,3) if _art_frame_enabled else 1
 root.scale=Vector2.ONE*float(_ui_scale)
 root.clip_contents=_art_frame_enabled
 if _art_frame_enabled:
  root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
  root.position=_art_frame.position
  _size=_art_frame.size/float(_ui_scale);root.size=_size
 else:
  root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  root.position=Vector2.ZERO
  _size=get_viewport().get_visible_rect().size

func _make_theme() -> Theme:
 var t := Theme.new();t.default_font = load("res://assets/fonts/ChineseSans.otf");t.default_font_size = 16
 for kind in ["Label","Button","OptionButton","LineEdit","CheckButton","SpinBox"]:
  t.set_color("font_color",kind,WHITE);t.set_color("font_hover_color",kind,INK);t.set_color("font_pressed_color",kind,INK)
 t.set_color("font_disabled_color","Button",DIM)
 for kind in ["Button","OptionButton"]:
  t.set_stylebox("normal",kind,_style(PANEL_LIGHT,2,8,false))
  t.set_stylebox("hover",kind,_style(YELLOW,2,8,false))
  t.set_stylebox("pressed",kind,_style(TEAL,2,8,false))
  t.set_stylebox("disabled",kind,_style(Color("394454"),2,8,false))
  t.set_stylebox("focus",kind,_focus_style())
 t.set_stylebox("normal","LineEdit",_style(INK,2,8,false));t.set_color("font_color","LineEdit",WHITE)
 t.set_color("font_selected_color","LineEdit",INK);t.set_color("selection_color","LineEdit",TEAL)
 t.set_stylebox("panel","PopupMenu",_style(PANEL,2,8,false));t.set_color("font_color","PopupMenu",WHITE);t.set_color("font_hover_color","PopupMenu",INK);t.set_stylebox("hover","PopupMenu",_style(YELLOW,0,6,false))
 t.set_stylebox("background","ProgressBar",_style(INK,0,0,false));t.set_stylebox("fill","ProgressBar",_style(TEAL,0,0,false))
 for kind in ["HScrollBar","VScrollBar"]:
  var rail:=_style(INK,0,0,false);rail.content_margin_left=5;rail.content_margin_top=5;t.set_stylebox("scroll",kind,rail)
  for style_name in ["grabber","grabber_highlight","grabber_pressed"]:
   var thumb:=_style(TEAL if style_name!="grabber" else EDGE,0,0,false);thumb.content_margin_left=5;thumb.content_margin_top=5;t.set_stylebox(style_name,kind,thumb)
 return t

func _style(fill: Color, border: int = 2, pad: int = 12, shadow: bool = true) -> StyleBoxFlat:
 var s := StyleBoxFlat.new();s.bg_color = fill;s.border_color = EDGE if fill.get_luminance()<.42 else INK;s.set_border_width_all(mini(border,2));s.set_corner_radius_all(0);s.corner_radius_top_right=6;s.corner_radius_bottom_left=6;s.corner_detail=1;s.anti_aliasing=false
 s.content_margin_left=pad;s.content_margin_right=pad;s.content_margin_top=pad;s.content_margin_bottom=pad
 if shadow:s.shadow_color=Color(0.04,0.07,0.13,.65);s.shadow_size=2;s.shadow_offset=Vector2(3,4)
 return s

func _focus_style() -> StyleBoxFlat:
 var s:=StyleBoxFlat.new();s.bg_color=Color.TRANSPARENT;s.border_color=CORAL;s.set_border_width_all(3);s.expand_margin_left=3;s.expand_margin_right=3;s.expand_margin_top=3;s.expand_margin_bottom=3
 return s

func _on_resize() -> void:
 if not _built:return
 _apply_art_frame()
 if not state.is_empty():render(state)

func render(data: Dictionary) -> void:
 var preserved:=_capture_ui_state() if _built and str(data.get("mode","hub"))==mode else {}
 state = data.duplicate(true)
 if not is_inside_tree():return
 _render_generation+=1
 _build_root()
 _apply_art_frame()
 mode = str(state.get("mode", "hub"))
 var incoming_selection:=int(state.get("selectedpart",state.get("selected_part",{})).get("id",-1))
 if mode=="workshop" and incoming_selection>=0 and (incoming_selection!=_last_selection_id or _last_mode!="workshop"):palette_open=false
 if mode!=_last_mode:toast_panel.hide();toast_timer=0
 if not _cancel_confirmation_id.is_empty():
  var order:Dictionary=state.get("activeorder",{})
  if mode!=_last_mode or not _has_accepted() or str(order.get("contract_id",order.get("id","accepted")))!=_cancel_confirmation_id:_cancel_confirmation_id=""
 _stop_motion()
 _launch_layer=null;_launch_phase="";_launch_dismissing=false
 _hotspot_layer=null;_hotspot_buttons.clear()
 for child in content.get_children():content.remove_child(child);child.queue_free()
 flight_labels.clear();progress_bar = null;_pause_button=null
 _ascent_cue=null;_ascent_telemetry.clear()
 _impact_absorbed=0;_impact_energy=0;_impact_cue_until=-1;_extreme_elapsed=0
 if mode == "flight":
  _flight()
 else:
  _shop_status()
  if mode in ["hub","workshop"]:_ticket()
  match mode:
   "hub":_home()
   "contracts":_contracts()
   "workshop":_workshop()
   "supply":_supply()
   "report":_report()
   "help":_help()
   _:_home()
 if dispatch_confirmation_open:_dispatch_confirmation()
 if settings_open:_settings()
 _wire_motion_feedback(content)
 if mode != _last_mode:
  _animate_mode_entry()
  _last_mode=mode
 else:
  var selected_id:=int(state.get("selectedpart",state.get("selected_part",{})).get("id",-1))
  if mode=="workshop" and selected_id!=_last_selection_id:
   for node in content.get_children():
    if node.has_meta("context_panel"):_enter_panel(node,Vector2(28,0),0,.18)
 var modal:="settings" if settings_open else "dispatch" if dispatch_confirmation_open else ""
 if not modal.is_empty() and modal!=_last_modal:
  for node in content.get_children():
   if node.has_meta("modal_panel"):_enter_panel(node,Vector2(-32,14),0,.21)
 _apply_modal_focus(modal,preserved)
 _restore_ui_state.call_deferred(preserved,_render_generation,modal)
 _last_modal=modal
 _last_selection_id=int(state.get("selectedpart",state.get("selected_part",{})).get("id",-1))
 _position_toast()

func _view_key(node: Node) -> String:
 if node==null:return ""
 if node.has_meta("view_key"):return str(node.get_meta("view_key"))
 if node is LineEdit and node.get_parent() is SpinBox:return _view_key(node.get_parent())+":edit"
 return ""

func _capture_ui_state() -> Dictionary:
 var owner:=get_viewport().gui_get_focus_owner()
 var saved:={"focus":_view_key(owner),"modal":_last_modal}
 for node in content.find_children("*","ScrollContainer",true,false):
  var key:=_view_key(node)
  if not key.is_empty():_scroll_memory[key]=Vector2i(node.scroll_horizontal,node.scroll_vertical)
 while _scroll_memory.size()>48:_scroll_memory.erase(_scroll_memory.keys()[0])
 if owner is LineEdit:
  saved["edit"]={"text":owner.text,"caret":owner.caret_column,"from":owner.get_selection_from_column(),"to":owner.get_selection_to_column(),"selected":owner.has_selection()}
 return saved

func _apply_modal_focus(modal: String, saved: Dictionary) -> void:
 if modal.is_empty():return
 var panel:Control
 for node in content.get_children():
  if node.has_meta("modal_panel"):panel=node
 if panel==null:return
 if _last_modal.is_empty():_modal_return_focus=str(saved.get("focus",""))
 for node in content.find_children("*","Control",true,false):
  if not panel.is_ancestor_of(node) and node!=panel:node.focus_mode=Control.FOCUS_NONE
 # The first keyboard action after opening can only dismiss the sheet, never
 # dispatch cargo. Background controls are excluded from Tab navigation.
 for node in panel.find_children("*","Button",true,false):
  if node.has_meta("safe_modal_default"):node.grab_focus();break

func _restore_ui_state(saved: Dictionary, generation: int, modal: String) -> void:
 if not is_inside_tree() or generation!=_render_generation:return
 # Container bounds must settle before restoring a clipped scroll offset.
 await get_tree().process_frame
 if not is_inside_tree() or generation!=_render_generation:return
 var focus_key:=str(saved.get("focus",""))
 if str(saved.get("modal",""))!=modal:
  if modal.is_empty():focus_key=_modal_return_focus;_modal_return_focus=""
  else:focus_key=""
 for node in content.find_children("*","Control",true,false):
  var key:=_view_key(node)
  if node is ScrollContainer and _scroll_memory.has(key):
   var offset:Vector2i=_scroll_memory[key];node.scroll_horizontal=offset.x;node.scroll_vertical=offset.y
  if key.is_empty() or key!=focus_key or node.focus_mode==Control.FOCUS_NONE:continue
  node.grab_focus()
  if node is LineEdit and saved.has("edit"):
   _restore_edit.call_deferred(node,saved.edit,generation)

func _restore_edit(editor: LineEdit, edit: Dictionary, generation: int) -> void:
 # SpinBox schedules its own focus-enter formatting. Apply the unfinished
 # text after that internal update, without committing or emitting a change.
 await get_tree().process_frame
 if generation!=_render_generation or not is_instance_valid(editor) or not editor.has_focus():return
 editor.text=str(edit.text);editor.caret_column=int(edit.caret)
 if bool(edit.selected):editor.select(int(edit.from),int(edit.to))

func _position_toast() -> void:
 if is_instance_valid(toast_panel):
  var y:=_size.y-156
  var x:=maxf(20,(_size.x-640)*.5)
  var width:=minf(640,_size.x-40)
  if mode=="workshop":
   width=minf(620,_size.x-376);x=20;y=_size.y-298 if palette_open else _size.y-144
  elif mode=="hub":x=20;width=minf(512,_size.x-40);y=88
  elif mode in ["contracts","supply","help"]:x=20;width=minf(512,_size.x-504);y=124
  toast_label.text=_wrap_toast(_toast_raw_text,maxf(80,width-28))
  toast_panel.position=Vector2(x,y);toast_panel.size=Vector2(width,58)

func _wrap_toast(text: String, width: float) -> String:
 var font:=root.theme.default_font
 var lines:Array[String]=[];var line:=""
 for character in text:
  if character=="\n":lines.append(line);line="";continue
  if not line.is_empty() and font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x>width:
   lines.append(line);line=character
  else:line+=character
 if not line.is_empty():lines.append(line)
 return "\n".join(lines)

func _panel(rect: Rect2, fill: Color = CREAM, parent: Node = null, pad: int = 16) -> PanelContainer:
 var p:=PanelContainer.new();p.position=rect.position;p.size=rect.size;p.mouse_filter=Control.MOUSE_FILTER_STOP;p.add_theme_stylebox_override("panel",_style(fill,3,pad));(content if parent==null else parent).add_child(p)
 return p

func _box(parent: Node, gap: int = 8) -> VBoxContainer:
 var b:=VBoxContainer.new();b.add_theme_constant_override("separation",gap);b.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(b);return b

func _row(parent: Node, gap: int = 8) -> HBoxContainer:
 var b:=HBoxContainer.new();b.add_theme_constant_override("separation",gap);b.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(b);return b

func _label(parent: Node, text: String, font_size: int = 16, color: Color = INK) -> Label:
 var l:=Label.new();l.text=text;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",_surface_text(parent,color));l.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(l);return l

func _surface_text(parent: Node, color: Color) -> Color:
 # Small paper receipts keep ink; dark metal HUD surfaces use light type.
 var node:=parent
 while node!=null and node!=content:
  if node is PanelContainer or node is Button:
   var box:StyleBoxFlat=node.get_theme_stylebox("panel" if node is PanelContainer else "normal") as StyleBoxFlat
   if box!=null:
    if box.bg_color.get_luminance()<.42:
     if color==INK:return WHITE
     if color==BLUE:return TEAL
     if color==MUTED:return DIM
    return color
  node=node.get_parent()
 return color

func _para(parent: Node, text: String, font_size: int = 15, color: Color = INK) -> Label:
 var l:=_label(parent,text,font_size,color);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return l

func _button(parent: Node, text: String, action: String, payload: Variant = null, fill: Color = PANEL_LIGHT, height: int = 40) -> Button:
 var b:=Button.new();b.text=text;b.custom_minimum_size.y=height;b.add_theme_stylebox_override("normal",_style(fill,2,8,false));b.add_theme_color_override("font_color",WHITE if fill.get_luminance()<.42 else INK);b.pressed.connect(func():_act(action,payload));b.set_meta("view_key","action:"+action+":"+JSON.stringify(payload));parent.add_child(b);return b

func _act(action: String, payload: Variant = null) -> void:
 if action=="dispatch":
  var order:Dictionary=state.get("activeorder",{})
  if not _has_order_details(order):toast("先到委托柜台，接下一份托付。","warning");return
  toast_panel.hide();toast_timer=0
  dispatch_confirmation_open=true;_dispatch_contract_id=str(order.get("contract_id",order.get("id","")));render(state);return
 if action in ["set_param","set_input"] and payload is Dictionary:
  var selected:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
  if int(selected.get("id",-1))==int(payload.get("id",-2)):
   var key:="param" if action=="set_param" else str(payload.get("key","input_a"))
   selected[key]=payload.get("value",0) if action=="set_param" else payload.get("source",-1)
 if action=="settings" and payload is Dictionary:
  var preferences:Dictionary=state.get("settings",{})
  for key in ["volume","reduced_motion","motion_blur","quality","pixel_density","controller_deadzone"]:
   if payload.has(key):preferences[key]=payload[key]
  state["settings"]=preferences
 action_requested.emit(action,payload)

func _rule(parent: Node) -> void:
 var r:=ColorRect.new();r.color=_surface_text(parent,MUTED);r.custom_minimum_size.y=1;r.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(r)

func _spacer(parent: Node) -> void:
 var c:=Control.new();c.size_flags_horizontal=Control.SIZE_EXPAND_FILL;c.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(c)

func _scroll(parent: Node) -> VBoxContainer:
 var s:=ScrollContainer.new();s.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;s.size_flags_vertical=Control.SIZE_EXPAND_FILL;s.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(s)
 s.set_meta("view_key","scroll:"+mode+":"+str(content.find_children("*","ScrollContainer",true,false).size()))
 var b:=_box(s,10);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return b

func _shop_status() -> void:
 var p:=_panel(Rect2(20,20,344,44),PANEL,null,8)
 p.name="DayLedger"
 var frame:=p.get_theme_stylebox("panel") as StyleBoxFlat;frame.border_width_bottom=3;frame.border_color=EDGE
 var row:=_row(p,12)
 _label(row,"DAY %02d"%int(state.get("day",1)),18,WHITE)
 _label(row,"|",17,EDGE)
 _label(row,"¥ %s"%str(state.get("credits",0)),20,YELLOW)
 _spacer(row)
 var phase:=str(state.get("phase","morning"))
 _label(row,"夜间" if phase in ["night","evening"] else "营业中",13,TEAL)
 var rep:=_label(row,"★ %d"%int(state.get("reputation",0)),13,DIM);rep.tooltip_text="店铺信誉"
 var util:=HBoxContainer.new();util.position=Vector2(372,24);util.add_theme_constant_override("separation",8);content.add_child(util)
 var help:=_button(util,"?","help",null,PANEL,36);help.custom_minimum_size.x=36;help.tooltip_text="航行手册"
 var settings:=_button(util,"≡","_settings",null,PANEL,36);settings.custom_minimum_size.x=36;settings.tooltip_text="设置"
 settings.pressed.disconnect(settings.pressed.get_connections()[0].callable)
 settings.pressed.connect(func():settings_open=not settings_open;toast_panel.hide();toast_timer=0;render(state))
 if mode!="hub":
  var back:=_button(content,"‹  返回店铺","close_drawer",null,PANEL,36);back.position=Vector2(20,76);back.size=Vector2(136,36)

func _has_order_details(order: Dictionary) -> bool:
 return order.has("name") and order.has("distance") and not str(order.get("name","")).is_empty()

func _ticket() -> void:
 var order:Dictionary=state.get("activeorder",{})
 var w:=252.0
 var has_order:=_has_order_details(order)
 var p:=_panel(Rect2(_size.x-w-20,20,w,120 if has_order else 76),CREAM,null,10)
 p.name="CurrentWaybill"
 var paper:=p.get_theme_stylebox("panel") as StyleBoxFlat;paper.border_width_left=4;paper.border_color=YELLOW
 var b:=_box(p,2)
 if not has_order:
  var phase:=str(state.get("phase","morning"))
  _label(b,"ORDER / 本趟委托",11,BLUE)
  if phase in ["night","evening"]:_label(b,"补好库存，准备明天。",16)
  elif state.get("contracts",[]).is_empty():_label(b,"今天的信，都处理好了。",16)
  else:_label(b,"柜台前，有人在等你。",16)
  return
 var r:=_row(b,4);_label(r,"ORDER / 本趟委托",11,BLUE);_spacer(r)
 if _has_accepted():_cancel_button(r,order,24)
 _label(b,str(order.name),19)
 _label(b,"%s · %s m"%[str(order.get("cargo","")),str(order.distance)],12,MUTED)
 var bottom:=_row(b,4)
 if order.has("required"):_label(bottom,"完整度 ≥ %s%%"%str(order.required),11,BLUE)
 _spacer(bottom)
 if order.has("deadline"):_label(bottom,"时限 %s s"%str(order.deadline),11,BLUE)

func _home() -> void:
 # Keep the storefront, characters and ship unobstructed. These are the only
 # hub navigation controls; projected labels no longer duplicate the dock.
 var y:=_size.y-68
 var w:=164.0
 _scene_action(Rect2(20,y,w,48),"cargo","委托柜台","接下今天的托付","focus_counter",YELLOW)
 _scene_action(Rect2(20+w+8,y,w,48),"beam","装配工位","装配与免费试飞","focus_workbench",TEAL)
 _scene_action(Rect2(20+(w+8)*2,y,w,48),"battery","补给与打烊","采购、研究，准备明天","focus_supply",CORAL)

func _scene_action(rect: Rect2, glyph: String, title: String, subtitle: String, action: String, accent: Color) -> void:
 var b:=Button.new();b.position=rect.position;b.size=rect.size;b.tooltip_text=subtitle
 var style:=_style(PANEL,2,8,false);style.border_color=accent;style.corner_radius_top_right=8;style.corner_radius_bottom_left=8;b.add_theme_stylebox_override("normal",style)
 var hover:=_style(PANEL_LIGHT,2,8,false);hover.border_color=accent;hover.corner_radius_top_right=8;hover.corner_radius_bottom_left=8;b.add_theme_stylebox_override("hover",hover);b.add_theme_stylebox_override("pressed",hover.duplicate())
 b.pressed.connect(func():_act(action));content.add_child(b)
 var icon:=_part_icon(b,glyph,Vector2(28,28));icon.position=Vector2(12,8);icon.size=Vector2(28,28)
 var title_label:=_label(b,title,17,WHITE);title_label.position=Vector2(48,10)
 var line:=ColorRect.new();line.color=accent;line.position=Vector2(2,44);line.size=Vector2(rect.size.x-4,4);line.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(line)

func _hotspots() -> void:
 pass

func update_hotspots(_spots: Variant) -> void:
 # Main still supplies these for compatibility; the compact hub dock owns
 # navigation so no floating button overlaps a person, parcel or aircraft.
 pass

func _has_accepted() -> bool:
 return bool(state.get("has_accepted_contract",state.get("activeorder",{}).get("accepted",false)))

func _cancel_button(parent: Node, order: Dictionary, height: int = 37) -> Button:
 var id:=str(order.get("contract_id",order.get("id","accepted")))
 var confirming:=_cancel_confirmation_id==id
 var btn:=Button.new();btn.set_meta("view_key","cancel:"+id);btn.text="确认取消？" if confirming else "取消委托";btn.custom_minimum_size.y=height;btn.add_theme_font_size_override("font_size",11 if height<32 else 14);btn.add_theme_stylebox_override("normal",_style(CORAL if confirming else WHITE,2,4,false));btn.add_theme_color_override("font_color",INK);parent.add_child(btn)
 btn.tooltip_text=str(state.get("cancel_warning","取消后将放弃本单。请确认是否继续。"))
 btn.pressed.connect(func():
  if _cancel_confirmation_id==id:
   _cancel_confirmation_id="";toast_panel.hide();toast_timer=0;_act("cancel_contract",id)
  else:
   _cancel_confirmation_id=id;render(state);toast(str(state.get("cancel_warning","确定放弃这份委托吗？再次点击「确认取消」才会取消。")),"warning")
 )
 return btn

func _drawer(title: String, kicker: String, width: float = 424, height_hint: float = 0) -> VBoxContainer:
 var height:=minf(_size.y-104,height_hint) if height_hint>0 else _size.y-104
 var p:=_panel(Rect2(_size.x-width-20,84,width,height),PANEL,null,12)
 p.name="SceneDrawer"
 var border:=p.get_theme_stylebox("panel") as StyleBoxFlat;border.border_width_top=3;border.border_color=TEAL
 var b:=_box(p,10)
 var head:=_row(b,4);var titles:=_box(head,2);titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _label(titles,kicker,11,TEAL);var heading:=_label(titles,title,20,WHITE);heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 _button(head,"×","close_drawer",null,PANEL_LIGHT,32).custom_minimum_size.x=32
 _rule(b)
 return b

func _contracts() -> void:
 var b:=_drawer("今天的托付，等你送达。","COUNTER / 委托柜台",424,minf(794,130+float(state.get("contracts",[]).size())*332))
 var summary:=_row(b);_label(summary,"挑一条航线，接下这一份心意。",13,DIM);_spacer(summary)
 var orders:Array=state.get("contracts",[])
 _label(summary,"%02d 份"%orders.size(),12,TEAL)
 var body:=_scroll(b);body.get_parent().name="ContractList"
 var serial:=0
 for order in orders:
  serial+=1
  var locked:bool=bool(order.get("locked",int(state.get("reputation",0))<int(order.get("rep",0))))
  var card:=PanelContainer.new();card.name="Waybill%d"%serial
  var paper:=_style(CREAM if not locked else Color("c7c5b4"),1,12,false);paper.border_width_top=4;paper.border_color=YELLOW if not locked else EDGE;card.add_theme_stylebox_override("panel",paper);body.add_child(card)
  var cb:=_box(card,7)
  var stub:=_row(cb);_label(stub,"托运单  /  %02d"%serial,11,BLUE);_spacer(stub);_label(stub,"待接取" if not locked else "未解锁",11,BLUE)
  var row:=_row(cb);var name:=_label(row,str(order.get("name","未命名航线")),22);name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _label(row,"¥ %s"%str(order.get("reward",0)),23,BLUE)
  _para(cb,str(order.get("client",""))+" · "+str(order.get("cargo","")),14)
  _para(cb,"“"+str(order.get("story","这一份心意，就拜托你了。"))+"”",13,MUTED)
  _rule(cb)
  var weight:=float(order.get("weight",1.0))*3.0
  var meta:="%s m  /  %.1f kg  /  完整度 %s%%"%[order.get("distance",0),weight,order.get("required",90)]
  _label(cb,meta,13,BLUE)
  _para(cb,"奖励时限 %s s · 最迟 %s s"%[order.get("deadline",0),order.get("time_limit",order.get("deadline",0))],13,BLUE)
  _para(cb,"投递半径 %s m · 到达速度 ≤ %s m/s"%[str(order.get("delivery_radius","—")),str(order.get("max_delivery_speed","—"))],11,MUTED)
  if order.has("risk"):_para(cb,"注意  "+str(order.risk),12,Color("a13f3e"))
  var choice_row:=_row(cb,8)
  var contract_id:Variant=order.get("contract_id",order.get("id",0))
  var go:=_button(choice_row,"需要声望 %s"%str(order.get("rep",0)) if locked else "接下这单  →","accept_contract",contract_id,YELLOW,42);go.disabled=locked;go.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  var decline:=_button(choice_row,"婉拒","decline_contract",contract_id,WHITE,42);decline.tooltip_text="婉拒未接受的委托，不产生违约处罚。"

func workshop_scene_rect() -> Rect2:
 # Screen coordinates, matching PixelStage's art-frame mapping. Leave current
 # controls visible and fit the WHOLE grid inside the genuinely usable region.
 var top:float=238.0 if not str(state.get("ship_stats",{}).get("warning","")).is_empty() else 176.0
 var bottom:float=_size.y-(244.0 if palette_open else 84.0)
 var local_rect:Rect2=Rect2(20,top,maxf(80,_size.x-368),maxf(80,bottom-top))
 var transform:Transform2D=root.get_global_transform_with_canvas()
 return Rect2(transform*local_rect.position,local_rect.size*float(_ui_scale))

func blocks_workshop_pointer(screen:Vector2) -> bool:
 return _workshop_control_contains(root,screen)

func _workshop_control_contains(node:Control,screen:Vector2) -> bool:
 if not node.is_visible_in_tree():return false
 var local:Vector2=node.get_global_transform_with_canvas().affine_inverse()*screen
 var inside:bool=Rect2(Vector2.ZERO,node.size).has_point(local)
 if node.clip_contents and not inside:return false
 if inside and node.mouse_filter!=Control.MOUSE_FILTER_IGNORE:return true
 for child in node.get_children():
  if child is Control and _workshop_control_contains(child,screen):return true
 return false

func _workshop() -> void:
 var toolbar:=_panel(Rect2(20,124,300,42),PANEL,null,4)
 var row:=_row(toolbar,4)
 var is_craft:=str(state.get("assembly_mode","craft"))=="craft"
 _button(row,"飞行器","assembly_mode","craft",YELLOW if is_craft else PANEL_LIGHT,32).size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _button(row,"发射台","assembly_mode","launcher",YELLOW if not is_craft else PANEL_LIGHT,32).size_flags_horizontal=Control.SIZE_EXPAND_FILL
 var ship:Dictionary=state.get("ship_stats",{})
 var stats_panel:=_panel(Rect2(328,128,328,34),PANEL,null,6)
 _label(stats_panel,"%d 模块  /  %.1f kg  /  储能 %.0f J"%[int(ship.get("parts",0)),float(ship.get("mass",0)),float(ship.get("energy",0))],13,DIM)
 var workshop:Dictionary=state.get("workshop",{})
 if not workshop.is_empty():
  var grid_size:Vector2i=workshop.get("size",Vector2i(9,5))
  var tier_panel:=_panel(Rect2(664,128,260,34),PANEL,null,6)
  _label(tier_panel,"工位 %d × %d 格 · 收工后可扩建"%[grid_size.x,grid_size.y] if int(workshop.get("tier",0))<2 else "扩建完成 · %d × %d 格"%[grid_size.x,grid_size.y],13,TEAL)
 if not str(ship.get("warning","")).is_empty():
  var warning:=_panel(Rect2(20,176,300,52),YELLOW,null,8);_para(warning,str(ship.warning),13)
 var selected:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
 if not selected.is_empty():_inspector(selected)
 else:
  var hint:=_panel(Rect2(_size.x-328,176,308,90),PANEL,null,10)
  var hb:=_box(hint,4);_label(hb,"装配操作",15,TEAL);_para(hb,"点空格安装 · 拖模块换位\n中键平移 · 滚轮缩放 · F 看全",13,DIM)
 if palette_open:_palette()
 var bottom:=_panel(Rect2(20,_size.y-72,466,52),PANEL,null,6)
 bottom.name="WorkshopTools"
 var br:=_row(bottom,6)
 var toggle:=_button(br,"收起零件箱" if palette_open else "打开零件箱","_palette",null,PANEL_LIGHT,38);toggle.custom_minimum_size.x=128;toggle.pressed.disconnect(toggle.pressed.get_connections()[0].callable);toggle.pressed.connect(func():palette_open=not palette_open;render(state))
 var undo:=_button(br,"撤销","undo",null,PANEL_LIGHT,38);undo.tooltip_text="撤销上一步装配 · Ctrl+Z"
 _button(br,"保存方案","save_blueprint",null,PANEL_LIGHT,38)
 _button(br,"载入方案","load_blueprint",null,PANEL_LIGHT,38)
 var fit_button:=_button(content,"看全工位 · F","fit_workshop",null,PANEL_LIGHT,38)
 fit_button.position=Vector2(496,_size.y-65);fit_button.size=Vector2(140,38)
 fit_button.tooltip_text="看全网格与装置 · 中键拖动画面 · 滚轮围绕指针缩放"
 var dispatch:=_panel(Rect2(_size.x-362,_size.y-72,342,52),PANEL,null,6);dispatch.name="DispatchActions"
 var launch_row:=_row(dispatch,6)
 _button(launch_row,"试飞 · 免费","trial",null,TEAL,38).custom_minimum_size.x=150
 _button(launch_row,"发射配送  ↗","dispatch",null,YELLOW,38).custom_minimum_size.x=172

func _catalog_entries() -> Array:
 var raw:Variant=state.get("catalog",{})
 var entries:Array=[]
 if raw is Dictionary:
  for type in raw:
   var e:Dictionary=raw[type].duplicate();e["type"]=type;entries.append(e)
 elif raw is Array:entries=raw
 return entries

func _palette() -> void:
 var entries:=_catalog_entries()
 var visible_entries:Array=[]
 for spec in entries:
  if palette_category=="现有库存":
   var stock_type:=str(spec.get("type",spec.get("id","")))
   var count:=int(spec.get("available",state.get("inventory",{}).get(stock_type,0)))
   var installed:bool=false
   for part in state.get("parts",[]):
    if str(part.get("type",""))==stock_type:installed=true;break
   if count<=0 and not installed:continue
  elif palette_category!="全部" and palette_category!=str(spec.get("category","其他")):continue
  if str(state.get("assembly_mode","craft"))=="launcher" and spec.has("launcher_compatible") and not spec.launcher_compatible:continue
  visible_entries.append(spec)
 var width:=minf(_size.x-40,clampf(visible_entries.size()*104+16,728,960))
 var p:=_panel(Rect2(20,_size.y-232,width,152),PANEL,null,8)
 p.name="PartsTray"
 var frame:=p.get_theme_stylebox("panel") as StyleBoxFlat;frame.border_width_top=3;frame.border_color=TEAL
 var box:=_box(p,6);var head:=_row(box,6);_label(head,"零件箱",16,WHITE)
 var cats:Array=["现有库存","全部"]
 for e in entries:
  var cat:=str(e.get("category","其他"))
  if not cat in cats:cats.append(cat)
 for cat in cats:
  var btn:=Button.new();btn.text=cat;btn.add_theme_font_size_override("font_size",13);btn.custom_minimum_size=Vector2(52,26);btn.add_theme_stylebox_override("normal",_style(YELLOW if palette_category==cat else PANEL_LIGHT,2,4,false));btn.add_theme_color_override("font_color",INK if palette_category==cat else WHITE);head.add_child(btn);btn.set_meta("view_key","category:"+cat);btn.pressed.connect(func():palette_category=cat;render(state))
 _spacer(head);_label(head,"滚轮浏览 / 点击选择",11,MUTED)
 var scroll:=ScrollContainer.new();scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.set_meta("view_key","parts:"+str(state.get("assembly_mode","craft"))+":"+palette_category);box.add_child(scroll)
 scroll.gui_input.connect(func(event):
  if event is InputEventMouseButton and event.pressed:
   if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:scroll.scroll_horizontal+=120;scroll.accept_event()
   elif event.button_index==MOUSE_BUTTON_WHEEL_UP:scroll.scroll_horizontal-=120;scroll.accept_event()
 )
 var strip:=_row(scroll,8)
 for spec in visible_entries:_part_card(strip,spec)

func _part_icon(parent: Node, type: String, icon_size: Vector2) -> Control:
 # Prefer the same image-generated pixel sprites that are installed in the 2D scene.
 var path:="res://assets/2d_v5/modules/"+type+"-pixel.png"
 if type=="coupler":path="res://assets/2d_v5/modules/cohesion/coupler-latch-pixel.png"
 var icon:Control
 if ResourceLoader.exists(path):
  var t:=TextureRect.new();t.texture=load(path);t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon=t
 else:
  var warning:=Label.new();warning.text="缺图";warning.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;warning.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;warning.add_theme_color_override("font_color",CORAL);warning.add_theme_font_size_override("font_size",11);warning.tooltip_text="缺少零件贴图："+type;icon=warning
  if not _missing_icon_reports.has(type):_missing_icon_reports[type]=true;push_error("Missing required 2D HUD module sprite: "+path)
 icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.custom_minimum_size=icon_size;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(icon);return icon

func _part_card(parent: Node, spec: Dictionary) -> void:
 var type:=str(spec.get("type",spec.get("id","beam")))
 var inventory:Dictionary=state.get("inventory",{})
 var available:=int(spec.get("available",inventory.get(type,0)))
 var selected:=type==str(state.get("chosen_type","beam"))
 var card:=Button.new();card.set_meta("view_key","catalog:"+type);card.custom_minimum_size=Vector2(96,92)
 var box:=_style(YELLOW if selected else PANEL_LIGHT,2,4,false);box.border_color=YELLOW if selected else EDGE;card.add_theme_stylebox_override("normal",box)
 var hover:=box.duplicate() as StyleBoxFlat;hover.border_color=TEAL;card.add_theme_stylebox_override("hover",hover);card.add_theme_stylebox_override("pressed",hover.duplicate())
 card.tooltip_text="%s\n%s\n质量 %.1f kg · 库存 %d"%[spec.get("name",type),spec.get("description",""),float(spec.get("mass",0)),available];parent.add_child(card);card.pressed.connect(func():_act("select_catalog",type))
 var icon:=_part_icon(card,type,Vector2(48,48));icon.position=Vector2(24,8);icon.size=Vector2(48,48)
 var title:=_label(card,str(spec.get("name",type)),12,INK if selected else WHITE);title.position=Vector2(4,62);title.size=Vector2(88,20);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 var stock:=_label(card,"× %d"%available,11,INK if selected else TEAL if available>0 else CORAL);stock.position=Vector2(61,4)

func _inspector(part: Dictionary) -> void:
 var control_count:=0
 var raw_controls:Variant=part.get("controls",[])
 if raw_controls is Array:control_count=raw_controls.size()
 elif raw_controls is Dictionary:control_count=int(raw_controls.get("inputs",0))+(1 if bool(raw_controls.get("accepts_target",false)) else 0)+(1 if bool(part.get("schema",{}).get("editable",false)) else 0)
 var reserved:=420 if palette_open else 268
 var h:=minf(minf(420,_size.y-reserved),206+control_count*72+(36 if control_count>0 else 0))
 var panel:=_panel(Rect2(_size.x-328,176,308,maxf(206,h)),PANEL,null,10);panel.set_meta("context_panel",true)
 var b:=_box(panel,8)
 var spec:Dictionary=part.get("spec",{})
 var name:=str(part.get("name",spec.get("name",part.get("type","模块"))))
 var header:=_row(b);_label(header,"MODULE / #%s"%str(part.get("id",0)),13,BLUE);_spacer(header);_label(header,str(part.get("category",spec.get("category","模块设置"))),12,MUTED)
 var title_row:=_row(b,8);_part_icon(title_row,str(part.get("type","beam")),Vector2(32,32));_label(title_row,name,19);_spacer(title_row)
 var quarter:=posmod(int(part.get("rot",0)),4)
 var facing:=_label(title_row,["→","↓","←","↑"][quarter]+" %d°"%(quarter*90),15,BLUE);facing.tooltip_text="当前朝向 · 每次顺时针旋转 90°"
 var description:=str(part.get("description",spec.get("description","")))
 if not description.is_empty():_para(b,description,12,MUTED)
 var scroll:=_scroll(b)
 var id:int=int(part.get("id",-1))
 scroll.get_parent().set_meta("view_key","inspector:"+str(id))
 var controls:Variant=part.get("controls",[])
 if controls is Dictionary:controls=_typed_controls(part,controls)
 for control in controls:
  var key:=str(control.get("key","param"))
  _label(scroll,str(control.get("label",key)),13,BLUE)
  if str(control.get("kind","number"))=="number":
   var spin:=SpinBox.new();spin.min_value=float(control.get("min",0));spin.max_value=float(control.get("max",100));spin.step=float(control.get("step",0.25));spin.value=float(control.get("value",part.get(key,0)));spin.suffix=str(control.get("unit",""));spin.custom_minimum_size.y=37;spin.set_meta("view_key","part:"+str(id)+":"+key);scroll.add_child(spin);spin.value_changed.connect(func(v):_act("set_param",{"id":id,"value":v}))
  else:
   var choice:=OptionButton.new();choice.set_meta("view_key","part:"+str(id)+":"+key);choice.custom_minimum_size.y=37;scroll.add_child(choice)
   var options:Array=control.get("options",[]);var ids:Array=[]
   if options.is_empty():options=_wire_options(part,key)
   for opt in options:choice.add_item(str(opt.get("label",opt.get("name","未连接"))));ids.append(int(opt.get("id",-1)))
   choice.select(maxi(0,ids.find(int(control.get("value",part.get(key,-1))))))
   choice.item_selected.connect(func(index):_act("set_input",{"id":id,"key":key,"source":ids[index]}))
 var behavior:=str(part.get("default_behavior",""))
 if not behavior.is_empty():_para(scroll,behavior,11,MUTED)
 var actions:=_row(b,7)
 _button(actions,"旋转 90°  [R]","rotate_part",id,TEAL,40).size_flags_horizontal=Control.SIZE_EXPAND_FILL
 var remove:=_button(actions,"拆卸","remove_part",id,CORAL,40);remove.tooltip_text="退回库存 · Delete"

func _typed_controls(part: Dictionary, controls: Dictionary) -> Array:
 var rows:Array=[];var schema:Dictionary=part.get("schema",{})
 if bool(schema.get("editable",false)):
  var row:=schema.duplicate();row["kind"]="number";row["key"]="param";row["value"]=part.get("param",schema.get("default",0));rows.append(row)
 for n in int(controls.get("inputs",0)):
  var key:="input_a" if n==0 else "input_b"
  rows.append({"kind":"input","key":key,"label":"信号输入 "+("A" if n==0 else "B"),"value":part.get(key,-1)})
 if bool(controls.get("accepts_target",false)):rows.append({"kind":"input","key":"target","label":"作用目标","value":part.get("target",-1)})
 return rows

func _wire_options(part: Dictionary, control_key: String = "input_a") -> Array:
 var entries:Array=[{"id":-1,"label":"— 未连接 —"}]
 if _pilot_mode() and control_key!="target":entries.append({"id":-2,"label":"驾驶按钮 · Space"})
 var catalog:Variant=state.get("catalog",{})
 for item in state.get("parts",[]):
  if int(item.id)==int(part.get("id",-1)):continue
  var name:=str(item.get("name",item.get("type","模块")))
  if catalog is Dictionary:name=str(catalog.get(item.type,{}).get("name",name))
  entries.append({"id":int(item.id),"label":"#%d %s"%[item.id,name]})
 return entries

func _supply() -> void:
 var is_night:=str(state.get("phase","day")) in ["night","evening"]
 var b:=_drawer("明天，也要准时送达。" if is_night else "今天的托付，都安排好了吗？","SUPPLY / 夜间补给" if is_night else "CLOSING TIME / 营业收尾",460)
 if not is_night:
  _label(b,"结束营业后，整理库存。",21,BLUE)
  _para(b,"白天继续接单、装配和配送。打烊后再采购零件、完成研究，为下一天做准备。",16)
  if _has_accepted():
   var order:Dictionary=state.get("activeorder",{})
   _rule(b);_label(b,"还有一份已接受的委托",17,BLUE);_para(b,str(order.get("name","待完成委托")),20)
   _para(b,"先完成配送；如果无法完成，可以确认取消后再打烊。",14,MUTED)
   _button(b,"回工位继续这单","focus_workbench",null,TEAL,48)
   _cancel_button(b,order,42)
  else:
   _para(b,"未接受的委托可以婉拒，不会产生违约处罚。",14,MUTED)
   _button(b,"再看看委托","focus_counter",null,CREAM,48)
  var rest:=Control.new();rest.size_flags_vertical=Control.SIZE_EXPAND_FILL;rest.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(rest)
  _rule(b)
  var close:=_button(b,"结束营业，进入夜间补给  →","close_day",null,YELLOW,51);close.disabled=_has_accepted()
  return
 var top:=_row(b);_label(top,"库存补给",19);_spacer(top);_label(top,"购买后立即入库",12,MUTED)
 var body:=_scroll(b)
 var workshop:Dictionary=state.get("workshop",{})
 if not workshop.is_empty():
  var current_size:Vector2i=workshop.get("size",Vector2i(9,5))
  _label(body,"车间扩建 · %d × %d 格"%[current_size.x,current_size.y],19,TEAL)
  if int(workshop.get("next_tier",-1))>=0:
   var next_size:Vector2i=workshop.get("next_size",Vector2i.ZERO)
   _para(body,"向右增加 4 列、向上增加 2 行。原方案与连线保留。",13,DIM)
   var buy_workshop:=_button(body,"扩至 %d × %d 格  ·  ¥ %d"%[next_size.x,next_size.y,int(workshop.cost)],"workshop_upgrade",int(workshop.next_tier),TEAL,44)
   buy_workshop.name="WorkshopUpgrade";buy_workshop.disabled=int(state.get("credits",0))<int(workshop.cost)
  else:_para(body,"已完成全部扩建。",13,DIM)
  _rule(body)
 for spec in _catalog_entries():
  var type:=str(spec.get("type",spec.get("id","")))
  var row_panel:=PanelContainer.new();row_panel.add_theme_stylebox_override("panel",_style(WHITE,2,8,false));body.add_child(row_panel)
  var row:=_row(row_panel,9);_part_icon(row,type,Vector2(43,43));var text:=_box(row,0);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _label(text,str(spec.get("name",type)),16);_label(text,"库存 %s · %.1f kg"%[state.get("inventory",{}).get(type,0),float(spec.get("mass",0))],11,MUTED)
  var cost:=int(spec.get("price",0));var buy:=_button(row,"¥ %d  +"%cost,"buy",type,YELLOW,42);buy.disabled=int(state.get("credits",0))<cost
 var upgrades:Array=state.get("upgrades",[])
 if not upgrades.is_empty():
  _label(body,"店铺研究",19,BLUE)
  for upgrade in upgrades:
   _button(body,str(upgrade.get("name","研究"))+"  ·  ¥ "+str(upgrade.get("cost",0)),"upgrade",upgrade.get("id","research"),TEAL,43).disabled=bool(upgrade.get("disabled",false))
 _rule(b)
 _button(b,"开门，迎接第 %d 天  →"%(int(state.get("day",1))+1),"next_day",null,BLUE,49).add_theme_color_override("font_color",WHITE)

func _pilot_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-v1","pilot-v2","pilot-v3"]

func _ascent_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-v2","pilot-v3"]

func _ground_mode() -> bool:
 return GroundProfile.is_ground_route(state.get("activeorder",{}))

func _extreme_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version","")))=="pilot-v3"

func _flight() -> void:
 var pilot:=_pilot_mode();var ascent:=_ascent_mode();var extreme:=_extreme_mode()
 var top:=_panel(Rect2(20,20,260,76),PANEL,null,8);var b:=_box(top,2)
 _label(b,"免费试飞" if bool(state.get("trial",false)) else "配送中",11,YELLOW)
 var order:Dictionary=state.get("activeorder",{})
 var name:=_label(b,str(order.get("destination_name","收件台")) if _ground_mode() else str(order.get("name","正在飞向目的地")),18,WHITE);name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 flight_labels["status"]=_label(b,"驾驶准备" if pilot else "自动航行 · 1×",12,TEAL)
 if ascent:
  # A quiet, non-interactive cue band leaves the ship and launch ribbon clear.
  # Distances are fictional route-space measures, never real orbital altitude.
  _ascent_cue=_panel(Rect2(20,108,260,78),PANEL,null,8);_ascent_cue.name="AscentCue";_ascent_cue.mouse_filter=Control.MOUSE_FILTER_IGNORE
  var cue:=_box(_ascent_cue,2)
  flight_labels["altitude"]=_label(cue,"高度 0 / 150 m",12,DIM)
  flight_labels["gate"]=_label(cue,"",14,TEAL)
  flight_labels["gate_detail"]=_label(cue,"",11,DIM)
 var width:=_size.x-608
 var route:=_panel(Rect2(292,20,width,76),PANEL,null,8);var rb:=_box(route,3)
 var r:=_row(rb);_label(r,"航线进度",12,DIM);_spacer(r);flight_labels["distance"]=_label(r,"0 / 0 m",14,WHITE)
 progress_bar=ProgressBar.new();progress_bar.custom_minimum_size.y=8;progress_bar.show_percentage=false;rb.add_child(progress_bar)
 var times:=_row(rb);flight_labels["elapsed"]=_label(times,"航时 0.0 s",12,DIM);_spacer(times);flight_labels["deadline"]=_label(times,"目标 60 s",12,DIM)
 # The ascent approach enters from the upper right. Keep its silhouettes clear
 # by stacking resources below the cue, outside the central flight band.
 var resource_rect:=Rect2(20,198,260,112 if extreme else 96) if ascent else Rect2(_size.x-304,20,284,96 if pilot else 76)
 var resources:=_panel(resource_rect,PANEL,null,8);resources.name="FlightResources";var ib:=_box(resources,1)
 var row:=_row(ib);_label(row,"货物完整度",13,DIM);_spacer(row);flight_labels["integrity"]=_label(row,"100%",20 if extreme else 24,YELLOW)
 flight_labels["energy"]=_label(ib,"电量 0 J" if pilot else "消耗 0 J · 信号正常",12,DIM)
 if extreme:flight_labels["thrust"]=_label(ib,"推力 — N",11,TEAL)
 if pilot:flight_labels["pilot_signal"]=_label(ib,"Space 回路 · 待命",11,TEAL)
 var events:=_panel(Rect2(20,_size.y-134,444,42) if ascent else Rect2(20,_size.y-184,444,84),PANEL,null,5 if ascent else 8);events.name="FlightEventReceipt";var eb:=_box(events,1 if ascent else 3)
 if extreme:flight_labels["impact"]=_label(eb,"",11,DIM)
 else:_label(eb,"飞行记录",11,TEAL)
 if ascent:
  flight_labels["events"]=_label(eb,"",12,WHITE);flight_labels.events.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 else:flight_labels["events"]=_para(eb,"",13,WHITE)
 var controls:=_panel(Rect2(20,_size.y-64,340 if pilot else 612,44),PANEL,null,4);var cr:=_row(controls,6)
 var pause_button:=_button(cr,"暂停  [Esc / P]" if pilot else "暂停 / 继续  [空格]","pause",null,YELLOW,34);pause_button.custom_minimum_size.x=184;_pause_button=weakref(pause_button)
 if not pilot:
  for rate in [1,2,4]:_button(cr,"%d×"%rate,"set_speed",rate,PANEL_LIGHT,34).custom_minimum_size.x=56
 _spacer(cr);_button(cr,"中止本次","abort",null,PANEL_LIGHT,34).custom_minimum_size.x=116
 if pilot:
  var legend:=_panel(Rect2(372,_size.y-64,minf(516,_size.x-392),44),PANEL,null,8)
  flight_labels["controls"]=_label(legend,"W / S  或  ↑ / ↓  升降    Shift  全功率    Space  触发回路" if extreme else "W / S  或  ↑ / ↓  升降    Shift  冲刺    Space  触发回路",13,WHITE)
 var hint:=_label(content,"",12,CREAM);hint.position=Vector2(20,_size.y-88);hint.add_theme_color_override("font_shadow_color",INK);hint.add_theme_constant_override("shadow_offset_x",1);hint.add_theme_constant_override("shadow_offset_y",1);flight_labels["hint"]=hint
 set_input_device(_gamepad)
 update_flight(state.get("flight",state))

func update_flight(data: Dictionary) -> void:
 if mode!="flight" or flight_labels.is_empty():return
 var elapsed:=float(data.get("elapsed",0));var distance:=float(data.get("distance",data.get("progress",0)));var total:=float(data.get("total_distance",state.get("activeorder",{}).get("distance",100)))
 var integrity:=float(data.get("integrity",100));if integrity<=1.0:integrity*=100
 var pilot:=_pilot_mode()
 var pause_button:Button=_pause_button.get_ref() if _pause_button!=null else null
 if pilot and is_instance_valid(pause_button):pause_button.text=("继续" if bool(data.get("paused",false)) else "暂停")+("  [Menu]" if _gamepad else "  [Esc / P]")
 if pilot:
  flight_labels.hint.text=""
  if _ascent_mode():
   var phase:=str(data.get("flight_phase","city"))
   var phase_text:=str({"city":"城市","climb":"爬升","approach":"接站"}.get(phase,"航行"))
   if _ground_mode():phase_text="接近收件台" if phase=="approach" and int(data.get("next_gate_index",-1))<0 else "低空配送"
   flight_labels.status.text="已暂停" if bool(data.get("paused",false)) else str(data.get("phase","发射准备")) if bool(data.get("charging",false)) else "速度 %.1f m/s · %s"%[_flight_number(data,"speed",0),phase_text]
   _ascent_telemetry=data.duplicate()
   _update_ascent_cue()
  else:flight_labels.status.text="已暂停" if bool(data.get("paused",false)) else "速度 %.1f m/s · 升降 %+.1f"%[float(data.get("forward_speed",data.get("speed",0))),float(data.get("vertical_speed",0))]
 else:
  flight_labels.hint.text=""
  flight_labels.status.text=("已暂停" if bool(data.get("paused",false)) else str(data.get("phase","自动航行")))+" · %s×"%str(data.get("speed",1))
 flight_labels.distance.text="%.0f / %.0f m"%[distance,total];progress_bar.value=clampf(distance/maxf(1,total)*100,0,100)
 flight_labels.elapsed.text="航时 %.1f s"%elapsed;flight_labels.deadline.text="奖励 %s s / 最迟 %s s"%[str(state.get("activeorder",{}).get("deadline",60)),str(state.get("activeorder",{}).get("time_limit","—"))]
 flight_labels.integrity.text="%.0f%%"%integrity;flight_labels.integrity.add_theme_color_override("font_color",YELLOW if integrity>=80 else CORAL)
 var signals:Variant=data.get("signals",[])
 if pilot:
  var energy:=float(data.get("energy_remaining",0));var boosting:=bool(data.get("pilot_boost",false))
  if _ascent_mode():
   energy=float(data.get("energy_remaining",NAN))
   var capacity:=float(data.get("battery_capacity",NAN))
   var energy_state:="电量未知" if not is_finite(energy) else "电量耗尽" if energy<=0 else "冲刺中" if boosting else "冲刺待命"
   if _extreme_mode():
    flight_labels.energy.text="电量 %s / %s"%[_flight_energy(energy),_flight_energy(capacity)]+(" · 耗尽" if is_finite(energy) and energy<=0 else "")
    _update_extreme_feedback(data)
   else:flight_labels.energy.text="电量 %s / %s · %s"%[_flight_energy(energy),_flight_energy(capacity),energy_state]
  else:flight_labels.energy.text="电量 %.0f J · %s"%[energy,"电量耗尽" if energy<=0 else "冲刺中" if boosting else "冲刺待命"]
  if flight_labels.has("pilot_signal"):
   flight_labels.pilot_signal.text=("A 回路 · " if _gamepad else "Space 回路 · ")+("触发中" if bool(data.get("pilot_active",false)) else "待命")
   flight_labels.pilot_signal.add_theme_color_override("font_color",YELLOW if bool(data.get("pilot_active",false)) else TEAL)
 else:
  flight_labels.energy.text="消耗 %.1f J%s"%[float(data.get("energy",data.get("energy_used",0)))," · %d 路信号"%signals.size() if signals is Array and not signals.is_empty() else ""]
 var events:Variant=data.get("events",[])
 if events is Array:
  var lines:Array[String]=[]
  for event in events.slice(maxi(0,events.size()-(2 if _ascent_mode() else 3))):lines.append(str(event))
  flight_labels.events.tooltip_text="\n".join(lines)
  if _ascent_mode():lines.reverse()
  flight_labels.events.text=("  ·  " if _ascent_mode() else "\n").join(lines) if not lines.is_empty() else ""
 else:flight_labels.events.text=str(events)
 var receipt:Control=content.get_node_or_null("FlightEventReceipt")
 if receipt!=null:receipt.visible=not flight_labels.events.text.is_empty() or (flight_labels.has("impact") and not flight_labels.impact.text.is_empty())


func _update_extreme_feedback(data: Dictionary) -> void:
 # Show the funded nozzle output; a held Shift key alone does not imply thrust.
 var actual:=_flight_number(data,"thrust_actual",NAN)
 var actual_text:="%.1f"%maxf(0,actual) if is_finite(actual) else "—"
 var drive:="" if not data.has("overdrive") else "全功率" if bool(data.overdrive) else "巡航"
 flight_labels.thrust.text=(drive+" · " if not drive.is_empty() else "")+"推力 %s N"%actual_text
 flight_labels.thrust.add_theme_color_override("font_color",YELLOW if data.get("overdrive",false) and is_finite(actual) and actual>.001 else DIM)
 var absorbed:=_flight_number(data,"impact_absorbed",NAN)
 var spent:=_flight_number(data,"impact_shield_energy",NAN)
 var elapsed:=_flight_number(data,"elapsed",_extreme_elapsed)
 if elapsed<_extreme_elapsed or (is_finite(absorbed) and absorbed<_impact_absorbed):
  _impact_absorbed=0;_impact_energy=0;_impact_cue_until=-1
 _extreme_elapsed=elapsed
 var funded:=is_finite(absorbed) and is_finite(spent) and absorbed>0 and spent>0
 if funded and absorbed>_impact_absorbed and spent>_impact_energy:_impact_cue_until=elapsed+.6
 if is_finite(absorbed):_impact_absorbed=absorbed
 if is_finite(spent):_impact_energy=spent
 # This is a collective damage receipt, not a made-up point of impact. No
 # protective halo is attached to an unverified body or disconnected island.
 flight_labels.impact.text="护盾 · 累计吸收 %.1f HP · 耗电 %s"%[absorbed,_flight_energy(spent)] if funded else ""
 flight_labels.impact.add_theme_color_override("font_color",TEAL if funded and elapsed<=_impact_cue_until else DIM)

func _flight_number(data: Dictionary, key: String, fallback: float) -> float:
 var value:=float(data.get(key,fallback))
 return value if is_finite(value) else fallback

func _flight_energy(value: float) -> String:
 if not is_finite(value):return "—"
 return "%.2f kJ"%(value/1000.0) if absf(value)>=1000.0 else "%.0f J"%value

func _update_ascent_cue() -> void:
 if not is_instance_valid(_ascent_cue):return
 var data:=_ascent_telemetry
 _ascent_cue.visible=not bool(data.get("charging",false)) and _launch_phase not in ["move","charge","ignition"]
 flight_labels.altitude.text="高度 %.0f / %.0f m"%[_flight_number(data,"altitude",0),_flight_number(data,"target_altitude",float(state.get("activeorder",{}).get("pilot_altitude",150)))]
 var paused:=bool(data.get("paused",false))
 var gate:=int(data.get("next_gate_index",-1))
 var seconds:=_flight_number(data,"next_gate_time",-1)
 var ready:=gate>=0 and seconds>=0
 var warning:=ready and seconds<=_flight_number(data,"lookahead_seconds",3.5) and not paused
 flight_labels.gate.add_theme_color_override("font_color",DIM if paused else YELLOW if warning else TEAL)
 if not ready:
  var approach:=str(data.get("flight_phase",""))=="approach"
  flight_labels.gate.text=("接近"+str(state.get("activeorder",{}).get("destination_name","收件台")) if _ground_mode() else "接近收件区") if approach else ""
  flight_labels.gate_detail.text="已暂停" if paused else ""
  if _ground_mode() and approach:
   var limit:=_flight_number(state.get("activeorder",{}),"max_delivery_speed",NAN)
   if is_finite(limit):flight_labels.gate_detail.text=("已暂停 · " if paused else "")+"收件限速 %.0f m/s"%limit
  return
 var direction:=int(data.get("next_gate_direction",0))
 var cue:="↑ 向上" if direction<0 else "↓ 向下" if direction>0 else "→ 保持"
 flight_labels.gate.text="%s · %.1f s 后过门"%[cue,seconds]
 flight_labels.gate_detail.text=("已暂停 · " if paused else "")+"第 %d 门 · 门高 %.0f m"%[gate+1,_flight_number(data,"next_gate_altitude",0)]

func _report() -> void:
 var report:Dictionary=state.get("report",{})
 var success:=bool(report.get("success",false));var trial:=bool(report.get("trial",state.get("trial",false)))
 var w:=760.0;var p:=_panel(Rect2((_size.x-w)/2,156,w,_size.y-184),PANEL,null,20)
 var b:=_box(p,11);var header:=_row(b);var titles:=_box(header,1);titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _label(titles,"FLIGHT REPORT / 试飞报告" if trial else "DELIVERY REPORT / 配送回执",12,BLUE)
 _label(titles,"稳稳送到！" if success else "这趟没送到。再调整一下。",29)
 _label(header,"✓" if success else "!",48,BLUE if success else Color("b84949"))
 var cause:=str(report.get("cause","全程完整，按时抵达目的地。" if success else "检查结构、推力和电量，再做一次免费试飞。"))
 var causep:=PanelContainer.new();causep.add_theme_stylebox_override("panel",_style(TEAL if success else CORAL,2,12,false));b.add_child(causep);_para(causep,cause,17)
 var metrics:=_row(b,20)
 var metric_rows:Array=[["航行用时","%.1f s"%float(report.get("elapsed",0))],["货物完整度","%.0f%%"%float(report.get("integrity",100))]]
 if trial:
  metric_rows.append(["本次耗能","%.1f J"%float(report.get("energy_j",report.get("energy",0)))])
  metric_rows.append(["预计净收益","¥ %s"%str(report.get("estimated_profit","—"))])
 else:metric_rows.append(["本单净收益","¥ %s"%str(report.get("profit",0))])
 for pair in metric_rows:
  var m:=_box(metrics,1);m.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_label(m,str(pair[0]),12,MUTED);_label(m,str(pair[1]),25,BLUE)
 if trial:_label(b,"试飞估算，未计费；正式结果以配送为准。",13,BLUE)
 var body:=_scroll(b)
 var comparison:Variant=report.get("comparison","")
 if not str(comparison).is_empty():
  _label(body,"和上一次相比",16,BLUE)
  if comparison is Dictionary:
   for key in comparison:_para(body,str(key)+"  "+str(comparison[key]),14)
  else:_para(body,str(comparison),14)
 var timings:Variant=report.get("timings",report.get("events",[]))
 if timings is Array and not timings.is_empty():
  _label(body,"关键时刻",16,BLUE)
  for timing in timings.slice(0,5):_para(body,str(timing),13,MUTED)
 if not trial:
  var costbtn:=Button.new();costbtn.text=("▼" if report_costs_open else "▶")+"  收支明细";body.add_child(costbtn);costbtn.pressed.connect(func():report_costs_open=not report_costs_open;render(state))
  if report_costs_open:
   for item in [["订单收入","income",1],["能源消耗","energy",-1],["弹药消耗","ammo",-1],["维修费用","repairs",-1],["零件损失","lost",-1]]:
    var row:=_row(body);_label(row,str(item[0]),14);_spacer(row);_label(row,"¥ %+d"%(int(report.get(item[1],0))*int(item[2])),14)
  if report.has("review"):_para(body,"客户回信：“"+str(report.review)+"”",15,BLUE)
  if report.has("replenishment"):_para(body,"整备说明："+str(report.replenishment),13,MUTED)
 else:_para(body,"试飞不扣资金、不改变声望。",14,MUTED)
 _rule(b)
 var actions:=_row(b,9)
 if trial:
  _button(actions,"回工位调整","focus_workbench",null,CREAM,49).size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _button(actions,"再试一次","trial_retry",null,TEAL,49).size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _button(actions,"正式配送","dispatch",null,YELLOW,49).size_flags_horizontal=Control.SIZE_EXPAND_FILL
 else:
  _button(actions,"返回店铺","close_drawer",null,CREAM,49).size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _button(actions,"下一份委托","next_contract",null,YELLOW,49).size_flags_horizontal=Control.SIZE_EXPAND_FILL

func _help() -> void:
 var b:=_drawer("把每一份心意，送到。","FLIGHT HANDBOOK / 航行手册",594)
 var body:=_scroll(b)
 var sections:Array=state.get("help",[
  ["01  从一份委托开始","在柜台挑选航线，确认距离、时限和完整度。先免费试飞，确认设计可靠后再正式配送。"],
  ["02  用零件解决问题","选择零件后点击工位空格安装，相邻模块自动形成结构连接。电芯、货舱和推进器要连成一体。"],
  ["03  接线，让机器自己判断","距离探头与碰撞开关输出信号，逻辑门组合条件，执行器收到信号后动作。点击模块设置参数与连线。"],
  ["04  看懂每一次失败","报告先指出首个失败原因和关键时刻。回工位调整后再试一次，用对比判断修改是否有效。"],
  ["快捷操作","R 旋转已选零件 · Delete 拆卸\nCtrl+Z 撤销上一步装配\nW / S 或 ↑ / ↓ 升降 · Shift %s\nSpace 触发驾驶回路 · Esc / P 暂停\nF11 切换全屏"%("全功率" if _extreme_mode() else "冲刺") if _pilot_mode() else "R 旋转已选零件 · Delete 拆卸\nCtrl+Z 撤销上一步装配\n右键模块拆卸 · 空格暂停 / 继续飞行\nF11 切换全屏 · Esc 返回 / 暂停"]
 ])
 if _extreme_mode():
  sections=sections.duplicate(true)
  sections.append(["05  全功率推进","按住 Shift 全功率推进。推力受接线、电量、阀门和喷口方向影响；加装引擎也会增加质量与耗电。松开后不会立即停下。"])
  sections.append(["06  钻头与碰撞护盾","钻头前端接触可破坏的障碍才会切削，空转也耗电，不能钻穿障碍门。护盾仅用实际电量吸收部分碰撞伤害，仍会受损、反弹；不能免除结构过载，高速撞击仍可能损坏装置。"])
 sections=sections.duplicate(true)
 sections.append(["店内操作","A / D 移动，持续按住后跑动；E 与附近柜台或工位交互。Tab 打开菜单。非弹窗界面按 A / D 返回店内移动。"])
 sections.append(["手柄操作","左摇杆 / 十字键移动，持续朝同一方向后跑动；A 与附近目标交互，Menu 进入菜单。菜单中方向选择、A 确认、B 返回，右摇杆滚动。工位按 X 切换网格：A 选择或放置，Y 拿起零件，移动后 A 落下，X 旋转，LB 拆除，RB 撤销，R3 全景，L3 切换已装零件，右摇杆平移。B 先取消搬动，再返回菜单。飞行中左摇杆 / 十字键升降，RB 全功率，A 触发回路，Menu 暂停。摇杆死区可在设置中调整。"])
 for section in sections:
  if section is Array and section.size()>=2:_label(body,str(section[0]),21,BLUE);_para(body,str(section[1]),16);_rule(body)
  elif section is Dictionary:_label(body,str(section.get("title","")),21,BLUE);_para(body,str(section.get("text","")),16)

func _dispatch_confirmation() -> void:
 var order:Dictionary=state.get("activeorder",{})
 if not _has_order_details(order):
  dispatch_confirmation_open=false;return
 var current_id:=str(order.get("contract_id",order.get("id","")))
 if current_id!=_dispatch_contract_id:
  dispatch_confirmation_open=false;return
 var dim:=ColorRect.new();dim.color=Color(.04,.08,.2,.5);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.add_child(dim)
 var panel:=_panel(Rect2((_size.x-640)/2,(_size.y-530)/2,640,530),CREAM,null,21);panel.set_meta("modal_panel",true)
 var b:=_box(panel,10);var heading:=_row(b);var title:=_box(heading,1);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _label(title,"DISPATCH CHECK / 发货前确认",12,BLUE);_label(title,"这一趟，要带上真货了。",27)
 var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(38,38);heading.add_child(close);close.pressed.connect(_dismiss_dispatch)
 _rule(b)
 var order_row:=_row(b);_label(order_row,str(order.name),22);_spacer(order_row);_label(order_row,"基础运费  ¥ %s"%str(order.get("reward","—")),20,BLUE)
 _para(b,"%s  ·  %.1f kg  ·  %s m"%[str(order.get("cargo","客户货物")),float(order.get("weight",1.0))*3.0,str(order.distance)],16)
 _para(b,"奖励时限 %s s  /  强制结束 %s s  /  完整度 ≥ %s%%"%[str(order.get("deadline","—")),str(order.get("time_limit","—")),str(order.get("required","—"))],14,BLUE)
 _para(b,"投递半径 %s m  ·  到达速度 ≤ %s m/s"%[str(order.get("delivery_radius","—")),str(order.get("max_delivery_speed","—"))],13,MUTED)
 var policy:=PanelContainer.new();policy.add_theme_stylebox_override("panel",_style(WHITE,2,12,false));b.add_child(policy)
 var pb:=_box(policy,5);_label(pb,"本趟按实际消耗结算",16,BLUE)
 var tariff_text:String=String.num(float(state.get("energy_tariff",.18)),5)
 var default_policy:String="能源 ¥%s / J，向上取整；耗用弹药与遗失零件按原价补齐，回收零件按损伤维修。成功送达后收取运费，晚到或破损会减少收入；失败也会扣除实际费用。"%tariff_text
 _para(pb,str(state.get("dispatch_fee_policy",default_policy)),14)
 _para(pb,"费用包含自动补件与维修，结算后恢复为发射前方案。",12,MUTED)
 _para(b,"这份委托只会正式配送一次。想先验证装置，可以返回工位免费试飞。",13,MUTED)
 var rest:=Control.new();rest.size_flags_vertical=Control.SIZE_EXPAND_FILL;rest.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(rest)
 var actions:=_row(b,10)
 var cancel:=Button.new();cancel.set_meta("view_key","dispatch:cancel");cancel.set_meta("safe_modal_default",true);cancel.text="再检查一下";cancel.custom_minimum_size.y=49;cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(cancel);cancel.pressed.connect(_dismiss_dispatch)
 var launch:=Button.new();launch.set_meta("view_key","dispatch:confirm");launch.text="确认发射配送  ↗";launch.custom_minimum_size.y=49;launch.size_flags_horizontal=Control.SIZE_EXPAND_FILL;launch.add_theme_stylebox_override("normal",_style(YELLOW,3,12));launch.add_theme_color_override("font_color",INK);actions.add_child(launch)
 launch.pressed.connect(func():
  if not dispatch_confirmation_open:return
  dispatch_confirmation_open=false;_dispatch_contract_id="";render(state);action_requested.emit("dispatch",null)
 )

func _dismiss_dispatch() -> void:
 dispatch_confirmation_open=false;_dispatch_contract_id="";render(state)

func _settings() -> void:
 var dim:=ColorRect.new();dim.color=Color(0.04,0.08,0.2,0.48);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.add_child(dim)
 var panel:=_panel(Rect2((_size.x-440)/2,(_size.y-580)/2,440,580),CREAM,null,21);panel.set_meta("modal_panel",true);var b:=_box(panel,14);var row:=_row(b);_label(row,"稍歇一下",28);_spacer(row)
 var close:=Button.new();close.text="×";row.add_child(close);close.pressed.connect(func():settings_open=false;render(state))
 _label(b,"声音",16,BLUE)
 var volume:=HSlider.new();volume.set_meta("view_key","settings:volume");volume.min_value=0;volume.max_value=1;volume.step=.05;volume.value=float(state.get("settings",{}).get("volume",.55));volume.custom_minimum_size.y=32;b.add_child(volume);volume.value_changed.connect(func(v):_act("settings",{"volume":v}))
 var reduced:=CheckBox.new();reduced.set_meta("view_key","settings:reduced_motion");reduced.text="减少镜头动态";reduced.button_pressed=bool(state.get("settings",{}).get("reduced_motion",false))
 reduced.add_theme_color_override("font_color",WHITE)
 for color_key in ["font_hover_color","font_pressed_color","font_hover_pressed_color"]:reduced.add_theme_color_override(color_key,INK)
 # CheckBox's default hover_pressed is transparent; pair its text with the
 # same cyan surface as pressed so a selected hover cannot become white/cream.
 reduced.add_theme_stylebox_override("hover_pressed",_style(TEAL,2,8,false))
 reduced.tooltip_text="减少震动、速度线和镜头缩放";reduced.custom_minimum_size.y=34;b.add_child(reduced);reduced.toggled.connect(func(enabled):_act("settings",{"reduced_motion":enabled}))
 var blur:=CheckBox.new();blur.set_meta("view_key","settings:motion_blur");blur.text="飞行背景动态模糊";blur.button_pressed=bool(state.get("settings",{}).get("motion_blur",true));blur.custom_minimum_size.y=34
 blur.add_theme_color_override("font_color",WHITE)
 for color_key in ["font_hover_color","font_pressed_color","font_hover_pressed_color"]:blur.add_theme_color_override(color_key,INK)
 blur.add_theme_stylebox_override("hover_pressed",_style(TEAL,2,8,false));blur.tooltip_text="只影响飞行背景；减少镜头动态开启时不启用。";b.add_child(blur);blur.toggled.connect(func(enabled):_act("settings",{"motion_blur":enabled}))
 var density_row:=_row(b,12);_label(density_row,"像素密度",16,BLUE)
 var density:=OptionButton.new();density.set_meta("view_key","settings:pixel_density");density.custom_minimum_size.y=42;density.size_flags_horizontal=Control.SIZE_EXPAND_FILL;density_row.add_child(density)
 var density_keys:Array=["auto","balanced","low"]
 for title in ["自动清晰","均衡","低像素密度"]:density.add_item(title)
 density.select(maxi(0,density_keys.find(str(state.get("settings",{}).get("pixel_density","auto")))))
 density.item_selected.connect(func(index):_act("settings",{"pixel_density":density_keys[index]}))
 density.tooltip_text="自动清晰：按窗口大小调整像素密度"
 var deadzone_row:=_row(b,12);_label(deadzone_row,"摇杆死区",16,BLUE)
 var deadzone:=HSlider.new();deadzone.set_meta("view_key","settings:controller_deadzone");deadzone.min_value=.10;deadzone.max_value=.45;deadzone.step=.05;deadzone.value=float(state.get("settings",{}).get("controller_deadzone",.22));deadzone.custom_minimum_size=Vector2(160,28);deadzone.size_flags_horizontal=Control.SIZE_EXPAND_FILL;deadzone_row.add_child(deadzone);deadzone.value_changed.connect(func(v):_act("settings",{"controller_deadzone":v}))
 _button(b,"切换全屏  [F11]","settings",{"toggle_fullscreen":true},TEAL,48)
 var done:=Button.new();done.set_meta("view_key","settings:done");done.set_meta("safe_modal_default",true);done.text="继续营业";done.custom_minimum_size.y=49;done.add_theme_stylebox_override("normal",_style(YELLOW,3,12));done.add_theme_color_override("font_color",INK);b.add_child(done);done.pressed.connect(func():settings_open=false;render(state))

func toast(text: String, tone: String = "info") -> void:
 if not _built:_build_root()
 _toast_raw_text=text;toast_panel.add_theme_stylebox_override("panel",_style(CORAL if tone in ["error","warning"] else TEAL if tone=="success" else YELLOW,3,12));_position_toast();toast_panel.show();toast_timer=4.5
 toast_panel.modulate.a=0;var tween:=create_tween();tween.tween_property(toast_panel,"modulate:a",1.0,.16)

func _process(delta: float) -> void:
 if toast_timer>0:
  toast_timer-=delta
  if toast_timer<=0:toast_panel.hide()

func is_blocking_modal() -> bool:
 return settings_open or dispatch_confirmation_open or not _cancel_confirmation_id.is_empty()

func set_input_device(gamepad:bool) -> void:
 _gamepad=gamepad
 if flight_labels.has("controls"):
  flight_labels.controls.text="左摇杆 / 十字键 升降    RB 全功率    A 触发回路" if _gamepad else ("W / S  或  ↑ / ↓  升降    Shift  全功率    Space  触发回路" if _extreme_mode() else "W / S  或  ↑ / ↓  升降    Shift  冲刺    Space  触发回路")

func controller_back() -> void:
 if dispatch_confirmation_open:_dismiss_dispatch()
 elif settings_open:settings_open=false;render(state)
 elif not _cancel_confirmation_id.is_empty():_cancel_confirmation_id="";toast_panel.hide();toast_timer=0;render(state)

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.keycode!=KEY_ESCAPE:return
 if dispatch_confirmation_open:
  _dismiss_dispatch();get_viewport().set_input_as_handled();return
 if settings_open:
  settings_open=false;render(state);get_viewport().set_input_as_handled();return
 if not _cancel_confirmation_id.is_empty():
  _cancel_confirmation_id="";toast_panel.hide();toast_timer=0;render(state);get_viewport().set_input_as_handled()

func _reduced_motion() -> bool:
 return bool(state.get("settings",{}).get("reduced_motion",false))

func _stop_motion() -> void:
 for tween in _motion_tweens.values():
  if is_instance_valid(tween):tween.kill()
 _motion_tweens.clear()

func _exit_tree() -> void:
 _stop_motion()

func _motion_for(node: Node, channel: String = "layout") -> Tween:
 var id:=str(node.get_instance_id())+":"+channel
 var old:Tween=_motion_tweens.get(id,null)
 if is_instance_valid(old):old.kill()
 var tween:=create_tween().bind_node(node)
 _motion_tweens[id]=tween
 # Capturing the Tween itself in its signal callback creates a RefCounted cycle,
 # including when kill() prevents finished from firing. Bind its identity only.
 tween.finished.connect(_finish_motion.bind(id,tween.get_instance_id()),CONNECT_ONE_SHOT)
 return tween

func _finish_motion(id: String, tween_id: int) -> void:
 var current:Tween=_motion_tweens.get(id,null)
 if is_instance_valid(current) and current.get_instance_id()==tween_id:_motion_tweens.erase(id)

func _enter_panel(node: Control, offset: Vector2, delay: float = 0.0, duration: float = .22) -> void:
 var target:=node.position
 var tween:=_motion_for(node)
 if _reduced_motion():
  node.modulate.a=.55;tween.tween_property(node,"modulate:a",1.0,.12);return
 node.position=target+offset;node.modulate.a=.35
 tween.set_parallel(true)
 tween.tween_property(node,"position",target,duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
 tween.tween_property(node,"modulate:a",1.0,minf(.12,duration)).set_delay(delay)

func _animate_mode_entry() -> void:
 content.modulate=Color.WHITE
 var count:=0
 for node in content.get_children():
  if not node is Control or node==_hotspot_layer:continue
  var offset:=Vector2(12,0)
  if node.position.y<160:offset=Vector2(0,-8)
  elif node.position.y>_size.y-300:offset=Vector2(0,12)
  elif mode in ["contracts","supply","help"]:offset=Vector2(12,0)
  elif mode=="report":offset=Vector2(0,12)
  _enter_panel(node,offset,minf(float(count)*.015,.045),.16)
  count+=1
 # No full-width decorative sweep across the storefront.

func _diagonal_sweep() -> void:
 var accent:=MotionAccent.new();accent.mouse_filter=Control.MOUSE_FILTER_IGNORE;accent.size=Vector2(258,80);accent.position=Vector2(-295,111);accent.z_index=-1;content.add_child(accent)
 var tween:=_motion_for(accent)
 tween.tween_property(accent,"position:x",26.0,.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
 tween.tween_interval(.035)
 tween.set_parallel(true)
 tween.tween_property(accent,"position:x",112.0,.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
 tween.tween_property(accent,"modulate:a",0.0,.13)
 tween.finished.connect(func():if is_instance_valid(accent):accent.queue_free())

func _wire_motion_feedback(node: Node) -> void:
 for child in node.get_children():_wire_motion_feedback(child)
 if not node is Button or node.has_meta("motion_feedback"):return
 node.set_meta("motion_feedback",true)
 node.add_theme_color_override("font_focus_color",node.get_theme_color("font_color"))
 var pressed:=node.get_theme_stylebox("pressed").duplicate() as StyleBoxFlat
 var hover:=node.get_theme_stylebox("hover").duplicate() as StyleBoxFlat
 node.add_theme_stylebox_override("pressed",pressed);node.add_theme_stylebox_override("hover",hover)
 node.button_down.connect(func():
  if not is_instance_valid(node) or _reduced_motion():return
  var t:=_motion_for(node,"feedback");t.set_parallel(true)
  t.tween_property(pressed,"expand_margin_left",-2.0,.055)
  t.tween_property(pressed,"expand_margin_right",-2.0,.055)
  t.tween_property(pressed,"expand_margin_top",-1.0,.055)
  t.tween_property(pressed,"shadow_offset",Vector2(1,1),.055)
 )
 node.button_up.connect(func():
  if not is_instance_valid(node):return
  pressed.expand_margin_left=0;pressed.expand_margin_right=0;pressed.expand_margin_top=0;pressed.shadow_offset=Vector2(4,5)
  if _reduced_motion():return
  hover.shadow_offset=Vector2(1,1)
  var t:=_motion_for(node,"feedback");t.tween_property(hover,"shadow_offset",Vector2(4,5),.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
 )

func update_launch(progress: float, phase: String) -> void:
 if mode!="flight":return
 # Moving a tall craft across the workshop must stay visible even if paused.
 # The ordinary flight status already names the transfer; reserve the central
 # ribbon for the charge/ignition shot once the craft is planted on its pad.
 if phase=="move":
  _launch_phase=phase
  _update_ascent_cue()
  if is_instance_valid(_launch_layer):_launch_layer.hide()
  return
 if is_instance_valid(_launch_layer):_launch_layer.show()
 if phase=="done":
  _launch_phase=phase
  _update_ascent_cue()
  if not is_instance_valid(_launch_layer) or _launch_dismissing:return
  _launch_dismissing=true
  var gone:=_launch_layer;var out:=_motion_for(gone)
  out.set_parallel(true);out.tween_property(gone,"modulate:a",0.0,.12)
  if not _reduced_motion():out.tween_property(gone,"position:x",gone.position.x+70,.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
  out.finished.connect(func():if is_instance_valid(gone):gone.queue_free())
  return
 if not is_instance_valid(_launch_layer):
  # The pilot starter is three modules tall. Keep the launch ribbon in the clear
  # band below the telemetry rather than covering its upper engine row.
  _launch_layer=LaunchRibbon.new();_launch_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;_launch_layer.position=Vector2((_size.x-464)/2,108 if _pilot_mode() else _size.y*.24);_launch_layer.size=Vector2(464,112);content.add_child(_launch_layer)
  _launch_title=_label(_launch_layer,"蓄能中",29,INK);_launch_title.position=Vector2(24,39)
  _launch_meter=ProgressBar.new();_launch_meter.position=Vector2(24,94);_launch_meter.size=Vector2(416,8);_launch_meter.show_percentage=false;_launch_meter.mouse_filter=Control.MOUSE_FILTER_IGNORE;_launch_layer.add_child(_launch_meter)
  _launch_dismissing=false
 _launch_meter.value=clampf(progress*100,0,100)
 if phase==_launch_phase:return
 _launch_phase=phase
 _update_ascent_cue()
 _launch_layer.phase=phase;_launch_layer.queue_redraw()
 match phase:
  "move":_launch_title.text="移送中"
  "charge":_launch_title.text="蓄能中"
  "ignition":_launch_title.text="点火！"
  "release":_launch_title.text="出发！  ↗"
  _:_launch_title.text=""
 if _reduced_motion():
  _launch_layer.modulate.a=.65;var t:=_motion_for(_launch_layer);t.tween_property(_launch_layer,"modulate:a",1.0,.09)
 else:
  _launch_layer.scale=Vector2.ONE;_launch_layer.modulate.a=.5
  var t:=_motion_for(_launch_layer);t.tween_property(_launch_layer,"modulate:a",1.0,.12)
