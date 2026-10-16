extends SceneTree
const E=preload("res://scripts/economy.gd")
func _initialize():
 var path=OS.get_environment("SC_MOON");var raw=JSON.parse_string(FileAccess.get_file_as_string(path));var f=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_buffer(FileAccess.get_file_as_bytes(path));f.close()
 var e=E.new();e.load_state();e.enable_story_mode();assert(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok);assert(e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok);assert(e.contracts[0].distance==200);print("OLD45 NORMAL D5 QUOTE200 READY");quit()
