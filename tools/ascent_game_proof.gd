extends SceneTree
## Scripted, paused composition checkpoints from the real v2 game/physics.
## Not native-input evidence. Use an isolated XDG_DATA_HOME.
var game
var output_dir:String="v5/ascent-first"
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var window_size:Vector2i=Vector2i(1920,1080)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output_dir=arg.trim_prefix("--output=")
  if arg.begins_with("--size="):
   var dimensions:PackedStringArray=arg.trim_prefix("--size=").split("x")
   if dimensions.size()==2:window_size=Vector2i(int(dimensions[0]),int(dimensions[1]))
 root.size=window_size
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/"+output_dir))
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.settings.pixel_density="auto";game._apply_quality()
 await create_timer(.5).timeout
 game.economy.accept_contract("D1-A");game.economy.mark_story_seen("D1-A","D1-A/accept");game.start_flight(true)
 game.paused=true;game.launch_age=2;game.launch_sfx_played=true
 var tick:int=0;var axis:int=0
 for target in [2.0,8.0,17.0,26.0,31.0]:
  while game.sim.elapsed<target and game.sim.status=="running":
   if tick%12==0:axis=game._smoke_guidance_axis()
   game.pilot_keys.clear()
   if axis!=0:game.pilot_keys[KEY_W if axis<0 else KEY_S]=true
   game._step_flight();tick+=1
  game._clear_pilot_input();game._process(0)
  await create_timer(.65).timeout
  await game._capture(output_dir+"/at-%02ds"%int(target))
  print("ASCENT_FRAME ",JSON.stringify({"elapsed":game.sim.elapsed,"position":str(game.sim.cargo_position()),"telemetry":game.sim.telemetry,"camera":str(game.world.camera.position),"background":game.world.ascent_backdrop.debug_snapshot()}))
 await game._quit_cleanly()
