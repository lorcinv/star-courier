extends SceneTree
## Pure-data regression. No main scene, imported art, rendered frames or physics.
## Run only with an isolated XDG_DATA_HOME; ordinary save/restart paths are real.
const Econ=preload("res://scripts/economy.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Wormhole=preload("res://scripts/pilot_wormhole_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
var passed:int=0
var failed:int=0

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("Ground contract tests require an isolated XDG_DATA_HOME.");quit(2);return
 clear_save()
 test_new_contract_boundary();test_bootstrap_boundary();test_legacy_saved_orders()
 test_trial_dispatch_restart();test_two_day_progression();test_story_destinations()
 test_story_context_normalization();test_read_skip_and_failure()
 clear_save()
 print("GROUND_CONTRACTS passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)

func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func equal(a:Variant,b:Variant) -> bool:
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not equal(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not equal(a[i],b[i]):return false
  return true
 return a==b

func same(a:Variant,b:Variant,label:String) -> void:check(equal(a,b),label)
func clear_save() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)

func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func craft() -> Array:return Extreme.starter_design()
func pad() -> Array:return Extreme.starter_launcher()
func telemetry() -> Dictionary:return {"integrity":1.0,"energy_used":128.0,"ammo_cost":2.0,"repair_cost":3.0,"lost_cost":4.0}
func ledger(e) -> Dictionary:
 return {"credits":e.credits,"reputation":e.reputation,"jobs_today":e.jobs_today,"deliveries":e.deliveries,"research":e.research,"workshop_tier":e.workshop_tier,"inventory":e.inventory.duplicate(true),"settled_ids":e.settled_ids.duplicate(true),"history":e.history.duplicate(true)}

func shop(reputation:int=0,stories:bool=true):
 var e=Econ.new();e.reputation=reputation;e.enable_extreme_mode();e.starter_stock(craft(),pad())
 if stories:e.story_state=Stories.initial_state(7421);e.enable_story_mode()
 return e

func test_new_contract_boundary() -> void:
 var e=shop(0,false)
 check(e.contracts.size()==2 and e.DISPATCHES_PER_DAY==2,"fresh v3 first day retains exactly two formal slots")
 for order in e.contracts:
  check(order.id==0 and Ground.is_ground_route(order),"fresh zero-reputation route 0 is explicitly ground: "+order.contract_id)
  check(order.control_version=="pilot-v3" and order.pilot_profile=="pilot-v3" and order.pilot_overdrive=="mounted-output","ground content retains uncapped mounted-output v3 identity")
  check(order.distance==360.0 and order.destination_y==-8.0 and order.pilot_cruise_speed==18.0,"fresh ground contract persists actual short low-altitude route")
  check(order.hazards.size()==6 and order.pilot_gates.size()==3 and order.destination_name=="屋顶收件台","fresh ground contract persists all three gates and actual local destination")
 check(e.contracts[0].contract_id=="D1-A" and e.contracts[1].contract_id=="D1-B","finite contract IDs remain unchanged")
 check(e.contracts[0].weight==1.0 and e.contracts[0].reward==165 and e.contracts[0].deadline==32.0,"standard ground contract keeps original commercial values and authored deadline")
 check(e.contracts[1].weight==1.55 and e.contracts[1].reward==220 and e.contracts[1].deadline==35.0,"heavy variant applies existing weight, reward and deadline adjustment exactly once")
 var orders:Array=e.contracts.duplicate(true)
 for i in 12:e.ensure_contracts();e.enable_extreme_mode();e.available_contracts()
 same(e.contracts,orders,"reads and repeated mode enable never reauthor existing ground orders")
 var catalog:Array=e.routes()
 check(catalog[0].distance==520.0 and catalog[0].destination_y==-150.0 and not catalog[0].has("route_profile"),"v3 route catalog remains the original ascent catalog")
 for rep in [2,4,7,10]:
  var unlocked=shop(rep,false)
  check(unlocked.contracts[1].id>0 and unlocked.contracts[1].rep<=rep,"existing reputation gate selects a higher route at rep %d"%rep)
  if rep==7:
   check(unlocked.contracts[1].control_version==Wormhole.CONTROL_VERSION and unlocked.contracts[1].route_profile==Wormhole.ROUTE_PROFILE,"only new rep-7 offers open the explicit wormhole route")
  else:
   check(not Ground.is_ground_route(unlocked.contracts[1]) and unlocked.contracts[1].distance==520.0 and unlocked.contracts[1].destination_y==-150.0,"other unlocked routes retain original ascent at rep %d"%rep)
 for mode in ["autonomous-v5","pilot-v1","pilot-v2"]:
  var old=Econ.new();old.flight_mode=mode;old.ensure_contracts()
  check(not old.contracts[0].has("route_profile"),"ground authoring does not touch older mode "+mode)
 # A saved nonempty catalog is authoritative even before accept/dispatch.
 e.contracts[0].distance=363.125;e.contracts[0].pilot_gates[0].y=-17.125
 orders=e.contracts.duplicate(true);e.ensure_contracts();e.enable_extreme_mode()
 same(e.contracts,orders,"custom available v3 route dictionaries are never normalized through ground authoring")

func test_bootstrap_boundary() -> void:
 # Read-only source check. The staging review file has only the supplied one-line
 # bootstrap hunk; after integration this reads the real production main source.
 var path:String="res://review/main.gd" if FileAccess.file_exists("res://review/main.gd") else "res://scripts/main.gd"
 var source:String=FileAccess.get_file_as_string(path)
 check(source.contains(" else:economy.enable_extreme_mode();economy.starter_stock(design,launcher)\n economy.enable_extreme_mode()"),"fresh main bootstrap opts into v3 before starter_stock authors any order")
 check(source.contains(" if not loaded.is_empty():\n  design=loaded.get(\"design\",design);launcher=loaded.get(\"launcher\",launcher);settings.merge(loaded.get(\"settings\",{}),true)"),"loaded-save main branch retains its original restoration boundary")
 var fresh=Econ.new();fresh.enable_extreme_mode();fresh.starter_stock(craft(),pad());fresh.enable_extreme_mode();fresh.enable_story_mode()
 check(Ground.is_ground_route(fresh.contracts[0]),"new-save bootstrap order actually generates first-day ground")
 var existing=Econ.new();existing.starter_stock(craft(),pad());existing.enable_extreme_mode()
 check(not existing.contracts[0].has("route_profile") and existing.contracts[0].distance==520.0,"already-created old contracts use existing upgrade path, never become ground")

func test_legacy_saved_orders() -> void:
 clear_save()
 var e=Econ.new();e.enable_extreme_mode();e.contracts=[]
 for i in range(2):
  var order:Dictionary=Extreme.route(e._autonomous_routes()[0]);order.contract_id="D1-"+("A" if i==0 else "B");order.status="available";order.accepted_day=1;order.variant="标准件"
  order.distance=567.125+i;order.pilot_energy_tariff=.03125;order.destination_y=-137.75
  order.pilot_gates[2].y=-104.8125;order.hazards[5].y=-89.8125
  e.contracts.append(order)
 e.story_state=Stories.initial_state(7421);e.enable_story_mode();e.workshop_tier=2;e.research=2
 e.accept_contract("D1-A");e.mark_cargo_loaded("D1-A")
 e.last_trials={"D1-A":{"estimated_profit":111,"route":{"distance":567.125},"inputs":[{"axis_q":1000}]}}
 var expected:Array=e.contracts.duplicate(true);var trials:Dictionary=e.last_trials.duplicate(true);var cash:Dictionary=ledger(e)
 check(e.save_state(craft(),pad(),{}),"legacy accepted v3 fixture saves through normal v5 writer")
 var restored=Econ.new();restored.load_state();restored.enable_extreme_mode();restored.enable_story_mode()
 same(restored.contracts,expected,"legacy accepted and available v3 dictionaries remain exact after current bootstrap")
 same(restored.last_trials,trials,"legacy saved trial comparison remains exact")
 same(ledger(restored),cash,"legacy load preserves workshop tier, research, money, inventory and quota")
 check(restored.story_conversation("D1-A","accept").lines[0].text.contains("星港") and not restored.story_conversation("D1-A","accept").lines[0].text.contains("屋顶"),"missing route_profile keeps old accepted story starport semantics")
 restored.begin_dispatch(craft(),pad());restored.in_flight.ticks=137;restored.in_flight.elapsed=137.0/60.0
 restored.in_flight.input_commands=[{"tick":0,"axis_q":0,"boost":false,"active":false},{"tick":8,"axis_q":-1000,"boost":true,"active":false},{"tick":65,"axis_q":1000,"boost":false,"active":true}]
 var snapshot:Dictionary=restored.in_flight.duplicate(true);expected=restored.contracts.duplicate(true)
 check(restored.save_state(craft(),pad(),{}),"legacy in-flight custom v3 snapshot saves through normal writer")
 var resumed=Econ.new();resumed.load_state();resumed.enable_extreme_mode();resumed.enable_story_mode()
 same(resumed.in_flight,snapshot,"legacy v3 in-flight route, seed, elapsed and sparse input snapshot survive restart exactly")
 same(resumed.contracts,expected,"in-flight and available legacy contract dictionaries remain exact")
 same(resumed.last_trials,trials,"formal restart does not replace earlier saved trial data")
 check(not resumed.in_flight.route.has("route_profile") and resumed.in_flight.route.distance==567.125,"old physical route never inherits new ground profile or dimensions")

func test_trial_dispatch_restart() -> void:
 clear_save();var e=shop();e.workshop_tier=1;e.research=2
 var cid:String=e.contracts[1].contract_id;e.accept_contract(cid);e.mark_cargo_loaded(cid)
 e.active_contract().distance=363.125;e.active_contract().pilot_energy_tariff=.03125
 var before:Dictionary=ledger(e);var story:Dictionary=e.story_state.duplicate(true)
 var trial:Dictionary=e.trial_route();var quote:Dictionary=e.estimate_delivery(e.active_contract(),telemetry(),22.0,true)
 same(ledger(e),before,"trial route and quote leave full economy ledger unchanged")
 same(e.story_state,story,"trial route and quote do not advance or queue story")
 check(trial.seed==101 and trial.battery_capacity_multiplier==1.3,"ground heavy trial keeps deterministic day/ID seed and research multiplier")
 check(e.begin_dispatch(craft(),pad()).ok,"loaded ground contract uses normal formal dispatch commitment")
 var formal:Dictionary=e.in_flight.route.duplicate(true);formal.seed=e.in_flight.seed
 trial.status="in_flight"
 same(formal,trial,"trial and formal have identical complete route/seed apart from deliberate accepted-to-inflight status")
 check(e.in_flight.control_version=="pilot-v3" and e.in_flight.input_commands==[{"tick":0,"axis_q":0,"boost":false,"active":false}],"ground snapshot keeps unchanged v3 input protocol and neutral first command")
 e.in_flight.ticks=73;e.in_flight.elapsed=73.0/60.0;e.in_flight.input_commands.append({"tick":12,"axis_q":-1000,"boost":true,"active":true})
 e.last_trials[cid]={"trial":true,"estimated_profit":quote.profit,"energy_tariff":quote.energy_tariff}
 var snapshot:Dictionary=e.in_flight.duplicate(true);var trials:Dictionary=e.last_trials.duplicate(true);var orders:Array=e.contracts.duplicate(true)
 check(e.save_state(craft(),pad(),{}),"ground route and input history use existing atomic save")
 check(disk().version==5 and Econ.SAVE_VERSION==5,"ground content requires no save-version migration")
 var loaded=Econ.new();loaded.load_state();loaded.enable_extreme_mode();loaded.enable_story_mode()
 same(loaded.in_flight,snapshot,"ground actualroute fields and input history survive save/restart without reauthoring")
 same(loaded.contracts,orders,"ground saved contracts retain full precision and custom values")
 same(loaded.last_trials,trials,"ground saved trial comparison survives restart")
 same(ledger(loaded),before,"restart retains money, quota, inventory, research and purchased workshop tier")
 var result:Dictionary=loaded.settle_contract(cid,telemetry(),22.0,true)
 check(result.ok and result.story_advanced and loaded.credits==int(before.credits)+int(quote.profit),"single formal settlement uses exactly the trial quote and advances one story")
 check(result.report.energy==4 and result.report.energy_tariff==.03125 and result.report.profit==quote.profit,"saved original tariff remains the actual billing source")
 check(loaded.jobs_today==1 and loaded.deliveries==1 and loaded.settled_ids.size()==1 and loaded.history.size()==1,"one ground completion is one finite ledger settlement")
 var committed:Dictionary=ledger(loaded);story=loaded.story_state.duplicate(true)
 var duplicate:Dictionary=loaded.settle_contract(cid,telemetry(),1.0,false)
 check(duplicate.get("duplicate",false),"unique ground settlement ID blocks repeated result with conflicting outcome")
 same(ledger(loaded),committed,"duplicate ground settlement cannot pay twice or add quota/history")
 same(loaded.story_state,story,"duplicate ground settlement cannot add story node or return")
 check(loaded.save_state(craft(),pad(),{}),"ground committed story and financial ledger save atomically")
 check(disk().settled_ids.has(cid) and disk().story_state.committed_contract_ids.has(cid),"same v5 payload contains the unique financial and story receipt")
 var final_load=Econ.new();final_load.load_state();final_load.enable_extreme_mode();final_load.enable_story_mode()
 same(ledger(final_load),committed,"settled ground ledger survives another restart without payment")
 same(final_load.story_state,story,"ground receipt destination and pending return survive normalized restart")

func test_two_day_progression() -> void:
 clear_save();var e=shop();e.workshop_tier=1
 var first_id:String=e.contracts[0].contract_id
 for order in e.contracts.duplicate(true):
  var cid:String=order.contract_id
  check(e.accept_contract(cid).ok,"day-one ground contract accepts "+cid)
  e.mark_cargo_loaded(cid);e.mark_story_seen(cid,cid+"/accept");e.begin_dispatch(craft(),pad())
  check(e.settle_contract(cid,telemetry(),22.0,true).ok,"day-one ground contract settles "+cid)
 check(e.jobs_today==2 and e.reputation==4 and e.deliveries==2,"two good ground jobs retain existing +2 reputation and exhaust the finite day")
 check(not e.accept_contract(first_id).ok and not e.begin_dispatch(craft(),pad()).ok,"used ground contracts cannot farm extra dispatches")
 var historical:Dictionary=e.story_conversation(first_id,"return")
 check(historical.route_hint=="城市货站 → 屋顶收件台" and historical.lines[0].text.contains("屋顶收件台"),"ground return before next day names actual roof destination")
 var prior_ledger:Dictionary=e.settled_ids.duplicate(true)
 check(e.close_day().ok and e.next_day().ok,"existing close/open day actions drive progression without a new subsystem")
 check(e.day==2 and e.jobs_today==0 and e.workshop_tier==1,"next day resets only quota while retaining paid workshop tier")
 check(e.contracts[0].id==1 and e.contracts[1].id==2,"day-two existing route selection unlocks rep 2 and rep 4 ascent contracts")
 for order in e.contracts:
  check(not order.has("route_profile") and order.control_version=="pilot-v3" and order.distance==520.0 and order.destination_y==-150.0,"day-two unlocked order retains original v3 ascent geometry")
 same(e.settled_ids,prior_ledger,"next day preserves unique ground ledger receipts")
 same(e.story_conversation(first_id,"return"),historical,"next-day return keeps exact saved ground dialogue after original contract array is discarded")
 check(e.pending_story_returns().size()==2,"both ground pending returns survive into space day")
 check(e.story_conversation(first_id,"result").title=="货站回执","next-day historical ground result is still a depot receipt")
 check(e.save_state(craft(),pad(),{}),"second morning saves old ground receipt beside new ascent orders")
 var loaded=Econ.new();loaded.load_state();loaded.enable_extreme_mode();loaded.enable_story_mode()
 same(loaded.story_conversation(first_id,"return"),historical,"restart on space day keeps historical ground destination")
 for order in loaded.contracts.duplicate(true):
  var cid:String=order.contract_id;loaded.accept_contract(cid)
  check(loaded.story_conversation(cid,"accept").lines[0].text.contains("星港"),"newly unlocked species story actually requests starport delivery")
  loaded.mark_cargo_loaded(cid);loaded.begin_dispatch(craft(),pad());loaded.settle_contract(cid,telemetry(),30.0,true)
  check(loaded.story_conversation(cid,"result").title=="星港回执","space job retains existing starport result title")
 check(loaded.settled_ids.size()==4 and loaded.jobs_today==2 and loaded.deliveries==4,"two days use four distinct existing settlement IDs and bounded daily quota")
 same(loaded.story_conversation(first_id,"return"),historical,"later ascent settlements cannot rewrite an earlier ground return")

func text_of(conversation:Dictionary) -> String:
 var result:String=str(conversation.get("title",""))+" "+str(conversation.get("route_hint",""))
 for line in conversation.get("lines",[]):result+=" "+str(line.text)
 return result

func test_story_destinations() -> void:
 for id in Stories.IDS:
  for node in [0,1,3]:
   var initial:Dictionary=Stories.initial_state(7421);initial.roster[id].story_node=node
   var cid:String=id+"-"+str(node)
   var order:Dictionary=Ground.route({"id":0,"contract_id":cid,"status":"available","appearance_id":id})
   var bound:Dictionary=Stories.bind_contract(initial,order,1,0)
   var accept:Dictionary=Stories.conversation_for(bound.state,bound.contract,"accept")
   check(text_of(accept).contains("屋顶收件台") and not text_of(accept).contains("星港") and not text_of(accept).contains("轨道"),"ground accept/repeat really requests local depot: %s node %d"%[id,node])
   check(accept.lines.size()==(3 if node==0 else 2),"ground story keeps lightweight first/repeat length")
   same(accept.actor,Stories.actor_metadata(bound.state.contract_bindings[cid]),"route copy never changes species/appearance/portrait/voice metadata")
   if node>0:check(accept.lines[0].text.contains("又来麻烦"),"ground repeat still acknowledges prior customer meeting")
   for success in [true,false]:
    bound.contract.status="settled"
    var result:Dictionary=Stories.commit_settlement(bound.state,bound.contract,{"contract_id":cid,"success":success})
    check(result.advanced and result.state.committed_contract_ids[cid].route_context.destination_name=="屋顶收件台","unique receipt captures local destination for %s outcome %s"%[id,str(success)])
    for beat in ["result","return"]:
     # No route dictionary is available to historical next-day requests.
     var historical:Dictionary=Stories.conversation_for(result.state,{"contract_id":cid},beat)
     check(text_of(historical).contains("屋顶收件台") and not text_of(historical).contains("星港") and not text_of(historical).contains("轨道"),"ground historical %s stays local for %s outcome %s"%[beat,id,str(success)])
     check(historical.lines[0].expression==("pleased" if success else ("concerned" if beat=="result" else "neutral")),"ground outcome retains its intended emotional response")
     if not success:check(historical.lines[0].text.contains("没送成" if beat=="result" else "包裹的事慢慢来"),"failed ground delivery never claims successful arrival")
    var misleading:Dictionary=Extreme.route({"contract_id":cid})
    same(Stories.conversation_for(result.state,misleading,"return"),Stories.conversation_for(result.state,{"contract_id":cid},"return"),"committed route context wins over a later misleading contract dictionary")
   # Legacy saved stories have no context; adding a current ground route cannot
   # reinterpret those already committed success-only entries.
   var old:Dictionary=bound.state.duplicate(true);old.committed_contract_ids[cid]={"success":true};old.pending_returns=[cid]
   var old_return:Dictionary=Stories.conversation_for(old,bound.contract,"return")
   check(old_return.route_hint=="晨星社区 → 星港中转站" and not text_of(old_return).contains("屋顶"),"old success-only receipt preserves prior default semantics: "+id)
   check(Stories.conversation_for(old,bound.contract,"result").title=="星港回执","old result stays a starport receipt even with a same-ID ground dictionary")
   same(Stories.normalize_state(old).committed_contract_ids[cid],{"success":true},"normalization never retrofits missing legacy route context")
  var legacy_order:Dictionary=Extreme.route({"contract_id":"legacy-"+id,"status":"available","appearance_id":id})
  legacy_order.distance=360.0;legacy_order.destination_y=-8.0;legacy_order.route_kind="ground"
  var legacy_bound:Dictionary=Stories.bind_contract(Stories.initial_state(),legacy_order,1,0)
  check(Stories.conversation_for(legacy_bound.state,legacy_bound.contract,"accept").lines[0].text.contains("星港"),"geometry or route_kind cannot reclassify a missing-profile legacy story: "+id)

func test_story_context_normalization() -> void:
 var bound:Dictionary=Stories.bind_contract(Stories.initial_state(),Ground.route({"contract_id":"context","status":"available"}),1,0)
 bound.contract.status="settled"
 var committed:Dictionary=Stories.commit_settlement(bound.state,bound.contract,{"contract_id":"context","success":true}).state
 var valid:Dictionary=committed.committed_contract_ids.context.route_context.duplicate(true)
 var original:Dictionary=committed.duplicate(true)
 same(Stories.normalize_state(JSON.parse_string(JSON.stringify(committed,"",true,true))),original,"new receipt context survives exact normalized JSON roundtrip")
 same(committed,original,"context normalization does not mutate caller-owned state")
 var malformed:Array=[null,true,42,"ground-city-v1",[],{}, {"route_profile":"ground-city-v1"}, valid.merged({"route_name":[]},true),valid.merged({"destination_name":{}},true),valid.merged({"route_profile":"unknown"},true),valid.merged({"destination_name":""},true),valid.merged({"route_name":"\nforged"},true),valid.merged({"route_name":"x".repeat(161)},true)]
 for value in malformed:
  var raw:Dictionary=committed.duplicate(true);raw.committed_contract_ids.context.route_context=value
  var normalized:Dictionary=Stories.normalize_state(raw)
  same(normalized.committed_contract_ids.context,{"success":true},"malformed optional destination context is safely discarded without losing valid receipt")
  check(normalized.pending_returns==["context"],"invalid copy context never drops a valid pending return")
 var extras:Dictionary=committed.duplicate(true);extras.committed_contract_ids.context.route_context.reward=99999;extras.committed_contract_ids.context.route_context.appearance_id="robot_machinist"
 same(Stories.normalize_state(extras),original,"context normalization strips reward/identity fields and keeps existing actor and receipt")
 var renamed:Dictionary=bound.contract.duplicate(true);renamed.destination_name="西区货站屋顶";renamed.name="城市货站 → 西区货站屋顶"
 var saved:Dictionary=Stories.commit_settlement(bound.state,renamed,{"contract_id":"context","success":true}).state
 var convo:Dictionary=Stories.conversation_for(Stories.normalize_state(saved),{"contract_id":"context"},"return")
 check(convo.route_hint==renamed.name and convo.lines[0].text.contains(renamed.destination_name),"historical ground copy uses exact saved destination rather than current profile defaults")

func test_read_skip_and_failure() -> void:
 clear_save();var e=shop();var cid:String=e.contracts[0].contract_id
 check(e.story_conversation(cid,"accept").is_empty(),"unaccepted ground story cannot open")
 e.accept_contract(cid);var before:Dictionary=ledger(e);var story:Dictionary=e.story_state.duplicate(true)
 for i in 12:e.story_actor(cid);e.story_conversation(cid,"accept");e.pending_story_returns();e.trial_route();e.estimate_delivery(e.active_contract(),telemetry(),22.0,true)
 same(ledger(e),before,"repeated ground dialogue/quote reads do not reward money, reputation or parts")
 same(e.story_state,story,"repeated ground reads do not advance story or consume dialogue")
 check(e.mark_story_seen(cid,cid+"/accept") and not e.mark_story_seen(cid,cid+"/accept"),"ground acceptance skip is saved once")
 same(ledger(e),before,"skipping acceptance grants no reward")
 check(not e.mark_story_seen(cid,"other/accept") and not e.mark_story_seen(cid,cid+"/invented"),"foreign/invented skip IDs stay blocked")
 e.mark_cargo_loaded(cid);e.begin_dispatch(craft(),pad())
 var result:Dictionary=e.settle_contract(cid,telemetry(),50.0,false)
 check(result.ok and result.report.income==0 and result.report.profit==-13 and e.credits==int(before.credits)-13,"failed ground job uses existing costs and never grants delivery income")
 check(e.jobs_today==1 and e.deliveries==0 and e.story_state.roster.human_courier.story_node==1,"failure uses one formal quota and one story advancement without a successful delivery")
 before=ledger(e)
 check(e.mark_story_seen(cid,cid+"/result") and e.mark_story_seen(cid,cid+"/return"),"failed ground result and return may each be skipped once")
 same(ledger(e),before,"skipping all failed delivery beats grants no refund or reward")
 check(e.pending_story_returns().is_empty() and e.story_conversation(cid,"result").is_empty(),"skipped ground result and return stay consumed")
 check(e.save_state(craft(),pad(),{}),"ground skipped dialogue flags save in the same v5 file")
 var restored=Econ.new();restored.load_state();restored.enable_extreme_mode();restored.enable_story_mode()
 same(ledger(restored),before,"restart after skip cannot duplicate costs or grant rewards")
 check(restored.pending_story_returns().is_empty() and restored.story_state.roster.human_courier.story_node==1,"skip and single failure advancement remain durable")
