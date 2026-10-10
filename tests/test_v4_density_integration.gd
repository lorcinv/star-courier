extends SceneTree
## Synthetic InputEvent GUI routing and real Window resize notifications.
## This is NOT OS/XTest pointer automation. All saves use the caller's fresh XDG.
const EXPECTED_CHECKS=46
## Density/input guarantees survive the v5 renderer; replay the current profile.
const Sim=preload("res://scripts/pilot_ascent_simulation.gd")
var game
var passed:int=0
var failed:int=0
var drag_started:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle(frames:int=5) -> void:
 for i in range(frames):await process_frame
 if is_instance_valid(game):
  for tween in game.hud._motion_tweens.values():
   if tween.is_valid():tween.custom_step(1.0)
func by_text(node:Node,text:String) -> Button:
 if node is Button and node.text==text:return node
 for child in node.get_children():
  var found:=by_text(child,text)
  if found!=null:return found
 return null
func slider(node:Node) -> HSlider:
 if node is HSlider:return node
 for child in node.get_children():
  var found:=slider(child)
  if found!=null:return found
 return null
func modal_panel() -> Control:
 for node in game.hud.content.get_children():
  if node.has_meta("modal_panel"):return node
 return null
func dimmer() -> ColorRect:
 for node in game.hud.content.get_children():
  if node is ColorRect:return node
 return null
func move(point:Vector2,held:bool=false) -> void:
 var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;root.push_input(event);await process_frame
func press(point:Vector2,down:bool) -> void:
 var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.pressed=down;root.push_input(event);await process_frame
func click(point:Vector2) -> void:
 await move(point);await press(point,true);await press(point,false)
func key(code:int) -> void:
 for down in [true,false]:
  var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event);await process_frame
func resize_window(extent:Vector2i) -> void:
 root.size=extent;await settle()
func sim_state(sim) -> String:
 return JSON.stringify({"elapsed":sim.elapsed,"parts":sim.parts,"bodies":sim.bodies,"links":sim.links,"events":sim.events,"telemetry":sim.telemetry,"status":sim.status,"route":sim.route,"seed":sim.seed_value})
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 # This historical resize/replay fixture deliberately uses frozen pilot-v2.
 game.economy.enable_ascent_mode();game.render()
 await resize_window(Vector2i(1440,900))
 check(game.settings.pixel_density=="auto","fresh game defaults to automatic pixel density")
 check(game.view.size==Vector2i(1280,720),"1440×900 automatic mode uses the sharpest integer-fit canvas")
 game._action("settings",{"pixel_density":"balanced"});await settle()
 check(game.settings.pixel_density=="balanced" and game.view.size==Vector2i(640,360),"controller applies balanced density at1440×900")
 var saved:Dictionary=game.economy.load_state()
 check(saved.get("settings",{}).get("pixel_density","")=="balanced","pixel-density choice persists in the game-written save")
 game._action("settings",{"pixel_density":"invalid"});await settle()
 check(game.settings.pixel_density=="auto" and game.economy.load_state().get("settings",{}).get("pixel_density","")=="auto","invalid persisted/controller density normalizes to auto")
 game.settings.reduced_motion=true
 game.economy.accept_contract("D1-A");game.navigate("workshop");game.selected_id=2;game.render();await settle()
 var design_before:String=JSON.stringify(game.design)
 for modal in ["settings","dispatch"]:
  var opener:=by_text(game.hud.content,"≡" if modal=="settings" else "发射配送  ↗")
  await click(opener.get_global_rect().get_center());await settle()
  check(game.hud.is_blocking_modal() and (game.hud.settings_open if modal=="settings" else game.hud.dispatch_confirmation_open),"InputEvent click opens "+modal+" modal")
  for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(1366,768),Vector2i(1440,900)]:
   await resize_window(extent)
   var frame:Rect2=game.view_container.display_rect
   check(game.hud.root.get_global_rect()==frame and dimmer().get_global_rect()==frame,modal+" dimmer follows density/letterbox resize to "+str(extent))
   check(frame.encloses(modal_panel().get_global_rect()) and game.hud.root.scale==Vector2.ONE,modal+" controls remain fully visible at native size "+str(extent))
   await key(KEY_R);await key(KEY_DELETE);await click(frame.get_center())
   check(JSON.stringify(game.design)==design_before and game.hud.is_blocking_modal(),modal+" blocks keys and scene clicks after resize "+str(extent))
  var close:=by_text(game.hud.content,"×" if modal=="settings" else "再检查一下")
  await click(close.get_global_rect().get_center());await settle()
  check(not game.hud.is_blocking_modal() and game.sim==null,"closing resized "+modal+" leaves editing enabled without accidental launch")
 # Hold the real Slider GUI drag across a density-selecting resize.
 await click(by_text(game.hud.content,"≡").get_global_rect().get_center());await settle()
 var volume:=slider(game.hud.content);volume.drag_started.connect(func():drag_started+=1)
 var initial_volume:float=game.settings.volume
 var start:Vector2=volume.get_global_rect().position+Vector2(volume.size.x*.5,volume.size.y*.5)
 await move(start);await press(start,true);await move(start+Vector2(80,0),true)
 check(drag_started==1 and not is_equal_approx(float(game.settings.volume),initial_volume),"synthetic held pointer starts and changes the actual volume Slider")
 var held_volume:float=game.settings.volume;var old_slider:WeakRef=weakref(volume)
 await resize_window(Vector2i(1920,1080))
 await move(game.view_container.display_rect.get_center()+Vector2(-360,0),true);await press(game.view_container.display_rect.get_center()+Vector2(-360,0),false);await settle()
 check(old_slider.get_ref()==null and game.hud.settings_open,"resize releases the old held Slider without dismissing settings")
 check(is_equal_approx(float(game.settings.volume),held_volume) and is_equal_approx(slider(game.hud.content).value,held_volume),"held-drag resize retains the committed volume without a ghost update")
 check(JSON.stringify(game.design)==design_before and game.sim==null,"held-drag move/release cannot edit or launch the scene behind settings")
 volume=slider(game.hud.content);var next_point:Vector2=volume.get_global_rect().position+Vector2(volume.size.x*.25,volume.size.y*.5)
 await click(next_point);await settle()
 check(is_finite(float(game.settings.volume)) and not is_equal_approx(float(game.settings.volume),held_volume),"replacement Slider accepts a fresh gesture after interrupted drag")
 check(is_equal_approx(float(game.economy.load_state().get("settings",{}).get("volume",-1)),float(game.settings.volume)),"post-resize Slider value is persisted")
 await click(by_text(game.hud.content,"×").get_global_rect().get_center());await settle()
 # A real continuously processed flight, then a same-tick deterministic replay.
 game.start_flight(true);await settle()
 var replay:=Sim.new();replay.configure(game.design.duplicate(true),game.launcher.duplicate(true),game.flight_order.duplicate(true),game.sim.seed_value)
 var craft_before:String=JSON.stringify(game.design);var credits_before:int=game.economy.credits
 game.set_process(true);await create_timer(1.0).timeout
 var previous_elapsed:float=game.sim.elapsed
 check(previous_elapsed>0 and game.sim.status=="running","running trial advances through actual process callbacks before resize")
 for pair in [[Vector2i(1280,800),"low"],[Vector2i(1920,1080),"balanced"],[Vector2i(1366,768),"auto"]]:
  game._action("settings",{"pixel_density":pair[1]});await resize_window(pair[0]);await create_timer(.16).timeout
  check(game.sim.elapsed>previous_elapsed and game.sim.status=="running","flight continues without reset across "+str(pair[1])+" density / resize")
  previous_elapsed=game.sim.elapsed
 game.set_process(false)
 var steps:int=roundi(game.sim.elapsed*60.0)
 for i in steps:replay.step(1.0/60.0)
 check(sim_state(game.sim)==sim_state(replay),"running resized flight exactly matches a same-tick replay with no UI/density changes")
 check(JSON.stringify(game.design)==craft_before and game.economy.credits==credits_before,"density changes do not change assembly or charge a free trial")
 var physics_before:String=sim_state(game.sim)
 for mode in ["low","balanced","auto"]:game._action("settings",{"pixel_density":mode});await settle()
 check(sim_state(game.sim)==physics_before,"density changes alone do not step or mutate the frozen simulation")
 game.music.stop();game.music.stream=null;game.sfx.stop();game.sfx.stream=null;game.queue_free();await settle()
 if passed+failed!=EXPECTED_CHECKS:check(false,"every expected integration assertion ran")
 print("V4_DENSITY_INTEGRATION passed=%d failed=%d input=synthetic_InputEvent_window_resize"%[passed,failed]);quit(1 if failed else 0)
