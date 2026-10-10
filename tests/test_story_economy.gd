extends SceneTree
## Persistence/accounting tests. Always run with an isolated XDG_DATA_HOME.
const Econ=preload("res://scripts/economy.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const AscentSim=preload("res://scripts/pilot_ascent_simulation.gd")
var passed:int=0
var failed:int=0
class TrialController extends "res://scripts/main.gd":
 func _ready() -> void:pass
 func render() -> void:pass
 func notify(_message:String) -> void:pass

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("Story economy tests require an isolated XDG_DATA_HOME.");quit(2);return
 clear_files()
 test_opt_in_and_seed();test_read_only_and_cancel();test_actual_trials();test_atomic_success();test_failure();test_legacy_dispatch();test_legacy_accepted();test_old_versions();test_failed_save();test_recurrence()
 clear_files()
 print("STORY_ECONOMY passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)

func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func difference(a:Variant,b:Variant,path:String="state") -> String:
 if (a is int or a is float) and (b is int or b is float):return "" if a==b else path+": numeric value differs"
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return path+": key count differs"
  for key in a:
   if not b.has(key):return path+": missing "+str(key)
   var issue:String=difference(a[key],b[key],path+"."+str(key))
   if not issue.is_empty():return issue
  return ""
 if a is Array and b is Array:
  if a.size()!=b.size():return path+": length differs"
  for i in a.size():
   var issue:String=difference(a[i],b[i],path+"[%d]"%i)
   if not issue.is_empty():return issue
  return ""
 return "" if a==b else path+": value differs"

func same(a:Variant,b:Variant,label:String) -> void:
 var issue:String=difference(a,b)
 check(issue.is_empty(),label+("" if issue.is_empty() else " | "+issue))

func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)

func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_fixture(value:Dictionary) -> void:
 clear_files()
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(value,"",true,true));file.close()

func make_story(shop_seed:int=7421):
 var e=Econ.new();e.enable_ascent_mode();e.ensure_contracts()
 e.story_state=Stories.initial_state(shop_seed);e.enable_story_mode()
 return e

func craft() -> Array:return Ascent.starter_design()
func pad() -> Array:return Ascent.starter_launcher()
func telemetry() -> Dictionary:return {"integrity":1.0,"energy_used":128.0,"ammo_cost":2.0,"repair_cost":3.0,"lost_cost":4.0}
func ledger(e) -> Dictionary:
 return {"credits":e.credits,"reputation":e.reputation,"jobs_today":e.jobs_today,"deliveries":e.deliveries,"research":e.research,"inventory":e.inventory.duplicate(true),"settled_ids":e.settled_ids.duplicate(true),"history":e.history.duplicate(true)}

func test_opt_in_and_seed() -> void:
 var e=Econ.new();e.starter_stock(craft(),pad());e.enable_ascent_mode()
 check(e.story_state.is_empty() and not e.story_mode,"starter stock and profile setup do not opt into stories")
 check(not e.contracts[0].has("appearance_id"),"legacy economy fixtures retain original unbound clients")
 var route:Dictionary=e.contracts[0].duplicate(true);var money:Dictionary=ledger(e)
 seed(81237);var expected:int=randi();seed(81237)
 e.enable_story_mode()
 check(randi()==expected,"fresh cosmetic seed does not consume global/simulation RNG")
 check(e.story_mode and e.story_state.world_seed>0 and e.story_state.world_seed<2147483647,"explicit new-shop boundary creates one bounded cosmetic seed")
 check(e.story_state.roster.size()==4 and e.story_state.contract_bindings.size()==2,"new shop saves all four identities and two contract bindings")
 check(e.contracts[0].appearance_id=="human_courier" and e.contracts[1].appearance_id=="elf_archivist","first day introduces human and elf identities")
 for id in Stories.IDS:
  check(e.story_state.roster[id].accessory_id in Stories.PROFILES[id].accessories,"new-shop accessory is compatible with "+id)
 same(ledger(e),money,"story setup does not change finances or research")
 for key in ["reward","weight","deadline","required","pilot_energy_tariff","pilot_battery_multiplier","pilot_gates","hazards","control_version"]:
  same(e.contracts[0][key],route[key],"binding preserves flight/accounting field "+key)
 check(str(e.contracts[0].story).contains("小勺") and str(e.contracts[1].cargo).begins_with("加急补货 · "),"bound teaser and heavy cargo label match current customer")
 var stable:Dictionary=e.story_state.duplicate(true);var orders:Array=e.contracts.duplicate(true)
 for i in 10:e.enable_story_mode();e.ensure_contracts();e.available_contracts()
 same(e.story_state,stable,"repeated enable and order reads keep the same cosmetic seed and bindings")
 same(e.contracts,orders,"repeated opt-in does not accumulate cargo prefixes or rewrite story nodes")
 check(e.save_state(craft(),pad(),{}),"new shop identity is persisted in the ordinary save")
 check(int(disk().version)==Econ.SAVE_VERSION and disk().has("story_state"),"current save schema includes story state in the ledger payload")
 var restored=Econ.new();seed(445);expected=randi();seed(445);restored.load_state();restored.enable_story_mode()
 check(randi()==expected,"saved story reload and enable never consume global RNG")
 same(restored.story_state,stable,"all saved identity seeds and accessories survive reload exactly")
 same(restored.contracts,orders,"contract identities remain unchanged after reload")

func test_read_only_and_cancel() -> void:
 clear_files();var e=make_story();var cid:String=e.contracts[0].contract_id
 check(e.story_conversation(cid,"accept").is_empty(),"unaccepted order cannot open acceptance dialogue")
 check(e.accept_contract(cid).ok,"bound order accepts through normal economy action")
 var state:Dictionary=e.story_state.duplicate(true);var money:Dictionary=ledger(e)
 var acceptance:Dictionary=e.story_conversation(cid,"accept")
 check(acceptance.id==cid+"/accept" and acceptance.actor.contract_id==cid,"acceptance and actor use stable contract IDs")
 check(acceptance.route_hint==e.active_contract().name,"conversation uses the actual ascent route name")
 check(e.story_actor(cid).appearance_id==e.active_contract().appearance_id and e.story_actor("unknown").is_empty(),"actor lookup uses only saved contract bindings")
 for i in 20:
  e.story_conversation(cid,"accept");e.story_actor(cid);e.pending_story_returns();e.trial_route();e.estimate_delivery(e.active_contract(),telemetry(),12.0,true)
 same(e.story_state,state,"dialogue reads, trial routes and estimate previews never advance or consume story")
 same(ledger(e),money,"preview and trial preparation never change any accounting field")
 check(e.story_conversation(cid,"result").is_empty() and e.pending_story_returns().is_empty(),"trial/preview cannot produce a paid result or return")
 check(not e.mark_story_seen(cid,"other/accept") and not e.mark_story_seen(cid,cid+"/invented"),"foreign and unknown dialogue IDs cannot mutate seen flags")
 check(e.mark_story_seen(cid,cid+"/accept") and not e.mark_story_seen(cid,cid+"/accept"),"acceptance completion or skip marks once")
 check(e.story_conversation(cid,"accept").is_empty(),"completed acceptance does not repeat")
 same(ledger(e),money,"dialogue completion grants no financial rewards")
 state=e.story_state.duplicate(true);e.reputation=3
 check(e.cancel_accepted().ok and e.reputation==2,"cancel keeps its original one-reputation penalty")
 check(e.credits==int(money.credits) and e.jobs_today==0 and e.deliveries==0,"cancel never pays or consumes a formal dispatch")
 same(e.story_state,state,"cancel does not advance or queue a story")
 check(not e.settle_contract(cid,telemetry(),12.0,true).ok,"cancelled order cannot be presented as a paid settlement")
 same(e.story_state,state,"rejected settlement keeps story state exact")
 var other:String=e.contracts[1].contract_id
 check(e.decline_available(other).ok,"second available customer can be declined")
 same(e.story_state,state,"decline neither advances stories nor queues a return")

func test_actual_trials() -> void:
 clear_files();var app=TrialController.new();app.economy=make_story();app.design=craft();app.launcher=pad()
 var cid:String=app.economy.contracts[0].contract_id;app.economy.accept_contract(cid)
 var state:Dictionary=app.economy.story_state.duplicate(true);var money:Dictionary=ledger(app.economy)
 for expected_success in [true,false]:
  app.trial=true;app.page="flight";app.flight_order=app.economy.trial_route();app.sim=AscentSim.new()
  app.sim.configure(app.design,app.launcher,app.flight_order,int(app.flight_order.seed))
  var axis:int=0
  for tick in 4200:
   if expected_success and tick%12==0:axis=app._smoke_guidance_axis()
   app.sim.set_pilot_input(axis,false,false);app.sim.step(1.0/60.0)
   if app.sim.status!="running":break
  check((app.sim.status=="success")==expected_success and app.sim.status!="running" and app.sim.telemetry.energy_used>0,"actual trial reaches expected paid-physics outcome: "+str(expected_success))
  app.finish_flight()
  check(app.report.trial and app.report.success==expected_success and app.economy.last_trials.has(cid),"real controller stores only a trial comparison for outcome: "+str(expected_success))
  same(app.economy.story_state,state,"actual trial completion never advances or queues stories: "+str(expected_success))
  same(ledger(app.economy),money,"actual trial completion never changes finances: "+str(expected_success))
  check(app.economy.active_contract().status=="accepted" and app.economy.in_flight.is_empty() and app.economy.pending_story_returns().is_empty(),"completed trial preserves accepted order without formal commitment")
  app.finish_flight()
  same(app.economy.story_state,state,"repeated controller trial finish remains story-idempotent")
 var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 same(restored.story_state,state,"completed trial save/reload preserves unadvanced identity")
 same(ledger(restored),money,"completed trial save/reload preserves original balance and counters")
 check(restored.active_contract().status=="accepted" and restored.in_flight.is_empty(),"completed trial save never reloads as a paid dispatch")
 app.free()

func test_atomic_success() -> void:
 clear_files();var e=make_story();var cid:String=e.contracts[0].contract_id
 e.research=2;e.accept_contract(cid);e.mark_cargo_loaded(cid);e.active_contract().pilot_energy_tariff=.03125
 check(e.begin_dispatch(craft(),pad()).ok,"formal story delivery creates a committed snapshot")
 var snapshot:Dictionary=e.in_flight.duplicate(true)
 check(snapshot.route.battery_capacity_multiplier==1.3 and snapshot.route.pilot_energy_tariff==.03125,"snapshot captures research and original custom tariff")
 check(e.save_state(craft(),pad(),{}),"in-flight identity and ledger save together")
 var restored=Econ.new();restored.load_state();restored.enable_ascent_mode();restored.enable_story_mode()
 same(restored.in_flight,snapshot,"modern story-enabled reload keeps full-precision committed snapshot exact")
 check(restored.story_state.roster.human_courier.story_node==0,"in-flight reload does not advance story")
 var quote:Dictionary=restored.estimate_delivery(restored.active_contract(),telemetry(),12.0,true)
 var credits:int=restored.credits;var result:Dictionary=restored.settle_contract(cid,telemetry(),12.0,true)
 check(result.ok and result.story_advanced,"unique paid settlement advances one story after ledger commit")
 check(restored.credits==credits+int(quote.profit) and result.report.profit==quote.profit,"stories do not change tariff, income or net profit")
 check(result.report.energy==4 and result.report.energy_tariff==.03125,"original saved tariff remains the source of actual energy charges")
 check(restored.jobs_today==1 and restored.deliveries==1 and restored.history.size()==1 and restored.settled_ids.size()==1,"one story receipt remains one economic settlement")
 check(restored.story_state.roster.human_courier.story_node==1 and restored.story_state.committed_contract_ids[cid].success,"only the committed identity advances exactly one node")
 check(restored.story_state.contract_bindings[cid].story_node==0,"the contract retains the chapter it was accepted with")
 check(restored.story_conversation(cid,"result").id==cid+"/result" and restored.pending_story_returns().size()==1,"committed result and return are available exactly once")
 var money:Dictionary=ledger(restored);var state:Dictionary=restored.story_state.duplicate(true)
 var duplicate:Dictionary=restored.settle_contract(cid,telemetry(),1.0,false)
 check(not duplicate.ok and duplicate.duplicate,"repeated settlement is rejected before any story update")
 same(ledger(restored),money,"repeated settlement cannot grant money or change outcome")
 same(restored.story_state,state,"repeated settlement cannot advance or enqueue again")
 check(restored.save_state(craft(),pad(),{}),"settlement and advancement share one atomic save")
 var saved:Dictionary=disk()
 check(saved.settled_ids.has(cid) and saved.story_state.committed_contract_ids.has(cid) and int(saved.credits)==restored.credits,"same durable payload contains payment, unique ID and node advancement")
 var again=Econ.new();again.load_state();again.enable_story_mode()
 same(again.story_state,state,"settled story and pending return survive restart without replay")
 same(ledger(again),money,"settled ledger survives restart without a second payment")
 check(not again.settle_contract(cid,telemetry(),12.0,true).ok,"saved unique ID blocks settlement after reload")
 check(again.mark_story_seen(cid,cid+"/result") and again.mark_story_seen(cid,cid+"/return"),"result and return completion mark separate saved beats")
 check(again.pending_story_returns().is_empty() and again.story_conversation(cid,"result").is_empty(),"seen result and return cannot reopen")
 same(ledger(again),money,"reading all story beats never grants a repeat reward")
 again.save_state(craft(),pad(),{});var final_load=Econ.new();final_load.load_state();final_load.enable_story_mode()
 check(final_load.pending_story_returns().is_empty() and final_load.story_state.roster.human_courier.story_node==1,"seen flags and single progression remain durable")

func test_failure() -> void:
 clear_files();var e=make_story();var cid:String=e.contracts[1].contract_id
 e.accept_contract(cid);e.mark_cargo_loaded(cid);e.begin_dispatch(craft(),pad());var before:int=e.credits
 var result:Dictionary=e.settle_contract(cid,telemetry(),60.0,false)
 check(result.ok and result.story_advanced and not result.report.success,"formal failed delivery commits one failure story")
 check(result.report.income==0 and result.report.profit==-13 and e.credits==before-13,"failure never invents income and retains actual costs")
 check(e.deliveries==0 and e.jobs_today==1 and e.story_state.roster.elf_archivist.story_node==1,"failure consumes one dispatch and advances only the committed NPC")
 var conversation:Dictionary=e.story_conversation(cid,"result")
 check(conversation.lines[0].expression=="concerned" and str(conversation.lines[0].text).contains("没送成"),"failure dialogue explicitly says the parcel was not delivered")
 check(str(e.pending_story_returns()[0].lines[0].text).contains("包裹的事慢慢来"),"failure return uses supportive failure text instead of success claims")
 e.save_state(craft(),pad(),{});var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 check(not restored.story_state.committed_contract_ids[cid].success and restored.story_state.roster.elf_archivist.story_node==1,"failure outcome and story node persist once")
 same(restored.story_conversation(cid,"result"),conversation,"failure dialogue remains identical after restart")

func test_legacy_dispatch() -> void:
 clear_files();var old=Econ.new();old.enable_pilot_mode();old.ensure_contracts();old.research=2
 var cid:String=old.contracts[0].contract_id;old.accept_contract(cid);old.begin_dispatch(craft(),pad())
 old.in_flight.ticks=17;old.in_flight.elapsed=17.0/60.0
 var receipt:Dictionary={"contract_id":"D0-A","success":true,"profit":123,"route":"旧航线","client":"原客户"}
 old.settled_ids["D0-A"]=receipt.duplicate(true);old.history.append(receipt.duplicate(true))
 var settled_order:Dictionary=old.contracts[0].duplicate(true);settled_order.contract_id="D0-A";settled_order.status="settled";old.contracts.append(settled_order)
 old.save_state(craft(),pad(),{})
 var fixture:Dictionary=disk();fixture.version=3;fixture.erase("story_state");write_fixture(fixture);fixture=disk()
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var e=Econ.new();e.load_state();var migrated:Dictionary=e.story_state.duplicate(true)
 check(not e.story_mode and e.story_state.contract_bindings.is_empty(),"legacy migration waits for explicit story opt-in")
 same(e.contracts,fixture.contracts,"legacy load leaves every original contract untouched")
 e.enable_ascent_mode();e.enable_story_mode()
 same(e.in_flight,fixture.in_flight,"story/profile migration never alters original in-flight route or replay fields")
 same(e.contracts[0],fixture.contracts[0],"legacy in-flight order retains original client cargo and protocol")
 same(e.contracts[2],fixture.contracts[2],"legacy settled order receives no retrofitted identity")
 same(e.settled_ids,fixture.settled_ids,"migration never alters existing receipts or grants old story rewards")
 same(e.history,fixture.history,"migration preserves historical accounting snapshots")
 check(e.contracts[1].appearance_id=="elf_archivist" and e.contracts[1].control_version==Ascent.CONTROL_VERSION,"only the available future order is eligible for NPC and ascent binding")
 check(e.story_actor(cid).is_empty() and e.story_conversation(cid,"result").is_empty(),"legacy in-flight client has no fabricated story actor or receipt")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"loading and opt-in leave original durable file byte-for-byte untouched")
 var repeat=Econ.new();repeat.load_state()
 same(repeat.story_state,migrated,"unwritten legacy migration derives the same seed on every reload")
 var state:Dictionary=e.story_state.duplicate(true);var result:Dictionary=e.settle_contract(cid,telemetry(),12.0,false)
 check(result.ok and not result.story_advanced and result.report.energy_tariff==.18,"legacy dispatch settles once under its original tariff without invented story advancement")
 same(e.story_state,state,"legacy formal failure cannot advance an unbound identity")
 check(not e.settle_contract("D0-A",telemetry(),12.0,true).ok,"old settled ID still blocks duplicate income")

func test_legacy_accepted() -> void:
 clear_files();var old=Econ.new();old.ensure_contracts();var cid:String=old.contracts[0].contract_id;old.accept_contract(cid)
 old.save_state(craft(),pad(),{});var fixture:Dictionary=disk();fixture.version=2;fixture.erase("story_state");write_fixture(fixture)
 var e=Econ.new();e.load_state();var money:Dictionary=ledger(e);e.enable_story_mode()
 check(e.active_contract_id==cid and e.active_contract().status=="accepted" and e.active_contract().appearance_id=="human_courier","legacy accepted unlaunched order receives one stable identity")
 check(not e.story_conversation(cid,"accept").is_empty() and e.story_state.roster.human_courier.story_node==0,"legacy accepted order starts with an unseen first chapter")
 same(ledger(e),money,"accepted-order migration leaves every ledger field unchanged")
 var identity:Dictionary=e.story_actor(cid);e.save_state(craft(),pad(),{});var again=Econ.new();again.load_state();again.enable_story_mode()
 same(again.story_actor(cid),identity,"migrated accepted appearance becomes durable on first successful save")

func test_old_versions() -> void:
 for version in [1,2,3]:
  write_fixture({"version":version,"design":craft(),"launcher":pad(),"credits":321,"inventory":{"battery":4},"research":2,"day":7,"history":[]})
  var e=Econ.new();var value:Dictionary=e.load_state()
  check(not value.is_empty() and e.credits==321 and e.research==2 and e.inventory.battery==4,"save v%d retains funds inventory and research"%version)
  check(e.story_state.committed_contract_ids.is_empty() and e.story_state.pending_returns.is_empty(),"save v%d migration does not invent prior story completions"%version)
  e.enable_story_mode()
  check(e.story_state.contract_bindings.size()==2,"save v%d safely binds only its current eligible orders"%version)

func test_failed_save() -> void:
 clear_files();var e=make_story();var cid:String=e.contracts[0].contract_id;e.accept_contract(cid);e.mark_cargo_loaded(cid);e.begin_dispatch(craft(),pad())
 check(e.save_state(craft(),pad(),{}),"failure fixture saves the original in-flight commitment")
 var previous:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json");var original:Dictionary=disk()
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(e.settle_contract(cid,telemetry(),12.0,true).ok and not e.save_state(craft(),pad(),{}),"blocked temporary write reports settlement save failure")
 check(not e.save_error.is_empty() and FileAccess.get_file_as_bytes("user://savegame.json")==previous,"failed save preserves the exact previous durable ledger and story")
 var restored=Econ.new();restored.load_state();restored.enable_story_mode()
 check(restored.credits==int(original.credits) and restored.story_state.roster.human_courier.story_node==0,"restart after failed save restores neither a half-payment nor a half-advanced story")
 same(restored.in_flight,original.in_flight,"failed settlement save leaves its replayable original commitment intact")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.save_state(craft(),pad(),{}),"successful retry atomically persists the already unique in-memory settlement")
 var final_load=Econ.new();final_load.load_state();final_load.enable_story_mode()
 check(final_load.credits==e.credits and final_load.story_state.roster.human_courier.story_node==1 and final_load.settled_ids.size()==1,"successful retry writes matching paid amount node and unique receipt")
 var state:Dictionary=final_load.story_state.duplicate(true);var money:Dictionary=ledger(final_load)
 check(not final_load.settle_contract(cid,telemetry(),12.0,true).ok,"reloaded retry cannot commit settlement a second time")
 same(final_load.story_state,state,"duplicate after retry leaves progression unchanged")
 same(ledger(final_load),money,"duplicate after retry leaves payment unchanged")

func test_recurrence() -> void:
 clear_files();var e=make_story(91237);var cid:String=e.contracts[0].contract_id;var appearance:Dictionary=e.story_actor(cid)
 e.accept_contract(cid);e.mark_cargo_loaded(cid);e.begin_dispatch(craft(),pad());e.settle_contract(cid,telemetry(),12.0,true)
 e.close_day();e.next_day()
 check(e.contracts[0].appearance_id=="alien_botanist" and e.contracts[1].appearance_id=="robot_machinist","second day introduces the other two recurring species")
 check(e.pending_story_returns().size()==1 and e.pending_story_returns()[0].route_hint==e.settled_ids[cid].route,"older-day return keeps its original receipt and actual route")
 e.close_day();e.next_day();var next_id:String=e.contracts[0].contract_id
 check(next_id!=cid and e.contracts[0].appearance_id=="human_courier" and e.contracts[0].story_node==1,"returning identity takes its next chapter under a fresh contract ID")
 var current:Dictionary=e.story_actor(next_id)
 for key in ["appearance_id","appearance_seed","species","accessory_id"]:same(current[key],appearance[key],"recurring identity retains "+key)
 check(e.story_state.contract_bindings[cid].story_node==0,"new chapter never retrofits an old contract's story snapshot")
 e.accept_contract(next_id)
 check(str(e.story_conversation(next_id,"accept").lines[0].text).contains("又来麻烦"),"recurring acceptance acknowledges the prior meeting")
 var money:Dictionary=ledger(e);e.mark_story_seen(cid,cid+"/return")
 same(ledger(e),money,"an old return can be read during a later day without rewards")
