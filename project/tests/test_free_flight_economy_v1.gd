extends SceneTree
## Lead-owned engine test. Requires an isolated XDG_DATA_HOME; never production.
const Econ=preload("res://scripts/economy.gd")
const Free=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Reviews=preload("res://scripts/customer_reviews_v3.gd")
const OldReviews=preload("res://scripts/customer_reviews_v2.gd")
var passed:int=0
var failed:int=0

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("Use an isolated XDG_DATA_HOME for free-flight economy tests.");quit(2);return
 clear_files()
 test_authoring_and_frozen_legacy()
 test_quotes_and_real_costs()
 test_settlement_restart_and_recovery()
 test_save_failure()
 test_debt_migration()
 test_debt_migration_failures()
 test_unknown_recovery_record()
 test_available_offer_upgrade()
 clear_files()
 print("FREE_FLIGHT_ECONOMY passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)

func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft() -> Array:return Extreme.starter_design()
func pad() -> Array:return Extreme.starter_launcher()
func telemetry(integrity:float=1.0,energy:float=8040.0,repair:float=0.0,lost:float=270.0) -> Dictionary:
 return {"integrity":integrity,"energy_used":energy,"ammo_cost":0.0,"repair_cost":repair,"lost_cost":lost}
func economy():
 var e=Econ.new();e.enable_free_mode();e.starter_stock(craft(),pad());e.enable_story_mode();return e
func begin(e,id:String="D1-A") -> void:
 check(e.accept_contract(id).ok,"accept "+id);check(e.mark_cargo_loaded(id).ok,"load "+id)
 check(e.begin_dispatch(craft(),pad()).ok,"dispatch "+id)
func snapshot(e) -> Dictionary:
 var out:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);out[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return out
func remove_tree(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for name in directory.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in directory.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","economy-recovery-v1"]:remove_tree("user://"+name)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_primary(value:Dictionary) -> void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(value,"",true,true));file.close()

func test_authoring_and_frozen_legacy() -> void:
 var e=economy()
 check(e.contracts.size()==2,"two real first deliveries")
 for order in e.contracts:
  check(order.control_version==Free.CONTROL_VERSION and order.economy_policy==Econ.FREE_ECONOMY_POLICY,"new ordinary policy is explicit")
  check(order.reward==220 and order.weight==1.0 and order.id==0,"first and follow-up are light ground jobs with real220 fee")
  check(Econ.route_validation_error(order).is_empty(),"new ordinary order validates")
 var current:Dictionary=snapshot(e);e.enable_free_mode();e.ensure_contracts()
 same(snapshot(e),current,"enabling and displaying never reroll offers or grant cash")
 var legacy=Econ.new();legacy.enable_extreme_mode();legacy.starter_stock(craft(),pad());legacy.enable_story_mode()
 var original:Array=legacy.contracts.duplicate(true);begin(legacy)
 var flight:Dictionary=legacy.in_flight.duplicate(true);var committed:Array=legacy.contracts.duplicate(true)
 legacy.enable_free_mode()
 same(legacy.contracts,committed,"legacy accepted and remaining available offers stay exact")
 same(legacy.in_flight,flight,"legacy paid snapshot stays exact")
 var old:Dictionary=original[0]
 var quote:Dictionary=legacy.estimate_delivery(old,telemetry(1.0,5080.0,4.0,10.0),32.13333333333215,true)
 check(quote.income==164 and quote.energy==127 and quote.profit==23,"observed legacy D1 bill remains164−127−4−10=23")
 check(not quote.has("insurance_coverage"),"old ledger has no retrospective insurance")

func test_quotes_and_real_costs() -> void:
 var e=economy();var order:Dictionary=e.contracts[0]
 var early:Dictionary=e.estimate_delivery(order,telemetry(1.0,5080.0,18.0,10.0),12.0,true)
 var slow:Dictionary=e.estimate_delivery(order,telemetry(1.0,5080.0,18.0,10.0),6000.0,true)
 same(early,slow,"taking time creates no reward or reputation pressure")
 check(slow.income==220 and slow.actual_costs==155 and slow.insurance_coverage==125 and slow.charged_costs==30 and slow.profit==190,"modest-damage costs stay real and success yields190")
 check(slow.energy==127 and slow.repairs==18 and slow.lost==10,"no fabricated energy or erased damaged parts")
 var damaged:Dictionary=e.estimate_delivery(order,telemetry(.01),6000.0,true)
 check(damaged.income>=110 and damaged.income<220 and damaged.profit>=80,"any living delivered cargo earns service fee while condition reduces reward")
 var failed_quote:Dictionary=e.estimate_delivery(order,telemetry(),43.7,false)
 check(failed_quote.income==0 and failed_quote.actual_costs==471 and failed_quote.insurance_coverage==446 and failed_quote.profit==-25,"actual user471 cost would produce25 player liability only on new policy")
 e.credits=3;var low:Dictionary=e.estimate_delivery(order,telemetry(),43.7,false)
 check(low.charged_costs==3 and low.insurance_coverage==468 and low.profit==-3,"low-cash failure cannot create negative balance")
 e.credits=0;var empty:Dictionary=e.estimate_delivery(order,telemetry(),43.7,false)
 check(empty.charged_costs==0 and empty.profit==0 and empty.insurance_coverage==471,"zero-cash failure cannot manufacture positive cash")

func test_settlement_restart_and_recovery() -> void:
 clear_files();var e=economy();e.credits=3
 var inventory:Dictionary=e.inventory.duplicate(true);var designs:Array=craft()
 begin(e)
 check(Econ.replay_protocol_error(e.in_flight).is_empty(),"new initial two-axis replay validates")
 var result:Dictionary=e.settle_contract_and_save("D1-A",telemetry(),43.7,false,designs,pad(),{})
 check(result.ok and e.credits==0 and e.jobs_today==1 and e.deliveries==0,"failure is atomic and floor0 is real balance")
 same(e.inventory,inventory,"insurance never adds, duplicates or refunds inventory")
 var durable:Dictionary=disk();var before:Dictionary=snapshot(e)
 check(not e.settle_contract_and_save("D1-A",telemetry(),43.7,false,designs,pad(),{}).ok,"second settlement refused")
 same(snapshot(e),before,"duplicate failure cannot reclaim insurer payment")
 var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 check(not restored.review_load_blocked and restored.credits==0,"insured result survives restart")
 same(restored.settled_ids,e.settled_ids,"financial fields and exact coverage survive restart")
 begin(restored,"D1-B")
 var follow:Dictionary=restored.settle_contract_and_save("D1-B",telemetry(.5,4000.0,14.0,0.0),6000.0,true,designs,pad(),{})
 check(follow.ok and restored.credits>=80 and restored.deliveries==1,"restored owned starter can earn after failure without buying parts")
 check(restored.close_day().ok and restored.next_day().ok,"failure and follow-up advance to next morning")
 check(restored.contracts[0].id==0 and restored.contracts[1].id==0,"insufficient working cash yields light recovery offers")
 var feed:Array=restored.customer_reviews()
 check(feed.size()==2,"both formal outcomes publish once")
 for review in feed:
  if review.success:check(not "晚" in review.body and not "按时" in review.body and review.category=="damaged","free review reports condition without lateness")
 check(restored.save_state(designs,pad(),{}),"published free reviews serialize")
 var again=Econ.new();again.load_state();check(not again.review_load_blocked,"published free reviews reload")
 check(not OldReviews.opaque_error(disk()).is_empty(),"old review reader blocks new explicit template rather than reinterpreting")
 same(durable.settled_ids["D1-A"],again.settled_ids["D1-A"],"next day keeps original failed receipt untouched")

func test_save_failure() -> void:
 clear_files();var e=economy();begin(e);check(e.save_state(craft(),pad(),{}),"paid initial state saved")
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json");var before:Dictionary=snapshot(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var rejected:Dictionary=e.settle_contract_and_save("D1-A",telemetry(),43.7,false,craft(),pad(),{})
 check(not rejected.ok,"blocked temp write rejects insured settlement")
 same(snapshot(e),before,"failed write restores balance coverage history review and dispatch")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"failed settlement preserves durable paid state")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.settle_contract_and_save("D1-A",telemetry(),43.7,false,craft(),pad(),{}).ok and e.credits==235,"retry charges exactly once")
 var low=economy();low.phase="night";low.credits=0;var unchanged:Dictionary=low.inventory.duplicate(true)
 check(not low.buy_part("battery",{"price":45}).ok,"insurance does not pay for new parts")
 same(low.inventory,unchanged,"unaffordable part cannot be acquired free")
 check(not low.research_upgrade().ok,"research still requires actual cash")

func debt_fixture():
 clear_files();var old=Econ.new();old.enable_extreme_mode();old.starter_stock(craft(),pad());old.credits=-1580
 check(old.save_state(craft(),pad(),{}),"legacy negative fixture saved")
 var loaded=Econ.new();loaded.load_state();return loaded
func test_debt_migration() -> void:
 var e=debt_fixture();var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var old_contracts:Array=e.contracts.duplicate(true);var old_receipts:Dictionary=e.settled_ids.duplicate(true)
 var result:Dictionary=e.recover_legacy_debt_and_save(craft(),pad(),{})
 check(result.ok and result.changed and result.recovery_grant==1580 and e.credits==0,"negative legacy balance grants only exact debt to0")
 check(e.economic_recovery.prior_credits==-1580 and e.economic_recovery.grant==1580,"migration has one explicit versioned grant ledger")
 var archive:String="user://economy-recovery-v1/"+str(e.economic_recovery.source_sha256)+"/savegame.json"
 check(FileAccess.get_file_as_bytes(archive)==original,"immutable pre-recovery primary is byte exact")
 same(e.contracts,old_contracts,"migration never rewrites old offers")
 same(e.settled_ids,old_receipts,"migration never rewrites old delivery ledger")
 var second:Dictionary=e.recover_legacy_debt_and_save(craft(),pad(),{})
 check(second.ok and not second.changed and e.credits==0,"repeat migration cannot award another grant")
 var again=Econ.new();again.load_state()
 check(not again.review_load_blocked and again.credits==0,"recovery record and balance reload together")
 check(not again.recover_legacy_debt_and_save(craft(),pad(),{}).changed,"restart migration is idempotent")
 again.credits=-1;check(not again.recover_legacy_debt_and_save(craft(),pad(),{}).changed and again.credits==-1,"one-time record cannot refill later debt")
 clear_files();var positive=economy();check(positive.save_state(craft(),pad(),{}),"positive fixture saves")
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 check(not positive.recover_legacy_debt_and_save(craft(),pad(),{}).changed and positive.credits==260,"positive legacy/current money unchanged")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"positive no-op does not rotate or write save")

func test_debt_migration_failures() -> void:
 var e=debt_fixture();var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json");var before:Dictionary=snapshot(e)
 var barrier=FileAccess.open("user://economy-recovery-v1",FileAccess.WRITE);barrier.store_string("block");barrier.close()
 check(not e.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"backup directory failure blocks migration")
 same(snapshot(e),before,"backup failure changes no model state")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==original,"backup failure preserves primary")
 remove_tree("user://economy-recovery-v1");DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"final save failure blocks migration")
 same(snapshot(e),before,"failed final save rolls grant and balance back together")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==original,"failed final save preserves primary")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.recover_legacy_debt_and_save(craft(),pad(),{}).ok and e.credits==0,"retry reuses identical archive and grants once")
 var deferred=debt_fixture();deferred.accept_contract("D1-A");deferred.begin_dispatch(craft(),pad())
 check(deferred.recover_legacy_debt_and_save(craft(),pad(),{}).deferred and deferred.credits==-1580,"old in-flight route defers migration until its real result")

func test_unknown_recovery_record() -> void:
 var e=debt_fixture();check(e.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"record validation fixture migrates")
 var valid:Dictionary=disk()
 for field in ["schema","id","grant","source_sha256"]:
  var corrupt:Dictionary=valid.duplicate(true)
  corrupt.economic_recovery[field]="future" if field!="grant" else 1581
  write_primary(corrupt);var restored=Econ.new();restored.load_state()
  check(restored.review_load_blocked,"invalid recovery "+field+" blocks rather than fallback and duplicate grant")
 var dropped:Dictionary=valid.duplicate(true);dropped.erase("economic_recovery");write_primary(dropped)
 var lost=Econ.new();lost.load_state();check(lost.review_load_blocked,"retained settings detect dropped grant ledger")

func test_available_offer_upgrade() -> void:
 var e=debt_fixture()
 check(e.recover_legacy_debt_and_save(craft(),pad(),{}).ok,"upgrade follows committed debt recovery")
 var before:Dictionary=snapshot(e);var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var preview:Dictionary=e.free_offer_upgrade_preview()
 check(preview.available and preview.count==2,"preview identifies two available old ordinary offers")
 same(snapshot(e),before,"preview/cancel changes nothing")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"preview/cancel never writes")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.upgrade_available_free_offers_and_save(craft(),pad(),{}).ok,"upgrade final-save failure is rejected")
 same(snapshot(e),before,"upgrade write failure restores exact old offers and metadata")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"upgrade failure leaves primary exact")
 DirAccess.remove_absolute("user://savegame.tmp")
 var result:Dictionary=e.upgrade_available_free_offers_and_save(craft(),pad(),{})
 check(result.ok and result.changed and result.contract_ids==["D1-A","D1-B"],"confirmed upgrade swaps only two unaccepted IDs")
 check(e.credits==0 and e.reputation==before.reputation and e.jobs_today==before.jobs_today,"upgrade has no hidden fee reputation loss or free money")
 same(e.inventory,before.inventory,"upgrade changes no owned hardware")
 same(e.settled_ids,before.settled_ids,"upgrade preserves every old financial receipt")
 for order in e.contracts:check(order.control_version==Free.CONTROL_VERSION and order.economy_policy==Econ.FREE_ECONOMY_POLICY and order.reward==220,"upgraded orders have complete fresh free policy")
 var archive:String="user://economy-recovery-v1/"+str(e.free_offer_upgrade.source_sha256)+"/savegame.json"
 check(FileAccess.get_file_as_bytes(archive)==bytes,"pre-upgrade primary is an immutable exact archive")
 var again=Econ.new();again.load_state()
 check(not again.review_load_blocked and not again.free_offer_upgrade_preview().available,"upgraded offer record is restart-idempotent")
 var changed:Dictionary=again.upgrade_available_free_offers_and_save(craft(),pad(),{})
 check(changed.ok and not changed.changed,"second upgrade never reauthors jobs")
 # Accepted legacy A stays exact while the still-available B can be upgraded.
 var mixed=debt_fixture();mixed.accept_contract("D1-A");check(mixed.save_state(craft(),pad(),{}),"accepted legacy fixture committed")
 var accepted:Dictionary=mixed.contracts[0].duplicate(true)
 check(mixed.free_offer_upgrade_preview().count==1,"accepted old A is excluded from preview")
 check(mixed.upgrade_available_free_offers_and_save(craft(),pad(),{}).ok,"available old B can be explicitly upgraded")
 same(mixed.contracts[0],accepted,"upgrade never changes accepted legacy contract")
 check(mixed.active_contract_id=="D1-A" and mixed.contracts[1].control_version==Free.CONTROL_VERSION,"accepted identity and new available offer coexist")
 mixed.begin_dispatch(craft(),pad());var flight:Dictionary=mixed.in_flight.duplicate(true)
 check(not mixed.upgrade_available_free_offers_and_save(craft(),pad(),{}).ok,"upgrade refuses during a paid flight")
 same(mixed.in_flight,flight,"flight refusal keeps exact replay snapshot")
 # Unknown optional upgrade records are recovery-only, never a reroll trigger.
 var saved:Dictionary=disk();saved.free_offer_upgrade.schema="future-v99";write_primary(saved)
 var unknown=Econ.new();unknown.load_state();check(unknown.review_load_blocked,"unknown upgrade record blocks safe loading")
