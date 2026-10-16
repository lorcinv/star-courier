extends SceneTree
## Lead-run deterministic fixture. NOT RUN by author; isolated XDG required.
const Econ=preload("res://scripts/economy.gd")
const Old=preload("res://scripts/pilot_free_profile_v1.gd")
const Force=preload("res://scripts/pilot_free_profile_v2.gd")
var passed:int=0
var failed:int=0
var craft:Array=Old.starter_design()
var pad:Array=Old.starter_launcher()
class CommitFault extends "res://scripts/economy.gd":
 var deny_commit:bool=false
 func _commit_shop_save() -> bool:
  if deny_commit:return false
  return super._commit_shop_save()
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Fresh isolated XDG_DATA_HOME required");quit(2);return
 test_upgrade_and_restart();test_failed_stale();test_accepted_retained();test_inflight_and_paid_retained();test_receipt_markers()
 clean();print("FORCE_OFFER_UPGRADE_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:check(JSON.stringify(a,"",true,true)==JSON.stringify(b,"",true,true),label)
func remove(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for file in directory.get_files():remove(path.path_join(file))
 for child in directory.get_directories():remove(path.path_join(child))
 DirAccess.remove_absolute(path)
func clean() -> void:
 for item in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","parts-retirement-v2","force-offer-upgrade-v2"]:remove("user://"+item)
func slots() -> Array:
 var result:Array=[]
 for path in ["user://savegame.json","user://savegame.backup.json"]:result.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return result
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func state(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var item:Variant=e.get(key);result[key]=item.duplicate(true) if item is Dictionary or item is Array else item
 return result
func fixture():
 clean();var e=CommitFault.new();e.enable_free_mode();e.starter_stock(craft,pad)
 # Legitimate previous v1 transition ledger must coexist with the v2 receipt.
 e.free_offer_upgrade={"schema":Econ.FREE_OFFER_UPGRADE_SCHEMA,"id":Econ.FREE_OFFER_UPGRADE_SCHEMA,"day":1,"contract_ids":["D1-A","D1-B"],"source_sha256":"a".repeat(64)}
 check(e.save_state(craft,pad,{}),"v1 offers and earlier receipt saved")
 e.credits+=1;check(e.save_state(craft,pad,{}),"second slot distinct")
 return e
func preview(e) -> Dictionary:return e.force_offer_upgrade_preview(craft,pad,{})
func confirm(e,p:Dictionary) -> Dictionary:return e.upgrade_available_force_offers_and_save(str(p.get("confirmation_token","")),craft,pad,{})
func test_upgrade_and_restart() -> void:
 var e=fixture();var before:Dictionary=state(e);var bytes:Array=slots();var p:Dictionary=preview(e)
 check(p.get("available",false) and p.get("count",0)==2,"old v1 offers with existing v1 receipt get separate preview")
 same(state(e),before,"read-only preview preserves model");same(slots(),bytes,"cancel preview leaves both files unchanged")
 check(not DirAccess.dir_exists_absolute("user://force-offer-upgrade-v2"),"cancel does not create archive")
 var result:Dictionary=confirm(e,p)
 if not result.get("ok",false):check(false,"force upgrade commits: "+str(result));return
 check(result.get("changed",false) and e.flight_mode==Force.VERSION,"explicit v2 upgrade commits once")
 for i in e.contracts.size():
  var fresh:Dictionary=e.contracts[i];var old:Dictionary=before.contracts[i]
  check(fresh.control_version==Force.VERSION and Force.validation_error(fresh).is_empty(),"new offer has exact full v2 protocol")
  for key in ["contract_id","client","cargo","reward","required","deadline","rep","weight"]:
   if old.has(key):same(fresh[key],old[key],"same quoted term or customer "+key)
 for key in ["credits","inventory","designs","settled_ids","last_settlement","history","review_state","story_state","free_offer_upgrade"]:same(e.get(key),before[key],"new receipt preserves "+key)
 check(e.force_offer_upgrade.schema==Econ.FORCE_OFFER_UPGRADE_SCHEMA,"independent v2 receipt created")
 var folder:String="user://force-offer-upgrade-v2/"+str(e.force_offer_upgrade.source_sha256)
 check(FileAccess.get_file_as_bytes(folder+"/savegame.json")==bytes[0],"v1 primary preserved raw")
 check(FileAccess.get_file_as_bytes(folder+"/savegame.backup.json")==bytes[1],"prior v1 backup preserved raw")
 var committed:Array=slots();check(not preview(e).get("available",false),"completed upgrade no longer offered")
 check(not confirm(e,p).ok,"queued duplicate confirmation cannot reauthor");same(slots(),committed,"duplicate changes neither slot")
 var loaded=Econ.new();var raw:Dictionary=loaded.load_state(true)
 check(not loaded.review_load_blocked,"both transition receipts reload")
 same(loaded.free_offer_upgrade,before.free_offer_upgrade,"earlier v1 receipt never overwritten")
 same(loaded.force_offer_upgrade,e.force_offer_upgrade,"v2 receipt survives restart")
 check(loaded.save_state(raw.design,raw.launcher,raw.settings),"ordinary save keeps both markers")
func test_failed_stale() -> void:
 var e=fixture();var p:Dictionary=preview(e);var bytes:Array=slots();var before:Dictionary=state(e)
 var stale:Dictionary=p.duplicate(true);stale.confirmation_token="stale";check(not confirm(e,stale).ok,"wrong whole-snapshot token rejected")
 same(slots(),bytes,"wrong token never writes slots");same(state(e),before,"wrong token never mutates state")
 e.deny_commit=true;check(not confirm(e,p).ok,"pre-rename save failure rejected")
 same(slots(),bytes,"failed commit preserves both files");same(state(e),before,"failed commit preserves model")
 e.deny_commit=false;check(confirm(e,p).ok,"confirmed failed attempt safely retries")
 e=fixture();p=preview(e);e.inventory["beam"]+=1;check(not confirm(e,p).ok,"unsaved unrelated inventory invalidates confirmation")
 e=fixture();p=preview(e);e.credits+=1;check(e.save_state(craft,pad,{}),"changed snapshot persisted")
 check(not confirm(e,p).ok,"saved unrelated money invalidates original token")
func test_accepted_retained() -> void:
 var e=fixture();check(e.accept_contract("D1-A").ok,"v1 accepted before optional upgrade");check(e.save_state(craft,pad,{}),"v1 acceptance persisted")
 var accepted:Dictionary=e.active_contract().duplicate(true);var before:Dictionary=state(e);var p:Dictionary=preview(e)
 check(p.get("available",false) and p.get("count",0)==1 and p.contract_ids==["D1-B"],"only unaccepted second v1 offer eligible")
 check(not e.accepted_free_swap_preview().get("available",false),"accepted v1 retains original rather than implicit exchange")
 check(confirm(e,p).ok,"available offer upgraded alongside retained accepted route")
 same(e.active_contract(),accepted,"accepted v1 route remains byte-equivalent")
 for key in ["active_contract_id","credits","inventory","settled_ids","story_state"]:same(e.get(key),before[key],"accepted coexistence preserves "+key)
 check(not e.parts_retirement_preview(craft,pad,{}).get("available",false),"parts remain deferred while accepted v1 retained")
func test_inflight_and_paid_retained() -> void:
 var e=fixture();e.accept_contract("D1-A");e.mark_cargo_loaded("D1-A");check(e.begin_dispatch(craft,pad).ok,"old v1 dispatch starts")
 check(e.save_state(craft,pad,{}),"old snapshot saved");var flight:Dictionary=e.in_flight.duplicate(true);var bytes:Array=slots()
 check(not preview(e).get("available",false),"inflight prohibits even available-offer replacement")
 same(e.in_flight,flight,"old replay remains exact");same(slots(),bytes,"inflight preview has no writes")
 var result:Dictionary=e.settle_contract_and_save("D1-A",{"integrity":1.0,"energy_used":100.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},10.0,true,craft,pad,{})
 if not result.get("ok",false):check(false,"actual v1 receipt fixture settles");return
 var receipts:Dictionary=e.settled_ids.duplicate(true);var history:Array=e.history.duplicate(true);var balance:int=e.credits
 var p:Dictionary=preview(e);check(p.get("available",false),"after old settlement remaining available v1 can upgrade")
 check(confirm(e,p).ok,"post-settlement v2 upgrade commits")
 same(e.settled_ids,receipts,"old paid receipt never rewritten");same(e.history,history,"old paid history never rewritten");check(e.credits==balance,"no repricing settled money")
func test_receipt_markers() -> void:
 var e=fixture()
 if not confirm(e,preview(e)).get("ok",false):check(false,"receipt fixture upgrade");return
 var valid:Dictionary=disk()
 for mode in ["missing_receipt","missing_marker","future_schema","bad_hash","duplicate_order"]:
  var bad:Dictionary=valid.duplicate(true)
  if mode=="missing_receipt":bad.erase("force_offer_upgrade")
  elif mode=="missing_marker":bad.settings.erase("force_offer_upgrade_schema")
  elif mode=="future_schema":bad.force_offer_upgrade.schema="future-v99"
  elif mode=="bad_hash":bad.force_offer_upgrade.orders[0].original_order_sha256="bad"
  else:bad.force_offer_upgrade.orders[1]=bad.force_offer_upgrade.orders[0].duplicate(true)
  var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(bad,"",true,true));file.close()
  var raw:Array=slots();var restored=Econ.new();restored.load_state(true)
  check(restored.review_load_blocked,"strict force marker/receipt blocks fallback "+mode)
  same(slots(),raw,"blocked load remains read-only "+mode)
