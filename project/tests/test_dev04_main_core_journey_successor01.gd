extends SceneTree
## Source successor to preserved run01 (47/2); only evidence-based harness fixes.
## Actual default Title/Main/World/Economy; isolated fictional profile.
## Automated API/button/analog/key events and explicit clocks, NOT native input.
## No trip-state, position, velocity, health, energy, inventory or credit writes.
## No migration, observer injection, audio-output, Windows or novice claims.
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
const TitleScene=preload("res://scenes/demo_title.tscn")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const FreeSim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Ground=preload("res://scripts/pilot_free_ground_route_v1.gd")
const STOCK={"cargo":1,"beam":5,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1}
const SOURCES=["project.godot","scenes/demo_title.tscn","scenes/main.tscn","scripts/demo_title.gd","tests/audio_clock_test_support.gd","scripts/main.gd","scripts/economy.gd","scripts/game_hud.gd","scripts/world_view_2d.gd","scripts/pilot_free_profile_v2.gd","scripts/pilot_free_simulation_v2.gd","scripts/pilot_free_input_v2.gd","scripts/pilot_free_timeline_v2.gd","scripts/pilot_free_ground_route_v1.gd","scripts/launcher_v2.gd"]
const LEDGER=["credits","day","phase","jobs_today","deliveries","inventory","history","settled_ids","last_settlement","review_state","story_state"]
const DT:float=1.0/60.0
const FLIGHT_BUDGET:int=7200
var title
var game
var passed:int=0
var failed:int=0
var waypoint:int=0
var held_keys:Dictionary={}
var wait_sequence:int=0

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func frames(count:int=2) -> void:
 for unused in count:await process_frame
func disk() -> Array:
 var result:Array=[]
 for name in ["savegame.json","savegame.backup.json"]:
  result.append(FileAccess.get_file_as_bytes("user://"+name) if FileAccess.file_exists("user://"+name) else PackedByteArray())
 return result
func saved() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func ledger() -> Dictionary:
 var full:Dictionary=saved();var result:Dictionary={}
 for key in LEDGER:result[key]=full.get(key)
 return result
func button(node:Node,key:String,value:Variant) -> Button:
 for item in node.find_children("*","Button",true,false):
  if item.has_meta(key) and item.get_meta(key)==value:return item
 return null
func click(control:Button,label:String) -> bool:
 if not check(is_instance_valid(control) and control.is_visible_in_tree() and not control.disabled,label):return false
 control.pressed.emit();return true
func close_title() -> void:
 game=null;held_keys.clear()
 var releases:Array=[]
 if is_instance_valid(title):
  # Test teardown only: stop real audio owners before destroying the scene.
  # Weak playback release is a cleanup condition, not an audible-output claim.
  for player in title.find_children("*","AudioStreamPlayer",true,false):
   AudioClock.watch_player(player,releases);player.stop();player.stream=null
  root.remove_child(title);title.free()
 title=null;await frames(3)
 if not releases.is_empty():
  var released:Dictionary=await AudioClock.wait_released(self,releases)
  print("DEV04_CORE_AUDIO_RELEASE ",JSON.stringify(released))
  check(released.ok,"test teardown releases audio players and playback owners")
func open_title() -> bool:
 title=TitleScene.instantiate();root.add_child(title);await frames(3)
 title._focus_entered()
 return check(title._preview_ready and title.game==null,"default title preview is ready without constructing Main")
func wait_game() -> bool:
 wait_sequence+=1
 var started:int=Time.get_ticks_msec();var deadline:int=started+15000
 var waited_frames:int=0;var samples:Array=[title_diagnostic("entry",started,waited_frames)]
 var previous:String="";var reason:String="deadline"
 while title.screen!="game" and Time.get_ticks_msec()<deadline:
  # run01 mistook the cancelled OLD opening's sticky failure flag for failure
  # of a NEW queued Continue. _start_opening clears it after deferred launch.
  # Only the currently active opening can fail this new attempt.
  if title.screen=="opening" and title._opening_failed:reason="current_opening_failed";break
  if title.screen=="menu" and not title.busy and waited_frames>0:reason="returned_to_idle_menu";break
  var state:Dictionary=title_diagnostic("transition",started,waited_frames)
  var signature:String=JSON.stringify([state.screen,state.busy,state.window_focused,state.opening_done,state.opening_failed,state.get("restore_pending"),state.get("restore_error"),state.get("completed_ticks")])
  if signature!=previous and samples.size()<16:samples.append(state);previous=signature
  await process_frame;waited_frames+=1
 if title.screen=="game":reason="game"
 samples.append(title_diagnostic("exit",started,waited_frames))
 print("DEV04_CORE_TITLE_WAIT ",JSON.stringify({"sequence":wait_sequence,"bound_ms":15000,"reason":reason,"samples":samples},"",true,true))
 if not check(title.screen=="game" and is_instance_valid(title.game),"actual title releases validated Main"):return false
 game=title.game;game.set_process(false);game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 game._on_focus_entered();game.courier_input.synchronize()
 if is_instance_valid(root.gui_get_focus_owner()):root.gui_get_focus_owner().release_focus()
 return check(not game.economy.review_load_blocked and not game.entry_defer_controls,"actual Main has committed safe entry")
func title_diagnostic(stage:String,started:int,waited_frames:int) -> Dictionary:
 var state:Dictionary={"stage":stage,"elapsed_ms":Time.get_ticks_msec()-started,"waited_frames":waited_frames,"engine_process_frames":Engine.get_process_frames(),"screen":title.screen,"busy":title.busy,"title_processing":title.is_processing(),"window_focused":title._window_focused,"native_window_focused":root.has_focus(),"opening_age":title._opening_age,"opening_done":title._opening_done,"opening_failed":title._opening_failed,"retiring_restore":title._retiring_restore,"launch_waiting_for_focus":title._launch_waiting_for_focus,"input_any_pressed":Input.is_anything_pressed(),"music_generation":title._music_generation,"music_index":title._music_index,"has_candidate":is_instance_valid(title.game)}
 if is_instance_valid(title._prologue_music):state.music={"playing":title._prologue_music.playing,"paused":title._prologue_music.stream_paused}
 if title._music_tween!=null:state.music_tween={"valid":title._music_tween.is_valid(),"running":title._music_tween.is_running()}
 if is_instance_valid(title.game):
  var candidate=title.game
  state.merge({"candidate_id":candidate.get_instance_id(),"main_page":candidate.page,"main_processing":candidate.is_processing(),"main_process_mode":candidate.process_mode,"entry_defer_controls":candidate.entry_defer_controls,"restore_pending":candidate.title_restore_pending(),"restore_progress":candidate.title_restore_progress(),"restore_error":candidate.title_restore_failure(),"resume_blocked":candidate.pilot_resume_blocked,"completed_ticks":candidate.pilot_completed_ticks,"saved_ticks":candidate.economy.in_flight.get("ticks",-1),"load_blocked":candidate.economy.review_load_blocked,"load_notice":candidate.economy.load_notice})
 return state
func shop_step() -> void:
 # Advance real actor/loading transitions; never set actor position or arrival.
 if game.world._parcel_tween!=null:
  game.world._parcel_tween.pause();game.world._parcel_tween.custom_step(DT)
 game.world._process(DT);game.world.assembly_feedback._process(DT);game._process(DT)
func pump(predicate:Callable,label:String,budget:int=2400) -> bool:
 for tick in budget:
  if predicate.call():return check(true,label)
  shop_step()
  if tick%60==0:await frames(1)
 return check(bool(predicate.call()),label)
func finish_launch() -> bool:
 # Main advances the real transfer/countdown. Shop actors stay frozen during
 # flight, including their legitimate residual return, to expose receipt waits.
 for tick in 1200:
  if game.launch_countdown<=0.0:return check(true,"actual launch transfer/countdown finishes")
  game._process(DT)
  if tick%60==0:await frames(1)
 return check(false,"actual launch transfer/countdown finishes")
func steer(value:Vector2) -> void:
 # Invert the real controller deadzone to request a normalized analog command.
 # The host records the quantized output; this is an automated test driver.
 var dz:float=game.courier_input.deadzone
 for axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
  var amount:float=value.x if axis==JOY_AXIS_LEFT_X else value.y
  var event:=InputEventJoypadMotion.new();event.device=0;event.axis=axis
  event.axis_value=0.0 if is_zero_approx(amount) else signf(amount)*(dz+absf(amount)*(1.0-dz))
  game.courier_input._input(event)
func key(code:int,down:bool) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
 game._input(event)
 if down:game._unhandled_key_input(event);held_keys[code]=true
 else:held_keys.erase(code)
func release() -> void:
 steer(Vector2.ZERO)
 for code in held_keys.keys():key(int(code),false)
func ticks(count:int) -> void:
 for unused in count:
  if game.sim.status!="running":return
  game._step_flight()
func velocity() -> Vector2:return game.sim.body_for_part(1).velocity
func drive() -> void:
 # Read-only waypoint feedback produces paid force inputs, never a speed write.
 # Keep a generous physical clearance above the one untouched default rock.
 var targets:Array=[Vector2(75,-20),Vector2(170,-20),Ground.DESTINATION]
 var at:Vector2=game.sim.cargo_position()
 if waypoint<2 and (at.distance_to(targets[waypoint])<7.0 or at.x>targets[waypoint].x):waypoint+=1
 var delta:Vector2=targets[waypoint]-at
 var desired:Vector2=delta.normalized()*minf(12.0,delta.length()*0.65)
 steer(((desired-velocity())*0.22).limit_length(1.0));ticks(1)
func physical() -> Dictionary:
 return {"status":game.sim.status,"elapsed":game.sim.elapsed,"bodies":game.sim.bodies.duplicate(true),"parts":game.sim.parts.duplicate(true),"links":game.sim.links.duplicate(true),"obstacles":game.sim.obstacles.duplicate(true),"telemetry":game.sim.telemetry.duplicate(true),"events":game.sim.events.duplicate(true),"rng":game.sim._rng.state,"aim":[game.sim.pilot_aim_x_q,game.sim.pilot_aim_y_q],"device_id":game.sim.pilot_device_id,"brake":game.sim.pilot_brake,"active_edge":game.sim._active_edge_device_id}
func timeline_valid(commands:Array) -> bool:
 var fields:Array=["tick","axis_x_q","axis_q","boost","active","device_id","brake"]
 for command in commands:
  if not command is Dictionary or command.size()!=7:return false
  for field in fields:
   if not command.has(field):return false
  for field in ["tick","axis_x_q","axis_q","device_id"]:
   var n:Variant=command[field]
   if not (n is int or n is float) or not is_finite(float(n)) or float(n)!=floor(float(n)) or absf(float(n))>2147483647.0:return false
  for field in ["boost","active","brake"]:
   if not command[field] is bool:return false
 return not commands.is_empty()

func exercise() -> void:
 if not await open_title():return
 check(disk()==[PackedByteArray(),PackedByteArray()],"fresh title preview is save-slot read-only")
 if not click(title.new_button,"real New Game button is enabled"):return
 await frames()
 if not check(title.screen=="prologue" and title.game==null,"New Game opens real prologue first"):return
 if not click(title.menu.find_child("PrologueSkip",true,false),"real prologue skip callback is available"):return
 if not await wait_game():return
 check(game.design==Profile.starter_design() and game.launcher==Profile.starter_launcher(),"fresh Main uses exact new default craft and paid launcher")
 check(game.economy.inventory==STOCK and game.economy.missing_parts(game.design,game.launcher).is_empty(),"new default stock covers unchanged default assembly, with no grants")
 if not check(game.economy.flight_mode==Profile.VERSION and game.economy.contracts.size()==2,"fresh Main creates two force-control offers"):return
 var cid:String=str(game.economy.contracts[0].contract_id)
 var order:Dictionary=game.economy.contract_by_id(cid).duplicate(true)
 if not check(order.control_version==Profile.VERSION and order.input_schema==Profile.INPUT_SCHEMA and order.free_ground_schema==Ground.SCHEMA and Profile.validation_error(order).is_empty(),"default ground order has explicit v2 control and immutable ground identity"):return
 for offer in game.economy.contracts:check(offer.control_version==Profile.VERSION and Profile.validation_error(offer).is_empty(),"new offer validates independently: "+str(offer.contract_id))
 var opening_credits:int=game.economy.credits
 game._action("focus_counter",null)
 if not await pump(func():return game.world.has_counter_customer(cid) and game.world.is_at_shop_counter(),"customer and clerk actually arrive before acceptance"):return
 game._action("focus_counter",null)
 if not click(button(game.hud.content,"shop_contract_id",cid),"actual arrived-customer Accept callback is enabled"):return
 if not check(game.economy.active_contract_id==cid and not game.economy.is_cargo_loaded(),"acceptance persists same unloaded order before dispatch"):return
 if not await pump(func():return game._dialogue_is_open(),"actual acceptance dialogue opens"):return
 check(str(game._active_story.get("dialogue_id",""))==cid+"/accept","matching accepted order owns dialogue")
 game.dialogue.skip_conversation()
 if not await pump(func():return game.economy.is_cargo_loaded() and game.world.is_parcel_loaded(cid),"real loading callback commits matching cargo"):return
 check(bool(saved().contracts[0].cargo_loaded) and saved().active_contract_id==cid,"actual loaded order is durable")
 game._action("focus_workbench",null)
 if not click(button(game.hud.content,"view_key","action:dispatch:null"),"actual workshop Dispatch callback opens confirmation"):return
 var loaded_bytes:Array=disk()
 if not click(button(game.hud.content,"view_key","dispatch:cancel"),"actual dispatch Cancel callback is available"):return
 check(disk()==loaded_bytes and game.economy.in_flight.is_empty(),"dispatch cancel keeps both raw slots byte-exact")
 if not click(button(game.hud.content,"view_key","action:dispatch:null"),"Dispatch callback reopens confirmation"):return
 if not click(button(game.hud.content,"view_key","dispatch:confirm"),"actual dispatch Confirm callback launches"):return
 if not check(game.page=="flight" and game.sim is FreeSim and not game.trial,"formal actual Main launch uses force-v2 simulator"):return
 var route:Dictionary=game.sim.route.duplicate(true)
 var launch_credits:int=game.economy.credits
 var pad_speed:float=velocity().length()
 check(pad_speed>0.5 and game.sim.telemetry.launch_energy_drawn>0.0 and game.sim.telemetry.launch_policy=="anchored-launch-v2","default pad imparts genuine paid outgoing velocity")
 check(game.sim.telemetry.control_version==Profile.VERSION and game.sim.telemetry.input_schema==Profile.INPUT_SCHEMA and game.sim.telemetry.free_force_policy=="held-thrust-coast-explicit-brake-v2","live telemetry pins the actual v2 force protocol")
 if not await finish_launch():return
 release();var before:Vector2=velocity();var pos:Vector2=game.sim.cargo_position();var energy:float=game.sim.telemetry.energy_used
 ticks(30)
 check(game.sim.cargo_position().distance_to(pos)>0.1 and velocity().length()>before.length()*0.90 and game.sim.telemetry.energy_used==energy and game.sim.telemetry.free_control_mode=="coast","released input coasts without spending propulsion energy")
 before=velocity();steer(Vector2.RIGHT);ticks(60)
 check(velocity().x>before.x+0.5 and game.sim.telemetry.energy_used>energy and game.sim.telemetry.free_control_mode=="thrust","held direction applies paid thrust and gains speed")
 release();before=velocity();energy=game.sim.telemetry.energy_used;key(KEY_CTRL,true);ticks(60)
 check(velocity().length()<before.length() and game.sim.telemetry.energy_used>energy and game.sim.telemetry.free_control_mode=="brake","explicit Ctrl event slows by paid force")
 release()
 while game.pilot_completed_ticks<480 and game.sim.status=="running":drive()
 if not check(game.sim.status=="running" and game.pilot_completed_ticks>=480,"default physical flight reaches bounded mid-trip checkpoint"):return
 release()
 if not click(game.hud._pause_button.get_ref(),"actual flight Pause callback is enabled"):return
 if not check(game.paused and game.save_game(),"paused actual Main saves recorded trip"):return
 var flight_bytes:Array=disk();var checkpoint:Dictionary=saved().in_flight.duplicate(true)
 var expected_physics:Dictionary=physical();var old_instance:int=game.sim.get_instance_id()
 check(checkpoint.input_schema==Profile.INPUT_SCHEMA and checkpoint.control_version==Profile.VERSION and timeline_valid(checkpoint.input_commands),"saved trip has all seven exact timeline keys including device and brake")
 check(checkpoint.input_commands.any(func(c):return bool(c.brake)) and checkpoint.input_commands.any(func(c):return int(c.axis_x_q)!=0),"saved commands contain observed brake and real direction inputs")
 if not click(game.hud.content.get_node_or_null("FlightSaveAndExit"),"actual paused Save and Exit callback opens prompt"):return
 if not click(game._quit_prompt.get_cancel_button(),"actual exit prompt Cancel callback returns to paused flight"):return
 await frames()
 check(game.paused and not game.closing and disk()==flight_bytes,"exit prompt cancel preserves both raw save slots")
 exact(physical(),expected_physics,"pause/exit-cancel physical state")
 await close_title()
 if not await open_title():return
 check(disk()==flight_bytes,"detached restart title preview leaves both raw slots exact")
 if not click(title.continue_button,"real Continue callback begins detached replay"):return
 var deadline:int=Time.get_ticks_msec()+15000
 while not (title.screen=="opening" and is_instance_valid(title.game) and title.game.title_restore_pending()) and title.screen!="game" and Time.get_ticks_msec()<deadline:await process_frame
 if not check(is_instance_valid(title.game) and title.game.title_restore_pending(),"title exposes bounded in-progress actual replay"):return
 if not click(title.title_stage.get_node_or_null("CancelFlightRestore"),"actual pending-replay Cancel callback is available"):return
 await frames(8)
 if not check(title.screen=="menu" and title.game==null and not title.busy and disk()==flight_bytes,"cancelled detached replay publishes no candidate and preserves raw slots"):return
 if not click(title.continue_button,"Continue retries unchanged saved trip"):return
 if not await wait_game():return
 check(game.paused and not game.pilot_resume_blocked and not game.title_restore_pending() and game.sim.get_instance_id()!=old_instance,"new detached simulator replays safely and resumes paused")
 check(disk()==flight_bytes,"successful paused replay is also raw-slot read-only")
 check(game.pilot_completed_ticks==int(checkpoint.ticks) and timeline_valid(game.pilot_timeline.snapshot()),"replay restores exact command tick count and seven-key shape")
 exact(game.pilot_timeline.snapshot(),checkpoint.input_commands,"recorded command JSON boundary")
 exact(physical(),expected_physics,"detached replay complete physical state")
 exact(game.sim.route,route,"detached replay immutable route")
 if not click(game.hud._pause_button.get_ref(),"actual Continue flight callback resumes control"):return
 release()
 for tick in FLIGHT_BUDGET:
  if game.sim.status!="running":break
  drive()
  if tick%120==0:await frames(1)
 release()
 print("DEV04_CORE_PHYSICAL ",JSON.stringify({"status":game.sim.status,"ticks":game.pilot_completed_ticks,"elapsed":game.sim.elapsed,"position":game.sim.cargo_position(),"integrity":game.sim.telemetry.integrity,"energy_used":game.sim.telemetry.energy_used,"energy_remaining":game.sim.telemetry.energy_remaining,"pad_speed":pad_speed,"commands":game.pilot_timeline.commands.size()},"",true,true))
 if not check(game.sim.status=="success","recorded actual Main commands physically reach receiver"):return
 check(game.sim.telemetry.integrity==1.0 and game.sim.telemetry.swept_contacts==0 and game.sim.obstacles[0].health==Ground.ROCK.health,"unchanged default craft detours intact around unchanged rock")
 check(game.sim.telemetry.energy_used>0.0 and game.sim.telemetry.energy_remaining>0.0 and game.economy.history.is_empty() and game.economy.credits==launch_credits,"physical success spends finite energy and cannot fabricate a receipt")
 check(game.world._clerk_return_requested,"real residual clerk return is still pending at physical arrival")
 game.finish_flight()
 if not check(game.page=="report" and game.report.success and game.economy.in_flight.is_empty(),"actual finalize durably settles immediately without a shop return wait"):return
 if not check(game._dialogue_is_open() and str(game._active_story.get("beat",""))=="result" and str(game._active_story.get("counter_contract_id",""))=="" and game.world._clerk_return_requested,"remote result dialogue opens immediately without actor return"):return
 var receipt:Dictionary=game.economy.last_settlement.duplicate(true);var settled:Dictionary=ledger();var paid_bytes:Array=disk()
 exact(receipt,settled.last_settlement,"authored receipt JSON boundary")
 check(int(receipt.profit)>0 and game.economy.credits==launch_credits+int(receipt.profit) and game.economy.credits>opening_credits,"actual default delivery earns durable positive net income")
 check(int(receipt.income)-int(receipt.charged_costs)==int(receipt.profit) and int(receipt.charged_costs)<=30 and float(receipt.energy_j)>0.0,"real receipt reconciles income, paid energy and cost cap")
 game.finish_flight();game.finish_flight()
 check(disk()==paid_bytes and ledger()==settled and game.economy.history.size()==1 and game.economy.settled_ids.size()==1,"repeated actual finalize is byte-exact and cannot settle or pay twice")
 print("DEV04_CORE_RECEIPT ",JSON.stringify({"opening_credits":opening_credits,"receipt":receipt,"final_credits":game.economy.credits},"",true,true))
 await close_title()
 if not await open_title():return
 check(disk()==paid_bytes,"paid receipt title preview leaves both raw slots exact")
 if not click(title.continue_button,"real Continue reopens paid receipt"):return
 if not await wait_game():return
 if not await pump(func():return game._dialogue_is_open(),"saved remote receipt restores its unread result dialogue",60):return
 exact(ledger(),settled,"saved paid Continue ledger")
 exact(game.economy.last_settlement,receipt,"saved paid Continue receipt")
 check(game.economy.jobs_today==1 and game.economy.deliveries==1 and game.economy.history.size()==1 and game.economy.settled_ids.size()==1 and game.economy.in_flight.is_empty(),"saved Continue preserves one delivery, one payment and no live trip")

func exact(a:Variant,b:Variant,label:String) -> bool:
 var differences:Array=[];var numeric_type_only:Array=[];var nonfinite_bits_equal:Array=[]
 compare(a,b,"$",differences,numeric_type_only,nonfinite_bits_equal)
 print("DEV04_CORE_EXACT ",JSON.stringify({"label":label,"differences":differences,"numeric_type_only":numeric_type_only,"nonfinite_bits_equal":nonfinite_bits_equal},"",true,true))
 return check(differences.is_empty(),label+" is losslessly exact, no epsilon")
func compare(a:Variant,b:Variant,path:String,differences:Array,numeric_type_only:Array,nonfinite_bits_equal:Array) -> void:
 if (a is int or a is float) and (b is int or b is float):
  var equal:bool=false
  if typeof(a)==typeof(b):
   # Retain legitimate INF sensor sentinels. Same-type floats must have exact
   # binary64 bits, including sign/payload; no nonfinite field is discarded.
   equal=PackedFloat64Array([a]).to_byte_array()==PackedFloat64Array([b]).to_byte_array() if a is float else a==b
  else:
   var integer:int=a if a is int else b;var decimal:float=b if b is float else a
   # Never use mixed Variant equality: above 2^53 it may hide precision loss.
   equal=is_finite(decimal) and absf(decimal)<=9007199254740991.0 and decimal==floor(decimal) and int(decimal)==integer and float(integer)==decimal
  var row:Dictionary={"path":path,"left_type":type_string(typeof(a)),"right_type":type_string(typeof(b)),"left":a,"right":b,"left_float64_bits":PackedFloat64Array([float(a)]).to_byte_array().hex_encode(),"right_float64_bits":PackedFloat64Array([float(b)]).to_byte_array().hex_encode()}
  if not equal:differences.append(row)
  elif typeof(a)!=typeof(b):numeric_type_only.append(row)
  elif a is float and not is_finite(a):nonfinite_bits_equal.append(row)
  return
 if a is Dictionary and b is Dictionary:
  for field in a:
   if b.has(field):compare(a[field],b[field],path+"."+str(field),differences,numeric_type_only,nonfinite_bits_equal)
   else:differences.append({"path":path+"."+str(field),"change":"missing_right"})
  for field in b:
   if not a.has(field):differences.append({"path":path+"."+str(field),"change":"missing_left"})
  return
 if a is Array and b is Array:
  if a.size()!=b.size():differences.append({"path":path,"left_size":a.size(),"right_size":b.size()})
  for index in mini(a.size(),b.size()):compare(a[index],b[index],path+"["+str(index)+"]",differences,numeric_type_only,nonfinite_bits_equal)
  return
 if typeof(a)!=typeof(b) or a!=b:differences.append({"path":path,"left":a,"right":b,"left_type":type_string(typeof(a)),"right_type":type_string(typeof(b))})
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refusing existing/unisolated profile; use a NEW empty /tmp XDG_DATA_HOME.");quit(2);return
 root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
 var pins:Dictionary={}
 for path in SOURCES:pins[path]=FileAccess.get_sha256("res://"+path)
 print("DEV04_CORE_SOURCE_PINS ",JSON.stringify(pins,"",true,true))
 print("DEV04_CORE_TEST_SOURCE ",JSON.stringify({"path":get_script().resource_path,"sha256":FileAccess.get_sha256(get_script().resource_path),"predecessor_sha256":"f3dd5fef9f2c71f8ed9828c433a51c015ebb6c402be495682d6566e482eaed07"}))
 print("DEV04_CORE_BOUNDS ",JSON.stringify({"command_hz":60,"midflight_ticks":480,"remaining_tick_budget":FLIGHT_BUDGET,"automated_api":true,"native_input":false,"production_scene_overrides":false}))
 await exercise();await close_title()
 print("DEV04_MAIN_CORE_JOURNEY_SUCCESSOR01 passed=%d failed=%d native_input=false migration=false"%[passed,failed]);quit(1 if failed else 0)
