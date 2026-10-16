extends SceneTree
## Real Title lifecycle and real SceneTree.quit in a copied native save profile.
## Test API calls are not native keyboard or Windows acceptance.
const TitleScene=preload("res://scenes/demo_title.tscn")
const FIXTURE:String="res://tests/fixtures/dev03-formal-flight-2815/"
var title
var candidate_weak:WeakRef
var candidate_left:bool=false
var ownership_failed:bool=false
func _initialize() -> void:run.call_deferred()
func settle(n:int=3) -> void:
 for unused in n:await process_frame
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or FileAccess.file_exists("user://savegame.json"):quit(2);return
 for name in ["savegame.json","savegame.backup.json"]:
  var f:=FileAccess.open("user://"+name,FileAccess.WRITE);f.store_buffer(FileAccess.get_file_as_bytes(FIXTURE+name));f.close()
 root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
 title=TitleScene.instantiate();root.add_child(title);await settle();title._focus_entered();await settle()
 title._continue_game()
 var deadline:int=Time.get_ticks_msec()+12000
 while title.screen!="opening" and (title.busy or title.screen!="menu") and Time.get_ticks_msec()<deadline:await process_frame
 if not is_instance_valid(title.game) or not title.game.title_restore_pending():push_error("FAILED no pending replay");quit(3);return
 candidate_weak=weakref(title.game)
 title.game.tree_exited.connect(func():candidate_left=true;print("PENDING_CANDIDATE_RETIRED"))
 var original_candidate=title.game
 var mode:String=OS.get_environment("STAR_COURIER_PENDING_QUIT_MODE")
 if mode=="cancel_then_quit":
  var cancel:Button=title.title_stage.get_node_or_null("CancelFlightRestore")
  if cancel==null:push_error("FAILED no Cancel control");quit(4);return
  cancel.pressed.emit()
  if not title._retiring_restore:push_error("FAILED cancellation not retiring");quit(5);return
 elif mode not in ["direct_pending_quit","os_signal_first","os_notification_first","cancel_then_os_close"]:quit(6);return
 print("ACTUAL_TITLE_QUIT mode=",mode," pending_candidate=true")
 if mode=="os_signal_first":
  root.close_requested.emit();root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
 elif mode=="os_notification_first":
  root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);root.close_requested.emit()
 elif mode=="cancel_then_os_close":
  title.title_stage.get_node("CancelFlightRestore").pressed.emit()
  root.close_requested.emit();root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
 else:title._quit_title()
 if original_candidate.closing:
  print("FAIL_CANDIDATE_OWNED_CLOSE_WHILE_TITLE_DEFERRED");ownership_failed=true
 else:print("PASS_TITLE_SOLE_CLOSE_OWNER")
 # The actual title quit owns process exit. No mocked Main or forced timeout.
