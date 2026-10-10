extends CanvasLayer
## The shop scene owns movement; this small native UI only captures input and
## requests one skip. No cargo, inventory, timing, dialogue or save mutations.
signal skip_requested(order_id:String)
const FONT=preload("res://assets/fonts/ChineseSans.otf")
const INK:=Color("15243d")
const CREAM:=Color("fff1ce")
const GOLD:=Color("f8c65b")
var _root:Control
var _canvas:Control
var _skip:Button
var _frame:Rect2
var _open:bool=false
var _order_id:String=""
var _phase:String=""
var _opened_frame:int=-1
var _generation:int=0
var _requested:bool=false
var _skip_count:int=0
var _focus_active:bool=true
var _return_focus:WeakRef

func _ready() -> void:
 layer=50
 _root=Control.new();_root.name="CooperativeLoadingScene";_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _root.mouse_filter=Control.MOUSE_FILTER_STOP;_root.mouse_force_pass_scroll_events=false;add_child(_root)
 _root.theme=Theme.new();_root.theme.default_font=FONT;_root.theme.default_font_size=20
 _root.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _canvas=Control.new();_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(_canvas)
 _skip=Button.new();_skip.name="SkipLoadingScene";_skip.text="跳过装货  ·  空格 / Esc";_skip.size=Vector2(290,48)
 _skip.add_theme_color_override("font_color",INK);_skip.add_theme_color_override("font_hover_color",INK);_skip.add_theme_color_override("font_pressed_color",INK)
 _skip.add_theme_color_override("font_focus_color",INK);_skip.add_theme_color_override("font_hover_pressed_color",INK)
 _skip.add_theme_stylebox_override("normal",_style(GOLD,INK,3,10));_skip.add_theme_stylebox_override("hover",_style(CREAM,INK,3,10))
 _skip.add_theme_stylebox_override("pressed",_style(Color("dfa64d"),INK,3,10));_skip.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),CREAM,2,0))
 _skip.pressed.connect(request_skip);_canvas.add_child(_skip)
 get_viewport().size_changed.connect(_layout);_layout();_root.hide();set_process_input(false)

func _style(fill:Color,border:Color,width:int,padding:int) -> StyleBoxFlat:
 var box:=StyleBoxFlat.new();box.bg_color=fill;box.border_color=border;box.set_border_width_all(width)
 box.content_margin_left=padding;box.content_margin_right=padding;box.content_margin_top=padding;box.content_margin_bottom=padding
 return box

func set_art_frame(frame:Rect2) -> void:
 _frame=frame;_layout()

func _layout() -> void:
 if not is_instance_valid(_canvas):return
 var frame:Rect2=_frame if _frame.has_area() else get_viewport().get_visible_rect()
 var scale_factor:int=clampi(floori(frame.size.y/720.0),1,3)
 _canvas.position=frame.position.round();_canvas.scale=Vector2.ONE*scale_factor;_canvas.size=(frame.size/float(scale_factor)).floor()
 _skip.position=Vector2(maxf(16,_canvas.size.x-_skip.size.x-28),maxf(92,_canvas.size.y-76)).round()

func update_state(snapshot:Dictionary) -> void:
 var order_id:String=str(snapshot.get("order_id",""))
 var should_open:bool=bool(snapshot.get("loading",false)) and not order_id.is_empty()
 if not should_open:close();return
 if not _open or order_id!=_order_id:
  _generation+=1;_order_id=order_id;_opened_frame=Engine.get_process_frames();_requested=false;_open=true;_skip.disabled=not _focus_active
  var owner_node:Control=get_viewport().gui_get_focus_owner()
  _return_focus=weakref(owner_node) if is_instance_valid(owner_node) else null
  _root.show();set_process_input(true);_focus_skip.call_deferred(_generation)
 # Keep phase identity for diagnostics only. Character action carries the scene;
 # no visible narration is needed over the shop painting.
 _phase=str(snapshot.get("phase",""))

func _focus_skip(generation:int) -> void:
 if _open and generation==_generation and not _requested:_skip.grab_focus()

func request_skip() -> void:
 # The key that closed dialogue must not also skip the scene it just created.
 if not _open or _requested or not _focus_active or Engine.get_process_frames()<=_opened_frame:return
 _requested=true;_skip.disabled=true;_skip_count+=1;skip_requested.emit(_order_id)

func close() -> void:
 if not _open:return
 _open=false;_generation+=1;_order_id="";_phase="";_requested=false
 _root.hide();set_process_input(false)
 var previous:Control=_return_focus.get_ref() as Control if _return_focus!=null else null
 if is_instance_valid(previous) and previous.is_visible_in_tree():previous.grab_focus()
 _return_focus=null

func is_open() -> bool:return _open

func set_focus_active(active:bool) -> void:
 _focus_active=active
 if is_instance_valid(_skip):_skip.disabled=_requested or not active

func set_input_device(gamepad:bool) -> void:
 if is_instance_valid(_skip):_skip.text="跳过装货  ·  A / B" if gamepad else "跳过装货  ·  空格 / Esc"

func _input(event:InputEvent) -> void:
 if not _open or not event is InputEventKey or not event.pressed:return
 if event.keycode==KEY_F11:return
 if not event.echo and event.keycode in [KEY_SPACE,KEY_ESCAPE,KEY_ENTER,KEY_KP_ENTER]:request_skip()
 # A focused old editor control cannot rotate/delete/undo during the scene.
 get_viewport().set_input_as_handled()

func debug_snapshot() -> Dictionary:
 return {"open":_open,"order_id":_order_id,"phase":_phase,"requested":_requested,"skip_count":_skip_count,"focus_active":_focus_active,
  "skip_rect":_skip.get_global_rect(),"frame":_frame,"generation":_generation}
