extends SceneTree
## Native Godot controls with synthetic window events, not OS-native capture.
const Overlay=preload("res://scripts/loading_scene_overlay.gd")
var panel
var passed:int=0
var failed:int=0
var requests:Array[String]=[]
var underlying_clicks:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func frames(count:int=2) -> void:
 for i in count:await process_frame
func key(code:int,pressed:bool=true,echo:bool=false) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.echo=echo
 root.push_input(event);await frames()
func click(point:Vector2) -> void:
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion)
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
  event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(event);await frames()
func state(id:String="A",phase:String="robot_carry") -> Dictionary:
 return {"order_id":id,"phase":phase,"loading":true}
func run() -> void:
 var underneath:=Button.new();underneath.position=Vector2(100,100);underneath.size=Vector2(180,80);underneath.text="Underlying editor"
 root.add_child(underneath);underneath.pressed.connect(func():underlying_clicks+=1)
 panel=Overlay.new();root.add_child(panel);panel.skip_requested.connect(func(id:String):requests.append(id));await frames()
 check(not panel.is_open() and not panel._root.visible,"overlay starts closed without capturing the workshop")
 check(panel._skip.get_theme_color("font_focus_color")==Overlay.INK and panel._skip.get_theme_color("font_hover_pressed_color")==Overlay.INK,"focused and pressed skip text keeps dark readable contrast on gold")
 panel.update_state(state());panel.request_skip()
 check(requests.is_empty(),"the same event/frame that ended dialogue cannot skip its newly opened scene")
 await frames();await click(underneath.get_global_rect().get_center())
 check(underlying_clicks==0 and requests.is_empty(),"transparent scene overlay blocks underlying native buttons without auto-skipping")
 for code in [KEY_R,KEY_DELETE,KEY_Z,KEY_W]:await key(code);await key(code,false)
 check(requests.is_empty(),"editor and pilot keys cannot accidentally become skip commands")
 await key(KEY_SPACE,true,true)
 check(requests.is_empty(),"held-key autorepeat does not skip a scene")
 await key(KEY_SPACE)
 check(requests==["A"] and panel._skip.disabled,"Space requests one matching-order skip and disables repeated activation")
 await key(KEY_ESCAPE);panel.request_skip();await click(panel._skip.get_global_rect().get_center())
 check(requests==["A"],"repeat keyboard/pointer/direct requests cannot enqueue extra completions")
 panel.close();panel.update_state(state("B","clerk_align"));await frames()
 check(panel.debug_snapshot().phase=="clerk_align" and not panel._skip.disabled,"new order resets its skip guard and preserves internal phase identity")
 panel.update_state(state("B","robot_insert"));check(panel._canvas.get_child_count()==1 and panel._canvas.get_child(0)==panel._skip,"loading presents only the useful skip control, with no explanatory phase narration")
 await key(KEY_ESCAPE)
 check(requests==["A","B"],"Escape skips the current scene, not a stale prior order")
 panel.update_state({"loading":false});await frames()
 check(not panel.is_open() and not panel._root.visible,"loaded/cancelled state releases all scene input capture")
 for size in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=size;await frames();var frame:=Rect2(Vector2(0,40) if size.x==1280 else Vector2.ZERO,Vector2(1280,720) if size.x==1280 else Vector2(size))
  panel.set_art_frame(frame);panel.update_state(state(str(size)));await frames()
  var snapshot:Dictionary=panel.debug_snapshot()
  check(frame.encloses(snapshot.skip_rect),"skip stays inside actual pixel art frame at "+str(size))
  check(panel._canvas.scale.x==floor(panel._canvas.scale.x) and panel._canvas.position==panel._canvas.position.round(),"integer UI scale and pixel registration at "+str(size))
  await click(snapshot.skip_rect.get_center())
  check(requests.back()==str(size),"actual GUI skip hit-testing agrees after resize "+str(size))
  panel.close()
 root.size=Vector2i(1280,800);await frames();panel.set_art_frame(Rect2(0,40,1280,720))
 var node_count:int=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT));var objects:int=int(Performance.get_monitor(Performance.OBJECT_COUNT))
 var controls:int=panel._root.get_child_count();var tweens:int=get_processed_tweens().size()
 for i in 160:
  panel.update_state(state("cycle/"+str(i),"robot_pickup"));panel.update_state(state("cycle/"+str(i),"clerk_confirm"));panel.close();await frames(1)
 check(panel._root.get_child_count()==controls and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))==node_count,"160 interrupted scenes reuse fixed controls without adding nodes")
 check(int(Performance.get_monitor(Performance.OBJECT_COUNT))<=objects+4 and get_processed_tweens().size()==tweens,"160 interrupted scenes retain no motion tweens or unbounded object growth")
 panel.queue_free();underneath.queue_free();await frames()
 print("LOADING_SCENE_OVERLAY passed=",passed," failed=",failed," native_input=false");quit(1 if failed else 0)
