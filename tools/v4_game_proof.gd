extends SceneTree
## Scripted composition proof using the live game/controller, not native-input QA.
var game
var capture_prefix:String="v4/runtime"
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var pixels:Vector2i=Vector2i(640,360)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--canvas="):
   var width:int=int(arg.get_slice("=",1));pixels=Vector2i(width,width*9/16)
  elif arg.begins_with("--window="):
   var dims:String=arg.get_slice("=",1);root.size=Vector2i(int(dims.get_slice("x",0)),int(dims.get_slice("x",1)))
  elif arg.begins_with("--tag="):capture_prefix="v4/"+arg.get_slice("=",1)+"/runtime"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/"+capture_prefix.get_base_dir()))
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.settings.quality="standard";game._apply_quality()
 game.view_container.set_canvas_size(pixels)
 await create_timer(2).timeout
 await game._capture(capture_prefix+"-01-hub")
 game.navigate("contracts");await create_timer(1.5).timeout;await game._capture(capture_prefix+"-02-counter")
 game._action("accept_contract","D1-A");await create_timer(.8).timeout
 game._action("focus_workbench",null);game.selected_id=3;game.render()
 await create_timer(1.5).timeout;await game._capture(capture_prefix+"-03-workshop")
 game.start_flight(true);await create_timer(.35).timeout;game.paused=true;await game._capture(capture_prefix+"-04-charge")
 game.paused=false;await create_timer(.46).timeout;game.paused=true;await game._capture(capture_prefix+"-05-ignition")
 game.paused=false;await create_timer(3).timeout;game.paused=true;await game._capture(capture_prefix+"-06-flight")
 print("V4_LIVE_GAME_PROOF_COMPLETE ",game.view.size," ",game.view_container.pixel_scale)
 await game._quit_cleanly()
