extends SceneTree
## Focused isolated test only; never point this at a player's data directory.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Old=preload("res://scripts/pilot_free_profile_v2.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Use an isolated XDG_DATA_HOME.");quit(2);return
 clear_files()
 test_authoring_and_progress()
 test_loss_debt_and_trials()
 test_migration_and_frozen_receipts()
 test_persistence_rejection()
 clear_files()
 print("DELIVERY_CHAPTER_ECONOMY_V3 passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft() -> Array:return Profile.starter_design()
func pad() -> Array:return Profile.starter_launcher()
func telemetry(integrity:float=1.0,energy:float=1200.0,repair:float=0.0,lost:float=0.0) -> Dictionary:
 return {"integrity":integrity,"delivery_integrity":integrity,"energy_used":energy,"ammo_cost":0.0,"repair_cost":repair,"lost_cost":lost}
func fresh():
 var e=Econ.new();check(e.enable_delivery_mode().ok,"new shop enables delivery before authoring")
 e.starter_stock(craft(),pad());e.enable_story_mode();return e
func begin(e,id:String="D1-A") -> void:
 check(e.accept_contract(id).ok,"accept "+id)
 if e.story_mode and e.active_contract().get("control_version")==Profile.VERSION:check("最低交付完整度" in str(e.story_conversation(id,"accept")),"acceptance dialogue reports actual chapter requirement")
 check(e.mark_cargo_loaded(id).ok,"load "+id)
 check(e.begin_dispatch(craft(),pad(),{"angle_degrees":20.0,"power_fraction":0.75}).ok,"dispatch "+id)
 check(not e.in_flight.launch_released and e.in_flight.launch_preparation.age==0.0,"new formal dispatch freezes unpaid preparation")
 check(Econ.replay_protocol_error(e.in_flight).is_empty(),"unreleased launch preparation is a valid restorable snapshot")
 # This model test represents Main's explicit physical release checkpoint.
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
func snapshot(e) -> Dictionary:
 var out:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var v:Variant=e.get(key);out[key]=v.duplicate(true) if v is Dictionary or v is Array else v
 return out
func remove_tree(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for name in directory.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in directory.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","delivery-chapter-upgrade-v3","economy-recovery-v1"]:remove_tree("user://"+name)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_primary(value:Dictionary) -> void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(value,"",true,true));file.close()
func test_authoring_and_progress() -> void:
 clear_files();var e=fresh()
 check(e.contracts.size()==2 and e.contracts[0].chapter_level==1,"normal new game has first light chapter and optional basic order")
 check(e.contracts[1].chapter_progression==false,"basic follow-up cannot skip chapter progression")
 check(e.missing_parts(craft(),pad()).is_empty(),"new stock covers the real four-spring launch platform")
 var stock:Dictionary=e.inventory.duplicate(true);e.starter_stock([],[]);same(e.inventory,stock,"starter stock cannot be claimed again")
 for level in range(1,4):
  var id:String="D%d-A"%level
  var order:Dictionary=e.contract_by_id(id)
  check(order.chapter_level==level and order.cargo_kind==Chapter.CARGO_KINDS[level-1],"normal days reach chapter level %d"%level)
  check(Econ.route_validation_error(order).is_empty(),"authored chapter level validates")
  check(order.required==order.min_delivery_integrity*100.0,"visible requirement mirrors sole normalized threshold")
  check(order.cargo in ["温室种子","货站蓄能芯","精密玻璃培养皿"],"story binding preserves real chapter cargo")
  var before:Dictionary=snapshot(e);e.ensure_contracts();same(snapshot(e),before,"display does not reroll quotes")
  begin(e,id)
  check(Econ.replay_protocol_error(e.in_flight).is_empty(),"v3 replay including launch settings validates")
  same(e.in_flight.launch_settings,{"angle_degrees":20.0,"power_fraction":0.75},"formal launch settings freeze")
  var result:Dictionary=e.settle_contract_and_save(id,telemetry(1.0),5000.0,true,craft(),pad(),{})
  check(result.ok and e.last_settlement.success and e.delivery_chapter_state.unlocked_level==level+1,"real qualified settlement advances exactly one level")
  check(e.last_settlement.income==order.reward and e.last_settlement.actual_costs==30 and e.last_settlement.compensation==0,"qualified income has real unbounded fees and no time pressure")
  check(Chapter.receipt_error(e.last_settlement).is_empty(),"versioned receipt validates")
  var receipt:Dictionary=e.last_settlement.duplicate(true)
  check(not e.settle_contract(id,telemetry(),1.0,true).ok,"duplicate formal outcome cannot earn twice")
  same(e.last_settlement,receipt,"duplicate attempt preserves receipt")
  var restored=Econ.new();restored.load_state();restored.enable_story_mode()
  check(not restored.review_load_blocked and restored.delivery_chapter_state.unlocked_level==level+1,"chapter progress survives restart")
  e=restored
  if level<3:
   check(e.close_day().ok and e.next_day_and_save(craft(),pad(),{}).ok,"normal close/next-day reaches next level")
 check(e.delivery_chapter_status().first_chapter_complete and not e.delivery_chapter_status().moon_complete,"third qualified delivery completes only first chapter")
 for review in e.customer_reviews():check(not "准时" in review.body and not "晚" in review.body,"chapter reviews do not invent delivery time promises")
 check(e.close_day().ok and e.next_day().ok,"completed chapter retains real repeatable deliveries")
 check(e.contracts[0].chapter_id==2 and e.contracts[0].chapter_level==4 and e.contracts[0].chapter_progression,"implemented ascent unlocks only after first chapter receipts")
func test_loss_debt_and_trials() -> void:
 clear_files();var e=fresh();var order:Dictionary=e.contracts[0]
 var before:Dictionary=snapshot(e)
 var quote:Dictionary=e.estimate_delivery(order,telemetry(0.69,8000.0,80.0,170.0),12.0,true)
 check(quote.delivery_qualified==false and quote.income==0 and quote.compensation==56,"below-threshold arrival fails and charges actual parcel damage")
 check(quote.actual_costs==506 and quote.profit==-506 and not quote.has("charge_cap"),"v3 total has no insurance or cash cap")
 same(snapshot(e),before,"free trial quote cannot settle money, stock or chapter")
 e.credits=0;var empty:Dictionary=e.estimate_delivery(order,telemetry(0.69,8000.0,80.0,170.0),12.0,false)
 same(quote,empty,"spending cash before failure never reduces v3 liability")
 begin(e);var inventory:Dictionary=e.inventory.duplicate(true)
 var result:Dictionary=e.settle_contract_and_save("D1-A",telemetry(0.69,8000.0,80.0,170.0),12.0,true,craft(),pad(),{})
 check(result.ok and not e.last_settlement.success and e.credits==-506,"caller success cannot override failed integrity")
 check(e.last_settlement.debt==506 and e.last_settlement.debt_added==506 and e.deliveries==0,"negative debt and actual failed outcome are recorded")
 check(e.delivery_chapter_state.unlocked_level==1,"failed task cannot advance chapter")
 same(e.inventory,inventory,"restitution bills restore only owned property without gifts")
 check(not e.recover_legacy_debt_and_save(craft(),pad(),{}).changed and e.credits==-506,"Continue cannot forgive v3 debt")
 var restored=Econ.new();restored.load_state()
 check(not restored.review_load_blocked and restored.credits==-506,"debt survives load unchanged")
 check(restored.close_day().ok and restored.next_day_and_save(craft(),pad(),{}).ok,"debt still reaches next business day")
 for next in restored.contracts:
  check(next.chapter_level==1 and next.recovery_offer and not next.chapter_progression,"negative cash receives real basic repayment tasks")
 var owned:Dictionary=restored.inventory.duplicate(true)
 begin(restored,"D2-A")
 check(restored.settle_contract_and_save("D2-A",telemetry(),12.0,true,craft(),pad(),{}).ok and restored.credits==-316,"owned craft earns net 190 toward debt without advance subsidy")
 same(restored.inventory,owned,"repayment delivery cannot mint inventory")
 check(not restored.buy_part("battery",{"price":45}).ok,"negative cash cannot purchase")
 restored.credits=500;restored.phase="night"
 check(not restored.buy_part("battery",{"price":0}).ok,"v3 night shop cannot accept a caller-supplied zero price")
 check(restored.buy_part("battery",{"price":45}).ok and restored.credits==455,"real full-price night purchase debits money")
func old_economy():
 var e=Econ.new();e.enable_force_mode();e.starter_stock(Old.starter_design(),Old.starter_launcher());e.enable_story_mode();return e
func test_migration_and_frozen_receipts() -> void:
 clear_files();var e=old_economy();var old_order:Dictionary=e.contracts[0].duplicate(true)
 var old_quote:Dictionary=e.estimate_delivery(old_order,telemetry(1.0,8000.0,80.0,170.0),12.0,false)
 check(old_quote.charged_costs==25 and old_quote.insurance_coverage==425,"old failure retains 25 cap")
 check(e.estimate_delivery(old_order,telemetry(),12.0,true).charged_costs==30,"old success retains 30 cap")
 check(e.accept_contract("D1-A").ok,"freeze old accepted contract before migration")
 check(e.save_state(Old.starter_design(),Old.starter_launcher(),{}),"old accepted state durably saved")
 var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var accepted:Dictionary=e.contracts[0].duplicate(true);var stock:Dictionary=e.inventory.duplicate(true)
 e.credits=-60;check(e.save_state(Old.starter_design(),Old.starter_launcher(),{}),"save legacy negative balance")
 original=FileAccess.get_file_as_bytes("user://savegame.json")
 var preview:Dictionary=e.delivery_upgrade_preview(Old.starter_design(),Old.starter_launcher(),{})
 check(preview.available and preview.replaced_count==1,"explicit migration can replace only available B while accepted A freezes")
 check(not e.upgrade_delivery_mode_and_save("stale",Old.starter_design(),Old.starter_launcher(),{}).ok,"stale confirmation cannot migrate")
 check(e.upgrade_delivery_mode_and_save(preview.confirmation_token,Old.starter_design(),Old.starter_launcher(),{}).ok,"confirmed migration atomically saves")
 same(e.contracts[0],accepted,"accepted old quote remains exact through migration")
 same(e.inventory,stock,"migration gives no assets")
 check(e.credits==-60 and e.contracts[1].control_version==Profile.VERSION,"migration keeps actual debt and exposes unaccepted v3 task")
 same(e.estimate_delivery(accepted,telemetry(1.0,8000.0,80.0,170.0),12.0,false).charge_cap,0,"old accepted failure uses frozen cash-limited policy")
 var archive:String="user://delivery-chapter-upgrade-v3/"+str(e.delivery_upgrade.source_sha256)+"/savegame.json"
 check(FileAccess.get_file_as_bytes(archive)==original,"explicit migration archives byte-exact original")
 check(not e.upgrade_delivery_mode_and_save(preview.confirmation_token,Old.starter_design(),Old.starter_launcher(),{}).changed,"migration repeat grants nothing")
 var reloaded=Econ.new();reloaded.load_state()
 check(not reloaded.review_load_blocked and reloaded.credits==-60 and reloaded.contracts[0].control_version==Old.VERSION,"mixed old accepted/new available survives restart")
func test_persistence_rejection() -> void:
 clear_files();var e=fresh();begin(e)
 check(e.save_state(craft(),pad(),{}),"pre-settlement launch saved")
 var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json");var before:Dictionary=snapshot(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.settle_contract_and_save("D1-A",telemetry(),12.0,true,craft(),pad(),{}).ok,"failed atomic write refuses financial success")
 same(snapshot(e),before,"failed write rolls chapter, bill, cash, story and review back together")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==original,"failed settlement does not replace durable launch")
 DirAccess.remove_absolute("user://savegame.tmp")
 var bad:Dictionary=telemetry();bad.delivery_integrity=80.0;bad.integrity=80.0
 check(not e.settle_contract("D1-A",bad,1.0,true).ok,"v3 never guesses percentage telemetry units")
 bad=telemetry();bad.repair_cost=-1.0
 check(not e.settle_contract("D1-A",bad,1.0,true).ok,"negative repair cannot manufacture funds")
 check(e.settle_contract_and_save("D1-A",telemetry(),12.0,true,craft(),pad(),{}).ok,"same launch retries exactly once")
 var valid:Dictionary=disk();var corrupt:Dictionary=valid.duplicate(true)
 corrupt.settled_ids["D1-A"].charged_costs=0
 check(not e._valid_save(corrupt),"receipt refuses erased liability")
 corrupt=valid.duplicate(true);corrupt.erase("delivery_chapter_state")
 check(not e._valid_save(corrupt),"downgrade-lost chapter state is rejected")
 corrupt=valid.duplicate(true);corrupt.delivery_chapter_state.unlocked_level=4
 check(not e._valid_save(corrupt),"progress cannot jump without real receipts")
 corrupt=valid.duplicate(true);corrupt.settled_ids["D1-A"].economy_policy="delivery-economy-v4"
 write_primary(corrupt);var blocked=Econ.new();blocked.load_state()
 check(blocked.review_load_blocked,"unknown receipt is retained opaque instead of falling back into old insurance")
 check(FileAccess.get_file_as_bytes("user://savegame.json")!=original,"opaque read does not overwrite source")
 clear_files();var old=old_economy();check(old.save_state(Old.starter_design(),Old.starter_launcher(),{}),"migration rollback source saved")
 var preview:Dictionary=old.delivery_upgrade_preview(Old.starter_design(),Old.starter_launcher(),{})
 var unchanged:Dictionary=snapshot(old);var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not old.upgrade_delivery_mode_and_save(preview.confirmation_token,Old.starter_design(),Old.starter_launcher(),{}).ok,"blocked migration commit reports failure")
 same(snapshot(old),unchanged,"failed migration retains original live object state")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"failed migration preserves durable source")
 DirAccess.remove_absolute("user://savegame.tmp")
