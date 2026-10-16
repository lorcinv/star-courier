extends SceneTree
## Source fixture for lead execution only, under an isolated XDG_DATA_HOME.
const Econ=preload("res://scripts/economy.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Free=preload("res://scripts/pilot_free_profile_v1.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated XDG_DATA_HOME required.");quit(2);return
 test_deferred_read_and_legacy_default()
 test_negative_transition_and_interruption()
 test_failed_recovery_keeps_empty_contracts()
 test_existing_order_and_flight_unchanged()
 test_legacy_v1_empty_boundary()
 clear_files();print("DEFERRED_CONTRACT_LOAD passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft() -> Array:return Extreme.starter_design()
func pad() -> Array:return Extreme.starter_launcher()
func state(e) -> Dictionary:
 var value:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var field:Variant=e.get(key);value[key]=field.duplicate(true) if field is Array or field is Dictionary else field
 return value
func remove_tree(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var d=DirAccess.open(path)
 for name in d.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in d.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","economy-recovery-v1"]:remove_tree("user://"+name)
func bytes() -> PackedByteArray:return FileAccess.get_file_as_bytes("user://savegame.json")
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_primary(value:Dictionary) -> void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(value,"",true,true));file.close()
func empty_old_fixture(credits:int=260):
 clear_files();var e=Econ.new();e.enable_extreme_mode();e.starter_stock(craft(),pad())
 e.credits=credits;e.contracts=[];e.story_state={};e.active_contract_id="";e.last_trials={}
 check(e.save_state(craft(),pad(),{}),"genuinely empty old morning is durable")
 return e

func test_deferred_read_and_legacy_default() -> void:
 empty_old_fixture();var original:PackedByteArray=bytes()
 var deferred=Econ.new();var raw:Dictionary=deferred.load_state(true)
 check(not raw.is_empty() and not deferred.review_load_blocked,"deferred load validates existing save")
 check(deferred.contracts.is_empty() and raw.contracts.is_empty(),"actual Continue leaves empty old contract boundary empty")
 check(deferred.flight_mode==Extreme.CONTROL_VERSION and deferred.credits==260,"read neither upgrades mode nor changes money")
 check(deferred.settled_ids.is_empty() and deferred.history.is_empty() and deferred.in_flight.is_empty(),"read invents no financial or dispatch facts")
 check(bytes()==original and not FileAccess.file_exists("user://savegame.backup.json"),"deferred read neither rewrites primary nor rotates backup")
 var again=Econ.new();again.load_state(true)
 check(again.contracts.is_empty() and bytes()==original,"repeated deferred reads remain side-effect free")
 var legacy=Econ.new();legacy.load_state()
 check(legacy.contracts.size()==2 and legacy.contracts[0].control_version==Extreme.CONTROL_VERSION,"no-argument API retains old automatic authoring")
 check(bytes()==original,"legacy automatic in-memory authoring still does not write on load")
 var explicit=Econ.new();explicit.load_state(false)
 same(explicit.contracts,legacy.contracts,"explicit false matches old default exactly")

func test_negative_transition_and_interruption() -> void:
 empty_old_fixture(-1580);var original:PackedByteArray=bytes()
 var e=Econ.new();e.load_state(true)
 check(e.credits==-1580 and e.contracts.is_empty(),"negative Continue is read before authoring")
 var result:Dictionary=e.recover_legacy_debt_and_save(craft(),pad(),{})
 check(result.ok and result.changed and e.credits==0,"one-time recovery commits exact old debt")
 check(e.contracts.is_empty() and disk().contracts.is_empty(),"subsidy does not author legacy or free orders as a side effect")
 var archived:String="user://economy-recovery-v1/"+str(e.economic_recovery.source_sha256)+"/savegame.json"
 check(FileAccess.get_file_as_bytes(archived)==original,"backup retains original negative empty-order save byte-for-byte")
 # Stop here models interruption between subsidy and explicit free authoring.
 var restart=Econ.new();restart.load_state(true)
 check(restart.credits==0 and restart.contracts.is_empty() and not restart.economic_recovery.is_empty(),"restart after subsidy preserves empty boundary and grant ledger")
 check(not restart.recover_legacy_debt_and_save(craft(),pad(),{}).changed,"interrupted continuation never grants again")
 restart.enable_free_mode()
 check(restart.contracts.is_empty(),"opting into free mode does not implicitly author")
 restart.enable_story_mode()
 check(restart.contracts.size()==2,"explicit post-recovery story/startup boundary authors two orders")
 for order in restart.contracts:
  check(order.control_version==Free.CONTROL_VERSION and order.economy_policy==Econ.FREE_ECONOMY_POLICY,"only new free insured contracts appear after recovery")
 check(restart.save_state(craft(),pad(),{}),"free authored batch persists normally")
 var final_load=Econ.new();final_load.load_state(true)
 same(final_load.contracts,restart.contracts,"saved new batch reloads without reauthoring")
 check(final_load.credits==0 and final_load.economic_recovery.grant==1580,"final restart retains one exact subsidy")

func test_failed_recovery_keeps_empty_contracts() -> void:
 empty_old_fixture(-471);var original:PackedByteArray=bytes();var e=Econ.new();e.load_state(true)
 var before:Dictionary=state(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var failed_save:Dictionary=e.recover_legacy_debt_and_save(craft(),pad(),{})
 check(not failed_save.ok,"blocked final save stops the continuation transition")
 same(state(e),before,"write failure rolls back balance/grant and leaves contracts empty")
 check(bytes()==original,"failed recovery leaves original negative primary exact")
 var reopened=Econ.new();reopened.load_state(true)
 check(reopened.credits==-471 and reopened.contracts.is_empty() and reopened.economic_recovery.is_empty(),"restart after failed recovery has no half-grant or old automatic offers")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(reopened.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"explicit retry commits once against the same archive")
 reopened.enable_free_mode();reopened.ensure_contracts()
 check(reopened.contracts.size()==2 and reopened.contracts[0].control_version==Free.CONTROL_VERSION,"only successful recovery proceeds to explicit free authoring")
 # Independent archive failure must stop before all mutations as well.
 empty_old_fixture(-25);e=Econ.new();e.load_state(true);before=state(e)
 var barrier=FileAccess.open("user://economy-recovery-v1",FileAccess.WRITE);barrier.store_string("blocked");barrier.close()
 check(not e.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"archive failure stops recovery before authoring")
 same(state(e),before,"archive failure leaves old negative empty state unchanged")

func test_existing_order_and_flight_unchanged() -> void:
 clear_files();var e=Econ.new();e.enable_extreme_mode();e.starter_stock(craft(),pad());e.accept_contract("D1-A")
 check(e.save_state(craft(),pad(),{}),"existing accepted old fixture saves")
 var accepted:Dictionary=disk();var original:PackedByteArray=bytes();var loaded=Econ.new();loaded.load_state(true)
 same(loaded.contracts,accepted.contracts,"deferred read preserves existing accepted and available offers")
 check(loaded.active_contract_id=="D1-A" and bytes()==original,"accepted identity and durable bytes unchanged")
 check(loaded.begin_dispatch(craft(),pad()).ok and loaded.save_state(craft(),pad(),{}),"old committed flight saves")
 var paid:Dictionary=disk();original=bytes();var resumed=Econ.new();resumed.load_state(true)
 same(resumed.in_flight,paid.in_flight,"old paid replay snapshot unchanged by deferred load")
 same(resumed.contracts,paid.contracts,"old paid contract identity unchanged")
 check(bytes()==original,"deferred old-flight restore performs no writes")

func test_legacy_v1_empty_boundary() -> void:
 empty_old_fixture(-80);var old:Dictionary=disk();old.version=1;old.erase("workshop_tier");write_primary(old)
 var original:PackedByteArray=bytes();var e=Econ.new();e.load_state(true)
 check(not e.review_load_blocked and e.contracts.is_empty() and e.credits==-80,"v1 reset-to-morning compatibility also respects authoring deferral")
 check(bytes()==original,"legacy v1 deferred read is still read-only")
 check(e.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"v1 debt recovery also commits before new authoring")
 e.enable_free_mode();e.ensure_contracts()
 check(e.contracts.size()==2 and e.contracts[0].control_version==Free.CONTROL_VERSION,"explicit later authoring owns the new protocol decision")
