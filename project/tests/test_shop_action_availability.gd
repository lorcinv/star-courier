extends SceneTree
## Real Main/HUD/input/world. Explicit world states + synthetic InputEvents;
## no OS mouse or physical gamepad claim. Run with isolated XDG_DATA_HOME.
var passed:int=0
var failed:int=0
var game
var input
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func frames(count:int=3) -> void:
 for unused in count:await process_frame
func button_for(action:String) -> Button:
 for button in game.hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("view_key","")).begins_with("action:"+action+":"):return button
 return null
func sync() -> void:
 game._sync_shop_action_availability();input.tick(0)
func key(code:int,down:bool=true) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
 Input.parse_input_event(event);await frames(1)
func joy(code:int,down:bool=true) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=code;event.pressed=down
 Input.parse_input_event(event);await frames(1)
func step(seconds:float) -> void:
 for unused in ceili(seconds*120):
  input.tick(1.0/120.0);game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0);game._sync_shop_action_availability()
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("ISOLATED XDG_DATA_HOME REQUIRED");quit(2);return
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await frames(4)
 game.world.set_process(false);game.world.assembly_feedback.set_process(false);input=game.courier_input;sync()
 var counter:Button=button_for("focus_counter");var phone:Button=button_for("customer_reviews")
 check(counter!=null and not counter.disabled and phone!=null and not phone.disabled,"fresh counter and phone expose real availability")
 var render_generation:int=game.hud._render_generation
 var counter_id:int=counter.get_instance_id()
 for unused in 120:sync()
 check(game.hud._render_generation==render_generation and button_for("focus_counter").get_instance_id()==counter_id,"steady availability performs no full HUD rebuild")
 var before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var credits:int=game.economy.credits;var design:Array=game.design.duplicate(true)
 counter.grab_focus();game.world._clerk_return_requested=true;sync()
 check(counter.disabled and counter.focus_mode==Control.FOCUS_NONE,"scripted return disables counter and removes it from Tab order")
 check(root.gui_get_focus_owner()!=counter and root.gui_get_focus_owner()!=null,"disabling a focused counter moves focus to an enabled control")
 check(phone.disabled,"phone follows its own return-owner predicate")
 check(not button_for("focus_workbench").disabled and not button_for("focus_supply").disabled and not button_for("help").disabled and not button_for("_settings").disabled,"return does not blanket-disable workbench supplies help or settings")
 for unused in 8:counter.pressed.emit()
 check(game.page=="hub" and game.world._shop_navigation.is_empty() and game.economy.active_contract_id.is_empty(),"disabled repeated counter intents queue no navigation or acceptance")
 check(input._hint.text.is_empty(),"return ownership hides the nearby E/A counter prompt")
 check(game.hud._render_generation==render_generation,"return transition changes disabled state in place")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;await frames(4);sync()
  check(button_for("focus_counter").disabled and button_for("customer_reviews").disabled,"resize preserves owner availability at "+str(extent))
 game.hud.settings_open=true;game.hud.render(game.hud.state);await frames();sync()
 var modal_focus:Control=root.gui_get_focus_owner()
 game.world._clerk_return_requested=false;sync()
 check(game.hud.settings_open and root.gui_get_focus_owner()==modal_focus and button_for("focus_counter").disabled,"owner release under settings does not steal modal focus or enable background counter")
 game.hud.settings_open=false;game.hud.render(game.hud.state);await frames();sync()
 check(not button_for("focus_counter").disabled and not button_for("customer_reviews").disabled,"closing settings restores live counter and phone")
 check(game._open_review_phone(),"phone can acquire its real owner")
 sync();var phone_focus:Control=root.gui_get_focus_owner()
 check(button_for("focus_counter").disabled and game.review_phone.focus_root().is_ancestor_of(phone_focus),"phone ownership disables background counter without taking phone focus")
 game._close_review_phone();sync();await frames()
 check(not button_for("focus_counter").disabled and not button_for("customer_reviews").disabled,"phone release restores actions")
 game.dialogue.begin({"dialogue_id":"availability-probe","lines":[{"speaker":"npc","text":"测试。"}]},{},game.settings);sync()
 check(button_for("focus_counter").disabled and button_for("customer_reviews").disabled,"real dialogue ownership gates counter and phone")
 game.dialogue.cancel(false);sync()
 check(not button_for("focus_counter").disabled,"dialogue dismissal restores counter")
 for guard in ["_review_phone_owner","_investigation_owner","_scene_paused","_focus_active"]:
  var previous:Variant=game.world.get(guard)
  game.world.set(guard,false if guard=="_focus_active" else (123 if guard.ends_with("owner") else true));sync()
  check(button_for("focus_counter").disabled,"world authoritative guard reaches HUD: "+guard)
  game.world.set(guard,previous);sync()
  check(not button_for("focus_counter").disabled,"world guard release restores HUD: "+guard)
 var phase:String=game.world._parcel_phase
 game.world._parcel_phase="counter_transfer";sync()
 check(button_for("focus_counter").disabled and input._hint.text.is_empty(),"counter-transfer guard also suppresses native input prompt")
 game.world._parcel_phase=phase;sync()
 game.world.night=true;sync()
 check(button_for("focus_counter").disabled and not button_for("customer_reviews").disabled,"closed counter station does not disable otherwise available phone")
 game.world.night=false;sync()
 # Start a genuine walk, then transfer ownership to the existing return path.
 game.world.set_shop_input(0,true)
 for unused in 150:game.world.set_shop_input(1,true);game.world._process(1.0/120.0)
 game.world.set_shop_input(0,true);sync()
 check(not game.world.is_at_shop_counter() and not button_for("focus_counter").disabled,"distant counter is still a valid physical navigation intent")
 check(not game.world.prepare_counter_interaction(),"roaming clerk starts real scripted return")
 sync();check(button_for("focus_counter").disabled,"real return path disables counter until ownership ends")
 step(10)
 check(game.world.is_at_shop_counter() and not button_for("focus_counter").disabled,"return settles at exact counter and restores action without rebuilding")
 # Navigation from a report is projected read-only before Main closes it.
 game.navigate("report");await frames();sync()
 var at:Vector2=game.world.clerk.position
 check(not button_for("next_contract").disabled and game.world.mode=="report" and game.world.clerk.position==at,"report next-contract predicate does not mutate world mode or clerk position")
 game.world._clerk_return_requested=true;sync()
 check(button_for("next_contract").disabled and not button_for("close_drawer").disabled,"report next-contract disabled while return-to-shop remains independent")
 game.world._clerk_return_requested=false;sync();button_for("next_contract").pressed.emit();await frames();sync()
 check(game.page=="contracts" and game.world.is_at_shop_counter(),"enabled next-contract still opens counter at actual home")
 var accept:Button=button_for("accept_contract")
 check(accept!=null and not accept.disabled,"counter acceptance available at exact home")
 game.world.clerk.position.x+=1;sync()
 check(accept.disabled,"accept is disabled outside the exact counter tolerance")
 for unused in 5:accept.pressed.emit()
 check(game.economy.active_contract_id.is_empty(),"disabled accept never queues or commits a contract")
 game.world.clerk.position.x-=1;sync()
 check(not accept.disabled,"exact proximity restoration re-enables accept")
 var snapshot:Dictionary=game.hud.state.duplicate(true)
 snapshot.contracts[0].locked=true;game.hud.render(snapshot);sync()
 check(button_for("accept_contract").disabled,"availability cannot unlock a reputation-locked contract")
 game.render();await frames();sync()
 check(game.economy.credits==credits and game.design==design and FileAccess.get_file_as_bytes("user://savegame.json")==before,"availability-only flow preserves money design and durable save bytes")
 # Real asynchronous navigation must survive the presentation update.
 game.navigate("hub");input._hub_ui=false;input.synchronize();game.world.set_shop_input(0,true)
 for unused in 150:game.world.set_shop_input(1,true);game.world._process(1.0/120.0)
 game.world.set_shop_input(0,true);sync();button_for("focus_counter").pressed.emit()
 check(game.page=="hub" and game.world._shop_navigation=="focus_counter","enabled distant click starts existing physical route")
 step(10);await frames();sync()
 check(game.page=="contracts" and game.world.is_at_shop_counter(),"availability refresh does not cancel accepted navigation or block arrival callback")
 # Synthetic keyboard and controller navigation skips disabled acceptance.
 game.world._clerk_return_requested=true;sync();await key(KEY_TAB);await key(KEY_TAB,false)
 var owner:Control=root.gui_get_focus_owner()
 check(not (owner is BaseButton and owner.disabled),"keyboard Tab does not focus disabled accept")
 input.controller_navigation=true;input.ensure_focus();input._navigate(Vector2i.DOWN)
 owner=root.gui_get_focus_owner()
 check(owner!=null and not (owner is BaseButton and owner.disabled),"controller navigation retains an enabled focus target")
 game.world._clerk_return_requested=false;sync()
 game.queue_free();await frames(5)
 print("SHOP_ACTION_AVAILABILITY passed=%d failed=%d native_input=false physical_gamepad=false"%[passed,failed]);quit(1 if failed else 0)
