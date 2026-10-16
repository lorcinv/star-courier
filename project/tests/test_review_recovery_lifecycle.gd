extends SceneTree
## Headless Window signals/direct calls/synthetic keys, not native OS input.
const Main=preload("res://scripts/main.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run() -> void:
 for filename in ["savegame.json","savegame.backup.json"]:
  var file=FileAccess.open("user://"+filename,FileAccess.WRITE);file.store_string("{recovery-only-corruption");file.close()
 var app=Main.new();root.add_child(app);await process_frame
 check(app.economy.review_load_blocked and app.world==null and app.hud==null,"lifecycle fixture enters recovery-only startup with absent world/HUD")
 check(not app.is_processing_unhandled_key_input(),"recovery-only startup disables unhandled-key processing as well as ordinary input")
 var original_settings:Dictionary=app.settings.duplicate(true);var original_design:Array=app.design.duplicate(true)
 for i in 3:
  root.focus_exited.emit();root.focus_entered.emit()
  app._on_focus_exited();app._on_focus_entered()
 check(not app.closing and app.world==null and app.hud==null,"connected and direct focus callbacks are null-safe before UI creation")
 for action in ["next_day","buy","upgrade","workshop_upgrade","dispatch","trial","settings","focus_counter","focus_workbench","close_drawer"]:app._action(action,null)
 check(app.economy.credits==260 and app.economy.settled_ids.is_empty() and app.economy.inventory.is_empty(),"external actions cannot initialize or mutate a blocked shop")
 app.navigate("workshop");app.navigate("hub");app.render();app.start_flight(false);app.start_flight(true)
 check(app.world==null and app.hud==null and app.sim==null and app.page=="hub","external navigation/render/flight calls cannot dereference missing UI or launch")
 for code in [KEY_ESCAPE,KEY_F11,KEY_R,KEY_DELETE,KEY_ENTER]:
  var key:=InputEventKey.new();key.pressed=true;key.keycode=code
  app._unhandled_key_input(key);app._input(key)
  key.pressed=false;app._input(key)
 check(app.settings==original_settings and app.design==original_design,"direct synthetic keys cannot toggle display, edit, or navigate recovery mode")
 app._process(0.01)
 check(not app.save_game() and not FileAccess.file_exists("user://savegame.tmp"),"manual process/save entry remains null-safe and cannot create replacement data")
 check(FileAccess.get_file_as_string("user://savegame.json")=="{recovery-only-corruption" and FileAccess.get_file_as_string("user://savegame.backup.json")=="{recovery-only-corruption","focus/input/action paths preserve both corrupt source files")
 # Run the real connected close handler. No test override bypasses its save,
 # null guards, 0.25 s timer, or actual SceneTree.quit path.
 root.close_requested.emit();root.close_requested.emit()
 app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
 await process_frame
 check(app.closing,"connected window close enters real clean shutdown exactly once")
 root.focus_exited.emit();root.focus_entered.emit();app._action("next_day",null)
 await create_timer(0.05).timeout
 check(FileAccess.get_file_as_string("user://savegame.json")=="{recovery-only-corruption" and FileAccess.get_file_as_string("user://savegame.backup.json")=="{recovery-only-corruption","window close and late focus/actions preserve both files")
 check(not FileAccess.file_exists("user://savegame.tmp") and app.world==null and app.hud==null,"shutdown never creates new-shop UI or a temporary overwrite")
 print("REVIEW_RECOVERY_LIFECYCLE passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 if failed:quit(1)
 # Passing run exits only through Main._quit_cleanly. The shell adds a timeout
 # so a missing real shutdown is a test failure rather than a hidden hang.
