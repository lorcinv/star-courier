extends SceneTree
## Lead-only engine fixture; use an isolated XDG_DATA_HOME, never a real save.
const Econ=preload("res://scripts/economy.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Free=preload("res://scripts/pilot_free_profile_v1.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated XDG_DATA_HOME required.");quit(2);return
 test_confirm_and_restart(false);test_confirm_and_restart(true)
 test_cancel_and_stale();test_write_rollback();test_backup_failure()
 test_forbidden_states();test_unknown_record();test_second_old_order();test_abort_protocol_validation()
 clear_files();print("ACCEPTED_FREE_SWAP passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft() -> Array:return Extreme.starter_design()
func pad() -> Array:return Extreme.starter_launcher()
func state(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func remove_tree(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var d=DirAccess.open(path)
 for name in d.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in d.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","economy-recovery-v1"]:remove_tree("user://"+name)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_primary(value:Dictionary) -> void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(value,"",true,true));file.close()
func fixture(loaded:bool=false):
 clear_files();var e=Econ.new();e.enable_extreme_mode();e.starter_stock(craft(),pad());e.enable_story_mode()
 check(e.accept_contract("D1-A").ok,"old order accepted")
 e.mark_story_seen("D1-A","D1-A/accept")
 if loaded:check(e.mark_cargo_loaded("D1-A").ok,"same cargo already loaded")
 e.last_trials={"D1-A":{"profit":23,"old_prediction":true},"unrelated":{"keep":true}}
 check(e.save_state(craft(),pad(),{}),"exact accepted original is durable")
 return e
func confirm(e,preview:Dictionary) -> Dictionary:
 return e.swap_accepted_legacy_for_free_and_save(str(preview.contract_id),str(preview.order_sha256),craft(),pad(),{})

func test_confirm_and_restart(loaded:bool) -> void:
 var e=fixture(loaded);var before:Dictionary=state(e);var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var old:Dictionary=e.active_contract().duplicate(true);var preview:Dictionary=e.accepted_free_swap_preview()
 check(preview.available and preview.contract_id=="D1-A" and preview.cargo_loaded==loaded,"preview names exact accepted order and cargo state")
 check(preview.order_sha256.length()==64 and preview.reward==220,"preview freezes old snapshot and discloses new fee")
 var result:Dictionary=confirm(e,preview)
 check(result.ok and result.changed and result.contract_id=="D1-A","explicit confirmation commits one replacement")
 var fresh:Dictionary=e.active_contract()
 check(fresh.status=="accepted" and fresh.control_version==Free.CONTROL_VERSION and fresh.economy_policy==Econ.FREE_ECONOMY_POLICY,"same active identity now uses complete new free policy")
 for key in ["contract_id","client","cargo","appearance_id","appearance_seed"]:same(fresh[key],old[key],"preserve same customer/parcel identity "+key)
 check(e.is_cargo_loaded("D1-A")==loaded,"preserve the same box's actual loading state")
 check(not e.last_trials.has("D1-A") and e.last_trials.unrelated.keep,"only old route trial cache is cleared")
 for key in ["credits","reputation","jobs_today","deliveries","inventory","history","settled_ids","last_settlement","review_state","story_state"]:same(e.get(key),before[key],"swap does not manufacture or rewrite "+key)
 same(e.contracts[1],before.contracts[1],"unaccepted other old order unchanged")
 var record:Dictionary=e.accepted_free_swaps.swaps["D1-A"]
 var archived:String="user://economy-recovery-v1/"+str(record.source_sha256)+"/savegame.json"
 check(FileAccess.get_file_as_bytes(archived)==bytes,"exact accepted pre-swap source archived")
 check(record.original_order_sha256==preview.order_sha256 and record.cargo_loaded==loaded,"ledger identifies consented original and loading state")
 var committed:Dictionary=state(e);check(not confirm(e,preview).ok,"same confirmation cannot replace again")
 same(state(e),committed,"duplicate confirm does not alter money, history or state")
 var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 check(not restored.review_load_blocked and not restored.accepted_free_swap_preview().available,"restart retains swap once-only identity")
 same(restored.accepted_free_swaps,e.accepted_free_swaps,"swap ledger survives JSON round trip")
 check(restored.active_contract_id=="D1-A" and restored.is_cargo_loaded()==loaded,"active identity and actual box state survive restart")
 if not loaded:check(restored.mark_cargo_loaded("D1-A").ok,"ordinary loading remains required if not done earlier")
 check(restored.begin_dispatch(craft(),pad()).ok,"new order can formally dispatch")
 check(restored.in_flight.control_version==Free.CONTROL_VERSION and restored.in_flight.input_schema==Free.INPUT_SCHEMA,"new dispatch uses exact free replay schema")
 check(restored.settled_ids.is_empty() and restored.credits==before.credits,"dispatch alone invents no payment or review")

func test_cancel_and_stale() -> void:
 var e=fixture(false);var before:Dictionary=state(e);var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var preview:Dictionary=e.accepted_free_swap_preview()
 same(state(e),before,"preview/cancel changes nothing")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"cancel leaves exact durable bytes")
 check(not e.swap_accepted_legacy_for_free_and_save("D1-B",preview.order_sha256,craft(),pad(),{}).ok,"confirmation cannot target another task")
 check(not e.swap_accepted_legacy_for_free_and_save("D1-A","stale",craft(),pad(),{}).ok,"stale token rejected")
 same(state(e),before,"bad confirmations do not mutate model")
 e.mark_cargo_loaded("D1-A")
 check(not confirm(e,preview).ok,"loading changes old snapshot and invalidates outstanding confirmation")
 var unsaved:Dictionary=e.accepted_free_swap_preview()
 check(not confirm(e,unsaved).ok,"unsaved old acceptance/loading cannot be replaced without an exact durable original")
 check(e.save_state(craft(),pad(),{}),"changed cargo loading saved")
 check(confirm(e,e.accepted_free_swap_preview()).ok,"fresh explicit confirmation succeeds on durable state")

func test_write_rollback() -> void:
 var e=fixture(true);var preview:Dictionary=e.accepted_free_swap_preview();var before:Dictionary=state(e)
 var primary:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var backup:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.backup.json") if FileAccess.file_exists("user://savegame.backup.json") else PackedByteArray()
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not confirm(e,preview).ok,"final write failure rejects swap")
 same(state(e),before,"rollback restores accepted route/cargo/trial/ledger plus every shop field")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==primary,"failed swap preserves primary")
 if not backup.is_empty():check(FileAccess.get_file_as_bytes("user://savegame.backup.json")==backup,"failed swap preserves previous backup")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(confirm(e,preview).ok,"same confirmed operation safely retries after recoverable save failure")

func test_backup_failure() -> void:
 var e=fixture();var before:Dictionary=state(e);var preview:Dictionary=e.accepted_free_swap_preview()
 var file=FileAccess.open("user://economy-recovery-v1",FileAccess.WRITE);file.store_string("blocked");file.close()
 check(not confirm(e,preview).ok,"missing immutable backup blocks swap")
 same(state(e),before,"backup failure changes no old acceptance or finances")

func test_forbidden_states() -> void:
 var e=fixture();var preview:Dictionary=e.accepted_free_swap_preview()
 e.mark_cargo_loaded("D1-A");e.begin_dispatch(craft(),pad())
 var flight:Dictionary=state(e)
 check(not e.accepted_free_swap_preview().available and not confirm(e,preview).ok,"paid in-flight trip cannot be swapped")
 same(state(e),flight,"in-flight refusal keeps original replay exact")
 e=fixture();e.phase="night";check(not e.accepted_free_swap_preview().available,"night is not a waiting accepted swap")
 e=fixture();e.active_contract().status="settled";check(not e.accepted_free_swap_preview().available,"settled order cannot become a new delivery")
 e=fixture();e.settled_ids["D1-A"]={"keep":true};check(not e.accepted_free_swap_preview().available,"existing ledger ID cannot be reused")
 e=fixture();e.active_contract().control_version="future-v99";check(not e.accepted_free_swap_preview().available,"unknown protocol remains opaque")
 e=fixture();e.contracts.append(e.contracts[0].duplicate(true));check(not e.accepted_free_swap_preview().available,"ambiguous duplicate active ID fails closed")

func test_unknown_record() -> void:
 var e=fixture();check(confirm(e,e.accepted_free_swap_preview()).ok,"unknown-record fixture swaps")
 var valid:Dictionary=disk()
 var changed:Dictionary=valid.duplicate(true);changed.accepted_free_swaps.schema="future";write_primary(changed)
 var restored=Econ.new();restored.load_state();check(restored.review_load_blocked,"future accepted swap ledger blocks fallback")
 changed=valid.duplicate(true);changed.accepted_free_swaps.swaps["D1-A"].original_order_sha256="bad";write_primary(changed)
 restored=Econ.new();restored.load_state();check(restored.review_load_blocked,"invalid old-order digest blocks loading")
 changed=valid.duplicate(true);changed.erase("accepted_free_swaps");write_primary(changed)
 restored=Econ.new();restored.load_state();check(restored.review_load_blocked,"writer marker prevents dropped transition ledger")

func test_second_old_order() -> void:
 var e=fixture(true);check(confirm(e,e.accepted_free_swap_preview()).ok,"first old accepted order swapped")
 check(e.begin_dispatch(craft(),pad()).ok,"first free dispatch")
 var result:Dictionary=e.settle_contract_and_save("D1-A",{"integrity":1.0,"energy_used":100.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},10.0,true,craft(),pad(),{})
 check(result.ok,"first free order truly settled")
 check(e.accept_contract_and_save("D1-B",craft(),pad(),{}).ok,"remaining old ordinary B accepted by player")
 var before:Dictionary=e.settled_ids.duplicate(true)
 check(confirm(e,e.accepted_free_swap_preview()).ok,"second distinct old accepted order can receive its own explicit confirmation")
 check(e.accepted_free_swaps.swaps.size()==2,"transition ledger bounds at two original daily orders")
 same(e.settled_ids,before,"second swap leaves actual earlier delivery ledger unchanged")

func test_abort_protocol_validation() -> void:
 var e=Econ.new();e.enable_free_mode();e.starter_stock(craft(),pad());e.accept_contract("D1-A");e.begin_dispatch(craft(),pad())
 for tick in [0,37]:
  var snapshot:Dictionary=e.in_flight.duplicate(true);snapshot.ticks=tick;snapshot.elapsed=float(tick)/60.0;snapshot.terminal_intent="abort"
  check(Econ.replay_protocol_error(snapshot).is_empty(),"exact free abort intent survives checkpoint at tick %d"%tick)
  var restored:Dictionary=JSON.parse_string(JSON.stringify(snapshot,"",true,true))
  check(Econ.replay_protocol_error(restored).is_empty(),"free abort validates after JSON at tick %d"%tick)
  for invalid in ["failed","success","",true,0,null]:
   var bad:Dictionary=snapshot.duplicate(true);bad.terminal_intent=invalid
   check(not Econ.replay_protocol_error(bad).is_empty(),"free terminal intent rejects non-exact abort %s"%str(invalid))
  var legacy_input:Dictionary=snapshot.duplicate(true);legacy_input.input_commands=[{"tick":0,"axis_q":0,"boost":false,"active":false}]
  check(not Econ.replay_protocol_error(legacy_input).is_empty(),"abort does not relax the new two-axis input schema")
  var wrong:Dictionary=snapshot.duplicate(true);wrong.route.control_version="pilot-v3"
  check(not Econ.replay_protocol_error(wrong).is_empty(),"abort does not relax coupled route identity")
 var old=Econ.new();old.enable_extreme_mode();old.starter_stock(craft(),pad());old.accept_contract("D1-A");old.begin_dispatch(craft(),pad())
 var legacy:Dictionary=old.in_flight.duplicate(true);legacy.terminal_intent="abort"
 check(not Econ.replay_protocol_error(legacy).is_empty(),"legacy ordinary replay keeps its original terminal-intent rejection")
