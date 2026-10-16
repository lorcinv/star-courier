extends SceneTree
## Signal-level regression. Run this exact file against old and guarded HUD.
## No native pointer, physical keyboard, screenshot, or raster-quality claim.
const HUD=preload("res://scripts/game_hud.gd")
const PHONE_TEXTURE=preload("res://assets/2d_v5/reviews/customer-review-phone-ninepatch-source.png")
var passed:int=0
var failed:int=0
var hud
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func feedback_key(button:Button) -> String:return str(button.get_instance_id())+":feedback"
func exercise(button:Button,label:String,reduced:bool) -> void:
 hud.state={"settings":{"reduced_motion":reduced}}
 var pressed:StyleBox=button.get_theme_stylebox("pressed")
 var hover:StyleBox=button.get_theme_stylebox("hover")
 button.button_down.emit()
 if not pressed is StyleBoxFlat or reduced:
  check(not hud._motion_tweens.has(feedback_key(button)),label+" down skips unavailable/reduced flat effect")
 else:
  check(hud._motion_tweens.has(feedback_key(button)),label+" flat down has feedback tween")
  hud._motion_tweens[feedback_key(button)].custom_step(.1)
  check(is_equal_approx(pressed.expand_margin_left,-2.0),label+" flat press still contracts")
 button.button_up.emit()
 if pressed is StyleBoxFlat:
  check(pressed.expand_margin_left==0.0 and pressed.expand_margin_right==0.0 and pressed.expand_margin_top==0.0 and pressed.shadow_offset==Vector2(4,5),label+" up restores flat pressed properties")
 if hover is StyleBoxFlat and not reduced:
  check(hud._motion_tweens.has(feedback_key(button)),label+" flat hover retains release feedback")
  hud._motion_tweens[feedback_key(button)].custom_step(.2)
  check(hover.shadow_offset==Vector2(4,5),label+" flat hover settles")
 else:
  check(not hud._motion_tweens.has(feedback_key(button)),label+" up skips unavailable/reduced flat effect")
 check(button.get_theme_stylebox("pressed")==pressed and button.get_theme_stylebox("hover")==hover,label+" signal handlers preserve selected skins")
 hud._stop_motion()
func run() -> void:
 hud=HUD.new();root.add_child(hud);hud.set_process(false)
 hud._phone_launcher()
 var launcher:Button=hud.content.get_node("PhoneLauncher")
 var pressed:StyleBox=launcher.get_theme_stylebox("pressed")
 var hover:StyleBox=launcher.get_theme_stylebox("hover")
 var normal:StyleBox=launcher.get_theme_stylebox("normal")
 var disabled:StyleBox=launcher.get_theme_stylebox("disabled")
 var casing:TextureRect
 var screen:ColorRect
 for node in launcher.get_children():
  if node is TextureRect and node.texture==PHONE_TEXTURE:casing=node
  if node is ColorRect:screen=node
 hud._wire_motion_feedback(launcher)
 check(launcher.get_theme_stylebox("pressed")==pressed and launcher.get_theme_stylebox("hover")==hover and pressed is StyleBoxEmpty and hover is StyleBoxEmpty,"phone keeps exact empty skins after wiring")
 check(launcher.get_theme_stylebox("normal")==normal and launcher.get_theme_stylebox("disabled")==disabled and casing!=null and casing.texture==PHONE_TEXTURE,"phone raster casing and ordinary Button states stay intact")
 if screen!=null:
  launcher.mouse_entered.emit();check(screen.color==HUD.BLUE,"phone custom mouse hover still works")
  launcher.mouse_exited.emit();check(screen.color==HUD.PANEL_LIGHT,"phone custom mouse exit still works")
 for reduced in [false,true]:exercise(launcher,"phone reduced="+str(reduced),reduced)
 for kind in ["texture","flat","mixed"]:
  var button:=Button.new();hud.content.add_child(button)
  var p:StyleBox=StyleBoxFlat.new() if kind!="texture" else StyleBoxTexture.new()
  var h:StyleBox=StyleBoxFlat.new() if kind=="flat" else StyleBoxTexture.new()
  if p is StyleBoxTexture:p.texture=PHONE_TEXTURE
  if h is StyleBoxTexture:h.texture=PHONE_TEXTURE
  button.add_theme_stylebox_override("pressed",p);button.add_theme_stylebox_override("hover",h)
  hud._wire_motion_feedback(button);hud._wire_motion_feedback(button)
  check(button.button_down.get_connections().size()==1 and button.button_up.get_connections().size()==1,kind+" wiring stays idempotent")
  check((button.get_theme_stylebox("pressed")!=p if p is StyleBoxFlat else button.get_theme_stylebox("pressed")==p) and (button.get_theme_stylebox("hover")!=h if h is StyleBoxFlat else button.get_theme_stylebox("hover")==h),kind+" duplicates only mutable flat styles")
  for reduced in [false,true]:exercise(button,kind+" reduced="+str(reduced),reduced)
 hud.queue_free();await process_frame;await process_frame
 print("HUD_SKIN_MOTION_FEEDBACK passed=%d failed=%d signal_level=true native_pointer=false"%[passed,failed])
 quit(1 if failed else 0)
