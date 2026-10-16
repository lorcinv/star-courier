extends CanvasLayer
const SpatialShields=preload("res://scripts/spatial_shield_v1.gd")
const SPATIAL_SHIELD_VERSIONS:Array[String]=["pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const CellCombinations=preload("res://scripts/cell_combinations_v6.gd")
const RiftPresenter=preload("res://scripts/rift_delivery_presenter_v5.gd")
const RiftRiskUI=preload("res://scripts/delivery_rift_risk_ui_v1.gd")
const MoonAscentPresenter=preload("res://scripts/moon_ascent_presenter_v4.gd")
const DeliveryUI=preload("res://scripts/delivery_ui_v3.gd")
const DeliveryRoutePreview=preload("res://scripts/delivery_route_preview_v1.gd")
const DeliveryLaunchPreview=preload("res://scripts/delivery_launch_preview_v3.gd")
const CargoIntegrityBar=preload("res://scripts/cargo_integrity_bar_v3.gd")
const DisplayMetrics=preload("res://scripts/demo_display_metrics.gd")
const DeliveryDirectionCue=preload("res://scripts/delivery_direction_cue.gd")
const FreeFlightFraming=preload("res://scripts/free_flight_framing_2d.gd")
const DemoRasterSkin=preload("res://scripts/demo_raster_skin.gd")
const ModuleControlsUI=preload("res://scripts/module_controls_ui.gd")
const CouplerCutGroups=preload("res://scripts/coupler_cut_preview.gd")
const WorkshopParts=preload("res://scripts/workshop_parts_v2.gd")
const CorridorFraming=preload("res://scripts/corridor_framing_2d.gd")
const MoonProfile=preload("res://scripts/pilot_moon_profile.gd")
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
const PIRATE_CONTROL_VERSION:String="pilot-pirate-drill-v1"
const PIRATE_CONTROL_VERSION_V2:String="pilot-pirate-drill-v2"
const FlightReceipt=preload("res://scripts/flight_receipt.gd")
## Scene-first presentation. Domain state lives in main; this layer emits intent only.
## Every full-viewport container ignores mouse events. Only visible controls capture them.
signal shield_preview_changed(preview: Dictionary)
signal accelerator_preview_changed(preview: Dictionary)
signal action_requested(action: String, payload: Variant)
signal target_popup_mouse_released(button: int)

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
var palette_category: String = WorkshopParts.DEFAULT_CATEGORY
var report_costs_open: bool = false
var settings_open: bool = false
var flight_labels: Dictionary = {}
var _flight_receipt=FlightReceipt.new()
var progress_bar: ProgressBar
var _pause_button: WeakRef
var _flight_save_exit_button:WeakRef
var _flight_pointer_buttons:Array[WeakRef]=[]
var _size: Vector2 = Vector2(1440, 900)
var _art_frame: Rect2 = Rect2()
var _art_frame_enabled: bool = false
var _ui_scale: float = 1.0
var _toast_style:StyleBoxFlat
var _built: bool = false
var _last_mode: String = ""
var _cancel_confirmation_id: String = ""
var _hotspot_layer: Control
var _hotspot_buttons: Dictionary = {}
var dispatch_confirmation_open: bool = false
var _dispatch_contract_id: String = ""
var _free_order_upgrade:Dictionary={}
var _free_upgrade_generation:int=0
var _motion_tweens: Dictionary = {}
var _last_selection_id: int = -999
var _gamepad:bool=false
var _input_context:String="ui"
var _workshop_labels:Dictionary={}
var _last_modal: String = ""
var _launch_layer: Control
var _launch_title: Label
var _launch_meter: ProgressBar
var _launch_phase: String = ""
var _launch_dismissing: bool = false
var _render_generation: int = 0
var _target_popup_id: int = 0
var _target_popup_epoch: int = 0
var _scroll_memory: Dictionary = {}
var _modal_return_focus: String = ""
var _missing_icon_reports: Dictionary = {}
var _inspector_selection_key:String=""
var _native_icon_cache:Dictionary={}
var _ascent_cue: Control
var _ascent_telemetry: Dictionary = {}
var _impact_absorbed: float = 0.0
var _impact_energy: float = 0.0
var _impact_cue_until: float = -1.0
var _extreme_elapsed: float = 0.0
const SHOP_AVAILABILITY_ACTIONS:Array[String]=["focus_counter","next_contract","accept_contract","customer_reviews","upgrade_free_offers","swap_accepted_free","upgrade_force_offers","retire_legacy_parts","upgrade_delivery_offers"]
var _shop_action_buttons:Array[Button]=[]
var _detail_open:Dictionary={}
var _destination_cue
var _energy_bar:ProgressBar
var _cargo_integrity_bar:ProgressBar
var _delivery_launch_labels:Dictionary={}
var _delivery_launch_preview:Control
var _delivery_launch_buttons:Array[Button]=[]


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
 var display_density:float=1.0
 var phase: String = "charge"
 func _draw() -> void:
  draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*display_density)
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
 toast_panel = PanelContainer.new();toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE;_toast_style=_style(YELLOW,3,12);toast_panel.add_theme_stylebox_override("panel",_toast_style);root.add_child(toast_panel)
 toast_label = _label(toast_panel, "", 16);toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
 toast_panel.hide()
 _apply_art_frame()

func set_art_frame(rect: Rect2) -> void:
 # Physical viewport coordinates; bounds/input stay tied to this rectangle.
 # Framed HUD rerenders native metrics at 720/1080/1440/2160 profiles.
 # The CanvasItem transform remains 1x; text/hit areas use integer output pixels.
 # _size is its local logical size. The caller renders state after updating
 # the stage. Empty/invalid sizes restore the unscaled legacy viewport HUD.
 _art_frame_enabled=rect.size.x>0.0 and rect.size.y>0.0
 _art_frame=Rect2(rect.position.round(),rect.size.round()) if _art_frame_enabled else Rect2()
 if _art_frame_enabled and (_art_frame.size.x<=0.0 or _art_frame.size.y<=0.0):_art_frame_enabled=false;_art_frame=Rect2()
 if _built:_apply_art_frame()

func _apply_art_frame() -> void:
 if not _built:return
 _ui_scale=DisplayMetrics.factor(_art_frame.size) if _art_frame_enabled else 1.0
 root.scale=Vector2.ONE
 root.clip_contents=_art_frame_enabled
 if _art_frame_enabled:
  root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
  root.position=_art_frame.position
  _size=_art_frame.size/_ui_scale;root.size=_art_frame.size
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

var _accelerator_blueprint_key:PackedByteArray=PackedByteArray()
var _accelerator_blueprint_value:Dictionary={}
var _accelerator_blueprint_calls:int=0
var _accelerator_workshop_labels:Dictionary={}
var _shield_workshop_labels:Dictionary={}
var _shield_blueprint_key:PackedByteArray=PackedByteArray()
var _shield_blueprint_value:Dictionary={}
var _shield_blueprint_calls:int=0

func _accelerator_blueprint(parts:Array,order:Dictionary,id:int) -> Dictionary:
 var key:PackedByteArray=var_to_bytes([parts,order,id])
 if key!=_accelerator_blueprint_key:
  _accelerator_blueprint_key=key
  _accelerator_blueprint_value=CellCombinations.preview_blueprint(parts,order,id)
  _accelerator_blueprint_calls+=1
 return _accelerator_blueprint_value.duplicate(true)

func sync_workshop_preview(parts:Array,part:Dictionary) -> void:
 # Main owns committed/sanitized edits. Keep the retained slider and its focus;
 # only replace the copied blueprint and refresh its dependent presentation.
 if mode!="workshop" or str(state.get("assembly_mode","craft"))!="craft" or not str(state.get("control_version","")) in DeliveryUI.CELL_VERSIONS:return
 state.parts=parts.duplicate(true)
 var selected:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
 if int(selected.get("id",-1))==int(part.get("id",-2)):
  for key in part:selected[key]=part[key]
 _refresh_accelerator_workshop_preview()
 _refresh_shield_workshop_preview()

func _refresh_accelerator_workshop_preview() -> void:
 if _accelerator_workshop_labels.is_empty():return
 var part:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
 if str(part.get("type",""))!="accelerator":return
 var parts:Array=state.get("parts",[])
 var version:String=str(state.get("control_version",""))
 var preview:Dictionary=_accelerator_blueprint(parts,state.get("activeorder",{}),int(part.get("id",-1)))
 var readiness:Dictionary=WorkshopParts.readiness(part,parts,_pilot_mode(),false,version)
 var trigger_problem:String=str(readiness.text) if not bool(readiness.ready) and bool(preview.get("can_fire",false)) else ""
 var ready:bool=bool(readiness.ready) and bool(preview.get("can_fire",false))
 _accelerator_workshop_labels.status.text=DeliveryUI.accelerator_copy(preview,true)+("\n"+trigger_problem if not trigger_problem.is_empty() else "")
 _accelerator_workshop_labels.status.add_theme_color_override("font_color",TEAL if ready else CORAL)
 var details:Dictionary=DeliveryUI.accelerator_details(preview)
 for key in ["motion","impact","cost","scope"]:
  var label:Label=_accelerator_workshop_labels[key]
  label.text=str(details.get(key,""));label.visible=not details.is_empty()
 _accelerator_workshop_labels.impact.tooltip_text=str(details.get("tooltip",""))
 _accelerator_workshop_labels.impact.add_theme_color_override("font_color",CORAL if bool(details.get("below_minimum",false)) else TEAL)
 var trigger:Label=content.find_child("ModuleStartupStatus",true,false)
 if trigger!=null:trigger.text=WorkshopParts.trigger_text(part,parts,_pilot_mode(),false,version)
 var visual:Dictionary=preview.duplicate(true);visual.control_version=version;visual.accelerator_id=int(part.get("id",-1));visual.context="workshop"
 accelerator_preview_changed.emit(visual)

func _refresh_shield_workshop_preview() -> void:
 if _shield_workshop_labels.is_empty():return
 var part:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
 var route:Dictionary=state.get("activeorder",{})
 if str(part.get("type",""))!="shield" or str(route.get("control_version","")) not in SPATIAL_SHIELD_VERSIONS:return
 var key:PackedByteArray=var_to_bytes([state.get("parts",[]),route,int(part.get("id",-1))])
 if key!=_shield_blueprint_key:
  _shield_blueprint_key=key
  _shield_blueprint_value=SpatialShields.preview_blueprint(state.get("parts",[]),route,int(part.get("id",-1)))
  _shield_blueprint_calls+=1
 var preview:Dictionary=_shield_blueprint_value.duplicate(true)
 var generators:Array=preview.get("generators",[])
 if generators.is_empty():
  _shield_workshop_labels.coverage.text="护盾范围待更新";_shield_workshop_labels.state.text=""
  shield_preview_changed.emit({});return
 var generator:Dictionary=generators[0]
 var active:bool=bool(generator.get("active",false))
 _shield_workshop_labels.coverage.text="半径 %.2f 格 · 可护 %d 格"%[float(generator.get("radius_m",0)),generator.get("protected_ids",[]).size()]
 _shield_workshop_labels.coverage.add_theme_color_override("font_color",TEAL if active else DIM)
 _shield_workshop_labels.state.text="圈内格中心可受护 · 按余电吸收" if active else SpatialShields.reason_text(str(generator.get("reason","")))
 _shield_workshop_labels.state.add_theme_color_override("font_color",TEAL if active else DIM)
 preview.control_version=route.control_version;preview.context="workshop"
 shield_preview_changed.emit(preview)

func render(data: Dictionary) -> void:
 var preserved:=_capture_ui_state() if _built and str(data.get("mode","hub"))==mode else {}
 # A resize/settings rebuild owns no new flight. Retain its latest snapshot
 # when the controller sends layout state without telemetry. A real mode,
 # contract, protocol, trial change or elapsed rewind starts a clean receipt.
 var same_flight:bool=mode=="flight" and str(data.get("mode","hub"))=="flight" and _flight_identity(state)==_flight_identity(data)
 var previous_flight:Dictionary=state.get("flight",{}).duplicate(true) if same_flight else {}
 state = data.duplicate(true)
 if same_flight and not state.has("flight"):state.flight=previous_flight
 if not same_flight:
  _flight_receipt.reset()
  _impact_absorbed=0;_impact_energy=0;_impact_cue_until=-1;_extreme_elapsed=0
 if not is_inside_tree():return
 _render_generation+=1
 _target_popup_id=0
 _build_root()
 _apply_art_frame()
 # Construct fresh controls under the authored theme so their automatic minimum
 # sizes cannot inherit the previous display profile before metric capture.
 DisplayMetrics.apply_theme(root,1.0)
 mode = str(state.get("mode", "hub"))
 accelerator_preview_changed.emit({})
 shield_preview_changed.emit({})
 var incoming_selection:=int(state.get("selectedpart",state.get("selected_part",{})).get("id",-1))
 if mode=="workshop" and incoming_selection>=0 and (incoming_selection!=_last_selection_id or _last_mode!="workshop"):palette_open=false
 if mode!=_last_mode:toast_panel.hide();toast_timer=0
 if not _cancel_confirmation_id.is_empty():
  var order:Dictionary=state.get("activeorder",{})
  if mode!=_last_mode or not _has_accepted() or str(order.get("contract_id",order.get("id","accepted")))!=_cancel_confirmation_id:_cancel_confirmation_id=""
 _stop_motion()
 _launch_layer=null;_launch_phase="";_launch_dismissing=false
 _hotspot_layer=null;_hotspot_buttons.clear();_shop_action_buttons.clear()
 for child in content.get_children():content.remove_child(child);child.queue_free()
 flight_labels.clear();_workshop_labels.clear();_accelerator_workshop_labels.clear();_shield_workshop_labels.clear();_delivery_launch_labels.clear();_delivery_launch_buttons.clear();_delivery_launch_preview=null;_cargo_integrity_bar=null;progress_bar = null;_pause_button=null;_flight_save_exit_button=null;_flight_pointer_buttons.clear()
 _ascent_cue=null;_ascent_telemetry.clear()
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
 if free_order_upgrade_open():_free_upgrade_confirmation()
 if settings_open:_settings()
 DemoRasterSkin.apply_hud(content)
 DisplayMetrics.apply_theme(root,_ui_scale)
 DisplayMetrics.apply_stage(content,_ui_scale)
 _wire_motion_feedback(content)
 if mode != _last_mode:
  _animate_mode_entry()
  _last_mode=mode
 else:
  var selected_id:=int(state.get("selectedpart",state.get("selected_part",{})).get("id",-1))
  if mode=="workshop" and selected_id!=_last_selection_id:
   for node in content.get_children():
    if node.has_meta("context_panel"):_enter_panel(node,Vector2(28,0),0,.18)
 var modal:="settings" if settings_open else "dispatch" if dispatch_confirmation_open else "free_upgrade" if free_order_upgrade_open() else ""
 if not modal.is_empty() and modal!=_last_modal:
  for node in content.get_children():
   if node.has_meta("modal_panel"):_enter_panel(node,Vector2(-32,14),0,.21)
 _apply_shop_action_availability()
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
 # A bound one-shot signal is disconnected when this HUD is freed. An await
 # would attempt to resume a destroyed script after returning to the title.
 var callback:Callable=_finish_restore_ui_state.bind(saved,generation,modal)
 if not get_tree().process_frame.is_connected(callback):get_tree().process_frame.connect(callback,CONNECT_ONE_SHOT)

func _finish_restore_ui_state(saved: Dictionary, generation: int, modal: String) -> void:
 if not is_inside_tree() or generation!=_render_generation:return
 var unavailable_focus:bool=false
 var focus_key:=str(saved.get("focus",""))
 if str(saved.get("modal",""))!=modal:
  if modal.is_empty():focus_key=_modal_return_focus;_modal_return_focus=""
  else:focus_key=""
 for node in content.find_children("*","Control",true,false):
  var key:=_view_key(node)
  if node is ScrollContainer and _scroll_memory.has(key):
   var offset:Vector2i=_scroll_memory[key];node.scroll_horizontal=offset.x;node.scroll_vertical=offset.y
  if key.is_empty() or key!=focus_key:continue
  if node is BaseButton and node.disabled:unavailable_focus=true;continue
  if node.focus_mode==Control.FOCUS_NONE:continue
  node.grab_focus()
  if node is LineEdit and saved.has("edit"):
   _restore_edit.call_deferred(node,saved.edit,generation)
 if unavailable_focus and get_viewport().gui_get_focus_owner()==null:_focus_available_action()

func _restore_edit(editor: LineEdit, edit: Dictionary, generation: int) -> void:
 # SpinBox schedules its own focus-enter formatting. Apply the unfinished
 # text after that internal update, without committing or emitting a change.
 if not is_inside_tree() or generation!=_render_generation:return
 var callback:Callable=_finish_restore_edit.bind(editor,edit,generation)
 if not get_tree().process_frame.is_connected(callback):get_tree().process_frame.connect(callback,CONNECT_ONE_SHOT)

func _finish_restore_edit(editor: LineEdit, edit: Dictionary, generation: int) -> void:
 if not is_inside_tree() or generation!=_render_generation or not is_instance_valid(editor) or not editor.has_focus():return
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
  var box:Rect2=DisplayMetrics.rect(Rect2(x,y,width,58),_ui_scale)
  toast_panel.position=box.position;toast_panel.size=box.size
  toast_label.add_theme_font_size_override("font_size",DisplayMetrics.font_size(16,_ui_scale))
  toast_panel.add_theme_stylebox_override("panel",DisplayMetrics.style(_toast_style,_ui_scale))

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
 var b:=Button.new();b.text=text;b.custom_minimum_size.y=height;b.add_theme_stylebox_override("normal",_style(fill,2,8,false));b.add_theme_color_override("font_color",WHITE if fill.get_luminance()<.42 else INK);b.pressed.connect(func():_act(action,payload));b.set_meta("view_key","action:"+action+":"+JSON.stringify(payload));parent.add_child(b);_register_shop_action(b,action)
 if mode=="flight" and action in ["pause","abort","set_speed"]:_flight_pointer_buttons.append(weakref(b))
 return b

func _register_shop_action(button:Button,action:String) -> void:
 if action not in SHOP_AVAILABILITY_ACTIONS:return
 button.set_meta("shop_action",action);_shop_action_buttons.append(button)

func update_shop_action_availability(availability:Dictionary,counter_id:String="") -> void:
 if state.get("shop_action_availability",{})==availability and str(state.get("counter_customer_id",""))==counter_id:return
 state.counter_customer_id=counter_id
 state.shop_action_availability=availability.duplicate()
 if _built:_apply_shop_action_availability()

func _apply_shop_action_availability() -> void:
 var lost_focus:bool=false
 for button in _shop_action_buttons:
  if not is_instance_valid(button):continue
  # Capture intrinsic locks only after the drawer has finished building.
  # Runtime ownership can never unlock a reputation-locked contract.
  if not button.has_meta("shop_base_disabled"):
   button.set_meta("shop_base_disabled",button.disabled)
   button.set_meta("shop_base_focus",button.focus_mode)
  var available:bool=bool(state.get("shop_action_availability",{}).get(str(button.get_meta("shop_action")),true))
  if button.has_meta("shop_contract_id") and state.has("counter_customer_id"):
   available=available and str(button.get_meta("shop_contract_id"))==str(state.counter_customer_id)
  var disabled:bool=bool(button.get_meta("shop_base_disabled")) or not available
  if disabled and button.has_focus():button.release_focus();lost_focus=true
  button.disabled=disabled
  if disabled:button.focus_mode=Control.FOCUS_NONE
  elif not settings_open and not dispatch_confirmation_open and not free_order_upgrade_open():button.focus_mode=int(button.get_meta("shop_base_focus"))
  if bool(button.get_meta("scene_action",false)):
   for child in button.get_children():
    if child is CanvasItem:child.modulate=Color(1,1,1,.45 if disabled else 1.0)
 if lost_focus:_focus_available_action()

func _focus_available_action() -> void:
 # Disabled controls never retain keyboard/gamepad focus. Do not steal
 # focus from an owning modal, and do not activate the replacement control.
 if get_viewport().gui_get_focus_owner()!=null:return
 for candidate in content.find_children("*","Button",true,false):
  if candidate.is_visible_in_tree() and not candidate.disabled and candidate.focus_mode!=Control.FOCUS_NONE:
   candidate.grab_focus();return

func _act(action: String, payload: Variant = null) -> void:
 if action=="save_and_quit" and mode=="flight":
  var flight:Dictionary=state.get("flight",{})
  if not bool(flight.get("paused",false)) or not bool(state.get("save_exit_available",false)):return
 if free_order_upgrade_open():return
 if not bool(state.get("shop_action_availability",{}).get(action,true)):return
 if action=="accept_contract" and state.has("counter_customer_id") and str(payload)!=str(state.counter_customer_id):return
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
 if mode=="hub":
  _phone_launcher()
  var completion:String=DeliveryUI.completed_chapter_copy(state)
  if not completion.is_empty():
   var debt:Variant=state.delivery_chapter_status.get("debt")
   var in_debt:bool=(debt is int or debt is float) and is_finite(float(debt)) and float(debt)>0.0
   var completed:=_label(content,completion+(" · 打烊后可接轻货偿债" if in_debt else " · 可继续接单复送"),14,TEAL);completed.name="CompletedChapterStatus";completed.position=Vector2(20,78)
   completed.tooltip_text="现有五关均已完成；之后的自选复送不重复推进章节或发放解锁奖励。负债时，打烊后有基础轻货可接。"
 if mode!="hub":
  var back:=_button(content,"‹  返回店铺","close_drawer",null,PANEL,36);back.position=Vector2(20,76);back.size=Vector2(136,36)

func _phone_launcher() -> void:
 # Same image-generated casing as the open device; no new raster or modal owner.
 var b:=_button(content,"","customer_reviews",null,PANEL,104)
 b.name="PhoneLauncher";b.tooltip_text="手机：打开客户留言应用";b.size=Vector2(66,104)
 b.position=Vector2(maxf(16,_size.x-86),maxf(16,_size.y-124))
 # At narrow sizes lift above the bottom-left dock instead of covering it.
 if b.position.x<540:b.position.y=maxf(16,_size.y-180)
 for state_name in ["normal","hover","pressed","disabled"]:b.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
 var focus:=_style(Color(0,0,0,0),2,0,false);focus.border_color=YELLOW;b.add_theme_stylebox_override("focus",focus)
 var screen:=ColorRect.new();screen.color=PANEL_LIGHT;screen.position=Vector2(5,10);screen.size=Vector2(56,82);screen.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(screen)
 var casing:=TextureRect.new();casing.texture=_native_icon("res://assets/2d_v5/reviews/customer-review-phone-ninepatch-source.png",Vector2i(33,52));casing.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;casing.size=b.size;casing.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(casing)
 var icon:=_part_icon(b,"cargo",Vector2(32,32));icon.position=Vector2(17,28);icon.size=Vector2(32,32)
 var caption:=_label(b,"手机",12,WHITE);caption.position=Vector2(21,67)
 b.mouse_entered.connect(func():if not b.disabled:screen.color=BLUE)
 b.mouse_exited.connect(func():screen.color=PANEL_LIGHT)

func _has_order_details(order: Dictionary) -> bool:
 return order.has("name") and order.has("distance") and not str(order.get("name","")).is_empty()

func _ticket() -> void:
 var order:Dictionary=state.get("activeorder",{})
 var w:=252.0
 var has_order:=_has_order_details(order)
 var swap_available:bool=bool(state.get("free_order_upgrade",{}).get("accepted",{}).get("available",false))
 var p:=_panel(Rect2(_size.x-w-20,20,w,(156 if swap_available else 120) if has_order else 76),CREAM,null,10)
 p.name="CurrentWaybill"
 var paper:=p.get_theme_stylebox("panel") as StyleBoxFlat;paper.border_width_left=4;paper.border_color=YELLOW
 var b:=_box(p,2)
 if not has_order:
  var phase:=str(state.get("phase","morning"))
  _label(b,"ORDER / 当前目标",11,BLUE)
  if phase in ["night","evening"]:_label(b,"补好库存，准备明天。",16)
  elif state.get("contracts",[]).is_empty():_label(b,"今天的委托都处理好了。",16)
  else:_label(b,"去柜台接一单",19)
  return
 var r:=_row(b,4);_label(r,"ORDER / 当前目标",11,BLUE);_spacer(r)
 if _has_accepted():_cancel_button(r,order,24)
 var ticket_name:=_label(b,"送到"+_destination_name(order),19)
 ticket_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;ticket_name.tooltip_text=ticket_name.text
 _label(b,str(order.get("cargo","客户货物")),13,MUTED)
 if DeliveryUI.applies(order):_label(b,DeliveryUI.requirement(order),12,BLUE)
 _label(b,"准备好后，点击「发射配送」" if mode=="workshop" else "下一步：打开装配工位",12,BLUE)
 if swap_available:_button(b,"免费换单","swap_accepted_free",null,YELLOW,30)

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
 b.pressed.connect(func():_act(action));b.set_meta("view_key","action:"+action+":null");content.add_child(b);_register_shop_action(b,action);b.set_meta("scene_action",true)
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
 var orders:Array=state.get("contracts",[])
 # A route preview makes even one card taller than the old 258px estimate.
 # Use the existing available drawer height so the primary action starts in
 # view; expanded details and multiple cards remain in the same scroll body.
 var has_route_preview:bool=orders.any(func(order):return not DeliveryUI.route_copy(order).is_empty())
 var b:=_drawer("接一单，出发。","委托柜台",424,0.0 if has_route_preview else minf(794,130+float(orders.size())*258))
 var upgrades:Dictionary=state.get("free_order_upgrade",{})
 if bool(upgrades.get("available",{}).get("available",false)):_button(b,"更换新版委托","upgrade_free_offers",null,TEAL,38)
 if bool(upgrades.get("accepted",{}).get("available",false)):_button(b,"免费换单","swap_accepted_free",null,YELLOW,38)
 if bool(upgrades.get("force",{}).get("available",false)):_button(b,"免费升级操控","upgrade_force_offers",null,TEAL,38)
 _parts_retirement_entry(b)
 if bool(upgrades.get("delivery",{}).get("available",false)):_button(b,"进入首章配送","upgrade_delivery_offers",null,YELLOW,38)
 var body:=_scroll(b);body.get_parent().name="ContractList"
 var serial:=0
 for order in orders:
  serial+=1
  var locked:bool=bool(order.get("locked",int(state.get("reputation",0))<int(order.get("rep",0))))
  var card:=PanelContainer.new();card.name="Waybill%d"%serial
  var paper:=_style(CREAM if not locked else Color("c7c5b4"),1,12,false);paper.border_width_top=4;paper.border_color=YELLOW if not locked else EDGE;card.add_theme_stylebox_override("panel",paper);body.add_child(card)
  var cb:=_box(card,8)
  _para(cb,str(order.get("client","客户"))+" · "+str(order.get("cargo","货物")),16)
  _para(cb,"送到"+_destination_name(order),22)
  _label(cb,("最高运费 ¥%s" if _insured_order(order) else "运费 ¥%s")%str(order.get("reward",0)),22,BLUE)
  if DeliveryUI.applies(order):
   var requirement:=_para(cb,DeliveryUI.requirement(order),16,BLUE);requirement.name="DeliveryIntegrityRequirement"
  _delivery_route_sketch(cb,order)
  var contract_id:Variant=order.get("contract_id",order.get("id",0))
  var details:=_foldout(cb,"委托详情","order:"+str(contract_id))
  _para(details,str(order.get("story","这一份心意，就拜托你了。")),15,MUTED)
  _para(details,"%s · 货重 %.1f kg"%[DeliveryUI.order_distance_copy(order),float(order.get("weight",1.0))*3.0],14,BLUE)
  if not _is_free_order(order):
   _para(details,"奖励时限 %s s · 最迟 %s s"%[order.get("deadline",0),order.get("time_limit",order.get("deadline",0))],14,BLUE)
   _para(details,"完整度要求 %s%% · 收件速度 ≤ %s m/s"%[str(order.get("required",90)),str(order.get("max_delivery_speed","—"))],14,BLUE)
  if DeliveryUI.applies(order):
   _para(details,DeliveryUI.liability(order),14,Color("a13f3e"))
   _para(details,"试飞免费，不扣赔偿、不增债务。",14,BLUE)
  if order.has("risk"):_para(details,"注意："+str(order.risk),14,Color("a13f3e"))
  var choice_row:=_row(cb,8)
  var go:=_button(choice_row,"需要声望 %s"%str(order.get("rep",0)) if locked else "接下这单  →","accept_contract",contract_id,YELLOW,42);go.disabled=locked;go.size_flags_horizontal=Control.SIZE_EXPAND_FILL;go.set_meta("shop_contract_id",str(contract_id))
  if not locked:go.tooltip_text="客人到达柜台后即可接单。"
  var decline:=_button(choice_row,"婉拒","decline_contract",contract_id,WHITE,42);decline.tooltip_text="婉拒未接受的委托，不产生违约处罚。"

func _workshop_warning_text() -> String:
 var power:Dictionary=state.get("power_status",{})
 if not power.get("unpowered_cargo_ids",[]).is_empty():
  var power_text:String=("货舱无电：可滑行，主动装置需电" if DeliveryUI.cell_rules(state.get("activeorder",{})) else "货舱缺电芯" if power.get("battery_ids",[]).is_empty() else "货舱未接电芯")
  if not str(state.get("ship_stats",{}).get("warning","")).is_empty():power_text+="\n有零件位于工位外"
  return power_text
 return str(state.get("ship_stats",{}).get("warning",""))

func workshop_scene_rect() -> Rect2:
 # Screen coordinates, matching PixelStage's art-frame mapping. Leave current
 # controls visible and fit the WHOLE grid inside the genuinely usable region.
 var warning_text:String=_workshop_warning_text()
 var top:float=(258.0 if warning_text.contains("\n") else 238.0) if not warning_text.is_empty() else 176.0
 if not DeliveryUI.route_preview(state.get("activeorder",{})).is_empty():top=maxf(top,252.0)
 if not DeliveryUI.ascent_geometry_copy(state.get("activeorder",{})).is_empty():top=maxf(top,220.0)
 var bottom:float=_size.y-(244.0 if palette_open else 84.0)
 var local_rect:Rect2=Rect2(20,top,maxf(80,_size.x-368),maxf(80,bottom-top))
 var transform:Transform2D=root.get_global_transform_with_canvas()
 var native_rect:Rect2=DisplayMetrics.rect(local_rect,_ui_scale)
 return Rect2(transform*native_rect.position,native_rect.size)

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
 var retirement:Dictionary=state.get("free_order_upgrade",{}).get("parts",{})
 if bool(retirement.get("available",false)) or bool(retirement.get("deferred",false)):
  var cleanup:=_button(content,"整理旧零件" if bool(retirement.get("available",false)) else "旧单结束后整理","retire_legacy_parts",null,PANEL_LIGHT,36)
  cleanup.position=Vector2(332,127);cleanup.size=Vector2(168,36);cleanup.disabled=not bool(retirement.get("available",false));cleanup.tooltip_text="预览旧零件折换与原存档备份。" if not cleanup.disabled else "先按原规则完成当前旧委托，原发射台和装配会保留。"
 var order:Dictionary=state.get("activeorder",{})
 if not DeliveryUI.route_copy(order).is_empty():
  var route_panel:=_panel(Rect2(332,124,maxf(260,_size.x-700),120 if not DeliveryUI.route_preview(order).is_empty() else 88 if not DeliveryUI.ascent_geometry_copy(order).is_empty() else 38),PANEL,null,8)
  route_panel.name="WorkshopRouteSketch"
  _delivery_route_sketch(_box(route_panel,4),order)
 var ship:Dictionary=state.get("ship_stats",{})
 # Keep actual build warnings; engineering totals and grid-size copy are not a default task.
 var warning_text:String=_workshop_warning_text()
 if not warning_text.is_empty():
  var warning:=_panel(Rect2(20,176,300,72 if warning_text.contains("\n") else 52),YELLOW,null,8);warning.name="WorkshopPowerOrBoundsWarning";warning.tooltip_text=str(ship.get("warning",""));_para(warning,warning_text,16 if not state.get("power_status",{}).get("unpowered_cargo_ids",[]).is_empty() else 13)
 var selected:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
 if not selected.is_empty():_inspector(selected)
 elif _delivery_mode() and not is_craft:
  var launch_panel:=_panel(Rect2(_size.x-348,176,328,maxf(206,minf(440,_size.y-(420 if palette_open else 268)))),PANEL,null,10)
  launch_panel.name="DeliveryLaunchControls"
  var launch_box:=_box(launch_panel,6);_label(launch_box,"发射台设置",18,TEAL)
  _delivery_launcher_controls(_scroll(launch_box))
 else:
  var hint:=_panel(Rect2(_size.x-328,176,308,90),PANEL,null,10)
  var hb:=_box(hint,4);_label(hb,"装配操作",15,TEAL);_workshop_labels["assembly"]=_para(hb,"",13,DIM)
 if palette_open:_palette()
 var bottom:=_panel(Rect2(20,_size.y-72,466,52),PANEL,null,6)
 bottom.name="WorkshopTools"
 var br:=_row(bottom,6)
 var toggle:=_button(br,"收起零件箱" if palette_open else "打开零件箱","_palette",null,PANEL_LIGHT,38);toggle.custom_minimum_size.x=128;toggle.pressed.disconnect(toggle.pressed.get_connections()[0].callable);toggle.pressed.connect(func():palette_open=not palette_open;render(state))
 var undo:=_button(br,"撤销","undo",null,PANEL_LIGHT,38);_workshop_labels["undo"]=undo
 _button(br,"保存方案","save_blueprint",null,PANEL_LIGHT,38)
 _button(br,"载入方案","load_blueprint",null,PANEL_LIGHT,38)
 var fit_button:=_button(content,"看全工位","fit_workshop",null,PANEL_LIGHT,38);_workshop_labels["fit"]=fit_button
 fit_button.position=Vector2(496,_size.y-65);fit_button.size=Vector2(140,38)
 _refresh_workshop_labels()
 var dispatch:=_panel(Rect2(_size.x-362,_size.y-72,342,52),PANEL,null,6);dispatch.name="DispatchActions"
 var launch_row:=_row(dispatch,6)
 var trial_button:=_button(launch_row,"试飞 · 免费","trial",null,TEAL,38);trial_button.custom_minimum_size.x=150
 var dispatch_button:=_button(launch_row,"发射配送  ↗","dispatch",null,YELLOW,38);dispatch_button.custom_minimum_size.x=172
 if _delivery_mode():
  _delivery_launch_buttons.assign([trial_button,dispatch_button]);_refresh_delivery_launch_preview()
  trial_button.tooltip_text="试飞免费，不扣正式赔偿、不增债务。"
  dispatch_button.tooltip_text=DeliveryUI.liability(state.get("activeorder",{}))

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
 var launcher:bool=str(state.get("assembly_mode","craft"))=="launcher"
 var cats:Array=WorkshopParts.categories(entries,state.get("parts",[]),state.get("inventory",{}),launcher,str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))))
 if not palette_category in cats:palette_category=WorkshopParts.DEFAULT_CATEGORY
 var visible_entries:Array=WorkshopParts.visible_entries(entries,state.get("parts",[]),state.get("inventory",{}),palette_category,launcher,str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))))
 var width:=minf(_size.x-40,clampf(visible_entries.size()*104+16,728,960))
 var p:=_panel(Rect2(20,_size.y-232,width,152),PANEL,null,8)
 p.name="PartsTray"
 var frame:=p.get_theme_stylebox("panel") as StyleBoxFlat;frame.border_width_top=3;frame.border_color=TEAL
 var box:=_box(p,6);var head:=_row(box,6);_label(head,"零件箱",16,WHITE)
 for cat in cats:
  var btn:=Button.new();btn.text=cat;btn.add_theme_font_size_override("font_size",13);btn.custom_minimum_size=Vector2(52,26);btn.add_theme_stylebox_override("normal",_style(YELLOW if palette_category==cat else PANEL_LIGHT,2,4,false));btn.add_theme_color_override("font_color",INK if palette_category==cat else WHITE);head.add_child(btn);btn.set_meta("view_key","category:"+cat);btn.tooltip_text=str(WorkshopParts.HINTS.get(cat,""));btn.pressed.connect(func():palette_category=cat;render(state))
 _spacer(head);_workshop_labels["palette"]=_label(head,"",11,MUTED)
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
  var t:=TextureRect.new();t.texture=_native_icon(path,Vector2i(icon_size*0.5));t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon=t
 else:
  var warning:=Label.new();warning.text="缺图";warning.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;warning.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;warning.add_theme_color_override("font_color",CORAL);warning.add_theme_font_size_override("font_size",11);warning.tooltip_text="缺少零件贴图："+type;icon=warning
  if not _missing_icon_reports.has(type):_missing_icon_reports[type]=true;push_error("Missing required 2D HUD module sprite: "+path)
 icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.custom_minimum_size=icon_size;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(icon);return icon

func _native_icon(path:String,grid:Vector2i) -> Texture2D:
 var key:String=path+":"+str(grid)
 if not _native_icon_cache.has(key):_native_icon_cache[key]=DisplayMetrics.integer_texture(load(path),grid)
 return _native_icon_cache[key]

func _part_card(parent: Node, spec: Dictionary) -> void:
 var type:=str(spec.get("type",spec.get("id","beam")))
 var launcher:bool=str(state.get("assembly_mode","craft"))=="launcher"
 var version:String=str(state.get("control_version",state.get("activeorder",{}).get("control_version","")))
 var inventory:Dictionary=state.get("inventory",{})
 var available:=int(spec.get("available",inventory.get(type,0)))
 var selected:=type==str(state.get("chosen_type","beam"))
 var card:=Button.new();card.set_meta("view_key","catalog:"+type);card.custom_minimum_size=Vector2(96,92)
 var box:=_style(YELLOW if selected else PANEL_LIGHT,2,4,false);box.border_color=YELLOW if selected else EDGE;card.add_theme_stylebox_override("normal",box)
 var hover:=box.duplicate() as StyleBoxFlat;hover.border_color=TEAL;card.add_theme_stylebox_override("hover",hover);card.add_theme_stylebox_override("pressed",hover.duplicate())
 card.tooltip_text="%s\n%s\n质量 %.1f kg · 库存 %d"%[spec.get("name",type),WorkshopParts.purpose(type,launcher,version),float(spec.get("mass",0)),available];parent.add_child(card);card.pressed.connect(func():_act("select_catalog",type))
 var icon:=_part_icon(card,type,Vector2(48,48));icon.position=Vector2(24,8);icon.size=Vector2(48,48)
 var title:=_label(card,str(spec.get("name",type)),12,INK if selected else WHITE);title.position=Vector2(4,62);title.size=Vector2(88,20);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 var stock:=_label(card,"× %d"%available,11,INK if selected else TEAL if available>0 else CORAL);stock.position=Vector2(61,4)
 if not WorkshopParts.is_core(type) or (type=="spring" and str(state.get("assembly_mode","craft"))!="launcher" and not _delivery_mode()):
  var retained:=_label(card,"旧件",10,CORAL);retained.position=Vector2(4,4);card.tooltip_text+="\n旧版保留：原属性与控制继续有效，不再出售。"

func _inspector(part: Dictionary) -> void:
 var id:int=int(part.get("id",-1));var kind:String=str(part.get("type",""))
 var launcher:bool=str(state.get("assembly_mode","craft"))=="launcher"
 var parts:Array=state.get("parts",[])
 var version:String=str(state.get("control_version",state.get("activeorder",{}).get("control_version","")))
 var reserved:float=420.0 if palette_open else 268.0
 var h:float=maxf(206.0,minf(440.0,_size.y-reserved))
 var panel:=_panel(Rect2(_size.x-348,176,328,h),PANEL,null,10);panel.set_meta("context_panel",true);panel.name="ModuleInspector"
 var b:=_box(panel,8);var spec:Dictionary=part.get("spec",{})
 var title_row:=_row(b,8);_part_icon(title_row,kind,Vector2(32,32));_label(title_row,str(part.get("name",spec.get("name",kind))),18);_spacer(title_row)
 var quarter:int=posmod(int(part.get("rot",0)),4)
 var facing:=_label(title_row,["→","↓","←","↑"][quarter],19,TEAL);facing.name="ModuleFacing";facing.tooltip_text="安装朝向；喷口箭头与喷火方向相反。"
 var scroll:=_scroll(b);scroll.get_parent().set_meta("view_key","inspector:"+str(id))
 if launcher and _delivery_mode():
  _delivery_launcher_controls(scroll);_rule(scroll)
 if kind!="cargo" and (not WorkshopParts.is_core(kind) or (kind=="spring" and not launcher and not _delivery_mode())):
  _para(scroll,"旧版保留 · 已有零件仍可拆装，原控制继续有效。",11,YELLOW)
 var purpose:=_para(scroll,WorkshopParts.purpose(kind,launcher,version),12,WHITE)
 purpose.tooltip_text=WorkshopParts.detail(kind,version)
 var trigger_text:String=WorkshopParts.trigger_text(part,parts,_pilot_mode(),launcher,version)
 var disconnected:bool=not launcher and kind=="battery" and id in state.get("power_status",{}).get("disconnected_battery_ids",[])
 if disconnected:trigger_text="未连到货舱"
 var trigger:=_para(scroll,trigger_text,12,CORAL if disconnected else TEAL);trigger.name="ModuleStartupStatus"
 if not launcher and kind=="accelerator" and version in DeliveryUI.CELL_VERSIONS:
  _accelerator_workshop_labels.status=_para(scroll,"",12,TEAL)
  _accelerator_workshop_labels.status.name="ModuleReadiness"
  _accelerator_workshop_labels.motion=_para(scroll,"",12,WHITE)
  _accelerator_workshop_labels.impact=_para(scroll,"",13,TEAL)
  _accelerator_workshop_labels.impact.name="AcceleratorImpactPreview"
  _accelerator_workshop_labels.cost=_para(scroll,"",12,WHITE)
  _accelerator_workshop_labels.scope=_para(scroll,"",11,DIM)
  _refresh_accelerator_workshop_preview()
 else:
  var readiness:Dictionary=WorkshopParts.readiness(part,parts,_pilot_mode(),launcher,version)
  if not str(readiness.text).is_empty():
   var status:=_para(scroll,str(readiness.text),12,CORAL if not bool(readiness.ready) else YELLOW if bool(readiness.get("warning",false)) else TEAL);status.name="ModuleReadiness"
 if not launcher and kind=="shield" and version in SPATIAL_SHIELD_VERSIONS:
  _shield_workshop_labels.coverage=_para(scroll,"",13,TEAL)
  _shield_workshop_labels.coverage.name="ShieldCoveragePreview"
  _shield_workshop_labels.state=_para(scroll,"",12,TEAL)
  _shield_workshop_labels.state.tooltip_text="按受击格中心判定；圆边缘不拦截射线。实际吸收仍受余电与本步预算限制。"
  _refresh_shield_workshop_preview()
 var convenience:Dictionary=WorkshopParts.convenience_source(part,_pilot_mode(),launcher,version)
 if not convenience.is_empty():
  var change:=_button(scroll,str(convenience.label),"set_input",{"id":id,"key":"input_a","source":int(convenience.source)},TEAL,36)
  change.set_meta("view_key","part:"+str(id)+":startup");change.tooltip_text="只修改这件零件的启动方式；可以撤销。"
  change.pressed.connect(func():render(state))
 for control in WorkshopParts.local_controls(part,launcher,version):
  if str(control.kind)=="slider":_part_slider(scroll,part,control)
  elif str(control.kind)=="target":_part_target(scroll,part,parts,control)
 if not launcher and kind=="coupler":
  var groups:Dictionary=CouplerCutGroups.design_groups(part,WorkshopParts.effective_target(part,parts),parts)
  var consequence:String=CouplerCutGroups.group_text(groups,_pilot_mode())
  if not consequence.is_empty():
   var preview:=_para(scroll,consequence,12,WHITE);preview.name="CouplerGroupPreview"
 if kind in WorkshopParts.LOGIC:
  _para(scroll,"保留原信号组合。此处不会重新接线或改变旧方案。",11,YELLOW)
 var actions:=_row(b,7)
 var rotate:=_button(actions,"转向","rotate_part",id,TEAL,40);rotate.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_workshop_labels["rotate"]=rotate
 var remove:=_button(actions,"拆卸","remove_part",id,CORAL,40);_workshop_labels["remove"]=remove

func _part_slider(parent:Node,part:Dictionary,control:Dictionary) -> void:
 var id:int=int(part.get("id",-1));var key:String=str(control.get("key","param"))
 var value:float=float(control.get("value",part.get(key,0)))
 var unit:String=str(control.get("unit",""));var title:String=str(control.get("label",key))
 var caption:=_label(parent,title+"  "+str(value)+" "+unit,13,TEAL)
 var slider:=HSlider.new();slider.name="PartParameterSlider";slider.min_value=float(control.get("min",0));slider.max_value=float(control.get("max",100));slider.step=float(control.get("step",.1));slider.custom_minimum_size=Vector2(0,36);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 # An old custom value is displayed exactly. Constructing a step-based widget
 # must never emit a save or silently round that stored value.
 slider.set_value_no_signal(value);slider.set_meta("view_key","part:"+str(id)+":"+key);slider.tooltip_text="拖动调整；键盘左右 / 手柄方向键微调。";parent.add_child(slider)
 var dragging:Array=[false]
 slider.drag_started.connect(func():dragging[0]=true)
 slider.value_changed.connect(func(next:float):
  caption.text=title+"  "+str(next)+" "+unit
  # Keyboard/controller steps commit immediately. Mouse drag commits only once.
  if not bool(dragging[0]):_commit_part_slider(slider,id,key)
 )
 slider.drag_ended.connect(func(changed:bool):
  dragging[0]=false
  if changed:_commit_part_slider(slider,id,key)
 )

func _commit_part_slider(slider:HSlider,id:int,key:String) -> void:
 if not is_instance_valid(slider):return
 var selected:Dictionary=state.get("selectedpart",state.get("selected_part",{}))
 if int(selected.get("id",-1))==id and float(selected.get(key,NAN))!=slider.value:_act("set_param",{"id":id,"value":slider.value})

func _part_target(parent:Node,part:Dictionary,parts:Array,control:Dictionary) -> void:
 var id:int=int(part.get("id",-1));var kind:String=str(part.get("type",""))
 _label(parent,str(control.get("label","作用目标")),13,TEAL)
 var options:Array=WorkshopParts.target_options(part,parts)
 var selected_target:Dictionary=WorkshopParts.effective_target(part,parts)
 var target_id:int=int(selected_target.get("id",-1))
 var choice:=OptionButton.new();choice.name="PartTargetChoice";choice.custom_minimum_size.y=36;choice.set_meta("view_key","part:"+str(id)+":target");parent.add_child(choice)
 var ids:Array=[]
 # Keep the exact old/default target visible even if invalid. A placeholder
 # cannot become an implicit change to a different, now-valid candidate.
 if not target_id in options.map(func(row):return int(row.id)):
  choice.add_item("请选相邻零件" if target_id<0 else "原目标："+WorkshopParts.reference_label(selected_target)+"（不可用）");ids.append(int(part.get("target",-1)))
 for option in options:choice.add_item(str(option.label));ids.append(int(option.id))
 var selected_index:int=ids.find(target_id)
 choice.select(maxi(0,selected_index))
 choice.disabled=options.is_empty()
 var generation:int=_render_generation
 var popup:PopupMenu=choice.get_popup()
 var popup_id:int=popup.get_instance_id()
 popup.about_to_popup.connect(_open_target_popup.bind(popup_id,generation))
 popup.popup_hide.connect(_close_target_popup.bind(popup_id,generation))
 popup.window_input.connect(_target_popup_input.bind(popup_id,generation))
 choice.item_selected.connect(func(index:int):
  if generation!=_render_generation or not choice.is_inside_tree():return
  if index<0 or index>=ids.size():return
  if int(part.get("target",-1))!=int(ids[index]):_act("set_input",{"id":id,"key":"target","source":int(ids[index])})
  # PopupMenu hides before selecting, then emits window_input after this
  # handler. Keep its ancestors alive until that genuine release is observed.
  _render_target_selection.call_deferred(generation)
 )
 if kind=="splitter":
  _para(parent,"青框可选，黄框为当前目标；红框表示原目标不可用。",11,WHITE)
 elif int(part.get("target",-1))<0 and not selected_target.is_empty():
  _para(parent,"当前自动选中："+WorkshopParts.reference_label(selected_target),11,WHITE)

func _open_target_popup(popup_id:int,generation:int) -> void:
 if generation!=_render_generation:return
 _target_popup_id=popup_id;_target_popup_epoch+=1

func _close_target_popup(popup_id:int,generation:int) -> void:
 # Retire after the closing event, not at popup_hide (which precedes release).
 _retire_target_popup.call_deferred(popup_id,generation,_target_popup_epoch)

func _retire_target_popup(popup_id:int,generation:int,epoch:int) -> void:
 if generation==_render_generation and epoch==_target_popup_epoch and popup_id==_target_popup_id:_target_popup_id=0

func _target_popup_input(event:InputEvent,popup_id:int,generation:int) -> void:
 if generation!=_render_generation or popup_id!=_target_popup_id:return
 var popup=instance_from_id(popup_id)
 if not is_instance_valid(popup) or not popup.is_inside_tree() or not is_ancestor_of(popup):return
 if event is InputEventMouseButton and not event.pressed:target_popup_mouse_released.emit(event.button_index)

func _render_target_selection(generation:int) -> void:
 if is_inside_tree() and generation==_render_generation:render(state)

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
 if _pilot_mode() and control_key!="target":entries.append({"id":-2,"label":"驾驶回路"})
 var catalog:Variant=state.get("catalog",{})
 for item in state.get("parts",[]):
  if int(item.id)==int(part.get("id",-1)):continue
  var name:=str(item.get("name",item.get("type","模块")))
  if catalog is Dictionary:name=str(catalog.get(item.type,{}).get("name",name))
  entries.append({"id":int(item.id),"label":"#%d %s"%[item.id,name]})
 return entries

func _supply() -> void:
 var is_night:=str(state.get("phase","day")) in ["night","evening"]
 if bool(state.get("day_basic_supply",false)) and not is_night:
  _day_basic_supply();return
 var b:=_drawer("补好货，明天见。" if is_night else "准备打烊？","夜间补给" if is_night else "打烊",460)
 if not is_night:
  _para(b,"打烊后，可以补买零件。",19)
  if _has_accepted():
   var order:Dictionary=state.get("activeorder",{})
   _rule(b);_label(b,"还有一份已接受的委托",17,BLUE);_para(b,str(order.get("name","待完成委托")),20)
   _para(b,"先送完这单，或取消委托。",14,MUTED)
   _button(b,"回工位继续这单","focus_workbench",null,TEAL,48)
   _cancel_button(b,order,42)
  else:
   _button(b,"再看看委托","focus_counter",null,CREAM,48)
  var rest:=Control.new();rest.size_flags_vertical=Control.SIZE_EXPAND_FILL;rest.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(rest)
  _rule(b)
  var close:=_button(b,"打烊  →","close_day",null,YELLOW,51);close.disabled=_has_accepted()
  return
 _parts_retirement_entry(b)
 var top:=_row(b);_label(top,"补买零件",19)
 var body:=_scroll(b)
 var workshop:Dictionary=state.get("workshop",{})
 if not workshop.is_empty():
  var current_size:Vector2i=workshop.get("size",Vector2i(9,5))
  _label(body,"车间扩建 · %d × %d 格"%[current_size.x,current_size.y],19,TEAL)
  if int(workshop.get("next_tier",-1))>=0:
   var next_size:Vector2i=workshop.get("next_size",Vector2i.ZERO)
   _para(body,"扩大工位，装下更多零件。",13,DIM)
   var buy_workshop:=_button(body,"扩至 %d × %d 格  ·  ¥ %d"%[next_size.x,next_size.y,int(workshop.cost)],"workshop_upgrade",int(workshop.next_tier),TEAL,44)
   buy_workshop.name="WorkshopUpgrade";buy_workshop.disabled=int(state.get("credits",0))<int(workshop.cost)
  else:_para(body,"已完成全部扩建。",13,DIM)
  _rule(body)
 for spec in _catalog_entries():
  var type:=str(spec.get("type",spec.get("id","")))
  if not WorkshopParts.is_core(type):continue
  var row_panel:=PanelContainer.new();row_panel.add_theme_stylebox_override("panel",_style(WHITE,2,8,false));body.add_child(row_panel)
  var row:=_row(row_panel,9);_part_icon(row,type,Vector2(43,43));var text:=_box(row,0);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _label(text,str(spec.get("name",type)),16);_label(text,"库存 %s"%str(state.get("inventory",{}).get(type,0)),11,MUTED)
  var cost:=int(spec.get("price",0));var buy:=_button(row,"¥ %d  +"%cost,"buy",type,YELLOW,42);buy.disabled=int(state.get("credits",0))<cost
 var upgrades:Array=state.get("upgrades",[])
 if not upgrades.is_empty():
  _label(body,"店铺研究",19,BLUE)
  for upgrade in upgrades:
   _button(body,str(upgrade.get("name","研究"))+"  ·  ¥ "+str(upgrade.get("cost",0)),"upgrade",upgrade.get("id","research"),TEAL,43).disabled=bool(upgrade.get("disabled",false))
 _rule(b)
 _button(b,"开门，迎接第 %d 天  →"%(int(state.get("day",1))+1),"next_day",null,BLUE,49).add_theme_color_override("font_color",WHITE)

func _flight_identity(data: Dictionary) -> Array:
 var order:Dictionary=data.get("activeorder",{})
 return [str(order.get("contract_id",order.get("id",""))),str(data.get("control_version",order.get("control_version",""))),bool(data.get("trial",false))]

func _pilot_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird",PIRATE_CONTROL_VERSION,PIRATE_CONTROL_VERSION_V2,"pilot-free-v1","pilot-free-v2",DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS

func _ascent_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird",PIRATE_CONTROL_VERSION,PIRATE_CONTROL_VERSION_V2,"pilot-free-v1","pilot-free-v2",DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS

func _ground_mode() -> bool:
 return GroundProfile.is_ground_route(state.get("activeorder",{}))

func _extreme_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird",PIRATE_CONTROL_VERSION,PIRATE_CONTROL_VERSION_V2,"pilot-free-v1","pilot-free-v2",DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS

func _wormhole_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-v4-wormhole","pilot-v5-protected-bird"]

func _moon_mode() -> bool:
 var route:Dictionary=state.get("activeorder",{})
 return MoonProfile.is_moon_route(route) and str(route.get("control_version",""))=="pilot-v3" and str(route.get("route_kind",""))=="moon" and str(route.get("destination_id",""))=="moon-regolith-airlock" and route.get("moon_schema")==1 and route.get("moon_receiver") is Dictionary

func _corridor_mode() -> bool:
 return CorridorFraming.applies(state.get("activeorder",{}))

func _flight() -> void:
 if _free_flight_mode():
  _free_flight();return
 var pilot:=_pilot_mode();var ascent:=_ascent_mode();var extreme:=_extreme_mode();var corridor:=_corridor_mode();var compact:=_moon_mode() or corridor
 var top:=_panel(Rect2(300 if compact else 20,20,260,76),PANEL,null,8);var b:=_box(top,2)
 _label(b,"免费试飞" if bool(state.get("trial",false)) else "配送中",11,YELLOW)
 var order:Dictionary=state.get("activeorder",{})
 var name:=_label(b,str(order.get("destination_name","收件台")) if _ground_mode() or _wormhole_mode() or _moon_mode() or corridor else str(order.get("name","正在飞向目的地")),18,WHITE);name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;flight_labels["destination"]=name
 flight_labels["status"]=_label(b,"驾驶准备" if pilot else "自动航行 · 1×",12,TEAL)
 if ascent:
  # A quiet, non-interactive cue band leaves the ship and launch ribbon clear.
  # Distances are fictional route-space measures, never real orbital altitude.
  _ascent_cue=_panel(Rect2(20,20.0 if compact else 108,260,78),PANEL,null,8);_ascent_cue.name="AscentCue";_ascent_cue.mouse_filter=Control.MOUSE_FILTER_IGNORE
  var cue:=_box(_ascent_cue,2)
  flight_labels["altitude"]=_label(cue,"高度 0 / 150 m",12,DIM)
  flight_labels["gate"]=_label(cue,"",14,TEAL)
  flight_labels["gate_detail"]=_label(cue,"",11,DIM)
 var width:=_size.x-(888 if compact else 608)
 var route:=_panel(Rect2(572 if compact else 292,20,width,76),PANEL,null,8);var rb:=_box(route,3)
 var r:=_row(rb);_label(r,"航线进度",12,DIM);_spacer(r);flight_labels["distance"]=_label(r,"0 / 0 m",14,WHITE)
 progress_bar=ProgressBar.new();progress_bar.custom_minimum_size.y=8;progress_bar.show_percentage=false;rb.add_child(progress_bar)
 var times:=_row(rb);flight_labels["elapsed"]=_label(times,"航时 0.0 s",12,DIM);_spacer(times);flight_labels["deadline"]=_label(times,"目标 60 s",12,DIM)
 # The ascent approach enters from the upper right. Keep its silhouettes clear
 # by stacking resources below the cue, outside the central flight band.
 var resource_rect:=Rect2(20,198,260,112 if extreme else 96) if ascent else Rect2(_size.x-304,20,284,96 if pilot else 76)
 if _moon_mode():resource_rect=Rect2(_size.x-304,20,284,112)
 elif corridor:resource_rect=Rect2(_size.x-304,20,284,96)
 var resources:=_panel(resource_rect,PANEL,null,8);resources.name="FlightResources";var ib:=_box(resources,1)
 var row:=_row(ib);_label(row,"货物完整度",13,DIM);_spacer(row);flight_labels["integrity"]=_label(row,"100%",20 if extreme else 24,YELLOW)
 flight_labels["energy"]=_label(ib,"电量 0 J" if pilot else "消耗 0 J · 信号正常",12,DIM)
 var signals:Control=_row(ib) if corridor else ib
 if extreme:flight_labels["thrust"]=_label(signals,"推力 — N",11,TEAL)
 if corridor and extreme:_spacer(signals)
 if pilot:flight_labels["pilot_signal"]=_label(signals,"Space 回路 · 待命",11,TEAL)
 var events:=_panel(Rect2(_size.x-464 if corridor else 20,_size.y-134,444,42) if ascent else Rect2(20,_size.y-184,444,84),PANEL,null,5 if ascent else 8);events.name="FlightEventReceipt";var eb:=_box(events,1 if ascent else 3)
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
 _build_destination_cue()
 _build_flight_save_exit()
 set_input_device(_gamepad)
 update_flight(state.get("flight",state))

func _build_flight_save_exit() -> void:
 var button:=_button(content,"保存并退出","save_and_quit",null,PANEL_LIGHT,44)
 button.name="FlightSaveAndExit";button.set_meta("view_key","flight:save_and_quit")
 # Force-flight keeps its device card in the bottom-right safe HUD band.
 # Use the existing top gap between speed and battery for the pause-only exit.
 button.position=Vector2(20,120) if _delivery_mode() else Vector2(_size.x-484,20) if _force_flight_mode() else Vector2(_size.x-204,_size.y-64);button.size=Vector2(184,44)
 button.visible=false;button.focus_mode=Control.FOCUS_NONE
 _flight_save_exit_button=weakref(button)

func update_flight_exit_state(paused:bool,available:bool) -> void:
 if mode!="flight":return
 var flight:Dictionary=state.get("flight",{}).duplicate()
 flight.paused=paused;flight.save_exit_available=available;state.flight=flight
 _update_flight_save_exit(flight)

func _update_flight_save_exit(data:Dictionary) -> void:
 var button:Button=_flight_save_exit_button.get_ref() if _flight_save_exit_button!=null else null
 if not is_instance_valid(button):return
 var show_button:bool=bool(data.get("paused",false))
 var was_visible:bool=button.visible
 var had_focus:bool=button.has_focus()
 var available:bool=bool(data.get("save_exit_available",state.get("save_exit_available",false)))
 state.save_exit_available=available
 var modal_owned:bool=is_blocking_modal()
 button.visible=show_button;button.disabled=not available or modal_owned
 button.focus_mode=Control.FOCUS_ALL if show_button and available and not modal_owned else Control.FOCUS_NONE
 button.tooltip_text="保存当前配送进度后退出；会先确认。" if available else "配送记录正在恢复或当前不可保存，暂不能保存退出。"
 # While piloting, pointer actions must remain clickable without taking Space
 # from the ship. Releasing focus every telemetry frame cancels an in-progress
 # mouse press before its release. Use non-focusable pointer controls instead;
 # restore normal keyboard/gamepad navigation only while paused.
 if not modal_owned:
  var action_focus:int=Control.FOCUS_ALL if show_button else Control.FOCUS_NONE
  for reference in _flight_pointer_buttons:
   var control:Button=reference.get_ref()
   if is_instance_valid(control) and control.focus_mode!=action_focus:control.focus_mode=action_focus
 if not show_button and not modal_owned and was_visible:
  var owner:Control=get_viewport().gui_get_focus_owner()
  if is_instance_valid(owner) and content.is_ancestor_of(owner):owner.release_focus()
 elif show_button and not modal_owned and ((not was_visible) or (had_focus and not available)):
  var continue_button:Button=_pause_button.get_ref() if _pause_button!=null else null
  if is_instance_valid(continue_button):continue_button.grab_focus()

func update_flight(data: Dictionary) -> void:
 if mode!="flight" or flight_labels.is_empty():return
 if _free_flight_mode():
  # This branch also serves initial layout, and owns its detached snapshot.
  _update_free_flight(data);return
 state["flight"]=data.duplicate(true)
 _update_flight_save_exit(data)
 _update_destination_cue(data)
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
   if _corridor_mode() and phase=="approach":phase_text="接近收件台" if _ordinary_receiver_near(data) and int(data.get("next_gate_index",-1))<0 else ("低空配送" if _ground_mode() else "轨道巡航")
   if _moon_mode():phase_text="月面进场" if distance>=float(state.activeorder.moon_approach_start) else "升空"
   if _wormhole_mode():phase_text=str({"ascent":"升空","space":"太空","otherworld":"异世界"}.get(str(data.get("wormhole_phase","")),"航行"))
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
 var receipt_data:Dictionary=data.duplicate()
 # Some legacy controller snapshots keep the protocol on the order only.
 receipt_data.control_version=str(state.get("control_version",state.get("activeorder",{}).get("control_version","")))
 var items:Array[Dictionary]=_flight_receipt.update(receipt_data,2 if _ascent_mode() else 3)
 var lines:Array[String]=[];var sources:Array[String]=[]
 if _ascent_mode():items.reverse()
 for item in items:lines.append(item.text);sources.append(item.source)
 flight_labels.events.text=("  ·  " if _ascent_mode() else "\n").join(lines)
 flight_labels.events.tooltip_text="\n".join(sources)
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

func _ordinary_receiver_near(data:Dictionary) -> bool:
 # Presentation-only proximity; the saved capture geometry still decides receipt.
 var total:float=_flight_number(data,"total_distance",_flight_number(state.get("activeorder",{}),"distance",NAN))
 var progress:float=_flight_number(data,"distance",NAN)
 return is_finite(total) and is_finite(progress) and absf(total-progress)<=60.0

func _update_ascent_cue() -> void:
 if not is_instance_valid(_ascent_cue):return
 var data:=_ascent_telemetry
 _ascent_cue.visible=not bool(data.get("charging",false)) and _launch_phase not in ["move","charge","ignition"]
 flight_labels.altitude.text="高度 %.0f / %.0f m"%[_flight_number(data,"altitude",0),_flight_number(data,"target_altitude",float(state.get("activeorder",{}).get("pilot_altitude",150)))]
 if _moon_mode() and _flight_number(data,"distance",0)>=float(state.activeorder.moon_approach_start):
  flight_labels.altitude.text="高度 %.0f m · 入口 %.1f m"%[_flight_number(data,"altitude",0),-float(state.activeorder.moon_receiver.ingress_center_y)]
 var paused:=bool(data.get("paused",false))
 if (_wormhole_mode() or _moon_mode()) and data.get("delivered",false) is bool and data.get("delivered",false):
  flight_labels.gate.text="货物已签收";flight_labels.gate.add_theme_color_override("font_color",TEAL)
  flight_labels.gate_detail.text=str(state.get("activeorder",{}).get("destination_name","收件台"))
  return
 var gate:=int(data.get("next_gate_index",-1))
 var seconds:=_flight_number(data,"next_gate_time",-1)
 var ready:=gate>=0 and seconds>=0
 var warning:=ready and seconds<=_flight_number(data,"lookahead_seconds",3.5) and not paused
 flight_labels.gate.add_theme_color_override("font_color",DIM if paused else YELLOW if warning else TEAL)
 if not ready:
  var approach:=str(data.get("wormhole_phase",""))=="otherworld" if _wormhole_mode() else str(data.get("flight_phase",""))=="approach"
  if _corridor_mode():approach=approach and _ordinary_receiver_near(data)
  flight_labels.gate.text=("接近"+str(state.get("activeorder",{}).get("destination_name","收件台")) if _ground_mode() or _wormhole_mode() or _moon_mode() else "接近收件区") if approach else ""
  if _wormhole_mode():flight_labels.gate.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
  flight_labels.gate_detail.text="已暂停" if paused else ""
  if (_ground_mode() or _wormhole_mode() or _moon_mode()) and approach:
   var limit:=_flight_number(state.get("activeorder",{}),"max_delivery_speed",NAN)
   if is_finite(limit):flight_labels.gate_detail.text=("已暂停 · " if paused else "")+"收件限速 %.0f m/s"%limit
  return
 var direction:=int(data.get("next_gate_direction",0))
 var cue:="↑ 向上" if direction<0 else "↓ 向下" if direction>0 else "→ 保持"
 flight_labels.gate.text="%s · %.1f s 后过门"%[cue,seconds]
 flight_labels.gate_detail.text=("已暂停 · " if paused else "")+"第 %d 门 · 门高 %.0f m"%[gate+1,_flight_number(data,"next_gate_altitude",0)]
 if _wormhole_mode() and str(data.get("wormhole_phase","")) in ["ascent","space"] and _is_wormhole_entry_gate(gate):
  flight_labels.gate.text="虫洞入口 · "+cue
  flight_labels.gate_detail.text=("已暂停 · " if paused else "")+"约 %.1f s · 门高 %.0f m"%[seconds,_flight_number(data,"next_gate_altitude",0)]


func _is_wormhole_entry_gate(index: int) -> bool:
 # Saved routes may change portal geometry and gate numbering. Only the
 # upcoming gate's explicit route marker can name it as the portal entrance.
 var gates:Variant=state.get("activeorder",{}).get("pilot_gates",[])
 if not gates is Array:return false
 var matches:=0
 var entrance:=false
 for gate in gates:
  if not gate is Dictionary:continue
  var gate_index:=_wormhole_number(gate,"index")
  if not is_finite(gate_index) or gate_index!=float(index):continue
  matches+=1
  entrance=gate.get("wormhole_entry",false) is bool and gate.get("wormhole_entry",false)
 return matches==1 and entrance

func _wormhole_number(data: Dictionary, key: String) -> float:
 var value:Variant=data.get(key)
 if not (value is int or value is float):return NAN
 return float(value) if is_finite(float(value)) else NAN

func _wormhole_preflight_lines() -> Array[String]:
 var value:Variant=state.get("wormhole_preflight",{})
 var quote:Dictionary=value if value is Dictionary else {}
 var estimate:=_wormhole_number(quote,"estimated_j")
 var capacity:=_wormhole_number(quote,"station_capacity_j")
 var bodies:=_wormhole_number(quote,"estimated_bodies")
 var valid:bool=quote.get("ok",false) is bool and quote.get("ok",false) and is_finite(estimate) and estimate>=0 and is_finite(capacity) and capacity>=0 and is_finite(bodies) and bodies>=1 and bodies==floorf(bodies)
 var energy:="预计通行 %.1f J，驿站储能 %s；合并计入能耗。分离后按实际计费。"%[estimate,_flight_energy(capacity)] if valid else "虫洞通行使用驿站储能，合并计入能耗；当前预估不可用。"
 if valid and estimate>capacity:energy+="储能不足。"
 var aperture:=_wormhole_number(quote,"max_centered_body_diameter_m")
 var outline:=_wormhole_number(quote,"starting_body_diameter_m")
 var aperture_text:="%.2f m"%aperture if is_finite(aperture) and aperture>0 else "—"
 var outline_text:="%.2f m"%outline if is_finite(outline) and outline>0 else "—"
 var warning:=""
 if is_finite(aperture) and aperture>0 and is_finite(outline) and outline>0 and (outline>aperture or (quote.get("fits_starting_outline") is bool and not quote.fits_starting_outline)):warning=" · 轮廓偏大"
 return [energy,"净口径 %s · 当前轮廓 %s%s"%[aperture_text,outline_text,warning]]

func _wormhole_report_receipt(parent: Node, report: Dictionary, trial: bool) -> void:
 if not str(report.get("control_version","")) in ["pilot-v4-wormhole","pilot-v5-protected-bird"]:return
 var energy:=_wormhole_number(report,"wormhole_energy_j")
 var total:=_wormhole_number(report,"energy_j")
 var transits:=_wormhole_number(report,"wormhole_transits")
 # This is a measured subtotal of the already-combined normal energy bill.
 # Incomplete or inconsistent reports must not manufacture a second debit.
 if not is_finite(energy) or energy<0 or not is_finite(total) or total<energy or not is_finite(transits) or transits<0 or transits!=floorf(transits):return
 var receipt:=_para(parent,"其中虫洞通行 %s · %d 个组件（已含在%s中）"%[_flight_energy(energy),int(transits),"本次耗能" if trial else "能源消耗"],13,BLUE)
 receipt.name="WormholeEnergySubtotal"
 var remaining:=_wormhole_number(report,"wormhole_station_remaining")
 if is_finite(remaining) and remaining>=0:_para(parent,"驿站余能 "+_flight_energy(remaining),12,MUTED)

func _trial_comparison_text(value: Variant, limit: int, truncate: bool = false) -> String:
 # Saved report text is display-only. Never stringify other Variant types or
 # scan unbounded changes; numeric strings over the limit are unavailable.
 if not value is String:return ""
 var source:String=value
 if source.length()>limit and not truncate:return ""
 var shown:String="";var space:bool=false
 for character in source.substr(0,limit):
  var code:int=character.unicode_at(0)
  var whitespace:bool=code<=32 or (code>=127 and code<=160) or code==0x1680 or (code>=0x2000 and code<=0x200f) or (code>=0x2028 and code<=0x202f) or code==0x205f or (code>=0x2060 and code<=0x2069) or code==0x3000 or code==0xfeff
  if whitespace:
   space=not shown.is_empty();continue
  if space:shown+=" ";space=false
  shown+=character
 if not shown.is_empty() and source.length()>limit:shown+="（内容较长，已省略）"
 return shown

func _trial_comparison(parent: Node, report: Dictionary, trial: bool) -> void:
 if not trial:return
 var raw:Variant=report.get("comparison")
 var comparison:Dictionary=raw if raw is Dictionary else {}
 var changes:=_trial_comparison_text(comparison.get("本次改动"),4096,true)
 var fields:Array=[
  ["航时","航时变化：","TrialComparisonElapsed"],
  ["耗能","耗能变化：","TrialComparisonEnergy"],
  ["完整度","完整度变化：","TrialComparisonIntegrity"],
  ["预计净收益","预计结余变化：","TrialComparisonProfit"]
 ]
 var values:Array[String]=[];var usable:bool=not changes.is_empty()
 for field in fields:
  var value:=_trial_comparison_text(comparison.get(field[0]),64)
  values.append(value);usable=usable or not value.is_empty()
 var section:=_box(parent,6);section.name="TrialComparison";section.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 if not usable:
  var missing:=_para(section,"暂无可用的上次试飞对比。",15,DIM);missing.name="TrialComparisonMissing"
  return
 var heading:=_para(section,"与上次同委托试飞比较",18,TEAL);heading.name="TrialComparisonHeading"
 var change_line:=_para(section,"本次装配改动："+(changes if not changes.is_empty() else "未记录"),15,WHITE);change_line.name="TrialComparisonChanges"
 for index in fields.size():
  var line:=_para(section,fields[index][1]+(values[index] if not values[index].is_empty() else "—"),15,DIM);line.name=fields[index][2]
 var note:=_para(section,"正负值表示本次减去上次；完整度按百分点比较。结果也受操作和结束时机影响。",13,DIM);note.name="TrialComparisonNote"

func _report() -> void:
 var report:Dictionary=state.get("report",{})
 # Only an explicit bool identifies a trial. Legacy state fallback is used
 # only for a missing report field; malformed values never become free trials.
 var trial_value:Variant=report.get("trial") if report.has("trial") else state.get("trial")
 var success:=bool(report.get("success",false));var trial:bool=trial_value is bool and trial_value
 var delivery:bool=DeliveryUI.applies(report) if report.has("control_version") else _delivery_mode()
 var w:=760.0;var p:=_panel(Rect2((_size.x-w)/2,156,w,_size.y-184),PANEL,null,20)
 var b:=_box(p,11);var header:=_row(b);var titles:=_box(header,1);titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 var completion:String=DeliveryUI.completed_chapter_copy(state)
 var receipt_title:=_label(titles,("免费试飞" if trial else "配送结果")+(" · "+completion if not completion.is_empty() else ""),14,TEAL)
 if not completion.is_empty():receipt_title.name="CompletedChapterReceipt"
 _label(titles,"送到了！" if success else "这趟没送到",29,WHITE)
 _label(header,"✓" if success else "!",48,TEAL if success else CORAL)
 var cause:String="货物已签收。" if success else _report_failure_copy(report)
 var causep:=PanelContainer.new();causep.add_theme_stylebox_override("panel",_style(TEAL if success else CORAL,2,12,false));b.add_child(causep);_para(causep,cause,20)
 if delivery:
  var health:Dictionary=DeliveryUI.integrity(report,report if report.has("min_delivery_integrity") else state.get("activeorder",{}))
  _label(b,"货物完整度 %s · %s · %s"%[health.current_text,health.minimum_text,health.status],17,CORAL if health.known and not health.qualified else TEAL)
 if trial:_label(b,"本次免费，不扣赔偿、不增债务。" if delivery else "本次免费，资金不变。",23,YELLOW)
 else:
  var profit:int=int(report.get("profit",0))
  _label(b,"赚了 ¥%d"%profit if profit>0 else "亏了 ¥%d"%absi(profit) if profit<0 else "本次收支 ¥0",27,YELLOW)
  if delivery:
   _label(b,"货损赔偿 ¥%d · 本次新增债务 ¥%d · 当前债务 ¥%d"%[int(report.get("compensation",0)),int(report.get("debt_added",0)),int(report.get("debt",0))],16,CORAL if int(report.get("debt",0))>0 else TEAL)
  if _insured_report(report):_label(b,"驿站承担 ¥%d · 你付 ¥%d"%[int(report.get("insurance_coverage",0)),int(report.get("charged_costs",0))],16,TEAL)
 var body:=_scroll(b)
 var cold_copy:String=RiftRiskUI.report_copy(report,state.get("report_order",{}))
 if not cold_copy.is_empty():
  var cold_hint:=_para(body,cold_copy,14,TEAL);cold_hint.name="BiologicalDamageReceipt"
  cold_hint.tooltip_text="仅解释本次记录的冷区累计伤害（HP），不等于全部货损或完整度百分点；赔偿仍按实际货物完整度结算。"
 var retry_copy:String=DeliveryUI.heavy_retry_copy(report,state.get("report_order",{}))
 if not retry_copy.is_empty():
  var retry_hint:=_para(body,retry_copy,14,DIM);retry_hint.name="HeavyRouteRetryGuidance"
 var debt_copy:String=DeliveryUI.debt_recovery_copy(report,state)
 if not debt_copy.is_empty():
  var debt_hint:=_para(body,debt_copy,14,TEAL);debt_hint.name="DebtRecoveryGuidance"
 _trial_comparison(body,report,trial)
 var detail:=_foldout(body,"飞行详情" if trial else "收支明细","report:"+str(report.get("contract_id","trial"))+":"+str(report.get("elapsed",0)))
 _label(detail,"飞行 %.1f 秒 · 货物完整度 %s"%[float(report.get("elapsed",0)),DeliveryUI.percent(DeliveryUI.fraction(report.get("delivery_integrity")))] if delivery else "飞行 %.1f 秒 · 货物完整度 %.0f%%"%[float(report.get("elapsed",0)),float(report.get("integrity",100))],15,DIM)
 if trial:
  _label(detail,"耗能 %s"%_flight_energy(float(report.get("energy_j",report.get("energy",0)))),15,DIM)
  if report.has("estimated_profit"):_label(detail,"若正式配送，预计结余 ¥%s"%str(report.estimated_profit),15,DIM)
 else:
  for item in [["运费收入","income",1],["电费","energy",-1],["弹药/燃料","ammo",-1],["维修","repairs",-1],["补回零件","lost",-1]]:
   var row:=_row(detail);_label(row,str(item[0]),15);_spacer(row);_label(row,"¥ %+d"%(int(report.get(item[1],0))*int(item[2])),15)
  if delivery:
   var damage_row:=_row(detail);_label(damage_row,"货损赔偿",15);_spacer(damage_row);_label(damage_row,"¥ -%d"%int(report.get("compensation",0)),15)
  if _insured_report(report):
   var covered:=_row(detail);_label(covered,"驿站承担",15);_spacer(covered);_label(covered,"¥ +%d"%int(report.get("insurance_coverage",0)),15,TEAL)
  _para(detail,"费用已记账，余额不足的部分保留为债务。" if delivery and int(report.get("debt",0))>0 else "费用已结清，零件已补齐。" if bool(report.get("restored",false)) else "以上为本次实际结算。",14,DIM)
 _wormhole_report_receipt(detail,report,trial)
 if not trial and not bool(state.get("daily_reviews_enabled",false)) and report.has("review"):_para(body,str(report.review),16,TEAL)
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
 var b:=_drawer("怎么操作","操作帮助",594)
 var body:=_scroll(b)
 _label(body,"驾驶",21,TEAL)
 if _force_flight_mode():
  _para(body,"WASD / 左摇杆 推进 · 松开滑行\nCtrl / LT 刹车 · Shift / RB 加力\nQ / Y 选装置 · Space / A 使用",17)
 elif _free_flight_mode():
  _para(body,"WASD / 方向键移动，松开刹车。\nShift 加速 · Space 启动设备 · Esc / P 暂停",17)
  _para(body,"朝目的地箭头飞。电量耗尽或货物损毁，配送就会失败。",16,DIM)
 elif _pilot_mode():_para(body,"W / S 或 ↑ / ↓ 升降 · Shift %s\nSpace 启动设备 · Esc / P 暂停"%("全功率" if _extreme_mode() else "冲刺"),17)
 else:_para(body,"飞行时，按屏幕下方的按键提示操作。",17)
 _label(body,"装配",21,TEAL)
 _para(body,"点空格装零件，拖动零件换位置。\nR 旋转 · Delete 拆下 · Ctrl+Z 撤销",17)
 _para(body,"主动装置须接电；无电货物仍能滑行。可随时点「中止本次」。" if DeliveryUI.cell_rules(state.get("activeorder",{})) else "电芯、货舱和推进器要连在一起。",16,DIM)
 var more:=_foldout(body,"更多按键","help:keys")
 for line in ["店内：A / D 行走，Shift 奔跑，E 交互，Tab 菜单。","工位：中键拖动画面，滚轮缩放，F 看全。","F11 切换全屏。"]:_para(more,line,16)
 var pad:=_foldout(body,"手柄操作","help:pad")
 for line in ["店内：左摇杆移动，A 交互，Menu 打开菜单。","菜单：方向选择，A 确认，B 返回。","工位：X 进入网格；A 选放，Y 拿起，X 旋转。","LB 拆下 · RB 撤销 · R3 看全 · 右摇杆平移。","飞行：左摇杆驾驶，RB 加速，A 启动设备，Menu 暂停。" if _free_flight_mode() else "飞行：左摇杆升降，RB 加速，A 启动设备，Menu 暂停。"]:_para(pad,line,16)
 var devices:=_foldout(body,"设备说明","help:devices")
 _para(devices,"选中零件，可以调参数或连接信号。Space 会启动接入驾驶回路的设备。",16)
 _para(devices,"钻头只切削可破坏的障碍，空转也耗电，不能钻穿障碍门。",16)
 _para(devices,"护盾耗电吸收部分碰撞伤害，不能免除结构过载。高速撞击仍会损坏零件。",16)

func free_order_upgrade_open() -> bool:
 return not _free_order_upgrade.is_empty()

func open_free_order_upgrade(preview:Dictionary) -> bool:
 if is_blocking_modal() or not bool(preview.get("available",false)):return false
 _free_upgrade_generation+=1
 _free_order_upgrade=preview.duplicate(true)
 var upgrades:Dictionary=state.get("free_order_upgrade",{}).duplicate(true)
 upgrades[str(preview.get("kind",""))]=preview.duplicate(true);state.free_order_upgrade=upgrades
 toast_panel.hide();toast_timer=0;render(state)
 return free_order_upgrade_open()

func _dismiss_free_order_upgrade(expected_generation:int=-1) -> void:
 if not free_order_upgrade_open() or (expected_generation>=0 and expected_generation!=_free_upgrade_generation):return
 _free_upgrade_generation+=1
 _free_order_upgrade.clear();render(state)
 action_requested.emit("cancel_free_upgrade",null)

func _confirm_free_order_upgrade(expected:Dictionary,expected_generation:int) -> void:
 # A queued click from an older rendered confirmation cannot approve a newer
 # identity after Cancel, resize or reopen. Main rechecks live Economy too.
 if not free_order_upgrade_open() or expected_generation!=_free_upgrade_generation or _free_order_upgrade!=expected:return
 _free_upgrade_generation+=1
 _free_order_upgrade.clear();render(state)
 action_requested.emit("confirm_free_upgrade",expected)

func reset_free_order_view() -> void:
 # Paid receipts live in Economy. These are only stale HUD previews.
 _free_upgrade_generation+=1
 _free_order_upgrade.clear();_cancel_confirmation_id=""
 dispatch_confirmation_open=false;_dispatch_contract_id=""
 _flight_receipt.reset();_detail_open.clear()
 state.erase("flight");state.erase("report");state.erase("activeorder")

func _parts_retirement_entry(parent:Node) -> void:
 var preview:Dictionary=state.get("free_order_upgrade",{}).get("parts",{})
 if bool(preview.get("available",false)):_button(parent,"整理旧零件","retire_legacy_parts",null,TEAL,38)

func _free_upgrade_confirmation() -> void:
 var expected:Dictionary=_free_order_upgrade.duplicate(true)
 var expected_generation:int=_free_upgrade_generation
 var kind:String=str(_free_order_upgrade.get("kind",""))
 var delivery:bool=kind=="delivery"
 var accepted:bool=kind=="accepted"
 var parts:bool=kind=="parts"
 var force:bool=kind=="force"
 var current:Dictionary=state.get("free_order_upgrade",{}).get(kind,{})
 if current!=_free_order_upgrade:
  _free_order_upgrade.clear();action_requested.emit("cancel_free_upgrade",null);return
 var dim:=ColorRect.new();dim.color=Color(.04,.08,.2,.5);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.add_child(dim)
 var height:=minf(398,_size.y-40)
 var panel:=_panel(Rect2((_size.x-584)/2,(_size.y-height)/2,584,height),CREAM,null,21);panel.set_meta("modal_panel",true)
 var b:=_box(panel,12);var heading:=_row(b)
 _label(heading,"进入首章配送" if delivery else "整理旧零件" if parts else "免费升级操控" if force else "免费换单" if accepted else "更换新版委托",26);_spacer(heading)
 var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(38,38);heading.add_child(close);close.pressed.connect(_dismiss_free_order_upgrade.bind(expected_generation))
 _rule(b)
 var body:=_scroll(b)
 if delivery:
  _para(body,"进入轻货、重货、易碎货的首章配送。",21,BLUE)
  _para(body,"发射角度和力度影响真实初速，每单有最低完整度要求。",17)
  _para(body,"正式配送按实际货损与消耗结算，余额可以变成负数。免费试飞不增债务。",17)
  _para(body,"确认前先备份原存档；已接旧订单按原规则完成，旧账单保留。取消不作修改。",15,MUTED)
 elif parts:
  _para(body,"%d 件旧零件 → 结构梁；补回差价 ¥%d。"%[int(expected.get("converted_count",0)),int(expected.get("credit_delta",0))],21,BLUE)
  _para(body,"位置和编号保留。旧信号线移除，装置改为直接控制。",17)
  _para(body,"确认前先备份原存档和上一份备份；取消不作修改。",15,MUTED)
 elif force:
  _para(body,"把 %d 份未接委托换成新版同类航线？"%int(expected.get("count",0)),21,BLUE)
  _para(body,"按住方向推进，松开滑行；Ctrl / 左扳机刹车。",17)
  _para(body,"不收费，运费和客户保留。已接委托、原装配和旧账单不变，原委托另行备份。",15,MUTED)
 elif accepted:
  _para(body,"改为自由飞行轻件，最高运费 ¥220。",21,BLUE)
  _para(body,"保留这位客人和同一份货物，不收费、不扣声望。旧委托会原样备份。",17)
  _para(body,"原来的试飞预估会清除。取消即可保留原委托。",15,MUTED)
 else:
  _para(body,"把 %d 份未接的旧委托换成自由飞行轻件？"%int(_free_order_upgrade.get("count",0)),21,BLUE)
  _para(body,"不收费，原存档会先备份。已接委托和旧账单会保留。",17)
 var actions:=_row(b,10)
 var cancel:=Button.new();cancel.text="暂不整理" if parts else "保留原委托";cancel.set_meta("view_key","free_upgrade:cancel");cancel.set_meta("safe_modal_default",true);cancel.custom_minimum_size.y=49;cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(cancel);cancel.pressed.connect(_dismiss_free_order_upgrade.bind(expected_generation))
 var confirm:=Button.new();confirm.text="确认进入首章" if delivery else "确认整理" if parts else "确认免费升级" if force else "确认免费换单" if accepted else "确认更换";confirm.set_meta("view_key","free_upgrade:confirm");confirm.custom_minimum_size.y=49;confirm.size_flags_horizontal=Control.SIZE_EXPAND_FILL;confirm.add_theme_stylebox_override("normal",_style(YELLOW,3,12));confirm.add_theme_color_override("font_color",INK);actions.add_child(confirm)
 confirm.pressed.connect(_confirm_free_order_upgrade.bind(expected,expected_generation))

func _dispatch_confirmation() -> void:
 var order:Dictionary=state.get("activeorder",{})
 if not _has_order_details(order):
  dispatch_confirmation_open=false;return
 var current_id:=str(order.get("contract_id",order.get("id","")))
 if current_id!=_dispatch_contract_id:
  dispatch_confirmation_open=false;return
 var dim:=ColorRect.new();dim.color=Color(.04,.08,.2,.5);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.add_child(dim)
 var height:=minf(530,_size.y-40)
 var panel:=_panel(Rect2((_size.x-640)/2,(_size.y-height)/2,640,height),CREAM,null,21);panel.set_meta("modal_panel",true)
 var b:=_box(panel,10);var heading:=_row(b);var title:=_box(heading,1);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _label(title,"正式配送",14,BLUE);_label(title,"准备出发？",27)
 var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(38,38);heading.add_child(close);close.pressed.connect(_dismiss_dispatch)
 _rule(b)
 var review:=_scroll(b)
 _para(review,"送到"+_destination_name(order),24)
 _para(review,str(order.get("client","客户"))+" · "+str(order.get("cargo","货物")),17)
 _label(review,("最高运费 ¥%s" if _insured_order(order) else "运费 ¥%s")%str(order.get("reward","—")),22,BLUE)
 if DeliveryUI.applies(order):
  _para(review,DeliveryUI.requirement(order),19,BLUE)
  _para(review,DeliveryUI.liability(order),17)
  _para(review,"免费试飞不扣赔偿、不增债务。",15,MUTED)
 else:_para(review,"运费到站结算。送达最多自付 ¥30，失败最多 ¥25。" if _insured_order(order) else "送达后收运费，耗能和损坏会扣钱。失败也会扣除本次消耗。",17)
 _para(review,"每单只有一次正式配送。没把握？先回工位免费试飞。",15,MUTED)
 var detail:=_foldout(review,"费用与收件要求","dispatch:"+current_id)
 var tariff_text:String=String.num(float(state.get("energy_tariff",.18)),5)
 if _insured_order(order):
  _para(detail,"驿站承担其余花费。送达有基础运费，货物越完整，奖励越多。",15)
 else:_para(detail,"电费 ¥%s / J（向上取整）。弹药与丢失零件按原价补齐，回收零件按损伤维修。"%tariff_text,14)
 _para(detail,"结算后，零件会补齐。",14,MUTED)
 if not _is_free_order(order):
  _para(detail,"晚到或货物破损会减少收入。奖励时限 %s s，最迟 %s s；完整度要求 %s%%。"%[str(order.get("deadline","—")),str(order.get("time_limit","—")),str(order.get("required","—"))],14)
  _para(detail,"收件范围 %s m，速度不超过 %s m/s。"%[str(order.get("delivery_radius","—")),str(order.get("max_delivery_speed","—"))],14)
 elif DeliveryUI.cell_rules(order):_para(detail,"无电仍可滑行；主动装置需电。进入收件范围时，速度和完整度都必须达标。可手动中止。",14)
 elif DeliveryUI.applies(order):_para(detail,"电量耗尽会失败；进入收件范围时，速度和完整度都必须达标。",14)
 else:_para(detail,"电量耗尽就会失败。靠近收件台时放慢速度。",14)
 if order.has("risk"):_para(detail,"注意："+str(order.risk),14,Color("a13f3e"))
 if _wormhole_mode():
  for line in _wormhole_preflight_lines():_para(detail,line,14,BLUE)
 var actions:=_row(b,10)
 var cancel:=Button.new();cancel.set_meta("view_key","dispatch:cancel");cancel.set_meta("safe_modal_default",true);cancel.text="再检查一下";cancel.custom_minimum_size.y=49;cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(cancel);cancel.pressed.connect(_dismiss_dispatch)
 var launch:=Button.new();launch.set_meta("view_key","dispatch:confirm");launch.text="出发配送  ↗";launch.custom_minimum_size.y=49;launch.size_flags_horizontal=Control.SIZE_EXPAND_FILL;launch.add_theme_stylebox_override("normal",_style(YELLOW,3,12));launch.add_theme_color_override("font_color",INK);actions.add_child(launch)
 launch.pressed.connect(func():
  if not dispatch_confirmation_open:return
  dispatch_confirmation_open=false;_dispatch_contract_id="";render(state);action_requested.emit("dispatch",null)
 )

func _dismiss_dispatch() -> void:
 dispatch_confirmation_open=false;_dispatch_contract_id="";render(state)

func _settings() -> void:
 var dim:=ColorRect.new();dim.color=Color(0.04,0.08,0.2,0.48);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.add_child(dim)
 var panel:=_panel(Rect2((_size.x-440)/2,(_size.y-660)/2,440,660),CREAM,null,21);panel.set_meta("modal_panel",true);var b:=_box(panel,14);var row:=_row(b);_label(row,"稍歇一下",28);_spacer(row)
 var close:=Button.new();close.text="×";row.add_child(close);close.pressed.connect(func():settings_open=false;render(state))
 var sound_row:=_row(b);_label(sound_row,"声音",16,BLUE);_spacer(sound_row);_button(sound_row,"试听","test_sound",null,TEAL,32)
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
 var save_row:=_row(b,12);_button(save_row,"保存进度","save_progress",null,TEAL,46);_button(save_row,"保存并退出","save_and_quit",null,YELLOW,46)
 var done:=Button.new();done.set_meta("view_key","settings:done");done.set_meta("safe_modal_default",true);done.text="返回";done.custom_minimum_size.y=49;done.add_theme_stylebox_override("normal",_style(YELLOW,3,12));done.add_theme_color_override("font_color",INK);b.add_child(done);done.pressed.connect(func():settings_open=false;render(state))

func toast(text: String, tone: String = "info") -> void:
 if not _built:_build_root()
 _toast_raw_text=text;_toast_style=_style(CORAL if tone in ["error","warning"] else TEAL if tone=="success" else YELLOW,3,12);_position_toast();toast_panel.show();toast_timer=4.5
 toast_panel.modulate.a=0;var tween:=create_tween();tween.tween_property(toast_panel,"modulate:a",1.0,.16)

func _process(delta: float) -> void:
 if toast_timer>0:
  toast_timer-=delta
  if toast_timer<=0:toast_panel.hide()

func is_blocking_modal() -> bool:
 return settings_open or dispatch_confirmation_open or free_order_upgrade_open() or not _cancel_confirmation_id.is_empty()

func set_input_device(gamepad:bool) -> void:
 _gamepad=gamepad
 _refresh_workshop_labels()
 if flight_labels.has("controls"):
  if _force_flight_mode():
   flight_labels.controls.text="摇杆推进 · 松开滑行 · LT 刹车 · RB 加力" if _gamepad else "WASD 推进 · 松开滑行 · Ctrl 刹车 · Shift 加力"
   return
  if _free_flight_mode():
   flight_labels.controls.text="左摇杆 / 十字键 驾驶 · 松开刹车 · RB 加速" if _gamepad else "WASD / 方向键 驾驶 · 松开刹车 · Shift 加速"
   return
  var boost:String="全功率" if _extreme_mode() else "冲刺"
  flight_labels.controls.text=("左摇杆 / 十字键 升降    RB %s    A 触发回路" if _gamepad else "W / S  或  ↑ / ↓  升降    Shift  %s    Space  触发回路")%boost

func set_input_context(context:String) -> void:
 # Cosmetic only: follow the router's existing ownership without rebuilding UI.
 _input_context=context
 _refresh_workshop_labels()

func _refresh_workshop_labels() -> void:
 if mode!="workshop":return
 var grid:bool=_gamepad and _input_context=="grid"
 if _workshop_labels.has("assembly"):
  _workshop_labels.assembly.text="A 选 / 放 · Y 搬动 · X 旋转\nLB 拆卸 · R3 看全 · B 取消 / 返回" if grid else "方向选择 · A 确认当前按钮\nX 进入网格装配" if _gamepad and _input_context=="ui" else "返回工位后继续装配" if _gamepad else "点空格安装 · 拖模块换位\n中键平移 · 滚轮缩放 · F 看全"
 if _workshop_labels.has("palette"):
  _workshop_labels.palette.text="返回菜单选择零件" if grid else "方向选择 / A 确认" if _gamepad and _input_context=="ui" else "返回工位后选择零件" if _gamepad else "滚轮浏览 / 点击选择"
 if _workshop_labels.has("fit"):
  _workshop_labels.fit.text="看全工位 · R3" if grid else "看全工位" if _gamepad else "看全工位 · F"
  _workshop_labels.fit.tooltip_text="看全网格与装置 · R3 · 右摇杆平移" if grid else "看全网格与装置" if _gamepad else "看全网格与装置 · 中键拖动画面 · 滚轮围绕指针缩放"
 if _workshop_labels.has("rotate"):
  _workshop_labels.rotate.text="转向  [X]" if grid else "转向" if _gamepad else "转向  [R]"
 if _workshop_labels.has("remove"):
  _workshop_labels.remove.tooltip_text="退回库存 · LB" if grid else "退回库存" if _gamepad else "退回库存 · Delete"
 if _workshop_labels.has("undo"):
  _workshop_labels.undo.tooltip_text="撤销上一步装配 · RB" if grid else "撤销上一步装配" if _gamepad else "撤销上一步装配 · Ctrl+Z"

func controller_back() -> void:
 if free_order_upgrade_open():_dismiss_free_order_upgrade()
 elif dispatch_confirmation_open:_dismiss_dispatch()
 elif settings_open:settings_open=false;render(state)
 elif not _cancel_confirmation_id.is_empty():_cancel_confirmation_id="";toast_panel.hide();toast_timer=0;render(state)

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.keycode!=KEY_ESCAPE:return
 if free_order_upgrade_open():
  _dismiss_free_order_upgrade();get_viewport().set_input_as_handled();return
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
 node.position=target+DisplayMetrics.point(offset,_ui_scale);node.modulate.a=.35
 tween.set_parallel(true)
 tween.tween_property(node,"position",target,duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
 tween.tween_property(node,"modulate:a",1.0,minf(.12,duration)).set_delay(delay)

func _animate_mode_entry() -> void:
 content.modulate=Color.WHITE
 var count:=0
 for node in content.get_children():
  if not node is Control or node==_hotspot_layer:continue
  var offset:=Vector2(12,0)
  if node.position.y<160*_ui_scale:offset=Vector2(0,-8)
  elif node.position.y>(_size.y-300)*_ui_scale:offset=Vector2(0,12)
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
 # Raster/empty skins own their normal Button states; only flat skins expose
 # the shadow/margin properties used by this optional motion accent.
 var pressed_style:StyleBox=node.get_theme_stylebox("pressed")
 var hover_style:StyleBox=node.get_theme_stylebox("hover")
 var pressed:StyleBoxFlat=pressed_style.duplicate() as StyleBoxFlat if pressed_style is StyleBoxFlat else null
 var hover:StyleBoxFlat=hover_style.duplicate() as StyleBoxFlat if hover_style is StyleBoxFlat else null
 if pressed!=null:node.add_theme_stylebox_override("pressed",pressed)
 if hover!=null:node.add_theme_stylebox_override("hover",hover)
 node.button_down.connect(func():
  if not is_instance_valid(node) or pressed==null or _reduced_motion():return
  var t:=_motion_for(node,"feedback");t.set_parallel(true)
  t.tween_property(pressed,"expand_margin_left",-2.0,.055)
  t.tween_property(pressed,"expand_margin_right",-2.0,.055)
  t.tween_property(pressed,"expand_margin_top",-1.0,.055)
  t.tween_property(pressed,"shadow_offset",Vector2(1,1),.055)
 )
 node.button_up.connect(func():
  if not is_instance_valid(node):return
  if pressed!=null:
   pressed.expand_margin_left=0;pressed.expand_margin_right=0;pressed.expand_margin_top=0;pressed.shadow_offset=Vector2(4,5)
  if hover==null or _reduced_motion():return
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
  _launch_layer.display_density=_ui_scale
  DisplayMetrics.apply_control(_launch_layer,_ui_scale)
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


func _destination_name(order:Dictionary) -> String:
 var result:String=str(order.get("destination_name","")).strip_edges()
 if not result.is_empty():return result
 result=str(order.get("name","收件台"))
 if result.contains("→"):result=result.get_slice("→",result.get_slice_count("→")-1).strip_edges()
 return result


func _is_free_order(order:Dictionary) -> bool:
 return str(order.get("control_version","")) in ["pilot-free-v1","pilot-free-v2",DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS


func _free_flight_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-free-v1","pilot-free-v2",DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS


func _force_flight_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in ["pilot-free-v2",DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS

func _foldout(parent:Node,title:String,key:String) -> VBoxContainer:
 var open:bool=bool(_detail_open.get(key,false))
 var button:=Button.new();button.text=("收起 · " if open else "查看 · ")+title
 button.custom_minimum_size.y=36;button.add_theme_font_size_override("font_size",14)
 button.set_meta("view_key","details:"+key);parent.add_child(button)
 var detail:=_box(parent,6);detail.visible=open;detail.name="OptionalDetails"
 button.pressed.connect(func():
  detail.visible=not detail.visible;_detail_open[key]=detail.visible
  button.text=("收起 · " if detail.visible else "查看 · ")+title
 )
 return detail


func _build_destination_cue() -> void:
 _destination_cue=DeliveryDirectionCue.new();_destination_cue.name="DestinationDirection";content.add_child(_destination_cue)


func _update_destination_cue(data:Dictionary) -> void:
 if not is_instance_valid(_destination_cue):return
 var snapshot:Dictionary=data.get("destination_navigation",{}).duplicate()
 snapshot.charging=bool(data.get("charging",snapshot.get("charging",false)))
 var top:float=126.0 if _free_flight_mode() else 142.0
 _destination_cue.present(snapshot,root.get_global_transform().affine_inverse(),DisplayMetrics.rect(Rect2(38,top,maxf(1,_size.x-76),maxf(1,_size.y-top-174)),_ui_scale),_ui_scale)


func _free_flight() -> void:
 # New protocol: destination, real cargo speed/height, connected energy and
 # one current action. Numeric height always names its authored reference.
 var delivery:bool=_delivery_mode()
 var top:=_panel(Rect2(20,20,350 if delivery else 460,88),PANEL,null,10);top.name="FreeFlightGoal"
 var b:=_box(top,3)
 _label(b,"免费试飞" if bool(state.get("trial",false)) else "配送中",13,YELLOW)
 flight_labels["destination"]=_label(b,"送到"+_destination_name(state.get("activeorder",{})),24,WHITE)
 flight_labels.destination.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 flight_labels["status"]=_label(b,"朝箭头方向飞",17,TEAL)
 var telemetry:=_panel(Rect2(382 if delivery else 496,20,214 if delivery else 264,88),PANEL,null,10);telemetry.name="FlightTelemetry"
 var tb:=_box(telemetry,3 if str(state.get("activeorder",{}).get("control_version","")) in [DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION,"pilot-ascent-v6","pilot-rift-v6","pilot-ascent-v7","pilot-rift-v7","pilot-ascent-v8","pilot-rift-v8"] else 6)
 flight_labels["speed"]=_label(tb,"速度 — m/s",21,WHITE)
 flight_labels["height"]=_label(tb,"高度 — m",14 if delivery else 16,DIM)
 if str(state.get("activeorder",{}).get("control_version","")) in [DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION,"pilot-ascent-v6","pilot-rift-v6","pilot-ascent-v7","pilot-rift-v7","pilot-ascent-v8","pilot-rift-v8"]:
  flight_labels["receipt_speed"]=_label(tb,"",14,TEAL)
  flight_labels.receipt_speed.visible=false
 if delivery:_build_delivery_integrity()
 if not DeliveryUI.route_preview(state.get("activeorder",{})).is_empty():
  var rift:bool=RiftRiskUI.applies(state.get("activeorder",{}))
  var edge_legend:=_panel(Rect2(20,116,520 if rift else 258,30),PANEL,null,5);edge_legend.name="RouteBoundaryLegend"
  _label(edge_legend,"蓝框：冷区看货物中心 · 橙框：乱流看刚体重心" if rift else "橙色圆边：浮石接触边界",13,YELLOW)
 var resources:=_panel(Rect2(_size.x-280,20,260,88),PANEL,null,10);resources.name="FlightResources"
 var ib:=_box(resources,4)
 flight_labels["energy"]=_label(ib,"电量未知",26,YELLOW)
 _energy_bar=ProgressBar.new();_energy_bar.show_percentage=false;_energy_bar.custom_minimum_size.y=12;ib.add_child(_energy_bar)
 flight_labels["energy_warning"]=_label(ib,"",15,CORAL)
 var controls:=_panel(Rect2(20,_size.y-64,340,44),PANEL,null,4);var cr:=_row(controls,6)
 var pause_button:=_button(cr,"暂停  [Esc / P]","pause",null,YELLOW,34);pause_button.custom_minimum_size.x=184;_pause_button=weakref(pause_button)
 _spacer(cr);_button(cr,"中止本次","abort",null,PANEL_LIGHT,34).custom_minimum_size.x=116
 var legend:=_panel(Rect2(372,_size.y-64,minf(640,_size.x-392),44),PANEL,null,8)
 flight_labels["controls"]=_label(legend,"",15,WHITE)
 if _force_flight_mode():
  var tools:=_panel(Rect2(_size.x-260,_size.y-122,240,100),PANEL,null,8);tools.name="SelectedFlightTool"
  var tool_box:=_box(tools,3)
  flight_labels["tool_name"]=_label(tool_box,"",19,YELLOW)
  flight_labels["tool_state"]=_label(tool_box,"",16,WHITE)
  if DeliveryUI.cell_rules(state.get("activeorder",{})):
   flight_labels["tool_motion"]=_label(tool_box,"",13,WHITE)
   flight_labels["tool_impact"]=_label(tool_box,"",13,TEAL)
   flight_labels["tool_cost"]=_label(tool_box,"",13,WHITE)
   flight_labels["tool_scope"]=_label(tool_box,"",11,DIM)
  flight_labels["tool_keys"]=_label(tool_box,"",14,DIM)
 var events:=_panel(Rect2(20,_size.y-122,minf(650,_size.x-40),42),PANEL,null,8);events.name="FlightEventReceipt"
 flight_labels["events"]=_label(events,"",15,WHITE);flight_labels.events.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 _build_destination_cue();_build_flight_save_exit();set_input_device(_gamepad)
 _update_free_flight(state.get("flight",state))


func _update_free_flight(data:Dictionary) -> void:
 state["flight"]=data.duplicate(true)
 _update_flight_save_exit(data)
 _update_destination_cue(data)
 if _delivery_mode():_update_delivery_integrity(data)
 var paused:bool=bool(data.get("paused",false))
 var charging:bool=bool(data.get("charging",false))
 var status:String=str(data.get("flight_status",data.get("destination_navigation",{}).get("status","running")))
 var arrival:String=str(data.get("arrival_state","en_route"))
 var received:bool=status=="success" or arrival=="received"
 var pause_button:Button=_pause_button.get_ref() if _pause_button!=null else null
 if is_instance_valid(pause_button):pause_button.text=("继续" if paused else "暂停")+("  [Menu]" if _gamepad else "  [Esc / P]")
 var lunar_action:String=_lunar_arrival_action(data)
 flight_labels.status.text="货物已签收" if received else "配送失败" if status=="failed" else "已暂停" if paused else "准备起飞" if charging else ("按 LT 刹车收件" if _gamepad else "按 Ctrl 刹车收件") if arrival=="slow_down" and _force_flight_mode() else "松开方向键，减速收件" if arrival=="slow_down" else lunar_action if not lunar_action.is_empty() else "朝箭头方向飞"
 if MoonAscentPresenter.applies(state.get("activeorder",{})) and not received and status!="failed" and not paused and not charging:
  var imminent:Array[Dictionary]=MoonAscentPresenter.warnings_from(data)
  if not imminent.is_empty() or arrival=="en_route":flight_labels.status.text=MoonAscentPresenter.status_text(data)
  flight_labels.status.add_theme_color_override("font_color",YELLOW if not imminent.is_empty() else TEAL)
 if RiftPresenter.applies(state.get("activeorder",{})) and not received and status!="failed" and not paused and not charging:
  flight_labels.status.text=RiftPresenter.status_text(data)
  flight_labels.status.add_theme_color_override("font_color",YELLOW if RiftPresenter.has_warning(data) else TEAL)
 if received or status=="failed":_destination_cue.hide()
 var ship_speed:float=_flight_number(data,"speed",NAN)
 flight_labels.speed.text="速度 %.1f m/s"%maxf(0.0,ship_speed) if is_finite(ship_speed) and ship_speed>=0.0 else "速度 — m/s"
 flight_labels.speed.tooltip_text="订单货物所在飞行组件的实际合速度，含水平与垂直运动。"
 if flight_labels.has("receipt_speed"):
  var receipt_speed:Dictionary=DeliveryUI.receipt_speed(data,state.get("activeorder",{}))
  flight_labels.receipt_speed.visible=not receipt_speed.is_empty()
  flight_labels.receipt_speed.text=str(receipt_speed.get("text",""))
  flight_labels.receipt_speed.add_theme_color_override("font_color",CORAL if bool(receipt_speed.get("overspeed",false)) else TEAL)
 var height:Dictionary=_free_flight_height(data,state.get("activeorder",{}))
 flight_labels.height.text=("高度 %+.1f m"%float(height.value) if is_finite(float(height.value)) else "高度 — m")+" · "+str(height.label)
 flight_labels.height.tooltip_text=str(height.description)
 var energy:float=_flight_number(data,"energy_remaining",NAN)
 var capacity:float=_flight_number(data,"energy_capacity",NAN)
 var fraction:float=_flight_number(data,"energy_fraction",NAN)
 if not is_finite(fraction) and is_finite(energy) and is_finite(capacity) and capacity>0:fraction=energy/capacity
 var known:bool=is_finite(energy) and is_finite(fraction)
 if known:fraction=clampf(fraction,0,1)
 flight_labels.energy.text="电量 %.0f%%"%(fraction*100.0) if known else "电量未知"
 flight_labels.energy.tooltip_text="剩余 %s / %s"%[_flight_energy(energy),_flight_energy(capacity)]
 _energy_bar.visible=known;_energy_bar.value=fraction*100.0 if known else 0.0
 var low:bool=known and fraction<=.2 and status=="running" and not received
 # Terminal evidence has priority; preparation/running observations explain
 # unavailable cargo power without pretending a failure already happened.
 var power_failure:Dictionary=data.get("power_failure",data.get("power_status",{}) if _force_flight_mode() else {})
 var power_code:String=str(power_failure.get("code",""))
 var power_hint:String=str({"battery_disconnected":"货舱未接电芯","no_battery":"货舱缺电芯","battery_destroyed":"电芯已损毁","mixed_power_failure":"货舱供电中断","battery_unavailable":"货舱供电中断","energy_depleted":"货舱电量耗尽"}.get(power_code,""))
 if power_code=="energy_depleted" and known and energy<=0:power_hint="电量耗尽"
 # One failed cargo can coexist with another charged cargo. The total energy
 # bar must not suppress that cargo-specific terminal explanation.
 flight_labels.energy_warning.text=power_hint if not power_hint.is_empty() else "电量耗尽" if known and energy<=0 else "电量不足，尽快送达" if low else ""
 if DeliveryUI.coasting(data,state.get("activeorder",{})):
  flight_labels.energy_warning.text="无电滑行 · 主动装置需电"
  flight_labels.energy_warning.tooltip_text="货物继续按惯性和重力运动。仍可合格收件；也可点左下角「中止本次」。"
 else:flight_labels.energy_warning.tooltip_text=""
 flight_labels.energy.add_theme_color_override("font_color",CORAL if low or not power_hint.is_empty() else YELLOW)
 # Retain actual collision and failure notices, never an idle telemetry wall.
 var receipt:Dictionary=data.duplicate();receipt.control_version=str(state.get("control_version",state.get("activeorder",{}).get("control_version","pilot-free-v1")))
 var items:Array[Dictionary]=_flight_receipt.update_free(receipt,1)
 flight_labels.events.text=_brief_flight_event(str(items[-1].text)) if not items.is_empty() else ""
 # A bounded split acknowledgement shares this existing line with the actual
 # micro-contact warning; terminal and meaningful damage remain authoritative.
 if not items.is_empty() and not str(items[-1].get("short_success","")).is_empty():
  flight_labels.events.text=str(items[-1].short_success)+" · "+flight_labels.events.text
 if not DeliveryUI.cell_rules(state.get("activeorder",{})) and not power_hint.is_empty() and str(data.get("free_failure",""))=="usable_energy_empty":flight_labels.events.text=_report_failure_copy(data)
 # Keep the existing damage/failure message first. Paid shield absorption is
 # only a short suffix in this same receipt, never a permanent status panel.
 var shield_copy:String=_flight_receipt.shield_receipt(receipt)
 var event_label:Label=flight_labels.events
 var event_panel:Control=content.get_node_or_null("FlightEventReceipt")
 if not shield_copy.is_empty():
  if event_label.text.is_empty():event_label.text=shield_copy
  else:
   # A fresh Label has no laid-out width yet: retain the original warning and
   # retry on the next flight update. Use current native font/width each time.
   var available:float=event_label.size.x
   if event_panel is PanelContainer:
    # A resize may shrink the panel before its Label receives the new size.
    available=minf(available,event_panel.size.x-event_panel.get_theme_stylebox("panel").get_minimum_size().x)
   available=maxf(0.0,available-event_label.get_theme_stylebox("normal").get_minimum_size().x)
   var combined:String=event_label.text+" · "+shield_copy
   var font:Font=event_label.get_theme_font("font")
   var font_size:int=event_label.get_theme_font_size("font_size")
   # Adding an overflowing suffix can make the end ellipsis eat a previously
   # fitting final warning glyph. Admit the entire line, never a partial cue.
   if available>0.0 and ceilf(font.get_string_size(combined,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)<=floorf(available):
    event_label.text=combined
 if event_panel!=null:event_panel.visible=not flight_labels.events.text.is_empty()
 if flight_labels.has("tool_name"):
  var tool:Dictionary=data.get("selected_tool",{})
  var panel:Control=content.get_node_or_null("SelectedFlightTool")
  if panel!=null:panel.visible=not tool.is_empty() and status=="running"
  flight_labels.tool_name.text=str(tool.get("name",""))+"  "+str(tool.get("direction",""))
  var hold_to_use:bool=bool(tool.get("hold_to_use",false))
  flight_labels.tool_state.text="已暂停" if hold_to_use and paused else str(tool.get("status",""))
  flight_labels.tool_state.tooltip_text=DeliveryUI.accelerator_copy(tool.accelerator_preview) if tool.get("accelerator_preview") is Dictionary else ""
  var details:Dictionary=DeliveryUI.accelerator_details(tool.get("accelerator_preview",{})) if DeliveryUI.cell_rules(state.get("activeorder",{})) else {}
  if flight_labels.has("tool_motion"):
   for key in ["motion","impact","cost","scope"]:
    flight_labels["tool_"+key].visible=not details.is_empty()
    flight_labels["tool_"+key].text=str(details.get(key,""))
   flight_labels.tool_impact.add_theme_color_override("font_color",CORAL if bool(details.get("below_minimum",false)) else TEAL)
   if panel!=null:
    DisplayMetrics.set_rect_override(panel,Rect2(_size.x-(380 if not details.is_empty() else 260),_size.y-(208 if not details.is_empty() else 122),360 if not details.is_empty() else 240,186 if not details.is_empty() else 100))
  var visual:Dictionary=tool.get("accelerator_preview",{}).duplicate(true) if status=="running" and not charging else {}
  if not visual.is_empty():visual.control_version=str(state.get("activeorder",{}).get("control_version",""));visual.context="flight"
  accelerator_preview_changed.emit(visual)
  flight_labels.tool_keys.text=("Y 切换 · 按住 A" if _gamepad else "Q 切换 · 按住 Space") if hold_to_use else ("Y 切换 · A 使用" if _gamepad else "Q 切换 · Space 使用")



func _lunar_arrival_action(data:Dictionary) -> String:
 # Read-only, lunar-only context for the existing action row. The preview
 # radius is the same one the camera uses; this is never a flight speed cap.
 var order:Dictionary=state.get("activeorder",{})
 if str(order.get("control_version",""))!="pilot-free-v2" or str(order.get("route_profile",""))!="lunar-outpost-v2":return ""
 var values:Array=[order.get("delivery_radius"),order.get("max_delivery_speed"),data.get("destination_distance"),data.get("speed")]
 for value in values:
  if not (value is int or value is float) or not is_finite(float(value)):return ""
 var radius:float=float(values[0]);var limit:float=float(values[1]);var distance:float=float(values[2]);var speed:float=float(values[3])
 if radius<=0.0 or limit<=0.0 or distance<0.0 or speed<0.0:return ""
 if distance>radius+FreeFlightFraming.ARRIVAL_MARGIN_M+FreeFlightFraming.PREVIEW_MARGIN_M:return ""
 if speed>limit:return "按 LT 减速交件" if _gamepad else "按 Ctrl 减速交件"
 return "进入光圈交件"


func _free_flight_height(data:Dictionary,order:Dictionary) -> Dictionary:
 # This 2D route has no sampled physical terrain mesh. Do not call -Y local
 # terrain clearance or orbital altitude. A persisted scene-ground plane is
 # the best available datum; otherwise use the route's launch-coordinate zero.
 var at_y:float=_flight_number(data,"cargo_y",NAN)
 if not is_finite(at_y):
  var altitude:float=_flight_number(data,"altitude",NAN)
  if is_finite(altitude):at_y=-altitude
 var ground:float=_flight_number(order,"background_ground_y_m",NAN)
 if is_finite(ground):
  return {"value":ground-at_y,"label":"地面基准","description":"订单货物相对场景地面基准线的高度；正值在基准线上方。不是脚下地形净空。"}
 return {"value":-at_y,"label":"起飞基准","description":"订单货物相对航线起飞坐标零点的高度；正值向上。此航线没有独立的地面高度数据。"}


func _insured_order(order:Dictionary) -> bool:
 return _is_free_order(order) and not DeliveryUI.applies(order) and str(order.get("economy_policy",""))=="free-flight-economy-v1"


func _insured_report(report:Dictionary) -> bool:
 return str(report.get("control_version","")) in ["pilot-free-v1","pilot-free-v2"] and str(report.get("economy_policy",""))=="free-flight-economy-v1" and report.has("insurance_coverage") and report.has("charged_costs")


func _event_message(raw:String) -> String:
 var message:String=raw
 var separator:int=message.find("s  ")
 if separator>0 and message.left(separator).is_valid_float():message=message.substr(separator+3)
 return message.strip_edges()


func _terminal_failure_copy(raw:String) -> String:
 var message:String=_event_message(raw)
 var known:Dictionary={
  "操作员中止本次航行。":"你结束了本次飞行。",
  "货舱可用能量耗尽，委托失败。":"电量耗尽，没能送达。",
  "部分货物损毁，委托失败。":"货物损毁，配送失败。",
  "抵达速度过高，收货平台拒收。":"进站太快，收件台没能接住。",
  "货物未全部抵达，委托超时。":"超时了，货物还没送到。",
  "货物偏离收货区，委托失败。":"飞出了这单的收货范围。",
  "错过了虫洞，未能到达苔光驿站。":"错过了虫洞入口。",
  "飞行状态超出有限数值范围，安全结束本次试飞。":"飞行出现异常，本次已停止。"
 }
 return str(known.get(message,""))


func _report_failure_copy(report:Dictionary) -> String:
 # A repair receipt or nonfatal first hit is not the reason a delivery ended.
 # Prefer an actual terminal message. Never infer a failure from cargo health.
 if DeliveryUI.applies(report) or (not report.has("control_version") and _delivery_mode()):
  if str(report.get("delivery_failure","")) in ["integrity_below_minimum","cargo_integrity_below_minimum","integrity_below_requirement"]:return "货物完整度低于本单最低要求，未能合格交付。"
 var free_failure:String=str(report.get("free_failure",""))
 if free_failure=="usable_energy_empty":
  var power_code:String=str(report.get("power_failure",{}).get("code",""))
  match power_code:
   "battery_disconnected":return "电芯未连到货舱。回工位接好再试。"
   "no_battery":return "货舱没有电芯。回工位装上再试。"
   "battery_destroyed":return "供电电芯已损毁，没能送达。"
   "battery_unavailable":return "电芯已随其他货物送达，货舱供电中断。"
   "mixed_power_failure":return "货舱供电中断。回工位检查电芯。"
  return "电量耗尽，没能送达。"
 if free_failure=="cargo_destroyed":return "货物损毁，配送失败。"
 var events:Variant=report.get("events",[])
 if events is Array:
  for index in range(events.size()-1,-1,-1):
   var terminal:String=_terminal_failure_copy(str(events[index]))
   if not terminal.is_empty():return terminal
 var cause:String=_event_message(str(report.get("failure_reason",report.get("cause",""))))
 var mapped:String=_terminal_failure_copy(cause)
 if not mapped.is_empty():return mapped
 if not cause.is_empty() and not cause.begins_with("自动整备") and not cause.begins_with("首次受损") and not cause.begins_with("救援回收") and not cause.contains("补齐") and not cause.contains("不重复计费") and not cause.begins_with("发射"):
  return cause
 return "这趟没能送达。回工位检查后再试试。"


func _brief_flight_event(raw:String) -> String:
 var message:String=_event_message(raw)
 if message.begins_with("自动整备") or message.begins_with("救援回收"):return ""
 var terminal:String=_terminal_failure_copy(message)
 if not terminal.is_empty():return terminal
 if message.begins_with("受损："):
  if message.contains("过载"):return "结构受力过大，零件受损。"
  if message.contains("攻击"):return "零件遭到攻击。"
  if message.contains("碰撞"):return "发生碰撞，零件受损。"
  return "零件受损。"
 return message


func _day_basic_supply() -> void:
 var b:=_drawer("添件工具，再出发。","零件补给",440,608)
 _parts_retirement_entry(b)
 _para(b,"钻头破石，位移越障，分裂会让零件一分为二。",15,TEAL)
 var body:=_scroll(b)
 for spec in _catalog_entries():
  var kind:String=str(spec.get("type",spec.get("id","")))
  if not WorkshopParts.is_core(kind):continue
  var row_panel:=PanelContainer.new();row_panel.add_theme_stylebox_override("panel",_style(CREAM,2,8,false));body.add_child(row_panel)
  var row:=_row(row_panel,9);_part_icon(row,kind,Vector2(40,40));var text:=_box(row,0);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _label(text,str(spec.get("name",kind)),17)
  _label(text,"已有 %d"%int(state.get("inventory",{}).get(kind,0)),12,MUTED)
  var cost:int=int(spec.get("price",0))
  var buy:=_button(row,"买一件  ¥%d"%cost,"buy",kind,YELLOW,42)
  buy.set_meta("day_basic_kind",kind);buy.disabled=int(state.get("credits",0))<cost
 _rule(b)
 _button(b,"回工位装上  →","focus_workbench",null,TEAL,46)
 var close:=_button(b,"打烊","close_day",null,PANEL_LIGHT,40);close.disabled=_has_accepted()


func _delivery_mode() -> bool:
 return str(state.get("control_version",state.get("activeorder",{}).get("control_version",""))) in [DeliveryUI.VERSION,DeliveryUI.ASCENT_VERSION,DeliveryUI.RIFT_VERSION]+DeliveryUI.CELL_VERSIONS


func _delivery_launcher_controls(parent:Node) -> void:
 _para(parent,"0° 向右 · 90° 向上",13,TEAL)
 var settings:Dictionary=DeliveryUI.launch_settings(state)
 _delivery_launch_slider(parent,"发射角度","angle_degrees",float(settings.angle_degrees),90.0,1.0,"°")
 _delivery_launch_slider(parent,"发射力度","power_fraction",float(settings.power_fraction)*100.0,100.0,1.0,"%")
 _delivery_launch_labels["numbers"]=_para(parent,"",13,WHITE)
 _delivery_launch_preview=DeliveryLaunchPreview.new();_delivery_launch_preview.name="DeliveryTrajectoryPreview";_delivery_launch_preview.custom_minimum_size=Vector2(0,72);parent.add_child(_delivery_launch_preview)
 _delivery_launch_labels["warning"]=_para(parent,"",12,YELLOW)
 _para(parent,"弧线按当前质量与储能预测，不含操控和碰撞。",11,DIM)
 _refresh_delivery_launch_preview()


func _delivery_launch_slider(parent:Node,title:String,key:String,value:float,maximum:float,increment:float,unit:String) -> void:
 # Same native HSlider and commit-on-release interaction as part parameters.
 # A setting is intent only; numeric estimates await the controller's solver.
 var caption:=_label(parent,"%s %.0f%s"%[title,value,unit],13,TEAL)
 var slider:=HSlider.new();slider.name="LaunchAngleSlider" if key=="angle_degrees" else "LaunchPowerSlider"
 slider.min_value=0.0;slider.max_value=maximum;slider.step=increment;slider.custom_minimum_size=Vector2(0,30);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 slider.set_value_no_signal(value);slider.set_meta("view_key","launch:"+key);slider.tooltip_text="拖动调整，松开更新物理预览；键盘左右 / 手柄方向键微调。";parent.add_child(slider)
 var dragging:Array=[false]
 var generation:int=_render_generation
 slider.drag_started.connect(func():dragging[0]=true)
 slider.value_changed.connect(func(next:float):
  if generation!=_render_generation:return
  caption.text="%s %.0f%s"%[title,next,unit]
  if bool(dragging[0]):
   if _delivery_launch_labels.has("numbers"):_delivery_launch_labels.numbers.text="松开滑条后更新发射预览"
   if is_instance_valid(_delivery_launch_preview):_delivery_launch_preview.present({},false)
   for button in _delivery_launch_buttons:button.disabled=true
  else:_commit_delivery_launch(slider,key,generation)
 )
 slider.drag_ended.connect(func(changed:bool):
  dragging[0]=false
  if changed:_commit_delivery_launch(slider,key,generation)
  elif generation==_render_generation:_refresh_delivery_launch_preview()
 )


func _commit_delivery_launch(slider:HSlider,key:String,generation:int) -> void:
 if not is_instance_valid(slider) or generation!=_render_generation or mode!="workshop" or not _delivery_mode() or is_blocking_modal():return
 var settings:Dictionary=DeliveryUI.launch_settings(state)
 var value:float=slider.value*.01 if key=="power_fraction" else slider.value
 if is_equal_approx(float(settings[key]),value):
  _refresh_delivery_launch_preview();return
 settings[key]=value;state.launch_settings=settings;state.launch_preview={}
 _refresh_delivery_launch_preview()
 _act("set_launch_settings",settings.duplicate(true))


func update_delivery_launch_preview(settings:Dictionary,preview:Dictionary) -> void:
 if not _delivery_mode():return
 state.launch_settings=settings.duplicate(true);state.launch_preview=preview.duplicate(true)
 _refresh_delivery_launch_preview()


func _refresh_delivery_launch_preview() -> void:
 if not _delivery_mode():return
 var settings:Dictionary=DeliveryUI.launch_settings(state)
 var preview:Dictionary=state.get("launch_preview",{})
 var ready:bool=DeliveryUI.preview_matches(preview,settings)
 if _delivery_launch_labels.has("numbers"):_delivery_launch_labels.numbers.text=DeliveryUI.launch_copy(preview,settings)
 if is_instance_valid(_delivery_launch_preview):_delivery_launch_preview.present(preview,ready)
 if _delivery_launch_labels.has("warning"):
  var warning:String=str(preview.get("warning","")) if ready else "等待同一设置的物理预览"
  if ready and warning.is_empty() and bool(preview.get("support_limited",false)):warning="已达到发射台支撑上限"
  if ready and warning.is_empty() and bool(preview.get("energy_limited",false)):warning="有效储能不足，已按可用能量计算"
  if ready and warning.is_empty() and not bool(preview.get("can_release",false)):warning="当前发射台无法释放，请检查装配"
  _delivery_launch_labels.warning.text=warning
 for button in _delivery_launch_buttons:button.disabled=not ready or not bool(preview.get("can_release",false))


func _build_delivery_integrity() -> void:
 var panel:=_panel(Rect2(608,20,maxf(260,_size.x-908),88),PANEL,null,10);panel.name="CargoIntegrityPanel"
 var box:=_box(panel,3)
 var headline:=_row(box,4);_label(headline,"货物完整度",14,DIM);_spacer(headline)
 flight_labels["integrity"]=_label(headline,"—",21,YELLOW)
 _cargo_integrity_bar=CargoIntegrityBar.new();_cargo_integrity_bar.name="CargoIntegrityBar";_cargo_integrity_bar.custom_minimum_size.y=12;box.add_child(_cargo_integrity_bar)
 var detail:=_row(box,4)
 flight_labels["integrity_minimum"]=_label(detail,"最低 —",12,WHITE);_spacer(detail)
 flight_labels["integrity_status"]=_label(detail,"",12,TEAL)
 if RiftRiskUI.applies(state.get("activeorder",{})):
  var biology_panel:=_panel(Rect2(608,112,maxf(260,_size.x-908),52),PANEL,null,6);biology_panel.name="RiftBiologyPanel"
  var biology_box:=_box(biology_panel,2)
  flight_labels["biology"]=_label(biology_box,"",13,TEAL);flight_labels.biology.name="RiftBiologyStatus"
  flight_labels["biology_note"]=_label(biology_box,"",12,DIM);flight_labels.biology_note.name="RiftBiologyNote"
  biology_panel.tooltip_text="冷区按货物中心计时，护盾不保温。离开冷区重置连续暴露并停止新增冷损；已有损伤不会自动修复。"


func _update_delivery_integrity(data:Dictionary) -> void:
 if not is_instance_valid(_cargo_integrity_bar):return
 var value:Dictionary=DeliveryUI.integrity(data,state.get("activeorder",{}))
 flight_labels.integrity.text=value.current_text
 flight_labels.integrity_minimum.text=value.minimum_text
 flight_labels.integrity_status.text=value.status
 if flight_labels.has("biology"):
  var biology:Dictionary=RiftRiskUI.biology(data,state.get("activeorder",{}))
  flight_labels.biology.get_parent().get_parent().visible=not biology.is_empty()
  if not biology.is_empty():
   flight_labels.biology.text=biology.text;flight_labels.biology_note.text=biology.note
   flight_labels.biology.add_theme_color_override("font_color",CORAL if biology.cold else TEAL)
 var color:Color=CORAL if value.known and not value.qualified else YELLOW
 flight_labels.integrity.add_theme_color_override("font_color",color)
 flight_labels.integrity_status.add_theme_color_override("font_color",CORAL if value.known and not value.qualified else TEAL)
 _cargo_integrity_bar.present(float(value.current),float(value.minimum))
 DisplayMetrics.set_style_override(_cargo_integrity_bar,"fill",_style(color,0,0,false))
 _cargo_integrity_bar.tooltip_text="唯一生命条：当前货物完整度。白色标线为本单最低交付要求；低于标线不合格。"


func _delivery_route_sketch(parent:Node,order:Dictionary)->void:
 var copy:String=DeliveryUI.route_copy(order)
 if copy.is_empty():return
 var rift:bool=RiftRiskUI.applies(order)
 var repeat:String=DeliveryUI.repeat_copy(order)
 # In the compact rift workbench, put the repeat tag beside the original map
 # rather than making the map smaller or pushing the build area downward.
 var side_repeat:bool=rift and mode=="workshop" and not repeat.is_empty() and not DeliveryUI.route_preview(order).is_empty()
 var heading_copy:String=copy.trim_prefix(repeat+"\n") if side_repeat else copy
 var heading:=_para(parent,heading_copy,13,BLUE) if rift or order.get("route_layout",{}).get("id")==DeliveryRoutePreview.Layout.ROCKBELT_ID or not DeliveryUI.ascent_geometry_copy(order).is_empty() else _label(parent,heading_copy,13,BLUE);heading.name="RouteClearance"
 if DeliveryUI.route_preview(order).is_empty():return
 var heavy:bool=DeliveryUI.heavy_route(order)
 heading.tooltip_text="本单真实高度、货物质量与完整度要求；图仅标位置。试飞免费。" if heavy else "本单路线净空；需考虑整船尺寸、旋转与操控余量。试飞免费。"
 var sketch=DeliveryRoutePreview.new();sketch.name="DeliveryRouteSketch";sketch.custom_minimum_size=Vector2(0,56 if copy.begins_with("自选复送 · 不推进章节\n") else 80);sketch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 if rift:
  heading.tooltip_text=RiftRiskUI.tooltip(order)
  var body:Node=_row(parent,8) if mode=="workshop" else parent
  sketch.custom_minimum_size=Vector2(240 if mode=="workshop" else 0,70 if mode=="workshop" else 80)
  if mode=="workshop":sketch.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
  body.add_child(sketch)
  var guidance_parent:Node=body
  if side_repeat:
   var notes:=_box(body,0);notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL;guidance_parent=notes
   var repeat_heading:=_label(notes,repeat,12,BLUE);repeat_heading.name="OptionalRepeatLabel"
  var guidance:=_para(guidance_parent,RiftRiskUI.guidance(order),12,MUTED);guidance.name="RiftRoutePreparation";guidance.tooltip_text=RiftRiskUI.tooltip(order)
 elif heavy:
  var body:Node=_row(parent,8) if mode=="workshop" else parent
  sketch.custom_minimum_size=Vector2(160 if mode=="workshop" else 0,52)
  if mode=="workshop":sketch.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
  body.add_child(sketch)
  var guidance:=_para(body,DeliveryUI.route_guidance(order),13,MUTED);guidance.name="HeavyRoutePreparation"
  guidance.tooltip_text="弹簧、喷口等动力件提供发射工作量，电芯供电，支撑承载；这些部件需相连。实际输出看发射预览。也可用默认台配船上推进，先免费试飞。"
 else:parent.add_child(sketch)
 sketch.present(order)
