extends SceneTree
class Econ extends "res://scripts/economy.gd":
 var obstruct:bool=false
 func _valid_save(value:Variant,check_integrity:bool=true) -> bool:
  var valid:bool=super._valid_save(value,check_integrity)
  if valid and obstruct:
   obstruct=false;DirAccess.remove_absolute("user://savegame.tmp");DirAccess.make_dir_absolute("user://savegame.tmp")
  return valid
func _initialize() -> void:
 var e=Econ.new();e.ensure_contracts();e.save_state([],[],{});e.credits+=1;e.save_state([],[],{})
 var primary:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var backup:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.backup.json")
 e.credits+=1;e.obstruct=true
 var ok:bool=e.save_state([],[],{})
 print("SAVE_RENAME_PROBE ",JSON.stringify({"ok":ok,"primary_unchanged":primary==FileAccess.get_file_as_bytes("user://savegame.json"),"backup_unchanged":backup==FileAccess.get_file_as_bytes("user://savegame.backup.json"),"save_error":e.save_error}))
 quit()
