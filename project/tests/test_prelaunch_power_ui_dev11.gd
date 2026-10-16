extends SceneTree
## Real Main/World/HUD regression using a fresh isolated profile. Ordinary edits,
## start_flight, presentation frames, simulation termination and finish_flight
## use production paths. Multi-cargo uses _configure_flight because commercial
## start_flight deliberately permits exactly one customer's cargo.
## No native mouse, screen-rendering or physical-controller acceptance is claimed.
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Legacy=preload("res://scripts/pilot_free_profile_v1.gd")
const Economy=preload("res://scripts/economy.gd")
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
var original:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func settle(count:int=4) -> void:
 for unused in count:await process_frame
func persisted() -> Dictionary:
 var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 return data if data is Dictionary else {}
func physical_bytes() -> PackedByteArray:
 return var_to_bytes([game.sim.parts,game.sim.bodies,game.sim.links,game.sim.obstacles,game.sim.launcher_parts,game.sim.effects,game.sim.incidents,game.sim.events,game.sim.telemetry,game.sim.route,game.sim.status,game.sim.elapsed,game.sim._rng.state,game.sim._accumulator,game.sim._graph_dirty,game.pilot_timeline.snapshot(),game.pilot_timeline._cursor,game.pilot_timeline._cursor_tick,game.pilot_timeline.error,game.pilot_completed_ticks])
func model_bytes() -> PackedByteArray:
 return var_to_bytes([game.design,game.launcher,game.undo_history,game.next_id,game.economy.inventory,game.economy.credits,game.economy.contracts,game.economy.settled_ids,game.economy.in_flight,game.economy.last_trials,game.economy.story_state,game.save_calls,FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")])
func visible_labels() -> Array:
 var labels:Array=[]
 for node in game.hud.content.find_children("*","Label",true,false):
  if node.is_visible_in_tree():labels.append(node.text)
 return labels
func workshop() -> void:
 game.workshop_input.cancel();game.page="workshop";game.assembly_mode="craft";game.selected_id=battery_id
 game.hud.palette_open=false;game.render();game.workshop_input.fit()
func move_battery(from:Vector2i,to:Vector2i) -> void:
 game.workshop_input._commit({"kind":"move","id":battery_id,"from":from,"cell":to})
func preparation(code:String,warning:String,label:String,positive_energy:bool=false) -> void:
 check(game.page=="flight" and game.sim.status=="running" and game.sim.elapsed==0.0,label+" begins on the real flight page before simulation")
 check(game.launch_transfer_remaining>0.0 and game.launch_age==0.0,label+" begins with real positive transfer duration")
 for phase in ["move","charge"]:
  if phase=="charge":
   var transition_before:PackedByteArray=physical_bytes()
   game._process(game.launch_transfer_remaining+0.1)
   check(game.launch_transfer_remaining==0.0 and game.launch_age>0.0 and game.launch_age<0.7,label+" advances through real transfer into charge")
   check(physical_bytes()==transition_before,label+" actual transfer-to-charge frame runs zero simulation and changes no telemetry or timeline")
  var before:PackedByteArray=physical_bytes()
  var before_model:PackedByteArray=model_bytes()
  for unused in 3:game._process(0.0)
  var data:Dictionary=game.hud.state.get("flight",{})
  var status:Dictionary=data.get("power_status",{})
  check(game.sim.status=="running" and game.sim.elapsed==0.0 and game.pilot_completed_ticks==0,label+" "+phase+" remains running with zero completed physics ticks")
  check(physical_bytes()==before,label+" "+phase+" repeated refresh preserves physics, telemetry, RNG and timeline byte-for-byte")
  check(model_bytes()==before_model,label+" "+phase+" refresh preserves design, undo, economy and both save slots")
  check(str(data.get("phase",""))==("移送到地面发射位" if phase=="move" else "发射台蓄能中") and bool(data.get("charging",false)),label+" "+phase+" carries the actual preparation phase")
  check(game.hud.flight_labels.status.text=="准备起飞",label+" "+phase+" still presents preparation rather than terminal failure")
  check(status.get("code","")==code and bool(status.get("ready",false))==(code=="ready"),label+" "+phase+" Main projects the precise read-only power status")
  check(not data.has("power_failure") and not data.has("free_failure") and not game.sim.telemetry.has("power_status"),label+" "+phase+" never invents a failure or writes presentation evidence into telemetry")
  check(game.hud.flight_labels.energy_warning.text==warning,label+" "+phase+" real energy warning label is exact")
  check(game.hud.flight_labels.events.text.is_empty(),label+" "+phase+" never fabricates a terminal event receipt")
  check(is_equal_approx(float(game.hud._energy_bar.value),float(game.sim.telemetry.energy_fraction)*100.0),label+" "+phase+" energy bar retains actual telemetry")
  if positive_energy:
   check(float(game.sim.telemetry.energy_remaining)>0.0 and game.hud._energy_bar.value>0.0,label+" "+phase+" preserves genuinely positive aggregate energy")
  else:
   check(game.hud.flight_labels.energy.text=="电量 0%" and game.hud._energy_bar.value==0.0,label+" "+phase+" keeps truthful zero usable-energy reading")
  print("PRELAUNCH_POWER_WITNESS case=",label," phase=",phase," elapsed=",game.sim.elapsed," transfer=",game.launch_transfer_remaining," age=",game.launch_age," energy=",game.hud._energy_bar.value," warning=",game.hud.flight_labels.energy_warning.text," events=",game.hud.flight_labels.events.text)
func terminal(code:String,warning:String,copy:String,is_trial:bool) -> void:
 var cash:int=game.economy.credits;var stock:Dictionary=game.economy.inventory.duplicate(true)
 game._step_flight()
 check(game.sim.status=="failed" and game.sim.telemetry.get("free_failure","")=="usable_energy_empty",code+" still terminates only on the actual simulator step")
 check(is_equal_approx(game.sim.elapsed,1.0/120.0) and game.pilot_completed_ticks==1,code+" retains exact first-substep 0.008333-second failure chronology")
 var before:PackedByteArray=physical_bytes()
 game._process(0.0)
 var data:Dictionary=game.hud.state.get("flight",{})
 check(physical_bytes()==before,code+" terminal presentation does not mutate the completed simulation")
 check(data.get("power_failure",{}).get("code","")==code and not data.has("power_status"),code+" terminal frame uses existing failure evidence without stale preparation status")
 check(game.hud.flight_labels.energy_warning.text==warning and game.hud.flight_labels.events.text==copy,code+" actual terminal HUD preserves the dev10 warning and receipt")
 var competing:Dictionary=data.duplicate(true)
 competing.power_status={"code":"no_battery" if code!="no_battery" else "battery_disconnected","ready":false}
 game.hud.update_flight(competing)
 check(game.hud.flight_labels.energy_warning.text==warning and game.hud.flight_labels.events.text==copy,code+" genuine terminal evidence outranks a conflicting preparation status")
 game.finish_flight()
 check(game.page=="report" and not game.report.success and game.report.trial==is_trial,code+" real finish_flight publishes the correct report type")
 check(game.report.cause==copy and game.report.get("power_failure",{}).get("code","")==code and game.report.get("free_failure","")=="usable_energy_empty",code+" report retains precise diagnosis and original terminal protocol")
 check(is_equal_approx(float(game.report.elapsed),1.0/120.0) and copy in visible_labels(),code+" actual report keeps the exact terminal time and visible diagnosis")
 if is_trial:check(game.economy.credits==cash and game.economy.inventory==stock,code+" free trial leaves funds and stock unchanged")
 else:check(game.economy.credits==cash+int(game.report.get("profit",0)) and game.economy.inventory==stock,code+" formal dispatch keeps real reported settlement cost and unchanged stock")
 if is_trial:
  var saved:Dictionary=persisted().get("last_trials",{}).get(contract_id,{}).get("latest",{})
  check(saved.get("cause","")==copy and saved.get("power_failure",{}).get("code","")==code,code+" durable trial record retains precise terminal evidence")
  var reopened=Economy.new();var loaded:Dictionary=reopened.load_state()
  check(not loaded.is_empty() and not reopened.review_load_blocked and reopened.last_trials.get(contract_id,{}).get("latest",{}).get("cause","")==copy,code+" real Economy reload reads the completed trial unchanged")
func launch_trial() -> bool:
 game.start_flight(true)
 return check(game.page=="flight" and game.trial and game.sim.route.control_version==Profile.VERSION,"real start_flight permits this freely assembled v2 trial")
func multi_cargo_case() -> void:
 var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var craft:Array=[Extreme.part(1,"cargo",0),Extreme.part(2,"battery",1),Extreme.part(10,"cargo",10),Extreme.part(12,"battery",15)]
 game.page="workshop";game._configure_flight(true,craft,[],route)
 if not check(game.page=="flight" and game.sim.parts.size()==4,"real Main multi-cargo presentation fixture configures both cargo circuits"):return
 preparation("battery_disconnected","货舱未接电芯","multi-cargo disconnected",true)
 var status:Dictionary=game.hud.state.flight.get("power_status",{})
 check(status.get("empty_cargo_ids",[])==[10] and status.get("disconnected_battery_ids",[])==[12],"multi-cargo warning preserves exact unpowered cargo and detached battery identities")
 check(game.hud.flight_labels.energy.text=="电量 100%" and game.hud.flight_labels.energy_warning.text=="货舱未接电芯","positive aggregate 100 percent never hides a different cargo's missing circuit")
func legacy_case() -> void:
 if game._dialogue_is_open():game.dialogue.skip_conversation()
 var economy=Economy.new();economy.enable_free_mode();economy.starter_stock(Legacy.starter_design(),Legacy.starter_launcher());economy.enable_story_mode()
 var id:String=str(economy.contracts[0].contract_id)
 check(economy.accept_contract(id).ok,"legacy fixture accepts an authored frozen v1 order")
 economy.mark_story_seen(id,id+"/accept");check(economy.mark_cargo_loaded(id).ok,"legacy fixture loads its real order")
 game.economy=economy;game.design=Legacy.starter_design();game.launcher=Legacy.starter_launcher()
 # A genuinely preserved v1 save owns its frozen retired parts. Fresh v2 stock
 # deliberately does not grant them, so install only the legacy fixture stock.
 for kind in economy.missing_parts(game.design,game.launcher):
  economy.inventory[kind]=int(economy.inventory.get(kind,0))+int(economy.missing_parts(game.design,game.launcher).get(kind,0))
 for part in game.design:
  if part.type=="battery":part.x=-3
 workshop();game.start_flight(true)
 if not check(game.page=="flight" and game.sim.route.control_version==Legacy.VERSION,"legacy start_flight still chooses the frozen v1 simulator"):return
 var before:PackedByteArray=physical_bytes();game._process(0.0)
 var data:Dictionary=game.hud.state.flight.duplicate(true)
 check(not data.has("power_status") and not data.has("power_failure") and physical_bytes()==before,"legacy Main emits no v2 power evidence and preparation remains read-only")
 var legacy_warning:String=game.hud.flight_labels.energy_warning.text
 check(legacy_warning=="电量耗尽","legacy zero-energy preparation keeps its historical depletion label")
 data.power_status={"code":"battery_disconnected","ready":false}
 game.hud.update_flight(data)
 check(game.hud.flight_labels.energy_warning.text==legacy_warning and game.hud.flight_labels.events.text.is_empty(),"v1 HUD ignores stray v2 preparation status and does not fabricate a terminal receipt")
 game._step_flight();game.finish_flight()
 check(game.page=="report" and game.report.cause==DEPLETED and not game.report.has("power_failure") and not game.report.has("free_failure"),"legacy real terminal report remains entirely unchanged by v2 presentation diagnosis")
func exercise() -> void:
 game=load("res://scenes/main.tscn").instantiate();game.set_script(QuietMain)
 # Reduced motion deliberately stays false: true skips the physical transfer
 # presentation and would make an alleged move-phase test vacuous.
 game.entry_settings_overrides={"volume":0.0,"dialogue_volume":0.0,"reduced_motion":false,"fullscreen":false}
 root.add_child(game);game.set_process(false);await settle(6)
 game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 game._on_focus_entered();game.courier_input.synchronize()
 if not check(not game.economy.review_load_blocked and game.design==Profile.starter_design() and game.launcher==Profile.starter_launcher(),"fresh real Main starts from the exact v2 craft and launcher"):return
 original=game.design.duplicate(true)
 for part in game.design:
  if part.type=="battery":battery_id=int(part.id)
  if part.type=="cargo":cargo_id=int(part.id)
 if not check(battery_id>=0 and cargo_id>=0,"fresh starter provides real battery and cargo identities"):return
 contract_id=str(game.economy.contracts[0].contract_id)
 check(game.economy.accept_contract(contract_id).ok,"fixture accepts the real first free-v2 order")
 game.economy.mark_story_seen(contract_id,contract_id+"/accept")
 check(game.economy.mark_cargo_loaded(contract_id).ok,"fixture loads the real order")
 workshop();move_battery(Vector2i(-1,0),Vector2i(-3,0))
 if not launch_trial():return
 preparation("battery_disconnected","货舱未接电芯","disconnected trial")
 terminal("battery_disconnected","货舱未接电芯",DISCONNECTED,true)
 workshop();move_battery(Vector2i(-3,0),Vector2i(-1,0))
 check(game.design==original,"ordinary workshop reconnection restores the exact original craft")
 if not launch_trial():return
 preparation("ready","","reconnected trial",true)
 check(game.hud.flight_labels.energy.text=="电量 100%" and game.hud.flight_labels.energy_warning.text.is_empty() and game.hud.flight_labels.events.text.is_empty(),"reconnected normal 100-percent flight has no stale warning or failure receipt")
 game.abort_flight()
 check(game.page=="report" and not game.report.has("power_failure"),"normal trial abort is not mislabeled as a power failure")
 workshop();game.design=original.filter(func(part):return str(part.type)!="battery").duplicate(true);game.render()
 if not launch_trial():return
 preparation("no_battery","货舱缺电芯","missing battery trial")
 terminal("no_battery","货舱缺电芯","货舱没有电芯。回工位装上再试。",true)
 workshop();game.design=original.duplicate(true);game.render()
 if not launch_trial():return
 # Preparing the explicit depletion fixture is separate from observation. No
 # presentation callback may consume energy or refresh simulator telemetry.
 game.sim.parts[battery_id].energy=0.0;game.sim._refresh_telemetry()
 preparation("energy_depleted","电量耗尽","genuinely depleted trial")
 terminal("energy_depleted","电量耗尽",DEPLETED,true)
 workshop();move_battery(Vector2i(-1,0),Vector2i(-3,0));game.start_flight(false)
 if not check(game.page=="flight" and not game.trial and not game.economy.in_flight.is_empty(),"real formal free dispatch remains permitted for disconnected craft"):return
 preparation("battery_disconnected","货舱未接电芯","disconnected formal")
 terminal("battery_disconnected","货舱未接电芯",DISCONNECTED,false)
 check(game.economy.jobs_today==1 and game.economy.in_flight.is_empty(),"formal terminal settlement consumes exactly one order and clears in-flight state")
 multi_cargo_case()
 legacy_case()
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/courier-dev11-prelaunch-ui-"):
  printerr("Use a new isolated /tmp/courier-dev11-prelaunch-ui-* XDG_DATA_HOME");quit(2);return
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):printerr("Refusing existing profile: "+name);quit(2);return
 root.gui_embed_subwindows=true
 await exercise()
 if is_instance_valid(game):game.queue_free();await settle(6)
 if passed+failed!=225:check(false,"all 225 prelaunch power UI regression assertions completed")
 print("PRELAUNCH_POWER_UI_DEV11 passed=%d failed=%d real_main_world_hud=true zero_step_preparation=true real_finish_and_persistence=true native_input=NOT_RUN native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)
