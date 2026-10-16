extends SceneTree
## Integer HUD scale and physical-window InputEvent hit testing, including the
## embedded native PopupMenu. This is not OS/XTest pointer automation.
const EXPECTED_CHECKS=54
const HUD=preload("res://scripts/game_hud.gd")
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
var background_clicks:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 5:await process_frame
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
func click(point:Vector2) -> void:
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion)
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event);await process_frame
func by_text(node:Node,text:String) -> Button:
 if node is Button and node.text==text:return node
 for child in node.get_children():
  var result:=by_text(child,text)
  if result!=null:return result
 return null
func density_option() -> OptionButton:
 for node in hud.content.find_children("*","OptionButton",true,false):
  if node.get_item_text(0)=="自动清晰":return node
 return null
func dimmer() -> ColorRect:
 for node in hud.content.get_children():
  if node is ColorRect:return node
 return null
func modal_panel() -> Control:
 for node in hud.content.get_children():
  if node.has_meta("modal_panel"):return node
 return null
func dock() -> Button:
 for node in hud.content.get_children():
  if node is Button and node.tooltip_text=="接下今天的托付":return node
 return null
func set_frame(frame:Rect2,window_size:Vector2i) -> void:
 root.size=window_size;hud.set_art_frame(frame);hud.render(hud.state);await settle()
func all_clicks(event:InputEvent) -> void:
 if event is InputEventMouseButton and event.pressed:background_clicks+=1
func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])
func capture(name:String) -> void:
 if DisplayServer.get_name()=="headless":return
 if not "--capture" in OS.get_cmdline_user_args():return
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/v4/hud-integer-scale"))
 root.get_texture().get_image().save_png("res://docs/qa/v4/hud-integer-scale/"+name+".png")
func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(3840,2160)
 var underlay:=ColorRect.new();underlay.color=Color("455d73");underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);underlay.gui_input.connect(all_clicks);root.add_child(underlay)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action)
 hud.render({"mode":"hub","day":1,"credits":260,"settings":{"reduced_motion":true,"pixel_density":"auto"},"has_accepted_contract":true,"activeorder":{"name":"晨星社区","cargo":"耐寒种子","distance":64,"required":85,"deadline":14,"contract_id":"scale-test"}});await settle()
 check(hud.root.scale==Vector2.ONE and hud._size==Vector2(3840,2160),"unconfigured4K HUD preserves the legacy unscaled behavior")
 var covered:=true
 for character in FileAccess.get_file_as_string("res://scripts/game_hud.gd"):
  if character.unicode_at(0)>127:covered=covered and hud.root.theme.default_font.has_char(character.unicode_at(0))
 check(covered,"imported font covers every non-ASCII HUD source character")
 for spec in [[Vector2i(2560,1440),2],[Vector2i(3840,2160),3]]:
  var extent:Vector2i=spec[0];var factor:int=spec[1];var frame:=Rect2(Vector2.ZERO,Vector2(extent));var label:="%d× at %s"%[factor,extent]
  hud.state.mode="hub";hud.state.settings.pixel_density="auto";actions.clear();await set_frame(frame,extent)
  check(hud._ui_scale==factor and hud.root.scale==Vector2.ONE*factor,"deliberate integer root scale: "+label)
  check(hud.root.get_global_rect()==frame and hud.content.get_global_rect()==frame,"physical root/content art bounds unchanged: "+label)
  check(hud._size==Vector2(1280,720) and hud.root.size==Vector2(1280,720),"logical layout divides by integer UI scale: "+label)
  check(hud.root.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"font/icon sampling is crisp nearest at "+label)
  check(frame.encloses(dock().get_global_rect()) and dock().get_global_rect().size==Vector2(164,48)*factor,"dock keeps readable integer-scaled size and in-frame bounds: "+label)
  await click(dock().get_global_rect().get_center())
  check(actions==[["focus_counter",null]],"physical pointer hits scaled dock exactly once: "+label)
  hud.toast("新提示")
  check(frame.encloses(hud.toast_panel.get_global_rect()),"toast stays within physical art bounds: "+label)
  await capture("hub-%d"%extent.y)
  await click(by_text(hud.content,"≡").get_global_rect().get_center());await settle()
  check(hud.settings_open and hud.is_blocking_modal(),"physical pointer opens scaled settings: "+label)
  check(dimmer().get_global_rect()==frame and frame.encloses(modal_panel().get_global_rect()),"settings dimmer and panel align with art bounds: "+label)
  var option:=density_option();await click(option.get_global_rect().get_center());await settle()
  var popup:=option.get_popup()
  check(popup.visible and is_equal_approx(popup.content_scale_factor,float(factor)),"embedded setting popup inherits the exact integer scale: "+label)
  var popup_position:Vector2=Vector2(popup.position)
  if not popup.is_embedded():popup_position-=Vector2(root.position)
  check(frame.encloses(Rect2(popup_position,Vector2(popup.size))),"setting popup fits the physical art frame: "+label)
  # Push physical parent-window coordinates. Godot routes them through its
  # embedded PopupMenu and inverse scale, without emitting selection signals.
  await click(popup_position+Vector2(popup.size)*Vector2(.5,.84));await settle()
  check(option.selected==2 and hud.state.settings.pixel_density=="low" and actions.back()==["settings",{"pixel_density":"low"}],"physical pointer selects the scaled density option: "+label)
  await capture("settings-%d"%extent.y)
  await set_frame(Rect2(0,0,1280,720),Vector2i(1280,720))
  check(hud.settings_open and hud.root.scale==Vector2.ONE and dimmer().get_global_rect()==Rect2(0,0,1280,720),"resize back keeps settings open and restores1× bounds: "+label)
  check(density_option().selected==2,"selected setting survives resize back from "+label)
  await click(by_text(hud.content,"×").get_global_rect().get_center());await settle()
  check(not hud.is_blocking_modal(),"resized settings closes at its new native pointer coordinates: "+label)
  hud.state.mode="workshop";await set_frame(frame,extent)
  await click(by_text(hud.content,"发射配送  ↗").get_global_rect().get_center());await settle()
  check(hud.dispatch_confirmation_open and dimmer().get_global_rect()==frame and frame.encloses(modal_panel().get_global_rect()),"scaled dispatch opens with correct art-frame bounds: "+label)
  var before:int=background_clicks;await click(Vector2(30,frame.size.y*.5))
  check(background_clicks==before and hud.dispatch_confirmation_open,"scaled dispatch blocks scene pointer events: "+label)
  await set_frame(Rect2(80,90,1280,720),Vector2i(1440,900))
  check(hud.dispatch_confirmation_open and hud.root.scale==Vector2.ONE and dimmer().get_global_rect()==Rect2(80,90,1280,720),"resize back preserves dispatch in the centered1× art frame: "+label)
  await click(by_text(hud.content,"再检查一下").get_global_rect().get_center());await settle()
  check(not hud.is_blocking_modal(),"resized dispatch cancel clears its guard: "+label)
  hud.state.mode="flight";await set_frame(frame,extent);hud.update_launch(.4,"charge");await settle()
  check(frame.encloses(hud._launch_layer.get_global_rect()) and hud._launch_layer.get_global_rect().size.is_equal_approx(Vector2(464,112)*factor),"launch ribbon preserves logical dimensions and scales inside frame: "+label)
  check(hud._launch_layer.mouse_filter==Control.MOUSE_FILTER_IGNORE,"scaled launch ribbon remains nonblocking: "+label)
  var ribbon:WeakRef=weakref(hud._launch_layer);hud.update_launch(1.0,"done");await settle();await process_frame
  check(ribbon.get_ref()==null,"scaled launch ribbon releases after dismissal: "+label)
 # Centered large frame verifies that root translation is not multiplied.
 hud.state.mode="hub";await set_frame(Rect2(80,90,2560,1440),Vector2i(2720,1620))
 check(hud.root.get_global_rect()==Rect2(80,90,2560,1440) and hud._ui_scale==2,"centered1440p frame keeps its physical offset at2×")
 var before:int=background_clicks;await click(Vector2(20,400));await click(Vector2(1360,20))
 check(background_clicks==before+2,"scaled root does not intercept letterbox margins")
 hud.settings_open=true;hud.render(hud.state);await settle()
 before=background_clicks;await click(Vector2(20,400));await click(Vector2(1360,20))
 check(background_clicks==before+2 and hud.settings_open,"scaled modal also leaves letterbox margins untouched")
 hud.settings_open=false
 for extent in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1920,1080)]:
  await set_frame(Rect2(Vector2.ZERO,Vector2(extent)),extent)
  check(hud.root.scale==Vector2.ONE and hud._size==Vector2(extent),"existing normal-size layout remains1× at "+str(extent))
 hud.set_art_frame(Rect2());hud.render(hud.state);await settle()
 check(hud.root.scale==Vector2.ONE and not hud.root.clip_contents,"clearing the frame restores unscaled legacy behavior")
 hud.queue_free();underlay.queue_free();for i in 5:await process_frame
 check(get_processed_tweens().is_empty(),"integer-scale teardown releases all processed Tweens")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every integer-scale assertion ran")
 print("V4_HUD_SCALE passed=%d failed=%d input=synthetic_physical_window_InputEvent"%[passed,failed]);quit(1 if failed else 0)
