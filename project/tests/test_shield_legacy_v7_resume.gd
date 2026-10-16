extends Node
const Main=preload("res://scripts/main.gd")
const Protocols=preload("res://scripts/free_flight_protocols.gd")
const Guard=preload("res://scripts/readable_offer_guard.gd")
const Economy=preload("res://scripts/economy.gd")
const Legacy=preload("res://scripts/pilot_delivery_profile_v7.gd")
var passed:int=0
var failed:int=0
var main
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func physical()->PackedByteArray:
 var evidence:Dictionary={}
 for key in ["control_version","energy_used","delivery_integrity","launch_energy_drawn","pilot_tick","accelerator_events"]:
  if main.sim.telemetry.has(key):evidence[key]=main.sim.telemetry[key]
 return var_to_bytes([main.sim.parts,main.sim.bodies,main.sim.links,evidence,main.sim.events])
func run()->void:
 if OS.get_environment("SC_SHIELD_LEGACY_ISOLATED")!="1":get_tree().quit(2);return
 var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_require_existing_save=true;main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main);main.set_process(false)
 check(not main.economy.review_load_blocked and main.economy.day==2 and main.economy.credits==444,"actual dev26 native v7 save loads unchanged")
 if main.economy.review_load_blocked:finish();return
 check(Guard.same(main.economy.contracts,original.contracts),"already displayed and accepted v7 JSON contract fields remain exact")
 var order:Dictionary=main.economy.active_contract();var original_route:PackedByteArray=var_to_bytes(order)
 check(order.contract_id=="D2-A" and order.control_version==Legacy.VERSION,"old committed heavy order remains exact v7")
 if not bool(order.get("cargo_loaded",false)):check(main.economy.mark_cargo_loaded("D2-A").ok,"old accepted cargo loads normally")
 check(main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"old v7 dispatch freezes its own protocol")
 var route:Dictionary=main.economy.in_flight.route.duplicate(true)
 main._configure_flight(false,main.design,main.launcher,route)
 check(main.sim.get_script()==load("res://scripts/pilot_delivery_simulation_v7.gd") and not main.sim.telemetry.has("spatial_shield_schema"),"old v7 uses original solver and no v8 spatial policy")
 main.launch_transfer_remaining=0;main.launch_age=.5;main._checkpoint_flight();var prep:Dictionary=main.economy.in_flight.duplicate(true)
 check(main.save_game() and Protocols.snapshot_error(prep).is_empty(),"old preparation persists under same v7 snapshot schema")
 await main._resume_free_dispatch(prep,route,0)
 check(not main.sim.launch_released and main.sim.telemetry.energy_used==0 and main.launch_age==.5,"old preparation resumes unpaid with original countdown")
 main._set_paused(false);main.launch_age=.949;main._process(.0011)
 for tick in 30:main._step_flight()
 main._checkpoint_flight();var snapshot:Dictionary=main.economy.in_flight.duplicate(true);var state:PackedByteArray=physical()
 check(main.save_game() and Protocols.snapshot_error(snapshot).is_empty(),"old flying v7 checkpoint saves")
 var restored=Economy.new();var loaded:Dictionary=restored.load_state(true)
 check(not loaded.is_empty() and restored.in_flight.control_version==Legacy.VERSION and Guard.same(restored.in_flight.route,snapshot.route),"disk read preserves frozen old route and controller")
 await main._resume_free_dispatch(snapshot,snapshot.route.duplicate(true),int(snapshot.ticks))
 check(main.sim.get_script()==load("res://scripts/pilot_delivery_simulation_v7.gd") and physical()==state,"old v7 input replay reproduces original physical state exactly")
 check(not snapshot.route.has("spatial_shield_schema") and snapshot.route.energy_policy=="unpowered-coast-v1","continuation does not add spatial shield assumptions")
 var before:int=main.economy.credits;main.abort_flight()
 check(main.economy.in_flight.is_empty() and main.report.control_version==Legacy.VERSION and not main.report.success and main.economy.credits<before,"old actual flight abort settles under retained v7 terms")
 finish()
func finish()->void:
 print("SHIELD_LEGACY_V7 ",passed," passed ",failed," failed");get_tree().quit(0 if failed==0 else 1)
