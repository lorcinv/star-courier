extends SceneTree
## Real, unmodified Main startup/focus/input/actions/shutdown, headless.
## No rendering proof, native OS input, or live player files are involved.
const Main=preload("res://scripts/main.gd")
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func write_save(path:String,value:Dictionary):
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(value,"",true,true));f.close()
func clear_files():
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:DirAccess.remove_absolute("user://"+name)
func exercise(app,source:String,backup:String,label:String):
 check(app.economy.review_load_blocked and app.world==null and app.hud==null and app.sim==null,"recovery-only before any UI/simulation: "+label)
 check(app.get_child_count()==1 and app.get_child(0) is Label and not app.is_processing() and not app.is_processing_input() and not app.is_processing_unhandled_key_input(),"only recovery notice and no normal input: "+label)
 var design:Array=app.design.duplicate(true);var settings:Dictionary=app.settings.duplicate(true);var flight:Dictionary=app.economy.in_flight.duplicate(true);var receipts:Dictionary=app.economy.settled_ids.duplicate(true)
 for unused in 3:
  root.focus_exited.emit();root.focus_entered.emit();app._on_focus_exited();app._on_focus_entered()
 for action in ["next_day","buy","upgrade","workshop_upgrade","dispatch","trial","settings","customer_reviews","focus_counter","focus_workbench","close_drawer"]:app._action(action,null)
 app.navigate("workshop");app.render();app.start_flight(false);app.start_flight(true);app._resume_dispatch();app.abort_flight();app.finish_flight();app._process(.01)
 for code in [KEY_ESCAPE,KEY_F11,KEY_R,KEY_DELETE,KEY_ENTER]:
  var key:=InputEventKey.new();key.pressed=true;key.keycode=code;app._unhandled_key_input(key);app._input(key);key.pressed=false;app._input(key)
 check(app.world==null and app.hud==null and app.sim==null and app.page=="hub" and app.review_phone==null,"focus/actions/direct resume cannot launch or disclose review: "+label)
 check(app.design==design and app.settings==settings and app.economy.in_flight==flight and app.economy.settled_ids==receipts,"all recovery entry points retain design/ledger/snapshot: "+label)
 check(not app.save_game() and not FileAccess.file_exists("user://savegame.tmp"),"recovery creates no temporary save: "+label)
 check(FileAccess.get_file_as_string("user://savegame.json")==source and FileAccess.get_file_as_string("user://savegame.backup.json")==backup,"both source byte strings preserved: "+label)
func run():
 clear_files();var e=Econ.new();e.enable_extreme_mode();e.ensure_contracts();e.accept_contract("D1-A");e.begin_dispatch(Profile.starter_design(),Profile.starter_launcher());e.save_state(Profile.starter_design(),Profile.starter_launcher(),{})
 var valid:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 var cases:Array=[]
 for value in [null,"203",203.5,true,9007199254740992]:
  var bad:Dictionary=valid.duplicate(true);bad.in_flight.seed=value;cases.append({"label":"seed "+str(value),"primary":bad,"backup":bad})
 e.settle_contract_and_save("D1-A",{"integrity":1.0},62.675,true,[],[],{})
 var review_bad:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"));review_bad.review_state.pending["D1-A"].elapsed=1.0;review_bad.review_state.pending["D1-A"].destination_name="虚构收货点"
 cases.append({"label":"contradictory review","primary":review_bad,"backup":review_bad})
 var future:Dictionary=valid.duplicate(true);future.in_flight.control_version="future-v900";future.in_flight.seed=null;future.in_flight.elapsed=null;future.in_flight.ticks={"opaque":true}
 cases.append({"label":"future protocol with valid old backup","primary":future,"backup":valid})
 var opaque:Dictionary=future.duplicate(true);opaque.version=99;opaque.review_state=["opaque future review"];opaque.settled_ids="opaque ledger";opaque.credits={"future":true};opaque.design=null;opaque.settings=null
 cases.append({"label":"future protocol with opaque adjacent structures","primary":opaque,"backup":valid})
 var app
 var source:String="";var backup:String=""
 for i in cases.size():
  var item:Dictionary=cases[i];clear_files();write_save("user://savegame.json",item.primary);write_save("user://savegame.backup.json",item.backup)
  source=FileAccess.get_file_as_string("user://savegame.json");backup=FileAccess.get_file_as_string("user://savegame.backup.json")
  app=Main.new();root.add_child(app);await process_frame
  exercise(app,source,backup,item.label)
  if i<cases.size()-1:app.queue_free();await process_frame
 # Last case exits only through the production connected close handler.
 root.close_requested.emit();root.close_requested.emit();app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
 await process_frame;check(app.closing,"connected close enters real clean shutdown once")
 root.focus_exited.emit();root.focus_entered.emit();app._action("next_day",null)
 await create_timer(.05).timeout
 check(FileAccess.get_file_as_string("user://savegame.json")==source and FileAccess.get_file_as_string("user://savegame.backup.json")==backup and not FileAccess.file_exists("user://savegame.tmp"),"shutdown and late callbacks preserve future primary and old backup")
 print("RECOVERY_INTEGRITY_LIFECYCLE passed=%d failed=%d"%[passed,failed])
 if failed:quit(1)
