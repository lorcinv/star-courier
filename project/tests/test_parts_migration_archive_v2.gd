extends SceneTree
## Filesystem backup probe. Run with isolated --user-data-dir if supported.
## Uses only user://dev04-parts-archive-test, never the game's savegame slots.
## NOT RUN by author.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const ROOT:String="user://dev04-parts-archive-test"
var failures:int=0
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func write(path:String,text:String) -> bool:
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file==null:return false
 var ok:bool=file.store_string(text);file.flush();file.close();return ok
func _initialize() -> void:
 var unique:String=ROOT.path_join(str(Time.get_ticks_usec()))
 check(DirAccess.make_dir_recursive_absolute(unique)==OK,"test-only directory created")
 var primary:String=unique.path_join("original-primary.json");var secondary:String=unique.path_join("original-backup.json");var archive:String=unique.path_join("archive")
 var raw:String="{\n\t\"credits\": 75, \"inventory\": {\"not_gate\": 2}, \"design\": [], \"launcher\": [], \"settings\": {}\n}\n"
 var old_raw:String="{ \"credits\": 72, \"exact_old_bytes\": true }\n"
 check(write(primary,raw) and write(secondary,old_raw),"test raw slots written with original whitespace")
 var snapshot:Dictionary=JSON.parse_string(raw)
 var backed:Dictionary=Migration.archive_raw_slots(snapshot,primary,primary,secondary,archive)
 check(backed.ok,"both raw slots backed before migration")
 if backed.ok:
  check(FileAccess.get_file_as_bytes(str(backed.archive_path).path_join("savegame.json"))==raw.to_utf8_buffer(),"primary archive is byte-for-byte, not JSON serialization")
  check(FileAccess.get_file_as_bytes(str(backed.archive_path).path_join("savegame.backup.json"))==old_raw.to_utf8_buffer(),"previous durable backup preserved verbatim")
  check(backed.source_sha256==FileAccess.get_sha256(primary),"receipt source hash is real original SHA256")
  check(Migration.archive_raw_slots(snapshot,primary,primary,secondary,archive).ok,"same uncommitted transaction can safely retry archive")
  var mismatch:Dictionary=snapshot.duplicate(true);mismatch.credits=76
  check(not Migration.archive_raw_slots(mismatch,primary,primary,secondary,archive).ok,"changed preview source refuses archival/commit")
  var archived:String=str(backed.archive_path).path_join("savegame.backup.json")
  check(write(archived,"conflicting backup"),"test intentionally conflicts only its own archive")
  check(not Migration.archive_raw_slots(snapshot,primary,primary,secondary,archive).ok,"conflicting archive fails closed rather than overwrite")
  check(FileAccess.get_file_as_string(archived)=="conflicting backup","existing archive is never replaced on conflict")
  check(FileAccess.get_file_as_string(primary)==raw and FileAccess.get_file_as_string(secondary)==old_raw,"archive checks never mutate original slots")
 print("PARTS_MIGRATION_ARCHIVE_V2 failures=",failures," fixtures_retained=",unique," real_save_paths=UNTOUCHED")
 quit(1 if failures else 0)
