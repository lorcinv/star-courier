extends SceneTree
## Context ownership/freshness and scaled presentation. All events synthesized.
var passed:int=0
var failed:int=0
var game
var input
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=2) -> void:
 for unused in n:await process_frame
func key(code:int,down:bool=true,echo:bool=false) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.echo=echo;Input.parse_input_event(event);await settle(1)
func button(code:int,down:bool=true) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=code;event.pressed=down;Input.parse_input_event(event);await settle(1)
func tap(code:int) -> void:await button(code);await button(code,false)
func focus_key(id:String) -> Control:
 for child in game.hud.content.find_children("*","Control",true,false):
  if str(child.get_meta("view_key",""))==id:input._focus(child);return child
 return null
func tick(delta:float=0) -> void:input.tick(delta)
func run() -> void:
 for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await settle(4)
 input=game.courier_input;game.world.set_process(false);tick()
 game.navigate("workshop");await settle();tick()
 var feet:Vector2=game.world.clerk.position
 await key(KEY_D);tick();check(game.page=="hub" and input.context=="shop" and input.shop_axis()==1,"fresh D closes nonmodal workbench and walks immediately")
 for unused in 5:tick(.04);game.world._process(.04)
 check(game.world.clerk.position.x>feet.x,"fresh D after drawer produces actual world displacement")
 await key(KEY_D,false);tick();game.navigate("contracts");await settle();tick()
 feet=game.world.clerk.position
 await key(KEY_A);tick();check(game.page=="hub" and input.shop_axis()==-1,"fresh A closes nonmodal counter drawer and walks immediately")
 for unused in 5:tick(.04);game.world._process(.04)
 check(game.world.clerk.position.x<feet.x,"fresh A after drawer produces actual world displacement")
 await key(KEY_A,false);tick();game.navigate("workshop");game.hud.settings_open=true;game.hud.render(game.hud.state);await settle();tick()
 await key(KEY_D);tick();check(game.page=="workshop" and game.hud.settings_open and input.shop_axis()==0,"D never closes settings or moves clerk through modal")
 game.hud.settings_open=false;game.hud.render(game.hud.state);tick();await key(KEY_D,true,true);tick()
 check(game.page=="workshop" and input.shop_axis()==0,"held D carried out of modal cannot close workbench or walk")
 await key(KEY_D,false);await key(KEY_D);tick();check(game.page=="hub" and input.shop_axis()==1,"released then fresh D works after modal barrier")
 await key(KEY_D,false);game.navigate("workshop");await settle();tick()
 var edit:=LineEdit.new();edit.size=Vector2(120,32);edit.focus_mode=Control.FOCUS_ALL;game.hud.content.add_child(edit);edit.grab_focus();await key(KEY_A);tick()
 check(game.page=="workshop" and input.shop_axis()==0,"text editor owns A without closing workbench")
 await key(KEY_A,false);edit.release_focus();edit.queue_free();await settle()
 var spin:=SpinBox.new();spin.size=Vector2(120,32);game.hud.content.add_child(spin);spin.get_line_edit().grab_focus();await key(KEY_D);tick()
 check(game.page=="workshop" and input.shop_axis()==0,"SpinBox text editor owns D without free-roam shortcut")
 await key(KEY_D,false);spin.get_line_edit().release_focus();spin.queue_free();await settle()
 input._set_device(true);await tap(JOY_BUTTON_X);tick();await key(KEY_D);tick()
 check(game.page=="hub" and input.shop_axis()==1 and not input._grid,"fresh keyboard movement also exits controller grid safely")
 await key(KEY_D,false);tick()
 # Real order accept, dialogue and loading skip via controller; no remote action.
 game._action("focus_counter",null);await settle();tick()
 for unused in 240:
  if game.page=="contracts":break
  tick(.04);game.world._process(.04);await settle(1)
 check(game.page=="contracts" and game.world.is_at_shop_counter(),"counter drawer opens only while actually at home counter")
 var cid:String=str(game.economy.available_contracts()[0].contract_id)
 var accept:=focus_key("action:accept_contract:"+JSON.stringify(cid));check(accept!=null,"order acceptance is reachable by native focus")
 await tap(JOY_BUTTON_A);tick()
 check(game.economy.active_contract_id==cid and game.dialogue.is_open(),"A accepts counter order and opens real customer dialogue")
 await button(JOY_BUTTON_B);tick();await settle();game._sync_loading_scene_ui();tick()
 check(not game.dialogue.is_open() and game._loading_scene_active(),"B ends dialogue into actual loading scene")
 var skips:int=game.loading_overlay._skip_count
 await button(JOY_BUTTON_B);tick();check(game.loading_overlay._skip_count==skips,"held B from dialogue cannot skip newly opened loading scene")
 await button(JOY_BUTTON_B,false);await tap(JOY_BUTTON_B);await settle(3);tick()
 check(game.loading_overlay._skip_count==skips+1 and game.economy.is_cargo_loaded() and game.page=="workshop","fresh B skips loading exactly once and reaches usable workbench")
 var count:int=game.design.size();await button(JOY_BUTTON_X);tick();await button(JOY_BUTTON_X,false);await button(JOY_BUTTON_A);tick();await button(JOY_BUTTON_A)
 check(game.design.size()<=count+1,"duplicate held confirm never places repeated workshop parts")
 await button(JOY_BUTTON_A,false);await tap(JOY_BUTTON_B);tick()
 # Dispatch modal must select safe cancel first, then remain fully navigable.
 game.hud._act("dispatch");await settle();tick();check(game.hud.dispatch_confirmation_open,"formal dispatch confirmation opens")
 check(str(root.gui_get_focus_owner().get_meta("view_key",""))=="dispatch:cancel","controller modal starts on nonbinding safe cancel")
 await key(KEY_D);tick();check(game.hud.dispatch_confirmation_open and game.page=="workshop","A/D cannot dismiss dispatch confirmation")
 await key(KEY_D,false);await tap(JOY_BUTTON_B);tick();check(not game.hud.dispatch_confirmation_open,"B cancels formal dispatch without launching or charging")
 # Stale move transactions and out-of-tier retained-part recovery.
 await tap(JOY_BUTTON_X);tick();var outside:Dictionary=game.part(900,"beam",9,3);game.design.append(outside);game.selected_id=int(game.design[game.design.size()-2].id)
 await tap(JOY_BUTTON_LEFT_STICK);tick();check(game.selected_id==900 and game.workshop_input.controller_cell==Vector2i(9,3),"L3 reaches retained legacy part outside paid grid")
 await tap(JOY_BUTTON_Y);game.workshop_input.controller_cell=Vector2i(-4,-2);await tap(JOY_BUTTON_A);tick()
 check(game.selected_part().x==-4 and game.selected_part().y==-2,"controller recovers out-of-tier source into allowed cell")
 await tap(JOY_BUTTON_Y);var selected:Dictionary=game.selected_part();selected.rot=posmod(int(selected.rot)+1,4);game.workshop_input.controller_cell=Vector2i(-3,-2);await tap(JOY_BUTTON_A);tick()
 check(game.selected_part().x==-4 and not game.workshop_input.controller_moving(),"changed structure invalidates stale pickup without moving a part")
 # Modal/resize/assembly transitions invalidate controller transactions.
 game.workshop_input.controller_cell=Vector2i(-4,-2);await tap(JOY_BUTTON_Y);tick()
 check(input._hint.text.contains("取消搬动") and input._hint.text.contains(str(game.catalog.beam.name)),"pending pickup shows module name and place/cancel prompts")
 var snapshot:Array=game.design.duplicate(true);game._on_art_frame_changed(game.view_container.display_rect);tick()
 check(not game.workshop_input.controller_moving() and game.design==snapshot,"resize cancels pickup without placing or debiting")
 await tap(JOY_BUTTON_Y);game.hud.settings_open=true;game.hud.render(game.hud.state);tick()
 check(not game.workshop_input.controller_moving() and game.design==snapshot,"modal opening cancels pending pickup without mutation")
 await tap(JOY_BUTTON_B);tick();await tap(JOY_BUTTON_Y);game._on_focus_exited();tick()
 check(not game.workshop_input.controller_moving() and game.design==snapshot,"focus loss cancels pending pickup without mutation")
 game._on_focus_entered();await button(JOY_BUTTON_Y,false);tick();await tap(JOY_BUTTON_Y);game.assembly_mode="launcher";game.render();tick()
 check(not game.workshop_input.controller_moving() and game.design==snapshot,"assembly switch cancels pending pickup without mutation")
 game.assembly_mode="craft";game.render();tick()
 # Real window/art-frame transformations and concise text at three densities.
 input._set_device(true)
 for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle(4);game._on_art_frame_changed(game.view_container.display_rect);await settle();tick()
  var snap:Dictionary=input.debug_snapshot();var frame:Rect2=game.view_container.display_rect
  check(frame.encloses(snap.hint_rect),"action strip fits art frame "+str(extent))
  check(float(snap.hint_scale)==float(clampi(floori(frame.size.y/720.0),1,3)),"action strip uses HUD integer scale "+str(extent))
  var font:Font=input._hint.get_theme_font("font");var text_width:float=font.get_string_size(input._hint.text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
  check(text_width<=input._hint.size.x,"compact grid labels fit without clipping "+str(extent))
  check(not bool(snap.cursor_visible) or frame.encloses(snap.cursor_rect),"grid cursor remains within art frame "+str(extent))
 game.navigate("hub");tick();check(input._hint.text in ["A 前台","E 前台",""],"shop shows only nearby action with no permanent tutorial line")
 game.queue_free();await settle(5)
 if passed+failed!=42:check(false,"every controller assertion ran")
 print("COURIER_CONTEXTS passed=%d failed=%d input=synthetic_InputEvent physical_gamepad=false"%[passed,failed]);quit(1 if failed else 0)
