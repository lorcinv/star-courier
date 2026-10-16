extends SceneTree
## Pure-data contracts/story/save tests. No simulation, main scene or GUI.
## Run in an authorized isolated review copy with a fresh XDG_DATA_HOME.
const Econ=preload("res://scripts/economy.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Wormhole=preload("res://scripts/pilot_wormhole_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const Pilot=preload("res://scripts/pilot_profile.gd")
var passed:int=0
var failed:int=0

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("Wormhole contract tests require an isolated XDG_DATA_HOME.");quit(2);return
 clear_save()
 test_three_day_progression();test_new_order_boundary();test_old_commitments()
 test_quote_dispatch_restart();test_invalid_protocols();test_save_versions();test_otherworld_stories();test_failure_and_skip()
 clear_save()
 print("WORMHOLE_CONTRACTS passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
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
func telemetry() -> Dictionary:
 # Total includes a 45.4 J station subtotal, not an additional future debit.
 return {"integrity":1.0,"energy_used":128.0,"wormhole_energy_used":45.4,"wormhole_transits":1,"wormhole_station_remaining":1954.6,"ammo_cost":2.0,"repair_cost":3.0,"lost_cost":4.0}
func ledger(e) -> Dictionary:
 return {"credits":e.credits,"reputation":e.reputation,"jobs_today":e.jobs_today,"deliveries":e.deliveries,"research":e.research,"workshop_tier":e.workshop_tier,"inventory":e.inventory.duplicate(true),"settled_ids":e.settled_ids.duplicate(true),"history":e.history.duplicate(true)}
func shop(rep:int=0,stories:bool=true):
 var e=Econ.new();e.reputation=rep;e.enable_extreme_mode();e.starter_stock(craft(),pad())
 if stories:e.story_state=Stories.initial_state(7421);e.enable_story_mode()
 return e
func text_of(conversation:Dictionary) -> String:
 var result:String=str(conversation.get("title",""))+" "+str(conversation.get("route_hint",""))
 for line in conversation.get("lines",[]):result+=" "+str(line.text)
 return result
func finish_day(e) -> void:
 for order in e.contracts.duplicate(true):
  var cid:String=order.contract_id
  check(e.accept_contract(cid).ok,"scheduled contract accepts "+cid)
  e.mark_cargo_loaded(cid);e.mark_story_seen(cid,cid+"/accept")
  check(e.begin_dispatch(craft(),pad()).ok,"scheduled contract formally commits "+cid)
  check(e.settle_contract(cid,telemetry(),22.0,true).ok,"synthetic intact receipt commits exactly once "+cid)
 check(e.close_day().ok and e.next_day().ok,"existing close/open actions advance one day")

func test_three_day_progression() -> void:
 var e=shop();var actor_seeds:Dictionary={}
 for id in Stories.IDS:actor_seeds[id]=e.story_state.roster[id].appearance_seed
 check(e.flight_mode=="pilot-v3" and e.contracts.size()==2,"workshop mode and bounded two-order day remain unchanged")
 for order in e.contracts:check(Ground.is_ground_route(order) and order.control_version=="pilot-v3","day one is the frozen v3 ground course")
 var first_id:String=e.contracts[0].contract_id
 finish_day(e)
 check(e.day==2 and e.reputation==4 and e.jobs_today==0,"two intact ground deliveries unlock day-two space at rep four")
 var ground_return:Dictionary=e.story_conversation(first_id,"return")
 for order in e.contracts:check(order.control_version=="pilot-v3" and not order.has("route_profile") and order.distance==520.0,"day-two offers keep original ascent trajectory")
 var old_orders:Array=e.contracts.duplicate(true)
 e.reputation=7;e.ensure_contracts();e.enable_extreme_mode()
 same(e.contracts,old_orders,"gaining rep mid-day never replaces already-created ascent offers")
 e.reputation=4;finish_day(e)
 check(e.day==3 and e.reputation==8 and e.contracts.size()==2,"four distinct good deliveries unlock subsequent third day")
 check(e.contracts[0].id==2 and e.contracts[0].control_version=="pilot-v3","day-three standard offer keeps its ascent route")
 var other:Dictionary=e.contracts[1]
 check(other.id==3 and other.rep==7 and other.contract_id=="D3-B" and other.control_version==Wormhole.CONTROL_VERSION,"existing rep-seven slot authors one new explicit v4 route")
 check(other.route_profile==Wormhole.ROUTE_PROFILE and other.distance==1240.0 and other.wormhole_portal.entry==[600.0,-150.0] and other.wormhole_portal.exit==[1000.0,-150.0],"offer persists exact restored portal and destination geometry")
 check(other.reward==395 and is_equal_approx(other.weight,3.72) and other.deadline==75.0,"heavy premium and restored deadline apply exactly once")
 check(e.settled_ids.size()==4 and e.deliveries==4 and e.history.size()==4,"unlock grants no bonus delivery, payment or ledger receipt")
 same(e.story_conversation(first_id,"return"),ground_return,"opening otherworld cannot rewrite saved ground return context")
 for id in Stories.IDS:check(e.story_state.roster[id].appearance_seed==actor_seeds[id],"same identity seed survives route progression "+id)
 var current:Array=e.contracts.duplicate(true);var before:Dictionary=ledger(e)
 for i in 15:e.ensure_contracts();e.enable_extreme_mode();e.available_contracts()
 same(e.contracts,current,"repeated catalog reads cannot duplicate or downgrade new wormhole orders")
 same(ledger(e),before,"progression and repeated reads are financially inert")

func test_new_order_boundary() -> void:
 for rep in [0,2,4,6,7,8,10]:
  var e=shop(rep,false)
  check(e.contracts.size()==2 and e.contracts[0].contract_id!=e.contracts[1].contract_id,"exactly two unique IDs at reputation %d"%rep)
  for order in e.contracts:
   if int(order.id)==3:
    check(rep>=7 and order.control_version==Wormhole.CONTROL_VERSION,"only unlocked route three becomes a wormhole offer")
   else:check(order.control_version=="pilot-v3","all other route IDs retain frozen v3")
  check(e.routes()[3].control_version=="pilot-v3" and not e.routes()[3].has("wormhole_portal"),"base catalog remains frozen; only contract creation authors v4")
 var old=shop(7,false);old.contracts=[]
 var order:Dictionary=Extreme.route(old._autonomous_routes()[3]);order.contract_id="D9-A";order.status="available";order.distance=567.125
 old.contracts=[order];var expected:Array=old.contracts.duplicate(true)
 old.ensure_contracts();old.enable_extreme_mode()
 same(old.contracts,expected,"an existing rep-seven v3 offer is not retrofitted into wormhole content")
 for mode in ["autonomous-v5","pilot-v1","pilot-v2"]:
  var legacy=Econ.new();legacy.flight_mode=mode;legacy.reputation=7;legacy.ensure_contracts()
  for contract in legacy.contracts:check(contract.get("control_version","")!=Wormhole.CONTROL_VERSION,"legacy authoring modes do not receive v4 offers")

func test_old_commitments() -> void:
 for version in ["","pilot-v1","pilot-v2","pilot-v3",Wormhole.CONTROL_VERSION]:
  clear_save();var e=Econ.new();e.reputation=7
  var order:Dictionary=e._autonomous_routes()[3]
  match version:
   "pilot-v1":order=Pilot.route(order)
   "pilot-v2":order=Ascent.route(order)
   "pilot-v3":order=Extreme.route(order)
   Wormhole.CONTROL_VERSION:order=Wormhole.route(order)
  order.contract_id="D1-A";order.status="accepted";order.accepted_day=1;order.distance+=.125
  if version in ["pilot-v2","pilot-v3",Wormhole.CONTROL_VERSION]:order.pilot_energy_tariff=.03125
  e.contracts=[order];e.active_contract_id=order.contract_id;e.phase="day"
  var expected:Dictionary=order.duplicate(true)
  for method in ["enable_extreme_mode","enable_ascent_mode","enable_pilot_mode","enable_extreme_mode"]:
   e.call(method);same(e.active_contract(),expected,"accepted route is immutable across %s for %s"%[method,version])
  check(e.save_state(craft(),pad(),{}),"accepted historical route saves normally "+version)
  var loaded=Econ.new();loaded.load_state();loaded.enable_extreme_mode()
  same(loaded.active_contract(),expected,"accepted saved route survives restart without reauthoring "+version)
  check(loaded.begin_dispatch(craft(),pad()).ok,"accepted saved route commits under its own rules "+version)
  loaded.in_flight.ticks=37;loaded.in_flight.elapsed=37.0/60.0
  if not version.is_empty():loaded.in_flight.input_commands.append({"tick":7,"axis_q":-1000,"boost":true,"active":false})
  var snapshot:Dictionary=loaded.in_flight.duplicate(true)
  check(loaded.save_state(craft(),pad(),{}),"historical in-flight checkpoint saves "+version)
  var resumed=Econ.new();resumed.load_state();resumed.enable_extreme_mode()
  same(resumed.in_flight,snapshot,"historical snapshot route/seed/time/input remain exact "+version)
  same(resumed.active_contract(),loaded.active_contract(),"historical in-flight order remains exact "+version)

func test_quote_dispatch_restart() -> void:
 clear_save();var e=shop(7);e.research=2;e.workshop_tier=1
 var cid:String=e.contracts[1].contract_id;e.accept_contract(cid);e.mark_cargo_loaded(cid)
 var order:Dictionary=e.active_contract();order.pilot_energy_tariff=.03125;order.distance=1260.125;order.wormhole_portal.station_energy_j=2050.0
 var before:Dictionary=ledger(e);var story:Dictionary=e.story_state.duplicate(true)
 var route:Dictionary=e.trial_route();var quote:Dictionary=e.estimate_delivery(order,telemetry(),60.0,true)
 same(ledger(e),before,"trial and single-bill quote never spend real money or a dispatch")
 same(e.story_state,story,"trial does not advance identity or story")
 check(quote.energy==4 and quote.energy_j==128.0 and quote.wormhole_energy_j==45.4 and quote.profit==382,"saved tariff bills ceil(128 x .03125) once; station subtotal is not added again")
 var fragments:Dictionary=telemetry();fragments.energy_used=173.4;fragments.wormhole_energy_used=90.8;fragments.wormhole_transits=2
 var split_quote:Dictionary=e.estimate_delivery(order,fragments,60.0,true)
 check(split_quote.energy==6 and split_quote.wormhole_transits==2 and split_quote.wormhole_energy_j==90.8,"two crossing islands remain one combined rounded bill with an island-count subtotal")
 var station_quote:Dictionary=Wormhole.transit_quote(order,10.2)
 check(station_quote.ok and is_equal_approx(station_quote.estimated_j,45.4) and is_equal_approx(station_quote.estimated_credits,1.41875) and not station_quote.separate_settlement_debit,"preflight station estimate uses same custom saved tariff")
 check(e.begin_dispatch(craft(),pad()).ok,"v4 commits using existing formal dispatch action")
 check(e.in_flight.control_version==Wormhole.CONTROL_VERSION and e.in_flight.ticks==0 and e.in_flight.input_commands==[{"tick":0,"axis_q":0,"boost":false,"active":false}],"v4 stores a neutral versioned pilot timeline, never autonomous replay")
 var formal:Dictionary=e.in_flight.route.duplicate(true);formal.seed=e.in_flight.seed;route.status="in_flight"
 same(formal,route,"trial and formal share exact route, seed, research and station capacity")
 e.in_flight.ticks=1800;e.in_flight.elapsed=30.0;e.in_flight.input_commands.append({"tick":400,"axis_q":-1000,"boost":false,"active":true})
 e.last_trials[cid]={"latest":quote.duplicate(true)}
 var checkpoint:Dictionary=e.in_flight.duplicate(true);var orders:Array=e.contracts.duplicate(true);var trials:Dictionary=e.last_trials.duplicate(true)
 var roundtrip:Dictionary=checkpoint.duplicate(true)
 for i in 12:
  roundtrip=JSON.parse_string(JSON.stringify(roundtrip,"",true,true))
  same(roundtrip,checkpoint,"full-precision JSON roundtrip %d keeps exact complete dispatch/route/input/seed"%i)
  check(roundtrip.route.weight==3.72 and roundtrip.seed==checkpoint.seed,"roundtrip %d keeps canonical 3.72 cargo multiplier and deterministic seed"%i)
  same(e.estimate_delivery(roundtrip.route,telemetry(),60.0,true),quote,"roundtrip %d keeps exact quote and one station-inclusive energy bill"%i)
 check(e.save_state(craft(),pad(),{}),"v4 checkpoint uses normal atomic save")
 check(disk().version==5 and Econ.SAVE_VERSION==5,"v4 route/timeline and optional receipt metadata require no save-schema bump")
 var restored=Econ.new();restored.load_state();restored.enable_extreme_mode();restored.enable_story_mode()
 same(restored.in_flight,checkpoint,"v4 restart preserves authoritative route and input checkpoint")
 same(restored.contracts,orders,"valid available/committed v4 route is never downgraded on production bootstrap")
 same(restored.last_trials,trials,"saved station quote and trial comparison survive restart")
 same(ledger(restored),before,"restart does not debit station energy or alter finite quota")
 var result:Dictionary=restored.settle_contract(cid,telemetry(),60.0,true)
 check(result.ok and result.story_advanced and restored.credits==int(before.credits)+382,"formal result applies identical quoted profit once")
 check(result.report.energy==4 and result.report.energy_j==128.0 and result.report.wormhole_energy_j==45.4 and result.report.wormhole_transits==1,"formal receipt stores combined energy plus explanatory station subtotal")
 check(result.report.route_context.route_profile==Wormhole.ROUTE_PROFILE and result.report.route_context.destination_name=="苔光驿站","financial receipt saves original otherworld route context")
 check(restored.jobs_today==1 and restored.deliveries==1 and restored.history.size()==1 and restored.settled_ids.size()==1,"one formal v4 receipt uses exactly one quota and one ledger entry")
 var committed:Dictionary=ledger(restored);story=restored.story_state.duplicate(true)
 check(restored.settle_contract(cid,telemetry(),1.0,false).get("duplicate",false),"duplicate result with conflicting outcome cannot replace receipt")
 same(ledger(restored),committed,"duplicate receipt never pays or debits again")
 same(restored.story_state,story,"duplicate receipt never advances the story twice")
 var returned:Dictionary=restored.story_conversation(cid,"return")
 check(restored.close_day().ok and restored.next_day().ok and restored.save_state(craft(),pad(),{}),"next day saves historical wormhole receipt with new offers")
 var next=Econ.new();next.load_state();next.enable_extreme_mode();next.enable_story_mode()
 same(next.settled_ids,restored.settled_ids,"settled ledger survives next-day restart without a second station charge")
 same(next.story_conversation(cid,"return"),returned,"otherworld return is exact after its source contract is discarded")

func test_invalid_protocols() -> void:
 var valid:Dictionary=Wormhole.route({"id":3,"rep":7,"reward":340,"required":90.0,"weight":2.4,"contract_id":"D1-X","status":"available"})
 var variants:Array=[]
 for version in ["pilot-future",null,7,true,[],{}]:
  var order:Dictionary=valid.duplicate(true);order.control_version=version;variants.append(order)
 var mismatch:Dictionary=valid.duplicate(true);mismatch.pilot_profile="pilot-v3";variants.append(mismatch)
 var legacy_portal:Dictionary=valid.duplicate(true);legacy_portal.control_version="pilot-v3";legacy_portal.pilot_profile="pilot-v3";variants.append(legacy_portal)
 var unknown_schema:Dictionary=valid.duplicate(true);unknown_schema.wormhole_schema=999;variants.append(unknown_schema)
 var bad_portal:Dictionary=valid.duplicate(true);bad_portal.wormhole_portal.entry=["bad",-150.0];variants.append(bad_portal)
 var absent:Dictionary=valid.duplicate(true);absent.erase("control_version");variants.append(absent)
 for order in variants:
  check(not Econ.route_validation_error(order).is_empty(),"malformed/unknown explicit route is rejected before use")
  var e=shop(7,false);e.contracts=[order];var expected:Dictionary=order.duplicate(true)
  e.enable_extreme_mode();e.ensure_contracts()
  same(e.contracts[0],expected,"mode migration never repairs an unknown or malformed route into v3")
  check(not e.accept_contract(str(order.contract_id)).ok,"malformed route cannot be accepted")
  e.contracts[0].status="accepted";e.active_contract_id=str(order.contract_id);e.phase="day"
  var before:Dictionary=ledger(e);expected=e.active_contract().duplicate(true)
  check(e.trial_route().is_empty() and not e.begin_dispatch(craft(),pad()).ok,"malformed trial and formal commitment both fail closed")
  same(e.active_contract(),expected,"rejected dispatch cannot flip the order into in-flight")
  same(ledger(e),before,"rejected route never awards money or consumes quota")
  check(e.in_flight.is_empty(),"rejected protocol cannot produce an autonomous fallback snapshot")
 var future=Econ.new();future.flight_mode="pilot-future";future.enable_extreme_mode();future.ensure_contracts()
 check(future.flight_mode=="pilot-future" and future.contracts.is_empty(),"unknown authoring mode cannot silently create replacement offers")
 for profile in [Pilot,Ascent,Extreme]:check(Econ.route_validation_error(profile.route()).is_empty(),"frozen valid legacy profile remains supported")

func test_save_versions() -> void:
 var validator=Econ.new()
 var base:Dictionary={"version":5,"design":[],"launcher":[],"workshop_tier":0}
 for version in [1,2,3,4,5,1.0,2.0,3.0,4.0,5.0]:
  var value:Dictionary=base.duplicate(true);value.version=version
  check(validator._valid_save(value),"known integral numeric save version stays compatible "+str(version))
 for version in [null,true,false,"5","1",[],{},NAN,INF,-INF,5.5,4.1,0,-1,6,999]:
  var value:Dictionary=base.duplicate(true);value.version=version
  check(not validator._valid_save(value),"malformed/unknown top-level save version is rejected without coercion "+str(version))
 clear_save();var original=shop(7,false);original.credits=321
 check(original.save_state(craft(),pad(),{}),"valid backup fixture saves")
 original.credits=456;check(original.save_state(craft(),pad(),{}),"second valid save retains prior validated backup")
 var corrupted:Dictionary=disk();corrupted.version=5.5;corrupted.credits=99999
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(corrupted));file.close()
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var recovered=Econ.new();var parsed:Dictionary=recovered.load_state()
 check(not parsed.is_empty() and recovered.credits==321 and recovered.load_notice.contains("备份"),"fractional-version primary fails closed into the existing valid backup")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"read-only recovery preserves malformed primary bytes until an explicit save")
 clear_save()

func test_otherworld_stories() -> void:
 for id in Stories.IDS:
  for node in [0,1,3]:
   var initial:Dictionary=Stories.initial_state(7421);initial.roster[id].story_node=node
   var cid:String=id+"-"+str(node)
   var order:Dictionary=Wormhole.route({"contract_id":cid,"status":"available","appearance_id":id})
   order.name="城市货站 → 晨星虫洞 → 北侧苔光台";order.destination_name="北侧苔光台"
   var bound:Dictionary=Stories.bind_contract(initial,order,3,0)
   var acceptance:Dictionary=Stories.conversation_for(bound.state,bound.contract,"accept")
   check(text_of(acceptance).contains("北侧苔光台") and text_of(acceptance).contains("虫洞") and not text_of(acceptance).contains("星港中转站"),"otherworld acceptance names the actual route for %s node %d"%[id,node])
   check(acceptance.lines.size()==(3 if node==0 else 2),"first/repeat otherworld dialogue remains brief")
   same(acceptance.actor,Stories.actor_metadata(bound.state.contract_bindings[cid]),"new route copy never rerolls identity, portraits, seed or voice")
   for success in [true,false]:
    bound.contract.status="settled"
    var result:Dictionary=Stories.commit_settlement(bound.state,bound.contract,{"contract_id":cid,"success":success})
    check(result.advanced and result.state.roster[id].story_node==mini(node+1,3),"one receipt advances the existing bounded story node once")
    check(result.state.committed_contract_ids[cid].route_context.destination_name=="北侧苔光台","unique story receipt saves exact custom otherworld destination")
    var normalized:Dictionary=Stories.normalize_state(JSON.parse_string(JSON.stringify(result.state,"",true,true)))
    same(normalized,result.state,"optional v4 story context round-trips under unchanged story schema")
    for beat in ["result","return"]:
     var historical:Dictionary=Stories.conversation_for(normalized,{"contract_id":cid},beat)
     check(text_of(historical).contains("北侧苔光台") and not text_of(historical).contains("星港中转站"),"historical otherworld beat uses saved context "+id+"/"+beat)
     if beat=="result":check(historical.title=="异界回执","actual v4 receipt has otherworld title")
     if not success:check(not text_of(historical).contains("签收") and not text_of(historical).contains("装好了"),"failed otherworld copy never claims successful delivery")
     same(Stories.conversation_for(normalized,Ground.route({"contract_id":cid}),beat),historical,"receipt context wins over misleading current ground data")
   var old:Dictionary=bound.state.duplicate(true);old.committed_contract_ids[cid]={"success":true};old.pending_returns=[cid]
   check(Stories.conversation_for(old,order,"result").title=="星港回执","old success-only receipt never acquires otherworld semantics")
   same(Stories.normalize_state(old).committed_contract_ids[cid],{"success":true},"normalization never fabricates route context for an old receipt")

func test_failure_and_skip() -> void:
 clear_save();var e=shop(7);var cid:String=e.contracts[1].contract_id;e.accept_contract(cid);e.mark_cargo_loaded(cid)
 var before:Dictionary=ledger(e);var story:Dictionary=e.story_state.duplicate(true)
 for i in 10:e.story_conversation(cid,"accept");e.trial_route();e.estimate_delivery(e.active_contract(),telemetry(),60.0,true)
 same(ledger(e),before,"repeated quote/dialogue reads never give station refunds or rewards")
 same(e.story_state,story,"reads never consume story beats")
 check(e.mark_story_seen(cid,cid+"/accept") and not e.mark_story_seen(cid,cid+"/accept"),"acceptance skip is idempotent")
 e.begin_dispatch(craft(),pad());var result:Dictionary=e.settle_contract(cid,telemetry(),99.0,false)
 check(result.ok and result.report.income==0 and result.report.energy==4 and result.report.profit==-13,"failed otherworld flight bills the same single combined energy cost without income")
 check(e.jobs_today==1 and e.deliveries==0 and e.reputation==6,"failure consumes one daily slot and existing reputation penalty")
 before=ledger(e)
 check(e.mark_story_seen(cid,cid+"/result") and e.mark_story_seen(cid,cid+"/return"),"failed result and return can be consumed once")
 same(ledger(e),before,"skipping failed dialogue grants no refund or reward")
 check(e.save_state(craft(),pad(),{}),"failure/skip persists with the same financial ledger")
 var restored=Econ.new();restored.load_state();restored.enable_extreme_mode();restored.enable_story_mode()
 same(ledger(restored),before,"restart cannot reapply failed-flight costs")
 check(restored.pending_story_returns().is_empty() and restored.story_state.roster.elf_archivist.story_node==1,"skips and single failure story advancement remain durable")
