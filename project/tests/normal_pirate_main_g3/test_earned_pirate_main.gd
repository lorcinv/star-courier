extends "res://tests/normal_pirate_main_g3/earned_main_base.gd"
## Actual Main/API continuation from original earned save. Never native-input QA.
## Only the copied candidate's reviewed exact admission constant may be enabled.
const Offer=preload("res://scripts/pirate_sidejob_offer_v1.gd")
const SOURCE_SHA="c407d992950d9b30c10f66d9714156f651599cadf72f1d5fb7bf4c296fd7ca6d"
var output:String=""
var source_path:String=""
var mode:String="prepared"
var initial:Dictionary={}
var checkpoints:Array=[]
var flights:Array=[]
var offers:Array=[]
var contract_id:String=""
var source_copy_verified:bool=false

func _initialize() -> void:run.call_deferred()
func write_json(name:String,value:Variant) -> void:
 var f=FileAccess.open(output.path_join(name),FileAccess.WRITE)
 if f!=null:f.store_string(JSON.stringify(value,"  ",true,true));f.close()
func complete_state() -> Dictionary:
 var result:Dictionary={}
 for key in game.economy.SHOP_TRANSACTION_FIELDS:
  var value:Variant=game.economy.get(key)
  result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func capture(label:String) -> void:
 if output.is_empty() or not is_instance_valid(game):return
 var record:Dictionary={"label":label,"stage":stage,"page":game.page,"state":complete_state(),"published_reviews":game.economy.customer_reviews().duplicate(true),"design":game.design.duplicate(true),"launcher":game.launcher.duplicate(true),"save_sha256":FileAccess.get_sha256("user://savegame.json"),"toast":str(game.hud._toast_raw_text) if is_instance_valid(game.hud) else "","diagnostic":game._pirate_diagnostic.duplicate(true)}
 if game.sim!=null and game.sim.has_method("save_candidate_json"):
  var native:Dictionary=game.sim.save_candidate_json()
  record.native_ok=bool(native.get("ok",false))
  if native.get("ok",false):
   var f=FileAccess.open(output.path_join(label+"-full-native.json"),FileAccess.WRITE)
   if f!=null:f.store_string(native.json);f.close()
  record.input_commands=game.pilot_timeline.snapshot();record.ticks=game.pilot_completed_ticks
  record.telemetry=game.sim.telemetry.duplicate(true);record.terminal=game.sim.route_terminal.duplicate(true)
 for file in ["savegame.json","savegame.backup.json"]:
  if FileAccess.file_exists("user://"+file):DirAccess.copy_absolute("user://"+file,output.path_join(label+"-"+file))
 write_json(label+"-state.json",record);checkpoints.append({"label":label,"save_sha256":record.save_sha256,"page":record.page})
func restart_boundary(label:String) -> bool:
 if not check(game.save_game(),label+" persists through actual Main"):return false
 var before:Dictionary=complete_state();var craft:Array=game.design.duplicate(true);var pad:Array=game.launcher.duplicate(true)
 capture(label+"-before-restart")
 if not await boot():return false
 check(equal(complete_state(),before) and equal(game.design,craft) and equal(game.launcher,pad),label+" restart retains all economic/story/review/offer values and exact blueprints")
 capture(label+"-after-restart")
 return failed==0
func original_receipts_exact() -> bool:
 for id in initial.settled_ids:
  if not game.economy.settled_ids.has(id) or not equal(game.economy.settled_ids[id],initial.settled_ids[id]):return false
 return true
func skip_available_pair(label:String) -> bool:
 var e=game.economy;var before:Dictionary=ledger();var authored:Array=e.contracts.duplicate(true)
 if not check(authored.size()==2 and e.active_contract_id.is_empty() and e.in_flight.is_empty(),label+" begins with the unmodified available pair"):return false
 for original in authored:
  if not check(original.get("status")=="available",label+" only explicitly declines an available existing offer"):return false
  game._action("decline_contract",str(original.contract_id));await frames()
  var after:Dictionary={}
  for row in e.contracts:
   if row.get("contract_id")==original.contract_id:after=row.duplicate(true)
  if not check(after.get("status")=="declined",label+" real Main decline commits "+str(original.contract_id)):return false
  after.status=original.status # Detached assertion copy only; never written back.
  check(equal(after,original),label+" decline preserves every authored field for "+str(original.contract_id))
 check(equal(ledger(),before),label+" decline has no fee, reputation, stock, quota, receipt or review side effect")
 capture(label+"-declined")
 return failed==0
func next_morning(label:String) -> bool:
 var e=game.economy;var day_before:int=e.day;var money:int=e.credits;var rep:int=e.reputation;var receipts:Dictionary=e.settled_ids.duplicate(true)
 game._action("close_day",null);await frames()
 if not check(e.day==day_before and e.phase=="night",label+" actual Main close_day enters night"):return false
 capture(label+"-night")
 if not await restart_boundary(label+"-night"):return false
 e=game.economy
 game._action("next_day",null);await frames()
 if not check(e.day==day_before+1 and e.phase=="morning" and e.jobs_today==0,label+" actual Main next_day commits a fresh morning"):return false
 check(e.credits==money and e.reputation==rep and equal(e.settled_ids,receipts),label+" next_day neither grants nor repays economic progress")
 capture("day%d-generated"%e.day)
 var state:Dictionary=complete_state();var durable:PackedByteArray=bytes()
 game._action("next_day",null)
 check(equal(complete_state(),state) and bytes()==durable,label+" duplicate next_day cannot reroll or republish")
 return failed==0
func generated_offer() -> bool:
 var e=game.economy
 if not check(e.contracts.size()==2,"newly generated morning has exactly the ordinary A and optional B slots"):return false
 var a:Dictionary=e.contracts[0];var b:Dictionary=e.contracts[1]
 if not Offer.has_markers(b):
  capture("day%d-no-pirate-retained"%e.day)
  write_json("DEFERRED.json",{"day":e.day,"root":e.offer_generation_state,"offers":e.contracts,"notice":e.load_notice,"message":"No fixture rewrite. Retain both authored offers. Parent must inspect actual deferral and continue only with normal actions in a successor run."})
  return check(false,"expected genuinely authored D5 optional B is absent; preserved deferral requires inspection")
 check(a.get("contract_id")=="D%d-A"%e.day and a.get("status")=="available" and not Offer.has_markers(a) and a.get("control_version")=="pilot-v3" and e.route_preflight_error(a).is_empty(),"A remains an ordinary validated ground/ascent offer")
 check(b.get("contract_id")=="D%d-B"%e.day and b.get("status")=="available" and Offer.validation_error(b).is_empty() and e.route_preflight_error(b).is_empty(),"B is a genuinely generated and admitted dedicated v2 side job")
 check(int(b.id)==5 and int(b.reward)==340 and float(b.weight)==1.55 and int(b.seed)==e.day*100+16 and b.generation.version=="pirate-sidejob-offers-v1" and int(b.generation.day)==e.day and int(b.generation.slot)==1 and int(b.generation.world_seed)==7421,"B carries exact saved commercial identity, physical seed and earned world provenance")
 check(e.offer_generation_state.version=="seeded-protected-bird-policy-v3-pirate-a1" and int(e.offer_generation_state.pirate_introduced_day)==e.day,"introduction stamp belongs to this saved freshly authored pair")
 check(original_receipts_exact() and e.deliveries==6 and e.settled_ids.size()==6 and equal(game.design,initial.design) and equal(game.launcher,initial.launcher) and equal(e.inventory,initial.inventory),"all six earned receipts and finite owned craft/launcher/stock remain exact")
 offers=e.contracts.duplicate(true);contract_id=str(b.contract_id)
 write_json("GENERATED-OFFER.json",{"contract_id":contract_id,"day":e.day,"root":e.offer_generation_state,"ordinary_a":a,"optional_b":b,"origin":"Main decline D4-A/B → close_day → next_day; no authoring API called by fixture"})
 return failed==0
func wait_story(beat:String) -> bool:
 for unused in 3600:
  if game._dialogue_is_open():break
  shop_step(1.0/120.0)
 return check(game._dialogue_is_open() and game._active_story.get("beat")==beat and game._active_story.get("contract_id")==contract_id,"actual Main opens matching "+beat+" dialogue")
func finish_return() -> bool:
 if not await wait_story("result"):return false
 capture("paid-result-dialogue")
 game.dialogue.skip_conversation();await frames();game._action("close_drawer",null);await frames()
 if not await wait_story("return"):return false
 capture("paid-return-dialogue")
 game.dialogue.skip_conversation();await frames();shop_step(3.0)
 return check(game.page=="hub" and not game._dialogue_is_open() and game._pending_story.is_empty() and game.economy.pending_story_returns().is_empty() and game.economy.active_contract_id.is_empty(),"actual result and return callbacks both finish before clean hub")
func warning_restart(label:String) -> bool:
 game._on_focus_exited()
 if not check(game.paused and not game.pilot_resume_blocked,label+" actual focus action saves and neutralizes the running Main flight"):return false
 var expected:Dictionary=game.sim.save_candidate_json();var commands:Array=game.pilot_timeline.snapshot();var tick:int=game.pilot_completed_ticks;var business:Dictionary=complete_state()
 if not check(expected.get("ok",false),label+" complete typed native packet serializes"):return false
 capture(label+"-before-restart")
 if not await boot():return false
 var actual:Dictionary=game.sim.save_candidate_json() if game.sim!=null else {}
 check(game.page=="flight" and game.paused and actual.get("ok",false) and actual.get("json")==expected.get("json") and game.pilot_completed_ticks==tick and equal(game.pilot_timeline.snapshot(),commands) and equal(complete_state(),business),label+" replay restores entire native packet/base/structure plus command and business state")
 capture(label+"-after-restart")
 game._on_focus_entered();game._set_paused(false)
 return failed==0
func trial_and_prepared_commit() -> bool:
 var before:Dictionary=ledger();var route:Dictionary=game.economy.trial_route().duplicate(true)
 game._action("trial",null)
 if not check(game.page=="flight" and game.trial and game.economy.in_flight.is_empty() and equal(ledger(),before),"real trial prepares the authored route without creating a paid dispatch"):return false
 check(equal(game.flight_order,route) and int(game.flight_order.seed)==516,"trial uses the exact saved D5-B route and seed")
 capture("trial-prepared-no-charge")
 # First gate tests cancellation/no-charge only. This is a real trial abort,
 # not a success witness; no synthetic terminal assignment or guide is used.
 game._action("abort",null)
 if not check(game.page=="report" and game.trial and equal(ledger(),before) and game.economy.in_flight.is_empty(),"explicit trial abort records a trial result without charges, quota or receipt"):return false
 capture("trial-aborted-no-charge")
 game._action("close_drawer",null);await frames()
 if not await restart_boundary("trial-no-charge"):return false
 check(equal(ledger(),before) and game.economy.is_cargo_loaded(contract_id),"trial restart preserves the available paid slot and loaded accepted order")
 route=game.economy.trial_route().duplicate(true)
 game._action("dispatch",null)
 if not check(game.page=="flight" and not game.trial and game.economy.in_flight.get("contract_id")==contract_id,"actual Main begins the single prepared paid dispatch"):return false
 check(equal(game.economy.in_flight.route,route) and equal(game.economy.in_flight.design,game.design) and equal(game.economy.in_flight.launcher,game.launcher) and int(game.economy.in_flight.seed)==int(route.seed),"atomic paid commit preserves exact prepared route, seed, craft and launcher")
 check(equal(ledger(),before) and game.pilot_completed_ticks==0 and int(disk().in_flight.ticks)==0,"prepared paid commit is durable before any flight tick or financial settlement")
 var committed:Dictionary=game.economy.in_flight.duplicate(true);game._action("dispatch",null)
 check(equal(game.economy.in_flight,committed),"duplicate dispatch cannot replace or duplicate the committed order")
 capture("paid-prepared-tick-zero")
 if not await warning_restart("paid-prepared-tick-zero"):return false
 # Leave the restored dispatch paused. No paid outcome is manufactured.
 game._set_paused(true)
 capture("paid-prepared-restored-paused")
 return check(equal(ledger(),before) and game.economy.settled_ids.size()==6 and game.economy.deliveries==6 and original_receipts_exact(),"paid restart still has six actual receipts and no seventh delivery claim") and failed==0
func fly(is_trial:bool) -> bool:
 var label:String="trial" if is_trial else "paid";var before:Dictionary=ledger();var prepared_route:Dictionary=game.economy.trial_route().duplicate(true)
 game._action("trial" if is_trial else "dispatch",null)
 if not check(game.page=="flight" and game.trial==is_trial,label+" enters actual Main flight"):return false
 if is_trial:
  check(game.economy.in_flight.is_empty() and equal(ledger(),before),"trial does not create a paid dispatch or consume money/quota")
 else:
  check(equal(game.economy.in_flight.route,prepared_route) and equal(game.economy.in_flight.design,game.design) and equal(game.economy.in_flight.launcher,game.launcher) and int(game.economy.in_flight.seed)==int(prepared_route.seed),"paid commit preserves the exact prepared route/seed/design/launcher")
  var committed:Dictionary=game.economy.in_flight.duplicate(true);game._action("dispatch",null)
  check(equal(game.economy.in_flight,committed),"duplicate paid dispatch does not replace the committed identity")
 capture(label+"-launch")
 for unused in 1200:
  if game.launch_countdown<=0.0:break
  game._process(1.0/60.0)
 if not check(game.launch_countdown<=0.0,label+" real launch transfer and charge complete"):return false
 var budget:float=game.sim.total_energy()+float(game.sim.telemetry.energy_used);var min_energy:float=game.sim.total_energy();var drift:float=0.0;var axis:int=0;var warning_seen:bool=false
 var limit:int=ceili(float(prepared_route.time_limit)*60.0)+1
 while game.sim.status=="running" and game.pilot_completed_ticks<limit:
  # Byte-identical inherited ordinary guide and command body; no new solver.
  if game.pilot_completed_ticks%12==0:axis=guide()
  command(axis);game._step_flight()
  min_energy=minf(min_energy,game.sim.total_energy());drift=maxf(drift,absf(game.sim.total_energy()+float(game.sim.telemetry.energy_used)-budget))
  if not is_trial and not warning_seen and not game.sim.pirate.warnings.is_empty():
   warning_seen=true
   if not await warning_restart(label+"-first-warning"):return false
   axis=guide()
 if not check(game.sim.status in ["success","failed"] and not game.pilot_resume_blocked and game.sim.chrono_error.is_empty(),label+" reaches a genuine terminal without hold or forced outcome"):return false
 capture(label+"-terminal")
 # Main finalizes and settles its real runtime. Failure is preserved and paid
 # when normal settlement says so; a failed physical attempt is never retried.
 game.finish_flight();capture(label+"-report")
 if not check(game.page=="report",label+" Main completes its normal report transaction"):return false
 var outcome:Dictionary={"kind":label,"contract_id":contract_id,"status":game.sim.status,"elapsed":game.sim.elapsed,"minimum_energy":min_energy,"maximum_energy_drift":drift,"full_telemetry":game.sim.telemetry.duplicate(true),"terminal":game.sim.route_terminal.duplicate(true),"warnings":game.sim.pirate.warnings.duplicate(true),"emissions":game.sim.pirate.emissions.duplicate(true),"rays":game.sim.route_ray_records.duplicate(true),"commands":game.pilot_timeline.snapshot(),"report":game.report.duplicate(true)}
 flights.append(outcome);write_json(label+"-outcome.json",outcome)
 check(min_energy>=-0.000001 and drift<0.01,label+" preserves finite courier storage")
 if is_trial:
  check(equal(ledger(),before) and game.economy.in_flight.is_empty(),"completed trial leaves money/stock/quota/receipts/reviews unchanged")
  game._action("close_drawer",null);await frames()
 else:
  if not check(game.economy.settled_ids.has(contract_id),"paid report has a durable unique receipt"):return false
  var receipt:Dictionary=game.economy.settled_ids[contract_id]
  check(receipt.profit==receipt.income-receipt.energy-receipt.ammo-receipt.repairs-receipt.lost and game.economy.credits==int(before.credits)+int(receipt.profit),"paid credits reconcile with every itemized cost")
  check(game.economy.jobs_today==int(before.jobs)+1 and game.economy.settled_ids.size()==7 and game.economy.in_flight.is_empty() and original_receipts_exact(),"one paid receipt consumes one slot and preserves all original receipts")
  check(game.economy.review_state.pending.has(contract_id) and not game.economy.review_state.pending[contract_id].has("rating") and game.economy.customer_reviews().size()==6,"new review remains unpublished on delivery day")
  var once:Dictionary=ledger();var durable:PackedByteArray=bytes();game.finish_flight();game.abort_flight()
  check(equal(ledger(),once) and bytes()==durable,"duplicate finish/abort after paid report stays inert")
  if not await finish_return():return false
 check(game.sim.status=="success" and game.sim.elapsed<=float(prepared_route.deadline) and float(game.sim.telemetry.integrity)>=float(prepared_route.required)/100.0,label+" guide physically delivers on time with required integrity; failed attempts remain recorded")
 return failed==0
func run() -> void:
 output=OS.get_environment("SC_G3_OUT");source_path=OS.get_environment("SC_G3_SOURCE");mode=OS.get_environment("SC_G3_MODE")
 var profile:String=OS.get_environment("SC_G3_PROFILE").simplify_path().trim_suffix("/");var user_dir:String=ProjectSettings.globalize_path("user://").simplify_path()
 if not check(OS.get_environment("SC_G3_ENGINE_GRANTED")=="1" and DisplayServer.get_name()=="headless" and mode in ["access","loaded","prepared","lifecycle"] and not output.is_empty() and profile.is_absolute_path() and "/normal-pirate-main-g3/" in profile and user_dir.begins_with(profile+"/"),"explicit isolated headless grant and profile required"):await finish();return
 if mode=="lifecycle" and not check(OS.get_environment("SC_G3_UNCHANGED_GUIDE_FIT_VERIFIED")=="1","full-flight mode requires separately pinned unchanged-guide fit evidence"):await finish();return
 if not check(FileAccess.file_exists(source_path) and FileAccess.get_sha256(source_path)==SOURCE_SHA and not source_path.simplify_path().begins_with(profile+"/"),"exact legitimate six-receipt D4 source verified"):await finish();return
 if not check(not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"new private run cannot overwrite an earlier failed state"):await finish();return
 DirAccess.make_dir_recursive_absolute(user_dir)
 if not check(DirAccess.copy_absolute(source_path,"user://savegame.json")==OK and FileAccess.get_sha256("user://savegame.json")==SOURCE_SHA,"byte-exact original copied into empty private profile"):await finish();return
 source_copy_verified=true;initial=disk();root.size=Vector2i(1280,720)
 if not await boot():await finish();return
 var e=game.economy
 if not check(game.PIRATE_PLAYER_ROUTE_REGISTERED and e.day==4 and e.phase=="morning" and e.credits==1146 and e.reputation==12 and e.research==0 and e.workshop_tier==1 and e.deliveries==6 and e.settled_ids.size()==6 and e.jobs_today==0 and e.in_flight.is_empty() and e.active_contract_id.is_empty(),"isolated exact-admission Main loads actual earned D4 state without progress injection"):await finish();return
 check(equal(e.contracts,initial.contracts) and equal(e.offer_generation_state,initial.offer_generation_state),"startup preserves BOTH already-authored D4 offers and their old root exactly")
 capture("original-d4-loaded")
 if not await restart_boundary("original-d4"):await finish();return
 if not await skip_available_pair("day4"):await finish();return
 stage="author-d5"
 if not await next_morning("day4"):await finish();return
 if not generated_offer():await finish();return
 if not await restart_boundary("generated-d5"):await finish();return
 if mode=="access":stage="complete";await finish();return
 stage="counter-loading"
 if not await accept(contract_id,false,true):capture("accept-loading-blocked");await finish();return
 if not await restart_boundary("loaded-optional-offer"):await finish();return
 if mode=="loaded":stage="complete";await finish();return
 if mode=="prepared":
  stage="trial-paid-commit"
  if not await trial_and_prepared_commit():await finish();return
  stage="complete";await finish();return
 stage="trial"
 if not await fly(true):await finish();return
 if not await restart_boundary("trial-completed"):await finish();return
 stage="paid"
 if not await fly(false):await finish();return
 if not await restart_boundary("paid-returned-hub"):await finish();return
 check(game.page=="hub" and game.sim==null and not game._dialogue_is_open() and game.economy.pending_story_returns().is_empty(),"clean hub restart has no repeated return or ghost flight")
 stage="delayed-review"
 if not await next_morning("paid-day5"):await finish();return
 check(game.economy.customer_reviews().size()==7 and game.economy.review_state.pending.is_empty() and original_receipts_exact(),"only next morning publishes exactly one new optional-job review")
 if not await restart_boundary("review-published"):await finish();return
 stage="complete";await finish()
func finish() -> void:
 if is_instance_valid(game):capture("final-"+stage)
 if not output.is_empty():write_json("G3-RESULT.json",{"stage":stage,"mode":mode,"passed":passed,"failed":failed,"failures":failures,"source_copy_verified":source_copy_verified,"source_unchanged":not source_path.is_empty() and FileAccess.get_sha256(source_path)==SOURCE_SHA,"offers":offers,"flights":flights,"checkpoints":checkpoints,"native_input":false,"production_enabled":false,"proof":"isolated exact-admission actual Main/API; inherited W/S guide, no new solver, no QA offer splice; native/G4/G5 remain separate"})
 print("EARNED_PIRATE_G3 mode=%s passed=%d failed=%d stage=%s native_input=false"%[mode,passed,failed,stage])
 await dispose();quit(0 if stage=="complete" and failed==0 else 1)
