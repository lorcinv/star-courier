extends SceneTree
## Scripted actual-GPU composition checkpoints. Not native input or FPS proof.
const Guide=preload("res://tools/pilot_wormhole_guidance.gd")
var game
var output:String="v5/wormhole-composition/first"
var tick:int=0
var axis:int=0
func _initialize() -> void:run.call_deferred()
func capture(label:String) -> void:
 game._clear_pilot_input();game.paused=true;game._process(0.0);game.world.settle_resumed_flight(game.sim)
 await create_timer(.3).timeout
 await game._capture(output+"/"+label)
 print("WORMHOLE_FRAME ",label," ",JSON.stringify({"elapsed":game.sim.elapsed,"position":str(game.sim.cargo_position()),"status":game.sim.status,"phase":game.sim.telemetry.wormhole_phase,"view":game.world.otherworld_presentation.debug_snapshot()}))
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 root.size=Vector2i(1920,1080)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/"+output))
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 game.settings.pixel_density="auto";game._apply_quality()
 game.economy.day=3;game.economy.reputation=8;game.economy.contracts=[];game.economy.ensure_contracts()
 game.economy.accept_contract("D3-B");game.economy.mark_story_seen("D3-B","D3-B/accept");game.start_flight(true)
 if game.page!="flight":push_error("Proof dispatch did not start");quit(2);return
 game.paused=true;game.launch_transfer_remaining=0;game.launch_countdown=0;game.launch_age=2;game.launch_sfx_played=true;game.world.launch_age=2
 var stops:Array=[{"x":570,"name":"01-entry-approach"},{"x":594,"name":"02-entry-mouth"},{"x":1005,"name":"03-exit"},{"x":1050,"name":"04-otherworld"},{"x":1205,"name":"05-receiver-approach"},{"x":1300,"name":"06-receipt"}]
 for stop in stops:
  while game.sim.cargo_position().x<float(stop.x) and game.sim.status=="running":
   if tick%12==0:axis=Guide.guidance(game.sim)
   game.pilot_keys.clear()
   if axis!=0:game.pilot_keys[KEY_W if axis<0 else KEY_S]=true
   game._step_flight();tick+=1
  await capture(str(stop.name))
 game.finish_flight();await create_timer(.3).timeout;await game._capture(output+"/07-trial-report")
 print("WORMHOLE_PROOF_COMPLETE ",game.sim.status," ",game.sim.elapsed)
 await game._quit_cleanly(0 if game.sim.status=="success" else 1)
