extends SceneTree
const E=preload("res://scripts/economy.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
const U=preload("res://scripts/delivery_rift_risk_ui_v1.gd")
const Sim=preload("res://scripts/pilot_delivery_rift_simulation_v8.gd")
var passed=0
var failed=0
var raw:Dictionary
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a,b)->bool:return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))
func load_seed(path:String):
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(path));file.close()
 var e=E.new();e.load_state();e.enable_story_mode();return e
func reload_e():
 var e=E.new();e.load_state();e.enable_story_mode();return e
func _initialize():
 raw=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_MOON")))
 var e=load_seed(OS.get_environment("SC_MOON"));check(not e.review_load_blocked and e.credits==1274,"genuine moon save loads 1274")
 var old=e.contracts.duplicate(true);e.ensure_contracts();check(same(old,e.contracts),"old visible day4 unchanged")
 check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"normal day boundary")
 var r=e.contracts[0].duplicate(true);check(r.contract_id=="D5-A" and r.rift_delivery_layout==C.COLD_MAINLINE_ID and r.chapter_progression,"new fifth mainline selected")
 check(r.reward==660 and r.required==80 and r.distance==240 and C.route_error(r).is_empty(),"same fees threshold valid layout")
 check(U.preview(r).cold_bounds==Rect2(110,-30,100,60) and U.guidance(r).contains("暖区") and not r.story.contains("不推进"),"normal preview and mainline wording")
 var shown=e.contracts.duplicate(true);e.ensure_contracts();check(same(shown,e.contracts),"new shown batch immutable")
 check(e.accept_contract_and_save("D5-A",raw.design,raw.launcher,raw.settings).ok and e.mark_cargo_loaded("D5-A").ok,"ordinary accept cargo")
 var purchase=e.buy_part_and_save("heater",{"price":45},raw.design,raw.launcher,raw.settings);print("PURCHASE ",purchase," mode ",e.flight_mode," phase ",e.phase);check(purchase.ok and e.credits==1229,"ordinary45 purchase affordable")
 var dialogue=e.story_conversation("D5-A","accept");check(dialogue.get("lines",[]).size()>2,"original dialogue retained beyond tutorial")
 var ship=raw.design.duplicate(true);ship[4].y=1;ship.append({"id":1027,"type":"heater","x":1,"y":0,"rot":0,"param":0,"target":-1,"input_a":-1,"input_b":-1})
 check(e.missing_parts(ship,raw.launcher).is_empty(),"all parts owned at full purchase")
 check(e.save_state(ship,raw.launcher,raw.settings),"accepted save");e=reload_e();check(not e.review_load_blocked and e.active_contract().rift_delivery_layout==C.COLD_MAINLINE_ID,"accepted reload")
 var before=e.delivery_chapter_state.duplicate(true);var money=e.credits
 var sim=Sim.new();sim.configure(ship,raw.launcher,r,42);sim.release_launcher(0,1)
 var ticks=0
 for tick in range(7200):
  if sim.status!="running":break
  var body=sim.body_for_part(1);var target=Vector2(240,0) if sim.telemetry.region=="greenhouse" else Vector2(29,0)
  var delta:Vector2=target-sim.cargo_position();var speed=minf(12,sqrt(5.6*maxf(0,delta.length()-1)));var request:Vector2=(delta.normalized()*speed-body.velocity).limit_length(3);var input:Vector2=request*float(body.mass)/(56*.72)
  sim.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,false,-1,false);sim.step(1.0/60);ticks+=1
 check(sim.status=="success" and sim.ship_integrity()>.96,"same fixed direct controller succeeds")
 var quote=e.estimate_delivery(r,sim.telemetry,sim.elapsed,true);check(quote.delivery_qualified and same(before,e.delivery_chapter_state) and money==e.credits,"trial estimate no charge or advancement")
 check(e.begin_dispatch(ship,raw.launcher,{"angle_degrees":0.0,"power_fraction":1.0}).ok,"formal dispatch")
 check(e.save_state(ship,raw.launcher,raw.settings),"inflight save");var flight=e.in_flight.duplicate(true);e=reload_e();check(not e.review_load_blocked and same(flight,e.in_flight),"inflight restore frozen mainline")
 # Ledger boundary using actual simulation telemetry; not GUI or command replay.
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation");e.in_flight.ticks=ticks;e.in_flight.elapsed=sim.elapsed
 var result=e.settle_contract_and_save("D5-A",sim.telemetry,sim.elapsed,true,ship,raw.launcher,raw.settings)
 check(result.ok and e.last_settlement.success and e.delivery_chapter_state.unlocked_level==6,"actual simulation outcome ledger advances fifth once")
 var settled=e.last_settlement.duplicate(true);check(not e.settle_contract("D5-A",sim.telemetry,sim.elapsed,true).ok and same(settled,e.last_settlement),"duplicate settlement rejected")
 e=reload_e();check(not e.review_load_blocked and e.delivery_chapter_state.unlocked_level==6,"completion reload")
 check(e.close_day_and_save(ship,raw.launcher,raw.settings).ok and e.next_day_and_save(ship,raw.launcher,raw.settings).ok and e.contracts[0].get("rift_delivery_layout")==C.COLD_REPEAT_ID,"post campaign day6 unchanged")
 # Independent failure ledger branch from normal old completed moon save.
 e=load_seed(OS.get_environment("SC_MOON"));e.close_day();e.next_day();e.accept_contract("D5-A");e.mark_cargo_loaded("D5-A");e.begin_dispatch(raw.design,raw.launcher,{"angle_degrees":0.0,"power_fraction":1.0})
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 var failure=Sim.new();failure.configure(raw.design,raw.launcher,e.active_contract(),42);failure.release_launcher(0,1);failure.step(1.0/60);e.in_flight.ticks=1;e.in_flight.elapsed=failure.elapsed
 result=e.settle_contract_and_save("D5-A",failure.telemetry,failure.elapsed,false,raw.design,raw.launcher,raw.settings)
 check(result.ok and not e.last_settlement.success and e.last_settlement.income==0 and e.delivery_chapter_state.unlocked_level==5,"failed attempt pays actual costs no progression")
 e=reload_e();check(not e.review_load_blocked and e.delivery_chapter_state.unlocked_level==5,"failure save reload")
 # Genuine old accepted fifth quote; no mutation of original file.
 var oldraw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_OLD5")))
 e=load_seed(OS.get_environment("SC_OLD5"));var accepted=e.active_contract().duplicate(true);check(not e.review_load_blocked and accepted.distance==200 and not accepted.has("rift_delivery_layout"),"genuine old fifth accepted200 retained")
 e.ensure_contracts();check(same(accepted,e.active_contract()),"old accepted ensure unchanged")
 check(e.begin_dispatch(oldraw.design,oldraw.launcher,oldraw.settings.launch_settings).ok,"old dispatch supported")
 flight=e.in_flight.duplicate(true);check(e.save_state(oldraw.design,oldraw.launcher,oldraw.settings),"old inflight saved");e=reload_e();check(not e.review_load_blocked and same(flight,e.in_flight),"old inflight reload exact200")
 var main=C.fresh_route(5,true,false,false,false,true);var repeat=C.fresh_route(5,false,false,false,true)
 check(C.route_error(main).is_empty() and C.route_error(repeat).is_empty(),"both independent identities valid")
 main.chapter_progression=false;repeat.chapter_progression=true;check(not C.route_error(main).is_empty() and not C.route_error(repeat).is_empty(),"identity cannot flip advancement")
 check(C.fresh_route(5,false,false,false,false,true).is_empty() and C.fresh_route(5,true,true,false,false,true).is_empty() and C.fresh_route(5,true,false,false,true,true).is_empty(),"invalid authoring combos rejected")
 print("DEV46_CHECK passed=%d failed=%d"%[passed,failed]);quit(0 if failed==0 else 1)
