extends SceneTree
## Real title + approved live World in a NEW fictional profile. Script events
## are not physical keyboard/gamepad acceptance. No native launcher is invoked.
const Title=preload("res://scripts/demo_title.gd")
const FACTORY:String="res://scripts/clerk_runtime_bootstrap_observed_v4.gd"
var passed:int=0
var failed:int=0
var title
var initial_ui_map:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func finish() -> void:
 print("DEMO_TITLE_LIFECYCLE passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
func settle(count:int=3) -> void:
 for unused in count:await process_frame
func write(slot:String,text:String) -> void:
 var file:=FileAccess.open("user://"+slot,FileAccess.WRITE);file.store_string(text);file.flush();file.close()
func bytes() -> Array:
 var result:Array=[]
 for slot in ["savegame.json","savegame.backup.json"]:
  result.append(FileAccess.get_file_as_bytes("user://"+slot) if FileAccess.file_exists("user://"+slot) else null)
 return result
func open_title(configured:bool=true) -> void:
 title=Title.new()
 if configured:title.clerk_pose_bootstrap_script=load(FACTORY)
 root.add_child(title);await settle()
 # Headless has no hardware window focus. Explicitly exercise the same focus
 # callback in this script fixture rather than pretending hardware was used.
 if DisplayServer.get_name()=="headless":title._focus_entered();await settle()
func close_title() -> void:
 root.remove_child(title);title.free();await settle()
func tap_joy(button_index:int) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=button_index;event.pressed=true;Input.parse_input_event(event);await settle(1)
 event=InputEventJoypadButton.new();event.device=0;event.button_index=button_index;event.pressed=false;Input.parse_input_event(event);await settle(2)
func wait_entry() -> bool:
 var deadline:int=Time.get_ticks_msec()+12000
 while title.screen not in ["game","menu"] and not title._opening_failed and Time.get_ticks_msec()<deadline:await process_frame
 return title.screen=="game" and is_instance_valid(title.game)
func ui_map_snapshot() -> Dictionary:
 var snapshot:Dictionary={}
 for action in ["ui_accept","ui_cancel","ui_left","ui_right","ui_up","ui_down"]:
  var events:Array[String]=[]
  if InputMap.has_action(action):
   for event in InputMap.action_get_events(action):events.append(event.get_class()+":"+str(event.device)+":"+event.as_text())
   snapshot[action]={"events":events,"deadzone":InputMap.action_get_deadzone(action)}
  else:snapshot[action]=null
 return snapshot
func check_title_maps() -> void:
 var buttons:Dictionary={"ui_accept":JOY_BUTTON_A,"ui_cancel":JOY_BUTTON_B,"ui_left":JOY_BUTTON_DPAD_LEFT,"ui_right":JOY_BUTTON_DPAD_RIGHT,"ui_up":JOY_BUTTON_DPAD_UP,"ui_down":JOY_BUTTON_DPAD_DOWN}
 for action in buttons:
  var event:=InputEventJoypadButton.new();event.device=0;event.button_index=buttons[action];event.pressed=true
  check(event.is_action(action),"native title joypad event maps to "+action)
 for action in ["ui_left","ui_right","ui_up","ui_down"]:
  var event:=InputEventJoypadMotion.new();event.device=0
  event.axis=JOY_AXIS_LEFT_X if action in ["ui_left","ui_right"] else JOY_AXIS_LEFT_Y
  event.axis_value=-1.0 if action in ["ui_left","ui_up"] else 1.0
  check(event.is_action_pressed(action),"native left stick maps to "+action)
 var before:Dictionary=ui_map_snapshot();title._install_title_actions()
 check(ui_map_snapshot()==before,"repeated title map installation adds no duplicate events or deadzone drift")
 var old:float=float(title.settings.controller_deadzone);title._set_setting("controller_deadzone",.31)
 var deadzones_match:bool=true
 for action in ["ui_left","ui_right","ui_up","ui_down"]:deadzones_match=deadzones_match and is_equal_approx(InputMap.action_get_deadzone(action),.31)
 check(deadzones_match,"title stick deadzone follows existing settings control")
 title._set_setting("controller_deadzone",old)
func raw_joy(device:int,button:int,pressed:bool) -> void:
 var event:=InputEventJoypadButton.new();event.device=device;event.button_index=button;event.pressed=pressed
 Input.parse_input_event(event);await settle(2)
func raw_enter(pressed:bool) -> void:
 var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.physical_keycode=KEY_ENTER;event.pressed=pressed
 Input.parse_input_event(event);await settle(2)
func check_custom_maps() -> void:
 # Add an actual swapped profile before title installation. No fixture calls
 # the menu activation handlers in place of a real remapped input event.
 var swaps:Dictionary={}
 for action in ["ui_accept","ui_cancel"]:
  var event:=InputEventJoypadButton.new();event.device=-1;event.button_index=JOY_BUTTON_B if action=="ui_accept" else JOY_BUTTON_A
  swaps[action]=event;InputMap.action_add_event(action,event)
 for action in ["ui_left","ui_right"]:
  var event:=InputEventJoypadMotion.new();event.device=-1;event.axis=JOY_AXIS_LEFT_X;event.axis_value=1.0 if action=="ui_left" else -1.0
  swaps[action]=event;InputMap.action_add_event(action,event);InputMap.action_set_deadzone(action,.37)
 var custom:Dictionary=ui_map_snapshot();await open_title()
 var a:=InputEventJoypadButton.new();a.device=0;a.button_index=JOY_BUTTON_A;a.pressed=true
 var b:=InputEventJoypadButton.new();b.device=0;b.button_index=JOY_BUTTON_B;b.pressed=true
 check(a.is_action("ui_cancel") and not a.is_action("ui_accept") and b.is_action("ui_accept") and not b.is_action("ui_cancel"),"existing swapped A/B bindings remain unambiguous")
 var right:=InputEventJoypadMotion.new();right.device=0;right.axis=JOY_AXIS_LEFT_X;right.axis_value=1
 var left:=InputEventJoypadMotion.new();left.device=0;left.axis=JOY_AXIS_LEFT_X;left.axis_value=-1
 print("TITLE_AXIS_PROBE map=",JSON.stringify(ui_map_snapshot()))
 print("TITLE_AXIS_PROBE positive=",right.as_text()," negative=",left.as_text()," exact_positive_left=",right.is_action("ui_left",true)," exact_positive_right=",right.is_action("ui_right",true)," exact_negative_left=",left.is_action("ui_left",true)," exact_negative_right=",left.is_action("ui_right",true))
 for action in ["ui_left","ui_right"]:
  for bound in InputMap.action_get_events(action):
   if bound is InputEventJoypadMotion:
    print("TITLE_AXIS_BOUND ",JSON.stringify({"action":action,"axis":bound.axis,"value":bound.axis_value,"device":bound.device,"positive_match":right.is_match(bound,true),"negative_match":left.is_match(bound,true),"positive_pressed":right.is_action_pressed(action,false,true),"negative_pressed":left.is_action_pressed(action,false,true)}))
 print("TITLE_AXIS_PROBE added=",title._title_added_events)
 check(right.is_action("ui_left",true) and not right.is_action("ui_right",true) and left.is_action("ui_right",true) and not left.is_action("ui_left",true),"existing reversed stick bindings remain unambiguous")
 title._show_settings();await settle();await tap_joy(JOY_BUTTON_B)
 check(title.screen=="menu" and title.game==null,"remapped B confirms the real focused Settings Back control once")
 title._show_settings();await settle();await tap_joy(JOY_BUTTON_A)
 check(title.screen=="menu" and root.gui_get_focus_owner()==title.settings_button,"remapped A executes native Back without confirming another control")
 await close_title();check(ui_map_snapshot()==custom,"title close restores the exact pre-existing custom mappings and deadzones")
 for action in swaps:InputMap.action_erase_event(action,swaps[action])
 for action in ["ui_left","ui_right"]:InputMap.action_set_deadzone(action,float(initial_ui_map[action].deadzone))
 check(ui_map_snapshot()==initial_ui_map,"custom-map fixture restores its baseline without touching keyboard bindings")
func check_disconnect_edges() -> void:
 var before:Dictionary=ui_map_snapshot()
 var observations:Array[int]=[0]
 var observer:Callable=func(_device:int,_connected:bool):observations[0]+=1
 Input.joy_connection_changed.connect(observer)
 title._focus_exited();await raw_joy(0,JOY_BUTTON_A,true);title._focus_entered();await settle()
 check(title._accept_quarantined,"focus-return held A enters title quarantine")
 var action_before:bool=Input.is_action_pressed("ui_accept")
 Input.joy_connection_changed.emit(0,false);await settle()
 check(not title._accept_quarantined and title._title_held_accept_buttons.is_empty(),"disconnect clears only that title-held confirmation quarantine")
 check(action_before and Input.is_action_pressed("ui_accept"),"disconnect does not globally release another owner's action state")
 check(observations[0]==1 and Input.joy_connection_changed.is_connected(observer),"title disconnect handling preserves other signal subscribers")
 await raw_joy(0,JOY_BUTTON_A,false)
 title._focus_exited();await raw_joy(0,JOY_BUTTON_A,true);await raw_joy(1,JOY_BUTTON_A,true);title._focus_entered();await settle()
 Input.joy_connection_changed.emit(0,false);await settle()
 check(title._accept_quarantined and title._title_held_accept_buttons.has(Vector2i(1,JOY_BUTTON_A)),"disconnecting one controller preserves the other controller's held quarantine")
 Input.joy_connection_changed.emit(1,true);await settle()
 check(title._accept_quarantined,"another controller reconnect does not clear held confirmation quarantine")
 await raw_joy(1,JOY_BUTTON_A,false)
 check(not title._accept_quarantined,"other controller's genuine release clears its own quarantine")
 await raw_joy(0,JOY_BUTTON_A,false)
 title._focus_exited();await raw_enter(true);await raw_joy(0,JOY_BUTTON_A,true);title._focus_entered();await settle()
 Input.joy_connection_changed.emit(0,false);await settle()
 check(title._accept_quarantined and Input.is_physical_key_pressed(KEY_ENTER),"controller disconnect preserves a simultaneously held keyboard confirm")
 await raw_enter(false);await raw_joy(0,JOY_BUTTON_A,false)
 Input.joy_connection_changed.disconnect(observer)
 check(ui_map_snapshot()==before and title.game==null,"connection edges leave mappings and game lifecycle unchanged")
func run() -> void:
 if OS.get_environment("STAR_COURIER_TITLE_TEST")!="1" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):
  printerr("Requires STAR_COURIER_TITLE_TEST=1 and a NEW /tmp XDG_DATA_HOME");quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refuse non-empty profile. Supply a NEW fictional profile.");quit(2);return
 if not ResourceLoader.exists(FACTORY):printerr("Approved factory dependency missing");quit(2);return
 initial_ui_map=ui_map_snapshot()
 await open_title(false)
 check(not title._preview_ready and title.new_button.disabled and title.continue_button.disabled and title.game==null,"unconfigured factory fails closed without a fallback actor or Main")
 check(bytes()==[null,null],"missing factory writes no save")
 await close_title()
 check(ui_map_snapshot()==initial_ui_map,"closing title restores original UI events and deadzones")
 await check_custom_maps()
 await open_title();check_title_maps();await check_disconnect_edges()
 check(title._preview_ready and is_instance_valid(title.preview_world),"configured title uses a live World")
 if not title._preview_ready:await close_title();finish();return
 check(title.game==null and bytes()==[null,null],"live resting title constructs no Main and writes no save")
 check(title.preview_world.night and title.preview_world.active_id.is_empty() and not title.preview_world.clerk.visible,"resting preview has no active order or on-duty clerk")
 check(title.continue_button.disabled and root.gui_get_focus_owner()==title.new_button,"fresh profile disables Continue and focuses New Game")
 title._show_settings();await settle();title._set_setting("volume",.25);title._set_setting("reduced_motion",true);title._return_from_settings();await settle()
 check(bytes()==[null,null] and title.game==null,"title settings are memory-only")
 title._request_new_game();await settle()
 check(title.screen=="prologue" and title.game==null and bytes()==[null,null],"first prologue precedes Main construction and any reset")
 title._advance_prologue();title._cancel_prologue();await settle()
 check(title.screen=="menu" and bytes()==[null,null],"cancel prologue preserves a fresh profile")
 title._request_new_game();await settle();title._finish_prologue();title._finish_prologue()
 title._focus_exited();await settle(5)
 check(title._launch_waiting_for_focus and title.game==null and bytes()==[null,null],"focus loss before deferred launch leaves Main/reset pending and records untouched")
 title._focus_entered();await settle(5)
 check(is_instance_valid(title.game) and title.screen=="opening" and title.game.entry_defer_controls,"skipping prologue creates one quarantined Main opening")
 if not is_instance_valid(title.game):await close_title();finish();return
 check(title.game.process_mode==Node.PROCESS_MODE_DISABLED and not title.game.hud.visible,"HUD and gameplay remain blocked during actual clerk entry")
 check(title.game.settings.volume==.25 and title.game.settings.reduced_motion,"title settings apply before first save")
 var entered:bool=await wait_entry();check(entered,"actual World entry finishes before title hands over control")
 if not entered:await close_title();finish();return
 check(not title.game.entry_defer_controls and title.game.economy.day==1,"normal control opens on first day")
 check(ui_map_snapshot()==initial_ui_map,"successful handoff removes temporary native UI maps before Main owns gameplay")
 check(not Input.joy_connection_changed.is_connected(title._title_joy_connection_changed),"successful handoff detaches the title connection callback from Main gameplay")
 await settle(2)
 check(title.preview_stage==null and title.preview_world==null and title.get_node_or_null("LiveTitlePixelStage")==null,"successful handoff disposes old World and UPDATE_ALWAYS viewport")
 check(title._bell==null,"completed opening leaves no bell player")
 var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(saved is Dictionary and saved.settings.volume==.25,"fresh save uses normal validated schema")
 await close_title()
 var valid_before:Array=bytes();await open_title()
 check(bytes()==valid_before and title.game==null,"valid existing title does not resave")
 title._continue_game();await settle(5)
 check(title.screen!="prologue","Continue never repeats new-game prologue")
 entered=await wait_entry();check(entered,"normal Continue finishes safe opening")
 if not entered:await close_title();finish();return
 check(title.game.economy.day==int(saved.day) and title.game.economy.credits==int(saved.credits),"Continue retains day and credits")
 await close_title()
 # Only this test's own fictional saves are replaced by corrupt fixtures.
 write("savegame.json","{broken fictional primary");write("savegame.backup.json","{different broken fictional backup")
 var originals:Array=bytes();await open_title()
 check(bytes()==originals and title.game==null and not title.continue_button.disabled,"corrupt title is non-mutating and Continue remains a validation route")
 title._request_new_game();await settle()
 check(title.screen=="confirm_new" and root.gui_get_focus_owner().name=="CancelNewGame","old progress defaults to safe Cancel focus")
 await tap_joy(JOY_BUTTON_A)
 check(title.screen=="menu" and bytes()==originals,"synthetic controller confirm activates safe Cancel, not reset")
 title._continue_game();await settle(5)
 check(title.game==null and title.screen=="menu" and bytes()==originals,"corrupt Continue refuses silent new game")
 check(not title.status.text.is_empty(),"recovery failure is visible")
 title._show_settings();await settle();await tap_joy(JOY_BUTTON_B)
 check(title.screen=="menu" and root.gui_get_focus_owner()==title.settings_button,"synthetic controller Back restores settings focus")
 title._request_new_game();await settle();title._focus_exited();title._focus_entered();await settle()
 check(root.gui_get_focus_owner().name=="CancelNewGame","focus return keeps safe confirmation default")
 title._cancel_new_game();await settle()
 write("new-game-recovery","fictional directory obstruction")
 title._prologue_accepted=true;title._begin_game(true);await settle(5)
 check(title.game==null and not title.busy and bytes()==originals,"failed old-save backup refuses transition and preserves both slots")
 check(not title.status.text.is_empty(),"backup failure is actionable")
 # Remove only this fixture obstruction, then fail the NORMAL Economy writer.
 DirAccess.remove_absolute("user://new-game-recovery")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 title._prologue_accepted=true;title._begin_game(true);await settle(5)
 check(title.game==null and not title.busy and bytes()==originals,"real temporary-save write failure preserves both old slots after recovery backup")
 check(not title.status.text.is_empty(),"failed fresh save refuses world/control transition visibly")
 DirAccess.remove_absolute("user://savegame.tmp")
 await close_title();finish()
