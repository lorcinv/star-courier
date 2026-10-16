extends SceneTree
## Script-driven behavioral tests, not human/native-input acceptance.
const Econ=preload("res://scripts/economy.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Policy=preload("res://scripts/combined_offer_authoring_policy.gd")
var passed:int=0
var failed:int=0
const SAVE_NAMES:Array=["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]
class InjectedEconomy extends "res://scripts/economy.gd":
 var fail_save:bool=true
 var save_calls:int=0
 func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
  save_calls+=1
  if fail_save:
   # Deliberately model normalization/metadata side effects before a failure.
   review_state={"injected":"candidate"};story_state["injected"]={"deep":[1,2]}
   offer_generation_state["injected"]=[3];load_notice="candidate notice"
   save_error="injected saver failure";return false
  return super.save_state(design,launcher,settings)
class RenameObstructedEconomy extends "res://scripts/economy.gd":
 var obstruct_after_validation:bool=false
 func _valid_save(value:Variant,check_integrity:bool=true) -> bool:
  var valid:bool=super._valid_save(value,check_integrity)
  if valid and obstruct_after_validation:
   obstruct_after_validation=false
   # Actual filesystem fault, not a fabricated false saver return. The valid
   # candidate was already read; replace only its disposable tmp with a dir.
   DirAccess.remove_absolute("user://savegame.tmp")
   DirAccess.make_dir_absolute("user://savegame.tmp")
  return valid
class ShopWorld extends RefCounted:
 var at_counter:bool=true
 var loading:bool=false
 func is_at_shop_counter() -> bool:return at_counter
 func request_shop_navigation(_action:String) -> bool:return false
 func is_loading_scene() -> bool:return loading
class OpenModal extends RefCounted:
 var opened:bool=true
 func is_open() -> bool:return opened
class Controller extends "res://scripts/main.gd":
 var notices:Array=[]
 var navigations:Array=[]
 var stories:Array=[]
 var renders:int=0
 func _ready() -> void:pass
 func notify(message:String) -> void:notices.append(message)
 func render() -> void:renders+=1
 func navigate(target:String) -> void:page=target;navigations.append(target)
 func _request_story(id:String,beat:String) -> void:stories.append([id,beat])
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 test_injected_failures();test_filesystem_failures();test_commit_point();test_implicit_metadata();test_rejections();test_main_behavior();test_main_guards()
 clean()
 print("SHOP_SAVE_TRANSACTIONS passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func snapshot(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func same(a:Variant,b:Variant) -> bool:return var_to_bytes(a)==var_to_bytes(b)
func disk_bytes() -> Array:
 var result:Array=[]
 for path in ["user://savegame.json","user://savegame.backup.json"]:
  result.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return result
func clean() -> void:
 for name in SAVE_NAMES:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func setup(action:String,e:Variant=null):
 if e==null:e=Econ.new()
 e.credits=2000;e.reputation=3;e.ensure_contracts()
 if action=="cancel":e.accept_contract("D1-A")
 if action in ["buy","research"]:e.phase="night"
 return e
func invoke(e,action:String) -> Dictionary:
 match action:
  "accept":return e.accept_contract_and_save("D1-A",[],[],{})
  "decline":return e.decline_available_and_save("D1-A",[],[],{})
  "cancel":return e.cancel_accepted_and_save([],[],{})
  "close":return e.close_day_and_save([],[],{})
  "buy":return e.buy_part_and_save("beam",Parts.catalog().beam,[],[],{})
  "research":return e.research_upgrade_and_save([],[],{})
 return {"ok":false}
func committed(e,action:String) -> bool:
 match action:
  "accept":return e.active_contract_id=="D1-A" and e.contracts[0].status=="accepted"
  "decline":return e.contracts[0].status=="declined"
  "cancel":return e.active_contract_id.is_empty() and e.contracts[0].status=="cancelled" and e.reputation==2
  "close":return e.phase=="night"
  "buy":return e.credits==1990 and e.inventory.beam==1
  "research":return e.research==1 and e.credits==1860
 return false
func test_injected_failures() -> void:
 for action in ["accept","decline","cancel","close","buy","research"]:
  clean();var e=setup(action,InjectedEconomy.new());e.fail_save=false
  check(e.save_state([],[],{}),action+" seed primary");e.credits+=1;e.save_state([],[],{});e.credits-=1
  var before:Dictionary=snapshot(e);var files:Array=disk_bytes();var held_contracts:Array=e.contracts;var held_stock:Dictionary=e.inventory;e.fail_save=true
  for attempt in 2:
   var result:Dictionary=invoke(e,action)
   check(not result.ok and result.message=="injected saver failure",action+" injected failure "+str(attempt))
   check(same(before,snapshot(e)),action+" all memory and nested metadata restored "+str(attempt))
   check(same(held_contracts,before.contracts) and same(held_stock,before.inventory),action+" prior HUD/model aliases never observe candidate changes")
   check(same(files,disk_bytes()),action+" injected saver leaves durable bytes unchanged")
  e.fail_save=false
  check(invoke(e,action).ok and committed(e,action),action+" retry applies exactly once")
  var loaded=Econ.new();check(not loaded.load_state().is_empty() and committed(loaded,action),action+" real success survives reload")
  var after:Dictionary=snapshot(e);var again:Dictionary=invoke(e,action)
  if action in ["accept","decline","cancel"]:check(not again.ok and same(after,snapshot(e)),action+" repeat rejected without side effects")
  elif action=="close":check(again.ok and same(after,snapshot(e)),"repeated close remains same day and phase")
  elif action=="buy":check(again.ok and e.credits==1980 and e.inventory.beam==2,"second successful click buys exactly one additional part")
  else:check(again.ok and e.research==2 and e.credits==1620,"second successful research uses existing next-level cost")
func test_filesystem_failures() -> void:
 for obstruction in ["savegame.tmp","savegame.shop-backup.tmp"]:
  for action in ["accept","decline","cancel","close","buy","research"]:
   clean();var e=setup(action);e.save_state([],[],{});e.credits+=1;e.save_state([],[],{});e.credits-=1
   var before:Dictionary=snapshot(e);var files:Array=disk_bytes()
   check(DirAccess.make_dir_absolute("user://"+obstruction)==OK,"create real directory obstruction "+obstruction)
   check(not invoke(e,action).ok,action+" actual filesystem save failure at "+obstruction)
   check(same(before,snapshot(e)) and same(files,disk_bytes()),action+" real failure restores memory and BOTH durable byte streams")
   DirAccess.remove_absolute("user://"+obstruction)
   check(invoke(e,action).ok and committed(e,action),action+" actual filesystem retry commits once")
func test_commit_point() -> void:
 for action in ["accept","decline","cancel","close","buy","research"]:
  clean();var e=setup(action,RenameObstructedEconomy.new());e.save_state([],[],{});e.credits+=1;e.save_state([],[],{});e.credits-=1
  var before:Dictionary=snapshot(e);var files:Array=disk_bytes();e.obstruct_after_validation=true
  check(not invoke(e,action).ok and "替换存档失败" in e.save_error,action+" real rename fails at authoritative commit point")
  check(same(before,snapshot(e)) and same(files,disk_bytes()),action+" failed primary rename retains original primary AND distinct backup")
  DirAccess.remove_absolute("user://savegame.tmp")
  check(invoke(e,action).ok and committed(e,action),action+" retry after failed primary rename commits once")
 # A backup destination directory creates a genuine post-commit rename error.
 # There was no backup file here: this case tests commit semantics, not bytes
 # of an existing file. The main failure tests above cover existing backups.
 clean();var e=setup("buy");e.save_state([],[],{});DirAccess.make_dir_absolute("user://savegame.backup.json")
 var result:Dictionary=invoke(e,"buy")
 check(result.ok and committed(e,"buy") and "已保存" in result.get("message",""),"post-commit backup promotion failure reports committed success with warning")
 var loaded=Econ.new();loaded.load_state()
 check(committed(loaded,"buy") and e.save_error.is_empty(),"post-commit backup warning cannot roll memory back against durable primary")
 DirAccess.remove_absolute("user://savegame.backup.json")
 clean();e=setup("buy");e.save_state([],[],{});var old:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 check(invoke(e,"buy").ok and FileAccess.get_file_as_bytes("user://savegame.backup.json")==old,"successful shop commit rotates exact previous valid primary to backup")

func test_implicit_metadata() -> void:
 clean();var e=Econ.new();e.flight_mode=Extreme.CONTROL_VERSION;e.story_mode=true;e.day=5;e.reputation=7
 e.story_state=e.Stories.initial_state(420)
 e.offer_generation_state={"version":Policy.CURRENT_VERSION,"world_seed":420,"ordinary_policy":Policy.Ordinary.CURRENT_VERSION,"introduced_day":0}
 var before:Dictionary=snapshot(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var result:Dictionary=e.accept_contract_and_save("D5-A",[],[],{})
 check(not result.ok and same(before,snapshot(e)),"implicit generated batch, bird introduction, story binding and review normalization roll back")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.accept_contract_and_save("D5-A",[],[],{}).ok,"empty authored batch succeeds on retry")
 check(e.offer_generation_state.introduced_day==5 and e.contracts.size()==2 and e.active_contract_id=="D5-A","retry retains deterministic identity and one introduction")
 # Invalid ID also triggers legacy ensure_contracts: rejection must restore it.
 clean();e=Econ.new();before=snapshot(e)
 check(not e.accept_contract_and_save("missing",[],[],{}).ok and same(before,snapshot(e)),"rejected action rolls back incidental empty-batch creation")
 # Actual save normalizes null review state before temporary-file failure.
 e=setup("buy");e.review_state=null;before=snapshot(e);DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not invoke(e,"buy").ok and same(before,snapshot(e)) and e.review_state==null,"actual failed writer restores null pre-normalization reviews")
 DirAccess.remove_absolute("user://savegame.tmp")
func test_rejections() -> void:
 clean();var e=setup("accept",InjectedEconomy.new());var before:Dictionary=snapshot(e)
 e.route_guard=func(_route:Dictionary) -> String:return "unsupported presentation"
 check(not invoke(e,"accept").ok and same(before,snapshot(e)) and e.save_calls==0,"route capability rejection runs before save/mutation")
 e.route_guard=Callable();e.review_load_blocked=true;e.load_notice="recovery lock";before=snapshot(e)
 check(not invoke(e,"close").ok and same(before,snapshot(e)) and e.save_calls==0,"review recovery guard unchanged")
 e=setup("buy",InjectedEconomy.new());e.credits=9;before=snapshot(e)
 check(not invoke(e,"buy").ok and same(before,snapshot(e)) and e.save_calls==0,"unaffordable purchase never saves")
 e=setup("research",InjectedEconomy.new());e.research=3;before=snapshot(e)
 check(not invoke(e,"research").ok and same(before,snapshot(e)) and e.save_calls==0,"max research never saves")
func make_app(action:String):
 var app=Controller.new();app.economy=setup(action);app.world=ShopWorld.new();app.catalog=Parts.catalog();app.page="contracts" if action in ["accept","decline","cancel"] else "supply"
 return app
func main_action(action:String) -> String:return {"accept":"accept_contract","decline":"decline_contract","cancel":"cancel_contract","close":"close_day","buy":"buy","research":"upgrade"}[action]
func main_payload(action:String) -> Variant:return "D1-A" if action in ["accept","decline"] else ("beam" if action=="buy" else null)
func test_main_behavior() -> void:
 for action in ["accept","decline","cancel","close","buy","research"]:
  clean();var app=make_app(action);app.economy.save_state([],[],{});app.economy.credits+=1;app.economy.save_state([],[],{});app.economy.credits-=1
  var before:Dictionary=snapshot(app.economy);var files:Array=disk_bytes();var page:String=app.page
  DirAccess.make_dir_absolute("user://savegame.tmp");app._action(main_action(action),main_payload(action))
  check(same(before,snapshot(app.economy)) and same(files,disk_bytes()),"Main "+action+" real failure restores memory and disk")
  check(app.page==page and app.renders==0 and app.navigations.is_empty() and app.stories.is_empty(),"Main "+action+" failure does not navigate/render/start story")
  check(app.notices.size()==1 and "临时存档" in app.notices[0],"Main "+action+" reports only one error, never success")
  DirAccess.remove_absolute("user://savegame.tmp");app.notices.clear();app._action(main_action(action),main_payload(action))
  check(committed(app.economy,action),"Main "+action+" retry commits expected single mutation")
  var loaded=Econ.new();loaded.load_state();check(committed(loaded,action),"Main "+action+" durable success")
  if action=="accept":check(app.navigations==["hub"] and app.stories==[["D1-A","accept"]],"Main accepted story begins only after commit")
  if action=="buy":check(app.notices==["零件已放到货架上。"] and app.renders==1,"Main purchase success feedback occurs after commit")
  app.free()
 clean();var app=make_app("buy");app.economy.save_state([],[],{});DirAccess.make_dir_absolute("user://savegame.backup.json")
 app._action("buy","beam")
 check(committed(app.economy,"buy") and app.notices.size()==1 and "备份未能更新" in app.notices[0],"Main committed purchase keeps its backup warning visible")
 DirAccess.remove_absolute("user://savegame.backup.json");app.free()
func test_main_guards() -> void:
 for guard in ["dialogue","phone","investigation","loading","replay"]:
  clean();var app=make_app("buy");var before:Dictionary=snapshot(app.economy)
  if guard=="dialogue":app.dialogue=OpenModal.new()
  if guard=="phone":app.review_phone=OpenModal.new();app._review_phone_owner=1
  if guard=="investigation":app.investigation=OpenModal.new()
  if guard=="loading":app.world.loading=true
  if guard=="replay":app.pilot_resume_blocked=true
  app._action("buy","beam")
  check(same(before,snapshot(app.economy)) and not FileAccess.file_exists("user://savegame.json"),"Main existing "+guard+" guard prevents mutation and persistence")
  app.free()
 clean();var app=make_app("accept");app.world.at_counter=false;var before:Dictionary=snapshot(app.economy);app._action("accept_contract","D1-A")
 check(same(before,snapshot(app.economy)) and app.stories.is_empty() and not FileAccess.file_exists("user://savegame.json"),"Main acceptance still requires arrival at counter")
 app.free()
