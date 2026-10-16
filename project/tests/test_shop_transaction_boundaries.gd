extends SceneTree
## Real Main + GameHUD lifecycle; actions are script-driven, not native input.
## Reentry is a synthetic callback-boundary robustness probe. Main's route
## guard is pure; this does not claim an observed live exploit.
const MainScene=preload("res://scenes/main.tscn")
const Econ=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
var game
const SAVE_NAMES:Array=["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","savegame.hud-held-backup.json"]
class ReentrantEconomy extends "res://scripts/economy.gd":
 var entered:bool=false
 var reject_outer:bool=false
 var fail_save:bool=false
 var save_calls:int=0
 var nested:Array=[]
 func reenter(_route:Dictionary) -> String:
  if entered:return ""
  entered=true
  nested.append(decline_available_and_save("D1-A",[],[],{}))
  return "outer rejected by synthetic callback" if reject_outer else ""
 func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
  save_calls+=1
  if fail_save:save_error="injected outer save failure";return false
  return super.save_state(design,launcher,settings)
class BackupObstructedEconomy extends "res://scripts/economy.gd":
 var obstruct_backup:bool=false
 var backup_faults:int=0
 func _commit_shop_save() -> bool:
  if not obstruct_backup:return super._commit_shop_save()
  # Real filesystem obstruction only for the shop commit. Restore the old
  # backup path before Main's independent story save, which stays unchanged.
  var backup:String="user://savegame.backup.json"
  var held:String="user://savegame.hud-held-backup.json"
  var existed:bool=FileAccess.file_exists(backup)
  if existed and DirAccess.rename_absolute(backup,held)!=OK:
   save_error="HUD fixture could not retain old backup";return false
  if DirAccess.make_dir_absolute(backup)!=OK:
   if existed:DirAccess.rename_absolute(held,backup)
   save_error="HUD fixture could not create obstruction";return false
  var saved:bool=super._commit_shop_save()
  if saved and not _shop_backup_warning.is_empty():backup_faults+=1
  DirAccess.remove_absolute(backup)
  if existed:DirAccess.rename_absolute(held,backup)
  return saved
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func same(a:Variant,b:Variant) -> bool:return var_to_bytes(a)==var_to_bytes(b)
func snapshot(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func durable() -> Array:
 var result:Array=[]
 for path in ["user://savegame.json","user://savegame.backup.json"]:result.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return result
func clean() -> void:
 for name in SAVE_NAMES:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func frames(count:int=4) -> void:
 for i in count:await process_frame
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 test_callback_reentry();test_prepare_reentry()
 root.size=Vector2i(1280,800)
 for action in ["accept_contract","cancel_contract","close_day"]:
  await test_real_hud(action,false)
  await test_real_hud(action,true)
 await dispose();clean()
 print("SHOP_TRANSACTION_BOUNDARIES passed=%d failed=%d total=%d native_input=false"%[passed,failed,passed+failed]);quit(1 if failed else 0)
func test_callback_reentry() -> void:
 for mode in ["success","mutation_rejected","save_failed"]:
  clean();var e=ReentrantEconomy.new();e.ensure_contracts();e.save_state([],[],{});e.save_calls=0
  var before:Dictionary=snapshot(e);var files:Array=durable()
  e.route_guard=e.reenter;e.reject_outer=mode=="mutation_rejected";e.fail_save=mode=="save_failed"
  var outer:Dictionary=e.accept_contract_and_save("D1-A",[],[],{})
  check(e.nested.size()==1 and not e.nested[0].ok,"mutation callback nested decline rejected: "+mode)
  check(e.save_calls==(0 if mode=="mutation_rejected" else 1),"nested callback cannot perform a separate save: "+mode)
  var loaded=Econ.new();loaded.load_state()
  if mode=="success":
   check(outer.ok and e.contracts[0].status=="accepted" and e.active_contract_id=="D1-A","outer acceptance remains internally consistent")
   check(loaded.contracts[0].status=="accepted" and loaded.active_contract_id=="D1-A","outer acceptance matches durable contract and identity")
  else:
   check(not outer.ok and same(before,snapshot(e)),"outer failure restores all memory: "+mode)
   check(same(files,durable()) and loaded.contracts[0].status=="available" and loaded.active_contract_id.is_empty(),"outer failure leaves disk unchanged despite nested attempt: "+mode)
  check(not e._shop_save_in_progress,"ownership released after outer outcome: "+mode)
  e.route_guard=Callable();e.fail_save=false
  check(e.decline_available_and_save("D1-B",[],[],{}).ok,"later independent action succeeds after outer outcome: "+mode)
func test_prepare_reentry() -> void:
 for permitted in [false,true]:
  clean();var e=ReentrantEconomy.new();e.ensure_contracts();e.save_state([],[],{});e.save_calls=0
  var before:Dictionary=snapshot(e);var files:Array=durable();var nested:Array=[]
  var prepare:Callable=func() -> bool:
   nested.append(e.decline_available_and_save("D1-B",[],[],{}));return permitted
  var result:Dictionary=e.accept_contract_and_save("D1-A",[],[],{},prepare)
  check(nested.size()==1 and not nested[0].ok,"prepare callback rejects nested transaction: "+str(permitted))
  check(result.ok==permitted and e.save_calls==(1 if permitted else 0),"prepare outcome has only outer save ownership: "+str(permitted))
  if not permitted:check(same(before,snapshot(e)) and same(files,durable()),"rejected prepare restores memory and original bytes")
  check(not e._shop_save_in_progress,"prepare outcome releases ownership: "+str(permitted))
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await frames()
 game=null
func fresh() -> void:
 await dispose();clean()
 game=MainScene.instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false);await frames()
 var guard:Callable=game.economy.route_guard
 var e=BackupObstructedEconomy.new();e.route_guard=guard;e.load_state();e.story_mode=game.economy.story_mode;game.economy=e
func test_real_hud(action:String,fail_before_commit:bool) -> void:
 await fresh()
 if action=="cancel_contract":
  check(game.economy.accept_contract("D1-A").ok,"cancel HUD fixture accepts its exact contract")
  game.economy.mark_story_seen("D1-A","D1-A/accept")
  check(game.economy.mark_cargo_loaded("D1-A").ok,"cancel HUD fixture retains completed cargo handoff")
  game.economy.save_state(game.design,game.launcher,game.settings)
 var initial_mode:String="hub" if action=="close_day" else "contracts"
 game.navigate(initial_mode);await frames()
 check(game.hud.mode==initial_mode and game.hud._last_mode==initial_mode,"real HUD begins in "+initial_mode+": "+action)
 var before:Dictionary=snapshot(game.economy);var files:Array=durable()
 game.economy.obstruct_backup=not fail_before_commit
 if fail_before_commit:DirAccess.make_dir_absolute("user://savegame.tmp")
 game._action(action,"D1-A" if action=="accept_contract" else null)
 await frames()
 if fail_before_commit:
  check(game.page==initial_mode and game.hud.mode==initial_mode,"real HUD failed action does not navigate: "+action)
  check(same(before,snapshot(game.economy)) and same(files,durable()),"real HUD failed action preserves memory and disk: "+action)
  check(game.hud.toast_panel.visible and game.hud.toast_timer>0 and "临时存档" in game.hud._toast_raw_text and not "本次操作已保存" in game.hud._toast_raw_text,"real HUD shows only failure after rollback: "+action)
  DirAccess.remove_absolute("user://savegame.tmp")
 else:
  var target:String="supply" if action=="close_day" else "hub"
  check(game.page==target and game.hud.mode==target,"real Main/HUD completed mode change: "+action)
  check(game.economy.backup_faults==1,"real backup promotion fault occurred once: "+action)
  check(game.hud.toast_panel.visible and game.hud.toast_timer>0 and "备份未能更新" in game.hud._toast_raw_text,"backup warning survives actual GameHUD mode change: "+action)
  check(game.hud.visible and not game.hud.toast_label.text.is_empty(),"warning remains in active HUD after deferred work: "+action)
  var loaded=Econ.new();loaded.load_state()
  if action=="accept_contract":
   check(game.dialogue.is_open() and game._active_story.get("contract_id")=="D1-A","acceptance story setup finishes before warning remains visible")
   check(loaded.active_contract_id=="D1-A" and loaded.contracts[0].status=="accepted","warning acceptance remains durably accepted")
  elif action=="cancel_contract":check(loaded.active_contract_id.is_empty() and loaded.contracts[0].status=="cancelled","warning cancellation remains durably cancelled")
  else:check(loaded.phase=="night","warning closing remains durably night")
