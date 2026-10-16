extends SceneTree
## Headless HUD-only regression: no world rendering, gameplay, or player saves.
const HUD = preload("res://scripts/game_hud.gd")
const EXPECTED_CHECKS = 64
var passed: int = 0
var failed: int = 0
var hud
var target: Control
var actions:Array=[]

func _initialize() -> void:
 run.call_deferred()

func check(condition: bool, message: String) -> void:
 if condition:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)

func settle(frames: int = 4) -> void:
 for i in range(frames):await process_frame

func retained(refs: Array) -> int:
 var count:=0
 for ref in refs:
  if ref.get_ref()!=null:count+=1
 return count

func advance_motion(seconds: float = 1.0) -> void:
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(seconds)

func replaced_batch(count: int) -> Array:
 var refs:Array=[]
 for i in range(count):
  var tween:Tween=hud._motion_for(target)
  tween.tween_property(target,"modulate:a",1.0,10.0)
  refs.append(weakref(tween))
 hud._stop_motion()
 return refs

func finished_batch(count: int, natural: bool = false) -> Array:
 var refs:Array=[]
 for i in range(count):
  var tween:Tween=hud._motion_for(target,"natural_%d"%i if natural else "layout")
  tween.tween_property(target,"modulate:a",1.0,.01)
  refs.append(weakref(tween))
  if not natural:tween.custom_step(1.0)
 return refs

func channel_replacement() -> Array:
 var layout:Tween=hud._motion_for(target)
 layout.tween_interval(10.0)
 var feedback:Tween=hud._motion_for(target,"feedback")
 feedback.tween_interval(10.0)
 var replacement:Tween=hud._motion_for(target)
 replacement.tween_interval(10.0)
 var key:=str(target.get_instance_id())+":layout"
 check(not layout.is_valid() and feedback.is_valid() and replacement.is_valid(),"replacement cancels only the matching target/channel")
 check(hud._motion_tweens.size()==2,"layout and feedback channels coexist with one Tween each")
 hud._finish_motion(key,layout.get_instance_id())
 check(hud._motion_tweens.get(key)==replacement,"stale completion cannot erase the newer animation")
 var refs:Array=[weakref(layout),weakref(feedback),weakref(replacement)]
 hud._stop_motion()
 return refs

func feedback_batch(button: Button, count: int) -> Array:
 var refs:Array=[]
 var key:=str(button.get_instance_id())+":feedback"
 for i in range(count):
  button.button_down.emit();refs.append(weakref(hud._motion_tweens[key]))
  button.button_up.emit();refs.append(weakref(hud._motion_tweens[key]))
 advance_motion()
 return refs

func motion_refs() -> Array:
 var refs:Array=[]
 for tween in hud._motion_tweens.values():refs.append(weakref(tween))
 return refs

func all_ignore_mouse(node: Node) -> bool:
 if node is Control and node.mouse_filter!=Control.MOUSE_FILTER_IGNORE:return false
 for child in node.get_children():
  if not all_ignore_mouse(child):return false
 return true

func find_button(node: Node, text: String) -> Button:
 if node is Button and node.text==text:return node
 for child in node.get_children():
  var button:=find_button(child,text)
  if button!=null:return button
 return null

func record_action(action: String, payload: Variant) -> void:
 actions.append({"action":action,"payload":payload})

func test_motion_behavior() -> void:
 hud.state={"settings":{"reduced_motion":false}}
 var origin:=Vector2(60,70)
 var offset:=Vector2(38,4)
 target.position=origin
 hud._enter_panel(target,offset,.075,.21)
 check(target.position==origin+offset and target.modulate.a<1.0,"normal panel entrance retains angular offset and fade")
 advance_motion(.025)
 check(target.position==origin+offset,"panel entrance retains its stagger delay")
 advance_motion()
 check(target.position.is_equal_approx(origin) and is_equal_approx(target.modulate.a,1.0),"elastic entrance finishes at the exact layout and opacity")
 check(hud._motion_tweens.is_empty(),"finished panel animation clears its registry entry")
 hud.state.settings.reduced_motion=true
 hud._enter_panel(target,offset,.075,.21)
 check(target.position==origin and target.scale==Vector2.ONE and is_zero_approx(target.rotation),"reduced motion entrance has no translation, scale, or rotation")
 advance_motion(.13)
 check(is_equal_approx(target.modulate.a,1.0) and hud._motion_tweens.is_empty(),"reduced motion fade finishes within the original120ms")
 await settle()

func test_feedback() -> void:
 hud.state.settings.reduced_motion=false
 var button:=Button.new();hud.content.add_child(button)
 hud._wire_motion_feedback(button)
 var refs:=feedback_batch(button,256)
 await settle()
 check(retained(refs)==0,"512 interrupted/completed button feedback Tweens are released")
 refs.clear()
 var pressed:=button.get_theme_stylebox("pressed") as StyleBoxFlat
 var hover:=button.get_theme_stylebox("hover") as StyleBoxFlat
 check(is_zero_approx(pressed.expand_margin_left) and is_zero_approx(pressed.expand_margin_right) and is_zero_approx(pressed.expand_margin_top),"rapid button presses restore the pressed border")
 check(pressed.shadow_offset==Vector2(4,5) and hover.shadow_offset.is_equal_approx(Vector2(4,5)),"rapid button presses restore both style shadows")
 hud.state.settings.reduced_motion=true
 button.button_down.emit();button.button_up.emit()
 check(hud._motion_tweens.is_empty(),"reduced motion button feedback creates no bounce Tween")
 button.queue_free();await settle()

func test_launch() -> void:
 for reduced in [false,true]:
  hud.render({"mode":"flight","settings":{"reduced_motion":reduced}})
  advance_motion();await settle()
  hud.update_launch(.2,"charge")
  var ribbon=weakref(hud._launch_layer)
  var origin:Vector2=hud._launch_layer.position
  check(hud._launch_layer.size==Vector2(464,112) and all_ignore_mouse(hud._launch_layer),"launch ribbon preserves its bounds and never captures input (reduced=%s)"%reduced)
  for phase in ["charge","ignition","release"]:
   hud.update_launch(.8,phase)
   advance_motion(.17)
   check(hud._launch_layer.position==origin and hud._launch_layer.scale.is_equal_approx(Vector2.ONE),"launch %s settles without layout drift (reduced=%s)"%[phase,reduced])
  check(is_equal_approx(hud._launch_meter.value,80.0),"launch phase API still updates progress (reduced=%s)"%reduced)
  hud.update_launch(1.0,"done")
  var count:int=hud._motion_tweens.size()
  hud.update_launch(1.0,"done")
  check(hud._motion_tweens.size()==count,"repeated launch dismissal does not replace its outgoing animation (reduced=%s)"%reduced)
  advance_motion(.13);await settle()
  check(ribbon.get_ref()==null and hud._motion_tweens.is_empty(),"launch ribbon and outgoing Tween release after120ms dismissal (reduced=%s)"%reduced)

func retry_cycle(reduced: bool) -> void:
 var settings:={"reduced_motion":reduced}
 # Deliberately replace most entrances before they finish, as rapid retry does.
 hud.render({"mode":"workshop","settings":settings})
 hud.render({"mode":"flight","settings":settings})
 for phase in ["charge","ignition","release","done"]:hud.update_launch(.8,phase)
 hud.render({"mode":"report","report":{"trial":true},"settings":settings})
 hud.render({"mode":"hub","settings":settings})
 advance_motion()

func counters() -> Dictionary:
 return {"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"static_memory_bytes":OS.get_static_memory_usage()}

func motion_memory_batch() -> bool:
 var refs:=replaced_batch(256)
 await settle()
 var released:=retained(refs)==0
 refs.clear()
 refs=finished_batch(256)
 await settle()
 released=released and retained(refs)==0
 refs.clear()
 return released

func test_motion_plateau() -> void:
 for i in range(2):await motion_memory_batch()
 var baseline:=counters()
 var peak_objects:int=baseline.objects
 var peak_memory:int=baseline.static_memory_bytes
 var all_released:=true
 for i in range(16):
  all_released=await motion_memory_batch() and all_released
  var sample:=counters()
  peak_objects=maxi(peak_objects,sample.objects)
  peak_memory=maxi(peak_memory,sample.static_memory_bytes)
 var final:=counters()
 print("HUD_MOTION_PLATEAU_METRICS ",JSON.stringify({"tweens":8192,"baseline":baseline,"final":final,"peak_object_growth":peak_objects-baseline.objects,"peak_memory_growth_bytes":peak_memory-baseline.static_memory_bytes}))
 check(all_released and peak_objects-baseline.objects<=4,"8192 canceled/completed animations release and object counts plateau")
 check(peak_memory-baseline.static_memory_bytes<=32768,"isolated animation static memory plateaus within32KiB after warmup")

func test_interruptions() -> void:
 var workshop:={"mode":"workshop","settings":{"reduced_motion":false}}
 hud.render(workshop)
 var refs:=motion_refs()
 hud.render(workshop)
 await settle()
 check(retained(refs)==0 and hud._motion_tweens.is_empty(),"same-mode rebuild cancels and releases the entering controls")
 refs.clear()
 var opaque:=true
 for child in hud.content.get_children():
  if child is CanvasItem:opaque=opaque and is_equal_approx(child.modulate.a,1.0)
 check(opaque,"same-mode replacement is fully visible rather than stranded mid-fade")
 var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
 hud.settings_open=true;hud.render(workshop)
 refs=motion_refs()
 hud._unhandled_key_input(escape)
 await settle()
 check(not hud.settings_open and retained(refs)==0,"Escape during settings entrance releases its canceled animation")
 refs.clear()
 workshop.activeorder={"name":"测试托付","distance":100,"contract_id":"lifecycle"}
 hud.dispatch_confirmation_open=true;hud._dispatch_contract_id="lifecycle";hud.render(workshop)
 refs=motion_refs()
 hud._unhandled_key_input(escape)
 await settle()
 check(not hud.dispatch_confirmation_open and retained(refs)==0,"Escape during dispatch entrance releases its canceled animation")
 refs.clear()
 hud.render({"mode":"flight","settings":{"reduced_motion":false}})
 hud.update_launch(.2,"charge")
 var ribbon:WeakRef=weakref(hud._launch_layer)
 refs=motion_refs()
 var original_size:=root.size
 root.size=Vector2i(1280,800)
 await settle()
 check(root.size==Vector2i(1280,800) and ribbon.get_ref()==null and retained(refs)==0,"viewport resize during launch rebuilds and releases the old ribbon/Tweens")
 refs.clear()
 hud.update_launch(.7,"ignition");advance_motion()
 check(is_instance_valid(hud._launch_layer) and hud._launch_layer.position.is_equal_approx(Vector2((hud._size.x-464)/2,hud._size.y*.24)),"next launch phase restores the ribbon at the resized layout")
 root.size=original_size
 await settle()

func test_cancellation_lifecycle() -> void:
 var data:={"mode":"hub","has_accepted_contract":true,"activeorder":{"name":"测试托付","distance":100,"contract_id":"lifecycle"},"settings":{"reduced_motion":false}}
 hud.action_requested.connect(record_action)
 hud.render(data)
 find_button(hud.content,"取消委托").pressed.emit()
 check(hud.is_blocking_modal() and actions.is_empty(),"first cancel press blocks editing without canceling the contract")
 var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
 hud._unhandled_key_input(escape)
 check(not hud.is_blocking_modal() and actions.is_empty(),"Escape clears inline cancellation and restores editing without canceling")
 find_button(hud.content,"取消委托").pressed.emit()
 data.mode="workshop";hud.render(data)
 check(not hud.is_blocking_modal() and hud._cancel_confirmation_id.is_empty(),"mode change dismisses inline cancellation instead of leaving a stale guard")
 find_button(hud.content,"取消委托").pressed.emit()
 hud.render(data)
 check(hud.is_blocking_modal() and find_button(hud.content,"确认取消？")!=null,"same-mode render preserves an active explicit cancellation question")
 find_button(hud.content,"确认取消？").pressed.emit()
 check(not hud.is_blocking_modal() and actions==[{"action":"cancel_contract","payload":"lifecycle"}],"second cancel press emits exactly the named cancellation and clears its guard")
 hud.render(data)
 find_button(hud.content,"取消委托").pressed.emit()
 data.activeorder.contract_id="replacement";hud.render(data)
 check(not hud.is_blocking_modal(),"changing the active contract invalidates the old cancellation question")
 find_button(hud.content,"取消委托").pressed.emit()
 data.has_accepted_contract=false;hud.render(data)
 check(not hud.is_blocking_modal(),"resolving the active contract invalidates inline cancellation")
 hud.action_requested.disconnect(record_action)
 await settle()

func test_toast_lifecycle() -> void:
 hud.render({"mode":"hub"})
 hud.toast("货物已收下。去工位，把它装上飞行器。")
 hud.render({"mode":"workshop"})
 check(not hud.toast_panel.visible and is_zero_approx(hud.toast_timer),"navigation dismisses the previous page's acceptance toast")
 hud.toast("新提示")
 check(hud.toast_panel.visible and hud.toast_timer>0,"an action toast requested after navigation is still displayed")
 hud.render({"mode":"workshop"})
 check(hud.toast_panel.visible and hud.toast_timer>0,"same-mode state rebuild preserves the current page's toast")
 hud.render({"mode":"flight"});hud.update_launch(.2,"charge")
 check(not hud.toast_panel.visible and is_zero_approx(hud.toast_timer),"charge/ignition never inherit a stale workshop toast")
 hud.toast("飞行提示");hud.render({"mode":"report"})
 check(not hud.toast_panel.visible and is_zero_approx(hud.toast_timer),"report entry dismisses the prior flight toast")
 hud.toast("回执已更新")
 check(hud.toast_panel.visible and hud.toast_timer>0,"a fresh report action toast remains allowed after render")
 # Toast fades are bound to the HUD and finish naturally outside panel motion.
 await create_timer(.2).timeout
 await settle()

func test_launch_hint() -> void:
 hud.render({"mode":"flight","flight":{"charging":true}})
 check(hud.flight_labels.hint.text.is_empty(),"charging telemetry adds no redundant helper sentence")
 hud.update_flight({"charging":false})
 check(hud.flight_labels.hint.text.is_empty(),"ignition does not restore coaching copy")
 hud.render({"mode":"flight"})
 check(hud.flight_labels.hint.text.is_empty(),"legacy flight stays free of persistent helper sentences")
 advance_motion();await settle()

func test_retry_plateau(reduced: bool) -> void:
 for i in range(3):retry_cycle(reduced);await settle()
 var baseline:=counters()
 var peak_objects:int=baseline.objects
 var peak_memory:int=baseline.static_memory_bytes
 var stable_nodes:=true;var stable_resources:=true;var empty_registry:=true
 for i in range(24):
  retry_cycle(reduced);await settle()
  var sample:=counters()
  peak_objects=maxi(peak_objects,sample.objects)
  peak_memory=maxi(peak_memory,sample.static_memory_bytes)
  stable_nodes=stable_nodes and sample.nodes==baseline.nodes and sample.orphans==baseline.orphans
  stable_resources=stable_resources and sample.resources==baseline.resources
  empty_registry=empty_registry and hud._motion_tweens.is_empty() and get_processed_tweens().is_empty()
 var final:=counters()
 print("HUD_LIFECYCLE_METRICS ",JSON.stringify({"reduced_motion":reduced,"cycles":24,"baseline":baseline,"final":final,"peak_object_growth":peak_objects-baseline.objects,"peak_memory_growth_bytes":peak_memory-baseline.static_memory_bytes}))
 check(peak_objects-baseline.objects<=8,"objects plateau across24 interrupted retry cycles (reduced=%s)"%reduced)
 # Full-engine static bytes also grow in a bare Control create/free probe.
 # Log those allocations here; the isolated animation test gates memory above.
 check(stable_nodes and stable_resources,"settled node/resource/orphan counts stay constant (reduced=%s)"%reduced)
 check(empty_registry,"all retry cycles end with no owned or processed Tweens (reduced=%s)"%reduced)

func teardown_refs() -> Array:
 target=Control.new();hud.content.add_child(target)
 var tween:Tween=hud._motion_for(target);tween.tween_interval(10.0)
 return [weakref(tween),weakref(hud)]

func run() -> void:
 hud=HUD.new();root.add_child(hud)
 target=Control.new();hud.content.add_child(target)
 await settle()
 var refs:=replaced_batch(512)
 await settle()
 check(retained(refs)==0,"512 canceled/replaced Tweens have no surviving strong references")
 check(hud._motion_tweens.is_empty() and get_processed_tweens().is_empty(),"cancel clears HUD registry and SceneTree Tween processing")
 refs.clear()
 refs=finished_batch(256)
 await settle()
 check(retained(refs)==0,"256 completed Tweens have no self-retaining signal callbacks")
 check(hud._motion_tweens.is_empty(),"completion removes every matching registry entry")
 refs.clear()
 refs=finished_batch(128,true)
 var deadline:=Time.get_ticks_msec()+2000
 while not hud._motion_tweens.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 await settle()
 check(retained(refs)==0 and hud._motion_tweens.is_empty(),"128 naturally processed completions also release without manual stepping")
 refs.clear()
 refs=channel_replacement();await settle()
 check(retained(refs)==0,"independent channels and replaced generation all release on cancel")
 refs.clear()
 await test_motion_behavior()
 await test_feedback()
 await test_motion_plateau()
 target=null
 await test_launch()
 await test_interruptions()
 await test_cancellation_lifecycle()
 await test_toast_lifecycle()
 await test_launch_hint()
 await test_retry_plateau(false)
 await test_retry_plateau(true)
 refs=teardown_refs();hud.queue_free();await settle()
 check(retained(refs)==0 and get_processed_tweens().is_empty(),"HUD teardown releases active bound Tween and HUD object")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every expected lifecycle assertion ran; no test exited early with a script error")
 print("HUD_LIFECYCLE passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)
