extends SceneTree
## Scripted renderer replay of a saved native-input trace. It is a composition
## diagnostic, not a new native input or real-time performance acceptance run.
var game
var output:String="v5/grounded-launch-safe-band"
func _initialize() -> void:run.call_deferred()
func capture(label:String) -> void:
 await create_timer(.20).timeout
 await RenderingServer.frame_post_draw
 await game._capture(output+"/"+label)
 print("VISIBILITY_FRAME ",label)
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 var source_path:String="res://docs/qa/v5/grounded-launch-safe-band/native-source.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--source="):source_path=arg.trim_prefix("--source=")
 if not FileAccess.file_exists(source_path):push_error("A saved native trace source is required: "+source_path);quit(2);return
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path))
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 root.size=Vector2i(1280,800);game.settings.pixel_density="auto";game.settings.reduced_motion=false;game._apply_quality()
 await create_timer(.2).timeout
 game.design=source.design;game.launcher=source.launcher
 game.navigate("workshop");game.world.focus("workshop",true)
 game._configure_flight(true,source.design,source.launcher,source.route)
 game._process(game.launch_transfer_remaining+.4);await capture("01-charge-1280")
 game._process(.35);await capture("02-ignition-1280")
 game._configure_flight(true,source.design,source.launcher,source.route,true)
 var timeline=game.PilotTimeline.new()
 if not timeline.restore(source.timeline,int(source.ticks)):push_error(timeline.error);quit(2);return
 for tick in int(source.ticks):
  var command:Dictionary=timeline.state_at(tick)
  game.sim.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active));game.sim.step(1.0/60.0)
  if tick+1 in [150,343,465]:
   game.pilot_completed_ticks=tick+1;game.paused=true;game._process(0.0);game.world.settle_resumed_flight(game.sim)
   await capture("%02d-tick-%03d-1280"%[3+[150,343,465].find(tick+1),tick+1])
 var max_body_error:float=0.0
 for expected in source.expected_bodies:
  for body in game.sim.bodies:
   if int(body.id)==int(expected.id):
    max_body_error=maxf(max_body_error,body.position.distance_to(Vector2(expected.position[0],expected.position[1])))
 print("NATIVE_TRACE_REPLAY ticks=",game.pilot_completed_ticks," body_position_max_error=",max_body_error," elapsed=",game.sim.elapsed)
 await game._quit_cleanly()
