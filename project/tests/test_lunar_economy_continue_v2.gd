extends SceneTree
## Actual next_day/accept/dispatch/save/Title-Continue/settlement entry. An
## explicit completed-day-one ledger fixture supplies progression only; every
## lunar offer, physical tick, restored flight and receipt uses production APIs.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Receipt=preload("res://scripts/lunar_outpost_receipt_v2.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
const Free=preload("res://scripts/pilot_free_simulation_v2.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Title=preload("res://scripts/demo_title.gd")
const FACTORY="res://scripts/clerk_runtime_bootstrap_observed_v4.gd"
var passed:int=0
var failed:int=0
var title
var settings:Dictionary={"volume":0.0,"reduced_motion":true}
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
 return ok
func gate(route:Dictionary) -> String:
 var error:String=Receipt.route_error(route)
 return error if not error.is_empty() else Caps.route_error(route)
func _initialize() -> void:run.call_deferred()
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func frames(count:int=3) -> void:
 for unused in count:await process_frame
func finish() -> void:
 if is_instance_valid(title):root.remove_child(title);title.free()
 await frames()
 print("LUNAR_ECONOMY_CONTINUE_V2_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
func command(sim,target:Vector2) -> Dictionary:
 var b:Dictionary=sim.body_for_part(1)
 var delta:Vector2=target-sim.cargo_position()
 var desired:Vector2=delta.normalized()*minf(9.0,sqrt(delta.length()*3.0))
 var force:float=0.0
 for p in b.parts:
  if p.type=="thruster" and p.alive:force+=float(p.param)*float(p.output_factor)
 var input:Vector2=(((desired-b.velocity)/.65-Vector2(0.0,float(sim.route.gravity)))*float(b.mass)/maxf(.001,force*float(sim.route.free_drive_throttle))).limit_length(1.0)
 var state:Dictionary=Timeline.neutral();state.axis_x_q=roundi(input.x*1000.0);state.axis_q=roundi(input.y*1000.0)
 return state
func step(sim,state:Dictionary) -> void:
 sim.set_free_flight_input(state.axis_x_q,state.axis_q,state.boost,state.active,state.device_id,state.brake);sim.step(1.0/60.0)
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json"):
  printerr("Use a fresh isolated XDG_DATA_HOME; existing saves are never deleted by this test.");quit(2);return
 var design:Array=Profile.starter_design();var pad:Array=Profile.starter_launcher()
 var e=Econ.new();e.route_guard=gate;e.enable_force_mode();e.starter_stock(design,pad);e.enable_story_mode()
 # This is a ledger-entry fixture, not two invented lunar delivery successes.
 e.day=1;e.phase="night";e.jobs_today=2;e.deliveries=2;e.reputation=2;e.credits=600
 if not check(e.save_state(design,pad,settings),"completed-day-one fixture saves through real guarded ledger"):await finish();return
 var advanced:Dictionary=e.next_day_and_save(design,pad,settings)
 print("LUNAR_ENTRY_NEXT_DAY ",JSON.stringify(advanced))
 if not check(advanced.ok,"ordinary next-day transaction authors and saves day two"):await finish();return
 var lunar:Dictionary={}
 for offer in e.available_contracts():
  if int(offer.id)==6:lunar=offer
 if not check(e.day==2 and not lunar.is_empty(),"actual day-two available offers contain new lunar ID6"):await finish();return
 var cid:String=lunar.contract_id
 check(lunar.variant=="重货件" and float(lunar.deadline)==83.0 and float(lunar.time_limit)==110.0,"ordinary B-slot heavy deadline is exactly83 while physical time rule stays110")
 var wrong:Dictionary=lunar.duplicate(true);wrong.deadline=80.0
 check(not Content.validation_error(wrong).is_empty(),"heavy lunar parcel cannot silently retain standard deadline80")
 wrong=lunar.duplicate(true);wrong.variant="标准件"
 check(not Content.validation_error(wrong).is_empty(),"standard lunar parcel cannot borrow heavy deadline83")
 wrong=lunar.duplicate(true);wrong.variant="future-unrecognized-variant"
 check(not Content.validation_error(wrong).is_empty(),"unknown lunar commercial variant fails closed")
 wrong=lunar.duplicate(true);wrong.deadline=84.0
 check(not Content.validation_error(wrong).is_empty(),"heavy lunar deadline cannot expand beyond exact83")
 check(lunar.control_version==Profile.VERSION and gate(lunar).is_empty() and Econ.route_validation_error(lunar).is_empty(),"available lunar offer has complete v2 physics/art/commercial validation")
 var authored:Dictionary=lunar.duplicate(true)
 e.ensure_contracts();check(Content._same(e.contract_by_id(cid),authored),"repeated offer queries do not reauthor lunar snapshot")
 if not check(e.accept_contract_and_save(cid,design,pad,settings).ok,"visible lunar ID6 is actually acceptable through durable API"):await finish();return
 check(disk().active_contract_id==cid,"raw save records exact accepted lunar contract")
 e.mark_story_seen(cid,cid+"/accept")
 if not check(e.mark_cargo_loaded(cid).ok,"accepted lunar order allows genuine loaded-state transition"):await finish();return
 if not check(e.begin_dispatch(design,pad).ok,"formal lunar launch records real v2 snapshot"):await finish();return
 var initial:Dictionary=e.in_flight.duplicate(true);var sim=Free.new()
 sim.configure(initial.design,initial.launcher,initial.route,int(initial.seed))
 var timeline=Timeline.new()
 for tick in range(120):
  if sim.status!="running":break
  var state:Dictionary=command(sim,Vector2(65.0,-38.0));timeline.record(tick,state);step(sim,state)
 if not check(sim.status=="running","formal actual lunar flight advances before saving"):await finish();return
 e.in_flight.input_commands=timeline.snapshot();e.in_flight.ticks=120;e.in_flight.elapsed=sim.elapsed
 if not check(e.save_state(design,pad,settings),"120 actual v2 ticks persist through normal save"):await finish();return
 var raw:Dictionary=disk();var expected_position:Vector2=sim.cargo_position();var expected_energy:float=float(sim.telemetry.energy_used)
 check(raw.in_flight.route.id==6 and raw.in_flight.input_schema==Profile.INPUT_SCHEMA and raw.in_flight.ticks==120,"raw saved dispatch keeps lunar ID6 and six-field v2 timeline")
 title=Title.new();title.clerk_pose_bootstrap_script=load(FACTORY);root.add_child(title);await frames()
 if DisplayServer.get_name()=="headless":title._focus_entered()
 title._continue_game()
 var deadline:int=Time.get_ticks_msec()+20000
 while title.screen!="game" and not title._opening_failed and Time.get_ticks_msec()<deadline:await process_frame
 if not check(title.screen=="game" and is_instance_valid(title.game),"real Title Continue opens Main from lunar raw save"):await finish();return
 var game=title.game;game.set_process(false);game.world.set_process(false)
 if not check(not game.economy.review_load_blocked and not game.pilot_resume_blocked and game.page=="flight" and game.paused,"Main Continue restores valid lunar flight paused"):await finish();return
 check(game.sim.route.id==6 and game.sim.route.control_version==Profile.VERSION and game.pilot_completed_ticks==120,"Continue retains exact lunar identity and replay version")
 check(game.sim.cargo_position()==expected_position and float(game.sim.telemetry.energy_used)==expected_energy,"Continue exactly reconstructs actual trajectory and paid energy")
 check(game.world.lunar_presentation.route_enabled(),"Continue uses the lunar presenter rather than orbital station fallback")
 var targets:Array=[Vector2(65.0,-38.0),Vector2(195.0,-63.0),Content.DESTINATION];var phase:int=0
 for unused in range(7200):
  if game.sim.status!="running":break
  if phase<targets.size()-1 and game.sim.cargo_position().distance_to(targets[phase])<2.0:phase+=1
  var state:Dictionary=command(game.sim,targets[phase]);game.pilot_timeline.record(game.pilot_completed_ticks,state)
  step(game.sim,state);game.pilot_completed_ticks+=1
 if not check(game.sim.status=="success" and float(game.sim.telemetry.energy_remaining)>0.0,"actual restored day-two heavy lunar order completes with finite energy"):await finish();return
 game.economy.in_flight.input_commands=game.pilot_timeline.snapshot();game.economy.in_flight.ticks=game.pilot_completed_ticks;game.economy.in_flight.elapsed=game.sim.elapsed
 game.sim.finalize_settlement()
 var settled:Dictionary=game.economy.settle_contract_and_save(cid,game.sim.telemetry,game.sim.elapsed,true,game.design,game.launcher,game.settings)
 if not check(settled.ok,"actual restored lunar delivery settles once through durable ledger"):await finish();return
 raw=disk();var context:Dictionary=raw.last_settlement.get("route_context",{})
 check(context.get("route_profile")==Content.ROUTE_PROFILE and context.get("route_kind")=="lunar" and context.get("destination_id")==Content.DESTINATION_ID and context.get("destination_name")==Content.FIELDS.destination_name,"raw formal receipt preserves exact lunar route_context")
 var restored=Econ.new();restored.route_guard=gate;restored.load_state(true)
 check(not restored.review_load_blocked and restored.in_flight.is_empty() and Content._same(restored.last_settlement.get("route_context"),context) and restored.settled_ids.has(cid),"ordinary saved-ledger reload preserves lunar receipt without reroll")
 await finish()
