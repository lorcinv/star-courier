extends SceneTree
const Main=preload("res://scripts/main.gd")
const Econ=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
class Controller extends "res://scripts/main.gd":
 var saves:int=0
 var exits:int=0
 var allow_save:bool=true
 var notices:Array=[]
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func save_game() -> bool:
  saves+=1;_last_save_error="测试写入失败"
  return allow_save
 func _finish_quit(_code:int) -> void:exits+=1
 func notify(message:String) -> void:notices.append(message)
class RenameObstructedEconomy extends "res://scripts/economy.gd":
 var obstruct:bool=false
 func _valid_save(value:Variant,check_integrity:bool=true) -> bool:
  var valid:bool=super._valid_save(value,check_integrity)
  if valid and obstruct:
   obstruct=false;DirAccess.remove_absolute("user://savegame.tmp");DirAccess.make_dir_absolute("user://savegame.tmp")
  return valid
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func clean() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  DirAccess.remove_absolute("user://"+name)
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func run() -> void:
 root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
 var app=Controller.new();root.add_child(app)
 app._action("save_and_quit",null);app._action("save_and_quit",null)
 check(app.closing and app._quit_prompt.visible and app.saves==0 and app.exits==0,"repeated exit requests open one confirmation with no save")
 app._quit_prompt.canceled.emit()
 check(not app.closing and app.saves==0 and app.exits==0,"cancel confirmation performs no save or exit")
 app.allow_save=false;app._request_save_and_quit();app._quit_prompt.confirmed.emit()
 check(app.saves==1 and app.exits==0 and app._quit_dialog.visible and app.closing,"failed save stays in game with retry/discard/cancel dialog")
 app._quit_cleanly();app._request_save_and_quit()
 check(app.saves==1 and app.exits==0,"repeated close during error cannot save or exit again")
 app._quit_dialog.canceled.emit()
 check(not app.closing and app.saves==1 and app.exits==0,"cancel error performs no additional save")
 app._quit_cleanly();app.allow_save=true;app._quit_dialog.confirmed.emit()
 check(app.saves==3 and app.exits==1,"retry saves once and exits only after success")
 app.free()
 app=Controller.new();root.add_child(app);app.allow_save=false;app._quit_cleanly();app._quit_dialog.custom_action.emit("discard")
 check(app.saves==1 and app.exits==1,"explicit discard exits without retrying or claiming a save")
 app.free()
 app=Controller.new();root.add_child(app);app.economy.review_load_blocked=true;app._request_save_and_quit()
 check(app.saves==0 and app.exits==1,"read-only recovery exits without rewriting unsupported save")
 app.free()
 for obstruction in ["savegame.tmp","savegame.shop-backup.tmp","primary_rename"]:
  clean();var e=RenameObstructedEconomy.new();e.ensure_contracts()
  check(e.save_state([],[],{}),"seed primary "+obstruction);e.credits+=1
  check(e.save_state([],[],{}),"seed distinct backup "+obstruction)
  var before:Array=disk();e.credits+=1
  if obstruction=="primary_rename":e.obstruct=true
  else:DirAccess.make_dir_absolute("user://"+obstruction)
  check(not e.save_state([],[],{}),"routine save reports injected filesystem failure "+obstruction)
  check(disk()==before,"BOTH durable byte streams unchanged after failed routine save "+obstruction)
  DirAccess.remove_absolute("user://savegame.tmp" if obstruction=="primary_rename" else "user://"+obstruction)
  check(e.save_state([],[],{}),"routine save retry succeeds "+obstruction)
  check(FileAccess.get_file_as_bytes("user://savegame.backup.json")==before[0],"retry rotates exact old primary "+obstruction)
  var loaded=Econ.new();check(not loaded.load_state().is_empty() and loaded.credits==e.credits,"committed save reloads "+obstruction)
 clean()
 print("DEV03_AUDIO_EXIT passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
