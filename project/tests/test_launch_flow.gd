extends SceneTree
## Interruptions, persisted resume and actual dispatched keyboard-event regression.
var game
var passed:int=0
var failed:int=0

func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)

func key(code:int,control:bool=false) -> void:
 var event=InputEventKey.new();event.keycode=code;event.pressed=true;event.ctrl_pressed=control
 Input.parse_input_event(event);await process_frame
 event=InputEventKey.new();event.keycode=code;event.pressed=false;event.ctrl_pressed=control
 Input.parse_input_event(event);await process_frame

func pad_geometry() -> Array:
 var geometry:Array=[]
 for child in game.world.flight_nodes.launch_pad.get_children():
  geometry.append([child.position,child.mesh.size if child is MeshInstance3D and child.mesh is BoxMesh else Vector3.ZERO])
 return geometry

func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 game.economy.accept_contract("D1-A");game.navigate("workshop");game.selected_id=2;game.render()
 game.economy.mark_story_seen("D1-A","D1-A/accept")
 for modal in ["dispatch","settings","cancel"]:
  if modal=="dispatch":game.hud.dispatch_confirmation_open=true
  elif modal=="settings":game.hud.settings_open=true
  else:game.hud._cancel_confirmation_id="D1-A"
  var before:String=JSON.stringify(game.design)
  await key(KEY_R);await key(KEY_DELETE);await key(KEY_Z,true)
  check(JSON.stringify(game.design)==before,"R, Delete and Ctrl+Z cannot mutate assembly behind "+modal+" modal")
  game.hud.dispatch_confirmation_open=false;game.hud.settings_open=false;game.hud._cancel_confirmation_id=""
 await key(KEY_R)
 check(game.selected_part().rot==1,"same real keyboard event rotates the selected part after modal closes")
 game.undo_assembly()
 game.start_flight(true);game._process(.3)
 check(not game.hud.flight_labels.events.text.contains("释放") or game.hud.flight_labels.events.text.contains("等待释放"),"charge shows preparation instead of claiming the launch already fired")
 var age:float=game.launch_age;var elapsed:float=game.sim.elapsed
 game.paused=true;game._process(1.0)
 check(is_equal_approx(age,game.launch_age) and is_equal_approx(elapsed,game.sim.elapsed),"pause freezes charge presentation and simulation together")
 game.abort_flight();check(game.page=="report" and game.economy.credits==260,"aborting during charge leaves flight without trial billing")
 game.start_flight(true)
 check(game.launch_age==0 and game.world.launch_age==0,"retry resets charge and world launch phase")
 game._process(game.world.launch_transfer_duration());game._process(.72)
 check(game.sim.elapsed>0 and game.launch_sfx_played and game.launch_countdown<=0,"ignition releases physics and plays launch sound once")
 check(game.sim.events.any(func(event):return str(event).contains("发射台完成压缩供能，释放")) and game.hud._launch_title.text=="点火！" and not game.hud.flight_labels.events.text.contains("发射台完成压缩供能"),"ignition uses the short launch status while the original launcher event remains in the simulation trace")
 game.abort_flight();game.navigate("workshop");game.start_flight(false)
 var fixed_geometry:Array=pad_geometry()
 for i in range(120):game.sim.step(1.0/60.0)
 var restored_elapsed:float=game.sim.elapsed
 game.economy.in_flight.elapsed=game.sim.elapsed;game.economy.in_flight.ticks=120;game._resume_dispatch()
 check(is_equal_approx(game.sim.elapsed,restored_elapsed),"formal resume restores exact deterministic checkpoint")
 check(game.launch_age>=1.35 and game.launch_countdown<=0 and game.launch_sfx_played,"formal resume skips charge, ignition and duplicate launch sound")
 check(pad_geometry()==fixed_geometry,"resumed launcher remains the original fixed cradle instead of stretching to moving craft")
 game.world.reduced_motion=true;game.world.launch_age=.8;game.world.show_flight(game.sim)
 check(not game.world.flight_nodes.launch_burst.visible,"reduced motion suppresses launch impact rays")
 game.world.leave_flight();game.world.show_design(game.design)
 check(game.world.fx_root.get_child_count()==1 and not game.world.effect_node.visible,"abort/navigation leaves no visible stale flight effects")
 game.music.stop();game.music.stream=null;game.sfx.stop();game.sfx.stream=null
 game.queue_free();await process_frame;await process_frame
 print("LAUNCH_FLOW_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
