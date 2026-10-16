extends Node
const Main=preload("res://scripts/main.gd")
const Protocols=preload("res://scripts/free_flight_protocols.gd")
const Cells=preload("res://scripts/cell_rules_profile_v6.gd")
const Ground=preload("res://scripts/pilot_delivery_profile_v7.gd")
const Ascent=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const Economy=preload("res://scripts/economy.gd")
const Framing=preload("res://scripts/free_flight_framing_2d.gd")
var passed:int=0
var failed:int=0
var main
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run()->void:
 if OS.get_environment("SC_MATERIAL_MAIN_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main);main.set_process(false)
 check(not main.economy.review_load_blocked,"normal fresh Main starts with v7 future offers")
 if main.economy.review_load_blocked:finish();return
 profile_boundaries()
 check(main.economy.flight_mode=="pilot-delivery-v3" and main.economy.contracts[0].control_version==Ground.VERSION,"shop identity unchanged while normal first new offer is explicit v7")
 check(main.economy.missing_parts(main.design,main.launcher).is_empty(),"starter ship and pad are actually owned")
 check(main.economy.accept_contract_and_save("D1-A",main.design,main.launcher,main.settings).ok,"normal first offer accepts and persists")
 main.page="workshop";main.assembly_mode="launcher";main.render()
 check(main.hud.state.control_version==Ground.VERSION and main.hud.state.launch_preview.speed>0,"actual HUD receives new protocol physical preview")
 main._action("set_launch_settings",{"angle_degrees":12.0,"power_fraction":0.5})
 check(main.economy.mark_cargo_loaded("D1-A").ok and main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"formal new dispatch freezes actual launch settings")
 main._configure_flight(false,main.design,main.launcher,main.economy.in_flight.route.duplicate(true))
 check(main.sim.get_script()==load("res://scripts/pilot_delivery_simulation_v7.gd"),"Main chooses thin ground v7 solver")
 main.launch_age=.5;main.launch_transfer_remaining=0;main._checkpoint_flight()
 var prep:Dictionary=main.economy.in_flight.duplicate(true)
 check(main.save_game() and Protocols.snapshot_error(prep).is_empty(),"unreleased preparation persists")
 await main._resume_free_dispatch(prep,prep.route.duplicate(true),0)
 check(not main.sim.launch_released and main.paused and is_zero_approx(main.sim.telemetry.energy_used) and main.launch_age==.5,"preparation Continue is still unpaid")
 main._set_paused(false);main.launch_age=.949;main._process(.0011)
 var drawn:float=main.sim.telemetry.launch_energy_drawn
 main._release_delivery_launcher();main._checkpoint_flight()
 var zero:Dictionary=main.economy.in_flight.duplicate(true)
 await main._resume_free_dispatch(zero,zero.route.duplicate(true),0)
 check(main.sim.launch_released and drawn>0 and main.sim.telemetry.launch_energy_drawn==drawn,"zero-tick released replay charges launcher exactly once")
 main._set_paused(false);main.pilot_keys[KEY_D]=true
 for tick in 60:main._step_flight()
 await replay_boundary("paid ordinary input")
 var credits:int=main.economy.credits
 main._action("abort",{})
 check(main.page=="report" and not main.report.success and main.economy.in_flight.is_empty(),"actual flight abort action settles failure once")
 check(main.report.energy_j>0 and main.economy.credits<credits and main.report.income==0,"manual abort pays actual energy and grants no reward")
 var restored=Economy.new();var save:Dictionary=restored.load_state(true)
 check(not save.is_empty() and restored.credits==main.economy.credits and restored.in_flight.is_empty(),"abort receipt and balance survive real disk reload")
 await ejection_delivery()
 finish()
func profile_boundaries()->void:
 for profile in [Ground,Ascent,Rift]:
  var route:Dictionary=profile.route();var before:PackedByteArray=var_to_bytes(route)
  check(not route.is_empty() and Protocols.route_error(route).is_empty() and main._recovery_route_error(route).is_empty(),profile.VERSION+" exact profile and art gate")
  var legacy:Dictionary=profile.compatibility_route(route)
  check(var_to_bytes(route)==before and not Ground.material_markers(legacy) and Protocols.route_error(legacy).is_empty(),profile.VERSION+" private compatibility copy never changes committed route")
  check(Framing.applies(route) and Framing.is_ground_route(route)==(profile==Ground),profile.VERSION+" camera environment is exact")
  var wrong:Dictionary=route.duplicate(true);wrong.cell_environment="unknown"
  check(not Protocols.route_error(wrong).is_empty(),profile.VERSION+" unknown environment rejected")
  wrong=route.duplicate(true);wrong.accelerator_stroke_metres=0.0
  check(not Protocols.route_error(wrong).is_empty(),profile.VERSION+" changed finite stroke rejected")
  wrong=route.duplicate(true);wrong.control_version=legacy.control_version
  check(not Protocols.route_error(wrong).is_empty() and not main._recovery_route_error(wrong).is_empty(),profile.VERSION+" mixed old identity fails closed")
  wrong=route.duplicate(true);wrong.contract_id="committed"
  check(profile.route(wrong).is_empty() and Cells.stamp_fresh(wrong,profile.ENVIRONMENT).is_empty(),profile.VERSION+" author cannot rewrite a committed contract")
func state()->PackedByteArray:
 var evidence:Dictionary={}
 for key in ["energy_used","delivery_integrity","unpowered_coasting","unpowered_cargo_ids","accelerator_events","cargo_peak_acceleration","launch_energy_drawn","pilot_tick"]:
  if main.sim.telemetry.has(key):evidence[key]=main.sim.telemetry[key]
 return var_to_bytes([main.sim.parts,main.sim.bodies,main.sim.links,evidence,main.sim.events])
func replay_boundary(label:String)->void:
 main._checkpoint_flight();var snapshot:Dictionary=main.economy.in_flight.duplicate(true);var exact:PackedByteArray=state()
 check(Protocols.snapshot_error(snapshot).is_empty() and main.save_game(),label+" saves valid replay")
 await main._resume_free_dispatch(snapshot,snapshot.route.duplicate(true),int(snapshot.ticks))
 check(not main.pilot_resume_blocked and state()==exact,label+" replay is byte exact")
 main._set_paused(false)
func ejection_delivery()->void:
 check(main.economy.close_day_and_save(main.design,main.launcher,main.settings).ok,"normal failed day closes")
 check(main.economy.buy_part_and_save("accelerator",main.catalog.accelerator,main.design,main.launcher,main.settings).ok,"accelerator really purchases from evening stock")
 check(main.economy.next_day_and_save(main.design,main.launcher,main.settings).ok,"normal next day offers unfinished light task")
 main.design=[piece(1,"cargo",1,0,100),piece(2,"accelerator",0,0,8),piece(3,"battery",-1,0,300)]
 main.design[1].target=1;main.design[1].input_a=-2
 check(main.economy.missing_parts(main.design,main.launcher).is_empty(),"bare-cargo accelerator ship uses paid owned parts")
 check(main.economy.accept_contract_and_save("D2-A",main.design,main.launcher,main.settings).ok,"normal light A accepts without route changes")
 main.settings.launch_settings={"angle_degrees":0.5,"power_fraction":0.3}
 check(main.economy.mark_cargo_loaded("D2-A").ok and main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"actual accelerator assembly dispatches")
 main._configure_flight(false,main.design,main.launcher,main.economy.in_flight.route.duplicate(true))
 main.launch_transfer_remaining=0;main.launch_age=.949;main._process(.0011)
 await replay_boundary("before grouped accelerator trigger")
 main.pilot_keys[KEY_SPACE]=true;main._step_flight();main.pilot_keys.clear()
 check(main.sim.parts[2].spent and main.sim.telemetry.unpowered_coasting and main.sim.status=="running","recorded active key ejects bare cargo and keeps coasting alive")
 await replay_boundary("after accelerator split")
 for tick in 120:main._step_flight()
 check(main.sim.telemetry.unpowered_coasting and main.sim.status=="running","unpowered cargo keeps objective flight after two seconds")
 await replay_boundary("unpowered cargo in flight")
 for tick in 60*30:
  if main.sim.status!="running":break
  main._step_flight()
 check(main.sim.status=="success","normal unmodified light order accepts real inertial bare cargo")
 var before:int=main.economy.credits
 main.finish_flight()
 check(main.economy.in_flight.is_empty() and main.report.success and main.report.lost==100 and main.report.energy_j>72 and main.report.income==220,"ejection success pays abandoned parent hardware and actual joules")
 var paid:int=main.economy.credits;main.finish_flight()
 check(main.economy.credits==paid and paid==before+int(main.report.profit),"repeated finish cannot settle reward twice")
 var reloaded=Economy.new();var save:Dictionary=reloaded.load_state(true)
 check(not save.is_empty() and reloaded.credits==paid and reloaded.in_flight.is_empty(),"inertial success receipt survives actual disk read")
 print("MATERIAL_MAIN_EJECTION ",JSON.stringify({"elapsed":main.report.elapsed,"energy_j":main.report.energy_j,"integrity":main.report.delivery_integrity,"lost":main.report.lost,"profit":main.report.profit,"credits":paid}))
func piece(id:int,kind:String,x:int,y:int,param:float)->Dictionary:return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1}
func finish()->void:
 print("MATERIAL_MAIN_V7 ",passed," passed ",failed," failed");get_tree().quit(0 if failed==0 else 1)
