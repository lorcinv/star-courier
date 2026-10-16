extends CanvasLayer
## One optional, local examination. No economics, story mutation or persistence.
const ACTION:String="investigate_black_marble"
const TITLE:String="黑色弹珠"
const QUOTE:String="一颗微缩黑洞，易碎，千万不要弄摔着了，可能会导致一些严重的小问题。"
const PROP_BOTTOM:Vector2=Vector2(610,363)
const PROP_WIDTH:float=36.0
const STATION_X:float=558.0
const STATION_RADIUS:float=28.0
const ART_ID:String="investigation/black-marble-pixel"
const PANEL_SIZE:Vector2=Vector2(620,228)
const FONT=preload("res://assets/fonts/ChineseSans.otf")
var host
var _root:Control
var _canvas:Panel
var _body:Label
var _close:Button
var _open:bool=false
var _owner:int=0

func _ready() -> void:
 layer=24;name="ShopInvestigation";process_mode=Node.PROCESS_MODE_ALWAYS
 _root=Control.new();_root.name="OptionalExaminationModal";_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _root.mouse_filter=Control.MOUSE_FILTER_STOP;_root.mouse_force_pass_scroll_events=false;add_child(_root)
 _root.theme=Theme.new();_root.theme.default_font=FONT;_root.theme.default_font_size=24
 var shade:=ColorRect.new();shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.color=Color(.02,.03,.06,.40);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(shade)
 _canvas=Panel.new();_canvas.name="ExaminationPanel";_canvas.size=PANEL_SIZE;_canvas.mouse_filter=Control.MOUSE_FILTER_STOP
 _canvas.add_theme_stylebox_override("panel",_style(Color("f7e3b4"),Color("15253a"),3));_root.add_child(_canvas)
 _label(Rect2(28,18,564,34),TITLE,24)
 _body=_label(Rect2(28,65,564,85),QUOTE,26);_body.name="ExactExaminationText";_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 _close=Button.new();_close.name="CloseExamination";_close.position=Vector2(430,168);_close.size=Vector2(162,40);_close.text="关闭  Esc";_close.focus_mode=Control.FOCUS_ALL
 _close.add_theme_font_size_override("font_size",20);_close.add_theme_color_override("font_color",Color("f7e3b4"));_close.add_theme_color_override("font_hover_color",Color("f7e3b4"));_close.add_theme_color_override("font_pressed_color",Color("f7e3b4"))
 for state in ["normal","hover","pressed"]:_close.add_theme_stylebox_override(state,_style(Color("15253a"),Color("5a83ac"),2))
 _close.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),Color("eab34a"),3));_canvas.add_child(_close);_close.pressed.connect(close)
 # The only native focus target loops to itself, including Tab/Shift+Tab.
 _close.focus_next=_close.get_path();_close.focus_previous=_close.get_path()
 get_viewport().size_changed.connect(_layout);_layout();_root.hide();set_process(false)

func bind(owner_node) -> void:host=owner_node
func _style(fill:Color,border:Color,width:int) -> StyleBoxFlat:
 var value:=StyleBoxFlat.new();value.bg_color=fill;value.border_color=border;value.set_border_width_all(width);return value
func _label(rect:Rect2,text_value:String,font_size:int) -> Label:
 var value:=Label.new();value.position=rect.position;value.size=rect.size;value.text=text_value;value.mouse_filter=Control.MOUSE_FILTER_IGNORE
 value.add_theme_font_size_override("font_size",font_size);value.add_theme_color_override("font_color",Color("15253a"));_canvas.add_child(value);return value
func _layout() -> void:
 if not is_instance_valid(_canvas):return
 if _open and is_instance_valid(host) and is_instance_valid(host.courier_input):host.courier_input.quarantine()
 var screen:Vector2=get_viewport().get_visible_rect().size
 var zoom:int=clampi(floori(screen.y/720.0),1,3)
 _canvas.scale=Vector2.ONE*zoom;_canvas.position=((screen-PANEL_SIZE*zoom)*.5).round()
func is_open() -> bool:return _open
func _available() -> bool:
 if not is_instance_valid(host) or not is_instance_valid(host.world) or not is_instance_valid(host.hud) or host.economy.review_load_blocked or host.closing or host.page!="hub" or host._review_phone_is_open() or host._dialogue_is_open() or host._loading_scene_active() or host.hud.is_blocking_modal() or not host._pending_story.is_empty():return false
 if not is_instance_valid(host.courier_input) or not host.courier_input.focused:return false
 return host.world.investigation_owned_by(_owner) if _open else host.world.can_open_investigation()
func begin() -> bool:
 if _open or not is_node_ready() or not _available():return false
 if host.courier_input.desired_context()!="shop":return false
 var owner:int=get_instance_id()
 if not host.world.acquire_investigation(owner):return false
 _owner=owner;_open=true;_root.show();_layout();_close.grab_focus();set_process(true)
 host.workshop_input.cancel();host.courier_input.quarantine();host._clear_pilot_input()
 host.courier_input.synchronize();set_input_device(host.courier_input.gamepad)
 return true
func close() -> void:
 if not _open and _owner==0:return
 _open=false
 if is_instance_valid(_close) and _close.is_inside_tree():_close.release_focus()
 if is_instance_valid(_root):_root.hide()
 set_process(false)
 var owner:int=_owner;_owner=0
 # No background native action receives focus or any held input on dismissal.
 if is_instance_valid(host):
  if is_instance_valid(host.world):host.world.release_investigation(owner)
  host.workshop_input.cancel();host._clear_pilot_input()
  if is_instance_valid(host.courier_input):
   host.courier_input.quarantine()
   if host.courier_input.is_inside_tree():host.courier_input.synchronize()
func set_input_device(gamepad:bool) -> void:
 if is_instance_valid(_close):_close.text="关闭  B" if gamepad else "关闭  Esc"
func _process(_delta:float) -> void:
 if _open and not _available():close()
func debug_snapshot() -> Dictionary:
 return {"open":_open,"text":_body.text,"panel_rect":_canvas.get_global_rect(),"body_rect":_body.get_global_rect(),"owner":_owner,"mouse_filter":_root.mouse_filter}

func _exit_tree() -> void:close()
