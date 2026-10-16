extends SceneTree
## Explicit legacy-v3 compatibility successor; original assertions are retained.
## Synthesized SDL-standard InputEventJoypadMotion/Button through Godot's real
## input pipeline. No claim of a connected or physically exercised controller.
const Timeline=preload("res://scripts/pilot_timeline.gd")
const Econ=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
var game
var input
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated XDG_DATA_HOME required.");quit(2);return
 run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(frames:int=2) -> void:
 for unused in frames:await process_frame
func button(index:int,pressed:bool=true,device:int=0) -> void:
 var event:=InputEventJoypadButton.new();event.device=device;event.button_index=index;event.pressed=pressed
 Input.parse_input_event(event);await settle(1)
func tap(index:int) -> void:await button(index);await button(index,false)
func axis(index:int,value:float,device:int=0) -> void:
 var event:=InputEventJoypadMotion.new();event.device=device;event.axis=index;event.axis_value=value
 Input.parse_input_event(event);await settle(1)
func key(code:int,pressed:bool=true,echo:bool=false) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.echo=echo
 Input.parse_input_event(event);await settle(1)
func neutral() -> void:
 for index in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y]:await axis(index,0)
 for index in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_START,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN]:await button(index,false)
func tick(delta:float=.016) -> void:input.tick(delta)
func focus_key(id:String) -> Control:
 for child in game.hud.content.find_children("*","Control",true,false):
  if str(child.get_meta("view_key",""))==id:input._focus(child);return child
 return null
func fresh() -> void:
 for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false)
 await settle(4);game.world.set_process(false);input=game.courier_input
 input.tick(0);await neutral()
func run() -> void:
 await fresh()
 check(input.context=="shop","new game owns free shop context")
 check(InputMap.has_action("courier_confirm") and InputMap.has_action("courier_shop_left"),"shared semantic InputMap installed")
 await axis(JOY_AXIS_LEFT_X,.08);tick();check(input.shop_axis()==0 and not input.gamepad,"neutral drift neither moves clerk nor changes prompts")
 await axis(JOY_AXIS_LEFT_X,.61);tick();check(input.shop_axis()>.49 and input.shop_axis()<.51 and input.gamepad,"left stick produces rescaled analog shop axis and controller prompts")
 await axis(JOY_AXIS_LEFT_X,0);await button(JOY_BUTTON_DPAD_LEFT);tick();check(input.shop_axis()==-1,"D-pad offers full shop directional input")
 await button(JOY_BUTTON_DPAD_LEFT,false);await key(KEY_D);tick();check(input.shop_axis()==1,"physical D keeps keyboard shop control")
 await key(KEY_A);tick();check(input.shop_axis()==0,"opposed shop keys cancel")
 await key(KEY_D,false);await key(KEY_A,false)
 input.tick(.5);await key(KEY_F11,false);await key(KEY_E);await key(KEY_E,false)
 check(game.page=="contracts","fresh nearby E enters counter drawer")
 await tap(JOY_BUTTON_B);tick();check(game.page=="hub" and input.context=="shop","controller back returns drawer to free shop")
 await tap(JOY_BUTTON_START);tick();check(input.context=="ui" and is_instance_valid(root.gui_get_focus_owner()),"Menu enters shop UI with actual focus")
 var before:Control=root.gui_get_focus_owner()
 await button(JOY_BUTTON_DPAD_RIGHT);tick();var after:Control=root.gui_get_focus_owner()
 check(before!=after,"D-pad moves actual native UI focus")
 tick(.1);check(root.gui_get_focus_owner()==after,"held focus direction waits for repeat delay")
 tick(.1);tick(.1);tick(.1);check(root.gui_get_focus_owner()!=after,"held focus direction repeats without OS key echo")
 await button(JOY_BUTTON_DPAD_RIGHT,false);await tap(JOY_BUTTON_B);tick()
 check(input.context=="shop","B exits hub menu without changing shop page")
 game.navigate("workshop");tick();await settle()
 var design:Array=game.design.duplicate(true)
 await tap(JOY_BUTTON_START);tick();check(game.hud.settings_open and input.context=="modal","Menu opens settings from workbench UI")
 await tap(JOY_BUTTON_A);tick();check(not game.hud.settings_open and game.design==design,"modal safe default closes without assembly mutation")
 game.hud.settings_open=true;game.hud.render(game.hud.state);tick();await settle()
 var slider:Control=focus_key("settings:controller_deadzone");check(slider!=null,"deadzone setting is focusable")
 var old_zone:float=game.settings.controller_deadzone
 await button(JOY_BUTTON_DPAD_RIGHT);tick();await button(JOY_BUTTON_DPAD_RIGHT,false);tick()
 check(game.settings.controller_deadzone>old_zone and game.settings.controller_deadzone<=.45,"controller adjusts persistent deadzone")
 focus_key("settings:pixel_density");await tap(JOY_BUTTON_A);tick();check(game.settings.pixel_density!="auto","controller can select OptionButton values without inaccessible popup")
 await tap(JOY_BUTTON_B);tick();game.settings.controller_deadzone=.22
 check(game.design==design,"menu navigation never edits structure")
 await tap(JOY_BUTTON_X);tick();check(input.context=="grid" and input._grid,"X explicitly enters grid mode")
 var cell:Vector2i=game.workshop_input.controller_cell
 await button(JOY_BUTTON_DPAD_DOWN);tick();await button(JOY_BUTTON_DPAD_DOWN,false);tick()
 check(game.workshop_input.controller_cell==cell+Vector2i.DOWN and game.design==design,"grid movement moves only cursor")
 game.workshop_input.controller_cell=Vector2i(1,-1);await tap(JOY_BUTTON_A);tick()
 check(game.selected_id>=0 and game.design==design,"A selects installed part without moving it")
 var oldrot:int=game.selected_part().rot;await tap(JOY_BUTTON_X);tick()
 check(game.selected_part().rot==posmod(oldrot+1,4),"X rotates selected part once per fresh press")
 var rotated:int=game.selected_part().rot;await button(JOY_BUTTON_X);await button(JOY_BUTTON_X);tick();check(game.selected_part().rot==posmod(rotated+1,4),"duplicate held button events cannot repeat destructive actions")
 await button(JOY_BUTTON_X,false);await tap(JOY_BUTTON_RIGHT_SHOULDER);tick();check(game.selected_part().rot==rotated,"RB undoes one edit through existing undo history")
 var inventory:Dictionary=game.economy.inventory.duplicate(true);var count:int=game.design.size()
 await tap(JOY_BUTTON_Y);tick();check(game.workshop_input.controller_moving(),"Y picks up selected part into pending transaction")
 var source:Vector2i=game.workshop_input.controller_cell
 var target:=Vector2i(-4,-2)
 game.workshop_input.controller_cell=target;await tap(JOY_BUTTON_A);tick()
 check(Vector2i(game.selected_part().x,game.selected_part().y)==target and game.design.size()==count,"A commits picked-up move once at valid grid cell")
 check(game.economy.inventory==inventory,"moving parts preserves purchased inventory")
 await tap(JOY_BUTTON_Y);await tap(JOY_BUTTON_B);tick();check(not game.workshop_input.controller_moving() and input.context=="grid","B cancels pickup before leaving grid")
 await tap(JOY_BUTTON_LEFT_SHOULDER);tick();check(game.design.size()==count-1,"LB removes selected ordinary part")
 await tap(JOY_BUTTON_RIGHT_SHOULDER);tick();check(game.design.size()==count,"RB restores removed part")
 var camera:Vector2=game.workshop_input.camera.center
 await axis(JOY_AXIS_RIGHT_X,.8);tick(.1);await axis(JOY_AXIS_RIGHT_X,0);check(game.workshop_input.camera.center!=camera,"right stick pans existing editor camera")
 await tap(JOY_BUTTON_RIGHT_STICK);tick();check(game.workshop_input.camera.configured,"R3 fits editor without leaving grid")
 await tap(JOY_BUTTON_B);tick();check(input.context=="ui","B exits grid into menu navigation")
 game.chosen_type="beam";game.economy.inventory.beam=int(game.economy.inventory.get("beam",0))+1
 await tap(JOY_BUTTON_X);game.workshop_input.controller_cell=Vector2i(4,2);count=game.design.size();await tap(JOY_BUTTON_A);tick()
 check(game.design.size()==count+1,"A places selected stocked part in empty grid cell")
 await tap(JOY_BUTTON_RIGHT_SHOULDER);await tap(JOY_BUTTON_B);tick()
 var story:Dictionary={"dialogue_id":"controller-test","lines":[{"text":"手柄测试。","speaker":"npc"},{"text":"第二句。","speaker":"clerk"}]}
 game.dialogue.begin(story,{},game.settings);tick();await button(JOY_BUTTON_A)
 check(game.dialogue._visible_chars==5,"controller confirms dialogue fast reveal")
 await button(JOY_BUTTON_A);check(game.dialogue._line_index==0,"held dialogue confirm cannot skip next line")
 await button(JOY_BUTTON_A,false);await tap(JOY_BUTTON_B);tick();check(not game.dialogue.is_open(),"B skips dialogue through existing ownership callback")
 game.hud.settings_open=true;game.hud.render(game.hud.state);tick();var snapshot:Array=game.design.duplicate(true)
 await axis(JOY_AXIS_LEFT_Y,-.85);await button(JOY_BUTTON_RIGHT_SHOULDER);await button(JOY_BUTTON_A);tick()
 check(game.design==snapshot,"modal analog and shoulder input never mutate assembly")
 await neutral();game.hud.settings_open=false;game.hud.render(game.hud.state);game.navigate("hub");tick()
 # Real flight engine and unchanged protocol, with actual fractional axis commands.
 game.design=game.ExtremeProfile.starter_design();game.launcher=game.ExtremeProfile.starter_launcher()
 # Keep all original UI and one-axis flight assertions. Only the fixture's
 # authoring boundary is explicit: never mutate an existing free-v1 offer.
 var legacy_economy=Econ.new();legacy_economy.route_guard=game.economy.route_guard
 legacy_economy.enable_extreme_mode();legacy_economy.starter_stock(game.design,game.launcher)
 legacy_economy.enable_story_mode();game.economy=legacy_economy
 check(game.economy.flight_mode=="pilot-v3" and game.economy.available_contracts()[0].control_version=="pilot-v3","separate fresh economy authors an explicit unchanged legacy-v3 contract")
 var accepted:Dictionary=game.economy.accept_contract(str(game.economy.available_contracts()[0].contract_id))
 check(accepted.ok,"flight fixture accepts real contract")
 var cid:String=game.economy.active_contract_id;game.economy.mark_story_seen(cid,cid+"/accept");game.start_flight(true);tick();await neutral()
 check(game.page=="flight" and game.flight_order.control_version=="pilot-v3","controller retains current pilot protocol version")
 await axis(JOY_AXIS_LEFT_Y,-.61);await button(JOY_BUTTON_RIGHT_SHOULDER);await button(JOY_BUTTON_A)
 var command:Dictionary=game._pilot_input_state();check(command.axis_q==-500 and command.boost and command.active,"analog axis_q, funded boost and active circuit reach pilot input")
 for unused in 30:game._step_flight()
 var commands:Array=game.pilot_timeline.snapshot();check(commands[0].axis_q==-500 and commands[0].boost and commands[0].active,"fractional controller command records in existing sparse timeline")
 check(float(game.sim.telemetry.energy_used)>0 and float(game.sim.telemetry.energy_remaining)<float(game.sim.telemetry.battery_capacity),"held boost consumes real finite engine energy")
 var replay=game._simulation_for_version(str(game.flight_order.control_version));replay.configure(game.design.duplicate(true),game.launcher.duplicate(true),game.flight_order,int(game.flight_order.get("seed",game.economy.day*100)))
 var timeline=Timeline.new();check(timeline.restore(commands,game.pilot_completed_ticks),"existing replay accepts controller command stream")
 for n in game.pilot_completed_ticks:
  var saved:Dictionary=timeline.state_at(n);replay.set_pilot_input(saved.axis_q,saved.boost,saved.active);replay.step(1.0/60.0)
 check(replay.telemetry==game.sim.telemetry and replay.cargo_position()==game.sim.cargo_position(),"fractional pad timeline reproduces actual physics and energy exactly")
 await tap(JOY_BUTTON_START);check(game.paused and game._pilot_input_state()==Timeline.neutral(),"Menu pause clears all effective controller command state immediately")
 await tap(JOY_BUTTON_START);check(not game.paused and game._pilot_input_state()==Timeline.neutral(),"resume requires fresh axis neutral and button release")
 await neutral();await axis(JOY_AXIS_LEFT_Y,.61);check(game._pilot_input_state().axis_q==500,"neutral then fresh analog motion resumes steering")
 await button(JOY_BUTTON_DPAD_UP);check(game._pilot_input_state().axis_q==-1000,"D-pad flight steering overrides analog with bounded full axis")
 await neutral();await button(JOY_BUTTON_A);game._on_focus_exited();check(game.paused and game._pilot_input_state()==Timeline.neutral(),"focus loss pauses real flight and clears active circuit")
 await tap(JOY_BUTTON_START);await key(KEY_P);await key(KEY_P,false);check(game.paused,"both controller and keyboard events ignored while unfocused")
 game._on_focus_entered();await neutral();await tap(JOY_BUTTON_START);await axis(JOY_AXIS_LEFT_Y,-1);check(not game.paused and game._pilot_input_state().axis_q==-1000,"focused fresh controller input resumes normally")
 input._joy_connection_changed(0,false);check(game.paused and input.active_device==-1 and game._pilot_input_state()==Timeline.neutral(),"physical disconnect callback pauses and neutralizes active flight")
 check(input._buttons.is_empty() and input._axes.is_empty(),"disconnect clears held states from removed device")
 await neutral();await tap(JOY_BUTTON_START);await axis(JOY_AXIS_LEFT_Y,-.2);tick();check(game._pilot_input_state().axis_q==0,"sub-deadzone flight drift stays neutral")
 # Fixed retained UI, no per-tick controls/resources/tweens.
 var nodes:int=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT));var tweens:int=get_processed_tweens().size()
 for unused in 200:input.tick(.016)
 await settle();check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))<=nodes and get_processed_tweens().size()<=tweens,"200 adapter ticks retain no nodes or tweens")
 game.queue_free();await settle(5)
 if passed+failed!=59:check(false,"every controller assertion ran")
 print("COURIER_INPUT_LEGACY_V3_DEV03_R1 passed=%d failed=%d input=synthetic_InputEventJoypadMotion_Button physical_gamepad=false"%[passed,failed]);quit(1 if failed else 0)
