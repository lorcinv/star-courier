extends SceneTree
## Focused model boundary: dev21-shaped three-receipt progress naturally authors
## level four, without grants, replay conversion or replacement of today's quotes.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Ascent=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String)->void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft()->Array:return Profile.starter_design()
func pad()->Array:return Profile.starter_launcher()
func telemetry(integrity:float=1.0,energy:float=1000.0,repair:float=0.0,lost:float=0.0)->Dictionary:
 return {"integrity":integrity,"delivery_integrity":integrity,"energy_used":energy,"ammo_cost":0.0,"repair_cost":repair,"lost_cost":lost}
func begin(e,id:String)->void:
 check(e.accept_contract(id).ok,"accept actual offered "+id);e.mark_cargo_loaded(id)
 check(e.begin_dispatch(craft(),pad(),{"angle_degrees":80.0,"power_fraction":1.0}).ok,"dispatch preserves actual protocol and vertical launch")
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
func complete_first_three():
 var e=Econ.new();e.enable_delivery_mode();e.starter_stock(craft(),pad());e.enable_story_mode()
 for level in range(1,4):
  var id:String="D%d-A"%level
  check(e.contract_by_id(id).control_version==Profile.VERSION,"original chapter retains v3 control")
  begin(e,id)
  check(e.settle_contract_and_save(id,telemetry(),20.0,true,craft(),pad(),{}).ok,"original chapter result saves")
  if level<3:check(e.close_day().ok and e.next_day_and_save(craft(),pad(),{}).ok,"original chapter advances normally")
 return e
func snapshot(e)->Dictionary:
 var out:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);out[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return out
func remove_tree(path:String)->void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for name in directory.get_files():DirAccess.remove_absolute(path.path_join(name))
 for name in directory.get_directories():remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:remove_tree("user://"+name)
func disk()->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func test_completed_save_and_fourth()->void:
 clear_files();var e=complete_first_three()
 var before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var state:Dictionary=e.delivery_chapter_state.duplicate(true)
 var quotes:Array=e.contracts.duplicate(true);var ledger:Dictionary=e.settled_ids.duplicate(true)
 var credits:int=e.credits;var inventory:Dictionary=e.inventory.duplicate(true)
 check(state=={"schema":"delivery-chapter-state-v3","chapter_id":1,"unlocked_level":4,"completed_levels":{"1":"D1-A","2":"D2-A","3":"D3-A"}},"completed save keeps original dev21 state shape and global next level")
 var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode()
 check(not loaded.review_load_blocked,"completed three-receipt save loads without reset")
 same(loaded.delivery_chapter_state,state,"Continue preserves prior chapter progress exactly")
 same(loaded.settled_ids,ledger,"Continue preserves all old financial receipts")
 same(loaded.contracts,quotes,"Continue never changes an already displayed quote")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==before,"read-only Continue does not rewrite old save bytes")
 check(loaded.credits==credits,"new content loading grants no cash")
 same(loaded.inventory,inventory,"new content loading grants no stock")
 check(loaded.delivery_chapter_status().first_chapter_complete and not loaded.delivery_chapter_status().moon_complete,"first chapter remains completed while moon is still pending")
 check(loaded.close_day().ok and loaded.next_day_and_save(craft(),pad(),{}).ok,"normal next business day generates fourth level")
 var moon:Dictionary=loaded.contracts[0]
 check(moon.chapter_id==2 and moon.chapter_level==4 and moon.control_version==Ascent.VERSION,"fourth global level belongs to chapter two and explicit ascent v4")
 check(moon.economy_policy==Chapter.ECONOMY_POLICY and moon.min_delivery_integrity==0.8,"new physics retains existing bill and normalized integrity semantics")
 check(loaded.contracts[1].chapter_level==1 and loaded.contracts[1].control_version==Profile.VERSION,"daily optional basic repayment task remains v3")
 check(Econ.route_validation_error(moon).is_empty() and not Profile.validation_error(moon).is_empty(),"new ascent validates but old v3 reader refuses to reinterpret it")
 check(not moon.has("wormhole_portal"),"normal fourth level is not a hidden portal route")
 same(loaded.settled_ids,ledger,"new fourth quote never rewrites prior completed receipts")
 same(loaded.inventory,inventory,"fourth level gives no new parts")
 begin(loaded,"D4-A")
 check(Econ.replay_protocol_error(loaded.in_flight).is_empty(),"v4 dispatch retains supported timeline and release replay")
 var mixed:Dictionary=loaded.in_flight.duplicate(true);mixed.control_version=Profile.VERSION
 check(not Econ.replay_protocol_error(mixed).is_empty(),"downgraded envelope cannot replay new physics as v3")
 check(loaded.save_state(craft(),pad(),{}),"new in-flight v4 saves")
 var flying=Econ.new();flying.load_state()
 check(not flying.review_load_blocked and flying.in_flight.control_version==Ascent.VERSION,"new in-flight v4 resumes without returning to chapter one")
 check(flying.settle_contract_and_save("D4-A",telemetry(),20.0,true,craft(),pad(),{}).ok,"fourth qualified formal delivery commits")
 check(flying.last_settlement.chapter_id==2 and flying.last_settlement.chapter_level==4 and flying.last_settlement.control_version==Ascent.VERSION,"receipt records actual fourth-level protocol")
 check(flying.last_settlement.receipt_schema==Chapter.RECEIPT_SCHEMA and flying.last_settlement.profit==int(moon.reward)-25,"unchanged economics bills actual energy once")
 check(flying.delivery_chapter_state.unlocked_level==5 and flying.delivery_chapter_status().moon_complete,"fourth qualified receipt advances global sequence exactly once")
 for id in ledger:same(flying.settled_ids[id],ledger[id],"old receipt remains frozen after moon success "+str(id))
 var resumed=Econ.new();resumed.load_state();resumed.enable_story_mode()
 check(not resumed.review_load_blocked and resumed.delivery_chapter_status().moon_complete,"fourth completion and money survive restart")
 check(resumed.close_day().ok and resumed.next_day_and_save(craft(),pad(),{}).ok,"new review can publish next day")
 check(resumed.customer_reviews()[0].success and not "准时" in resumed.customer_reviews()[0].body,"moon review uses existing no-time-pressure template")
func test_failure_debt_and_day_rollback()->void:
 clear_files();var e=complete_first_three();e.close_day();check(e.save_state(craft(),pad(),{}),"pre-fourth night saves")
 var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json");var previous:Dictionary=snapshot(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.next_day_and_save(craft(),pad(),{}).ok,"blocked next-day write cannot expose an unsaved moon order")
 same(snapshot(e),previous,"failed day transition restores all old quotes/progress/cash")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==original,"failed day transition preserves durable old save")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.next_day_and_save(craft(),pad(),{}).ok,"same normal next-day action safely retries")
 begin(e,"D4-A");e.credits=0
 var actual:Dictionary=telemetry(0.79,8000.0,80.0,170.0)
 check(e.settle_contract_and_save("D4-A",actual,30.0,true,craft(),pad(),{}).ok,"below-threshold moon arrival settles real failure")
 check(not e.last_settlement.success and e.credits==-555 and e.last_settlement.compensation==105,"new fourth failure carries full actual loss into debt")
 check(e.delivery_chapter_state.unlocked_level==4,"failed fourth level does not advance")
 check(not e.recover_legacy_debt_and_save(craft(),pad(),{}).changed and e.credits==-555,"new protocol cannot revive Continue debt relief")
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.review_load_blocked and loaded.credits==-555,"fourth-level debt survives restart")
 check(loaded.close_day().ok and loaded.next_day_and_save(craft(),pad(),{}).ok,"debt has a normal next-day continuation")
 for order in loaded.contracts:check(order.chapter_level==1 and order.recovery_offer and not order.chapter_progression,"existing basic work remains available to repay moon losses")
func test_unfinished_v3_contract_freezes()->void:
 clear_files();var e=Econ.new();e.enable_delivery_mode();e.starter_stock(craft(),pad());e.enable_story_mode()
 begin(e,"D1-A");check(e.save_state(craft(),pad(),{}),"old v3 in-flight sample saved")
 var frozen:Dictionary=e.in_flight.duplicate(true);var quotes:Array=e.contracts.duplicate(true)
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.review_load_blocked,"old committed v3 dispatch still readable")
 same(loaded.in_flight,frozen,"old committed replay is not upgraded to ascent")
 same(loaded.contracts,quotes,"old accepted and displayed routes retain original fields")
 check(loaded.settle_contract_and_save("D1-A",telemetry(),20.0,true,craft(),pad(),{}).ok,"old protocol can finish using old exact commercial terms")
 check(loaded.last_settlement.control_version==Profile.VERSION and loaded.last_settlement.chapter_id==1,"old result never claims moon protocol")
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Use isolated XDG_DATA_HOME.");quit(2);return
 test_completed_save_and_fourth();test_failure_debt_and_day_rollback();test_unfinished_v3_contract_freezes()
 clear_files();print("DELIVERY_ASCENT_ECONOMY_V4 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
