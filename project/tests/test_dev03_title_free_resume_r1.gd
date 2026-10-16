extends SceneTree
## Actual default Title/Main with a frozen native paid-flight save. API entry,
## not native keyboard. No simulation fields are written into the saved source.
const TitleScene=preload("res://scenes/demo_title.tscn")
const FIXTURE:String="res://tests/fixtures/dev03-formal-flight-2815/"
var title
var passed:int=0
var failed:int=0
var original:Array=[]
var expected:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=3) -> void:
 for i in n:await process_frame
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func seed_fixture() -> void:
 for name in ["savegame.json","savegame.backup.json"]:
  var f:=FileAccess.open("user://"+name,FileAccess.WRITE);f.store_buffer(FileAccess.get_file_as_bytes(FIXTURE+name));f.close()
 original=disk();expected=JSON.parse_string(original[0].get_string_from_utf8())
func open_title() -> void:
 title=TitleScene.instantiate();root.add_child(title);await settle()
 title._focus_entered();await settle()
func close_title() -> void:
 if is_instance_valid(title):title.queue_free()
 await settle(5)
func wait_start() -> void:
 var deadline:int=Time.get_ticks_msec()+12000
 while is_instance_valid(title) and not (title.screen=="game" or (title.screen=="menu" and not title.busy)) and Time.get_ticks_msec()<deadline:await process_frame
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):quit(2);return
 if FileAccess.file_exists("user://savegame.json"):push_error("fresh profile required");quit(2);return
 root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
 seed_fixture();await open_title();check(disk()==original,"actual title preview leaves both original slots byte-exact")
 title._continue_game();await wait_start()
 var restored:bool=title.screen=="game" and is_instance_valid(title.game)
 check(restored,"actual title waits for yielded 2815-tick replay and hands off to Main")
 if restored:
  var g=title.game
  check(g.page=="flight" and g.paused and not g.pilot_resume_blocked and not g.title_restore_pending(),"long resume is paused and controllable, not a failure hold")
  check(g.pilot_completed_ticks==int(expected.in_flight.ticks) and g.pilot_timeline.snapshot()==expected.in_flight.input_commands,"exact saved tick count and all input commands survive title handoff")
  check(g.economy.credits==450 and g.economy.jobs_today==1 and g.economy.deliveries==1 and not g.economy.settled_ids.has("D1-B"),"Continue neither charges nor settles the pending second order")
  check(g.economy.in_flight.contract_id=="D1-B" and g.flight_order.control_version=="pilot-free-v1","same paid free-flight identity is resumed")
  check(is_equal_approx(g.sim.elapsed,float(expected.in_flight.elapsed)),"elapsed display matches recorded flight duration")
  var t:int=g.pilot_completed_ticks;await settle(8)
  check(g.paused and g.pilot_completed_ticks==t,"waiting on resumed screen advances no physical ticks")
 await close_title()
 # Cancel during the first yield rather than after the small replay completes.
 seed_fixture();await open_title();title._continue_game()
 var deadline:int=Time.get_ticks_msec()+12000
 while title.screen!="opening" and (title.busy or title.screen!="menu") and Time.get_ticks_msec()<deadline:await process_frame
 var pending:bool=is_instance_valid(title.game) and title.game.title_restore_pending()
 check(pending,"real title exposes its pending replay state instead of rejecting it")
 if pending:
  var cancel:Button=title.title_stage.get_node_or_null("CancelFlightRestore")
  check(cancel!=null and cancel.visible,"pending replay exposes a visible Return Title control")
  if cancel!=null:cancel.pressed.emit();await settle(30)
  check(title.screen=="menu" and title.game==null and not title.busy,"cancel returns to title without late candidate publication")
  check(disk()==original,"cancelled replay preserves both exact original save files")
 await close_title()
 print("DEV03_TITLE_FREE_RESUME_R1 passed=%d failed=%d formal_fixture=true native_keyboard=false"%[passed,failed]);quit(1 if failed else 0)
