extends SceneTree
## Isolated synthetic input/controller test, not native OS or usability evidence.
const Econ=preload("res://scripts/economy.gd")
const Free=preload("res://scripts/pilot_free_profile_v1.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v1.gd")
const Simulator=preload("res://scripts/pilot_free_simulation_v1.gd")
var game
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func frames(n:int=3) -> void:
 for i in n:await process_frame
func write_fixture() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
 var e=Econ.new();e.enable_free_mode();e.starter_stock(Free.starter_design(),Free.starter_launcher());e.enable_story_mode()
 check(e.accept_contract("D1-A").ok,"fixture accepts exact authored free order")
 e.mark_story_seen("D1-A","D1-A/accept");e.mark_cargo_loaded("D1-A")
 check(e.save_state(Free.starter_design(),Free.starter_launcher(),{}),"isolated earned-order shape saved")
func boot(defer_entry:bool=false) -> void:
 game=load("res://scenes/main.tscn").instantiate();game.entry_defer_controls=defer_entry;root.add_child(game);game.set_process(false)
 await frames(5)
 if is_instance_valid(root.gui_get_focus_owner()):root.gui_get_focus_owner().release_focus()
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await frames(4)
 game=null
func key(code:int,pressed:bool) -> void:
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
 Input.parse_input_event(e);await frames(1)
func state(s) -> Dictionary:
 var out:Dictionary={"status":s.status,"elapsed":s.elapsed,"parts":[],"bodies":[],"obstacles":[],"accumulator":s._accumulator,"telemetry":s.telemetry.duplicate(true)}
 for name in ["pilot_axis_x_q","pilot_axis_q","pilot_boost","pilot_active","overdrive"]:out.telemetry.erase(name)
 for b in s.bodies:out.bodies.append({"id":b.id,"position":b.position,"velocity":b.velocity,"angle":b.angle,"angular_velocity":b.angular_velocity,"mass":b.mass,"inertia":b.inertia})
 for p in s.parts.values():out.parts.append({"id":p.id,"hp":p.hp,"energy":p.energy,"alive":p.alive,"body_id":p.body_id,"world_pos":p.world_pos,"delivered":p.delivered,"gimbal_angle":p.get("gimbal_angle",0.0)})
 for h in s.obstacles:out.obstacles.append({"position":h.position,"velocity":h.velocity,"health":h.health,"radius":h.radius})
 return out
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 write_fixture();await boot()
 check(not game.economy.review_load_blocked and game.economy.active_contract().control_version==Free.VERSION,"Main loads free order without downgrade")
 game.start_flight(false)
 check(game.page=="flight" and game.sim is Simulator and game.pilot_timeline is Timeline,"Main chooses free simulator and exact two-axis timeline")
 check(game.economy.in_flight.get("input_schema")==Free.INPUT_SCHEMA,"formal launch writes distinct input schema")
 await key(KEY_A,true)
 check(game._pilot_input_state().axis_x_q==-1000,"A reaches free-flight negative-X input")
 for i in 12:game._step_flight()
 await key(KEY_D,true)
 check(game._pilot_input_state().axis_x_q==0,"opposite horizontal held keys cancel")
 await key(KEY_A,false);await key(KEY_W,true);await key(KEY_SHIFT,true)
 check(game._pilot_input_state().axis_x_q==1000 and game._pilot_input_state().axis_q==-1000 and game._pilot_input_state().boost,"D+W+Shift remain actual two-axis controls")
 for i in 18:game._step_flight()
 await key(KEY_D,false);await key(KEY_W,false);await key(KEY_SHIFT,false)
 check(game._pilot_input_state()==Timeline.neutral(),"releases clear both axes and boost")
 for i in 240:game._step_flight()
 var expected:Dictionary=state(game.sim);var ticks:int=game.pilot_completed_ticks;var commands:Array=game.pilot_timeline.snapshot()
 game._on_focus_exited()
 check(game.paused and game.sim.pilot_axis_x_q==0 and game._pilot_input_state()==Timeline.neutral(),"focus loss clears full two-axis state")
 var durable:String=FileAccess.get_sha256("user://savegame.json")
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(saved.in_flight.input_schema==Free.INPUT_SCHEMA and saved.in_flight.ticks==ticks and saved.in_flight.input_commands==JSON.parse_string(JSON.stringify(commands)),"checkpoint preserves both axis histories and tick identity")
 await dispose();await boot(true)
 game.prepare_title_restore()
 check(game.title_restore_pending() and game.sim==null,"long replay yields before publishing any simulation/world state")
 for i in 10:
  if not game.title_restore_pending():break
  await frames(1)
 check(not game.title_restore_pending() and not game.pilot_resume_blocked and game.paused,"bounded replay completes to paused flight")
 if game.sim!=null:
  check(state(game.sim)==expected,"Main JSON replay preserves exact simulator state")
  check(game.pilot_completed_ticks==ticks and game.pilot_timeline.snapshot()==commands,"Main replay retains original timeline boundary")
 check(FileAccess.get_sha256("user://savegame.json")==durable,"title-owned replay does not rewrite durable save")
 await dispose();await boot(true)
 game.prepare_title_restore();check(game.title_restore_pending(),"cancel fixture begins same yielded replay")
 game.cancel_title_restore();await frames(4)
 check(game.sim==null and game.pilot_resume_blocked and not game.title_restore_pending(),"cancel prevents late candidate publication")
 check(FileAccess.get_sha256("user://savegame.json")==durable,"cancel leaves original save bytes unchanged")
 await dispose()
 # Persist an abort request under an injected settlement-write failure, then
 # restore the exact tick history and apply that request once after replay.
 await write_abort_restart_fixture()
 print("MAIN_FREE_HOST_V1 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)

func write_abort_restart_fixture() -> void:
 write_fixture();await boot()
 game.start_flight(false)
 await key(KEY_D,true)
 for i in 37:game._step_flight()
 await key(KEY_D,false)
 var credits:int=game.economy.credits
 var previous:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 game.abort_flight()
 check(game.page=="flight" and game.sim.status=="failed" and game.economy.credits==credits,"failed abort settlement holds rather than issuing unpaid receipt")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==previous,"failed abort settlement preserves prior durable bytes")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(game.save_game(),"pending exact abort checkpoint saves after storage recovers")
 var saved_abort:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(saved_abort.in_flight.terminal_intent=="abort" and saved_abort.in_flight.ticks==37,"abort intent and completed command boundary are stored")
 await dispose();await boot(true);game.prepare_title_restore()
 for i in 10:
  if not game.title_restore_pending():break
  await frames(1)
 check(game.sim!=null and game.sim.status=="failed" and game._free_abort_intent and game.pilot_completed_ticks==37,"restore cannot turn a saved abort into a running delivery")
 game.entry_defer_controls=false;game.finish_flight()
 check(game.page=="report" and not game.report.success and game.economy.jobs_today==1 and game.economy.in_flight.is_empty(),"restored abort settles and consumes exactly one order")
 var settled_credits:int=game.economy.credits
 game.finish_flight()
 check(game.economy.credits==settled_credits and game.economy.jobs_today==1,"repeated terminal handler cannot charge twice")
 check(int(game.report.lost)==0 and int(game.report.get("charged_costs",999))<=25,"living hardware is rescued; abort charge is bounded")
 await dispose()
