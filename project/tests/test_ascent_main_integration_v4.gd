extends Node
## Copies a real completed-chapter save into isolated XDG before boot. The
## original is never written, and progression uses only normal Economy actions.
const Main=preload("res://scripts/main.gd")
const Protocols=preload("res://scripts/free_flight_protocols.gd")
const Profile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const Economy=preload("res://scripts/economy.gd")
const Framing=preload("res://scripts/free_flight_framing_2d.gd")
const Parts=preload("res://scripts/workshop_parts_v2.gd")
var passed:int=0
var failed:int=0
var main
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run()->void:
 if OS.get_environment("SC_ASCENT_MAIN_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_require_existing_save=true;main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main)
 check(not main.economy.review_load_blocked,"actual native completed-chapter save loads in successor Main")
 if main.economy.review_load_blocked:printerr(main.economy.load_notice);finish();return
 main.set_process(false)
 check(main.economy.day==3 and main.economy.credits==1082 and main.economy.deliveries==3,"existing day credits and deliveries are retained")
 check(main.economy.flight_mode=="pilot-delivery-v3","shop mode and old chapter version remain v3")
 for order in main.economy.contracts:check(order.get("control_version")=="pilot-delivery-v3","already visible day-three contract is not rewritten")
 var closed:Dictionary=main.economy.close_day_and_save(main.design,main.launcher,main.settings)
 check(closed.ok,"ordinary close-day action saves completed day three")
 var next:Dictionary=main.economy.next_day_and_save(main.design,main.launcher,main.settings)
 check(next.ok,"ordinary next-day action opens fourth delivery")
 if not next.ok:printerr(next);finish();return
 var order:Dictionary=main.economy.contract_by_id("D4-A")
 check(order.get("control_version")==Profile.VERSION and order.get("route_profile")=="delivery-lunar-ascent-v1","normal D4-A is explicit new altitude protocol")
 check(main.economy.contract_by_id("D4-B").get("control_version")=="pilot-delivery-v3","B basic order retains original free recovery gameplay")
 check(main._recovery_route_error(order).is_empty(),"precise ascent profile earns existing verified moon assets")
 check(not main._recovery_route_error({"control_version":"pilot-v2","route_kind":"moon"}).is_empty(),"legacy unready moon route remains blocked")
 var mixed:Dictionary=order.duplicate(true);mixed.control_version="pilot-delivery-v3"
 check(not Protocols.route_error(mixed).is_empty() and not main._recovery_route_error(mixed).is_empty(),"mixed new fields cannot silently fall through old v3")
 check(Framing.applies(order) and not Framing.is_ground_route(order),"bidirectional camera tracks ascent without classifying it as ground")
 check(Parts.compatible("spring",false,Profile.VERSION),"new ascent preserves passive cargo mount assembly")
 check(main.economy.accept_contract_and_save("D4-A",main.design,main.launcher,main.settings).ok,"real fourth offer accepts and persists")
 main.page="workshop";main.assembly_mode="launcher";main.render()
 main._action("set_launch_settings",{"angle_degrees":80.0,"power_fraction":1.0})
 check(main.hud.state.control_version==Profile.VERSION and main.hud.state.launch_preview.velocity.y<0.0,"workshop HUD receives altitude-solver launch preview")
 check(main.economy.mark_cargo_loaded("D4-A").ok,"fourth cargo loads through existing formal action")
 check(main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"fourth formal dispatch binds launch settings and protocol")
 main._configure_flight(false,main.design,main.launcher,main.economy.in_flight.route.duplicate(true))
 check(main.page=="flight" and main.sim.get_script()==load("res://scripts/pilot_delivery_ascent_simulation_v4.gd"),"Main creates exact new ascent solver")
 main.launch_age=.5;main.launch_transfer_remaining=0.0;main._checkpoint_flight()
 var prep:Dictionary=main.economy.in_flight.duplicate(true)
 check(main.save_game() and Protocols.snapshot_error(prep).is_empty(),"v4 preparation stage saves with versioned frozen release state")
 await main._resume_free_dispatch(prep,prep.route.duplicate(true),0)
 check(not main.sim.launch_released and main.paused and is_zero_approx(main.sim.telemetry.energy_used) and is_equal_approx(main.launch_age,.5),"v4 Continue remains in unpaid preparation stage")
 main._set_paused(false);main.launch_age=.949;main._process(.0011)
 check(main.sim.launch_released and main.sim.telemetry.control_version==Profile.VERSION,"v4 actual release uses new solver identity")
 main.pilot_keys[KEY_W]=true
 for tick in 360:
  if main.sim.status!="running":break
  main._step_flight()
 main._checkpoint_flight()
 var checkpoint:Dictionary=main.economy.in_flight.duplicate(true)
 var at:Vector2=main.sim.cargo_position();var paid:float=main.sim.telemetry.energy_used
 var integrity:float=main.sim.telemetry.delivery_integrity
 var warnings:PackedByteArray=var_to_bytes(main.sim.telemetry.get("ascent_warnings",[]))
 check(float(main.sim.telemetry.get("altitude_m",0))>0.0,"held upward input actually gains physical altitude")
 check(Protocols.snapshot_error(checkpoint).is_empty() and main.save_game(),"recorded ascent flight saves without changing its exact contract")
 await main._resume_free_dispatch(checkpoint,checkpoint.route.duplicate(true),int(checkpoint.ticks))
 check(not main.pilot_resume_blocked and main.sim.cargo_position().distance_to(at)<.00001,"ascent position replays from actual recorded ticks")
 check(absf(main.sim.telemetry.energy_used-paid)<.00001 and absf(main.sim.telemetry.delivery_integrity-integrity)<.00001,"ascent replay preserves launch costs energy and cargo damage")
 check(var_to_bytes(main.sim.telemetry.get("ascent_warnings",[]))==warnings,"sim-time meteor warnings reconstruct exactly")
 main.abort_flight()
 check(main.page=="report" and main.economy.in_flight.is_empty() and main.report.control_version==Profile.VERSION,"formal ascent abort settles under new exact version")
 var restored=Economy.new();var saved:Dictionary=restored.load_state(true)
 check(not saved.is_empty() and restored.credits==main.economy.credits and restored.in_flight.is_empty(),"fourth-flight receipt and credits survive disk reload without duplicate settlement")
 finish()
func finish()->void:
 print("ASCENT_MAIN_V4 ",passed," passed ",failed," failed")
 get_tree().quit(0 if failed==0 else 1)
