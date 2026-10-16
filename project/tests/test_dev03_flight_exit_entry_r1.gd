extends SceneTree
## Actual HUD Button.pressed coverage; synthetic headless/native signals only.
const HUD=preload("res://scripts/game_hud.gd")
class FlightStub extends RefCounted:
 var status:String="running"
class Controller extends "res://scripts/main.gd":
 var saves:int=0
 var checkpoints:int=0
 var exits:int=0
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func save_game() -> bool:saves+=1;return economy.save_state([],[],settings)
 func _checkpoint_flight() -> void:checkpoints+=1
 func _finish_quit(_code:int) -> void:exits+=1
 func notify(_message:String) -> void:pass
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 await process_frame;await process_frame
func bytes() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func state_bytes(app) -> PackedByteArray:
 return var_to_bytes([app.economy.credits,app.economy.contracts,app.economy.settled_ids,app.economy.in_flight,app.economy.story_state])
func snapshot(app,protocol:String) -> Dictionary:
 return {"mode":"flight","control_version":protocol,"activeorder":{"control_version":protocol,"name":"配送测试","destination_name":"测试收件台","distance":100.0,"deadline":60},"save_exit_available":app._flight_save_exit_available(),"settings":{"reduced_motion":true},"flight":{"paused":app.paused,"save_exit_available":app._flight_save_exit_available(),"speed":10.0,"cargo_y":-8.0,"distance":20.0,"total_distance":100.0,"integrity":1.0,"energy_remaining":80.0,"energy_capacity":100.0,"energy_fraction":.8,"flight_status":"running","events":[],"destination_navigation":{"status":"running","charging":false,"cargo_screen":Vector2(600,360),"receiver_screen":Vector2(1400,360),"distance_m":100.0}}}
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):push_error("Use a fresh /tmp XDG profile");quit(2);return
 root.gui_embed_subwindows=true
 for protocol in ["pilot-free-v1","pilot-v1"]:
  var app=Controller.new();root.add_child(app);app.page="flight";app.flight_order={"control_version":protocol};app.sim=FlightStub.new()
  app.economy.ensure_contracts();check(app.economy.save_state([],[],app.settings),protocol+" seed primary");app.economy.credits+=1;check(app.economy.save_state([],[],app.settings),protocol+" seed distinct backup")
  var disk_before:Array=bytes();var state_before:PackedByteArray=state_bytes(app)
  app.hud=HUD.new();app.add_child(app.hud);app.hud.action_requested.connect(app._action)
  for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
   root.size=extent;app.hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));app.paused=false;app.hud.render(snapshot(app,protocol));await settle()
   var exit_button:Button=app.hud.content.get_node("FlightSaveAndExit")
   var continue_button:Button=app.hud._pause_button.get_ref()
   check(not exit_button.visible and exit_button.focus_mode==Control.FOCUS_NONE,protocol+" active flight hides exit from pointer/focus")
   exit_button.pressed.emit();check(not app.closing and app.saves==0,protocol+" hidden stale exit signal cannot open confirmation")
   continue_button.pressed.emit();await settle()
   check(app.paused and exit_button.visible and not exit_button.disabled,protocol+" actual Pause button exposes ordinary Save and Exit immediately")
   check(root.gui_get_focus_owner()==continue_button,protocol+" newly paused HUD keeps Continue as safe default focus")
   check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(exit_button.get_global_rect()) and not exit_button.get_global_rect().intersects(continue_button.get_global_rect()),protocol+" paused exit entry fits native viewport without covering Continue")
   exit_button.pressed.emit();await settle()
   check(app.closing and app._quit_prompt.visible and app.saves==0 and app.checkpoints==0,protocol+" actual HUD exit button enters existing confirmation without writing")
   app._quit_prompt.get_cancel_button().pressed.emit();await settle()
   check(not app.closing and app.paused and not app._paused_before_modal and app.saves==0 and app.checkpoints==0 and app.exits==0,protocol+" cancel preserves prior manual pause without save/checkpoint/exit")
   check(bytes()==disk_before and state_bytes(app)==state_before,protocol+" cancel preserves exact primary/backup and settlement state")
   continue_button.pressed.emit();await settle()
   check(not app.paused and not exit_button.visible,protocol+" Continue resumes and removes pause-only exit")
  app._set_paused(true)
  var exit_button:Button=app.hud.content.get_node("FlightSaveAndExit")
  for guard in ["pilot_resume_blocked","_free_restore_active","entry_defer_controls","closing"]:
   app.set(guard,true);app.hud.update_flight_exit_state(true,app._flight_save_exit_available());exit_button.pressed.emit()
   check(exit_button.disabled and exit_button.focus_mode==Control.FOCUS_NONE and app.saves==0 and not app._quit_prompt.visible,protocol+" unavailable guard rejects actual button signal: "+guard)
   app.set(guard,false)
  app.economy.review_load_blocked=true;app.hud.update_flight_exit_state(true,app._flight_save_exit_available());exit_button.pressed.emit()
  check(exit_button.disabled and app.saves==0 and app.exits==0,protocol+" recovery guard disables entry without invoking recovery exit")
  app.economy.review_load_blocked=false;app.hud.update_flight_exit_state(true,app._flight_save_exit_available())
  app.pilot_resume_blocked=true # Deliberately stale visible availability.
  exit_button.pressed.emit();check(not app.closing and app.saves==0 and app.exits==0,protocol+" Main rechecks unavailable guard behind stale HUD state")
  app.pilot_resume_blocked=false
  check(bytes()==disk_before and state_bytes(app)==state_before,protocol+" all rejected entries leave persistence and settlement unchanged")
  app.free();await settle()
 print("DEV03_FLIGHT_EXIT_ENTRY_R1 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
