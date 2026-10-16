extends Node
## Real completed-moon seed is copied into isolated XDG by the external runner.
## Ordinary day progression, native Main command recording and live settlement.
const Main=preload("res://scripts/main.gd")
const Protocols=preload("res://scripts/free_flight_protocols.gd")
const Profile=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
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
 if OS.get_environment("SC_CELL_RIFT_MAIN_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_require_existing_save=true;main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main)
 check(not main.economy.review_load_blocked,"actual native completed-moon save loads in successor Main")
 if main.economy.review_load_blocked:printerr(main.economy.load_notice);finish();return
 main.set_process(false)
 check(main.economy.day==5 and main.economy.credits==1229 and main.economy.deliveries==4,"native day credits and four deliveries retained")
 check(main.economy.flight_mode=="pilot-delivery-v3","shop mode remains v3")
 check(main.economy.contract_by_id("D5-A").get("control_version")=="pilot-ascent-v4" and main.economy.contract_by_id("D5-B").get("control_version")=="pilot-delivery-v3","already visible moon and basic contracts retain their exact old versions")
 check(main.economy.close_day_and_save(main.design,main.launcher,main.settings).ok,"ordinary close-day action saves completed moon day")
 var next:Dictionary=main.economy.next_day_and_save(main.design,main.launcher,main.settings)
 check(next.ok,"ordinary next-day action opens fifth-level delivery")
 if not next.ok:printerr(next);finish();return
 var order:Dictionary=main.economy.contract_by_id("D6-A")
 check(order.get("control_version")==Profile.VERSION and order.get("route_profile")==Profile.ROUTE_PROFILE,"normal D6-A is explicit rift protocol")
 check(main.economy.contract_by_id("D6-B").get("control_version")=="pilot-delivery-v6","B basic order retains debt recovery gameplay")
 check(main._recovery_route_error(order).is_empty(),"exact new rift profile earns its actual pixel presentation")
 check(not main._recovery_route_error({"control_version":"pilot-v4-wormhole","route_kind":"wormhole"}).is_empty(),"legacy incomplete wormhole capability remains blocked")
 var mixed:Dictionary=order.duplicate(true);mixed.control_version="pilot-delivery-v3"
 check(not Protocols.route_error(mixed).is_empty() and not main._recovery_route_error(mixed).is_empty(),"mixed rift markers cannot silently enter v3 physics")
 check(Framing.applies(order) and not Framing.is_ground_route(order),"rift uses bidirectional framing without ground identity")
 check(Parts.compatible("spring",false,Profile.VERSION),"rift preserves passive cargo mount compatibility")
 check(main.economy.accept_contract_and_save("D6-A",main.design,main.launcher,main.settings).ok,"normal fifth offer accepts and persists")
 main.page="workshop";main.assembly_mode="launcher";main.render()
 main._action("set_launch_settings",{"angle_degrees":0.0,"power_fraction":1.0})
 check(main.hud.state.control_version==Profile.VERSION and main.hud.state.launch_preview.velocity.x>0.0,"workshop receives new solver authority preview")
 check(main.economy.mark_cargo_loaded("D6-A").ok,"rift cargo loads through formal action")
 check(main.economy.begin_dispatch(main.design,main.launcher,main._launch_settings()).ok,"rift dispatch freezes version and launch settings")
 main._configure_flight(false,main.design,main.launcher,main.economy.in_flight.route.duplicate(true))
 check(main.page=="flight" and main.sim.get_script()==load("res://scripts/pilot_delivery_rift_simulation_v6.gd"),"Main selects exact rift solver")
 main.launch_age=.5;main.launch_transfer_remaining=0.0;main._checkpoint_flight()
 var prep:Dictionary=main.economy.in_flight.duplicate(true)
 check(main.save_game() and Protocols.snapshot_error(prep).is_empty(),"v6 preparation stage saves frozen release state")
 await main._resume_free_dispatch(prep,prep.route.duplicate(true),0)
 check(not main.sim.launch_released and main.paused and is_zero_approx(main.sim.telemetry.energy_used) and is_equal_approx(main.launch_age,.5),"pre-release Continue remains unpaid and unadvanced")
 main._set_paused(false);main.launch_age=.949;main._process(.0011)
 check(main.sim.launch_released and main.sim.telemetry.control_version==Profile.VERSION,"actual release uses rift identity once")
 var checks:Dictionary={"before":false,"after":false,"warning":false,"shot":false}
 var waypoint:int=0
 var points:Array[Vector2]=[Vector2(115,16),Vector2(178,16),Vector2(200,0)]
 for tick in 60*90:
  if main.sim.status!="running":break
  var at:Vector2=main.sim.cargo_position()
  var region:String=str(main.sim.telemetry.get("region","departure"))
  var goal:Vector2=Vector2(29,0)
  if region=="greenhouse":
   if at.distance_to(points[waypoint])<5.0 and waypoint<points.size()-1:waypoint+=1
   goal=points[waypoint]
  steer(goal,10.0 if region=="greenhouse" else 7.0)
  main._step_flight()
  var t:Dictionary=main.sim.telemetry
  if not checks.before and main.pilot_completed_ticks>=60 and t.get("region")=="departure":
   checks.before=true;await replay_boundary("before portal")
  if not checks.after and t.get("region")=="greenhouse":
   checks.after=true
   check(int(t.get("portal_crossing_tick",-1))>=0 and t.get("portal_crossings",[]).size()==1,"physical crossing creates one real portal proof")
   await replay_boundary("after portal")
  var pirate:Dictionary=main.sim.telemetry.get("rift_pirate",{})
  if not checks.warning and pirate.get("warning",false):
   checks.warning=true;await replay_boundary("pirate warning")
  if not checks.shot and int(pirate.get("shots_fired",0))>0:
   checks.shot=true;await replay_boundary("after pirate shot")
 check(checks.before and checks.after and checks.warning and checks.shot,"real flight visits portal and actual warning/shot replay boundaries")
 print("RIFT_MAIN_FLIGHT ",JSON.stringify({"status":main.sim.status,"elapsed":main.sim.elapsed,"at":[main.sim.cargo_position().x,main.sim.cargo_position().y],"integrity":main.sim.telemetry.delivery_integrity,"energy":main.sim.telemetry.energy_used,"boundaries":checks}))
 check(main.sim.status=="success","normal owned native assembly completes required-gate biological delivery")
 if main.sim.status=="success":main.finish_flight()
 else:main.abort_flight()
 check(main.page=="report" and main.economy.in_flight.is_empty() and main.report.control_version==Profile.VERSION,"formal rift flight settles with exact control version")
 if bool(main.report.get("success",false)):
  check(main.report.get("portal_delivery_evidence",{}).get("schema")=="rift-crossing-proof-v1","successful receipt stores verified portal evidence")
 var restored=Economy.new();var saved:Dictionary=restored.load_state(true)
 check(not saved.is_empty() and restored.credits==main.economy.credits and restored.in_flight.is_empty(),"receipt and credits reload without duplicate settlement")
 finish()
func steer(goal:Vector2,speed:float)->void:
 var body:Dictionary=main.sim.body_for_part(1)
 var delta:Vector2=goal-main.sim.cargo_position()
 var desired:Vector2=delta.normalized()*minf(speed,sqrt(2.0*2.0*maxf(0.0,delta.length()-1.0)))
 var error:Vector2=desired-Vector2(body.velocity)
 main.pilot_keys.clear()
 if error.x>.2:main.pilot_keys[KEY_D]=true
 elif error.x<-.2:main.pilot_keys[KEY_A]=true
 if error.y>.2:main.pilot_keys[KEY_S]=true
 elif error.y<-.2:main.pilot_keys[KEY_W]=true
func physical_state()->PackedByteArray:
 var evidence:Dictionary={}
 var keys:Array=main.sim.telemetry.keys();keys.sort()
 for key in keys:
  if str(key).begins_with("rift_") or str(key).begins_with("portal_") or key in ["region","required_portal_id","pilot_tick","energy_used","delivery_integrity"]:evidence[key]=main.sim.telemetry[key]
 return var_to_bytes([main.sim.parts,main.sim.bodies,main.sim.obstacles,evidence])
func replay_boundary(label:String)->void:
 main._checkpoint_flight()
 var snapshot:Dictionary=main.economy.in_flight.duplicate(true)
 var exact:PackedByteArray=physical_state()
 check(Protocols.snapshot_error(snapshot).is_empty() and main.save_game(),label+" checkpoint saves")
 await main._resume_free_dispatch(snapshot,snapshot.route.duplicate(true),int(snapshot.ticks))
 check(not main.pilot_resume_blocked and physical_state()==exact,label+" replay preserves bodies, energy, crossing and threat state exactly")
 main._set_paused(false)
func finish()->void:
 print("CELL_RIFT_MAIN_V6 ",passed," passed ",failed," failed")
 get_tree().quit(0 if failed==0 else 1)
