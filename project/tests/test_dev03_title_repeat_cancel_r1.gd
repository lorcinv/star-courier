extends SceneTree
const TitleScene=preload("res://scenes/demo_title.tscn")
const FIXTURE:String="res://tests/fixtures/dev03-formal-flight-2815/"
var title
var passed:int=0
var failed:int=0
var original:Array=[]
func _initialize() -> void:run.call_deferred()
func settle(n:int=3) -> void:
 for unused in n:await process_frame
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or FileAccess.file_exists("user://savegame.json"):quit(2);return
 for name in ["savegame.json","savegame.backup.json"]:
  var f:=FileAccess.open("user://"+name,FileAccess.WRITE);f.store_buffer(FileAccess.get_file_as_bytes(FIXTURE+name));f.close()
 original=disk();root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
 title=TitleScene.instantiate();root.add_child(title);await settle();title._focus_entered();await settle()
 for cycle in 2:
  title._continue_game()
  var deadline:int=Time.get_ticks_msec()+12000
  while title.screen!="opening" and (title.busy or title.screen!="menu") and Time.get_ticks_msec()<deadline:await process_frame
  var pending:bool=is_instance_valid(title.game) and title.game.title_restore_pending()
  check(pending,"cycle %d exposes pending restore"%cycle)
  if not pending:break
  var cancel:Button=title.title_stage.get_node_or_null("CancelFlightRestore")
  check(cancel!=null and cancel.visible,"cycle %d owns visible cancellation"%cycle)
  if cancel!=null:cancel.pressed.emit()
  await settle(5)
  check(title.screen=="menu" and title.game==null and not title.busy,"cycle %d returns to same title"%cycle)
  check(title.title_stage.get_node_or_null("CancelFlightRestore")==null,"cycle %d removes obsolete cancellation control"%cycle)
  check(disk()==original,"cycle %d preserves both save bytes"%cycle)
 print("DEV03_REPEAT_CANCEL passed=%d failed=%d"%[passed,failed])
 # Verify real title close; failures remain in output, wrapper evaluates them.
 title._quit_title()
