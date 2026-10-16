extends SceneTree
## Additive dev03 coverage for the newly shared routine-save staged commit.
## Real isolated filesystem obstructions; no production override or engine run
## is supplied by this overlay. This fixture must be run by the engine owner.
const Econ=preload("res://scripts/economy.gd")
const NAMES:Array=["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","savegame.routine-held-backup.json"]
var passed:int=0
var failed:int=0
class RoutineProbe extends "res://scripts/economy.gd":
 var obstruct_once:bool=false
 var fault_attempts:int=0
 var commit_calls:Array=[]
 func _commit_shop_save() -> bool:
  var call:Dictionary={"scope":"shop" if _shop_save_in_progress else "routine","injected":false,"ok":false,"warning":""}
  commit_calls.append(call)
  var result:bool=false
  if obstruct_once and not _shop_save_in_progress and fault_attempts==0:
   fault_attempts+=1;call.injected=true;result=_obstruct_backup_promotion()
  else:result=super._commit_shop_save()
  call.ok=result;call.warning=_shop_backup_warning
  return result
 func _obstruct_backup_promotion() -> bool:
  var backup:String="user://savegame.backup.json";var held:String="user://savegame.routine-held-backup.json"
  var had_backup:bool=FileAccess.file_exists(backup)
  if had_backup and DirAccess.rename_absolute(backup,held)!=OK:
   save_error="routine fixture could not retain old backup";return false
  if DirAccess.make_dir_absolute(backup)!=OK:
   if had_backup:DirAccess.rename_absolute(held,backup)
   save_error="routine fixture could not create backup obstruction";return false
  var result:bool=super._commit_shop_save()
  DirAccess.remove_absolute(backup)
  if had_backup:DirAccess.rename_absolute(held,backup)
  return result
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated XDG_DATA_HOME required.");quit(2);return
 test_normal_routine_rotation()
 for with_backup in [false,true]:test_routine_promotion_warning(with_backup)
 test_routine_precommit_failure()
 clean();print("ROUTINE_SAVE_BACKUP_PROMOTION_DEV03_R1 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant) -> bool:return var_to_bytes(a)==var_to_bytes(b)
func clean() -> void:
 for name in NAMES:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func slots() -> Array:
 var result:Array=[]
 for name in ["savegame.json","savegame.backup.json"]:
  var path:String="user://"+name
  result.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return result
func state(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func fixture(with_backup:bool=true):
 clean();var e=RoutineProbe.new();e.enable_free_mode();e.ensure_contracts()
 check(e.save_state([],[],{"routine_probe":"initial"}),"first routine save commits without prior primary")
 check(FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"first save has an authoritative primary and no invented backup")
 if with_backup:
  e.credits=259
  check(e.save_state([],[],{"routine_probe":"seed_backup"}),"second routine save seeds a distinct backup")
 e.commit_calls.clear();return e
func verify_loaded(e,label:String) -> void:
 var loaded=Econ.new();var payload:Dictionary=loaded.load_state(true)
 check(not loaded.review_load_blocked and loaded.load_notice.is_empty() and loaded._loaded_save_path=="user://savegame.json","routine result reloads authoritative primary without fallback: "+label)
 for key in ["credits","inventory","contracts","active_contract_id","phase","jobs_today","deliveries","settled_ids","history","last_settlement","in_flight"]:
  # JSON round-trip normalizes number types; compare semantic saved fields.
  check(JSON.parse_string(JSON.stringify(loaded.get(key),"",true,true))==JSON.parse_string(JSON.stringify(e.get(key),"",true,true)),"routine durable field matches exact committed outcome "+key+": "+label)
 check(not payload.is_empty(),"routine result returns a readable saved payload: "+label)
func test_normal_routine_rotation() -> void:
 var e=fixture();var before:Array=slots();e.credits=252;var expected:Dictionary=state(e)
 check(e.save_state([],[],{"routine_probe":"normal"}),"routine save successfully promotes its staged primary")
 check(same(state(e),expected),"successful routine save does not remutate the caller's candidate state")
 check(FileAccess.get_file_as_bytes("user://savegame.backup.json")==before[0],"routine success promotes the exact prior primary into backup")
 check(e.commit_calls.size()==1 and e.commit_calls[0].scope=="routine" and e.commit_calls[0].ok,"normal routine save reaches shared commit exactly once without shop ownership")
 check(e._shop_backup_warning.is_empty() and e.save_error.is_empty(),"normal routine save has neither failure nor backup warning")
 check(not FileAccess.file_exists("user://savegame.tmp") and not FileAccess.file_exists("user://savegame.shop-backup.tmp"),"successful routine rotation consumes both staged files")
 verify_loaded(e,"normal rotation")
 print("DEV03_ROUTINE_RAW normal=",JSON.stringify(e.commit_calls))
func test_routine_promotion_warning(with_backup:bool) -> void:
 var e=fixture(with_backup);var before:Array=slots();e.credits=252;var expected:Dictionary=state(e)
 e.obstruct_once=true
 check(e.save_state([],[],{"routine_probe":"promotion_obstructed"}),"routine backup-promotion failure reports committed success; previous backup="+str(with_backup))
 check(e.fault_attempts==1 and e.commit_calls.size()==1 and e.commit_calls[0].scope=="routine" and e.commit_calls[0].injected,"one real obstruction occurs inside exactly one routine commit")
 check(e.save_error.is_empty() and "备份未能更新" in e._shop_backup_warning,"routine postcommit backup failure exposes warning rather than rollback error")
 check(same(state(e),expected),"postcommit routine warning cannot roll back or repeat the caller's state change")
 var after:Array=slots()
 check(after[0]!=before[0] and same(after[1],before[1]),"routine primary is new while exact previous backup or its absence is preserved")
 check(not FileAccess.file_exists("user://savegame.tmp") and FileAccess.file_exists("user://savegame.shop-backup.tmp"),"postcommit warning leaves only the unpromoted old-primary stage")
 verify_loaded(e,"promotion warning "+str(with_backup))
 # A later explicit save persists the same state, rather than redoing a purchase
 # or settlement. Leave the one-shot flag armed to observe any accidental repeat.
 check(e.save_state([],[],{"routine_probe":"later_independent_save"}),"later explicit routine save succeeds after backup path is restored")
 check(e.fault_attempts==1 and e.commit_calls.size()==2 and not e.commit_calls[1].injected and e.commit_calls[1].ok,"later save is observed separately and never reinjects the one-shot fault")
 check(e._shop_backup_warning.is_empty() and e.save_error.is_empty(),"next normal routine save clears the obsolete promotion warning")
 check(same(state(e),expected),"later routine save leaves money, inventory, orders and settlement fields exact")
 check(FileAccess.get_file_as_bytes("user://savegame.backup.json")==after[0],"later normal save rotates the previously committed warning primary exactly")
 check(not FileAccess.file_exists("user://savegame.shop-backup.tmp"),"later normal save consumes the recovered staging path")
 verify_loaded(e,"after independent save "+str(with_backup))
 print("DEV03_ROUTINE_RAW with_backup=",with_backup," calls=",JSON.stringify(e.commit_calls))
func test_routine_precommit_failure() -> void:
 var e=fixture();var before:Array=slots();e.credits=252;var candidate:Dictionary=state(e)
 DirAccess.make_dir_absolute("user://savegame.shop-backup.tmp")
 check(not e.save_state([],[],{"routine_probe":"stage_obstructed"}),"routine failure before primary rename reports failure")
 check(e.commit_calls.size()==1 and e.commit_calls[0].scope=="routine" and not e.commit_calls[0].ok,"precommit failure still exposes the exact raw routine call")
 check(same(slots(),before),"routine precommit failure preserves both durable slots byte-for-byte")
 check(same(state(e),candidate),"save_state alone does not invent an economic rollback; caller candidate remains exact")
 check(not e.save_error.is_empty() and e._shop_backup_warning.is_empty(),"routine precommit failure yields an error and no committed-success warning")
 DirAccess.remove_absolute("user://savegame.shop-backup.tmp")
 check(e.save_state([],[],{"routine_probe":"stage_retry"}),"explicit routine retry succeeds after staging obstruction removal")
 check(e.commit_calls.size()==2 and same(state(e),candidate),"retry is one independent persistence call with no repeated state mutation")
 verify_loaded(e,"precommit retry")
 print("DEV03_ROUTINE_RAW precommit=",JSON.stringify(e.commit_calls))
