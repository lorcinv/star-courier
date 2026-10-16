extends Control
## Development title entry; illustrated presentation is independent of saves. No Main/Economy instance exists while the menu is open.
## Native Godot ui_* focus supports keyboard and SDL-standard gamepad events.
## This is not evidence that physical hardware has been exercised.
const RasterSkin=preload("res://scripts/demo_raster_skin.gd")
const SaveGuard=preload("res://scripts/demo_save_guard.gd")
const PixelStage=preload("res://scripts/pixel_stage.gd")
const WorldView=preload("res://scripts/world_view_2d.gd")
const PartsDB=preload("res://scripts/parts_expanded.gd")
const Bell=preload("res://scripts/demo_bell.gd")
const DisplayMetrics=preload("res://scripts/demo_display_metrics.gd")
const TITLE_LOGO_PATH:String="res://assets/2d_v5/title/star-courier-pixel-v2.png"
const TITLE_CHINESE_PATH:String="res://assets/2d_v5/title/xingji-kuaidi-pixel-v2.png"
const PROLOGUE_IMAGES:Array[String]=[
 "res://assets/2d_v5/prologue/prologue-01-fleet.png",
 "res://assets/2d_v5/prologue/prologue-02-departure.png",
 "res://assets/2d_v5/prologue/prologue-03-shop.png"
]
const PROLOGUE_MUSIC:Array[String]=[
 "res://assets/audio/prologue_fleet.ogg",
 "res://assets/audio/prologue_departure.ogg",
 "res://assets/audio/prologue_shop.ogg"
]
@export var clerk_pose_bootstrap_script:Script
const PROLOGUE:Array[String]=[
 "在星际第一联合舰队，你画过能穿过风暴的舰船，也见过它们驶向一次又一次没有尽头的远征。",
 "后来，你交还了首席舰船设计师的徽章。带走的只有一箱工具，和几张一直没机会造出来的民用图纸。",
 "你在星港边缘租下一间旧店。今天要装进货舱的，是花种、修好的零件，还有某个人等了很久的信。"
]
const MENU_MUSIC_INDEX:int=-2
const MENU_MUSIC:AudioStream=preload("res://assets/audio/workshop_loop.ogg")
const TEST_SOUND:AudioStream=preload("res://assets/audio/delivery_success.wav")
const TITLE_UI_SOUND:AudioStream=preload("res://assets/audio/ui_select.wav")
const MAIN_SCENE:String="res://scenes/main.tscn"
const DEFAULT_SETTINGS:Dictionary={"volume":.55,"reduced_motion":false,"motion_blur":true,"pixel_density":"auto","controller_deadzone":.22,"fullscreen":false}
const INK:Color=Color("101a30")
const PANEL:Color=Color("17243a")
const CREAM:Color=Color("fff3d7")
const TEAL:Color=Color("49cce5")
const YELLOW:Color=Color("ffca57")
var save_guard=SaveGuard.new()
var settings:Dictionary=DEFAULT_SETTINGS.duplicate(true)
var setting_overrides:Dictionary={}
var title_stage:Control
var title_layer:CanvasLayer
var preview_stage
var preview_world
var _preview_error:String=""
var _preview_ready:bool=false
var _prologue_index:int=0
var _prologue_accepted:bool=false
var _prologue_layer:Control
var _prologue_image:TextureRect
var _prologue_story:Label
var _prologue_counter:Label
var _prologue_textures:Array[Texture2D]=[]
var _prologue_streams:Array[AudioStream]=[]
var _presentation_error:String=""
var _prologue_transition:Tween
var _prologue_music:AudioStreamPlayer
var _title_test_sound:AudioStreamPlayer
var _title_ui_sound:AudioStreamPlayer
var _title_navigation_pending:bool=false
var _audio_test_status:String=""
var _music_tween:Tween
var _music_gain:float=0.0
var _music_index:int=-1
var _music_generation:int=0
var _settings_return_screen:String="menu"
var _title_decor:Array[Control]=[]
var _opening_age:float=0.0
var _opening_done:bool=false
var _opening_failed:bool=false
var _retiring_restore:bool=false
var _opening_world
var _opening_colors:Dictionary={}
var _opening_badge:Label
var _restore_cancel:Button
var _bell:AudioStreamPlayer
var panel:PanelContainer
var menu:BoxContainer
var status:Label
var continue_button:Button
var new_button:Button
var settings_button:Button
var game
var busy:bool=false
var _closing:bool=false
var screen:String="menu"
var _window_focused:bool=true
var _launch_waiting_for_focus:bool=false
var _pending_launch_new_game:bool=false
var _accept_quarantined:bool=false
var _focus_return:Button
var _title_added_events:Dictionary={}
var _title_previous_deadzones:Dictionary={}
var _title_created_actions:Array[String]=[]
var _title_held_accept_buttons:Dictionary={}
const TITLE_UI_DIRECTIONS:Array[String]=["ui_left","ui_right","ui_up","ui_down"]

func _ready() -> void:
 get_tree().auto_accept_quit=false
 get_window().title="星际快递"
 get_window().min_size=Vector2i(1280,720)
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 get_window().content_scale_size=Vector2i.ZERO
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _window_focused=get_window().has_focus()
 theme=_make_theme()
 _read_settings_preview()
 if DisplayServer.get_name()!="headless" and bool(settings.get("fullscreen",false)):DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 _install_title_actions()
 if not Input.joy_connection_changed.is_connected(_title_joy_connection_changed):Input.joy_connection_changed.connect(_title_joy_connection_changed)
 _build_preview()
 _build_title()
 get_viewport().size_changed.connect(_layout)
 get_window().focus_exited.connect(_focus_exited)
 get_window().focus_entered.connect(_focus_entered)
 _window_focused=get_window().has_focus()
 if is_instance_valid(preview_world):preview_world.set_focus_active(_window_focused)
 _layout()
 _show_menu()

func _install_title_actions() -> void:
 # Some exported/headless configurations contain keyboard-only builtin ui_*
 # bindings. Install native GUI gamepad events while this title owns input.
 var buttons:Dictionary={"ui_accept":JOY_BUTTON_A,"ui_cancel":JOY_BUTTON_B,"ui_left":JOY_BUTTON_DPAD_LEFT,"ui_right":JOY_BUTTON_DPAD_RIGHT,"ui_up":JOY_BUTTON_DPAD_UP,"ui_down":JOY_BUTTON_DPAD_DOWN}
 for action in buttons:
  if not InputMap.has_action(action):
   InputMap.add_action(action);_title_created_actions.append(action)
  var event:=InputEventJoypadButton.new();event.device=-1;event.button_index=buttons[action]
  _add_title_action_event(action,event)
 for action in TITLE_UI_DIRECTIONS:
  if not _title_previous_deadzones.has(action):_title_previous_deadzones[action]=InputMap.action_get_deadzone(action)
  var event:=InputEventJoypadMotion.new();event.device=-1
  event.axis=JOY_AXIS_LEFT_X if action in ["ui_left","ui_right"] else JOY_AXIS_LEFT_Y
  event.axis_value=-1.0 if action in ["ui_left","ui_up"] else 1.0
  _add_title_action_event(action,event)
 _update_title_deadzone()

func _add_title_action_event(action:String,event:InputEvent) -> void:
 if InputMap.action_has_event(action,event) or _title_binding_conflicts(action,event):return
 InputMap.action_add_event(action,event)
 if not _title_added_events.has(action):_title_added_events[action]=[]
 _title_added_events[action].append(event)

func _title_binding_conflicts(action:String,event:InputEvent) -> bool:
 # Do not turn a pre-existing swapped A/B or directional binding into two
 # simultaneous ui_* actions. Defaults yield to the player's existing map.
 for other in InputMap.get_actions():
  if other==action or not str(other).begins_with("ui_"):continue
  for bound in InputMap.action_get_events(other):
   if event.device!=-1 and bound.device!=-1 and event.device!=bound.device:continue
   if event is InputEventJoypadButton and bound is InputEventJoypadButton and event.button_index==bound.button_index:return true
   if event is InputEventJoypadMotion and bound is InputEventJoypadMotion and event.axis==bound.axis and signf(event.axis_value)==signf(bound.axis_value):return true
 return false

func _title_accept_is_held(excluded_device:int=-1) -> bool:
 # Read other owners' physical state, never release their global action. Raw
 # events retained by this title also support disconnected synthetic fixtures.
 for token in _title_held_accept_buttons:
  if token.x!=excluded_device:return true
 for event in InputMap.action_get_events("ui_accept"):
  if event is InputEventKey:
   if event.physical_keycode!=0 and Input.is_physical_key_pressed(event.physical_keycode):return true
   if event.keycode!=0 and Input.is_key_pressed(event.keycode):return true
  elif event is InputEventMouseButton and Input.is_mouse_button_pressed(event.button_index):return true
  elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
   for device in Input.get_connected_joypads():
    if device==excluded_device or (event.device!=-1 and event.device!=device):continue
    if event is InputEventJoypadButton and Input.is_joy_button_pressed(device,event.button_index):return true
    if event is InputEventJoypadMotion and Input.get_joy_axis(device,event.axis)*signf(event.axis_value)>InputMap.action_get_deadzone("ui_accept"):return true
 return false

func _title_joy_connection_changed(device:int,connected:bool) -> void:
 if connected or screen=="game":return
 for token in _title_held_accept_buttons.keys():
  if token.x==device:_title_held_accept_buttons.erase(token)
 if _accept_quarantined:_accept_quarantined=_title_accept_is_held(device)

func _update_title_deadzone() -> void:
 for action in _title_previous_deadzones:
  if InputMap.has_action(action):InputMap.action_set_deadzone(action,clampf(float(settings.controller_deadzone),.10,.45))

func _restore_title_actions() -> void:
 if Input.joy_connection_changed.is_connected(_title_joy_connection_changed):Input.joy_connection_changed.disconnect(_title_joy_connection_changed)
 _title_held_accept_buttons.clear()
 # Remove only events inserted by this owner. Existing keyboard/gamepad maps
 # are untouched, and Main's CourierInput keeps exclusive gameplay routing.
 for action in _title_added_events:
  if not InputMap.has_action(action):continue
  for event in _title_added_events[action]:InputMap.action_erase_event(action,event)
 for action in _title_previous_deadzones:
  if InputMap.has_action(action):InputMap.action_set_deadzone(action,float(_title_previous_deadzones[action]))
 for action in _title_created_actions:
  if InputMap.has_action(action):InputMap.erase_action(action)
 _title_added_events.clear();_title_previous_deadzones.clear();_title_created_actions.clear()

func _exit_tree() -> void:
 _kill_prologue_transition()
 _stop_prologue_music(false)
 _dispose_title_test_sound()
 _dispose_title_ui_sound()
 _dispose_bell()
 _restore_title_actions()

func _read_settings_preview() -> void:
 # Read bounded presentation preferences only. Do not migrate, validate/repair
 # gameplay, call Economy.load_state, or persist anything from this menu.
 for filename in SaveGuard.SLOT_NAMES:
  var path:String=save_guard.save_root.path_join(filename)
  if not FileAccess.file_exists(path):continue
  var json:=JSON.new()
  if json.parse(FileAccess.get_file_as_string(path))!=OK or not json.data is Dictionary:continue
  var saved:Variant=json.data.get("settings",{})
  if not saved is Dictionary:continue
  for key in ["reduced_motion","motion_blur","fullscreen"]:
   if saved.get(key) is bool:settings[key]=saved[key]
  for key in ["volume","controller_deadzone"]:
   var value:Variant=saved.get(key)
   if (value is int or value is float) and is_finite(float(value)):
    settings[key]=clampf(float(value),.10 if key=="controller_deadzone" else 0.0,.45 if key=="controller_deadzone" else 1.0)
  if saved.get("pixel_density") in ["auto","balanced","low"]:settings.pixel_density=saved.pixel_density
  return

func _make_theme() -> Theme:
 var result:=Theme.new()
 result.default_font=preload("res://assets/fonts/TitleChineseSans.otf")
 result.default_font_size=20
 result.set_color("font_color","Label",CREAM)
 for kind in ["Button","CheckBox","OptionButton"]:
  result.set_color("font_color",kind,CREAM)
  result.set_color("font_hover_color",kind,INK)
  result.set_color("font_pressed_color",kind,INK)
  result.set_color("font_hover_pressed_color",kind,INK)
  result.set_color("font_disabled_color",kind,Color("a8b8cb"))
  result.set_stylebox("normal",kind,_style(Color("253b58")))
  result.set_stylebox("hover",kind,_style(YELLOW))
  result.set_stylebox("pressed",kind,_style(TEAL))
  result.set_stylebox("hover_pressed",kind,_style(TEAL))
  result.set_stylebox("disabled",kind,_style(Color("394454")))
  var focus:=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=YELLOW;focus.set_border_width_all(3);focus.set_expand_margin_all(3)
  result.set_stylebox("focus",kind,focus)
 return result

func _style(color:Color) -> StyleBoxFlat:
 var result:=StyleBoxFlat.new();result.bg_color=color;result.border_color=Color("7588a2");result.set_border_width_all(2)
 result.content_margin_left=18;result.content_margin_right=18;result.content_margin_top=10;result.content_margin_bottom=10
 result.anti_aliasing=false
 return result

func _build_preview() -> void:
 preview_stage=PixelStage.new();preview_stage.name="LiveTitlePixelStage";add_child(preview_stage)
 preview_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 preview_stage.set_density_mode(str(settings.pixel_density))
 preview_stage.display.mouse_filter=Control.MOUSE_FILTER_IGNORE
 if clerk_pose_bootstrap_script==null:
  _preview_error="店铺资源尚未准备完成。";return
 preview_world=WorldView.new();preview_world.name="LiveRestingShop"
 preview_world.catalog=PartsDB.catalog();preview_world.catalog.cargo=PartsDB.cargo_spec()
 preview_world.screen_mapper=preview_stage
 if not preview_world.configure_clerk_pose_bootstrap(clerk_pose_bootstrap_script):
  _preview_error="店铺暂时无法打开。";preview_world.free();preview_world=null;return
 preview_stage.viewport.add_child(preview_world)
 if not str(preview_world.get("_clerk_pose_setup_error")).is_empty():
  _preview_error="店铺暂时无法打开。";preview_stage.viewport.remove_child(preview_world);preview_world.free();preview_world=null;return
 preview_world.reduced_motion=bool(settings.reduced_motion)
 preview_world.update_shop_state({"phase":"night","contracts":[],"active_contract_id":""})
 preview_world.focus("hub",true);preview_world.set_shop_input(0.0,false)
 # Resting shop has no clerk on duty. Hiding presentation never moves the root.
 preview_world.clerk.hide()
 _preview_ready=true

func _load_presentation() -> void:
 # Paths are real raster/audio delivery contracts, never screenshot crops or
 # generated geometry. A missing asset stays a visible integration failure.
 for path in PROLOGUE_IMAGES:
  var picture:Texture2D=load(path) as Texture2D if ResourceLoader.exists(path) else null
  if picture==null:
   _presentation_error="序章图片尚未准备完成。";return
  _prologue_textures.append(picture)
 for path in PROLOGUE_MUSIC:
  var source:AudioStream=load(path) as AudioStream if ResourceLoader.exists(path) else null
  if source==null:
   _presentation_error="序章音乐尚未准备完成。";return
  var stream:AudioStream=source.duplicate() as AudioStream
  if stream is AudioStreamOggVorbis:stream.loop=true
  _prologue_streams.append(stream)

func _make_wordmark(path:String,node_name:String,position:Vector2,native_size:Vector2) -> void:
 var picture:Texture2D=load(path) as Texture2D if ResourceLoader.exists(path) else null
 if picture==null:
  _presentation_error="标题图片尚未准备完成。";return
 var mark:=TextureRect.new();mark.name=node_name;mark.texture=picture
 mark.position=position;mark.size=native_size*2.0
 mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 mark.mouse_filter=Control.MOUSE_FILTER_IGNORE;mark.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 title_stage.add_child(mark);_title_decor.append(mark)

func _build_title() -> void:
 _load_presentation()
 var background:=ColorRect.new();background.color=Color(0.02,0.03,0.08,.18);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 title_layer=CanvasLayer.new();title_layer.layer=100;add_child(title_layer)
 title_stage=Control.new();title_stage.name="TitleStage";title_stage.size=Vector2(1280,720);title_stage.theme=theme;title_layer.add_child(title_stage)
 _make_wordmark(TITLE_LOGO_PATH,"StarCourierPixelLogo",Vector2(64,56),Vector2(288,160))
 _make_wordmark(TITLE_CHINESE_PATH,"XingjiKuaidiPixelLogo",Vector2(88,382),Vector2(208,80))
 var footer:=Label.new();footer.name="TitleInputHint";footer.text="↑ / ↓ 或十字键选择    Enter / A 确认    Esc / B 返回";footer.position=Vector2(64,671);footer.add_theme_font_size_override("font_size",18);title_stage.add_child(footer);_title_decor.append(footer)
 var demo:=Label.new();demo.name="DemoMark";demo.text="DEMO";demo.position=Vector2(1148,674);demo.size=Vector2(68,24);demo.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;demo.add_theme_font_size_override("font_size",16);demo.add_theme_color_override("font_color",Color("a8b8cb"));title_stage.add_child(demo);_title_decor.append(demo)
 _build_prologue_surface()
 panel=PanelContainer.new();panel.name="TitlePanel";panel.position=Vector2(786,55);panel.size=Vector2(430,600);panel.add_theme_stylebox_override("panel",_style(PANEL));title_stage.add_child(panel)
 menu=VBoxContainer.new();menu.add_theme_constant_override("separation",14);panel.add_child(menu)

func _build_prologue_surface() -> void:
 _prologue_layer=Control.new();_prologue_layer.name="IllustratedPrologue";_prologue_layer.size=Vector2(1280,720);_prologue_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;title_stage.add_child(_prologue_layer)
 var backdrop:=ColorRect.new();backdrop.color=INK;backdrop.size=Vector2(1280,720);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;_prologue_layer.add_child(backdrop)
 _prologue_image=TextureRect.new();_prologue_image.name="PrologueIllustration";_prologue_image.size=Vector2(1280,720)
 _prologue_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_prologue_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_prologue_image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;_prologue_image.mouse_filter=Control.MOUSE_FILTER_IGNORE;_prologue_layer.add_child(_prologue_image)
 # A restrained readability band overlays actual art; it is not scene artwork.
 var band:=ColorRect.new();band.name="NarrationShade";band.color=Color(.025,.045,.08,.84);band.position=Vector2(0,566);band.size=Vector2(1280,154);band.mouse_filter=Control.MOUSE_FILTER_IGNORE;_prologue_layer.add_child(band)
 _prologue_counter=Label.new();_prologue_counter.name="PrologueCounter";_prologue_counter.position=Vector2(52,576);_prologue_counter.size=Vector2(1176,27);_prologue_counter.add_theme_font_size_override("font_size",18);_prologue_counter.add_theme_color_override("font_color",YELLOW);_prologue_layer.add_child(_prologue_counter)
 _prologue_story=Label.new();_prologue_story.name="PrologueNarration";_prologue_story.position=Vector2(52,608);_prologue_story.size=Vector2(1176,34);_prologue_story.add_theme_font_size_override("font_size",23);_prologue_story.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_prologue_layer.add_child(_prologue_story)
 _prologue_layer.hide()

func _set_title_presentation(mode:String) -> void:
 var illustrated:bool=mode=="prologue" or (mode=="settings" and _settings_return_screen=="prologue")
 for control in _title_decor:control.visible=not illustrated
 _prologue_layer.visible=illustrated
 _prologue_story.visible=mode=="prologue"
 _prologue_counter.visible=mode=="prologue"
 DisplayMetrics.set_rect_override(panel,Rect2(52,646,1176,54) if mode=="prologue" else Rect2(786,55,430,600))


func _layout() -> void:
 if not is_instance_valid(title_stage):return
 var available:Vector2=get_viewport_rect().size
 var density:float=DisplayMetrics.factor(available)
 var shown:Vector2=DisplayMetrics.point(Vector2(1280,720),density)
 title_stage.scale=Vector2.ONE
 title_stage.size=shown
 title_stage.position=((available-shown)*.5).floor()
 DisplayMetrics.apply_stage(title_stage,density)

func _clear_menu(mode:String) -> void:
 # New controls must be measured against authored fonts before the native
 # profile is reapplied; otherwise inherited 1080p minima can compound.
 DisplayMetrics.apply_theme(title_stage,1.0)
 screen=mode
 DisplayMetrics.set_style_override(panel,"panel",StyleBoxEmpty.new() if mode in ["menu","prologue"] else RasterSkin.panel_style())
 # Story controls form one quiet row below the narration. Every other title
 # screen keeps the existing vertical menu, controls and safe focus defaults.
 if (mode=="prologue") != (menu is HBoxContainer):
  panel.remove_child(menu);menu.queue_free()
  menu=HBoxContainer.new() if mode=="prologue" else VBoxContainer.new()
  panel.add_child(menu)
 else:
  for child in menu.get_children():
   menu.remove_child(child);child.queue_free()
 DisplayMetrics.set_constant_override(menu,"separation",12 if mode=="prologue" else (6 if mode=="settings" else 14))
 _set_title_presentation(mode)


func _label(text:String,font_size:int=20) -> Label:
 var result:=Label.new();result.text=text;result.add_theme_font_size_override("font_size",font_size);result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;menu.add_child(result);return result

func _button(text:String,callback:Callable,id:String="") -> Button:
 var result:=Button.new();result.text=text;result.name=id if not id.is_empty() else "MenuButton";result.custom_minimum_size.y=54;result.focus_mode=Control.FOCUS_ALL;result.pressed.connect(callback);menu.add_child(result)
 # Native button-down runs before a callback can rebuild the menu or begin
 # handoff. Keyboard, mouse and controller activation share this same owner.
 result.button_down.connect(_play_title_ui_sound.bind(false))
 RasterSkin.button(result,screen!="menu")
 if screen=="menu":
  result.alignment=HORIZONTAL_ALIGNMENT_LEFT
  result.add_theme_font_size_override("font_size",24)
 return result

# A deferred target may have been freed by another menu transition. Accept a
# Variant so the validity guard runs before Godot attempts a Control cast.
func _focus_control(target:Variant,expected_screen:String) -> void:
 if not is_instance_valid(target) or not target is Control or screen!=expected_screen or not target.is_inside_tree() or not target.is_visible_in_tree():return
 if target is BaseButton and target.disabled:return
 _title_navigation_pending=false # Screen-entry/focus recovery is quiet.
 target.grab_focus()

func _wire_focus() -> void:
 _layout.call_deferred()
 var controls:Array[Control]=[]
 for child in menu.get_children():
  if child is Control and child.focus_mode==Control.FOCUS_ALL and not (child is BaseButton and child.disabled):controls.append(child)
 for index in controls.size():
  var current:Control=controls[index]
  if not current.focus_entered.is_connected(_title_control_focused):current.focus_entered.connect(_title_control_focused)
  var previous:Control=controls[posmod(index-1,controls.size())]
  var next:Control=controls[(index+1)%controls.size()]
  current.focus_neighbor_top=current.get_path_to(previous);current.focus_neighbor_bottom=current.get_path_to(next)
  current.focus_previous=current.get_path_to(previous);current.focus_next=current.get_path_to(next)
  if menu is HBoxContainer:
   current.focus_neighbor_left=current.get_path_to(previous);current.focus_neighbor_right=current.get_path_to(next)

func _show_menu(message:String="") -> void:
 _dispose_restore_cancel()
 _kill_prologue_transition()
 _settings_return_screen="menu"
 if is_instance_valid(_opening_badge):
  _opening_badge.queue_free();_opening_badge=null
 for child in title_stage.get_children():
  if not child.is_queued_for_deletion():child.show()
 _clear_menu("menu")
 _label("休息中",30)
 var has_save:bool=save_guard.has_saved_progress()
 new_button=_button("新游戏",_request_new_game,"NewGame");new_button.disabled=not _preview_ready
 continue_button=_button("继续游戏",_continue_game,"Continue");continue_button.disabled=not has_save or not _preview_ready
 settings_button=_button("设置",_show_settings,"Settings")
 _button("退出",_quit_title,"Quit")
 status=_label(message if not message.is_empty() else (_preview_error if not _preview_error.is_empty() else _presentation_error),17)
 status.custom_minimum_size.y=80
 _wire_focus()
 _focus_return=(continue_button if has_save else new_button) if _preview_ready else settings_button
 _focus_control.call_deferred(_focus_return,screen)
 _play_menu_music()

func _set_setting(key:String,value:Variant) -> void:
 settings[key]=value;setting_overrides[key]=value
 if key=="controller_deadzone":_update_title_deadzone()
 if key=="volume":
  _apply_prologue_volume()
  if is_instance_valid(_title_ui_sound):
   if float(value)<=0.0:_title_ui_sound.stop()
   else:_title_ui_sound.volume_db=linear_to_db(clampf(float(value),0.0,1.0)*(.65 if _title_ui_sound.pitch_scale<1.0 else 1.0))
  if is_instance_valid(_title_test_sound):
   _title_test_sound.volume_db=linear_to_db(float(value)) if float(value)>0.0 else -80.0
   if float(value)<=0.0:_title_test_sound.stop()
 if key=="reduced_motion" and is_instance_valid(preview_world):preview_world.reduced_motion=bool(value)
 if key=="pixel_density" and is_instance_valid(preview_stage):preview_stage.set_density_mode(str(value))

func _show_settings() -> void:
 if busy:return
 _settings_return_screen="prologue" if screen=="prologue" else "menu"
 _kill_prologue_transition()
 _clear_menu("settings")
 _sync_prologue_audio_pause()
 _label("设置",30)
 var volume_label:=_label("音量  %d%%"%roundi(float(settings.volume)*100),18)
 var volume:=HSlider.new();volume.name="Volume";volume.min_value=0;volume.max_value=1;volume.step=.05;volume.value=float(settings.volume);volume.custom_minimum_size.y=28;menu.add_child(volume)
 volume.value_changed.connect(func(value:float):_set_setting("volume",value);volume_label.text="音量  %d%%"%roundi(value*100))
 var test_sound:=_button("试听音效",_test_title_sound,"TestSound");test_sound.custom_minimum_size.y=32
 var reduced:=_button("减少镜头动态："+("开" if settings.reduced_motion else "关"),func():_toggle_boolean("reduced_motion"),"ReducedMotion")
 reduced.custom_minimum_size.y=42
 var blur:=_button("飞行背景动态模糊："+("开" if settings.motion_blur else "关"),func():_toggle_boolean("motion_blur"),"MotionBlur")
 blur.custom_minimum_size.y=42
 var density_names:Dictionary={"auto":"自动清晰","balanced":"均衡","low":"低像素密度"}
 var density:=_button("像素密度："+str(density_names[settings.pixel_density]),_cycle_density,"PixelDensity");density.custom_minimum_size.y=42
 var deadzone_label:=_label("摇杆死区  %d%%"%roundi(float(settings.controller_deadzone)*100),18)
 var deadzone:=HSlider.new();deadzone.name="Deadzone";deadzone.min_value=.10;deadzone.max_value=.45;deadzone.step=.01;deadzone.value=float(settings.controller_deadzone);deadzone.custom_minimum_size.y=28;menu.add_child(deadzone)
 deadzone.value_changed.connect(func(value:float):_set_setting("controller_deadzone",value);deadzone_label.text="摇杆死区  %d%%"%roundi(value*100))
 var full:=_button("切换全屏  [F11]",_toggle_fullscreen,"Fullscreen");full.custom_minimum_size.y=42
 var back:=_button("返回",_return_from_settings,"SettingsBack");back.custom_minimum_size.y=44
 _wire_focus();_focus_control.call_deferred(back,screen)

func _toggle_boolean(key:String) -> void:
 _set_setting(key,not bool(settings[key]))
 var control:Button=menu.get_node("ReducedMotion" if key=="reduced_motion" else "MotionBlur")
 control.text=("减少镜头动态：" if key=="reduced_motion" else "飞行背景动态模糊：")+("开" if settings[key] else "关")

func _cycle_density() -> void:
 var values:Array[String]=["auto","balanced","low"]
 var names:Dictionary={"auto":"自动清晰","balanced":"均衡","low":"低像素密度"}
 _set_setting("pixel_density",values[(values.find(str(settings.pixel_density))+1)%values.size()])
 menu.get_node("PixelDensity").text="像素密度："+str(names[settings.pixel_density])

func _toggle_fullscreen() -> void:
 var fullscreen:bool=DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN
 _set_setting("fullscreen",fullscreen)
 if DisplayServer.get_name()!="headless":DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _return_from_settings() -> void:
 if _settings_return_screen=="prologue":
  _show_prologue(false);return
 _show_menu();_focus_control.call_deferred(settings_button,screen)

func _request_new_game() -> void:
 if busy or not _preview_ready:return
 _prologue_accepted=false
 if not save_guard.has_saved_progress():_begin_game(true);return
 _clear_menu("confirm_new")
 _label("重新开始？",30)
 _label("当前进度将被替换，从第一天开始。",21)
 _label("旧存档和备份会先保存到本地 new-game-recovery 文件夹。保存失败时保留原记录。",18)
 var cancel:=_button("取消，保留当前进度",_cancel_new_game,"CancelNewGame")
 _button("备份旧进度并开始新游戏",func():_begin_game(true),"ConfirmNewGame")
 _wire_focus();_focus_control.call_deferred(cancel,screen)

func _cancel_new_game() -> void:
 if busy:return
 _show_menu();_focus_control.call_deferred(new_button,screen)

func _continue_game() -> void:
 if busy or not _preview_ready:return
 if not save_guard.has_saved_progress():_show_menu("存档已移走。可以选择开始游戏。");return
 for filename in SaveGuard.SLOT_NAMES:
  if DirAccess.dir_exists_absolute(save_guard.save_root.path_join(filename)):_show_menu("存档路径无法读取，原记录未改变。请检查存档目录。");return
 _begin_game(false)

func _begin_game(new_game:bool) -> void:
 if busy or not _preview_ready:return
 if new_game and not _prologue_accepted:
  if _prologue_textures.size()!=PROLOGUE.size() or _prologue_streams.size()!=PROLOGUE.size():
   _show_menu(_presentation_error);return
  _prologue_index=0;_show_prologue();return
 busy=true
 _dispose_title_test_sound()
 for child in menu.get_children():
  if child is BaseButton:child.disabled=true
 if screen=="menu" and is_instance_valid(status):status.text="正在检查存档…"
 _stop_prologue_music(true,func():_launch_game.call_deferred(new_game))

func _launch_game(new_game:bool) -> void:
 if _closing:return
 # A focus-exit signal may precede this deferred callback and the not-yet-
 # constructed Main cannot have observed it. Keep this request pending until
 # focus returns; do not create recovery files, Main or an active entrance yet.
 if not _window_focused:
  _launch_waiting_for_focus=true;_pending_launch_new_game=new_game;return
 _launch_waiting_for_focus=false
 _dispose_title_ui_sound()
 # Load code before creating recovery files; a missing scene is a clean refusal.
 var packed:PackedScene=load(MAIN_SCENE) as PackedScene
 if packed==null:busy=false;_show_menu("游戏场景暂时无法打开，原存档未改变。");return
 var ticket:Dictionary={}
 if new_game:
  ticket=save_guard.prepare_new_game()
  if not ticket.ok:busy=false;_show_menu(str(ticket.message));return
 var candidate=packed.instantiate()
 candidate.process_mode=Node.PROCESS_MODE_DISABLED
 candidate.entry_defer_controls=true
 candidate.clerk_pose_bootstrap_script=clerk_pose_bootstrap_script
 candidate.entry_new_game=new_game
 candidate.entry_require_existing_save=not new_game
 candidate.entry_settings_overrides=settings.duplicate(true) if new_game else setting_overrides.duplicate(true)
 if new_game:candidate.economy.new_game_commit_guard=save_guard.commit_new_game.bind(ticket)
 # The new game's _ready must pass normal validation + initial durable commit
 # before it builds a world or advances a story. The title stays until then.
 add_child(candidate)
 if candidate.economy.review_load_blocked:
  var message:String=save_guard.last_error if new_game and not save_guard.last_error.is_empty() else str(candidate.economy.load_notice)
  remove_child(candidate);candidate.queue_free();busy=false;_show_menu(message);return
 game=candidate
 game.prepare_title_restore()
 if game.pilot_resume_blocked and not game.title_restore_pending():
  game=null;remove_child(candidate);candidate.queue_free();busy=false
  _show_menu("配送记录暂时无法继续。原存档已保留。");return
 settings.merge(game.settings,true)
 if is_instance_valid(preview_stage):preview_stage.hide();preview_stage.process_mode=Node.PROCESS_MODE_DISABLED
 _start_opening()

func _show_prologue(transition:bool=true) -> void:
 _clear_menu("prologue")
 _set_prologue_beat(transition)
 var next:=_button("开始营业" if _prologue_index==PROLOGUE.size()-1 else "继续",_advance_prologue,"PrologueNext")
 _button("跳过故事",_finish_prologue,"PrologueSkip")
 _button("返回标题",_cancel_prologue,"PrologueBack")
 _button("设置",_show_settings,"PrologueSettings")
 for child in menu.get_children():
  if child is Button:child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _play_prologue_music(_prologue_index)
 _wire_focus();_focus_control.call_deferred(next,screen)
 _layout.call_deferred()

func _kill_prologue_transition() -> void:
 if _prologue_transition!=null and _prologue_transition.is_valid():_prologue_transition.kill()
 _prologue_transition=null

func _commit_prologue_beat() -> void:
 _prologue_image.texture=_prologue_textures[_prologue_index]
 _prologue_story.text=PROLOGUE[_prologue_index]
 _prologue_counter.text="序章  %d / %d"%[_prologue_index+1,PROLOGUE.size()]

func _set_prologue_beat(transition:bool) -> void:
 _kill_prologue_transition()
 if not transition or bool(settings.reduced_motion):
  _commit_prologue_beat();_prologue_image.modulate.a=1.0;return
 _prologue_transition=create_tween()
 if _prologue_image.texture!=null:
  _prologue_transition.tween_property(_prologue_image,"modulate:a",0.0,.16)
 else:_prologue_image.modulate.a=0.0
 _prologue_transition.tween_callback(_commit_prologue_beat)
 _prologue_transition.tween_property(_prologue_image,"modulate:a",1.0,.28)
 if not _window_focused:_prologue_transition.pause()

func _apply_prologue_volume() -> void:
 if is_instance_valid(_prologue_music):
  var track_gain:float=.85 if _music_index==MENU_MUSIC_INDEX else .708
  var amount:float=clampf(float(settings.volume),0.0,1.0)*_music_gain*track_gain
  _prologue_music.volume_db=linear_to_db(amount) if amount>0.0001 else -80.0
  _sync_prologue_audio_pause()

func _set_music_gain(value:float) -> void:
 _music_gain=value;_apply_prologue_volume()

func _kill_music_tween() -> void:
 if _music_tween!=null and _music_tween.is_valid():_music_tween.kill()
 _music_tween=null

func _sync_prologue_audio_pause() -> void:
 if is_instance_valid(_prologue_music):
  var menu_screen:bool=screen in ["menu","confirm_new"] or (screen=="settings" and _settings_return_screen=="menu")
  var owns_screen:bool=menu_screen if _music_index==MENU_MUSIC_INDEX else screen=="prologue"
  _prologue_music.stream_paused=not _window_focused or not owns_screen or float(settings.volume)<=0.0

func _play_menu_music() -> void:
 _play_title_music(MENU_MUSIC,MENU_MUSIC_INDEX)

func _play_prologue_music(index:int) -> void:
 if index<0 or index>=_prologue_streams.size():return
 _play_title_music(_prologue_streams[index],index)

func _play_title_music(track:AudioStream,index:int) -> void:
 _music_generation+=1
 var generation:int=_music_generation
 _kill_music_tween()
 if not is_instance_valid(_prologue_music):
  _prologue_music=AudioStreamPlayer.new();_prologue_music.name="TitleMusic";_prologue_music.process_mode=Node.PROCESS_MODE_ALWAYS;add_child(_prologue_music)
 if _music_index==index and _prologue_music.stream==track:
  _sync_prologue_audio_pause()
  _music_tween=create_tween();_music_tween.tween_method(_set_music_gain,_music_gain,1.0,.25)
  return
 # Menu and prologue use ONE player; switch only at silence, never crossfade
 # two tracks. Begin Game disposes this owner before Main or its bell starts.
 _music_tween=create_tween()
 if _music_index!=-1 and _music_gain>0.0 and not _prologue_music.stream_paused:
  _music_tween.tween_method(_set_music_gain,_music_gain,0.0,.18)
 _music_tween.tween_callback(func():
  if generation!=_music_generation or not is_instance_valid(_prologue_music):return
  _prologue_music.stop();_prologue_music.stream=track;_music_index=index
  if _prologue_music.stream is AudioStreamOggVorbis:_prologue_music.stream.loop=true
  _set_music_gain(0.0);_prologue_music.play();_sync_prologue_audio_pause())
 _music_tween.tween_method(_set_music_gain,0.0,1.0,.25)

func _title_control_focused() -> void:
 if not _title_navigation_pending:return
 _title_navigation_pending=false
 _play_title_ui_sound(true)

func _play_title_ui_sound(navigation:bool=false) -> void:
 # One preloaded short cue, one reusable title-owned player. Do not create
 # players for mute/focus loss, replay stale input, or overlap test sounds.
 var volume:float=clampf(float(settings.volume),0.0,1.0)
 if volume<=0.0 or not _window_focused or busy or _closing or screen=="game":return
 _dispose_title_test_sound()
 if not is_instance_valid(_title_ui_sound):
  _title_ui_sound=AudioStreamPlayer.new();_title_ui_sound.name="TitleUISound";_title_ui_sound.process_mode=Node.PROCESS_MODE_ALWAYS;add_child(_title_ui_sound)
 _title_ui_sound.stop()
 _title_ui_sound.stream=TITLE_UI_SOUND
 _title_ui_sound.pitch_scale=.88 if navigation else 1.0
 _title_ui_sound.volume_db=linear_to_db(volume*(.65 if navigation else 1.0))
 _title_ui_sound.play()

func _dispose_title_ui_sound() -> void:
 _title_navigation_pending=false
 if not is_instance_valid(_title_ui_sound):return
 var previous:AudioStreamPlayer=_title_ui_sound;_title_ui_sound=null
 previous.stop();remove_child(previous);previous.queue_free()

func _test_title_sound() -> void:
 _dispose_title_ui_sound()
 var volume:float=clampf(float(settings.volume),0.0,1.0)
 if volume<=0.0:
  _audio_test_status="当前音量为 0，请调高后试听。"
 else:
  if not is_instance_valid(_title_test_sound):
   _title_test_sound=AudioStreamPlayer.new();_title_test_sound.name="TitleSoundTest";_title_test_sound.process_mode=Node.PROCESS_MODE_ALWAYS;add_child(_title_test_sound)
  _title_test_sound.stream=TEST_SOUND;_title_test_sound.volume_db=linear_to_db(volume);_title_test_sound.play()
  _audio_test_status="当前没有实际声音输出（Dummy 驱动）。" if AudioServer.get_driver_name()=="Dummy" else "已触发试听，音量 %d%%。输出：%s。若听不到，请检查系统音量与输出设备。"%[roundi(volume*100),AudioServer.get_output_device()]
 if is_instance_valid(menu) and menu.has_node("TestSound"):
  var button:Button=menu.get_node("TestSound")
  button.text="音量为 0 · 调高后试听" if volume<=0.0 else "无实际输出 · Dummy" if AudioServer.get_driver_name()=="Dummy" else "再次试听 · %d%%"%roundi(volume*100)
  button.tooltip_text=_audio_test_status

func _dispose_title_test_sound() -> void:
 if not is_instance_valid(_title_test_sound):return
 var previous:AudioStreamPlayer=_title_test_sound;_title_test_sound=null
 previous.stop();remove_child(previous);previous.queue_free()

func _dispose_prologue_music(generation:int,after:Callable) -> void:
 if generation!=_music_generation:return
 if is_instance_valid(_prologue_music):
  var previous:AudioStreamPlayer=_prologue_music;_prologue_music=null
  previous.stop();remove_child(previous);previous.queue_free()
 _music_index=-1;_music_gain=0.0
 if after.is_valid():after.call()

func _stop_prologue_music(fade:bool=false,after:Callable=Callable()) -> void:
 _music_generation+=1
 var generation:int=_music_generation
 _kill_music_tween()
 # Paused/inaudible/headless audio needs no perceptual tail. This also keeps
 # deterministic lifecycle fixtures independent of the audio clock.
 if not is_instance_valid(_prologue_music) or not fade or _prologue_music.stream_paused or _music_gain<=0.0 or float(settings.volume)<=0.0 or DisplayServer.get_name()=="headless":
  _dispose_prologue_music(generation,after);return
 _music_tween=create_tween()
 _music_tween.tween_method(_set_music_gain,_music_gain,0.0,.45)
 _music_tween.tween_callback(_dispose_prologue_music.bind(generation,after))


func _advance_prologue() -> void:
 if screen!="prologue" or busy:return
 if _prologue_index==PROLOGUE.size()-1:_finish_prologue();return
 _prologue_index+=1;_show_prologue()

func _finish_prologue() -> void:
 if screen!="prologue" or busy:return
 _prologue_accepted=true;_begin_game(true)

func _cancel_prologue() -> void:
 if screen!="prologue" or busy:return
 _prologue_accepted=false;_show_menu();_focus_control.call_deferred(new_button,screen)

func _start_opening() -> void:
 _dispose_restore_cancel()
 _kill_prologue_transition()
 _stop_prologue_music(false)
 _clear_menu("opening")
 panel.hide()
 for child in title_stage.get_children():child.hide()
 _opening_badge=Label.new();_opening_badge.text="营业中";_opening_badge.position=Vector2(930,92)
 _opening_badge.add_theme_font_size_override("font_size",32);_opening_badge.add_theme_color_override("font_color",YELLOW)
 _opening_badge.add_theme_color_override("font_shadow_color",INK);_opening_badge.add_theme_constant_override("shadow_offset_x",3);_opening_badge.add_theme_constant_override("shadow_offset_y",3);title_stage.add_child(_opening_badge)
 _layout.call_deferred()
 _opening_age=0.0;_opening_done=false;_opening_failed=false
 # In-flight/result/accepted/story states never run a shop entrance or empty
 # shop snapshot. Their original dispatch/dialogue restoration stays deferred.
 if not bool(game.entry_shop_walk):
  _opening_badge.text="继续配送" if not game.economy.in_flight.is_empty() else ("休息中" if game.economy.phase=="night" else "营业中")
  _opening_done=true
  if game.has_method("title_restore_pending") and game.title_restore_pending():
   busy=false
   var cancel:=Button.new();_restore_cancel=cancel;cancel.name="CancelFlightRestore";cancel.text="返回标题"
   cancel.position=Vector2(1010,626);cancel.size=Vector2(220,52);title_stage.add_child(cancel)
   RasterSkin.button(cancel)
   cancel.button_down.connect(_play_title_ui_sound.bind(false))
   cancel.pressed.connect(func():
    if is_instance_valid(game) and game.title_restore_pending():
     game.cancel_title_restore();_opening_failed=true;_abort_opening_to_title())
   _layout.call_deferred()
  return
 _opening_world=game.world
 for key in ["workshop_root","actors_root","foreground_root","ship_root"]:
  var layer:CanvasItem=_opening_world.get(key)
  _opening_colors[key]=layer.modulate;layer.modulate=Color("677394")
 _opening_world.process_mode=Node.PROCESS_MODE_ALWAYS
 _opening_world.title_shop_entry_finished.connect(_entry_walk_finished)
 if not _opening_world.start_title_shop_entry():
  _entry_walk_finished(false,"店员暂时无法到达柜台。");return
 _bell=AudioStreamPlayer.new();_bell.stream=Bell.make_stream();_bell.volume_db=linear_to_db(maxf(.001,float(settings.volume)))-12;add_child(_bell)
 if DisplayServer.get_name()!="headless" and float(settings.volume)>0.0:
  _bell.finished.connect(_dispose_bell);_bell.play()
 else:_dispose_bell()

func _dispose_bell() -> void:
 if not is_instance_valid(_bell):_bell=null;return
 var finished_player:AudioStreamPlayer=_bell;_bell=null
 finished_player.stop();finished_player.queue_free()

func _entry_walk_finished(success:bool,reason:String) -> void:
 if screen!="opening" or _opening_done:return
 _opening_done=true;_opening_failed=not success
 if _opening_failed:
  _opening_badge.text="店铺暂时无法打开"
  _show_opening_error()

func _show_opening_error() -> void:
 busy=false
 panel.show()
 _label("店铺暂时无法打开",26)
 _label("存档已保留。请返回标题后重试。",19)
 var back:=_button("返回标题",_abort_opening_to_title,"OpeningBack")
 _wire_focus();_focus_control.call_deferred(back,screen)

func _dispose_restore_cancel() -> void:
 if not is_instance_valid(_restore_cancel):_restore_cancel=null;return
 var old:Button=_restore_cancel;_restore_cancel=null
 old.hide();old.disabled=true
 if old.get_parent()!=null:old.get_parent().remove_child(old)
 old.queue_free()

func _retire_title_candidate(previous:Node) -> void:
 # The replay and HUD may be suspended on the next process_frame. Invalidate
 # publication first, then let those existing continuations return before free.
 # This is a signal barrier, not an elapsed-time substitute for completion.
 _retiring_restore=true
 _dispose_restore_cancel()
 if is_instance_valid(_opening_world):
  _opening_world.process_mode=Node.PROCESS_MODE_DISABLED
  if _opening_world.title_shop_entry_finished.is_connected(_entry_walk_finished):_opening_world.title_shop_entry_finished.disconnect(_entry_walk_finished)
 _opening_world=null;_opening_colors.clear();_dispose_bell()
 previous.process_mode=Node.PROCESS_MODE_DISABLED
 if previous.has_method("cancel_title_restore"):previous.cancel_title_restore()
 await get_tree().process_frame
 if is_instance_valid(previous):previous.free()
 _retiring_restore=false

func _abort_opening_to_title() -> void:
 if screen!="opening" or not _opening_failed or _retiring_restore:return
 busy=true
 if is_instance_valid(_opening_world):_opening_world.process_mode=Node.PROCESS_MODE_DISABLED
 _opening_world=null;_opening_colors.clear();_dispose_bell()
 if is_instance_valid(game):
  var previous=game;game=null
  await _retire_title_candidate(previous)
 if _closing:get_tree().quit();return
 preview_stage.process_mode=Node.PROCESS_MODE_INHERIT;preview_stage.show()
 busy=false;_show_menu("存档已保留。")

func _process(delta:float) -> void:
 if screen!="opening" or not is_instance_valid(game) or game.closing or not _window_focused:return
 if game.has_method("title_restore_pending") and game.title_restore_pending():
  _opening_badge.text="恢复配送 %d%%"%roundi(game.title_restore_progress()*100.0)
  return
 if game.has_method("title_restore_failure") and not str(game.title_restore_failure()).is_empty() and not _opening_failed:
  _opening_failed=true;_opening_done=true;_show_opening_error();return
 _opening_age+=maxf(0.0,delta)
 if is_instance_valid(_opening_world):
  var amount:float=1.0 if settings.reduced_motion else clampf(_opening_age/.75,0.0,1.0)
  for key in _opening_colors:
   var layer:CanvasItem=_opening_world.get(key);layer.modulate=Color("677394").lerp(_opening_colors[key],amount)
 # Actual root completion, minimum readable status time, focus, and released
 # input are all required. No elapsed-time shortcut can invent arrival.
 if _opening_done and not _opening_failed and _opening_age>=.7 and not Input.is_anything_pressed():_release_game()

func _release_game() -> void:
 if screen!="opening" or not _opening_done or _opening_failed:return
 _dispose_restore_cancel()
 _stop_prologue_music(false)
 _dispose_title_ui_sound()
 screen="game"
 _restore_title_actions()
 game.finish_title_entry()
 # UPDATE_ALWAYS is a rendering policy, independent of PROCESS_MODE_DISABLED.
 # A successful handoff has no route back to this preview, so dispose it. A
 # failed opening retains it until the explicit Return Title action instead.
 if is_instance_valid(preview_stage):
  preview_stage.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
  preview_stage.queue_free()
 preview_stage=null;preview_world=null
 _dispose_bell()
 get_window().focus_exited.disconnect(_focus_exited)
 get_window().focus_entered.disconnect(_focus_entered)
 title_stage.hide();set_process(false);set_process_input(false);set_process_unhandled_input(false)
 get_window().title="星际快递"

func _input(event:InputEvent) -> void:
 if screen=="game":return
 _title_navigation_pending=false
 if event is InputEventJoypadButton and event.is_action("ui_accept"):
  var token:=Vector2i(event.device,event.button_index)
  if event.pressed:_title_held_accept_buttons[token]=true
  else:_title_held_accept_buttons.erase(token)
 if not _window_focused or busy:
  get_viewport().set_input_as_handled();return
 for action in TITLE_UI_DIRECTIONS+["ui_focus_next","ui_focus_prev"]:
  if event.is_action_pressed(action,true):_title_navigation_pending=true;break
 if _accept_quarantined and event.is_action("ui_accept"):
  if event.is_action_released("ui_accept"):_accept_quarantined=_title_accept_is_held()
  get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent) -> void:
 if busy or is_instance_valid(game):return
 if event.is_action_pressed("ui_cancel"):
  if screen=="settings":_return_from_settings()
  elif screen=="confirm_new":_cancel_new_game()
  elif screen=="prologue":_cancel_prologue()
  get_viewport().set_input_as_handled()
 elif event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode==KEY_F11 or event.keycode==KEY_F11):
  _toggle_fullscreen();get_viewport().set_input_as_handled()

func _focus_exited() -> void:
 _dispose_title_test_sound()
 _dispose_title_ui_sound()
 _title_held_accept_buttons.clear()
 _window_focused=false
 _sync_prologue_audio_pause()
 if _prologue_transition!=null and _prologue_transition.is_valid():_prologue_transition.pause()
 if is_instance_valid(preview_world):preview_world.set_focus_active(false)
 var owner:Control=get_viewport().gui_get_focus_owner()
 if is_instance_valid(owner):owner.release_focus()

func _focus_entered() -> void:
 _window_focused=true
 _sync_prologue_audio_pause()
 if _prologue_transition!=null and _prologue_transition.is_valid() and screen=="prologue":_prologue_transition.play()
 if is_instance_valid(preview_world):preview_world.set_focus_active(true)
 if _launch_waiting_for_focus:
  _launch_waiting_for_focus=false
  _launch_game.call_deferred(_pending_launch_new_game)
  return
 _accept_quarantined=Input.is_action_pressed("ui_accept")
 if screen=="opening":
  if _opening_failed:_focus_control.call_deferred(menu.get_node("OpeningBack"),screen)
  return
 if screen=="prologue":_focus_control.call_deferred(menu.get_node("PrologueBack"),screen)
 elif screen=="confirm_new":_focus_control.call_deferred(menu.get_node("CancelNewGame"),screen)
 elif screen=="settings":_focus_control.call_deferred(menu.get_node("SettingsBack"),screen)
 elif is_instance_valid(_focus_return):_focus_control.call_deferred(_focus_return,screen)

func _notification(what:int) -> void:
 if what==NOTIFICATION_WM_CLOSE_REQUEST:_quit_title()

func _quit_title() -> void:
 if _closing:return
 if is_instance_valid(game) and not game.entry_defer_controls:game._request_save_and_quit();return
 _closing=true;_launch_waiting_for_focus=false
 _dispose_title_test_sound()
 _dispose_title_ui_sound()
 _stop_prologue_music(false)
 _dispose_bell()
 if _retiring_restore:return # The owner of retirement completes the quit.
 if is_instance_valid(game):
  var previous=game;game=null
  await _retire_title_candidate(previous)
 get_tree().quit()
