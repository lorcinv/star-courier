extends SceneTree
## Live-controller checkbox contrast and selection through synthetic InputEvent
## routing. Rendered captures use the real shop; this is not OS pointer automation.
const EXPECTED_CHECKS=20
var game
var passed:int=0
var failed:int=0
var draw_modes:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 5:await process_frame
 for tween in game.hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
func by_text(node:Node,text:String) -> Button:
 if node is Button and node.text==text:return node
 for child in node.get_children():
  var found:=by_text(child,text)
  if found!=null:return found
 return null
func checkbox() -> CheckBox:return by_text(game.hud.content,"减少镜头动态") as CheckBox
func move(point:Vector2,held:bool=false) -> void:
 var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;root.push_input(event);await process_frame
func press(point:Vector2,down:bool) -> void:
 var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.pressed=down;root.push_input(event);await process_frame
func click(point:Vector2) -> void:
 await move(point);await press(point,true);await press(point,false);await settle()
func contrast(foreground:Color,background:Color) -> float:
 var f:=foreground.srgb_to_linear().get_luminance();var b:=background.srgb_to_linear().get_luminance()
 return (maxf(f,b)+.05)/(minf(f,b)+.05)
func inspect_state(name:String,selected:bool) -> void:
 var box:=checkbox();var draw_mode:int=box.get_draw_mode();draw_modes[draw_mode]=true
 var style_key:String={BaseButton.DRAW_NORMAL:"normal",BaseButton.DRAW_HOVER:"hover",BaseButton.DRAW_PRESSED:"pressed",BaseButton.DRAW_HOVER_PRESSED:"hover_pressed"}.get(draw_mode,"")
 var color_key:="font_color" if style_key=="normal" else "font_"+style_key+"_color"
 var style:=box.get_theme_stylebox(style_key) as StyleBoxFlat
 var ratio:=contrast(box.get_theme_color(color_key),style.bg_color) if style!=null else 0.0
 check(box.button_pressed==selected and bool(game.settings.reduced_motion)==selected,"InputEvent reaches expected toggle state: "+name)
 check(style!=null and style.bg_color.a==1.0 and ratio>=4.5,"readable text on actual %s draw surface: %s (%.2f:1)"%[style_key,name,ratio])
 if DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args():
  await RenderingServer.frame_post_draw
  var output:="res://docs/qa/v4/settings-checkbox-contrast/"
  DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
  root.get_texture().get_image().save_png(output+name+".png")
func run() -> void:
 root.size=Vector2i(1920,1080)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 if DisplayServer.get_name()!="headless":await create_timer(.8).timeout
 game.set_process(false);game.world.set_process(false)
 game.settings.reduced_motion=false;game.render();await settle()
 var density:String=game.settings.pixel_density;var canvas:Vector2i=game.view.size;var scale:Vector2=game.hud.root.scale
 await click(by_text(game.hud.content,"≡").get_global_rect().get_center())
 check(game.hud.settings_open,"physical InputEvent opens live settings")
 await move(Vector2(16,16));await inspect_state("01-unselected-normal",false)
 var center:=checkbox().get_global_rect().get_center()
 await move(center);await inspect_state("02-unselected-hover",false)
 await press(center,true);await inspect_state("03-unselected-held",false)
 await press(center,false);await settle();await inspect_state("04-selected-hover",true)
 await move(Vector2(16,16));await inspect_state("05-selected-normal",true)
 await move(center);await press(center,true);await inspect_state("06-selected-held",true)
 await press(center,false);await settle();await move(Vector2(16,16));await inspect_state("07-unselected-again",false)
 check(draw_modes.size()==4,"InputEvents exercised normal, hover, pressed and hover_pressed draw modes")
 check(not bool(game.economy.load_state().get("settings",{}).get("reduced_motion",true)),"second click persists the unselected setting")
 check(game.settings.pixel_density==density and game.view.size==canvas and game.hud.root.scale==scale,"checkbox gestures leave pixel density, world canvas and UI scale unchanged")
 await click(by_text(game.hud.content,"继续营业").get_global_rect().get_center())
 check(not game.hud.is_blocking_modal(),"settings closes normally after repeated checkbox toggles")
 game.music.stop();game.music.stream=null;game.sfx.stop();game.sfx.stream=null
 game.queue_free();for i in 5:await process_frame
 check(get_processed_tweens().is_empty(),"checkbox test teardown releases processed Tweens")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every contrast assertion ran")
 print("V4_SETTINGS_CONTRAST passed=%d failed=%d input=synthetic_physical_window_InputEvent"%[passed,failed]);quit(1 if failed else 0)
