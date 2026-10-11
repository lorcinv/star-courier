extends SceneTree
## Headless controller integration. Fixture prior progression is synthetic.
## Flights use the real saved commercial 2.4 kg factor and recorded W/S commands.
## No native input, visual quality or performance claim.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const Sim=preload("res://scripts/pilot_protected_bird_simulation.gd")
const Offer=preload("res://scripts/protected_bird_offer_v1.gd")
const Policy=preload("res://scripts/protected_bird_authoring_policy.gd")
const Evidence=preload("res://scripts/protected_bird_settlement_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
const Receipt=preload("res://scripts/flight_receipt.gd")
var passed:int=0
var failed:int=0
var game
var fixtures:Dictionary={}

class FailingEconomy:
 extends "res://scripts/economy.gd"
 var fail_save:bool=false
 var save_calls:int=0
 func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
  save_calls+=1
  if fail_save:save_error="进度暂时无法保存。";return false
  return super.save_state(design,launcher,settings)

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated XDG_DATA_HOME required.");quit(2);return
 for kind in ["safe","harm"]:
  fixtures[kind]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/protected_bird_controller/commercial-replay-%s.json"%kind))
 run.call_deferred()

func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func bytes(value:Variant) -> String:return JSON.stringify(value,"",true,true)
func same(a:Variant,b:Variant,label:String) -> void:
 check(a==b,label)
 if a!=b:print("ACTUAL ",bytes(a));print("EXPECTED ",bytes(b))
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func clear_save() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
func write_fixture(data:Dictionary) -> void:
 var f=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_string(bytes(data));f.close()
 if FileAccess.file_exists("user://savegame.backup.json"):DirAccess.remove_absolute("user://savegame.backup.json")
func frames(count:int=3) -> void:
 for i in count:await process_frame
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await frames()
 game=null
func fresh() -> void:
 await dispose()
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false)
 if is_instance_valid(game.world):game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames()
 if is_instance_valid(root.gui_get_focus_owner()):root.gui_get_focus_owner().release_focus()
func setup() -> void:
 await dispose();clear_save()
 var e=Econ.new();e.day=5;e.reputation=7;e.flight_mode=Extreme.CONTROL_VERSION;e.workshop_tier=2
 e.story_state=Stories.initial_state(420)
 e.offer_generation_state={"version":Policy.VERSION,"world_seed":420,"introduced_day":0}
 e.starter_stock(Extreme.starter_design(),Extreme.starter_launcher());e.enable_story_mode()
 check(e.accept_contract("D5-A").ok,"accept actual authored D5-A introduction")
 e.mark_story_seen("D5-A","D5-A/accept");e.mark_cargo_loaded("D5-A")
 check(e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{"reduced_motion":true}),"save synthetic day-five setup without fake bird receipts")
 await fresh()
 check(not game.economy.review_load_blocked and game.economy.active_contract().seed==670371318,"real scene boot retains exact offered seed")
 game.navigate("workshop")
func ledger() -> Dictionary:
 var result:Dictionary={}
 for key in ["credits","reputation","day","jobs_today","deliveries","workshop_tier","inventory","settled_ids","history","story_state","review_state"]:
  var value:Variant=game.economy.get(key);result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result
func state() -> Dictionary:
 var result:Dictionary={}
 for property in game.sim.get_property_list():
  if not (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE):continue
  var name:String=property.name
  if name in ["pilot_axis_q","pilot_boost","pilot_active"]:continue
  var value:Variant=game.sim.get(name)
  if value is RandomNumberGenerator:result[name]={"seed":value.seed,"state":value.state}
  elif value is Dictionary or value is Array:result[name]=value.duplicate(true)
  else:result[name]=value
 for key in ["pilot_axis_q","pilot_boost","pilot_active","overdrive"]:result.telemetry.erase(key)
 return result
func drive(command:Dictionary) -> void:
 game._clear_pilot_input()
 for pair in [[KEY_W,int(command.axis_q)<0],[KEY_S,int(command.axis_q)>0],[KEY_SHIFT,bool(command.boost)],[KEY_SPACE,bool(command.active)]]:
  if pair[1]:
   var event=InputEventKey.new();event.keycode=pair[0];event.physical_keycode=pair[0];event.pressed=true;game._unhandled_key_input(event)
func replay(kind:String,stop_at:int=-1) -> void:
 var source:Dictionary=fixtures[kind];var timeline=Timeline.new()
 check(timeline.restore(source.commands,int(source.completed_command_ticks)),"recorded "+kind+" timeline validates")
 var end:int=int(source.completed_command_ticks) if stop_at<0 else stop_at
 while game.pilot_completed_ticks<end and game.sim.status=="running":
  drive(timeline.state_at(game.pilot_completed_ticks));game._step_flight()
func copy_is_clear() -> bool:
 var visible:String=""
 for node in game.hud.content.find_children("*","Label",true,false):visible+=" "+node.text
 for code in ["pilot-v5","protected-bird","mosslight_leafwing","completion_","bird_offer_","physics_ticks","command_ticks"]:
  if visible.contains(code):return false
 return true
func terminal_capture(kind:String) -> Dictionary:
 check(game.sim.status=="success" and game.pilot_completed_ticks==int(fixtures[kind].completed_command_ticks),kind+": complete actual controller flight at expected command tick")
 check(absf(game.sim.elapsed-(51.2916666666667 if kind=="safe" else 51.5666666666667))<.000001,kind+": fixed commercial elapsed matches physical witness")
 return {"ticks":game.pilot_completed_ticks,"commands":game.pilot_timeline.snapshot(),"result":game.sim.wildlife_result().duplicate(true),"elapsed":game.sim.elapsed,"telemetry":game.sim.telemetry.duplicate(true)}
func assert_receipt(capture:Dictionary,harm:bool,success:bool=true) -> void:
 check(game.page=="report" and not game.economy.in_flight.size(),"formal terminal enters report only after atomic commit")
 var receipt:Dictionary=game.economy.last_settlement
 check(receipt.has("wildlife_evidence"),"formal receipt includes actual live simulator evidence")
 if not receipt.has("wildlife_evidence"):return
 var evidence:Dictionary=receipt.wildlife_evidence
 check(Evidence.validation_error(evidence).is_empty(),"committed evidence passes strict bounded validation")
 same(evidence.result,capture.result,"committed wildlife facts equal actual live state")
 check(evidence.command_ticks==capture.ticks and evidence.elapsed==capture.elapsed,"terminal checkpoint binds exact command count and elapsed")
 check(evidence.route.contract_id=="D5-A" and evidence.seed==670371318 and evidence.dispatch_identity.client=="小禾" and evidence.dispatch_identity.appearance_id=="human_courier","receipt binds actual order, seed and recurring customer")
 check(evidence.result.harms.size()==(1 if harm else 0) and receipt.success==success,"safe, harm or abort outcome remains factual")
 check(game.economy.review_state.pending.size()==1 and game.economy.customer_reviews().is_empty(),"formal settlement stores one pending fact and no same-day review")
 check(not receipt.has("review") and not receipt.has("rating") and not game.economy.review_state.pending["D5-A"].has("rating"),"no premature review or rating is exposed")
 check(game.report.route_context.route_profile==Profile.ROUTE_PROFILE and game.economy.story_state.committed_contract_ids["D5-A"].route_context.route_profile==Profile.ROUTE_PROFILE,"financial and story receipt retain v5 otherworld profile")
 check(game.economy.story_conversation("D5-A","result").title=="异界回执","v5 result uses otherworld story context")
 check(game.hud.content.find_children("WormholeEnergySubtotal","Label",true,false).size()==1 and copy_is_clear(),"v5 report shows one station subtotal and no helper codes")
 check(disk().version==5 and disk().workshop_tier==2,"bird settlement retains save v5 and paid workshop tier")
 var once:Dictionary=ledger();game.finish_flight()
 var duplicate:Dictionary=game.economy.settle_contract("D5-A",capture.telemetry,capture.elapsed,success,evidence)
 check(duplicate.get("duplicate",false),"repeat settlement is explicitly idempotent")
 same(ledger(),once,"repeat controller finish and settlement cannot charge twice")

func test_trial_and_quote() -> void:
 await setup()
 check(game.hud._pilot_mode() and game.hud._ascent_mode() and game.hud._extreme_mode() and game.hud._wormhole_mode(),"v5 explicitly enables pilot, ascent, extreme and wormhole HUD")
 check(game.world.protected_bird_hud_root==game.hud.root,"world receives actual current HUD root for occlusion")
 var route:Dictionary=game.economy.trial_route();var route_before:String=bytes(route)
 var quote:Dictionary=game._wormhole_preflight(route)
 check(quote.get("ok",false) and quote.estimated_bodies==1 and absf(quote.estimated_j-53.8)<.000001,"v5 quote uses exact canonical route and actual 14.4 mass")
 check(bytes(route)==route_before and copy_is_clear(),"preflight retains full commercial route and ordinary copy")
 var original_design:Array=game.design.duplicate(true)
 var fragmented:Array=original_design.duplicate(true);fragmented.append(Extreme.part(81,"battery",10,0));fragmented.append(Extreme.part(82,"beam",11,0))
 game.design=fragmented
 var actual=Sim.new();actual.configure(fragmented,game.launcher,Offer.canonical_route(route),int(route.seed))
 var fragments:Dictionary=game._wormhole_preflight(route)
 check(fragments.get("ok",false) and fragments.estimated_bodies==actual.bodies.size() and actual.bodies.size()==2,"v5 preflight counts actual disconnected starting bodies")
 check(absf(fragments.estimated_j-(25.0*actual.bodies.size()+2.0*actual.total_mass()))<.000001,"v5 disconnected quote bills actual installed and cargo-weighted mass")
 game.design=original_design
 var before:Dictionary=ledger();game.start_flight(true)
 check(game.sim is Sim and game._is_pilot_flight() and game.flight_order.has("generation") and not game.sim.route.has("generation"),"trial preserves full saved order and configures strict canonical v5 solver")
 check(Profile.same_value(game.sim.route,fixtures.safe.route),"actual configured trial matches physics fixture including commercial weight")
 replay("safe");terminal_capture("safe");game.finish_flight()
 same(ledger(),before,"trial terminal creates no financial, story or pending review facts")
 check(game.economy.in_flight.is_empty() and game.economy.review_state.version==1 and game.page=="report","trial stays free without lazy review migration")
 await dispose()

func test_formal_safe() -> void:
 await setup();game.start_flight(false)
 var money:int=game.economy.credits;replay("safe");var capture:Dictionary=terminal_capture("safe")
 check(game.economy.in_flight.ticks==0,"test deliberately finishes before any timed save checkpoint")
 var expected:Dictionary=game.economy.estimate_delivery(game.flight_order,game.sim.telemetry,game.sim.elapsed,true)
 game.finish_flight();assert_receipt(capture,false)
 check(game.economy.credits==money+int(expected.profit),"safe formal credits equal one ordinary combined bill")
 game.economy.mark_story_seen("D5-A","D5-A/result")
 check(game.economy.close_day().ok and game.economy.next_day_and_save(game.design,game.launcher,game.settings).ok,"safe review publishes only at successfully saved next morning")
 var feed:Array=game.economy.customer_reviews()
 check(feed.size()==1 and feed[0].rating>2 and not feed[0].body.contains("保护鸟"),"safe flight retains ordinary review text and rating")
 await dispose()

func test_harm_restart_and_rollback() -> void:
 await setup()
 var failing=FailingEconomy.new();failing.load_state();game.economy=failing
 game.start_flight(false);replay("harm",2500)
 check(game.sim.status=="running","pause checkpoint occurs before terminal delivery")
 var physical:Dictionary=state();game._on_focus_exited();var snapshot:Dictionary=disk().in_flight
 check(game.paused and snapshot.ticks==2500 and game.pilot_keys.is_empty(),"focus pause records exact deterministic timeline and releases input")
 await fresh()
 check(game.paused and game.sim is Sim and game.pilot_completed_ticks==2500 and not game.pilot_resume_blocked,"real restart restores v5 paused at exact saved command boundary")
 same(state(),physical,"restart recreates every physical, bird, energy and event state")
 same(game.economy.in_flight,snapshot,"resume consumes saved input without reauthoring full offer")
 game._process(.02);same(state(),physical,"paused rendering does not advance bird or repeat harm")
 game._on_focus_entered();game._set_paused(false);replay("harm",2700)
 check(not game.sim.first_harm.is_empty() and game.sim.status=="running","second checkpoint follows actual bird harm before terminal delivery")
 physical=state();game._on_focus_exited();snapshot=disk().in_flight
 await fresh()
 check(game.paused and game.pilot_completed_ticks==2700,"post-harm restart remains paused at saved command boundary")
 same(state(),physical,"post-harm restart reproduces actual bird HP, unique cause and all physical state")
 same(game.economy.in_flight,snapshot,"post-harm input snapshot survives restore unchanged")
 game._process(.02);same(state(),physical,"post-harm paused frame cannot duplicate the harm")
 game._on_focus_entered();game._set_paused(false);replay("harm")
 var capture:Dictionary=terminal_capture("harm")
 var replacement=FailingEconomy.new();replacement.load_state();game.economy=replacement
 var before:Dictionary=ledger();var saved_bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var terminal_sim=game.sim;var calls:int=replacement.save_calls
 game._checkpoint_flight()
 check(replacement.save_calls==calls and FileAccess.get_file_as_bytes("user://savegame.json")==saved_bytes,"terminal checkpoint has no I/O")
 same(game.economy.in_flight.input_commands,capture.commands,"terminal checkpoint retains exact real input history")
 replacement.fail_save=true;game.finish_flight()
 check(game.sim==terminal_sim and game.sim.status=="success" and game.page=="flight" and game.paused,"failed settlement retains live terminal sim for safe retry")
 same(ledger(),before,"failed save rolls back finance, story and pending review together")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==saved_bytes and game.economy.in_flight.ticks==capture.ticks,"failed commit preserves disk and terminal checkpoint")
 replacement.fail_save=false;game.finish_flight();assert_receipt(capture,true)
 var quote:Dictionary=game.economy.estimate_delivery(game.flight_order,capture.telemetry,capture.elapsed,true)
 check(game.economy.credits==int(before.credits)+int(quote.profit),"harm and retry do not add an ecological debit or duplicate charge")
 game.economy.mark_story_seen("D5-A","D5-A/result")
 check(game.economy.close_day().ok and game.economy.next_day_and_save(game.design,game.launcher,game.settings).ok,"harm review commits on next morning")
 var feed:Array=game.economy.customer_reviews()
 check(feed.size()==1 and feed[0].rating==2 and feed[0].body.contains("伤到了保护鸟") and feed[0].published_day==6,"actual harm yields one next-day two-star review")
 await fresh();check(Profile.same_value(game.economy.customer_reviews(),feed),"published harm review values remain exact across JSON restart")
 await dispose()

func test_abort() -> void:
 for after_harm in [false,true]:
  await setup()
  var failing=FailingEconomy.new();failing.load_state();game.economy=failing
  game.start_flight(false)
  if after_harm:
   var timeline=Timeline.new();timeline.restore(fixtures.harm.commands,fixtures.harm.completed_command_ticks)
   while game.sim.first_harm.is_empty() and game.sim.status=="running":drive(timeline.state_at(game.pilot_completed_ticks));game._step_flight()
  # Commit only the still-running input checkpoint. Abort intent has no new
  # replay flag: an unsuccessful abort transaction must not invent one.
  game._checkpoint_flight();check(game.save_game(),"pre-abort running checkpoint is durably saved")
  var saved_checkpoint:Dictionary=disk();var saved_bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  var before:Dictionary=ledger();var terminal_sim=game.sim
  var capture:Dictionary={"ticks":game.pilot_completed_ticks,"commands":game.pilot_timeline.snapshot(),"result":game.sim.wildlife_result().duplicate(true),"elapsed":game.sim.elapsed,"telemetry":game.sim.telemetry.duplicate(true)}
  failing.fail_save=true;game.abort_flight()
  check(game.page=="flight" and game.paused and game.sim==terminal_sim and game.sim.status=="failed","failed abort commit retains exact terminal live sim for retry")
  same(ledger(),before,"failed abort save rolls back finance/story/review")
  check(FileAccess.get_file_as_bytes("user://savegame.json")==saved_bytes,"failed abort leaves exact pre-failure disk bytes")
  same(game.sim.wildlife_result(),capture.result,"failed abort does not lose actual harm or safe facts")
  failing.fail_save=false;game.finish_flight();assert_receipt(capture,after_harm,false)
  check((capture.ticks>0)==after_harm,"live retry covers both immediate zero-tick and actual post-harm abort")
  # Independent restart branch from the exact pre-failure file. A failed
  # transaction did not persist an abort; replay resumes that running checkpoint.
  await dispose();write_fixture(saved_checkpoint);await fresh()
  check(game.sim is Sim and game.sim.status=="running" and game.paused and game.pilot_completed_ticks==capture.ticks,"restart before committed abort resumes the saved running checkpoint")
  check(game.economy.jobs_today==0 and game.economy.settled_ids.is_empty() and game.economy.customer_reviews().is_empty(),"uncommitted abort restart cannot manufacture a settlement or review")
  same(game.sim.wildlife_result(),capture.result,"rollback restart retains saved actual harm without duplication")
  game.abort_flight();assert_receipt(capture,after_harm,false)
  await dispose()

func test_internal_failure_copy() -> void:
 for reason in ["node_budget","earlier_uncertain_root","invalid_harm_source: origin_missing"]:
  await setup();game.start_flight(true)
  # Explicit fault injection tests copy boundaries; it is not a flight witness.
  game.sim._fail_wildlife(reason);game.sim.finalize_settlement()
  var raw:Array=game.sim.events.duplicate(true)
  game.launch_age=1.35;game.launch_transfer_remaining=0.0;game.launch_countdown=0.0;game._process(0.0)
  check(not game.hud.flight_labels.events.text.contains(reason) and not game.hud.flight_labels.events.tooltip_text.contains(reason),"actual v5 HUD and tooltip hide "+reason)
  check(game.hud.flight_labels.events.text.contains(Receipt.BIRD_FAILURE_COPY),"actual HUD retains concise stopped-flight notice")
  game.finish_flight()
  check(not JSON.stringify(game.report.events).contains(reason) and not str(game.report.cause).contains(reason),"final report events and cause hide "+reason)
  check(str(game.report.cause).contains(Receipt.BIRD_FAILURE_COPY) and copy_is_clear(),"final report retains user-facing failure without helper codes")
  same(game.sim.events,raw,"presentation never alters the frozen solver diagnostic ring")
  check(game.sim.status=="failed" and game.sim.wildlife_error==reason and game.economy.review_state.version==1,"copy filtering does not ignore failure or manufacture review facts")
  await dispose()

func test_rejected_launch() -> void:
 for field in ["control_version","pilot_profile","ecology_schema"]:
  await setup()
  var active:Dictionary=game.economy.active_contract();active[field]="unsupported-future"
  var before:Dictionary=ledger();var saved_bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  game.start_flight(true);game.start_flight(false);game._configure_flight(true,game.design,game.launcher,active)
  check(game.sim==null and game.page!="flight" and game.economy.in_flight.is_empty(),field+": malformed trial/formal/direct launch blocked")
  check(game._wormhole_preflight(active).is_empty(),field+": malformed route cannot produce plausible quote")
  same(ledger(),before,field+": rejected launch has no ledger side effects")
  check(FileAccess.get_file_as_bytes("user://savegame.json")==saved_bytes,field+": rejected launch preserves disk bytes")
  await dispose()

func test_invalid_bird_design() -> void:
 await setup()
 var route:Dictionary=game.economy.active_contract().duplicate(true)
 game.design[0].unknown_field=true
 var before:Dictionary=ledger();var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 check(game._bird_design_error(route,game.design,game.launcher)=="这份装配记录不完整，暂时无法出发。","v5 design token is translated before reaching simulator")
 game.start_flight(true);game.start_flight(false);game._configure_flight(true,game.design,game.launcher,route)
 check(game.sim==null and game.economy.in_flight.is_empty(),"invalid v5 trial/formal/direct configure never starts or commits")
 check(game._wormhole_preflight(route).is_empty(),"unsupported design emits no plausible portal quote")
 same(ledger(),before,"invalid design leaves finance/story/review unchanged")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==original,"invalid design rejection preserves original saved bytes")
 await dispose()

func test_wrong_protocol() -> void:
 await setup();game.start_flight(false);game._step_flight();check(game.save_game(),"valid one-tick v5 save provides corruption fixture")
 var valid:Dictionary=disk();await dispose()
 for kind in ["future","conflict","unknown ecology","wrong saved input","unsupported design"]:
  clear_save();var bad:Dictionary=valid.duplicate(true)
  if kind=="future":bad.in_flight.control_version="pilot-v99";bad.in_flight.route.control_version="pilot-v99"
  elif kind=="conflict":bad.in_flight.simulation_version="pilot-v4-wormhole"
  elif kind=="unknown ecology":bad.in_flight.route.ecology_schema="protected-bird-route-v99"
  elif kind=="wrong saved input":bad.in_flight.input_commands[0].axis_q=1001
  else:bad.in_flight.design[0].unknown_field=true
  write_fixture(bad);var original:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  await fresh()
  check(game.economy.review_load_blocked or game.pilot_resume_blocked,kind+": unsupported or contradictory restore blocks")
  check(not game.save_game() and FileAccess.get_file_as_bytes("user://savegame.json")==original,kind+": rejection never overwrites original bytes")
  await dispose()

func run() -> void:
 await test_trial_and_quote();await test_formal_safe();await test_harm_restart_and_rollback();await test_abort();await test_internal_failure_copy();await test_rejected_launch();await test_invalid_bird_design();await test_wrong_protocol()
 clear_save()
 print("PROTECTED_BIRD_CONTROLLER passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
