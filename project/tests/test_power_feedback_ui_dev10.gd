extends SceneTree
## Fresh isolated Main/World/HUD regression. Core launch, simulator termination,
## finish_flight and save/reload are production paths. Setup accepts/loads the
## first order through Economy; this is not native mouse or visual acceptance.
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Legacy=preload("res://scripts/pilot_free_profile_v1.gd")
const Economy=preload("res://scripts/economy.gd")
const Power=preload("res://scripts/workshop_power_status_v1.gd")
const Simulator=preload("res://scripts/pilot_free_simulation_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const DISCONNECTED:String="电芯未连到货舱。回工位接好再试。"
const DEPLETED:String="电量耗尽，没能送达。"
class QuietMain extends "res://scripts/main.gd":
 var save_calls:int=0
 func save_game() -> bool:save_calls+=1;return super.save_game()
 func _ensure_audio_players() -> void:pass
 func _play_music(_flying:bool) -> void:pass
 func _sound(_name:String) -> void:pass
var game
var passed:int=0
var failed:int=0
var battery_id:int=-1
var cargo_id:int=-1
var contract_id:String=""
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func settle(count:int=4) -> void:
 for unused in count:await process_frame
func named(name:String) -> Node:return game.hud.content.find_child(name,true,false)
func label_text(name:String) -> String:
 var node:=named(name) as Label
 return node.text if node!=null else ""
func action_button(action:String) -> Button:
 for node in game.hud.content.find_children("*","Button",true,false):
  if str(node.get_meta("view_key",""))=="action:"+action+":null":return node
 return null
func visible_labels() -> Array:
 var labels:Array=[]
 for node in game.hud.content.find_children("*","Label",true,false):
  if node.is_visible_in_tree():labels.append(node.text)
 return labels
func persisted() -> Dictionary:
 var value:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 return value if value is Dictionary else {}
func model_bytes() -> PackedByteArray:
 return var_to_bytes([game.design,game.launcher,game.undo_history,game.next_id,game.economy.inventory,game.economy.credits,game.economy.contracts,game.economy.settled_ids,game.economy.in_flight,game.economy.last_trials,game.economy.story_state,game.save_calls,FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")])
func workshop() -> void:
 game.workshop_input.cancel();game.page="workshop";game.assembly_mode="craft";game.selected_id=battery_id
 game.hud.palette_open=false;game.render();game.workshop_input.fit()
func move_battery(from:Vector2i,to:Vector2i) -> void:
 game.workshop_input._commit({"kind":"move","id":battery_id,"from":from,"cell":to})
func part_cell(id:int) -> Vector2i:
 for part in game.design:
  if int(part.id)==id:return Vector2i(int(part.x),int(part.y))
 return Vector2i(999,999)
func physical_bytes() -> PackedByteArray:
 return var_to_bytes([game.sim.parts,game.sim.bodies,game.sim.links,game.sim.events,game.sim.telemetry,game.sim.elapsed,game.sim._rng.state])
func terminal_step() -> bool:
 for unused in 120:
  if game.sim.status!="running":break
  game._step_flight()
 return check(game.sim.status=="failed" and game.sim.telemetry.get("free_failure","")=="usable_energy_empty","actual simulator reaches the unchanged usable-energy terminal condition")
func check_report(code:String,copy:String,is_trial:bool) -> void:
 var before:PackedByteArray=physical_bytes()
 check(Power.runtime_failure(game.sim).code==code,"read-only runtime observation identifies "+code)
 check(physical_bytes()==before,"runtime diagnosis does not mutate solver or RNG")
 game.finish_flight()
 check(game.page=="report" and game.report.success==false and game.report.trial==is_trial,"real Main.finish_flight publishes the terminal "+("trial" if is_trial else "delivery")+" report")
 check(game.report.get("cause","")==copy,"Main diagnosis stores precise "+code+" cause")
 check(game.report.get("free_failure","")=="usable_energy_empty" and game.report.get("power_failure",{}).get("code","")==code,"report carries presentation evidence without changing terminal protocol")
 check(game.report.events.any(func(item):return str(item).contains("货舱可用能量耗尽，委托失败。")),"original simulator terminal event remains present as the priority-regression witness")
 check(game.hud._report_failure_copy(game.report)==copy and copy in visible_labels(),"visible report prioritizes precise power reason over the old terminal event")
 if is_trial:
  var record:Dictionary=game.economy.last_trials.get(contract_id,{}).get("latest",{})
  check(record.get("cause","")==copy and record.get("power_failure",{}).get("code","")==code,"in-memory last_trials keeps precise cause and evidence")
  var saved:Dictionary=persisted().get("last_trials",{}).get(contract_id,{}).get("latest",{})
  check(saved.get("cause","")==copy and saved.get("power_failure",{}).get("code","")==code,"durable last_trials keeps precise cause and evidence")
  var reopened=Economy.new();var loaded:Dictionary=reopened.load_state()
  check(not loaded.is_empty() and not reopened.review_load_blocked and reopened.last_trials.get(contract_id,{}).get("latest",{}).get("cause","")==copy,"real Economy reload retains the saved cause")
func layout_case(extent:Vector2i,palette:bool) -> void:
 root.size=extent;game._apply_quality();game.hud.palette_open=palette;game.render();await settle()
 var frame:=Rect2(Vector2.ZERO,Vector2(extent))
 var warning:=named("WorkshopPowerOrBoundsWarning") as Control
 var inspector:=named("ModuleInspector") as Control
 var startup:=named("ModuleStartupStatus") as Control
 var region:Rect2=game.hud.workshop_scene_rect()
 var suffix:String=" "+str(extent)+" palette="+str(palette)
 check(warning!=null and frame.encloses(warning.get_global_rect()),"warning stays inside native viewport"+suffix)
 check(inspector!=null and startup!=null and frame.encloses(inspector.get_global_rect()) and inspector.get_global_rect().encloses(startup.get_global_rect()),"selected disconnected status remains visible inside inspector"+suffix)
 check(region.size.x>0 and region.size.y>0 and frame.encloses(region) and not region.intersects(warning.get_global_rect()) and not region.intersects(inspector.get_global_rect()),"warning and inspector leave a nonzero unobscured drag region"+suffix)
 check(not game.hud.blocks_workshop_pointer(region.get_center()),"center of usable drag region is not captured by UI"+suffix)
 for action in ["trial","dispatch"]:
  var button:=action_button(action)
  check(button!=null and button.is_visible_in_tree() and not button.disabled and frame.encloses(button.get_global_rect()),"unpowered craft retains usable "+action+" button"+suffix)
func multi_cargo_hud_cases() -> void:
 # These are real simulator/helper observations projected into the existing HUD.
 # Main launch intentionally accepts one customer's cargo only, so do not alter
 # production preflight or persist a manufactured multi-cargo blueprint.
 var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 for mode in ["one_disconnected","one_depleted","mixed"]:
  var craft:Array=[Extreme.part(1,"cargo",0),Extreme.part(2,"battery",1),Extreme.part(10,"cargo",10),Extreme.part(12,"battery",15 if mode!="one_depleted" else 11)]
  var sim=Simulator.new();sim.configure(craft,[],route,42)
  if mode!="one_disconnected":sim.parts[2].energy=0.0
  sim.step(1.0/120.0)
  var failure:Dictionary=Power.runtime_failure(sim)
  var code:String="battery_disconnected" if mode=="one_disconnected" else "energy_depleted" if mode=="one_depleted" else "mixed_power_failure"
  var copy:String="货舱未接电芯" if mode=="one_disconnected" else "货舱电量耗尽" if mode=="one_depleted" else "货舱供电中断"
  check(sim.status=="failed" and failure.code==code,"real multi-cargo fixture classifies "+mode)
  var before:PackedByteArray=var_to_bytes([craft,sim.parts,sim.bodies,sim.links,sim.telemetry,sim.events,sim._rng.state])
  var data:Dictionary=sim.telemetry.duplicate(true);data.power_failure=failure;data.events=sim.events.duplicate();data.elapsed=sim.elapsed;data.charging=false;data.paused=false
  game.hud.render({"mode":"flight","control_version":Profile.VERSION,"activeorder":route,"settings":{"reduced_motion":true},"flight":data})
  check(game.hud.flight_labels.energy_warning.text==copy,"HUD retains exact cargo-specific warning for "+mode)
  if mode!="mixed":
   check(float(sim.telemetry.energy_remaining)>0.0 and float(sim.telemetry.energy_fraction)>0.0,"another cargo keeps real positive aggregate battery energy for "+mode)
   check(game.hud._energy_bar.value>0.0 and is_equal_approx(game.hud._energy_bar.value,float(sim.telemetry.energy_fraction)*100.0),"HUD preserves positive actual energy bar rather than inventing total depletion for "+mode)
  print("POWER_FEEDBACK_LIVE_RECEIPT mode=",mode," text=",game.hud.flight_labels.events.text)
  var terminal_copy:String=DISCONNECTED if mode=="one_disconnected" else DEPLETED if mode=="one_depleted" else "货舱供电中断。回工位检查电芯。"
  check(game.hud.flight_labels.events.text==terminal_copy,"live terminal receipt agrees with observed cause for "+mode)
  check(var_to_bytes([craft,sim.parts,sim.bodies,sim.links,sim.telemetry,sim.events,sim._rng.state])==before,"multi-cargo HUD rendering never mutates simulator or design for "+mode)
func exercise() -> void:
 game=load("res://scenes/main.tscn").instantiate();game.set_script(QuietMain)
 game.entry_settings_overrides={"volume":0.0,"dialogue_volume":0.0,"reduced_motion":true,"fullscreen":false}
 root.add_child(game);game.set_process(false);await settle(6)
 if not check(not game.economy.review_load_blocked and game.design==Profile.starter_design() and game.launcher==Profile.starter_launcher(),"actual fresh Main keeps the exact default craft and launcher"):return
 game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 game._on_focus_entered();game.courier_input.synchronize()
 for part in game.design:
  if part.type=="battery":battery_id=int(part.id)
  if part.type=="cargo":cargo_id=int(part.id)
 if not check(battery_id>=0 and cargo_id>=0 and part_cell(battery_id)==Vector2i(-1,0),"fresh starter exposes the exact battery at (-1,0)"):return
 contract_id=str(game.economy.contracts[0].contract_id)
 check(game.economy.accept_contract(contract_id).ok,"fixture accepts the real fresh first order")
 game.economy.mark_story_seen(contract_id,contract_id+"/accept")
 check(game.economy.mark_cargo_loaded(contract_id).ok and game.economy.active_contract().control_version==Profile.VERSION,"fresh first order retains its v2 identity and loaded cargo")
 workshop();await settle()
 check(named("WorkshopPowerOrBoundsWarning")==null and game.world.grid.unpowered_cells.is_empty() and game.world.grid.disconnected_battery_cells.is_empty(),"connected default craft has no false warning or power marks")
 var original:Array=game.design.duplicate(true)
 move_battery(Vector2i(-1,0),Vector2i(-3,0));await settle()
 if not check(part_cell(battery_id)==Vector2i(-3,0),"production workshop edit moves only the battery to (-3,0)"):return
 var expected:Array=original.duplicate(true)
 for part in expected:
  if int(part.id)==battery_id:part.x=-3
 check(game.design==expected and game.undo_history.size()==1,"disconnection uses ordinary one-edit undo without other craft changes")
 check(visible_labels().count("货舱未接电芯")==1 and game.hud._workshop_warning_text()=="货舱未接电芯","workshop shows exactly one short cargo-power warning")
 check(label_text("ModuleStartupStatus")=="未连到货舱","selected battery explains its actual missing cargo connection")
 check(game.hud.state.power_status.unpowered_cargo_ids==[cargo_id] and game.hud.state.power_status.disconnected_battery_ids==[battery_id],"Main passes exact disconnected identities to HUD")
 check(game.world.grid.unpowered_cells==[Vector2(part_cell(cargo_id))] and game.world.grid.disconnected_battery_cells==[Vector2(-3,0)],"actual Grid marks only the unpowered cargo and detached battery")
 for extent in [Vector2i(1280,720),Vector2i(1280,812),Vector2i(1366,768),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
  for palette in [false,true]:await layout_case(extent,palette)
 var before:PackedByteArray=model_bytes()
 for id in [cargo_id,battery_id,cargo_id,battery_id]:game.selected_id=id;game.refresh_workshop_selection();game.render();await settle(1)
 check(model_bytes()==before,"selection and redraw never change assembly, undo, economy or either save slot")
 game._action("assembly_mode","launcher");await settle()
 check(not game.hud.state.has("power_status") and not visible_labels().has("货舱未接电芯") and game.world.grid.unpowered_cells.is_empty() and game.world.grid.disconnected_battery_cells.is_empty(),"launcher context does not reuse craft warnings or overlay marks")
 game._action("assembly_mode","craft");game.selected_id=battery_id;game.render();await settle()
 check(label_text("ModuleStartupStatus")=="未连到货舱" and visible_labels().count("货舱未接电芯")==1,"returning to craft restores only its actual warning")
 var saves_before_undo:int=game.save_calls
 var economy_before_undo:PackedByteArray=var_to_bytes([game.economy.credits,game.economy.inventory,game.economy.contracts])
 action_button("undo").pressed.emit();await settle()
 check(game.design==original and game.undo_history.is_empty() and game.save_calls==saves_before_undo+1,"real Undo button routes through Main action and restores the pre-disconnection design in one save")
 check(named("WorkshopPowerOrBoundsWarning")==null and label_text("ModuleStartupStatus")!="未连到货舱" and game.world.grid.unpowered_cells.is_empty() and game.world.grid.disconnected_battery_cells.is_empty(),"production undo immediately clears HUD status and all disconnected Grid marks")
 check(persisted().design==JSON.parse_string(JSON.stringify(original)) and var_to_bytes([game.economy.credits,game.economy.inventory,game.economy.contracts])==economy_before_undo,"undo persists the exact restored craft without changing economy or contract")
 move_battery(Vector2i(-1,0),Vector2i(-3,0));await settle()
 check(part_cell(battery_id)==Vector2i(-3,0) and visible_labels().count("货舱未接电芯")==1 and game.world.grid.disconnected_battery_cells==[Vector2(-3,0)],"a fresh ordinary edit after undo restores the correct disconnection feedback")
 move_battery(Vector2i(-3,0),Vector2i(-1,0));await settle()
 check(game.design==original and game.hud.state.power_status.unpowered_cargo_ids.is_empty() and game.hud.state.power_status.disconnected_battery_ids.is_empty(),"ordinary reconnection immediately restores the original powered topology")
 check(named("WorkshopPowerOrBoundsWarning")==null and label_text("ModuleStartupStatus")!="未连到货舱" and game.world.grid.unpowered_cells.is_empty() and game.world.grid.disconnected_battery_cells.is_empty(),"reconnection clears warning, selected status and every power overlay")
 move_battery(Vector2i(-1,0),Vector2i(-3,0));game.hud.palette_open=false;game.render()
 var cash:int=game.economy.credits;var stock:Dictionary=game.economy.inventory.duplicate(true)
 var trial_button:=action_button("trial")
 trial_button.pressed.emit()
 if not check(game.page=="flight" and game.trial and game.sim.route.control_version==Profile.VERSION,"real free-trial button permits launching the disconnected craft"):return
 if not terminal_step():return
 var live_before:PackedByteArray=physical_bytes()
 game._process(0.0)
 check(physical_bytes()==live_before,"terminal HUD refresh does not mutate physics")
 check(game.hud.flight_labels.energy_warning.text=="货舱未接电芯","terminal flight energy warning distinguishes a disconnected battery")
 print("POWER_FEEDBACK_LIVE_RECEIPT mode=single_disconnected text=",game.hud.flight_labels.events.text)
 check(game.hud.flight_labels.events.text==DISCONNECTED,"live disconnected terminal receipt does not contradict the power warning")
 check_report("battery_disconnected",DISCONNECTED,true)
 check(game.economy.credits==cash and game.economy.inventory==stock,"disconnected free trial changes neither funds nor stock")
 var disconnected_report:Dictionary=game.report.duplicate(true)
 workshop();move_battery(Vector2i(-3,0),Vector2i(-1,0));game.start_flight(true)
 if not check(game.page=="flight" and game.sim.parts[battery_id].alive,"connected comparison starts the same real trial path"):return
 game.sim.parts[battery_id].energy=0.0
 if not terminal_step():return
 game._process(0.0)
 check(game.hud.flight_labels.energy_warning.text=="电量耗尽" and game.hud.flight_labels.events.text==DEPLETED,"genuine zero-energy connected battery keeps its original depletion warning and terminal receipt")
 check_report("energy_depleted",DEPLETED,true)
 check(game.economy.last_trials[contract_id].previous.cause==DISCONNECTED,"next trial preserves the earlier precise disconnected result")
 var old_record:Dictionary=disconnected_report.duplicate(true);old_record.erase("free_failure");old_record.erase("power_failure");old_record.control_version=Legacy.VERSION;old_record.cause=DEPLETED
 var old_before:PackedByteArray=var_to_bytes(old_record)
 check(game.hud._report_failure_copy(old_record)==DEPLETED and var_to_bytes(old_record)==old_before,"old v1 report without new evidence is read unchanged and keeps its historical interpretation")
 workshop();move_battery(Vector2i(-1,0),Vector2i(-3,0));game.start_flight(false)
 if not check(game.page=="flight" and not game.trial and not game.economy.in_flight.is_empty(),"formal dispatch remains allowed for freely assembled disconnected craft"):return
 if not terminal_step():return
 check_report("battery_disconnected",DISCONNECTED,false)
 check(game.economy.jobs_today==1 and game.economy.in_flight.is_empty(),"real formal settlement consumes exactly one order and clears the active flight")
 var legacy_e=Economy.new();legacy_e.enable_free_mode();legacy_e.starter_stock(Legacy.starter_design(),Legacy.starter_launcher());legacy_e.enable_story_mode()
 var legacy_id:String=str(legacy_e.contracts[0].contract_id)
 check(legacy_e.accept_contract(legacy_id).ok,"legacy regression uses an authored frozen v1 contract")
 legacy_e.mark_story_seen(legacy_id,legacy_id+"/accept");legacy_e.mark_cargo_loaded(legacy_id)
 game.economy=legacy_e;game.design=Legacy.starter_design();game.launcher=Legacy.starter_launcher()
 for part in game.design:
  if part.type=="battery":part.x=-3
 game.page="workshop";game._configure_flight(true,game.design,game.launcher,legacy_e.trial_route())
 if not check(game.page=="flight" and game.sim.route.control_version==Legacy.VERSION,"Main retains the frozen v1 simulator for a legacy order"):return
 if not terminal_step():return
 game.finish_flight()
 check(game.report.cause==DEPLETED and not game.report.has("power_failure") and not game.report.has("free_failure") and game.hud._report_failure_copy(game.report)==DEPLETED,"real v1 finish_flight is not relabeled by v2 presentation evidence")
 check(persisted().last_trials[legacy_id].latest.cause==DEPLETED and not persisted().last_trials[legacy_id].latest.has("power_failure"),"legacy durable trial record preserves the original diagnosis")
 multi_cargo_hud_cases()
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/courier-dev10-power-ui-"):
  printerr("Use a new isolated /tmp/courier-dev10-power-ui-* XDG_DATA_HOME");quit(2);return
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):printerr("Refusing existing profile: "+name);quit(2);return
 root.gui_embed_subwindows=true
 await exercise()
 if is_instance_valid(game):game.queue_free();await settle(6)
 if passed+failed!=154:check(false,"all 154 power-feedback regression assertions completed")
 print("POWER_FEEDBACK_UI_DEV10 passed=%d failed=%d real_main_world_hud=true real_finish_and_persistence=true native_input=NOT_RUN native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)
