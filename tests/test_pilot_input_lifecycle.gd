extends SceneTree
## Controller integration. Keys use Input.parse_input_event (synthetic Godot input,
## NOT native operating-system input). Process time is stepped explicitly so
## fixture pauses do not obscure exact replay assertions. Use an isolated XDG home.
const Profile = preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Legacy = preload("res://scripts/simulation.gd")
const Econ = preload("res://scripts/economy.gd")
const EXPECTED_CHECKS:int=85
class KeyboardCapture:
 extends Control
 var presses:int=0
 func _gui_input(event:InputEvent) -> void:
  if event is InputEventKey:
   if event.pressed:presses+=1
   accept_event()

var passed:int=0
var failed:int=0
var game

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(frames:int=3) -> void:
 for i in frames:await process_frame
func key(code:int,down:bool,echo:bool=false,physical:int=-1) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code if physical<0 else physical;event.pressed=down;event.echo=echo;event.unicode=code if code>=32 and code<=126 else 0
 Input.parse_input_event(event);await settle(1)
func tap(code:int) -> void:
 await key(code,true);await key(code,false)
func neutral() -> bool:
 return game._pilot_input_state()==Timeline.neutral() and game.sim.pilot_axis_q==0 and not game.sim.pilot_boost and not game.sim.pilot_active
func saved() -> Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_fixture(value:Dictionary) -> void:
 var file:=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()
 if FileAccess.file_exists("user://savegame.backup.json"):DirAccess.remove_absolute("user://savegame.backup.json")
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await settle(4)
 game=null
func fresh(clear_save:bool=true) -> void:
 await dispose()
 if clear_save:
  for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
   if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false)
 # Retain v2 held-key/replay coverage; v3 has a separate production-controller suite.
 game.economy.enable_ascent_mode();game.render()
 await settle(4)
 if is_instance_valid(root.gui_get_focus_owner()):root.gui_get_focus_owner().release_focus()
func accept() -> void:
 check(game.economy.accept_contract(str(game.economy.available_contracts()[0].contract_id)).ok,"fixture accepts available contract")
 # Complete non-flight dialogue setup before testing exact held-key lifecycles.
 var cid:String=game.economy.active_contract_id
 game.economy.mark_story_seen(cid,cid+"/accept")
func flight(is_trial:bool=true) -> void:
 game.start_flight(is_trial)
 if is_instance_valid(root.gui_get_focus_owner()):root.gui_get_focus_owner().release_focus()
func steps(count:int) -> void:
 for i in count:
  if game.sim.status!="running":break
  game._step_flight()
func state(sim) -> Dictionary:
 var value:Dictionary={"status":sim.status,"elapsed":sim.elapsed,"telemetry":sim.telemetry.duplicate(true),"bodies":[],"parts":[],"obstacles":[],"accumulator":sim._accumulator}
 # Command telemetry is immediate UI state, intentionally neutralized on pause/resume.
 for field in ["pilot_axis_q","pilot_boost","pilot_active"]:value.telemetry.erase(field)
 for b in sim.bodies:value.bodies.append({"id":b.id,"position":b.position,"velocity":b.velocity,"angle":b.angle,"angular_velocity":b.angular_velocity,"mass":b.mass,"inertia":b.inertia})
 for h in sim.obstacles:value.obstacles.append({"position":h.position,"velocity":h.velocity,"mass":h.mass,"radius":h.radius,"health":h.health,"type":h.type,"cooldown":h.cooldown})
 for p in sim.parts.values():value.parts.append({"id":p.id,"hp":p.hp,"energy":p.energy,"alive":p.alive,"body_id":p.body_id,"world_pos":p.world_pos,"delivered":p.delivered,"gimbal_angle":p.get("gimbal_angle",0.0)})
 return value
func difference(a:Variant,b:Variant,path:String="state") -> String:
 if (a is int or a is float) and (b is int or b is float):
  return "" if float(a)==float(b) else path+" numeric "+str(a)+" != "+str(b)
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return path+" key count differs"
  for k in a:
   if not b.has(k):return path+" missing key "+str(k)
   var diff:String=difference(a[k],b[k],path+"."+str(k))
   if not diff.is_empty():return diff
  return ""
 if a is Array and b is Array:
  if a.size()!=b.size():return path+" array size differs"
  for i in a.size():
   var diff:String=difference(a[i],b[i],path+"["+str(i)+"]")
   if not diff.is_empty():return diff
  return ""
 return "" if a==b else path+" "+str(a)+" != "+str(b)
func control(key_name:String) -> Control:
 for node in game.hud.content.find_children("*","Control",true,false):
  if str(node.get_meta("view_key",""))==key_name:return node
 return null
func test_keys() -> void:
 await fresh();accept();flight()
 check(game._is_pilot_flight() and game.sim.get_script()==preload("res://scripts/pilot_ascent_simulation.gd"),"new flight uses versioned ascent simulator")
 await key(KEY_W,true);check(game._pilot_input_state().axis_q==-1000,"W press reaches controller through Input.parse_input_event")
 await key(KEY_S,true);check(game._pilot_input_state().axis_q==0,"opposite held W and S cancel exactly")
 await key(KEY_W,false);check(game._pilot_input_state().axis_q==1000,"releasing W preserves held S")
 await key(KEY_DOWN,true);await key(KEY_S,false);check(game._pilot_input_state().axis_q==1000,"alias Down remains held after S release")
 await key(KEY_UP,true);check(game._pilot_input_state().axis_q==0,"held arrow opposites cancel")
 await key(KEY_DOWN,false);check(game._pilot_input_state().axis_q==-1000,"releasing Down preserves Up")
 await key(KEY_SHIFT,true);await key(KEY_SPACE,true)
 check(game._pilot_input_state()=={"axis_q":-1000,"boost":true,"active":true} and not game.paused,"Shift boosts and Space activates without pausing")
 steps(2);check(game.pilot_completed_ticks==2 and game.sim.pilot_tick==4,"one command tick advances exactly two 120Hz physics ticks")
 check(game.pilot_timeline.snapshot()==[{"tick":0,"axis_q":-1000,"boost":true,"active":true}],"unchanged held command remains sparse")
 var editor:=KeyboardCapture.new();editor.size=Vector2(200,60);editor.focus_mode=Control.FOCUS_ALL;game.hud.root.add_child(editor);editor.grab_focus();await settle()
 await key(KEY_UP,false);await key(KEY_SHIFT,false);await key(KEY_SPACE,false)
 check(game._pilot_input_state()==Timeline.neutral(),"_input captures releases even while focused UI consumes keys")
 await key(KEY_W,true);check(editor.presses>0 and game._pilot_input_state().axis_q==0,"focused GUI control consumes press before flight controller")
 await key(KEY_W,false);editor.release_focus();editor.queue_free();await settle()
 steps(1);check(game.pilot_timeline.state_at(2)==Timeline.neutral(),"release command starts at matching next step")
 for cycle in 4:
  await key(KEY_W,true);await tap(KEY_P)
  check(game.paused and neutral(),"pause clears held controls cycle "+str(cycle))
  var tick:int=game.pilot_completed_ticks;game._process(.2)
  check(game.pilot_completed_ticks==tick,"paused processing does not step cycle "+str(cycle))
  await key(KEY_W,true,true);await key(KEY_W,false);await tap(KEY_ESCAPE)
  check(not game.paused and neutral(),"resume requires fresh press after echo/release cycle "+str(cycle))
 await key(KEY_W,true);steps(1);check(game.sim.pilot_axis_q==-1000,"fresh post-resume press steers")
 await key(KEY_W,false)
 var design:Array=game.design.duplicate(true)
 game.hud.settings_open=true;game.hud.render(game.hud.state);game._process(0)
 check(game.paused and neutral() and game.hud.is_blocking_modal(),"opening settings pauses and neutralizes immediately on process")
 var before:Dictionary=state(game.sim);var tick:int=game.pilot_completed_ticks
 for code in [KEY_W,KEY_S,KEY_UP,KEY_DOWN,KEY_SHIFT,KEY_R,KEY_DELETE,KEY_P]:await tap(code)
 game._process(.2)
 check(game.design==design and state(game.sim)==before and game.pilot_completed_ticks==tick and neutral(),"modal captures edit/steer/pause input without moving craft or mutating assembly")
 await tap(KEY_ESCAPE);game._process(0)
 check(not game.hud.is_blocking_modal() and not game.paused and neutral(),"Escape closes settings and restores previously running flight with neutral keys")
 game._set_paused(true);game.hud.settings_open=true;game.hud.render(game.hud.state);game._process(0)
 await tap(KEY_ESCAPE);game._process(0)
 check(game.paused and neutral(),"closing settings preserves a preexisting pause")
 game._set_paused(false);game.hud.settings_open=true;game.hud.render(game.hud.state);game._process(0)
 game._on_focus_exited();await tap(KEY_ESCAPE);game._process(0)
 check(game.hud.is_blocking_modal() and game.paused and neutral(),"unfocused Escape cannot dismiss settings")
 game._on_focus_entered();await tap(KEY_ESCAPE);game._process(0)
 check(game.paused and neutral(),"focus loss inside settings remains paused after modal closes")
 game._set_paused(false);await key(KEY_W,true);await key(KEY_SHIFT,true);steps(2)
 game._on_focus_exited();check(game.paused and neutral(),"focus loss pauses and clears flight controls")
 check(int(game.sim.telemetry.pilot_axis_q)==0 and not game.sim.telemetry.pilot_boost and not game.sim.telemetry.pilot_active,"pause/focus clearing updates HUD command telemetry without another physics tick")
 await key(KEY_W,false);await key(KEY_SHIFT,false);await tap(KEY_P)
 check(game.paused and neutral(),"unfocused pause input is ignored")
 game._on_focus_entered();await tap(KEY_P)
 check(not game.paused and neutral(),"release delivered while unfocused cannot latch input after resume")
 var credits:int=game.economy.credits;game.abort_flight()
 check(game.page=="report" and game.economy.credits==credits and game.economy.in_flight.is_empty(),"trial abort reports without changing money or creating a dispatch")
 game.start_flight(true)
 check(game.page=="flight" and game.pilot_completed_ticks==0 and game.pilot_timeline.snapshot()==[{"tick":0,"axis_q":0,"boost":false,"active":false}] and neutral() and not game.paused,"retry resets ticks, timeline, pause and held keys")

func test_formal_replay() -> void:
 await fresh();accept();var credits:int=game.economy.credits
 flight();var trial_route:Dictionary=game.flight_order.duplicate(true);game.abort_flight();flight(false)
 check(game.economy.credits==credits,"trial and dispatch launch do not debit money")
 var formal_route:Dictionary=game.flight_order.duplicate(true);var trial_compare:Dictionary=trial_route.duplicate(true)
 formal_route.erase("status");trial_compare.erase("status")
 check(formal_route==trial_compare,"trial and formal gameplay route/seed/profile are identical (contract status naturally differs)")
 var launch:Dictionary=saved().in_flight
 check(launch.control_version==Profile.CONTROL_VERSION and int(launch.ticks)==0 and launch.input_commands.size()==1,"formal launch persists neutral timeline before first physics step")
 await key(KEY_W,true);steps(12);await key(KEY_SHIFT,true);steps(6);await key(KEY_W,false);await key(KEY_S,true);steps(9);await key(KEY_SHIFT,false);await key(KEY_S,false);await key(KEY_SPACE,true);steps(4);await key(KEY_SPACE,false);steps(3);await key(KEY_W,true);await key(KEY_SHIFT,true);await key(KEY_SPACE,true);steps(2)
 var expected:Dictionary=state(game.sim);var ticks:int=game.pilot_completed_ticks;var commands:Array=game.pilot_timeline.snapshot()
 game._on_focus_exited()
 check(game.paused and neutral() and int(saved().in_flight.ticks)==ticks and saved().in_flight.input_commands==JSON.parse_string(JSON.stringify(commands)),"focus-loss checkpoint writes completed ticks and sparse commands")
 await fresh(false)
 check(game._is_pilot_flight() and game.paused and not game.pilot_resume_blocked,"saved pilot reconstructs then pauses")
 print("REPLAY_DIAGNOSTIC expected_ticks=",ticks," actual_ticks=",game.pilot_completed_ticks," expected_status=",expected.status," actual_status=",game.sim.status," expected_hazard=",expected.obstacles[0].position," actual_hazard=",game.sim.obstacles[0].position)
 print("REPLAY_FIRST_DIFFERENCE ",difference(state(game.sim),expected))
 check(game.pilot_completed_ticks==ticks and difference(state(game.sim),expected).is_empty(),"disk JSON replay exactly reconstructs positions, velocity, energy, HP, obstacles and ticks")
 check(neutral(),"reconstructed flight never restores physically held inputs")
 check(game.pilot_timeline.snapshot()==commands,"reconstruction preserves command boundary history")
 var replica=preload("res://scripts/pilot_ascent_simulation.gd").new();replica.configure(game.design,game.launcher,trial_route,int(trial_route.seed))
 var timeline=Timeline.new();timeline.restore(commands,ticks)
 for i in ticks:
  var command:Dictionary=timeline.state_at(i);replica.set_pilot_input(command.axis_q,command.boost,command.active);replica.step(1.0/60.0)
 replica.set_pilot_input(0,false,false);replica.step(1.0/60.0)
 await tap(KEY_P);steps(1)
 print("RESUMED_FIRST_DIFFERENCE ",difference(state(game.sim),state(replica)))
 check(difference(state(game.sim),state(replica)).is_empty(),"first resumed command is neutral at exact checkpoint boundary")
 var id:String=game.flight_order.contract_id;game.abort_flight();var after:int=game.economy.credits;var jobs:int=game.economy.jobs_today
 check(game.page=="report" and game.economy.in_flight.is_empty() and saved().in_flight.is_empty(),"formal completion leaves no ghost in-flight checkpoint")
 check(game.economy.settled_ids.has(id) and jobs==1,"formal flight settles one unique contract")
 game.finish_flight();var duplicate:Dictionary=game.economy.settle_contract(id,game.sim.telemetry,game.sim.elapsed,false)
 check(duplicate.get("duplicate",false) and game.economy.credits==after and game.economy.jobs_today==jobs,"repeated finish/settlement cannot pay or charge twice")
 await fresh(false)
 check(game.page=="hub" and game.economy.in_flight.is_empty() and game.economy.credits==after,"settled new-version run reloads without dispatch resurrection")

func test_invalid_and_legacy() -> void:
 await fresh();accept();flight(false);steps(4);game.save_game();var base:Dictionary=saved()
 await dispose()
 var bads:Array=[]
 var unknown:Dictionary=base.duplicate(true);unknown.in_flight.control_version="pilot-future";bads.append(["unknown control version",unknown])
 var conflict:Dictionary=base.duplicate(true);conflict.in_flight.route.control_version="pilot-future";bads.append(["conflicting route control version",conflict])
 var explicit_legacy:Dictionary=base.duplicate(true);explicit_legacy.in_flight.control_version="";bads.append(["conflicting explicit legacy version",explicit_legacy])
 var fractional:Dictionary=base.duplicate(true);fractional.in_flight.ticks=4.5;bads.append(["fractional completed ticks",fractional])
 var malformed:Dictionary=base.duplicate(true);malformed.in_flight.input_commands=[{"tick":0,"axis_q":5000,"boost":false,"active":false}];bads.append(["out-of-range command",malformed])
 var absent:Dictionary=base.duplicate(true);absent.in_flight.erase("input_commands");bads.append(["missing timeline",absent])
 for pair in bads:
  write_fixture(pair[1]);var original:String=FileAccess.get_file_as_string("user://savegame.json");await fresh(false)
  var money:int=game.economy.credits;var jobs:int=game.economy.jobs_today;var flight_snapshot:Dictionary=game.economy.in_flight.duplicate(true)
  check(game.pilot_resume_blocked,"fails closed on "+str(pair[0]))
  game._set_paused(false);game.abort_flight();game._process(2);game._process(2)
  check(not game.save_game() and FileAccess.get_file_as_string("user://savegame.json")==original,"preserves original bytes for "+str(pair[0]))
  check(game.economy.credits==money and game.economy.jobs_today==jobs and game.economy.in_flight==flight_snapshot,"does not settle or mutate broken dispatch for "+str(pair[0]))
  game.navigate("workshop");game.start_flight(true);game.abort_flight()
  check(game.pilot_resume_blocked and not game.save_game() and FileAccess.get_file_as_string("user://savegame.json")==original and game.economy.in_flight==flight_snapshot,"trial/retry cannot bypass recovery block or overwrite "+str(pair[0]))
  await dispose()
 # Genuine legacy route has no pilot fields; its controller and physics remain old.
 var legacy=Econ.new();var custom:Array=Profile.starter_design();custom[2].x=-2;custom[2].y=-1
 legacy.starter_stock(custom,Profile.starter_launcher());legacy.accept_contract(str(legacy.available_contracts()[0].contract_id));legacy.begin_dispatch(custom,Profile.starter_launcher())
 var oldsim=Legacy.new();var oldroute:Dictionary=legacy.in_flight.route.duplicate(true);oldroute.seed=legacy.in_flight.seed;oldsim.configure(custom,Profile.starter_launcher(),oldroute,int(oldroute.seed))
 for i in 18:oldsim.step(1.0/60.0)
 legacy.in_flight.elapsed=oldsim.elapsed;legacy.in_flight.ticks=18;legacy.save_state(custom,Profile.starter_launcher(),{})
 var oldsave:Dictionary=saved();oldsave.version=2;oldsave.erase("flight_mode");write_fixture(oldsave);await fresh(false)
 check(not game._is_pilot_flight() and game.sim.get_script()==Legacy and not game.pilot_resume_blocked,"version-2 in-flight save resumes unchanged legacy simulator")
 check(state(game.sim)==state(oldsim),"legacy replay retains exact old-route physics")
 check(JSON.stringify(game.design)==JSON.stringify(custom),"existing custom workshop is not replaced by pilot starter")
 game.abort_flight();accept();flight()
 check(game._is_pilot_flight() and game.sim.get_script()==preload("res://scripts/pilot_ascent_simulation.gd") and neutral(),"legacy completion can begin a neutral ascent trial in the same controller")
 steps(1);check(game.pilot_completed_ticks==1 and game.sim.pilot_tick==2,"legacy-to-pilot transition steps the new simulator without old-API calls")
 await dispose()
 oldsave.version=1;oldsave.in_flight={};oldsave.active_contract_id="";write_fixture(oldsave);await fresh(false)
 check(JSON.stringify(game.design)==JSON.stringify(custom) and game.economy.in_flight.is_empty(),"version-1 migration retains custom design and reads safely")

func run() -> void:
 root.size=Vector2i(1280,800);Input.use_accumulated_input=false
 await test_keys();await test_formal_replay();await test_invalid_and_legacy();await dispose()
 if passed+failed!=EXPECTED_CHECKS:check(false,"every planned lifecycle assertion ran")
 print("PILOT_INPUT_LIFECYCLE passed=%d failed=%d input=synthetic_Input.parse_input_event native_input=false"%[passed,failed])
 quit(1 if failed else 0)
