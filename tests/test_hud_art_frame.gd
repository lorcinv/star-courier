extends SceneTree
## HUD framing and actual GUI pointer routing, independent of the world renderer.
const HUD=preload("res://scripts/game_hud.gd")
const EXPECTED_CHECKS=37
var hud
var passed:int=0
var failed:int=0
var background_clicks:int=0
var actions:Array=[]

func _initialize() -> void:run.call_deferred()

func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)

func settle(frames:int=4) -> void:
 for i in range(frames):await process_frame

func finish_motion() -> void:
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)

func click(point:Vector2) -> void:
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion)
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event)
  await process_frame

func modal_dimmer() -> ColorRect:
 for node in hud.content.get_children():
  if node is ColorRect:return node
 return null

func button_named(node:Node,text:String) -> Button:
 if node is Button and node.text==text:return node
 for child in node.get_children():
  var found:=button_named(child,text)
  if found!=null:return found
 return null

func all_clicks(_event:InputEvent) -> void:
 if _event is InputEventMouseButton and _event.pressed:background_clicks+=1

func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])

func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1440,900)
 var background:=ColorRect.new();background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.gui_input.connect(all_clicks);root.add_child(background)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action)
 var state:={"mode":"hub","settings":{"reduced_motion":true},"has_accepted_contract":true,"activeorder":{"name":"测试托付","distance":100,"contract_id":"frame-test"}}
 hud.render(state);await settle();finish_motion()
 check(hud._size==Vector2(1440,900) and hud.root.position==Vector2.ZERO,"unconfigured HUD preserves the full-viewport default")
 check(hud.root.size==Vector2(1440,900) and not hud.root.clip_contents,"default root retains legacy anchors and clipping")
 var copy_covered:=true
 for letter in "自动清晰：按窗口大小调整像素密度":copy_covered=copy_covered and hud.root.theme.default_font.has_char(letter.unicode_at(0))
 check(copy_covered,"imported font covers concise quality and density tooltips")
 var frame:=Rect2(80,90,1280,720)
 hud.set_art_frame(frame)
 check(hud.root.position==frame.position and hud.root.size==frame.size,"setter immediately places native HUD within the art rectangle")
 check(hud._size==frame.size and hud.root.scale==Vector2.ONE,"setter uses frame dimensions without scaling Chinese controls")
 check(hud.root.clip_contents and hud.root.mouse_filter==Control.MOUSE_FILTER_IGNORE,"framed root clips descendants without capturing empty space")
 hud.render(state);await settle();finish_motion()
 check(hud.content.get_global_rect()==frame,"content anchors follow the framed root after render")
 check(hud.root.get_child_count()==2,"art-frame updates do not add overlay roots or duplicate toast nodes")
 var dock:=hud.content.get_child(hud.content.get_child_count()-3) as Button
 check(dock!=null and frame.encloses(dock.get_global_rect()),"hub dock lies inside the shifted active art frame")
 var before:=background_clicks
 await click(Vector2(24,420));await click(Vector2(720,30));await click(Vector2(1420,420));await click(Vector2(720,880))
 check(background_clicks==before+4,"all four letterbox margins pass input through the nonmodal HUD")
 await click(frame.position+Vector2(640,360))
 check(background_clicks==before+5,"open storefront inside the art frame remains interactive")
 await click(dock.get_global_rect().get_center())
 check(actions==[["focus_counter",null]],"native pointer coordinates reach the shifted hub action exactly once")
 for modal in ["settings","dispatch"]:
  hud.settings_open=modal=="settings";hud.dispatch_confirmation_open=modal=="dispatch";hud._dispatch_contract_id="frame-test"
  hud.render(state);await settle();finish_motion()
  var dim:=modal_dimmer()
  check(dim!=null and dim.get_global_rect()==frame,modal+" dimmer covers precisely the active art frame")
  check(dim.mouse_filter==Control.MOUSE_FILTER_STOP,modal+" dimmer blocks background input inside the frame")
  before=background_clicks;var action_count:=actions.size()
  await click(frame.position+Vector2(12,320));await click(dock.get_global_rect().get_center() if is_instance_valid(dock) else frame.position+Vector2(100,676))
  check(background_clicks==before and actions.size()==action_count,modal+" blocks scene and underlying dock clicks")
  await click(Vector2(24,420));await click(Vector2(720,30));await click(Vector2(1420,420));await click(Vector2(720,880))
  check(background_clicks==before+4,modal+" does not intercept any letterbox margin")
  var close:=button_named(hud.content,"×" if modal=="settings" else "再检查一下")
  await click(close.get_global_rect().get_center())
  check(not hud.is_blocking_modal(),modal+" close uses the shifted native coordinates and clears its guard")
  hud.render(state);await settle();finish_motion()
 hud.toast("新提示")
 check(frame.encloses(hud.toast_panel.get_global_rect()),"toast is clipped and positioned relative to the art frame")
 state.mode="flight";hud.render(state);hud.update_launch(.3,"charge");finish_motion()
 check(frame.encloses(hud._launch_layer.get_global_rect()),"nonblocking launch ribbon stays within the art frame")
 hud.settings_open=true;hud.render(state);hud.update_launch(.4,"charge")
 var old_ribbon:WeakRef=weakref(hud._launch_layer);var old_tweens:Array=[]
 for tween in hud._motion_tweens.values():old_tweens.append(weakref(tween))
 check(not old_tweens.is_empty(),"resize interruption starts with genuinely active layout Tweens")
 root.size=Vector2i(1280,720);hud.set_art_frame(Rect2(0,0,1280,720));hud.render(state);await settle();finish_motion()
 check(hud.root.position==Vector2.ZERO and hud._size==Vector2(1280,720),"resize to the base window removes the letterbox offset")
 check(hud.content.get_global_rect()==Rect2(0,0,1280,720),"base-window content remains native-resolution after resize")
 check(modal_dimmer().get_global_rect()==Rect2(0,0,1280,720),"an open modal follows the changed frame during resize")
 check(old_ribbon.get_ref()==null,"resize rebuild releases the previous launch ribbon")
 var released:=true
 for ref in old_tweens:released=released and ref.get_ref()==null
 check(released,"art-frame rebuild releases interrupted layout Tweens")
 hud.settings_open=false;hud.render(state);hud.update_launch(.7,"ignition");finish_motion()
 check(hud._launch_layer.position.is_equal_approx(Vector2((1280-464)/2.0,720*.24)),"next launch phase uses the resized frame's local coordinates")
 root.size=Vector2i(1440,900);hud.set_art_frame(Rect2());hud.render(state);await settle();finish_motion()
 check(hud._size==Vector2(1440,900) and hud.root.get_global_rect()==Rect2(0,0,1440,900),"Rect2() restores full-viewport layout")
 check(not hud.root.clip_contents and hud.root.scale==Vector2.ONE,"clearing the override restores default clipping without rescaling")
 hud.set_art_frame(Rect2(0,0,-1,720));check(not hud._art_frame_enabled,"nonpositive art dimensions also reset the override")
 hud.set_art_frame(Rect2(80.4,89.7,1279.6,720.2))
 check(hud.root.get_global_rect()==Rect2(80,90,1280,720),"fractional API input snaps once to full-resolution pixel boundaries")
 var early=HUD.new();early.set_art_frame(frame);root.add_child(early);early.render(state);await settle()
 check(early.root.get_global_rect()==frame and early._size==frame.size,"an art rectangle supplied before ready survives root construction")
 early.queue_free();hud.queue_free();background.queue_free();await settle()
 check(get_processed_tweens().is_empty(),"framed HUD teardown leaves no processed Tweens")
 if passed+failed!=EXPECTED_CHECKS:check(false,"all expected art-frame assertions ran")
 print("HUD_ART_FRAME passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
