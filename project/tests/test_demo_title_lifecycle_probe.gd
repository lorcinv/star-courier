extends SceneTree
## Real title + approved live World in a NEW fictional profile. Script events
## are not physical keyboard/gamepad acceptance. No native launcher is invoked.
const Title=preload("res://scripts/demo_title.gd")
const FACTORY:String="res://scripts/clerk_runtime_bootstrap_observed_v4.gd"
var passed:int=0
var failed:int=0
var title
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
func focus_probe(tag:String,event:InputEventJoypadButton) -> void:
 var owner:Control=root.gui_get_focus_owner()
 print("TITLE_JOY_PROBE ",JSON.stringify({"tag":tag,"screen":title.screen,"busy":title.busy,"owner":str(owner.get_path()) if is_instance_valid(owner) else "none","owner_visible":owner.is_visible_in_tree() if is_instance_valid(owner) else false,"title_focus":title._window_focused,"window_focus":root.has_focus(),"quarantined":title._accept_quarantined,"input_enabled":title.is_processing_input(),"unhandled_enabled":title.is_processing_unhandled_input(),"gui_disabled":root.gui_disable_input,"event_accept":event.is_action("ui_accept"),"event_cancel":event.is_action("ui_cancel"),"event_button":event.button_index,"event_device":event.device,"event_pressed":event.pressed,"accept_state":Input.is_action_pressed("ui_accept"),"cancel_state":Input.is_action_pressed("ui_cancel"),"joy_connected":Input.get_connected_joypads()}))
 print("TITLE_INPUT_MAP accept=",InputMap.action_get_events("ui_accept")," cancel=",InputMap.action_get_events("ui_cancel"))
func tap_joy(button_index:int) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=button_index;event.pressed=true;focus_probe("before_press",event);Input.parse_input_event(event);await settle(1);focus_probe("after_press",event)
 event=InputEventJoypadButton.new();event.device=0;event.button_index=button_index;event.pressed=false;Input.parse_input_event(event);await settle(2);focus_probe("after_release",event)
func wait_entry() -> bool:
 var deadline:int=Time.get_ticks_msec()+12000
 while title.screen not in ["game","menu"] and not title._opening_failed and Time.get_ticks_msec()<deadline:await process_frame
 return title.screen=="game" and is_instance_valid(title.game)
func run() -> void:
 if OS.get_environment("STAR_COURIER_TITLE_TEST")!="1" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):
  printerr("Requires STAR_COURIER_TITLE_TEST=1 and a NEW /tmp XDG_DATA_HOME");quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refuse non-empty profile. Supply a NEW fictional profile.");quit(2);return
 if not ResourceLoader.exists(FACTORY):printerr("Approved factory dependency missing");quit(2);return
 await open_title(false)
 check(not title._preview_ready and title.new_button.disabled and title.continue_button.disabled and title.game==null,"unconfigured factory fails closed without a fallback actor or Main")
 check(bytes()==[null,null],"missing factory writes no save")
 await close_title();await open_title()
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
