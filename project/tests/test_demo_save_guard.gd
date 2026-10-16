extends SceneTree
## Script-only fictional fixtures. Engine lead must run in a NEW /tmp XDG profile.
## No actual or earned save is read, modified, or used as test evidence.
const Guard=preload("res://scripts/demo_save_guard.gd")
var passed:int=0
var failed:int=0
var suite_root:String
var serial:int=0
class CopyFailure extends "res://scripts/demo_save_guard.gd":
 var fail_suffix:String="savegame.backup.json"
 func _write_verified(path:String,bytes:PackedByteArray) -> bool:
  if path.ends_with(fail_suffix):return false
  return super._write_verified(path,bytes)
class RenameFailure extends "res://scripts/demo_save_guard.gd":
 var sabotage:bool=false
 func _read_bytes(path:String) -> Dictionary:
  var result:Dictionary=super._read_bytes(path)
  if sabotage and path.ends_with("savegame.tmp") and result.get("exists",false):
   sabotage=false
   # Delete only the disposable fixture candidate AFTER its successful read.
   # The real rename then fails; both distinct original slot files remain.
   DirAccess.remove_absolute(path)
  return result
func _initialize() -> void:
 var profile:String=OS.get_environment("XDG_DATA_HOME")
 if OS.get_environment("STAR_COURIER_TITLE_TEST")!="1" or not profile.begins_with("/tmp/"):
  printerr("Requires STAR_COURIER_TITLE_TEST=1 and a new /tmp XDG_DATA_HOME");quit(2);return
 suite_root="user://title-fixtures-%d"%Time.get_ticks_usec()
 test_no_saves();test_both_slots();test_copy_failures();test_rename_failure();test_mutation_guards();test_slot_edges()
 print("DEMO_SAVE_GUARD passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func fixture(guard:Variant=null):
 serial+=1
 var path:String=suite_root.path_join(str(serial))
 DirAccess.make_dir_recursive_absolute(path)
 if guard==null:guard=Guard.new()
 guard.save_root=path;guard.recovery_root=path.path_join("new-game-recovery")
 return guard
func write(guard,slot:String,data:String) -> void:
 var file:=FileAccess.open(guard.save_root.path_join(slot),FileAccess.WRITE)
 file.store_string(data);file.flush();file.close()
func slots(guard) -> Array:
 var output:Array=[]
 for slot in Guard.SLOT_NAMES:
  var path:String=guard.save_root.path_join(slot)
  output.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return output
func seed_slots(guard) -> void:
 write(guard,"savegame.json","fictional primary - deliberately opaque")
 write(guard,"savegame.backup.json","different fictional backup - keep both")
func test_no_saves() -> void:
 var guard=fixture();check(not guard.has_saved_progress(),"fresh title existence probe is read-only")
 var ticket:Dictionary=guard.prepare_new_game()
 check(ticket.ok and ticket.recovery_dir.is_empty() and slots(guard)==[null,null],"empty profile prepares without save or archive")
 write(guard,"savegame.tmp","fictional validated new candidate")
 check(guard.commit_new_game(ticket).ok and FileAccess.get_file_as_string(guard.save_root.path_join("savegame.json"))=="fictional validated new candidate","fresh primary commits once")
 var after:Array=slots(guard);check(not guard.commit_new_game(ticket).ok and after==slots(guard),"used ticket refuses duplicate commit")
func test_both_slots() -> void:
 var guard=fixture();seed_slots(guard);var before:Array=slots(guard)
 var ticket:Dictionary=guard.prepare_new_game()
 check(ticket.ok and before==slots(guard),"prepare leaves both distinct original slots untouched")
 for index in Guard.SLOT_NAMES.size():check(FileAccess.get_file_as_bytes(str(ticket.recovery_dir).path_join(Guard.SLOT_NAMES[index]))==before[index],"exact durable recovery bytes "+Guard.SLOT_NAMES[index])
 check(FileAccess.file_exists(str(ticket.recovery_dir).path_join("manifest.json")),"recovery manifest was flushed and reread")
 write(guard,"savegame.tmp","fictional new day one")
 check(guard.commit_new_game(ticket).ok and slots(guard)[1]==before[1],"new primary leaves old rotating backup unchanged")
 for index in Guard.SLOT_NAMES.size():check(FileAccess.get_file_as_bytes(str(ticket.recovery_dir).path_join(Guard.SLOT_NAMES[index]))==before[index],"commit retains recovery bytes "+Guard.SLOT_NAMES[index])
func test_copy_failures() -> void:
 for suffix in ["savegame.json","savegame.backup.json","manifest.json"]:
  var guard=fixture(CopyFailure.new());guard.fail_suffix=suffix;seed_slots(guard);var before:Array=slots(guard)
  check(not guard.prepare_new_game().ok and before==slots(guard),"failed recovery write preserves both originals: "+suffix)
 var guard=fixture();seed_slots(guard);var before:Array=slots(guard)
 write(guard,"new-game-recovery","directory obstruction")
 check(not guard.prepare_new_game().ok and before==slots(guard),"real archive directory creation failure preserves slots")
func test_rename_failure() -> void:
 var guard=fixture(RenameFailure.new());seed_slots(guard);var before:Array=slots(guard)
 var ticket:Dictionary=guard.prepare_new_game();write(guard,"savegame.tmp","fictional validated candidate");guard.sabotage=true
 check(not guard.commit_new_game(ticket).ok and before==slots(guard),"real missing-source rename failure preserves both originals")
 check(not ticket.used,"failed commit ticket does not claim success")
func test_mutation_guards() -> void:
 var guard=fixture();seed_slots(guard);var ticket:Dictionary=guard.prepare_new_game()
 write(guard,"savegame.tmp","fictional new candidate");write(guard,"savegame.json","changed by another process")
 var before:Array=slots(guard)
 check(not guard.commit_new_game(ticket).ok and before==slots(guard),"changed original aborts rather than clobbers newer state")
 guard=fixture();seed_slots(guard);ticket=guard.prepare_new_game();before=slots(guard)
 var archive:=FileAccess.open(str(ticket.recovery_dir).path_join("savegame.backup.json"),FileAccess.WRITE);archive.store_string("damaged archive");archive.close()
 write(guard,"savegame.tmp","fictional new candidate")
 check(not guard.commit_new_game(ticket).ok and before==slots(guard),"damaged archived backup prevents reset")
func test_slot_edges() -> void:
 for name in Guard.SLOT_NAMES:
  var guard=fixture();write(guard,name,"");var ticket:Dictionary=guard.prepare_new_game()
  check(guard.has_saved_progress() and ticket.ok and FileAccess.file_exists(str(ticket.recovery_dir).path_join(name)),"empty/corrupt slot still requires confirmation and exact backup: "+name)
 var guard=fixture();DirAccess.make_dir_absolute(guard.save_root.path_join("savegame.json"))
 check(guard.has_saved_progress() and not guard.prepare_new_game().ok,"directory in save slot is blocked, never mistaken for fresh profile")
