extends Node
const Main=preload("res://scripts/main.gd")
const Protocols=preload("res://scripts/free_flight_protocols.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const Parts=preload("res://scripts/workshop_parts_v2.gd")
const Economy=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
var main
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run()->void:
 if OS.get_environment("SC_DELIVERY_MAIN_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main)
 check(not main.economy.review_load_blocked,"fresh Main starts without recovery screen")
 if main.economy.review_load_blocked:printerr(main.economy.load_notice);finish();return
 main.set_process(false)
 check(main.economy.flight_mode==Profile.VERSION,"normal new shop selects delivery v3")
 check(main.economy.contracts.size()==2 and main.economy.contracts[0].get("control_version")==Profile.VERSION,"first chapter offers come through normal new game")
 check(main.economy.missing_parts(main.design,main.launcher).is_empty(),"new starter inventory covers actual ship and four-spring pad")
 check(Parts.compatible("spring",false,Profile.VERSION) and not Parts.compatible("spring",false,"pilot-free-v2"),"ship spring eligibility is version bounded")
 main.page="workshop";main.assembly_mode="launcher";main.render()
 check(main.hud.state.launch_preview.get("speed",0)>0 and main.hud.state.launch_preview.get("mass",0)>0,"Main sends authoritative physical launch preview to actual HUD")
 var old_energy:float=main.hud.state.launch_preview.energy_used
 main._action("set_launch_settings",{"angle_degrees":35.0,"power_fraction":0.5})
 check(main.settings.launch_settings=={"angle_degrees":35.0,"power_fraction":0.5},"HUD action persists angle and strength")
 check(main.hud.state.launch_preview.energy_used<old_energy,"settings action recomputes preview with lower physical energy")
 var fresh=Economy.new();var loaded:Dictionary=fresh.load_state(true)
 check(not loaded.is_empty() and loaded.settings.launch_settings==main.settings.launch_settings,"launcher settings survive disk load")
 var id:String=main.economy.contracts[0].contract_id
 check(main.economy.accept_contract_and_save(id,main.design,main.launcher,main.settings).ok,"first real offered contract accepts and saves")
 check(main.economy.mark_cargo_loaded(id).ok,"accepted cargo can be loaded through existing model")
 check(main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"formal dispatch freezes launch settings")
 var frozen:Dictionary=main.economy.in_flight.launch_settings.duplicate(true)
 main._configure_flight(false,main.design,main.launcher,main.economy.in_flight.route.duplicate(true))
 check(main.page=="flight" and not main.sim.launch_released and is_zero_approx(main.sim.elapsed),"configure leaves pad unreleased and simulation frozen")
 check(main._is_pilot_flight() and main._force_input_version(Profile.VERSION),"v3 owns existing bidirectional free-v2 input")
 main.settings.launch_settings={"angle_degrees":0.0,"power_fraction":1.0}
 main.launch_transfer_remaining=main.world.launch_transfer_duration()*.5;main.launch_age=0.0
 main._checkpoint_flight()
 var transfer:Dictionary=main.economy.in_flight.duplicate(true)
 check(main.save_game() and not transfer.launch_released,"pre-release transfer autosave retains unpaid launch")
 await main._resume_free_dispatch(transfer,transfer.route.duplicate(true),0)
 check(not main.sim.launch_released and is_zero_approx(main.sim.telemetry.energy_used) and is_equal_approx(main.launch_transfer_remaining,float(transfer.launch_preparation.transfer_remaining)),"transfer-stage resume retains zero charge and remaining transfer")
 main._set_paused(false)
 main.launch_transfer_remaining=0.0;main.launch_age=.7
 main._process(.1)
 check(not main.sim.launch_released and is_zero_approx(main.sim.elapsed),"ignition frame still has no impulse or paid energy")
 main._checkpoint_flight()
 var preparing:Dictionary=main.economy.in_flight.duplicate(true)
 check(main.save_game() and Protocols.snapshot_error(preparing).is_empty(),"charge-stage zero-tick flight saves valid preparation snapshot")
 await main._resume_free_dispatch(preparing,preparing.route.duplicate(true),0)
 check(not main.sim.launch_released and is_zero_approx(main.sim.telemetry.energy_used) and is_equal_approx(main.launch_age,float(preparing.launch_preparation.age)),"charge-stage resume stays unpaid and retains its exact phase")
 var inconsistent:Dictionary=preparing.duplicate(true);inconsistent.ticks=1
 check(not Protocols.snapshot_error(inconsistent).is_empty(),"unreleased snapshot with flight ticks is rejected")
 main._set_paused(false)
 main.launch_age=.949
 main._process(.0011)
 check(main.sim.launch_released and is_equal_approx(main.sim.telemetry.launch_angle_degrees,35.0) and is_equal_approx(main.sim.telemetry.launch_power_fraction,.5),"first release frame uses frozen formal angle and strength")
 var paid:float=main.sim.telemetry.launch_energy_drawn
 check(paid>0.0 and main.pilot_completed_ticks==0,"zero-tick release pays real launcher energy once")
 main._release_delivery_launcher();main._release_delivery_launcher()
 check(is_equal_approx(main.sim.telemetry.launch_energy_drawn,paid),"repeated release calls do not pay twice")
 main._checkpoint_flight()
 var zero:Dictionary=main.economy.in_flight.duplicate(true)
 check(Protocols.snapshot_error(zero).is_empty() and zero.launch_settings==frozen,"zero-tick checkpoint keeps exact frozen launch and input schema")
 check(main.save_game(),"real zero-tick released flight saves")
 var before_energy:float=main.sim.telemetry.energy_used
 await main._resume_free_dispatch(zero,zero.route.duplicate(true),0)
 check(not main.pilot_resume_blocked and main.paused and main.sim.launch_released,"zero-tick saved flight resumes paused with one fresh release")
 check(is_equal_approx(main.sim.telemetry.energy_used,before_energy) and is_equal_approx(main.sim.telemetry.launch_energy_drawn,paid),"zero-tick reconstruction neither loses nor duplicates launch cost")
 main._set_paused(false)
 main.pilot_keys[KEY_D]=true
 for tick in 60:main._step_flight()
 main._checkpoint_flight()
 var snapshot:Dictionary=main.economy.in_flight.duplicate(true)
 var at:Vector2=main.sim.cargo_position();var energy:float=main.sim.telemetry.energy_used
 await main._resume_free_dispatch(snapshot,snapshot.route.duplicate(true),int(snapshot.ticks))
 check(main.sim.cargo_position().distance_to(at)<.00001 and absf(main.sim.telemetry.energy_used-energy)<.00001,"recorded flight ticks replay deterministic motion and energy")
 check(main._selected_free_device_id==int(main.pilot_timeline.state_at(int(snapshot.ticks)).device_id),"selected tool survives replay")
 var invalid:Dictionary=snapshot.duplicate(true);invalid.launch_settings.power_fraction=2.0
 check(not Protocols.snapshot_error(invalid).is_empty(),"out-of-range frozen launch settings are rejected")
 check(main.hud.state.activeorder.min_delivery_integrity==snapshot.route.min_delivery_integrity,"flight HUD owns the same minimum cargo requirement")
 main.economy.credits=-123
 var debt:int=main.economy.credits
 check(main._prepare_free_economy_entry(true) and main.economy.credits==debt and main.economy.flight_mode==Profile.VERSION,"Continue never clears new debt or switches new mode")
 var legacy=Main.new();legacy._starter();legacy.economy.enable_free_mode();legacy.economy.ensure_contracts()
 var old_version:String=legacy.economy.flight_mode;var old_contracts:PackedByteArray=var_to_bytes(legacy.economy.contracts)
 check(legacy._prepare_free_economy_entry(true) and legacy.economy.flight_mode==old_version and var_to_bytes(legacy.economy.contracts)==old_contracts,"legacy Continue keeps exact prior mode and offered contracts")
 legacy.free()
 var aborted:Dictionary=preparing.duplicate(true);aborted.terminal_intent="abort"
 main.economy.in_flight=aborted.duplicate(true)
 await main._resume_free_dispatch(aborted,aborted.route.duplicate(true),0)
 check(main.sim.status=="failed" and not main.sim.launch_released and is_zero_approx(main.sim.telemetry.energy_used),"pre-release abort reconstructs without a hidden launch charge")
 main.finish_flight()
 check(main.page=="report" and main.economy.in_flight.is_empty() and not main.report.success and is_zero_approx(main.report.energy_j),"pre-release abort settles once with zero nonexistent flight costs")
 var settled=Economy.new();var settled_save:Dictionary=settled.load_state(true)
 check(not settled_save.is_empty() and settled.credits==main.economy.credits and settled.credits==debt,"post-abort debt survives real disk load without a grant")
 finish()
func finish()->void:
 print("DELIVERY_MAIN ",passed," passed ",failed," failed")
 get_tree().quit(0 if failed==0 else 1)
