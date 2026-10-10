extends SceneTree
## Cosmetic prompt debounce must never delay real controller UI ownership.
## Synthesized Godot events, not physical controller hardware.
const EXPECTED_CHECKS:int=23
var game
var input
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=2) -> void:
 for unused in n:await process_frame
func key(code:int,pressed:bool=true) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event);await settle(1)
func button(code:int,pressed:bool=true) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=code;event.pressed=pressed;Input.parse_input_event(event);await settle(1)
func tap(code:int) -> void:await button(code);await button(code,false)
func keyboard_owner() -> void:
 input.tick(.5);input._set_device(true);input.tick(.5)
 await key(KEY_F8);await key(KEY_F8,false);input.tick(.01)
func release_focus() -> void:
 var owner:Control=root.gui_get_focus_owner()
 if owner!=null:owner.release_focus()
func native_focus_in(scope:Node) -> bool:
 var owner:Control=root.gui_get_focus_owner()
 return owner!=null and (scope==owner or scope.is_ancestor_of(owner)) and owner.is_visible_in_tree()
func assert_hysteresis(label:String) -> void:
 check(not input.gamepad and input.controller_navigation,"real controller owns "+label+" while prompts still show keyboard")
func find_control(id:String) -> Control:
 for child in game.hud.content.find_children("*","Control",true,false):
  if str(child.get_meta("view_key",""))==id:return child
 return null
func run() -> void:
 for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await settle(4)
 game.world.set_process(false);input=game.courier_input;input.tick(0)
 # Hub Menu: common context path, no special-case focus assignment.
 await keyboard_owner();release_focus();await tap(JOY_BUTTON_START)
 assert_hysteresis("hub menu")
 check(input.context=="ui" and native_focus_in(game.hud.content),"rapid pad Menu establishes hub native focus")
 await tap(JOY_BUTTON_B)
 # Workshop Menu opens a blocking settings sheet and preserves its safe default.
 game.navigate("workshop");input.tick(0);await settle();await keyboard_owner();release_focus();await tap(JOY_BUTTON_START)
 assert_hysteresis("workshop settings")
 check(input.context=="modal" and native_focus_in(input._focus_root()),"rapid pad Menu establishes settings modal focus")
 check(str(root.gui_get_focus_owner().get_meta("view_key",""))=="settings:done","settings keeps its safe close default under rapid device changes")
 await tap(JOY_BUTTON_B)
 # Grid back: a third distinct controller transition to navigable UI.
 await tap(JOY_BUTTON_X);await keyboard_owner();release_focus();await tap(JOY_BUTTON_B)
 assert_hysteresis("workbench menu")
 check(input.context=="ui" and native_focus_in(game.hud.content),"rapid pad Back establishes workbench menu focus")
 # A controller-selected UI action enters a dialogue in the same event.
 await keyboard_owner()
 var open_dialogue:=Button.new();open_dialogue.text="Test dialogue";game.hud.content.add_child(open_dialogue)
 open_dialogue.pressed.connect(func():game.dialogue.begin({"dialogue_id":"ownership-test","lines":[{"speaker":"npc","text":"测试。"}]},{},game.settings))
 open_dialogue.grab_focus();await tap(JOY_BUTTON_A)
 assert_hysteresis("dialogue")
 check(input.context=="dialogue" and native_focus_in(game.dialogue._root),"rapid controller selection establishes dialogue focus")
 check(root.gui_get_focus_owner()==game.dialogue._continue,"dialogue starts on continue without activating underlying UI")
 await tap(JOY_BUTTON_B);await settle();input.tick(0)
 # A formal confirmation uses the same owner and keeps cancellation selected.
 var cid:String=str(game.economy.available_contracts()[0].contract_id)
 game.economy.accept_contract(cid);game.economy.mark_story_seen(cid,cid+"/accept");game.render();game._ensure_cargo_loaded_for_launch();await settle();game.navigate("workshop");input.tick(0);await settle()
 await keyboard_owner()
 var dispatch:Control=find_control("action:dispatch:null");check(dispatch!=null,"dispatch confirmation control exists for ownership matrix")
 input._focus(dispatch);await tap(JOY_BUTTON_A)
 assert_hysteresis("dispatch confirmation")
 check(input.context=="modal" and native_focus_in(input._focus_root()),"rapid controller confirm establishes dispatch modal focus")
 check(str(root.gui_get_focus_owner().get_meta("view_key",""))=="dispatch:cancel","dispatch keeps safe cancel selected under rapid device changes")
 await tap(JOY_BUTTON_B)
 # Independent review repro: W selects keyboard labels, then Start inside .32 s.
 game.start_flight(true);input.tick(.5);await settle();input._set_device(true);input.tick(.5);release_focus()
 await key(KEY_W);await tap(JOY_BUTTON_START)
 assert_hysteresis("paused flight")
 check(game.paused and input.context=="flight_paused" and native_focus_in(game.hud.content),"rapid W to pad Start pauses with visible native focus")
 check(game._pilot_input_state()=={"axis_q":0,"boost":false,"active":false},"pause ownership change still clears held flight controls")
 await key(KEY_W,false);await tap(JOY_BUTTON_START);game.abort_flight();game.navigate("hub");input.tick(0);await settle()
 # Reverse case: cosmetic pad prompts can remain while keyboard owns interaction.
 input.tick(.5);input._set_device(true);await key(KEY_F8);await key(KEY_F8,false);release_focus()
 check(input.gamepad and not input.controller_navigation,"keyboard ownership changes immediately while pad prompts debounce")
 game.navigate("workshop");input.tick(.01);await settle()
 check(root.gui_get_focus_owner()==null,"keyboard workshop entry never auto-focuses navigation because pad prompts linger")
 var before:String=game.page;await key(KEY_SPACE);await key(KEY_SPACE,false)
 check(game.page==before,"fresh keyboard Space cannot activate an unsolicited post-cutscene navigation focus")
 # Mouse likewise relinquishes controller ownership without waiting for labels.
 await tap(JOY_BUTTON_START);await tap(JOY_BUTTON_B);input.tick(.5);input._set_device(true)
 var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=Vector2(640,310);mouse.pressed=true;Input.parse_input_event(mouse);await settle(1)
 mouse=mouse.duplicate();mouse.pressed=false;Input.parse_input_event(mouse);await settle(1)
 check(not input.controller_navigation,"mouse input immediately relinquishes controller navigation ownership")
 # Focus loss and disconnect cannot retain real controller navigation ownership.
 await tap(JOY_BUTTON_START);game._on_focus_exited()
 check(not input.controller_navigation and input.context=="inactive","focus loss releases controller navigation ownership")
 game._on_focus_entered();await button(JOY_BUTTON_START,false);await tap(JOY_BUTTON_B);input._joy_connection_changed(0,false)
 check(not input.controller_navigation and input.active_device==-1,"disconnect releases controller ownership independently of prompt labels")
 game.queue_free();await settle(5)
 if passed+failed!=EXPECTED_CHECKS:check(false,"every ownership matrix assertion ran")
 print("COURIER_INPUT_OWNERSHIP passed=%d failed=%d input=synthetic_InputEvent physical_gamepad=false"%[passed,failed]);quit(1 if failed else 0)
