extends SceneTree
## Exact exported-entry wiring, fresh fictional profile, no native window/input.
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or OS.get_environment("STAR_COURIER_TITLE_TEST")!="1":quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):quit(2);return
 var entry:String=str(ProjectSettings.get_setting("application/run/main_scene"))
 check(entry=="res://scenes/demo_title.tscn","default application entry is the dedicated title scene")
 var title=load(entry).instantiate();root.add_child(title)
 for unused in 5:await process_frame
 check(title.clerk_pose_bootstrap_script!=null and title.clerk_pose_bootstrap_script.resource_path=="res://scripts/clerk_runtime_bootstrap_observed_v4.gd","shipped scene itself binds actual approved factory")
 check(title._preview_ready and is_instance_valid(title.preview_world),"default title constructs real resting World without test injection")
 check(title.preview_world._clerk_pose_consumer_enabled and title.preview_world._clerk_pose_setup_error.is_empty(),"default preview uses exact coupled actor without legacy fallback")
 check(not title.preview_world.clerk.visible and title.preview_world.night,"default preview starts resting with clerk off duty")
 check(title.game==null and not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"entering final default scene creates neither Main nor save")
 check(title.new_button.get_theme_stylebox("normal") is StyleBoxTexture,"title actual New Game uses generated raster paint")
 check(title.continue_button.disabled,"fresh default entry clearly disables Continue")
 root.remove_child(title);title.free()
 for unused in 3:await process_frame
 print("DEMO_DEFAULT_ENTRY_BINDING passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
