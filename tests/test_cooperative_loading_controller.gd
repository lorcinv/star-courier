extends SceneTree
## Controller/persistence and synthetic native-Control input. Motion appearance
## still needs an inspected OS-native recording; these assertions cannot prove it.
const Main=preload("res://scenes/main.tscn")
var game
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func frames(count:int=3) -> void:
 for i in count:await process_frame
func fresh(erase:bool=true) -> void:
 if is_instance_valid(game):game.queue_free();await frames()
 if erase:
  for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
   if FileAccess.file_exists("user://"+file) or DirAccess.dir_exists_absolute("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=Main.instantiate();root.add_child(game)
 game.set_process(false);game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames()
func step(seconds:float) -> void:
 for i in ceili(seconds*120):
  var tween:Tween=game.world._parcel_tween
  if tween!=null and game.world._focus_active and game.world.is_visible_in_tree():tween.pause();tween.custom_step(1.0/120.0)
  game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0)
  game._process(1.0/120.0)
func accept(id:String="D1-A") -> void:
 game._action("accept_contract",id)
 for i in 1500:
  if game.dialogue.is_open():break
  step(1.0/120.0)
 if game.dialogue.is_open():game.dialogue.skip_conversation()
 game._sync_loading_scene_ui()
func reach(phase:String) -> void:
 for i in 2400:
  if game.world._parcel_phase==phase:return
  step(1.0/120.0)
 check(false,"reachable cooperative controller phase "+phase)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func ledger() -> Dictionary:
 return {"credits":game.economy.credits,"stock":game.economy.inventory.duplicate(true),"jobs":game.economy.jobs_today,"deliveries":game.economy.deliveries,"settled":game.economy.settled_ids.duplicate(true)}
func final_pose() -> Dictionary:
 var s:Dictionary=game.world.loading_snapshot()
 return {"state":s.state,"phase":s.phase,"parcel":s.parcel_position,"visible":s.parcel_visible,"clerk":s.clerk_position,"clerk_state":s.clerk_state,"z":s.clerk_z,"customer":s.customer_departure,"customer_position":s.customer_position,"robot_x":s.robot.robot_x,"robot_pose":s.robot.robot_pose,"robot_owner":s.robot.transport_owner}
func key(code:int,ctrl:bool=false) -> void:
 for down in [true,false]:
  var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.ctrl_pressed=ctrl;root.push_input(event);await frames(1)
func click(point:Vector2) -> void:
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion)
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
  root.push_input(event);await frames(1)
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 root.size=Vector2i(1280,800);await fresh();accept();await frames()
 var before:Dictionary=ledger();var original:Array=game.design.duplicate(true);var parcel:int=game.world.parcel.get_instance_id()
 check(game._loading_scene_active() and game.loading_overlay.is_open() and not game.hud.visible,"dialogue completion starts an unobscured input-captured cooperative scene")
 check(not game.economy.is_cargo_loaded() and not disk().contracts[0].cargo_loaded,"visual scene start does not prematurely persist loaded cargo")
 game.navigate("workshop");game.selected_id=2;game._remember_assembly()
 for code in [KEY_R,KEY_DELETE]:await key(code)
 await key(KEY_Z,true)
 var point:Vector2=game.world._screen_point(game.world.assembly_origin+Vector2(3,2)*72)
 await click(point);game._action("select_catalog","battery");game._action("dispatch",null)
 check(game.design==original and game.page!="flight" and game.sim==null and game.economy.in_flight.is_empty(),"keyboard, pointer and stale underlying actions cannot edit or launch through the scene")
 check(not game.workshop_input.enabled() and game.workshop_input.camera.gesture.is_empty(),"scene cancels and disables workshop pan/edit ownership")
 reach("clerk_round_counter")
 game._on_focus_exited();var stopped:Dictionary=game.world.loading_snapshot();var stopped_time:float=game.world.visual_time;step(.8)
 game.loading_overlay.request_skip()
 check(game.world.loading_snapshot()==stopped and game.world.visual_time==stopped_time and not game.loading_overlay._requested,"focus loss freezes all choreography and cannot latch a rejected skip")
 game._on_focus_entered();root.size=Vector2i(1920,1080);await frames()
 check(game.loading_overlay.is_open() and game.loading_overlay.debug_snapshot().frame.encloses(game.loading_overlay._skip.get_global_rect()),"resizing preserves current scene/order and maps its skip button")
 step(12);await frames()
 check(game.economy.is_cargo_loaded() and game.world.is_parcel_loaded() and game.page=="workshop","natural confirmation persists loaded cargo and enters the editable workshop")
 check(not game.loading_overlay.is_open() and game.hud.visible and game.workshop_input.enabled(),"natural completion releases scene input and restores the correct workshop HUD")
 check(ledger()==before and game.world.parcel.get_instance_id()==parcel,"natural scene moves one parcel without inventory, reward or quota mutations")
 check(bool(disk().contracts[0].cargo_loaded) and game.hud.toast_label.text=="货物已装入货舱。","completion save and concise ready message survive the deferred page transition")
 var expected:Dictionary=final_pose();var saved:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 for i in 30:game._on_cargo_loading_complete("D1-A");game.world.fastforward_loading("D1-A")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==saved and ledger()==before,"repeated completion/skip cannot resave or charge a completed parcel")
 await fresh(false)
 check(final_pose()==expected and not game.world.is_loading() and not game.loading_overlay.is_open(),"loaded restart restores identical departed NPC, helper positions and installed parcel without replay")
 var phases:Array[String]=["customer_handoff","robot_fetch","robot_pickup","robot_turn","clerk_round_counter","clerk_join","robot_carry","robot_insert","clerk_align","clerk_confirm"]
 for phase in phases:
  await fresh();accept();reach(phase);await frames()
  before=ledger();parcel=game.world.parcel.get_instance_id();var active:String=game.world.active_id
  game._skip_loading_scene("foreign");check(game.world._parcel_phase==phase,"foreign skip cannot settle "+phase)
  await key(KEY_ESCAPE)
  check(game.page=="workshop" and game.economy.is_cargo_loaded() and final_pose()==expected,"Escape reaches the exact natural loaded workshop from "+phase)
  check(game.world.parcel.get_instance_id()==parcel and ledger()==before and disk().contracts[0].cargo_loaded,"skip retains parcel identity and one durable nonfinancial completion from "+phase)
  game._skip_loading_scene(active);await key(KEY_SPACE)
  check(game.page=="workshop" and game.sim==null and ledger()==before,"held/repeated skip does not launch or alter the completed scene from "+phase)
 await fresh();accept();reach("clerk_join");game.save_game();check(not disk().contracts[0].cargo_loaded,"mid-scene save remains accepted but unloaded")
 await fresh(false);await frames()
 check(game.world.is_loading() and not game.dialogue.is_open() and not game.economy.is_cargo_loaded(),"restart resumes one unfinished visual handoff without repeating read dialogue")
 var old_generation:int=game.world._parcel_generation
 game._action("cancel_contract",null);game._action("accept_contract","D1-B");step(8)
 check(game.economy.active_contract_id=="D1-B" and game.dialogue.is_open(),"cancel/new order waits for the clerk's natural return before its dialogue")
 game.world._complete_loading("D1-A",old_generation);game._on_cargo_loading_complete("D1-A");game._skip_loading_scene("D1-A")
 check(not game.economy.is_cargo_loaded() and game.world.active_id=="D1-B","stale order callbacks and skip cannot load the replacement parcel")
 game.dialogue.skip_conversation();await frames();game._skip_loading_scene("D1-B");await frames()
 check(game.economy.is_cargo_loaded("D1-B") and game.page=="workshop","replacement order gets one independently skippable loading scene")
 await fresh();accept();await frames();var bytes_before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp");game._skip_loading_scene();await frames()
 check(game.world.is_parcel_loaded() and not game.economy.is_cargo_loaded() and game.page=="workshop","failed loading save settles visuals but never claims a durable loaded model")
 check(game.hud.toast_label.text.contains("重试") and FileAccess.get_file_as_bytes("user://savegame.json")==bytes_before,"save-failure message survives transition and prior bytes remain unchanged")
 game.start_flight(false)
 check(game.sim==null and game.economy.in_flight.is_empty(),"unrecoverable storage failure blocks formal dispatch even after skipped animation")
 DirAccess.remove_absolute("user://savegame.tmp");game.start_flight(false)
 check(game.page=="flight" and game.economy.in_flight.route.cargo_loaded and disk().in_flight.route.cargo_loaded,"explicit retry after storage recovery saves loaded state before one formal commitment")
 await fresh();game.settings.reduced_motion=true;game.render();accept();await frames()
 check(game.page=="workshop" and game.economy.is_cargo_loaded() and final_pose()==expected,"reduced motion reaches the same saved final actors and cargo with no forced waiting")
 game.queue_free();await frames()
 print("COOPERATIVE_LOADING_CONTROLLER passed=",passed," failed=",failed," native_input=false");quit(1 if failed else 0)
