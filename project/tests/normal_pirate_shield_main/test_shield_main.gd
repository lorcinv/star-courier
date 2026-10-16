extends "res://tests/normal_pirate_main_g3/test_earned_pirate_main.gd"
## One independent CPU-only Main/API branch from the exact genuine D4 save.
## Inherits the byte-identical guide() and command() from the completed paid
## continuation. Only ordinary Main shop/editor/dispatch operations mutate play.
## No source, route, physics, persisted data, fit flag, or resource injection.
var purchased_stock:Dictionary={}
var built_design:Array=[]
var shield_id:int=-1
var physical_attempts:int=0
var finish_calls:int=0
var physical_outcome:String="not_reached"
var observed_events:Array=[]
var launch_observation:Dictionary={}
var purchase:Dictionary={}

func live_snapshot() -> Dictionary:
 var s=game.sim
 var modules:Array=[]
 for p in s.parts.values():
  modules.append({"id":p.id,"type":p.type,"alive":p.alive,"delivered":p.delivered,"hp":p.hp,"energy":p.energy,"capacity":p.capacity,"stored_energy":p.stored_energy,"body_id":p.body_id,"position":s._part_position(p),"input_a":p.input_a,"input_b":p.input_b,"target":p.target})
 var shield:Dictionary=s.parts.get(shield_id,{})
 var battery:Dictionary=s.parts.get(3,{})
 return {"tick":game.pilot_completed_ticks,"elapsed":s.elapsed,"status":s.status,"cargo_position":s.cargo_position(),"modules":modules,"launcher_parts":s.launcher_parts.duplicate(true),"links":s.links.duplicate(true),"mass":s.total_mass(),"energy":s.total_energy(),"telemetry":s.telemetry.duplicate(true),"shield_enabled":not shield.is_empty() and s._enabled(shield),"shield_battery_same_circuit":s._same_circuit(shield,battery),"shield_component":s._component(shield_id),"reservations":s.chrono_reservations.duplicate(true)}

func buy_and_author() -> bool:
 if not await skip_available_pair("day4"):return false
 var before:Dictionary=ledger()
 game._action("close_day",null);await frames()
 if not check(game.economy.phase=="night" and game.economy.day==4,"Main closes genuine declined D4 into night supply"):return false
 capture("day4-night-before-purchase")
 game._action("buy","shield");await frames()
 purchased_stock=game.economy.inventory.duplicate(true)
 purchase={"item":"shield","quantity":1,"capital_cost":55,"credits_before":before.credits,"credits_after":game.economy.credits,"stock_before":before.stock,"stock_after":purchased_stock}
 write_json("PURCHASE.json",purchase);capture("day4-night-shield-purchased")
 var expected_stock:Dictionary=before.stock.duplicate(true);expected_stock.shield=1
 if not check(game.economy.credits==1091 and int(before.stock.get("shield",0))==0 and equal(purchased_stock,expected_stock) and equal(game.design,initial.design) and equal(game.launcher,initial.launcher) and original_receipts_exact(),"exact one genuine 55-credit purchase increases owned shield stock 0 to 1 only"):return false
 game._action("next_day",null);await frames()
 if not check(game.economy.day==5 and game.economy.phase=="morning" and game.economy.credits==1091 and game.economy.jobs_today==0,"normal next_day authors D5 without grants"):return false
 var e=game.economy
 if not check(e.contracts.size()==2,"D5 has the ordinary A and optional B pair"):return false
 var a:Dictionary=e.contracts[0];var b:Dictionary=e.contracts[1]
 if not check(a.get("contract_id")=="D5-A" and not Offer.has_markers(a) and e.route_preflight_error(a).is_empty(),"ordinary D5-A preserved"):return false
 if not check(b.get("contract_id")=="D5-B" and Offer.has_markers(b) and Offer.validation_error(b).is_empty() and e.route_preflight_error(b).is_empty(),"D5-B is genuinely generated and admitted; any deferral is retained"):return false
 if not check(int(b.id)==5 and int(b.seed)==516 and int(b.reward)==340 and float(b.weight)==1.55 and float(b.deadline)==50.0 and float(b.time_limit)==70.0 and float(b.required)==85.0,"optional B has exact seed and commercial terms"):return false
 contract_id="D5-B";offers=e.contracts.duplicate(true)
 check(e.deliveries==6 and e.settled_ids.size()==6 and original_receipts_exact() and equal(e.inventory,purchased_stock) and equal(game.design,initial.design) and equal(game.launcher,initial.launcher),"six genuine receipts and retained hardware unchanged after authoring")
 write_json("GENERATED-OFFER.json",{"ordinary_a":a,"optional_b":b,"root":e.offer_generation_state,"origin":"Main decline A/B, close day, one shield buy, next_day"})
 capture("day5-generated")
 return failed==0

func load_and_build() -> bool:
 game.navigate("hub");game.world.request_shop_navigation("focus_counter")
 for unused in 3600:
  if game.world.is_at_shop_counter():break
  shop_step(1.0/120.0)
 game._action("accept_contract",contract_id)
 if not await wait_story("accept"):return false
 if not check(game.economy.active_contract_id==contract_id,"optional order accepted by Main at the counter"):return false
 game.dialogue.skip_conversation();game._sync_loading_scene_ui()
 shop_step(24.0);await frames()
 if not check(game.economy.is_cargo_loaded(contract_id) and game.world.is_parcel_loaded(contract_id) and game.page=="workshop","natural loading completes into workshop"):return false
 capture("day5-loaded-before-build")
 game._action("assembly_mode","craft");game._action("select_catalog","shield")
 if not check(game.workshop_input.enabled(),"normal workshop editor permits placement"):return false
 var allocated:int=game.next_id
 game.workshop_input._commit({"kind":"place","cell":Vector2i(-1,-1)})
 await frames();shield_id=int(game.selected_id);built_design=game.design.duplicate(true)
 if not check(built_design.size()==9 and shield_id==allocated and game.next_id==allocated+1,"editor allocates exactly one actual shield ID without overriding the allocator"):return false
 var p:Dictionary=game.selected_part()
 if not check(p.type=="shield" and int(p.x)==-1 and int(p.y)==-1 and int(p.rot)==0 and float(p.param)==1.5 and int(p.input_a)==-1 and int(p.input_b)==-1 and int(p.target)==-1,"placed shield has exact cell, orientation, parameter and automatic input"):return false
 var original:Array=built_design.duplicate(true);original.pop_back()
 if not check(equal(original,initial.design) and equal(game.launcher,initial.launcher) and equal(game.economy.inventory,purchased_stock) and game._installed_count("shield")==1 and game.economy.missing_parts(game.design,game.launcher).is_empty(),"existing eight craft and three launcher parts exact, one owned shield now installed with zero spare"):return false
 if not check(equal(disk().design,built_design) and equal(disk().launcher,initial.launcher),"ordinary editor persists the real placement"):return false
 capture("shield-built")
 write_json("BUILD.json",{"actual_shield_id":shield_id,"allocator_expected":allocated,"usual_expected_id":1004,"design":built_design,"launcher":game.launcher,"stock":purchased_stock,"installed_shield":1,"spare_shield":0,"placement_api":"workshop_input._commit","no_blueprint_injection":true})
 return failed==0

func paid_flight() -> bool:
 var before:Dictionary=ledger()
 var route:Dictionary=game.economy.trial_route().duplicate(true)
 physical_attempts+=1;game._action("dispatch",null)
 if not check(game.page=="flight" and not game.trial and game.economy.in_flight.get("contract_id")==contract_id,"single paid dispatch admitted through actual Main"):return false
 if not check(equal(game.economy.in_flight.design,built_design) and equal(game.economy.in_flight.launcher,initial.launcher) and equal(game.economy.in_flight.route,route) and game.pilot_completed_ticks==0 and equal(ledger(),before),"atomic paid commit has exact purchased hardware and route without settlement"):return false
 launch_observation=live_snapshot()
 launch_observation.countdown=game.launch_countdown;launch_observation.transfer_remaining=game.launch_transfer_remaining
 write_json("LAUNCH.json",launch_observation);capture("paid-launch")
 if not check(absf(game.sim.total_mass()-12.65)<0.00001 and absf(game.sim.total_energy()-6000.0)<0.00001 and absf(float(game.sim.telemetry.energy_used)-20.0)<0.00001,"runtime verifies 12.65kg, 6000J own craft storage and separate 20J launcher preparation"):return false
 var shield:Dictionary=game.sim.parts[shield_id]
 if not check(game.sim._enabled(shield) and game.sim._same_circuit(shield,game.sim.parts[3]) and game.sim._linked(shield_id,3) and game.sim._linked(shield_id,4),"live automatic shield has the two real sockets and its own connected craft battery"):return false
 for unused in 1200:
  if game.launch_countdown<=0.0:break
  game._process(1.0/60.0)
 if not check(game.launch_countdown<=0.0 and not game.paused,"actual launch transfer and countdown finish normally"):return false
 var budget:float=game.sim.total_energy()+float(game.sim.telemetry.energy_used)
 var min_energy:float=game.sim.total_energy();var drift:float=0.0;var axis:int=0
 var warning_count:int=0;var ray_count:int=0
 var limit:int=ceili(float(route.time_limit)*60.0)+1
 stage="paid-flight"
 while game.sim.status=="running" and game.pilot_completed_ticks<limit:
  if game.pilot_completed_ticks%12==0:axis=guide()
  var previous:Dictionary=live_snapshot()
  command(axis);game._step_flight()
  min_energy=minf(min_energy,game.sim.total_energy())
  drift=maxf(drift,absf(game.sim.total_energy()+float(game.sim.telemetry.energy_used)-budget))
  var trace:Array=game.sim.chrono_trace.duplicate(true)
  var contacts:Array=[]
  for row in trace:
   if row.get("kind")=="contact":contacts.append(row)
  if game.sim.pirate.warnings.size()!=warning_count or game.sim.route_ray_records.size()!=ray_count or not contacts.is_empty():
   observed_events.append({"before":previous,"after":live_snapshot(),"warnings":game.sim.pirate.warnings.duplicate(true),"rays":game.sim.route_ray_records.duplicate(true),"contacts":contacts,"trace":trace})
   warning_count=game.sim.pirate.warnings.size();ray_count=game.sim.route_ray_records.size()
   write_json("EVENT-OBSERVATIONS.json",observed_events)
 if not check(game.sim.status in ["success","failed"] and not game.pilot_resume_blocked and game.sim.chrono_error.is_empty(),"one unchanged-guide attempt reaches an honest terminal without hold or force"):return false
 physical_outcome=str(game.sim.status);stage="terminal"
 write_json("TERMINAL-LIVE.json",live_snapshot());capture("paid-terminal")
 var terminal:Dictionary=game.sim.route_terminal.duplicate(true)
 var elapsed:float=game.sim.elapsed
 finish_calls+=1;game.finish_flight();capture("paid-report")
 if not check(game.page=="report" and game.economy.settled_ids.has(contract_id),"Main settles the genuine terminal once into a durable report"):return false
 var receipt:Dictionary=game.economy.settled_ids[contract_id]
 var telemetry:Dictionary=game.sim.telemetry.duplicate(true)
 var integrity:float=float(telemetry.get("integrity",0.0))*100.0
 var income:int=int(int(route.reward)*clampf(float(route.deadline)/maxf(elapsed,float(route.deadline)),.35,1.0)*clampf(integrity/float(route.required),0.0,1.0)) if physical_outcome=="success" else 0
 var expected:Dictionary={"income":income,"energy":int(ceil(float(telemetry.energy_used)*clampf(float(route.pilot_energy_tariff),.001,.18))),"ammo":int(ceil(float(telemetry.get("ammo_cost",0.0)))),"repairs":int(ceil(float(telemetry.get("repair_cost",0.0)))),"lost":int(ceil(float(telemetry.get("lost_cost",0.0))))}
 expected.profit=expected.income-expected.energy-expected.ammo-expected.repairs-expected.lost
 var costs_ok:bool=true
 for key in expected:
  if int(receipt.get(key,-999999))!=int(expected[key]) or int(game.report.get(key,-999999))!=int(expected[key]):costs_ok=false
 check(costs_ok and game.economy.credits==int(initial.credits)-55+int(expected.profit),"receipt itemization and credits reconcile with 55 capital cost separated")
 check(game.economy.settled_ids.size()==7 and game.economy.jobs_today==1 and original_receipts_exact() and game.economy.in_flight.is_empty() and finish_calls==1,"exactly one new receipt and paid slot, all six original receipts preserved")
 check(game.economy.deliveries==6+(1 if physical_outcome=="success" else 0) and bool(receipt.success)==(physical_outcome=="success") and equal(receipt.route_terminal,terminal),"delivery counter and durable terminal follow actual physics")
 check(equal(game.design,built_design) and equal(game.launcher,initial.launcher) and equal(game.economy.inventory,purchased_stock),"normal settlement preserves owned shield build and finite stock")
 check(min_energy>=-0.000001 and drift<0.01,"courier stored plus used energy stays finite and conserved")
 var outcome:Dictionary={"status":physical_outcome,"elapsed":elapsed,"integrity_percent":integrity,"on_time":elapsed<=float(route.deadline),"minimum_energy":min_energy,"maximum_energy_drift":drift,"full_telemetry":telemetry,"terminal":terminal,"warnings":game.sim.pirate.warnings.duplicate(true),"emissions":game.sim.pirate.emissions.duplicate(true),"rays":game.sim.route_ray_records.duplicate(true),"commands":game.pilot_timeline.snapshot(),"receipt":receipt,"report":game.report.duplicate(true),"independent_expected_costs":expected,"capital_purchase_cost":55,"cash_change_from_D4":game.economy.credits-int(initial.credits),"finish_calls":finish_calls,"policy":"byte-identical inherited discrete W/S guide and command, every 12 ticks; one paid physical attempt; no retuning"}
 write_json("PAID-OUTCOME.json",outcome);flights.append(outcome)
 if physical_outcome!="success":return check(false,"physical failure preserved and normally settled; no retry or refill")
 if not check(int(expected.profit)>0,"actual operating net is positive"):return false
 if failed>0:return false
 game._on_focus_entered();stage="result-and-return"
 if not await finish_return():return false
 if not await restart_boundary("paid-returned-hub"):return false
 if not check(game.page=="hub" and game.sim==null and not game._dialogue_is_open() and game.economy.pending_story_returns().is_empty(),"clean hub scene reload has no repeated callback or ghost flight"):return false
 stage="delayed-review"
 if not await next_morning("paid-day5"):return false
 var matches:Array=[]
 for review in game.economy.customer_reviews():
  if review.get("settlement_id")==contract_id:matches.append(review)
 check(game.economy.day==6 and game.economy.customer_reviews().size()==7 and game.economy.review_state.pending.is_empty() and matches.size()==1 and original_receipts_exact() and game.economy.credits==int(initial.credits)-55+int(expected.profit),"normal D6 publishes exactly one review without duplicate payment")
 if not await restart_boundary("review-published"):return false
 return failed==0

func run() -> void:
 output=OS.get_environment("SC_SHIELD_OUT");source_path=OS.get_environment("SC_SHIELD_SOURCE");mode="one-earned-shield-Main-API"
 var profile:String=OS.get_environment("SC_SHIELD_PROFILE").simplify_path().trim_suffix("/")
 var user_dir:String=ProjectSettings.globalize_path("user://").simplify_path()
 if not check(OS.get_environment("SC_SHIELD_ENGINE_GRANTED")=="1" and DisplayServer.get_name()=="headless" and profile.is_absolute_path() and "/normal-pirate-shield-main/" in profile and user_dir.begins_with(profile+"/"),"independent authorized CPU lane and isolated correct XDG profile"):await finish();return
 if not check(FileAccess.get_sha256(source_path)==SOURCE_SHA and not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"exact original D4 input and new profile with no overwrite"):await finish();return
 DirAccess.make_dir_recursive_absolute(user_dir)
 if not check(DirAccess.copy_absolute(source_path,"user://savegame.json")==OK and FileAccess.get_sha256("user://savegame.json")==SOURCE_SHA,"byte-identical genuine D4 save copied without editing"):await finish();return
 initial=disk();source_copy_verified=true;root.size=Vector2i(1280,720)
 if not await boot():await finish();return
 if not check(game.PIRATE_PLAYER_ROUTE_REGISTERED and game.economy.day==4 and game.economy.phase=="morning" and game.economy.credits==1146 and game.economy.deliveries==6 and game.economy.settled_ids.size()==6 and equal(game.economy.contracts,initial.contracts) and equal(game.design,initial.design) and equal(game.launcher,initial.launcher),"isolated R3 admission loads genuine D4 without changing its offers or earned state"):await finish();return
 capture("original-d4-loaded");stage="purchase-and-author"
 if not await buy_and_author():await finish();return
 stage="load-and-build"
 if not await load_and_build():await finish();return
 stage="paid-prepare"
 if not await paid_flight():await finish();return
 stage="complete";await finish()

func finish() -> void:
 if is_instance_valid(game):capture("final-"+stage)
 if not output.is_empty():write_json("SHIELD-RESULT.json",{"stage":stage,"mode":mode,"passed":passed,"failed":failed,"failures":failures,"physical_outcome":physical_outcome,"physical_attempts":physical_attempts,"finish_calls":finish_calls,"actual_shield_id":shield_id,"purchase":purchase,"flights":flights,"checkpoints":checkpoints,"native_input":false,"production_enabled":false,"guide_fit_verified":false,"pilot_retries":0,"proof":"one independent CPU-only Main/API shield branch from genuine D4, normal supplier/editor, unchanged guide"})
 print("SHIELD_MAIN passed=%d failed=%d stage=%s outcome=%s"%[passed,failed,stage,physical_outcome])
 await dispose();quit(0 if stage=="complete" and failed==0 else 1)
